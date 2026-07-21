-- The original one-argument function and the newer country-batched function
-- both matched a PostgREST call with only p_release, returning HTTP 300 after
-- the entire Overture release had already been staged. Keep the batchable
-- signature as the sole apply path.
drop function public.apply_overture_place_import(text);
