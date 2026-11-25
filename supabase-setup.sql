-- CourtFlow cloud storage. Paste into Supabase > SQL Editor > Run.
create table if not exists public.cf_state (
  user_id    uuid primary key references auth.users(id) on delete cascade,
  data       jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);

alter table public.cf_state enable row level security;

-- Each signed-in user can only ever see and change their own row.
create policy "cf_state select own" on public.cf_state for select to authenticated using (auth.uid() = user_id);
create policy "cf_state insert own" on public.cf_state for insert to authenticated with check (auth.uid() = user_id);
create policy "cf_state update own" on public.cf_state for update to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "cf_state delete own" on public.cf_state for delete to authenticated using (auth.uid() = user_id);
