-- 0004_product_auth_privacy_foundations.sql
-- Product plumbing for scan/log flows plus launch-grade privacy guardrails.

-- ============================================================ Explore trend feed, RLS-aware.
create or replace view beer_trend_feed
with (security_invoker = true) as
select
  bt.beer_id,
  b.name,
  b.style,
  b.abv,
  br.name as brewery_name,
  br.country,
  bt.region,
  bt.popularity,
  bt.momentum,
  bt.avg_rating,
  bt.updated_at
from beer_trend bt
join beer_catalog b on b.id = bt.beer_id
left join brewery br on br.id = b.brewery_id;

grant select on beer_trend_feed to anon, authenticated;

-- ============================================================ Scan matching.
create or replace function match_beers(p_query text, p_limit int default 8)
returns table (
  id uuid,
  name text,
  style text,
  abv numeric,
  brewery_name text,
  country text,
  confidence numeric
)
language sql
stable
set search_path = public
as $$
  with q as (
    select nullif(trim(p_query), '') as value
  )
  select
    b.id,
    b.name,
    b.style,
    b.abv,
    br.name as brewery_name,
    br.country,
    case
      when b.gtin = q.value then 1.0
      else greatest(similarity(b.name, q.value), similarity(coalesce(br.name, ''), q.value))
    end::numeric as confidence
  from q, beer_catalog b
  left join brewery br on br.id = b.brewery_id
  where q.value is not null
    and (
      b.gtin = q.value
      or b.name % q.value
      or br.name % q.value
      or b.name ilike '%' || q.value || '%'
      or br.name ilike '%' || q.value || '%'
    )
  order by
    case when b.gtin = q.value then 0 else 1 end,
    confidence desc,
    b.name
  limit least(greatest(p_limit, 1), 20);
$$;

grant execute on function match_beers(text, int) to anon, authenticated;

-- ============================================================ Privacy/RLS hardening.
drop policy if exists read_checkins_public on checkin_event;
drop policy if exists own_checkins on checkin_event;

create policy own_checkins_select
on checkin_event
for select
to authenticated
using ((select auth.uid()) = user_id);

create policy own_checkins_insert
on checkin_event
for insert
to authenticated
with check ((select auth.uid()) = user_id);

drop policy if exists read_profiles_public on user_profile;

create or replace view public_profile
with (security_invoker = true) as
select id, handle, display_name, avatar_url
from user_profile;

grant select on public_profile to anon, authenticated;

drop policy if exists read_venue on venue;

create or replace view public_venue
with (security_invoker = true) as
select id, name, apple_map_item_id, poi_category, on_off_premise, geo_bucket_h3, external_ids
from venue;

grant select on public_venue to anon, authenticated;

create or replace function taste_sale_eligible(p_user uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce((
    select up.birth_verified
      and not up.is_eu_user
      and coalesce(latest.granted, false)
      and latest.action = 'granted'
    from user_profile up
    left join lateral (
      select c.granted, c.action
      from consent_ledger c
      where c.user_id = up.id and c.purpose = 'data_sale'
      order by c.created_at desc
      limit 1
    ) latest on true
    where up.id = p_user
  ), false);
$$;

revoke execute on function taste_sale_eligible(uuid) from public, anon, authenticated;
grant execute on function taste_sale_eligible(uuid) to service_role;

-- ============================================================ Account deletion initiation.
create table if not exists account_deletion_request (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references user_profile(id) on delete cascade,
  reason text,
  status text not null default 'requested' check (status in ('requested','processing','completed','canceled')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger t_account_deletion_request_updated
before update on account_deletion_request
for each row execute function set_updated_at();

alter table account_deletion_request enable row level security;

create policy own_account_deletion_insert
on account_deletion_request
for insert
to authenticated
with check ((select auth.uid()) = user_id);

create policy own_account_deletion_read
on account_deletion_request
for select
to authenticated
using ((select auth.uid()) = user_id);

-- ============================================================ Storage buckets and owner-only object policies.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
  ('checkin-photos', 'checkin-photos', false, 5242880, array['image/jpeg','image/png','image/heic','image/heif']),
  ('avatars', 'avatars', true, 2097152, array['image/jpeg','image/png','image/heic','image/heif'])
on conflict (id) do nothing;

create policy "checkin photo owner read"
on storage.objects
for select
to authenticated
using (bucket_id = 'checkin-photos' and owner = (select auth.uid()));

create policy "checkin photo owner insert"
on storage.objects
for insert
to authenticated
with check (bucket_id = 'checkin-photos' and owner = (select auth.uid()));

create policy "checkin photo owner update"
on storage.objects
for update
to authenticated
using (bucket_id = 'checkin-photos' and owner = (select auth.uid()))
with check (bucket_id = 'checkin-photos' and owner = (select auth.uid()));

create policy "avatar public read"
on storage.objects
for select
to anon, authenticated
using (bucket_id = 'avatars');

create policy "avatar owner insert"
on storage.objects
for insert
to authenticated
with check (bucket_id = 'avatars' and owner = (select auth.uid()));

create policy "avatar owner update"
on storage.objects
for update
to authenticated
using (bucket_id = 'avatars' and owner = (select auth.uid()))
with check (bucket_id = 'avatars' and owner = (select auth.uid()));
