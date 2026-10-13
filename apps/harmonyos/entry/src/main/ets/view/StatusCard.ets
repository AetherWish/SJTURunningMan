/**
 * 任务状态卡
 * 迁移自 Android: com.sjtu.runner.ui.components.StatusCard
 *
 * ArkUI 差异说明：
 * 1. Android 用 rotate 动画画进度圈，这里用系统 LoadingProgress（原生等价物）；
 * 2. 进度比例在本组件内按 current/total 计算，不依赖 TaskProgress 上的访问器
 *    （属性深拷贝不会带上原型上的 getter）；
 * 3. Android 的低层容器色 cardLow 用已有颜色资源替代（本工程不新增颜色 token）：
 *    进度条轨道用 outline_variant，统计格用 card_surface + outline_variant 描边，
 *    运行中图标底衬用 brand_primary_container。
 */
import { TaskProgress, TaskStatus, taskStatusLabel } from '../viewmodel/TaskModels';

/** 状态卡底部统计项（等价 Android StatItem） */
export class StatItem {
  label: string;
  value: string;

  constructor(label: string, value: string) {
    this.label = label;
    this.value = value;
  }
}

@Component
export struct StatusCard {
  /** 任务进度（当前/总数/阶段） */
  @Prop progress: TaskProgress = new TaskProgress(0, 0, TaskStatus.IDLE);
  /** 主标题，如「1 次 · 3.0 km」 */
  @Prop headline: string = '';
  /** 底部统计项 */
  @Prop stats: StatItem[] = [];

  /** 完成比例（0-1），total<=0 时为 0 */
  private fraction(): number {
    if (this.progress.total <= 0) {
      return 0;
    }
    const value: number = this.progress.current / this.progress.total;
    if (value < 0) {
      return 0;
    }
    if (value > 1) {
      return 1;
    }
    return value;
  }

  /** 是否处于运行中的阶段（等价 Android 旋转圈显示条件） */
  private isBusy(): boolean {
    return this.progress.status !== TaskStatus.IDLE && this.progress.status !== TaskStatus.FINISHED;
  }

  build() {
    Column() {
      Row({ space: 12 }) {
        if (this.isBusy()) {
          Row() {
            LoadingProgress()
              .width(20)
              .height(20)
              .color($r('app.color.brand_primary'))
          }
          .width(28)
          .height(28)
          .borderRadius(14)
          .backgroundColor($r('app.color.brand_primary_container'))
          .justifyContent(FlexAlign.Center)
          .alignItems(VerticalAlign.Center)
        }

        Column({ space: 2 }) {
          Text(this.headline)
            .fontSize(19)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
          Text(taskStatusLabel(this.progress.status))
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        if (this.progress.total > 0) {
          Text(`${this.progress.current}/${this.progress.total}`)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.brand_primary'))
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      if (this.progress.total > 0) {
        Progress({ value: this.fraction() * 100, total: 100, type: ProgressType.Linear })
          .width('100%')
          .height(8)
          .color($r('app.color.brand_primary'))
          .backgroundColor($r('app.color.outline_variant'))
          .margin({ top: 12 })
      }

      Row({ space: 10 }) {
        ForEach(this.stats, (item: StatItem) => {
          Row() {
            Column({ space: 2 }) {
              Text(item.label)
                .fontSize(11)
                .fontColor($r('app.color.text_secondary'))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .width('100%')
              Text(item.value)
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_primary'))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .width('100%')
            }
            .width('100%')
            .padding({ left: 12, right: 12, top: 10, bottom: 10 })
            .borderRadius(14)
            .backgroundColor($r('app.color.card_surface'))
            .border({ width: 1, color: $r('app.color.outline_variant') })
            .alignItems(HorizontalAlign.Start)
          }
          .layoutWeight(1)
        }, (item: StatItem) => item.label)
      }
      .width('100%')
      .margin({ top: 14 })
    }
    .width('100%')
    .padding(18)
    .borderRadius(20)
    .backgroundColor($r('app.color.card_surface'))
    .border({ width: 1, color: $r('app.color.outline_variant') })
    .alignItems(HorizontalAlign.Start)
  }
}
