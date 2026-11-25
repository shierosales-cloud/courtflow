-- CourtFlow Rewards: integrated registration, organizer card design, loyalty ledger.
-- Run this migration once in Supabase SQL Editor BEFORE deploying the updated site.
-- It extends the existing cf_player_profiles / cf_profile_invites infrastructure.

create extension if not exists pgcrypto;

-- 1) Extend existing player profiles with an optional birthday.
alter table public.cf_player_profiles
  add column if not exists birthday date;

-- 2) One organizer-owned loyalty program and its published card design.
create table if not exists public.cf_loyalty_programs (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null unique references auth.users(id) on delete cascade,
  is_active boolean not null default false,
  stamp_target integer not null default 10 check (stamp_target = 10),
  config jsonb not null default '{"programName":"Club Rewards","subtitle":"Play more. Earn more.","welcomeMessage":"Collect stamps when you attend eligible sessions.","rewardTitle":"1 FREE OPEN-PLAY SESSION","stampIcon":"pickleball","primaryColor":"#173F36","secondaryColor":"#285448","accentColor":"#D8B66F","textColor":"#FFFFFF","mutedTextColor":"#DCE9E2","emptyStampColor":"#315E50","earnedStampColor":"#D8B66F","cardLayout":"classic","backgroundMode":"overlay"}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- 3) A loyalty membership is separate from the player profile and requires opt-in.
create table if not exists public.cf_loyalty_members (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  program_id uuid not null references public.cf_loyalty_programs(id) on delete cascade,
  player_profile_id uuid not null references public.cf_player_profiles(id) on delete restrict,
  card_number text not null unique,
  card_token_hash text not null unique,
  status text not null default 'active' check (status in ('active','paused','revoked')),
  membership_type text check (membership_type in ('founding','monthly','pay-per-play')),
  total_stamps integer not null default 0 check (total_stamps >= 0),
  enrolled_at timestamptz not null default now(),
  consent_policy_version text not null default '1.2',
  consent_source text not null default 'registration',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(program_id, player_profile_id)
);
create index if not exists cf_loyalty_members_owner_idx on public.cf_loyalty_members(owner_id, status);

-- 4) Permanent, auditable stamp ledger. One stamp award per member/session.
create table if not exists public.cf_loyalty_transactions (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  member_id uuid not null references public.cf_loyalty_members(id) on delete restrict,
  transaction_type text not null check (transaction_type in ('stamp_award','manual_adjustment','stamp_reversal')),
  stamp_delta integer not null,
  session_key text,
  session_name text,
  reason text,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now()
);
create unique index if not exists cf_loyalty_one_stamp_per_session
  on public.cf_loyalty_transactions(member_id, session_key)
  where transaction_type = 'stamp_award' and session_key is not null;
create index if not exists cf_loyalty_tx_owner_created_idx
  on public.cf_loyalty_transactions(owner_id, created_at desc);

-- 5) Rewards are unique per 10-stamp milestone.
create table if not exists public.cf_loyalty_rewards (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  member_id uuid not null references public.cf_loyalty_members(id) on delete restrict,
  milestone_no integer not null check (milestone_no > 0),
  reward_type text not null default 'free_open_play',
  redemption_code text not null unique,
  status text not null default 'available' check (status in ('available','redeemed','cancelled')),
  issued_at timestamptz not null default now(),
  redeemed_at timestamptz,
  redeemed_by uuid references auth.users(id),
  redeemed_session_name text,
  unique(member_id, milestone_no)
);
create index if not exists cf_loyalty_rewards_owner_status_idx
  on public.cf_loyalty_rewards(owner_id, status, issued_at desc);

-- 6) Restrict direct table access. Read/write is performed through owner-checked RPCs.
alter table public.cf_loyalty_programs enable row level security;
alter table public.cf_loyalty_members enable row level security;
alter table public.cf_loyalty_transactions enable row level security;
alter table public.cf_loyalty_rewards enable row level security;
revoke all on public.cf_loyalty_programs from anon, public, authenticated;
revoke all on public.cf_loyalty_members from anon, public, authenticated;
revoke all on public.cf_loyalty_transactions from anon, public, authenticated;
revoke all on public.cf_loyalty_rewards from anon, public, authenticated;

-- 7) Public assets bucket for organizer logos/backgrounds/custom stamp artwork.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('cf-loyalty-assets', 'cf-loyalty-assets', true, 5242880, array['image/png','image/jpeg','image/webp'])
on conflict (id) do update set public = true, file_size_limit = 5242880,
  allowed_mime_types = array['image/png','image/jpeg','image/webp'];

drop policy if exists "CourtFlow loyalty assets public read" on storage.objects;
create policy "CourtFlow loyalty assets public read" on storage.objects
  for select to public using (bucket_id = 'cf-loyalty-assets');
drop policy if exists "CourtFlow loyalty assets owner upload" on storage.objects;
create policy "CourtFlow loyalty assets owner upload" on storage.objects
  for insert to authenticated with check (
    bucket_id = 'cf-loyalty-assets' and (storage.foldername(name))[1] = auth.uid()::text
  );
drop policy if exists "CourtFlow loyalty assets owner update" on storage.objects;
create policy "CourtFlow loyalty assets owner update" on storage.objects
  for update to authenticated using (
    bucket_id = 'cf-loyalty-assets' and (storage.foldername(name))[1] = auth.uid()::text
  ) with check (
    bucket_id = 'cf-loyalty-assets' and (storage.foldername(name))[1] = auth.uid()::text
  );
drop policy if exists "CourtFlow loyalty assets owner delete" on storage.objects;
create policy "CourtFlow loyalty assets owner delete" on storage.objects
  for delete to authenticated using (
    bucket_id = 'cf-loyalty-assets' and (storage.foldername(name))[1] = auth.uid()::text
  );

-- 8) Organizer saves/updates their own program and card theme.
create or replace function public.cf_save_loyalty_program(p_is_active boolean, p_config jsonb)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare v_id uuid; v_config jsonb;
begin
  if auth.uid() is null then raise exception 'Sign in as the organizer first'; end if;
  if p_config is null or jsonb_typeof(p_config) <> 'object' then raise exception 'Invalid card design'; end if;
  if octet_length(p_config::text) > 100000 then raise exception 'Card settings are too large'; end if;
  if length(coalesce(p_config->>'programName','')) > 60 then raise exception 'Program name is too long'; end if;
  if length(coalesce(p_config->>'subtitle','')) > 100 then raise exception 'Subtitle is too long'; end if;
  if length(coalesce(p_config->>'welcomeMessage','')) > 240 then raise exception 'Welcome message is too long'; end if;
  if length(coalesce(p_config->>'rewardTitle','')) > 100 then raise exception 'Reward title is too long'; end if;
  v_config := p_config;
  insert into public.cf_loyalty_programs(owner_id, is_active, stamp_target, config)
  values(auth.uid(), coalesce(p_is_active,false), 10, v_config)
  on conflict (owner_id) do update set is_active = excluded.is_active, config = excluded.config, updated_at = now()
  returning id into v_id;
  return jsonb_build_object('id',v_id,'is_active',coalesce(p_is_active,false),'stamp_target',10,'config',v_config);
end; $$;
revoke all on function public.cf_save_loyalty_program(boolean,jsonb) from public;
grant execute on function public.cf_save_loyalty_program(boolean,jsonb) to authenticated;

-- 9) Owner-only read of their loyalty program.
create or replace function public.cf_get_my_loyalty_program()
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_result jsonb;
begin
  if auth.uid() is null then raise exception 'Sign in as the organizer first'; end if;
  select jsonb_build_object('id',id,'is_active',is_active,'stamp_target',stamp_target,'config',config,'updated_at',updated_at)
    into v_result from public.cf_loyalty_programs where owner_id=auth.uid();
  return v_result;
end; $$;
revoke all on function public.cf_get_my_loyalty_program() from public;
grant execute on function public.cf_get_my_loyalty_program() to authenticated;

-- 10) Public registration page gets only the published branding for the exact valid invite link.
create or replace function public.cf_get_public_loyalty_program(p_invite text)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare v_owner uuid; v_result jsonb;
begin
  if p_invite is null or length(p_invite) < 40 then return null; end if;
  select owner_id into v_owner from public.cf_profile_invites
    where token_hash=encode(digest(p_invite,'sha256'),'hex') and revoked_at is null;
  if v_owner is null then return null; end if;
  select jsonb_build_object('id',id,'program_name',config->>'programName','config',config,'stamp_target',stamp_target)
    into v_result from public.cf_loyalty_programs
    where owner_id=v_owner and is_active=true;
  return v_result;
end; $$;
revoke all on function public.cf_get_public_loyalty_program(text) from public;
grant execute on function public.cf_get_public_loyalty_program(text) to anon, authenticated;

-- 11) Save existing player details, optional birthday and optional loyalty enrollment atomically.
create or replace function public.cf_save_player_profile_v2(
  p_invite text, p_edit text, p_display_name text, p_full_name text,
  p_level integer, p_whatsapp text, p_photo text, p_gender text,
  p_birthday date default null, p_join_loyalty boolean default false
) returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare
  v_owner uuid; v_edit text; v_id uuid; v_photo text; v_program_id uuid;
  v_member_id uuid; v_card_token text; v_card_number text; v_ids uuid[];
begin
  if coalesce(length(trim(p_display_name)),0) not between 1 and 40 then raise exception 'Display name must be 1–40 characters'; end if;
  if coalesce(length(trim(p_full_name)),0) not between 1 and 80 then raise exception 'Full name must be 1–80 characters'; end if;
  if p_level is null or p_level not between 1 and 6 then raise exception 'Choose a valid playing level'; end if;
  if coalesce(p_gender,'') not in ('','M','W') then raise exception 'Choose a valid gender'; end if;
  if length(coalesce(p_whatsapp,'')) > 30 then raise exception 'WhatsApp number is too long'; end if;
  if p_photo is not null and length(p_photo) > 700000 then raise exception 'Photo is too large. Please choose a smaller image'; end if;
  if p_birthday is not null and (p_birthday > current_date or p_birthday < (current_date - interval '120 years')::date) then raise exception 'Enter a valid birthday'; end if;
  v_photo := p_photo;
  if p_edit is not null and length(p_edit) >= 40 then
    update public.cf_player_profiles set display_name=trim(p_display_name), full_name=trim(p_full_name), level=p_level,
      gender=coalesce(p_gender,''), whatsapp=coalesce(trim(p_whatsapp),''), photo=coalesce(v_photo,photo),
      birthday=p_birthday, updated_at=now()
    where edit_hash=encode(digest(p_edit,'sha256'),'hex') returning id, owner_id into v_id, v_owner;
    if v_id is null then raise exception 'This edit link is invalid or expired'; end if;
    v_edit := p_edit;
  else
    if p_invite is null or length(p_invite) < 40 then raise exception 'Ask the organizer for the registration link'; end if;
    select owner_id into v_owner from public.cf_profile_invites
      where token_hash=encode(digest(p_invite,'sha256'),'hex') and revoked_at is null;
    if v_owner is null then raise exception 'This registration link is invalid or has been revoked'; end if;

    -- Reuse a profile when a unique WhatsApp number already exists for this organizer.
    if nullif(trim(p_whatsapp),'') is not null then
      select array_agg(id) into v_ids from (
        select id from public.cf_player_profiles
        where owner_id=v_owner and regexp_replace(whatsapp,'[^0-9]','','g')=regexp_replace(trim(p_whatsapp),'[^0-9]','','g')
        order by created_at desc limit 2
      ) q;
      if coalesce(cardinality(v_ids),0)=1 then
        v_id := v_ids[1];
        v_edit := encode(gen_random_bytes(32),'hex');
        update public.cf_player_profiles set display_name=trim(p_display_name), full_name=trim(p_full_name), level=p_level,
          gender=coalesce(p_gender,''), whatsapp=coalesce(trim(p_whatsapp),''), photo=coalesce(v_photo,photo),
          birthday=p_birthday, edit_hash=encode(digest(v_edit,'sha256'),'hex'), updated_at=now()
        where id=v_id and owner_id=v_owner;
      end if;
    end if;
    if v_id is null then
      v_edit := encode(gen_random_bytes(32),'hex');
      insert into public.cf_player_profiles(owner_id,display_name,full_name,level,gender,whatsapp,photo,birthday,edit_hash)
      values(v_owner,trim(p_display_name),trim(p_full_name),p_level,coalesce(p_gender,''),coalesce(trim(p_whatsapp),''),v_photo,p_birthday,encode(digest(v_edit,'sha256'),'hex'))
      returning id into v_id;
    end if;
  end if;

  if coalesce(p_join_loyalty,false) and p_invite is not null and length(p_invite)>=40 then
    select id into v_program_id from public.cf_loyalty_programs where owner_id=v_owner and is_active=true;
    -- If the organizer deactivates the program after the registration page was opened,
    -- normal profile registration still completes; no loyalty membership is created.
    if v_program_id is not null then
      v_card_token := encode(gen_random_bytes(32),'hex');
      v_card_number := 'CF-' || upper(substr(replace(gen_random_uuid()::text,'-',''),1,10));
      insert into public.cf_loyalty_members(owner_id,program_id,player_profile_id,card_number,card_token_hash,status,consent_source)
      values(v_owner,v_program_id,v_id,v_card_number,encode(digest(v_card_token,'sha256'),'hex'),'active','registration')
      on conflict(program_id,player_profile_id) do update set
        card_token_hash=excluded.card_token_hash, status='active', updated_at=now()
      returning id,card_number into v_member_id,v_card_number;
    end if;
  end if;

  return jsonb_build_object('id',v_id,'edit_token',v_edit,'birthday',p_birthday,
    'loyalty_enrolled',v_member_id is not null,'card_token',case when v_member_id is not null then v_card_token else null end,
    'card_number',case when v_member_id is not null then v_card_number else null end);
end; $$;
-- 12) Read an individual's saved profile through their private edit token.
create or replace function public.cf_get_player_profile(p_edit text)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare v_row public.cf_player_profiles%rowtype; v_enrolled boolean;
begin
  if p_edit is null or length(p_edit) < 40 then return null; end if;
  select * into v_row from public.cf_player_profiles where edit_hash=encode(digest(p_edit,'sha256'),'hex');
  if not found then return null; end if;
  select exists(select 1 from public.cf_loyalty_members where player_profile_id=v_row.id and status='active') into v_enrolled;
  return jsonb_build_object('display_name',v_row.display_name,'full_name',v_row.full_name,'level',v_row.level,
    'gender',v_row.gender,'whatsapp',v_row.whatsapp,'photo',v_row.photo,'birthday',v_row.birthday,'loyalty_enrolled',v_enrolled);
end; $$;
revoke all on function public.cf_get_player_profile(text) from public;
grant execute on function public.cf_get_player_profile(text) to anon, authenticated;

-- 13) Organizer updates a player's birthday from the existing Player Pool editor.
create or replace function public.cf_organizer_save_player_v2(
  p_id uuid, p_display_name text, p_gender text, p_level integer,
  p_full_name text default '', p_whatsapp text default '', p_photo text default null,
  p_birthday date default null
) returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare v_id uuid;
begin
  if auth.uid() is null then raise exception 'Sign in as the organizer first'; end if;
  if coalesce(length(trim(p_display_name)),0) not between 1 and 40 then raise exception 'Display name must be 1–40 characters'; end if;
  if coalesce(p_gender,'') not in ('M','W') then raise exception 'Choose a gender'; end if;
  if p_level is null or p_level not between 1 and 6 then raise exception 'Choose a playing level'; end if;
  if length(coalesce(p_full_name,'')) > 80 then raise exception 'Full name is too long'; end if;
  if length(coalesce(p_whatsapp,'')) > 30 then raise exception 'WhatsApp number is too long'; end if;
  if p_photo is not null and length(p_photo) > 700000 then raise exception 'Photo is too large. Please choose a smaller image'; end if;
  if p_birthday is not null and (p_birthday > current_date or p_birthday < (current_date - interval '120 years')::date) then raise exception 'Enter a valid birthday'; end if;
  if p_id is null then
    insert into public.cf_player_profiles(owner_id,display_name,full_name,level,gender,whatsapp,photo,birthday,edit_hash)
    values(auth.uid(),trim(p_display_name),coalesce(trim(p_full_name),''),p_level,p_gender,coalesce(trim(p_whatsapp),''),p_photo,p_birthday,encode(digest(encode(gen_random_bytes(32),'hex'),'sha256'),'hex'))
    returning id into v_id;
  else
    update public.cf_player_profiles set display_name=trim(p_display_name),full_name=coalesce(trim(p_full_name),''),
      level=p_level,gender=p_gender,whatsapp=coalesce(trim(p_whatsapp),''),photo=p_photo,birthday=p_birthday,updated_at=now()
    where id=p_id and owner_id=auth.uid() returning id into v_id;
    if v_id is null then raise exception 'Player profile not found or access denied'; end if;
  end if;
  return jsonb_build_object('id',v_id,'status',case when coalesce(trim(p_full_name),'')<>'' and coalesce(trim(p_whatsapp),'')<>'' and p_photo is not null then 'complete' else 'incomplete' end);
end; $$;
revoke all on function public.cf_organizer_save_player_v2(uuid,text,text,integer,text,text,text,date) from public;
grant execute on function public.cf_organizer_save_player_v2(uuid,text,text,integer,text,text,text,date) to authenticated;

-- 14) Organizer dashboard: enrolled players and their current balances.
create or replace function public.cf_get_my_loyalty_members()
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_result jsonb;
begin
  if auth.uid() is null then raise exception 'Sign in as the organizer first'; end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'member_id',m.id,'player_profile_id',m.player_profile_id,'player_name',p.display_name,
    'card_number',m.card_number,'status',m.status,'membership_type',m.membership_type,'total_stamps',m.total_stamps,
    'progress',mod(m.total_stamps,10), 'total_rewards',coalesce(r.total,0),'available_rewards',coalesce(r.available,0),
    'enrolled_at',m.enrolled_at
  ) order by p.display_name),'[]'::jsonb) into v_result
  from public.cf_loyalty_members m join public.cf_player_profiles p on p.id=m.player_profile_id
  left join lateral (select count(*)::integer total,count(*) filter(where status='available')::integer available
    from public.cf_loyalty_rewards where member_id=m.id) r on true
  where m.owner_id=auth.uid();
  return v_result;
end; $$;
revoke all on function public.cf_get_my_loyalty_members() from public;
grant execute on function public.cf_get_my_loyalty_members() to authenticated;

-- 15) Stamp awards are deduplicated by member + completed session key.
create or replace function public.cf_award_session_loyalty_stamps(p_session_key text, p_session_name text, p_attendees jsonb)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare
  v_program_id uuid; v_attendee jsonb; v_name text; v_profile_id uuid; v_ids uuid[];
  v_member_id uuid; v_tx uuid; v_total integer; v_awarded integer := 0; v_rewards integer := 0;
begin
  if auth.uid() is null then raise exception 'Sign in as the organizer first'; end if;
  if coalesce(length(trim(p_session_key)),0)=0 then raise exception 'Missing session reference'; end if;
  if jsonb_typeof(p_attendees)<>'array' then raise exception 'Invalid attendee list'; end if;
  select id into v_program_id from public.cf_loyalty_programs where owner_id=auth.uid() and is_active=true;
  if v_program_id is null then return jsonb_build_object('awarded',0,'rewards',0,'reason','Loyalty program is not active'); end if;
  for v_attendee in select value from jsonb_array_elements(p_attendees) loop
    v_profile_id := null;
    if coalesce(v_attendee->>'profile_id','') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
      select id into v_profile_id from public.cf_player_profiles where id=(v_attendee->>'profile_id')::uuid and owner_id=auth.uid();
    end if;
    v_name := trim(coalesce(v_attendee->>'name',''));
    if v_profile_id is null and v_name<>'' then
      select array_agg(id) into v_ids from (
        select id from public.cf_player_profiles where owner_id=auth.uid() and lower(display_name)=lower(v_name) limit 2
      ) q;
      if coalesce(cardinality(v_ids),0)=1 then v_profile_id := v_ids[1]; end if;
    end if;
    if v_profile_id is null then continue; end if;
    select id into v_member_id from public.cf_loyalty_members
      where owner_id=auth.uid() and program_id=v_program_id and player_profile_id=v_profile_id and status='active';
    if v_member_id is null then continue; end if;
    insert into public.cf_loyalty_transactions(owner_id,member_id,transaction_type,stamp_delta,session_key,session_name,created_by)
    values(auth.uid(),v_member_id,'stamp_award',1,p_session_key,p_session_name,auth.uid())
    on conflict do nothing returning id into v_tx;
    if v_tx is null then continue; end if;
    update public.cf_loyalty_members set total_stamps=total_stamps+1,updated_at=now()
      where id=v_member_id returning total_stamps into v_total;
    v_awarded := v_awarded+1;
    if mod(v_total,10)=0 then
      insert into public.cf_loyalty_rewards(owner_id,member_id,milestone_no,redemption_code)
      values(auth.uid(),v_member_id,(v_total/10)::integer,upper(substr(encode(gen_random_bytes(8),'hex'),1,12)))
      on conflict(member_id,milestone_no) do nothing;
      if found then v_rewards := v_rewards+1; end if;
    end if;
  end loop;
  return jsonb_build_object('awarded',v_awarded,'rewards',v_rewards);
end; $$;
revoke all on function public.cf_award_session_loyalty_stamps(text,text,jsonb) from public;
grant execute on function public.cf_award_session_loyalty_stamps(text,text,jsonb) to authenticated;

-- 16) Organizer redeems a player's one-time reward code.
create or replace function public.cf_redeem_loyalty_reward(p_code text, p_session_name text default '')
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_reward public.cf_loyalty_rewards%rowtype; v_player text;
begin
  if auth.uid() is null then raise exception 'Sign in as the organizer first'; end if;
  update public.cf_loyalty_rewards set status='redeemed',redeemed_at=now(),redeemed_by=auth.uid(),redeemed_session_name=left(coalesce(p_session_name,''),100)
  where owner_id=auth.uid() and upper(redemption_code)=upper(trim(p_code)) and status='available'
  returning * into v_reward;
  if v_reward.id is null then raise exception 'Reward code is invalid, already redeemed or belongs to another organizer'; end if;
  select p.display_name into v_player from public.cf_loyalty_members m join public.cf_player_profiles p on p.id=m.player_profile_id where m.id=v_reward.member_id;
  return jsonb_build_object('success',true,'player_name',v_player,'reward_id',v_reward.id,'redeemed_at',v_reward.redeemed_at);
end; $$;
revoke all on function public.cf_redeem_loyalty_reward(text,text) from public;
grant execute on function public.cf_redeem_loyalty_reward(text,text) to authenticated;

-- 17) Public, read-only card endpoint. It exposes only the card owner's display name and loyalty data.
create or replace function public.cf_get_public_loyalty_card(p_card_token text)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare v_result jsonb;
begin
  if p_card_token is null or length(p_card_token)<40 then return null; end if;
  select jsonb_build_object(
    'player_name',p.display_name,'card_number',m.card_number,'membership_type',m.membership_type,'total_stamps',m.total_stamps,
    'progress',mod(m.total_stamps,10),'available_rewards',coalesce(r.available,0),
    'available_reward_codes',coalesce(r.codes,'[]'::jsonb),
    'program_name',pr.config->>'programName','config',pr.config,'status',m.status
  ) into v_result
  from public.cf_loyalty_members m
  join public.cf_player_profiles p on p.id=m.player_profile_id
  join public.cf_loyalty_programs pr on pr.id=m.program_id
  left join lateral (
    select count(*)::integer available,
      coalesce(jsonb_agg(redemption_code order by issued_at),'[]'::jsonb) codes
    from public.cf_loyalty_rewards where member_id=m.id and status='available'
  ) r on true
  where m.card_token_hash=encode(digest(p_card_token,'sha256'),'hex') and m.status='active';
  return v_result;
end; $$;
revoke all on function public.cf_get_public_loyalty_card(text) from public;
grant execute on function public.cf_get_public_loyalty_card(text) to anon, authenticated;

-- 18) Prevent silently deleting a player who has a loyalty ledger. Archive/revoke first instead.
create or replace function public.cf_organizer_delete_player(p_id uuid)
returns boolean language plpgsql security definer set search_path = public as $$
declare v_count integer;
begin
  if auth.uid() is null then raise exception 'Sign in as the organizer first'; end if;
  if exists(select 1 from public.cf_loyalty_members where player_profile_id=p_id and owner_id=auth.uid()) then
    raise exception 'This player has a loyalty card or history. Revoke/pause the loyalty membership instead of deleting the profile.';
  end if;
  delete from public.cf_player_profiles where id=p_id and owner_id=auth.uid();
  get diagnostics v_count = row_count;
  if v_count=0 then raise exception 'Player profile not found or access denied'; end if;
  return true;
end; $$;
revoke all on function public.cf_organizer_delete_player(uuid) from public;
grant execute on function public.cf_organizer_delete_player(uuid) to authenticated;

-- The new player-save function is granted to public registration links (anon) and authenticated users.
revoke all on function public.cf_save_player_profile_v2(text,text,text,text,integer,text,text,text,date,boolean) from public;
grant execute on function public.cf_save_player_profile_v2(text,text,text,text,integer,text,text,text,date,boolean) to anon, authenticated;

-- Note: Birthday is optional. No historic session attendance is imported into loyalty stamps.
-- CourtFlow Player Portal: read-only player access using the existing private profile edit token.
-- Run after supabase-loyalty-registration.sql.
-- This endpoint intentionally returns only the player's own display profile and loyalty data.

create or replace function public.cf_get_player_portal(p_access_token text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_profile public.cf_player_profiles%rowtype;
  v_loyalty jsonb;
  v_level text;
begin
  if p_access_token is null or length(p_access_token) < 40 or length(p_access_token) > 100 then
    return null;
  end if;

  select * into v_profile
  from public.cf_player_profiles
  where edit_hash = encode(digest(p_access_token, 'sha256'), 'hex')
  limit 1;

  if not found then
    return null;
  end if;

  v_level := case v_profile.level
    when 1 then 'Newbie'
    when 2 then 'Novice'
    when 3 then 'Low Intermediate'
    when 4 then 'High Intermediate'
    when 5 then 'Advanced'
    when 6 then 'Expert'
    else 'CourtFlow Player'
  end;

  select jsonb_build_object(
    'program_name', pr.config->>'programName',
    'config', pr.config,
    'card_number', m.card_number,
    'membership_type', m.membership_type,
    'total_stamps', m.total_stamps,
    'progress', mod(m.total_stamps, 10),
    'available_rewards', coalesce(r.available, 0),
    'available_reward_codes', coalesce(r.codes, '[]'::jsonb),
    'status', m.status
  )
  into v_loyalty
  from public.cf_loyalty_members m
  join public.cf_loyalty_programs pr on pr.id = m.program_id and pr.is_active = true
  left join lateral (
    select count(*) filter (where status = 'available')::integer as available,
           coalesce(jsonb_agg(redemption_code order by issued_at) filter (where status = 'available'), '[]'::jsonb) as codes
    from public.cf_loyalty_rewards
    where member_id = m.id
  ) r on true
  where m.player_profile_id = v_profile.id
    and m.status = 'active'
  order by m.created_at desc
  limit 1;

  return jsonb_build_object(
    'player_name', v_profile.display_name,
    'photo', v_profile.photo,
    'level_name', v_level,
    'loyalty', v_loyalty
  );
end;
$$;

revoke all on function public.cf_get_player_portal(text) from public;
grant execute on function public.cf_get_player_portal(text) to anon, authenticated;

-- 12) Organizer-managed membership label shown on each Club Rewards card.
alter table public.cf_loyalty_members add column if not exists membership_type text
  check (membership_type in ('founding','monthly','pay-per-play'));
create or replace function public.cf_set_loyalty_membership_type(p_member_id uuid,p_membership_type text)
returns boolean language plpgsql security definer set search_path=public as $$
begin
  if auth.uid() is null then raise exception 'Sign in as the organizer first'; end if;
  if p_membership_type is not null and p_membership_type not in ('founding','monthly','pay-per-play') then
    raise exception 'Invalid membership type';
  end if;
  update public.cf_loyalty_members set membership_type=p_membership_type,updated_at=now()
    where id=p_member_id and owner_id=auth.uid();
  if not found then raise exception 'Rewards member not found'; end if;
  return true;
end; $$;
revoke all on function public.cf_set_loyalty_membership_type(uuid,text) from public;
grant execute on function public.cf_set_loyalty_membership_type(uuid,text) to authenticated;
