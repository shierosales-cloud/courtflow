-- CourtFlow Club Rewards membership type update
-- Run this once in Supabase SQL Editor for an existing installation.
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

create or replace function public.cf_get_my_loyalty_members()
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_result jsonb;
begin
  if auth.uid() is null then raise exception 'Sign in as the organizer first'; end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'member_id',m.id,'player_profile_id',m.player_profile_id,'player_name',p.display_name,
    'card_number',m.card_number,'status',m.status,'membership_type',m.membership_type,'total_stamps',m.total_stamps,
    'progress',mod(m.total_stamps,10),'total_rewards',coalesce(r.total,0),'available_rewards',coalesce(r.available,0),
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

-- Recreate public card RPC so the assigned type is included in its safe card payload.
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
  from public.cf_loyalty_members m join public.cf_player_profiles p on p.id=m.player_profile_id
  join public.cf_loyalty_programs pr on pr.id=m.program_id
  left join lateral (select count(*)::integer available,
      coalesce(jsonb_agg(redemption_code order by issued_at),'[]'::jsonb) codes
    from public.cf_loyalty_rewards where member_id=m.id and status='available') r on true
  where m.card_token_hash=encode(digest(p_card_token,'sha256'),'hex') and m.status='active';
  return v_result;
end; $$;
revoke all on function public.cf_get_public_loyalty_card(text) from public;
grant execute on function public.cf_get_public_loyalty_card(text) to anon, authenticated;
