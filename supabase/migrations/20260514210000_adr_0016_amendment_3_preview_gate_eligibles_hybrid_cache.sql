-- ADR-0016 Amendment 3 — preview_gate_eligibles hybrid cache
-- Cache table + row-level triggers (members + engagements) + adapter RPC + 24h TTL fallback.

-- ============================================================================
-- 1. CACHE TABLE
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.preview_gate_eligibles_cache (
  member_id uuid NOT NULL REFERENCES public.members(id) ON DELETE CASCADE,
  doc_type text NOT NULL,
  eligible_gates text[] NOT NULL DEFAULT ARRAY[]::text[],
  last_refreshed timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (member_id, doc_type)
);

CREATE INDEX IF NOT EXISTS preview_gate_eligibles_cache_doc_idx
  ON public.preview_gate_eligibles_cache (doc_type, last_refreshed);

ALTER TABLE public.preview_gate_eligibles_cache ENABLE ROW LEVEL SECURITY;

COMMENT ON TABLE public.preview_gate_eligibles_cache IS
  'Cache for preview_gate_eligibles: per (member, doc_type) → list of gate_kinds member is eligible for. Excludes submitter_acceptance (per-call dependency). Refreshed via triggers on members + engagements; full rebuild via refresh_preview_gate_eligibles_cache_all(). 24h TTL fallback. Internal: no RLS policies → service-role-only.';

-- ============================================================================
-- 2. CACHEABLE DOC TYPES
-- ============================================================================

CREATE OR REPLACE FUNCTION public._cacheable_preview_doc_types()
RETURNS text[]
LANGUAGE sql
IMMUTABLE
SET search_path TO 'public', 'pg_temp'
AS $$
  SELECT ARRAY[
    'cooperation_agreement',
    'cooperation_addendum',
    'volunteer_term_template',
    'volunteer_addendum',
    'policy'
  ]::text[];
$$;

-- ============================================================================
-- 3. REFRESH FUNCTION FOR ONE MEMBER
-- ============================================================================

CREATE OR REPLACE FUNCTION public._refresh_preview_gate_eligibles_for_member(
  p_member_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_doc_type text;
  v_gates jsonb;
  v_gate jsonb;
  v_eligible text[];
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.members m
    WHERE m.id = p_member_id AND m.is_active = true
  ) THEN
    DELETE FROM public.preview_gate_eligibles_cache WHERE member_id = p_member_id;
    RETURN;
  END IF;

  FOREACH v_doc_type IN ARRAY public._cacheable_preview_doc_types()
  LOOP
    v_gates := public.resolve_default_gates(v_doc_type);
    IF v_gates IS NULL THEN CONTINUE; END IF;

    v_eligible := ARRAY[]::text[];
    FOR v_gate IN SELECT * FROM jsonb_array_elements(v_gates)
    LOOP
      IF (v_gate->>'kind') = 'submitter_acceptance' THEN
        CONTINUE;
      END IF;

      IF public._can_sign_gate(p_member_id, NULL, v_gate->>'kind', v_doc_type, NULL) THEN
        v_eligible := v_eligible || (v_gate->>'kind');
      END IF;
    END LOOP;

    INSERT INTO public.preview_gate_eligibles_cache (member_id, doc_type, eligible_gates, last_refreshed)
    VALUES (p_member_id, v_doc_type, v_eligible, now())
    ON CONFLICT (member_id, doc_type)
    DO UPDATE SET eligible_gates = EXCLUDED.eligible_gates, last_refreshed = EXCLUDED.last_refreshed;
  END LOOP;
END;
$$;

COMMENT ON FUNCTION public._refresh_preview_gate_eligibles_for_member(uuid) IS
  'Recompute preview_gate_eligibles_cache rows for one member across cacheable doc_types. Skips submitter_acceptance (per-call). Deletes rows for inactive/missing members.';

-- ============================================================================
-- 4. FULL REBUILD RPC (admin)
-- ============================================================================

CREATE OR REPLACE FUNCTION public.refresh_preview_gate_eligibles_cache_all()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_count_before int;
  v_count_after int;
  v_member_count int;
  v_member record;
  v_caller uuid;
  v_caller_member_id uuid;
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT m.id INTO v_caller_member_id
  FROM public.members m WHERE m.auth_id = v_caller AND m.is_active = true;

  IF v_caller_member_id IS NULL OR NOT public.can_by_member(v_caller_member_id, 'manage_platform') THEN
    RAISE EXCEPTION 'Not authorized: manage_platform required' USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT count(*) INTO v_count_before FROM public.preview_gate_eligibles_cache;

  v_member_count := 0;
  FOR v_member IN SELECT m.id FROM public.members m WHERE m.is_active = true
  LOOP
    PERFORM public._refresh_preview_gate_eligibles_for_member(v_member.id);
    v_member_count := v_member_count + 1;
  END LOOP;

  DELETE FROM public.preview_gate_eligibles_cache c
  WHERE NOT EXISTS (
    SELECT 1 FROM public.members m WHERE m.id = c.member_id AND m.is_active = true
  );

  SELECT count(*) INTO v_count_after FROM public.preview_gate_eligibles_cache;

  RETURN jsonb_build_object(
    'rebuilt_at', now(),
    'members_processed', v_member_count,
    'cache_rows_before', v_count_before,
    'cache_rows_after', v_count_after,
    'caller', v_caller_member_id
  );
END;
$$;

COMMENT ON FUNCTION public.refresh_preview_gate_eligibles_cache_all() IS
  'Full rebuild of preview_gate_eligibles_cache. V4 gated (manage_platform). Returns jsonb summary.';

-- ============================================================================
-- 5. TRIGGER ON members
-- ============================================================================

CREATE OR REPLACE FUNCTION public._trg_refresh_preview_gate_eligibles_on_member()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    PERFORM public._refresh_preview_gate_eligibles_for_member(NEW.id);
  ELSIF TG_OP = 'UPDATE' THEN
    IF NEW.is_active IS DISTINCT FROM OLD.is_active
       OR NEW.member_status IS DISTINCT FROM OLD.member_status
       OR NEW.operational_role IS DISTINCT FROM OLD.operational_role
       OR NEW.designations IS DISTINCT FROM OLD.designations
       OR NEW.chapter IS DISTINCT FROM OLD.chapter
       OR NEW.person_id IS DISTINCT FROM OLD.person_id
    THEN
      PERFORM public._refresh_preview_gate_eligibles_for_member(NEW.id);
    END IF;
  ELSIF TG_OP = 'DELETE' THEN
    DELETE FROM public.preview_gate_eligibles_cache WHERE member_id = OLD.id;
  END IF;
  RETURN COALESCE(NEW, OLD);
END;
$$;

DROP TRIGGER IF EXISTS trg_refresh_preview_gate_eligibles_on_member ON public.members;
CREATE TRIGGER trg_refresh_preview_gate_eligibles_on_member
  AFTER INSERT OR UPDATE OR DELETE ON public.members
  FOR EACH ROW
  EXECUTE FUNCTION public._trg_refresh_preview_gate_eligibles_on_member();

-- ============================================================================
-- 6. TRIGGER ON engagements
-- ============================================================================

CREATE OR REPLACE FUNCTION public._trg_refresh_preview_gate_eligibles_on_engagement()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_person_id uuid;
  v_member_id uuid;
BEGIN
  IF TG_OP = 'DELETE' THEN
    v_person_id := OLD.person_id;
  ELSE
    v_person_id := NEW.person_id;
  END IF;

  IF v_person_id IS NULL THEN RETURN COALESCE(NEW, OLD); END IF;

  FOR v_member_id IN
    SELECT m.id FROM public.members m WHERE m.person_id = v_person_id
  LOOP
    PERFORM public._refresh_preview_gate_eligibles_for_member(v_member_id);
  END LOOP;

  RETURN COALESCE(NEW, OLD);
END;
$$;

DROP TRIGGER IF EXISTS trg_refresh_preview_gate_eligibles_on_engagement ON public.engagements;
CREATE TRIGGER trg_refresh_preview_gate_eligibles_on_engagement
  AFTER INSERT OR UPDATE OR DELETE ON public.engagements
  FOR EACH ROW
  EXECUTE FUNCTION public._trg_refresh_preview_gate_eligibles_on_engagement();

-- ============================================================================
-- 7. ADAPTER RPC — reads cache + falls back to live
-- ============================================================================

CREATE OR REPLACE FUNCTION public.preview_gate_eligibles(p_doc_type text, p_submitter_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_gates jsonb;
  v_result jsonb := '[]'::jsonb;
  v_gate jsonb;
  v_gate_kind text;
  v_count int;
  v_sample jsonb;
  v_use_cache boolean;
  v_stale_cutoff timestamptz := now() - interval '24 hours';
BEGIN
  v_gates := public.resolve_default_gates(p_doc_type);
  IF v_gates IS NULL THEN RETURN NULL; END IF;

  v_use_cache := p_doc_type = ANY(public._cacheable_preview_doc_types())
    AND EXISTS (
      SELECT 1 FROM public.preview_gate_eligibles_cache c
      JOIN public.members m ON m.id = c.member_id
      WHERE c.doc_type = p_doc_type
        AND m.is_active = true
        AND c.last_refreshed >= v_stale_cutoff
    );

  FOR v_gate IN SELECT * FROM jsonb_array_elements(v_gates)
  LOOP
    v_gate_kind := v_gate->>'kind';

    IF v_gate_kind = 'submitter_acceptance' THEN
      SELECT count(*) INTO v_count
      FROM public.members m
      WHERE m.is_active = true
        AND public._can_sign_gate(m.id, NULL, v_gate_kind, p_doc_type, p_submitter_id);

      SELECT coalesce(jsonb_agg(name ORDER BY name), '[]'::jsonb) INTO v_sample
      FROM (
        SELECT m.name FROM public.members m
        WHERE m.is_active = true
          AND public._can_sign_gate(m.id, NULL, v_gate_kind, p_doc_type, p_submitter_id)
        ORDER BY m.name LIMIT 3
      ) m;

    ELSIF v_use_cache THEN
      SELECT count(*) INTO v_count
      FROM public.preview_gate_eligibles_cache c
      JOIN public.members m ON m.id = c.member_id
      WHERE c.doc_type = p_doc_type
        AND m.is_active = true
        AND c.last_refreshed >= v_stale_cutoff
        AND v_gate_kind = ANY(c.eligible_gates);

      SELECT coalesce(jsonb_agg(name ORDER BY name), '[]'::jsonb) INTO v_sample
      FROM (
        SELECT m.name
        FROM public.preview_gate_eligibles_cache c
        JOIN public.members m ON m.id = c.member_id
        WHERE c.doc_type = p_doc_type
          AND m.is_active = true
          AND c.last_refreshed >= v_stale_cutoff
          AND v_gate_kind = ANY(c.eligible_gates)
        ORDER BY m.name LIMIT 3
      ) m;

    ELSE
      SELECT count(*) INTO v_count
      FROM public.members m
      WHERE m.is_active = true
        AND public._can_sign_gate(m.id, NULL, v_gate_kind, p_doc_type, p_submitter_id);

      SELECT coalesce(jsonb_agg(name ORDER BY name), '[]'::jsonb) INTO v_sample
      FROM (
        SELECT m.name FROM public.members m
        WHERE m.is_active = true
          AND public._can_sign_gate(m.id, NULL, v_gate_kind, p_doc_type, p_submitter_id)
        ORDER BY m.name LIMIT 3
      ) m;
    END IF;

    v_result := v_result || jsonb_build_array(jsonb_build_object(
      'gate_kind', v_gate_kind,
      'gate_order', (v_gate->>'order')::int,
      'threshold', v_gate->'threshold',
      'count', v_count,
      'sample', v_sample,
      'source', CASE
        WHEN v_gate_kind = 'submitter_acceptance' THEN 'live'
        WHEN v_use_cache THEN 'cache'
        ELSE 'live_fallback'
      END
    ));
  END LOOP;

  RETURN v_result;
END;
$$;

COMMENT ON FUNCTION public.preview_gate_eligibles(text, uuid) IS
  'Hybrid cache + live fallback (ADR-0016 Amendment 3). Reads preview_gate_eligibles_cache when fresh; falls back to live _can_sign_gate when cache empty/stale (>24h). Always evaluates submitter_acceptance live. Each gate response includes "source": cache|live|live_fallback for diagnostics.';

-- ============================================================================
-- 8. INITIAL POPULATION
-- ============================================================================

DO $$
DECLARE
  v_member record;
  v_count int := 0;
BEGIN
  FOR v_member IN SELECT m.id FROM public.members m WHERE m.is_active = true
  LOOP
    PERFORM public._refresh_preview_gate_eligibles_for_member(v_member.id);
    v_count := v_count + 1;
  END LOOP;
  RAISE NOTICE 'Initial cache population: % members processed', v_count;
END $$;

NOTIFY pgrst, 'reload schema';
