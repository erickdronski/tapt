-- 0080_release_privacy_security.sql
-- Close two launch-critical trust gaps:
--   1. only the JWT-protected verification function may add OFF products;
--   2. partner analytics use current opt-in consent and k >= 10 suppression.

revoke all on function public.add_beer_from_barcode(
  text, text, text, text, numeric, text, text
) from public, anon, authenticated, service_role;

create index if not exists beer_catalog_added_by_created
  on public.beer_catalog ((external_ids->>'added_by'), created_at desc)
  where external_ids ? 'added_by';

create or replace function public.add_verified_beer_from_barcode(
  p_user uuid,
  p_gtin text,
  p_name text,
  p_brand text default null,
  p_abv numeric default null,
  p_image_url text default null
)
returns table (
  id uuid,
  name text,
  style text,
  abv numeric,
  brewery_name text,
  country text
)
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_gtin text := regexp_replace(coalesce(p_gtin, ''), '[^0-9]', '', 'g');
  v_name text := trim(coalesce(p_name, ''));
  v_brand text := nullif(trim(coalesce(p_brand, '')), '');
  v_image_url text := nullif(trim(coalesce(p_image_url, '')), '');
  v_brewery_id uuid;
  v_beer_id uuid;
  v_recent integer;
begin
  -- EXECUTE is revoked from PUBLIC and granted only to service_role below.
  if p_user is null or not exists (select 1 from auth.users u where u.id = p_user) then
    raise exception 'valid user required';
  end if;
  if length(v_gtin) not between 8 and 14 then raise exception 'invalid barcode'; end if;
  if length(v_name) not between 2 and 160 then raise exception 'invalid name'; end if;
  if v_brand is not null and length(v_brand) > 160 then raise exception 'invalid brand'; end if;
  if p_abv is not null and (p_abv < 0 or p_abv > 70) then raise exception 'invalid abv'; end if;
  if v_image_url is not null and lower(v_image_url)
       !~ '^https://([a-z0-9-]+\.)*openfoodfacts\.(org|net)/' then
    raise exception 'invalid image source';
  end if;

  select count(*) into v_recent
  from public.beer_catalog bc
  where bc.external_ids->>'added_by' = p_user::text
    and bc.created_at > now() - interval '1 day';
  if v_recent >= 40 then raise exception 'daily add limit reached'; end if;

  select bc.id into v_beer_id
  from public.beer_catalog bc
  where bc.gtin = v_gtin
  limit 1;

  if v_beer_id is null then
    if v_brand is not null then
      select b.id into v_brewery_id
      from public.brewery b
      where lower(b.name) = lower(v_brand)
      order by b.created_at
      limit 1;

      if v_brewery_id is null then
        insert into public.brewery (name, external_ids)
        values (
          v_brand,
          jsonb_build_object(
            'source', 'open_food_facts',
            'verified_via', 'verify-barcode-beer',
            'added_by', p_user
          )
        )
        returning brewery.id into v_brewery_id;
      end if;
    end if;

    insert into public.beer_catalog (
      name, abv, is_na_low, gtin, brewery_id,
      label_image_url, label_image_license, external_ids
    )
    values (
      v_name,
      p_abv,
      coalesce(p_abv, 100) <= 0.5,
      v_gtin,
      v_brewery_id,
      v_image_url,
      case when v_image_url is not null then 'Open Food Facts (ODbL/CC-BY-SA)' end,
      jsonb_build_object(
        'off_barcode', v_gtin,
        'source', 'open_food_facts',
        'verified_via', 'verify-barcode-beer',
        'verified_at', now(),
        'added_by', p_user
      )
    )
    on conflict (gtin) where gtin is not null do nothing
    returning beer_catalog.id into v_beer_id;

    if v_beer_id is null then
      select bc.id into v_beer_id
      from public.beer_catalog bc
      where bc.gtin = v_gtin
      limit 1;
    end if;
  end if;

  return query
  select bc.id, bc.name, bc.style, bc.abv, br.name, br.country
  from public.beer_catalog bc
  left join public.brewery br on br.id = bc.brewery_id
  where bc.id = v_beer_id;
end;
$$;

revoke all on function public.add_verified_beer_from_barcode(
  uuid, text, text, text, numeric, text
) from public, anon, authenticated;
grant execute on function public.add_verified_beer_from_barcode(
  uuid, text, text, text, numeric, text
) to service_role;

create or replace function public.venue_analytics(p_venue uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v jsonb;
  f jsonb;
begin
  if not (
    public.is_admin()
    or exists (
      select 1
      from public.venue_claim vc
      where vc.venue_id = p_venue
        and vc.user_id = auth.uid()
        and vc.status = 'approved'
    )
  ) then
    raise exception 'venue not claimed/approved';
  end if;

  with eligible as (
    select ce.*
    from public.checkin_event ce
    where ce.venue_id = p_venue
      and ce.moderation_status = 'visible'
      and public.has_current_consent(ce.user_id, 'aggregate_analytics')
      and public.has_current_consent(ce.user_id, 'data_sale')
  ), counts as (
    select
      count(distinct user_id)::integer as all_users,
      count(distinct user_id) filter (
        where event_ts > now() - interval '7 days'
      )::integer as week_users
    from eligible
  )
  select jsonb_build_object(
    'pours_total', case when c.all_users >= 10 then (select count(*) from eligible) else 0 end,
    'pours_7d', case when c.week_users >= 10 then (
      select count(*) from eligible where event_ts > now() - interval '7 days'
    ) else 0 end,
    'unique_drinkers', case when c.all_users >= 10 then c.all_users else 0 end,
    'avg_rating', case when c.all_users >= 10 then (
      select round(avg(rating), 2) from eligible where rating is not null
    ) else null end,
    'top_beers', case when c.all_users >= 10 then coalesce((
      select jsonb_agg(t order by t.pours desc, t.name)
      from (
        select b.name, br.name as brewery, count(*)::integer as pours
        from eligible e
        join public.beer_catalog b on b.id = e.beer_id
        left join public.brewery br on br.id = b.brewery_id
        group by b.id, b.name, br.name
        having count(distinct e.user_id) >= 10
        order by count(*) desc, b.name
        limit 8
      ) t
    ), '[]'::jsonb) else '[]'::jsonb end,
    'privacy_threshold_met', c.all_users >= 10,
    'weekly_threshold_met', c.week_users >= 10,
    'minimum_drinkers', 10
  ) into v
  from counts c;

  with eligible as (
    select fi.*
    from public.featured_impression fi
    join public.featured_partner fp on fp.id = fi.featured_id
    where fp.venue_id = p_venue
      and fi.user_id is not null
      and public.has_current_consent(fi.user_id, 'aggregate_analytics')
      and public.has_current_consent(fi.user_id, 'data_sale')
  ), counts as (
    select
      count(distinct user_id)::integer as all_users,
      count(distinct user_id) filter (
        where created_at > now() - interval '7 days'
      )::integer as week_users
    from eligible
  ), events as (
    select
      count(*) filter (where event = 'impression')::integer as impressions,
      count(*) filter (where event = 'tap')::integer as taps,
      count(*) filter (
        where event = 'impression' and created_at > now() - interval '7 days'
      )::integer as impressions_7d
    from eligible
  )
  select jsonb_build_object(
    'active_campaigns', (
      select count(*)
      from public.featured_partner fp
      where fp.venue_id = p_venue
        and fp.active
        and (fp.ends_at is null or fp.ends_at > now())
    ),
    'impressions_total', case when c.all_users >= 10 then e.impressions else 0 end,
    'impressions_7d', case when c.week_users >= 10 then e.impressions_7d else 0 end,
    'taps_total', case when c.all_users >= 10 then e.taps else 0 end,
    'ctr_pct', case when c.all_users >= 10 and e.impressions > 0
      then round(e.taps::numeric * 100 / e.impressions, 1) else null end,
    'reached_drinkers', case when c.all_users >= 10 then c.all_users else 0 end,
    'privacy_threshold_met', c.all_users >= 10,
    'minimum_drinkers', 10
  ) into f
  from counts c cross join events e;

  return v || jsonb_build_object('featured', f);
end;
$$;

revoke all on function public.venue_analytics(uuid) from public, anon;
grant execute on function public.venue_analytics(uuid) to authenticated;
