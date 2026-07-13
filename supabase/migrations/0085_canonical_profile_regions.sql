-- 0085_canonical_profile_regions.sql
-- Keep profile vote regions in the same full-name vocabulary used by the app,
-- venue rows, and beer-trend shelves. One trigger covers every current and
-- future profile write path.

create or replace function public.tapt_region_name(region_value text)
returns text
language sql
immutable
strict
set search_path = pg_catalog
as $$
  select coalesce(
    (
      select region_name
      from (values
        ('AL', 'Alabama'), ('AK', 'Alaska'), ('AZ', 'Arizona'),
        ('AR', 'Arkansas'), ('CA', 'California'), ('CO', 'Colorado'),
        ('CT', 'Connecticut'), ('DE', 'Delaware'), ('DC', 'District of Columbia'),
        ('FL', 'Florida'), ('GA', 'Georgia'), ('HI', 'Hawaii'),
        ('ID', 'Idaho'), ('IL', 'Illinois'), ('IN', 'Indiana'),
        ('IA', 'Iowa'), ('KS', 'Kansas'), ('KY', 'Kentucky'),
        ('LA', 'Louisiana'), ('ME', 'Maine'), ('MD', 'Maryland'),
        ('MA', 'Massachusetts'), ('MI', 'Michigan'), ('MN', 'Minnesota'),
        ('MS', 'Mississippi'), ('MO', 'Missouri'), ('MT', 'Montana'),
        ('NE', 'Nebraska'), ('NV', 'Nevada'), ('NH', 'New Hampshire'),
        ('NJ', 'New Jersey'), ('NM', 'New Mexico'), ('NY', 'New York'),
        ('NC', 'North Carolina'), ('ND', 'North Dakota'), ('OH', 'Ohio'),
        ('OK', 'Oklahoma'), ('OR', 'Oregon'), ('PA', 'Pennsylvania'),
        ('RI', 'Rhode Island'), ('SC', 'South Carolina'), ('SD', 'South Dakota'),
        ('TN', 'Tennessee'), ('TX', 'Texas'), ('UT', 'Utah'),
        ('VT', 'Vermont'), ('VA', 'Virginia'), ('WA', 'Washington'),
        ('WV', 'West Virginia'), ('WI', 'Wisconsin'), ('WY', 'Wyoming')
      ) as us_region(region_code, region_name)
      where us_region.region_code = upper(btrim(region_value))
         or lower(us_region.region_name) = lower(btrim(region_value))
      limit 1
    ),
    btrim(region_value)
  );
$$;

create or replace function public.t_normalize_profile_region()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  new.region_code := public.tapt_region_name(new.region_code);
  return new;
end;
$$;

drop trigger if exists t_user_profile_region_name on public.user_profile;
create trigger t_user_profile_region_name
before insert or update of region_code on public.user_profile
for each row execute function public.t_normalize_profile_region();

revoke all on function public.tapt_region_name(text)
  from public, anon, authenticated;
revoke all on function public.t_normalize_profile_region()
  from public, anon, authenticated;

update public.user_profile
set region_code = public.tapt_region_name(region_code),
    updated_at = now()
where region_code is not null
  and public.tapt_region_name(region_code) is distinct from region_code;

select public.refresh_beer_trend();

do $$
begin
  if public.tapt_region_name('CA') <> 'California'
     or public.tapt_region_name('new jersey') <> 'New Jersey'
     or public.tapt_region_name('DC') <> 'District of Columbia' then
    raise exception 'profile region canonicalization failed';
  end if;

  if exists (
    select 1
    from public.user_profile up
    where up.region_code is not null
      and public.tapt_region_name(up.region_code) is distinct from up.region_code
  ) then
    raise exception 'noncanonical profile regions remain';
  end if;
end $$;

notify pgrst, 'reload schema';
