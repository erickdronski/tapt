-- Audit fix (CAN-SPAM / abuse): subscribe_newsletter took ANY email from the
-- caller and did `on conflict (email) do update set status = 'subscribed'`, so:
--
--   1. Third-party signup. Any account holder could type a stranger's address
--      and sign them up for the weekly Dispatch, with no confirmation anywhere.
--   2. Resurrection. That same call flipped an already-unsubscribed address back
--      to 'subscribed', which is exactly the opt-out that CAN-SPAM requires us to
--      honor. The web path already refused to do this (dispatch-signup:47-54);
--      the RPC the iOS app calls did not.
--
-- The fix for both is the same one check: an address can only be subscribed by
-- the person who owns it, proven by the caller's verified auth email. Once the
-- caller must be the owner, nobody can sign up a stranger, and nobody but the
-- recipient can undo their own opt-out.
--
-- Note this deliberately still lets an unsubscribed person RE-subscribe
-- themselves, which is a normal thing to want and what the app's "Come back any
-- time" copy promises. That is the one case where reviving an opt-out is
-- legitimate, and we record fresh consent text plus clear unsubscribed_at so the
-- audit trail shows a new, deliberate opt-in rather than a silent flip. The
-- anonymous web path keeps its stricter no-resurrection rule, because an
-- anonymous caller cannot prove they own the address.
create or replace function public.subscribe_newsletter(
  p_email text,
  p_source text default 'app',
  p_ui_text text default null
) returns text
 language plpgsql security definer set search_path to 'public'
as $function$
declare
  v_email text := lower(trim(p_email));
  v_self  text := lower(trim(coalesce(auth.email(), '')));
begin
  if auth.uid() is null then
    raise exception 'sign in required';
  end if;
  if v_email is null or position('@' in v_email) <= 1 or length(v_email) > 320 then
    raise exception 'invalid email';
  end if;
  -- You may only subscribe your own verified address.
  if v_self = '' or v_email <> v_self then
    raise exception 'you can only subscribe your own email address';
  end if;

  insert into newsletter_subscriber (email, user_id, source, status, consent_ui_text)
  values (v_email, auth.uid(), coalesce(nullif(trim(p_source), ''), 'app'), 'subscribed', p_ui_text)
  on conflict (email) do update
    set status = 'subscribed',
        user_id = coalesce(newsletter_subscriber.user_id, excluded.user_id),
        source = excluded.source,
        consent_ui_text = coalesce(excluded.consent_ui_text, newsletter_subscriber.consent_ui_text),
        unsubscribed_at = null,
        updated_at = now();

  return 'subscribed';
end;
$function$;
