-- 0032_materialize_beer_score_leaderboard.sql
--
-- Completes the load-test bulletproofing (see 0030). leaderboard_beers still did a
-- full live aggregation of beer_vote + checkin_event on every read (~233ms @500k
-- votes in the isolated load test, degrading linearly). Materialize a per-beer
-- score refreshed every 5 minutes (off the read path) and read that instead: the
-- read becomes an index scan over a small table, flat at any vote volume. A single
-- beer's live count is still available via the beer_vote(beer_id) covering index.

create table if not exists public.beer_score (
  beer_id    uuid primary key references beer_catalog(id) on delete cascade,
  net        int not null default 0,
  ups        int not null default 0,
  downs      int not null default 0,
  checkins   int not null default 0,
  avg_rating numeric(3,2),
  updated_at timestamptz not null default now()
);
create index if not exists beer_score_rank on public.beer_score (((net + checkins * 2)) desc);

create or replace function public.refresh_beer_score()
returns void language plpgsql security definer set search_path to 'public'
as $$
begin
  insert into beer_score (beer_id, net, ups, downs, checkins, avg_rating, updated_at)
  select beers.b,
         coalesce(v.net,0), coalesce(v.ups,0), coalesce(v.downs,0),
         coalesce(c.n,0), c.avgr, now()
  from (
    select beer_id as b from beer_vote group by beer_id
    union
    select beer_id from checkin_event where beer_id is not null group by beer_id
  ) beers
  left join (
    select beer_id,
           sum(value)::int as net,
           count(*) filter (where value = 1)::int  as ups,
           count(*) filter (where value = -1)::int as downs
    from beer_vote group by beer_id
  ) v on v.beer_id = beers.b
  left join (
    select beer_id, count(*)::int as n, avg(rating)::numeric(3,2) as avgr
    from checkin_event where beer_id is not null group by beer_id
  ) c on c.beer_id = beers.b
  on conflict (beer_id) do update
    set net = excluded.net, ups = excluded.ups, downs = excluded.downs,
        checkins = excluded.checkins, avg_rating = excluded.avg_rating, updated_at = now();

  delete from beer_score s
  where not exists (select 1 from beer_vote bv where bv.beer_id = s.beer_id)
    and not exists (select 1 from checkin_event ce where ce.beer_id = s.beer_id);
end; $$;

create or replace function public.leaderboard_beers(p_limit integer default 20, p_na_only boolean default false)
returns table(beer_id uuid, name text, style text, brewery_name text, country text,
              net_votes integer, ups integer, downs integer, checkin_count integer, avg_rating numeric)
language sql stable security definer set search_path to 'public'
as $$
  select b.id, b.name, b.style, br.name, br.country,
         s.net, s.ups, s.downs, s.checkins, s.avg_rating
  from beer_score s
  join beer_catalog b on b.id = s.beer_id
  left join brewery br on br.id = b.brewery_id
  where (s.net <> 0 or s.checkins > 0)
    and (not p_na_only or b.is_na_low)
  order by (s.net + s.checkins * 2) desc, b.name
  limit least(greatest(coalesce(p_limit, 20), 1), 50);
$$;

select cron.schedule('beer-score-refresh', '*/5 * * * *', 'select public.refresh_beer_score()');
