/**
 * 通用格式化工具
 * 迁移自 Android 代码中的 String.format / LocalDate / DateTimeFormatter / UUID 等用法。
 * ArkTS 环境下自行实现等价能力。
 */

/** 数字补零，如 pad2(7) => "07" */
export function pad2(n: number): string {
  return n < 10 ? `0${n}` : `${n}`;
}

/** 时间戳 -> HH:mm:ss（本地时区） */
export function formatTimeMs(ms: number): string {
  const d = new Date(ms);
  return `${pad2(d.getHours())}:${pad2(d.getMinutes())}:${pad2(d.getSeconds())}`;
}

/** Date -> YYYY-MM-DD（本地时区，等价 DateTimeFormatter.ISO_LOCAL_DATE） */
export function formatDate(d: Date): string {
  return `${d.getFullYear()}-${pad2(d.getMonth() + 1)}-${pad2(d.getDate())}`;
}

/** 解析 YYYY-MM-DD 字符串为本地时区 Date（当天 00:00:00），非法时返回 null */
export function parseDate(text: string): Date | null {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(text)) {
    return null;
  }
  const parts = text.split('-');
  const y = parseInt(parts[0]);
  const m = parseInt(parts[1]);
  const d = parseInt(parts[2]);
  if (m < 1 || m > 12 || d < 1 || d > 31) {
    return null;
  }
  const date = new Date(y, m - 1, d, 0, 0, 0, 0);
  if (date.getMonth() !== m - 1 || date.getDate() !== d) {
    return null;
  }
  return date;
}

/** 昨天的 Date（本地时区 00:00:00） */
export function yesterday(): Date {
  const d = new Date();
  d.setHours(0, 0, 0, 0);
  d.setDate(d.getDate() - 1);
  return d;
}

/** 指定日期 + 时分 -> 毫秒时间戳（本地时区，等价 date.atTime(hour, minute).atZone(systemDefault).toInstant().toEpochMilli()） */
export function localDateTimeMs(d: Date, hour: number, minute: number): number {
  return new Date(d.getFullYear(), d.getMonth(), d.getDate(), hour, minute, 0, 0).getTime();
}

/** [min, max] 闭区间随机整数（等价 Kotlin Random.nextLong(min, max+1)） */
export function randomInt(min: number, max: number): number {
  return Math.floor(Math.random() * (max - min + 1)) + min;
}

/** UUID v4 生成（等价 java.util.UUID.randomUUID().toString()） */
export function uuidV4(): string {
  const hex = '0123456789abcdef';
  let s = '';
  for (let i = 0; i < 36; i++) {
    if (i === 8 || i === 13 || i === 18 || i === 23) {
      s += '-';
    } else if (i === 14) {
      s += '4';
    } else if (i === 19) {
      s += hex.charAt(Math.floor(Math.random() * 4) + 8);
    } else {
      s += hex.charAt(Math.floor(Math.random() * 16));
    }
  }
  return s;
}

/** 保留 N 位小数的定点字符串（等价 String.format("%.Nf", v)） */
export function toFixedStr(v: number, digits: number): string {
  return v.toFixed(digits);
}

/** 过滤出纯数字字符（等价 Kotlin c.isDigit() filter） */
export function digitsOnly(text: string): string {
  let out = '';
  for (let i = 0; i < text.length; i++) {
    const c = text.charAt(i);
    if (c >= '0' && c <= '9') {
      out += c;
    }
  }
  return out;
}
