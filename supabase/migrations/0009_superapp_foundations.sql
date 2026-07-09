-- 0009_superapp_foundations.sql
-- THE Beer Superapp foundations:
--   1. Honest beer market: beer_trend recomputed ONLY from real first-party
--      check-ins + votes (kills the seeded synthetic rows — no fabricated data).
--   2. Newsletter (The Tapt Dispatch): subscriber table + RPCs.
--   3. Partnerships: partner inquiries + curated featured placements.
--   4. Leaderboards: beers / tasters / styles, all computed from real activity.
--   5. Social: profile search + follow/unfollow RPCs.
--   6. Scan-to-catalog: add a real beer from a scanned barcode (Open Food Facts
--      provenance), dedup'd by GTIN.

-- ============================================================ 1. honest market
-- beer_trend stays a table (feed views + tonight_feed read it) but its rows are
-- now derived exclusively from first-party signals. Region attribution:
--   check-in -> venue state (US) or venue country, else the drinker's home region.
--   vote     -> the voter's home region.
-- A Global rollup row per beer keeps the worldwide board real.

-- The live table carried a synthetic default (popularity 50); zero it.
alter table beer_trend alter column popularity set default 0;

-- Align beer_vote with the repo contract (live table was missing updated_at).
alter table beer_vote add column if not exists updated_at timestamptz not null default now();
drop trigger if exists t_beer_vote_updated on beer_vote;
create trigger t_beer_vote_updated
before update on beer_vote
for each row execute function set_updated_at();

-- GTIN is the strongest natural key for scan-to-catalog dedup.
create unique index if not exists beer_catalog_gtin_key
  on beer_catalog (gtin) where gtin is not null;

create or replace function refresh_beer_trend()
returns void
language plpgsql
volatile
security definer
set search_path = public
as $$
begin
  delete from beer_trend;

  insert into beer_trend (beer_id, region, popularity, momentum, checkins_7d, avg_rating, updated_at)
  with checkin_base as (
    select
      ce.beer_id,
      coalesce(
        case
          when (v.external_ids->>'country') = 'United States'
               and coalesce(v.external_ids->>'region', '') <> ''
            then v.external_ids->>'region'
          when coalesce(v.external_ids->>'country', '') <> ''
            then v.external_ids->>'country'
          else null
        end,
        nullif(up.region_code, ''),
        'Global'
      ) as region,
      ce.rating,
      ce.event_ts
    from checkin_event ce
    left join venue v on v.id = ce.venue_id
    left join user_profile up on up.id = ce.user_id
    where ce.beer_id is not null
  ),
  vote_base as (
    select
      bv.beer_id,
      coalesce(nullif(up.region_code, ''), 'Global') as region,
      bv.value,
      coalesce(bv.updated_at, bv.created_at) as updated_at
    from beer_vote bv
    left join user_profile up on up.id = bv.user_id
  ),
  regional as (
    select
      beer_id,
      region,
      sum(checkin_count) as checkin_count,
      sum(checkins_7d) as checkins_7d,
      avg(avg_rating) as avg_rating,
      sum(net_votes) as net_votes,
      sum(votes_7d) as votes_7d
    from (
      select beer_id, region,
             count(*)::int as checkin_count,
             count(*) filter (where event_ts > now() - interval '7 days')::int as checkins_7d,
             avg(rating)::numeric(3,2) as avg_rating,
             0 as net_votes, 0 as votes_7d
      from checkin_base group by beer_id, region
      union all
      select beer_id, region,
             0, 0, null,
             coalesce(sum(value), 0)::int as net_votes,
             coalesce(sum(value) filter (where updated_at > now() - interval '7 days'), 0)::int as votes_7d
      from vote_base group by beer_id, region
    ) u
    group by beer_id, region
  ),
  with_global as (
    -- Regional rows (excluding the unattributed bucket), plus one Global rollup
    -- per beer that sums ALL real activity.
    select beer_id, region, checkin_count, checkins_7d, avg_rating, net_votes, votes_7d
    from regional
    where region <> 'Global'
    union all
    select beer_id, 'Global',
           sum(checkin_count)::int, sum(checkins_7d)::int, avg(avg_rating), sum(net_votes)::int, sum(votes_7d)::int
    from regional
    group by beer_id
  )
  select
    beer_id,
    region,
    greatest(coalesce(checkin_count, 0)::int * 3 + coalesce(net_votes, 0)::int, 0),
    (coalesce(checkins_7d, 0)::int * 3 + coalesce(votes_7d, 0)::int),
    coalesce(checkins_7d, 0)::int,
    avg_rating,
    now()
  from with_global;
end;
$$;

revoke all on function refresh_beer_trend() from public, anon, authenticated;

-- Recompute when real signal changes (cheap set-based rebuild at catalog scale).
create or replace function t_refresh_beer_trend()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform refresh_beer_trend();
  return null;
end;
$$;

revoke all on function t_refresh_beer_trend() from public, anon, authenticated;

drop trigger if exists t_beer_vote_trend on beer_vote;
create trigger t_beer_vote_trend
after insert or update or delete on beer_vote
for each statement execute function t_refresh_beer_trend();

drop trigger if exists t_checkin_trend on checkin_event;
create trigger t_checkin_trend
after insert or update or delete on checkin_event
for each statement execute function t_refresh_beer_trend();

-- Purge the synthetic seed rows and rebuild from reality (empty until activity).
select refresh_beer_trend();

-- Nightly refresh keeps the 7-day momentum window honest as time passes.
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.schedule('tapt-beer-trend-nightly', '15 9 * * *', 'select public.refresh_beer_trend()');
  end if;
exception when others then
  raise notice 'pg_cron scheduling skipped: %', sqlerrm;
end $$;

-- ============================================================ 2. newsletter
create table if not exists newsletter_subscriber (
  id uuid primary key default gen_random_uuid(),
  email text not null unique check (position('@' in email) > 1 and length(email) <= 320),
  user_id uuid references user_profile(id) on delete set null,
  source text not null default 'app' check (length(source) <= 40),
  status text not null default 'subscribed' check (status in ('subscribed', 'unsubscribed')),
  consent_ui_text text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger t_newsletter_subscriber_updated
before update on newsletter_subscriber
for each row execute function set_updated_at();

alter table newsletter_subscriber enable row level security;
-- No direct policies: all access flows through the RPCs below (deny by default).

create or replace function subscribe_newsletter(
  p_email text,
  p_source text default 'app',
  p_ui_text text default null
)
returns text
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_email text := lower(trim(p_email));
begin
  if auth.uid() is null then
    raise exception 'sign in required';
  end if;
  if v_email is null or position('@' in v_email) <= 1 or length(v_email) > 320 then
    raise exception 'invalid email';
  end if;

  insert into newsletter_subscriber (email, user_id, source, status, consent_ui_text)
  values (v_email, auth.uid(), coalesce(nullif(trim(p_source), ''), 'app'), 'subscribed', p_ui_text)
  on conflict (email) do update
    set status = 'subscribed',
        user_id = coalesce(newsletter_subscriber.user_id, excluded.user_id),
        source = excluded.source,
        consent_ui_text = coalesce(excluded.consent_ui_text, newsletter_subscriber.consent_ui_text);

  return 'subscribed';
end;
$$;

create or replace function unsubscribe_newsletter()
returns text
language plpgsql
volatile
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'sign in required';
  end if;
  update newsletter_subscriber
     set status = 'unsubscribed'
   where user_id = auth.uid();
  return 'unsubscribed';
end;
$$;

create or replace function newsletter_status()
returns table (email text, status text)
language sql
stable
security definer
set search_path = public
as $$
  select ns.email, ns.status
  from newsletter_subscriber ns
  where ns.user_id = auth.uid()
  limit 1;
$$;

revoke all on function subscribe_newsletter(text, text, text) from public, anon;
revoke all on function unsubscribe_newsletter() from public, anon;
revoke all on function newsletter_status() from public, anon;
grant execute on function subscribe_newsletter(text, text, text) to authenticated;
grant execute on function unsubscribe_newsletter() to authenticated;
grant execute on function newsletter_status() to authenticated;

-- ============================================================ 3. partnerships
create table if not exists partner_inquiry (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references user_profile(id) on delete set null,
  business_name text not null check (length(business_name) between 2 and 160),
  business_kind text not null check (business_kind in ('brewery', 'bar', 'pub', 'taproom', 'beer_garden', 'bottle_shop', 'festival', 'distributor', 'other')),
  contact_email text not null check (position('@' in contact_email) > 1 and length(contact_email) <= 320),
  city text check (length(city) <= 120),
  region text check (length(region) <= 120),
  country text check (length(country) <= 120),
  message text check (length(message) <= 2000),
  status text not null default 'new' check (status in ('new', 'contacted', 'closed')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger t_partner_inquiry_updated
before update on partner_inquiry
for each row execute function set_updated_at();

alter table partner_inquiry enable row level security;
-- Deny by default; inserts flow through the RPC, review happens service-side.

create or replace function submit_partner_inquiry(
  p_business_name text,
  p_business_kind text,
  p_contact_email text,
  p_city text default null,
  p_region text default null,
  p_country text default null,
  p_message text default null
)
returns uuid
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_id uuid;
  v_recent int;
begin
  if auth.uid() is null then
    raise exception 'sign in required';
  end if;
  select count(*) into v_recent
  from partner_inquiry
  where user_id = auth.uid() and created_at > now() - interval '1 day';
  if v_recent >= 5 then
    raise exception 'too many inquiries today';
  end if;

  insert into partner_inquiry (user_id, business_name, business_kind, contact_email, city, region, country, message)
  values (
    auth.uid(),
    trim(p_business_name),
    p_business_kind,
    lower(trim(p_contact_email)),
    nullif(trim(coalesce(p_city, '')), ''),
    nullif(trim(coalesce(p_region, '')), ''),
    nullif(trim(coalesce(p_country, '')), ''),
    nullif(trim(coalesce(p_message, '')), '')
  )
  returning id into v_id;
  return v_id;
end;
$$;

revoke all on function submit_partner_inquiry(text, text, text, text, text, text, text) from public, anon;
grant execute on function submit_partner_inquiry(text, text, text, text, text, text, text) to authenticated;

-- Curated featured placements. Rows are added by the owner (real partners only);
-- the feed is empty until real partnerships exist — the app shows an honest
-- "your brewery here" card instead of fake partners.
create table if not exists featured_partner (
  id uuid primary key default gen_random_uuid(),
  kind text not null check (kind in ('brewery', 'venue', 'event')),
  venue_id uuid references venue(id) on delete cascade,
  brewery_id uuid references brewery(id) on delete cascade,
  title text not null check (length(title) between 2 and 120),
  blurb text check (length(blurb) <= 280),
  cta_label text check (length(cta_label) <= 40),
  cta_url text check (cta_url is null or cta_url ~* '^https://'),
  city text, region text, country text,
  tier text not null default 'featured' check (tier in ('spotlight', 'featured')),
  starts_at timestamptz not null default now(),
  ends_at timestamptz,
  active boolean not null default true,
  sort_rank int not null default 100,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger t_featured_partner_updated
before update on featured_partner
for each row execute function set_updated_at();

alter table featured_partner enable row level security;
-- Deny by default; reads flow through the feed RPC.

create or replace function featured_partner_feed(p_limit int default 10)
returns table (
  id uuid,
  kind text,
  title text,
  blurb text,
  cta_label text,
  cta_url text,
  city text,
  region text,
  country text,
  tier text,
  venue_id uuid,
  brewery_id uuid
)
language sql
stable
security definer
set search_path = public
as $$
  select fp.id, fp.kind, fp.title, fp.blurb, fp.cta_label, fp.cta_url, fp.city, fp.region, fp.country, fp.tier, fp.venue_id, fp.brewery_id
  from featured_partner fp
  where fp.active
    and fp.starts_at <= now()
    and (fp.ends_at is null or fp.ends_at > now())
  order by fp.tier = 'spotlight' desc, fp.sort_rank asc, fp.created_at desc
  limit least(greatest(coalesce(p_limit, 10), 1), 25);
$$;

revoke all on function featured_partner_feed(int) from public;
grant execute on function featured_partner_feed(int) to anon, authenticated;

-- ============================================================ 4. leaderboards
-- All boards are computed live from first-party activity. Empty until real
-- activity exists — never seeded.

create or replace function leaderboard_beers(p_limit int default 20)
returns table (
  beer_id uuid,
  name text,
  style text,
  brewery_name text,
  country text,
  net_votes int,
  ups int,
  downs int,
  checkin_count int,
  avg_rating numeric
)
language sql
stable
security definer
set search_path = public
as $$
  with votes as (
    select bv.beer_id as vote_beer_id,
           coalesce(sum(bv.value), 0)::int as net,
           count(*) filter (where bv.value = 1)::int as ups,
           count(*) filter (where bv.value = -1)::int as downs
    from beer_vote bv group by bv.beer_id
  ),
  checkins as (
    select ce.beer_id as ci_beer_id, count(*)::int as n, avg(ce.rating)::numeric(3,2) as ci_avg
    from checkin_event ce where ce.beer_id is not null group by ce.beer_id
  )
  select
    b.id, b.name, b.style, br.name, br.country,
    coalesce(v.net, 0), coalesce(v.ups, 0), coalesce(v.downs, 0),
    coalesce(c.n, 0), c.ci_avg
  from beer_catalog b
  left join brewery br on br.id = b.brewery_id
  left join votes v on v.vote_beer_id = b.id
  left join checkins c on c.ci_beer_id = b.id
  where coalesce(v.net, 0) <> 0 or coalesce(c.n, 0) > 0
  order by coalesce(v.net, 0) + coalesce(c.n, 0) * 2 desc, b.name
  limit least(greatest(coalesce(p_limit, 20), 1), 50);
$$;

create or replace function leaderboard_tasters(p_limit int default 20)
returns table (
  user_id uuid,
  display_name text,
  handle text,
  avatar_url text,
  pours int,
  styles int,
  countries int
)
language sql
stable
security definer
set search_path = public
as $$
  select
    up.id,
    coalesce(nullif(up.display_name, ''), nullif(up.handle, ''), 'Beer fan'),
    up.handle,
    up.avatar_url,
    count(ce.id)::int as pours,
    count(distinct ce.style) filter (where coalesce(ce.style, '') <> '')::int as styles,
    count(distinct br.country) filter (where coalesce(br.country, '') <> '')::int as countries
  from user_profile up
  join checkin_event ce on ce.user_id = up.id
  left join beer_catalog b on b.id = ce.beer_id
  left join brewery br on br.id = b.brewery_id
  where not exists (
    select 1 from user_block ub
    where (ub.blocker_id = auth.uid() and ub.blocked_id = up.id)
       or (ub.blocker_id = up.id and ub.blocked_id = auth.uid())
  )
  group by up.id
  order by pours desc, styles desc
  limit least(greatest(coalesce(p_limit, 20), 1), 50);
$$;

create or replace function leaderboard_styles(p_limit int default 20)
returns table (
  style text,
  pours int,
  avg_rating numeric,
  last_pour_at timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select
    ce.style,
    count(*)::int,
    avg(ce.rating)::numeric(3,2),
    max(ce.event_ts)
  from checkin_event ce
  where coalesce(ce.style, '') <> ''
  group by ce.style
  order by count(*) desc, max(ce.event_ts) desc
  limit least(greatest(coalesce(p_limit, 20), 1), 50);
$$;

revoke all on function leaderboard_beers(int) from public;
revoke all on function leaderboard_tasters(int) from public, anon;
revoke all on function leaderboard_styles(int) from public;
grant execute on function leaderboard_beers(int) to anon, authenticated;
grant execute on function leaderboard_tasters(int) to authenticated;
grant execute on function leaderboard_styles(int) to anon, authenticated;

-- ============================================================ 5. social
create or replace function search_profiles(p_query text, p_limit int default 12)
returns table (
  user_id uuid,
  display_name text,
  handle text,
  avatar_url text,
  pours int,
  is_following boolean
)
language sql
stable
security definer
set search_path = public
as $$
  select
    up.id,
    coalesce(nullif(up.display_name, ''), nullif(up.handle, ''), 'Beer fan'),
    up.handle,
    up.avatar_url,
    (select count(*)::int from checkin_event ce where ce.user_id = up.id),
    exists (select 1 from follow f where f.follower_id = auth.uid() and f.followee_id = up.id)
  from user_profile up
  where auth.uid() is not null
    and up.id <> auth.uid()
    and length(trim(coalesce(p_query, ''))) >= 2
    and (up.display_name ilike '%' || trim(p_query) || '%'
         or up.handle ilike '%' || trim(p_query) || '%')
    and not exists (
      select 1 from user_block ub
      where (ub.blocker_id = auth.uid() and ub.blocked_id = up.id)
         or (ub.blocker_id = up.id and ub.blocked_id = auth.uid())
    )
  order by 5 desc
  limit least(greatest(coalesce(p_limit, 12), 1), 25);
$$;

create or replace function follow_user(p_followee uuid)
returns void
language plpgsql
volatile
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then raise exception 'sign in required'; end if;
  if p_followee = auth.uid() then raise exception 'cannot follow yourself'; end if;
  if exists (
    select 1 from user_block ub
    where (ub.blocker_id = auth.uid() and ub.blocked_id = p_followee)
       or (ub.blocker_id = p_followee and ub.blocked_id = auth.uid())
  ) then
    raise exception 'unavailable';
  end if;
  insert into follow (follower_id, followee_id)
  values (auth.uid(), p_followee)
  on conflict do nothing;
end;
$$;

create or replace function unfollow_user(p_followee uuid)
returns void
language plpgsql
volatile
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then raise exception 'sign in required'; end if;
  delete from follow where follower_id = auth.uid() and followee_id = p_followee;
end;
$$;

revoke all on function search_profiles(text, int) from public, anon;
revoke all on function follow_user(uuid) from public, anon;
revoke all on function unfollow_user(uuid) from public, anon;
grant execute on function search_profiles(text, int) to authenticated;
grant execute on function follow_user(uuid) to authenticated;
grant execute on function unfollow_user(uuid) to authenticated;

-- ============================================================ 6. scan-to-catalog
-- Adds a real scanned product (Open Food Facts lookup happens client-side; the
-- payload carries OFF provenance). Dedup by GTIN. Never invents fields.
create or replace function add_beer_from_barcode(
  p_gtin text,
  p_name text,
  p_brand text default null,
  p_style text default null,
  p_abv numeric default null,
  p_country text default null,
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
  v_brewery_id uuid;
  v_beer_id uuid;
  v_recent int;
begin
  if auth.uid() is null then raise exception 'sign in required'; end if;
  if length(v_gtin) not between 8 and 14 then raise exception 'invalid barcode'; end if;
  if length(v_name) between 2 and 160 then null; else raise exception 'invalid name'; end if;
  if p_abv is not null and (p_abv < 0 or p_abv > 70) then raise exception 'invalid abv'; end if;

  select count(*) into v_recent
  from beer_catalog bc
  where bc.external_ids->>'added_by' = auth.uid()::text
    and bc.created_at > now() - interval '1 day';
  if v_recent >= 40 then raise exception 'daily add limit reached'; end if;

  -- Existing product wins (GTIN is the strongest natural key).
  select bc.id into v_beer_id from beer_catalog bc where bc.gtin = v_gtin;

  if v_beer_id is null then
    if coalesce(trim(p_brand), '') <> '' then
      select b.id into v_brewery_id
      from brewery b
      where lower(b.name) = lower(trim(p_brand))
      limit 1;
      if v_brewery_id is null then
        insert into brewery (name, country, external_ids)
        values (
          trim(p_brand),
          nullif(trim(coalesce(p_country, '')), ''),
          jsonb_build_object('source', 'open_food_facts', 'added_by', auth.uid())
        )
        returning brewery.id into v_brewery_id;
      end if;
    end if;

    insert into beer_catalog (name, style, abv, is_na_low, gtin, brewery_id, label_image_url, label_image_license, external_ids)
    values (
      v_name,
      nullif(trim(coalesce(p_style, '')), ''),
      p_abv,
      coalesce(p_abv, 100) <= 0.5,
      v_gtin,
      v_brewery_id,
      nullif(trim(coalesce(p_image_url, '')), ''),
      case when coalesce(trim(p_image_url), '') <> '' then 'Open Food Facts (ODbL/CC-BY-SA)' end,
      jsonb_build_object('off_barcode', v_gtin, 'source', 'open_food_facts', 'added_by', auth.uid())
    )
    returning beer_catalog.id into v_beer_id;
  end if;

  return query
  select bc.id, bc.name, bc.style, bc.abv, br.name, br.country
  from beer_catalog bc
  left join brewery br on br.id = bc.brewery_id
  where bc.id = v_beer_id;
end;
$$;

revoke all on function add_beer_from_barcode(text, text, text, text, numeric, text, text) from public, anon;
grant execute on function add_beer_from_barcode(text, text, text, text, numeric, text, text) to authenticated;
