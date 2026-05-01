-- Security advisor auto-remediation captured locally (applied via dashboard).
-- Pins search_path on the V4 updated_at trigger helper.
CREATE OR REPLACE FUNCTION public.set_updated_at_v4()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $function$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$function$;
