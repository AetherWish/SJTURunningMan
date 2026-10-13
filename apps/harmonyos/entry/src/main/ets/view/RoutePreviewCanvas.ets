/**
 * 路线预览画布
 * 迁移自 Android: com.sjtu.runner.ui.components.RoutePreviewCanvas
 *
 * ArkUI 差异说明：
 * 1. Android 用 Compose Canvas 绘制，这里用 ArkUI Canvas + CanvasRenderingContext2D；
 * 2. 画布颜色需要具体颜色字符串（Canvas 的 strokeStyle / fillStyle 不接受 Resource），
 *    取值来自冻结的预览配色：连线 #01689B、起点 #10B981、终点 #E87525、跳段 #EF4444，
 *    透明度以 rgba() 表达；点标记外圈光晕用中性灰，浅色/深色背景下都可见；
 * 3. 跳段距离在本文件内实现（Android 复用 GpsUtil.haversine，本文件不在其写入范围内），
 *    常量 EARTH_RADIUS = 6371000，参数顺序与 Android 一致：haversine(lat1, lon1, lat2, lon2)；
 * 4. 轨迹数据变更后重绘走属性变更回调，画布尚未就绪时由 onReady 补绘。
 */
import { TrackSample } from '../viewmodel/TaskModels';

/** 跳段判定阈值（米），与 Android DataGenerator.JUMP_THRESHOLD_M 一致 */
const JUMP_THRESHOLD_M: number = 150;
/** 地球平均半径（米） */
const EARTH_RADIUS: number = 6371000;
/** 画布内边距（vp） */
const VIEW_PADDING: number = 12;
/** 虚线样式（实线段 / 空白段，单位 vp） */
const DASH_PATTERN: number[] = [14, 6];
/** 轨迹连线（半透明蓝） */
const LINE_COLOR: string = 'rgba(1, 104, 155, 0.85)';
/** 跳段高亮（半透明红） */
const JUMP_COLOR: string = 'rgba(239, 68, 68, 0.9)';
/** 起点（绿） */
const START_COLOR: string = '#10B981';
/** 终点（橙） */
const END_COLOR: string = '#E87525';
/** 标记点光晕（中性灰，明暗背景下均可见） */
const HALO_COLOR: string = 'rgba(128, 128, 128, 0.45)';

const FULL_CIRCLE: number = Math.PI * 2;

function toRadians(degree: number): number {
  return degree * Math.PI / 180;
}

/** 球面距离（米），参数顺序与 Android GpsUtil.haversine(lat1, lon1, lat2, lon2) 一致 */
function haversine(lat1: number, lon1: number, lat2: number, lon2: number): number {
  const dLat: number = toRadians(lat2 - lat1);
  const dLon: number = toRadians(lon2 - lon1);
  const sinLat: number = Math.sin(dLat / 2);
  const sinLon: number = Math.sin(dLon / 2);
  const a: number = sinLat * sinLat + Math.cos(toRadians(lat1)) * Math.cos(toRadians(lat2)) * sinLon * sinLon;
  return 2 * EARTH_RADIUS * Math.asin(Math.sqrt(a > 1 ? 1 : a));
}

@Component
export struct RoutePreviewCanvas {
  /** 预览采样点（少于 2 个点显示占位文案） */
  @Prop @Watch('onDataChanged') samples: TrackSample[] = [];
  /** 跳段数量，>0 时高亮超阈值线段 */
  @Prop @Watch('onDataChanged') jumpCount: number = 0;
  /** 画布高度（vp） */
  @Prop canvasHeight: number = 150;

  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private context: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  /** 画布是否已就绪（onReady 之前不能绘制） */
  private ready: boolean = false;

  /** 轨迹数据变更后重绘；画布尚未就绪时由 onReady 补绘 */
  onDataChanged(): void {
    if (this.ready) {
      this.draw();
    }
  }

  /** 绘制轨迹：等比例投影 + 虚线主轨迹 + 跳段高亮 + 起终点标记 */
  private draw(): void {
    const ctx: CanvasRenderingContext2D = this.context;
    const width: number = ctx.width;
    const height: number = ctx.height;
    if (width <= 0 || height <= 0 || this.samples.length < 2) {
      return;
    }
    ctx.clearRect(0, 0, width, height);

    let minLon: number = this.samples[0].longitude;
    let maxLon: number = this.samples[0].longitude;
    let minLat: number = this.samples[0].latitude;
    let maxLat: number = this.samples[0].latitude;
    for (let i = 1; i < this.samples.length; i++) {
      const sample: TrackSample = this.samples[i];
      if (sample.longitude < minLon) {
        minLon = sample.longitude;
      }
      if (sample.longitude > maxLon) {
        maxLon = sample.longitude;
      }
      if (sample.latitude < minLat) {
        minLat = sample.latitude;
      }
      if (sample.latitude > maxLat) {
        maxLat = sample.latitude;
      }
    }

    const spanLon: number = Math.max(maxLon - minLon, 1e-6);
    const spanLat: number = Math.max(maxLat - minLat, 1e-6);
    const latScale: number = Math.cos((minLat + maxLat) / 2 * Math.PI / 180);
    const availableW: number = width - VIEW_PADDING * 2;
    const availableH: number = height - VIEW_PADDING * 2;
    const scale: number = Math.min(availableW / spanLon, availableH / (spanLat * latScale));
    const drawnW: number = spanLon * scale;
    const drawnH: number = spanLat * latScale * scale;
    const offsetX: number = (width - drawnW) / 2;
    const offsetY: number = (height - drawnH) / 2;

    // 主轨迹（虚线）
    ctx.beginPath();
    ctx.setLineDash(DASH_PATTERN);
    ctx.lineWidth = 2.5;
    ctx.lineCap = 'round';
    ctx.strokeStyle = LINE_COLOR;
    for (let i = 0; i < this.samples.length; i++) {
      const x: number = offsetX + (this.samples[i].longitude - minLon) * scale;
      const y: number = offsetY + (maxLat - this.samples[i].latitude) * scale * latScale;
      if (i === 0) {
        ctx.moveTo(x, y);
      } else {
        ctx.lineTo(x, y);
      }
    }
    ctx.stroke();
    ctx.setLineDash([]);

    // 跳段高亮（仅统计到跳段时）
    if (this.jumpCount > 0) {
      ctx.lineWidth = 3;
      ctx.lineCap = 'round';
      ctx.strokeStyle = JUMP_COLOR;
      for (let i = 1; i < this.samples.length; i++) {
        const prev: TrackSample = this.samples[i - 1];
        const cur: TrackSample = this.samples[i];
        if (haversine(prev.latitude, prev.longitude, cur.latitude, cur.longitude) <= JUMP_THRESHOLD_M) {
          continue;
        }
        ctx.beginPath();
        ctx.moveTo(offsetX + (prev.longitude - minLon) * scale,
          offsetY + (maxLat - prev.latitude) * scale * latScale);
        ctx.lineTo(offsetX + (cur.longitude - minLon) * scale,
          offsetY + (maxLat - cur.latitude) * scale * latScale);
        ctx.stroke();
      }
    }

    // 起点 / 终点标记
    const start: TrackSample = this.samples[0];
    const end: TrackSample = this.samples[this.samples.length - 1];
    this.drawMarker(offsetX + (start.longitude - minLon) * scale,
      offsetY + (maxLat - start.latitude) * scale * latScale, START_COLOR);
    this.drawMarker(offsetX + (end.longitude - minLon) * scale,
      offsetY + (maxLat - end.latitude) * scale * latScale, END_COLOR);
  }

  /** 画一个标记点：外圈光晕 + 实心圆 */
  private drawMarker(x: number, y: number, color: string): void {
    const ctx: CanvasRenderingContext2D = this.context;
    ctx.beginPath();
    ctx.setLineDash([]);
    ctx.lineWidth = 1;
    ctx.strokeStyle = HALO_COLOR;
    ctx.arc(x, y, 9, 0, FULL_CIRCLE);
    ctx.stroke();

    ctx.beginPath();
    ctx.fillStyle = color;
    ctx.arc(x, y, 6, 0, FULL_CIRCLE);
    ctx.fill();
  }

  build() {
    Column() {
      if (this.samples.length < 2) {
        Text('暂无可预览路线')
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_secondary'))
      } else {
        Canvas(this.context)
          .width('100%')
          .height('100%')
          .onReady(() => {
            this.ready = true;
            this.draw();
          })
      }
    }
    .width('100%')
    .height(this.canvasHeight)
    .borderRadius(14)
    .backgroundColor($r('app.color.card_surface'))
    .border({ width: 1, color: $r('app.color.outline_variant') })
    .clip(true)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }
}
