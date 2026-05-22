-- ============================================================
-- p220 drift capture — update_initiative live body
-- ============================================================
-- WHY: rpc-migration-coverage Phase C body-hash drift gate flagged
-- update_initiative as drifted on PR #278 (docs-only close session).
-- live_len=1629 vs migration capture (20260686000000) mig_len=977.
-- The live body has added V4 authorization guard (can() check via
-- persons.auth_id resolution) + lifecycle_states validation that the
-- earlier capture didn't have. Source likely a session that ran
-- CREATE OR REPLACE via execute_sql / dashboard SQL editor without
-- writing a migration file (anti-pattern documented in p59 drift audit
-- — see Track Q-C ratification 2026-04-25).
--
-- This file captures the verbatim live body so the drift gate stops
-- flagging. No semantic change. Idempotent (CREATE OR REPLACE).
--
-- ROLLBACK: re-apply prior body (mig_len=977) without the auth guard +
-- lifecycle validation. NOT RECOMMENDED — strips V4 authority gate.
-- ============================================================

CREATE OR REPLACE FUNCTION public.update_initiative(p_initiative_id uuid, p_title text DEFAULT NULL::text, p_description text DEFAULT NULL::text, p_status text DEFAULT NULL::text, p_metadata jsonb DEFAULT NULL::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_person_id uuid;
  v_initiative record;
  v_kind_row record;
BEGIN
  -- Authorization guard (mirrors activate_initiative / manage_initiative_engagement).
  -- SECURITY DEFINER bypasses RLS, so this check is mandatory before any write.
  SELECT p.id INTO v_caller_person_id
  FROM public.persons p
  WHERE p.auth_id = auth.uid();

  IF v_caller_person_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = '42501';
  END IF;

  IF NOT can(v_caller_person_id, 'manage_member', 'initiative', p_initiative_id) THEN
    RAISE EXCEPTION 'Unauthorized: requires manage_member capability on this initiative'
      USING ERRCODE = '42501';
  END IF;

  -- Original logic, unchanged.
  SELECT * INTO v_initiative FROM public.initiatives WHERE id = p_initiative_id;
  IF v_initiative IS NULL THEN
    RAISE EXCEPTION 'Initiative not found: %', p_initiative_id USING ERRCODE = 'P0002';
  END IF;

  IF p_status IS NOT NULL THEN
    SELECT * INTO v_kind_row FROM public.initiative_kinds WHERE slug = v_initiative.kind;
    IF NOT (p_status = ANY(v_kind_row.lifecycle_states)) THEN
      RAISE EXCEPTION 'Invalid status "%" for kind "%". Allowed: %',
        p_status, v_initiative.kind, v_kind_row.lifecycle_states USING ERRCODE = 'P0006';
    END IF;
  END IF;

  UPDATE public.initiatives SET
    title = COALESCE(p_title, title),
    description = COALESCE(p_description, description),
    status = COALESCE(p_status, status),
    metadata = COALESCE(p_metadata, metadata),
    updated_at = now()
  WHERE id = p_initiative_id;

  RETURN jsonb_build_object('id', p_initiative_id, 'updated', true);
END;
$function$;
