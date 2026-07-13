-- 0083_beer_name_quality_v4.sql
-- Preserve product identity for No / Low variants and hide unambiguous retail
-- scrape debris. Blank beats rewriting an uncertain product into a fake name.

create or replace function public.tapt_display_name(nm text) returns text
language sql immutable as $$
  with s0 as (
    -- Six or more leading digits are a barcode/listing token. Four-digit beer
    -- brands such as 1664 are identity and must remain.
    select case when btrim(coalesce(nm, '')) ~ '^[0-9]{6,}\s+[[:alpha:]]'
                then regexp_replace(btrim(nm), '^[0-9]{6,}[\s.-]+', '')
                else btrim(coalesce(nm, '')) end t
  ),
  s1 as (
    select regexp_replace(
             regexp_replace(t, '\y\d+\s*[xX×]\s*\d+([.,]\d+)?\s*(cl|ml|l)?\y', ' ', 'gi'),
             '\y(\d+[- ]?)?pack(\s+of\s*\d*)?\y', ' ', 'gi') t
    from s0
  ),
  s2 as (
    select regexp_replace(t, '\y\d+([.,]\d+)?\s*(cl|ml|litre?s?|l)\y', ' ', 'gi') t
    from s1
  ),
  s3 as (
    select regexp_replace(
             regexp_replace(t, '\y\d+([.,]\d+)?\s*(degre|degré|°)\s*(d.)?\s*alco+o?l\y', ' ', 'gi'),
             '\y\d+([.,]\d+)?\s*%(\s*vol\.?)?', ' ', 'gi') t
    from s2
  ),
  s4 as (
    select regexp_replace(
             regexp_replace(
               regexp_replace(
                 t,
                 '\y(sans[- ]+alco+o?l|sin[- ]+alcohol|senza[- ]+alcol|zonder[- ]+alcohol|non[- ]?alcoholic|alcohol[- ]?free|alkoholfrei)\y',
                 ' Non-Alcoholic ', 'gi'),
               '\y(low[- ]?alcohol|faible[- ]+en[- ]+alcool)\y',
               ' Low Alcohol ', 'gi'),
             '\y(canettes?|cannettes?|bouteilles?|blles?|bte)\y', ' ', 'gi') t
    from s3
  ),
  s5 as (
    select btrim(
      regexp_replace(regexp_replace(t, '\s+[-–—/|]+\s+', ' ', 'g'), '\s{2,}', ' ', 'g'),
      ' -–—,./|'
    ) t
    from s4
  ),
  s6 as (
    select btrim(regexp_replace(t, '(\y[[:alnum:]-]+\y)(\s+\1)+', '\1', 'gi')) t
    from s5
  )
  select case
    when t ~ '[a-z]' and t !~ '[A-Z]' and t ~ '^[[:ascii:]]+$' then initcap(t)
    when t ~ '[A-Z]' and t !~ '[a-z]' and t ~ '^[[:ascii:]]+$' then initcap(t)
    else t end
  from s6;
$$;

create or replace function public.tapt_name_ok(nm text) returns boolean
language sql immutable as $$
  with candidate as (
    select btrim(coalesce(nm, '')) as raw,
           public.tapt_display_name(coalesce(nm, '')) as display
  )
  select display ~ '[[:alpha:]]{3,}'
     and raw !~* '^(bi[eè]res?|biers?|beers?|cervezas?|cervejas?|birra|piwo|[oø]l|olut|alus|ipa|apa|ale|lager|stout|pils(ner)?|alt|cerveza)\.?$'
     and raw !~* '^(bi[eè]re\s+)?(belge\s+)?(blonde|brune|blanche|ambr[ée]e)?\s*(bi[eè]re\s+)?(sans[- ]+alco+o?l|non[- ]?alcoholic|alcohol[- ]?free|alkoholfrei)(\s+beer)?$'
     and raw not ilike '%unknown%'
     and raw !~ '[€$£¥₹]'
     and raw !~* '\m(eur|usd|gbp|chf|cad|aud|zzgl|pfand|basispreis|packung)\M'
     and raw !~ '[0-9]{7,}'
     and raw !~* '^\s*(chargement|loading|cargando)([.!…\s]*)$'
     and raw !~* '@\s*chiller'
     and raw !~ '~'
     and raw !~* '^de\s+[0-9]+\s+de\M'
     and raw !~* '\s+de\s*$'
     and mod(length(raw) - length(replace(raw, '"', '')), 2) = 0
     and display !~* '^(argentina|australia|austria|belgium|brazil|canada|china|croatia|czechia|czech republic|denmark|england|finland|france|germany|india|ireland|italy|japan|lithuania|mexico|netherlands|new zealand|norway|poland|portugal|scotland|singapore|south africa|south korea|spain|sweden|switzerland|united kingdom|united states|wales|world|global)$'
  from candidate;
$$;

-- PostgreSQL 17 rewrites stored generated values in place without dropping
-- dependent views or indexes.
alter table public.beer_catalog
  alter column display_name set expression as (public.tapt_display_name(name)),
  alter column name_ok set expression as (public.tapt_name_ok(name));

analyze public.beer_catalog;
select public.refresh_beer_market_standing();

do $$
begin
  if public.tapt_display_name('1664 Blonde sans alcool')
       <> '1664 Blonde Non-Alcoholic' then
    raise exception 'v4 lost the 1664 No / Low identity';
  end if;
  if public.tapt_display_name('1664 Blanc Sans Alcool 0.4 DEGRE ALCOOL')
       <> '1664 Blanc Non-Alcoholic' then
    raise exception 'v4 did not preserve the No / Low qualifier';
  end if;
  if not public.tapt_name_ok('8.6 Original')
     or not public.tapt_name_ok('5,0 Original Bier')
     or not public.tapt_name_ok('De Garre')
     or not public.tapt_name_ok('Guinness Draught') then
    raise exception 'v4 hid a valid numeric or named beer';
  end if;
  if public.tapt_name_ok('Chargement…')
     or public.tapt_name_ok('Belgium')
     or public.tapt_name_ok('Sapporo @ chiller')
     or public.tapt_name_ok('Bier "Irish Red Ale')
     or public.tapt_name_ok('Guinness Extra Stout 4053400211428 Schankbier Stout')
     or public.tapt_name_ok('Erdinger Helles 2,19 € zzgl. Pfand') then
    raise exception 'v4 allowed known scrape debris';
  end if;
end $$;

notify pgrst, 'reload schema';
