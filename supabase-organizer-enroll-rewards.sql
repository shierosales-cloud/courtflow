-- CourtFlow v29: let the organizer enroll a player in Club Rewards (manual add / Player Pool).
-- Run ONCE in the Supabase SQL Editor (after supabase-loyalty-registration.sql).
create or replace function public.cf_organizer_enroll_player_loyalty(p_player_id uuid, p_membership_type text default 'pay-per-play')
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare v_program uuid; v_member uuid; v_no text;
begin
  if auth.uid() is null then raise exception 'Sign in as the organizer first'; end if;
  if p_membership_type is not null and p_membership_type not in ('founding','monthly','pay-per-play') then raise exception 'Invalid membership type'; end if;
  perform 1 from public.cf_player_profiles where id=p_player_id and owner_id=auth.uid();
  if not found then raise exception 'Player profile not found or access denied'; end if;
  select id into v_program from public.cf_loyalty_programs where owner_id=auth.uid() and is_active=true;
  if v_program is null then raise exception 'Turn on your Club Rewards program first'; end if;
  select id, card_number into v_member, v_no from public.cf_loyalty_members where program_id=v_program and player_profile_id=p_player_id;
  if v_member is not null then
    update public.cf_loyalty_members set status='active', membership_type=coalesce(p_membership_type,membership_type), updated_at=now() where id=v_member;
    return jsonb_build_object('loyalty_enrolled',true,'already_enrolled',true,'member_id',v_member,'card_number',v_no);
  end if;
  v_no := 'CF-' || upper(substr(replace(gen_random_uuid()::text,'-',''),1,10));
  insert into public.cf_loyalty_members(owner_id,program_id,player_profile_id,card_number,card_token_hash,status,consent_source,membership_type)
  values(auth.uid(),v_program,p_player_id,v_no,encode(digest(encode(gen_random_bytes(32),'hex'),'sha256'),'hex'),'active','organizer',p_membership_type)
  returning id into v_member;
  return jsonb_build_object('loyalty_enrolled',true,'already_enrolled',false,'member_id',v_member,'card_number',v_no);
end; $$;
revoke all on function public.cf_organizer_enroll_player_loyalty(uuid,text) from public;
grant execute on function public.cf_organizer_enroll_player_loyalty(uuid,text) to authenticated;
