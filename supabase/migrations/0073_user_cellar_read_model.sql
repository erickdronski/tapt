-- 0073_user_cellar_read_model.sql
-- Page the signed-in drinker's complete Cellar without exposing another
-- person's check-ins or silently truncating Passport statistics at 100 rows.

create or replace function public.my_checkins(
  p_limit integer default 250,
  p_before_ts timestamptz default null,
  p_before_id uuid default null
)
returns table (
  id uuid,
  beer_id uuid,
  rating numeric,
  style text,
  event_ts timestamptz,
  beer_catalog jsonb,
  venue jsonb
)
language sql
stable
security definer
set search_path = public
as $$
  select
    ce.id,
    ce.beer_id,
    ce.rating,
    ce.style,
    ce.event_ts,
    case when b.id is null then null else jsonb_build_object(
      'name', coalesce(nullif(b.display_name, ''), b.name),
      'brewery', case when br.id is null then null else jsonb_build_object(
        'name', br.name,
        'country', br.country
      ) end
    ) end,
    case when v.id is null then null else jsonb_build_object(
      'name', v.name,
      'external_ids', v.external_ids
    ) end
  from public.checkin_event ce
  left join public.beer_catalog b on b.id = ce.beer_id
  left join public.brewery br on br.id = b.brewery_id
  left join public.venue v on v.id = ce.venue_id
  where ce.user_id = auth.uid()
    and (
      p_before_ts is null
      or (p_before_id is not null and (ce.event_ts, ce.id) < (p_before_ts, p_before_id))
    )
  order by ce.event_ts desc, ce.id desc
  limit greatest(1, least(coalesce(p_limit, 250), 500));
$$;

revoke all on function public.my_checkins(integer, timestamptz, uuid) from public, anon;
grant execute on function public.my_checkins(integer, timestamptz, uuid) to authenticated;

notify pgrst, 'reload schema';
