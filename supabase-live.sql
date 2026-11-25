-- CourtFlow live view (QR code / link for players).
-- Run in Supabase > SQL Editor. Safe to run again at any time: it also upgrades older installs.
-- Needs the table from supabase-setup.sql (cf_state) to exist already.

create table if not exists public.cf_live (
  code       text primary key check (code ~ '^[A-Za-z0-9]{8,32}$'),
  user_id    uuid not null references auth.users(id) on delete cascade,
  data       jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);
alter table public.cf_live enable row level security;

-- Upgrade: earlier builds expired links on a timer. Links now live exactly as long as the session is shared.
drop trigger if exists cf_live_touch on public.cf_live;
alter table public.cf_live drop column if exists expires_at;
create or replace function public.cf_live_touch() returns trigger language plpgsql as $$
begin new.updated_at := now(); return new; end $$;
create trigger cf_live_touch before insert or update on public.cf_live
  for each row execute function public.cf_live_touch();

-- Only the organizer (signed in) can create, change or delete their live snapshot.
drop policy if exists "cf_live select own" on public.cf_live;
drop policy if exists "cf_live insert own" on public.cf_live;
drop policy if exists "cf_live update own" on public.cf_live;
drop policy if exists "cf_live delete own" on public.cf_live;
create policy "cf_live select own" on public.cf_live for select to authenticated using (auth.uid() = user_id);
create policy "cf_live insert own" on public.cf_live for insert to authenticated with check (auth.uid() = user_id);
create policy "cf_live update own" on public.cf_live for update to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "cf_live delete own" on public.cf_live for delete to authenticated using (auth.uid() = user_id);

-- Players are not signed in. They can fetch ONE snapshot, only with its secret code.
-- The link works only while the organizer's saved session (cf_state) is still running AND still shares this exact code.
-- So it ends the moment the session is ended, deleted, replaced or sharing is stopped, even if a delete never got through.
-- It does NOT depend on the organizer's phone being online: a lost connection, closed browser or crashed phone changes nothing.
-- There is no way to list or search other sessions.
create or replace function public.get_live(p_code text)
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object('data', l.data, 'updated_at', l.updated_at)
  from public.cf_live l
  join public.cf_state s on s.user_id = l.user_id
  where l.code = p_code and s.data -> 'sess' ->> 'share' = p_code
$$;
revoke all on function public.get_live(text) from public;
grant execute on function public.get_live(text) to anon, authenticated;
