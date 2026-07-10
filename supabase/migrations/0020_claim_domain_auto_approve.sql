-- 0020_claim_domain_auto_approve.sql — auto-approve a claim when the claimant's
-- email domain matches the venue's OBDB website domain. Generic mail providers
-- never auto-approve (they fall to the /admin human queue).
create or replace function claim_venue(p_venue uuid, p_email text, p_role text default 'manager')
returns uuid language plpgsql volatile security definer set search_path = public as $$
declare
  v_id uuid;
  v_email text := lower(trim(p_email));
  v_domain text := split_part(v_email, '@', 2);
  v_site text;
  v_site_host text;
  v_status text := 'pending';
begin
  if auth.uid() is null then raise exception 'sign in required'; end if;

  select v.external_ids->>'website_url' into v_site from venue v where v.id = p_venue;
  if v_site is not null then
    v_site_host := lower(regexp_replace(regexp_replace(v_site, '^https?://(www\.)?', ''), '/.*$', ''));
    if v_domain <> '' and v_site_host <> ''
       and v_domain not in ('gmail.com','yahoo.com','hotmail.com','outlook.com','icloud.com','aol.com','proton.me','protonmail.com')
       and (v_domain = v_site_host or v_site_host like '%' || v_domain or v_domain like '%' || v_site_host) then
      v_status := 'approved';
    end if;
  end if;

  insert into venue_claim (venue_id, user_id, business_email, claimant_role, status)
  values (p_venue, auth.uid(), v_email, p_role, v_status)
  on conflict (venue_id, user_id) do update set business_email = excluded.business_email
  returning id into v_id;
  return v_id;
end; $$;

revoke all on function claim_venue(uuid, text, text) from public, anon;
grant execute on function claim_venue(uuid, text, text) to authenticated;
