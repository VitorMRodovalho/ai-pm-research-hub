-- ============================================================================
-- ADR-0015 Phase 1 — webinars reader cutover (first C3 table)
--
-- Scope: refactor 2 reader RPCs to use `initiatives` (V4 primitive) instead
-- of `tribes` (V3 bridge) for display/filter joins. Output shape preserved
-- identically (frontend contract).
--
-- Per ADR-0015 Phase 1: webinars chosen first — smallest C3 (6 rows), 6/6
-- dual-write integrity confirmed, isolated (no cascade readers).
--
-- Changed RPCs:
--   1. list_webinars_v2 — JOIN initiatives, derive tribe_name from i.name,
--      filter by i.legacy_tribe_id (or w.tribe_id still as fallback during
--      transition period).
--   2. webinars_pending_comms — JOIN initiatives for tribe_name display.
--
-- NOT changed (dual-write handles sync until Phase 2/3):
--   - upsert_webinar — still writes webinars.tribe_id (triggers sync init_id)
--   - link_webinar_event — still reads v_webinar.tribe_id and writes to
--     events.tribe_id (events is separate C3 — its own cutover later)
--
-- Invariantes preservadas (ADR-0015):
--   - tribes table permanent (15 FKs)
--   - webinars.tribe_id column still exists (not dropped in Phase 1)
--   - dual-write triggers active (Phase 2 drops them)
--   - Output shape of list_webinars_v2 + webinars_pending_comms IDENTICAL
--
-- ADR: ADR-0015 (tribes bridge consolidation), ADR-0005 (initiative primitive)
-- Rollback: restore prior function bodies (see rollback block at bottom).
-- ============================================================================

BEGIN;

-- ═══════════════════════════════════════════════════════════════════════════
-- 1. list_webinars_v2 — JOIN initiatives instead of tribes
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.list_webinars_v2(
  p_status text DEFAULT NULL,
  p_chapter text DEFAULT NULL,
  p_tribe_id integer DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public', 'pg_temp'
AS $$
DECLARE
  v_result jsonb;
BEGIN
  SELECT COALESCE(jsonb_agg(row_to_json(r) ORDER BY r.scheduled_at DESC), '[]'::jsonb)
  INTO v_result
  FROM (
    SELECT
      w.id, w.title, w.description, w.scheduled_at, w.duration_min,
      w.status, w.chapter_code, w.tribe_id, w.organizer_id,
      w.co_manager_ids, w.meeting_link, w.youtube_url, w.notes,
      w.event_id, w.board_item_id,
      w.created_at, w.updated_at,
      m.name AS organizer_name,
      i.title AS tribe_name,  -- ADR-0015 Phase 1: derive from initiative
      e.date AS event_date,
      e.type AS event_type,
      (SELECT COUNT(*) FROM attendance a WHERE a.event_id = w.event_id AND a.present = true) AS attendee_count,
      (SELECT COALESCE(jsonb_agg(jsonb_build_object('id', cm.id, 'name', cm.name)), '[]'::jsonb)
       FROM members cm WHERE cm.id = ANY(w.co_manager_ids)) AS co_managers,
      bi.title AS board_item_title,
      bi.status AS board_item_status
    FROM webinars w
    LEFT JOIN members m ON m.id = w.organizer_id
    LEFT JOIN initiatives i ON i.id = w.initiative_id  -- ADR-0015 Phase 1
    LEFT JOIN events e ON e.id = w.event_id
    LEFT JOIN board_items bi ON bi.id = w.board_item_id
    WHERE (p_status IS NULL OR w.status = p_status)
      AND (p_chapter IS NULL OR w.chapter_code = p_chapter)
      AND (p_tribe_id IS NULL OR i.legacy_tribe_id = p_tribe_id)  -- ADR-0015 Phase 1
  ) r;

  RETURN v_result;
END;
$$;

-- ═══════════════════════════════════════════════════════════════════════════
-- 2. webinars_pending_comms — JOIN initiatives
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.webinars_pending_comms()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public', 'pg_temp'
AS $$
DECLARE
  v_result jsonb;
BEGIN
  SELECT COALESCE(jsonb_agg(row_to_json(r) ORDER BY r.scheduled_at), '[]'::jsonb)
  INTO v_result
  FROM (
    SELECT
      w.id, w.title, w.scheduled_at, w.status, w.chapter_code,
      w.meeting_link, w.youtube_url, w.tribe_id,
      i.title AS tribe_name,  -- ADR-0015 Phase 1: derive from initiative
      m.name AS organizer_name,
      CASE
        WHEN w.status = 'confirmed' AND w.scheduled_at > now() THEN 'invite'
        WHEN w.status = 'confirmed' AND w.scheduled_at <= now() THEN 'followup'
        WHEN w.status = 'completed' AND w.youtube_url IS NULL THEN 'awaiting_replay'
        WHEN w.status = 'completed' AND w.youtube_url IS NOT NULL THEN 'replay_ready'
        ELSE 'info'
      END AS comms_action,
      CASE
        WHEN w.status = 'confirmed' AND w.scheduled_at > now() THEN 'Preparar convite e lembretes'
        WHEN w.status = 'confirmed' AND w.scheduled_at <= now() THEN 'Preparar follow-up pós-evento'
        WHEN w.status = 'completed' AND w.youtube_url IS NULL THEN 'Aguardando replay para divulgar'
        WHEN w.status = 'completed' AND w.youtube_url IS NOT NULL THEN 'Divulgar replay e materiais'
        ELSE 'Acompanhar'
      END AS comms_label
    FROM webinars w
    LEFT JOIN initiatives i ON i.id = w.initiative_id  -- ADR-0015 Phase 1
    LEFT JOIN members m ON m.id = w.organizer_id
    WHERE w.status IN ('confirmed', 'completed')
    ORDER BY w.scheduled_at
  ) r;

  RETURN v_result;
END;
$$;

NOTIFY pgrst, 'reload schema';

COMMIT;

-- ═══════════════════════════════════════════════════════════════════════════
-- ROLLBACK: restore previous bodies (JOIN tribes instead of initiatives)
-- ═══════════════════════════════════════════════════════════════════════════
/*
-- list_webinars_v2 before:
-- LEFT JOIN tribes t ON t.id = w.tribe_id
-- t.name AS tribe_name
-- AND (p_tribe_id IS NULL OR w.tribe_id = p_tribe_id)

-- webinars_pending_comms before:
-- LEFT JOIN tribes t ON t.id = w.tribe_id
-- t.name AS tribe_name
*/
