-- One-tap pour logging: log_checkin accepts a NULL rating (an honest "logged,
-- unrated" quick log; a provided rating is still validated 0-5), and
-- update_checkin_details(p_checkin_id, ...) fills rating/tags/glassware/occasion
-- into that SAME check-in afterwards, so the fast path and the thoughtful path
-- never double-count a pour. Grants: authenticated only.
--
-- AUDIT FIX 2026-07-17: this file had been a comment-only stub while the real
-- DDL lived only in prod, so a DB rebuilt from source (CI, preview branch, DR,
-- `supabase db reset`) still had the OLD log_checkin that rejects a null rating
-- and had no update_checkin_details -- the one-tap core loop was dead outside
-- prod. The real function bodies are now inlined; the schema is reproducible.

create or replace function public.log_checkin(
  p_beer_id uuid,
  p_rating numeric,
  p_flavor_tags text[] default '{}'::text[],
  p_glassware text default null,
  p_occasion text default null,
  p_venue_id uuid default null,
  p_on_off_premise text default null,
  p_geo_bucket_h3 text default null,
  p_photo_url text default null,
  p_price_paid numeric default null,
  p_price_tier text default null,
  p_purchase_intent_flags jsonb default '{}'::jsonb,
  p_source text default 'manual'
) returns uuid
 language plpgsql security definer set search_path to 'public'
as $function$
declare
  v_user uuid := (select auth.uid());
  v_id uuid;
  v_beer beer_catalog%rowtype;
  v_venue venue%rowtype;
  v_occasion occasion_kind;
  v_on_off on_off_premise;
  v_price_tier price_tier_kind;
  v_sale_optin boolean := false;
  v_location_optin boolean := false;
  v_gpc boolean := false;
  v_daypart daypart_kind;
  v_season season_kind;
  v_hour int := extract(hour from now());
  v_month int := extract(month from now());
begin
  if v_user is null then raise exception 'not authenticated'; end if;
  -- NULL rating = a quick, unrated log. A provided rating must be sane.
  if p_rating is not null and (p_rating < 0 or p_rating > 5) then
    raise exception 'rating must be between 0 and 5';
  end if;

  select * into v_beer from beer_catalog where id = p_beer_id;
  if not found then raise exception 'beer not found'; end if;
  if p_venue_id is not null then select * into v_venue from venue where id = p_venue_id; end if;

  if p_occasion in ('home','bar','restaurant','event','sports','other') then v_occasion := p_occasion::occasion_kind; end if;
  if p_on_off_premise in ('on_premise','off_premise') then v_on_off := p_on_off_premise::on_off_premise;
  elsif p_venue_id is not null then v_on_off := v_venue.on_off_premise;
  elsif v_occasion = 'home' then v_on_off := 'off_premise'::on_off_premise; end if;
  if p_price_tier in ('value','mid','premium','luxury') then v_price_tier := p_price_tier::price_tier_kind; end if;

  select coalesce(granted, false) into v_sale_optin from consent_ledger where user_id = v_user and purpose = 'data_sale' order by created_at desc limit 1;
  select coalesce(granted, false) into v_location_optin from consent_ledger where user_id = v_user and purpose = 'location' order by created_at desc limit 1;
  select exists (select 1 from consent_ledger where user_id = v_user and action = 'gpc_signal' and granted = false limit 1) into v_gpc;

  v_daypart := case when v_hour between 5 and 11 then 'morning'::daypart_kind when v_hour between 12 and 16 then 'afternoon'::daypart_kind when v_hour between 17 and 22 then 'evening'::daypart_kind else 'late_night'::daypart_kind end;
  v_season := case when v_month in (12,1,2) then 'winter'::season_kind when v_month in (3,4,5) then 'spring'::season_kind when v_month in (6,7,8) then 'summer'::season_kind else 'fall'::season_kind end;

  insert into checkin_event (user_id, beer_id, brewery_id, sku_canonical_id, style, substyle, abv, ibu, srm, rating, flavor_tags, photo_url, glassware, venue_id, geo_bucket_h3, on_off_premise, occasion, day_of_week, daypart, season, consent_version, sale_optin, location_optin, gpc_flag, price_paid, price_tier, purchase_intent_flags, source)
  values (v_user, v_beer.id, v_beer.brewery_id, v_beer.sku_canonical_id, v_beer.style, v_beer.substyle, v_beer.abv, v_beer.ibu, v_beer.srm, p_rating, coalesce(p_flavor_tags, '{}'), nullif(trim(p_photo_url), ''), nullif(trim(p_glassware), ''), p_venue_id, coalesce(nullif(trim(p_geo_bucket_h3), ''), v_venue.geo_bucket_h3), v_on_off, v_occasion, extract(dow from now())::smallint, v_daypart, v_season, '2026-07-09', coalesce(v_sale_optin, false), coalesce(v_location_optin, false), coalesce(v_gpc, false), p_price_paid, v_price_tier, coalesce(p_purchase_intent_flags, '{}'), coalesce(nullif(trim(p_source), ''), 'manual'))
  returning id into v_id;
  return v_id;
end;
$function$;

create or replace function public.update_checkin_details(
  p_checkin_id uuid,
  p_rating numeric default null,
  p_flavor_tags text[] default null,
  p_glassware text default null,
  p_occasion text default null
) returns void
 language plpgsql security definer set search_path to 'public'
as $function$
declare
  v_user uuid := (select auth.uid());
  v_occasion occasion_kind;
begin
  if v_user is null then raise exception 'not authenticated'; end if;
  if p_rating is not null and (p_rating < 0 or p_rating > 5) then
    raise exception 'rating must be between 0 and 5';
  end if;
  if p_occasion in ('home','bar','restaurant','event','sports','other') then
    v_occasion := p_occasion::occasion_kind;
  end if;

  update checkin_event
  set rating      = coalesce(p_rating, rating),
      flavor_tags = coalesce(p_flavor_tags, flavor_tags),
      glassware   = coalesce(nullif(trim(p_glassware), ''), glassware),
      occasion    = coalesce(v_occasion, occasion)
  where id = p_checkin_id and user_id = v_user;
  if not found then raise exception 'check-in not found'; end if;
end;
$function$;

grant execute on function public.update_checkin_details(uuid, numeric, text[], text, text) to authenticated;