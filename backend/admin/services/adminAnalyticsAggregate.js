/**
 * Admin Analytics 聚合查询（第二部分）
 *
 * 中文注释：所有读数优先走 analytics_* 视图，避免接口直接拼 jsonb；
 * 窗口级 UV 等不能对分桶行简单相加的指标，走专用 SQL 函数。
 */

/**
 * Supabase / PostgREST 返回的数值可能是 string，这里统一成有限数字。
 * @param {unknown} v
 * @returns {number}
 */
function n(v) {
  if (v == null || v === '') return 0;
  const x = Number(v);
  return Number.isFinite(x) ? x : 0;
}

/**
 * 比率字段转 number；null 视为 0。
 * @param {unknown} v
 * @returns {number}
 */
function nRate(v) {
  if (v == null) return 0;
  const x = Number(v);
  return Number.isFinite(x) ? x : 0;
}

const FLAT_PAGE_SIZE = 1000;
const FLAT_MAX_ROWS = 50000;
// 误触防抖窗口：用于过滤一次点击流程中的快速双击/三击（毫秒级）。
const UPLOAD_CLICK_DEDUP_MS = 600;
const AI_EVENTS = ['ai_identify_start', 'ai_identify_result', 'ai_identify_fail'];

/**
 * 分页拉平 analytics_event_flat_v / analytics_events，在管理端数据量下做补充聚合。
 * 中文注释：超过 FLAT_MAX_ROWS 会截断，避免极端情况下 OOM。
 * @param {import('@supabase/supabase-js').SupabaseClient} supabaseAdmin
 * @param {() => import('@supabase/supabase-js').PostgrestFilterBuilder} buildQuery
 */
async function fetchAllPaged(supabaseAdmin, buildQuery) {
  let from = 0;
  /** @type {Record<string, unknown>[]} */
  const out = [];
  for (;;) {
    const q = buildQuery().range(from, from + FLAT_PAGE_SIZE - 1);
    const { data, error } = await q;
    if (error) throw new Error(error.message || String(error));
    const rows = data || [];
    out.push(...rows);
    if (rows.length < FLAT_PAGE_SIZE) break;
    from += FLAT_PAGE_SIZE;
    if (from >= FLAT_MAX_ROWS) break;
  }
  return out;
}

/**
 * 口径：DAU = 当天触发 app_launch 的去重用户数（identity_key）。
 * 返回按日（全平台）和按日+平台两个层级，便于 summary 与 daily 同步。
 * @param {import('@supabase/supabase-js').SupabaseClient} supabaseAdmin
 * @param {{ utc_date_from: string, utc_date_to: string, platform: string | null }} filter
 */
async function computeAppLaunchDauMetrics(supabaseAdmin, filter) {
  const rows = await fetchAllPaged(supabaseAdmin, () => {
    let q = supabaseAdmin
      .from('analytics_event_flat_v')
      .select('event_date, platform, identity_key')
      .eq('event_type', 'app_launch')
      .gte('event_date', filter.utc_date_from)
      .lte('event_date', filter.utc_date_to);
    if (filter.platform) q = q.eq('platform', filter.platform);
    return q;
  });

  /** @type {Map<string, Set<string>>} */
  const dayIdentity = new Map();
  /** @type {Map<string, Set<string>>} */
  const dayPlatformIdentity = new Map();
  const windowIdentity = new Set();
  for (const r of rows) {
    const d = String(r.event_date || '');
    const p = String(r.platform || '__unknown__');
    const id = r.identity_key != null ? String(r.identity_key) : '';
    if (!d || !id) continue;

    if (!dayIdentity.has(d)) dayIdentity.set(d, new Set());
    dayIdentity.get(d).add(id);
    windowIdentity.add(id);

    const k = `${d}\0${p}`;
    if (!dayPlatformIdentity.has(k)) dayPlatformIdentity.set(k, new Set());
    dayPlatformIdentity.get(k).add(id);
  }

  /** @type {Record<string, number>} */
  const dauByDay = {};
  for (const [d, s] of dayIdentity.entries()) {
    dauByDay[d] = s.size;
  }

  /** @type {Record<string, number>} */
  const dauByDayPlatform = {};
  for (const [k, s] of dayPlatformIdentity.entries()) {
    dauByDayPlatform[k] = s.size;
  }

  return {
    // summary DAU 口径：筛选窗口结束日（utc_date_to）当日 DAU。
    summary_dau: dauByDay[filter.utc_date_to] || 0,
    window_app_launch_uv: windowIdentity.size,
    dauByDay,
    dauByDayPlatform,
  };
}

/**
 * upload_click 去重口径：同 identity_key + platform + entry_position，
 * 在短时间窗口内的重复点击只计一次。
 * @param {import('@supabase/supabase-js').SupabaseClient} supabaseAdmin
 * @param {{ utc_date_from: string, utc_date_to: string, platform: string | null, entry_position: string | null }} filter
 */
async function computeUploadClickDedupMetrics(supabaseAdmin, filter) {
  const rows = await fetchAllPaged(supabaseAdmin, () => {
    let q = supabaseAdmin
      .from('analytics_event_flat_v')
      .select('event_date, platform, entry_position, identity_key, occurred_at')
      .eq('event_type', 'upload_click')
      .gte('event_date', filter.utc_date_from)
      .lte('event_date', filter.utc_date_to)
      .order('occurred_at', { ascending: true });
    if (filter.platform) q = q.eq('platform', filter.platform);
    if (filter.entry_position) q = q.eq('entry_position', filter.entry_position);
    return q;
  });

  /** @type {Map<string, number>} */
  const lastTsByIdentityBucket = new Map();
  /** @type {Record<string, number>} */
  const byDayPlatform = {};
  /** @type {Record<string, number>} */
  const byDayPlatformEntry = {};
  /** @type {Record<string, number>} */
  const byEntry = {};
  let total = 0;

  for (const r of rows) {
    const d = String(r.event_date || '');
    const p = String(r.platform || '__unknown__');
    const entry = r.entry_position != null && String(r.entry_position).trim() !== ''
      ? String(r.entry_position)
      : '__all__';
    const id = r.identity_key != null ? String(r.identity_key) : '';
    const ts = Date.parse(String(r.occurred_at || ''));
    if (!d || !id || Number.isNaN(ts)) continue;

    const dedupKey = `${id}\0${p}\0${entry}`;
    const prev = lastTsByIdentityBucket.get(dedupKey);
    if (prev != null && ts - prev <= UPLOAD_CLICK_DEDUP_MS) {
      continue;
    }
    lastTsByIdentityBucket.set(dedupKey, ts);

    total += 1;
    const kDayPlatform = `${d}\0${p}`;
    const kDayPlatformEntry = `${d}\0${p}\0${entry}`;
    byDayPlatform[kDayPlatform] = (byDayPlatform[kDayPlatform] || 0) + 1;
    byDayPlatformEntry[kDayPlatformEntry] = (byDayPlatformEntry[kDayPlatformEntry] || 0) + 1;
    if (entry !== '__all__') {
      byEntry[entry] = (byEntry[entry] || 0) + 1;
    }
  }

  return {
    total,
    byDayPlatform,
    byDayPlatformEntry,
    byEntry,
  };
}

/**
 * Collection 口径补齐：窗口内访问次数、访问UV、解锁次数、解锁用户数。
 * @param {import('@supabase/supabase-js').SupabaseClient} supabaseAdmin
 * @param {{ utc_date_from: string, utc_date_to: string, platform: string | null }} filter
 */
async function computeCollectionFlatExtras(supabaseAdmin, filter) {
  const rows = await fetchAllPaged(supabaseAdmin, () => {
    let q = supabaseAdmin
      .from('analytics_event_flat_v')
      .select('event_date, platform, event_type, identity_key')
      .in('event_type', ['species_unlock', 'collection_view', 'species_detail_view'])
      .gte('event_date', filter.utc_date_from)
      .lte('event_date', filter.utc_date_to);
    if (filter.platform) q = q.eq('platform', filter.platform);
    return q;
  });

  let collection_view_count = 0;
  let species_detail_view_count = 0;
  let species_unlock_count = 0;
  const collectionUv = new Set();
  const detailUv = new Set();
  const unlockUv = new Set();
  /** @type {Record<string, number>} */
  const unlockCountByDayPlatform = {};

  for (const r of rows) {
    const t = String(r.event_type || '');
    const id = r.identity_key != null ? String(r.identity_key) : '';
    const d = String(r.event_date || '');
    const p = String(r.platform || '__unknown__');
    if (t === 'collection_view') {
      collection_view_count += 1;
      if (id) collectionUv.add(id);
    } else if (t === 'species_detail_view') {
      species_detail_view_count += 1;
      if (id) detailUv.add(id);
    } else if (t === 'species_unlock') {
      species_unlock_count += 1;
      if (id) unlockUv.add(id);
      if (d) {
        const k = `${d}\0${p}`;
        unlockCountByDayPlatform[k] = (unlockCountByDayPlatform[k] || 0) + 1;
      }
    }
  }

  return {
    collection_view_count,
    species_detail_view_count,
    species_unlock_count,
    collection_view_uv: collectionUv.size,
    species_detail_view_uv: detailUv.size,
    species_unlock_user_uv: unlockUv.size,
    unlockCountByDayPlatform,
  };
}

/**
 * AI 请求口径：基于 request_id 去重统计发起/成功/失败请求数。
 * @param {import('@supabase/supabase-js').SupabaseClient} supabaseAdmin
 * @param {{ utc_date_from: string, utc_date_to: string, platform: string | null }} filter
 */
async function computeAiDedupRequestMetrics(supabaseAdmin, filter) {
  const rows = await fetchAllPaged(supabaseAdmin, () => {
    let q = supabaseAdmin
      .from('analytics_event_flat_v')
      .select('event_date, platform, event_type, request_id, identity_key')
      .in('event_type', AI_EVENTS)
      .not('request_id', 'is', null)
      .gte('event_date', filter.utc_date_from)
      .lte('event_date', filter.utc_date_to);
    if (filter.platform) q = q.eq('platform', filter.platform);
    return q;
  });

  const start = new Set();
  const success = new Set();
  const fail = new Set();
  const successUsers = new Set();
  /** @type {Map<string, Set<string>>} */
  const startByDayPlatform = new Map();
  /** @type {Map<string, Set<string>>} */
  const successByDayPlatform = new Map();
  /** @type {Map<string, Set<string>>} */
  const failByDayPlatform = new Map();

  for (const r of rows) {
    const req = r.request_id != null ? String(r.request_id).trim() : '';
    if (!req) continue;
    const type = String(r.event_type || '');
    const day = String(r.event_date || '');
    const platform = String(r.platform || '__unknown__');
    const k = `${day}\0${platform}`;
    if (type === 'ai_identify_start') {
      start.add(req);
      if (!startByDayPlatform.has(k)) startByDayPlatform.set(k, new Set());
      startByDayPlatform.get(k).add(req);
    } else if (type === 'ai_identify_result') {
      success.add(req);
      if (r.identity_key != null && String(r.identity_key).trim() !== '') {
        successUsers.add(String(r.identity_key).trim());
      }
      if (!successByDayPlatform.has(k)) successByDayPlatform.set(k, new Set());
      successByDayPlatform.get(k).add(req);
    } else if (type === 'ai_identify_fail') {
      fail.add(req);
      if (!failByDayPlatform.has(k)) failByDayPlatform.set(k, new Set());
      failByDayPlatform.get(k).add(req);
    }
  }

  /** @type {Record<string, number>} */
  const startDaily = {};
  /** @type {Record<string, number>} */
  const successDaily = {};
  /** @type {Record<string, number>} */
  const failDaily = {};
  for (const [k, v] of startByDayPlatform.entries()) startDaily[k] = v.size;
  for (const [k, v] of successByDayPlatform.entries()) successDaily[k] = v.size;
  for (const [k, v] of failByDayPlatform.entries()) failDaily[k] = v.size;

  return {
    start_count: start.size,
    success_count: success.size,
    fail_count: fail.size,
    success_user_uv: successUsers.size,
    startDaily,
    successDaily,
    failDaily,
  };
}

/**
 * 上传成功：平均耗时、成功人数（identity 去重）；上传点击人数。
 * @param {import('@supabase/supabase-js').SupabaseClient} supabaseAdmin
 * @param {{ utc_date_from: string, utc_date_to: string, platform: string | null, entry_position: string | null }} filter
 */
async function computeUploadFlatExtras(supabaseAdmin, filter) {
  const successRows = await fetchAllPaged(supabaseAdmin, () => {
    let q = supabaseAdmin
      .from('analytics_event_flat_v')
      .select('upload_duration_ms, identity_key')
      .eq('event_type', 'upload_success')
      .gte('event_date', filter.utc_date_from)
      .lte('event_date', filter.utc_date_to);
    if (filter.platform) q = q.eq('platform', filter.platform);
    if (filter.entry_position) q = q.eq('entry_position', filter.entry_position);
    return q;
  });
  const durs = [];
  const succUv = new Set();
  for (const r of successRows) {
    if (r.identity_key) succUv.add(String(r.identity_key));
    const ms = n(r.upload_duration_ms);
    if (ms > 0) durs.push(ms);
  }
  const clickRows = await fetchAllPaged(supabaseAdmin, () => {
    let q = supabaseAdmin
      .from('analytics_event_flat_v')
      .select('identity_key')
      .eq('event_type', 'upload_click')
      .gte('event_date', filter.utc_date_from)
      .lte('event_date', filter.utc_date_to);
    if (filter.platform) q = q.eq('platform', filter.platform);
    if (filter.entry_position) q = q.eq('entry_position', filter.entry_position);
    return q;
  });
  const clickUv = new Set();
  for (const r of clickRows) {
    if (r.identity_key) clickUv.add(String(r.identity_key));
  }
  return {
    upload_success_uv: succUv.size,
    upload_click_uv: clickUv.size,
    upload_avg_duration_ms: durs.length === 0 ? null : durs.reduce((a, b) => a + b, 0) / durs.length,
  };
}

/**
 * AI：失败原因分布、平均延迟（result+fail）、平均 confidence（读原始 properties）。
 * @param {import('@supabase/supabase-js').SupabaseClient} supabaseAdmin
 * @param {{ utc_date_from: string, utc_date_to: string, platform: string | null, occurred_at_from: string, occurred_at_to: string }} filter
 */
async function computeAiFlatExtras(supabaseAdmin, filter) {
  const failRows = await fetchAllPaged(supabaseAdmin, () => {
    let q = supabaseAdmin
      .from('analytics_event_flat_v')
      .select('error_code')
      .eq('event_type', 'ai_identify_fail')
      .gte('event_date', filter.utc_date_from)
      .lte('event_date', filter.utc_date_to);
    if (filter.platform) q = q.eq('platform', filter.platform);
    return q;
  });
  /** @type {Record<string, number>} */
  const fail_reason_breakdown = {};
  for (const r of failRows) {
    const c =
      r.error_code != null && String(r.error_code).trim() !== ''
        ? String(r.error_code)
        : 'unknown';
    fail_reason_breakdown[c] = (fail_reason_breakdown[c] || 0) + 1;
  }

  const latRows = await fetchAllPaged(supabaseAdmin, () => {
    let q = supabaseAdmin
      .from('analytics_event_flat_v')
      .select('latency_ms')
      .in('event_type', ['ai_identify_result', 'ai_identify_fail'])
      .gte('event_date', filter.utc_date_from)
      .lte('event_date', filter.utc_date_to)
      .not('latency_ms', 'is', null);
    if (filter.platform) q = q.eq('platform', filter.platform);
    return q;
  });
  const lats = latRows.map((r) => n(r.latency_ms)).filter((x) => x > 0);
  const identify_latency_avg_ms = lats.length === 0 ? null : lats.reduce((a, b) => a + b, 0) / lats.length;

  const resultEvents = await fetchAllPaged(supabaseAdmin, () => {
    let q = supabaseAdmin
      .from('analytics_events')
      .select('properties')
      .eq('event_type', 'ai_identify_result')
      .gte('occurred_at', filter.occurred_at_from)
      .lte('occurred_at', filter.occurred_at_to);
    return q;
  });
  const confVals = [];
  for (const r of resultEvents) {
    const props = r.properties && typeof r.properties === 'object' ? r.properties : {};
    if (filter.platform) {
      const pl = props.platform != null ? String(props.platform) : '';
      if (pl !== filter.platform) continue;
    }
    const raw = props.confidence;
    if (raw == null) continue;
    const x = Number(raw);
    if (Number.isFinite(x)) confVals.push(x);
  }
  const identify_confidence_avg = confVals.length === 0 ? null : confVals.reduce((a, b) => a + b, 0) / confVals.length;

  return {
    fail_reason_breakdown,
    identify_latency_avg_ms,
    identify_confidence_avg,
  };
}

/**
 * 在链式查询上追加 event_date 闭区间与可选 platform 条件。
 * @param {import('@supabase/supabase-js').SupabaseClient} supabase
 * @param {string} table
 * @param {{ utc_date_from: string, utc_date_to: string, platform: string | null }} filter
 */
function baseRangeQuery(supabase, table, filter) {
  let q = supabase
    .from(table)
    .select('*')
    .gte('event_date', filter.utc_date_from)
    .lte('event_date', filter.utc_date_to)
    .order('event_date', { ascending: true })
    .order('platform', { ascending: true });
  if (filter.platform) {
    q = q.eq('platform', filter.platform);
  }
  return q;
}

/**
 * Overview：analytics_overview_daily_v + 窗口内 distinct UV 函数。
 * @param {import('@supabase/supabase-js').SupabaseClient} supabaseAdmin
 * @param {{ utc_date_from: string, utc_date_to: string, platform: string | null }} filter
 */
async function fetchOverviewAggregate(supabaseAdmin, filter) {
  const { data: rows, error } = await baseRangeQuery(
    supabaseAdmin,
    'analytics_overview_daily_v',
    filter
  );
  if (error) throw new Error(error.message || String(error));

  const list = rows || [];

  const dauMetrics = await computeAppLaunchDauMetrics(supabaseAdmin, filter);
  const clickDedup = await computeUploadClickDedupMetrics(supabaseAdmin, {
    ...filter,
    entry_position: null,
  });
  const uploadExtras = await computeUploadFlatExtras(supabaseAdmin, {
    ...filter,
    entry_position: null,
  });
  const collectionExtras = await computeCollectionFlatExtras(supabaseAdmin, filter);
  const aiDedup = await computeAiDedupRequestMetrics(supabaseAdmin, filter);

  let appLaunch = 0;
  let uploadClick = 0;
  let uploadSuccess = 0;
  let aiStart = 0;
  let aiResult = 0;
  let aiFail = 0;
  let collectionView = 0;

  for (const r of list) {
    appLaunch += n(r.app_launch_count);
    const k = `${r.event_date}\0${r.platform}`;
    uploadClick += clickDedup.byDayPlatform[k] || 0;
    uploadSuccess += n(r.upload_success_count);
    aiStart += n(r.ai_identify_start_count);
    aiResult += n(r.ai_identify_result_count);
    aiFail += n(r.ai_identify_fail_count);
    collectionView += n(r.collection_view_count);
  }

  const upload_conversion_rate = uploadClick === 0 ? 0 : uploadSuccess / uploadClick;
  const identify_success_rate = aiStart === 0 ? 0 : aiResult / aiStart;
  const identify_fail_rate = aiStart === 0 ? 0 : aiFail / aiStart;

  return {
    summary: {
      app_launch_count: appLaunch,
      app_launch_uv: dauMetrics.window_app_launch_uv,
      upload_click_count: uploadClick,
      upload_success_count: uploadSuccess,
      upload_click_uv: n(uploadExtras.upload_click_uv),
      upload_success_uv: n(uploadExtras.upload_success_uv),
      ai_identify_start_count: aiStart,
      ai_identify_result_count: aiResult,
      ai_identify_success_request_count: n(aiDedup.success_count),
      ai_identify_success_uv: n(aiDedup.success_user_uv),
      ai_identify_fail_count: aiFail,
      collection_view_count: collectionView,
      species_unlock_count: n(collectionExtras.species_unlock_count),
      species_unlock_user_uv: n(collectionExtras.species_unlock_user_uv),
      collection_view_uv: n(collectionExtras.collection_view_uv),
      // DAU 口径：窗口结束日（utc_date_to）触发 app_launch 的去重用户数。
      active_users_uv: dauMetrics.summary_dau,
      upload_success_rate: upload_conversion_rate,
      upload_conversion_rate: upload_conversion_rate,
      identify_success_rate,
      identify_fail_rate,
    },
    daily: list.map((r) => ({
      event_date: r.event_date,
      platform: r.platform,
      app_launch_count: n(r.app_launch_count),
      upload_click_count: clickDedup.byDayPlatform[`${r.event_date}\0${r.platform}`] || 0,
      upload_success_count: n(r.upload_success_count),
      ai_identify_start_count: n(r.ai_identify_start_count),
      ai_identify_result_count: n(r.ai_identify_result_count),
      ai_identify_fail_count: n(r.ai_identify_fail_count),
      collection_view_count: n(r.collection_view_count),
      species_unlock_count:
        collectionExtras.unlockCountByDayPlatform[`${r.event_date}\0${r.platform}`] || 0,
      // daily 的 DAU：当天 app_launch 去重用户数（按日+平台）。
      active_users_uv: dauMetrics.dauByDayPlatform[`${r.event_date}\0${r.platform}`] || 0,
      // 全平台日 DAU（用于前端按天趋势，不受平台分面重复影响）。
      app_launch_uv_day_global: dauMetrics.dauByDay[`${r.event_date}`] || 0,
      upload_conversion_rate:
        (clickDedup.byDayPlatform[`${r.event_date}\0${r.platform}`] || 0) === 0
          ? 0
          : n(r.upload_success_count) /
            (clickDedup.byDayPlatform[`${r.event_date}\0${r.platform}`] || 0),
      identify_success_rate: nRate(r.identify_success_rate),
      identify_fail_rate: nRate(r.identify_fail_rate),
    })),
  };
}

/**
 * Upload 漏斗：analytics_daily_kpi_v；可选 entry_position_bucket。
 * @param {import('@supabase/supabase-js').SupabaseClient} supabaseAdmin
 * @param {{ utc_date_from: string, utc_date_to: string, platform: string | null, entry_position: string | null }} filter
 */
async function fetchUploadFunnelAggregate(supabaseAdmin, filter) {
  let q = supabaseAdmin
    .from('analytics_daily_kpi_v')
    .select('*')
    .gte('event_date', filter.utc_date_from)
    .lte('event_date', filter.utc_date_to)
    .order('event_date', { ascending: true })
    .order('platform', { ascending: true })
    .order('entry_position_bucket', { ascending: true });

  if (filter.platform) q = q.eq('platform', filter.platform);
  if (filter.entry_position) q = q.eq('entry_position_bucket', filter.entry_position);

  const { data: rows, error } = await q;
  if (error) throw new Error(error.message || String(error));
  const list = rows || [];

  const clickDedup = await computeUploadClickDedupMetrics(supabaseAdmin, filter);
  const entry_position_click_mix = { ...clickDedup.byEntry };

  /** @type {typeof list} */
  let effectiveRows = list;

  // 中文注释：未指定入口时，把同一日、同一平台下各 entry 桶的行按日汇总，避免前端看到碎片化桶。
  if (!filter.entry_position) {
    const merged = new Map();
    for (const r of list) {
      const key = `${r.event_date}\0${r.platform}`;
      if (!merged.has(key)) {
        merged.set(key, {
          event_date: r.event_date,
          platform: r.platform,
          entry_position_bucket: '__rollup__',
          upload_click_count: 0,
          upload_success_count: 0,
          ai_identify_start_count: 0,
          ai_identify_result_count: 0,
          ai_identify_fail_count: 0,
          app_launch_count: 0,
          collection_view_count: 0,
        });
      }
      const m = merged.get(key);
      m.upload_click_count += clickDedup.byDayPlatformEntry[
        `${r.event_date}\0${r.platform}\0${r.entry_position_bucket}`
      ] || 0;
      m.upload_success_count += n(r.upload_success_count);
      m.ai_identify_start_count += n(r.ai_identify_start_count);
      m.ai_identify_result_count += n(r.ai_identify_result_count);
      m.ai_identify_fail_count += n(r.ai_identify_fail_count);
      m.app_launch_count += n(r.app_launch_count);
      m.collection_view_count += n(r.collection_view_count);
    }
    effectiveRows = Array.from(merged.values()).sort((a, b) => {
      const c = String(a.event_date).localeCompare(String(b.event_date));
      if (c !== 0) return c;
      return String(a.platform).localeCompare(String(b.platform));
    });
  }

  let uc = 0;
  let us = 0;
  let ais = 0;
  let air = 0;
  let aif = 0;

  for (const r of effectiveRows) {
    if (filter.entry_position) {
      uc += clickDedup.byDayPlatformEntry[
        `${r.event_date}\0${r.platform}\0${r.entry_position_bucket}`
      ] || 0;
    } else {
      uc += clickDedup.byDayPlatform[`${r.event_date}\0${r.platform}`] || 0;
    }
    us += n(r.upload_success_count);
    ais += n(r.ai_identify_start_count);
    air += n(r.ai_identify_result_count);
    aif += n(r.ai_identify_fail_count);
  }

  /** @type {Record<string, unknown>} */
  let uploadFlatExtras = {};
  try {
    uploadFlatExtras = await computeUploadFlatExtras(supabaseAdmin, filter);
  } catch (e) {
    console.warn('[adminAnalytics] upload flat extras failed', e?.message || e);
  }

  return {
    summary: {
      upload_click_count: uc,
      upload_success_count: us,
      upload_success_rate: uc === 0 ? 0 : us / uc,
      upload_conversion_rate: uc === 0 ? 0 : us / uc,
      funnel: {
        upload_click: uc,
        ai_identify_start: ais,
        upload_success: us,
      },
      identify_success_rate: ais === 0 ? 0 : air / ais,
      identify_fail_rate: ais === 0 ? 0 : aif / ais,
      entry_position_click_mix,
      ...uploadFlatExtras,
    },
    daily: effectiveRows.map((r) => ({
      event_date: r.event_date,
      platform: r.platform,
      entry_position_bucket: r.entry_position_bucket,
      upload_click_count: filter.entry_position
        ? clickDedup.byDayPlatformEntry[`${r.event_date}\0${r.platform}\0${r.entry_position_bucket}`] || 0
        : clickDedup.byDayPlatform[`${r.event_date}\0${r.platform}`] || 0,
      upload_success_count: n(r.upload_success_count),
      upload_conversion_rate:
        (filter.entry_position
          ? clickDedup.byDayPlatformEntry[`${r.event_date}\0${r.platform}\0${r.entry_position_bucket}`] || 0
          : clickDedup.byDayPlatform[`${r.event_date}\0${r.platform}`] || 0) === 0
          ? 0
          : n(r.upload_success_count) /
            (filter.entry_position
              ? clickDedup.byDayPlatformEntry[`${r.event_date}\0${r.platform}\0${r.entry_position_bucket}`] || 0
              : clickDedup.byDayPlatform[`${r.event_date}\0${r.platform}`] || 0),
      ai_identify_start_count: n(r.ai_identify_start_count),
      ai_identify_result_count: n(r.ai_identify_result_count),
      ai_identify_fail_count: n(r.ai_identify_fail_count),
    })),
  };
}

/**
 * AI Identify：analytics_ai_daily_v。
 * @param {import('@supabase/supabase-js').SupabaseClient} supabaseAdmin
 * @param {{ utc_date_from: string, utc_date_to: string, platform: string | null }} filter
 */
async function fetchAiIdentifyAggregate(supabaseAdmin, filter) {
  const { data: rows, error } = await baseRangeQuery(
    supabaseAdmin,
    'analytics_ai_daily_v',
    filter
  );
  if (error) throw new Error(error.message || String(error));
  const list = rows || [];

  const aiDedup = await computeAiDedupRequestMetrics(supabaseAdmin, filter);
  const starts = n(aiDedup.start_count);
  const results = n(aiDedup.success_count);
  const fails = n(aiDedup.fail_count);

  // 中文注释：整窗 dedup 必须 count(distinct request_id)，禁止对 daily 的 dedup_request_count 求和。
  const { data: dedupRaw, error: dedupErr } = await supabaseAdmin.rpc(
    'admin_analytics_ai_dedup_request_count_window',
    {
      p_from: filter.utc_date_from,
      p_to: filter.utc_date_to,
      p_platform: filter.platform || null,
    }
  );
  if (dedupErr) throw new Error(dedupErr.message || String(dedupErr));

  /** @type {Record<string, unknown>} */
  let aiFlatExtras = {};
  try {
    aiFlatExtras = await computeAiFlatExtras(supabaseAdmin, filter);
  } catch (e) {
    console.warn('[adminAnalytics] ai flat extras failed', e?.message || e);
  }

  return {
    summary: {
      identify_start_count: starts,
      identify_result_count: results,
      identify_fail_count: fails,
      dedup_request_count: n(dedupRaw) || starts,
      identify_success_rate: starts === 0 ? 0 : results / starts,
      identify_fail_rate: starts === 0 ? 0 : fails / starts,
      ...aiFlatExtras,
    },
    daily: list.map((r) => ({
      event_date: r.event_date,
      platform: r.platform,
      identify_start_count: aiDedup.startDaily[`${r.event_date}\0${r.platform}`] || 0,
      identify_result_count:
        aiDedup.successDaily[`${r.event_date}\0${r.platform}`] || 0,
      identify_fail_count: aiDedup.failDaily[`${r.event_date}\0${r.platform}`] || 0,
      // 中文注释：按日+平台维度的 dedup，仅用于趋势/分面；整窗 KPI 请用 summary.dedup_request_count。
      dedup_request_count: n(r.dedup_request_count),
      identify_latency_p50_ms: r.identify_latency_p50_ms != null ? n(r.identify_latency_p50_ms) : null,
      identify_latency_p95_ms: r.identify_latency_p95_ms != null ? n(r.identify_latency_p95_ms) : null,
    })),
  };
}

/**
 * Collection：analytics_collection_daily_v。
 * @param {import('@supabase/supabase-js').SupabaseClient} supabaseAdmin
 * @param {{ utc_date_from: string, utc_date_to: string, platform: string | null }} filter
 */
async function fetchCollectionGrowthAggregate(supabaseAdmin, filter) {
  const { data: rows, error } = await baseRangeQuery(
    supabaseAdmin,
    'analytics_collection_daily_v',
    filter
  );
  if (error) throw new Error(error.message || String(error));
  const list = rows || [];

  const collectionExtras = await computeCollectionFlatExtras(supabaseAdmin, filter);
  let unlocks = n(collectionExtras.species_unlock_count);

  // 中文注释：整窗 UV 必须 count(distinct identity_key) 跨日一次算清，禁止对 daily 的 UV 列求和。
  const { data: uvPayload, error: uvErr } = await supabaseAdmin.rpc(
    'admin_analytics_collection_uv_window',
    {
      p_from: filter.utc_date_from,
      p_to: filter.utc_date_to,
      p_platform: filter.platform || null,
    }
  );
  if (uvErr) throw new Error(uvErr.message || String(uvErr));

  /** @type {Record<string, unknown>} */
  let uvObj = {};
  if (typeof uvPayload === 'string') {
    try {
      uvObj = JSON.parse(uvPayload);
    } catch {
      uvObj = {};
    }
  } else if (uvPayload && typeof uvPayload === 'object' && !Array.isArray(uvPayload)) {
    uvObj = uvPayload;
  }

  return {
    summary: {
      species_unlock_count: unlocks,
      species_unlock_user_uv: n(collectionExtras.species_unlock_user_uv),
      collection_view_uv: n(uvObj.collection_view_uv),
      species_detail_view_uv: n(uvObj.species_detail_view_uv),
      collection_view_count: n(collectionExtras.collection_view_count),
      species_detail_view_count: n(collectionExtras.species_detail_view_count),
    },
    daily: list.map((r) => ({
      event_date: r.event_date,
      platform: r.platform,
      species_unlock_count: n(r.species_unlock_count),
      // 中文注释：单日+平台 UV，用于折线/分面；整窗 KPI 请用 summary 中两项 UV。
      collection_view_uv: n(r.collection_view_uv),
      species_detail_view_uv: n(r.species_detail_view_uv),
      unlock_to_detail_conversion_rate: nRate(r.unlock_to_detail_conversion_rate),
    })),
  };
}

module.exports = {
  fetchOverviewAggregate,
  fetchUploadFunnelAggregate,
  fetchAiIdentifyAggregate,
  fetchCollectionGrowthAggregate,
};
