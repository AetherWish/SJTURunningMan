import { common } from '@kit.AbilityKit';
import { RouteInfo, GpsPoint } from '../model/RouteInfo';
import { ApiService } from '../service/ApiService';
import { RouteManager } from '../service/RouteManager';
import { GpsUtil } from '../service/GpsUtil';
import { CookieService } from '../service/CookieService';
import { DataGenerator } from '../service/DataGenerator';
import { AppConfig } from '../config/AppConfig';
import { parseDate, yesterday, pad2, randomInt } from '../utils/FormatUtil';
import {
  LogLevel,
  LogEntry,
  TaskStatus,
  TaskProgress,
  RouteDecision,
  RouteConflict,
  RoutePreview,
  TrackSample,
  PointRules,
  RunOutcome
} from './TaskModels';

/**
 * 任务运行配置
 * 迁移自 Android: com.sjtu.runner.viewmodel.MainViewModel.RunConfig
 */
export class RunConfig {
  days: number = 1;
  distanceKm: number = AppConfig.DEFAULT_DISTANCE_KM;
  hour: number = AppConfig.DEFAULT_RUN_HOUR;
  minute: number = AppConfig.DEFAULT_RUN_MINUTE;
  second: number = AppConfig.DEFAULT_RUN_SECOND;
  /** 起始（结束）日期，默认昨天 */
  startDate: Date = yesterday();
  routeDecision: RouteDecision | undefined = undefined;

  constructor(days: number, distanceKm: number, hour: number, minute: number, second: number,
    startDate: Date, routeDecision: RouteDecision | undefined = undefined) {
    this.days = days;
    this.distanceKm = distanceKm;
    this.hour = hour;
    this.minute = minute;
    this.second = second;
    this.startDate = startDate;
    this.routeDecision = routeDecision;
  }
}

/**
 * 主界面 ViewModel
 * 迁移自 Android: com.sjtu.runner.viewmodel.MainViewModel
 * - StateFlow -> @ObservedV2 + @Trace（V2 状态管理）
 * - viewModelScope 协程 -> async/await 串行任务 + 停止标记
 * - 日志由“单条文本”改为 LogEntry 列表（等级 + 时间 + 内容），保留上限 400 条
 */
@ObservedV2
export class MainViewModel {
  /** 运行日志（环形上限 AppConfig.MAX_LOG_ENTRIES） */
  @Trace logs: LogEntry[] = [];
  @Trace running: boolean = false;
  /** 任务进度（当前/总数/阶段） */
  @Trace progress: TaskProgress = new TaskProgress(0, 0, TaskStatus.IDLE);
  @Trace routes: RouteInfo[] = [];
  @Trace selectedRoute: RouteInfo | undefined = undefined;
  /** 当前选中路线的预览（原始路线 / 离线预览 / 待上传 / 已上传） */
  @Trace preview: RoutePreview | undefined = undefined;
  /** 路线长度超过目标距离时的冲突提示 */
  @Trace routeConflict: RouteConflict | undefined = undefined;
  @Trace reloginRequired: boolean = false;
  /** 登录状态（由 CookieService 检测，供界面响应式刷新） */
  @Trace loginState: boolean = false;

  /** 触发重新登录时的回调（等价 MainActivity 设置的 onReloginRequired） */
  onReloginRequired: (() => void) | null = null;
  /** 新日志追加回调（用于日志面板自动滚动到底部） */
  onLogAppended: (() => void) | null = null;
  /** 路线冲突挂起时的回调（界面据此弹出“路线距离提醒”） */
  onRouteConflict: (() => void) | null = null;
  /** 当前生效的任务配置（等价 Android currentConfig） */
  currentConfig: RunConfig | undefined = undefined;

  private api: ApiService = new ApiService();
  private routeManager: RouteManager = RouteManager.getInstance();
  private taskStopped: boolean = false;
  private successCount: number = 0;
  private failCount: number = 0;
  private context: common.Context | undefined = undefined;

  private static instance: MainViewModel | null = null;

  static getInstance(): MainViewModel {
    if (MainViewModel.instance === null) {
      MainViewModel.instance = new MainViewModel();
    }
    return MainViewModel.instance;
  }

  /** 监听日志变化，通知 UI 滚动（等价 Android LaunchedEffect(logs.size) { animateScrollTo(max) }） */
  @Monitor('logs')
  onLogChange(): void {
    if (this.onLogAppended !== null) {
      this.onLogAppended();
    }
  }

  /** 通知界面路线冲突状态变化 */
  private notifyRouteConflict(): void {
    if (this.onRouteConflict !== null) {
      this.onRouteConflict();
    }
  }

  // ==================== 生命周期 / 路线 ====================

  /** 初始化（等价 Android ViewModel init { loadRoutes() }） */
  init(context: common.Context): void {
    this.context = context;
    this.routeManager.init(context);
    this.loadRoutes();
  }

  loadRoutes(): void {
    const allRoutes = this.routeManager.getAllRoutes();
    this.routes = allRoutes;
    // 没有选中路线时，默认选中默认路线（否则第一条）
    if (this.selectedRoute === undefined && allRoutes.length > 0) {
      let first: RouteInfo | undefined = undefined;
      for (let i = 0; i < allRoutes.length; i++) {
        if (allRoutes[i].isDefault) {
          first = allRoutes[i];
          break;
        }
      }
      if (first === undefined) {
        first = allRoutes[0];
      }
      this.selectedRoute = first;
    }
    this.refreshPreviewForSelectedRoute();
  }

  selectRoute(route: RouteInfo): void {
    this.selectedRoute = route;
    this.logMsg(LogLevel.INFO, `已选择路线: ${route.name}`);
    this.refreshPreviewForSelectedRoute();
  }

  deleteRoute(route: RouteInfo): void {
    if (route.isDefault) {
      this.logMsg(LogLevel.WARN, '默认路线不能删除');
      return;
    }
    const success = this.routeManager.deleteRoute(route.id);
    if (success) {
      this.logMsg(LogLevel.SUCCESS, `已删除路线: ${route.name}`);
      this.loadRoutes();
      if (this.selectedRoute !== undefined && this.selectedRoute.id === route.id) {
        let fallback: RouteInfo | undefined = undefined;
        for (let i = 0; i < this.routes.length; i++) {
          if (this.routes[i].isDefault) {
            fallback = this.routes[i];
            break;
          }
        }
        this.selectedRoute = fallback;
        this.refreshPreviewForSelectedRoute();
      }
    } else {
      this.logMsg(LogLevel.ERROR, '删除路线失败');
    }
  }

  refreshRoutes(): void {
    this.loadRoutes();
  }

  /** 刷新登录状态（写 @Trace loginState，界面自动响应） */
  refreshLoginState(): void {
    this.loginState = CookieService.isLoggedIn();
  }

  clearLogs(): void {
    this.logs = [];
  }

  private async currentRouteCoordinates(): Promise<GpsPoint[]> {
    const route = this.selectedRoute;
    if (route === undefined) {
      return [];
    }
    if (route.isDefault) {
      return this.routeManager.readDefaultRouteCoordinates();
    }
    const points = GpsUtil.readCoordinatesFromFile(route.filePath);
    if (points.length === 0) {
      this.logMsg(LogLevel.WARN, '路线文件不存在，使用默认路线');
      return this.routeManager.readDefaultRouteCoordinates();
    }
    return points;
  }

  // ==================== 日志 ====================

  /** 追加一条日志（等宽样式由界面按等级着色） */
  logMsg(level: LogLevel, msg: string): void {
    const now = new Date();
    const time = `${pad2(now.getHours())}:${pad2(now.getMinutes())}:${pad2(now.getSeconds())}`;
    const entry = new LogEntry(level, time, msg);
    if (this.logs.length >= AppConfig.MAX_LOG_ENTRIES) {
      const kept = this.logs.slice(this.logs.length - (AppConfig.MAX_LOG_ENTRIES - 1));
      kept.push(entry);
      this.logs = kept;
    } else {
      this.logs = this.logs.concat([entry]);
    }
  }

  // ==================== 参数校验 ====================

  /** 校验配置，返回错误文案；返回 undefined 表示通过 */
  validate(config: RunConfig): string | undefined {
    if (config.days < 1 || config.days > AppConfig.MAX_RUN_TIMES) {
      return `跑步次数应在 1-${AppConfig.MAX_RUN_TIMES} 之间`;
    }
    if (config.distanceKm <= 0 || config.distanceKm > AppConfig.MAX_DISTANCE_KM) {
      return `距离应大于 0 且不超过 ${Math.trunc(AppConfig.MAX_DISTANCE_KM)}km`;
    }
    if (config.hour < 0 || config.hour > 23 || config.minute < 0 || config.minute > 59
      || config.second < 0 || config.second > 59) {
      return '时间范围无效，小时 00-23，分钟和秒 00-59';
    }
    if (this.selectedRoute === undefined) {
      return '未选择任何路线，请先选择路线';
    }
    return undefined;
  }

  /** 界面每次重绘同步配置（等价 MainScreen 的 LaunchedEffect(config)） */
  updateConfig(config: RunConfig): void {
    this.currentConfig = config;
  }

  // ==================== 任务控制 ====================

  /**
   * 开始任务（等价 Android startUpload(config)）
   * routeDecision 为空时先判定路线是否超过目标距离，超过则挂起等待用户选择。
   */
  async startUpload(config: RunConfig): Promise<void> {
    if (this.running) {
      return;
    }
    // 先占位，避免 await 期间重复点击造成并发任务
    this.running = true;
    this.currentConfig = config;

    try {
      const error = this.validate(config);
      if (error !== undefined) {
        this.logMsg(LogLevel.ERROR, `配置错误: ${error}`);
        return;
      }

      const route = this.selectedRoute as RouteInfo;
      const coordinates = await this.currentRouteCoordinates();
      if (coordinates.length < 2) {
        this.logMsg(LogLevel.ERROR, '路线坐标为空，请选择其他路线');
        return;
      }

      if (config.routeDecision === undefined) {
        const routeDistanceM = DataGenerator.correctedRouteDistance(coordinates);
        const targetDistanceM = config.distanceKm * 1000.0;
        if (routeDistanceM > targetDistanceM) {
          // 挂起任务，等待用户在“路线距离提醒”中选择
          this.routeConflict = new RouteConflict(route.name, routeDistanceM, targetDistanceM);
          this.notifyRouteConflict();
          return;
        }
        await this.runUpload(new RunConfig(config.days, config.distanceKm, config.hour, config.minute,
          config.second, config.startDate, RouteDecision.TRUNCATE), coordinates);
        return;
      }

      if (config.routeDecision === RouteDecision.CANCEL) {
        this.routeConflict = undefined;
        this.notifyRouteConflict();
        this.logMsg(LogLevel.WARN, '已取消本次任务');
        return;
      }

      this.routeConflict = undefined;
      this.notifyRouteConflict();
      await this.runUpload(config, coordinates);
    } finally {
      this.running = false;
    }
  }

  /** 用户在“路线距离提醒”中做出选择后继续任务（等价 resolveRouteConflict） */
  async resolveRouteConflict(decision: RouteDecision): Promise<void> {
    const conflict = this.routeConflict;
    const base = this.currentConfig;
    this.routeConflict = undefined;
    this.notifyRouteConflict();
    if (conflict === undefined || base === undefined) {
      return;
    }
    if (decision === RouteDecision.TRUNCATE) {
      this.logMsg(LogLevel.INFO, '用户选择自动削减路线至目标距离');
    } else if (decision === RouteDecision.FULL_ROUTE) {
      this.logMsg(LogLevel.INFO, '用户选择按照完整路线进行跑步');
    } else {
      this.logMsg(LogLevel.WARN, '用户选择停止任务');
    }
    const distanceKm = decision === RouteDecision.FULL_ROUTE
      ? conflict.routeDistanceM / 1000.0
      : base.distanceKm;
    await this.startUpload(new RunConfig(base.days, distanceKm, base.hour, base.minute, base.second,
      base.startDate, decision));
  }

  /** 停止任务（等价 job?.cancel()，在每轮循环边界生效） */
  stopUpload(): void {
    if (!this.running) {
      return;
    }
    this.taskStopped = true;
    this.progress = new TaskProgress(this.progress.current, this.progress.total, TaskStatus.STOPPING);
    this.logMsg(LogLevel.WARN, '正在停止任务...');
  }

  /**
   * 执行生成与上传（等价 Android runUpload）
   * 并发度为 1：单条记录串行生成 + 上传，无重试、无断点续传。
   */
  private async runUpload(config: RunConfig, coordinates: GpsPoint[]): Promise<void> {
    this.taskStopped = false;
    this.successCount = 0;
    this.failCount = 0;
    this.reloginRequired = false;

    const days = config.days;
    const targetDistanceM = config.distanceKm * 1000.0;

    try {
      this.progress = new TaskProgress(0, days, TaskStatus.PREPARING);

      const route = this.selectedRoute;
      const routeName = route !== undefined ? route.name : '未知路线';
      this.logMsg(LogLevel.INFO, `使用路线: ${routeName}`);
      this.logMsg(LogLevel.INFO, '步骤 1/2: 获取认证...');
      if (coordinates.length < 2) {
        this.logMsg(LogLevel.ERROR, '路线坐标为空，请选择其他路线');
        this.progress = new TaskProgress(0, days, TaskStatus.FAILED);
        return;
      }
      this.logMsg(LogLevel.INFO, `路线点数量: ${coordinates.length}`);

      const uid = await this.api.getUid();
      if (uid === null) {
        this.logMsg(LogLevel.ERROR, 'UID 获取失败，cookie 可能已过期');
        this.progress = new TaskProgress(0, days, TaskStatus.FAILED);
        this.triggerRelogin();
        return;
      }
      this.logMsg(LogLevel.SUCCESS, 'UID 获取成功');

      this.progress = new TaskProgress(0, days, TaskStatus.AUTHENTICATING);
      const rules: PointRules = await this.api.getPointRules(uid, AppConfig.START_LONGITUDE, AppConfig.START_LATITUDE);
      this.logMsg(LogLevel.INFO,
        `打卡规则: id=${rules.id} 配速 ${Math.trunc(rules.spmin / 60)}-${Math.trunc(rules.spmax / 60)} 分钟/公里`);

      this.logMsg(LogLevel.INFO, '步骤 2/2: 生成并上传跑步数据...');

      for (let i = 0; i < days; i++) {
        if (!this.running || this.taskStopped) {
          break;
        }

        const startTimeMs = this.baseStartDateTimeMs(config, i);
        this.logMsg(LogLevel.INFO,
          `生成第 ${i + 1}/${days} 条数据 (${MainViewModel.formatDateTime(startTimeMs)})`);
        this.progress = new TaskProgress(i, days, TaskStatus.GENERATING);

        // 不在此处吞掉异常：生成失败应整体终止任务（等价 Android 异常冒泡到
        // 外层 catch → "错误: …" + TaskStatus.FAILED），而非跳过该天继续生成
        const outcome: RunOutcome = await DataGenerator.generate(coordinates, uid, targetDistanceM, startTimeMs,
          AppConfig.INTERVAL_SECONDS, rules, config.routeDecision !== RouteDecision.FULL_ROUTE,
          (level: LogLevel, msg: string) => {
            this.logMsg(level, msg);
          });

        this.publishPreview(outcome, routeName, '待上传', i + 1, days);
        this.logMsg(LogLevel.INFO,
          `实际距离 ${(outcome.distanceM / 1000.0).toFixed(2)}km / ${Math.trunc(outcome.durationSec / 60)}min / ${outcome.pointCount}点`);

        if (this.taskStopped) {
          break;
        }

        this.progress = new TaskProgress(i, days, TaskStatus.UPLOADING);
        const uploadResult = await this.api.upload(uid, outcome.payload);

        if (uploadResult.success) {
          this.successCount++;
          this.logMsg(LogLevel.SUCCESS, `第 ${i + 1}/${days} 条上传成功`);
          this.publishPreview(outcome, routeName, '已上传', i + 1, days);
        } else if (uploadResult.needRelogin) {
          this.logMsg(LogLevel.ERROR, `上传失败: ${uploadResult.message}`);
          this.progress = new TaskProgress(i + 1, days, TaskStatus.FAILED);
          this.triggerRelogin();
          break;
        } else {
          this.failCount++;
          this.logMsg(LogLevel.ERROR, `第 ${i + 1} 条失败: ${uploadResult.message}`);
          this.publishPreview(outcome, routeName, '上传失败', i + 1, days);
        }
        this.progress = new TaskProgress(i + 1, days, TaskStatus.UPLOADING);
      }

      if (this.running && !this.taskStopped) {
        const finished = this.failCount === 0;
        this.progress = new TaskProgress(this.successCount + this.failCount, days,
          finished ? TaskStatus.FINISHED : TaskStatus.FAILED);
        const summary = `任务完成: 成功 ${this.successCount} 条，失败 ${this.failCount} 条`;
        this.logMsg(finished ? LogLevel.SUCCESS : LogLevel.WARN, summary);
      } else {
        this.logMsg(LogLevel.WARN, '任务已手动停止');
        this.progress = new TaskProgress(this.progress.current, days, TaskStatus.IDLE);
      }
    } catch (e) {
      this.logMsg(LogLevel.ERROR, `错误: ${(e as Error).message}`);
      this.progress = new TaskProgress(this.progress.current, days, TaskStatus.FAILED);
    } finally {
      this.taskStopped = false;
    }
  }

  /** 起始时刻：配置时间 ± 10 分钟 ± 30 秒随机波动，再按第 i 条向前推 i 天 */
  private baseStartDateTimeMs(config: RunConfig, index: number): number {
    const base = new Date(config.startDate.getFullYear(), config.startDate.getMonth(), config.startDate.getDate(),
      config.hour, config.minute, config.second);
    base.setDate(base.getDate() - index);
    const jitterMs = randomInt(-600, 600) * 1000 + randomInt(-30, 30) * 1000;
    return base.getTime() + jitterMs;
  }

  private static formatDateTime(ms: number): string {
    const d = new Date(ms);
    return `${d.getFullYear()}-${pad2(d.getMonth() + 1)}-${pad2(d.getDate())} `
      + `${pad2(d.getHours())}:${pad2(d.getMinutes())}:${pad2(d.getSeconds())}`;
  }

  // ==================== 预览 ====================

  /** 离线预览当前设置下的轨迹（等价 Android previewRoute） */
  async previewRoute(): Promise<void> {
    if (this.running) {
      return;
    }
    const config = this.currentConfig;
    if (this.selectedRoute === undefined) {
      this.logMsg(LogLevel.ERROR, '未选择路线，无法预览');
      return;
    }
    if (config !== undefined) {
      const error = this.validate(config);
      if (error !== undefined) {
        this.logMsg(LogLevel.ERROR, `配置错误: ${error}`);
        return;
      }
    }
    this.logMsg(LogLevel.INFO, '正在离线预览路线…');
    const coordinates = await this.currentRouteCoordinates();
    if (coordinates.length < 2) {
      this.logMsg(LogLevel.ERROR, '路线坐标为空，无法预览');
      return;
    }
    const routeName = this.selectedRoute.name;
    try {
      const outcome = await DataGenerator.generate(coordinates, 'preview', Date.now(),
        config !== undefined ? config.distanceKm * 1000.0 : AppConfig.DEFAULT_DISTANCE_KM * 1000.0,
        AppConfig.INTERVAL_SECONDS, new PointRules(9, 180, 540), true,
        (level: LogLevel, msg: string) => {
          this.logMsg(level, msg);
        });
      this.publishPreview(outcome, routeName, '离线预览', 1, 1);
      this.logMsg(LogLevel.SUCCESS,
        `预览生成完成: ${(outcome.distanceM / 1000.0).toFixed(2)}km / ${outcome.pointCount}点 / ${outcome.jumpCount}处跳段`);
    } catch (e) {
      this.logMsg(LogLevel.ERROR, `预览失败: ${(e as Error).message}`);
    }
  }

  /** 仅展示原始路线（校正后），无轨迹时间（等价 refreshPreviewForSelectedRoute） */
  async refreshPreviewForSelectedRoute(): Promise<void> {
    const route = this.selectedRoute;
    if (route === undefined) {
      this.preview = undefined;
      return;
    }
    const coordinates = await this.currentRouteCoordinates();
    if (coordinates.length < 2) {
      this.preview = undefined;
      return;
    }
    const corrected = DataGenerator.correct(coordinates);
    const samples: TrackSample[] = [];
    for (let i = 0; i < corrected.length; i++) {
      samples.push(new TrackSample(corrected[i].lon, corrected[i].lat, 0));
    }
    const distanceKm = DataGenerator.routeDistance(corrected) / 1000.0;
    // 相邻点最大间距与首尾距离（等价 Android refreshPreviewForSelectedRoute 的统计口径）
    let maxSegmentM = 0.0;
    for (let i = 1; i < corrected.length; i++) {
      const seg = GpsUtil.haversineDistance(corrected[i - 1].lat, corrected[i - 1].lon,
        corrected[i].lat, corrected[i].lon);
      if (seg > maxSegmentM) {
        maxSegmentM = seg;
      }
    }
    const startEndDistanceM = corrected.length >= 2
      ? GpsUtil.haversineDistance(corrected[0].lat, corrected[0].lon,
        corrected[corrected.length - 1].lat, corrected[corrected.length - 1].lon)
      : 0.0;
    this.preview = new RoutePreview(route.name, '原始路线', distanceKm, 0.0, corrected.length, 0, 0,
      maxSegmentM, startEndDistanceM, samples);
  }

  private publishPreview(outcome: RunOutcome, routeName: string, status: string, index: number, total: number): void {
    const title = total > 1 ? `${routeName} · 第 ${index}/${total} 条` : routeName;
    this.preview = new RoutePreview(title, status, outcome.distanceM / 1000.0,
      outcome.durationSec / 60.0, outcome.pointCount, outcome.segmentCount, outcome.jumpCount,
      outcome.maxSegmentM, outcome.startEndDistanceM, outcome.samples);
  }

  // ==================== 重新登录 ====================

  /** 触发重新登录：清理 cookie 并回调（等价 triggerRelogin） */
  private triggerRelogin(): void {
    CookieService.clearAll();
    this.reloginRequired = true;
    if (this.onReloginRequired !== null) {
      this.onReloginRequired();
    }
  }
}
