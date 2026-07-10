-- 0019_admin_claim_approval.sql — admin surface for approving venue claims.
create table if not exists app_admin (
  user_id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);
alter table app_admin enable row level security;

insert into app_admin (user_id)
select id from auth.users where lower(email) = 'esdronski@gmail.com'
on conflict do nothing;

create or replace function is_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from app_admin a where a.user_id = auth.uid());
$$;

create or replace function admin_claims()
returns table (claim_id uuid, venue_id uuid, venue_name text, city text, region text,
               business_email text, claimant_role text, status text, created_at timestamptz)
language sql stable security definer set search_path = public as $$
  select vc.id, vc.venue_id, v.name, v.external_ids->>'city', v.external_ids->>'region',
         vc.business_email, vc.claimant_role, vc.status, vc.created_at
  from venue_claim vc join venue v on v.id = vc.venue_id
  where is_admin()
  order by (vc.status = 'pending') desc, vc.created_at desc
  limit 200;
$$;

create or replace function set_claim_status(p_claim uuid, p_status text)
returns void language plpgsql volatile security definer set search_path = public as $$
begin
  if not is_admin() then raise exception 'admin only'; end if;
  if p_status not in ('approved','rejected','pending') then raise exception 'bad status'; end if;
  update venue_claim set status = p_status where id = p_claim;
end; $$;

revoke all on function is_admin() from public, anon;
revoke all on function admin_claims() from public, anon;
revoke all on function set_claim_status(uuid, text) from public, anon;
grant execute on function is_admin() to authenticated;
grant execute on function admin_claims() to authenticated;
grant execute on function set_claim_status(uuid, text) to authenticated;
