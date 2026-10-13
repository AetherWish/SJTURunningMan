import { http } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { PayloadItem } from '../model/PayloadModels';
import { UploadResult } from '../model/PayloadModels';
import { CookieService } from './CookieService';
import { PointRules } from '../viewmodel/TaskModels';
import { AppConfig } from '../config/AppConfig';

/**
 * 网络服务
 * 迁移自 Android: com.sjtu.runner.network.ApiService（OkHttp + WebViewCookieJar -> @ohos.net.http + WebCookieManager）
 * 差异：ArkTS 无 OkHttp CookieJar，Cookie 显式从 webview.WebCookieManager 读取并写入请求头。
 */
export class ApiService {
  private static readonly TAG: string = 'ApiService';

  /** 任务中心内嵌 WebView 的 UA（Android APP_USER_AGENT 原样） */
  private static readonly APP_USER_AGENT: string =
    'Mozilla/5.0 (Linux; Android 12; SM-S9080 Build/V417IR; wv) AppleWebKit/537.36 ' +
      '(KHTML, like Gecko) Version/4.0 Chrome/138.0.7204.67 Safari/537.36 TaskCenterApp/3.5.0';

  /** 桌面浏览器 UA（Android WEB_USER_AGENT 原样） */
  private static readonly WEB_USER_AGENT: string =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 ' +
      '(KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36';

  /** 默认跑步规则（等价 Android PointRules(id = 9, spmin = 180, spmax = 540)） */
  private static readonly DEFAULT_POINT_RULES: PointRules = new PointRules(9, 180, 540);

  /** 精准判断是否为 jAccount 登录页（仅登录页才触发重新登录），逻辑与 Android 版一致 */
  private static isJAccountLoginPage(content: string): boolean {
    return content.includes('Login jAccount') ||
      content.includes('jaccount.sjtu.edu.cn') ||
      content.includes('扫码登录') ||
      content.includes('Scan QR code') ||
      content.includes('统一身份认证');
  }

  /**
   * UID 形态校验：等价 Android ApiService.looksLikeUid()
   * find(Regex("[a-zA-Z0-9_-]{4,}")) —— 至少 4 位，允许字母、数字、下划线与连字符。
   * （旧实现为 /^[a-zA-Z0-9]+$/，会接受 1-3 位假 UID、拒绝含 _ / - 的真实 UID，
   *   与 Android 行为相反，2026-10 评审 M3 修正。）
   */
  private static looksLikeUid(text: string): boolean {
    return /[a-zA-Z0-9_-]{4,}/.test(text);
  }

  /** 判断 JSON 值是否等价于 Kotlin map["code"] == 0.0 */
  private static isCodeZero(code: Object | undefined): boolean {
    if (typeof code === 'number') {
      return (code as number) === 0;
    }
    if (typeof code === 'string') {
      return (code as string) === '0';
    }
    return false;
  }

  /**
   * 获取 UID
   * 迁移自 ApiService.getUid(): 依次尝试
   * 1) JSON 对象 {code:0, data:{uid}}
   * 2) JSON 字符串（纯字母数字）
   * 3) 纯文本（纯字母数字）
   */
  async getUid(): Promise<string | null> {
    const cookie = CookieService.getCookie('https://pe.sjtu.edu.cn');
    hilog.info(0x0000, ApiService.TAG, 'cookies for pe.sjtu.edu.cn: %{public}s', cookie);

    const header: Record<string, string> = { 'User-Agent': 'okhttp/4.10.0' };
    if (cookie.length > 0) {
      header['Cookie'] = cookie;
    }

    const req = http.createHttp();
    try {
      const resp = await req.request('https://pe.sjtu.edu.cn/sports/my/uid', {
        method: http.RequestMethod.GET,
        header: header,
        expectDataType: http.HttpDataType.STRING,
        usingCache: false,
        connectTimeout: 15000,
        readTimeout: 15000
      });
      const body = resp.result as string;
      hilog.info(0x0000, ApiService.TAG, 'Raw response body: %{public}s', body);
      hilog.info(0x0000, ApiService.TAG, 'Response code: %{public}d', resp.responseCode);

      // 仅精准匹配 jAccount 登录页特征
      if (ApiService.isJAccountLoginPage(body) || resp.responseCode === 302 || resp.responseCode === 403) {
        hilog.info(0x0000, ApiService.TAG, 'Response is jAccount login page/redirect - cookie已过期');
        return null;
      }

      let parsed: Object | null = null;
      try {
        parsed = JSON.parse(body) as Object;
      } catch (e) {
        parsed = null;
      }

      if (typeof parsed === 'object' && parsed !== null && !Array.isArray(parsed)) {
        const map = parsed as Record<string, Object>;
        if (ApiService.isCodeZero(map['code'])) {
          const data = map['data'] as Record<string, Object>;
          if (data !== undefined && data !== null && data['uid'] !== undefined) {
            return String(data['uid']);
          }
          return null;
        }
        hilog.info(0x0000, ApiService.TAG, 'API returned error code: %{public}s, message: %{public}s',
          JSON.stringify(map['code']), JSON.stringify(map['message']));
        return null;
      } else if (typeof parsed === 'string') {
        const uidString = parsed as string;
        hilog.info(0x0000, ApiService.TAG, 'API returned raw string: %{public}s', uidString);
        if (uidString.length > 0 && ApiService.looksLikeUid(uidString.trim())) {
          return uidString.trim();
        }
        return null;
      } else {
        hilog.info(0x0000, ApiService.TAG, 'Not valid JSON. Response might be HTML/plain text: %{public}s...',
          body.substring(0, Math.min(200, body.length)));
        const trimmedBody = body.trim();
        if (ApiService.looksLikeUid(trimmedBody)) {
          return trimmedBody;
        }
        return null;
      }
    } catch (e) {
      const err = e as BusinessError;
      hilog.error(0x0000, ApiService.TAG, 'getUid failed: %{public}d %{public}s', err.code, err.message);
      return null;
    } finally {
      req.destroy();
    }
  }

  /** 把 JSON 字段读取为 int（等价 Gson 的 JsonPrimitive.asInt），非法时返回 fallback */
  private static readInt(value: Object | undefined, fallback: number): number {
    if (typeof value === 'number') {
      // 不依赖 Math.trunc：数字统一走 parseInt(String(n))，截断语义一致且构造最保守
      const parsed = parseInt(String(value as number));
      return isNaN(parsed) ? fallback : parsed;
    }
    if (typeof value === 'string') {
      const parsed = parseInt(value as string);
      return isNaN(parsed) ? fallback : parsed;
    }
    return fallback;
  }

  /**
   * 异常 -> 可读文案。
   * catch 到的值不做 BusinessError 断言，统一按 Record 逐字段 typeof 校验，
   * 保证非 BusinessError（普通 Error / 任意抛出值）也能安全取到 message。
   */
  private static describeError(e: Object): string {
    if (typeof e !== 'object' || e === null) {
      return '未知错误';
    }
    const fields = e as Record<string, Object>;
    const messageVal = fields['message'];
    if (typeof messageVal === 'string') {
      const message = messageVal as string;
      if (message.length > 0) {
        return message;
      }
    }
    return '未知错误';
  }

  /**
   * 拉取跑步打卡规则（配速上下限、run id），失败时返回默认规则。
   * 迁移自 ApiService.getPointRules(): 先预热个人数据接口，再请求 point-rule。
   * 差异：OkHttp 的 connect/read 超时改用 http.request 的 connectTimeout/readTimeout，
   *       URLEncoder.encode(s, "UTF-8") 改用 encodeURIComponent（逗号同样编码为 %2C）。
   */
  async getPointRules(authToken: string, longitude: number, latitude: number): Promise<PointRules> {
    const defaultRules = ApiService.DEFAULT_POINT_RULES;
    const cookie = CookieService.getCookie(`https://${AppConfig.HOST}`);
    try {
      // 预热一次个人数据接口，失败不影响后续
      const warmUpHeader: Record<string, string> = {
        'User-Agent': ApiService.APP_USER_AGENT,
        'Accept': 'application/json, text/plain, */*',
        'Authorization': authToken
      };
      if (cookie.length > 0) {
        warmUpHeader['Cookie'] = cookie;
      }
      const warmUpReq = http.createHttp();
      try {
        await warmUpReq.request(AppConfig.MY_DATA_URL, {
          method: http.RequestMethod.GET,
          header: warmUpHeader,
          expectDataType: http.HttpDataType.STRING,
          usingCache: false,
          connectTimeout: 15000,
          readTimeout: 20000
        });
      } catch (e) {
        // 预热失败忽略，不写日志（与 Android runCatching 一致）
      } finally {
        warmUpReq.destroy();
      }

      const location = `${longitude.toFixed(14)},${latitude.toFixed(14)}`;
      const encodedLocation = encodeURIComponent(location);
      const ruleUrl = `${AppConfig.POINT_RULE_URL}?location=${encodedLocation}`;

      const header: Record<string, string> = {
        'User-Agent': ApiService.WEB_USER_AGENT,
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Authorization': authToken,
        'Cache-Control': 'no-cache',
        'Referer': ruleUrl
      };
      if (cookie.length > 0) {
        header['Cookie'] = cookie;
      }

      const req = http.createHttp();
      try {
        const resp = await req.request(ruleUrl, {
          method: http.RequestMethod.GET,
          header: header,
          expectDataType: http.HttpDataType.STRING,
          usingCache: false,
          connectTimeout: 15000,
          readTimeout: 20000
        });
        const body = resp.result as string;
        if (resp.responseCode < 200 || resp.responseCode >= 300) {
          hilog.warn(0x0000, ApiService.TAG, 'getPointRules: HTTP %{public}d', resp.responseCode);
          return defaultRules;
        }
        // 与 getUid 一致的登录页判断：命中即视为 cookie 过期
        if (ApiService.isJAccountLoginPage(body)) {
          hilog.warn(0x0000, ApiService.TAG, 'getPointRules: 返回登录页，使用默认规则');
          return defaultRules;
        }

        let element: Object | null = null;
        try {
          element = JSON.parse(body) as Object;
        } catch (e) {
          element = null;
        }
        if (typeof element !== 'object' || element === null || Array.isArray(element)) {
          return defaultRules;
        }
        const root = element as Record<string, Object>;
        const dataVal = root['data'];
        if (typeof dataVal !== 'object' || dataVal === null || Array.isArray(dataVal)) {
          return defaultRules;
        }
        const data = dataVal as Record<string, Object>;
        const rulesVal = data['rules'];
        if (typeof rulesVal !== 'object' || rulesVal === null || Array.isArray(rulesVal)) {
          return defaultRules;
        }
        const rules = rulesVal as Record<string, Object>;

        const id = ApiService.readInt(rules['id'], 6);
        const spmin = ApiService.readInt(rules['spmin'], 180);
        const spmax = ApiService.readInt(rules['spmax'], 540);
        return new PointRules(id === 6 ? 9 : id, spmin, spmax);
      } finally {
        req.destroy();
      }
    } catch (e) {
      // 不做 BusinessError 断言，统一按 Object 读取 message
      const err = e as Object;
      hilog.warn(0x0000, ApiService.TAG, 'getPointRules 失败，使用默认规则: %{public}s',
        ApiService.describeError(err));
      return defaultRules;
    }
  }

  /**
   * 上传跑步数据
   * 迁移自 ApiService.upload(): POST JSON payload，Authorization 携带 uid（与 Android 一致）
   */
  async upload(authToken: string, payload: PayloadItem[]): Promise<UploadResult> {
    const cookie = CookieService.getCookie('https://pe.sjtu.edu.cn');
    const json = JSON.stringify(payload);

    const header: Record<string, string> = {
      'Authorization': authToken,
      'Content-Type': 'application/json; charset=utf-8'
    };
    if (cookie.length > 0) {
      header['Cookie'] = cookie;
    }

    const req = http.createHttp();
    try {
      const resp = await req.request('https://pe.sjtu.edu.cn/api/running/result/upload', {
        method: http.RequestMethod.POST,
        header: header,
        extraData: json,
        expectDataType: http.HttpDataType.STRING,
        usingCache: false,
        connectTimeout: 20000,
        readTimeout: 20000
      });
      const respBody = resp.result as string;
      hilog.info(0x0000, ApiService.TAG, 'Upload response code: %{public}d', resp.responseCode);
      hilog.info(0x0000, ApiService.TAG, 'Upload response body: %{public}s',
        respBody.substring(0, Math.min(200, respBody.length)));

      // 检测是否因 cookie 过期导致上传失败（复用 jAccount 登录页判断）
      if (ApiService.isJAccountLoginPage(respBody) || resp.responseCode === 403 || resp.responseCode === 401) {
        hilog.info(0x0000, ApiService.TAG, '上传失败，可能cookie已过期');
        return new UploadResult(false, 'cookie已过期，需要重新登录', true);
      }

      try {
        const resMap = JSON.parse(respBody) as Record<string, Object>;
        let code = -1;
        const rawCode = resMap['code'];
        if (typeof rawCode === 'number') {
          code = rawCode as number;
        } else if (typeof rawCode === 'string') {
          code = parseInt(rawCode as string);
          if (isNaN(code)) {
            code = -1;
          }
        }
        const message = resMap['message'] !== undefined ? String(resMap['message']) : '未知错误';
        return new UploadResult(code === 0, message, false);
      } catch (e) {
        return new UploadResult(false, respBody, false);
      }
    } catch (e) {
      const err = e as BusinessError;
      hilog.error(0x0000, ApiService.TAG, 'upload failed: %{public}d %{public}s', err.code, err.message);
      return new UploadResult(false, `网络请求失败: ${err.message}`, false);
    } finally {
      req.destroy();
    }
  }
}
