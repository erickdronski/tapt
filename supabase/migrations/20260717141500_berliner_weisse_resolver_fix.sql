-- Audit fix (data accuracy): tapt_ref_style_name is an ordered CASE, and the
-- generic `weisse` branch (-> Weissbier) fired on "berliner weisse" BEFORE the
-- specific `berliner` branch was ever reached, so every Berliner Weisse (a pale,
-- lactic-sour 2.8-3.8% ale, BJCP 23A) resolved to Weissbier and inherited a
-- Bavarian wheat-beer style card. This resolver is the live style source and is
-- baked into beer_catalog.style_ref, so it drives Explore, catalog, market and
-- the trend feed. Fix: move the specific `berliner` branch above the generic
-- weisse branch, then recompute style_ref for the misfiled rows.
create or replace function public.tapt_ref_style_name(p_style text, p_name text)
 returns text
 language sql immutable set search_path to 'pg_catalog'
as $function$
  select case
    when h ~* '(non[- ]?alco|alcohol[- ]?free|alkoholfrei|sin alcohol|0[.,]0\s*%)' and h ~* 'ipa' then 'Non-Alcoholic IPA'
    when h ~* '(non[- ]?alco|alcohol[- ]?free|alkoholfrei|sin alcohol|0[.,]0\s*%)' then 'Non-Alcoholic Beer'
    when h ~* 'hazy|new england|neipa|juicy' then 'Hazy IPA'
    when h ~* 'west ?coast' then 'West Coast IPA'
    when h ~* 'double ?ipa|dipa|imperial ipa|triple ipa' then 'Double IPA'
    when h ~* 'english ipa|british ipa' then 'English IPA'
    when h ~* '\yipa\y|india pale' then 'American IPA'
    when h ~* 'imperial stout|russian imperial|pastry stout' then 'Imperial Stout'
    when h ~* 'oatmeal stout' then 'Oatmeal Stout'
    when h ~* 'milk stout|sweet stout|cream stout|lactose' then 'Sweet Stout'
    when h ~* 'foreign extra' then 'Foreign Extra Stout'
    when h ~* 'dry stout|irish stout' then 'Irish Stout'
    when h ~* '\ystout\y' then 'Stout'
    when h ~* 'baltic porter' then 'Baltic Porter'
    when h ~* 'english porter' then 'English Porter'
    when h ~* '\yporter\y' then 'American Porter'
    when h ~* 'weizenbock' then 'Weizenbock'
    when h ~* 'berliner' then 'Berliner Weisse'
    when h ~* 'hefe|weiss?bier|weizen|weiße|weisse' then 'Weissbier'
    when h ~* 'witbier|\ywit\y|blanche|white ale' then 'Witbier'
    when h ~* 'american wheat|wheat ale|\ywheat\y' then 'American Wheat'
    when h ~* 'flanders|oud bruin' then 'Flanders Red Ale'
    when h ~* '\ygose\y' then 'Gose'
    when h ~* 'gueuze|geuze|lambic' then 'Gueuze'
    when h ~* 'dubbel' then 'Belgian Dubbel'
    when h ~* 'tripel|triple' then 'Belgian Tripel'
    when h ~* 'quad|quadrupel|dark strong' then 'Belgian Dark Strong Ale'
    when h ~* 'golden strong' then 'Belgian Golden Strong Ale'
    when h ~* 'belgian blond' then 'Belgian Blond Ale'
    when h ~* '\ysaison\y|farmhouse' then 'Saison'
    when h ~* 'doppelbock|double bock' then 'Doppelbock'
    when h ~* 'maibock|helles bock' then 'Helles Bock (Maibock)'
    when h ~* '\ybock\y' then 'Dunkles Bock'
    when h ~* 'altbier|\yalt\y' then 'Altbier'
    when h ~* 'k(ö|o)lsch|kolsch' then 'Kölsch'
    when h ~* 'irish red|red ale' then 'Irish Red Ale'
    when h ~* 'amber' and h ~* 'ale' then 'American Amber Ale'
    when h ~* 'brown ale' and h ~* 'english|nut' then 'English Brown Ale'
    when h ~* 'brown ale' then 'American Brown Ale'
    when h ~* 'california common|steam beer' then 'California Common'
    when h ~* 'barley\s?wine|barleywine' then 'English Barleywine'
    when h ~* 'old ale' then 'Old Ale'
    when h ~* '\yesb\y|extra special bitter|strong bitter' then 'Strong Bitter (ESB)'
    when h ~* 'bitter' then 'Best Bitter'
    when h ~* 'schwarz' then 'Schwarzbier'
    when h ~* 'm(ä|a)rzen|oktoberfest' then 'Märzen'
    when h ~* 'festbier' then 'Festbier'
    when h ~* 'munich helles' then 'Munich Helles'
    when h ~* 'munich dunkel|dunkel' then 'Munich Dunkel'
    when h ~* '\yhelles\y' then 'Helles'
    when h ~* 'vienna' then 'Vienna Lager'
    when h ~* 'czech|bohemian' then 'Czech Premium Pale Lager'
    when h ~* 'german pils|pilsener|pilsner|\ypils\y' then 'German Pils'
    when h ~* 'light lager|\ylite\y' then 'American Light Lager'
    when h ~* 'american lager|adjunct' then 'American Lager'
    when h ~* '\ylager\y|pale lager|premium lager|euro' then 'International Pale Lager'
    when h ~* 'american pale|\yapa\y|pale ale' then 'American Pale Ale'
    when h ~* 'blond' then 'Blonde Ale'
    when h ~* 'rauch|smoke' then 'Rauchbier'
    when h ~* '\ypale\y' then 'American Pale Ale'
    else null
  end
  from (select lower(coalesce(p_style,'')||' '||coalesce(p_name,'')) h) x;
$function$;

-- style_ref is a STORED generated column, so it does not recompute when the
-- resolver body changes. Touch the misfiled rows (a no-op write to style) to
-- force the generated column to recompute with the corrected function.
update public.beer_catalog
set style = style
where lower(coalesce(style,'')||' '||coalesce(name,'')) ~ 'berliner'
  and style_ref is distinct from public.tapt_ref_style_name(style, name);