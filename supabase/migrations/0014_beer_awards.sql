-- 0014_beer_awards.sql
-- Awards, certs, and accolades layer + a No/Low lens on the beer leaderboard.
--   - beer_award: one row per verified accolade (award body, year, category,
--     medal, citation URL). Facts only, always cited — competition RESULTS are
--     public facts; editorial "best of" lists are copyrighted compilations and
--     are NOT ingested.
--   - 'tapt_favorite' medal = Tapt's own first-party award program ("we were
--     here, we poured it") — granted by Tapt itself, global or per-region.
--   - beer_detail returns the award list; leaderboard_beers gains p_na_only.

insert into ingestion_source (id, name, source_kind, license, homepage_url, ingest_cadence, notes)
values
  ('world-beer-cup', 'World Beer Cup results', 'reference', 'Competition results are public facts; cite the result publication', 'https://www.worldbeercup.org/', 'yearly', 'Winner facts (beer, brewery, medal, category, year).'),
  ('world-beer-awards', 'World Beer Awards results', 'reference', 'Competition results are public facts; cite the result publication', 'https://www.worldbeerawards.com/', 'yearly', 'World''s Best winner facts by style.'),
  ('tapt-favorites', 'Tapt''s Favorite program', 'first_party', 'First-party editorial award, granted by Tapt', null, 'as-needed', 'Tapt''s own public picks for local and global markets.')
on conflict (id) do nothing;

create table if not exists beer_award (
  id uuid primary key default gen_random_uuid(),
  beer_id uuid not null references beer_catalog(id) on delete cascade,
  award_body text not null check (length(award_body) between 2 and 120),
  year int check (year between 1900 and 2100),
  category text check (length(category) <= 160),
  medal text not null check (medal in ('gold', 'silver', 'bronze', 'winner', 'finalist', 'tapt_favorite')),
  scope text not null default 'global' check (scope in ('global', 'local')),
  region text check (length(region) <= 120),
  source_id text references ingestion_source(id) on delete set null,
  source_url text check (source_url is null or source_url ~* '^https://'),
  note text check (length(note) <= 400),
  created_at timestamptz not null default now()
);

create index if not exists beer_award_beer on beer_award (beer_id, year desc);

alter table beer_award enable row level security;
create policy beer_award_read on beer_award for select to anon, authenticated using (true);
-- Writes: service-role only (yearly ingest scripts + Tapt's Favorite grants).

-- ============================================================ beer_detail v3
drop function if exists beer_detail(uuid);
create or replace function beer_detail(p_beer_id uuid)
returns table (
  id uuid,
  name text,
  style text,
  substyle text,
  abv numeric,
  ibu smallint,
  is_na_low boolean,
  gtin text,
  label_image_url text,
  label_image_license text,
  nutrition jsonb,
  data_source text,
  brewery_name text,
  brewery_country text,
  brewery_website text,
  style_family text,
  style_name text,
  style_description text,
  style_abv_min numeric,
  style_abv_max numeric,
  style_ibu_min smallint,
  style_ibu_max smallint,
  style_srm_min smallint,
  style_srm_max smallint,
  style_source_url text,
  ups int,
  downs int,
  checkin_count int,
  avg_rating numeric,
  venues_in_country int,
  awards jsonb
)
language sql
stable
security definer
set search_path = public
as $$
  select
    b.id, b.name, b.style, b.substyle, b.abv, b.ibu, b.is_na_low, b.gtin,
    b.label_image_url, b.label_image_license,
    b.external_ids->'nutrition' as nutrition,
    b.external_ids->>'source' as data_source,
    br.name, br.country, br.website_url,
    sr.style_family, sr.style_name, sr.description,
    sr.abv_min, sr.abv_max, sr.ibu_min, sr.ibu_max,
    sr.color_min_srm, sr.color_max_srm, sr.source_url,
    coalesce((select count(*) filter (where bv.value = 1) from beer_vote bv where bv.beer_id = b.id), 0)::int,
    coalesce((select count(*) filter (where bv.value = -1) from beer_vote bv where bv.beer_id = b.id), 0)::int,
    coalesce((select count(*) from checkin_event ce where ce.beer_id = b.id), 0)::int,
    (select avg(ce.rating)::numeric(3,2) from checkin_event ce where ce.beer_id = b.id),
    coalesce((
      select count(*)::int from venue v
      where v.external_ids->>'country' = br.country
    ), 0),
    coalesce((
      select jsonb_agg(jsonb_build_object(
        'award_body', a.award_body,
        'year', a.year,
        'category', a.category,
        'medal', a.medal,
        'scope', a.scope,
        'region', a.region,
        'source_url', a.source_url,
        'note', a.note
      ) order by a.year desc nulls last, a.medal)
      from beer_award a where a.beer_id = b.id
    ), '[]'::jsonb)
  from beer_catalog b
  left join brewery br on br.id = b.brewery_id
  left join beer_style_reference sr
    on b.style is not null
   and lower(sr.style_name) = lower(coalesce(
         (select sa.style_name from style_alias sa where sa.alias = lower(b.style)),
         b.style
       ))
  where b.id = p_beer_id;
$$;

revoke all on function beer_detail(uuid) from public;
grant execute on function beer_detail(uuid) to anon, authenticated;

-- ============================================================ NA leaderboard lens
drop function if exists leaderboard_beers(int);
create or replace function leaderboard_beers(p_limit int default 20, p_na_only boolean default false)
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
  where (coalesce(v.net, 0) <> 0 or coalesce(c.n, 0) > 0)
    and (not p_na_only or b.is_na_low)
  order by coalesce(v.net, 0) + coalesce(c.n, 0) * 2 desc, b.name
  limit least(greatest(coalesce(p_limit, 20), 1), 50);
$$;

revoke all on function leaderboard_beers(int, boolean) from public;
grant execute on function leaderboard_beers(int, boolean) to anon, authenticated;

-- ============================================================ verified seeds
-- Only awards verified against the award body's published results are seeded.
-- 2026 World Beer Cup (8,166 entries, 1,644 breweries): Allagash White won
-- gold in Belgian-Style Witbier.
insert into beer_award (beer_id, award_body, year, category, medal, scope, source_id, source_url, note)
select b.id, 'World Beer Cup', 2026, 'Belgian-Style Witbier', 'gold', 'global',
       'world-beer-cup', 'https://www.worldbeercup.org/',
       'Gold at the 2026 World Beer Cup (8,166 entries from 1,644 breweries).'
from beer_catalog b
where b.name = 'Allagash White'
  and not exists (
    select 1 from beer_award a
    where a.beer_id = b.id and a.award_body = 'World Beer Cup' and a.year = 2026
  );
