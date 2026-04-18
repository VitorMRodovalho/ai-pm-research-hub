-- ============================================================================
-- ADR-0015 Phase 3a — DROP COLUMN tribe_id em 3 tabelas C3 menores
--
-- Primeira leva do column drop irreversível. Seleção pelas tabelas com:
--   - 0 reader RPCs que filtram por <table>.tribe_id
--   - 0 views dependentes
--   - 0 RLS policies que referenciam tribe_id
--   - 0 indexes sobre tribe_id
--   - writers já V4 + dual-write (Commits 1-2 ADR-0015 + Step 1 V4 sweep)
--
-- Target tables + motivação:
--   1. announcements           — 1 row, 0 reader RPCs; AnnouncementBanner.astro
--                                 não usa tribe_id; 0 writer RPC.
--   2. ia_pilots               — 1 row; get_public_impact_data usa members.tribe_id
--                                 (coincidência semântica, não ia_pilots.tribe_id);
--                                 0 writer RPC.
--   3. pilots                  — 1 row; writers create_pilot + update_pilot
--                                 modificados aqui para remover tribe_id do
--                                 INSERT/UPDATE. get_pilots_summary já usa
--                                 initiative_id via JOIN.
--
-- Out of scope (próximas levas):
--   - webinars, broadcast_log, meeting_artifacts, publication_submissions,
--     public_publications, hub_resources, project_boards, events,
--     tribe_deliverables — auditoria de reader dependencies mais ampla necessária
--   - members (Phase 5 deferred pós-CBGPL)
--
-- Writer refactor in same migration (pre-requisite for pilots DROP COLUMN):
--   - create_pilot: remove tribe_id do INSERT column list
--   - update_pilot: remove tribe_id = COALESCE(...) do UPDATE SET
--   - p_tribe_id param preservado na signature (frontend compat) — deriva
--     initiative_id internamente; tribe_id column não existe mais para escrever
--
-- DROP COLUMN is CASCADE on FK `<table>_tribe_id_fkey → tribes(id)`:
--   Postgres drops FK automaticamente. RESTRICT is the default safe mode.
--
-- Rollback: irreversível no caminho limpo. Exigiria:
--   ALTER TABLE <t> ADD COLUMN tribe_id int;
--   + FK recreation + data backfill via legacy_tribe_id lookup.
-- Recomendado validar em staging 24-48h antes de deploy prod (ou manter eye
-- on production logs pós-push).
--
-- ADR: ADR-0015 Phase 3 (part a)
-- ============================================================================

BEGIN;

-- ═══════════════════════════════════════════════════════════════════════════
-- 1. create_pilot — remove tribe_id do INSERT
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.create_pilot(
  p_title text,
  p_hypothesis text DEFAULT NULL::text,
  p_problem_statement text DEFAULT NULL::text,
  p_scope text DEFAULT NULL::text,
  p_status text DEFAULT 'draft'::text,
  p_tribe_id integer DEFAULT NULL::integer,
  p_board_id uuid DEFAULT NULL::uuid,
  p_success_metrics jsonb DEFAULT '[]'::jsonb,
  p_team_member_ids uuid[] DEFAULT '{}'::uuid[]
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_caller_id uuid;
  v_next_number integer;
  v_new_id uuid;
  v_initiative_id uuid;
BEGIN
  SELECT id INTO v_caller_id FROM public.members
  WHERE auth_id = auth.uid() LIMIT 1;
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: not authenticated';
  END IF;

  IF NOT public.can_by_member(v_caller_id, 'manage_member') THEN
    RAISE EXCEPTION 'Unauthorized: requires manage_member permission';
  END IF;

  SELECT COALESCE(MAX(pilot_number), 0) + 1 INTO v_next_number FROM public.pilots;

  -- p_tribe_id kept for frontend compatibility; resolved to initiative_id.
  IF p_tribe_id IS NOT NULL THEN
    SELECT id INTO v_initiative_id FROM public.initiatives
    WHERE legacy_tribe_id = p_tribe_id LIMIT 1;
  END IF;

  INSERT INTO public.pilots (
    pilot_number, title, hypothesis, problem_statement, scope, status,
    initiative_id,
    board_id, success_metrics, team_member_ids, created_by, started_at
  )
  VALUES (
    v_next_number, p_title, p_hypothesis, p_problem_statement, p_scope, p_status,
    v_initiative_id,
    p_board_id, p_success_metrics, p_team_member_ids, v_caller_id,
    CASE WHEN p_status = 'active' THEN CURRENT_DATE ELSE NULL END
  )
  RETURNING id INTO v_new_id;

  RETURN jsonb_build_object('success', true, 'id', v_new_id, 'pilot_number', v_next_number);
END;
$$;

-- ═══════════════════════════════════════════════════════════════════════════
-- 2. update_pilot — remove tribe_id do UPDATE SET
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.update_pilot(
  p_id uuid,
  p_title text DEFAULT NULL::text,
  p_hypothesis text DEFAULT NULL::text,
  p_problem_statement text DEFAULT NULL::text,
  p_scope text DEFAULT NULL::text,
  p_status text DEFAULT NULL::text,
  p_tribe_id integer DEFAULT NULL::integer,
  p_board_id uuid DEFAULT NULL::uuid,
  p_success_metrics jsonb DEFAULT NULL::jsonb,
  p_team_member_ids uuid[] DEFAULT NULL::uuid[],
  p_lessons_learned jsonb DEFAULT NULL::jsonb,
  p_started_at date DEFAULT NULL::date,
  p_completed_at date DEFAULT NULL::date
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_caller_id uuid;
  v_initiative_id uuid;
BEGIN
  SELECT id INTO v_caller_id FROM public.members
  WHERE auth_id = auth.uid() LIMIT 1;
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: not authenticated';
  END IF;

  IF NOT public.can_by_member(v_caller_id, 'manage_member') THEN
    RAISE EXCEPTION 'Unauthorized: requires manage_member permission';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.pilots WHERE id = p_id) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Pilot not found');
  END IF;

  IF p_tribe_id IS NOT NULL THEN
    SELECT id INTO v_initiative_id FROM public.initiatives
    WHERE legacy_tribe_id = p_tribe_id LIMIT 1;
  END IF;

  UPDATE public.pilots SET
    title = COALESCE(p_title, title),
    hypothesis = COALESCE(p_hypothesis, hypothesis),
    problem_statement = COALESCE(p_problem_statement, problem_statement),
    scope = COALESCE(p_scope, scope),
    status = COALESCE(p_status, status),
    initiative_id = CASE WHEN p_tribe_id IS NOT NULL THEN v_initiative_id ELSE initiative_id END,
    board_id = COALESCE(p_board_id, board_id),
    success_metrics = COALESCE(p_success_metrics, success_metrics),
    team_member_ids = COALESCE(p_team_member_ids, team_member_ids),
    lessons_learned = COALESCE(p_lessons_learned, lessons_learned),
    started_at = CASE
      WHEN p_started_at IS NOT NULL THEN p_started_at
      WHEN COALESCE(p_status, status) = 'active' AND started_at IS NULL THEN CURRENT_DATE
      ELSE started_at
    END,
    completed_at = CASE
      WHEN p_completed_at IS NOT NULL THEN p_completed_at
      WHEN COALESCE(p_status, status) IN ('completed', 'cancelled') AND completed_at IS NULL THEN CURRENT_DATE
      ELSE completed_at
    END,
    updated_at = now()
  WHERE id = p_id;

  RETURN jsonb_build_object('success', true);
END;
$$;

-- ═══════════════════════════════════════════════════════════════════════════
-- 3. DROP COLUMN tribe_id — announcements, ia_pilots, pilots
-- FK constraints são automaticamente dropadas (CASCADE implicit).
-- ═══════════════════════════════════════════════════════════════════════════

ALTER TABLE public.announcements DROP COLUMN tribe_id;
ALTER TABLE public.ia_pilots DROP COLUMN tribe_id;
ALTER TABLE public.pilots DROP COLUMN tribe_id;

COMMIT;

NOTIFY pgrst, 'reload schema';
