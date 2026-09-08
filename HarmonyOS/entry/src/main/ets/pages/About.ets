import { HdsNavDestination } from '@kit.UIDesignKit';
import { ImmersiveMaterialHelper } from '../common/ImmersiveMaterialHelper';

/**
 * 关于页（二级页，挂载于 Index 的 HdsNavigation 导航栈）
 * 迁移自 Android: com.sjtu.runner.about.AboutActivity
 * - 自绘顶栏/返回键 -> HdsNavDestination 原生标题栏与系统返回控件
 */
@Component
export struct AboutPage {
  /** 沉浸光感材质：Logo 卡片（小面积局部容器）；运行时不支持时为 undefined，组件自动降级为普通样式 */
  private logoCardMaterial = ImmersiveMaterialHelper.regular();

  build() {
    HdsNavDestination() {
      Column() {
        Column({ space: 16 }) {
          // Logo 卡片
          Column() {
            Image($r('app.media.app_icon'))
              .width(120)
              .height(120)
              .borderRadius(16)
              .objectFit(ImageFit.Cover)
          }
          .width(120)
          .height(120)
          .borderRadius(16)
          // 沉浸光感：Logo 卡片开启常规材质
          .systemMaterial(this.logoCardMaterial)

          Text('交我润')
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))

          Text('本应用用于学习和研究用途，演示运动数据生成与上传的流程。请遵守学校与平台的使用规范。')
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
            .textAlign(TextAlign.Center)
            .lineHeight(22)
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .padding({ left: 24, right: 24, bottom: 24 })
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.page_background'))
    }
    .titleBar({
      content: {
        title: {
          mainTitle: '关于'
        }
      }
    })
  }
}
