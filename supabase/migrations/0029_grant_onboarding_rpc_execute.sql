-- 0029_grant_onboarding_rpc_execute.sql
--
-- Defensive, idempotent re-grant of EXECUTE on the onboarding/preference RPCs to
-- the `authenticated` role. These grants already exist (0005_release_hardening.sql
-- lines 181-182); this migration re-states them so a future create-or-replace that
-- drops+recreates either function cannot silently lose the grant, and reloads the
-- PostgREST schema cache.
--
-- Context: while QA'ing the app in the iOS simulator, "Start pouring" (the onboarding
-- finish) returned "Could not save your setup." The API logs showed
-- POST /rpc/complete_profile_onboarding -> HTTP 401, i.e. the request reached PostgREST
-- as the `anon` role (no Authorization: Bearer <user-jwt>). Root cause was NOT a missing
-- grant (authenticated has had it since 0005) but that the token wasn't attached: the
-- simulator build was unsigned, so it had no keychain-access-group and the Supabase SDK
-- could not persist/return the session (auth.session throws -> SDK omits the auth header
-- -> anon). The signed release build is unaffected. Keeping this grant explicit is cheap
-- insurance regardless.

grant execute on function public.complete_profile_onboarding(text, text[], boolean, boolean, boolean, text) to authenticated;
grant execute on function public.set_profile_preferences(text, boolean) to authenticated;

notify pgrst, 'reload schema';
