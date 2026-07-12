-- 0064  Beer name normalization v3: kill retail listing strings.
-- OFF imports carry RETAIL PACK STRINGS as names ("1664 6x25cl 1664 blanc 5.0
-- degre alcool", "6X25 CL LEFFE RUBY RUBY"). v3 strips pack counts, volumes,
-- ABV fragments, container words, no-alcohol suffixes; collapses duplicated
-- tokens; fixes ALL-CAPS; tightens tapt_name_ok (hides generic descriptors +
-- no-real-word names). All readers route through these fns -> app-wide fix.
-- Verified live before apply: "1664 blanc", "Leffe Ruby", "Kronenbourg",
-- "Heineken 0.0"; "0.0" hidden; "Guinness Draught" untouched. 766 hidden.

create or replace function public.tapt_display_name(nm text) returns text
language sql immutable as $$
  with s0 as (
    select case when btrim(coalesce(nm,'')) ~ '^[0-9]{4,}\s+[[:alpha:]]'
                then regexp_replace(btrim(nm), '^[0-9]{4,}[\s.-]+', '')
                else btrim(coalesce(nm,'')) end t
  ),
  s1 as (
    select regexp_replace(
             regexp_replace(t, '\y\d+\s*[xX]\s*\d+([.,]\d+)?\s*(cl|ml|l)?\y', ' ', 'gi'),
             '\y(\d+[- ]?)?pack(\s+of\s*\d*)?\y', ' ', 'gi') t
    from s0
  ),
  s2 as (
    select regexp_replace(t, '\y\d+([.,]\d+)?\s*(cl|ml|litre?s?|l)\y', ' ', 'gi') t from s1
  ),
  s3 as (
    select regexp_replace(
             regexp_replace(t, '\y\d+([.,]\d+)?\s*(degre|degré|°)\s*(d.)?\s*alco+o?l\y', ' ', 'gi'),
             '\y\d+([.,]\d+)?\s*%(\s*vol\.?)?', ' ', 'gi') t
    from s2
  ),
  s4 as (
    select regexp_replace(
             regexp_replace(t, '\y(sans\s+alco+o?l|non[- ]?alcoholic|alcohol[- ]?free|alkoholfrei)\y', ' ', 'gi'),
             '\y(canettes?|cannettes?|bouteilles?|blles?|bte)\y', ' ', 'gi') t
    from s3
  ),
  s5 as (
    select btrim(regexp_replace(regexp_replace(t, '\s+[-–—/|]+\s+', ' ', 'g'), '\s{2,}', ' ', 'g'), ' -–—,./|') t from s4
  ),
  s6 as (
    select btrim(regexp_replace(t, '(\y[[:alnum:]]+\y)(\s+\1)+', '\1', 'gi')) t from s5
  )
  select case
    when t ~ '[a-z]' and t !~ '[A-Z]' and t ~ '^[[:ascii:]]+$' then initcap(t)
    when t ~ '[A-Z]' and t !~ '[a-z]' and t ~ '^[[:ascii:]]+$' then initcap(t)
    else t end
  from s6;
$$;

create or replace function public.tapt_name_ok(nm text) returns boolean
language sql immutable as $$
  select public.tapt_display_name(coalesce(nm,'')) ~ '[[:alpha:]]{3,}'
     and btrim(coalesce(nm,'')) !~* '^(bi[eè]res?|biers?|beers?|cervezas?|cervejas?|birra|piwo|[oø]l|olut|alus|ipa|apa|ale|lager|stout|pils(ner)?|alt|cerveza)\.?$'
     and btrim(coalesce(nm,'')) !~* '^(bi[eè]re\s+)?(belge\s+)?(blonde|brune|blanche|ambr[ée]e)?\s*(bi[eè]re\s+)?(sans\s+alco+o?l|non[- ]?alcoholic|alcohol[- ]?free|alkoholfrei)(\s+beer)?$'
     and coalesce(nm,'') not ilike '%unknown%';
$$;

select public.refresh_beer_market_standing();
