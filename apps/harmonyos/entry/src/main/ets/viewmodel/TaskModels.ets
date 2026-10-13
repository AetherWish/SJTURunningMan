/**
 * 任务模型
 * 迁移自 Android: com.sjtu.runner.viewmodel.TaskModels
 * 差异：Kotlin 的 enum（带 label）/ data class 改为 ArkTS 枚举 + 显式 class，
 *       summary/fraction 由 Kotlin 的计算属性改为 ArkTS getter。
 */

import { PayloadItem } from '../model/PayloadModels';

/** 日志等级（等价 Android data.LogLevel） */
export enum LogLevel {
  INFO = 'INFO',
  WARN = 'WARN',
  ERROR = 'ERROR',
  SUCCESS = 'SUCCESS'
}

/** 单条日志：等级 + HH:mm:ss 时间 + 内容 */
export class LogEntry {
  level: LogLevel;
  time: string;
  message: string;

  constructor(level: LogLevel, time: string, message: string) {
    this.level = level;
    this.time = time;
    this.message = message;
  }
}

/** 任务阶段（label 与 Android 逐字一致） */
export enum TaskStatus {
  IDLE = 'IDLE',
  PREPARING = 'PREPARING',
  AUTHENTICATING = 'AUTHENTICATING',
  GENERATING = 'GENERATING',
  UPLOADING = 'UPLOADING',
  STOPPING = 'STOPPING',
  FINISHED = 'FINISHED',
  FAILED = 'FAILED'
}

/** 任务阶段中文文案 */
export function taskStatusLabel(status: TaskStatus): string {
  switch (status) {
    case TaskStatus.PREPARING:
      return '准备中';
    case TaskStatus.AUTHENTICATING:
      return '获取认证';
    case TaskStatus.GENERATING:
      return '生成数据';
    case TaskStatus.UPLOADING:
      return '上传中';
    case TaskStatus.STOPPING:
      return '正在停止';
    case TaskStatus.FINISHED:
      return '已完成';
    case TaskStatus.FAILED:
      return '失败';
    case TaskStatus.IDLE:
    default:
      return '空闲';
  }
}

/** 任务进度 */
export class TaskProgress {
  current: number;
  total: number;
  status: TaskStatus;

  constructor(current: number = 0, total: number = 0, status: TaskStatus = TaskStatus.IDLE) {
    this.current = current;
    this.total = total;
    this.status = status;
  }

  /** 完成比例（0-1），total<=0 时为 0 */
  get fraction(): number {
    if (this.total <= 0) {
      return 0;
    }
    const value = this.current / this.total;
    if (value < 0) {
      return 0;
    }
    if (value > 1) {
      return 1;
    }
    return value;
  }
}

/** 用户对“路线过长”的处理决策 */
export enum RouteDecision {
  TRUNCATE = 'TRUNCATE',
  FULL_ROUTE = 'FULL_ROUTE',
  CANCEL = 'CANCEL'
}

/** 路线长度冲突（用于弹出“路线距离提醒”） */
export class RouteConflict {
  routeName: string;
  routeDistanceM: number;
  targetDistanceM: number;

  constructor(routeName: string, routeDistanceM: number, targetDistanceM: number) {
    this.routeName = routeName;
    this.routeDistanceM = routeDistanceM;
    this.targetDistanceM = targetDistanceM;
  }
}

/** 预览用轨迹采样点 */
export class TrackSample {
  longitude: number;
  latitude: number;
  timeMs: number;

  constructor(longitude: number, latitude: number, timeMs: number) {
    this.longitude = longitude;
    this.latitude = latitude;
    this.timeMs = timeMs;
  }
}

/** 路线/轨迹预览（映射到 Android RoutePreview） */
export class RoutePreview {
  title: string;
  status: string;
  distanceKm: number;
  durationMin: number;
  pointCount: number;
  segmentCount: number;
  jumpCount: number;
  maxSegmentM: number;
  startEndDistanceM: number;
  samples: TrackSample[];

  constructor(title: string, status: string, distanceKm: number, durationMin: number, pointCount: number,
    segmentCount: number, jumpCount: number, maxSegmentM: number, startEndDistanceM: number,
    samples: TrackSample[]) {
    this.title = title;
    this.status = status;
    this.distanceKm = distanceKm;
    this.durationMin = durationMin;
    this.pointCount = pointCount;
    this.segmentCount = segmentCount;
    this.jumpCount = jumpCount;
    this.maxSegmentM = maxSegmentM;
    this.startEndDistanceM = startEndDistanceM;
    this.samples = samples;
  }

  /** 摘要文案，格式与 Android 完全一致 */
  get summary(): string {
    return `${this.distanceKm.toFixed(2)}km / ${this.pointCount}点 / ${this.jumpCount}处跳段 / ${this.status}`;
  }
}

/** 打卡规则（服务端返回，id==6 会被规范化为 9） */
export class PointRules {
  id: number;
  spmin: number;
  spmax: number;

  constructor(id: number, spmin: number, spmax: number) {
    this.id = id;
    this.spmin = spmin;
    this.spmax = spmax;
  }
}

/** 数据生成结果：payload + 统计信息（等价 Android RunOutcome） */
export class RunOutcome {
  payload: PayloadItem[];
  distanceM: number;
  durationSec: number;
  pointCount: number;
  segmentCount: number;
  maxSegmentM: number;
  jumpCount: number;
  startEndDistanceM: number;
  samples: TrackSample[];
  paceMinPerKm: number;

  constructor(payload: PayloadItem[], distanceM: number, durationSec: number, pointCount: number,
    segmentCount: number, maxSegmentM: number, jumpCount: number, startEndDistanceM: number,
    samples: TrackSample[], paceMinPerKm: number) {
    this.payload = payload;
    this.distanceM = distanceM;
    this.durationSec = durationSec;
    this.pointCount = pointCount;
    this.segmentCount = segmentCount;
    this.maxSegmentM = maxSegmentM;
    this.jumpCount = jumpCount;
    this.startEndDistanceM = startEndDistanceM;
    this.samples = samples;
    this.paceMinPerKm = paceMinPerKm;
  }
}
