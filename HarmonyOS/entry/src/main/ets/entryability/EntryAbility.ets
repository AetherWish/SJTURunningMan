import { AbilityConstant, Configuration, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';

const DOMAIN: number = 0x0000;
const TAG: string = 'EntryAbility';

/**
 * 沉浸式系统栏配色常量（与 resources/base|dark/element/color.json 中的同名色保持一致）。
 *
 * setWindowSystemBarProperties 仅接受十六进制字符串、不接受 Resource 资源引用，
 * 故在此镜像硬编码；若资源色值调整，需同步更新此处。
 *
 * 依据华为官方《窗口沉浸式》指南（immersive-window-feature）：
 * 采用"沉浸式布局 + 布局避让"方案——onWindowStageCreate 中调用
 * setWindowLayoutFullScreen(true) 进入沉浸式布局（窗口内容延伸到状态栏/导航条区域），
 * 再通过 getWindowAvoidArea / on('avoidAreaChange') 获取避让区域存入 AppStorage，
 * 由页面按 px2vp 换算后以 padding 避让，避免组件与系统 UI 重叠。
 * 同时将状态栏/导航栏背景色设为页面背景色，保证系统栏与页面内容间无可见色差。
 */
const BAR_BG_LIGHT: string = '#FFFBFE'; // == app.color.page_background (base) 浅色页面背景
const BAR_BG_DARK: string = '#141218';  // == app.color.page_background (dark) 深色页面背景
const BAR_FG_LIGHT: string = '#1C1B1F'; // == app.color.text_primary (base) 浅底 → 深色图标/文字
const BAR_FG_DARK: string = '#E6E0E9';  // == app.color.text_primary (dark) 深底 → 浅色图标/文字

/**
 * 应用入口 UIAbility
 * 迁移自 Android: com.sjtu.runner.MainActivity（Activity -> UIAbility）
 *
 * 窗口沉浸式（官方《窗口沉浸式》指南）：
 * 1. 沉浸式布局：setWindowLayoutFullScreen(true)，窗口延伸至状态栏/导航条区域；
 * 2. 布局避让：getWindowAvoidArea + on('avoidAreaChange') 把避让区域写入 AppStorage，
 *    页面（Index）按 px2vp 换算后 padding 避让，保证贴顶控件（如二级页返回键）可点击；
 * 3. 系统栏配色：背景色 = 页面背景色（跟随深浅色模式），消除系统栏与页面色差。
 */
export default class EntryAbility extends UIAbility {
  /** 主窗口引用：onWindowStageCreate 中获取并缓存，供 onConfigurationUpdate 复用 */
  private mainWindow: window.Window | null = null;

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onCreate');
  }

  onDestroy(): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onWindowStageCreate');

    // 官方示例：在 loadContent 成功回调内完成沉浸式布局与避让区域初始化
    windowStage.loadContent('pages/Index', async (err) => {
      if (err.code) {
        hilog.error(DOMAIN, TAG, 'Failed to load content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, TAG, '%{public}s', 'Succeeded in loading content.');
      try {
        const mainWindow = windowStage.getMainWindowSync(); // 获取应用主窗口
        this.mainWindow = mainWindow;
        // 进入窗口沉浸式布局（非自由窗口状态），窗口内容延伸至状态栏/导航条区域
        await mainWindow.setWindowLayoutFullScreen(true);
        // 初始化并监听避让区域（状态栏/导航条/挖孔区），写入 AppStorage 供页面避让
        this.initSafeArea(mainWindow);
        this.watchAvoidAreaChange(mainWindow);
        // 系统栏背景色 = 页面背景色：沉浸式布局下页面背景铺满整个窗口，
        // 系统栏与页面内容间无可见色差；内容色保证状态栏图标可读。
        this.applyImmersiveSystemBar(this.context.config.colorMode);
      } catch (e) {
        hilog.warn(DOMAIN, TAG, 'Immersive window setup failed: %{public}s', JSON.stringify(e));
      }
    });
  }

  /**
   * 官方《窗口沉浸式》：初始化避让区域缓存。
   * AvoidArea 的 Rect 以窗口左上角为原点、单位为像素（px），
   * 页面使用时需通过 getUIContext().px2vp() 换算为 vp。
   */
  private initSafeArea(win: window.Window): void {
    try {
      // 状态栏避让区域（顶部）
      const systemAvoidArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      // 底部导航条（手势指示条）避让区域
      const navigationAvoidArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
      // 挖孔区避让区域（左右）
      const cutoutAvoidArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_CUTOUT);
      AppStorage.setOrCreate('topAvoidHeight', systemAvoidArea.topRect.height);
      AppStorage.setOrCreate('bottomAvoidHeight', navigationAvoidArea.bottomRect.height);
      AppStorage.setOrCreate('leftAvoidWidth', cutoutAvoidArea.leftRect.width);
      AppStorage.setOrCreate('rightAvoidWidth', cutoutAvoidArea.rightRect.width);
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'initSafeArea failed: %{public}s', JSON.stringify(e));
    }
  }

  /**
   * 官方《窗口沉浸式》：监听避让区域变化（全屏/分屏切换、窗口旋转、
   * 折叠态切换、多设备流转等场景触发），动态刷新 AppStorage 缓存值。
   */
  private watchAvoidAreaChange(win: window.Window): void {
    try {
      win.on('avoidAreaChange', (option: window.AvoidAreaOptions) => {
        if (option.type === window.AvoidAreaType.TYPE_SYSTEM) {
          AppStorage.setOrCreate('topAvoidHeight', option.area.topRect.height);
        } else if (option.type === window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR) {
          AppStorage.setOrCreate('bottomAvoidHeight', option.area.bottomRect.height);
        } else if (option.type === window.AvoidAreaType.TYPE_CUTOUT) {
          AppStorage.setOrCreate('leftAvoidWidth', option.area.leftRect.width);
          AppStorage.setOrCreate('rightAvoidWidth', option.area.rightRect.width);
        }
      });
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'watchAvoidAreaChange failed: %{public}s', JSON.stringify(e));
    }
  }

  /**
   * 系统（深/浅色）模式切换时重新应用系统栏配色，保证色差始终为零。
   * UIAbility.onConfigurationUpdate 在配置变化（含 colorMode 切换）时由系统回调。
   */
  onConfigurationUpdate(newConfig: Configuration): void {
    this.applyImmersiveSystemBar(newConfig.colorMode);
  }

  /**
   * 按当前颜色模式将状态栏/导航栏背景色设为页面背景色（消除色差），
   * 内容色设为对比可读的图标/文字色（保证状态栏图标可见）。
   * SystemBarProperties 仅接受十六进制色值字符串，不接受 Resource。
   *
   * 注：Configuration.colorMode 为可选字段（类型 ColorMode | undefined），
   * 故此参数同样接受 undefined——非 DARK（含 NOT_SET/未设置）一律按浅色处理。
   */
  private async applyImmersiveSystemBar(colorMode: ConfigurationConstant.ColorMode | undefined): Promise<void> {
    const win = this.mainWindow;
    if (win === null) {
      // 主窗口尚未创建（理论上不会到此分支，防御性返回）
      return;
    }
    const isDark: boolean = colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
    const bg: string = isDark ? BAR_BG_DARK : BAR_BG_LIGHT;
    const fg: string = isDark ? BAR_FG_DARK : BAR_FG_LIGHT;
    try {
      await win.setWindowSystemBarProperties({
        statusBarColor: bg,
        navigationBarColor: bg,
        statusBarContentColor: fg,
        navigationBarContentColor: fg
      });
      hilog.info(DOMAIN, TAG, 'Immersive system bar applied (colorMode=%{public}d).', colorMode);
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'setWindowSystemBarProperties failed: %{public}s', JSON.stringify(e));
    }
  }

  onForeground(): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onForeground');
  }

  onBackground(): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onBackground');
  }
}
