-- 0044_beer_market_votes_only.sql
-- The market is VOTES, not dollars. net = up-minus-down standing, change = 24h net
-- delta (trending up/down), volume = votes in 24h. Isolated demo lane seeded with a
-- famous-beer whitelist so the board is recognizable + alive pre-launch, without
-- touching the real boards. Deduped by name. Flip p_demo=false at launch for real votes.
create schema if not exists demo;
create table if not exists demo.demo_vote (
  id bigint generated always as identity primary key,
  beer_id uuid not null,
  value smallint not null check (value in (-1, 1)),
  created_at timestamptz not null default now());
create index if not exists demo_vote_beer_idx on demo.demo_vote (beer_id, created_at);
truncate demo.demo_vote;
with picks as (
  select distinct on (b.name) b.id, b.name
  from beer_catalog b join brewery br on br.id = b.brewery_id
  where b.label_image_url is not null and b.name ~ '^[A-Za-z]'
    and b.name in ('Guinness Draught','Pilsner Urquell','Chimay Bleue','La Chouffe','Duvel','Stella Artois','Heineken',
     'Sierra Nevada Pale Ale','Allagash White','Weihenstephaner Hefeweissbier','Samuel Adams Boston Lager','Leffe Blonde',
     'Leffe Brune','Hoegaarden','Paulaner Hefe-Weissbier','Erdinger Weissbier','Corona Extra','Modelo Especial',
     'Peroni Nastro Azzurro','Asahi Super Dry','Sapporo','Tsingtao','Carlsberg','Franziskaner','Blue Moon Belgian White',
     'Lagunitas IPA','Founders All Day IPA','Budweiser','Coors Light','Miller Lite','Michelob Ultra','Newcastle Brown Ale',
     'Fat Tire','Stone IPA','Kronenbourg 1664','Grolsch','Beck''s','Amstel','Estrella Damm','San Miguel','Tiger','Singha',
     'Bitburger','Warsteiner','Delirium Tremens','Orval','Jupiler','Efes','Kwak','Leffe Ruby','Desperados','1664 Blanc',
     'Birra Moretti','Kirin Ichiban')
  order by b.name, (b.label_image_url ilike '%full%') desc),
params as (select id, (abs(hashtext(id::text))%60)+12 base_ups, (abs(hashtext(id::text||'r'))%25)+3 recent_n, (abs(hashtext(id::text||'t'))%3)-1 trend from picks),
baseline as (select p.id beer_id, 1::smallint value, now()-(interval '1 day'+random()*interval '6 days') created_at from params p cross join generate_series(1,p.base_ups) g),
recent as (select p.id beer_id, (case p.trend when 1 then 1 when -1 then -1 else (case when g%2=0 then 1 else -1 end) end)::smallint value, now()-(random()*interval '24 hours') created_at from params p cross join generate_series(1,p.recent_n) g)
insert into demo.demo_vote(beer_id,value,created_at) select beer_id,value,created_at from baseline union all select beer_id,value,created_at from recent;

drop function if exists public.beer_market(text, int, boolean);
create or replace function public.beer_market(p_sort text default 'movers', p_limit int default 40, p_demo boolean default true)
returns table(beer_id uuid, symbol text, name text, brewery text, style text, country text, image_url text,
              net int, votes int, change int, volume int, ups int, downs int, spark float8[])
language sql stable security definer set search_path to 'public' as $$
  with votes as (
    select v.beer_id, v.value, v.created_at from demo.demo_vote v where p_demo
    union all select bv.beer_id, bv.value::smallint, bv.created_at from public.beer_vote bv where not p_demo),
  agg as (select beer_id, sum(value)::int net, count(*)::int votes,
      count(*) filter (where value>0)::int ups, count(*) filter (where value<0)::int downs,
      count(*) filter (where created_at>now()-interval '24 hours')::int volume,
      (sum(value)-coalesce(sum(value) filter (where created_at<=now()-interval '24 hours'),0))::int change
    from votes group by beer_id),
  spark as (select a.beer_id, array(select coalesce((select sum(v2.value) from votes v2 where v2.beer_id=a.beer_id and v2.created_at<=now()-make_interval(days=>d)),0)::float8 from generate_series(6,0,-1) d) spark from agg a),
  ranked as (select distinct on (b.name) a.*, b.id bid, b.name bname, br.name brewery, coalesce(nullif(b.style,''),'Beer') style, br.country, b.label_image_url img
    from agg a join beer_catalog b on b.id=a.beer_id left join brewery br on br.id=b.brewery_id order by b.name, a.votes desc)
  select r.bid, upper(left(regexp_replace(r.bname,'[^A-Za-z0-9]','','g'),4)), r.bname, r.brewery, r.style, r.country, r.img,
    r.net, r.votes, r.change, r.volume, r.ups, r.downs, s.spark
  from ranked r join spark s on s.beer_id=r.beer_id
  order by case p_sort when 'gainers' then r.change when 'losers' then -r.change when 'active' then r.volume when 'top' then r.net else abs(r.change) end desc, r.net desc, r.bname
  limit least(greatest(coalesce(p_limit,40),1),100);
$$;
grant execute on function public.beer_market(text, int, boolean) to anon, authenticated;
