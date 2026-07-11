-- 0043_beer_name_normalize_v2.sql
-- Surgical name normalization: fix leading ABV ("0.3% Citrus Blonde"), packaging
-- codes, HTML entities, stray quotes, trailing "6,4 °" -- WITHOUT touching legitimate
-- non-Latin names (Hebrew/Cyrillic/Greek are real beers). % leaves the name unless
-- commercial; the NA/low signal lives in is_na_low, not the name.
create or replace function public.clean_beer_name(p text)
returns text language plpgsql immutable as $$
declare s text := p;
begin
  if s is null then return null; end if;
  s := replace(replace(replace(replace(replace(s,'&quot;','"'),'&amp;','&'),'&#39;',''''),'&apos;',''''),'&deg;','°');
  s := btrim(s);
  s := regexp_replace(s, '^["'']+', '');
  s := regexp_replace(s, '["'']+$', '');
  s := regexp_replace(s, '^\s*(bte|pack|lot|caisse|carton|case)?\s*\d+\s*[xX]?\s*\d*\s*(cl|ml|l|litre|liter)\b[.\s:-]*', '', 'i');
  s := regexp_replace(s, '^\s*\d+[.,]?\d*\s*%\s*', '');
  s := regexp_replace(s, '[,\s]+(1[0-5]|[0-9])([.,]\d+)?\s*(°|%)(\s|$)', '\4', 'g');
  s := regexp_replace(s, '\s*(1[0-5]|[0-9])([.,]\d+)?\s*(°|%)\s*"?\s*$', '');
  s := btrim(regexp_replace(s, '\s+', ' ', 'g'));
  s := btrim(s, ' ,-:');
  if length(s) < 2 then s := btrim(p); end if;
  return s;
end; $$;
update beer_catalog set name = clean_beer_name(name), updated_at = now()
where clean_beer_name(name) is distinct from name and length(clean_beer_name(name)) >= 2;
