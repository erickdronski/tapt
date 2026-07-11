-- 0045_beer_market_seasonality.sql
-- Make the market feel smart: a short "why it's moving" reason tied to season.
-- Standing + movement stay pure community votes (honest); season is a real signal
-- (today's date + the beer's style). A beer earns a reason only when its style truly
-- fits the current season. Adds an "In season" sort that lightly weights seasonal fit.
drop function if exists public.beer_market(text, int, boolean);
create or replace function public.beer_market(p_sort text default 'movers', p_limit int default 40, p_demo boolean default true)
returns table(beer_id uuid, symbol text, name text, brewery text, style text, country text, image_url text,
              net int, votes int, change int, volume int, ups int, downs int, spark float8[], reason text, season_fit int)
language sql stable security definer set search_path to 'public' as $$
  with season as (select case when extract(month from now()) in (6,7,8) then 'summer'
                              when extract(month from now()) in (9,10,11) then 'fall'
                              when extract(month from now()) in (12,1,2) then 'winter'
                              else 'spring' end s),
  votes as (select v.beer_id, v.value, v.created_at from demo.demo_vote v where p_demo
            union all select bv.beer_id, bv.value::smallint, bv.created_at from public.beer_vote bv where not p_demo),
  agg as (select beer_id, sum(value)::int net, count(*)::int votes,
      count(*) filter (where value>0)::int ups, count(*) filter (where value<0)::int downs,
      count(*) filter (where created_at>now()-interval '24 hours')::int volume,
      (sum(value)-coalesce(sum(value) filter (where created_at<=now()-interval '24 hours'),0))::int change
    from votes group by beer_id),
  spark as (select a.beer_id, array(select coalesce((select sum(v2.value) from votes v2 where v2.beer_id=a.beer_id and v2.created_at<=now()-make_interval(days=>d)),0)::float8 from generate_series(6,0,-1) d) spark from agg a),
  ranked as (select distinct on (b.name) a.*, b.id bid, b.name bname, br.name brewery,
      coalesce(nullif(b.style,''),'Beer') style, br.country, b.label_image_url img,
      case
        when coalesce(b.style,'')||' '||b.name ~* 'non[- ]?alco|alcohol[- ]?free|sans alco|0[.,]0\s*%' then 'Sober-curious pick'
        when (select s from season)='summer' and b.style ~* 'ipa|pale|wheat|wit|hefe|weiss|weizen|pils|lager|blonde|sour|gose|radler|shandy|session|helles|k(ö|o)lsch' then 'Summer crusher'
        when (select s from season)='winter' and b.style ~* 'stout|porter|barley\s?wine|bock|strong|winter|imperial|quad|dubbel|dark|schwarz' then 'Cold-weather climber'
        when (select s from season)='fall'   and b.style ~* 'm(ä|a)rzen|oktoberfest|amber|brown|pumpkin|porter|dunkel' then 'Autumn pour'
        when (select s from season)='spring' and b.style ~* 'saison|pale|bock|blonde|farmhouse' then 'Spring seasonal'
        else null end reason
    from agg a join beer_catalog b on b.id=a.beer_id left join brewery br on br.id=b.brewery_id order by b.name, a.votes desc)
  select r.bid, upper(left(regexp_replace(r.bname,'[^A-Za-z0-9]','','g'),4)), r.bname, r.brewery, r.style, r.country, r.img,
    r.net, r.votes, r.change, r.volume, r.ups, r.downs, s.spark, r.reason, (case when r.reason is null then 0 else 2 end)
  from ranked r join spark s on s.beer_id=r.beer_id
  order by case p_sort when 'gainers' then r.change when 'losers' then -r.change when 'active' then r.volume
      when 'top' then r.net when 'season' then (case when r.reason is null then 0 else 2 end)*100 + r.net
      else abs(r.change) end desc, r.net desc, r.bname
  limit least(greatest(coalesce(p_limit,40),1),100);
$$;
grant execute on function public.beer_market(text, int, boolean) to anon, authenticated;
