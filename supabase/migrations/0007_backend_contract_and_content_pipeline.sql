-- 0007_backend_contract_and_content_pipeline.sql
-- App-safe write contracts, ingestion job control, beer-world content, and
-- map/radar seed data for a populated Tapt experience while first-party data grows.

-- ============================================================ trend view repair
create or replace view beer_trend_feed
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
order by bt.beer_id, bt.region, bt.updated_at desc nulls last, bt.beer_id;

grant select on beer_trend_feed to anon, authenticated;

-- ============================================================ ingestion control plane
create table if not exists ingestion_run (
  id uuid primary key default gen_random_uuid(),
  source_id text references ingestion_source(id) on delete set null,
  run_kind text not null check (run_kind in ('brewery','venue','beer_catalog','barcode','style','first_party','aggregate','region_guide')),
  status text not null default 'queued' check (status in ('queued','running','succeeded','failed','partial','canceled')),
  cursor_token text,
  records_seen int not null default 0,
  records_inserted int not null default 0,
  records_updated int not null default 0,
  records_rejected int not null default 0,
  error_text text,
  metadata jsonb not null default '{}',
  started_at timestamptz,
  finished_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger t_ingestion_run_updated
before update on ingestion_run
for each row execute function set_updated_at();

create index if not exists ingestion_run_source_status on ingestion_run (source_id, status, created_at desc);

create table if not exists ingestion_stage_object (
  id uuid primary key default gen_random_uuid(),
  run_id uuid not null references ingestion_run(id) on delete cascade,
  source_id text not null references ingestion_source(id) on delete cascade,
  object_type text not null check (object_type in ('brewery','venue','beer','sku','style','region_guide')),
  external_id text not null,
  payload jsonb not null default '{}',
  payload_hash text,
  normalized_name text,
  license_class text not null default 'unknown' check (license_class in ('permissive','attribution','share_alike','commercial','unknown','restricted')),
  commercial_use_allowed boolean not null default false,
  export_allowed boolean not null default false,
  quarantine_reason text,
  confidence numeric(4,3) check (confidence is null or (confidence >= 0 and confidence <= 1)),
  status text not null default 'staged' check (status in ('staged','matched','queued','merged','rejected','quarantined')),
  match_object_id uuid,
  error_text text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (source_id, object_type, external_id)
);

create trigger t_ingestion_stage_object_updated
before update on ingestion_stage_object
for each row execute function set_updated_at();

create index if not exists ingestion_stage_run on ingestion_stage_object (run_id, status);
create index if not exists ingestion_stage_lookup on ingestion_stage_object (source_id, object_type, external_id);
create index if not exists ingestion_stage_name_trgm on ingestion_stage_object using gin (normalized_name gin_trgm_ops);

create table if not exists canonical_merge_queue (
  id uuid primary key default gen_random_uuid(),
  stage_object_id uuid references ingestion_stage_object(id) on delete cascade,
  object_type text not null check (object_type in ('brewery','venue','beer','sku','style','region_guide')),
  candidate_object_id uuid,
  proposed_action text not null check (proposed_action in ('create','update','link','reject','manual_review')),
  status text not null default 'queued' check (status in ('queued','approved','applied','rejected')),
  confidence numeric(4,3) check (confidence is null or (confidence >= 0 and confidence <= 1)),
  reason text,
  payload jsonb not null default '{}',
  reviewed_by uuid references user_profile(id) on delete set null,
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger t_canonical_merge_queue_updated
before update on canonical_merge_queue
for each row execute function set_updated_at();

create index if not exists canonical_merge_status on canonical_merge_queue (status, created_at);
create index if not exists canonical_merge_stage on canonical_merge_queue (stage_object_id);

alter table ingestion_run enable row level security;
alter table ingestion_stage_object enable row level security;
alter table canonical_merge_queue enable row level security;

revoke all on ingestion_run, ingestion_stage_object, canonical_merge_queue from anon, authenticated;
grant select, insert, update on ingestion_run, ingestion_stage_object, canonical_merge_queue to service_role;

create or replace function record_ingestion_run(
  p_source_id text,
  p_run_kind text,
  p_status text default 'running',
  p_metadata jsonb default '{}'
)
returns uuid
language plpgsql
set search_path = public
as $$
declare
  v_id uuid;
begin
  insert into ingestion_run (source_id, run_kind, status, metadata, started_at)
  values (p_source_id, p_run_kind, p_status, coalesce(p_metadata, '{}'), now())
  returning id into v_id;

  return v_id;
end;
$$;

create or replace function stage_ingestion_record(
  p_run_id uuid,
  p_source_id text,
  p_object_type text,
  p_external_id text,
  p_payload jsonb,
  p_normalized_name text default null,
  p_license_class text default 'unknown',
  p_commercial_use_allowed boolean default false,
  p_export_allowed boolean default false,
  p_confidence numeric default null
)
returns uuid
language plpgsql
set search_path = public
as $$
declare
  v_id uuid;
begin
  insert into ingestion_stage_object (
    run_id,
    source_id,
    object_type,
    external_id,
    payload,
    payload_hash,
    normalized_name,
    license_class,
    commercial_use_allowed,
    export_allowed,
    confidence,
    status
  )
  values (
    p_run_id,
    p_source_id,
    p_object_type,
    p_external_id,
    coalesce(p_payload, '{}'),
    md5(coalesce(p_payload, '{}')::text),
    nullif(trim(p_normalized_name), ''),
    coalesce(p_license_class, 'unknown'),
    coalesce(p_commercial_use_allowed, false),
    coalesce(p_export_allowed, false),
    p_confidence,
    case when coalesce(p_commercial_use_allowed, false) then 'staged' else 'quarantined' end
  )
  on conflict (source_id, object_type, external_id) do update
    set run_id = excluded.run_id,
        payload = excluded.payload,
        payload_hash = excluded.payload_hash,
        normalized_name = excluded.normalized_name,
        license_class = excluded.license_class,
        commercial_use_allowed = excluded.commercial_use_allowed,
        export_allowed = excluded.export_allowed,
        confidence = excluded.confidence,
        status = excluded.status,
        updated_at = now()
  returning id into v_id;

  return v_id;
end;
$$;

revoke execute on function record_ingestion_run(text, text, text, jsonb) from public, anon, authenticated;
revoke execute on function stage_ingestion_record(uuid, text, text, text, jsonb, text, text, boolean, boolean, numeric) from public, anon, authenticated;
grant execute on function record_ingestion_run(text, text, text, jsonb) to service_role;
grant execute on function stage_ingestion_record(uuid, text, text, text, jsonb, text, text, boolean, boolean, numeric) to service_role;

-- ============================================================ check-in contract and moderation
do $$
begin
  create type price_tier_kind as enum ('value','mid','premium','luxury');
exception when duplicate_object then null;
end $$;

alter table checkin_event
  add column if not exists price_paid numeric(6,2),
  add column if not exists price_tier price_tier_kind,
  add column if not exists purchase_intent_flags jsonb not null default '{}',
  add column if not exists moderation_status text not null default 'visible'
    check (moderation_status in ('visible','hidden','removed','under_review')),
  add column if not exists source text not null default 'manual';

create index if not exists checkin_event_moderation on checkin_event (moderation_status, event_ts desc);
create index if not exists checkin_event_venue_time on checkin_event (venue_id, event_ts desc);
create index if not exists checkin_event_brewery on checkin_event (brewery_id);
create index if not exists checkin_event_sku on checkin_event (sku_canonical_id);

create unique index if not exists content_report_dedupe
on content_report (reporter_id, target_type, target_id, reason);

alter table content_report
  add column if not exists updated_at timestamptz not null default now();

drop trigger if exists t_content_report_updated on content_report;
create trigger t_content_report_updated
before update on content_report
for each row execute function set_updated_at();

create table if not exists moderation_action (
  id uuid primary key default gen_random_uuid(),
  report_id uuid references content_report(id) on delete set null,
  moderator_id uuid references user_profile(id) on delete set null,
  target_type text not null check (target_type in ('user','checkin','venue','beer','session','crew','tap_item')),
  target_id uuid not null,
  action_type text not null check (action_type in ('note','hide','restore','warn','block','dismiss','remove','merge_correction')),
  note text,
  created_at timestamptz not null default now()
);

create index if not exists moderation_action_target on moderation_action (target_type, target_id, created_at desc);
alter table moderation_action enable row level security;
revoke all on moderation_action from anon, authenticated;
grant select, insert on moderation_action to service_role;

create or replace function log_checkin(
  p_beer_id uuid,
  p_rating numeric,
  p_flavor_tags text[] default '{}',
  p_glassware text default null,
  p_occasion text default null,
  p_venue_id uuid default null,
  p_on_off_premise text default null,
  p_geo_bucket_h3 text default null,
  p_photo_url text default null,
  p_price_paid numeric default null,
  p_price_tier text default null,
  p_purchase_intent_flags jsonb default '{}',
  p_source text default 'manual'
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
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
  if v_user is null then
    raise exception 'not authenticated';
  end if;

  if p_rating is null or p_rating < 0 or p_rating > 5 then
    raise exception 'rating must be between 0 and 5';
  end if;

  select * into v_beer from beer_catalog where id = p_beer_id;
  if not found then
    raise exception 'beer not found';
  end if;

  if p_venue_id is not null then
    select * into v_venue from venue where id = p_venue_id;
  end if;

  if p_occasion in ('home','bar','restaurant','event','sports','other') then
    v_occasion := p_occasion::occasion_kind;
  end if;

  if p_on_off_premise in ('on_premise','off_premise') then
    v_on_off := p_on_off_premise::on_off_premise;
  elsif p_venue_id is not null then
    v_on_off := v_venue.on_off_premise;
  elsif v_occasion = 'home' then
    v_on_off := 'off_premise'::on_off_premise;
  end if;

  if p_price_tier in ('value','mid','premium','luxury') then
    v_price_tier := p_price_tier::price_tier_kind;
  end if;

  select coalesce(granted, false) into v_sale_optin
  from consent_ledger
  where user_id = v_user and purpose = 'data_sale'
  order by created_at desc
  limit 1;

  select coalesce(granted, false) into v_location_optin
  from consent_ledger
  where user_id = v_user and purpose = 'location'
  order by created_at desc
  limit 1;

  select exists (
    select 1
    from consent_ledger
    where user_id = v_user
      and action = 'gpc_signal'
      and granted = false
    order by created_at desc
    limit 1
  ) into v_gpc;

  v_daypart := case
    when v_hour between 5 and 11 then 'morning'::daypart_kind
    when v_hour between 12 and 16 then 'afternoon'::daypart_kind
    when v_hour between 17 and 22 then 'evening'::daypart_kind
    else 'late_night'::daypart_kind
  end;

  v_season := case
    when v_month in (12,1,2) then 'winter'::season_kind
    when v_month in (3,4,5) then 'spring'::season_kind
    when v_month in (6,7,8) then 'summer'::season_kind
    else 'fall'::season_kind
  end;

  insert into checkin_event (
    user_id,
    beer_id,
    brewery_id,
    sku_canonical_id,
    style,
    substyle,
    abv,
    ibu,
    srm,
    rating,
    flavor_tags,
    photo_url,
    glassware,
    venue_id,
    geo_bucket_h3,
    on_off_premise,
    occasion,
    day_of_week,
    daypart,
    season,
    consent_version,
    sale_optin,
    location_optin,
    gpc_flag,
    price_paid,
    price_tier,
    purchase_intent_flags,
    source
  )
  values (
    v_user,
    v_beer.id,
    v_beer.brewery_id,
    v_beer.sku_canonical_id,
    v_beer.style,
    v_beer.substyle,
    v_beer.abv,
    v_beer.ibu,
    v_beer.srm,
    p_rating,
    coalesce(p_flavor_tags, '{}'),
    nullif(trim(p_photo_url), ''),
    nullif(trim(p_glassware), ''),
    p_venue_id,
    coalesce(nullif(trim(p_geo_bucket_h3), ''), v_venue.geo_bucket_h3),
    v_on_off,
    v_occasion,
    extract(dow from now())::smallint,
    v_daypart,
    v_season,
    '2026-07-09',
    coalesce(v_sale_optin, false),
    coalesce(v_location_optin, false),
    coalesce(v_gpc, false),
    p_price_paid,
    v_price_tier,
    coalesce(p_purchase_intent_flags, '{}'),
    coalesce(nullif(trim(p_source), ''), 'manual')
  )
  returning id into v_id;

  return v_id;
end;
$$;

revoke execute on function log_checkin(uuid, numeric, text[], text, text, uuid, text, text, text, numeric, text, jsonb, text) from public, anon;
grant execute on function log_checkin(uuid, numeric, text[], text, text, uuid, text, text, text, numeric, text, jsonb, text) to authenticated;

create or replace function enforce_checkin_review_owner()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (
    select 1
    from checkin_event c
    where c.id = new.checkin_id
      and c.user_id = new.user_id
  ) then
    raise exception 'review owner must match check-in owner';
  end if;

  return new;
end;
$$;

drop trigger if exists t_checkin_review_owner on checkin_review;
create trigger t_checkin_review_owner
before insert or update on checkin_review
for each row execute function enforce_checkin_review_owner();

create or replace function report_content(
  p_target_type text,
  p_target_id uuid,
  p_reason text,
  p_details text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := (select auth.uid());
  v_id uuid;
begin
  if v_user is null then
    raise exception 'not authenticated';
  end if;

  insert into content_report (reporter_id, target_type, target_id, reason, details)
  values (v_user, p_target_type, p_target_id, nullif(trim(p_reason), ''), nullif(trim(p_details), ''))
  on conflict (reporter_id, target_type, target_id, reason) do update
    set details = coalesce(excluded.details, content_report.details),
        status = 'open',
        updated_at = now()
  returning id into v_id;

  if p_target_type = 'checkin' then
    update checkin_event
    set moderation_status = 'under_review'
    where id = p_target_id
      and moderation_status = 'visible';
  end if;

  return v_id;
end;
$$;

create or replace function block_user(p_blocked_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := (select auth.uid());
begin
  if v_user is null then
    raise exception 'not authenticated';
  end if;

  if p_blocked_id = v_user then
    raise exception 'cannot block yourself';
  end if;

  insert into user_block (blocker_id, blocked_id)
  values (v_user, p_blocked_id)
  on conflict (blocker_id, blocked_id) do nothing;
end;
$$;

create or replace function submit_venue_correction(
  p_venue_id uuid,
  p_correction_type text,
  p_suggested_value jsonb default '{}',
  p_note text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := (select auth.uid());
  v_id uuid;
begin
  if v_user is null then
    raise exception 'not authenticated';
  end if;

  insert into venue_correction (venue_id, submitted_by, correction_type, suggested_value, note)
  values (p_venue_id, v_user, p_correction_type, coalesce(p_suggested_value, '{}'), nullif(trim(p_note), ''))
  returning id into v_id;

  return v_id;
end;
$$;

revoke execute on function report_content(text, uuid, text, text) from public, anon;
revoke execute on function block_user(uuid) from public, anon;
revoke execute on function submit_venue_correction(uuid, text, jsonb, text) from public, anon;
grant execute on function report_content(text, uuid, text, text) to authenticated;
grant execute on function block_user(uuid) to authenticated;
grant execute on function submit_venue_correction(uuid, text, jsonb, text) to authenticated;

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
  v_user uuid := (select auth.uid());
  v_purpose consent_purpose;
begin
  if v_user is null then
    raise exception 'not authenticated';
  end if;

  if p_purpose not in ('essential','location','personalization','aggregate_analytics','data_sale','marketing') then
    raise exception 'unsupported consent purpose';
  end if;

  v_purpose := p_purpose::consent_purpose;

  insert into consent_ledger (user_id, purpose, action, granted, policy_version, ui_text_shown, source)
  values (
    v_user,
    v_purpose,
    case when p_granted then 'granted'::consent_action else 'withdrawn'::consent_action end,
    p_granted,
    coalesce(nullif(trim(p_policy_version), ''), '2026-07-08'),
    case v_purpose
      when 'location'::consent_purpose then 'Use my location for nearby breweries and local recommendations.'
      when 'aggregate_analytics'::consent_purpose then 'Use my check-ins for anonymous aggregate trend reports.'
      when 'data_sale'::consent_purpose then 'Include my anonymous aggregate data in partner insights.'
      when 'personalization'::consent_purpose then 'Use my pours to personalize matches and style recommendations.'
      when 'marketing'::consent_purpose then 'Send me beer, brewery, and event updates.'
      else 'Use required data to operate Tapt.'
    end,
    'profile'
  );
end;
$$;

revoke execute on function record_privacy_choice(text, boolean, text, text) from public, anon;
grant execute on function record_privacy_choice(text, boolean, text, text) to authenticated;

-- ============================================================ beer-world content and map seeds
create table if not exists region_beer_guide (
  id text primary key,
  scope text not null check (scope in ('state','country','global')),
  name text not null,
  country text not null,
  state_code text,
  flag text,
  hero_style text not null,
  flavor_notes text[] not null default '{}',
  signature_drinks text[] not null default '{}',
  top_styles text[] not null default '{}',
  cellar_prompt text not null,
  passport_phrase text not null,
  latitude numeric(9,6),
  longitude numeric(9,6),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger t_region_beer_guide_updated
before update on region_beer_guide
for each row execute function set_updated_at();

alter table region_beer_guide enable row level security;

drop policy if exists region_beer_guide_public_read on region_beer_guide;
create policy region_beer_guide_public_read
on region_beer_guide
for select to anon, authenticated
using (true);

grant select on region_beer_guide to anon, authenticated;

insert into region_beer_guide (
  id, scope, name, country, state_code, flag, hero_style, flavor_notes,
  signature_drinks, top_styles, cellar_prompt, passport_phrase, latitude, longitude
)
values
  ('us-al', 'state', 'Alabama', 'United States', 'AL', 'US', 'Southern pale ale', array['citrus','light malt','porch-friendly'], array['pale ale','wheat ale','porter'], array['Pale Ale','Wheat','Porter'], 'Build an easygoing Southern shelf with pale ales and patio beers.', 'Alabama stamp: bright, social, and built for warm nights.', 32.806671, -86.791130),
  ('us-ak', 'state', 'Alaska', 'United States', 'AK', 'US', 'Amber ale', array['caramel','spruce','crisp air'], array['amber ale','smoked porter','winter ale'], array['Amber Ale','Porter','Winter Ale'], 'Your Alaska shelf leans rugged: amber, roast, and cold-weather depth.', 'Alaska stamp: northern malt and frontier roast.', 61.370716, -152.404419),
  ('us-az', 'state', 'Arizona', 'United States', 'AZ', 'US', 'Desert IPA', array['pine','citrus','dry finish'], array['west coast IPA','lager','fruited sour'], array['IPA','Lager','Sour'], 'Make the Arizona row crisp, dry, and sunlit.', 'Arizona stamp: desert hops and clean finishes.', 33.729759, -111.431221),
  ('us-ca', 'state', 'California', 'United States', 'CA', 'US', 'West Coast IPA', array['pine','resin','grapefruit'], array['west coast IPA','hazy IPA','pilsner'], array['West Coast IPA','Hazy IPA','Pilsner'], 'California turns your Cellar into a hop coastline.', 'California stamp: the modern IPA engine room.', 36.116203, -119.681564),
  ('us-co', 'state', 'Colorado', 'United States', 'CO', 'US', 'Mountain IPA', array['fresh hop','pine','clean malt'], array['IPA','amber ale','pilsner'], array['IPA','Amber Ale','Pilsner'], 'Colorado adds a mountain row: bright hops, clean lagers, taproom classics.', 'Colorado stamp: alpine hops and brewery trail energy.', 39.059811, -105.311104),
  ('us-de', 'state', 'Delaware', 'United States', 'DE', 'US', 'Experimental ale', array['culinary','fruit','offbeat'], array['creative ale','IPA','sour'], array['Experimental Ale','IPA','Sour'], 'Delaware unlocks the weird-and-wonderful shelf.', 'Delaware stamp: small state, wild ideas.', 39.318523, -75.507141),
  ('us-fl', 'state', 'Florida', 'United States', 'FL', 'US', 'Citrus IPA', array['orange','tropical','bright acidity'], array['citrus IPA','lager','fruited sour'], array['IPA','Lager','Fruited Sour'], 'Florida brings sunshine, citrus, and poolside crushability.', 'Florida stamp: tropical hops and patio refreshers.', 27.766279, -81.686783),
  ('us-ga', 'state', 'Georgia', 'United States', 'GA', 'US', 'Tropical IPA', array['peach','citrus','soft hops'], array['IPA','pilsner','saison'], array['IPA','Pilsner','Saison'], 'Georgia adds a bright, peach-toned shelf to the Cellar.', 'Georgia stamp: Southern fruit and crisp taproom lagers.', 33.040619, -83.643074),
  ('us-il', 'state', 'Illinois', 'United States', 'IL', 'US', 'Deep-dish stout', array['roast','chocolate','city malt'], array['stout','IPA','lager'], array['Stout','IPA','Lager'], 'Illinois gives the Cellar a city-beer mix: roast, hops, and tavern lagers.', 'Illinois stamp: Chicago malt, hops, and neighborhood taps.', 40.349457, -88.986137),
  ('us-ma', 'state', 'Massachusetts', 'United States', 'MA', 'US', 'New England IPA', array['hazy','tropical','soft body'], array['hazy IPA','porter','pilsner'], array['Hazy IPA','Porter','Pilsner'], 'Massachusetts builds your hazy shelf fast.', 'Massachusetts stamp: soft haze and colonial pub roots.', 42.230171, -71.530106),
  ('us-me', 'state', 'Maine', 'United States', 'ME', 'US', 'Belgian-style white', array['coriander','citrus','coastal'], array['white ale','IPA','stout'], array['Witbier','IPA','Stout'], 'Maine adds coastal refreshers and piney hops.', 'Maine stamp: sea air, white ale, and pine hops.', 44.693947, -69.381927),
  ('us-mi', 'state', 'Michigan', 'United States', 'MI', 'US', 'Two-hearted IPA', array['pine','malt balance','lake effect'], array['IPA','porter','lager'], array['IPA','Porter','Lager'], 'Michigan makes your shelf feel like a Great Lakes tap list.', 'Michigan stamp: lake country hops and malt balance.', 43.326618, -84.536095),
  ('us-mn', 'state', 'Minnesota', 'United States', 'MN', 'US', 'Cold-weather IPA', array['pine','clean bitterness','winter malt'], array['IPA','cream ale','dark lager'], array['IPA','Cream Ale','Dark Lager'], 'Minnesota adds a cold-weather row with crisp bitterness.', 'Minnesota stamp: lakes, saisons, and winter-ready malt.', 45.694454, -93.900192),
  ('us-mo', 'state', 'Missouri', 'United States', 'MO', 'US', 'Foeder ale', array['oak','tart','heritage lager'], array['foeder ale','lager','pale ale'], array['Sour','Lager','Pale Ale'], 'Missouri mixes classic lager roots with serious cellar sour energy.', 'Missouri stamp: lager history and barrel-room depth.', 38.456085, -92.288368),
  ('us-nc', 'state', 'North Carolina', 'United States', 'NC', 'US', 'Blue Ridge IPA', array['pine','stone fruit','soft malt'], array['IPA','porter','farmhouse ale'], array['IPA','Porter','Farmhouse Ale'], 'North Carolina gives the Cellar a mountain-meets-city beer trail.', 'North Carolina stamp: Blue Ridge hops and Asheville energy.', 35.630066, -79.806419),
  ('us-nj', 'state', 'New Jersey', 'United States', 'NJ', 'US', 'Shore IPA', array['citrus','pine','boardwalk crisp'], array['IPA','lager','porter'], array['IPA','Lager','Porter'], 'New Jersey adds shore-day hops and neighborhood taproom lagers.', 'New Jersey stamp: local hops with beach-town momentum.', 40.298904, -74.521011),
  ('us-ny', 'state', 'New York', 'United States', 'NY', 'US', 'Empire hazy IPA', array['hazy','orchard fruit','city edge'], array['hazy IPA','lager','stout'], array['Hazy IPA','Lager','Stout'], 'New York brings borough haze, farmhouse range, and crisp lagers.', 'New York stamp: city heat and upstate harvest.', 42.165726, -74.948051),
  ('us-oh', 'state', 'Ohio', 'United States', 'OH', 'US', 'Midwest IPA', array['balanced hops','toasty malt','pub-friendly'], array['IPA','cream ale','stout'], array['IPA','Cream Ale','Stout'], 'Ohio gives your shelf a sturdy Midwest pub backbone.', 'Ohio stamp: balanced taps and neighborhood beer halls.', 40.388783, -82.764915),
  ('us-or', 'state', 'Oregon', 'United States', 'OR', 'US', 'Fresh hop ale', array['green hop','pine','forest'], array['fresh hop ale','IPA','pilsner'], array['Fresh Hop Ale','IPA','Pilsner'], 'Oregon turns your Cellar into a hop harvest trail.', 'Oregon stamp: fresh-hop country and forest pints.', 44.572021, -122.070938),
  ('us-pa', 'state', 'Pennsylvania', 'United States', 'PA', 'US', 'Keystone lager', array['crisp','toasty','old pub'], array['lager','porter','IPA'], array['Lager','Porter','IPA'], 'Pennsylvania adds old-brewery history and modern taproom range.', 'Pennsylvania stamp: lager roots and city-beer revival.', 40.590752, -77.209755),
  ('us-tx', 'state', 'Texas', 'United States', 'TX', 'US', 'Hill Country lager', array['crisp','lime','oak'], array['lager','IPA','wild ale'], array['Lager','IPA','Wild Ale'], 'Texas adds a big, varied shelf: crisp lagers, barbecue beers, and wild ales.', 'Texas stamp: hill-country refreshers and big taproom energy.', 31.054487, -97.563461),
  ('us-vt', 'state', 'Vermont', 'United States', 'VT', 'US', 'Farmhouse IPA', array['soft haze','pastoral','yeast spice'], array['farmhouse ale','hazy IPA','pilsner'], array['Farmhouse Ale','Hazy IPA','Pilsner'], 'Vermont builds the pastoral shelf: soft haze, saisons, and small-town icons.', 'Vermont stamp: farmhouse haze and green mountain beer.', 44.045876, -72.710686),
  ('us-wa', 'state', 'Washington', 'United States', 'WA', 'US', 'Yakima hop IPA', array['fresh hop','dank','citrus'], array['fresh hop IPA','pilsner','porter'], array['Fresh Hop IPA','Pilsner','Porter'], 'Washington gives your Cellar the hop-field row.', 'Washington stamp: Yakima aroma and Pacific Northwest crisp.', 47.400902, -121.490494),
  ('be', 'country', 'Belgium', 'Belgium', null, 'BE', 'Trappist ale', array['yeast spice','dark fruit','dry finish'], array['dubbel','tripel','lambic'], array['Dubbel','Tripel','Lambic'], 'Belgium opens the monastery-and-cellar shelf.', 'Belgium stamp: yeast, patience, and world-class tradition.', 50.503887, 4.469936),
  ('cz', 'country', 'Czechia', 'Czechia', null, 'CZ', 'Pilsner', array['spicy hop','soft malt','crisp finish'], array['pilsner','dark lager','svetle'], array['Pilsner','Dark Lager','Czech Lager'], 'Czechia adds the golden-lager origin shelf.', 'Czechia stamp: clean pours and Saaz snap.', 49.817492, 15.472962),
  ('de', 'country', 'Germany', 'Germany', null, 'DE', 'Helles', array['bread crust','soft malt','clean lager'], array['helles','weissbier','bock'], array['Helles','Weissbier','Bock'], 'Germany brings the precision lager shelf.', 'Germany stamp: Prost, foam, and clean malt.', 51.165691, 10.451526),
  ('ie', 'country', 'Ireland', 'Ireland', null, 'IE', 'Dry stout', array['coffee','roast','creamy'], array['dry stout','red ale','lager'], array['Dry Stout','Red Ale','Lager'], 'Ireland adds roast, pub warmth, and creamy dark pours.', 'Ireland stamp: pub culture and roasty classics.', 53.412910, -8.243890),
  ('jp', 'country', 'Japan', 'Japan', null, 'JP', 'Rice lager', array['crisp','delicate','clean'], array['rice lager','yuzu ale','pilsner'], array['Rice Lager','Fruit Ale','Pilsner'], 'Japan adds a precise, delicate shelf with crisp lagers and citrus accents.', 'Japan stamp: Kanpai, clean lines, and bright detail.', 36.204824, 138.252924),
  ('mx', 'country', 'Mexico', 'Mexico', null, 'MX', 'Mexican lager', array['lime','corn sweetness','crisp'], array['lager','vienna lager','chelada'], array['Lager','Vienna Lager','Michelada'], 'Mexico adds the sunshine-lager row.', 'Mexico stamp: Salud, crisp lager, and patio energy.', 23.634501, -102.552784),
  ('pl', 'country', 'Poland', 'Poland', null, 'PL', 'Baltic porter', array['dark fruit','roast','smooth lager yeast'], array['baltic porter','pilsner','grodziskie'], array['Baltic Porter','Pilsner','Grodziskie'], 'Poland adds a dark, smooth Baltic porter shelf.', 'Poland stamp: Na zdrowie and porter depth.', 51.919438, 19.145136),
  ('uk', 'country', 'United Kingdom', 'United Kingdom', null, 'GB', 'Cask bitter', array['biscuit','earthy hop','pub pint'], array['bitter','porter','pale ale'], array['Bitter','Porter','Pale Ale'], 'The UK adds cask-pub texture and classic malt balance.', 'UK stamp: pub pints, bitter, and porter history.', 55.378051, -3.435973)
on conflict (id) do update
set hero_style = excluded.hero_style,
    flavor_notes = excluded.flavor_notes,
    signature_drinks = excluded.signature_drinks,
    top_styles = excluded.top_styles,
    cellar_prompt = excluded.cellar_prompt,
    passport_phrase = excluded.passport_phrase,
    latitude = excluded.latitude,
    longitude = excluded.longitude,
    updated_at = now();

with seed (seed_id, name, city, region, country, lat, lon, source_note) as (
  values
    ('seed-us-ca-sierra-nevada', 'Sierra Nevada Brewing Co.', 'Chico', 'California', 'United States', 39.724000, -121.815000, 'Tapt curated map seed'),
    ('seed-us-ca-russian-river', 'Russian River Brewing Company', 'Santa Rosa', 'California', 'United States', 38.440400, -122.714100, 'Tapt curated map seed'),
    ('seed-us-ca-stone', 'Stone Brewing', 'Escondido', 'California', 'United States', 33.119200, -117.119000, 'Tapt curated map seed'),
    ('seed-us-co-new-belgium', 'New Belgium Brewing', 'Fort Collins', 'Colorado', 'United States', 40.593000, -105.067000, 'Tapt curated map seed'),
    ('seed-us-co-odell', 'Odell Brewing Co.', 'Fort Collins', 'Colorado', 'United States', 40.589200, -105.079100, 'Tapt curated map seed'),
    ('seed-us-de-dogfish', 'Dogfish Head Craft Brewery', 'Milton', 'Delaware', 'United States', 38.777600, -75.309900, 'Tapt curated map seed'),
    ('seed-us-fl-cigar-city', 'Cigar City Brewing', 'Tampa', 'Florida', 'United States', 27.959000, -82.509000, 'Tapt curated map seed'),
    ('seed-us-ga-creature-comforts', 'Creature Comforts Brewing Co.', 'Athens', 'Georgia', 'United States', 33.959000, -83.373000, 'Tapt curated map seed'),
    ('seed-us-il-revolution', 'Revolution Brewing', 'Chicago', 'Illinois', 'United States', 41.920000, -87.703000, 'Tapt curated map seed'),
    ('seed-us-ma-tree-house', 'Tree House Brewing Company', 'Charlton', 'Massachusetts', 'United States', 42.137000, -72.002000, 'Tapt curated map seed'),
    ('seed-us-me-allagash', 'Allagash Brewing Company', 'Portland', 'Maine', 'United States', 43.704000, -70.318000, 'Tapt curated map seed'),
    ('seed-us-mi-bells', 'Bells Brewery', 'Kalamazoo', 'Michigan', 'United States', 42.292000, -85.587000, 'Tapt curated map seed'),
    ('seed-us-mn-surly', 'Surly Brewing Co.', 'Minneapolis', 'Minnesota', 'United States', 44.973000, -93.209000, 'Tapt curated map seed'),
    ('seed-us-mo-side-project', 'Side Project Brewing', 'Maplewood', 'Missouri', 'United States', 38.611000, -90.331000, 'Tapt curated map seed'),
    ('seed-us-nc-burial', 'Burial Beer Co.', 'Asheville', 'North Carolina', 'United States', 35.588000, -82.554000, 'Tapt curated map seed'),
    ('seed-us-nj-kane', 'Kane Brewing Company', 'Ocean Township', 'New Jersey', 'United States', 40.251000, -74.042000, 'Tapt curated map seed'),
    ('seed-us-ny-other-half', 'Other Half Brewing', 'Brooklyn', 'New York', 'United States', 40.673000, -74.003000, 'Tapt curated map seed'),
    ('seed-us-oh-rhinegeist', 'Rhinegeist Brewery', 'Cincinnati', 'Ohio', 'United States', 39.117000, -84.520000, 'Tapt curated map seed'),
    ('seed-us-or-deschutes', 'Deschutes Brewery', 'Bend', 'Oregon', 'United States', 44.059000, -121.315000, 'Tapt curated map seed'),
    ('seed-us-pa-yuengling', 'Yuengling Brewery', 'Pottsville', 'Pennsylvania', 'United States', 40.685000, -76.195000, 'Tapt curated map seed'),
    ('seed-us-tx-jester-king', 'Jester King Brewery', 'Austin', 'Texas', 'United States', 30.231000, -97.999000, 'Tapt curated map seed'),
    ('seed-us-vt-hill-farmstead', 'Hill Farmstead Brewery', 'Greensboro Bend', 'Vermont', 'United States', 44.594000, -72.262000, 'Tapt curated map seed'),
    ('seed-us-wa-fremont', 'Fremont Brewing', 'Seattle', 'Washington', 'United States', 47.653000, -122.351000, 'Tapt curated map seed'),
    ('seed-be-cantillon', 'Brasserie Cantillon', 'Brussels', 'Brussels', 'Belgium', 50.842000, 4.336000, 'Tapt curated map seed'),
    ('seed-cz-pilsner-urquell', 'Pilsner Urquell Brewery', 'Plzen', 'Plzen', 'Czechia', 49.747000, 13.387000, 'Tapt curated map seed'),
    ('seed-de-weihenstephan', 'Bayerische Staatsbrauerei Weihenstephan', 'Freising', 'Bavaria', 'Germany', 48.395000, 11.729000, 'Tapt curated map seed'),
    ('seed-ie-guinness', 'Guinness Storehouse', 'Dublin', 'Dublin', 'Ireland', 53.342000, -6.286000, 'Tapt curated map seed'),
    ('seed-jp-kiuchi', 'Kiuchi Brewery', 'Naka', 'Ibaraki', 'Japan', 36.457000, 140.493000, 'Tapt curated map seed'),
    ('seed-mx-minerva', 'Cerveceria Minerva', 'Guadalajara', 'Jalisco', 'Mexico', 20.676000, -103.379000, 'Tapt curated map seed'),
    ('seed-pl-browar-stu-mostow', 'Browar Stu Mostow', 'Wroclaw', 'Lower Silesia', 'Poland', 51.107000, 17.038000, 'Tapt curated map seed'),
    ('seed-uk-brewdog', 'BrewDog HQ', 'Ellon', 'Scotland', 'United Kingdom', 57.364000, -2.073000, 'Tapt curated map seed')
)
insert into venue (name, poi_category, on_off_premise, geo, geo_bucket_h3, external_ids)
select
  seed.name,
  'brewery',
  'on_premise'::on_off_premise,
  st_setsrid(st_makepoint(seed.lon, seed.lat), 4326)::geography,
  lower(replace(coalesce(seed.country, 'global'), ' ', '-')) || ':' || lower(replace(coalesce(seed.region, 'region'), ' ', '-')),
  jsonb_build_object(
    'tapt_seed', seed.seed_id,
    'city', seed.city,
    'region', seed.region,
    'country', seed.country,
    'source_note', seed.source_note
  )
from seed
where not exists (
  select 1
  from venue v
  where v.external_ids->>'tapt_seed' = seed.seed_id
);

create or replace function brewery_map_feed(
  p_limit int default 200
)
returns table (
  venue_id uuid,
  name text,
  city text,
  region text,
  country text,
  latitude numeric,
  longitude numeric,
  source_label text,
  heat_score int,
  updated_at timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select
    v.id as venue_id,
    v.name,
    v.external_ids->>'city' as city,
    v.external_ids->>'region' as region,
    v.external_ids->>'country' as country,
    st_y(v.geo::geometry)::numeric as latitude,
    st_x(v.geo::geometry)::numeric as longitude,
    coalesce(v.external_ids->>'source_note', 'Tapt brewery map') as source_label,
    greatest(count(c.id)::int * 3 + count(ti.id)::int, 1) as heat_score,
    greatest(v.updated_at, coalesce(max(c.event_ts), v.updated_at), coalesce(max(ts.observed_at), v.updated_at)) as updated_at
  from venue v
  left join checkin_event c on c.venue_id = v.id and c.moderation_status = 'visible'
  left join venue_tap_snapshot ts on ts.venue_id = v.id and ts.expires_at > now()
  left join venue_tap_item ti on ti.snapshot_id = ts.id
  where v.poi_category in ('brewery','bar','taproom','nightlife')
    and v.geo is not null
  group by v.id
  order by heat_score desc, updated_at desc
  limit least(greatest(coalesce(p_limit, 200), 1), 500);
$$;

revoke execute on function brewery_map_feed(int) from public;
grant execute on function brewery_map_feed(int) to anon, authenticated;

create or replace function region_guide_feed()
returns setof region_beer_guide
language sql
stable
security invoker
set search_path = public
as $$
  select *
  from region_beer_guide
  order by case scope when 'state' then 0 when 'country' then 1 else 2 end, name;
$$;

revoke execute on function region_guide_feed() from public;
grant execute on function region_guide_feed() to anon, authenticated;

-- Keep the social feed from showing reported/hidden content.
create or replace function social_pour_feed(p_limit int default 30)
returns table (
  checkin_id uuid,
  actor_id uuid,
  actor_name text,
  avatar_url text,
  beer_name text,
  brewery_name text,
  venue_name text,
  style text,
  rating numeric,
  event_ts timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  with me as (select auth.uid() as uid)
  select
    c.id,
    c.user_id,
    coalesce(p.display_name, p.handle, 'Beer fan') as actor_name,
    p.avatar_url,
    b.name as beer_name,
    br.name as brewery_name,
    v.name as venue_name,
    c.style,
    c.rating,
    c.event_ts
  from me
  join checkin_event c on c.user_id = me.uid
    or exists (
      select 1 from follow f
      where f.follower_id = me.uid and f.followee_id = c.user_id
    )
  join user_profile p on p.id = c.user_id
  left join beer_catalog b on b.id = c.beer_id
  left join brewery br on br.id = b.brewery_id
  left join venue v on v.id = c.venue_id
  where me.uid is not null
    and c.moderation_status = 'visible'
    and not exists (
      select 1 from user_block ub
      where (ub.blocker_id = me.uid and ub.blocked_id = c.user_id)
         or (ub.blocker_id = c.user_id and ub.blocked_id = me.uid)
    )
  order by c.event_ts desc
  limit least(greatest(coalesce(p_limit, 30), 1), 60);
$$;

revoke execute on function social_pour_feed(int) from public, anon;
grant execute on function social_pour_feed(int) to authenticated;
