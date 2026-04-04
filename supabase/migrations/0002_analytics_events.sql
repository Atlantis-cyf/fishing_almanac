-- Minimal analytics event store for retention + funnel + feature usage metrics.
-- Run: npm run migrate:analytics (from backend/) or supabase db push or SQL editor.

create extension if not exists pgcrypto;

create table if not exists public.analytics_events (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users (id) on delete cascade,
  anon_id text,
  session_id text,
  event_type text not null,
  occurred_at timestamptz not null default now(),
  properties jsonb not null default '{}'::jsonb
);

create index if not exists analytics_events_event_type_time_idx
  on public.analytics_events (event_type, occurred_at desc);

create index if not exists analytics_events_user_time_idx
  on public.analytics_events (user_id, occurred_at desc);

create index if not exists analytics_events_anon_time_idx
  on public.analytics_events (anon_id, occurred_at desc);

-- BFF uses service role (bypasses RLS). Lock down direct client access.
alter table public.analytics_events enable row level security;

