-- Audit fix (stale materialized pick): weekly_pick writes one row per user per
-- week and then never looks at it again -- it only checks "does a row exist".
--
-- That means a pick computed by a buggy or pre-fix recommender stays in front of
-- the drinker for the rest of the week, and stays in their pick history forever.
-- Concretely: the No/Low fix (20260717140500) taught recommend_beer to respect a
-- "No/Low alcohol" taste preference, but anyone who already had a full-strength
-- beer materialized this week keeps being shown it. Someone who is not drinking
-- alcohol gets a barleywine recommended to them for six more days.
--
-- Two changes:
--   1. Re-validate the stored pick on every read and drop it if it no longer
--      holds. The existing insert-if-missing block then recomputes it with the
--      current recommender. Validation is deliberately narrow: only checks that
--      cannot be a matter of taste (the beer still exists; a No/Low drinker is
--      not handed alcohol). It is not a "recompute if the score changed" hook --
--      the whole point of the weekly pick is that it stays put.
--   2. Backfill: delete already-materialized picks that violate the No/Low
--      preference, current and past. These were wrong recommendations, not user
--      actions, and leaving them in the passport log keeps repeating the advice.
delete from public.user_beer_pick p
using public.beer_catalog b
where b.id = p.beer_id
  and not coalesce(b.is_na_low, false)
  and exists (
    select 1 from public.taste_vector t, unnest(t.top_styles) tv(s)
    where t.user_id = p.user_id
      and lower(coalesce(tv.s, '')) ~ 'no\s*/?\s*low|non.?alco|alcohol.?free'
  );

create or replace function public.weekly_pick(p_user uuid DEFAULT NULL::uuid)
 returns table(beer_id uuid, name text, brewery text, style text, country text, image_url text, abv numeric, reason text, match_kind text, week_start date)
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
#variable_conflict use_column
declare
  uid uuid := coalesce(auth.uid(), p_user);
  wk  date := date_trunc('week', now())::date;
begin
  if uid is null then return; end if;

  -- Self-heal: drop this week's pick if it is no longer servable.
  delete from public.user_beer_pick p
  where p.user_id = uid
    and p.week_start = wk
    and (
      -- the beer went away, which would render an empty pick all week
      not exists (select 1 from public.beer_catalog b where b.id = p.beer_id)
      -- or it is alcoholic and this drinker asked for No/Low
      or exists (
        select 1
        from public.beer_catalog b
        where b.id = p.beer_id
          and not coalesce(b.is_na_low, false)
          and exists (
            select 1 from public.taste_vector t, unnest(t.top_styles) tv(s)
            where t.user_id = uid
              and lower(coalesce(tv.s, '')) ~ 'no\s*/?\s*low|non.?alco|alcohol.?free'
          )
      )
    );

  if not exists (
    select 1 from public.user_beer_pick p where p.user_id = uid and p.week_start = wk
  ) then
    insert into public.user_beer_pick(user_id, week_start, beer_id, reason, match_kind)
    select uid, wk, r.beer_id, r.reason, r.match_kind
    from public.recommend_beer(uid) r
    limit 1
    on conflict (user_id, week_start) do nothing;
  end if;

  return query
    select b.id, coalesce(nullif(b.display_name, ''), b.name), br.name, b.style_ref,
           public.tapt_trusted_country(br.country, br.external_ids),
           coalesce(b.cutout_url, b.label_image_url), b.abv, p.reason, p.match_kind, p.week_start
    from public.user_beer_pick p
    join public.beer_catalog b on b.id = p.beer_id
    left join public.brewery br on br.id = b.brewery_id
    where p.user_id = uid and p.week_start = wk;
end;
$function$;
