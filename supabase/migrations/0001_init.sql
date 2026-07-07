-- Tapt — 0001_init.sql
-- Core schema for a free, global, scan-first beer passport built as a SELLABLE asset.
-- Design doctrine (see docs/04-SCHEMA-NOTES.md):
--   * EVENT-FIRST: the atomic sellable unit is one immutable check-in ("consumption moment").
--   * TWO PLANES with a hard boundary:
--       personal plane  (raw check-ins, exact geo, reviews, taste vectors) -> NEVER sold, RLS owner-only
--       aggregate plane (k>=10 anonymized cells)                            -> the ONLY thing ever sold
--   * CONSENT is a gating asset: append-only ledger + per-event consent snapshot + suppression list,
--     so a future data sale OR company acquisition is legally clean (CA AB 1824, GDPR, CCPA/CPRA).

-- ============================================================ extensions
create extension if not exists postgis;   -- venue geography, radius search, "near me"
create extension if not exists pg_trgm;    -- fuzzy beer-name matching for scan -> identify
-- create extension if not exists h3;      -- enable if available; else compute H3 in the ingestion pipeline (Lore pattern)

-- ============================================================ enums
create type on_off_premise  as enum ('on_premise','off_premise');
create type occasion_kind   as enum ('home','bar','restaurant','event','sports','other');
create type daypart_kind    as enum ('morning','afternoon','evening','late_night');
create type season_kind     as enum ('winter','spring','summer','fall');
create type consent_purpose as enum ('essential','location','personalization','aggregate_analytics','data_sale','marketing');
create type consent_action  as enum ('granted','withdrawn','gpc_signal');

-- ============================================================ updated_at touch helper
create or replace function set_updated_at() returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end $$;

-- ============================================================ reference / catalog (public-read; seeded from license-clean sources)
-- sku_taxonomy = the PROPRIETARY canonical join key (the moat that makes our data joinable to CPG systems)
create table sku_taxonomy (
  id            uuid primary key default gen_random_uuid(),
  canonical_name text not null,
  brand         text,
  sub_brand     text,
  style         text,
  substyle      text,
  abv           numeric(4,2),
  ibu           smallint,
  srm           smallint,
  gtin          text,                       -- barcode/UPC: strongest de-dup key
  apple_map_item_id text,                    -- iOS 18 MKMapItem.identifier (brewery join)
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
create index sku_taxonomy_name_trgm on sku_taxonomy using gin (canonical_name gin_trgm_ops);
create index sku_taxonomy_gtin on sku_taxonomy (gtin);
create trigger t_sku_updated before update on sku_taxonomy for each row execute function set_updated_at();

create table brewery (
  id            uuid primary key default gen_random_uuid(),
  name          text not null,
  brand_ref     uuid references sku_taxonomy(id),
  country       text,
  apple_map_item_id text,
  home_geo_bucket_h3 text,
  verified_partner boolean not null default false,   -- brewery Pro portal flag
  website_url   text,
  external_ids  jsonb not null default '{}',          -- {open_brewery_db, wikidata, foursquare, ...}
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
create index brewery_name_trgm on brewery using gin (name gin_trgm_ops);
create trigger t_brewery_updated before update on brewery for each row execute function set_updated_at();

create table beer_catalog (
  id            uuid primary key default gen_random_uuid(),
  sku_canonical_id uuid references sku_taxonomy(id),
  brewery_id    uuid references brewery(id),
  name          text not null,
  style         text,
  substyle      text,
  abv           numeric(4,2),
  ibu           smallint,
  srm           smallint,
  is_na_low     boolean not null default false,        -- No/Low lens: first-class, not bolted on
  gtin          text,
  label_image_url text,                                 -- license-segregated (OFF / Logo.dev / first-party)
  label_image_license text,                             -- provenance for the sellable-asset firewall
  external_ids  jsonb not null default '{}',
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
create index beer_name_trgm on beer_catalog using gin (name gin_trgm_ops);
create index beer_brewery on beer_catalog (brewery_id);
create index beer_gtin on beer_catalog (gtin);
create trigger t_beer_updated before update on beer_catalog for each row execute function set_updated_at();

create table venue (
  id            uuid primary key default gen_random_uuid(),
  name          text not null,
  apple_map_item_id text,                               -- Apple owns geometry/hours/photos/LookAround
  poi_category  text,                                    -- MKPointOfInterestCategory (brewery/bar/...)
  on_off_premise on_off_premise not null default 'on_premise',
  geo           geography(Point,4326),                   -- PERSONAL-PLANE precision (RLS-guarded reads)
  geo_bucket_h3 text not null,                           -- coarse cell used by the sellable aggregate layer
  external_ids  jsonb not null default '{}',
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
create index venue_geo on venue using gist (geo);
create index venue_h3 on venue (geo_bucket_h3);
create trigger t_venue_updated before update on venue for each row execute function set_updated_at();

-- ============================================================ users (personal plane)
create table user_profile (
  id            uuid primary key references auth.users(id) on delete cascade,
  handle        text unique,
  display_name  text,
  avatar_url    text,
  region_code   text,                                    -- for GDPR data-residency scoping
  is_eu_user    boolean not null default false,          -- EU set is architecturally excludable from any sale
  birth_verified boolean not null default false,         -- 18+ gate result; DOB itself is NEVER stored in sellable data
  beer_geek_mode boolean not null default false,         -- toggles the lexicon register
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
create trigger t_user_updated before update on user_profile for each row execute function set_updated_at();

-- friend / follow graph
create table follow (
  follower_id   uuid not null references user_profile(id) on delete cascade,
  followee_id   uuid not null references user_profile(id) on delete cascade,
  created_at    timestamptz not null default now(),
  primary key (follower_id, followee_id)
);

-- ============================================================ event spine — the atomic sellable unit (immutable)
create table checkin_event (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references user_profile(id) on delete cascade,   -- join key; NEVER in exports
  beer_id       uuid references beer_catalog(id),
  brewery_id    uuid references brewery(id),
  sku_canonical_id uuid references sku_taxonomy(id),      -- the CPG-joinable moat key
  style         text,
  substyle      text,
  abv           numeric(4,2),
  ibu           smallint,
  srm           smallint,
  rating        numeric(2,1) check (rating >= 0 and rating <= 5),
  flavor_tags   text[] not null default '{}',              -- hoppy/malty/sour/fruity/roasty...
  photo_url     text,
  glassware     text,
  venue_id      uuid references venue(id),
  geo_bucket_h3 text,                                       -- coarse cell only (NO raw lat/long here)
  on_off_premise on_off_premise,
  occasion      occasion_kind,
  event_ts      timestamptz not null default now(),
  day_of_week   smallint,                                   -- denormalized CPG signals (filled by trigger/app)
  daypart       daypart_kind,
  season        season_kind,
  -- per-event consent SNAPSHOT so the aggregation pipeline can include/exclude correctly at roll-up time
  consent_version text,
  sale_optin    boolean not null default false,
  location_optin boolean not null default false,
  gpc_flag      boolean not null default false,
  created_at    timestamptz not null default now()
);
create index checkin_user on checkin_event (user_id);
create index checkin_h3_style_ts on checkin_event (geo_bucket_h3, style, event_ts);
create index checkin_beer on checkin_event (beer_id);

-- personal-plane review detail (aspect-based sentiment; raw text stays device-derived)
create table checkin_review (
  checkin_id    uuid primary key references checkin_event(id) on delete cascade,
  user_id       uuid not null references user_profile(id) on delete cascade,
  aspect_scores jsonb,                                      -- {appearance,aroma,palate,taste,overall}
  flavor_ontology_tags text[] not null default '{}',
  sentiment_confidence real,
  created_at    timestamptz not null default now()
);

-- derived per-user preference vector — powers recs; NEVER sold at the individual level
create table taste_vector (
  user_id       uuid primary key references user_profile(id) on delete cascade,
  top_styles    text[] not null default '{}',
  abv_comfort_band numrange,
  ibu_comfort_band int4range,
  novelty_score real,
  price_tier_pref smallint,
  updated_at    timestamptz not null default now()
);
create trigger t_taste_updated before update on taste_vector for each row execute function set_updated_at();

-- ============================================================ consent & compliance (gating assets)
-- append-only, timestamped, per-purpose, EXPORTABLE to a buyer (AB 1824: opt-outs travel with the data)
create table consent_ledger (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references user_profile(id) on delete cascade,
  purpose       consent_purpose not null,
  action        consent_action not null,
  granted       boolean not null,
  policy_version text not null,
  ui_text_shown text,                                        -- exact copy the user saw (diligence-grade)
  source        text,                                         -- 'onboarding' | 'settings' | 'gpc' | ...
  created_at    timestamptz not null default now()
);
create index consent_user on consent_ledger (user_id, purpose, created_at desc);

-- geopoints that must NEVER enter the sellable layer (FTC hot-button for an alcohol app)
create table sensitive_location_suppression (
  id            uuid primary key default gen_random_uuid(),
  geo_bucket_h3 text not null,
  category      text not null,                                -- addiction_treatment/medical/reproductive/religious/shelter
  source        text,
  created_at    timestamptz not null default now()
);
create index suppression_h3 on sensitive_location_suppression (geo_bucket_h3);

-- security-definer helper: is this user's data eligible to enter the sold aggregate?
create or replace function taste_sale_eligible(p_user uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(
    (select up.birth_verified and not up.is_eu_user
       and exists (select 1 from consent_ledger c
                   where c.user_id = up.id and c.purpose = 'data_sale'
                   order by c.created_at desc limit 1)
     from user_profile up where up.id = p_user), false);
$$;

-- ============================================================ the ONLY sellable layer: k>=10 anonymized cells
-- Populated by a scheduled aggregation job that (a) excludes opted-out users, (b) drops suppressed geos,
-- (c) enforces k-anonymity + minimum distinct venues, (d) adds calibrated DP noise. Materialized here.
create table aggregate_cell (
  id            uuid primary key default gen_random_uuid(),
  geo_bucket    text not null,
  style         text,
  window_start  date not null,
  window_end    date not null,
  distinct_users int not null check (distinct_users >= 10),   -- k-anonymity floor, enforced in schema
  distinct_venues int not null,
  checkin_count int not null,
  style_share   numeric,
  avg_rating    numeric,
  momentum      numeric,                                       -- period-over-period delta (the "up 30%" figure)
  created_at    timestamptz not null default now()
);
create index aggregate_cell_lookup on aggregate_cell (geo_bucket, style, window_start);

-- ============================================================ Row-Level Security
-- Catalog/reference: public read (anon + authenticated), writes are service-role only.
alter table sku_taxonomy enable row level security;
alter table brewery      enable row level security;
alter table beer_catalog enable row level security;
alter table venue        enable row level security;
create policy read_sku      on sku_taxonomy for select using (true);
create policy read_brewery  on brewery      for select using (true);
create policy read_beer     on beer_catalog for select using (true);
create policy read_venue    on venue        for select using (true);

-- Personal plane: owner-only.
alter table user_profile   enable row level security;
alter table follow         enable row level security;
alter table checkin_event  enable row level security;
alter table checkin_review enable row level security;
alter table taste_vector   enable row level security;
alter table consent_ledger enable row level security;

create policy self_profile        on user_profile   for all    using (id = auth.uid())      with check (id = auth.uid());
create policy read_profiles_public on user_profile   for select using (true);  -- public handles/avatars for the social graph
create policy own_follows         on follow         for all    using (follower_id = auth.uid()) with check (follower_id = auth.uid());
create policy own_checkins        on checkin_event  for all    using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy read_checkins_public on checkin_event  for select using (true);  -- feed/leaderboards read pours; tighten later if needed
create policy own_reviews         on checkin_review for all    using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy own_taste           on taste_vector   for all    using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy own_consent_insert  on consent_ledger for insert  with check (user_id = auth.uid());
create policy own_consent_read    on consent_ledger for select using (user_id = auth.uid());
-- consent_ledger is append-only: no update/delete policies (immutability preserved).

-- aggregate_cell + suppression + sensitive tables: NO anon/authenticated policies => service-role only.
alter table aggregate_cell enable row level security;
alter table sensitive_location_suppression enable row level security;

-- auto-create a profile row on signup
create or replace function handle_new_user() returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.user_profile (id, display_name, avatar_url)
  values (new.id, new.raw_user_meta_data->>'full_name', new.raw_user_meta_data->>'avatar_url')
  on conflict (id) do nothing;
  return new;
end $$;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function handle_new_user();
