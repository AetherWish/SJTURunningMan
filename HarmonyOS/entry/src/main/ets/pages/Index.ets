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

const DOMAIN: number = 0x0000;
const TAG: string = 'IndexPage';
const PREFS_NAME: string = 'app_prefs';
const PREF_DISCLAIMER_ACCEPTED: string = 'disclaimer_accepted';

/**
 * 根界面
 * 迁移自 Android: com.sjtu.runner.MainActivity + MainScreen.kt 中的 RootScreen
 *
 * - Activity -> @Entry 页面（Stage 模型）
 * - 底部 NavigationBar -> HdsTabs 悬浮页签（沉浸光感，HarmonyOS Symbol 系统图标）
 * - CenterAlignedTopAppBar -> HdsNavigation titleBar（沉浸光感）
 * - 二级页面（登录/路线设计/关于）-> HdsNavDestination + NavPathStack，
 *   由系统提供标题栏与返回控件（等价 Android startActivity/startActivityForResult）
 * - 免责声明 AlertDialog 保留原交互
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
  @State contentReady: boolean = false;
  @State materialLevel: hdsMaterial.MaterialLevel = hdsMaterial.MaterialLevel.ADAPTIVE;
  @State materialType: hdsMaterial.MaterialType = hdsMaterial.MaterialType.ADAPTIVE;

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
      this.viewModel.logMsg('检测到cookie过期，正在重新登录...');
      this.pathStack.pushPathByName('Login', null);
    };

    // 初始化 ViewModel 与路线列表
    const context = getContext(this) as common.UIAbilityContext;
    this.viewModel.init(context);

    // 检查免责声明是否已被接受（等价 MainActivity.onCreate 中的 SharedPreferences 检查）
    try {
      const prefs = preferences.getPreferencesSync(context, { name: PREFS_NAME });
      const accepted = prefs.getSync(PREF_DISCLAIMER_ACCEPTED, false) as boolean;
      if (accepted) {
        this.contentReady = true;
      } else {
        this.showDisclaimerDialog(prefs);
      }
    } catch (e) {
      this.contentReady = true;
    }
  }

  private showDisclaimerDialog(prefs: preferences.Preferences): void {
    AlertDialog.show({
      title: '免责声明',
      message: '本项目仅用于学习、研究和技术测试，主要用于理解运动数据记录与上传相关的技术流程。' +
        '项目作者不鼓励、不支持任何违反学校规定的使用方式。请在使用前确认自己的行为符合 SJTU 及相关平台的要求，' +
        '请不要用于伪造运动数据或规避体育锻炼要求。',
      autoCancel: false,
      alignment: DialogAlignment.Center,
      primaryButton: {
        value: '退出本应用',
        fontColor: $r('app.color.error_color'),
        action: () => {
          // 等价 Android finish()
          (getContext(this) as common.UIAbilityContext).terminateSelf();
        }
      },
      secondaryButton: {
        value: '我已了解，进入应用',
        fontColor: $r('app.color.brand_primary'),
        action: () => {
          prefs.putSync(PREF_DISCLAIMER_ACCEPTED, true);
          prefs.flushSync();
          this.contentReady = true;
        }
      }
    });
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
    Stack() {
      if (this.contentReady) {
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
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
  }
}
