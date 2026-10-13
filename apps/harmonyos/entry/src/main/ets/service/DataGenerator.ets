import { GpsPoint } from '../model/RouteInfo';
import { GpsUtil } from './GpsUtil';
import { LatLng, TrackPoint, Track, PayloadItem } from '../model/PayloadModels';
import { uuidV4 } from '../utils/FormatUtil';
import { LogLevel, PointRules, RunOutcome, TrackSample } from '../viewmodel/TaskModels';

/**
 * 数据生成器
 * 迁移自 Android: com.sjtu.runner.data.DataGenerator
 *
 * 业务逻辑逐行对齐 Android 版：
 *   坐标校正（固定常量平移）-> 单圈距离 -> 随机配速/目标速度 -> 路径调整
 *   （过长削减 / 往返策略 / 环路策略，含 +200m 补偿）-> 匀速时间戳 ->
 *   随机分段 -> 配速收敛到打卡规则 -> 组装 payload 与统计信息
 *
 * 说明：Android 侧的坐标“转换”仅有 correct() 这一步固定常量平移（BD09 -> 近似 GCJ02），
 * 没有真正的 BD09/GCJ02/WGS84 转换函数，此处保持一致。
 */
export class DataGenerator {
  private static readonly OFFSET_LON: number = -0.00651271494735 + 0.000094;
  private static readonly OFFSET_LAT: number = -0.00560888976477 - 0.000700;

  /** 距离补偿（米）：内部按“目标距离 + 200m”组织路径 */
  private static readonly DISTANCE_COMPENSATION_M: number = 200.0;
  /** 起终点距离阈值（米）：超过则采用往返策略，否则采用环路策略 */
  private static readonly ROUND_TRIP_THRESHOLD_M: number = 15.0;
  /** 跳段阈值（米）：相邻轨迹点距离超过该值视为一处跳段（仅用于预览高亮与统计） */
  static readonly JUMP_THRESHOLD_M: number = 150.0;
  /** 轨迹点坐标保留小数位 */
  private static readonly TRACK_POINT_DECIMAL_PLACES: number = 7;
  /** 单个轨迹段最少点数 */
  private static readonly MIN_SEGMENT_POINTS: number = 5;
  /**
   * 路径扩增上限（点数）。
   * 环路/往返策略按 completeLoops = target / singleLoop 复制整条路径：
   * 若路线过短（两点几乎重合，singleLoop 只有几厘米甚至更小），圈数可达数十万，
   * 每次循环都 push 一次 detailed，数组会被撑爆并触发 OutOfMemoryError（真机闪退）。
   * 正常路线（内置路线 singleLoop ≈ 871m、目标 ≤ 5km）最多几百点，远低于该上限；
   * 100km/1km 这类极端但结构正常的路线约 11 万点，会命中提示而不是闪退。
   */
  private static readonly MAX_EXPANSION_POINTS: number = 100000;
  /**
   * 目标距离合法区间（米）。
   * 界面只允许 1.0-5.0km，预留量级余量后作为兜底：距离一旦超出该区间（例如上游把
   * 毫秒时间戳误当作距离传入）说明参数错误，直接抛出可读错误，绝不进入扩增循环。
   */
  private static readonly MIN_TARGET_DISTANCE_M: number = 100.0;
  private static readonly MAX_TARGET_DISTANCE_M: number = 50000.0;

  private static readonly DEFAULT_RULES: PointRules = new PointRules(9, 180, 540);

  // ==================== 公共工具 ====================

  /** 坐标校正：逐点固定常量平移 */
  static correct(coordinates: GpsPoint[]): GpsPoint[] {
    const result: GpsPoint[] = [];
    for (let i = 0; i < coordinates.length; i++) {
      result.push(new GpsPoint(
        coordinates[i].lon + DataGenerator.OFFSET_LON,
        coordinates[i].lat + DataGenerator.OFFSET_LAT));
    }
    return result;
  }

  /** 逐段半正矢距离之和（米） */
  static routeDistance(coordinates: GpsPoint[]): number {
    let total = 0.0;
    for (let i = 0; i < coordinates.length - 1; i++) {
      total += GpsUtil.haversineDistance(
        coordinates[i].lat, coordinates[i].lon,
        coordinates[i + 1].lat, coordinates[i + 1].lon);
    }
    return total;
  }

  /** 校正后的路线长度（米），用于任务前的“路线是否超过目标距离”判定 */
  static correctedRouteDistance(coordinates: GpsPoint[]): number {
    return DataGenerator.routeDistance(DataGenerator.correct(coordinates));
  }

  private static roundTrack(value: number): number {
    const factor = Math.pow(10, DataGenerator.TRACK_POINT_DECIMAL_PLACES);
    return Math.round(value * factor) / factor;
  }

  private static fmtTrack(value: number): string {
    return value.toFixed(DataGenerator.TRACK_POINT_DECIMAL_PLACES);
  }

  private static fmt2(value: number): string {
    return value.toFixed(2);
  }

  // ==================== 主流程 ====================

  static async generate(
    coordinates: GpsPoint[],
    userId: string,
    targetDistanceM: number,
    startTimeMs: number,
    intervalSeconds: number = 3,
    rules: PointRules = DataGenerator.DEFAULT_RULES,
    truncateToTarget: boolean = true,
    log: (level: LogLevel, msg: string) => void
  ): Promise<RunOutcome> {
    if (coordinates.length < 2) {
      throw new Error('路线坐标点不足，至少需要 2 个点');
    }
    // 目标距离量纲与范围校验：只接受米，且不超过上限。
    // 若上游误传大数量级（例如把毫秒时间戳当成距离），循环圈数会到十亿级，
    // 数组瞬间撑爆内存；这里先拦下并给出可读错误。
    if (!Number.isFinite(targetDistanceM) || targetDistanceM < DataGenerator.MIN_TARGET_DISTANCE_M
      || targetDistanceM > DataGenerator.MAX_TARGET_DISTANCE_M) {
      throw new Error(
        `目标距离异常（${targetDistanceM}m），应在 ${DataGenerator.MIN_TARGET_DISTANCE_M}-` +
        `${DataGenerator.MAX_TARGET_DISTANCE_M}m 之间`);
    }

    const corrected = DataGenerator.correct(coordinates);
    log(LogLevel.INFO, `坐标已校正，共 ${corrected.length} 个点`);

    let singleLoopDistance = DataGenerator.routeDistance(corrected);
    log(LogLevel.INFO, `单圈距离: ${DataGenerator.fmt2(singleLoopDistance)}m`);

    // 完整路线模式：目标距离不足一条路线时，抬升为目标路线本身长度
    let effectiveTarget = targetDistanceM;
    if (!truncateToTarget && singleLoopDistance > effectiveTarget) {
      effectiveTarget = singleLoopDistance;
      log(LogLevel.INFO, `按完整路线跑步，目标距离调整为 ${DataGenerator.fmt2(effectiveTarget / 1000.0)} km`);
    }

    const randomPaceMinPerKm = 4.0 + Math.random() * 2.0;
    const totalDurationSec = Math.max(1, Math.round(randomPaceMinPerKm * 60.0 * effectiveTarget / 1000.0));
    const targetSpeedMps = effectiveTarget / totalDurationSec;
    log(LogLevel.INFO,
      `使用随机配速: ${randomPaceMinPerKm.toFixed(1)} 分钟/公里 (${Math.round(randomPaceMinPerKm * 60)} 秒/公里)`);
    log(LogLevel.INFO,
      `目标速度: ${DataGenerator.fmt2(targetSpeedMps)} m/s，目标距离: ${DataGenerator.fmt2(effectiveTarget)}m`);

    const adjusted = DataGenerator.adjustPath(corrected, targetSpeedMps, effectiveTarget, intervalSeconds, log);
    log(LogLevel.INFO, `调整后路径点数: ${adjusted.length}`);

    const points = DataGenerator.generateTrackPoints(adjusted, startTimeMs, targetSpeedMps);
    log(LogLevel.INFO, `生成轨迹点 ${points.length} 个`);

    const actualDistance = DataGenerator.pathDistance(adjusted);
    let actualDurationSec = 1;
    if (points.length >= 2) {
      actualDurationSec = Math.max(1,
        Math.round((points[points.length - 1].locatetime - points[0].locatetime) / 1000.0));
    }

    const tracks = DataGenerator.splitIntoSegments(points, actualDurationSec, log);
    log(LogLevel.INFO, `拆分为 ${tracks.length} 个轨迹段`);

    // 统计：相邻点最大间距与跳段数量
    // 注意：必须用未舍入的坐标（adjusted）计算，等价 Android 用 Triple 原始坐标；
    // 上传 payload 里的 latLng 仍是 7 位小数（与 Android 的 fmtTrack 一致）。
    let maxSegmentM = 0.0;
    let jumpCount = 0;
    for (let i = 0; i < adjusted.length - 1; i++) {
      const d = GpsUtil.haversineDistance(
        adjusted[i].lat, adjusted[i].lon,
        adjusted[i + 1].lat, adjusted[i + 1].lon);
      if (d > maxSegmentM) {
        maxSegmentM = d;
      }
      if (d > DataGenerator.JUMP_THRESHOLD_M) {
        jumpCount++;
      }
    }

    let startEndDistanceM = 0.0;
    if (adjusted.length >= 2) {
      startEndDistanceM = GpsUtil.haversineDistance(
        adjusted[0].lat, adjusted[0].lon,
        adjusted[adjusted.length - 1].lat, adjusted[adjusted.length - 1].lon);
    }

    const spAvg = DataGenerator.computeSpAvg(actualDistance, actualDurationSec, rules, log);

    const payloadItem: PayloadItem = {
      fravg: 0,
      id: rules.id,
      sid: uuidV4(),
      signpoints: [],
      spavg: spAvg,
      state: '0',
      tracks: tracks,
      userId: userId
    };

    const samples: TrackSample[] = [];
    for (let i = 0; i < points.length; i++) {
      samples.push(new TrackSample(points[i].latLng.longitude, points[i].latLng.latitude, points[i].locatetime));
    }

    const paceMinPerKm = actualDistance > 0 ? actualDurationSec / (actualDistance / 1000.0) / 60.0 : 0.0;

    return new RunOutcome([payloadItem], actualDistance, actualDurationSec, points.length, tracks.length,
      maxSegmentM, jumpCount, startEndDistanceM, samples, paceMinPerKm);
  }

  /**
   * 折线总长度（未舍入坐标）
   * 等价 Android routeDistance(List<Pair<Double, Double>>)，
   * 用于「调整后路径」本身的长度统计，避免 7 位小数舍入带来的误差。
   */
  private static pathDistance(points: GpsPoint[]): number {
    let total = 0.0;
    for (let i = 0; i < points.length - 1; i++) {
      total += GpsUtil.haversineDistance(
        points[i].lat, points[i].lon,
        points[i + 1].lat, points[i + 1].lon);
    }
    return total;
  }


  /**
   * 配速收敛到打卡规则允许的区间
   * 返回 spavg（整分钟/公里的整数），输入单位为米/秒
   */
  private static computeSpAvg(
    distanceM: number,
    durationSec: number,
    rules: PointRules,
    log: (level: LogLevel, msg: string) => void
  ): number {
    if (distanceM <= 0 || durationSec <= 0) {
      return 0;
    }
    const spAvgMinPerKm = Math.round(durationSec / (distanceM / 1000.0) / 60.0);
    if (spAvgMinPerKm * 60 < rules.spmin) {
      log(LogLevel.WARN,
        `配速 ${spAvgMinPerKm} 分钟/公里快于下限 ${Math.trunc(rules.spmin / 60)} 分钟/公里，已调整至下限`);
      return Math.ceil(rules.spmin / 60.0);
    } else if (spAvgMinPerKm * 60 > rules.spmax) {
      log(LogLevel.WARN,
        `配速 ${spAvgMinPerKm} 分钟/公里慢于上限 ${Math.trunc(rules.spmax / 60)} 分钟/公里，已调整至上限`);
      return Math.floor(rules.spmax / 60.0);
    }
    return spAvgMinPerKm;
  }

  // ==================== 路径调整 ====================

  private static adjustPath(
    original: GpsPoint[],
    speedMps: number,
    targetDistanceM: number,
    intervalSec: number,
    log: (level: LogLevel, msg: string) => void
  ): GpsPoint[] {
    const interval = Math.max(0.1, speedMps * Math.max(1, intervalSec));
    const compensatedTarget = targetDistanceM + DataGenerator.DISTANCE_COMPENSATION_M;

    // 1. 按步长在相邻原始点之间插值加密
    const detailed: GpsPoint[] = [original[0]];
    for (let i = 0; i < original.length - 1; i++) {
      const additions = DataGenerator.interpolateBetween(original[i], original[i + 1], interval);
      for (let j = 0; j < additions.length; j++) {
        detailed.push(additions[j]);
      }
      detailed.push(original[i + 1]);
    }

    // 1.5 扩增上限保护：加密后点数过多时直接拒绝。
    // 路线两点几乎重合（单段不足一个步长）或跨度过大时，detailed 本身就可能上百万点，
    // 继续下游会直接 OutOfMemoryError 杀进程（安卓端同样存在该缺陷，此处刻意加保护）。
    if (detailed.length > DataGenerator.MAX_EXPANSION_POINTS) {
      throw new Error(
        `路线点间距过小：按 ${DataGenerator.fmt2(interval)}m 加密后需要 ${detailed.length} 个点，` +
        `请重新设计路线或选择其他路线`);
    }

    const singleLoop = DataGenerator.routeDistance(detailed);
    const startEndDistance = (detailed.length >= 2)
      ? GpsUtil.haversineDistance(detailed[0].lat, detailed[0].lon,
        detailed[detailed.length - 1].lat, detailed[detailed.length - 1].lon)
      : 0.0;

    // 1.6 环路/往返按整条路径复制：先估算最终点数，避免 completeLoops 达数十万时撑爆数组。
    const estimatedPoints = (singleLoop > 0.0)
      ? (Math.trunc(compensatedTarget / singleLoop) + 1) * detailed.length
      : detailed.length;
    log(LogLevel.INFO,
      `路径加密后 ${detailed.length} 个点，单圈 ${DataGenerator.fmt2(singleLoop)}m，预计扩增后约 ${estimatedPoints} 个点`);
    if (estimatedPoints > DataGenerator.MAX_EXPANSION_POINTS) {
      throw new Error(
        `路线过短（单圈仅 ${DataGenerator.fmt2(singleLoop)}m），扩展到 ${DataGenerator.fmt2(targetDistanceM / 1000.0)}km ` +
        `需要约 ${estimatedPoints} 个轨迹点，请重新设计路线或选择其他路线`);
    }

    if (singleLoop > compensatedTarget) {
      log(LogLevel.WARN,
        `单次路径长度 ${DataGenerator.fmt2(singleLoop)}m 超过目标 ${DataGenerator.fmt2(targetDistanceM)}m，自动削减至目标距离`);
      return DataGenerator.truncateTo(detailed, compensatedTarget);
    }
    if (startEndDistance > DataGenerator.ROUND_TRIP_THRESHOLD_M) {
      log(LogLevel.INFO, `采用往返策略: 起终点距离 ${DataGenerator.fmt2(startEndDistance)}m > 15m`);
      return DataGenerator.buildRoundTrip(detailed, singleLoop, compensatedTarget);
    }
    log(LogLevel.INFO, `采用环路策略: 起终点距离 ${DataGenerator.fmt2(startEndDistance)}m <= 15m`);
    return DataGenerator.buildLoops(detailed, singleLoop, compensatedTarget);
  }

  /** 两点间按间隔插值（不含两端点；分母为 count+1，与 Android 一致） */
  private static interpolateBetween(a: GpsPoint, b: GpsPoint, interval: number): GpsPoint[] {
    const result: GpsPoint[] = [];
    const total = GpsUtil.haversineDistance(a.lat, a.lon, b.lat, b.lon);
    if (total <= 0.0 || interval <= 0.0) {
      return result;
    }
    const count = Math.trunc(total / interval);
    if (count <= 0) {
      return result;
    }
    // 单段插值同样要设上限：两点跨度过大时 count 可达上百万，先分配数组就会 OOM。
    // 正常跑步路线（相邻点几十米）count 为个位数到几十。
    if (count > DataGenerator.MAX_EXPANSION_POINTS) {
      throw new Error(
        `路线相邻点间距过大（${DataGenerator.fmt2(total)}m），按步长加密后单段需要 ${count} 个点，请检查路线坐标`);
    }
    for (let i = 1; i <= count; i++) {
      const f = i / (count + 1);
      result.push(new GpsPoint(a.lon + f * (b.lon - a.lon), a.lat + f * (b.lat - a.lat)));
    }
    return result;
  }

  /** 截断到目标距离（首点必留，末点按比例插值） */
  private static truncateTo(path: GpsPoint[], targetDistance: number): GpsPoint[] {
    const result: GpsPoint[] = [path[0]];
    let acc = 0.0;
    for (let i = 0; i < path.length - 1; i++) {
      const seg = GpsUtil.haversineDistance(path[i].lat, path[i].lon, path[i + 1].lat, path[i + 1].lon);
      if (acc + seg > targetDistance) {
        const remaining = targetDistance - acc;
        if (seg > 0) {
          const f = remaining / seg;
          result.push(new GpsPoint(
            path[i].lon + f * (path[i + 1].lon - path[i].lon),
            path[i].lat + f * (path[i + 1].lat - path[i].lat)));
        }
        acc = targetDistance;
        break;
      }
      const last = result[result.length - 1];
      if (last.lon !== path[i].lon || last.lat !== path[i].lat) {
        result.push(path[i]);
      }
      acc += seg;
    }
    return result;
  }

  /** 从路径头部前进到目标距离（用于往返/环路的余量段） */
  private static partialForward(path: GpsPoint[], targetDistance: number): GpsPoint[] {
    const partial: GpsPoint[] = [];
    let acc = 0.0;
    for (let i = 0; i < path.length - 1; i++) {
      const seg = GpsUtil.haversineDistance(path[i].lat, path[i].lon, path[i + 1].lat, path[i + 1].lon);
      if (acc + seg > targetDistance) {
        const remaining = targetDistance - acc;
        if (seg > 0) {
          const f = remaining / seg;
          partial.push(new GpsPoint(
            path[i].lon + f * (path[i + 1].lon - path[i].lon),
            path[i].lat + f * (path[i + 1].lat - path[i].lat)));
        }
        break;
      }
      if (partial.length === 0 || partial[partial.length - 1].lon !== path[i].lon
        || partial[partial.length - 1].lat !== path[i].lat) {
        partial.push(path[i]);
      }
      acc += seg;
    }
    return partial;
  }

  /** 追加 source 到 target，若衔接点重复则跳过 source 首点 */
  private static appendAvoidingDuplicate(target: GpsPoint[], source: GpsPoint[]): void {
    if (source.length === 0) {
      return;
    }
    let skip = 0;
    if (target.length > 0) {
      const last = target[target.length - 1];
      if (last.lon === source[0].lon && last.lat === source[0].lat) {
        skip = 1;
      }
    }
    for (let i = skip; i < source.length; i++) {
      target.push(source[i]);
    }
  }

  private static reversed(path: GpsPoint[]): GpsPoint[] {
    const result: GpsPoint[] = [];
    for (let i = path.length - 1; i >= 0; i--) {
      result.push(path[i]);
    }
    return result;
  }

  /** 往返策略：去程 + 回程为一趟，补足完整趟数后按余量取部分行程 */
  private static buildRoundTrip(detailed: GpsPoint[], singleLoop: number, compensatedTarget: number): GpsPoint[] {
    const roundTrip = singleLoop * 2;
    if (roundTrip <= 0.0) {
      return DataGenerator.truncateTo(
        DataGenerator.repeatForward(detailed, compensatedTarget), compensatedTarget);
    }
    const completeTrips = Math.trunc(compensatedTarget / roundTrip);
    const remaining = compensatedTarget - completeTrips * roundTrip;

    const result: GpsPoint[] = [];
    const backward = DataGenerator.reversed(detailed);
    for (let i = 0; i < completeTrips; i++) {
      for (let j = 0; j < detailed.length; j++) {
        result.push(detailed[j]);
      }
      DataGenerator.appendAvoidingDuplicate(result, backward);
    }

    if (remaining > 0) {
      const ratio = remaining / roundTrip;
      if (ratio <= 0.5) {
        DataGenerator.appendAvoidingDuplicate(result, DataGenerator.partialForward(detailed, remaining));
      } else {
        // 去重追加：每完成一圈后 result 末点已等于 detailed[0]，直接整段 push 会多出一个零长度点
        DataGenerator.appendAvoidingDuplicate(result, detailed);
        const backwardRemaining = remaining - singleLoop;
        if (backwardRemaining > 0) {
          DataGenerator.appendAvoidingDuplicate(result,
            DataGenerator.partialForward(backward, backwardRemaining));
        }
      }
    }
    return result;
  }

  /** 环路策略：整圈循环 + 余量部分前进 */
  private static buildLoops(detailed: GpsPoint[], singleLoop: number, compensatedTarget: number): GpsPoint[] {
    if (singleLoop <= 0.0) {
      return DataGenerator.truncateTo(
        DataGenerator.repeatForward(detailed, compensatedTarget), compensatedTarget);
    }
    const completeLoops = Math.trunc(compensatedTarget / singleLoop);
    const remaining = compensatedTarget - completeLoops * singleLoop;

    const result: GpsPoint[] = [];
    for (let i = 0; i < completeLoops; i++) {
      for (let j = 0; j < detailed.length; j++) {
        result.push(detailed[j]);
      }
    }
    if (remaining > 0) {
      DataGenerator.appendAvoidingDuplicate(result, DataGenerator.partialForward(detailed, remaining));
    }
    return result;
  }

  private static repeatForward(path: GpsPoint[], targetDistance: number): GpsPoint[] {
    const loopDistance = DataGenerator.routeDistance(path);
    if (loopDistance <= 0.0) {
      return path;
    }
    const loops = Math.max(1, Math.ceil(targetDistance / loopDistance));
    const result: GpsPoint[] = [];
    for (let i = 0; i < loops; i++) {
      for (let j = 0; j < path.length; j++) {
        result.push(path[j]);
      }
    }
    return result;
  }

  // ==================== 轨迹点与分段 ====================

  /** 匀速模型：按累计里程/速度推算每点时间戳（无逐点抖动） */
  private static generateTrackPoints(
    coords: GpsPoint[],
    startTimeMs: number,
    speedMps: number
  ): TrackPoint[] {
    const points: TrackPoint[] = [];
    let cumDist = 0.0;
    for (let i = 0; i < coords.length; i++) {
      if (i > 0) {
        cumDist += GpsUtil.haversineDistance(
          coords[i - 1].lat, coords[i - 1].lon,
          coords[i].lat, coords[i].lon);
      }
      const elapsed = speedMps > 0 ? cumDist / speedMps : 0.0;
      const latLng: LatLng = {
        latitude: DataGenerator.roundTrack(coords[i].lat),
        longitude: DataGenerator.roundTrack(coords[i].lon)
      };
      const point: TrackPoint = {
        latLng: latLng,
        location: `${DataGenerator.fmtTrack(coords[i].lon)},${DataGenerator.fmtTrack(coords[i].lat)}`,
        step: 0,
        // 等价 Android (elapsed * 1000).toLong()：向零截断，非四舍五入
        locatetime: startTimeMs + Math.trunc(elapsed * 1000)
      };
      points.push(point);
    }
    return points;
  }

  /** 随机分段：段长在 [5, remaining/3] 之间随机，段状态按 0.8/0.9 概率划分 */
  private static splitIntoSegments(
    allPoints: TrackPoint[],
    totalDurationSec: number,
    log: (level: LogLevel, msg: string) => void
  ): Track[] {
    const tracks: Track[] = [];
    let idx = 0;
    while (idx < allPoints.length) {
      const remainingPoints = allPoints.length - idx;
      let segmentLength = remainingPoints;
      if (remainingPoints > DataGenerator.MIN_SEGMENT_POINTS) {
        const upper = Math.max(DataGenerator.MIN_SEGMENT_POINTS + 1,
          Math.trunc(remainingPoints / 3) + 1);
        const r = DataGenerator.MIN_SEGMENT_POINTS
          + Math.trunc(Math.random() * (upper - DataGenerator.MIN_SEGMENT_POINTS));
        segmentLength = Math.max(DataGenerator.MIN_SEGMENT_POINTS, r);
      }
      const end = Math.min(idx + segmentLength, allPoints.length);
      const segmentPoints: TrackPoint[] = allPoints.slice(idx, end);
      idx += segmentPoints.length;

      let status: string;
      const rand = Math.random();
      if (rand < 0.8) {
        status = 'normal';
      } else if (rand < 0.9) {
        status = 'invalid';
      } else {
        status = 'stop';
      }
      const tstate = status === 'invalid' ? '2' : '0';

      let segmentDistance = 0.0;
      for (let i = 0; i < segmentPoints.length - 1; i++) {
        segmentDistance += GpsUtil.haversineDistance(
          segmentPoints[i].latLng.latitude, segmentPoints[i].latLng.longitude,
          segmentPoints[i + 1].latLng.latitude, segmentPoints[i + 1].latLng.longitude);
      }

      const startTime = segmentPoints[0].locatetime;
      const endTime = segmentPoints[segmentPoints.length - 1].locatetime;
      const track: Track = {
        counts: segmentPoints.length,
        distance: segmentDistance,
        duration: Math.ceil((endTime - startTime) / 1000.0),
        points: segmentPoints,
        status: status,
        trid: uuidV4(),
        tstate: tstate,
        stime: Math.trunc(startTime / 1000),
        etime: Math.trunc(endTime / 1000)
      };
      tracks.push(track);
    }
    if (totalDurationSec <= 0) {
      log(LogLevel.WARN, '轨迹总时长异常');
    }
    return tracks;
  }
}
