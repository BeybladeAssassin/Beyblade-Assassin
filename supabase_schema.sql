-- 陀螺刺客賽程系統 V1：新增專用 ta_ 資料表，先檢查再執行。
-- 此 SQL 不會自動改動現有資料表。前端 index.html 目前是本機示範版，尚未連線。
create extension if not exists pgcrypto;
create table if not exists public.ta_events (
 id uuid primary key default gen_random_uuid(), name text not null, event_date date,
 venue_count integer not null default 1 check (venue_count between 1 and 30),
 zone_count integer not null check (zone_count in (1,2,3)),
 status text not null default 'draft' check (status in ('draft','published','finished')),
 is_public boolean not null default false, created_by uuid not null references auth.users(id) on delete restrict,
 created_at timestamptz not null default now()
);
create table if not exists public.ta_players (
 id uuid primary key default gen_random_uuid(), event_id uuid not null references public.ta_events(id) on delete cascade,
 name text not null, player_number text not null, zone text not null check (zone in ('A','B','C')),
 seed integer, created_at timestamptz not null default now(), unique(event_id, player_number)
);
create table if not exists public.ta_matches (
 id uuid primary key default gen_random_uuid(), event_id uuid not null references public.ta_events(id) on delete cascade,
 zone text not null check (zone in ('A','B','C','FINAL')), round_number integer not null check (round_number>=1),
 round_name text not null, match_number integer not null, venue_code text not null,
 player1_id uuid references public.ta_players(id) on delete set null,
 player2_id uuid references public.ta_players(id) on delete set null,
 winner_id uuid references public.ta_players(id) on delete set null,
 score1 integer check (score1 is null or score1>=0), score2 integer check (score2 is null or score2>=0),
 status text not null default 'pending' check (status in ('pending','live','completed','bye')),
 next_match_id uuid references public.ta_matches(id) on delete set null, next_slot smallint check (next_slot in (1,2)),
 created_at timestamptz not null default now(), unique(event_id,match_number)
);
create table if not exists public.ta_admins (
 user_id uuid primary key references auth.users(id) on delete cascade, created_at timestamptz not null default now()
);
create index if not exists ta_events_public_idx on public.ta_events(is_public,status);
create index if not exists ta_players_event_idx on public.ta_players(event_id);
create index if not exists ta_matches_event_idx on public.ta_matches(event_id,match_number);
create or replace function public.ta_is_admin() returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.ta_admins a where a.user_id=(select auth.uid()));
$$;
revoke all on function public.ta_is_admin() from public;
grant execute on function public.ta_is_admin() to anon,authenticated;
alter table public.ta_events enable row level security;
alter table public.ta_players enable row level security;
alter table public.ta_matches enable row level security;
alter table public.ta_admins enable row level security;
drop policy if exists "ta_public_reads_events" on public.ta_events;
create policy "ta_public_reads_events" on public.ta_events for select to anon,authenticated using (is_public=true or public.ta_is_admin());
drop policy if exists "ta_admins_manage_events" on public.ta_events;
create policy "ta_admins_manage_events" on public.ta_events for all to authenticated using (public.ta_is_admin()) with check (public.ta_is_admin());
drop policy if exists "ta_public_reads_players" on public.ta_players;
create policy "ta_public_reads_players" on public.ta_players for select to anon,authenticated using (public.ta_is_admin() or exists(select 1 from public.ta_events e where e.id=event_id and e.is_public=true));
drop policy if exists "ta_admins_manage_players" on public.ta_players;
create policy "ta_admins_manage_players" on public.ta_players for all to authenticated using (public.ta_is_admin()) with check (public.ta_is_admin());
drop policy if exists "ta_public_reads_matches" on public.ta_matches;
create policy "ta_public_reads_matches" on public.ta_matches for select to anon,authenticated using (public.ta_is_admin() or exists(select 1 from public.ta_events e where e.id=event_id and e.is_public=true));
drop policy if exists "ta_admins_manage_matches" on public.ta_matches;
create policy "ta_admins_manage_matches" on public.ta_matches for all to authenticated using (public.ta_is_admin()) with check (public.ta_is_admin());
drop policy if exists "ta_admins_read_admins" on public.ta_admins;
create policy "ta_admins_read_admins" on public.ta_admins for select to authenticated using (public.ta_is_admin());
-- 建立管理員：先在 Supabase Auth 建使用者，取得 UID 後執行：
-- insert into public.ta_admins(user_id) values ('替換成真實的-auth-user-uuid');
-- 選手編號為每場賽事內唯一編號（例如 001、002），正式查詢可用姓名＋選手編號。
