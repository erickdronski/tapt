-- Extend the release profile filter with common cross-script confusables used
-- to evade an otherwise ASCII-normalized UGC denylist.

create or replace function public.profile_text_is_allowed(p_value text)
returns boolean
language plpgsql
stable
set search_path = pg_catalog, extensions
as $$
declare
  v_value text;
  v_tokens text;
  v_compact text;
  v_squashed text;
  v_terms constant text :=
    '(fuck|fucker|fucking|shit|bullshit|bitch|cunt|nigger|nigga|faggot|retard|kike|spic|chink|whore|slut|rape|rapist|nazi|hitler|porn|xxx)';
begin
  v_value := extensions.unaccent(lower(coalesce(p_value, '')));
  v_value := translate(v_value, '013457@$', 'oieastas');
  v_value := translate(
    v_value,
    U&'\0430\0435\043E\0440\0441\0445\0443\0456\043A\043C\0442\0432\03B1\03B5\03BF\03C1\03C7\03C5\03B9\03BA\03BC\03C4\03B2\0455\04CF\0458\0501\03C3\03C2\03BB',
    'aeopcxyikmtbaeopxyikmtbsljdssl'
  );
  v_tokens := regexp_replace(v_value, '[^a-z0-9]+', ' ', 'g');
  v_compact := regexp_replace(v_value, '[^a-z0-9]+', '', 'g');
  v_squashed := regexp_replace(v_compact, '(.)\1+', '\1', 'g');
  return v_tokens !~ ('\m' || v_terms || '\M')
    and v_compact !~ v_terms
    and v_squashed !~ v_terms;
end;
$$;

revoke all on function public.profile_text_is_allowed(text) from public, anon, authenticated;

notify pgrst, 'reload schema';
