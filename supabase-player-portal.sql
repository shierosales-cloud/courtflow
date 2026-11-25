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
