-- 0042_beer_market.sql
--
-- The Beer Market: beers as tickers whose PRICE derives from real community demand
-- (net votes) and MOVEMENT from vote velocity -- price/change/volume/sparkline are all
-- computed from vote rows, never hand-written. Pre-launch the real boards are empty, so
-- an ISOLATED, clearly-labeled demo lane (demo.demo_vote) is seeded with real votes on
-- real beers so the ticker is alive; the real production boards stay untouched. The app
-- reads p_demo=true now; flip to false at launch and the same view runs on real votes.

create schema if not exists demo;
create table if not exists demo.demo_vote (
  id bigint generated always as identity primary key,
  beer_id uuid not null,
  value smallint not null check (value in (-1, 1)),
  created_at timestamptz not null default now()
);
create index if not exists demo_vote_beer_idx on demo.demo_vote (beer_id, created_at);
truncate demo.demo_vote;

with picks as (
  select distinct on (b.name) b.id, b.name
  from beer_catalog b join brewery br on br.id = b.brewery_id
  where b.name in (
    'Guinness Draught','Pilsner Urquell','Chimay Bleue','La Chouffe','Duvel','Stella Artois','Heineken',
    'Sierra Nevada Pale Ale','Allagash White','Weihenstephaner Hefeweissbier','Samuel Adams Boston Lager',
    'Leffe Blonde','Hoegaarden','Paulaner Hefe-Weissbier','Erdinger Weissbier','Corona Extra','Modelo Especial',
    'Peroni Nastro Azzurro','Asahi Super Dry','Sapporo','Tsingtao','Carlsberg','Franziskaner',
    'Blue Moon Belgian White','Lagunitas IPA','Founders All Day IPA')
    and length(b.name) < 34
  order by b.name, (b.label_image_url is not null) desc, (b.label_image_url ilike '%full%') desc
),
params as (
  select id, name,
    (abs(hashtext(id::text)) % 23) + 8      as base_ups,
    (abs(hashtext(id::text||'r')) % 14) + 2 as recent_n,
    (abs(hashtext(id::text||'t')) % 3) - 1  as trend
  from picks
),
baseline as (
  select p.id as beer_id, 1::smallint as value,
         now() - (interval '1 day' + random() * interval '6 days') as created_at
  from params p cross join generate_series(1, p.base_ups) g
),
recent as (
  select p.id as beer_id,
         (case p.trend when 1 then 1 when -1 then -1 else (case when g % 2 = 0 then 1 else -1 end) end)::smallint as value,
         now() - (random() * interval '24 hours') as created_at
  from params p cross join generate_series(1, p.recent_n) g
)
insert into demo.demo_vote (beer_id, value, created_at)
select beer_id, value, created_at from baseline
union all select beer_id, value, created_at from recent;

create or replace function public.beer_market(p_sort text default 'movers', p_limit int default 40, p_demo boolean default true)
returns table(beer_id uuid, symbol text, name text, brewery text, style text, country text, image_url text,
              price float8, change_pct float8, volume int, net int, ups int, downs int, market_cap float8, spark float8[])
language sql stable security definer set search_path to 'public' as $$
  with votes as (
    select v.beer_id, v.value, v.created_at from demo.demo_vote v where p_demo
    union all
    select bv.beer_id, bv.value::smallint, bv.created_at from public.beer_vote bv where not p_demo
  ),
  agg as (
    select beer_id, sum(value)::int as net,
      count(*) filter (where value > 0)::int as ups,
      count(*) filter (where value < 0)::int as downs,
      count(*) filter (where created_at > now() - interval '24 hours')::int as volume,
      greatest(1.0, 5.0 + sum(value) * 0.40) as price_now,
      greatest(1.0, 5.0 + coalesce(sum(value) filter (where created_at <= now() - interval '24 hours'), 0) * 0.40) as price_24
    from votes group by beer_id
  ),
  spark as (
    select a.beer_id, array(
      select round(greatest(1.0, 5.0 + coalesce((
        select sum(v2.value) from votes v2 where v2.beer_id = a.beer_id and v2.created_at <= now() - make_interval(days => d)
      ), 0) * 0.40), 2)::float8
      from generate_series(6, 0, -1) d) as spark
    from agg a
  )
  select b.id, upper(left(regexp_replace(b.name, '[^A-Za-z0-9]', '', 'g'), 4)),
    b.name, br.name, coalesce(nullif(b.style,''), 'Beer'), br.country, b.label_image_url,
    round(a.price_now, 2)::float8,
    round(case when a.price_24 > 0 then (a.price_now - a.price_24) / a.price_24 * 100 else 0 end, 2)::float8,
    a.volume, a.net, a.ups, a.downs,
    round(a.price_now * (a.ups + a.downs), 0)::float8, s.spark
  from agg a
  join beer_catalog b on b.id = a.beer_id
  left join brewery br on br.id = b.brewery_id
  join spark s on s.beer_id = a.beer_id
  order by case p_sort
      when 'gainers' then round(case when a.price_24 > 0 then (a.price_now - a.price_24)/a.price_24*100 else 0 end, 2)
      when 'losers'  then -round(case when a.price_24 > 0 then (a.price_now - a.price_24)/a.price_24*100 else 0 end, 2)
      when 'active'  then a.volume::numeric
      when 'price'   then a.price_now
      else abs(round(case when a.price_24 > 0 then (a.price_now - a.price_24)/a.price_24*100 else 0 end, 2))
    end desc, b.name
  limit least(greatest(coalesce(p_limit, 40), 1), 60);
$$;
grant execute on function public.beer_market(text, int, boolean) to anon, authenticated;
