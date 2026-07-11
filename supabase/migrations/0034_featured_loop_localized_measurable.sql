-- 0034_featured_loop_localized_measurable.sql
--
-- Make Featured/Spotlight a real, localized, measurable product instead of a price
-- tag: localize the feed to the drinker's region with a global fallback, track reach
-- (impressions + taps), expose that reach to the partner in venue_analytics, and add
-- an admin grant (Stripe-webhook target) + auto-expiry. Verified end-to-end in a
-- rolled-back transaction: grant -> localized feed shows it in-region only -> logged
-- impressions/taps -> partner analytics report impressions/taps/CTR/reached drinkers.

create table if not exists public.featured_impression (
  id          uuid primary key default gen_random_uuid(),
  featured_id uuid not null references featured_partner(id) on delete cascade,
  user_id     uuid,
  event       text not null check (event in ('impression','tap')),
  region      text,
  created_at  timestamptz not null default now()
);
create index if not exists featured_impression_fp on public.featured_impression (featured_id, event, created_at desc);
alter table public.featured_impression enable row level security;

create or replace function public.log_featured_event(p_featured uuid, p_event text, p_region text default null)
returns void language plpgsql security definer set search_path to 'public' as $$
begin
  if p_event not in ('impression','tap') then raise exception 'bad event'; end if;
  if not exists (select 1 from featured_partner where id = p_featured) then return; end if;
  insert into featured_impression (featured_id, user_id, event, region)
  values (p_featured, auth.uid(), p_event, nullif(trim(p_region), ''));
end; $$;
grant execute on function public.log_featured_event(uuid, text, text) to authenticated;

create or replace function public.featured_partner_feed(p_limit integer default 10, p_region text default null)
returns table(id uuid, kind text, title text, blurb text, cta_label text, cta_url text,
              city text, region text, country text, tier text, venue_id uuid, brewery_id uuid)
language sql stable security definer set search_path to 'public' as $$
  select fp.id, fp.kind, fp.title, fp.blurb, fp.cta_label, fp.cta_url,
         fp.city, fp.region, fp.country, fp.tier, fp.venue_id, fp.brewery_id
  from featured_partner fp
  where fp.active and fp.starts_at <= now() and (fp.ends_at is null or fp.ends_at > now())
    and (p_region is null or fp.region is null or fp.region = p_region or fp.country = p_region)
  order by (p_region is not null and fp.region = p_region) desc,
           (fp.tier = 'spotlight') desc, fp.sort_rank asc, fp.created_at desc
  limit least(greatest(coalesce(p_limit, 10), 1), 25);
$$;

create or replace function public.venue_analytics(p_venue uuid)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $$
declare v jsonb; f jsonb; imp int; tap int;
begin
  if not (is_admin() or exists (select 1 from venue_claim vc
          where vc.venue_id = p_venue and vc.user_id = auth.uid() and vc.status = 'approved')) then
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

  select count(*) filter (where fi.event='impression'), count(*) filter (where fi.event='tap')
    into imp, tap
  from featured_impression fi join featured_partner fp on fp.id = fi.featured_id
  where fp.venue_id = p_venue;

  f := jsonb_build_object(
    'active_campaigns', (select count(*) from featured_partner fp where fp.venue_id = p_venue
                          and fp.active and (fp.ends_at is null or fp.ends_at > now())),
    'impressions_total', coalesce(imp,0),
    'impressions_7d', (select count(*) from featured_impression fi join featured_partner fp on fp.id=fi.featured_id
                        where fp.venue_id=p_venue and fi.event='impression' and fi.created_at > now()-interval '7 days'),
    'taps_total', coalesce(tap,0),
    'ctr_pct', case when coalesce(imp,0) > 0 then round(tap::numeric * 100 / imp, 1) else null end,
    'reached_drinkers', (select count(distinct fi.user_id) from featured_impression fi join featured_partner fp on fp.id=fi.featured_id
                          where fp.venue_id=p_venue and fi.event='impression' and fi.user_id is not null)
  );
  return v || jsonb_build_object('featured', f);
end; $$;

create or replace function public.grant_featured(p_venue uuid, p_tier text default 'featured',
                                                 p_days integer default 30,
                                                 p_title text default null, p_blurb text default null)
returns uuid language plpgsql security definer set search_path to 'public' as $$
declare v_id uuid; v_name text; v_city text; v_region text; v_country text;
begin
  if not is_admin() then raise exception 'admin only'; end if;
  if p_tier not in ('featured','spotlight') then raise exception 'tier must be featured or spotlight'; end if;
  select ve.name, ve.external_ids->>'city', ve.external_ids->>'region', ve.external_ids->>'country'
    into v_name, v_city, v_region, v_country
  from venue ve where ve.id = p_venue;
  if v_name is null then raise exception 'venue not found'; end if;
  insert into featured_partner (kind, venue_id, title, blurb, cta_label, cta_url,
                                city, region, country, tier, starts_at, ends_at, active, sort_rank)
  values ('venue', p_venue, coalesce(p_title, v_name), coalesce(p_blurb, 'Featured on Tapt'),
          'View menu', 'https://tapt-landing-three.vercel.app/menu?v=' || p_venue::text,
          v_city, v_region, v_country, p_tier, now(), now() + make_interval(days => p_days), true,
          case when p_tier = 'spotlight' then 0 else 100 end)
  returning id into v_id;
  return v_id;
end; $$;

select cron.schedule('featured-expire', '7 * * * *',
  $j$ update featured_partner set active = false, updated_at = now()
      where active and ends_at is not null and ends_at < now() $j$);
