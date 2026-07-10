-- 0023_trending_engine_v2.sql — momentum becomes a true period-over-period delta
-- (last 7d activity minus prior 7d) = real trending up (+) / down (-). Auto-runs
-- on every vote/check-in (triggers) + nightly (cron). See body for the full CTE.
create or replace function refresh_beer_trend()
returns void language plpgsql volatile security definer set search_path = public as $$
begin
  delete from beer_trend;
  insert into beer_trend (beer_id, region, popularity, momentum, checkins_7d, avg_rating, updated_at)
  with checkin_base as (
    select ce.beer_id,
      coalesce(
        case when (v.external_ids->>'country') = 'United States' and coalesce(v.external_ids->>'region','') <> ''
               then v.external_ids->>'region'
             when coalesce(v.external_ids->>'country','') <> '' then v.external_ids->>'country'
             else null end,
        nullif(up.region_code,''), 'Global') as region,
      ce.rating, ce.event_ts
    from checkin_event ce
    left join venue v on v.id = ce.venue_id
    left join user_profile up on up.id = ce.user_id
    where ce.beer_id is not null
  ),
  vote_base as (
    select bv.beer_id, coalesce(nullif(up.region_code,''),'Global') as region,
           bv.value, coalesce(bv.updated_at, bv.created_at) as ts
    from beer_vote bv left join user_profile up on up.id = bv.user_id
  ),
  regional as (
    select beer_id, region,
      sum(c_total) as c_total, sum(c7) as c7, sum(c14) as c14, avg(avg_rating) as avg_rating,
      sum(v_net) as v_net, sum(v7) as v7, sum(v14) as v14
    from (
      select beer_id, region,
        count(*)::int c_total,
        count(*) filter (where event_ts > now() - interval '7 days')::int c7,
        count(*) filter (where event_ts <= now() - interval '7 days' and event_ts > now() - interval '14 days')::int c14,
        avg(rating)::numeric(3,2) avg_rating, 0 v_net, 0 v7, 0 v14
      from checkin_base group by beer_id, region
      union all
      select beer_id, region, 0,0,0, null,
        coalesce(sum(value),0)::int v_net,
        coalesce(sum(value) filter (where ts > now() - interval '7 days'),0)::int v7,
        coalesce(sum(value) filter (where ts <= now() - interval '7 days' and ts > now() - interval '14 days'),0)::int v14
      from vote_base group by beer_id, region
    ) u group by beer_id, region
  ),
  with_global as (
    select beer_id, region, c_total, c7, c14, avg_rating, v_net, v7, v14 from regional where region <> 'Global'
    union all
    select beer_id, 'Global', sum(c_total)::int, sum(c7)::int, sum(c14)::int, avg(avg_rating),
           sum(v_net)::int, sum(v7)::int, sum(v14)::int
    from regional group by beer_id
  )
  select beer_id, region,
    greatest(coalesce(c_total,0)::int * 3 + coalesce(v_net,0)::int, 0) as popularity,
    ((coalesce(c7,0)::int * 3 + coalesce(v7,0)::int) - (coalesce(c14,0)::int * 3 + coalesce(v14,0)::int)) as momentum,
    coalesce(c7,0)::int, avg_rating, now()
  from with_global;
end; $$;
revoke all on function refresh_beer_trend() from public, anon, authenticated;
