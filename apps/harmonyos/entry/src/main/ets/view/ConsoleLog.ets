/**
 * 运行日志面板
 * 迁移自 Android: com.sjtu.runner.ui.components.ConsoleLog
 *
 * ArkUI 差异说明：
 * 1. Android 用 LazyColumn + LaunchedEffect 自动滚动到底部，这里用 List + Scroller，
 *    在日志数组变更的属性回调里调用 scrollEdge(Edge.Bottom)，列表尚未完成布局时忽略异常；
 * 2. 等级着色复用已有颜色资源：INFO -> text_primary、SUCCESS -> success_color、
 *    WARN -> warning_color、ERROR -> error_color；
 * 3. 等宽字体用 fontFamily('monospace')，字号 12、行高 18，与 Android 控制台一致。
 */
import { LogEntry, LogLevel } from '../viewmodel/TaskModels';

@Component
export struct ConsoleLog {
  /** 日志条目（父组件每次追加后重新传入） */
  @Prop @Watch('onEntriesChanged') entries: LogEntry[] = [];
  /** 面板高度（vp） */
  @Prop panelHeight: number = 210;
  /** 空列表占位文案 */
  @Prop placeholder: string = '就绪。点击「开始任务」启动。';

  private scroller: Scroller = new Scroller();

  /** 日志变更后滚动到底部（新消息追加时保持可见） */
  onEntriesChanged(): void {
    try {
      this.scroller.scrollEdge(Edge.Bottom);
    } catch (err) {
      // 列表尚未完成布局时忽略：下一次日志追加会再次触发
    }
  }

  /** 日志等级对应的文字颜色 */
  private levelColor(level: LogLevel): Resource {
    switch (level) {
      case LogLevel.SUCCESS:
        return $r('app.color.success_color');
      case LogLevel.WARN:
        return $r('app.color.warning_color');
      case LogLevel.ERROR:
        return $r('app.color.error_color');
      case LogLevel.INFO:
      default:
        return $r('app.color.text_primary');
    }
  }

  build() {
    Column() {
      if (this.entries.length === 0) {
        Text(this.placeholder)
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .opacity(0.55)
          .padding(14)
      } else {
        List({ space: 4, scroller: this.scroller }) {
          ForEach(this.entries, (entry: LogEntry) => {
            ListItem() {
              Row({ space: 8 }) {
                Text(entry.time)
                  .fontSize(12)
                  .lineHeight(18)
                  .fontFamily('monospace')
                  .fontColor($r('app.color.text_secondary'))
                  .opacity(0.45)
                Text(entry.message)
                  .fontSize(12)
                  .lineHeight(18)
                  .fontFamily('monospace')
                  .fontColor(this.levelColor(entry.level))
                  .layoutWeight(1)
              }
              .width('100%')
              .alignItems(VerticalAlign.Top)
            }
          }, (entry: LogEntry, index: number) => `${index}-${entry.time}-${entry.message}`)
        }
        .width('100%')
        .layoutWeight(1)
        .padding(14)
        .scrollBar(BarState.Auto)
      }
    }
    .width('100%')
    .height(this.panelHeight)
    .borderRadius(14)
    .backgroundColor($r('app.color.log_panel_background'))
    .border({ width: 1, color: $r('app.color.outline_variant') })
    .clip(true)
    .alignItems(HorizontalAlign.Start)
  }
}
