-- Revoke direct API execution from SECURITY DEFINER trigger/helper functions.
-- Trigger functions continue to run through their triggers; RLS helper
-- functions keep authenticated execute where policies depend on them.

begin;

revoke execute on function public.handle_admin_response() from public, anon, authenticated;
revoke execute on function public.log_group_movement() from public, anon, authenticated;
revoke execute on function public.on_message_notify() from public, anon, authenticated;
revoke execute on function public.on_profile_created_notify() from public, anon, authenticated;
revoke execute on function public.populate_notification_recipients() from public, anon, authenticated;
revoke execute on function public.rls_auto_enable() from public, anon, authenticated;
revoke execute on function public.trigger_invoke_send_notification() from public, anon, authenticated;

revoke execute on function public.is_group_member(uuid) from public, anon;
revoke execute on function public.is_group_member_v2(uuid) from public, anon;
grant execute on function public.is_group_member(uuid) to authenticated;
grant execute on function public.is_group_member_v2(uuid) to authenticated;

commit;
