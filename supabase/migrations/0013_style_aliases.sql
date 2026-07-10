-- 0013_style_aliases.sql
-- Catalog styles are colloquial ("IPA", "Stout"); the BJCP reference is
-- precise ("American IPA", "Irish Stout"). An explicit, curated alias map
-- beats fuzzy matching (no accidental wrong science). The beer page shows the
-- reference style's own name, so the basis is always visible.

create table if not exists style_alias (
  alias text primary key,
  style_name text not null
);

alter table style_alias enable row level security;
create policy style_alias_read on style_alias for select to anon, authenticated using (true);

-- One missing reference style used by seeded classics (BJCP 13B).
insert into beer_style_reference (style_family, style_name, description, abv_min, abv_max, ibu_min, ibu_max, color_min_srm, color_max_srm, source_id, source_url)
select 'Amber & Brown', 'English Brown Ale',
       'A malty, caramelly, nutty brown British ale — gentle, balanced, sessionable.',
       4.2, 5.9, 20, 30, 12, 22, 'bjcp-2021', 'https://www.bjcp.org/style/2021/'
where not exists (select 1 from beer_style_reference r where lower(r.style_name) = 'english brown ale');

insert into style_alias (alias, style_name) values
  ('ipa', 'American IPA'),
  ('imperial ipa', 'Double IPA'),
  ('pale ale', 'American Pale Ale'),
  ('pale lager', 'International Pale Lager'),
  ('lager', 'International Pale Lager'),
  ('light lager', 'American Light Lager'),
  ('pilsner', 'German Pils'),
  ('hefeweizen', 'Weissbier'),
  ('wheat ale', 'American Wheat'),
  ('helles', 'Munich Helles'),
  ('export helles', 'Munich Helles'),
  ('dark lager', 'Munich Dunkel'),
  ('amber lager', 'Vienna Lager'),
  ('bock', 'Dunkles Bock'),
  ('maibock', 'Helles Bock (Maibock)'),
  ('stout', 'Irish Stout'),
  ('milk stout', 'Sweet Stout'),
  ('imperial coffee stout', 'Imperial Stout'),
  ('porter', 'American Porter'),
  ('imperial baltic porter', 'Baltic Porter'),
  ('tripel', 'Belgian Tripel'),
  ('quadrupel', 'Belgian Dark Strong Ale'),
  ('belgian quadrupel', 'Belgian Dark Strong Ale'),
  ('belgian dark strong', 'Belgian Dark Strong Ale'),
  ('belgian strong golden', 'Belgian Golden Strong Ale'),
  ('belgian blonde', 'Belgian Blond Ale'),
  ('esb', 'Strong Bitter (ESB)'),
  ('bitter', 'Best Bitter'),
  ('barleywine', 'English Barleywine'),
  ('golden ale', 'Blonde Ale'),
  ('amber ale', 'American Amber Ale'),
  ('brown ale', 'English Brown Ale'),
  ('non-alcoholic lager', 'Non-Alcoholic Beer'),
  ('non-alcoholic ipa', 'Non-Alcoholic Beer'),
  ('non-alcoholic stout', 'Non-Alcoholic Beer'),
  ('non-alcoholic golden ale', 'Non-Alcoholic Beer'),
  ('non-alcoholic weissbier', 'Non-Alcoholic Beer'),
  ('non-alcoholic pale ale', 'Non-Alcoholic Beer')
on conflict (alias) do update set style_name = excluded.style_name;

-- Rewire beer_detail's style join through the alias map (adds style_name to
-- the row shape, so the old signature is dropped first).
drop function if exists beer_detail(uuid);
create or replace function beer_detail(p_beer_id uuid)
returns table (
  id uuid,
  name text,
  style text,
  substyle text,
  abv numeric,
  ibu smallint,
  is_na_low boolean,
  gtin text,
  label_image_url text,
  label_image_license text,
  nutrition jsonb,
  data_source text,
  brewery_name text,
  brewery_country text,
  brewery_website text,
  style_family text,
  style_name text,
  style_description text,
  style_abv_min numeric,
  style_abv_max numeric,
  style_ibu_min smallint,
  style_ibu_max smallint,
  style_srm_min smallint,
  style_srm_max smallint,
  style_source_url text,
  ups int,
  downs int,
  checkin_count int,
  avg_rating numeric,
  venues_in_country int
)
language sql
stable
security definer
set search_path = public
as $$
  select
    b.id, b.name, b.style, b.substyle, b.abv, b.ibu, b.is_na_low, b.gtin,
    b.label_image_url, b.label_image_license,
    b.external_ids->'nutrition' as nutrition,
    b.external_ids->>'source' as data_source,
    br.name, br.country, br.website_url,
    sr.style_family, sr.style_name, sr.description,
    sr.abv_min, sr.abv_max, sr.ibu_min, sr.ibu_max,
    sr.color_min_srm, sr.color_max_srm, sr.source_url,
    coalesce((select count(*) filter (where bv.value = 1) from beer_vote bv where bv.beer_id = b.id), 0)::int,
    coalesce((select count(*) filter (where bv.value = -1) from beer_vote bv where bv.beer_id = b.id), 0)::int,
    coalesce((select count(*) from checkin_event ce where ce.beer_id = b.id), 0)::int,
    (select avg(ce.rating)::numeric(3,2) from checkin_event ce where ce.beer_id = b.id),
    coalesce((
      select count(*)::int from venue v
      where v.external_ids->>'country' = br.country
    ), 0)
  from beer_catalog b
  left join brewery br on br.id = b.brewery_id
  left join beer_style_reference sr
    on b.style is not null
   and lower(sr.style_name) = lower(coalesce(
         (select sa.style_name from style_alias sa where sa.alias = lower(b.style)),
         b.style
       ))
  where b.id = p_beer_id;
$$;

revoke all on function beer_detail(uuid) from public;
grant execute on function beer_detail(uuid) to anon, authenticated;
