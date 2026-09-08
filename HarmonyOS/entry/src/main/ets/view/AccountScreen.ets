import { promptAction } from '@kit.ArkUI';
import { MainViewModel } from '../viewmodel/MainViewModel';
import { CookieService } from '../service/CookieService';
import { HdsListItemCard, SuffixArrow } from '@kit.UIDesignKit';
import { hdsPrefixIcon, hdsLabelItem, HdsCardOptions, HDS_FULL_TITLE_BAR_HEIGHT } from './CommonComponents';

/**
 * 账号页（第二个页签 "账号"）
 * 迁移自 Android: com.sjtu.runner.ui.MainScreen.kt 中的 AccountScreen @Composable
 * 登录/登出逻辑对应 MainActivity 的 onLoginRequested / onLogoutRequested / onOpenAbout
 */
@Component
export struct AccountScreen {
  viewModel: MainViewModel = MainViewModel.getInstance();
  /** 主导航栈（由 Index 传入），用于跳转登录页/关于页 */
  navStack: NavPathStack = new NavPathStack();

  aboutToAppear(): void {
    // 检查 cookie 状态（简单判断），等价 Android LaunchedEffect 中的 CookieManager 检查
    this.viewModel.refreshLoginState();
  }

  private handleLogout(): void {
    // 清理 cookie 并刷新界面（等价 MainActivity.onLogoutRequested）
    CookieService.clearAll();
    this.viewModel.loginState = false;
    this.viewModel.reloginRequired = false;
    promptAction.showToast({ message: '已退出登录', duration: 1500 });
  }

  // ===== HDS 列表卡片选项（本地结构兼容接口 HdsCardOptions，
  // 规避 kit 的 HdsListItemCardOptions 因引用未导出类型而无法通过字面量检查） =====

  /** 登录状态卡片选项 */
  private accountCardOptions(): HdsCardOptions {
    const options: HdsCardOptions = {
      prefixItem: hdsPrefixIcon($r('sys.symbol.person_crop_circle_fill_1')),
      textItem: {
        primaryText: { text: 'JAccount 账号' },
        secondaryText: {
          text: this.viewModel.loginState ? '已登录，点击可退出' : '未登录，点击登录以便上传数据'
        }
      },
      suffixItem: new SuffixArrow(),
      onClick: (): void => {
        if (this.viewModel.loginState) {
          AlertDialog.show({
            title: '退出账号',
            message: '是否退出该账号？',
            autoCancel: true,
            alignment: DialogAlignment.Center,
            primaryButton: {
              value: '取消',
              action: () => {
              }
            },
            secondaryButton: {
              value: '退出',
              fontColor: $r('app.color.error_color'),
              action: () => {
                this.handleLogout();
              }
            }
          });
        } else {
          this.navStack.pushPathByName('Login', null);
        }
      }
    };
    return options;
  }

  /** 关于入口卡片选项 */
  private aboutCardOptions(): HdsCardOptions {
    const options: HdsCardOptions = {
      prefixItem: hdsPrefixIcon($r('sys.symbol.info_circle')),
      textItem: hdsLabelItem('关于'),
      suffixItem: new SuffixArrow(),
      onClick: (): void => {
        this.navStack.pushPathByName('About', null);
      }
    };
    return options;
  }

  build() {
    Column({ space: 8 }) {
      // 登录状态卡片（HDS 原生列表卡片）
      HdsListItemCard(this.accountCardOptions())

      // 关于入口（HDS 原生列表卡片）
      HdsListItemCard(this.aboutCardOptions())

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
    .alignItems(HorizontalAlign.Start)
    .backgroundColor($r('app.color.page_background'))
  }
}
