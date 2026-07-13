-- 0095  The scanner shows clean names, not raw Open Food Facts junk.
--
-- match_beers backs the barcode/menu scanner. It returned raw beer_catalog.name,
-- so scanning a Corona showed "Biere corona" and a Peroni "bere Peroni". It now
-- returns the cleaned display_name run through tapt_scan_name (strips a leading
-- locale beer-noun) + resolved style_ref, ranking name_ok rows first. The
-- exact-GTIN hit always resolves so a scan is never empty just for a weak name.
-- tapt_scan_name is scanner-scoped and does NOT touch the generated display_name
-- column (the app-wide strip belongs in tapt_display_name, the name pipeline's
-- lane).
create or replace function public.tapt_scan_name(nm text) returns text
language sql immutable set search_path to 'pg_catalog' as $$
  with s as (
    select btrim(regexp_replace(
      coalesce(nm,''),
      '^(bi[eè]res?|biers?|bier|cervezas?|cervejas?|birra|piwo|alus|olut|[oø]l|beers?|bere)\s+',
      '', 'i')) as t
  )
  select case
    when (select t from s) ~ '[[:alpha:]]{2,}' then
      case when (select t from s) ~ '[a-z]' and (select t from s) !~ '[A-Z]'
           then initcap((select t from s)) else (select t from s) end
    else btrim(coalesce(nm,''))
  end;
$$;
grant execute on function public.tapt_scan_name(text) to anon, authenticated;

create or replace function public.match_beers(p_query text, p_limit integer default 8)
returns table(id uuid, name text, style text, abv numeric, brewery_name text, country text, confidence numeric)
language sql
stable
set search_path to 'public'
as $function$
  with q as (
    select nullif(left(regexp_replace(trim(p_query), '\s+', ' ', 'g'), 96), '') as value,
           least(greatest(coalesce(p_limit, 8), 1), 12) as max_rows
  )
  select
    b.id,
    public.tapt_scan_name(coalesce(nullif(b.display_name, ''), b.name)) as name,
    b.style_ref as style,
    b.abv,
    br.name as brewery_name,
    public.tapt_trusted_country(br.country, br.external_ids) as country,
    case
      when b.gtin = regexp_replace(q.value, '\D', '', 'g') then 1.0
      else greatest(similarity(b.name, q.value), similarity(coalesce(br.name, ''), q.value))
    end::numeric as confidence
  from q, beer_catalog b
  left join brewery br on br.id = b.brewery_id
  where q.value is not null
    and (
      b.gtin = regexp_replace(q.value, '\D', '', 'g')
      or b.name % q.value
      or br.name % q.value
      or b.name ilike '%' || q.value || '%'
      or br.name ilike '%' || q.value || '%'
    )
  order by
    case when b.gtin = regexp_replace(q.value, '\D', '', 'g') then 0 else 1 end,
    b.name_ok desc,
    confidence desc,
    b.name
  limit (select max_rows from q);
$function$;

revoke all on function public.match_beers(text, integer) from public;
grant execute on function public.match_beers(text, integer) to anon, authenticated;
