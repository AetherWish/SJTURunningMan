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
 * 采用华为官方“颜色背景通铺”沉浸式方案（见华为开发者论坛《三种方式实现沉浸式界面开发》）：
 * 不开启 setWindowLayoutFullScreen（窗口不延伸至系统栏下方），而是将状态栏、
 * 导航栏的背景色设为与页面背景相同的颜色，三窗口平铺不重叠。这样既消除了系统栏
 * 与页面内容之间的可见色差，又不改变系统默认安全区避让——此前曾因 ignoreLayoutSafeArea
 * 使内容顶入状态栏、导致二级页返回键贴顶无法点击，本方案从根上规避该问题。
 */
const BAR_BG_LIGHT: string = '#FFFBFE'; // == app.color.page_background (base) 浅色页面背景
const BAR_BG_DARK: string = '#141218';  // == app.color.page_background (dark) 深色页面背景
const BAR_FG_LIGHT: string = '#1C1B1F'; // == app.color.text_primary (base) 浅底 → 深色图标/文字
const BAR_FG_DARK: string = '#E6E0E9';  // == app.color.text_primary (dark) 深底 → 浅色图标/文字

/**
 * 应用入口 UIAbility
 * 迁移自 Android: com.sjtu.runner.MainActivity（Activity -> UIAbility）
 *
 * 窗口布局：保持系统默认避让（非全屏布局），由系统为状态栏/导航栏预留空间，
 * 页面内容不会顶入系统栏区域，返回键等贴顶控件可正常点击。
 * 沉浸式配色：状态栏/导航栏背景色 = 页面背景色（跟随深浅色模式），消除系统栏与页面色差。
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

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, TAG, 'Failed to load content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, TAG, '%{public}s', 'Succeeded in loading content.');
    });

    try {
      const mainWindow = windowStage.getMainWindowSync();
      this.mainWindow = mainWindow;
      // 系统默认避让：窗口不延伸至系统栏下方（默认即为 false，此处显式设置
      // 以覆盖旧方案残留的全屏布局，确保状态栏空间被系统自动预留）
      mainWindow.setWindowLayoutFullScreen(false);
      // 沉浸式配色：状态栏/导航栏背景色 = 页面背景色，消除系统栏与页面内容间的可见色差。
      // 传入当前颜色模式以选择正确的背景色与图标色。
      this.applyImmersiveSystemBar(this.context.config.colorMode);
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'Window layout setup failed: %{public}s', JSON.stringify(e));
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
