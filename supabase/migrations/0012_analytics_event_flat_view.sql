-- Step 1 / 3: 建立查询基线层（标准化明细视图）
-- 目标：把 analytics_events 中常用字段扁平化，并统一空值/类型处理，保证接口查询稳定。

create or replace view public.analytics_event_flat_v as
select
  e.id,
  e.user_id,
  e.anon_id,
  -- 中文注释：UV 去重统一使用 identity_key，优先 user_id，缺失时回退 anon_id。
  coalesce(e.user_id::text, e.anon_id) as identity_key,
  e.session_id,
  e.event_type,
  e.occurred_at,
  -- 中文注释：统一按 UTC 生成日粒度字段，避免跨时区导致按天统计错位。
  (e.occurred_at at time zone 'UTC')::date as event_date,

  -- 中文注释：平台字段统一兜底为 __unknown__，避免 group by 时丢桶。
  coalesce(nullif(e.properties->>'platform', ''), '__unknown__') as platform,
  nullif(e.properties->>'entry_position', '') as entry_position,

  -- 中文注释：AI 识别相关维度字段。
  nullif(e.properties->>'request_id', '') as request_id,
  nullif(e.properties->>'species_name', '') as species_name,
  nullif(e.properties->>'error_code', '') as error_code,

  -- 中文注释：数值字段统一走“正则 + 安全转换”，避免脏数据触发 cast 异常。
  case
    when (e.properties->>'latency_ms') ~ '^\d+(\.\d+)?$' then (e.properties->>'latency_ms')::numeric
    else null
  end as latency_ms,

  case
    when (e.properties->>'upload_duration_ms') ~ '^\d+(\.\d+)?$' then (e.properties->>'upload_duration_ms')::numeric
    else null
  end as upload_duration_ms,

  case
    when (e.properties->>'unlocked_species_count') ~ '^\d+$' then (e.properties->>'unlocked_species_count')::integer
    else null
  end as unlocked_species_count,

  case
    when (e.properties->>'total_species_count') ~ '^\d+$' then (e.properties->>'total_species_count')::integer
    else null
  end as total_species_count,

  -- 中文注释：保留原始 properties，便于后续专题视图扩展时复用。
  e.properties
from public.analytics_events e;

comment on view public.analytics_event_flat_v is
'Analytics 标准化明细视图：统一字段、时间粒度、空值和类型转换规则。';

-- =========================
-- Step 1 验收 SQL（手工执行）
-- =========================
-- 1) 视图可读性检查（应返回 >= 1 行；空库可返回 0 行但语句应成功）
-- select * from public.analytics_event_flat_v limit 1;
--
-- 2) 结构检查（确认关键列存在）
-- select column_name, data_type
-- from information_schema.columns
-- where table_schema = 'public'
--   and table_name = 'analytics_event_flat_v'
-- order by ordinal_position;
--
-- 3) 筛选稳定性检查（time/platform/entry_position/request_id）
-- select count(*) as cnt
-- from public.analytics_event_flat_v
-- where event_date between (current_date - 7) and current_date
--   and platform in ('ios', 'android', '__unknown__');
--
-- select count(*) as cnt
-- from public.analytics_event_flat_v
-- where entry_position is not null;
--
-- select count(*) as cnt
-- from public.analytics_event_flat_v
-- where request_id is not null;
