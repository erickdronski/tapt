-- Adding details to a one-tap pour must also preserve the venue the user picked.
-- Otherwise a visible place selection silently fails to advance place progress.

drop function if exists public.update_checkin_details(
  uuid, numeric, text[], text, text
);

create function public.update_checkin_details(
  p_checkin_id uuid,
  p_rating numeric default null,
  p_flavor_tags text[] default null,
  p_glassware text default null,
  p_occasion text default null,
  p_venue_id uuid default null
) returns void
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_user uuid := (select auth.uid());
  v_occasion occasion_kind;
begin
  if v_user is null then
    raise exception 'not authenticated';
  end if;
  if p_rating is not null and (p_rating < 0 or p_rating > 5) then
    raise exception 'rating must be between 0 and 5';
  end if;
  if p_occasion in ('home', 'bar', 'restaurant', 'event', 'sports', 'other') then
    v_occasion := p_occasion::occasion_kind;
  end if;
  if p_venue_id is not null
     and not exists (select 1 from public.venue where id = p_venue_id) then
    raise exception 'venue not found';
  end if;

  update public.checkin_event
  set rating = coalesce(p_rating, rating),
      flavor_tags = coalesce(p_flavor_tags, flavor_tags),
      glassware = coalesce(nullif(trim(p_glassware), ''), glassware),
      occasion = coalesce(v_occasion, occasion),
      venue_id = coalesce(p_venue_id, venue_id)
  where id = p_checkin_id
    and user_id = v_user;

  if not found then
    raise exception 'check-in not found';
  end if;
end;
$function$;

revoke all on function public.update_checkin_details(
  uuid, numeric, text[], text, text, uuid
) from public, anon;
grant execute on function public.update_checkin_details(
  uuid, numeric, text[], text, text, uuid
) to authenticated, service_role;
