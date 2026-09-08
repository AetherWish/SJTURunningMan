import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';

const DOMAIN: number = 0x0000;
const TAG: string = 'EntryAbility';

/**
 * 应用入口 UIAbility
 * 迁移自 Android: com.sjtu.runner.MainActivity（Activity -> UIAbility）
 *
 * 窗口布局：保持系统默认避让（非全屏布局），由系统为状态栏/导航栏预留空间，
 * 页面内容不会顶入系统栏区域，返回键等贴顶控件可正常点击。
 */
export default class EntryAbility extends UIAbility {
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
      // 系统默认避让：窗口不延伸至系统栏下方（默认即为 false，此处显式设置
      // 以覆盖旧方案残留的全屏布局，确保状态栏空间被系统自动预留）
      mainWindow.setWindowLayoutFullScreen(false);
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'Window layout setup failed: %{public}s', JSON.stringify(e));
    }
  }

  onForeground(): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onForeground');
  }

  onBackground(): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onBackground');
  }
}
