-- 0063  Partner-published menus must never silently vanish.
--
-- publish_tap_list stored menus as snapshots expiring in 14 days, and
-- venue_menu only serves non-expired snapshots. A bar that didn't re-publish
-- for two weeks would have a BLANK page behind its printed QR code. The
-- 14-day freshness window is right for crowd-sourced tap sightings, but a
-- partner-published menu is authoritative: it stays live until the partner
-- replaces it. The public menu page already shows an honest "Updated <date>"
-- line, which is the correct freshness signal.
create or replace function publish_tap_list(p_venue uuid, p_items jsonb)
returns int language plpgsql volatile security definer set search_path = public as $$
declare v_snap uuid; v_count int := 0; v_item jsonb;
begin
  if auth.uid() is null then raise exception 'sign in required'; end if;
  if not exists (select 1 from venue_claim vc where vc.venue_id = p_venue
                 and vc.user_id = auth.uid() and vc.status = 'approved') then
    raise exception 'venue not claimed/approved';
  end if;
  if jsonb_array_length(p_items) < 1 or jsonb_array_length(p_items) > 60 then
    raise exception 'send 1-60 taps';
  end if;
  insert into venue_tap_snapshot (venue_id, captured_by, source, observed_at, expires_at)
  values (p_venue, auth.uid(), 'partner_portal', now(), now() + interval '3650 days')
  returning id into v_snap;
  for v_item in select * from jsonb_array_elements(p_items) loop
    insert into venue_tap_item (snapshot_id, beer_name, brewery_name, style, price_text, confidence)
    values (v_snap,
      left(trim(v_item->>'beer_name'), 160),
      nullif(left(trim(coalesce(v_item->>'brewery_name','')), 160), ''),
      nullif(left(trim(coalesce(v_item->>'style','')), 80), ''),
      nullif(left(trim(coalesce(v_item->>'price','')), 40), ''),
      1.0);
    v_count := v_count + 1;
  end loop;
  return v_count;
end; $$;

revoke all on function publish_tap_list(uuid, jsonb) from public, anon;
grant execute on function publish_tap_list(uuid, jsonb) to authenticated;
