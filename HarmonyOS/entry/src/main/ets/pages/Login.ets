import { promptAction } from '@kit.ArkUI';
import { webview } from '@kit.ArkWeb';
import { common } from '@kit.AbilityKit';
import { HdsNavDestination } from '@kit.UIDesignKit';
import { CookieService } from '../service/CookieService';
import { MainViewModel } from '../viewmodel/MainViewModel';

/** jAccount OAuth 登录地址（与 Android LoginActivity 保持一致） */
const LOGIN_URL: string = 'https://jaccount.sjtu.edu.cn/oauth2/authorize' +
  '?response_type=code' +
  '&scope=profile' +
  '&client_id=9mqzULSXYgUYj5fPOpyL' +
  '&state=8' +
  '&redirect_uri=https://pe.sjtu.edu.cn/oauth2Login';

/** 移动端 UA（与 Android LoginActivity 保持一致） */
const MOBILE_USER_AGENT: string = 'Mozilla/5.0 (iPhone; CPU iPhone OS 13_2_3 like Mac OS X) ' +
  'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/13.0.3 Mobile/15E148 Safari/604.1 Edg/89.0.4389.72';

/**
 * 登录页（二级页，挂载于 Index 的 HdsNavigation 导航栈）
 * 迁移自 Android: com.sjtu.runner.login.LoginActivity
 * - WebView -> Web 组件
 * - CookieManager -> webview.WebCookieManager
 * - shouldOverrideUrlLoading -> onLoadIntercept
 * - onPageFinished -> onPageEnd
 * - 自绘顶栏/返回键 -> HdsNavDestination 原生标题栏与系统返回控件
 *
 * 登录完成判定与 Android 版一致：
 * 1) 跳转到 OAuth 授权回调页 https://pe.sjtu.edu.cn/oauth2Login（最可靠）
 * 2) 拿到体育学院会话 Cookie JSESSIONID（API 请求必需）
 * 3) 成功跳转到体育学院主站页面（非登录、非授权页）
 */
@Component
export struct LoginPage {
  controller: webview.WebviewController = new webview.WebviewController();
  navStack: NavPathStack = new NavPathStack();
  @State progressValue: number = 0;

  aboutToAppear(): void {
    // 清除已有 cookie 全新开始（等价 Android onCreate 中的 removeAllCookies）
    CookieService.clearAll();
  }

  /** 判断登录是否完成，等价 LoginActivity.onPageFinished 中的判定 */
  private checkLoginComplete(url: string): boolean {
    const cookies = CookieService.getCookie('https://pe.sjtu.edu.cn');
    if (url.startsWith('https://pe.sjtu.edu.cn/oauth2Login')) {
      return true;
    }
    if (cookies.length > 0 && cookies.includes('JSESSIONID')) {
      return true;
    }
    if (url.startsWith('https://pe.sjtu.edu.cn') && !url.includes('oauth2/authorize') && !url.includes('jaccount')) {
      return true;
    }
    return false;
  }

  /** 跳转交我办（等价 openJwbLogin） */
  private openJwbLogin(url: string): void {
    const context = getContext(this) as common.UIAbilityContext;
    try {
      context.openLink(url);
      promptAction.showToast({ message: '已跳转交我办，请完成登录后返回', duration: 2000 });
    } catch (e) {
      promptAction.showToast({ message: '未找到交我办，留在网页登录', duration: 2500 });
    }
  }

  /** 登录完成：刷新登录态并返回上一页（等价 setResult(RESULT_OK) + finish()） */
  private finishLogin(): void {
    const viewModel = MainViewModel.getInstance();
    viewModel.logMsg('重新登录成功，重新加载界面...');
    viewModel.refreshLoginState();
    this.navStack.pop();
  }

  build() {
    HdsNavDestination() {
      Column() {
        // 加载进度条
        Progress({ value: this.progressValue, total: 100, type: ProgressType.Linear })
          .color($r('app.color.brand_primary'))
          .width('100%')
          .height(2)
          .visibility(this.progressValue < 100 ? Visibility.Visible : Visibility.None)

        Web({ src: LOGIN_URL, controller: this.controller })
          .javaScriptAccess(true)
          .domStorageAccess(true)
          .zoomAccess(false)
          .width('100%')
          .layoutWeight(1)
          .onControllerAttached(() => {
            try {
              this.controller.setCustomUserAgent(MOBILE_USER_AGENT);
            } catch (e) {
            }
          })
          .onLoadIntercept((event) => {
            const url: string = event.data.getRequestUrl();
            const scheme: string = url.split(':')[0];
            if (scheme === 'jaccount') {
              this.openJwbLogin(url);
              return true;
            }
            // 非网页协议一律拦截，避免 WebView 错误页（与 Android 版一致）
            return scheme !== 'http' && scheme !== 'https';
          })
          .onPageEnd((event) => {
            const url: string = event.url;
            if (this.checkLoginComplete(url)) {
              promptAction.showToast({ message: '登录成功', duration: 1500 });
              this.finishLogin();
            }
          })
          .onProgressChange((event) => {
            if (event) {
              this.progressValue = event.newProgress;
            }
          })
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.page_background'))
    }
    .titleBar({
      content: {
        title: {
          mainTitle: 'JAccount 登录'
        }
      }
    })
  }
}
