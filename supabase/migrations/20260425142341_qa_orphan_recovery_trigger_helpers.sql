-- Track Q-A Batch A — orphan recovery: trigger / utility helpers (5 fns)
--
-- Captures live bodies as-of 2026-04-25 for 5 orphan functions previously
-- defined out-of-band (no migration capture). No behavior change — bodies are
-- byte-equivalent to live `pg_get_functiondef` output. Resolves Q-A baseline
-- entries: title_case, trg_set_updated_at, set_knowledge_updated_at,
-- set_knowledge_insights_updated_at, set_progress.
--
-- Drift hardening (search_path='') is Phase B work; here we preserve the live
-- search_path setting verbatim to keep this migration purely capture-only.
--
-- Rollback: DROP FUNCTION public.<name>(<args>); the trigger-attached helpers
-- (set_knowledge_*, trg_set_updated_at) are referenced by triggers, so a
-- rollback would require dropping those triggers first. set_progress is an
-- internal seed helper for course_progress (no public call sites).

CREATE OR REPLACE FUNCTION public.title_case(input text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
  SELECT string_agg(
    upper(left(word, 1)) || lower(substring(word from 2)),
    ' '
  ) FROM unnest(string_to_array(lower(input), ' ')) AS word
  WHERE word != '';
$function$;

CREATE OR REPLACE FUNCTION public.trg_set_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.set_knowledge_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
begin
  new.updated_at = now();
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION public.set_knowledge_insights_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
begin
  new.updated_at = now();
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION public.set_progress(p_email text, p_code text, p_status text)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
DECLARE
  _mid UUID;
  _cid INTEGER;
BEGIN
  SELECT id INTO _mid FROM members WHERE email = p_email;
  SELECT id INTO _cid FROM courses WHERE code = p_code;
  IF _mid IS NOT NULL AND _cid IS NOT NULL THEN
    INSERT INTO course_progress (member_id, course_id, status, completed_at)
    VALUES (_mid, _cid, p_status, CASE WHEN p_status = 'completed' THEN now() ELSE NULL END)
    ON CONFLICT (member_id, course_id) DO UPDATE SET status = p_status, updated_at = now(),
      completed_at = CASE WHEN p_status = 'completed' THEN now() ELSE NULL END;
  END IF;
END;
$function$;
