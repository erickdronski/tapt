-- 0017_venue_search.sql — public venue search for the partner portal claim flow.
create or replace function search_venues(p_query text, p_limit int default 10)
returns table (venue_id uuid, name text, city text, region text, country text)
language sql stable security definer set search_path = public as $$
  select v.id, v.name, v.external_ids->>'city', v.external_ids->>'region', v.external_ids->>'country'
  from venue v
  where length(trim(coalesce(p_query,''))) >= 2
    and (v.name ilike '%' || trim(p_query) || '%'
         or v.external_ids->>'city' ilike trim(p_query) || '%')
  order by v.name
  limit least(greatest(coalesce(p_limit,10),1), 25);
$$;
revoke all on function search_venues(text, int) from public;
grant execute on function search_venues(text, int) to anon, authenticated;
