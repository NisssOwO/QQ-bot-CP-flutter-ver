'use strict';

/**
 * Android 上打包进 APK 的 Node 是裁剪构建，没有编译 ICU，全局连 `Intl` 都不存在。
 *
 * 表现：任何 `new Intl.DateTimeFormat(...)` 直接抛 `ReferenceError: Intl is not defined`。
 * 具体到这台机器人，harness 的 time-context 插件在应用里构造时间戳格式器就会炸，
 * 于是每轮请求拿不到「当前时间」，日志里只剩一条
 * `im-qqbot (@tencent-connect/dsh-qqbot): ReferenceError: Intl is not defined`，
 * 模型也没法判断“今天”是几号，联网搜索因此不肯触发。
 *
 * 这里补一个够用的最小实现：只覆盖 DateTimeFormat / NumberFormat 的常用能力，
 * 时区按设备本地偏移换算（本机是 UTC+8），输出 en-US 数字风格。
 * 有真 Intl 的运行环境完全不动（`typeof Intl === 'undefined'` 才安装）。
 */

if (typeof globalThis.Intl === 'undefined') {
  const localOffsetMinutes = () => -new Date().getTimezoneOffset();

  /**
   * 没有 ICU 就查不到 IANA 时区库：除了 UTC，一律按设备本地偏移算。
   * 这台机器固定在国内，等价于 Asia/Shanghai。
   */
  const zoneOffsetMinutes = (timeZone) => {
    if (!timeZone || timeZone === 'UTC' || timeZone === 'Etc/UTC' || timeZone === 'GMT') return 0;
    return localOffsetMinutes();
  };

  const pad = (value, width) => String(value).padStart(width, '0');

  const offsetLabel = (minutes) => {
    const sign = minutes < 0 ? '-' : '+';
    const abs = Math.abs(minutes);
    return `GMT${sign}${pad(Math.floor(abs / 60), 2)}:${pad(abs % 60, 2)}`;
  };

  /** 例如 `UTC+08:00`，与 ISO 时间戳末尾的 `[zone]` 标签对应。 */
  const defaultTimeZone = () => `UTC${offsetLabel(localOffsetMinutes()).slice(3)}`;

  const localeOf = (locales) => {
    if (Array.isArray(locales)) return typeof locales[0] === 'string' ? locales[0] : 'en-US';
    return typeof locales === 'string' ? locales : 'en-US';
  };

  class DateTimeFormat {
    constructor(locales, options) {
      this.locale = localeOf(locales);
      this.options = options && typeof options === 'object' ? { ...options } : {};
      this.timeZone = this.options.timeZone || defaultTimeZone();
    }

    resolvedOptions() {
      return {
        locale: this.locale,
        calendar: 'gregory',
        numberingSystem: 'latn',
        timeZone: this.timeZone,
      };
    }

    formatToParts(date) {
      const at = date === undefined ? new Date() : new Date(date);
      const shifted = new Date(at.getTime() + zoneOffsetMinutes(this.timeZone) * 60_000);
      const wanted = (key) => this.options[key] !== undefined;
      const parts = [];
      const push = (type, value) => parts.push({ type, value });

      if (wanted('year')) push('year', pad(shifted.getUTCFullYear(), 4));
      if (wanted('month')) push('month', pad(shifted.getUTCMonth() + 1, 2));
      if (wanted('day')) push('day', pad(shifted.getUTCDate(), 2));
      if (wanted('hour')) push('hour', pad(shifted.getUTCHours(), 2));
      if (wanted('minute')) push('minute', pad(shifted.getUTCMinutes(), 2));
      if (wanted('second')) push('second', pad(shifted.getUTCSeconds(), 2));
      if (parts.length === 0) {
        // 没给任何字段时按原生默认行为输出日期部分。
        push('year', pad(shifted.getUTCFullYear(), 4));
        push('month', pad(shifted.getUTCMonth() + 1, 2));
        push('day', pad(shifted.getUTCDate(), 2));
      }
      if (wanted('timeZoneName')) push('timeZoneName', offsetLabel(zoneOffsetMinutes(this.timeZone)));
      return parts;
    }

    format(date) {
      return this.formatToParts(date)
        .map((part) => part.value)
        .join(' ');
    }
  }

  class NumberFormat {
    constructor(locales, options) {
      this.locale = localeOf(locales);
      this.options = options && typeof options === 'object' ? { ...options } : {};
    }

    resolvedOptions() {
      return { locale: this.locale, numberingSystem: 'latn' };
    }

    format(value) {
      const number = Number(value);
      return Number.isFinite(number) ? String(number) : String(value);
    }
  }

  globalThis.Intl = {
    DateTimeFormat,
    NumberFormat,
    supportedValuesOf: () => [],
  };
}
