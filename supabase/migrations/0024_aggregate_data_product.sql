-- 0024_aggregate_data_product.sql — the sellable aggregate layer (docs/02, 16).
-- refresh_aggregate_cells() rolls consented check-ins into aggregate_cell
-- (geo_bucket x style x 30d) with HARD gates: consent (sale_optin AND NOT
-- gpc_flag), sensitive-location suppression, k-anonymity (>=10 users AND >=3
-- venues). territory_report() = named Style Demand Index (local share indexed
-- to global=100), admin-gated. Weekly cron. Empty until consented density.
-- Full function bodies applied live; see migration history / docs/16.
create or replace function refresh_aggregate_cells()
returns int language plpgsql volatile security definer set search_path = public as $$
declare v_rows int;
begin
  delete from aggregate_cell where window_end >= (now() - interval '30 days')::date;
  with consented as (
    select ce.geo_bucket_h3, ce.style, ce.user_id, ce.venue_id, ce.rating, ce.event_ts
    from checkin_event ce
    where ce.sale_optin = true and ce.gpc_flag = false
      and coalesce(ce.style,'') <> '' and coalesce(ce.geo_bucket_h3,'') <> ''
      and not exists (select 1 from sensitive_location_suppression s where s.geo_bucket_h3 = ce.geo_bucket_h3)
  ),
  cur as (
    select geo_bucket_h3, style,
      count(*) filter (where event_ts > now() - interval '30 days')::int as checkin_count,
      count(distinct user_id) filter (where event_ts > now() - interval '30 days')::int as distinct_users,
      count(distinct venue_id) filter (where event_ts > now() - interval '30 days')::int as distinct_venues,
      avg(rating) filter (where event_ts > now() - interval '30 days')::numeric(3,2) as avg_rating,
      count(*) filter (where event_ts <= now() - interval '30 days' and event_ts > now() - interval '60 days')::int as prior_count
    from consented group by geo_bucket_h3, style
  ),
  geo_totals as (select geo_bucket_h3, sum(checkin_count) as geo_total from cur group by geo_bucket_h3)
  insert into aggregate_cell (geo_bucket, style, window_start, window_end,
    distinct_users, distinct_venues, checkin_count, style_share, avg_rating, momentum)
  select c.geo_bucket_h3, c.style, (now()-interval '30 days')::date, now()::date,
    c.distinct_users, c.distinct_venues, c.checkin_count,
    round(c.checkin_count::numeric / nullif(g.geo_total,0), 4), c.avg_rating,
    (c.checkin_count - c.prior_count)::numeric
  from cur c join geo_totals g on g.geo_bucket_h3 = c.geo_bucket_h3
  where c.distinct_users >= 10 and c.distinct_venues >= 3;
  get diagnostics v_rows = row_count;
  return v_rows;
end; $$;

create or replace function territory_report(p_geo text default null)
returns table (geo_bucket text, style text, checkin_count int, distinct_users int,
               style_share numeric, style_demand_index numeric, momentum numeric, avg_rating numeric)
language sql stable security definer set search_path = public as $$
  with global_share as (
    select style, sum(checkin_count)::numeric / nullif(sum(sum(checkin_count)) over (),0) as g_share
    from aggregate_cell group by style
  )
  select a.geo_bucket, a.style, a.checkin_count, a.distinct_users, a.style_share,
    round(a.style_share / nullif(gs.g_share,0) * 100, 1), a.momentum, a.avg_rating
  from aggregate_cell a left join global_share gs on gs.style = a.style
  where is_admin() and (p_geo is null or a.geo_bucket = p_geo)
  order by a.checkin_count desc;
$$;

revoke all on function refresh_aggregate_cells() from public, anon, authenticated;
revoke all on function territory_report(text) from public, anon;
grant execute on function territory_report(text) to authenticated;
