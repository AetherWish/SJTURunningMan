/**
 * 上传 payload 数据模型
 * 迁移自 Android DataGenerator.kt 中以 Map<String, Any> 表达的结构，
 * ArkTS 严格类型模式下改为显式 interface，字段与原始 JSON 保持一致。
 */

/** 轨迹点坐标 */
export interface LatLng {
  latitude: number;
  longitude: number;
}

/** 单个轨迹点（含时间戳与位置字符串） */
export interface TrackPoint {
  latLng: LatLng;
  location: string;
  step: number;
  locatetime: number;
}

/** 轨迹段 */
export interface Track {
  counts: number;
  distance: number;
  duration: number;
  points: TrackPoint[];
  status: string;
  trid: string;
  tstate: string;
  stime: number;
  etime: number;
}

/** 上传 payload 顶层结构（数组元素） */
export interface PayloadItem {
  fravg: number;
  id: number;
  sid: string;
  signpoints: Object[];
  spavg: number;
  state: string;
  tracks: Track[];
  userId: string;
}

/** 上传结果 */
export class UploadResult {
  success: boolean;
  message: string;
  needRelogin: boolean;

  constructor(success: boolean, message: string, needRelogin: boolean = false) {
    this.success = success;
    this.message = message;
    this.needRelogin = needRelogin;
  }
}

/** 生成结果：payload + 实际距离（米） */
export class GenerateResult {
  payload: PayloadItem[];
  actualDistance: number;

  constructor(payload: PayloadItem[], actualDistance: number) {
    this.payload = payload;
    this.actualDistance = actualDistance;
  }
}
