-- Jornadas de onboarding, fatia B (parte 2): a gestão vê, audita e corrige a jornada pelo front.
--
-- Regra do GP (20/11): toda automação dá às diretorias e à gestão visibilidade, auditoria e controle pela tela.
--
-- 1. get_onboarding_journey_admin: a jornada por membro e por etapa, com a FONTE do fechamento derivada da
--    evidência que existe, e não de um carimbo nos escritores (eles quase nunca gravaram a fonte):
--      gp            metadata.closed_by = 'gp' (admin_complete_onboarding_step), com quem, a nota e a data;
--      fato          a etapa de fato tem a evidência: termo assinado (certificado volunteer_agreement não
--                    revogado), VEP Active/Complete, presença em reunião, presença em reunião de tribo;
--      clique        etapa que o catálogo diz que fecha por clique;
--      sem_evidencia etapa de fato fechada sem a evidência: é o sinal de auditoria.
--    Portão: manage_member (diretorias e gestão). Leitura sem escrita.
-- 2. admin_reopen_onboarding_step: a correção do GP. Reabre uma etapa fechada, com nota obrigatória, e guarda
--    no metadata o que havia antes (reopen_history). Portão: manage_platform.
--
-- Não toca fila, portão, radar nem nudge da filiação.
-- Guard: tests/contracts/jornadas-fatia-b2-jornada-na-tela.test.mjs.

CREATE OR REPLACE FUNCTION public.get_onboarding_journey_admin(p_member_id uuid DEFAULT NULL)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_result jsonb;
BEGIN
  SELECT id INTO v_caller_id FROM members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL OR NOT public.can_by_member(v_caller_id, 'manage_member') THEN
    RAISE EXCEPTION 'Unauthorized: manage_member required' USING ERRCODE = 'insufficient_privilege';
  END IF;

  WITH mem AS (
    SELECT m.id, m.name, m.chapter, m.tribe_id, m.operational_role, m.member_status, m.email
    FROM members m
    WHERE (p_member_id IS NULL AND m.member_status = 'active'
           AND EXISTS (SELECT 1 FROM onboarding_progress op0 WHERE op0.member_id = m.id))
       OR m.id = p_member_id
  ),
  jr AS (
    SELECT mem.id AS member_id, s.id AS step_key, s.step_order, s.closed_by AS step_closed_by,
           op.status, op.completed_at, op.sla_deadline, op.metadata, op.application_id,
           CASE s.id
             WHEN 'volunteer_term' THEN (
               SELECT jsonb_build_object('kind', 'certificate', 'certificate_id', c.id,
                                         'verification_code', c.verification_code, 'at', c.issued_at)
               FROM certificates c
               WHERE c.member_id = mem.id AND c.type = 'volunteer_agreement' AND c.revoked_at IS NULL
               ORDER BY c.issued_at DESC NULLS LAST LIMIT 1)
             WHEN 'vep_acceptance' THEN (
               SELECT jsonb_build_object('kind', 'vep', 'application_id', sa.id,
                                         'vep_status', sa.vep_status_raw, 'at', sa.vep_last_seen_at)
               FROM selection_applications sa
               WHERE (sa.id = op.application_id OR lower(sa.email) = lower(mem.email))
                 AND sa.vep_status_raw IN ('Active', 'Complete')
               ORDER BY sa.vep_last_seen_at DESC NULLS LAST LIMIT 1)
             WHEN 'first_meeting' THEN (
               SELECT jsonb_build_object('kind', 'attendance', 'event_id', e.id, 'title', e.title, 'at', e.date)
               FROM attendance a JOIN events e ON e.id = a.event_id
               WHERE a.member_id = mem.id AND a.present
               ORDER BY e.date ASC NULLS LAST LIMIT 1)
             WHEN 'meet_tribe' THEN (
               -- a tribo atual; sem tribo hoje, qualquer tribo (quem saiu da tribo esteve nela).
               SELECT jsonb_build_object('kind', 'tribe_attendance', 'event_id', e.id, 'title', e.title,
                                         'at', e.date, 'tribe_id', i.legacy_tribe_id)
               FROM attendance a JOIN events e ON e.id = a.event_id JOIN initiatives i ON i.id = e.initiative_id
               WHERE a.member_id = mem.id AND a.present
                 AND i.legacy_tribe_id IS NOT NULL
                 AND (mem.tribe_id IS NULL OR i.legacy_tribe_id = mem.tribe_id)
               ORDER BY e.date ASC NULLS LAST LIMIT 1)
           END AS evidence
    FROM mem
    JOIN onboarding_steps s ON public.onboarding_step_applies(s.applies_to_role, mem.operational_role)
    LEFT JOIN onboarding_progress op ON op.member_id = mem.id AND op.step_key = s.id
  ),
  srcd AS (
    SELECT r.*,
           CASE
             WHEN r.status IS DISTINCT FROM 'completed' THEN NULL
             WHEN r.metadata->>'closed_by' = 'gp' THEN 'gp'
             WHEN r.step_closed_by = 'member' THEN 'clique'
             WHEN r.evidence IS NOT NULL THEN 'fato'
             ELSE 'sem_evidencia'
           END AS source
    FROM jr r
  )
  SELECT jsonb_build_object(
    'steps', (SELECT jsonb_agg(jsonb_build_object(
                'id', s.id, 'step_order', s.step_order, 'closed_by', s.closed_by, 'is_required', s.is_required,
                'label_pt', s.label_pt, 'label_en', s.label_en, 'label_es', s.label_es) ORDER BY s.step_order)
              FROM onboarding_steps s),
    'members', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
               'member_id', mem.id, 'name', mem.name, 'chapter', mem.chapter, 'tribe_id', mem.tribe_id,
               'operational_role', mem.operational_role, 'member_status', mem.member_status,
               'steps', (SELECT jsonb_agg(jsonb_build_object(
                           'step_key', x.step_key,
                           'status', COALESCE(x.status, 'not_seeded'),
                           'completed_at', x.completed_at,
                           'sla_deadline', x.sla_deadline,
                           'source', x.source,
                           'evidence', x.evidence,
                           'gp', CASE WHEN x.metadata->>'closed_by' = 'gp' THEN jsonb_build_object(
                                   'member_id', x.metadata->>'gp_member_id',
                                   'name', (SELECT g.name FROM members g WHERE g.id::text = x.metadata->>'gp_member_id'),
                                   'note', x.metadata->>'gp_note', 'at', x.metadata->>'gp_at') END,
                           'reopen_history', x.metadata->'reopen_history'
                         ) ORDER BY x.step_order)
                         FROM srcd x WHERE x.member_id = mem.id)
             ) ORDER BY mem.name)
      FROM mem), '[]'::jsonb)
  ) INTO v_result;

  RETURN v_result;
END;
$function$;

REVOKE ALL ON FUNCTION public.get_onboarding_journey_admin(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_onboarding_journey_admin(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_reopen_onboarding_step(p_member_id uuid, p_step_key text, p_note text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_row onboarding_progress%ROWTYPE;
  v_entry jsonb;
BEGIN
  SELECT id INTO v_caller_id FROM members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL OR NOT public.can_by_member(v_caller_id, 'manage_platform') THEN
    RAISE EXCEPTION 'Unauthorized: manage_platform required' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF p_note IS NULL OR length(btrim(p_note)) < 3 THEN
    RAISE EXCEPTION 'A written reason is required' USING ERRCODE = 'check_violation';
  END IF;

  SELECT * INTO v_row FROM onboarding_progress
  WHERE member_id = p_member_id AND step_key = p_step_key
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Step % not found for this member', p_step_key USING ERRCODE = 'no_data_found';
  END IF;
  IF v_row.status NOT IN ('completed', 'skipped') THEN
    RAISE EXCEPTION 'Step % is not closed (status %)', p_step_key, v_row.status USING ERRCODE = 'check_violation';
  END IF;

  -- o que havia antes fica no histórico; a marca do GP sai, para o próximo fechamento não herdar a fonte.
  v_entry := jsonb_build_object(
    'reopened_by', v_caller_id, 'reopen_note', btrim(p_note), 'reopened_at', now(),
    'previous_status', v_row.status, 'previous_completed_at', v_row.completed_at,
    'previous_closed_by', v_row.metadata->>'closed_by', 'previous_gp_note', v_row.metadata->>'gp_note');

  UPDATE onboarding_progress
  SET status = 'pending', completed_at = NULL, updated_at = now(),
      metadata = (COALESCE(metadata, '{}'::jsonb) - 'closed_by' - 'gp_member_id' - 'gp_note' - 'gp_at')
        || jsonb_build_object('reopen_history',
             COALESCE(metadata->'reopen_history', '[]'::jsonb) || jsonb_build_array(v_entry))
  WHERE id = v_row.id;

  RETURN jsonb_build_object('success', true, 'member_id', p_member_id, 'step_key', p_step_key);
END;
$function$;

REVOKE ALL ON FUNCTION public.admin_reopen_onboarding_step(uuid, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_reopen_onboarding_step(uuid, text, text) TO authenticated;

NOTIFY pgrst, 'reload schema';
