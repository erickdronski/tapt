-- 0048: clean beer names (hide junk/number-only), style-science resolver
-- (maps messy catalog styles -> real BJCP reference), multi-signal decayed market.
-- Everything real/cited; junk is HIDDEN, never invented.

create or replace function public.tapt_name_ok(nm text) returns boolean
language sql immutable as $$
  select coalesce(nm,'') ~ '[[:alpha:]]{3,}'
     and btrim(coalesce(nm,'')) !~* '^(bi[eè]res?|biers?|beers?|cervezas?|cervejas?|birra|piwo|[oø]l|olut|alus|ipa|apa|ale|lager|stout|pils(ner)?|alt|cerveza)\.?$'
     and coalesce(nm,'') not ilike '%unknown%';
$$;

create or replace function public.tapt_display_name(nm text) returns text
language sql immutable as $$
  with s as (
    select case
      when btrim(coalesce(nm,'')) ~ '^[0-9]{4,}\s+[[:alpha:]]'
        then btrim(regexp_replace(btrim(nm), '^[0-9]{4,}[\s.-]+', ''))
      else btrim(coalesce(nm,''))
    end t
  )
  select case when t ~ '[a-z]' and t !~ '[A-Z]' and t ~ '^[[:ascii:]]+$'
              then initcap(t) else t end
  from s;
$$;

create or replace function public.tapt_ref_style_name(p_style text, p_name text) returns text
language sql immutable as $$
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
    when h ~* 'hefe|weiss?bier|weizen|weiße|weisse' then 'Weissbier'
    when h ~* 'witbier|\ywit\y|blanche|white ale' then 'Witbier'
    when h ~* 'american wheat|wheat ale|\ywheat\y' then 'American Wheat'
    when h ~* 'berliner' then 'Berliner Weisse'
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
$$;

create or replace function public.beer_style_science(p_beer uuid)
returns table(style_family text, style_name text, description text,
              abv_min numeric, abv_max numeric, ibu_min smallint, ibu_max smallint,
              srm_min smallint, srm_max smallint, source_url text)
language sql stable security definer set search_path to 'public' as $$
  select r.style_family, r.style_name, r.description,
         r.abv_min, r.abv_max, r.ibu_min, r.ibu_max, r.color_min_srm, r.color_max_srm, r.source_url
  from beer_catalog b
  join beer_style_reference r on r.style_name = public.tapt_ref_style_name(b.style, b.name)
  where b.id = p_beer
  limit 1;
$$;
grant execute on function public.beer_style_science(uuid) to anon, authenticated;

create or replace view public.beer_catalog_listable as
select b.id, b.sku_canonical_id, b.brewery_id,
       public.tapt_display_name(b.name) as name,
       b.style, b.substyle, b.abv, b.ibu, b.srm, b.is_na_low, b.gtin,
       b.label_image_url, b.label_image_license, b.external_ids,
       b.created_at, b.updated_at, b.cutout_url
from public.beer_catalog b
where public.tapt_name_ok(b.name);
grant select on public.beer_catalog_listable to anon, authenticated;

drop function if exists public.beer_market(text, integer, boolean);
create function public.beer_market(p_sort text DEFAULT 'movers', p_limit integer DEFAULT 40, p_demo boolean DEFAULT true)
returns table(beer_id uuid, symbol text, name text, brewery text, style text, country text,
              image_url text, net integer, votes integer, change integer, volume integer,
              ups integer, downs integer, spark double precision[], reason text,
              season_fit integer, heat integer)
language sql stable security definer set search_path to 'public' as $$
  with season as (
    select case when extract(month from now()) in (6,7,8) then 'summer'
                when extract(month from now()) in (9,10,11) then 'fall'
                when extract(month from now()) in (12,1,2) then 'winter'
                else 'spring' end as s
  ),
  votes as (
    select v.beer_id, v.value::int value from demo.demo_vote v where p_demo
    union all select bv.beer_id, bv.value::int from public.beer_vote bv where not p_demo),
  agg as (select beer_id, sum(value)::int net, count(*)::int votes,
      count(*) filter (where value>0)::int ups, count(*) filter (where value<0)::int downs
    from votes group by beer_id),
  ev as (
    select v.beer_id, v.value::numeric w, v.created_at ts from demo.demo_vote v where p_demo
    union all select bv.beer_id, bv.value::numeric, bv.created_at from public.beer_vote bv where not p_demo
    union all select ce.beer_id, greatest(least(coalesce(ce.rating,3)-3,2),-2)::numeric,
                     coalesce(ce.event_ts, ce.created_at) from public.checkin_event ce where not p_demo
    union all select bn.beer_id, 0.5::numeric, coalesce(bn.updated_at, now()) from public.beer_note bn where not p_demo
  ),
  mom as (
    select beer_id,
      sum(w * exp(-greatest(extract(epoch from now()-ts),0)/(86400*3.0)))::numeric momentum,
      count(*) filter (where ts > now()-interval '24 hours')::int volume
    from ev group by beer_id),
  spark as (
    select a.beer_id, array(
      select coalesce((select sum(e2.w) from ev e2 where e2.beer_id=a.beer_id
                       and e2.ts >= now()-make_interval(days=>d+1) and e2.ts < now()-make_interval(days=>d)),0)::float8
      from generate_series(6,0,-1) d) spark
    from agg a),
  ranked as (
    select distinct on (public.tapt_display_name(b.name))
      a.beer_id, a.net, a.votes, a.ups, a.downs,
      round(coalesce(m.momentum,0))::int change, coalesce(m.volume,0) volume,
      coalesce(m.momentum,0) mraw,
      public.tapt_display_name(b.name) bname, br.name brewery,
      coalesce(nullif(b.style,''),'Beer') style, br.country, coalesce(b.cutout_url,b.label_image_url) img,
      case
        when coalesce(b.style,'')||' '||b.name ~* 'non[- ]?alco|alcohol[- ]?free|0[.,]0\s*%' then 'Sober-curious pick'
        when (select s from season)='summer' and b.style ~* 'ipa|pale|wheat|wit|hefe|weiss|weizen|pils|lager|blonde|sour|gose|radler|shandy|session|helles|k(ö|o)lsch' then 'Summer crusher'
        when (select s from season)='winter' and b.style ~* 'stout|porter|barley\s?wine|bock|strong|winter|imperial|quad|dubbel|dark|schwarz' then 'Cold-weather climber'
        when (select s from season)='fall'   and b.style ~* 'm(ä|a)rzen|oktoberfest|amber|brown|pumpkin|porter|dunkel' then 'Autumn pour'
        when (select s from season)='spring' and b.style ~* 'saison|pale|bock|blonde|farmhouse' then 'Spring seasonal'
        else null end as reason
    from agg a
    join beer_catalog b on b.id=a.beer_id
    left join brewery br on br.id=b.brewery_id
    left join mom m on m.beer_id=a.beer_id
    where public.tapt_name_ok(b.name)
    order by public.tapt_display_name(b.name), a.votes desc)
  select r.beer_id,
    upper(left(regexp_replace(r.bname,'[^A-Za-z0-9]','','g'),4)) symbol,
    r.bname, r.brewery, r.style, r.country, r.img,
    r.net, r.votes, r.change, r.volume, r.ups, r.downs, s.spark, r.reason,
    (case when r.reason is null then 0 else 2 end) season_fit,
    least(100, round(abs(r.mraw)/nullif(max(abs(r.mraw)) over(),0)*100))::int heat
  from ranked r join spark s on s.beer_id=r.beer_id
  order by case p_sort
      when 'gainers' then r.change
      when 'losers'  then -r.change
      when 'active'  then r.volume
      when 'top'     then r.net
      when 'season'  then (case when r.reason is null then 0 else 2 end)*100 + r.net
      else abs(r.change) end desc, r.net desc, r.bname
  limit least(greatest(coalesce(p_limit,40),1),100);
$$;
grant execute on function public.beer_market(text, integer, boolean) to anon, authenticated;

-- one-time: give the demo lane life (isolated demo schema only)
update demo.demo_vote set created_at = now() - (power(random(), 1.7) * interval '12 days');
