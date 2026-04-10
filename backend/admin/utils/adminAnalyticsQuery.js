/**
 * Admin Analytics 查询参数治理层（第一部分骨架）
 *
 * 统一解析 time_range / platform / entry_position / custom 区间，
 * 后续聚合接口只消费 parseAdminAnalyticsQuery 的返回值即可。
 */

const ALLOWED_TIME_RANGES = new Set(['today', '7d', '14d', '30d', 'custom']);

/**
 * 取当前时刻的 UTC 日历「日」零点。
 * @param {Date} d
 * @returns {Date}
 */
function startOfUtcDay(d) {
  return new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate(), 0, 0, 0, 0));
}

/**
 * 取当前时刻的 UTC 日历「日」最后一刻（含毫秒）。
 * @param {Date} d
 * @returns {Date}
 */
function endOfUtcDay(d) {
  return new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate(), 23, 59, 59, 999));
}

/**
 * UTC 日期加天数（可为负）。
 * @param {Date} utcDayStart
 * @param {number} days
 * @returns {Date}
 */
function addUtcDays(utcDayStart, days) {
  const t = utcDayStart.getTime();
  return new Date(t + days * 24 * 60 * 60 * 1000);
}

/**
 * Date → YYYY-MM-DD（UTC）
 * @param {Date} d
 * @returns {string}
 */
function toUtcDateString(d) {
  const y = d.getUTCFullYear();
  const m = String(d.getUTCMonth() + 1).padStart(2, '0');
  const day = String(d.getUTCDate()).padStart(2, '0');
  return `${y}-${m}-${day}`;
}

/**
 * 尝试解析 ISO-8601 时间字符串；失败返回 null。
 * @param {string} raw
 * @returns {Date | null}
 */
function parseIsoDate(raw) {
  if (!raw || typeof raw !== 'string') return null;
  const s = raw.trim();
  if (!s) return null;
  const d = new Date(s);
  return Number.isNaN(d.getTime()) ? null : d;
}

/**
 * 从 Express req.query 解析管理员 Analytics 筛选条件。
 *
 * Query 约定：
 * - time_range: today | 7d | 14d | 30d | custom（缺省按合同默认 7d）
 * - platform: 可选，空字符串视为未筛选
 * - entry_position: 可选，仅 Upload 漏斗使用
 * - from / to: 当 time_range=custom 时必填，ISO-8601（建议带 Z 的 UTC）
 *
 * @param {Record<string, unknown>} query Express req.query
 * @param {{ requireEntryPosition?: boolean }} [opts]
 * @returns {{ ok: true, filter: object } | { ok: false, error: { status: number, code: string, message: string } }}
 */
function parseAdminAnalyticsQuery(query, opts = {}) {
  const q = query || {};
  const rawRange = String(q.time_range || '7d').trim().toLowerCase();
  if (!ALLOWED_TIME_RANGES.has(rawRange)) {
    return {
      ok: false,
      error: {
        status: 400,
        code: 'INVALID_TIME_RANGE',
        message: `time_range 必须是 ${[...ALLOWED_TIME_RANGES].join(' | ')} 之一`,
      },
    };
  }

  const platformRaw = q.platform != null ? String(q.platform).trim() : '';
  const platform = platformRaw === '' ? null : platformRaw;

  const entryRaw = q.entry_position != null ? String(q.entry_position).trim() : '';
  const entry_position = entryRaw === '' ? null : entryRaw;
  if (opts.requireEntryPosition && !entry_position) {
    return {
      ok: false,
      error: {
        status: 400,
        code: 'MISSING_ENTRY_POSITION',
        message: '该接口需要 query 参数 entry_position',
      },
    };
  }

  const now = new Date();
  const todayStart = startOfUtcDay(now);
  const todayEnd = endOfUtcDay(now);

  let occurred_at_from;
  let occurred_at_to;
  let utc_date_from;
  let utc_date_to;

  if (rawRange === 'today') {
    occurred_at_from = todayStart;
    occurred_at_to = todayEnd;
    utc_date_from = toUtcDateString(todayStart);
    utc_date_to = toUtcDateString(todayStart);
  } else if (rawRange === '7d') {
    // 中文注释：含今天共 7 个 UTC 日历日（与 event_date 按天对齐时常用口径）
    const fromDay = addUtcDays(todayStart, -6);
    occurred_at_from = startOfUtcDay(fromDay);
    occurred_at_to = todayEnd;
    utc_date_from = toUtcDateString(fromDay);
    utc_date_to = toUtcDateString(todayStart);
  } else if (rawRange === '14d') {
    const fromDay = addUtcDays(todayStart, -13);
    occurred_at_from = startOfUtcDay(fromDay);
    occurred_at_to = todayEnd;
    utc_date_from = toUtcDateString(fromDay);
    utc_date_to = toUtcDateString(todayStart);
  } else if (rawRange === '30d') {
    const fromDay = addUtcDays(todayStart, -29);
    occurred_at_from = startOfUtcDay(fromDay);
    occurred_at_to = todayEnd;
    utc_date_from = toUtcDateString(fromDay);
    utc_date_to = toUtcDateString(todayStart);
  } else {
    // custom
    const fromD = parseIsoDate(String(q.from || ''));
    const toD = parseIsoDate(String(q.to || ''));
    if (!fromD || !toD) {
      return {
        ok: false,
        error: {
          status: 400,
          code: 'INVALID_CUSTOM_RANGE',
          message: "time_range=custom 时必须提供有效的 from 与 to（ISO-8601，例如 2026-04-01T00:00:00.000Z）",
        },
      };
    }
    if (fromD.getTime() > toD.getTime()) {
      return {
        ok: false,
        error: {
          status: 400,
          code: 'CUSTOM_RANGE_INVERTED',
          message: 'from 不能晚于 to',
        },
      };
    }
    occurred_at_from = fromD;
    occurred_at_to = toD;
    utc_date_from = toUtcDateString(startOfUtcDay(fromD));
    utc_date_to = toUtcDateString(startOfUtcDay(toD));
  }

  return {
    ok: true,
    filter: {
      time_range: rawRange,
      platform,
      entry_position,
      occurred_at_from: occurred_at_from.toISOString(),
      occurred_at_to: occurred_at_to.toISOString(),
      utc_date_from,
      utc_date_to,
    },
  };
}

module.exports = {
  parseAdminAnalyticsQuery,
  ALLOWED_TIME_RANGES,
};
