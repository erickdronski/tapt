-- 0022_venue_analytics_and_events.sql — partner analytics (data moat + paid hook)
-- + venue events/specials (free stickiness tool). See docs/16 for the thesis.
create or replace function venue_analytics(p_venue uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v jsonb;
begin
  if not (is_admin() or exists (select 1 from venue_claim vc
          where vc.venue_id = p_venue and vc.user_id = auth.uid() and vc.status='approved')) then
    raise exception 'venue not claimed/approved';
  end if;
  select jsonb_build_object(
    'pours_total', (select count(*) from checkin_event where venue_id = p_venue),
    'pours_7d', (select count(*) from checkin_event where venue_id = p_venue and event_ts > now() - interval '7 days'),
    'unique_drinkers', (select count(distinct user_id) from checkin_event where venue_id = p_venue),
    'avg_rating', (select round(avg(rating),2) from checkin_event where venue_id = p_venue and rating is not null),
    'top_beers', coalesce((select jsonb_agg(t) from (
        select b.name, br.name as brewery, count(*)::int as pours
        from checkin_event ce join beer_catalog b on b.id = ce.beer_id
        left join brewery br on br.id = b.brewery_id
        where ce.venue_id = p_venue group by b.name, br.name
        order by count(*) desc limit 8) t), '[]'::jsonb)
  ) into v;
  return v;
end; $$;

create table if not exists venue_event (
  id uuid primary key default gen_random_uuid(),
  venue_id uuid not null references venue(id) on delete cascade,
  kind text not null check (kind in ('happy_hour','tap_takeover','release','live_music','trivia','other')),
  title text not null check (length(title) between 2 and 120),
  details text check (length(details) <= 500),
  starts_at timestamptz,
  ends_at timestamptz,
  active boolean not null default true,
  created_by uuid references user_profile(id) on delete set null,
  created_at timestamptz not null default now()
);
create index if not exists venue_event_venue on venue_event (venue_id, active);
alter table venue_event enable row level security;

create or replace function set_venue_events(p_venue uuid, p_events jsonb)
returns int language plpgsql volatile security definer set search_path = public as $$
declare v_item jsonb; v_count int := 0;
begin
  if not exists (select 1 from venue_claim vc where vc.venue_id = p_venue
                 and vc.user_id = auth.uid() and vc.status='approved') then
    raise exception 'venue not claimed/approved';
  end if;
  if jsonb_array_length(coalesce(p_events,'[]'::jsonb)) > 20 then raise exception 'max 20 events'; end if;
  delete from venue_event where venue_id = p_venue;
  for v_item in select * from jsonb_array_elements(coalesce(p_events,'[]'::jsonb)) loop
    insert into venue_event (venue_id, kind, title, details, starts_at, ends_at, created_by)
    values (p_venue, coalesce(nullif(v_item->>'kind',''), 'other'),
      left(trim(v_item->>'title'),120),
      nullif(left(trim(coalesce(v_item->>'details','')),500),''),
      (v_item->>'starts_at')::timestamptz, (v_item->>'ends_at')::timestamptz, auth.uid());
    v_count := v_count + 1;
  end loop;
  return v_count;
end; $$;

create or replace function venue_events(p_venue uuid)
returns table (kind text, title text, details text, starts_at timestamptz, ends_at timestamptz)
language sql stable security definer set search_path = public as $$
  select e.kind, e.title, e.details, e.starts_at, e.ends_at
  from venue_event e
  where e.venue_id = p_venue and e.active and (e.ends_at is null or e.ends_at > now())
  order by e.starts_at nulls last, e.created_at;
$$;

revoke all on function venue_analytics(uuid) from public, anon;
revoke all on function set_venue_events(uuid, jsonb) from public, anon;
revoke all on function venue_events(uuid) from public;
grant execute on function venue_analytics(uuid) to authenticated;
grant execute on function set_venue_events(uuid, jsonb) to authenticated;
grant execute on function venue_events(uuid) to anon, authenticated;
