-- #1832: get_application_interviews passa a devolver o NOME do entrevistador
--
-- A tela de histórico de entrevistas em /admin/selection mostrava tag de tempo, data/hora,
-- status e ações, e não mostrava com QUEM. A RPC já devolvia `interviewer_ids`; o que faltava
-- era o nome (aqui) e o desenho (na UI).
--
-- Medido em 17/08/2026: 129 entrevistas, 26 sem entrevistador registrado (20%), 29 com mais de
-- um, 132 pares sobre 3 entrevistadores distintos. A ausência está concentrada no caminho do
-- webhook de calendário (24 de 55, 44%), cuja raiz é a lista literal de e-mails do Apps Script
-- descrita na #1614. Este PR torna a ausência VISÍVEL; não a corrige.
--
-- Corpo extraído de 20260805000458_1383_w4_selection_gate_hardening.sql, provado idêntico ao
-- corpo vivo por md5 normalizado (cd7e63336e91d6952ae15ba93a5b1a9d) antes da edição.
-- Substituição contada: 1 ocorrência, diffada. CREATE OR REPLACE preserva as ACLs existentes
-- (postgres, authenticated, service_role; sem anon, sem PUBLIC).

CREATE OR REPLACE FUNCTION public.get_application_interviews(p_application_id uuid)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_cycle_id uuid;
  v_is_committee boolean;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: member not found';
  END IF;

  SELECT cycle_id INTO v_cycle_id FROM public.selection_applications WHERE id = p_application_id;
  IF v_cycle_id IS NULL THEN
    RAISE EXCEPTION 'Application not found';
  END IF;

  -- #1383 W4 (taxonomy §2.4): widen from GP-only to committee, per this tool's own
  -- docstring ("Used by committee to coordinate"). A committee member of THIS
  -- application's cycle may read its interviews; platform admins keep global access.
  SELECT EXISTS (
    SELECT 1 FROM public.selection_committee
    WHERE cycle_id = v_cycle_id AND member_id = v_caller_id
  ) INTO v_is_committee;

  IF NOT v_is_committee AND NOT public.can_by_member(v_caller_id, 'manage_platform') THEN
    RAISE EXCEPTION 'Unauthorized: requires committee membership or manage_platform permission';
  END IF;

  -- ADR-0109 PR-2 COI recusal: an active candidate in this application's cycle is recused
  -- from selection surfaces even if seated on the committee.
  IF public.selection_coi_recused(v_caller_id, v_cycle_id) THEN
    RAISE EXCEPTION 'recused_conflict_of_interest';
  END IF;

  RETURN (
    SELECT coalesce(json_agg(json_build_object(
      'id', si.id, 'scheduled_at', si.scheduled_at, 'duration_minutes', si.duration_minutes,
      'status', si.status, 'conducted_at', si.conducted_at, 'theme_of_interest', si.theme_of_interest,
      'notes', si.notes, 'interviewer_ids', si.interviewer_ids,
      -- #1832: o nome do entrevistador, resolvido NO SERVIDOR. A tela do histórico mostrava dia
      -- e hora e não COM QUEM, e a RPC já devolvia os ids: faltava o nome e faltava desenhar.
      -- Resolver no cliente, a partir do comitê ATUAL, quebraria calado no dia em que alguém
      -- saísse do comitê. Hoje 0 dos 132 pares está fora, mas isso vale por acidente do dado e
      -- não por estrutura, que é a classe que já custou caro nesta base.
      -- LEFT JOIN de propósito: um id sem membro correspondente mantém a posição com nome nulo,
      -- para a contagem nunca divergir de interviewer_ids e a UI poder ser honesta sobre o que
      -- não resolveu, em vez de encurtar a lista em silêncio.
      'interviewers', (
        SELECT coalesce(
                 json_agg(json_build_object('id', u.iid, 'name', m.name) ORDER BY u.ord),
                 '[]'::json)
        FROM unnest(si.interviewer_ids) WITH ORDINALITY AS u(iid, ord)
        LEFT JOIN public.members m ON m.id = u.iid
      )
    ) ORDER BY si.created_at DESC), '[]'::json)
    FROM selection_interviews si
    WHERE si.application_id = p_application_id
  );
END;
$function$;