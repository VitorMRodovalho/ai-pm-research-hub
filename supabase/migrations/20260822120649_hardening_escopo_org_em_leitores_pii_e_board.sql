-- Hardening de escopo de autoridade em leitores de PII de admin e na escrita de
-- board (decisao do PM 2026-08-22).
--
-- Esta migration e ADITIVA no nivel do gate: public.can() fica INTOCADA. Ela
-- introduz um helper que pergunta a mesma coisa aceitando apenas combo de
-- escopo organization/global, e passa a usa-lo nos chamadores que precisam de
-- autoridade independente de recurso. Onde o chamador ja tem o recurso em maos,
-- ele passa a ser repassado ao gate em vez de omitido.
--
-- Funcoes tocadas:
--   can_org / can_org_by_member          (novas, aditivas)
--   admin_get_member_details             (leitor de PII)
--   admin_list_members_with_pii          (leitor de PII)
--   admin_list_member_consents           (leitor de PII)
--   board_write_authority                (escrita de board)
--
-- Verificado apos aplicar: nenhum papel legitimo perdeu acesso -- sponsors,
-- pontos focais, GP e co-GP ficaram inalterados, e lideres de tribo seguem
-- lendo os contatos da propria tribo.
--
-- O contexto de seguranca, a exposicao medida antes/depois e o trabalho ainda
-- em aberto estao registrados em advisory PRIVADO do repositorio. Este arquivo
-- nao o referencia por identificador: o repositorio e PUBLICO e a correcao de
-- raiz ainda nao foi entregue.
-- ─────────────────────────────────────────────────────────────────────────────
-- B1. Helper: a MESMA pergunta de can(), mas so aceitando combo de escopo
-- organization/global. Serve a quem precisa de autoridade que nao depende de
-- recurso -- e que, por isso, nunca deve ser satisfeita por um combo escopado.
-- Aditivo: can() fica intocada.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.can_org(p_person_id uuid, p_action text)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT EXISTS (
    SELECT 1
    FROM public.auth_engagements ae
    JOIN public.engagement_kind_permissions ekp
      ON ekp.kind = ae.kind AND ekp.role = ae.role AND ekp.action = p_action
    WHERE ae.person_id = p_person_id
      AND (
        ae.is_authoritative = true
        -- mesmo carve-out p195 de can(): comentario em governanca nao exige termo
        OR (p_action = 'participate_in_governance_review' AND ae.status = 'active')
      )
      AND ekp.scope IN ('organization', 'global')
  );
$function$;

CREATE OR REPLACE FUNCTION public.can_org_by_member(p_member_id uuid, p_action text)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT public.can_org(
    (SELECT id FROM public.persons WHERE legacy_member_id = p_member_id),
    p_action
  );
$function$;

-- CREATE FUNCTION nasce com EXECUTE para PUBLIC (logo, anon). Estes helpers sao
-- SECDEF e so precisam ser chamados de dentro de outras SECDEF e por sessao
-- autenticada.
REVOKE EXECUTE ON FUNCTION public.can_org(uuid, text) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.can_org_by_member(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.can_org(uuid, text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.can_org_by_member(uuid, text) TO authenticated, service_role;

-- ─────────────────────────────────────────────────────────────────────────────
-- B2. Os tres leitores de PII de admin passam a exigir view_pii de escopo
-- ORGANIZATION. Nenhum deles recebe recurso, e nenhum deveria ser satisfeito por
-- um view_pii de tribo. O resto do corpo fica identico ao anterior.
-- (Aplicado no banco por um DO block sobre a definicao viva, para nao transcrever
-- os corpos a mao; o CREATE literal abaixo e a captura para o gate de drift, e a
-- igualdade com o vivo esta provada por hash -- ver o commit.)
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.admin_get_member_details(p_member_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_caller_id uuid;
  v_result jsonb;
  v_scope text;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
  IF NOT public.can_org_by_member(v_caller_id, 'view_pii') THEN
    RAISE EXCEPTION 'Access denied: requires view_pii permission (LGPD-sensitive data)';
  END IF;

  -- FU-2 Slice A: chapter-scope — non-GP/non-sede callers may not read out-of-chapter member details.
  v_scope := public.caller_chapter_scope();
  IF v_scope IS NOT NULL
     AND p_member_id <> v_caller_id
     AND (SELECT chapter FROM public.members WHERE id = p_member_id) IS DISTINCT FROM v_scope THEN
    RAISE EXCEPTION 'Access denied: cross-chapter member details';
  END IF;

  PERFORM public.log_pii_access(
    p_member_id,
    ARRAY['name','email','phone','photo_url','role','designations','is_active','cycles']::text[],
    'admin_get_member_details',
    NULL
  );

  SELECT jsonb_build_object(
    'id', m.id,
    'name', m.name,
    'email', m.email,
    'phone', m.phone,
    'photo_url', m.photo_url,
    'tribe_id', m.tribe_id,
    'operational_role', m.operational_role,
    'designations', m.designations,
    'is_superadmin', m.is_superadmin,
    'is_active', m.is_active,
    'cycle_active', m.current_cycle_active,
    'cycles', m.cycles,
    'created_at', m.created_at
  ) INTO v_result
  FROM public.members m
  WHERE m.id = p_member_id;

  RETURN v_result;
END;
$function$;

CREATE OR REPLACE FUNCTION public.admin_list_members_with_pii(p_tribe_id integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_caller_id uuid;
  v_result jsonb;
  v_accessed_ids uuid[];
  v_scope text;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
  IF NOT public.can_org_by_member(v_caller_id, 'view_pii') THEN
    RAISE EXCEPTION 'Access denied: requires view_pii permission (LGPD-sensitive data)';
  END IF;

  -- FU-2 Slice A: chapter-scope — non-GP/non-sede callers see only their own chapter's members.
  v_scope := public.caller_chapter_scope();

  SELECT array_agg(m.id) INTO v_accessed_ids
  FROM public.members m
  WHERE (p_tribe_id IS NULL OR m.tribe_id = p_tribe_id)
    AND (v_scope IS NULL OR m.chapter = v_scope)
    AND m.id <> v_caller_id;

  PERFORM public.log_pii_access_batch(
    v_accessed_ids,
    ARRAY['name','email','phone','role','designations']::text[],
    'admin_list_members_with_pii',
    CASE WHEN p_tribe_id IS NOT NULL THEN 'filtered by tribe ' || p_tribe_id ELSE 'all members' END
  );

  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'id', m.id,
    'name', m.name,
    'email', m.email,
    'phone', m.phone,
    'tribe_id', m.tribe_id,
    'operational_role', m.operational_role,
    'designations', m.designations,
    'is_active', m.is_active,
    'cycle_active', m.current_cycle_active
  ) ORDER BY m.name), '[]'::jsonb) INTO v_result
  FROM public.members m
  WHERE (p_tribe_id IS NULL OR m.tribe_id = p_tribe_id)
    AND (v_scope IS NULL OR m.chapter = v_scope);

  RETURN v_result;
END;
$function$;

CREATE OR REPLACE FUNCTION public.admin_list_member_consents(p_member_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_caller_org_id uuid;
  v_target_org_id uuid;
  v_scope text;
  v_result jsonb;
BEGIN
  SELECT m.id, m.organization_id INTO v_caller_id, v_caller_org_id
  FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  IF NOT public.can_org_by_member(v_caller_id, 'view_pii') THEN
    RAISE EXCEPTION 'Access denied: requires view_pii permission (LGPD-sensitive data)';
  END IF;

  -- Multi-tenant fence (CRITICAL): SECDEF bypasses the RESTRICTIVE org-scope RLS policy, and
  -- can_by_member('view_pii') is satisfied by the caller holding view_pii in ANY engagement —
  -- it does NOT bound the TARGET. Re-enforce org isolation here.
  SELECT m.organization_id INTO v_target_org_id FROM public.members m WHERE m.id = p_member_id;
  IF v_target_org_id IS NULL OR v_caller_org_id IS NULL OR v_target_org_id <> v_caller_org_id THEN
    RAISE EXCEPTION 'Access denied: target member not in caller organization';
  END IF;

  -- FU-2 Slice C: chapter-scope — a non-GP/non-sede caller may not read another chapter's consent
  -- history (the org fence above is a no-op while all chapters share one organization). Self always allowed.
  v_scope := public.caller_chapter_scope();
  IF v_scope IS NOT NULL AND p_member_id <> v_caller_id
     AND (SELECT chapter FROM public.members WHERE id = p_member_id) IS DISTINCT FROM v_scope THEN
    RAISE EXCEPTION 'Access denied: cross-chapter member consents';
  END IF;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', cr.id,
    'member_id', cr.member_id,
    'application_id', cr.application_id,
    'policy_type', cr.policy_type,
    'policy_version', cr.policy_version,
    'policy_document_id', cr.policy_document_id,
    'accepted_at', cr.accepted_at,
    'channel', cr.channel,
    -- capture-evidence hashes (pseudonymized) — relevant to a consent audit; view_pii-gated + logged.
    'email_hash', cr.email_hash,
    'ip_hash', cr.ip_hash,
    'user_agent_hash', cr.user_agent_hash,
    'revoked_at', cr.revoked_at,
    'revocation_reason', cr.revocation_reason,
    'is_active', (cr.revoked_at IS NULL),
    'created_at', cr.created_at
  ) ORDER BY cr.accepted_at DESC), '[]'::jsonb)
  INTO v_result
  FROM public.consent_records cr
  WHERE cr.member_id = p_member_id
    AND cr.organization_id = v_caller_org_id;

  -- Accountability (Art. 37): log EVERY admin read of consent history, incl. self-reads via this path.
  INSERT INTO public.pii_access_log (accessor_id, target_member_id, fields_accessed, context, reason, accessed_at)
  VALUES (v_caller_id, p_member_id, ARRAY['consent_history']::text[], 'admin_list_member_consents', 'consent audit', now());

  RETURN v_result;
END;
$function$;

-- ─────────────────────────────────────────────────────────────────────────────
-- A. board_write_authority: a funcao JA recebe p_board_id e ja resolveu
-- v_board.initiative_id. O ultimo ramo perguntava sem passar nada, o que fazia
-- qualquer write_board escopado valer para QUALQUER board. Agora o ramo se parte
-- em dois: autoridade de organizacao (vale para todo board, que e o desenho dos
-- seeds) e autoridade escopada A ESTA iniciativa.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.board_write_authority(p_member_id uuid, p_board_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_actor record;
  v_board record;
  v_board_legacy_tribe_id int;
BEGIN
  SELECT * INTO v_actor FROM public.members WHERE id = p_member_id;
  IF NOT FOUND THEN RETURN false; END IF;
  SELECT * INTO v_board FROM public.project_boards WHERE id = p_board_id;
  IF NOT FOUND THEN RETURN false; END IF;
  SELECT legacy_tribe_id INTO v_board_legacy_tribe_id
  FROM public.initiatives WHERE id = v_board.initiative_id;

  RETURN (
    -- GP
    coalesce(v_actor.is_superadmin, false)
    OR v_actor.operational_role IN ('manager', 'deputy_manager')
    OR coalesce('co_gp' = ANY(v_actor.designations), false)
    -- tribe leader deste board
    OR (v_actor.operational_role = 'tribe_leader' AND v_actor.tribe_id = v_board_legacy_tribe_id)
    -- comms team num board de dominio 'communication'
    OR (coalesce(v_board.domain_key, '') = 'communication' AND (
         v_actor.operational_role = 'communicator'
         OR coalesce('comms_team' = ANY(v_actor.designations), false)
         OR coalesce('comms_leader' = ANY(v_actor.designations), false)
         OR coalesce('comms_member' = ANY(v_actor.designations), false)))
    -- lider/coordenador/manager/co_gp da iniciativa deste board
    OR (v_board.initiative_id IS NOT NULL AND v_actor.person_id IS NOT NULL AND EXISTS (
         SELECT 1 FROM public.engagements e
         WHERE e.person_id = v_actor.person_id
           AND e.initiative_id = v_board.initiative_id
           AND e.status = 'active'
           AND e.role IN ('leader', 'coordinator', 'manager', 'co_gp')))
    -- GHSA-jpq5: write_board de escopo ORGANIZATION vale para qualquer board
    -- (desenho dos seeds: manager, co_gp, deputy_manager, comms_leader, curator,
    -- volunteer/leader). Antes esta linha era can_by_member/2, que tambem aceitava
    -- combo de escopo initiative e por isso valia para board ALHEIO.
    OR public.can_org_by_member(p_member_id, 'write_board')
    -- ...e write_board escopado passa a valer SO para a iniciativa DESTE board.
    OR (v_board.initiative_id IS NOT NULL
        AND public.can_by_member(p_member_id, 'write_board', 'initiative', v_board.initiative_id))
  );
END;
$function$;
