import { webview } from '@kit.ArkWeb';

/**
 * Cookie 服务
 * 迁移自 Android: android.webkit.CookieManager 的用法（LoginActivity / ApiService / MainActivity）。
 *
 * Android 版通过 WebViewCookieJar 在 OkHttp 与 WebView CookieManager 之间双向同步 Cookie；
 * HarmonyOS 版登录在 Web 组件中完成，Cookie 统一存放于 webview.WebCookieManager，
 * HTTP 请求（ApiService）通过 fetchCookieSync 读取，实现同等效果。
 */
export class CookieService {
  /** 读取指定 URL 的 Cookie（等价 CookieManager.getInstance().getCookie(url)） */
  static getCookie(url: string): string {
    try {
      return webview.WebCookieManager.fetchCookieSync(url);
    } catch (e) {
      return '';
    }
  }

  /** 判断是否已登录（等价 MainScreen/AccountScreen 中的 cookie 判断逻辑） */
  static isLoggedIn(): boolean {
    const peCookie = CookieService.getCookie('https://pe.sjtu.edu.cn');
    const jaCookie = CookieService.getCookie('https://jaccount.sjtu.edu.cn');
    return (peCookie.length > 0 && peCookie.includes('JSESSIONID')) ||
      (jaCookie.length > 0 && jaCookie.includes('JAAuthCookie'));
  }

  /** 清除全部 Cookie（等价 CookieManager.removeAllCookies(null) + flush()） */
  static async clearAll(): Promise<void> {
    try {
      await webview.WebCookieManager.deleteEntireCookie();
      webview.WebCookieManager.saveCookieSync();
    } catch (e) {
      // 忽略清理失败
    }
  }
}
