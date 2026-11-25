-- CourtFlow: allow organizers to delete a player even if enrolled in the Rewards program.
-- Run once in the Supabase SQL Editor. Deleting a player also deletes their Rewards card,
-- stamp history and rewards (this cannot be undone).
create or replace function public.cf_organizer_delete_player(p_id uuid)
returns boolean language plpgsql security definer set search_path = public as $$
declare v_count integer;
begin
  if auth.uid() is null then raise exception 'Sign in as the organizer first'; end if;
  if not exists(select 1 from public.cf_player_profiles where id=p_id and owner_id=auth.uid()) then
    raise exception 'Player profile not found or access denied';
  end if;
  delete from public.cf_loyalty_transactions where member_id in
    (select id from public.cf_loyalty_members where player_profile_id=p_id and owner_id=auth.uid());
  delete from public.cf_loyalty_rewards where member_id in
    (select id from public.cf_loyalty_members where player_profile_id=p_id and owner_id=auth.uid());
  delete from public.cf_loyalty_members where player_profile_id=p_id and owner_id=auth.uid();
  delete from public.cf_player_profiles where id=p_id and owner_id=auth.uid();
  get diagnostics v_count = row_count;
  if v_count=0 then raise exception 'Player profile not found or access denied'; end if;
  return true;
end; $$;
revoke all on function public.cf_organizer_delete_player(uuid) from public;
grant execute on function public.cf_organizer_delete_player(uuid) to authenticated;
