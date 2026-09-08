import { HdsListItemCard, SuffixArrow } from '@kit.UIDesignKit';
import { hdsPrefixIcon, hdsLabelItem, HdsCardOptions, HDS_FULL_TITLE_BAR_HEIGHT } from './CommonComponents';

/**
 * 路线页（第三个页签 "路线"）
 * 功能与原 RunScreen"跑步路线"下拉中的"＋ 设定新路线"项一致：
 * 跳转路线设计页（RouteDesign，WebView 地图上绘制路线并保存为自定义路线），
 * 保存成功后由 RouteDesign 通知 ViewModel 刷新路线列表并返回。
 * 原 RunScreen 下拉中的"＋ 设定新路线"项已随本页新增而移除。
 */
@Component
export struct RouteScreen {
  /** 主导航栈（由 Index 传入），用于跳转路线设计页 */
  navStack: NavPathStack = new NavPathStack();

  /** 路线管理入口卡片选项：与“设定新路线”并列，进入路线管理页 */
  private manageCardOptions(): HdsCardOptions {
    const options: HdsCardOptions = {
      prefixItem: hdsPrefixIcon($r('sys.symbol.gearshape')),
      textItem: {
        primaryText: { text: '路线管理' },
        secondaryText: { text: '默认路线、排序与删除' }
      },
      suffixItem: new SuffixArrow(),
      onClick: (): void => {
        this.navStack.pushPathByName('RouteManage', null);
      }
    };
    return options;
  }

  /** 设定新路线入口卡片选项（等价原 RunScreen 下拉“＋ 设定新路线”项） */
  private newRouteCardOptions(): HdsCardOptions {
    const options: HdsCardOptions = {
      prefixItem: hdsPrefixIcon($r('sys.symbol.map')),
      textItem: {
        primaryText: { text: '设定新路线' },
        secondaryText: { text: '在地图上绘制并保存自定义跑步路线' }
      },
      suffixItem: new SuffixArrow(),
      onClick: (): void => {
        this.navStack.pushPathByName('RouteDesign', null);
      }
    };
    return options;
  }

  build() {
    Column({ space: 8 }) {
      // 官方《设置列表卡片样式》：HdsListItemCard 置于 List>ListItem 中，
      // List（width '100%'）经 ListItem 提供满宽，与其他页面选项横条等宽。
      List({ space: 8 }) {
        ListItem() {
          HdsListItemCard(this.newRouteCardOptions())
            .width('100%')
        }

        ListItem() {
          HdsListItemCard(this.manageCardOptions())
            .width('100%')
        }
      }
      .width('100%')

      Blank()
    }
    .width('100%')
    .height('100%')
    // top 叠加 HdsNavigation FULL 大标题栏高度（112vp）：titleBar 为悬浮层覆盖在
    // 内容上方，官方示例要求内容首部预留等高空间避让，否则大标题遮挡卡片；
    // 注意 ArkUI 同属性链式调用后者覆盖前者，padding 只能写这一次（四边合一遍）
    .padding({
      left: 16,
      right: 16,
      top: HDS_FULL_TITLE_BAR_HEIGHT + 16,
      bottom: 16
    })
    .backgroundColor($r('app.color.page_background'))
  }
}
