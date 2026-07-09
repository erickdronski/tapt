-- seeds/0001_world_classics.sql
-- Editorial seed: real, verifiable world-classic flagship beers + BJCP 2021
-- style reference. Rules: every row is a real product; ABV only where it is
-- the standard published figure (null otherwise — blank beats invented);
-- no ratings, popularity, or momentum are EVER seeded (those stay first-party).
-- Idempotent: dedups beers by name and breweries by lower(name).

-- ============================================================ provenance
insert into ingestion_source (id, name, source_kind, license, homepage_url, ingest_cadence, notes)
values
  ('bjcp-2021', 'BJCP 2021 Style Guidelines', 'style', 'BJCP guidelines; free to reference with attribution', 'https://www.bjcp.org/style/2021/', 'yearly', 'Beer style families, descriptions, and vital-statistics ranges.'),
  ('us-ttb-labeling', 'US TTB labeling standard', 'reference', 'US federal regulation (public domain)', 'https://www.ttb.gov', 'yearly', 'Non-alcoholic labeling threshold (0.5% ABV).'),
  ('tapt_editorial', 'Tapt editorial seed', 'beer_catalog', 'First-party editorial curation of real, verifiable products', null, 'as-needed', 'World classic flagship beers; ABV only where standard published figure.')
on conflict (id) do nothing;

-- ============================================================ world classics
with data (beer, brewery, country, style, abv, na) as (
  values
  -- Belgium
  ('Orval', 'Orval', 'Belgium', 'Belgian Pale Ale', 6.2::numeric, false),
  ('Rochefort 10', 'Rochefort', 'Belgium', 'Belgian Quadrupel', 11.3, false),
  ('Westvleteren 12', 'Westvleteren', 'Belgium', 'Belgian Quadrupel', 10.2, false),
  ('La Chouffe', 'Brasserie d''Achouffe', 'Belgium', 'Belgian Blonde', 8.0, false),
  ('Tripel Karmeliet', 'Bosteels', 'Belgium', 'Tripel', 8.4, false),
  ('Saison Dupont', 'Brasserie Dupont', 'Belgium', 'Saison', 6.5, false),
  ('Rodenbach Grand Cru', 'Rodenbach', 'Belgium', 'Flanders Red Ale', 6.0, false),
  ('Cantillon Gueuze 100% Lambic', 'Cantillon', 'Belgium', 'Gueuze', null, false),
  ('Boon Oude Geuze', 'Brouwerij Boon', 'Belgium', 'Gueuze', null, false),
  ('Leffe Blonde', 'Leffe', 'Belgium', 'Belgian Blonde', 6.6, false),
  ('Hoegaarden', 'Hoegaarden', 'Belgium', 'Witbier', 4.9, false),
  ('Stella Artois', 'Stella Artois', 'Belgium', 'Pale Lager', null, false),
  ('Chimay White (Cinq Cents)', 'Chimay', 'Belgium', 'Tripel', 8.0, false),
  ('Duchesse de Bourgogne', 'Verhaeghe', 'Belgium', 'Flanders Red Ale', 6.2, false),
  -- Germany
  ('Weihenstephaner Vitus', 'Weihenstephan', 'Germany', 'Weizenbock', 7.7, false),
  ('Ayinger Celebrator', 'Ayinger', 'Germany', 'Doppelbock', 6.7, false),
  ('Schneider Weisse Aventinus', 'Schneider', 'Germany', 'Weizenbock', 8.2, false),
  ('Spaten Oktoberfest', 'Spaten', 'Germany', 'Märzen', 5.9, false),
  ('Hofbräu Original', 'Hofbräu München', 'Germany', 'Helles', 5.1, false),
  ('Augustiner Edelstoff', 'Augustiner', 'Germany', 'Export Helles', 5.6, false),
  ('Rothaus Tannenzäpfle', 'Rothaus', 'Germany', 'Pilsner', 5.1, false),
  ('Bitburger Premium Pils', 'Bitburger', 'Germany', 'Pilsner', 4.8, false),
  ('Warsteiner Premium Pilsener', 'Warsteiner', 'Germany', 'Pilsner', 4.8, false),
  ('Erdinger Weissbier', 'Erdinger', 'Germany', 'Hefeweizen', 5.3, false),
  ('Franziskaner Hefe-Weissbier', 'Franziskaner', 'Germany', 'Hefeweizen', 5.0, false),
  ('Aecht Schlenkerla Rauchbier Märzen', 'Schlenkerla', 'Germany', 'Rauchbier', 5.1, false),
  ('Köstritzer Schwarzbier', 'Köstritzer', 'Germany', 'Schwarzbier', 4.8, false),
  ('Gaffel Kölsch', 'Gaffel', 'Germany', 'Kölsch', 4.8, false),
  ('Uerige Altbier', 'Uerige', 'Germany', 'Altbier', 4.7, false),
  ('Paulaner Salvator', 'Paulaner', 'Germany', 'Doppelbock', 7.9, false),
  ('Beck''s', 'Beck''s', 'Germany', 'Pilsner', null, false),
  -- Czechia
  ('Staropramen Premium', 'Staropramen', 'Czechia', 'Pale Lager', null, false),
  ('Velkopopovický Kozel Černý', 'Velké Popovice', 'Czechia', 'Dark Lager', 3.8, false),
  ('Bernard Sváteční Ležák', 'Bernard', 'Czechia', 'Pilsner', null, false),
  -- United Kingdom
  ('Fuller''s ESB', 'Fuller''s', 'United Kingdom', 'ESB', null, false),
  ('Samuel Smith''s Oatmeal Stout', 'Samuel Smith', 'United Kingdom', 'Oatmeal Stout', 5.0, false),
  ('Samuel Smith''s Nut Brown Ale', 'Samuel Smith', 'United Kingdom', 'Brown Ale', 5.0, false),
  ('Timothy Taylor''s Landlord', 'Timothy Taylor', 'United Kingdom', 'Bitter', null, false),
  ('Theakston Old Peculier', 'Theakston', 'United Kingdom', 'Old Ale', 5.6, false),
  ('Newcastle Brown Ale', 'Newcastle', 'United Kingdom', 'Brown Ale', 4.7, false),
  ('BrewDog Punk IPA', 'BrewDog', 'United Kingdom', 'IPA', null, false),
  ('Belhaven Best', 'Belhaven', 'United Kingdom', 'Scottish Ale', null, false),
  -- Ireland
  ('Guinness Extra Stout', 'Guinness', 'Ireland', 'Stout', null, false),
  ('Guinness Foreign Extra Stout', 'Guinness', 'Ireland', 'Foreign Extra Stout', 7.5, false),
  ('Murphy''s Irish Stout', 'Murphy''s', 'Ireland', 'Irish Stout', 4.0, false),
  ('Smithwick''s Red Ale', 'Smithwick''s', 'Ireland', 'Irish Red Ale', null, false),
  -- United States
  ('Bell''s Oberon', 'Bell''s', 'United States', 'American Wheat', 5.8, false),
  ('Founders Breakfast Stout', 'Founders', 'United States', 'Imperial Stout', 8.3, false),
  ('Goose Island 312 Urban Wheat', 'Goose Island', 'United States', 'American Wheat', 4.2, false),
  ('Lagunitas IPA', 'Lagunitas', 'United States', 'IPA', 6.2, false),
  ('Stone IPA', 'Stone', 'United States', 'IPA', 6.9, false),
  ('Arrogant Bastard Ale', 'Stone', 'United States', 'American Strong Ale', 7.2, false),
  ('Dogfish Head 90 Minute IPA', 'Dogfish Head', 'United States', 'Imperial IPA', 9.0, false),
  ('Allagash White', 'Allagash', 'United States', 'Witbier', 5.2, false),
  ('Blue Moon Belgian White', 'Blue Moon', 'United States', 'Witbier', 5.4, false),
  ('Brooklyn Lager', 'Brooklyn Brewery', 'United States', 'Amber Lager', 5.2, false),
  ('Anchor Steam', 'Anchor', 'United States', 'California Common', 4.9, false),
  ('Deschutes Black Butte Porter', 'Deschutes', 'United States', 'Porter', null, false),
  ('Deschutes Fresh Squeezed IPA', 'Deschutes', 'United States', 'IPA', 6.4, false),
  ('Cigar City Jai Alai', 'Cigar City', 'United States', 'IPA', 7.5, false),
  ('Firestone Walker 805', 'Firestone Walker', 'United States', 'Blonde Ale', 4.7, false),
  ('New Belgium Fat Tire', 'New Belgium', 'United States', 'Amber Ale', null, false),
  ('Voodoo Ranger IPA', 'New Belgium', 'United States', 'IPA', 7.0, false),
  ('Dale''s Pale Ale', 'Oskar Blues', 'United States', 'Pale Ale', 6.5, false),
  ('Yuengling Traditional Lager', 'Yuengling', 'United States', 'Amber Lager', 4.5, false),
  ('Miller High Life', 'Miller', 'United States', 'American Lager', 4.6, false),
  ('Pabst Blue Ribbon', 'Pabst', 'United States', 'American Lager', 4.7, false),
  ('Coors Banquet', 'Coors', 'United States', 'American Lager', 5.0, false),
  ('Michelob Ultra', 'Anheuser-Busch', 'United States', 'Light Lager', 4.2, false),
  ('Budweiser', 'Anheuser-Busch', 'United States', 'American Lager', 5.0, false),
  ('Bud Light', 'Anheuser-Busch', 'United States', 'Light Lager', 4.2, false),
  ('Tree House Julius', 'Tree House', 'United States', 'Hazy IPA', 6.8, false),
  ('Russian River Blind Pig IPA', 'Russian River', 'United States', 'IPA', null, false),
  ('Alaskan Amber', 'Alaskan', 'United States', 'Altbier', 5.3, false),
  ('Shiner Bock', 'Spoetzl', 'United States', 'Bock', 4.4, false),
  ('Great Lakes Edmund Fitzgerald', 'Great Lakes', 'United States', 'Porter', 6.0, false),
  ('Left Hand Milk Stout Nitro', 'Left Hand', 'United States', 'Milk Stout', 6.0, false),
  ('Rogue Dead Guy Ale', 'Rogue', 'United States', 'Maibock', 6.8, false),
  ('Odell 90 Shilling', 'Odell', 'United States', 'Scottish Ale', 5.3, false),
  ('Toppling Goliath Pseudo Sue', 'Toppling Goliath', 'United States', 'Pale Ale', 5.8, false),
  ('Maine Beer Lunch', 'Maine Beer Company', 'United States', 'IPA', 7.0, false),
  ('Half Acre Daisy Cutter', 'Half Acre', 'United States', 'Pale Ale', 5.2, false),
  -- Mexico
  ('Corona Extra', 'Grupo Modelo', 'Mexico', 'Pale Lager', 4.6, false),
  ('Negra Modelo', 'Grupo Modelo', 'Mexico', 'Dark Lager', 5.4, false),
  ('Pacifico', 'Grupo Modelo', 'Mexico', 'Pilsner', null, false),
  ('Victoria', 'Grupo Modelo', 'Mexico', 'Vienna Lager', 4.0, false),
  ('Dos Equis Lager Especial', 'Cuauhtémoc Moctezuma', 'Mexico', 'Pale Lager', null, false),
  -- Japan
  ('Asahi Super Dry', 'Asahi', 'Japan', 'Japanese Rice Lager', 5.0, false),
  ('Sapporo Premium', 'Sapporo', 'Japan', 'Pale Lager', null, false),
  ('Kirin Ichiban', 'Kirin', 'Japan', 'Pale Lager', 5.0, false),
  ('Yebisu', 'Sapporo', 'Japan', 'Dortmunder Lager', 5.0, false),
  ('Hitachino Nest White Ale', 'Kiuchi', 'Japan', 'Witbier', 5.5, false),
  -- Asia
  ('Tsingtao', 'Tsingtao', 'China', 'Pale Lager', 4.7, false),
  ('Snow', 'CR Snow', 'China', 'Pale Lager', null, false),
  ('Singha', 'Boon Rawd', 'Thailand', 'Pale Lager', 5.0, false),
  ('Chang', 'ThaiBev', 'Thailand', 'Pale Lager', null, false),
  ('333 Premium Export', 'Sabeco', 'Vietnam', 'Pale Lager', null, false),
  ('Tiger', 'Asia Pacific Breweries', 'Singapore', 'Pale Lager', 5.0, false),
  ('San Miguel Pale Pilsen', 'San Miguel', 'Philippines', 'Pilsner', 5.0, false),
  ('Kingfisher Premium', 'United Breweries', 'India', 'Lager', null, false),
  ('Lion Stout', 'Lion Brewery Ceylon', 'Sri Lanka', 'Foreign Extra Stout', 8.8, false),
  ('Cass Fresh', 'Oriental Brewery', 'South Korea', 'Pale Lager', 4.5, false),
  ('Taiwan Beer', 'Taiwan Tobacco & Liquor', 'Taiwan', 'Pale Lager', null, false),
  -- Australia & New Zealand
  ('Coopers Sparkling Ale', 'Coopers', 'Australia', 'Australian Pale Ale', 5.8, false),
  ('Coopers Original Pale Ale', 'Coopers', 'Australia', 'Pale Ale', 4.5, false),
  ('Victoria Bitter', 'Carlton & United', 'Australia', 'Lager', 4.9, false),
  ('Little Creatures Pale Ale', 'Little Creatures', 'Australia', 'Pale Ale', 5.2, false),
  ('Stone & Wood Pacific Ale', 'Stone & Wood', 'Australia', 'Pale Ale', 4.4, false),
  ('Balter XPA', 'Balter', 'Australia', 'XPA', 5.0, false),
  ('Steinlager Classic', 'Lion', 'New Zealand', 'Lager', 5.0, false),
  ('Speight''s Gold Medal Ale', 'Speight''s', 'New Zealand', 'Golden Ale', 4.0, false),
  ('Panhead Supercharger APA', 'Panhead', 'New Zealand', 'Pale Ale', 5.7, false),
  -- Canada
  ('La Fin du Monde', 'Unibroue', 'Canada', 'Tripel', 9.0, false),
  ('Blanche de Chambly', 'Unibroue', 'Canada', 'Witbier', 5.0, false),
  ('Moosehead Lager', 'Moosehead', 'Canada', 'Lager', 5.0, false),
  ('Labatt Blue', 'Labatt', 'Canada', 'Pilsner', 5.0, false),
  ('Péché Mortel', 'Dieu du Ciel!', 'Canada', 'Imperial Coffee Stout', 9.5, false),
  -- Netherlands
  ('La Trappe Quadrupel', 'La Trappe', 'Netherlands', 'Quadrupel', 10.0, false),
  ('Grolsch Premium Pilsner', 'Grolsch', 'Netherlands', 'Pilsner', null, false),
  -- Austria
  ('Stiegl Goldbräu', 'Stiegl', 'Austria', 'Märzen', 4.9, false),
  ('Gösser Märzen', 'Gösser', 'Austria', 'Märzen', null, false),
  -- Denmark & Nordics
  ('Carlsberg Pilsner', 'Carlsberg', 'Denmark', 'Pilsner', null, false),
  ('Tuborg Green', 'Tuborg', 'Denmark', 'Pale Lager', null, false),
  ('Carnegie Porter', 'Carlsberg Sverige', 'Sweden', 'Baltic Porter', 5.5, false),
  ('Sinebrychoff Porter', 'Sinebrychoff', 'Finland', 'Baltic Porter', 7.2, false),
  ('Karhu', 'Sinebrychoff', 'Finland', 'Lager', null, false),
  ('Einstök Icelandic White Ale', 'Einstök', 'Iceland', 'Witbier', 5.2, false),
  ('Ringnes Pilsener', 'Ringnes', 'Norway', 'Pilsner', null, false),
  -- Poland & Baltics & Eastern Europe
  ('Żywiec Porter', 'Żywiec', 'Poland', 'Baltic Porter', 9.5, false),
  ('Lech Premium', 'Lech', 'Poland', 'Pale Lager', null, false),
  ('Švyturys Ekstra', 'Švyturys', 'Lithuania', 'Dortmunder Lager', null, false),
  ('Obolon Premium', 'Obolon', 'Ukraine', 'Pale Lager', null, false),
  ('Põhjala Öö', 'Põhjala', 'Estonia', 'Imperial Baltic Porter', 10.5, false),
  ('Baltika No. 6 Porter', 'Baltika', 'Russia', 'Baltic Porter', 7.0, false),
  -- Italy, Spain, Portugal, France, Switzerland, Greece, Turkey
  ('Peroni Nastro Azzurro', 'Peroni', 'Italy', 'Pale Lager', null, false),
  ('Birra Moretti', 'Moretti', 'Italy', 'Pale Lager', null, false),
  ('Baladin Isaac', 'Baladin', 'Italy', 'Witbier', null, false),
  ('Estrella Damm', 'Damm', 'Spain', 'Pale Lager', null, false),
  ('Mahou Cinco Estrellas', 'Mahou', 'Spain', 'Pale Lager', 5.5, false),
  ('Alhambra Reserva 1925', 'Alhambra', 'Spain', 'Pale Lager', 6.4, false),
  ('Super Bock', 'Super Bock Group', 'Portugal', 'Pale Lager', null, false),
  ('Sagres', 'Sociedade Central de Cervejas', 'Portugal', 'Pale Lager', null, false),
  ('Kronenbourg 1664', 'Kronenbourg', 'France', 'Pale Lager', null, false),
  ('3 Monts', 'Brasserie de Saint-Sylvestre', 'France', 'Bière de Garde', 8.5, false),
  ('Feldschlösschen Original', 'Feldschlösschen', 'Switzerland', 'Lager', null, false),
  ('Mythos', 'Mythos Brewery', 'Greece', 'Lager', null, false),
  ('Efes Pilsener', 'Anadolu Efes', 'Turkey', 'Pilsner', 5.0, false),
  -- Latin America & Caribbean
  ('Brahma', 'Ambev', 'Brazil', 'Pale Lager', null, false),
  ('Antarctica Original', 'Ambev', 'Brazil', 'Pale Lager', null, false),
  ('Quilmes Clásica', 'Quilmes', 'Argentina', 'Pale Lager', null, false),
  ('Cusqueña', 'Backus', 'Peru', 'Pale Lager', null, false),
  ('Red Stripe', 'Desnoes & Geddes', 'Jamaica', 'Lager', 4.7, false),
  -- Africa
  ('Castle Lager', 'South African Breweries', 'South Africa', 'Pale Lager', null, false),
  ('Windhoek Lager', 'Namibia Breweries', 'Namibia', 'Lager', 4.0, false),
  ('Tusker', 'East African Breweries', 'Kenya', 'Lager', 4.2, false),
  ('Star Lager', 'Nigerian Breweries', 'Nigeria', 'Lager', null, false),
  -- No / Low (first-class citizens)
  ('Athletic Run Wild IPA', 'Athletic Brewing', 'United States', 'Non-Alcoholic IPA', 0.5, true),
  ('Athletic Upside Dawn', 'Athletic Brewing', 'United States', 'Non-Alcoholic Golden Ale', 0.5, true),
  ('Heineken 0.0', 'Heineken', 'Netherlands', 'Non-Alcoholic Lager', 0.0, true),
  ('Guinness 0', 'Guinness', 'Ireland', 'Non-Alcoholic Stout', 0.0, true),
  ('Clausthaler Original', 'Clausthaler', 'Germany', 'Non-Alcoholic Lager', 0.5, true),
  ('Erdinger Alkoholfrei', 'Erdinger', 'Germany', 'Non-Alcoholic Weissbier', 0.5, true),
  ('Samuel Adams Just the Haze', 'Boston Beer', 'United States', 'Non-Alcoholic IPA', 0.5, true)
),
new_breweries as (
  insert into brewery (name, country, external_ids)
  select distinct on (lower(d.brewery)) d.brewery, d.country,
    jsonb_build_object('source_note', 'Tapt editorial brand seed', 'seeded_at', '2026-07-09')
  from data d
  where not exists (select 1 from brewery br where lower(br.name) = lower(d.brewery))
  returning id, name
)
insert into beer_catalog (name, style, abv, is_na_low, brewery_id, external_ids)
select
  d.beer,
  d.style,
  d.abv,
  d.na,
  coalesce(
    (select nb.id from new_breweries nb where lower(nb.name) = lower(d.brewery)),
    (select br.id from brewery br where lower(br.name) = lower(d.brewery) order by br.created_at limit 1)
  ),
  jsonb_build_object('source', 'tapt_editorial', 'note', 'world classic flagship')
from data d
where not exists (select 1 from beer_catalog bc where lower(bc.name) = lower(d.beer));

-- ============================================================ style reference
-- BJCP 2021 style guidelines (public reference: https://www.bjcp.org/style/2021/).
-- Ranges included only where standard; nulls where a single range would mislead.
with styles (family, name, description, abv_min, abv_max, ibu_min, ibu_max, srm_min, srm_max) as (
  values
  ('IPA', 'American IPA', 'Decidedly hoppy and bitter, moderately strong American pale ale — citrus, pine, tropical fruit.', 5.5::numeric, 7.5::numeric, 40::int, 70::int, 6::int, 14::int),
  ('IPA', 'Hazy IPA', 'Juicy, cloudy, soft-bodied IPA with intense fruit-forward hop aroma and low perceived bitterness.', 6.0, 9.0, 25, 60, 3, 7),
  ('IPA', 'Double IPA', 'An intensely hoppy, fairly strong pale ale — a showcase for hops without heavy maltiness.', 7.5, 10.0, 60, 100, 6, 14),
  ('IPA', 'English IPA', 'A hoppy, moderately-strong, very well-attenuated pale British ale with earthy, floral hop character.', 5.0, 7.5, 40, 60, 6, 14),
  ('Pale Ale', 'American Pale Ale', 'An average-strength, hop-forward pale American craft beer — balanced enough for every day.', 4.5, 6.2, 30, 50, 5, 10),
  ('Pale Ale', 'Blonde Ale', 'Easy-drinking, approachable, malt-oriented American craft beer — the gateway pour.', 3.8, 5.5, 15, 28, 3, 6),
  ('Bitter', 'Best Bitter', 'A flavorful, yet refreshing session English ale — malty, fruity, low carbonation on cask.', 3.8, 4.6, 25, 40, 8, 16),
  ('Bitter', 'Strong Bitter (ESB)', 'An average-strength to moderately-strong British bitter with hop, malt, and fruit balance.', 4.6, 6.2, 30, 50, 8, 18),
  ('Lager', 'American Light Lager', 'Highly carbonated, very light-bodied, nearly flavor-neutral lager brewed for maximum refreshment.', 2.8, 4.2, 8, 12, 2, 3),
  ('Lager', 'American Lager', 'A very pale, highly-carbonated, light-bodied, well-attenuated lager with a crisp, dry finish.', 4.2, 5.3, 8, 18, 2, 3),
  ('Lager', 'International Pale Lager', 'The world''s everyday golden lager — clean, crisp, and universally understood.', 4.5, 6.0, 18, 25, 2, 6),
  ('Lager', 'German Pils', 'A light-bodied, highly-attenuated, gold-colored German lager with a crisp bitter finish and floral hops.', 4.4, 5.2, 22, 40, 2, 5),
  ('Lager', 'Czech Premium Pale Lager', 'Rich, characterful, pale Czech lager with considerable Saaz hop flavor — the original pilsner family.', 4.2, 5.8, 30, 45, 3, 6),
  ('Lager', 'Munich Helles', 'A clean, malty, gold-colored German lager with soft bread flavor and a gentle finish.', 4.7, 5.4, 16, 22, 3, 6),
  ('Lager', 'Festbier', 'A smooth, clean, pale German festival lager — the modern Oktoberfest pour.', 5.8, 6.3, 18, 25, 4, 7),
  ('Lager', 'Märzen', 'An amber, malty German lager with a clean, dry finish — toasty bread crust in a glass.', 5.6, 6.3, 18, 24, 8, 17),
  ('Lager', 'Vienna Lager', 'A moderate-strength amber lager with soft, smooth maltiness and clean finish.', 4.7, 5.5, 18, 30, 9, 15),
  ('Lager', 'Munich Dunkel', 'Deeply bready, chocolatey dark German lager that stays smooth and drinkable.', 4.5, 5.6, 18, 28, 14, 28),
  ('Lager', 'Schwarzbier', 'A dark German lager balancing roasted-but-smooth coffee notes with lager crispness.', 4.4, 5.4, 20, 35, 17, 30),
  ('Bock', 'Dunkles Bock', 'A dark, strong, malty German lager — bread crust and caramel, no roast burn.', 6.3, 7.2, 20, 27, 14, 22),
  ('Bock', 'Doppelbock', 'A strong, rich, very malty German lager — liquid bread with warming strength.', 7.0, 10.0, 16, 26, 6, 25),
  ('Bock', 'Helles Bock (Maibock)', 'A relatively pale, strong, malty German lager with lightly toasted character.', 6.3, 7.4, 23, 35, 6, 11),
  ('Wheat', 'Weissbier', 'A pale, refreshing German wheat beer with banana and clove yeast character.', 4.3, 5.6, 8, 15, 2, 6),
  ('Wheat', 'Weizenbock', 'A strong, malty, fruity, wheat-based ale — the bock of the wheat family.', 6.5, 9.0, 15, 30, 6, 25),
  ('Wheat', 'Witbier', 'A refreshing, elegant, moderate-strength Belgian wheat ale with coriander and orange peel.', 4.5, 5.5, 8, 20, 2, 4),
  ('Wheat', 'American Wheat', 'A refreshing wheat beer displaying more hop character and less yeast character than European cousins.', 4.0, 5.5, 15, 30, 3, 6),
  ('Sour', 'Berliner Weisse', 'A very pale, refreshing, low-alcohol German wheat beer with clean lactic sourness.', 2.8, 3.8, 3, 8, 2, 3),
  ('Sour', 'Gose', 'A highly-carbonated, tart German wheat beer with restrained coriander and salt.', 4.2, 4.8, 5, 12, 3, 4),
  ('Sour', 'Flanders Red Ale', 'A sour, fruity, wine-like Belgian-style red ale aged in oak — beer''s answer to Burgundy.', 4.6, 6.5, 10, 25, 10, 16),
  ('Sour', 'Gueuze', 'A blend of young and old lambics — complex, sour, funky, bottle-fermented Belgian tradition.', 5.0, 8.0, 0, 10, 3, 7),
  ('Belgian', 'Belgian Blond Ale', 'A moderately strong golden Belgian ale — subtle spice, soft fruit, deceptive drinkability.', 6.0, 7.5, 15, 30, 4, 7),
  ('Belgian', 'Saison', 'A refreshing, highly attenuated, hoppy, fairly bitter farmhouse ale with spicy yeast character.', 5.0, 7.0, 20, 35, 5, 14),
  ('Belgian', 'Belgian Tripel', 'A strong, spicy, dry golden Belgian ale that hides its strength dangerously well.', 7.5, 9.5, 20, 40, 4, 7),
  ('Belgian', 'Belgian Dubbel', 'A deep reddish-brown, moderately strong, malty, complex Trappist-style ale — raisin and dark fruit.', 6.0, 7.6, 15, 25, 10, 17),
  ('Belgian', 'Belgian Dark Strong Ale', 'The quadrupel zone — dark, rich, complex, very strong Belgian ale.', 8.0, 12.0, 20, 35, 12, 22),
  ('Belgian', 'Belgian Golden Strong Ale', 'Pale, complex, effervescent, strong Belgian ale — fruity, spicy, dry (the Duvel family).', 7.5, 10.5, 22, 35, 3, 6),
  ('Porter & Stout', 'English Porter', 'A moderate-strength brown British beer with restrained roasty character — chocolate before coffee.', 4.0, 5.4, 18, 35, 20, 30),
  ('Porter & Stout', 'American Porter', 'A substantial, malty dark beer with a complementary roasted and often hoppy character.', 4.8, 6.5, 25, 50, 22, 40),
  ('Porter & Stout', 'Irish Stout', 'A black beer with pronounced roasted flavor, often resembling coffee — smooth and sessionable.', 4.0, 4.5, 25, 45, 25, 40),
  ('Porter & Stout', 'Sweet Stout', 'A very dark, sweet, full-bodied stout — milk sugar softens the roast (milk stout).', 4.0, 6.0, 20, 40, 30, 40),
  ('Porter & Stout', 'Oatmeal Stout', 'A very dark, full-bodied, roasty stout with the smooth silkiness oats bring.', 4.2, 5.9, 25, 40, 22, 40),
  ('Porter & Stout', 'Foreign Extra Stout', 'A very dark, moderately strong, roasty stout brewed for the tropics and export.', 6.3, 8.0, 50, 70, 30, 40),
  ('Porter & Stout', 'Imperial Stout', 'An intensely-flavored, big, dark ale — roast, fruit, and warming strength.', 8.0, 12.0, 50, 90, 30, 40),
  ('Porter & Stout', 'Baltic Porter', 'A strong, malty, smooth dark lager-fermented porter from the Baltic rim.', 6.5, 9.5, 20, 40, 17, 30),
  ('Amber & Brown', 'American Amber Ale', 'An amber, hoppy, moderate-strength American craft beer with caramel malt backbone.', 4.5, 6.2, 25, 40, 10, 17),
  ('Amber & Brown', 'California Common', 'A lightly fruity beer brewed with lager yeast at warm temperatures — a true American original.', 4.5, 5.5, 30, 45, 10, 14),
  ('Amber & Brown', 'American Brown Ale', 'A malty brown ale with chocolate and caramel plus American hop character.', 4.3, 6.2, 20, 30, 18, 35),
  ('Amber & Brown', 'Irish Red Ale', 'An easy-drinking amber ale with caramel sweetness and a dry roasted finish.', 3.8, 5.0, 18, 28, 9, 14),
  ('Amber & Brown', 'Kölsch', 'A clean, crisp, delicately-balanced pale ale fermented cool and lagered — Cologne''s pride.', 4.4, 5.2, 18, 30, 3, 5),
  ('Amber & Brown', 'Altbier', 'A well-balanced, bitter yet malty, clean, smooth, coppery German ale — Düsseldorf''s answer to Cologne.', 4.3, 5.5, 25, 50, 9, 17),
  ('Specialty', 'Rauchbier', 'An elegant, malty German amber lager with balanced beechwood smoke — campfire in a stein.', 4.8, 6.0, 20, 30, 12, 22),
  ('Strong', 'Old Ale', 'An aged, malty, warming British strong ale — dark fruit, toffee, and time.', 5.5, 9.0, 30, 60, 10, 22),
  ('Strong', 'English Barleywine', 'The richest and strongest of English ales — an intense, complex, warming sipper.', 8.0, 12.0, 35, 70, 8, 22),
  ('No & Low', 'Non-Alcoholic Beer', 'Beer at 0.5% ABV or below (US labeling standard) — full flavor, zero proof, counts just as much.', 0.0, 0.5, null, null, null, null)
)
insert into beer_style_reference (style_family, style_name, description, abv_min, abv_max, ibu_min, ibu_max, color_min_srm, color_max_srm, source_id, source_url)
select s.family, s.name, s.description, s.abv_min, s.abv_max,
       s.ibu_min::smallint, s.ibu_max::smallint, s.srm_min::smallint, s.srm_max::smallint,
       case when s.family = 'No & Low' then 'us-ttb-labeling' else 'bjcp-2021' end,
       case when s.family = 'No & Low' then 'https://www.ttb.gov' else 'https://www.bjcp.org/style/2021/' end
from styles s
where not exists (
  select 1 from beer_style_reference r where lower(r.style_name) = lower(s.name)
);
