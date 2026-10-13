import { http } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppConfig } from '../config/AppConfig';

/**
 * 更新检查
 * 迁移自 Android: com.sjtu.runner.update.UpdateChecker
 * 差异：Kotlin 的 sealed class / Pair 改为显式 class + 枚举（ArkTS 严格模式不支持联合类型收窄与结构类型），
 *       OkHttp 改为 @kit.NetworkKit 的 http 模块，异常按 BusinessError.code 判定超时/网络不可用。
 *       catch 到的值不直接断言为 BusinessError，而是在 shortError 里按 Record 逐字段取值（见该方法注释）。
 */

/** GitHub Release 摘要 */
export class ReleaseInfo {
  tag: string;
  url: string;
  prerelease: boolean;
  publishedAt: string;

  constructor(tag: string, url: string, prerelease: boolean, publishedAt: string) {
    this.tag = tag;
    this.url = url;
    this.prerelease = prerelease;
    this.publishedAt = publishedAt;
  }
}

/** 更新检查结果类型 */
export enum UpdateResultKind {
  UP_TO_DATE = 'UP_TO_DATE',
  UPDATE_AVAILABLE = 'UPDATE_AVAILABLE',
  FAILED = 'FAILED'
}

/** 更新检查结果（等价 Android sealed class UpdateResult 的三个子类） */
export class UpdateResult {
  kind: UpdateResultKind;
  currentTag: string;
  latestTag: string;
  latest: ReleaseInfo | null;
  reason: string;

  constructor(kind: UpdateResultKind, currentTag: string, latestTag: string,
    latest: ReleaseInfo | null, reason: string) {
    this.kind = kind;
    this.currentTag = currentTag;
    this.latestTag = latestTag;
    this.latest = latest;
    this.reason = reason;
  }

  /** 已是最新（UpToDate） */
  static upToDate(currentTag: string, latestTag: string): UpdateResult {
    return new UpdateResult(UpdateResultKind.UP_TO_DATE, currentTag, latestTag, null, '');
  }

  /** 有可用更新（UpdateAvailable） */
  static available(currentTag: string, latest: ReleaseInfo): UpdateResult {
    return new UpdateResult(UpdateResultKind.UPDATE_AVAILABLE, currentTag, latest.tag, latest, '');
  }

  /** 检查失败（Failed） */
  static failed(reason: string): UpdateResult {
    return new UpdateResult(UpdateResultKind.FAILED, '', '', null, reason);
  }
}

/**
 * 版本号拆解结果：数字元组 + 预发布后缀。
 * stable 只在排序键（sortKey）里使用：稳定版 1、预发布 0；
 * parseVersion 出来的值不参与稳定标记比较（isNewer 用的是显式传入的 1/1）。
 */
export class VersionKey {
  numbers: number[];
  prerelease: string;
  stable: number;

  constructor(numbers: number[], prerelease: string, stable: number = 0) {
    this.numbers = numbers;
    this.prerelease = prerelease;
    this.stable = stable;
  }
}

/**
 * GitHub releases 列表元素。
 * 不用 interface + `as` 断言（JSON.parse 的产物是 Object，断言成接口数组在严格模式下不保险），
 * 改为运行时逐字段校验后装进类实例，等价 Android 的 Gson 反序列化 + 可空字段。
 */
class ReleaseEntry {
  tagName: string | null;
  htmlUrl: string | null;
  draft: boolean;
  prerelease: boolean;
  publishedAt: string | null;

  constructor(tagName: string | null, htmlUrl: string | null, draft: boolean,
    prerelease: boolean, publishedAt: string | null) {
    this.tagName = tagName;
    this.htmlUrl = htmlUrl;
    this.draft = draft;
    this.prerelease = prerelease;
    this.publishedAt = publishedAt;
  }

  /** 从 JSON 条目做类型校验；非法（标量/数组/null）返回 null */
  static fromJson(raw: Object | null): ReleaseEntry | null {
    if (typeof raw !== 'object' || raw === null || Array.isArray(raw)) {
      return null;
    }
    const map = raw as Record<string, Object>;
    const tagVal = map['tag_name'];
    const urlVal = map['html_url'];
    const draftVal = map['draft'];
    const preVal = map['prerelease'];
    const publishedVal = map['published_at'];
    return new ReleaseEntry(
      typeof tagVal === 'string' ? tagVal as string : null,
      typeof urlVal === 'string' ? urlVal as string : null,
      typeof draftVal === 'boolean' ? draftVal as boolean : false,
      typeof preVal === 'boolean' ? preVal as boolean : false,
      typeof publishedVal === 'string' ? publishedVal as string : null
    );
  }
}

/** 参与比较的候选 Release：保留原始条目 + 排序键 */
class Candidate {
  release: ReleaseEntry;
  key: VersionKey;

  constructor(release: ReleaseEntry, key: VersionKey) {
    this.release = release;
    this.key = key;
  }
}

/** 更新检查器 */
export class UpdateChecker {
  /** 超时类错误码（@kit.NetworkKit http 请求超时） */
  private static readonly TIMEOUT_CODES: number[] = [2300028, 2300027];
  /** 网络不可用类错误码（主机解析失败 / 连接失败） */
  private static readonly NETWORK_CODES: number[] = [2300006, 2300007];

  private static readonly CONNECT_TIMEOUT_MS: number = 15000;
  private static readonly READ_TIMEOUT_MS: number = 15000;
  private static readonly TAG: string = 'UpdateChecker';

  /** 把 tag 拆成 (数字元组, 预发布后缀)，例如 "v4.4.0" -> ([4,4,0], "") */
  static parseVersion(text: string | null): VersionKey {
    if (text === null || text === undefined) {
      return new VersionKey([], '');
    }
    const trimmed = text.trim();
    if (trimmed.length === 0) {
      return new VersionKey([], '');
    }
    let raw = trimmed;
    if (raw.startsWith('v') || raw.startsWith('V')) {
      raw = raw.substring(1);
    }
    // 在第一个 '-' 处拆分（等价 Kotlin split("-", limit = 2)）
    const dashIndex = raw.indexOf('-');
    const head = dashIndex < 0 ? raw : raw.substring(0, dashIndex);
    const tail = dashIndex < 0 ? '' : raw.substring(dashIndex + 1);

    const numbers: number[] = [];
    const chunks = head.split('.');
    for (const chunk of chunks) {
      // 取该段的前导数字串（等价 chunk.takeWhile { it.isDigit() }）
      let digits = '';
      for (let i = 0; i < chunk.length; i++) {
        const codePoint = chunk.charCodeAt(i);
        if (codePoint < 48 || codePoint > 57) {
          break;
        }
        digits += chunk.charAt(i);
      }
      if (digits.length === 0) {
        break;
      }
      numbers.push(parseInt(digits));
    }
    return new VersionKey(numbers, tail);
  }

  /** 远程 tag 是否比本地版本新；版本号相同时稳定版优先于预发布版 */
  static isNewer(remoteTag: string | null, localTag: string): boolean {
    const remote = UpdateChecker.parseVersion(remoteTag);
    const local = UpdateChecker.parseVersion(localTag);
    if (remote.numbers.length === 0) {
      return false;
    }
    // 调用点 1：只比数字，两侧 stable 标记固定传 1
    // （等价 Android `compareKeys(remoteNumbers to 1, localNumbers to 1)`）。
    // 预发布只作为下面单独一步的 tie-break，绝不参与这里的数字比较。
    const cmp = UpdateChecker.compareWithFlags(remote.numbers, 1, local.numbers, 1);
    if (cmp !== 0) {
      return cmp > 0;
    }
    // 数字完全相同：远程是稳定版而本地是预发布版时才算更新
    return remote.prerelease.length === 0 && local.prerelease.length > 0;
  }

  /** 检查更新；网络/解析失败时返回 UpdateResult.FAILED */
  static async checkForUpdates(currentVersion: string = AppConfig.VERSION_NAME): Promise<UpdateResult> {
    try {
      const latest = await UpdateChecker.fetchLatestRelease();
      if (UpdateChecker.isNewer(latest.tag, currentVersion)) {
        return UpdateResult.available(currentVersion, latest);
      }
      return UpdateResult.upToDate(currentVersion, latest.tag);
    } catch (e) {
      // catch 到的值不做 BusinessError 断言：统一按 Object 逐字段读取
      const err = e as Object;
      const reason = UpdateChecker.shortError(err);
      hilog.warn(0x0000, UpdateChecker.TAG, 'checkForUpdates failed: %{public}s', reason);
      return UpdateResult.failed(reason);
    }
  }

  /** 拉取最新 Release；失败抛出异常（等价 Android Result.failure） */
  private static async fetchLatestRelease(): Promise<ReleaseInfo> {
    const header: Record<string, string> = {
      'Accept': 'application/vnd.github+json',
      'User-Agent': `SJTURunningMan/${AppConfig.VERSION_NAME}`
    };
    const req = http.createHttp();
    try {
      const resp = await req.request(AppConfig.GITHUB_RELEASES_API, {
        method: http.RequestMethod.GET,
        header: header,
        expectDataType: http.HttpDataType.STRING,
        usingCache: false,
        connectTimeout: UpdateChecker.CONNECT_TIMEOUT_MS,
        readTimeout: UpdateChecker.READ_TIMEOUT_MS
      });
      if (resp.responseCode < 200 || resp.responseCode >= 300) {
        hilog.warn(0x0000, UpdateChecker.TAG, 'releases HTTP %{public}d', resp.responseCode);
        throw new Error(UpdateChecker.shortErrorForCode(resp.responseCode));
      }
      const body = resp.result as string;
      if (body === undefined || body === null || body.trim().length === 0) {
        throw new Error('空响应');
      }
      let parsed: Object | null = null;
      try {
        parsed = JSON.parse(body) as Object;
      } catch (e) {
        parsed = null;
      }
      if (parsed === null || !Array.isArray(parsed)) {
        throw new Error('未找到可用的 Release');
      }
      // 只断言到 Object[]，逐条经 ReleaseEntry.fromJson 做运行时字段校验（避免 JSON.parse 结果直接断言为接口数组）
      const rawList = parsed as Object[];
      let best: Candidate | null = null;
      for (const rawEntry of rawList) {
        const release = ReleaseEntry.fromJson(rawEntry);
        if (release === null) {
          continue;
        }
        if (release.draft) {
          // 等价 Android `it.draft != true`
          continue;
        }
        const key = UpdateChecker.sortKey(release.tagName);
        if (key.numbers.length === 0) {
          continue;
        }
        if (best === null || UpdateChecker.compareKeys(key, best.key) > 0) {
          best = new Candidate(release, key);
        }
      }
      if (best === null) {
        throw new Error('未找到可用的 Release');
      }
      const chosen: ReleaseEntry = best.release;
      const chosenTag: string | null = chosen.tagName;
      const tagName: string = chosenTag === null ? '' : chosenTag;
      const chosenUrl: string | null = chosen.htmlUrl;
      const htmlUrl: string = chosenUrl === null ? `${AppConfig.GITHUB_REPO_URL}/releases` : chosenUrl;
      const chosenPublished: string | null = chosen.publishedAt;
      const publishedAt: string = chosenPublished === null ? '' : chosenPublished;
      return new ReleaseInfo(tagName, htmlUrl, chosen.prerelease, publishedAt);
    } finally {
      req.destroy();
    }
  }

  /** 排序键：数字元组 + 稳定标记（稳定 1 / 预发布 0） */
  private static sortKey(tag: string | null): VersionKey {
    const parsed = UpdateChecker.parseVersion(tag);
    return new VersionKey(parsed.numbers, parsed.prerelease, parsed.prerelease.length === 0 ? 1 : 0);
  }

  /**
   * 调用点 2：候选 Release 之间的比较，用 sortKey 里真实写入的稳定标记。
   * sortKey 的预期取值只有 1（稳定）与 0（预发布），这里逐位比较数字后再比该标记，
   * 因此同一版本号的稳定 Release 一定排在预发布之前。
   */
  private static compareKeys(a: VersionKey, b: VersionKey): number {
    return UpdateChecker.compareWithFlags(a.numbers, a.stable, b.numbers, b.stable);
  }

  /** 逐位比较：missing index 视为 0；数字全等则比较传入的 stable 标记 */
  private static compareWithFlags(aNumbers: number[], aStable: number,
    bNumbers: number[], bStable: number): number {
    const size = Math.max(aNumbers.length, bNumbers.length);
    for (let i = 0; i < size; i++) {
      let x = 0;
      if (i < aNumbers.length) {
        const av: number = aNumbers[i];
        x = av;
      }
      let y = 0;
      if (i < bNumbers.length) {
        const bv: number = bNumbers[i];
        y = bv;
      }
      if (x !== y) {
        return x > y ? 1 : -1;
      }
    }
    if (aStable !== bStable) {
      return aStable > bStable ? 1 : -1;
    }
    return 0;
  }

  /** HTTP 状态码 -> 简短原因（等价 Android shortError(httpCode)） */
  private static shortErrorForCode(httpCode: number): string {
    if (httpCode === 403) {
      return '请求过于频繁 (403)';
    }
    return `HTTP ${httpCode}`;
  }

  /**
   * 异常 -> 简短原因。
   * Android 依据 SocketTimeoutException / IOException 分类；
   * HarmonyOS @kit.NetworkKit 的 http 以 BusinessError.code 表达同类错误，故按错误码映射：
   * 2300028 为请求超时，2300006/2300007 为主机解析/连接失败（网络不可用）。
   * 入参类型为 Object：catch 到的值不做 BusinessError 断言，这里统一按 Record 逐字段 typeof 校验，
   * 非 BusinessError（如解析时主动抛出的 Error）回落到 message，再不行给固定文案。
   */
  private static shortError(err: Object | null): string {
    if (err === null || typeof err !== 'object') {
      return '网络请求失败';
    }
    const fields = err as Record<string, Object>;
    const codeVal = fields['code'];
    let code = 0;
    if (typeof codeVal === 'number') {
      code = codeVal as number;
    }
    if (UpdateChecker.TIMEOUT_CODES.includes(code)) {
      return '连接超时';
    }
    if (UpdateChecker.NETWORK_CODES.includes(code)) {
      return '网络不可用';
    }
    const messageVal = fields['message'];
    if (typeof messageVal === 'string') {
      const message = messageVal as string;
      if (message.length > 0) {
        return message;
      }
    }
    return '网络请求失败';
  }
}
