-- 0055_real_activity_consent_gates.sql
-- Remove the demo lane and private-note signals from public rankings. Every public
-- check-in aggregate now honors the account's latest aggregate consent; the
-- commercial geo layer additionally requires event-time and current opt-ins.

create or replace function public.beer_market(
  p_sort text default 'movers',
  p_limit integer default 40,
  p_demo boolean default false
)
returns table(
  beer_id uuid, symbol text, name text, brewery text, style text, country text,
  image_url text, net integer, votes integer, change integer, volume integer,
  ups integer, downs integer, spark double precision[], reason text,
  season_fit integer, heat integer
)
language sql
stable
security definer
set search_path = public
as $$
  with season as (
    select case when extract(month from now()) in (6,7,8) then 'summer'
                when extract(month from now()) in (9,10,11) then 'fall'
                when extract(month from now()) in (12,1,2) then 'winter'
                else 'spring' end as s
  ),
  votes as (
    select bv.beer_id, bv.value::int value
    from public.beer_vote bv
  ),
  agg as (
    select beer_id, sum(value)::int net, count(*)::int votes,
      count(*) filter (where value > 0)::int ups,
      count(*) filter (where value < 0)::int downs
    from votes
    group by beer_id
  ),
  ev as (
    select bv.beer_id, bv.value::numeric w, coalesce(bv.updated_at, bv.created_at) ts
    from public.beer_vote bv
    union all
    select ce.beer_id,
           greatest(least(coalesce(ce.rating, 3) - 3, 2), -2)::numeric,
           coalesce(ce.event_ts, ce.created_at)
    from public.checkin_event ce
    where ce.beer_id is not null
      and public.has_current_consent(ce.user_id, 'aggregate_analytics')
  ),
  mom as (
    select beer_id,
      sum(w * exp(-greatest(extract(epoch from now() - ts), 0) / (86400 * 3.0)))::numeric momentum,
      count(*) filter (where ts > now() - interval '24 hours')::int volume
    from ev
    group by beer_id
  ),
  spark as (
    select a.beer_id, array(
      select coalesce((
        select sum(e2.w) from ev e2
        where e2.beer_id = a.beer_id
          and e2.ts >= now() - make_interval(days => d + 1)
          and e2.ts < now() - make_interval(days => d)
      ), 0)::float8
      from generate_series(6, 0, -1) d
    ) spark
    from agg a
  ),
  ranked as (
    select distinct on (public.tapt_display_name(b.name))
      a.beer_id, a.net, a.votes, a.ups, a.downs,
      round(coalesce(m.momentum, 0))::int change,
      coalesce(m.volume, 0) volume,
      coalesce(m.momentum, 0) mraw,
      public.tapt_display_name(b.name) bname,
      br.name brewery,
      coalesce(nullif(b.style, ''), 'Beer') style,
      br.country,
      coalesce(b.cutout_url, b.label_image_url) img,
      case
        when coalesce(b.style, '') || ' ' || b.name ~* 'non[- ]?alco|alcohol[- ]?free|0[.,]0\s*%' then 'Sober-curious pick'
        when (select s from season) = 'summer' and b.style ~* 'ipa|pale|wheat|wit|hefe|weiss|weizen|pils|lager|blonde|sour|gose|radler|shandy|session|helles|k(ö|o)lsch' then 'Summer crusher'
        when (select s from season) = 'winter' and b.style ~* 'stout|porter|barley\s?wine|bock|strong|winter|imperial|quad|dubbel|dark|schwarz' then 'Cold-weather climber'
        when (select s from season) = 'fall' and b.style ~* 'm(ä|a)rzen|oktoberfest|amber|brown|pumpkin|porter|dunkel' then 'Autumn pour'
        when (select s from season) = 'spring' and b.style ~* 'saison|pale|bock|blonde|farmhouse' then 'Spring seasonal'
        else null
      end as reason
    from agg a
    join public.beer_catalog b on b.id = a.beer_id
    left join public.brewery br on br.id = b.brewery_id
    left join mom m on m.beer_id = a.beer_id
    where public.tapt_name_ok(b.name)
    order by public.tapt_display_name(b.name), a.votes desc
  )
  select r.beer_id,
    upper(left(regexp_replace(r.bname, '[^A-Za-z0-9]', '', 'g'), 4)) symbol,
    r.bname, r.brewery, r.style, r.country, r.img,
    r.net, r.votes, r.change, r.volume, r.ups, r.downs, s.spark, r.reason,
    case when r.reason is null then 0 else 2 end,
    least(100, round(abs(r.mraw) / nullif(max(abs(r.mraw)) over (), 0) * 100))::int
  from ranked r
  join spark s on s.beer_id = r.beer_id
  order by case p_sort
      when 'gainers' then r.change
      when 'losers' then -r.change
      when 'active' then r.volume
      when 'top' then r.net
      when 'season' then (case when r.reason is null then 0 else 2 end) * 100 + r.net
      else abs(r.change)
    end desc,
    r.net desc,
    r.bname
  limit least(greatest(coalesce(p_limit, 40), 1), 100);
$$;
revoke all on function public.beer_market(text, integer, boolean)
  from public, anon, authenticated;
grant execute on function public.beer_market(text, integer, boolean)
  to authenticated;

create or replace function public.refresh_beer_trend()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from public.beer_trend;

  insert into public.beer_trend
    (beer_id, region, popularity, momentum, checkins_7d, avg_rating, updated_at)
  with checkin_base as (
    select ce.beer_id,
      coalesce(
        case
          when v.external_ids->>'country' = 'United States'
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
    from public.checkin_event ce
    left join public.venue v on v.id = ce.venue_id
    left join public.user_profile up on up.id = ce.user_id
    where ce.beer_id is not null
      and public.has_current_consent(ce.user_id, 'aggregate_analytics')
  ),
  vote_base as (
    select bv.beer_id,
           coalesce(nullif(up.region_code, ''), 'Global') as region,
           bv.value,
           coalesce(bv.updated_at, bv.created_at) as ts
    from public.beer_vote bv
    left join public.user_profile up on up.id = bv.user_id
  ),
  regional as (
    select beer_id, region,
      sum(c_total) as c_total,
      sum(c7) as c7,
      sum(c14) as c14,
      avg(avg_rating) as avg_rating,
      sum(v_net) as v_net,
      sum(v7) as v7,
      sum(v14) as v14
    from (
      select beer_id, region,
        count(*)::int c_total,
        count(*) filter (where event_ts > now() - interval '7 days')::int c7,
        count(*) filter (
          where event_ts <= now() - interval '7 days'
            and event_ts > now() - interval '14 days'
        )::int c14,
        avg(rating)::numeric(3,2) avg_rating,
        0 v_net, 0 v7, 0 v14
      from checkin_base
      group by beer_id, region
      union all
      select beer_id, region, 0, 0, 0, null,
        coalesce(sum(value), 0)::int,
        coalesce(sum(value) filter (where ts > now() - interval '7 days'), 0)::int,
        coalesce(sum(value) filter (
          where ts <= now() - interval '7 days'
            and ts > now() - interval '14 days'
        ), 0)::int
      from vote_base
      group by beer_id, region
    ) u
    group by beer_id, region
  ),
  with_global as (
    select beer_id, region, c_total, c7, c14, avg_rating, v_net, v7, v14
    from regional
    where region <> 'Global'
    union all
    select beer_id, 'Global',
           sum(c_total)::int, sum(c7)::int, sum(c14)::int,
           avg(avg_rating), sum(v_net)::int, sum(v7)::int, sum(v14)::int
    from regional
    group by beer_id
  )
  select beer_id, region,
    greatest(coalesce(c_total, 0)::int * 3 + coalesce(v_net, 0)::int, 0),
    (coalesce(c7, 0)::int * 3 + coalesce(v7, 0)::int)
      - (coalesce(c14, 0)::int * 3 + coalesce(v14, 0)::int),
    coalesce(c7, 0)::int,
    avg_rating,
    now()
  from with_global;
end;
$$;
revoke all on function public.refresh_beer_trend()
  from public, anon, authenticated;
grant execute on function public.refresh_beer_trend() to service_role;

create or replace function public.refresh_beer_score()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.beer_score
    (beer_id, net, ups, downs, checkins, avg_rating, updated_at)
  select beers.b,
         coalesce(v.net, 0), coalesce(v.ups, 0), coalesce(v.downs, 0),
         coalesce(c.n, 0), c.avgr, now()
  from (
    select beer_id as b from public.beer_vote group by beer_id
    union
    select beer_id from public.checkin_event
    where beer_id is not null
      and public.has_current_consent(user_id, 'aggregate_analytics')
    group by beer_id
  ) beers
  left join (
    select beer_id,
           sum(value)::int as net,
           count(*) filter (where value = 1)::int as ups,
           count(*) filter (where value = -1)::int as downs
    from public.beer_vote
    group by beer_id
  ) v on v.beer_id = beers.b
  left join (
    select beer_id, count(*)::int as n, avg(rating)::numeric(3,2) as avgr
    from public.checkin_event
    where beer_id is not null
      and public.has_current_consent(user_id, 'aggregate_analytics')
    group by beer_id
  ) c on c.beer_id = beers.b
  on conflict (beer_id) do update
    set net = excluded.net,
        ups = excluded.ups,
        downs = excluded.downs,
        checkins = excluded.checkins,
        avg_rating = excluded.avg_rating,
        updated_at = now();

  delete from public.beer_score s
  where not exists (select 1 from public.beer_vote bv where bv.beer_id = s.beer_id)
    and not exists (
      select 1 from public.checkin_event ce
      where ce.beer_id = s.beer_id
        and public.has_current_consent(ce.user_id, 'aggregate_analytics')
    );
end;
$$;
revoke all on function public.refresh_beer_score()
  from public, anon, authenticated;
grant execute on function public.refresh_beer_score() to service_role;

create or replace function public.refresh_aggregate_cells()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare v_rows integer;
begin
  delete from public.aggregate_cell
  where window_end >= (now() - interval '30 days')::date;

  with consented as (
    select ce.geo_bucket_h3, ce.style, ce.user_id, ce.venue_id,
           ce.rating, ce.event_ts
    from public.checkin_event ce
    join public.user_profile up on up.id = ce.user_id
    where ce.sale_optin
      and ce.location_optin
      and not ce.gpc_flag
      and up.birth_verified
      and not up.is_eu_user
      and public.has_current_consent(ce.user_id, 'location')
      and public.has_current_consent(ce.user_id, 'aggregate_analytics')
      and public.has_current_consent(ce.user_id, 'data_sale')
      and coalesce(ce.style, '') <> ''
      and coalesce(ce.geo_bucket_h3, '') <> ''
      and not exists (
        select 1 from public.sensitive_location_suppression s
        where s.geo_bucket_h3 = ce.geo_bucket_h3
      )
  ),
  stats as (
    select geo_bucket_h3, style,
      count(*) filter (where event_ts > now() - interval '30 days')::int as checkin_count,
      count(distinct user_id) filter (where event_ts > now() - interval '30 days')::int as distinct_users,
      count(distinct venue_id) filter (where event_ts > now() - interval '30 days')::int as distinct_venues,
      avg(rating) filter (where event_ts > now() - interval '30 days')::numeric(3,2) as avg_rating,
      count(*) filter (
        where event_ts <= now() - interval '30 days'
          and event_ts > now() - interval '60 days'
      )::int as prior_count,
      count(distinct user_id) filter (
        where event_ts <= now() - interval '30 days'
          and event_ts > now() - interval '60 days'
      )::int as prior_users,
      count(distinct venue_id) filter (
        where event_ts <= now() - interval '30 days'
          and event_ts > now() - interval '60 days'
      )::int as prior_venues
    from consented
    group by geo_bucket_h3, style
  ),
  eligible as (
    select * from stats
    where distinct_users >= 10 and distinct_venues >= 3
  ),
  geo_totals as (
    select geo_bucket_h3, sum(checkin_count) as geo_total
    from eligible
    group by geo_bucket_h3
  )
  insert into public.aggregate_cell
    (geo_bucket, style, window_start, window_end, distinct_users,
     distinct_venues, checkin_count, style_share, avg_rating, momentum)
  select e.geo_bucket_h3,
         e.style,
         (now() - interval '30 days')::date,
         now()::date,
         e.distinct_users,
         e.distinct_venues,
         e.checkin_count,
         round(e.checkin_count::numeric / nullif(g.geo_total, 0), 4),
         e.avg_rating,
         case
           when e.prior_users >= 10 and e.prior_venues >= 3
             then (e.checkin_count - e.prior_count)::numeric
           else null
         end
  from eligible e
  join geo_totals g on g.geo_bucket_h3 = e.geo_bucket_h3;

  get diagnostics v_rows = row_count;
  return v_rows;
end;
$$;
revoke all on function public.refresh_aggregate_cells()
  from public, anon, authenticated;
grant execute on function public.refresh_aggregate_cells() to service_role;

-- Rebuild every derived surface immediately under the corrected gates.
select public.refresh_beer_trend();
select public.refresh_beer_score();
select public.refresh_aggregate_cells();

notify pgrst, 'reload schema';
