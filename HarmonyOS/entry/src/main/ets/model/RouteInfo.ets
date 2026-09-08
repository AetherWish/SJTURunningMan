/**
 * 路线信息模型
 * 迁移自 Android: com.sjtu.runner.route.RouteInfo (data class + Parcelable)
 * HarmonyOS 端通过路由参数/AppStorage 传递即可，无需 Parcelable 等价物。
 */
export interface RouteInfo {
  id: string;
  name: string;
  filePath: string;
  isDefault: boolean;
  pointCount: number;
  createdAt: number;
}

/**
 * 坐标点（经纬度对）
 * 迁移自 Android 中广泛使用的 Pair<Double, Double>（first=经度 lon, second=纬度 lat）
 */
export class GpsPoint {
  lon: number;
  lat: number;

  constructor(lon: number, lat: number) {
    this.lon = lon;
    this.lat = lat;
  }
}
