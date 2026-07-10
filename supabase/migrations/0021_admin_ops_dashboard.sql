-- 0021_admin_ops_dashboard.sql — admin ops metrics + inquiries feed (admin-gated).
create or replace function admin_stats()
returns jsonb language sql stable security definer set search_path = public as $$
  select case when is_admin() then jsonb_build_object(
    'users', (select count(*) from user_profile),
    'venues_total', (select count(*) from venue),
    'venues_claimed', (select count(*) from venue_claim where status='approved'),
    'claims_pending', (select count(*) from venue_claim where status='pending'),
    'menus_live', (select count(distinct venue_id) from venue_tap_snapshot where expires_at > now()),
    'beers', (select count(*) from beer_catalog),
    'pours', (select count(*) from checkin_event),
    'votes', (select count(*) from beer_vote),
    'subscribers', (select count(*) from newsletter_subscriber where status='subscribed'),
    'inquiries', (select count(*) from partner_inquiry),
    'inquiries_new', (select count(*) from partner_inquiry where status='new'),
    'partners_featured', (select count(*) from featured_partner where active)
  ) else null end;
$$;

create or replace function admin_inquiries()
returns table (id uuid, business_name text, business_kind text, contact_email text,
               city text, region text, country text, message text, status text, created_at timestamptz)
language sql stable security definer set search_path = public as $$
  select i.id, i.business_name, i.business_kind, i.contact_email, i.city, i.region,
         i.country, i.message, i.status, i.created_at
  from partner_inquiry i
  where is_admin()
  order by (i.status='new') desc, i.created_at desc
  limit 100;
$$;

revoke all on function admin_stats() from public, anon;
revoke all on function admin_inquiries() from public, anon;
grant execute on function admin_stats() to authenticated;
grant execute on function admin_inquiries() to authenticated;
