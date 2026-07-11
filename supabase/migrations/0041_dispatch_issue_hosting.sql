-- 0041_dispatch_issue_hosting.sql
--
-- Hosting mechanism for The Tapt Dispatch: every weekly issue persists as a row so
-- it can be browsed in a public archive and re-rendered at a stable URL. Content is
-- structured jsonb (beer_of_week / fun_fact / story / trends) so the page styles it
-- consistently. Only 'published' issues are public (RLS). No back-catalog is seeded:
-- the archive is honestly empty until the first real issue ships.

create table if not exists public.dispatch_issue (
  id            uuid primary key default gen_random_uuid(),
  issue_number  int  not null unique,
  slug          text not null unique,
  title         text not null,
  subtitle      text,
  status        text not null default 'draft' check (status in ('draft','published')),
  content       jsonb not null default '{}'::jsonb,
  published_at  timestamptz,
  created_at    timestamptz not null default now()
);
alter table public.dispatch_issue enable row level security;

drop policy if exists dispatch_issue_public_read on public.dispatch_issue;
create policy dispatch_issue_public_read on public.dispatch_issue
  for select using (status = 'published');

create or replace function public.dispatch_archive(p_limit int default 24)
returns table(issue_number int, slug text, title text, subtitle text, published_at timestamptz)
language sql stable security definer set search_path to 'public' as $$
  select issue_number, slug, title, subtitle, published_at
  from dispatch_issue
  where status = 'published'
  order by issue_number desc
  limit least(greatest(coalesce(p_limit, 24), 1), 100);
$$;
grant execute on function public.dispatch_archive(int) to anon, authenticated;

create or replace function public.dispatch_issue_by_slug(p_slug text)
returns jsonb language sql stable security definer set search_path to 'public' as $$
  select to_jsonb(di) - 'status'
  from dispatch_issue di
  where di.slug = p_slug and di.status = 'published'
  limit 1;
$$;
grant execute on function public.dispatch_issue_by_slug(text) to anon, authenticated;
