-- 0031_dispatch_content_generator.sql
--
-- The Tapt Dispatch weekly newsletter content generator. Assembles a real issue
-- from live data ONLY: a featured beer (real product + label image), a style
-- science section (real BJCP/beerjson style reference), and real catalog stats.
-- Deterministic per ISO week so an issue is stable within the week but rotates
-- weekly. The featured beer is framed honestly as the week's pick, never as a
-- Beer-of-the-Week vote winner (that gets wired once real voting exists).
--
-- Consumed by the `dispatch-weekly` edge function, which renders the branded HTML
-- and (mode=send, gated by CRON_SECRET) mails it to subscribed addresses via the
-- Resend integration. Scheduled weekly by the `dispatch-weekly-send` pg_cron job.
-- See supabase/functions/dispatch-weekly/README.md for the owner setup.

create or replace function public.build_dispatch_content()
returns jsonb
language sql stable security definer set search_path to 'public'
as $$
  with wk as (
    select (extract(isoyear from now())::int * 100 + extract(week from now())::int)::text as w
  ),
  featured as (
    select bc.id, bc.name, bc.style, bc.abv, bc.label_image_url as image,
           br.name as brewery, br.country
    from beer_catalog bc
    join brewery br on br.id = bc.brewery_id
    cross join wk
    where bc.label_image_url is not null and bc.label_image_url <> ''
      and bc.abv is not null and bc.style is not null and bc.style <> ''
      and bc.name ~ '^[A-Za-z]' and length(bc.name) between 4 and 34
    order by md5(bc.id::text || wk.w)
    limit 1
  ),
  style as (
    select style_name, style_family, description, abv_min, abv_max, ibu_min, ibu_max, source_url
    from beer_style_reference, wk
    where description is not null and description <> ''
    order by md5(id::text || wk.w)
    limit 1
  )
  select jsonb_build_object(
    'week', (select w from wk),
    'featured', (select row_to_json(f) from featured f),
    'style', (select row_to_json(s) from style s),
    'stats', jsonb_build_object(
      'beers',    (select count(*) from beer_catalog),
      'breweries',(select count(*) from brewery),
      'venues',   (select count(*) from venue),
      'styles',   (select count(*) from beer_style_reference),
      'countries',(select count(distinct country) from brewery where country is not null)
    )
  );
$$;

grant execute on function public.build_dispatch_content() to authenticated, service_role;
