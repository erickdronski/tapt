-- 0003_explore_trends.sql
-- Back ExploreView's "beer stock market" surface with real database objects.

create table if not exists beer_vote (
  user_id uuid not null references public.user_profile(id) on delete cascade,
  beer_id uuid not null references public.beer_catalog(id) on delete cascade,
  value smallint not null check (value in (-1, 1)),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (user_id, beer_id)
);

create trigger t_beer_vote_updated
before update on beer_vote
for each row execute function set_updated_at();

alter table beer_vote enable row level security;

create policy own_beer_vote
on beer_vote
for all
using (user_id = auth.uid())
with check (user_id = auth.uid());

create or replace view beer_trend as
with checkin_stats as (
  select
    beer_id,
    count(*)::int as checkin_count,
    avg(rating)::numeric(3,2) as avg_rating
  from checkin_event
  where beer_id is not null
  group by beer_id
),
vote_stats as (
  select
    beer_id,
    coalesce(sum(value), 0)::int as vote_score,
    count(*)::int as vote_count
  from beer_vote
  group by beer_id
)
select
  b.id as beer_id,
  b.name,
  b.style,
  b.abv,
  brewery.name as brewery_name,
  brewery.country,
  coalesce(nullif(brewery.country, ''), 'Global') as region,
  greatest(
    coalesce(cs.checkin_count, 0) * 3 + coalesce(vs.vote_score, 0),
    0
  )::int as popularity,
  (
    coalesce(vs.vote_score, 0)
    + coalesce(cs.checkin_count, 0)
  )::int as momentum,
  cs.avg_rating,
  b.created_at as updated_at
from beer_catalog b
left join brewery on brewery.id = b.brewery_id
left join checkin_stats cs on cs.beer_id = b.id
left join vote_stats vs on vs.beer_id = b.id;

grant select on beer_trend to anon, authenticated;
