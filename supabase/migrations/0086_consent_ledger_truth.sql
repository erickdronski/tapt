-- 0086_consent_ledger_truth.sql
-- Future consent rows use the published policy version and text shown in the
-- corresponding UI. Historical attestations remain immutable.

create or replace function public.tapt_current_policy_version()
returns text
language sql
immutable
set search_path = pg_catalog
as $$ select '2026-07-12'::text $$;

create or replace function public.record_privacy_choice(
  p_purpose text,
  p_granted boolean,
  p_ui_text text,
  p_policy_version text default null
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_user uuid := auth.uid();
  v_purpose public.consent_purpose;
  v_ui_text text;
begin
  if v_user is null then
    raise exception 'not authenticated';
  end if;

  if p_purpose not in (
    'essential', 'location', 'personalization',
    'aggregate_analytics', 'data_sale', 'marketing'
  ) then
    raise exception 'unsupported consent purpose';
  end if;

  v_purpose := p_purpose::public.consent_purpose;
  v_ui_text := coalesce(
    nullif(btrim(p_ui_text), ''),
    case v_purpose
      when 'location'::public.consent_purpose then 'Nearby beer spots'
      when 'aggregate_analytics'::public.consent_purpose then 'Anonymous trend reports'
      when 'data_sale'::public.consent_purpose then 'Share anonymized aggregates with partners'
      when 'personalization'::public.consent_purpose then 'Personalized beer recommendations'
      when 'marketing'::public.consent_purpose then 'Beer, brewery, and event updates'
      else 'Required data to operate Tapt'
    end
  );

  insert into public.consent_ledger
    (user_id, purpose, action, granted, policy_version, ui_text_shown, source)
  values (
    v_user,
    v_purpose,
    case when p_granted
      then 'granted'::public.consent_action
      else 'withdrawn'::public.consent_action
    end,
    p_granted,
    public.tapt_current_policy_version(),
    v_ui_text,
    'profile'
  );
end;
$$;

create or replace function public.complete_profile_onboarding(
  p_age_confirmed boolean,
  p_region_code text,
  p_top_styles text[],
  p_location_consent boolean,
  p_aggregate_consent boolean,
  p_data_sale_consent boolean
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_user uuid := auth.uid();
  v_policy text := public.tapt_current_policy_version();
begin
  if v_user is null then raise exception 'not authenticated'; end if;
  if coalesce(p_age_confirmed, false) is not true then
    raise exception 'legal drinking age confirmation required';
  end if;

  update public.user_profile
  set birth_verified = true,
      region_code = nullif(btrim(p_region_code), ''),
      updated_at = now()
  where id = v_user;

  insert into public.taste_vector (user_id, top_styles)
  values (v_user, coalesce(p_top_styles, '{}'))
  on conflict (user_id) do update
    set top_styles = excluded.top_styles,
        updated_at = now();

  insert into public.consent_ledger
    (user_id, purpose, action, granted, policy_version, ui_text_shown, source)
  values
    (v_user, 'location',
     case when p_location_consent
       then 'granted'::public.consent_action
       else 'withdrawn'::public.consent_action
     end,
     p_location_consent, v_policy,
     'Use my location for nearby pubs, bars, breweries, taprooms, and beer gardens.',
     'onboarding'),
    (v_user, 'aggregate_analytics',
     case when p_aggregate_consent
       then 'granted'::public.consent_action
       else 'withdrawn'::public.consent_action
     end,
     p_aggregate_consent, v_policy,
     'Use my check-ins for anonymous aggregate trend reports.',
     'onboarding'),
    (v_user, 'data_sale',
     case when p_data_sale_consent
       then 'granted'::public.consent_action
       else 'withdrawn'::public.consent_action
     end,
     p_data_sale_consent, v_policy,
     'Share anonymized aggregates with partners.',
     'onboarding');
end;
$$;

create or replace function public.complete_profile_onboarding(
  p_region_code text,
  p_top_styles text[],
  p_location_consent boolean,
  p_aggregate_consent boolean,
  p_data_sale_consent boolean,
  p_policy_version text default null
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  perform public.complete_profile_onboarding(
    true,
    p_region_code,
    p_top_styles,
    p_location_consent,
    p_aggregate_consent,
    p_data_sale_consent
  );
end;
$$;

revoke all on function public.tapt_current_policy_version()
  from public, anon, authenticated;
revoke all on function public.record_privacy_choice(text, boolean, text, text)
  from public, anon;
grant execute on function public.record_privacy_choice(text, boolean, text, text)
  to authenticated;
revoke all on function public.complete_profile_onboarding(
  boolean, text, text[], boolean, boolean, boolean
) from public, anon;
grant execute on function public.complete_profile_onboarding(
  boolean, text, text[], boolean, boolean, boolean
) to authenticated;
revoke all on function public.complete_profile_onboarding(
  text, text[], boolean, boolean, boolean, text
) from public, anon;
grant execute on function public.complete_profile_onboarding(
  text, text[], boolean, boolean, boolean, text
) to authenticated;

do $$
begin
  if public.tapt_current_policy_version() <> '2026-07-12' then
    raise exception 'current consent policy version is not aligned';
  end if;
end $$;

notify pgrst, 'reload schema';
