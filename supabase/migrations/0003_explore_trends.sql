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

-- Mutable aggregate storage. Later migrations rebuild it exclusively from real
-- first-party activity; keeping the table contract here makes a fresh replay match
-- the live schema used by 0005+ (which requires id and checkins_7d).
create table if not exists beer_trend (
  id uuid primary key default gen_random_uuid(),
  beer_id uuid not null references beer_catalog(id) on delete cascade,
  region text not null default 'Global',
  popularity int not null default 0,
  momentum int not null default 0,
  checkins_7d int not null default 0,
  avg_rating numeric(3,2),
  updated_at timestamptz not null default now(),
  unique (beer_id, region)
);

alter table beer_trend enable row level security;
create policy read_trend on beer_trend for select using (true);

grant select on beer_trend to anon, authenticated;
