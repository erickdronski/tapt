-- 0072_partner_menu_canonical_checkins.sql
-- Resolve defensible exact menu entries to canonical beers so a partner QR can
-- create a venue-attributed pour and close the analytics loop. Ambiguous menu
-- text remains visible but is deliberately not guessed.

create or replace function public.publish_tap_list(p_venue uuid, p_items jsonb)
returns int
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_snap uuid;
  v_count int := 0;
  v_item jsonb;
  v_beer_id uuid;
  v_name_key text;
  v_brewery_key text;
begin
  if auth.uid() is null then raise exception 'sign in required'; end if;
  if not exists (
    select 1 from public.venue_claim vc
    where vc.venue_id = p_venue
      and vc.user_id = auth.uid()
      and vc.status = 'approved'
  ) then
    raise exception 'venue not claimed/approved';
  end if;
  if jsonb_typeof(p_items) <> 'array'
     or jsonb_array_length(p_items) < 1
     or jsonb_array_length(p_items) > 60 then
    raise exception 'send 1-60 taps';
  end if;

  insert into public.venue_tap_snapshot
    (venue_id, captured_by, source, observed_at, expires_at)
  values (p_venue, auth.uid(), 'partner_portal', now(), now() + interval '3650 days')
  returning id into v_snap;

  for v_item in select * from jsonb_array_elements(p_items) loop
    v_beer_id := null;
    v_name_key := lower(public.tapt_display_name(trim(v_item->>'beer_name')));
    v_brewery_key := regexp_replace(lower(trim(coalesce(v_item->>'brewery_name', ''))), '[^a-z0-9]+', '', 'g');

    if length(v_name_key) >= 2 and length(v_brewery_key) >= 2 then
      select b.id into v_beer_id
      from public.beer_catalog b
      join public.brewery br on br.id = b.brewery_id
      where b.name_ok
        and lower(b.display_name) = v_name_key
        and regexp_replace(lower(trim(br.name)), '[^a-z0-9]+', '', 'g') = v_brewery_key
      order by (b.cutout_url is not null) desc,
               (b.label_image_url is not null) desc,
               b.updated_at desc,
               b.id
      limit 1;
    elsif length(v_name_key) >= 2 then
      select case when count(*) = 1 then (array_agg(x.id))[1] else null end
      into v_beer_id
      from (
        select b.id
        from public.beer_catalog b
        where b.name_ok and lower(b.display_name) = v_name_key
        order by (b.cutout_url is not null) desc,
                 (b.label_image_url is not null) desc,
                 b.updated_at desc,
                 b.id
        limit 2
      ) x;
    end if;

    insert into public.venue_tap_item
      (snapshot_id, beer_id, beer_name, brewery_name, style, price_text, confidence)
    values (
      v_snap,
      v_beer_id,
      left(trim(v_item->>'beer_name'), 160),
      nullif(left(trim(coalesce(v_item->>'brewery_name','')), 160), ''),
      nullif(left(trim(coalesce(v_item->>'style','')), 80), ''),
      nullif(left(trim(coalesce(v_item->>'price','')), 40), ''),
      case when v_beer_id is null then 0.5 else 1.0 end
    );
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;

drop function if exists public.venue_menu(uuid);
create function public.venue_menu(p_venue uuid)
returns table (
  tap_item_id uuid,
  venue_name text,
  city text,
  region text,
  country text,
  beer_id uuid,
  beer_name text,
  brewery_name text,
  style text,
  abv numeric,
  beer_country text,
  price_text text,
  updated_at timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select
    i.id,
    v.name,
    v.external_ids->>'city',
    v.external_ids->>'region',
    v.external_ids->>'country',
    i.beer_id,
    i.beer_name,
    i.brewery_name,
    coalesce(b.style, i.style),
    b.abv,
    br.country,
    i.price_text,
    s.observed_at
  from public.venue v
  join public.venue_tap_snapshot s
    on s.venue_id = v.id and s.expires_at > now()
  join public.venue_tap_item i on i.snapshot_id = s.id
  left join public.beer_catalog b on b.id = i.beer_id
  left join public.brewery br on br.id = b.brewery_id
  where v.id = p_venue
    and s.id = (
      select s2.id from public.venue_tap_snapshot s2
      where s2.venue_id = v.id and s2.expires_at > now()
      order by s2.observed_at desc limit 1
    )
  order by i.created_at;
$$;

revoke all on function public.publish_tap_list(uuid, jsonb) from public, anon;
revoke all on function public.venue_menu(uuid) from public;
grant execute on function public.publish_tap_list(uuid, jsonb) to authenticated;
grant execute on function public.venue_menu(uuid) to anon, authenticated;

notify pgrst, 'reload schema';
