-- CourtFlow permanent player profile directory
-- Run this once in Supabase SQL Editor before deploying the updated site.
create extension if not exists pgcrypto;

create table if not exists public.cf_player_profiles (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  display_name text not null check (char_length(display_name) between 1 and 40),
  full_name text not null default '' check (char_length(full_name) <= 80),
  level integer not null default 3 check (level between 1 and 6),
  gender text not null default '' check (gender in ('','M','W')),
  whatsapp text not null default '' check (char_length(whatsapp) <= 30),
  photo text,
  edit_hash text not null unique,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.cf_player_profiles add column if not exists gender text not null default '';
alter table public.cf_player_profiles drop constraint if exists cf_player_profiles_gender_check;
alter table public.cf_player_profiles add constraint cf_player_profiles_gender_check check (gender in ('','M','W'));

create index if not exists cf_player_profiles_owner_name_idx
  on public.cf_player_profiles(owner_id, lower(display_name));

create table if not exists public.cf_profile_invites (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  token_hash text not null unique,
  created_at timestamptz not null default now(),
  revoked_at timestamptz
);

alter table public.cf_player_profiles enable row level security;
alter table public.cf_profile_invites enable row level security;
revoke all on table public.cf_player_profiles from anon, public;
revoke all on table public.cf_profile_invites from anon, public;
revoke insert, update, delete on table public.cf_player_profiles from authenticated;
revoke insert, update, delete on table public.cf_profile_invites from authenticated;
grant select on table public.cf_player_profiles to authenticated;
grant select on table public.cf_profile_invites to authenticated;
drop policy if exists "cf profiles owner read" on public.cf_player_profiles;
create policy "cf profiles owner read" on public.cf_player_profiles
  for select to authenticated using (auth.uid() = owner_id);
drop policy if exists "cf invites owner read" on public.cf_profile_invites;
create policy "cf invites owner read" on public.cf_profile_invites
  for select to authenticated using (auth.uid() = owner_id);


-- Allow organizer-created placeholder profiles. These records contain only a display name
-- until the organizer gathers the player's remaining details. They are not claimable from
-- the public session page; that page remains read-only.
alter table public.cf_player_profiles alter column full_name set default '';
alter table public.cf_player_profiles drop constraint if exists cf_player_profiles_full_name_check;
alter table public.cf_player_profiles add constraint cf_player_profiles_full_name_check check (char_length(full_name) <= 80);

create or replace function public.cf_create_incomplete_player(p_display_name text)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare v_id uuid;
begin
  if auth.uid() is null then raise exception 'Sign in as the organizer first'; end if;
  if coalesce(length(trim(p_display_name)),0) not between 1 and 40 then
    raise exception 'Player display name must be 1–40 characters';
  end if;
  insert into public.cf_player_profiles(owner_id,display_name,full_name,level,gender,whatsapp,photo,edit_hash)
  values(auth.uid(),trim(p_display_name),'',3,'','',null,encode(gen_random_bytes(32),'hex'))
  returning id into v_id;
  return jsonb_build_object('id',v_id,'status','incomplete');
end; $$;
revoke all on function public.cf_create_incomplete_player(text) from public;
grant execute on function public.cf_create_incomplete_player(text) to authenticated;

create or replace function public.cf_create_profile_invite()
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare v_token text; begin
  if auth.uid() is null then raise exception 'Sign in as the organizer first'; end if;
  v_token := encode(gen_random_bytes(32), 'hex');
  insert into public.cf_profile_invites(owner_id, token_hash) values (auth.uid(), encode(digest(v_token,'sha256'),'hex'));
  return jsonb_build_object('invite_token',v_token);
end; $$;
revoke all on function public.cf_create_profile_invite() from public;
grant execute on function public.cf_create_profile_invite() to authenticated;

create or replace function public.cf_get_player_profile(p_edit text)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare v_row public.cf_player_profiles%rowtype; begin
  if p_edit is null or length(p_edit) < 40 then return null; end if;
  select * into v_row from public.cf_player_profiles where edit_hash=encode(digest(p_edit,'sha256'),'hex');
  if not found then return null; end if;
  return jsonb_build_object('display_name',v_row.display_name,'full_name',v_row.full_name,'level',v_row.level,'gender',v_row.gender,'whatsapp',v_row.whatsapp,'photo',v_row.photo);
end; $$;
revoke all on function public.cf_get_player_profile(text) from public;
grant execute on function public.cf_get_player_profile(text) to anon, authenticated;

create or replace function public.cf_save_player_profile(
  p_invite text, p_edit text, p_display_name text, p_full_name text,
  p_level integer, p_whatsapp text, p_photo text, p_gender text default ''
) returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare v_owner uuid; v_edit text; v_id uuid; v_photo text;
begin
  if coalesce(length(trim(p_display_name)),0) not between 1 and 40 then raise exception 'Display name must be 1–40 characters'; end if;
  if coalesce(length(trim(p_full_name)),0) not between 1 and 80 then raise exception 'Full name must be 1–80 characters'; end if;
  if p_level is null or p_level not between 1 and 6 then raise exception 'Choose a valid playing level'; end if;
  if coalesce(p_gender,'') not in ('','M','W') then raise exception 'Choose a valid gender'; end if;
  if length(coalesce(p_whatsapp,'')) > 30 then raise exception 'WhatsApp number is too long'; end if;
  if p_photo is not null and length(p_photo) > 700000 then raise exception 'Photo is too large. Please choose a smaller image'; end if;
  v_photo := p_photo;
  if p_edit is not null and length(p_edit) >= 40 then
    update public.cf_player_profiles set display_name=trim(p_display_name), full_name=trim(p_full_name), level=p_level, gender=coalesce(p_gender,''),
      whatsapp=coalesce(trim(p_whatsapp),''), photo=coalesce(v_photo,photo), updated_at=now()
      where edit_hash=encode(digest(p_edit,'sha256'),'hex') returning id into v_id;
    if v_id is null then raise exception 'This edit link is invalid or expired'; end if;
    v_edit := p_edit;
  else
    if p_invite is null or length(p_invite) < 40 then raise exception 'Ask the organizer for the registration link'; end if;
    select owner_id into v_owner from public.cf_profile_invites
      where token_hash=encode(digest(p_invite,'sha256'),'hex') and revoked_at is null;
    if v_owner is null then raise exception 'This registration link is invalid or has been revoked'; end if;
    v_edit := encode(gen_random_bytes(32),'hex');
    insert into public.cf_player_profiles(owner_id,display_name,full_name,level,gender,whatsapp,photo,edit_hash)
      values(v_owner,trim(p_display_name),trim(p_full_name),p_level,coalesce(p_gender,''),coalesce(trim(p_whatsapp),''),v_photo,encode(digest(v_edit,'sha256'),'hex'))
      returning id into v_id;
  end if;
  return jsonb_build_object('id',v_id,'edit_token',v_edit);
end; $$;
drop function if exists public.cf_save_player_profile(text,text,text,text,integer,text,text);
revoke all on function public.cf_save_player_profile(text,text,text,text,integer,text,text,text) from public;
grant execute on function public.cf_save_player_profile(text,text,text,text,integer,text,text,text) to anon, authenticated;

-- Organizer-managed complete profile form (optional details may be left blank).
-- Display name, gender and level are required by the app; full name, WhatsApp and
-- photo are optional. The shared session page remains read-only.
create or replace function public.cf_organizer_save_player(
  p_id uuid, p_display_name text, p_gender text, p_level integer,
  p_full_name text default '', p_whatsapp text default '', p_photo text default null
) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare v_id uuid;
begin
  if auth.uid() is null then raise exception 'Sign in as the organizer first'; end if;
  if coalesce(length(trim(p_display_name)),0) not between 1 and 40 then raise exception 'Display name must be 1–40 characters'; end if;
  if coalesce(p_gender,'') not in ('M','W') then raise exception 'Choose a gender'; end if;
  if p_level is null or p_level not between 1 and 6 then raise exception 'Choose a playing level'; end if;
  if length(coalesce(p_full_name,'')) > 80 then raise exception 'Full name is too long'; end if;
  if length(coalesce(p_whatsapp,'')) > 30 then raise exception 'WhatsApp number is too long'; end if;
  if p_photo is not null and length(p_photo) > 700000 then raise exception 'Photo is too large. Please choose a smaller image'; end if;
  if p_id is null then
    insert into public.cf_player_profiles(owner_id,display_name,full_name,level,gender,whatsapp,photo,edit_hash)
    values(auth.uid(),trim(p_display_name),coalesce(trim(p_full_name),''),p_level,p_gender,coalesce(trim(p_whatsapp),''),p_photo,encode(digest(encode(gen_random_bytes(32),'hex'),'sha256'),'hex'))
    returning id into v_id;
  else
    update public.cf_player_profiles set display_name=trim(p_display_name), full_name=coalesce(trim(p_full_name),''),
      level=p_level, gender=p_gender, whatsapp=coalesce(trim(p_whatsapp),''), photo=p_photo, updated_at=now()
    where id=p_id and owner_id=auth.uid() returning id into v_id;
    if v_id is null then raise exception 'Player profile not found or access denied'; end if;
  end if;
  return jsonb_build_object('id',v_id,'status',case when coalesce(trim(p_full_name),'')<>'' and coalesce(trim(p_whatsapp),'')<>'' and p_photo is not null then 'complete' else 'incomplete' end);
end; $$;
revoke all on function public.cf_organizer_save_player(uuid,text,text,integer,text,text,text) from public;
grant execute on function public.cf_organizer_save_player(uuid,text,text,integer,text,text,text) to authenticated;

create or replace function public.cf_organizer_delete_player(p_id uuid)
returns boolean language plpgsql security definer set search_path = public as $$
declare v_count integer;
begin
  if auth.uid() is null then raise exception 'Sign in as the organizer first'; end if;
  delete from public.cf_player_profiles where id=p_id and owner_id=auth.uid();
  get diagnostics v_count = row_count;
  if v_count=0 then raise exception 'Player profile not found or access denied'; end if;
  return true;
end; $$;
revoke all on function public.cf_organizer_delete_player(uuid) from public;
grant execute on function public.cf_organizer_delete_player(uuid) to authenticated;
