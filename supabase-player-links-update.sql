-- CourtFlow: let the organizer see/copy/share each player's personal link, and keep new tokens retrievable.
-- Run once in the Supabase SQL Editor (after the earlier loyalty/player SQL files).
-- NOTE: the private player token is now stored (plain text) so the organizer can share it again. It is only
-- readable by the organizer who owns the player, through the functions below.
-- Players registered before this update: their token is saved automatically the next time they open their
-- own link. For the rest, the organizer taps "Get Link" (this creates a NEW link; the old one stops working).

alter table public.cf_player_profiles add column if not exists edit_token text;

-- Players created by the signed-in organizer get a retrievable token automatically.
create or replace function public.cf_profiles_default_token() returns trigger
language plpgsql security definer set search_path = public, extensions as $$
declare v text;
begin
  if new.edit_token is null and auth.uid() is not null then
    v := encode(gen_random_bytes(32),'hex');
    new.edit_token := v;
    new.edit_hash := encode(digest(v,'sha256'),'hex');
  end if;
  return new;
end; $$;
drop trigger if exists cf_profiles_default_token_trg on public.cf_player_profiles;
create trigger cf_profiles_default_token_trg before insert on public.cf_player_profiles
  for each row execute function public.cf_profiles_default_token();

-- All known links for the signed-in organizer: { "<player id>": "<token>" }
create or replace function public.cf_organizer_player_links() returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'Sign in as the organizer first'; end if;
  return (select coalesce(jsonb_object_agg(id::text, edit_token),'{}'::jsonb)
          from public.cf_player_profiles where owner_id=auth.uid() and edit_token is not null);
end; $$;
revoke all on function public.cf_organizer_player_links() from public;
grant execute on function public.cf_organizer_player_links() to authenticated;

-- One player's link. If none is stored yet, p_confirm=true creates a new one (old link stops working).
create or replace function public.cf_organizer_player_link(p_id uuid, p_confirm boolean default false) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare v text; v_found boolean;
begin
  if auth.uid() is null then raise exception 'Sign in as the organizer first'; end if;
  select edit_token, true into v, v_found from public.cf_player_profiles where id=p_id and owner_id=auth.uid();
  if v_found is null then raise exception 'Player profile not found or access denied'; end if;
  if v is null then
    if not coalesce(p_confirm,false) then return jsonb_build_object('needs_confirm',true); end if;
    v := encode(gen_random_bytes(32),'hex');
    update public.cf_player_profiles set edit_token=v, edit_hash=encode(digest(v,'sha256'),'hex'), updated_at=now()
      where id=p_id and owner_id=auth.uid();
  end if;
  return jsonb_build_object('edit_token',v);
end; $$;
revoke all on function public.cf_organizer_player_link(uuid,boolean) from public;
grant execute on function public.cf_organizer_player_link(uuid,boolean) to authenticated;

-- When a player opens their own link, remember the token so the organizer can share it later.
create or replace function public.cf_player_remember_token(p_edit text) returns boolean
language plpgsql security definer set search_path = public, extensions as $$
begin
  if p_edit is null or length(p_edit) < 40 or length(p_edit) > 100 then return false; end if;
  update public.cf_player_profiles set edit_token=p_edit
    where edit_hash=encode(digest(p_edit,'sha256'),'hex') and edit_token is null;
  return found;
end; $$;
revoke all on function public.cf_player_remember_token(text) from public;
grant execute on function public.cf_player_remember_token(text) to anon, authenticated;

-- Registration function: now also stores the token.
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
      birthday=p_birthday, edit_token=coalesce(edit_token,p_edit), updated_at=now()
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
          birthday=p_birthday, edit_hash=encode(digest(v_edit,'sha256'),'hex'), edit_token=v_edit, updated_at=now()
        where id=v_id and owner_id=v_owner;
      end if;
    end if;
    if v_id is null then
      v_edit := encode(gen_random_bytes(32),'hex');
      insert into public.cf_player_profiles(owner_id,display_name,full_name,level,gender,whatsapp,photo,birthday,edit_hash,edit_token)
      values(v_owner,trim(p_display_name),trim(p_full_name),p_level,coalesce(p_gender,''),coalesce(trim(p_whatsapp),''),v_photo,p_birthday,encode(digest(v_edit,'sha256'),'hex'),v_edit)
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
revoke all on function public.cf_save_player_profile_v2(text,text,text,text,integer,text,text,text,date,boolean) from public;
grant execute on function public.cf_save_player_profile_v2(text,text,text,text,integer,text,text,text,date,boolean) to anon, authenticated;
