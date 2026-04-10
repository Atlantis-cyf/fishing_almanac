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

  const { data: uvRaw, error: uvErr } = await supabaseAdmin.rpc('admin_analytics_active_uv', {
    p_from: filter.utc_date_from,
    p_to: filter.utc_date_to,
    p_platform: filter.platform || null,
  });
  if (uvErr) throw new Error(uvErr.message || String(uvErr));

  let appLaunch = 0;
  let uploadClick = 0;
  let uploadSuccess = 0;
  let aiStart = 0;
  let aiResult = 0;
  let aiFail = 0;
  let collectionView = 0;

  for (const r of list) {
    appLaunch += n(r.app_launch_count);
    uploadClick += n(r.upload_click_count);
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
      upload_click_count: uploadClick,
      upload_success_count: uploadSuccess,
      ai_identify_start_count: aiStart,
      ai_identify_result_count: aiResult,
      ai_identify_fail_count: aiFail,
      collection_view_count: collectionView,
      active_users_uv: n(uvRaw),
      upload_conversion_rate,
      identify_success_rate,
      identify_fail_rate,
    },
    daily: list.map((r) => ({
      event_date: r.event_date,
      platform: r.platform,
      app_launch_count: n(r.app_launch_count),
      upload_click_count: n(r.upload_click_count),
      upload_success_count: n(r.upload_success_count),
      ai_identify_start_count: n(r.ai_identify_start_count),
      ai_identify_result_count: n(r.ai_identify_result_count),
      ai_identify_fail_count: n(r.ai_identify_fail_count),
      collection_view_count: n(r.collection_view_count),
      active_users_uv: n(r.active_users_uv),
      upload_conversion_rate: nRate(r.upload_conversion_rate),
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
      m.upload_click_count += n(r.upload_click_count);
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
    uc += n(r.upload_click_count);
    us += n(r.upload_success_count);
    ais += n(r.ai_identify_start_count);
    air += n(r.ai_identify_result_count);
    aif += n(r.ai_identify_fail_count);
  }

  return {
    summary: {
      upload_click_count: uc,
      upload_success_count: us,
      upload_conversion_rate: uc === 0 ? 0 : us / uc,
      funnel: {
        upload_click: uc,
        ai_identify_start: ais,
        upload_success: us,
      },
      identify_success_rate: ais === 0 ? 0 : air / ais,
      identify_fail_rate: ais === 0 ? 0 : aif / ais,
    },
    daily: effectiveRows.map((r) => ({
      event_date: r.event_date,
      platform: r.platform,
      entry_position_bucket: r.entry_position_bucket,
      upload_click_count: n(r.upload_click_count),
      upload_success_count: n(r.upload_success_count),
      upload_conversion_rate:
        n(r.upload_click_count) === 0 ? 0 : n(r.upload_success_count) / n(r.upload_click_count),
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

  let starts = 0;
  let results = 0;
  let fails = 0;

  for (const r of list) {
    starts += n(r.identify_start_count);
    results += n(r.identify_result_count);
    fails += n(r.identify_fail_count);
  }

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

  return {
    summary: {
      identify_start_count: starts,
      identify_result_count: results,
      identify_fail_count: fails,
      dedup_request_count: n(dedupRaw),
      identify_success_rate: starts === 0 ? 0 : results / starts,
      identify_fail_rate: starts === 0 ? 0 : fails / starts,
    },
    daily: list.map((r) => ({
      event_date: r.event_date,
      platform: r.platform,
      identify_start_count: n(r.identify_start_count),
      identify_result_count: n(r.identify_result_count),
      identify_fail_count: n(r.identify_fail_count),
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

  let unlocks = 0;
  for (const r of list) {
    unlocks += n(r.species_unlock_count);
  }

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
      collection_view_uv: n(uvObj.collection_view_uv),
      species_detail_view_uv: n(uvObj.species_detail_view_uv),
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
