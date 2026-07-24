-- Keep scoring-formula changes from masquerading as community movement.
-- Version 2 also removes catalog completeness from the consumer-facing score:
-- having metadata makes a record usable, but does not make the beer better.

alter table public.beer_market_snapshot
  add column if not exists score_version integer not null default 1;

alter table public.beer_market_snapshot
  alter column score_version set default 2;

comment on column public.beer_market_snapshot.score_version is
  'Consumer score formula version. Movement is compared only within one version.';

alter function public.refresh_beer_market_standing()
  rename to refresh_beer_market_standing_scored_v1;

revoke all on function public.refresh_beer_market_standing_scored_v1()
  from public, anon, authenticated;
grant execute on function public.refresh_beer_market_standing_scored_v1()
  to service_role;

create or replace function public.refresh_beer_market_standing()
returns integer
language plpgsql
security definer
set search_path = public
as $function$
declare
  n integer;
begin
  n := public.refresh_beer_market_standing_scored_v1();

  -- The v1 scorer still calculates all audited components. The public score
  -- removes metadata points, then recomputes movement only against a v2
  -- baseline. On the transition day there is intentionally no movement.
  with adjusted as (
    select
      st.beer_id,
      greatest(1, st.standing - st.notability_pts) as score,
      sn.standing as previous_score
    from public.beer_market_standing st
    left join public.beer_market_snapshot sn
      on sn.beer_id = st.beer_id
     and sn.snap_date = current_date - 1
     and sn.score_version = 2
  )
  update public.beer_market_standing st
  set standing = a.score,
      notability_pts = 0,
      change_24h = coalesce(a.score - a.previous_score, 0)
  from adjusted a
  where a.beer_id = st.beer_id;

  with peak as (
    select greatest(max(standing), 1)::numeric as score
    from public.beer_market_standing
  )
  update public.beer_market_standing st
  set heat = least(100, round(st.standing::numeric / peak.score * 100))::int
  from peak;

  insert into public.beer_market_snapshot
    (beer_id, snap_date, standing, score_version)
  select beer_id, current_date, standing, 2
  from public.beer_market_standing
  on conflict (beer_id, snap_date) do update
    set standing = excluded.standing,
        score_version = excluded.score_version;

  return n;
end;
$function$;

revoke all on function public.refresh_beer_market_standing()
  from public, anon, authenticated;
grant execute on function public.refresh_beer_market_standing() to service_role;

select public.refresh_beer_market_standing();
