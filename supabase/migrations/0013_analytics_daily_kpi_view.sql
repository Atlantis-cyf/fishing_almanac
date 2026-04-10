-- Step 2 / 3: 建立通用日聚合层（核心 KPI 稳定输出）
-- 目标：基于 analytics_event_flat_v 输出 Overview / Upload 可复用的核心指标。

create or replace view public.analytics_daily_kpi_v as
with agg as (
  select
    f.event_date,
    f.platform,
    -- 中文注释：entry_position 为空时汇总到 __all__，便于“全入口”和“按入口”复用同一视图。
    coalesce(f.entry_position, '__all__') as entry_position_bucket,

    count(*) filter (where f.event_type = 'app_launch') as app_launch_count,
    count(*) filter (where f.event_type = 'upload_click') as upload_click_count,
    count(*) filter (where f.event_type = 'upload_success') as upload_success_count,
    count(*) filter (where f.event_type = 'ai_identify_start') as ai_identify_start_count,
    count(*) filter (where f.event_type = 'ai_identify_result') as ai_identify_result_count,
    count(*) filter (where f.event_type = 'ai_identify_fail') as ai_identify_fail_count,
    count(*) filter (where f.event_type = 'collection_view') as collection_view_count,

    -- 中文注释：active_users_uv 口径与合同一致，统一按 identity_key 去重。
    count(distinct f.identity_key) filter (
      where f.event_type in ('app_launch', 'home_view', 'upload_click', 'upload_success', 'collection_view')
    ) as active_users_uv
  from public.analytics_event_flat_v f
  group by
    f.event_date,
    f.platform,
    coalesce(f.entry_position, '__all__')
)
select
  a.event_date,
  a.platform,
  a.entry_position_bucket,

  a.app_launch_count,
  a.upload_click_count,
  a.upload_success_count,
  a.ai_identify_start_count,
  a.ai_identify_result_count,
  a.ai_identify_fail_count,
  a.collection_view_count,
  a.active_users_uv,

  -- 中文注释：分母为 0 时统一返回 0，避免 NaN / Infinity 影响接口稳定性。
  case
    when a.upload_click_count = 0 then 0::numeric
    else a.upload_success_count::numeric / a.upload_click_count
  end as upload_conversion_rate,

  case
    when a.ai_identify_start_count = 0 then 0::numeric
    else a.ai_identify_result_count::numeric / a.ai_identify_start_count
  end as identify_success_rate,

  case
    when a.ai_identify_start_count = 0 then 0::numeric
    else a.ai_identify_fail_count::numeric / a.ai_identify_start_count
  end as identify_fail_rate
from agg a;

comment on view public.analytics_daily_kpi_v is
'Analytics 通用日聚合视图：Overview/Upload 核心 KPI 与趋势基线。';

-- =========================
-- Step 2 验收 SQL（手工执行）
-- =========================
-- 1) 基础可读性（语句成功即通过）
-- select * from public.analytics_daily_kpi_v limit 5;
--
-- 2) 比率列稳定性（不应出现 null / NaN / Infinity）
-- select
--   count(*) filter (where upload_conversion_rate is null) as upload_rate_null_cnt,
--   count(*) filter (where identify_success_rate is null) as identify_success_rate_null_cnt,
--   count(*) filter (where identify_fail_rate is null) as identify_fail_rate_null_cnt
-- from public.analytics_daily_kpi_v;
--
-- 3) 抽样对账（upload_success 原始事件 vs 日聚合求和）
-- select
--   (select count(*) from public.analytics_event_flat_v
--    where event_type = 'upload_success'
--      and event_date between current_date - 7 and current_date - 1) as raw_upload_success,
--   (select coalesce(sum(upload_success_count), 0) from public.analytics_daily_kpi_v
--    where event_date between current_date - 7 and current_date - 1) as kpi_upload_success;
