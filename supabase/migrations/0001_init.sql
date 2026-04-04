-- Minimal schema to make fishing_almanac front-end APIs work.
-- Run: supabase db push (or execute in Supabase SQL editor).

create extension if not exists pgcrypto;

-- User display name cache / profile.
create table if not exists public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  display_name text
);

-- Fish catches timeline records.
create table if not exists public.catches (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,

  species_zh text not null,
  notes text not null default '',
  weight_kg numeric not null default 0,
  length_cm numeric not null default 0,
  location_label text not null default '',
  lat double precision,
  lng double precision,

  occurred_at timestamptz not null,
  occurred_at_ms bigint not null,

  review_status text not null default 'approved'
    check (review_status in ('pending_review', 'rejected', 'approved')),

  -- Keep least setup: store base64 in DB (no Storage bucket needed).
  image_base64 text,
  image_url text
);

create index if not exists catches_review_species_time_idx
  on public.catches (review_status, species_zh, occurred_at_ms desc, id desc);

