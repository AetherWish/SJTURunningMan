import { GpsPoint } from '../model/RouteInfo';
import { GpsUtil } from './GpsUtil';
import { LatLng, TrackPoint, Track, PayloadItem, GenerateResult } from '../model/PayloadModels';
import { toFixedStr, uuidV4 } from '../utils/FormatUtil';

/**
 * 数据生成器
 * 迁移自 Android: com.sjtu.runner.data.DataGenerator（object -> class 静态方法）
 * 业务逻辑保持一致：坐标校正 -> 路径调整 -> 轨迹点生成 -> 轨迹分段 -> payload 组装
 */
export class DataGenerator {
  private static readonly OFFSET_LON: number = -0.00651271494735 + 0.000094;
  private static readonly OFFSET_LAT: number = -0.00560888976477 - 0.000700;

  static async generate(
    coordinates: GpsPoint[],
    userId: string,
    targetDistanceM: number,
    startTimeMs: number,
    intervalSeconds: number,
    log: (msg: string) => void
  ): Promise<GenerateResult> {

    const corrected: GpsPoint[] = coordinates.map((p: GpsPoint) =>
      new GpsPoint(p.lon + DataGenerator.OFFSET_LON, p.lat + DataGenerator.OFFSET_LAT));
    log(`坐标已校正，共 ${corrected.length} 个点`);

    let singleLoopDistance = 0.0;
    if (corrected.length > 1) {
      for (let i = 0; i < corrected.length - 1; i++) {
        singleLoopDistance += GpsUtil.haversineDistance(
          corrected[i].lat, corrected[i].lon,
          corrected[i + 1].lat, corrected[i + 1].lon);
      }
    }
    log(`单圈距离: ${toFixedStr(singleLoopDistance, 2)}m，目标: ${targetDistanceM}m`);

    // 配速随机化：在4-6分钟/公里范围内随机生成（4-6分配）
    const randomPaceMinPerKm = 4.0 + (Math.random() * 2.0);
    const totalDurationSec = Math.round(randomPaceMinPerKm * 60.0 * targetDistanceM / 1000.0);
    const targetSpeedMps = targetDistanceM / totalDurationSec;
    log(`使用随机配速: ${toFixedStr(randomPaceMinPerKm, 1)} 分钟/公里 (${Math.round(randomPaceMinPerKm * 60)} 秒/公里)`);
    log(`目标速度: ${toFixedStr(targetSpeedMps, 2)} m/s`);

    const adjustedCoords = DataGenerator.adjustPath(corrected, targetDistanceM, targetSpeedMps, intervalSeconds, log);
    log(`调整后路径点数: ${adjustedCoords.length}`);

    const pointsWithTime = DataGenerator.generateTrackPoints(adjustedCoords, startTimeMs, targetSpeedMps, intervalSeconds);
    log(`生成轨迹点 ${pointsWithTime.length} 个`);

    const tracks = DataGenerator.splitIntoSegments(pointsWithTime);

    let actualDistance = 0.0;
    if (pointsWithTime.length >= 2) {
      for (let i = 0; i < pointsWithTime.length - 1; i++) {
        const p1 = pointsWithTime[i].latLng;
        const p2 = pointsWithTime[i + 1].latLng;
        actualDistance += GpsUtil.haversineDistance(p1.latitude, p1.longitude, p2.latitude, p2.longitude);
      }
    }

    let actualDurationSec = 0.0;
    if (pointsWithTime.length >= 2) {
      actualDurationSec =
        (pointsWithTime[pointsWithTime.length - 1].locatetime - pointsWithTime[0].locatetime) / 1000.0;
    }
    const avgPaceMinPerKm = actualDistance > 0 ? actualDurationSec / (actualDistance / 1000.0) / 60.0 : 0.0;
    const spAvg = Math.min(Math.max(Math.round(avgPaceMinPerKm), 3), 9);

    const payloadItem: PayloadItem = {
      fravg: 0,
      id: 9,
      sid: uuidV4(),
      signpoints: [],
      spavg: spAvg,
      state: '0',
      tracks: tracks,
      userId: userId
    };
    const payload: PayloadItem[] = [payloadItem];

    return new GenerateResult(payload, actualDistance);
  }

  /** 智能路径调整：过长得截断，过短则按整圈 + 余量补足（往返/环路策略在路线本身上体现） */
  private static adjustPath(
    original: GpsPoint[],
    targetDistance: number,
    speedMps: number,
    intervalSec: number,
    log: (msg: string) => void
  ): GpsPoint[] {
    const stepDist = speedMps * intervalSec;

    // 1. 细化：在相邻原始点之间按步长线性插值
    const detailed: GpsPoint[] = [original[0]];
    for (let i = 0; i < original.length - 1; i++) {
      const lon1 = original[i].lon;
      const lat1 = original[i].lat;
      const lon2 = original[i + 1].lon;
      const lat2 = original[i + 1].lat;
      const dist = GpsUtil.haversineDistance(lat1, lon1, lat2, lon2);
      const steps = Math.max(1, Math.round(dist / stepDist));
      for (let j = 1; j <= steps; j++) {
        const f = j / (steps + 1);
        const lon = lon1 + f * (lon2 - lon1);
        const lat = lat1 + f * (lat2 - lat1);
        detailed.push(new GpsPoint(lon, lat));
      }
      detailed.push(original[i + 1]);
    }

    // 2. 计算细化后单圈距离
    let singleLoop = 0.0;
    for (let i = 0; i < detailed.length - 1; i++) {
      singleLoop += GpsUtil.haversineDistance(
        detailed[i].lat, detailed[i].lon,
        detailed[i + 1].lat, detailed[i + 1].lon);
    }

    // 3. 单圈 >= 目标：截断到目标距离
    if (singleLoop >= targetDistance) {
      let acc = 0.0;
      const truncated: GpsPoint[] = [detailed[0]];
      for (let i = 0; i < detailed.length - 1; i++) {
        const seg = GpsUtil.haversineDistance(
          detailed[i].lat, detailed[i].lon,
          detailed[i + 1].lat, detailed[i + 1].lon);
        if (acc + seg >= targetDistance) {
          const rem = targetDistance - acc;
          const f = seg > 0 ? rem / seg : 0.0;
          const lastLon = detailed[i].lon + f * (detailed[i + 1].lon - detailed[i].lon);
          const lastLat = detailed[i].lat + f * (detailed[i + 1].lat - detailed[i].lat);
          truncated.push(new GpsPoint(lastLon, lastLat));
          break;
        }
        truncated.push(detailed[i + 1]);
        acc += seg;
      }
      return truncated;
    }

    // 4. 单圈 < 目标：整圈循环 + 余量截断
    const fullLoops = Math.floor(targetDistance / singleLoop);
    const remainder = targetDistance - fullLoops * singleLoop;

    const result: GpsPoint[] = [];
    for (let k = 0; k < fullLoops; k++) {
      for (let i = 0; i < detailed.length; i++) {
        result.push(detailed[i]);
      }
    }
    let acc = 0.0;
    for (let i = 0; i < detailed.length - 1; i++) {
      const seg = GpsUtil.haversineDistance(
        detailed[i].lat, detailed[i].lon,
        detailed[i + 1].lat, detailed[i + 1].lon);
      if (acc + seg >= remainder) {
        const rem = remainder - acc;
        const f = seg > 0 ? rem / seg : 0.0;
        const lastLon = detailed[i].lon + f * (detailed[i + 1].lon - detailed[i].lon);
        const lastLat = detailed[i].lat + f * (detailed[i + 1].lat - detailed[i].lat);
        result.push(new GpsPoint(lastLon, lastLat));
        break;
      }
      result.push(detailed[i + 1]);
      acc += seg;
    }
    log(`最终路径: ${fullLoops}圈 + 余量 ${toFixedStr(remainder, 2)}m`);
    return result;
  }

  /** 按累计里程/速度生成带时间戳的轨迹点 */
  private static generateTrackPoints(
    coords: GpsPoint[],
    startTimeMs: number,
    speedMps: number,
    intervalSec: number
  ): TrackPoint[] {
    const points: TrackPoint[] = [];
    let cumDist = 0.0;
    for (let i = 0; i < coords.length; i++) {
      if (i > 0) {
        cumDist += GpsUtil.haversineDistance(
          coords[i - 1].lat, coords[i - 1].lon,
          coords[i].lat, coords[i].lon);
      }
      const elapsed = cumDist / speedMps;
      const time = startTimeMs + Math.trunc(elapsed * 1000);
      const latLng: LatLng = { latitude: coords[i].lat, longitude: coords[i].lon };
      const point: TrackPoint = {
        latLng: latLng,
        location: `${toFixedStr(coords[i].lon, 14)},${toFixedStr(coords[i].lat, 14)}`,
        step: 0,
        locatetime: time
      };
      points.push(point);
    }
    return points;
  }

  /** 将轨迹点随机切分为多个轨迹段，并分配 normal/invalid/stop 状态 */
  private static splitIntoSegments(allPoints: TrackPoint[]): Track[] {
    const tracks: Track[] = [];
    let idx = 0;
    while (idx < allPoints.length) {
      const divisor = 2 + Math.trunc(Math.random() * 3);
      const take = Math.min(Math.max(5, Math.trunc((allPoints.length - idx) / divisor)), allPoints.length - idx);
      const segmentPoints: TrackPoint[] = allPoints.slice(idx, idx + take);
      idx += take;

      let status: string;
      if (Math.random() < 0.8) {
        status = 'normal';
      } else if (Math.random() < 0.9) {
        status = 'invalid';
      } else {
        status = 'stop';
      }
      const tstate = status === 'invalid' ? '2' : '0';

      let dist = 0.0;
      if (segmentPoints.length >= 2) {
        for (let i = 0; i < segmentPoints.length - 1; i++) {
          const al = segmentPoints[i].latLng;
          const bl = segmentPoints[i + 1].latLng;
          dist += GpsUtil.haversineDistance(al.latitude, al.longitude, bl.latitude, bl.longitude);
        }
      }

      const startTime = segmentPoints[0].locatetime;
      const endTime = segmentPoints[segmentPoints.length - 1].locatetime;
      const track: Track = {
        counts: segmentPoints.length,
        distance: dist,
        duration: Math.round((endTime - startTime) / 1000.0),
        points: segmentPoints,
        status: status,
        trid: uuidV4(),
        tstate: tstate,
        stime: Math.trunc(startTime / 1000),
        etime: Math.trunc(endTime / 1000)
      };
      tracks.push(track);
    }
    return tracks;
  }
}
