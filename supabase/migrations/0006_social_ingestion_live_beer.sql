-- 0006_social_ingestion_live_beer.sql
-- Beer-super-app expansion: ingestion provenance, venue tap intelligence,
-- crews/live tasting sessions, safer social feeds, moderation, and RLS hardening.

-- ============================================================ source/provenance layer
create table if not exists ingestion_source (
  id text primary key,
  name text not null,
  source_kind text not null check (source_kind in ('brewery','venue','beer_catalog','barcode','style','first_party','reference')),
  license text not null,
  homepage_url text,
  ingest_cadence text,
  enabled boolean not null default true,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger t_ingestion_source_updated
before update on ingestion_source
for each row execute function set_updated_at();

insert into ingestion_source (id, name, source_kind, license, homepage_url, ingest_cadence, notes)
values
  ('open_brewery_db', 'Open Brewery DB', 'brewery', 'Open data; verify terms before commercial export', 'https://www.openbrewerydb.org/', 'weekly', 'Brewery identity and address enrichment.'),
  ('overture_places', 'Overture Places', 'venue', 'Open data; verify release terms per drop', 'https://overturemaps.org/', 'monthly', 'Venue and POI base layer.'),
  ('foursquare_places', 'Foursquare Places', 'venue', 'Commercial/provider terms', 'https://location.foursquare.com/products/places-api/', 'daily', 'Higher-confidence POI enrichment when enabled.'),
  ('wikidata', 'Wikidata', 'reference', 'CC0', 'https://www.wikidata.org/', 'monthly', 'Brewery and brand facts with license-clean references.'),
  ('open_food_facts', 'Open Food Facts', 'barcode', 'ODbL/content licenses vary; isolate payload provenance', 'https://world.openfoodfacts.org/', 'weekly', 'Barcode fallback, separated from proprietary canonical catalog.'),
  ('upc_provider', 'UPC / GTIN provider', 'barcode', 'Commercial/provider terms', null, 'daily', 'Paid barcode lookup provider placeholder.'),
  ('beerjson', 'BeerJSON', 'style', 'Open standard', 'https://beerjson.github.io/', 'manual', 'Style and recipe metadata reference.'),
  ('first_party_checkins', 'Tapt first-party check-ins', 'first_party', 'Owned first-party data; personal plane remains private', null, 'realtime', 'User check-ins, ratings, tap-list scans, and venue corrections.')
on conflict (id) do update
set name = excluded.name,
    source_kind = excluded.source_kind,
    license = excluded.license,
    homepage_url = excluded.homepage_url,
    ingest_cadence = excluded.ingest_cadence,
    notes = excluded.notes,
    updated_at = now();

create table if not exists source_object_link (
  source_id text not null references ingestion_source(id) on delete cascade,
  object_type text not null check (object_type in ('brewery','venue','beer','sku','style')),
  object_id uuid not null,
  external_id text not null,
  external_url text,
  confidence numeric(4,3) check (confidence is null or (confidence >= 0 and confidence <= 1)),
  payload jsonb not null default '{}',
  last_seen_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  primary key (source_id, object_type, object_id, external_id)
);

create index if not exists source_object_external_lookup
on source_object_link (source_id, object_type, external_id);

create table if not exists beer_style_reference (
  id uuid primary key default gen_random_uuid(),
  style_family text not null,
  style_name text not null unique,
  description text,
  abv_min numeric(4,2),
  abv_max numeric(4,2),
  ibu_min smallint,
  ibu_max smallint,
  color_min_srm smallint,
  color_max_srm smallint,
  source_id text references ingestion_source(id),
  source_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger t_beer_style_reference_updated
before update on beer_style_reference
for each row execute function set_updated_at();

insert into beer_style_reference (style_family, style_name, description, abv_min, abv_max, ibu_min, ibu_max, source_id)
values
  ('Lager', 'Pilsner', 'Bright, pale, crisp lager with expressive bitterness.', 4.2, 5.8, 25, 45, 'beerjson'),
  ('Lager', 'Helles', 'Soft, pale Munich lager with gentle malt and low bitterness.', 4.5, 5.5, 16, 25, 'beerjson'),
  ('IPA', 'West Coast IPA', 'Clear, dry, bitter IPA with citrus, pine, and resin.', 6.0, 7.5, 50, 90, 'beerjson'),
  ('IPA', 'Hazy IPA', 'Soft, aromatic IPA with haze, tropical fruit, and low perceived bitterness.', 5.5, 7.5, 25, 60, 'beerjson'),
  ('Dark', 'Porter', 'Dark ale with chocolate, toast, and moderate roast.', 4.5, 6.5, 18, 40, 'beerjson'),
  ('Dark', 'Stout', 'Roasty dark ale with coffee, cocoa, and dry finish.', 4.0, 8.0, 25, 70, 'beerjson'),
  ('Sour', 'Gose', 'Tart wheat ale with coriander and salinity.', 4.0, 5.5, 5, 15, 'beerjson'),
  ('No / Low', 'Non-Alcoholic IPA', 'Hop-forward IPA-style beer at low or no alcohol.', 0.0, 0.5, 20, 70, 'beerjson')
on conflict (style_name) do update
set style_family = excluded.style_family,
    description = excluded.description,
    abv_min = excluded.abv_min,
    abv_max = excluded.abv_max,
    ibu_min = excluded.ibu_min,
    ibu_max = excluded.ibu_max,
    source_id = excluded.source_id,
    updated_at = now();

-- ============================================================ venue tap intelligence
create table if not exists venue_tap_snapshot (
  id uuid primary key default gen_random_uuid(),
  venue_id uuid references venue(id) on delete set null,
  captured_by uuid references user_profile(id) on delete set null,
  source text not null default 'tap_list_scan',
  raw_text text,
  observed_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '12 hours'),
  created_at timestamptz not null default now()
);

create index if not exists venue_tap_snapshot_venue_time
on venue_tap_snapshot (venue_id, observed_at desc);

create table if not exists venue_tap_item (
  id uuid primary key default gen_random_uuid(),
  snapshot_id uuid not null references venue_tap_snapshot(id) on delete cascade,
  beer_id uuid references beer_catalog(id) on delete set null,
  beer_name text not null,
  brewery_name text,
  style text,
  price_text text,
  confidence numeric(4,3) not null default 0.5 check (confidence >= 0 and confidence <= 1),
  created_at timestamptz not null default now()
);

create index if not exists venue_tap_item_snapshot on venue_tap_item (snapshot_id);
create index if not exists venue_tap_item_beer on venue_tap_item (beer_id);
create index if not exists venue_tap_item_name_trgm on venue_tap_item using gin (beer_name gin_trgm_ops);

-- ============================================================ crews and live tasting sessions
create table if not exists crew (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references user_profile(id) on delete cascade,
  name text not null,
  emoji text not null default 'beer',
  visibility text not null default 'private' check (visibility in ('private','invite','public')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger t_crew_updated
before update on crew
for each row execute function set_updated_at();

create table if not exists crew_member (
  crew_id uuid not null references crew(id) on delete cascade,
  user_id uuid not null references user_profile(id) on delete cascade,
  role text not null default 'member' check (role in ('owner','admin','member')),
  created_at timestamptz not null default now(),
  primary key (crew_id, user_id)
);

create table if not exists tasting_session (
  id uuid primary key default gen_random_uuid(),
  crew_id uuid references crew(id) on delete cascade,
  host_id uuid not null references user_profile(id) on delete cascade,
  venue_id uuid references venue(id) on delete set null,
  title text not null,
  status text not null default 'planned' check (status in ('planned','live','finished','canceled')),
  starts_at timestamptz not null default now(),
  ended_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger t_tasting_session_updated
before update on tasting_session
for each row execute function set_updated_at();

create index if not exists tasting_session_crew_time on tasting_session (crew_id, starts_at desc);
create index if not exists tasting_session_venue_time on tasting_session (venue_id, starts_at desc);

create table if not exists session_participant (
  session_id uuid not null references tasting_session(id) on delete cascade,
  user_id uuid not null references user_profile(id) on delete cascade,
  status text not null default 'joined' check (status in ('invited','joined','left')),
  joined_at timestamptz not null default now(),
  primary key (session_id, user_id)
);

create table if not exists session_pour (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references tasting_session(id) on delete cascade,
  checkin_id uuid references checkin_event(id) on delete set null,
  beer_id uuid references beer_catalog(id) on delete set null,
  user_id uuid not null references user_profile(id) on delete cascade,
  round_number smallint,
  note text,
  created_at timestamptz not null default now()
);

create index if not exists session_pour_session_time on session_pour (session_id, created_at desc);

-- ============================================================ trust, safety, and corrections
create table if not exists user_block (
  blocker_id uuid not null references user_profile(id) on delete cascade,
  blocked_id uuid not null references user_profile(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  check (blocker_id <> blocked_id)
);

create table if not exists content_report (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references user_profile(id) on delete cascade,
  target_type text not null check (target_type in ('user','checkin','venue','beer','session','crew')),
  target_id uuid not null,
  reason text not null,
  details text,
  status text not null default 'open' check (status in ('open','reviewing','actioned','dismissed')),
  created_at timestamptz not null default now()
);

create index if not exists content_report_target on content_report (target_type, target_id);
create index if not exists content_report_reporter on content_report (reporter_id, created_at desc);

create table if not exists venue_correction (
  id uuid primary key default gen_random_uuid(),
  venue_id uuid references venue(id) on delete cascade,
  submitted_by uuid not null references user_profile(id) on delete cascade,
  correction_type text not null check (correction_type in ('closed','duplicate','name','category','location','tap_list','other')),
  suggested_value jsonb not null default '{}',
  note text,
  status text not null default 'open' check (status in ('open','accepted','rejected','merged')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger t_venue_correction_updated
before update on venue_correction
for each row execute function set_updated_at();

create index if not exists venue_correction_venue on venue_correction (venue_id, created_at desc);
create index if not exists venue_correction_user on venue_correction (submitted_by, created_at desc);

-- ============================================================ helper functions for RLS
create or replace function is_crew_member(p_crew_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from crew_member cm
    where cm.crew_id = p_crew_id
      and cm.user_id = (select auth.uid())
  );
$$;

create or replace function is_crew_owner(p_crew_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from crew c
    where c.id = p_crew_id
      and c.owner_id = (select auth.uid())
  );
$$;

revoke execute on function is_crew_member(uuid) from public, anon;
revoke execute on function is_crew_owner(uuid) from public, anon;
grant execute on function is_crew_member(uuid) to authenticated;
grant execute on function is_crew_owner(uuid) to authenticated;

-- ============================================================ RLS for new tables
alter table ingestion_source enable row level security;
alter table source_object_link enable row level security;
alter table beer_style_reference enable row level security;
alter table venue_tap_snapshot enable row level security;
alter table venue_tap_item enable row level security;
alter table crew enable row level security;
alter table crew_member enable row level security;
alter table tasting_session enable row level security;
alter table session_participant enable row level security;
alter table session_pour enable row level security;
alter table user_block enable row level security;
alter table content_report enable row level security;
alter table venue_correction enable row level security;

create policy ingestion_source_public_read on ingestion_source
for select to anon, authenticated using (enabled);

create policy beer_style_reference_public_read on beer_style_reference
for select to anon, authenticated using (true);

create policy venue_tap_snapshot_owner_insert on venue_tap_snapshot
for insert to authenticated with check ((select auth.uid()) = captured_by);

create policy venue_tap_snapshot_owner_read on venue_tap_snapshot
for select to authenticated using ((select auth.uid()) = captured_by);

create policy venue_tap_item_public_read on venue_tap_item
for select to anon, authenticated
using (true);

create policy crew_insert_owner on crew
for insert to authenticated with check ((select auth.uid()) = owner_id);

create policy crew_read_member on crew
for select to authenticated using (owner_id = (select auth.uid()) or is_crew_member(id) or visibility = 'public');

create policy crew_update_owner on crew
for update to authenticated
using (owner_id = (select auth.uid()))
with check (owner_id = (select auth.uid()));

create policy crew_member_read_member on crew_member
for select to authenticated using (is_crew_member(crew_id) or is_crew_owner(crew_id));

create policy crew_member_insert_owner on crew_member
for insert to authenticated with check (is_crew_owner(crew_id) or user_id = (select auth.uid()));

create policy crew_member_delete_self_or_owner on crew_member
for delete to authenticated using (user_id = (select auth.uid()) or is_crew_owner(crew_id));

create policy tasting_session_insert_member on tasting_session
for insert to authenticated with check ((select auth.uid()) = host_id and (crew_id is null or is_crew_member(crew_id)));

create policy tasting_session_read_member on tasting_session
for select to authenticated using ((select auth.uid()) = host_id or crew_id is null or is_crew_member(crew_id));

create policy tasting_session_update_host on tasting_session
for update to authenticated
using ((select auth.uid()) = host_id)
with check ((select auth.uid()) = host_id);

create policy session_participant_read_member on session_participant
for select to authenticated
using (
  user_id = (select auth.uid())
  or exists (select 1 from tasting_session s where s.id = session_id and ((select auth.uid()) = s.host_id or is_crew_member(s.crew_id)))
);

create policy session_participant_insert_self on session_participant
for insert to authenticated with check (user_id = (select auth.uid()));

create policy session_pour_read_session_member on session_pour
for select to authenticated
using (
  user_id = (select auth.uid())
  or exists (select 1 from tasting_session s where s.id = session_id and ((select auth.uid()) = s.host_id or is_crew_member(s.crew_id)))
);

create policy session_pour_insert_self on session_pour
for insert to authenticated with check (user_id = (select auth.uid()));

create policy user_block_owner on user_block
for all to authenticated
using (blocker_id = (select auth.uid()))
with check (blocker_id = (select auth.uid()));

create policy content_report_insert on content_report
for insert to authenticated with check (reporter_id = (select auth.uid()));

create policy content_report_read_own on content_report
for select to authenticated using (reporter_id = (select auth.uid()));

create policy venue_correction_insert on venue_correction
for insert to authenticated with check (submitted_by = (select auth.uid()));

create policy venue_correction_read_own on venue_correction
for select to authenticated using (submitted_by = (select auth.uid()));

-- ============================================================ existing RLS hardening
drop policy if exists own_votes on beer_vote;
drop policy if exists own_beer_vote on beer_vote;
create policy own_beer_vote_select on beer_vote
for select to authenticated using (user_id = (select auth.uid()));
create policy own_beer_vote_insert on beer_vote
for insert to authenticated with check (user_id = (select auth.uid()));
create policy own_beer_vote_update on beer_vote
for update to authenticated
using (user_id = (select auth.uid()))
with check (user_id = (select auth.uid()));
create policy own_beer_vote_delete on beer_vote
for delete to authenticated using (user_id = (select auth.uid()));

drop policy if exists own_reviews on checkin_review;
create policy own_reviews_select on checkin_review
for select to authenticated using (user_id = (select auth.uid()));
create policy own_reviews_insert on checkin_review
for insert to authenticated with check (user_id = (select auth.uid()));
create policy own_reviews_update on checkin_review
for update to authenticated
using (user_id = (select auth.uid()))
with check (user_id = (select auth.uid()));
create policy own_reviews_delete on checkin_review
for delete to authenticated using (user_id = (select auth.uid()));

drop policy if exists own_follows on follow;
create policy own_follows_select on follow
for select to authenticated using (follower_id = (select auth.uid()) or followee_id = (select auth.uid()));
create policy own_follows_insert on follow
for insert to authenticated with check (follower_id = (select auth.uid()));
create policy own_follows_delete on follow
for delete to authenticated using (follower_id = (select auth.uid()));

drop policy if exists own_taste on taste_vector;
create policy own_taste_select on taste_vector
for select to authenticated using (user_id = (select auth.uid()));
create policy own_taste_insert on taste_vector
for insert to authenticated with check (user_id = (select auth.uid()));
create policy own_taste_update on taste_vector
for update to authenticated
using (user_id = (select auth.uid()))
with check (user_id = (select auth.uid()));

drop policy if exists own_consent_insert on consent_ledger;
drop policy if exists own_consent_read on consent_ledger;
create policy own_consent_insert on consent_ledger
for insert to authenticated with check (user_id = (select auth.uid()));
create policy own_consent_read on consent_ledger
for select to authenticated using (user_id = (select auth.uid()));

-- Recreate public aggregate views as security invoker where possible.
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

drop view if exists beer_vote_tally;
create view beer_vote_tally
with (security_invoker = true) as
select
  beer_id,
  count(*) filter (where value = 1) as ups,
  count(*) filter (where value = -1) as downs,
  coalesce(sum(value), 0)::int as net
from beer_vote
group by beer_id;

revoke all on beer_vote_tally from anon, authenticated;

-- ============================================================ safe app RPCs
create or replace function tonight_feed(
  p_geo_bucket text default null,
  p_limit int default 20
)
returns table (
  venue_id uuid,
  venue_name text,
  beer_id uuid,
  beer_name text,
  brewery_name text,
  style text,
  source_label text,
  heat_score int,
  updated_at timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  with tap_rows as (
    select
      v.id as venue_id,
      v.name as venue_name,
      i.beer_id,
      i.beer_name,
      i.brewery_name,
      i.style,
      'tap list'::text as source_label,
      greatest((i.confidence * 100)::int, 1) as heat_score,
      s.observed_at as updated_at
    from venue_tap_item i
    join venue_tap_snapshot s on s.id = i.snapshot_id
    left join venue v on v.id = s.venue_id
    where s.expires_at > now()
      and (p_geo_bucket is null or v.geo_bucket_h3 = p_geo_bucket)
  ),
  trend_rows as (
    select
      null::uuid as venue_id,
      coalesce(region, 'Global') as venue_name,
      beer_id,
      name as beer_name,
      brewery_name,
      style,
      'market heat'::text as source_label,
      greatest(momentum, popularity, 1) as heat_score,
      updated_at
    from beer_trend_feed
    where p_geo_bucket is null
    order by momentum desc, popularity desc
    limit 12
  )
  select *
  from (
    select * from tap_rows
    union all
    select * from trend_rows
  ) q
  order by heat_score desc, updated_at desc
  limit least(greatest(coalesce(p_limit, 20), 1), 50);
$$;

revoke execute on function tonight_feed(text, int) from public;
grant execute on function tonight_feed(text, int) to anon, authenticated;

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

create or replace function taste_profile_snapshot(p_user uuid default auth.uid())
returns table (
  style text,
  pour_count int,
  avg_rating numeric,
  last_pour_at timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select
    coalesce(c.style, b.style, 'Beer') as style,
    count(*)::int as pour_count,
    avg(c.rating)::numeric(3,2) as avg_rating,
    max(c.event_ts) as last_pour_at
  from checkin_event c
  left join beer_catalog b on b.id = c.beer_id
  where c.user_id = (select auth.uid())
    and (p_user is null or p_user = (select auth.uid()))
  group by coalesce(c.style, b.style, 'Beer')
  order by pour_count desc, avg_rating desc nulls last;
$$;

revoke execute on function taste_profile_snapshot(uuid) from public, anon;
grant execute on function taste_profile_snapshot(uuid) to authenticated;

-- Data API grants for newly exposed objects. RLS still controls rows.
grant select on ingestion_source, beer_style_reference, venue_tap_item to anon, authenticated;
grant select, insert on venue_tap_snapshot to authenticated;
grant select, insert, update, delete on crew, crew_member, tasting_session, session_participant, session_pour, user_block to authenticated;
grant select, insert on content_report, venue_correction to authenticated;
