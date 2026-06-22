-- #785 PR-4 — Write surface for confidential-initiative visibility.
--
-- Threads the `visibility` column (added in PR-1, gated by RLS in PR-2 and by the
-- SECURITY DEFINER read RPCs in PR-3) into the two canonical initiative-write RPCs so a
-- coordinator/GP can mark an initiative confidential at creation or edit time.
--
-- Authority model (ratified in ADR-0105):
--   * create_initiative: visibility is set by whoever may create an initiative in the org.
--     Raising the wall on a brand-new initiative is harmless, so no new guard is added here.
--   * update_initiative: visibility edits ride the EXISTING manage_member-on-initiative guard
--     (coordinator-level) — the same gate that already protects title/status/metadata. GP
--     (manage_platform) inherits it via can(). Lowering confidential->standard exposes data, so
--     it is deliberately kept behind that coordinator/GP gate (and GP oversight is always present
--     per PM decision #1).
--
-- Signature change (param count) => DROP + CREATE (project rule), not CREATE OR REPLACE.
-- The #708 board_scope derivation in create_initiative is preserved verbatim (p708 contract test
-- DB-aware invariant depends on it). UI badge/toggle is a separate FE slice (#211/#212).

-- ── create_initiative: append p_visibility (default 'standard') ──────────────────────────────
DROP FUNCTION IF EXISTS public.create_initiative(text, text, text, jsonb, uuid);

CREATE OR REPLACE FUNCTION public.create_initiative(
  p_kind text,
  p_title text,
  p_description text DEFAULT NULL::text,
  p_metadata jsonb DEFAULT '{}'::jsonb,
  p_parent_initiative_id uuid DEFAULT NULL::uuid,
  p_visibility text DEFAULT 'standard'::text
)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_kind_row record;
  v_count integer;
  v_new_id uuid;
  v_legacy_tribe_id int;
  v_board_scope text;
  v_domain_key text;
BEGIN
  SELECT * INTO v_kind_row FROM public.initiative_kinds WHERE slug = p_kind;
  IF v_kind_row IS NULL THEN
    RAISE EXCEPTION 'Unknown initiative kind: %', p_kind USING ERRCODE = 'P0004';
  END IF;

  -- #785 PR-4: validate the visibility enum (the column CHECK enforces it too, but a clean
  -- ERRCODE is friendlier to callers than a constraint-violation).
  IF p_visibility IS NULL OR p_visibility NOT IN ('standard', 'confidential') THEN
    RAISE EXCEPTION 'Invalid visibility "%": must be standard or confidential', p_visibility
      USING ERRCODE = 'P0007';
  END IF;

  -- #708: research_tribe é tribe-scoped — precisa do bridge legacy_tribe_id (via
  -- admin_upsert_legacy_tribe). create_initiative nunca seta legacy_tribe_id, então
  -- criar uma tribo por aqui produziria uma tribo SEM legacy_tribe_id, cujo board
  -- nem 'tribe' (trigger exige legacy_tribe_id) nem 'global' (scope errado p/ tribo)
  -- é válido. Fail-loud em vez de criar uma tribo meia-quebrada.
  IF p_kind = 'research_tribe' THEN
    RAISE EXCEPTION 'research_tribe deve ser criada via o bridge de tribo (admin_upsert_legacy_tribe), não create_initiative'
      USING ERRCODE = 'P0006';
  END IF;

  IF v_kind_row.max_concurrent_per_org IS NOT NULL THEN
    SELECT count(*) INTO v_count
    FROM public.initiatives
    WHERE kind = p_kind
      AND organization_id = public.auth_org()
      AND status IN ('draft', 'active');

    IF v_count >= v_kind_row.max_concurrent_per_org THEN
      RAISE EXCEPTION 'Maximum concurrent initiatives of kind "%" reached (limit: %)',
        p_kind, v_kind_row.max_concurrent_per_org USING ERRCODE = 'P0005';
    END IF;
  END IF;

  INSERT INTO public.initiatives (kind, title, description, metadata, parent_initiative_id, organization_id, visibility)
  VALUES (p_kind, p_title, p_description, p_metadata, p_parent_initiative_id, public.auth_org(), p_visibility)
  RETURNING id INTO v_new_id;

  IF v_kind_row.has_board THEN
    -- #708: derivar board_scope da tribe-scoping real (um dual-write trigger pode ter
    -- setado legacy_tribe_id para kinds de tribo). Antes ficava no default 'tribe' e o
    -- trigger de taxonomy rejeitava todo board de kind não-tribo.
    SELECT legacy_tribe_id INTO v_legacy_tribe_id FROM public.initiatives WHERE id = v_new_id;
    IF v_legacy_tribe_id IS NOT NULL THEN
      v_board_scope := 'tribe';
      v_domain_key  := nullif(p_metadata->>'domain_key', '');
    ELSE
      v_board_scope := 'global';
      v_domain_key  := coalesce(nullif(p_metadata->>'domain_key', ''), 'cross_functional');
    END IF;

    INSERT INTO public.project_boards (board_name, initiative_id, source, is_active, organization_id, board_scope, domain_key)
    VALUES (p_title, v_new_id, 'manual', true, public.auth_org(), v_board_scope, v_domain_key);
  END IF;

  RETURN v_new_id;
END;
$function$;

REVOKE ALL ON FUNCTION public.create_initiative(text, text, text, jsonb, uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_initiative(text, text, text, jsonb, uuid, text) TO authenticated, service_role;

-- ── update_initiative: append p_visibility (default NULL = unchanged) ─────────────────────────
DROP FUNCTION IF EXISTS public.update_initiative(uuid, text, text, text, jsonb);

CREATE OR REPLACE FUNCTION public.update_initiative(
  p_initiative_id uuid,
  p_title text DEFAULT NULL::text,
  p_description text DEFAULT NULL::text,
  p_status text DEFAULT NULL::text,
  p_metadata jsonb DEFAULT NULL::jsonb,
  p_visibility text DEFAULT NULL::text
)
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

  -- #785 PR-4: visibility edits ride the same manage_member-on-initiative guard above
  -- (coordinator/GP). Validate the enum when provided; NULL = leave unchanged.
  IF p_visibility IS NOT NULL AND p_visibility NOT IN ('standard', 'confidential') THEN
    RAISE EXCEPTION 'Invalid visibility "%": must be standard or confidential', p_visibility
      USING ERRCODE = 'P0007';
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
    visibility = COALESCE(p_visibility, visibility),
    updated_at = now()
  WHERE id = p_initiative_id;

  RETURN jsonb_build_object('id', p_initiative_id, 'updated', true);
END;
$function$;

REVOKE ALL ON FUNCTION public.update_initiative(uuid, text, text, text, jsonb, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.update_initiative(uuid, text, text, text, jsonb, text) TO authenticated, service_role;

NOTIFY pgrst, 'reload schema';
