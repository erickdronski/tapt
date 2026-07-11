-- 0037_clean_beer_names.sql
--
-- The OFF-sourced beer names were e-commerce product titles, not clean names:
-- HTML entities (&quot;), embedded ABV ("Heineken, lager, 4,7%"), packaging codes
-- ("BLE 75CL BIERE ... 8%V", "6 pack 25cl"), embedded barcodes, and junk rows named
-- only a percentage ("0.0%"). clean_beer_name() normalizes them; capped at 15% ABV so
-- descriptors like "100% malta" survive. Applied to the catalog + used by future
-- ingestion so names stay clean. Real data, just de-junked (blank > invented: rows
-- with no real product name are removed).

create or replace function public.clean_beer_name(p text)
returns text language sql immutable as $$
  with s0 as (select replace(replace(replace(replace(replace(replace(coalesce(p,''),
              '&quot;','"'),'&amp;','&'),'&#39;',''''),'&apos;',''''),'&lt;','<'),'&gt;','>') as t),
  sb as (select regexp_replace(t, '\s*\b[0-9]{6,}\b', ' ', 'g') as t from s0),
  s1 as (select regexp_replace(t, '\s*\([^)]*(pack|[0-9]+\s*(cl|ml|l)\b|x\s*[0-9]|bouteille|canette|lot|fut|%ig|bis\s)[^)]*\)', '', 'gi') as t from sb),
  s2 as (select regexp_replace(t, '^\s*([0-9]+\s*(pack|x|×|bottles?|cans?)\s+)+', '', 'i') as t from s1),
  s3 as (select regexp_replace(t, '^\s*(BLE|BTE|CAN|PET|PACK|LOT|MINI\s+FUT|FUT)\s+', '', 'i') as t from s2),
  s4 as (select regexp_replace(t, '\s*\b[0-9]{1,4}\s*(x\s*[0-9]{1,4}\s*)?(cl|ml|l)\b\.?', ' ', 'gi') as t from s3),
  s5 as (select regexp_replace(t, '\s*[,\-–—(]?\s*(alc\.?\s*|alk\.?\s*)?\b(0|[0-9]|1[0-5])([.,][0-9]{1,2})?\s*%\s*(vol\.?|v/v|[vViI]|øl|ol|öl|alk\.?|alc\.?|ig)?\)?', ' ', 'gi') as t from s4),
  s6 as (select regexp_replace(t, '\s*\b([0-9]|1[0-5])([.,][0-9])?\s*(degré?s?|degre?s?|deg)\.?\s*(alcool|alc\.?|d.?alcool)?', ' ', 'gi') as t from s5),
  s7 as (select regexp_replace(t, '\s+schankbier\b|\s+bis\s+[0-9]+.*$', ' ', 'gi') as t from s6),
  s8 as (select regexp_replace(t, '\s+(0|[0-9]|1[0-5])([.,][0-9]{1,2})?\s*$', '', 'g') as t from s7),
  s9 as (select regexp_replace(t, '\s{2,}', ' ', 'g') as t from s8)
  select nullif(trim(both ' -,.·' from t), '') from s9;
$$;

-- one-time cleanup of the existing catalog
update beer_catalog b set name = clean_beer_name(name), updated_at = now()
where clean_beer_name(name) is not null and clean_beer_name(name) <> b.name;

delete from beer_catalog where clean_beer_name(name) is null or length(trim(name)) < 2;
