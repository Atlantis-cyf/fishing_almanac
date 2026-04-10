-- Step 3 / 3: 建立专题聚合层 + 回归对账模板
-- 目标：补齐 AI Identify 与 Collection Growth 的专题指标视图，提供可复用查询基线。

-- =========================
-- A) AI Identify 专题日聚合
-- =========================
create or replace view public.analytics_ai_daily_v as
select
  f.event_date,
  f.platform,
  count(*) filter (where f.event_type = 'ai_identify_start') as identify_start_count,
  count(*) filter (where f.event_type = 'ai_identify_result') as identify_result_count,
  count(*) filter (where f.event_type = 'ai_identify_fail') as identify_fail_count,

  -- 中文注释：优先按 request_id 去重统计请求量，减少客户端重试导致的重复放大。
  count(distinct f.request_id) filter (
    where f.event_type in ('ai_identify_start', 'ai_identify_result', 'ai_identify_fail')
      and f.request_id is not null
  ) as dedup_request_count,

  -- 中文注释：P50/P95 延迟口径统一基于 result + fail 的 latency_ms。
  percentile_cont(0.5) within group (order by f.latency_ms) filter (
    where f.event_type in ('ai_identify_result', 'ai_identify_fail')
      and f.latency_ms is not null
  ) as identify_latency_p50_ms,

  percentile_cont(0.95) within group (order by f.latency_ms) filter (
    where f.event_type in ('ai_identify_result', 'ai_identify_fail')
      and f.latency_ms is not null
  ) as identify_latency_p95_ms
from public.analytics_event_flat_v f
group by
  f.event_date,
  f.platform;

comment on view public.analytics_ai_daily_v is
'AI Identify 专题日聚合视图（请求量、成功失败、延迟分位）。';

-- =========================
-- B) Collection Growth 专题日聚合
-- =========================
create or replace view public.analytics_collection_daily_v as
select
  f.event_date,
  f.platform,
  count(*) filter (where f.event_type = 'species_unlock') as species_unlock_count,
  count(distinct f.identity_key) filter (where f.event_type = 'collection_view') as collection_view_uv,
  count(distinct f.identity_key) filter (where f.event_type = 'species_detail_view') as species_detail_view_uv,
  -- 中文注释：解锁到详情访问转化率，分母为 0 时返回 0，保持接口稳定。
  case
    when count(distinct f.identity_key) filter (where f.event_type = 'species_unlock') = 0 then 0::numeric
    else
      (
        count(distinct f.identity_key) filter (where f.event_type = 'species_detail_view')
      )::numeric
      /
      (
        count(distinct f.identity_key) filter (where f.event_type = 'species_unlock')
      )::numeric
  end as unlock_to_detail_conversion_rate
from public.analytics_event_flat_v f
group by
  f.event_date,
  f.platform;

comment on view public.analytics_collection_daily_v is
'Collection Growth 专题日聚合视图（解锁、浏览 UV、详情 UV、转化率）。';

-- =========================
-- Step 3 验收 SQL（手工执行）
-- =========================
-- 1) 基础可读性
-- select * from public.analytics_ai_daily_v limit 5;
-- select * from public.analytics_collection_daily_v limit 5;
--
-- 2) AI 对账（raw vs ai_daily）
-- select
--   (select count(*) from public.analytics_event_flat_v
--    where event_type = 'ai_identify_start'
--      and event_date between current_date - 7 and current_date - 1) as raw_ai_start,
--   (select coalesce(sum(identify_start_count), 0) from public.analytics_ai_daily_v
--    where event_date between current_date - 7 and current_date - 1) as view_ai_start;
--
-- 3) Collection 对账（raw vs collection_daily）
-- select
--   (select count(*) from public.analytics_event_flat_v
--    where event_type = 'species_unlock'
--      and event_date between current_date - 7 and current_date - 1) as raw_species_unlock,
--   (select coalesce(sum(species_unlock_count), 0) from public.analytics_collection_daily_v
--    where event_date between current_date - 7 and current_date - 1) as view_species_unlock;
