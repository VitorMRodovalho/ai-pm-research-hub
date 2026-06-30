-- =====================================================================
-- #975 (PR-3 of #571) — Camada 5 Material-change backbone: CADEIA DE
-- RATIFICAÇÃO de Material change (WA2 — Política 12.2.2).
--
-- Comitê de Curadoria por MAIORIA SIMPLES + ratificação obrigatória
-- PMI-GO (president_go, já existe) + capítulos parceiros 15 dias úteis
-- CONSULTIVO **sem veto**. Hoje o único gate de parceiro (president_others,
-- threshold 4) é BLOQUEANTE => veto invertido; esta PR introduz um gate
-- consultivo janelado que NUNCA bloqueia.
--
-- BEHAVIOR-NEUTRAL / dormant:
--   * NÃO repropositamos president_others — cooperation_agreement/_addendum/
--     manual e a chain de policy IN-FLIGHT (template antigo) continuam a usá-lo
--     bloqueante. A troca de resolve_default_gates('policy') só afeta chains
--     NOVAS; gates já materializados em approval_chains.gates NÃO mudam
--     retroativamente (auditado este turno: 1 chain de policy em review usa o
--     template antigo president_others/4 — preservada).
--   * committee_majority._can_sign_gate = stub FALSE até §7.1 (composição/quórum
--     do Comitê — legal/PM). Roster vazio => maioria nunca atingida => qualquer
--     chain de policy NOVA fica dormente até o go-live. Não abrimos chains de
--     policy novas até v2.7 ratificar + §7.1 (padrão build-ahead do projeto).
--   * gate_state só é escrito para gates 'majority'/'window_optional'; nenhuma
--     chain existente possui esses gates => zero efeito observável no apply.
--
-- SPEC docs/specs/SPEC_571_CAMADA5_MATERIAL_CHANGE.md §5 PR-3 + §9.4. ADR-0115
-- (Gate Matrix v3 — amenda ADR-0016). Deps: PR-1 (add_business_days).
--
-- GROUNDING (este turno, ao vivo):
--   * _gate_threshold_met hoje: all | int>0 | (else true). _can_sign_gate
--     president_others = chapter IN (CE/DF/MG/RS) + chapter_board + legal_signer
--     (4 elegíveis, 1 por capítulo, confirmado ao vivo).
--   * Conclusão da chain = COUNT(gates WHERE NOT _gate_threshold_met)=0 em
--     sign_ip_ratification => status='approved'. O cron espelha exatamente isso.
--   * Notificações de avanço vêm de trg_approval_signoff_notify_fn (AFTER INSERT
--     em approval_signoffs) -> _enqueue_gate_notifications('gate_advanced'); por
--     isso adicionamos CASE PT-BR p/ os 2 kinds.
--   * trg_sync_ratification_cache (AFTER UPDATE OF status) só age em status='active';
--     notify_project_charter_chain_approved só age p/ doc_type='project_charter'
--     numa transição p/ 'approved' — ambos NO-OP p/ writes de gate_state e p/ a
--     transição 'approved' de uma chain de policy. Sem recursão (gate_state UPDATE
--     não é UPDATE OF status).
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. _validate_gates_shape — estende os DOIS branches na MESMA migration
--    (invariante §4.4): allowlist de KIND (+committee_majority,+partner_consultation)
--    E allowlist de THRESHOLD string (+'majority',+'window_optional'). Esquecer o
--    branch de threshold faria o INSERT da chain estourar o CHECK
--    approval_chains_gates_shape. Optional keys (blocking, window_business_days)
--    validados quando presentes => "aceita novos campos / rejeita malformados".
--    IMMUTABLE usada em CHECK: CREATE OR REPLACE não re-valida linhas existentes.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public._validate_gates_shape(p_gates jsonb)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT
    -- gates é jsonb array não-vazio
    jsonb_typeof(p_gates) = 'array'
    AND jsonb_array_length(p_gates) > 0
    AND NOT EXISTS (
      SELECT 1 FROM jsonb_array_elements(p_gates) g
      WHERE NOT (
        -- cada elemento é jsonb object
        jsonb_typeof(g) = 'object'
        -- required keys presentes
        AND g ? 'kind' AND g ? 'order' AND g ? 'threshold'
        -- kind é string no allowlist
        AND (g->>'kind') IN (
          'curator','leader','leader_awareness','submitter_acceptance',
          'chapter_witness','president_go','president_others',
          'volunteers_in_role_active','member_ratification','external_signer',
          'cert_director_go',
          'committee_majority','partner_consultation'  -- #975 PR-3 (WA2)
        )
        -- order é integer >= 1
        AND jsonb_typeof(g->'order') = 'number'
        AND (g->>'order')::int >= 1
        -- threshold é integer >= 0 OU string 'all'/'majority'/'window_optional' (#975 PR-3)
        AND (
          (jsonb_typeof(g->'threshold') = 'number' AND (g->>'threshold')::int >= 0)
          OR (jsonb_typeof(g->'threshold') = 'string'
              AND g->>'threshold' IN ('all','majority','window_optional'))
        )
        -- #975 PR-3: optional keys, quando presentes, bem-tipados (rejeita malformados)
        AND (NOT (g ? 'blocking') OR jsonb_typeof(g->'blocking') = 'boolean')
        AND (NOT (g ? 'window_business_days')
             OR (jsonb_typeof(g->'window_business_days') = 'number'
                 AND (g->>'window_business_days')::int >= 1))
      )
    );
$function$;
COMMENT ON FUNCTION public._validate_gates_shape(jsonb) IS
  '#975 PR-3 (WA2): valida o shape dos gates de uma approval_chain. NOTA (review #10): o campo '
  '"blocking" é METADADO DECLARATIVO — nenhuma lógica de enforcement o lê. O comportamento '
  'NÃO-bloqueante de partner_consultation deriva inteiramente do threshold "window_optional" '
  '(_gate_threshold_met: auto-satisfaz na expiração da janela), não de blocking=false. Um gate '
  '{blocking:false, threshold:1} BLOQUEARIA como qualquer threshold int>0.';

-- ---------------------------------------------------------------------
-- 2. _can_sign_gate — adiciona partner_consultation (= predicado president_others,
--    escopo CE/DF/MG/RS + chapter_board + legal_signer) e committee_majority
--    (stub false até §7.1). #654: _can_sign_gate permanece PURO — toda lógica de
--    maioria/janela vive em _gate_threshold_met. Corpo verbatim da captura live
--    (mig do #666) + as 2 WHEN; nada mais muda.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public._can_sign_gate(p_member_id uuid, p_chain_id uuid, p_gate_kind text, p_doc_type text DEFAULT NULL::text, p_submitter_id uuid DEFAULT NULL::uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_member record; v_chain record; v_doc_type text; v_submitter_id uuid;
  v_doc_initiative_id uuid;  -- #666: scope the 'leader' gate to the doc's initiative leader
BEGIN
  SELECT m.id, m.operational_role, m.designations, m.chapter, m.is_active,
         m.member_status, m.person_id
  INTO v_member FROM public.members m WHERE m.id = p_member_id;
  IF v_member.id IS NULL OR v_member.is_active = false THEN RETURN false; END IF;

  IF p_chain_id IS NOT NULL THEN
    SELECT ac.id, ac.status, ac.gates, ac.document_id, ac.opened_by INTO v_chain
    FROM public.approval_chains ac WHERE ac.id = p_chain_id;
    IF v_chain.id IS NULL OR v_chain.status NOT IN ('review','approved') THEN RETURN false; END IF;
    IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_chain.gates) g WHERE g->>'kind' = p_gate_kind) THEN
      RETURN false;
    END IF;
    -- #666: also resolve the doc's initiative (for the 'leader' scope below).
    SELECT gd.doc_type, gd.initiative_id INTO v_doc_type, v_doc_initiative_id
    FROM public.governance_documents gd WHERE gd.id = v_chain.document_id;
    v_submitter_id := v_chain.opened_by;
  ELSE
    IF p_doc_type IS NULL THEN RETURN false; END IF;
    v_doc_type := p_doc_type;
    v_submitter_id := p_submitter_id;
  END IF;

  RETURN CASE p_gate_kind
    -- p200 ADR-0087: curator V3 designation → V4 can_by_member('curate_content')
    WHEN 'curator' THEN public.can_by_member(v_member.id, 'curate_content')
    -- #666: 'leader' = leader OF THE DOCUMENT'S INITIATIVE (not any sign_chain_leader). The chain
    -- path resolves v_doc_initiative_id; non-initiative org docs (policy/cooperation/volunteer_term,
    -- which legitimately have no initiative) fall back to the bare capability (back-compat). A
    -- project_charter MUST be initiative-scoped, so a charter with a missing initiative link fails
    -- CLOSED here (security review #666 F1) — never "any leader". `leader_awareness` stays broad.
    WHEN 'leader' THEN
      public.can_by_member(v_member.id, 'sign_chain_leader')
      AND (
        (v_doc_initiative_id IS NULL AND v_doc_type IS DISTINCT FROM 'project_charter')
        OR EXISTS (SELECT 1 FROM public.v_initiative_roster r
                   WHERE r.initiative_id = v_doc_initiative_id
                     AND r.member_id = v_member.id
                     AND r.role = 'leader')
      )
    WHEN 'leader_awareness' THEN public.can_by_member(v_member.id, 'sign_chain_leader')
    WHEN 'submitter_acceptance' THEN v_submitter_id IS NOT NULL AND v_member.id = v_submitter_id
    WHEN 'president_go' THEN
      v_member.chapter = 'PMI-GO' AND 'chapter_board' = ANY(v_member.designations)
      AND ('legal_signer' = ANY(v_member.designations)
        OR (v_doc_type = 'volunteer_term_template' AND 'voluntariado_director' = ANY(v_member.designations)))
    WHEN 'president_others' THEN
      v_member.chapter IN ('PMI-CE','PMI-DF','PMI-MG','PMI-RS')
      AND 'chapter_board' = ANY(v_member.designations)
      AND 'legal_signer' = ANY(v_member.designations)
    -- #975 PR-3 (WA2): partner_consultation reusa o MESMO predicado de president_others
    -- (capítulos CE/DF/MG/RS + chapter_board + legal_signer). O caráter CONSULTIVO /
    -- NÃO-bloqueante / janelado vive inteiramente em _gate_threshold_met (threshold
    -- 'window_optional'), NUNCA aqui — _can_sign_gate permanece o denominador PURO (#654).
    WHEN 'partner_consultation' THEN
      v_member.chapter IN ('PMI-CE','PMI-DF','PMI-MG','PMI-RS')
      AND 'chapter_board' = ANY(v_member.designations)
      AND 'legal_signer' = ANY(v_member.designations)
    -- #975 PR-3 (WA2): committee_majority — STUB false até §7.1 fixar o roster/quórum
    -- do Comitê de Curadoria (questão aberta legal/PM). False mantém o gate dormente
    -- (snapshot de roster vazio => maioria nunca atingida) sem travar outros gates. No
    -- go-live, trocar por um predicado de designação (ex.: 'ip_committee' = ANY(designations));
    -- a matemática da maioria em _gate_threshold_met já lê o roster do snapshot (gate_state),
    -- então nenhuma outra mudança é necessária — o roster passa a popular na ativação.
    WHEN 'committee_majority' THEN false
    -- ADR-0016 Amendment 4: Diretoria de Certificação do capítulo sede (PMI-GO) valida
    -- charters do tema certificação antes da assinatura presidencial. Predicado mínimo
    -- por designação de diretoria (sem chapter_board/legal_signer — validação programática
    -- interna, não contra-assinatura jurídica). doc_type-scoped (defense-in-depth).
    WHEN 'cert_director_go' THEN
      v_member.chapter = 'PMI-GO'
      AND 'certificacao_director' = ANY(v_member.designations)
      AND (v_doc_type IS NULL OR v_doc_type = 'project_charter')
    WHEN 'chapter_witness' THEN (
      v_member.operational_role = 'chapter_liaison'
      OR 'chapter_liaison' = ANY(v_member.designations)
      OR ('chapter_vice_president' = ANY(v_member.designations) AND NOT EXISTS (
          SELECT 1 FROM public.members m2 WHERE m2.is_active = true
            AND m2.chapter = v_member.chapter
            AND (m2.operational_role = 'chapter_liaison' OR 'chapter_liaison' = ANY(m2.designations))))
      OR ('chapter_board' = ANY(v_member.designations) AND EXISTS (
          SELECT 1 FROM public.governance_documents gd
          WHERE gd.doc_type = 'cooperation_agreement'
            AND gd.status = 'active'
            AND v_member.chapter = ANY(gd.parties)
            AND gd.signed_at IS NOT NULL
            AND gd.signed_at + interval '60 days' > now()))
    )
    -- #625: um voluntário pré-onboarding (active, mas com engagements ativos ainda pendentes do termo)
    -- NÃO é ainda "volunteer in role active" — contá-lo no denominador 'all' da ratificação é o defeito
    -- circular da família #654 (ele teria de ratificar o próprio termo que ainda não assinou). Exclui
    -- via o helper canônico C0 (mig 20260805000143).
    WHEN 'volunteers_in_role_active' THEN
      v_member.member_status = 'active'
      AND NOT public.member_is_pre_onboarding(v_member.person_id, v_member.member_status)
      AND EXISTS (SELECT 1 FROM public.engagements e
        WHERE e.person_id = v_member.person_id AND e.kind = 'volunteer'
          AND e.status = 'active'
          AND (e.end_date IS NULL OR e.end_date >= CURRENT_DATE)
          AND e.role IN ('researcher','leader','manager'))
    WHEN 'external_signer' THEN EXISTS (
      SELECT 1 FROM public.auth_engagements ae
      WHERE ae.person_id = v_member.person_id
        AND ae.kind = 'external_signer'
        AND ae.is_authoritative = true
    )
    WHEN 'member_ratification' THEN false
    ELSE false
  END;
END;
$function$;

-- ---------------------------------------------------------------------
-- 3. approval_chains.gate_state — estado por-gate (âncora de elegibilidade,
--    snapshot de roster/denominador, janela). Shape (§9.4):
--      {<gate_kind>: {eligible_from, eligible_snapshot, committee_roster_ids,
--                     window_business_days, window_closes_at, auto_closed_at}}
--    Escrito SÓ p/ gates 'majority'/'window_optional' (ver _activate_eligible_gates);
--    auto_closed_at escrito pelo cron. NOT NULL DEFAULT '{}' => linhas existentes ok.
-- ---------------------------------------------------------------------
ALTER TABLE public.approval_chains
  ADD COLUMN IF NOT EXISTS gate_state jsonb NOT NULL DEFAULT '{}'::jsonb;
COMMENT ON COLUMN public.approval_chains.gate_state IS
  '#975 Camada 5 PR-3 (WA2): estado por-gate p/ committee_majority (roster pinado na ativação) '
  'e partner_consultation (janela 15 úteis). {<kind>:{eligible_from,eligible_snapshot,'
  'committee_roster_ids,window_business_days,window_closes_at,auto_closed_at}}. Escrito por '
  '_activate_eligible_gates (elegibilidade) e ratification_window_close_cron (auto_closed_at). '
  'Vazio {} p/ chains sem gates majority/window_optional (todas as existentes).';

-- ---------------------------------------------------------------------
-- 4. _activate_eligible_gates — escreve gate_state quando um gate
--    'majority'/'window_optional' fica ELEGÍVEL (prior gates satisfeitos),
--    snapshotando o roster/denominador (via _can_sign_gate PURO) e a janela.
--    Idempotente: só ativa gate ainda sem entry. Append-only (jsonb_set). Um único
--    UPDATE por chamada (batch). committee_majority: roster pinado na abertura
--    (não live — não encolhe mid-flight). window_optional: window_closes_at =
--    add_business_days(now(), window_business_days).
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public._activate_eligible_gates(p_chain_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_chain record;
  v_gate jsonb;
  v_kind text;
  v_threshold text;
  v_roster uuid[];
  v_eligible int;
  v_window_days int;
  v_state jsonb;
  v_changed boolean := false;
BEGIN
  -- review fix (#5): FOR UPDATE serializa ativações concorrentes (trigger de abertura da
  -- chain correndo contra trigger de signoff) — uma não pode clobberar o gate_state da outra.
  SELECT ac.id, ac.gates, ac.gate_state, ac.status
    INTO v_chain
  FROM public.approval_chains ac WHERE ac.id = p_chain_id
  FOR UPDATE;
  IF v_chain.id IS NULL THEN RETURN; END IF;
  -- only meaningful while the chain is open
  IF v_chain.status NOT IN ('review','approved') THEN RETURN; END IF;

  v_state := COALESCE(v_chain.gate_state, '{}'::jsonb);

  FOR v_gate IN SELECT g FROM jsonb_array_elements(v_chain.gates) g
  LOOP
    v_threshold := v_gate->>'threshold';
    -- only stateful gates carry gate_state
    CONTINUE WHEN v_threshold IS NULL OR v_threshold NOT IN ('majority','window_optional');
    v_kind := v_gate->>'kind';
    -- idempotent: skip gates already activated
    CONTINUE WHEN v_state ? v_kind;
    -- only activate once prior gates are satisfied (the gate is eligible)
    CONTINUE WHEN NOT public._prior_gates_satisfied(p_chain_id, v_kind);

    -- snapshot the eligible cohort via the PURE _can_sign_gate predicate (#654).
    -- For committee_majority this is the roster (stub false => empty until §7.1);
    -- for partner_consultation this is the consultative partner cohort (the 4
    -- CE/DF/MG/RS presidents today). Pinned here so it can't shrink mid-flight.
    SELECT COALESCE(array_agg(m.id ORDER BY m.id), ARRAY[]::uuid[]), count(*)::int
      INTO v_roster, v_eligible
    FROM public.members m
    WHERE m.is_active = true
      AND public._can_sign_gate(m.id, p_chain_id, v_kind);

    IF v_threshold = 'majority' THEN
      v_state := jsonb_set(v_state, ARRAY[v_kind], jsonb_build_object(
        'eligible_from', now(),
        'eligible_snapshot', v_eligible,
        'committee_roster_ids', to_jsonb(v_roster)
      ), true);
    ELSE  -- window_optional
      v_window_days := COALESCE((v_gate->>'window_business_days')::int, 15);
      v_state := jsonb_set(v_state, ARRAY[v_kind], jsonb_build_object(
        'eligible_from', now(),
        'eligible_snapshot', v_eligible,
        'window_business_days', v_window_days,
        'window_closes_at', public.add_business_days(now(), v_window_days)
      ), true);
    END IF;
    v_changed := true;
  END LOOP;

  IF v_changed THEN
    -- gate_state-only UPDATE (NOT status) => does not fire trg_sync_ratification_cache
    -- (AFTER UPDATE OF status); notify_project_charter no-ops (status unchanged). No recursion.
    UPDATE public.approval_chains
      SET gate_state = v_state, updated_at = now()
      WHERE id = p_chain_id;
  END IF;
END;
$function$;
REVOKE EXECUTE ON FUNCTION public._activate_eligible_gates(uuid) FROM PUBLIC, anon, authenticated;

-- 4a/4b. Triggers que ativam gates elegíveis: ao abrir a chain (snapshot do 1º
--        gate, ex.: committee_majority order 1) e a cada signoff (quando um gate
--        prévio é satisfeito, o próximo gate stateful fica elegível e abre a janela).
--        AFTER ROW => roda antes do próximo statement do RPC chamador, então a
--        conclusão da chain em sign_ip_ratification já enxerga o gate_state fresco.
CREATE OR REPLACE FUNCTION public.trg_activate_eligible_gates_on_signoff()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  PERFORM public._activate_eligible_gates(NEW.approval_chain_id);
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.trg_activate_eligible_gates_on_chain()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  PERFORM public._activate_eligible_gates(NEW.id);
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_activate_eligible_gates_on_signoff ON public.approval_signoffs;
CREATE TRIGGER trg_activate_eligible_gates_on_signoff
  AFTER INSERT ON public.approval_signoffs
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_activate_eligible_gates_on_signoff();

DROP TRIGGER IF EXISTS trg_activate_eligible_gates_on_chain ON public.approval_chains;
CREATE TRIGGER trg_activate_eligible_gates_on_chain
  AFTER INSERT OR UPDATE OF status ON public.approval_chains
  FOR EACH ROW
  WHEN (NEW.status = 'review')
  EXECUTE FUNCTION public.trg_activate_eligible_gates_on_chain();

-- review fix (#6): REVOKE nos wrappers SECDEF (convenção Track Q-D; sob default-PUBLIC
-- um session autenticado poderia chamar o wrapper direto e disparar _activate em qualquer chain_id).
REVOKE EXECUTE ON FUNCTION public.trg_activate_eligible_gates_on_signoff() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.trg_activate_eligible_gates_on_chain() FROM PUBLIC, anon, authenticated;

-- ---------------------------------------------------------------------
-- 4c. trg_guard_gate_state_system_only — review fix (#4, HIGH): gate_state é
--     SYSTEM-MANAGED. A policy RLS approval_chains_update_admin permite a qualquer
--     detentor de manage_member (NÃO GP-only: inclui liaisons/coordenadores) UPDATE
--     de qualquer coluna. Sem este guard, um detentor poderia forjar
--     gate_state.<kind>.auto_closed_at (data passada) ou committee_roster_ids e CONCLUIR
--     uma chain de Política pulando a consulta de 15 úteis (mesmo bypass do #1 por outra
--     porta). Guard SECURITY INVOKER (NÃO definer — precisa enxergar o current_user REAL
--     do statement): bloqueia mudança de gate_state salvo writers de sistema. _activate /
--     cron são SECDEF owned-by-postgres => current_user='postgres' dentro deles => liberados;
--     service_role (tests/admin) liberado; authenticated/anon (PostgREST) => RAISE.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.trg_guard_gate_state_system_only()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  IF NEW.gate_state IS DISTINCT FROM OLD.gate_state
     AND current_user NOT IN ('postgres', 'supabase_admin', 'service_role') THEN
    RAISE EXCEPTION 'approval_chains.gate_state is system-managed (set only by _activate_eligible_gates / ratification_window_close_cron); direct writes are forbidden (#975 PR-3 governance integrity)'
      USING ERRCODE = 'insufficient_privilege';
  END IF;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_guard_gate_state_system_only ON public.approval_chains;
CREATE TRIGGER trg_guard_gate_state_system_only
  BEFORE UPDATE OF gate_state ON public.approval_chains
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_guard_gate_state_system_only();

-- ---------------------------------------------------------------------
-- 5. _gate_threshold_met — adiciona branch 'majority' (maioria estrita contra o
--    roster snapshotado em gate_state) e 'window_optional' (consultivo janelado:
--    TRUE quando auto_closed_at OU todos os elegíveis responderam). Corpo verbatim
--    da captura live (#654) + os 2 branches. Branch 'all'/int/else INALTERADOS.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public._gate_threshold_met(p_chain_id uuid, p_gate jsonb)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT CASE
    WHEN (p_gate->>'threshold') = 'all' THEN
      (SELECT count(*) FROM public.approval_signoffs s
         WHERE s.approval_chain_id = p_chain_id AND s.gate_kind = (p_gate->>'kind')
           AND s.signoff_type IN ('approval','acknowledge'))
      >= (SELECT count(*) FROM public.members m
          WHERE m.is_active AND public._can_sign_gate(m.id, p_chain_id, p_gate->>'kind'))
    -- #975 PR-3 (WA2): committee_majority — maioria ESTRITA das aprovações sobre o
    -- roster pinado em gate_state na ativação (NÃO live _can_sign_gate, que encolheria
    -- mid-flight se um membro saísse de função). Roster vazio/ausente => não atingido
    -- (quórum falha; dormente até §7.1). Conta só signoff_type='approval'.
    WHEN (p_gate->>'threshold') = 'majority' THEN
      (SELECT r.n >= 1
          AND (SELECT count(*) FROM public.approval_signoffs s
               WHERE s.approval_chain_id = p_chain_id
                 AND s.gate_kind = (p_gate->>'kind')
                 AND s.signoff_type = 'approval'
                 AND s.signer_id = ANY(r.roster))
              > floor(r.n::numeric / 2)
       FROM (
         SELECT roster, cardinality(roster) AS n
         FROM (
           SELECT COALESCE(ARRAY(
             SELECT (jsonb_array_elements_text(
                       ac.gate_state -> (p_gate->>'kind') -> 'committee_roster_ids'))::uuid
           ), ARRAY[]::uuid[]) AS roster
           FROM public.approval_chains ac WHERE ac.id = p_chain_id
         ) q
       ) r)
    -- #975 PR-3 (WA2): partner_consultation — consultivo janelado NÃO-bloqueante.
    -- Atingido quando a janela auto-fechou (cron escreveu auto_closed_at) OU todos os
    -- elegíveis responderam (QUALQUER signoff_type — approval/abstain/rejection; uma
    -- rejeição é registrada mas NUNCA veta). eligible_snapshot ausente => não atingido.
    WHEN (p_gate->>'threshold') = 'window_optional' THEN
      (SELECT (ac.gate_state -> (p_gate->>'kind') ->> 'auto_closed_at') IS NOT NULL
          OR (
            (ac.gate_state -> (p_gate->>'kind') ->> 'eligible_snapshot') IS NOT NULL
            -- review fix (BLOCKER, 4 lentes): guard eligible_snapshot > 0. Com 0 parceiros
            -- elegíveis o gate consultivo NÃO pode auto-satisfazer via count(0)>=0 — só fecha
            -- por auto_closed_at (cron, após os 15 úteis), preservando a janela de observação
            -- mandatória da Política 12.2.2. Espelha o guard n>=1 do branch committee_majority.
            AND (ac.gate_state -> (p_gate->>'kind') ->> 'eligible_snapshot')::int > 0
            -- count DISTINCT signer (o UNIQUE existente approval_signoffs(chain,gate,signer) já
            -- garante 1 linha/membro, mas DISTINCT é a intenção correta e auto-documentada:
            -- "todos os elegíveis responderam" = respondentes distintos >= snapshot).
            AND (SELECT count(DISTINCT s.signer_id) FROM public.approval_signoffs s
                 WHERE s.approval_chain_id = p_chain_id AND s.gate_kind = (p_gate->>'kind'))
                >= (ac.gate_state -> (p_gate->>'kind') ->> 'eligible_snapshot')::int
          )
       FROM public.approval_chains ac WHERE ac.id = p_chain_id)
    WHEN (p_gate->>'threshold') ~ '^[0-9]+$' AND (p_gate->>'threshold')::int > 0 THEN
      (SELECT count(*) FROM public.approval_signoffs s
         WHERE s.approval_chain_id = p_chain_id AND s.gate_kind = (p_gate->>'kind')
           AND s.signoff_type IN ('approval','acknowledge'))
      >= (p_gate->>'threshold')::int
    ELSE true
  END;
$function$;

-- ---------------------------------------------------------------------
-- 6. _enqueue_gate_notifications — CASE PT-BR p/ os 2 novos kinds nos DOIS blocos
--    (chain_opened + gate_advanced). Corpo verbatim da captura live + entradas
--    committee_majority / partner_consultation. Texto ASCII (sem diacríticos) p/
--    casar o estilo das entradas existentes.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public._enqueue_gate_notifications(p_chain_id uuid, p_event text, p_gate_kind text DEFAULT NULL::text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_chain record;
  v_doc record;
  v_version record;
  v_submitter record;
  v_gate jsonb;
  v_target record;
  v_link text;
  v_title text;
  v_body text;
  v_notif_type text;
  v_enqueued int := 0;
  v_action_label text;
  v_role_singular text;
  v_action_verb text;
  v_current_order int;
  v_next_order int;
BEGIN
  IF p_event NOT IN ('chain_opened','gate_advanced','chain_approved') THEN
    RAISE EXCEPTION 'Invalid event: %', p_event USING ERRCODE = 'invalid_parameter_value';
  END IF;

  SELECT ac.id, ac.status, ac.gates, ac.document_id, ac.version_id, ac.opened_by
  INTO v_chain FROM public.approval_chains ac WHERE ac.id = p_chain_id;
  IF v_chain.id IS NULL THEN RETURN 0; END IF;

  SELECT gd.id, gd.title, gd.doc_type INTO v_doc
  FROM public.governance_documents gd WHERE gd.id = v_chain.document_id;

  SELECT dv.id, dv.version_label INTO v_version
  FROM public.document_versions dv WHERE dv.id = v_chain.version_id;

  SELECT m.id, m.name, m.email INTO v_submitter
  FROM public.members m WHERE m.id = v_chain.opened_by;

  IF p_event = 'chain_opened' THEN
    SELECT MIN((g->>'order')::int) INTO v_next_order
    FROM jsonb_array_elements(v_chain.gates) g;

    IF v_next_order IS NULL THEN RETURN 0; END IF;

    FOR v_gate IN
      SELECT g FROM jsonb_array_elements(v_chain.gates) g
      WHERE (g->>'order')::int = v_next_order
      ORDER BY g->>'kind'
    LOOP
      v_link := public._ip_ratify_cta_link(p_chain_id, v_gate->>'kind');
      v_notif_type := 'ip_ratification_gate_pending';

      v_action_label := CASE v_gate->>'kind'
        WHEN 'curator' THEN 'Curadoria'
        WHEN 'leader_awareness' THEN 'Ciencia da lideranca'
        WHEN 'submitter_acceptance' THEN 'Aceite do GP'
        WHEN 'chapter_witness' THEN 'Testemunho de capitulo'
        WHEN 'president_go' THEN 'Assinatura da presidencia PMI-GO'
        WHEN 'president_others' THEN 'Assinatura de presidencia de capitulo'
        WHEN 'cert_director_go' THEN 'Validacao da Diretoria de Certificacao PMI-GO'
        WHEN 'volunteers_in_role_active' THEN 'Ratificacao de voluntario em funcao ativa'
        WHEN 'member_ratification' THEN 'Ratificacao de membro'
        WHEN 'committee_majority' THEN 'Deliberacao do Comite de Curadoria'
        WHEN 'partner_consultation' THEN 'Manifestacao consultiva do capitulo parceiro'
        ELSE v_gate->>'kind'
      END;
      v_role_singular := CASE v_gate->>'kind'
        WHEN 'curator' THEN 'curador(a)'
        WHEN 'leader_awareness' THEN 'lider do Nucleo'
        WHEN 'submitter_acceptance' THEN 'Gerente de Projeto'
        WHEN 'chapter_witness' THEN 'ponto focal do seu capitulo'
        WHEN 'president_go' THEN 'presidencia do PMI-GO'
        WHEN 'president_others' THEN 'presidencia do seu capitulo'
        WHEN 'cert_director_go' THEN 'Diretoria de Certificacao do PMI-GO'
        WHEN 'volunteers_in_role_active' THEN 'voluntario(a) em funcao ativa'
        WHEN 'member_ratification' THEN 'membro ativo'
        WHEN 'committee_majority' THEN 'membro do Comite de Curadoria'
        WHEN 'partner_consultation' THEN 'presidencia do seu capitulo parceiro'
        ELSE v_gate->>'kind'
      END;
      v_action_verb := CASE v_gate->>'kind'
        WHEN 'curator' THEN 'ler o documento completo e decidir se ele avanca para a fase de aprovacao pelas presidencias de capitulo. Voce pode registrar duvidas ou pontos de ajuste como comentarios antes de aprovar'
        WHEN 'leader_awareness' THEN 'ler o documento e registrar ciencia. Este passo nao bloqueia o workflow, mas formaliza que a lideranca esta ciente do que sera ratificado'
        WHEN 'submitter_acceptance' THEN 'confirmar formalmente que o documento esta pronto para circular as presidencias de capitulo'
        WHEN 'chapter_witness' THEN 'confirmar que o documento foi apresentado e e de conhecimento dos membros do seu capitulo'
        WHEN 'president_go' THEN 'ler e assinar como presidencia do capitulo-sede. Apos sua assinatura, as demais presidencias serao notificadas'
        WHEN 'president_others' THEN 'ler e assinar como presidencia do seu capitulo, apos a presidencia PMI-GO ja ter assinado'
        WHEN 'cert_director_go' THEN 'validar como Diretoria de Certificacao do PMI-GO'
        WHEN 'volunteers_in_role_active' THEN 'ler o documento e ratificar como voluntario(a) em funcao ativa. Sua ratificacao formaliza a adesao pessoal aos termos atualizados enquanto voce mantem funcao ativa no Nucleo'
        WHEN 'member_ratification' THEN 'ler o documento e ratificar como membro ativo. Sua ratificacao formaliza a adesao pessoal aos termos'
        WHEN 'committee_majority' THEN 'deliberar como membro do Comite de Curadoria sobre a mudanca material; a aprovacao do colegiado se da por MAIORIA SIMPLES dos membros do roster'
        WHEN 'partner_consultation' THEN 'manifestar-se em carater CONSULTIVO e SEM poder de veto sobre a mudanca material da Politica, no prazo de 15 dias uteis contados pelo calendario de feriados de Goias (sede do Nucleo IA & GP); o silencio ou a discordancia nao impedem a ratificacao'
        ELSE 'revisar e agir conforme o seu papel neste workflow'
      END;

      FOR v_target IN
        SELECT m.id AS member_id, m.name FROM public.members m
        WHERE m.is_active = true
          AND public._can_sign_gate(m.id, p_chain_id, v_gate->>'kind')
          AND NOT EXISTS (
            SELECT 1 FROM public.approval_signoffs s
            WHERE s.approval_chain_id = p_chain_id
              AND s.gate_kind = v_gate->>'kind' AND s.signer_id = m.id
          )
      LOOP
        v_title := v_doc.title || ' ' || COALESCE(v_version.version_label,'') ||
                   ' — ' || v_action_label || ' solicitada por ' || COALESCE(v_submitter.name, 'Gerente de Projeto');
        v_body := COALESCE(v_submitter.name, 'O Gerente de Projeto') ||
                  ' submeteu o documento "' || v_doc.title || '" versao ' ||
                  COALESCE(v_version.version_label,'') || ' para ratificacao no Nucleo IA & GP. ' ||
                  'Como ' || v_role_singular || ', voce deve ' || v_action_verb || '.';

        PERFORM public.create_notification(
          v_target.member_id, v_notif_type, v_title, v_body, v_link,
          'approval_chain', p_chain_id
        );
        v_enqueued := v_enqueued + 1;
      END LOOP;
    END LOOP;
    RETURN v_enqueued;
  END IF;

  IF p_event = 'gate_advanced' AND p_gate_kind IS NOT NULL THEN
    SELECT (g->>'order')::int INTO v_current_order
    FROM jsonb_array_elements(v_chain.gates) g
    WHERE g->>'kind' = p_gate_kind
    LIMIT 1;

    SELECT MIN((g->>'order')::int) INTO v_next_order
    FROM jsonb_array_elements(v_chain.gates) g
    WHERE v_current_order IS NOT NULL
      AND (g->>'order')::int > v_current_order;

    IF v_next_order IS NOT NULL THEN
      FOR v_gate IN
        SELECT g FROM jsonb_array_elements(v_chain.gates) g
        WHERE (g->>'order')::int = v_next_order
        ORDER BY g->>'kind'
      LOOP
        v_link := public._ip_ratify_cta_link(p_chain_id, v_gate->>'kind');
        v_notif_type := CASE WHEN (v_gate->>'kind') IN ('volunteers_in_role_active','member_ratification')
                            THEN 'ip_ratification_awaiting_members'
                            ELSE 'ip_ratification_gate_pending' END;

        v_action_label := CASE v_gate->>'kind'
          WHEN 'curator' THEN 'Curadoria'
          WHEN 'leader_awareness' THEN 'Ciencia da lideranca'
          WHEN 'submitter_acceptance' THEN 'Aceite do GP'
          WHEN 'chapter_witness' THEN 'Testemunho de capitulo'
          WHEN 'president_go' THEN 'Assinatura da presidencia PMI-GO'
          WHEN 'president_others' THEN 'Assinatura de presidencia de capitulo'
          WHEN 'cert_director_go' THEN 'Validacao da Diretoria de Certificacao PMI-GO'
          WHEN 'volunteers_in_role_active' THEN 'Ratificacao de voluntario em funcao ativa'
          WHEN 'member_ratification' THEN 'Ratificacao de membro'
          WHEN 'committee_majority' THEN 'Deliberacao do Comite de Curadoria'
          WHEN 'partner_consultation' THEN 'Manifestacao consultiva do capitulo parceiro'
          ELSE v_gate->>'kind'
        END;
        v_role_singular := CASE v_gate->>'kind'
          WHEN 'curator' THEN 'curador(a)'
          WHEN 'leader_awareness' THEN 'lider do Nucleo'
          WHEN 'submitter_acceptance' THEN 'Gerente de Projeto'
          WHEN 'chapter_witness' THEN 'ponto focal do seu capitulo'
          WHEN 'president_go' THEN 'presidencia do PMI-GO'
          WHEN 'president_others' THEN 'presidencia do seu capitulo'
          WHEN 'cert_director_go' THEN 'Diretoria de Certificacao do PMI-GO'
          WHEN 'volunteers_in_role_active' THEN 'voluntario(a) em funcao ativa'
          WHEN 'member_ratification' THEN 'membro ativo'
          WHEN 'committee_majority' THEN 'membro do Comite de Curadoria'
          WHEN 'partner_consultation' THEN 'presidencia do seu capitulo parceiro'
          ELSE v_gate->>'kind'
        END;
        v_action_verb := CASE v_gate->>'kind'
          WHEN 'curator' THEN 'ler o documento e aprovar como curador'
          WHEN 'leader_awareness' THEN 'ler e registrar ciencia'
          WHEN 'submitter_acceptance' THEN 'confirmar que esta pronto para circular presidencias'
          WHEN 'chapter_witness' THEN 'confirmar como ponto focal do seu capitulo'
          WHEN 'president_go' THEN 'assinar como presidencia PMI-GO'
          WHEN 'president_others' THEN 'assinar como presidencia de capitulo'
          WHEN 'cert_director_go' THEN 'validar como Diretoria de Certificacao do PMI-GO'
          WHEN 'volunteers_in_role_active' THEN 'ratificar como voluntario(a) em funcao ativa'
          WHEN 'member_ratification' THEN 'ratificar como membro ativo'
          WHEN 'committee_majority' THEN 'deliberar como membro do Comite de Curadoria (maioria simples)'
          WHEN 'partner_consultation' THEN 'manifestar-se em carater consultivo, SEM veto, no prazo de 15 dias uteis contados pelo calendario de feriados de Goias, sede do Nucleo IA & GP (o silencio nao impede a ratificacao)'
          ELSE 'agir conforme seu papel'
        END;

        FOR v_target IN
          SELECT m.id AS member_id, m.name FROM public.members m
          WHERE m.is_active = true
            AND public._can_sign_gate(m.id, p_chain_id, v_gate->>'kind')
            AND NOT EXISTS (
              SELECT 1 FROM public.approval_signoffs s
              WHERE s.approval_chain_id = p_chain_id
                AND s.gate_kind = v_gate->>'kind' AND s.signer_id = m.id
            )
        LOOP
          v_title := v_doc.title || ' ' || COALESCE(v_version.version_label,'') ||
                     ' — sua ' || lower(v_action_label) || ' agora e necessaria';
          v_body := 'O gate anterior foi satisfeito. Voce esta agora elegivel para ' ||
                    v_action_verb || ' no documento "' || v_doc.title || '" versao ' ||
                    COALESCE(v_version.version_label,'') ||
                    ', submetido por ' || COALESCE(v_submitter.name, 'Gerente de Projeto') ||
                    ' para ratificacao no Nucleo IA & GP. Como ' || v_role_singular || ', ' || v_action_verb || '.';

          PERFORM public.create_notification(
            v_target.member_id, v_notif_type, v_title, v_body, v_link,
            'approval_chain', p_chain_id
          );
          v_enqueued := v_enqueued + 1;
        END LOOP;
      END LOOP;
    END IF;

    IF v_submitter.id IS NOT NULL THEN
      v_link := '/admin/governance/documents/' || p_chain_id::text;
      v_title := v_doc.title || ' ' || COALESCE(v_version.version_label,'') ||
                 ' — gate "' || p_gate_kind || '" satisfeito';
      v_body := 'O gate "' || p_gate_kind || '" da cadeia de ratificacao do documento "' ||
                v_doc.title || '" versao ' || COALESCE(v_version.version_label,'') ||
                ' foi satisfeito. O workflow avancou automaticamente. Acompanhe o progresso dos proximos gates na plataforma.';
      PERFORM public.create_notification(
        v_submitter.id, 'ip_ratification_gate_advanced', v_title, v_body, v_link,
        'approval_chain', p_chain_id
      );
      v_enqueued := v_enqueued + 1;
    END IF;
    RETURN v_enqueued;
  END IF;

  IF p_event = 'chain_approved' AND v_submitter.id IS NOT NULL THEN
    v_link := '/admin/governance/documents/' || p_chain_id::text;
    v_title := v_doc.title || ' ' || COALESCE(v_version.version_label,'') ||
               ' — cadeia de ratificacao concluida';
    v_body := 'Todos os gates da cadeia de ratificacao do documento "' || v_doc.title ||
              '" versao ' || COALESCE(v_version.version_label,'') ||
              ' foram satisfeitos. O documento pode ser ativado como vigente no Nucleo IA & GP.';
    PERFORM public.create_notification(
      v_submitter.id, 'ip_ratification_chain_approved', v_title, v_body, v_link,
      'approval_chain', p_chain_id
    );
    RETURN 1;
  END IF;

  RETURN 0;
END;
$function$;

-- ---------------------------------------------------------------------
-- 7. resolve_default_gates('policy') — Gate Matrix v3 (ADR-0115). Novo template
--    de ratificação de Material change da Política (12.2.2): Comitê de Curadoria
--    por MAIORIA SIMPLES -> ratificação obrigatória PMI-GO -> consulta consultiva
--    aos parceiros (15 úteis, sem veto). Substitui o antigo president_others/4
--    (veto invertido). Demais doc_types INALTERADOS (verbatim).
--    A troca só afeta chains NOVAS; a chain de policy IN-FLIGHT em review mantém
--    seus gates já materializados (president_others/4). curator/submitter_acceptance
--    são upstream (CR submit->review->approve, §6 passo 4) — o Comitê de Curadoria
--    deliberando por maioria É a revisão curatorial desta cadeia (ADR-0115 §rationale).
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.resolve_default_gates(p_doc_type text)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT CASE p_doc_type
    WHEN 'cooperation_agreement' THEN '[
      {"kind":"curator","order":1,"threshold":"all"},
      {"kind":"leader_awareness","order":2,"threshold":0},
      {"kind":"submitter_acceptance","order":3,"threshold":1},
      {"kind":"chapter_witness","order":4,"threshold":5},
      {"kind":"president_go","order":5,"threshold":1},
      {"kind":"president_others","order":6,"threshold":4}
    ]'::jsonb
    WHEN 'cooperation_addendum' THEN '[
      {"kind":"curator","order":1,"threshold":"all"},
      {"kind":"leader_awareness","order":2,"threshold":0},
      {"kind":"submitter_acceptance","order":3,"threshold":1},
      {"kind":"chapter_witness","order":4,"threshold":5},
      {"kind":"president_go","order":5,"threshold":1},
      {"kind":"president_others","order":6,"threshold":4}
    ]'::jsonb
    WHEN 'volunteer_term_template' THEN '[
      {"kind":"curator","order":1,"threshold":"all"},
      {"kind":"leader_awareness","order":2,"threshold":0},
      {"kind":"submitter_acceptance","order":3,"threshold":1},
      {"kind":"president_go","order":4,"threshold":1},
      {"kind":"volunteers_in_role_active","order":5,"threshold":"all"}
    ]'::jsonb
    WHEN 'volunteer_addendum' THEN '[
      {"kind":"curator","order":1,"threshold":"all"},
      {"kind":"leader_awareness","order":2,"threshold":0},
      {"kind":"submitter_acceptance","order":3,"threshold":1},
      {"kind":"president_go","order":4,"threshold":1},
      {"kind":"volunteers_in_role_active","order":5,"threshold":"all"}
    ]'::jsonb
    WHEN 'policy' THEN '[
      {"kind":"committee_majority","order":1,"threshold":"majority"},
      {"kind":"president_go","order":2,"threshold":1},
      {"kind":"partner_consultation","order":3,"threshold":"window_optional","blocking":false,"window_business_days":15}
    ]'::jsonb
    WHEN 'editorial_guide' THEN '[
      {"kind":"curator","order":1,"threshold":"all"},
      {"kind":"leader_awareness","order":2,"threshold":0},
      {"kind":"submitter_acceptance","order":3,"threshold":1}
    ]'::jsonb
    WHEN 'governance_guideline' THEN '[
      {"kind":"curator","order":1,"threshold":"all"},
      {"kind":"leader_awareness","order":2,"threshold":0},
      {"kind":"submitter_acceptance","order":3,"threshold":1}
    ]'::jsonb
    WHEN 'manual' THEN '[
      {"kind":"curator","order":1,"threshold":"all"},
      {"kind":"leader_awareness","order":2,"threshold":0},
      {"kind":"submitter_acceptance","order":3,"threshold":1},
      {"kind":"president_go","order":4,"threshold":1},
      {"kind":"president_others","order":5,"threshold":4}
    ]'::jsonb
    WHEN 'executive_summary' THEN '[
      {"kind":"curator","order":1,"threshold":"all"},
      {"kind":"submitter_acceptance","order":2,"threshold":1}
    ]'::jsonb
    WHEN 'framework_reference' THEN '[
      {"kind":"curator","order":1,"threshold":"all"},
      {"kind":"leader_awareness","order":2,"threshold":0},
      {"kind":"submitter_acceptance","order":3,"threshold":1}
    ]'::jsonb
    WHEN 'project_charter' THEN '[
      {"kind":"curator","order":1,"threshold":"all"},
      {"kind":"leader_awareness","order":2,"threshold":0}
    ]'::jsonb
    ELSE NULL
  END;
$function$;

-- ---------------------------------------------------------------------
-- 7b. trg_notify_chain_approved — review fix (#3, HIGH): notificação de conclusão
--     em TODOS os caminhos de conclusão. Antes desta PR, a conclusão de chain
--     (sign_ip_ratification UPDATE status='approved') NÃO emitia notificação de
--     "cadeia concluída" em nenhum caminho. PR-3 introduz o caminho do cron (janela
--     expira) — para não criar assimetria (cron notifica / assinatura-antecipada
--     silencia), centralizamos a notificação numa transição review->approved.
--     Cobre AMBOS: cron de janela E assinatura de todos os parceiros antes da expiração
--     (sign_ip_ratification, sem editar o RPC). project_charter tem notifier dedicado
--     (notify_project_charter_chain_approved) => skip aqui p/ não duplicar.
--     Mudança de comportamento mínima e positiva: o submitter passa a saber que a
--     cadeia concluiu (todos os doc_types de ratificação exceto project_charter).
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.trg_notify_chain_approved()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  IF EXISTS (SELECT 1 FROM public.governance_documents gd
             WHERE gd.id = NEW.document_id AND gd.doc_type = 'project_charter') THEN
    RETURN NEW;  -- project_charter: dedicated notifier handles it
  END IF;
  PERFORM public._enqueue_gate_notifications(NEW.id, 'chain_approved', NULL);
  RETURN NEW;
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.trg_notify_chain_approved() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_notify_chain_approved ON public.approval_chains;
CREATE TRIGGER trg_notify_chain_approved
  AFTER UPDATE OF status ON public.approval_chains
  FOR EACH ROW
  WHEN (NEW.status = 'approved' AND OLD.status = 'review')
  EXECUTE FUNCTION public.trg_notify_chain_approved();

-- ---------------------------------------------------------------------
-- 8. ratification_window_close_cron — fecha janelas consultivas expiradas
--    (escreve auto_closed_at), re-avalia a conclusão da chain (espelha
--    sign_ip_ratification: COUNT(gates WHERE NOT _gate_threshold_met)=0 =>
--    status='approved') e notifica o submitter. Idempotente (auto_closed_at
--    escrito uma vez). FOR UPDATE serializa contra signoffs concorrentes.
--    On-read NUNCA vira status sozinho — só este cron (e sign_ip_ratification).
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.ratification_window_close_cron()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_chain record;
  v_gate jsonb;
  v_kind text;
  v_state jsonb;
  v_closed int := 0;
  v_concluded int := 0;
  v_remaining int;
  v_changed boolean;
BEGIN
  FOR v_chain IN
    SELECT ac.id, ac.gates, ac.gate_state
    FROM public.approval_chains ac
    WHERE ac.status = 'review' AND ac.closed_at IS NULL
      AND ac.gate_state <> '{}'::jsonb
      AND EXISTS (
        SELECT 1 FROM jsonb_array_elements(ac.gates) g
        WHERE (g->>'threshold') = 'window_optional'
          AND (ac.gate_state -> (g->>'kind') ->> 'window_closes_at') IS NOT NULL
          AND (ac.gate_state -> (g->>'kind') ->> 'auto_closed_at') IS NULL
          AND (ac.gate_state -> (g->>'kind') ->> 'window_closes_at')::timestamptz <= now()
      )
    FOR UPDATE OF ac
  LOOP
    v_state := v_chain.gate_state;
    v_changed := false;

    FOR v_gate IN
      SELECT g FROM jsonb_array_elements(v_chain.gates) g
      WHERE (g->>'threshold') = 'window_optional'
    LOOP
      v_kind := v_gate->>'kind';
      IF (v_state -> v_kind ->> 'window_closes_at') IS NOT NULL
         AND (v_state -> v_kind ->> 'auto_closed_at') IS NULL
         AND (v_state -> v_kind ->> 'window_closes_at')::timestamptz <= now() THEN
        INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes)
        VALUES (NULL, 'ratification_window.auto_closed', 'approval_chain', v_chain.id,
          jsonb_build_object('gate_kind', v_kind,
            'window_closes_at', (v_state -> v_kind ->> 'window_closes_at'),
            'eligible_snapshot', (v_state -> v_kind ->> 'eligible_snapshot')));
        v_state := jsonb_set(v_state, ARRAY[v_kind,'auto_closed_at'], to_jsonb(now()), true);
        v_changed := true;
        v_closed := v_closed + 1;
      END IF;
    END LOOP;

    IF v_changed THEN
      UPDATE public.approval_chains SET gate_state = v_state, updated_at = now() WHERE id = v_chain.id;
      -- re-evaluate conclusion exactly like sign_ip_ratification
      SELECT count(*) INTO v_remaining
      FROM jsonb_array_elements(v_chain.gates) g
      WHERE NOT public._gate_threshold_met(v_chain.id, g);
      IF v_remaining = 0 THEN
        -- the review->approved UPDATE fires trg_notify_chain_approved (review fix #3),
        -- which enqueues the chain_approved notification — no explicit call here (would double-notify).
        UPDATE public.approval_chains
          SET status = 'approved', approved_at = now(), updated_at = now()
          WHERE id = v_chain.id AND status = 'review';
        v_concluded := v_concluded + 1;
      END IF;
    END IF;
  END LOOP;

  RETURN jsonb_build_object('windows_closed', v_closed, 'chains_concluded', v_concluded, 'ran_at', now());
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.ratification_window_close_cron() FROM PUBLIC, anon, authenticated;

-- 8a. Agendar o cron (diário 07:00 UTC = 04:00 BRT). cron.schedule por nome é
--     idempotente (upsert). Janela em dias úteis => granularidade diária basta.
SELECT cron.schedule('ratification-window-close-daily', '0 7 * * *',
  $$SELECT public.ratification_window_close_cron();$$);

-- ---------------------------------------------------------------------
-- 8b. Rebuild the preview_gate_eligibles cache: resolve_default_gates('policy')
--     mudou o conjunto de gates da Política (committee_majority/partner_consultation
--     entram; curator/president_others saem). O cache pré-computado (ADR-0016 Amend 3)
--     não tem hook de invalidação sobre resolve_default_gates (função pura), então
--     rebuildamos aqui — senão preview_gate_eligibles_cache mente sobre partner_consultation
--     (cache=0 vs live=4) e _audit_preview_gate_eligibles_drift acusa drift.
--     Usamos o helper interno _refresh_preview_gate_eligibles_for_member (SECDEF, SEM
--     auth-gate) num loop — NÃO refresh_preview_gate_eligibles_cache_all(), que exige
--     auth.uid()+manage_platform e RAISEia 'Not authenticated' em contexto de migration
--     (postgres/service_role, sem JWT) — quebraria o replay.
-- ---------------------------------------------------------------------
DO $refresh_preview$
DECLARE rec record;  -- NOT 'm' — would shadow the members alias in the DELETE below (ambiguous m.id)
BEGIN
  FOR rec IN SELECT id FROM public.members WHERE is_active = true LOOP
    PERFORM public._refresh_preview_gate_eligibles_for_member(rec.id);
  END LOOP;
  -- prune cache rows for members no longer active (parity with _all's cleanup)
  DELETE FROM public.preview_gate_eligibles_cache c
  WHERE NOT EXISTS (SELECT 1 FROM public.members m WHERE m.id = c.member_id AND m.is_active = true);
END;
$refresh_preview$;

-- ---------------------------------------------------------------------
-- 9. PostgREST schema reload (nova coluna + assinaturas/registry alterados).
-- ---------------------------------------------------------------------
NOTIFY pgrst, 'reload schema';
