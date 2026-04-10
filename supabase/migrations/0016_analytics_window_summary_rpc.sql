-- 窗口级 summary 专用 RPC（避免对「按日 UV / 按日 dedup」结果做简单求和导致口径错误）

-- Collection：整窗内按 identity_key 去重（与 analytics_collection_daily_v 单日 UV 口径一致，但跨日合并）
create or replace function public.admin_analytics_collection_uv_window(
  p_from date,
  p_to date,
  p_platform text default null
) returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'collection_view_uv',
      (select count(distinct identity_key)::bigint
       from public.analytics_event_flat_v
       where event_date between p_from and p_to
         and event_type = 'collection_view'
         and (p_platform is null or p_platform = '' or platform = p_platform)),
    'species_detail_view_uv',
      (select count(distinct identity_key)::bigint
       from public.analytics_event_flat_v
       where event_date between p_from and p_to
         and event_type = 'species_detail_view'
         and (p_platform is null or p_platform = '' or platform = p_platform))
  );
$$;

comment on function public.admin_analytics_collection_uv_window(date, date, text) is
'整窗 collection_view / species_detail_view 的 UV（distinct identity_key），禁止用 daily UV 相加替代。';

revoke all on function public.admin_analytics_collection_uv_window(date, date, text) from public;
grant execute on function public.admin_analytics_collection_uv_window(date, date, text) to service_role;

-- AI：整窗内按 request_id 严格去重（与 analytics_ai_daily_v 单日 dedup 范围一致：三类 AI 事件且 request_id 非空）
create or replace function public.admin_analytics_ai_dedup_request_count_window(
  p_from date,
  p_to date,
  p_platform text default null
) returns bigint
language sql
stable
security definer
set search_path = public
as $$
  select count(distinct request_id)::bigint
  from public.analytics_event_flat_v
  where event_date between p_from and p_to
    and event_type in ('ai_identify_start', 'ai_identify_result', 'ai_identify_fail')
    and request_id is not null
    and (p_platform is null or p_platform = '' or platform = p_platform);
$$;

comment on function public.admin_analytics_ai_dedup_request_count_window(date, date, text) is
'整窗 AI 请求 distinct request_id；禁止对按日 dedup_request_count 求和替代。';

revoke all on function public.admin_analytics_ai_dedup_request_count_window(date, date, text) from public;
grant execute on function public.admin_analytics_ai_dedup_request_count_window(date, date, text) to service_role;
