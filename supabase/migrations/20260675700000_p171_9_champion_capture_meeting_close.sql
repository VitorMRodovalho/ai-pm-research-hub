-- p171 #9 — Champion capture no flow meeting_close (Track B)
--
-- Antes: meeting_close (MCP-only) só persistia summary + counters. Não havia
-- caminho pra leader "sugerir Champion pra X, Y" durante fechamento.
-- Conexão events → champions_awarded só via context_id retrospectivo.
-- champion_pending no digest é heurística (events sem champions_awarded),
-- não suggestion-driven.
--
-- Depois: events.suggested_champion_ids uuid[] persiste sugestões do líder
-- no momento do fechamento. UI grant modal em /admin/gamification (deep-link
-- via `?award_event_id=X`) carrega esse array e:
--   - 1 sugestão → prefill recipient_id automaticamente
--   - >1 sugestões → nudge panel "Sugeridos no fechamento"
--   - 0 sugestões → fallback ao showcaseNudge existente (ADR-0084)
--
-- meeting_close ganha p_suggested_champion_ids uuid[] opcional. Validation:
-- cada uuid deve ser member ativo da mesma org do caller; duplicates
-- removidos; max 10 ids (anti-flood).
--
-- Rollback:
--   ALTER TABLE events DROP COLUMN suggested_champion_ids;
--   (Restore previous meeting_close body.)

-- ─────────────────────────────────────────────────────────────────────────────
-- Part 1 — Add column to events
-- ─────────────────────────────────────────────────────────────────────────────
ALTER TABLE public.events
  ADD COLUMN IF NOT EXISTS suggested_champion_ids uuid[] DEFAULT NULL;

COMMENT ON COLUMN public.events.suggested_champion_ids IS
  'p171 #9 — uuid[] de members sugeridos para Champion durante meeting_close. UI /admin/gamification carrega para prefill/nudge. NULL = não sugerido; array vazio possível (explicitly cleared).';

-- ─────────────────────────────────────────────────────────────────────────────
-- Part 2 — Extend meeting_close to accept + persist suggestions
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.meeting_close(
  p_event_id uuid,
  p_summary text DEFAULT NULL,
  p_suggested_champion_ids uuid[] DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_caller_org uuid;
  v_event record;
  v_already_closed boolean;
  v_action_count int;
  v_decision_count int;
  v_unresolved_count int;
  v_markdown_action_count int;
  v_structured_drift int;
  v_links_total int;
  v_showcase_count int;
  v_validated_suggestions uuid[];
  v_invalid_suggestions uuid[];
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  SELECT id, organization_id INTO v_caller_id, v_caller_org
  FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Caller has no member record'; END IF;

  IF NOT public.can_by_member(v_caller_id, 'manage_event') THEN
    RAISE EXCEPTION 'Requires manage_event permission';
  END IF;

  SELECT id, title, date, minutes_text, minutes_posted_at
  INTO v_event FROM public.events WHERE id = p_event_id;
  IF v_event.id IS NULL THEN
    RETURN jsonb_build_object('error', 'event_not_found');
  END IF;

  v_already_closed := v_event.minutes_posted_at IS NOT NULL;

  -- p171 #9: validate suggested_champion_ids (same-org, active members, max 10, deduped)
  IF p_suggested_champion_ids IS NOT NULL AND cardinality(p_suggested_champion_ids) > 0 THEN
    IF cardinality(p_suggested_champion_ids) > 10 THEN
      RETURN jsonb_build_object('error', 'too_many_suggestions', 'detail', 'max 10 suggested member ids per meeting_close');
    END IF;

    -- Dedupe + validate each id is a member in caller's org
    SELECT array_agg(DISTINCT s ORDER BY s) INTO v_validated_suggestions
    FROM unnest(p_suggested_champion_ids) AS s
    WHERE EXISTS (
      SELECT 1 FROM public.members m
      WHERE m.id = s AND m.organization_id = v_caller_org
    );

    SELECT array_agg(DISTINCT s) INTO v_invalid_suggestions
    FROM unnest(p_suggested_champion_ids) AS s
    WHERE NOT EXISTS (
      SELECT 1 FROM public.members m
      WHERE m.id = s AND m.organization_id = v_caller_org
    );

    IF v_invalid_suggestions IS NOT NULL AND cardinality(v_invalid_suggestions) > 0 THEN
      RETURN jsonb_build_object(
        'error', 'invalid_suggestions',
        'detail', 'unknown or out-of-org member ids: ' || array_to_string(v_invalid_suggestions, ', ')
      );
    END IF;
  END IF;

  SELECT
    COUNT(*) FILTER (WHERE kind = 'action'),
    COUNT(*) FILTER (WHERE kind = 'decision'),
    COUNT(*) FILTER (WHERE kind IN ('action','followup') AND resolved_at IS NULL)
  INTO v_action_count, v_decision_count, v_unresolved_count
  FROM public.meeting_action_items WHERE event_id = p_event_id;

  v_markdown_action_count := COALESCE(
    (SELECT array_length(regexp_split_to_array(v_event.minutes_text, E'(^|\\n)\\s*-\\s*\\[\\s*\\]'), 1) - 1),
    0
  );
  v_markdown_action_count := GREATEST(0, v_markdown_action_count);
  v_structured_drift := GREATEST(0, v_markdown_action_count - v_action_count);

  SELECT COUNT(*) INTO v_links_total
  FROM public.board_item_event_links WHERE event_id = p_event_id;

  SELECT COUNT(*) INTO v_showcase_count
  FROM public.event_showcases WHERE event_id = p_event_id;

  IF NOT v_already_closed THEN
    UPDATE public.events
    SET minutes_posted_at = now(),
        minutes_posted_by = v_caller_id,
        notes = CASE
          WHEN p_summary IS NOT NULL AND length(trim(p_summary)) > 0
            THEN COALESCE(notes, '') ||
                 CASE WHEN COALESCE(notes, '') <> '' THEN E'\n\n' ELSE '' END ||
                 '## Meeting close summary (' || to_char(now(), 'YYYY-MM-DD HH24:MI') || ')' ||
                 E'\n' || trim(p_summary)
          ELSE notes
        END,
        suggested_champion_ids = COALESCE(v_validated_suggestions, suggested_champion_ids),
        updated_at = now()
    WHERE id = p_event_id;
  ELSE
    -- Already closed: allow updating suggestions only (idempotent close)
    IF v_validated_suggestions IS NOT NULL THEN
      UPDATE public.events
      SET suggested_champion_ids = v_validated_suggestions,
          updated_at = now()
      WHERE id = p_event_id;
    END IF;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'event_id', p_event_id,
    'event_title', v_event.title,
    'already_closed', v_already_closed,
    'closed_at', CASE WHEN v_already_closed THEN v_event.minutes_posted_at ELSE now() END,
    'action_count', v_action_count,
    'decision_count', v_decision_count,
    'unresolved_actions', v_unresolved_count,
    'markdown_action_count', v_markdown_action_count,
    'structured_drift', v_structured_drift,
    'links_total', v_links_total,
    'showcase_count', v_showcase_count,
    'drift_signal', v_structured_drift > 0,
    'summary_appended', p_summary IS NOT NULL AND length(trim(p_summary)) > 0 AND NOT v_already_closed,
    'suggestions_count', COALESCE(cardinality(v_validated_suggestions), 0),
    'suggestions_stored', v_validated_suggestions
  );
END;
$function$;

COMMENT ON FUNCTION public.meeting_close(uuid, text, uuid[]) IS
  'p171 #9 — Extended with p_suggested_champion_ids uuid[] (Track B). Atomic meeting close + champion suggestion persistence. UI /admin/gamification deep-link reads events.suggested_champion_ids para prefill/nudge. Idempotent (allows updating suggestions on already-closed events). Validates same-org + max 10.';

-- ─────────────────────────────────────────────────────────────────────────────
-- Part 3 — RPC para UI consumir as sugestões (deep-link helper)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.get_event_champion_suggestions(
  p_event_id uuid
)
RETURNS TABLE(
  member_id uuid,
  member_name text,
  designation_summary text
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_caller_id uuid;
  v_caller_org uuid;
  v_event_org uuid;
  v_suggestions uuid[];
BEGIN
  SELECT id, organization_id INTO v_caller_id, v_caller_org
  FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: member not found';
  END IF;

  IF NOT public.can_by_member(v_caller_id, 'manage_event')
     AND NOT public.can_by_member(v_caller_id, 'award_champion') THEN
    RAISE EXCEPTION 'Unauthorized: requires manage_event or award_champion';
  END IF;

  SELECT e.suggested_champion_ids, e.organization_id INTO v_suggestions, v_event_org
  FROM public.events e WHERE e.id = p_event_id;

  IF v_event_org IS NULL THEN
    RAISE EXCEPTION 'event_not_found';
  END IF;
  IF v_event_org != v_caller_org THEN
    RAISE EXCEPTION 'event_not_in_caller_org';
  END IF;

  IF v_suggestions IS NULL OR cardinality(v_suggestions) = 0 THEN
    RETURN; -- empty result
  END IF;

  RETURN QUERY
  SELECT
    m.id AS member_id,
    m.name AS member_name,
    CASE WHEN cardinality(m.designations) > 0
      THEN array_to_string(m.designations, ', ')
      ELSE COALESCE(m.operational_role, '—')
    END AS designation_summary
  FROM public.members m
  WHERE m.id = ANY(v_suggestions)
    AND m.organization_id = v_caller_org
  ORDER BY m.name;
END;
$function$;

COMMENT ON FUNCTION public.get_event_champion_suggestions(uuid) IS
  'p171 #9 — Returns members suggested for Champion no meeting_close. UI /admin/gamification carrega para prefill/nudge. Auth: manage_event OR award_champion. Org-scoped via auth_org.';

GRANT EXECUTE ON FUNCTION public.get_event_champion_suggestions(uuid) TO authenticated;

NOTIFY pgrst, 'reload schema';
