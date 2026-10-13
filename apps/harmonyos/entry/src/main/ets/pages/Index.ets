import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { SymbolGlyphModifier } from '@kit.ArkUI';
import {
  hdsMaterial, HdsNavigation, HdsNavigationTitleMode, HdsTabs, HdsTabsController
} from '@kit.UIDesignKit';
import { preferences } from '@kit.ArkData';
import { RunScreen } from '../view/RunScreen';
import { AccountScreen } from '../view/AccountScreen';
import { LoginPage } from '../pages/Login';
import { RouteDesignPage } from '../pages/RouteDesign';
import { AboutPage } from '../pages/About';
import { MainViewModel } from '../viewmodel/MainViewModel';
import { LogLevel } from '../viewmodel/TaskModels';
import { AppConfig } from '../config/AppConfig';

const DOMAIN: number = 0x0000;
const TAG: string = 'IndexPage';
const PREFS_NAME: string = 'app_prefs';
const PREF_COMMITMENT_ACCEPTED: string = 'commitment_accepted';

/**
 * 根界面
 * 迁移自 Android: com.sjtu.runner.MainActivity + MainScreen.kt 中的 RootScreen
 *
 * - Activity -> @Entry 页面（Stage 模型）
 * - 底部 NavigationBar -> HdsTabs 悬浮页签（沉浸光感，HarmonyOS Symbol 系统图标）
 * - CenterAlignedTopAppBar -> HdsNavigation titleBar（沉浸光感）
 * - 二级页面（登录/路线设计/关于）-> HdsNavDestination + NavPathStack，
 *   由系统提供标题栏与返回控件（等价 Android startActivity/startActivityForResult）
 * - 使用承诺书门禁：与安卓一致，未同意时以全屏卡片遮挡并允许“退出”结束应用
 *
 * 沉浸光感适配：
 * 1. aboutToAppear 中调用 hdsMaterial.getSystemMaterialTypes() 查询设备材质能力，
 *    不支持 IMMERSIVE 时降级为 SMOOTH 档位，避免低端设备卡顿发热；
 * 2. HdsNavigation 标题栏与 HdsTabs 悬浮页签均使用 ADAPTIVE 自适应档位；
 * 3. 应用级开关已在 module.json5 配置 ohos.arkui.UIMaterial.state = enable。
 */
@Entry
@Component
struct Index {
  private hdsTabsController: HdsTabsController = new HdsTabsController();
  private viewModel: MainViewModel = MainViewModel.getInstance();
  /** 主导航栈：登录 / 路线设计 / 关于 二级页均挂载于此 */
  private pathStack: NavPathStack = new NavPathStack();

  @State selectedTab: number = 0;
  @State materialLevel: hdsMaterial.MaterialLevel = hdsMaterial.MaterialLevel.ADAPTIVE;
  @State materialType: hdsMaterial.MaterialType = hdsMaterial.MaterialType.ADAPTIVE;
  /** 使用承诺书是否已同意（持久化于 app_prefs/commitment_accepted；读取失败时保持未同意） */
  @State commitmentAccepted: boolean = false;
  /** 承诺书勾选状态（等价 Android MainScreen 的 commitmentChecked） */
  @State commitmentChecked: boolean = false;

  aboutToAppear(): void {
    // 查询设备支持的 HDS 材质类型，设备不支持 IMMERSIVE 时降级 SMOOTH（官方 FAQ 推荐做法）
    try {
      const types: hdsMaterial.MaterialType[] = hdsMaterial.getSystemMaterialTypes();
      let immersiveSupported = false;
      for (let i = 0; i < types.length; i++) {
        if (types[i] === hdsMaterial.MaterialType.IMMERSIVE) {
          immersiveSupported = true;
          break;
        }
      }
      this.materialType = hdsMaterial.MaterialType.ADAPTIVE;
      this.materialLevel = immersiveSupported
        ? hdsMaterial.MaterialLevel.ADAPTIVE
        : hdsMaterial.MaterialLevel.SMOOTH;
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'getSystemMaterialTypes failed: %{public}s', JSON.stringify(e));
      this.materialLevel = hdsMaterial.MaterialLevel.SMOOTH;
    }

    // 触发重新登录回调：清理 cookie 并跳转登录页（等价 MainActivity.onReloginRequired）
    this.viewModel.onReloginRequired = () => {
      this.viewModel.logMsg(LogLevel.WARN, '检测到cookie过期，正在重新登录...');
      this.pathStack.pushPathByName('Login', null);
    };

    // 初始化 ViewModel 与路线列表
    const context = getContext(this) as common.UIAbilityContext;
    this.viewModel.init(context);
    // 启动时同步一次登录态（cookie 由系统 WebView cookie jar 持久化，
    // 等价 Android 启动时读 CookieManager 判断是否已登录）
    this.viewModel.refreshLoginState();

    // 检查使用承诺书是否已同意（等价 MainActivity.onCreate 中的 SharedPreferences 检查）
    // 读取失败时保持“未同意”，与 Android prefs.getBoolean(KEY, false) 的 fail-closed 语义一致
    try {
      const prefs = preferences.getPreferencesSync(context, { name: PREFS_NAME });
      this.commitmentAccepted = prefs.getSync(PREF_COMMITMENT_ACCEPTED, false) as boolean;
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'read commitment flag failed: %{public}s', JSON.stringify(e));
      this.commitmentAccepted = false;
    }
  }

  /** 持久化承诺书同意标记 */
  private acceptCommitment(): void {
    try {
      const context = getContext(this) as common.UIAbilityContext;
      const prefs = preferences.getPreferencesSync(context, { name: PREFS_NAME });
      prefs.putSync(PREF_COMMITMENT_ACCEPTED, true);
      prefs.flushSync();
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'persist commitment flag failed: %{public}s', JSON.stringify(e));
    }
    this.commitmentChecked = false;
    this.commitmentAccepted = true;
  }

  /** 拒绝承诺书：退出应用（等价 Android Activity.finish()） */
  private declineCommitment(): void {
    (getContext(this) as common.UIAbilityContext).terminateSelf();
  }

  /**
   * 使用承诺书门禁（等价 Android CommitmentDialog）。
   * 覆盖在整个 HdsNavigation 之上（含标题栏与悬浮页签），未同意时无法操作其它界面；
   * Android 用 AlertDialog + 复选框，ArkUI 的 AlertDialog 不支持自定义内容组件，故用全屏遮罩实现。
   */
  @Builder
  CommitmentDialog() {
    Column() {
      Column({ space: 14 }) {
        Text('使用承诺书')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .width('100%')

        Scroll() {
          Text(AppConfig.COMMITMENT_TEXT)
            .fontSize(14)
            .lineHeight(22)
            .fontColor($r('app.color.text_primary'))
            .width('100%')
        }
        .scrollable(ScrollDirection.Vertical)
        .scrollBar(BarState.Auto)
        .width('100%')
        .constraintSize({ maxHeight: 300 })
        .align(Alignment.TopStart)

        Row({ space: 8 }) {
          Checkbox()
            .select(this.commitmentChecked)
            .selectedColor($r('app.color.brand_primary'))
            .onChange((value: boolean) => {
              this.commitmentChecked = value;
            })
          Text('我已阅读以上内容，并承诺不会将本软件用于任何违规操作。')
            .fontSize(14)
            .fontColor($r('app.color.text_primary'))
            .layoutWeight(1)
        }
        .width('100%')
        .alignItems(VerticalAlign.Top)

        Row({ space: 10 }) {
          Button('退出')
            .fontSize(15)
            .height(44)
            .layoutWeight(1)
            .borderRadius(22)
            .backgroundColor(Color.Transparent)
            .fontColor($r('app.color.error_color'))
            .onClick(() => {
              this.declineCommitment();
            })
          Button('我承诺，进入软件')
            .fontSize(15)
            .height(44)
            .layoutWeight(1)
            .borderRadius(22)
            .backgroundColor($r('app.color.brand_primary'))
            .fontColor($r('app.color.text_on_brand'))
            .enabled(this.commitmentChecked)
            .opacity(this.commitmentChecked ? 1 : 0.5)
            .onClick(() => {
              this.acceptCommitment();
            })
        }
        .width('100%')
      }
      .width('90%')
      .padding(20)
      .borderRadius(24)
      .backgroundColor($r('app.color.card_surface'))
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#99000000')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  /** 二级页路由表：登录 / 路线设计 / 关于（系统标题栏 + 原生返回键） */
  @Builder
  PageMap(name: string) {
    if (name === 'Login') {
      LoginPage({ navStack: this.pathStack })
    } else if (name === 'RouteDesign') {
      RouteDesignPage({ navStack: this.pathStack })
    } else if (name === 'About') {
      AboutPage()
    }
  }

  build() {
    // 单根容器 Stack：HdsNavigation 与全屏承诺书遮罩是兄弟节点（等价 Android 中
    // CommitmentDialog 渲染在 Scaffold 之外，覆盖含顶栏的整屏）
    Stack() {
      HdsNavigation(this.pathStack) {
        HdsTabs({ controller: this.hdsTabsController }) {
          TabContent() {
            RunScreen({ navStack: this.pathStack })
          }
          .tabBar(new BottomTabBarStyle(
            { normal: new SymbolGlyphModifier($r('sys.symbol.figure_running')) }, '开润'))

          TabContent() {
            AccountScreen({ navStack: this.pathStack })
          }
          .tabBar(new BottomTabBarStyle(
            { normal: new SymbolGlyphModifier($r('sys.symbol.person_crop_circle_fill_1')) }, '账号'))
        }
        .barOverlap(true)
        .vertical(false)
        .barPosition(BarPosition.End)
        .onChange((index: number) => {
          this.selectedTab = index;
          // 切到“账号”页时刷新登录状态（等价 Android Compose 切换 tab 重组时的 cookie 检查）
          if (index === 1) {
            this.viewModel.refreshLoginState();
          }
        })
        .barFloatingStyle({
          barBottomMargin: 24,
          systemMaterialEffect: {
            materialType: this.materialType,
            materialLevel: this.materialLevel
          }
        })
      }
      .mode(NavigationMode.Stack)
      .navDestination(this.PageMap)
      .titleBar({
        content: {
          title: {
            // 一级页大标题随页签切换（开润/账号）
            mainTitle: this.selectedTab === 0 ? '开润' : '账号'
          }
        },
        style: {
          systemMaterialEffect: {
            materialType: this.materialType,
            materialLevel: this.materialLevel
          }
        }
      })
      // 一级页（NavBar）使用贴左大标题（HarmonyOS 系统应用一级页样式）；
      // 二级页 HdsNavDestination 的返回键不受影响
      .titleMode(HdsNavigationTitleMode.FULL)
      .hideBackButton(true)
      // 安全区：保持系统默认避让（此前 ignoreLayoutSafeArea 使内容顶入状态栏，
      // 导致二级页返回键贴顶无法点击），HdsTabs 悬浮页签自行处理底部导航条
      .width('100%')
      .height('100%')

      // ===== 使用承诺书门禁：作为 Stack 子节点覆盖整个 HdsNavigation（含标题栏与悬浮页签） =====
      if (!this.commitmentAccepted) {
        this.CommitmentDialog()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
  }
}
