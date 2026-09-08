import { common } from '@kit.AbilityKit';
import { RouteInfo } from '../model/RouteInfo';
import { ApiService } from '../service/ApiService';
import { RouteManager } from '../service/RouteManager';
import { GpsUtil } from '../service/GpsUtil';
import { CookieService } from '../service/CookieService';
import { DataGenerator } from '../service/DataGenerator';
import { GpsPoint } from '../model/RouteInfo';
import { formatDate, parseDate, yesterday, randomInt, localDateTimeMs, formatTimeMs, pad2 } from '../utils/FormatUtil';

/**
 * 主界面 ViewModel
 * 迁移自 Android: com.sjtu.runner.viewmodel.MainViewModel
 * - StateFlow -> @ObservedV2 + @Trace（V2 状态管理）
 * - viewModelScope 协程 -> async/await 串行任务 + 停止标记
 */
@ObservedV2
export class MainViewModel {
  @Trace log: string = '';
  @Trace running: boolean = false;
  @Trace routes: RouteInfo[] = [];
  @Trace selectedRoute: RouteInfo | undefined = undefined;
  @Trace reloginRequired: boolean = false;
  /** 登录状态（由 CookieService 检测，供界面响应式刷新） */
  @Trace loginState: boolean = false;
  /** 触发重新登录时的回调（等价 MainActivity 设置的 onReloginRequired） */
  onReloginRequired: (() => void) | null = null;
  /** 新日志追加回调（用于日志面板自动滚动到底部） */
  onLogAppended: (() => void) | null = null;

  private api: ApiService = new ApiService();
  private routeManager: RouteManager = RouteManager.getInstance();
  private taskStopped: boolean = false;

  private static instance: MainViewModel | null = null;

  static getInstance(): MainViewModel {
    if (MainViewModel.instance === null) {
      MainViewModel.instance = new MainViewModel();
    }
    return MainViewModel.instance;
  }

  /** 监听日志变化，通知 UI 滚动（等价 Android LaunchedEffect(log) { animateScrollTo(max) }） */
  @Monitor('log')
  onLogChange(): void {
    if (this.onLogAppended !== null) {
      this.onLogAppended();
    }
  }

  /** 初始化（等价 Android ViewModel init + loadRoutes） */
  init(context: common.Context): void {
    this.routeManager.init(context);
    this.loadRoutes();
  }

  loadRoutes(): void {
    const allRoutes = this.routeManager.getAllRoutes();
    this.routes = allRoutes;
    // 如果没有选中路线，默认选中默认路线
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
  }

  selectRoute(route: RouteInfo): void {
    this.selectedRoute = route;
    this.logMsg(`已选择路线: ${route.name}`);
  }

  deleteRoute(route: RouteInfo): void {
    if (route.isDefault) {
      this.logMsg('默认路线不能删除');
      return;
    }
    const success = this.routeManager.deleteRoute(route.id);
    if (success) {
      this.logMsg(`已删除路线: ${route.name}`);
      this.loadRoutes(); // 刷新列表
      // 如果删除的是当前选中的路线，切换到默认路线
      if (this.selectedRoute !== undefined && this.selectedRoute.id === route.id) {
        let fallback: RouteInfo | undefined = undefined;
        for (let i = 0; i < this.routes.length; i++) {
          if (this.routes[i].isDefault) {
            fallback = this.routes[i];
            break;
          }
        }
        this.selectedRoute = fallback;
      }
    } else {
      this.logMsg('删除路线失败');
    }
  }

  refreshRoutes(): void {
    this.loadRoutes();
  }

  /** 刷新登录状态（写 @Trace loginState，界面自动响应） */
  refreshLoginState(): void {
    this.loginState = CookieService.isLoggedIn();
  }

  private async getCurrentRouteCoordinates(): Promise<GpsPoint[]> {
    const route = this.selectedRoute;
    if (route === undefined) {
      return [];
    }
    if (route.isDefault) {
      return this.routeManager.readDefaultRouteCoordinates();
    }
    const points = GpsUtil.readCoordinatesFromFile(route.filePath);
    if (points.length === 0) {
      this.logMsg('路线文件不存在，使用默认路线');
      return this.routeManager.readDefaultRouteCoordinates();
    }
    return points;
  }

  /**
   * 开始生成并上传
   * 迁移自 MainViewModel.startUpload(days, distanceKm, hour, minute, dateStr)
   */
  async startUpload(days: number, distanceKm: number, hour: number, minute: number, dateStr: string): Promise<void> {
    this.running = true;
    this.log = '';
    this.taskStopped = false;

    try {
      // 检查是否选中路线
      const selected = this.selectedRoute;
      if (selected === undefined) {
        this.logMsg('未选择任何路线，请先选择路线');
        return;
      }
      this.logMsg(`使用路线: ${selected.name}`);

      this.logMsg('步骤1: 获取坐标路线...');
      const coordinates = await this.getCurrentRouteCoordinates();
      if (coordinates.length === 0) {
        this.logMsg('路线坐标为空，请选择其他路线');
        return;
      }
      this.logMsg(`路线点数量: ${coordinates.length}`);

      this.logMsg('步骤2: 获取 UID...');
      const uid = await this.api.getUid();
      if (uid === null) {
        this.logMsg('UID 获取失败，可能cookie已过期，尝试重新登录...');
        this.triggerRelogin();
        return;
      }
      this.logMsg(`UID 获取成功: ${uid}`);

      const targetDistanceM = distanceKm * 1000;

      let startDate: Date;
      const parsed = parseDate(dateStr.trim());
      if (dateStr.trim().length === 0 || parsed === null) {
        startDate = yesterday();
      } else {
        startDate = parsed;
      }

      for (let i = 0; i < days; i++) {
        if (!this.running || this.taskStopped) {
          break;
        }

        const date = new Date(startDate.getFullYear(), startDate.getMonth(), startDate.getDate());
        date.setDate(date.getDate() - i);

        const randomOffsetSec = randomInt(-600, 600);

        const startTimeMs = localDateTimeMs(date, hour, minute) + randomOffsetSec * 1000;
        const displayTime = formatTimeMs(startTimeMs);

        this.logMsg(`生成第 ${i + 1}/${days} 条数据 (${formatDate(date)} ${displayTime})...`);
        const result = await DataGenerator.generate(coordinates, uid, targetDistanceM, startTimeMs, 3,
          (msg: string) => {
            this.logMsg(msg);
          });
        this.logMsg(`实际距离: ${result.actualDistance.toFixed(2)} m`);

        this.logMsg(`上传第 ${i + 1}/${days} 条...`);
        const uploadResult = await this.api.upload(uid, result.payload);

        if (uploadResult.success) {
          this.logMsg(`第 ${i + 1} 条上传成功`);
        } else {
          if (uploadResult.needRelogin) {
            this.logMsg(`上传失败: ${uploadResult.message}，尝试重新登录...`);
            this.triggerRelogin();
            break;
          } else {
            this.logMsg(`失败: ${uploadResult.message}`);
          }
        }
      }
      this.logMsg('全部任务完成');
    } catch (e) {
      this.logMsg(`错误: ${(e as Error).message}`);
    } finally {
      this.running = false;
    }
  }

  /** 停止任务（等价 job?.cancel()） */
  stopUpload(): void {
    this.taskStopped = true;
    this.running = false;
    this.logMsg('任务已手动停止');
  }

  logMsg(msg: string): void {
    this.log = this.log + `\n${pad2(new Date().getHours())}:${pad2(new Date().getMinutes())}:${pad2(new Date().getSeconds())} ${msg}`;
  }

  /** 触发重新登录：清理 cookie 并回调（等价 triggerRelogin） */
  private triggerRelogin(): void {
    CookieService.clearAll();
    this.reloginRequired = true;
    if (this.onReloginRequired !== null) {
      this.onReloginRequired();
    }
  }
}
