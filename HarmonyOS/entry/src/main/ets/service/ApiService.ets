import { http } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { PayloadItem } from '../model/PayloadModels';
import { UploadResult } from '../model/PayloadModels';
import { CookieService } from './CookieService';

/**
 * 网络服务
 * 迁移自 Android: com.sjtu.runner.network.ApiService（OkHttp + WebViewCookieJar -> @ohos.net.http + WebCookieManager）
 */
export class ApiService {
  private static readonly TAG: string = 'ApiService';

  /** 精准判断是否为 jAccount 登录页（仅登录页才触发重新登录），逻辑与 Android 版一致 */
  private static isJAccountLoginPage(content: string): boolean {
    return content.includes('Login jAccount') ||
      content.includes('jaccount.sjtu.edu.cn') ||
      content.includes('扫码登录') ||
      content.includes('Scan QR code') ||
      content.includes('统一身份认证');
  }

  /** 纯文本校验：仅字母数字（等价 Regex("[a-zA-Z0-9]+") 全匹配） */
  private static isAlphanumeric(text: string): boolean {
    return /^[a-zA-Z0-9]+$/.test(text);
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
        if (uidString.length > 0 && ApiService.isAlphanumeric(uidString.trim())) {
          return uidString.trim();
        }
        return null;
      } else {
        hilog.info(0x0000, ApiService.TAG, 'Not valid JSON. Response might be HTML/plain text: %{public}s...',
          body.substring(0, Math.min(200, body.length)));
        const trimmedBody = body.trim();
        if (ApiService.isAlphanumeric(trimmedBody)) {
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
