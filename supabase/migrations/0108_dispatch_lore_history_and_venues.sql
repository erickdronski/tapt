-- Editorial lore for The Tapt Dispatch: real, curated beer-history facts and
-- legendary venues. Rotated deterministically by ISO week so each issue is fresh.
-- Everything here is real and widely documented; superlative/"oldest" claims are
-- phrased as claims, per the no-fabrication rule.
create table if not exists public.dispatch_lore (
  id      serial primary key,
  kind    text not null check (kind in ('history','venue')),
  title   text not null,
  body    text not null,
  meta    text,
  unique (kind, title)
);

insert into public.dispatch_lore (kind, title, body, meta) values
('history', $b$The 1516 purity law still in force$b$, $b$Bavaria's Reinheitsgebot, enacted on 23 April 1516, ruled that beer could contain only water, barley, and hops (yeast joined the list once science caught up). Five centuries on, it still shapes how German beer is brewed.$b$, $b$Germany · 1516$b$),
('history', $b$Guinness signed a 9,000-year lease$b$, $b$In 1759 Arthur Guinness signed a lease on Dublin's St. James's Gate brewery for 9,000 years at 45 pounds a year. The brewery outgrew the lease long ago, but the confidence aged well.$b$, $b$Ireland · 1759$b$),
('history', $b$The oldest recipe is a hymn$b$, $b$The earliest known beer recipe is baked into the Hymn to Ninkasi, a roughly 3,800-year-old Sumerian ode to the goddess of beer that doubles as brewing instructions.$b$, $b$Mesopotamia · c. 1800 BC$b$),
('history', $b$IPA was built for a sea voyage$b$, $b$India Pale Ale earned its name from heavily hopped pale ales shipped from England to India in the 1800s. The extra hops acted as a preservative for the long, hot journey, and a style was born.$b$, $b$England · 1800s$b$),
('history', $b$One town shaped most of the world's beer$b$, $b$The world's first pale lager was brewed in Plzen, Bohemia, in 1842 by Bavarian brewer Josef Groll. Golden, crisp pilsner went on to become the template for most of the beer made today.$b$, $b$Czechia · 1842$b$),
('history', $b$London once flooded with beer$b$, $b$In 1814 a giant fermentation vat at a London brewery burst, sending well over a million litres of porter into the streets in a wave that killed eight people. It is remembered as the London Beer Flood.$b$, $b$England · 1814$b$),
('history', $b$Only a handful of beers are truly Trappist$b$, $b$The Authentic Trappist Product mark can only go on beer brewed inside a Trappist monastery, under the monks' control, with proceeds supporting the community or charity. Fewer than a dozen breweries worldwide qualify.$b$, $b$Europe$b$),
('history', $b$Lambic is fermented by thin air$b$, $b$Belgium's lambic beers add no brewer's yeast at all. Hot wort is left open overnight in shallow coolships so wild yeast and bacteria drifting through the Zenne valley near Brussels can begin fermentation.$b$, $b$Belgium$b$),
('history', $b$Bock beer is named after a goat$b$, $b$Bock originated in the German town of Einbeck. Bavarians pronounced the name ein Bock, which also means a billy goat, so bock labels have featured goats ever since.$b$, $b$Germany$b$),
('history', $b$Beer was once bittered with herbs, not hops$b$, $b$Before hops took over around the 15th and 16th centuries, brewers flavoured and preserved beer with gruit, a closely guarded mix of herbs like bog myrtle, yarrow, and sweet gale.$b$, $b$Medieval Europe$b$),
('history', $b$A wheat beer's banana is all yeast$b$, $b$The banana-and-clove character of a German wheat beer comes entirely from the yeast, which throws off fruity isoamyl acetate and clove-like 4-vinyl guaiacol. There is no fruit or spice in the recipe.$b$, $b$Germany$b$),
('history', $b$Porter was named after its drinkers$b$, $b$The dark, hearty porter style of 1700s London took its name from the porters, the street and river workers who drank it by the gallon.$b$, $b$England · 1700s$b$),
('history', $b$Steam beer was born without ice$b$, $b$California steam beer emerged during the Gold Rush, when brewers fermented lager yeast at warm ale temperatures because there was no ice for cooling. It is one of the few truly American-born styles.$b$, $b$USA · 1800s$b$),
('history', $b$Oktoberfest started as a wedding$b$, $b$The first Oktoberfest was held in Munich in October 1810 to celebrate the marriage of Crown Prince Ludwig of Bavaria. The public was invited, everyone had a good time, and it simply never stopped.$b$, $b$Germany · 1810$b$),
('history', $b$Barley wine is not wine$b$, $b$Barley wine is a very strong ale, often 8 to 12 percent and beyond, named for a wine-like strength rather than any grape. English brewers coined the term to signal: sip this slowly.$b$, $b$England$b$),
('history', $b$The saint who prescribed beer$b$, $b$St. Arnold of Metz is a patron of brewers. During a plague he is said to have urged people to drink beer over water. Because brewing water was boiled, the advice unknowingly spared many from waterborne illness.$b$, $b$Europe · 7th century$b$),
('venue', $b$Sean's Bar$b$, $b$In the Irish midlands sits a pub that Guinness World Records recognises as Ireland's oldest, with roots traced to around 900 AD. Renovations even uncovered ancient wattle-and-wicker walls behind the plaster.$b$, $b$Athlone, Ireland · c. 900 AD$b$),
('venue', $b$U Fleku$b$, $b$This Prague institution has brewed its own dark lager on the same spot since 1499. More than five centuries later it still pours a single house beer to packed, candlelit halls.$b$, $b$Prague, Czechia · 1499$b$),
('venue', $b$Cantillon$b$, $b$A working lambic brewery and living museum in Brussels, Cantillon has spontaneously fermented sour beer in open coolships since 1900, run by the same family and doing it almost exactly as they always have.$b$, $b$Brussels, Belgium · 1900$b$),
('venue', $b$McSorley's Old Ale House$b$, $b$Open in New York's East Village since 1854, McSorley's serves just two beers, light and dark, in pairs. Its motto, Be Good or Be Gone, has outlasted more than a few patrons.$b$, $b$New York City · 1854$b$),
('venue', $b$The Brazen Head$b$, $b$Dublin's Brazen Head traces its origins to 1198, making it a leading contender for Ireland's oldest pub and a long-running home of music and storytelling.$b$, $b$Dublin, Ireland · 1198$b$),
('venue', $b$Weihenstephan$b$, $b$The Bavarian State Brewery Weihenstephan in Freising traces its brewing back to 1040 AD and is widely called the world's oldest continuously operating brewery.$b$, $b$Freising, Germany · 1040$b$),
('venue', $b$Ye Olde Trip to Jerusalem$b$, $b$Carved partly into the sandstone beneath Nottingham Castle, this inn claims a founding date of 1189 and a name tied to knights setting off for the Crusades.$b$, $b$Nottingham, England · 1189$b$),
('venue', $b$The Eagle and Child$b$, $b$Nicknamed the Bird and Baby, this Oxford pub was the regular meeting place of the Inklings, the writing circle that included J.R.R. Tolkien and C.S. Lewis.$b$, $b$Oxford, England$b$),
('venue', $b$Delirium Cafe$b$, $b$This warren of bars in central Brussels once held a Guinness World Record for the most beers commercially available, with a list running well past 2,000.$b$, $b$Brussels, Belgium$b$),
('venue', $b$White Horse Tavern$b$, $b$Operating in Newport since 1673, the White Horse is often called the oldest tavern in the United States, all creaking floors and colonial timber.$b$, $b$Newport, Rhode Island · 1673$b$),
('venue', $b$Zum Uerige$b$, $b$In Dusseldorf's old town, Zum Uerige brews and pours copper-coloured Altbier that servers carry through the crowd on trays, refilling your glass until you set a coaster on top.$b$, $b$Dusseldorf, Germany$b$),
('venue', $b$Hofbrauhaus$b$, $b$Founded as a royal brewery in 1589 and later opened to the public, Munich's Hofbrauhaus is perhaps the most famous beer hall on earth, oompah band and all.$b$, $b$Munich, Germany · 1589$b$)
on conflict (kind, title) do nothing;

-- Extend the content builder with the two rotating editorial sections.
create or replace function public.build_dispatch_content()
 returns jsonb
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  with wk as (
    select (extract(isoyear from now())::int * 100 + extract(week from now())::int)::text as w
  ),
  featured as (
    select id, name, style, abv, image, brewery, country
    from (
      select bc.id,
             coalesce(nullif(bc.display_name, ''), bc.name) as name,
             coalesce(nullif(bc.style_ref, ''), bc.style) as style,
             bc.abv,
             coalesce(bc.cutout_url, bc.label_image_url) as image,
             br.name as brewery,
             public.tapt_trusted_country(br.country, br.external_ids) as country,
             1 as pri,
             to_char(w.week_start, 'YYYY-MM-DD') as ord
      from public.beer_of_week_winner w
      join public.beer_catalog bc on bc.id = w.beer_id
      left join public.brewery br on br.id = bc.brewery_id
      union all
      select bc.id,
             coalesce(nullif(bc.display_name, ''), bc.name) as name,
             coalesce(nullif(bc.style_ref, ''), bc.style) as style,
             bc.abv,
             coalesce(bc.cutout_url, bc.label_image_url) as image,
             br.name as brewery,
             public.tapt_trusted_country(br.country, br.external_ids) as country,
             2 as pri,
             md5(bc.id::text || wk.w) as ord
      from public.beer_catalog bc
      join public.brewery br on br.id = bc.brewery_id
      cross join wk
      where coalesce(bc.cutout_url, bc.label_image_url) is not null
        and bc.abv is not null and nullif(bc.style, '') is not null
        and bc.name_ok
        and bc.display_name ~ '^[A-Za-z]' and length(bc.display_name) between 4 and 34
    ) c
    order by pri asc, ord desc
    limit 1
  ),
  style as (
    select style_name, style_family, description, abv_min, abv_max,
           ibu_min, ibu_max, source_url
    from public.beer_style_reference, wk
    where nullif(description, '') is not null
    order by md5(id::text || wk.w)
    limit 1
  ),
  history as (
    select title, body, meta
    from public.dispatch_lore, wk
    where kind = 'history'
    order by md5(id::text || wk.w)
    limit 1
  ),
  venue as (
    select title, body, meta
    from public.dispatch_lore, wk
    where kind = 'venue'
    order by md5(id::text || wk.w)
    limit 1
  )
  select jsonb_build_object(
    'week', (select w from wk),
    'featured', (select row_to_json(f) from featured f),
    'style', (select row_to_json(s) from style s),
    'history', (select row_to_json(h) from history h),
    'venue', (select row_to_json(v) from venue v),
    'stats', jsonb_build_object(
      'beers', (select count(*) from public.beer_catalog),
      'breweries', (select count(*) from public.brewery),
      'venues', (select count(*) from public.venue),
      'styles', (select count(*) from public.beer_style_reference),
      'countries', (select count(distinct country) from public.brewery where country is not null)
    )
  );
$function$;
