-- 0005_release_hardening.sql
-- Repairs release-readiness issues found after the TestFlight upload.

-- Keep the raw trend storage table private and expose one deterministic row per beer/region.
revoke all on beer_trend from anon, authenticated;

drop view if exists beer_trend_feed;
create view beer_trend_feed
with (security_invoker = true) as
select distinct on (bt.beer_id, bt.region)
  bt.beer_id,
  b.name,
  b.style,
  b.abv,
  br.name as brewery_name,
  br.country,
  bt.region,
  bt.popularity,
  bt.momentum,
  bt.avg_rating,
  bt.updated_at
from beer_trend bt
join beer_catalog b on b.id = bt.beer_id
left join brewery br on br.id = b.brewery_id
order by bt.beer_id, bt.region, bt.updated_at desc nulls last, bt.id;

grant select on beer_trend_feed to anon, authenticated;

-- Bound anonymous scan matching harder.
create or replace function match_beers(p_query text, p_limit int default 8)
returns table (
  id uuid,
  name text,
  style text,
  abv numeric,
  brewery_name text,
  country text,
  confidence numeric
)
language sql
stable
set search_path = public
as $$
  with q as (
    select nullif(left(regexp_replace(trim(p_query), '\s+', ' ', 'g'), 96), '') as value,
           least(greatest(coalesce(p_limit, 8), 1), 12) as max_rows
  )
  select
    b.id,
    b.name,
    b.style,
    b.abv,
    br.name as brewery_name,
    br.country,
    case
      when b.gtin = regexp_replace(q.value, '\D', '', 'g') then 1.0
      else greatest(similarity(b.name, q.value), similarity(coalesce(br.name, ''), q.value))
    end::numeric as confidence
  from q, beer_catalog b
  left join brewery br on br.id = b.brewery_id
  where q.value is not null
    and (
      b.gtin = regexp_replace(q.value, '\D', '', 'g')
      or b.name % q.value
      or br.name % q.value
      or b.name ilike '%' || q.value || '%'
      or br.name ilike '%' || q.value || '%'
    )
  order by
    case when b.gtin = regexp_replace(q.value, '\D', '', 'g') then 0 else 1 end,
    confidence desc,
    b.name
  limit (select max_rows from q);
$$;

grant execute on function match_beers(text, int) to anon, authenticated;

-- Reduce profile mutation surface: users can read themselves/public view, but write through narrow RPCs.
drop policy if exists self_profile on user_profile;
drop policy if exists self_profile_select on user_profile;
create policy self_profile_select
on user_profile
for select
to authenticated
using ((select auth.uid()) = id);

create or replace function set_profile_preferences(
  p_region_code text default null,
  p_beer_geek_mode boolean default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update user_profile
  set
    region_code = coalesce(nullif(trim(p_region_code), ''), region_code),
    beer_geek_mode = coalesce(p_beer_geek_mode, beer_geek_mode),
    updated_at = now()
  where id = auth.uid();
end;
$$;

create or replace function complete_profile_onboarding(
  p_region_code text,
  p_top_styles text[],
  p_location_consent boolean,
  p_aggregate_consent boolean,
  p_data_sale_consent boolean,
  p_policy_version text default '2026-07-08'
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
begin
  if v_user is null then
    raise exception 'not authenticated';
  end if;

  update user_profile
  set
    birth_verified = true,
    region_code = nullif(trim(p_region_code), ''),
    updated_at = now()
  where id = v_user;

  insert into taste_vector (user_id, top_styles)
  values (v_user, coalesce(p_top_styles, '{}'))
  on conflict (user_id) do update
    set top_styles = excluded.top_styles,
        updated_at = now();

  insert into consent_ledger (user_id, purpose, action, granted, policy_version, ui_text_shown, source)
  values
    (v_user, 'location', case when p_location_consent then 'granted'::consent_action else 'withdrawn'::consent_action end, p_location_consent, p_policy_version, 'Use my location for nearby breweries and local recommendations.', 'onboarding'),
    (v_user, 'aggregate_analytics', case when p_aggregate_consent then 'granted'::consent_action else 'withdrawn'::consent_action end, p_aggregate_consent, p_policy_version, 'Use my check-ins for anonymous aggregate trend reports.', 'onboarding'),
    (v_user, 'data_sale', case when p_data_sale_consent then 'granted'::consent_action else 'withdrawn'::consent_action end, p_data_sale_consent, p_policy_version, 'Include my anonymous aggregate data in partner insights.', 'onboarding');
end;
$$;

create or replace function record_privacy_choice(
  p_purpose text,
  p_granted boolean,
  p_ui_text text,
  p_policy_version text default '2026-07-08'
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
begin
  if v_user is null then
    raise exception 'not authenticated';
  end if;

  insert into consent_ledger (user_id, purpose, action, granted, policy_version, ui_text_shown, source)
  values (
    v_user,
    p_purpose,
    case when p_granted then 'granted'::consent_action else 'withdrawn'::consent_action end,
    p_granted,
    p_policy_version,
    p_ui_text,
    'profile'
  );
end;
$$;

revoke execute on function set_profile_preferences(text, boolean) from public, anon;
revoke execute on function complete_profile_onboarding(text, text[], boolean, boolean, boolean, text) from public, anon;
revoke execute on function record_privacy_choice(text, boolean, text, text) from public, anon;
grant execute on function set_profile_preferences(text, boolean) to authenticated;
grant execute on function complete_profile_onboarding(text, text[], boolean, boolean, boolean, text) to authenticated;
grant execute on function record_privacy_choice(text, boolean, text, text) to authenticated;
