-- Overview 专用：仅按 event_date + platform 聚合，不按 entry 分桶。
-- 中文注释：避免把 analytics_daily_kpi_v 多桶行的 active_users_uv 简单相加导致重复计数。

create or replace view public.analytics_overview_daily_v as
select
  f.event_date,
  f.platform,
  count(*) filter (where f.event_type = 'app_launch') as app_launch_count,
  count(*) filter (where f.event_type = 'upload_click') as upload_click_count,
  count(*) filter (where f.event_type = 'upload_success') as upload_success_count,
  count(*) filter (where f.event_type = 'ai_identify_start') as ai_identify_start_count,
  count(*) filter (where f.event_type = 'ai_identify_result') as ai_identify_result_count,
  count(*) filter (where f.event_type = 'ai_identify_fail') as ai_identify_fail_count,
  count(*) filter (where f.event_type = 'collection_view') as collection_view_count,
  count(distinct f.identity_key) filter (
    where f.event_type in ('app_launch', 'home_view', 'upload_click', 'upload_success', 'collection_view')
  ) as active_users_uv,
  case
    when count(*) filter (where f.event_type = 'upload_click') = 0 then 0::numeric
    else count(*) filter (where f.event_type = 'upload_success')::numeric
      / count(*) filter (where f.event_type = 'upload_click')
  end as upload_conversion_rate,
  case
    when count(*) filter (where f.event_type = 'ai_identify_start') = 0 then 0::numeric
    else count(*) filter (where f.event_type = 'ai_identify_result')::numeric
      / count(*) filter (where f.event_type = 'ai_identify_start')
  end as identify_success_rate,
  case
    when count(*) filter (where f.event_type = 'ai_identify_start') = 0 then 0::numeric
    else count(*) filter (where f.event_type = 'ai_identify_fail')::numeric
      / count(*) filter (where f.event_type = 'ai_identify_start')
  end as identify_fail_rate
from public.analytics_event_flat_v f
group by f.event_date, f.platform;

comment on view public.analytics_overview_daily_v is
'Overview 日趋势：按日+平台聚合，UV 口径正确。';

-- 中文注释：跨日窗口内的活跃 UV 不能对「每日 UV」求和，用单次 count(distinct) 保证口径。
create or replace function public.admin_analytics_active_uv(
  p_from date,
  p_to date,
  p_platform text default null
) returns bigint
language sql
stable
security definer
set search_path = public
as $$
  select count(distinct identity_key)::bigint
  from public.analytics_event_flat_v
  where event_date between p_from and p_to
    and event_type in ('app_launch', 'home_view', 'upload_click', 'upload_success', 'collection_view')
    and (p_platform is null or p_platform = '' or platform = p_platform);
$$;

comment on function public.admin_analytics_active_uv(date, date, text) is
'BFF 专用：查询时间窗口内活跃 UV（与合同 identity_key 口径一致）。';

revoke all on function public.admin_analytics_active_uv(date, date, text) from public;
grant execute on function public.admin_analytics_active_uv(date, date, text) to service_role;
