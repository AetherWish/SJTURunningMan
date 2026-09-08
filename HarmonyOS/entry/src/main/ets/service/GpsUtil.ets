import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { common } from '@kit.AbilityKit';
import { GpsPoint } from '../model/RouteInfo';

/**
 * GPS 工具
 * 迁移自 Android: com.sjtu.runner.utils.GpsUtil
 */
export class GpsUtil {
  static readonly EARTH_RADIUS: number = 6371000.0;

  /** 半正矢球面距离（米），参数顺序与 Android 版保持一致 */
  static haversineDistance(lat1: number, lon1: number, lat2: number, lon2: number): number {
    const dLat = (lat2 - lat1) * Math.PI / 180.0;
    const dLon = (lon2 - lon1) * Math.PI / 180.0;
    const a = Math.pow(Math.sin(dLat / 2), 2) +
      Math.cos(lat1 * Math.PI / 180.0) * Math.cos(lat2 * Math.PI / 180.0) *
      Math.pow(Math.sin(dLon / 2), 2);
    const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
    return GpsUtil.EARTH_RADIUS * c;
  }

  /** 解析 "lon,lat" 文本为坐标列表 */
  static parseCoordinates(text: string): GpsPoint[] {
    const list: GpsPoint[] = [];
    const lines = text.split(/\r?\n/);
    for (let i = 0; i < lines.length; i++) {
      const line = lines[i].trim();
      if (line.length === 0) {
        continue;
      }
      const parts = line.split(',');
      if (parts.length === 2) {
        const lon = parseFloat(parts[0]);
        const lat = parseFloat(parts[1]);
        if (!isNaN(lon) && !isNaN(lat)) {
          list.push(new GpsPoint(lon, lat));
        }
      }
    }
    return list;
  }

  /** 统计路线文本行数（用于显示点数） */
  static countCoordinateLines(text: string): number {
    let count = 0;
    const lines = text.split(/\r?\n/);
    for (let i = 0; i < lines.length; i++) {
      if (lines[i].trim().length > 0) {
        count++;
      }
    }
    return count;
  }

  /** 同步读取内置默认路线 rawfile 文本（rawfile/route_coordinates.txt） */
  static readDefaultRouteTextSync(context: common.Context): string {
    try {
      const content: Uint8Array = context.resourceManager.getRawFileContentSync('route_coordinates.txt');
      const decoder = util.TextDecoder.create('utf-8');
      return decoder.decodeToString(content);
    } catch (e) {
      return '';
    }
  }

  /**
   * 异步读取内置默认路线坐标
   * 等价 Android GpsUtil.readCoordinates(context)
   */
  static async readDefaultCoordinates(context: common.Context): Promise<GpsPoint[]> {
    const text = GpsUtil.readDefaultRouteTextSync(context);
    return GpsUtil.parseCoordinates(text);
  }

  /** 从沙箱文件读取坐标，等价 Android GpsUtil.readCoordinatesFromFile(file) */
  static readCoordinatesFromFile(filePath: string): GpsPoint[] {
    try {
      if (!fs.accessSync(filePath)) {
        return [];
      }
      const text = fs.readTextSync(filePath, { encoding: 'utf-8' });
      return GpsUtil.parseCoordinates(text);
    } catch (e) {
      return [];
    }
  }
}
