-- =====================================================================
-- #976 (PR-4 of #571) — Camada 5 Material-change backbone: MÁQUINA DE
-- ESTADOS DE RE-ACEITE (WA1 — Política 12.2.1; Termo 15.3, 15.4.3,
-- 15.4.4, 15.4.5).
--
-- Ciclo: aviso-30d (corridos) -> janela de re-aceite 15 úteis -> suspenso
-- +30d (corridos) -> desligamento, com objeção fundamentada (15.4.3) e
-- recusa expressa (15.3(e)). Construída DORMENTE.
--
-- BEHAVIOR-NEUTRAL / dormant:
--   * O fan-out real (open_reacceptance_obligations com p_dry_run=false) é a
--     superfície do leak #648/#653 (ADR-0102 GR-1) e é OUTWARD-gated em PM-OK +
--     #334 (G12 DPO/ANPD). Nada dispara sozinho: o cron diário varre uma tabela
--     vazia (no-op) até alguém chamar open(). member_document_signatures = 0 ao
--     vivo => mesmo um open(dry_run=false) hoje teria fan-out VAZIO (o alvo é
--     "signatário com is_current", não members.is_active).
--   * change_class IS NULL = NÃO-material (fail-safe, contrato forward de PR-1):
--     open() só abre obrigação para to_version com change_class='material'.
--
-- SPEC docs/specs/SPEC_571_CAMADA5_MATERIAL_CHANGE.md §5 PR-4 + §9.5 (correções
-- legais VINCULANTES — sobrescrevem o pseudocódigo de §5). ADR-0116 (amenda
-- ADR-0016 família legal-ops). Deps: PR-1 (add_business_days, change_class) +
-- PR-3 (effective_from/material gate já existem no doc-level).
--
-- GROUNDING (este turno, ao vivo, projeto ldrfrvwhxsmgaabwmaik):
--   * member_document_signatures: ledger SSOT por (member,document) com
--     auto-supersede AFTER INSERT (trg_member_doc_sig_supersede_previous). 0 rows.
--     SEM organization_id; tem signed_version_id/is_current/superseded_*.
--     (sign_volunteer_agreement escreve em CERTIFICATES, não aqui — por isso
--     express_reacceptance faz INSERT direto no ledger, não chama aquele RPC.)
--   * offboard_reason_categories: colunas code/label_pt/label_en/label_es/
--     description_pt/is_volunteer_fault/preserves_return_eligibility/sort_order/
--     is_active. (A §5/§9.5 propôs (code,label,description) — corrigido aqui.)
--     'reacceptance_refusal'/'reacceptance_lapse' confirmados AUSENTES.
--   * offboard_member / admin_offboard_member: ambos exigem auth.uid(); o shim
--     offboard_member hardcoda reason_category='other' (NÃO 'administrative', a
--     §9.5 errou o literal — o ponto permanece: precisa de helper no-auth).
--     => _reacceptance_disengage é NOVO, SECDEF, SEM auth.uid(), chamável por cron.
--   * validate_status_transition: active->inactive é PERMITIDO (só bloqueia
--     candidate-edges e alumni->active). engagements.status 'suspended' É CHECK-
--     válido E setado pelo cron de expiração (jobid 18) => SSOT do 'suspenso' do
--     re-aceite vive em obligation.state, NUNCA espelhado em engagements.status.
--   * anonimização: jobid 17 anonymize_by_engagement_kind (persons->legacy_member_id)
--     + jobid 15 anonymize_inactive_members (member_id) tocam MEMBROS => recebem o
--     guard de preservação de licença. jobid 71 anonymize_premember_applications
--     opera em pré-membros (sem member_document_signatures) => guard não se aplica.
--   * invariantes: 41 (0 violações). Esta PR NÃO adiciona invariante (o contrato de
--     preservação de licença é coberto por contract test, per §5); fica em 41.
-- =====================================================================

-- =====================================================================
-- 1. TABELAS — member_reacceptance_obligations + reacceptance_objections.
--    FK circular resolvida (§9.5): cria obligations SEM objection_id, depois
--    objections (FK->obligations), depois ALTER obligations ADD objection_id.
-- =====================================================================

CREATE TABLE IF NOT EXISTS public.member_reacceptance_obligations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  member_id uuid NOT NULL REFERENCES public.members(id),
  document_id uuid NOT NULL REFERENCES public.governance_documents(id),
  from_version_id uuid REFERENCES public.document_versions(id),   -- versão que o membro tinha assinado (nullable)
  to_version_id uuid NOT NULL REFERENCES public.document_versions(id),  -- nova versão material a re-aceitar
  change_class text NOT NULL DEFAULT 'material',  -- registro (open só abre p/ material)
  -- Ancoragem de prazos (§9.5): TODOS computados em RPC no INSERT (add_business_days
  -- é STABLE => proibido em DEFAULT/GENERATED). NUNCA ancorar em notified_at.
  notified_at timestamptz,                  -- quando o aviso-30d foi rascunhado (open)
  effective_from timestamptz,               -- = notified_at + 30 corridos (vigência)
  window_opens_at timestamptz,              -- = effective_from
  window_closes_at timestamptz,             -- = add_business_days(effective_from, 15)
  suspended_until timestamptz,              -- = window_closes_at + 30 corridos
  state text NOT NULL DEFAULT 'notified'
    CHECK (state IN (
      -- (review: 'pending_notification' removido — era estado morto: open() insere 'notified'
      --  direto, nenhum caminho o criava, e ele bloqueava re-fanout via o índice parcial.)
      'notified',              -- aviso-30d rascunhado; aguardando vigência (estado inicial via open)
      'in_window',             -- vigência atingida; janela 15 úteis aberta
      'objection_pending',     -- objeção registrada; CASCATA CONGELADA
      'accommodation_window',  -- acomodação mediada 5 úteis (15.4.3(c))
      'suspended',             -- janela fechou sem re-aceite; +30d p/ re-aceite tardio (15.3(c))
      're_accepted',           -- terminal: membro re-aceitou (INSERT no ledger)
      'refused',               -- terminal: recusa expressa (15.3(e))
      'lapsed_disengaged',     -- terminal: lapso da suspensão -> desligamento (15.3(d))
      'superseded'             -- terminal: objeção acolhida -> doc recirculado (15.4.3(a))
    )),
  signature_id uuid REFERENCES public.member_document_signatures(id),  -- preenchido no re-aceite
  license_preservation_noted boolean NOT NULL DEFAULT false,
  resolved_at timestamptz,
  resolution text CHECK (resolution IS NULL OR resolution IN
    ('re_accepted','refused','lapsed','objection_accepted_recirculated')),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE public.member_reacceptance_obligations IS
  '#976 Camada 5 PR-4 (WA1): máquina de estados de re-aceite por (membro,documento,versão-material). '
  'SSOT do estado "suspenso" do re-aceite (NÃO espelhar em engagements.status — já usado pelo cron de expiração). '
  'Prazos ancorados em effective_from (= notified_at + 30 corridos), nunca em notified_at (§9.5). DORMENTE: '
  'só é populada por open_reacceptance_obligations (OUTWARD-gated #334).';
COMMENT ON COLUMN public.member_reacceptance_obligations.notified_at IS
  '#976 PR-4: timestamp de disparo do aviso-30d (in-app, síncrono no open). O email é entregue por jobid 9 '
  '(send-notification-emails, assíncrono); para membros que dependem só de email o pré-aviso efetivo pode ser '
  'marginalmente inferior a 30 dias corridos — manter o jobid 9 em cadência ≤ diária mitiga (review legal LOW).';

CREATE TABLE IF NOT EXISTS public.reacceptance_objections (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  obligation_id uuid NOT NULL REFERENCES public.member_reacceptance_obligations(id),
  member_id uuid NOT NULL REFERENCES public.members(id),
  body text NOT NULL,
  contested_points text,
  suggested_text text,
  registered_at timestamptz NOT NULL DEFAULT now(),
  committee_due_at timestamptz NOT NULL,    -- = add_business_days(registered_at, 10) (§9.5, computado no RPC)
  committee_decision text CHECK (committee_decision IS NULL OR committee_decision IN ('accepted','rejected','accommodation')),
  committee_responded_at timestamptz,
  committee_responder_id uuid REFERENCES public.members(id),
  minutes_ref text,
  accommodation_window_closes_at timestamptz,  -- = add_business_days(responded_at, 5) (set on accommodation)
  recirculated_chain_id uuid REFERENCES public.approval_chains(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE public.reacceptance_objections IS
  '#976 Camada 5 PR-4 (WA1): objeção fundamentada (Termo 15.4.3). Comitê responde em 10 úteis '
  '(accepted->recircula / rejected->ata+retoma cascata / accommodation->janela 5 úteis). Congela a '
  'cascata da obrigação enquanto objection_pending.';

-- FK circular: obligation aponta para a objeção ativa (criada após a tabela existir).
ALTER TABLE public.member_reacceptance_obligations
  ADD COLUMN IF NOT EXISTS objection_id uuid REFERENCES public.reacceptance_objections(id) ON DELETE SET NULL;

-- =====================================================================
-- 2. ÍNDICES — sweeps do cron por estado+prazo; leitura por membro; 1 obrigação
--    ativa por (membro,doc,versão-alvo) (impede double fan-out, idempotência do open).
-- =====================================================================
CREATE UNIQUE INDEX IF NOT EXISTS mro_active_unique
  ON public.member_reacceptance_obligations(member_id, document_id, to_version_id)
  WHERE state IN ('notified','in_window','objection_pending','accommodation_window','suspended');
CREATE INDEX IF NOT EXISTS mro_notified_effective ON public.member_reacceptance_obligations(state, effective_from)
  WHERE state = 'notified';
CREATE INDEX IF NOT EXISTS mro_inwindow_close ON public.member_reacceptance_obligations(state, window_closes_at)
  WHERE state = 'in_window';
CREATE INDEX IF NOT EXISTS mro_suspended_until ON public.member_reacceptance_obligations(state, suspended_until)
  WHERE state = 'suspended';
CREATE INDEX IF NOT EXISTS mro_member ON public.member_reacceptance_obligations(member_id);
CREATE INDEX IF NOT EXISTS mro_document ON public.member_reacceptance_obligations(document_id);
CREATE INDEX IF NOT EXISTS ro_obligation ON public.reacceptance_objections(obligation_id);
CREATE INDEX IF NOT EXISTS ro_pending_due ON public.reacceptance_objections(committee_due_at)
  WHERE committee_decision IS NULL;

-- =====================================================================
-- 3. RLS (GC-162) — member-scoped read + admin (manage_member). Escritas SÓ via
--    SECDEF RPCs (sem policy de INSERT/UPDATE/DELETE => default-deny p/ PostgREST).
-- =====================================================================
ALTER TABLE public.member_reacceptance_obligations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.reacceptance_objections ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS mro_read_self_or_admin ON public.member_reacceptance_obligations;
CREATE POLICY mro_read_self_or_admin ON public.member_reacceptance_obligations
  FOR SELECT TO authenticated
  USING (
    member_id IN (SELECT m.id FROM public.members m WHERE m.auth_id = (SELECT auth.uid()))
    OR EXISTS (SELECT 1 FROM public.members m WHERE m.auth_id = (SELECT auth.uid())
               AND public.can_by_member(m.id, 'manage_member'))
  );

DROP POLICY IF EXISTS ro_read_self_or_admin ON public.reacceptance_objections;
CREATE POLICY ro_read_self_or_admin ON public.reacceptance_objections
  FOR SELECT TO authenticated
  USING (
    member_id IN (SELECT m.id FROM public.members m WHERE m.auth_id = (SELECT auth.uid()))
    OR EXISTS (SELECT 1 FROM public.members m WHERE m.auth_id = (SELECT auth.uid())
               AND public.can_by_member(m.id, 'manage_member'))
  );

GRANT SELECT ON public.member_reacceptance_obligations TO authenticated;
GRANT SELECT ON public.reacceptance_objections TO authenticated;

-- =====================================================================
-- 4. offboard_reason_categories — categorias de saída por re-aceite. Ambas
--    preservam elegibilidade de retorno e licenças (15.4.5); is_volunteer_fault=false.
-- =====================================================================
INSERT INTO public.offboard_reason_categories
  (code, label_pt, label_en, label_es, description_pt, is_volunteer_fault, preserves_return_eligibility, sort_order, is_active)
VALUES
  ('reacceptance_refusal', 'Recusa de re-aceite', 'Re-acceptance refusal', 'Rechazo de re-aceptación',
   'Termo 15.3(e): recusa expressa de re-aceitar mudança material de instrumento. Licenças preservadas per 15.4.5.',
   false, true, 80, true),
  ('reacceptance_lapse', 'Lapso de re-aceite', 'Re-acceptance lapse', 'Caducidad de re-aceptación',
   'Termo 15.3(c)/(d): não re-aceite dentro da janela + período de suspensão. Licenças preservadas per 15.4.5.',
   false, true, 81, true)
ON CONFLICT (code) DO NOTHING;

-- =====================================================================
-- 5. _reacceptance_disengage — desligamento SEM auth.uid() (cron + refuse_reacceptance).
--    NÃO é o shim offboard_member (hardcoda reason + exige JWT). Replica a mecânica
--    de admin_offboard_member (status/role/engagements/onboarding) sem o gate de auth.
--    PRESERVA member_document_signatures (licenças, 15.4.5) — nunca as toca. Terminal
--    = 'inactive' reversível (§7 Q6). REVOKE total (interno).
-- =====================================================================
CREATE OR REPLACE FUNCTION public._reacceptance_disengage(
  p_member_id uuid,
  p_reason_category text,
  p_preserve_licenses boolean DEFAULT true
)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_member record;
  v_prev_status text;
  v_engagements_closed int := 0;
  v_status_flipped boolean := false;
BEGIN
  -- review (security LOW): preservation is unconditional by design (15.4.5). The parameter is
  -- spec-mandated (_reacceptance_disengage(member,reason,preserve)) but false is not a supported
  -- mode — fail loud instead of silently no-op'ing a caller who expected licenses cleared.
  IF NOT p_preserve_licenses THEN
    RAISE EXCEPTION 'p_preserve_licenses=false nao e suportado: Termo 15.4.5 exige preservacao incondicional das licencas no desligamento por re-aceite'
      USING ERRCODE = 'feature_not_supported';
  END IF;

  SELECT m.id, m.name, m.member_status, m.operational_role, m.person_id, m.designations
    INTO v_member
  FROM public.members m WHERE m.id = p_member_id;
  -- review (data-arch MEDIUM): RAISE (not soft-return) so PERFORM callers ABORT the obligation
  -- state transition instead of marking it lapsed/refused while the member stays de-facto active.
  IF v_member.id IS NULL THEN
    RAISE EXCEPTION 'member_not_found for reacceptance_disengage: %', p_member_id USING ERRCODE = 'no_data_found';
  END IF;

  v_prev_status := COALESCE(v_member.member_status, 'active');

  -- Flip status only from active-ish reversible states (idempotent if already terminal).
  -- active->inactive is an allowed ARM-9 edge (validate_status_transition, grounded live).
  IF v_prev_status IN ('active','observer') THEN
    PERFORM public.validate_status_transition(v_prev_status, 'inactive');  -- IMMUTABLE, no auth
    UPDATE public.members SET
      member_status        = 'inactive',
      operational_role     = 'none',
      is_active            = false,
      designations         = '{}'::text[],
      offboarded_at        = now(),
      offboarded_by        = NULL,           -- system/cron action, no human actor
      status_changed_at    = now(),
      status_change_reason = p_reason_category,
      updated_at           = now()
    WHERE id = p_member_id;
    v_status_flipped := true;
  END IF;

  -- Close active engagements (mirror admin_offboard_member, but revoked_by=NULL).
  IF v_member.person_id IS NOT NULL THEN
    UPDATE public.engagements SET
      status = 'offboarded', end_date = CURRENT_DATE,
      revoked_at = now(), revoked_by = NULL,
      revoke_reason = p_reason_category, updated_at = now()
    WHERE person_id = v_member.person_id AND status = 'active';
    GET DIAGNOSTICS v_engagements_closed = ROW_COUNT;
  END IF;

  -- Auto-skip any open volunteer_term onboarding step (idempotent).
  UPDATE public.onboarding_progress SET
    status = 'skipped', completed_at = now(), updated_at = now(),
    metadata = COALESCE(metadata, '{}'::jsonb) || jsonb_build_object(
      'completed_via', '976_pr4_reacceptance_disengage', 'reason', p_reason_category)
  WHERE member_id = p_member_id AND step_key = 'volunteer_term' AND status = 'pending';

  -- LICENSE PRESERVATION (15.4.5): member_document_signatures is deliberately NOT touched.
  -- The long-term guard lives in the anonymization crons (section 14).

  -- review (senior-eng MEDIUM): notify the member of the adverse decision at the moment it occurs
  -- (15.3(d)/(e)). The cron-driven lapse is otherwise silent; the email is queued via jobid 9.
  PERFORM public.create_notification(
    p_member_id, 'governance_reacceptance_disengaged',
    'Participacao no Nucleo IA & GP encerrada',
    CASE p_reason_category
      WHEN 'reacceptance_refusal' THEN 'Sua participacao foi encerrada conforme sua recusa expressa de re-aceitar a mudanca material do instrumento (Termo 15.3(e)).'
      ELSE 'Sua participacao foi encerrada por nao re-aceite dentro do prazo apos a suspensao (Termo 15.3(d)).'
    END || ' Suas licencas de propriedade intelectual ja concedidas permanecem preservadas (Termo 15.4.5). Se voce acredita que houve erro, entre em contato com o GP.',
    '/governance/reacceptance', 'member', p_member_id);

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes)
  VALUES (NULL, 'member.reacceptance_disengaged', 'member', p_member_id,
    jsonb_build_object(
      'reason_category', p_reason_category,
      'preserve_licenses', p_preserve_licenses,
      'previous_status', v_prev_status,
      'status_flipped', v_status_flipped,
      'engagements_closed', v_engagements_closed,
      'legal_basis', 'Termo 15.3(d)/(e) + 15.4.5 (licenças preservadas)',
      'source', 'reacceptance_state_machine'));

  RETURN jsonb_build_object(
    'success', true, 'member_id', p_member_id, 'previous_status', v_prev_status,
    'status_flipped', v_status_flipped, 'engagements_closed', v_engagements_closed,
    'licenses_preserved', p_preserve_licenses);
END;
$function$;
REVOKE EXECUTE ON FUNCTION public._reacceptance_disengage(uuid, text, boolean) FROM PUBLIC, anon, authenticated;

-- =====================================================================
-- 6. open_reacceptance_obligations — fan-out (OUTWARD-gated #334). manage_platform.
--    Só p/ to_version material (change_class='material'); editorial/unclassified =>
--    nenhuma obrigação (aceite tácito, 15.4.4). Alvo = signatários com is_current
--    (NUNCA members.is_active => não pega guests pré-onboarding, §9.5/GR-1). Prazos
--    computados explicitamente. p_dry_run=true por DEFAULT (safety do dispatch gated).
-- =====================================================================
CREATE OR REPLACE FUNCTION public.open_reacceptance_obligations(
  p_document_id uuid,
  p_to_version_id uuid,
  p_dry_run boolean DEFAULT true
)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller record;
  v_version record;
  v_doc record;
  v_notified timestamptz := now();
  v_effective timestamptz;
  v_window_close timestamptz;
  v_suspended timestamptz;
  v_target record;
  v_created int := 0;
  v_skipped int := 0;
  v_duplicates int := 0;
  v_has_active boolean;
  v_targets jsonb := '[]'::jsonb;
  v_obl_id uuid;
BEGIN
  SELECT m.id INTO v_caller FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_caller.id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF NOT public.can_by_member(v_caller.id, 'manage_platform') THEN
    RAISE EXCEPTION 'Access denied: manage_platform required' USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT dv.id, dv.document_id, dv.version_label, dv.change_class, dv.locked_at, dv.summary_pt
    INTO v_version
  FROM public.document_versions dv WHERE dv.id = p_to_version_id;
  IF v_version.id IS NULL THEN
    RAISE EXCEPTION 'document_version not found (id=%)', p_to_version_id USING ERRCODE = 'no_data_found';
  END IF;
  IF v_version.document_id <> p_document_id THEN
    RAISE EXCEPTION 'version % does not belong to document %', p_to_version_id, p_document_id USING ERRCODE = 'check_violation';
  END IF;
  IF v_version.locked_at IS NULL THEN
    RAISE EXCEPTION 'to_version must be locked before opening re-acceptance obligations' USING ERRCODE = 'check_violation';
  END IF;
  -- change_class IS NULL => non-material fail-safe (PR-1 forward contract); editorial => tácito.
  IF v_version.change_class IS DISTINCT FROM 'material' THEN
    RETURN jsonb_build_object(
      'opened', false,
      'reason', CASE WHEN v_version.change_class IS NULL THEN 'unclassified_treated_non_material' ELSE 'editorial_no_obligation' END,
      'note', 'Apenas mudanças MATERIAIS abrem obrigação de re-aceite (15.4.4). Editorial usa o caminho de ciência (notify_editorial_change_awareness).',
      'change_class', v_version.change_class);
  END IF;

  SELECT gd.id, gd.title INTO v_doc FROM public.governance_documents gd WHERE gd.id = p_document_id;

  -- Anchors (§9.5): NUNCA em notified_at. window em úteis (calendário GO).
  v_effective    := v_notified + INTERVAL '30 days';
  v_window_close := public.add_business_days(v_effective, 15);
  v_suspended    := v_window_close + INTERVAL '30 days';

  FOR v_target IN
    SELECT m.id AS member_id, m.name, m.organization_id, mds.signed_version_id AS from_version_id
    FROM public.members m
    JOIN public.member_document_signatures mds
      ON mds.member_id = m.id AND mds.document_id = p_document_id AND mds.is_current = true
    WHERE mds.signed_version_id IS DISTINCT FROM p_to_version_id   -- já aceitou a nova => skip
  LOOP
    IF v_target.organization_id IS NULL THEN
      v_skipped := v_skipped + 1;
      CONTINUE;
    END IF;

    -- review (data-arch/security LOW): pre-check an existing active obligation so BOTH the dry-run
    -- preview and the real-run accounting separate net-new from already-obligated members. The
    -- ON CONFLICT below stays only as a concurrency backstop (two GP open() calls racing).
    SELECT EXISTS (
      SELECT 1 FROM public.member_reacceptance_obligations o
      WHERE o.member_id = v_target.member_id AND o.document_id = p_document_id
        AND o.to_version_id = p_to_version_id
        AND o.state IN ('notified','in_window','objection_pending','accommodation_window','suspended')
    ) INTO v_has_active;
    IF v_has_active THEN
      v_duplicates := v_duplicates + 1;
      CONTINUE;
    END IF;

    v_obl_id := NULL;  -- reset per iteration: ON CONFLICT DO NOTHING leaves RETURNING-target UNCHANGED, not NULL
    IF NOT p_dry_run THEN
      INSERT INTO public.member_reacceptance_obligations (
        organization_id, member_id, document_id, from_version_id, to_version_id, change_class,
        notified_at, effective_from, window_opens_at, window_closes_at, suspended_until, state)
      VALUES (
        v_target.organization_id, v_target.member_id, p_document_id, v_target.from_version_id, p_to_version_id, 'material',
        v_notified, v_effective, v_effective, v_window_close, v_suspended, 'notified')
      ON CONFLICT (member_id, document_id, to_version_id)
        WHERE state IN ('notified','in_window','objection_pending','accommodation_window','suspended')
        DO NOTHING
      RETURNING id INTO v_obl_id;

      IF v_obl_id IS NOT NULL THEN
        -- Aviso-30d (in-app; o email-cron jobid 9 entrega). Disclosure do calendário.
        PERFORM public.create_notification(
          v_target.member_id, 'governance_reacceptance_required',
          v_doc.title || ' ' || COALESCE(v_version.version_label,'') || ' — re-aceite necessario',
          'O instrumento "' || v_doc.title || '" recebeu uma mudanca MATERIAL (versao ' ||
            COALESCE(v_version.version_label,'') || '), com vigencia a partir de ' ||
            to_char(v_effective, 'DD/MM/YYYY') || '. ' ||
            COALESCE('Resumo: ' || v_version.summary_pt || '. ', '') ||
            'Voce tem ate ' || to_char(v_window_close, 'DD/MM/YYYY') ||
            ' (15 dias uteis pelo calendario de Goias) para re-aceitar. Apos esse prazo, sua participacao fica suspensa por 30 dias; o nao re-aceite ate ' ||
            to_char(v_suspended, 'DD/MM/YYYY') || ' implica desligamento (Termo 15.3). Voce pode tambem objetar de forma fundamentada (15.4.3) ou recusar expressamente (15.3(e)).',
          '/governance/reacceptance', 'governance_document', p_document_id);
        v_created := v_created + 1;
        v_targets := v_targets || jsonb_build_object(
          'member_id', v_target.member_id, 'name', v_target.name, 'from_version_id', v_target.from_version_id);
      ELSE
        v_duplicates := v_duplicates + 1;  -- lost the race: a concurrent open() already inserted it
      END IF;
    ELSE
      -- dry-run: this member would receive a net-new obligation
      v_targets := v_targets || jsonb_build_object(
        'member_id', v_target.member_id, 'name', v_target.name, 'from_version_id', v_target.from_version_id);
    END IF;
  END LOOP;

  IF NOT p_dry_run THEN
    INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes)
    VALUES (v_caller.id, 'reacceptance.obligations_opened', 'governance_document', p_document_id,
      jsonb_build_object('to_version_id', p_to_version_id, 'created', v_created, 'skipped', v_skipped,
        'duplicates_skipped', v_duplicates,
        'effective_from', v_effective, 'window_closes_at', v_window_close, 'suspended_until', v_suspended,
        'legal_basis', 'Termo 15.3 / Politica 12.2.1'));
  END IF;

  RETURN jsonb_build_object(
    'opened', NOT p_dry_run, 'dry_run', p_dry_run, 'document_id', p_document_id, 'to_version_id', p_to_version_id,
    'created', v_created, 'skipped', v_skipped, 'duplicates_skipped', v_duplicates, 'target_count', jsonb_array_length(v_targets),
    'effective_from', v_effective, 'window_closes_at', v_window_close, 'suspended_until', v_suspended,
    'targets', v_targets);
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.open_reacceptance_obligations(uuid, uuid, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.open_reacceptance_obligations(uuid, uuid, boolean) TO authenticated, service_role;

-- =====================================================================
-- 7. notify_editorial_change_awareness — caminho de CIÊNCIA p/ editorial (15d
--    corridos, Política 12.3 / Termo 15.2): notifica signatários SEM abrir obrigação
--    (aceite tácito art. 111 CC). OUTWARD-gated (manage_platform). dry_run default.
-- =====================================================================
CREATE OR REPLACE FUNCTION public.notify_editorial_change_awareness(
  p_document_id uuid,
  p_to_version_id uuid,
  p_dry_run boolean DEFAULT true
)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller record; v_version record; v_doc record; v_target record;
  v_notified int := 0;
BEGIN
  SELECT m.id INTO v_caller FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_caller.id IS NULL THEN RAISE EXCEPTION 'Not authenticated' USING ERRCODE = 'insufficient_privilege'; END IF;
  IF NOT public.can_by_member(v_caller.id, 'manage_platform') THEN
    RAISE EXCEPTION 'Access denied: manage_platform required' USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT dv.id, dv.document_id, dv.version_label, dv.change_class, dv.summary_pt, dv.locked_at INTO v_version
  FROM public.document_versions dv WHERE dv.id = p_to_version_id;
  IF v_version.id IS NULL OR v_version.document_id <> p_document_id THEN
    RAISE EXCEPTION 'version not found or mismatched document' USING ERRCODE = 'no_data_found';
  END IF;
  -- review (data-arch MEDIUM): mirror open()'s lock guard — ciência só sobre texto FINAL (Política 12.3
  -- / Termo 15.2 ancoram a ciência na versão lacrada; disparar sobre draft corromperia a timeline).
  IF v_version.locked_at IS NULL THEN
    RAISE EXCEPTION 'to_version must be locked before notifying editorial awareness (Politica 12.3 exige texto final)' USING ERRCODE = 'check_violation';
  END IF;
  -- Este caminho é SÓ para editorial; material usa open_reacceptance_obligations.
  IF v_version.change_class IS DISTINCT FROM 'editorial' THEN
    RETURN jsonb_build_object('notified', false, 'reason', 'not_editorial',
      'note', 'Mudanca material exige re-aceite (open_reacceptance_obligations), nao ciencia tacita.',
      'change_class', v_version.change_class);
  END IF;

  SELECT gd.title INTO v_doc FROM public.governance_documents gd WHERE gd.id = p_document_id;

  IF NOT p_dry_run THEN
    FOR v_target IN
      SELECT DISTINCT m.id AS member_id FROM public.members m
      JOIN public.member_document_signatures mds
        ON mds.member_id = m.id AND mds.document_id = p_document_id AND mds.is_current = true
    LOOP
      PERFORM public.create_notification(
        v_target.member_id, 'governance_editorial_awareness',
        v_doc.title || ' ' || COALESCE(v_version.version_label,'') || ' — atualizacao editorial',
        'O instrumento "' || v_doc.title || '" recebeu uma atualizacao EDITORIAL (versao ' ||
          COALESCE(v_version.version_label,'') || '). ' || COALESCE('Resumo: ' || v_version.summary_pt || '. ', '') ||
          'Mudancas editoriais nao exigem re-aceite (aceite tacito, art. 111 CC). Esta mensagem e um aviso de transparencia; nenhuma acao e necessaria. Prazo de ciencia: 15 dias.',
        '/governance/documents', 'governance_document', p_document_id);
      v_notified := v_notified + 1;
    END LOOP;
    INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes)
    VALUES (v_caller.id, 'reacceptance.editorial_awareness_notified', 'governance_document', p_document_id,
      jsonb_build_object('to_version_id', p_to_version_id, 'notified', v_notified));
  END IF;

  RETURN jsonb_build_object('notified', NOT p_dry_run, 'dry_run', p_dry_run, 'count', v_notified,
    'change_class', v_version.change_class);
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.notify_editorial_change_awareness(uuid, uuid, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.notify_editorial_change_awareness(uuid, uuid, boolean) TO authenticated, service_role;

-- =====================================================================
-- 8. express_reacceptance — membro re-aceita. INSERT no ledger (auto-supersede via
--    trigger). Permitido in_window/suspended (tardio 15.3(c))/accommodation_window.
--    SELECT FOR UPDATE (race com o cron, §9.5).
-- =====================================================================
CREATE OR REPLACE FUNCTION public.express_reacceptance(p_obligation_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_member record; v_ob record; v_sig_id uuid;
BEGIN
  SELECT m.id INTO v_member FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_member.id IS NULL THEN RAISE EXCEPTION 'Not authenticated' USING ERRCODE = 'insufficient_privilege'; END IF;

  SELECT * INTO v_ob FROM public.member_reacceptance_obligations WHERE id = p_obligation_id FOR UPDATE;
  IF v_ob.id IS NULL THEN RAISE EXCEPTION 'obligation not found' USING ERRCODE = 'no_data_found'; END IF;
  IF v_ob.member_id <> v_member.id THEN RAISE EXCEPTION 'not your obligation' USING ERRCODE = 'insufficient_privilege'; END IF;
  IF v_ob.state NOT IN ('in_window','suspended','accommodation_window') THEN
    RETURN jsonb_build_object('success', false, 'error', 'state_not_acceptable', 'state', v_ob.state,
      'note', 'Re-aceite permitido apenas na janela aberta, na suspensao (tardio) ou na acomodacao.');
  END IF;

  -- review (data-arch): approval_chain_id/signoff_id/certificate_id confirmados NULLABLE (sem default)
  -- ao vivo este turno — NULLs explícitos auto-documentam a intenção e tornam qualquer NOT NULL futuro
  -- um erro de constraint imediato e atribuível, não uma falha silenciosa no primeiro re-aceite real.
  INSERT INTO public.member_document_signatures
    (member_id, document_id, signed_version_id, approval_chain_id, signoff_id, certificate_id, signed_at, is_current)
  VALUES (v_member.id, v_ob.document_id, v_ob.to_version_id, NULL, NULL, NULL, now(), true)
  RETURNING id INTO v_sig_id;

  UPDATE public.member_reacceptance_obligations SET
    state = 're_accepted', signature_id = v_sig_id, resolved_at = now(),
    resolution = 're_accepted', updated_at = now()
  WHERE id = p_obligation_id;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes)
  VALUES (v_member.id, 'reacceptance.expressed', 'member_reacceptance_obligation', p_obligation_id,
    jsonb_build_object('document_id', v_ob.document_id, 'to_version_id', v_ob.to_version_id, 'signature_id', v_sig_id));

  RETURN jsonb_build_object('success', true, 'signature_id', v_sig_id, 'to_version_id', v_ob.to_version_id);
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.express_reacceptance(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.express_reacceptance(uuid) TO authenticated, service_role;

-- =====================================================================
-- 9. register_reacceptance_objection — objeção fundamentada (15.4.3). Congela a
--    cascata (state=objection_pending). committee_due_at = add_business_days(now,10).
-- =====================================================================
CREATE OR REPLACE FUNCTION public.register_reacceptance_objection(
  p_obligation_id uuid,
  p_body text,
  p_contested_points text DEFAULT NULL,
  p_suggested_text text DEFAULT NULL
)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_member record; v_ob record; v_obj_id uuid;
BEGIN
  SELECT m.id INTO v_member FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_member.id IS NULL THEN RAISE EXCEPTION 'Not authenticated' USING ERRCODE = 'insufficient_privilege'; END IF;
  IF p_body IS NULL OR length(trim(p_body)) = 0 THEN
    RAISE EXCEPTION 'objection body is required (15.4.3 exige fundamentacao)' USING ERRCODE = 'invalid_parameter_value';
  END IF;

  SELECT * INTO v_ob FROM public.member_reacceptance_obligations WHERE id = p_obligation_id FOR UPDATE;
  IF v_ob.id IS NULL THEN RAISE EXCEPTION 'obligation not found' USING ERRCODE = 'no_data_found'; END IF;
  IF v_ob.member_id <> v_member.id THEN RAISE EXCEPTION 'not your obligation' USING ERRCODE = 'insufficient_privilege'; END IF;
  IF v_ob.state NOT IN ('in_window','suspended') THEN
    RETURN jsonb_build_object('success', false, 'error', 'state_not_objectable', 'state', v_ob.state);
  END IF;

  INSERT INTO public.reacceptance_objections (
    organization_id, obligation_id, member_id, body, contested_points, suggested_text,
    registered_at, committee_due_at)
  VALUES (
    v_ob.organization_id, p_obligation_id, v_member.id, p_body, p_contested_points, p_suggested_text,
    now(), public.add_business_days(now(), 10))
  RETURNING id INTO v_obj_id;

  UPDATE public.member_reacceptance_obligations SET
    state = 'objection_pending', objection_id = v_obj_id, updated_at = now()
  WHERE id = p_obligation_id;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes)
  VALUES (v_member.id, 'reacceptance.objection_registered', 'member_reacceptance_obligation', p_obligation_id,
    jsonb_build_object('objection_id', v_obj_id, 'committee_due_at', public.add_business_days(now(), 10)));

  RETURN jsonb_build_object('success', true, 'objection_id', v_obj_id,
    'committee_due_at', public.add_business_days(now(), 10), 'note', 'Cascata congelada ate a decisao do Comite.');
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.register_reacceptance_objection(uuid, text, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.register_reacceptance_objection(uuid, text, text, text) TO authenticated, service_role;

-- =====================================================================
-- 10. respond_reacceptance_objection — Comitê responde (gate manage_platform até
--     §7.1 definir o roster). accepted->supersede (recircula, reinicia 15.3) /
--     rejected->ata + retoma cascata com prazos estendidos pelo atraso do Comitê /
--     accommodation->janela 5 úteis. Resposta tardia auto-estende a janela do membro.
-- =====================================================================
CREATE OR REPLACE FUNCTION public.respond_reacceptance_objection(
  p_objection_id uuid,
  p_decision text,
  p_minutes_ref text DEFAULT NULL
)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller record; v_obj record; v_ob record;
  v_now timestamptz := now();
  v_delay interval;
  v_new_window timestamptz; v_new_suspended timestamptz; v_new_state text;
  v_accom timestamptz;
BEGIN
  SELECT m.id INTO v_caller FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_caller.id IS NULL THEN RAISE EXCEPTION 'Not authenticated' USING ERRCODE = 'insufficient_privilege'; END IF;
  IF NOT public.can_by_member(v_caller.id, 'manage_platform') THEN
    RAISE EXCEPTION 'Access denied: manage_platform required' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF p_decision NOT IN ('accepted','rejected','accommodation') THEN
    RAISE EXCEPTION 'decision must be accepted|rejected|accommodation' USING ERRCODE = 'invalid_parameter_value';
  END IF;

  SELECT * INTO v_obj FROM public.reacceptance_objections WHERE id = p_objection_id FOR UPDATE;
  IF v_obj.id IS NULL THEN RAISE EXCEPTION 'objection not found' USING ERRCODE = 'no_data_found'; END IF;
  IF v_obj.committee_decision IS NOT NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'already_decided', 'decision', v_obj.committee_decision);
  END IF;

  SELECT * INTO v_ob FROM public.member_reacceptance_obligations WHERE id = v_obj.obligation_id FOR UPDATE;
  IF v_ob.state <> 'objection_pending' THEN
    RETURN jsonb_build_object('success', false, 'error', 'obligation_not_pending', 'state', v_ob.state);
  END IF;

  UPDATE public.reacceptance_objections SET
    committee_decision = p_decision, committee_responded_at = v_now,
    committee_responder_id = v_caller.id, minutes_ref = p_minutes_ref, updated_at = v_now
  WHERE id = p_objection_id;

  IF p_decision = 'accepted' THEN
    -- 15.4.3(a): objeção acolhida => o instrumento será recirculado (re-ratificação
    -- com o texto ajustado). A obrigação atual é SUPERADA; uma nova obrigação será
    -- aberta quando a versão recirculada for ratificada/lacrada (open novamente).
    UPDATE public.member_reacceptance_obligations SET
      state = 'superseded', resolved_at = v_now, resolution = 'objection_accepted_recirculated', updated_at = v_now
    WHERE id = v_ob.id;
    PERFORM public.create_notification(v_ob.member_id, 'governance_reacceptance_objection_accepted',
      'Objecao acolhida', 'O Comite acolheu sua objecao. O GP iniciara a revisao do instrumento e, quando a versao revisada for ratificada, abrira um novo ciclo de re-aceite (aviso-30d + 15 dias uteis) sobre ela; voce sera notificado.',
      '/governance/reacceptance', 'reacceptance_objection', p_objection_id);

  ELSIF p_decision = 'accommodation' THEN
    -- 15.4.3(c): janela de acomodação mediada de 5 úteis.
    v_accom := public.add_business_days(v_now, 5);
    UPDATE public.reacceptance_objections SET accommodation_window_closes_at = v_accom WHERE id = p_objection_id;
    UPDATE public.member_reacceptance_obligations SET state = 'accommodation_window', updated_at = v_now WHERE id = v_ob.id;
    PERFORM public.create_notification(v_ob.member_id, 'governance_reacceptance_accommodation',
      'Acomodacao mediada', 'O Comite propos uma acomodacao. Voce tem ate ' || to_char(v_accom,'DD/MM/YYYY') ||
      ' (5 dias uteis) para re-aceitar o texto acomodado.', '/governance/reacceptance', 'reacceptance_objection', p_objection_id);

  ELSE  -- rejected: retoma cascata; estende prazos pelo atraso do Comitê (resposta tardia auto-estende).
    v_delay := v_now - v_obj.registered_at;  -- duração da deliberação = tempo congelado
    v_new_window := v_ob.window_closes_at + v_delay;
    v_new_suspended := v_ob.suspended_until + v_delay;
    v_new_state := CASE
      WHEN v_now < v_new_window THEN 'in_window'
      WHEN v_now < v_new_suspended THEN 'suspended'
      ELSE 'lapsed' END;
    IF v_new_state = 'lapsed' THEN
      -- o período combinado (objeção + deliberação) esgotou a janela de suspensão => desligamento.
      -- _reacceptance_disengage já notifica o membro (lapso); NÃO enviar a mensagem "retomado" aqui.
      PERFORM public._reacceptance_disengage(v_ob.member_id, 'reacceptance_lapse', true);
      UPDATE public.member_reacceptance_obligations SET
        state = 'lapsed_disengaged', window_closes_at = v_new_window, suspended_until = v_new_suspended,
        resolved_at = v_now, resolution = 'lapsed', license_preservation_noted = true, updated_at = v_now
      WHERE id = v_ob.id;
    ELSE
      UPDATE public.member_reacceptance_obligations SET
        state = v_new_state, window_closes_at = v_new_window, suspended_until = v_new_suspended, updated_at = v_now
      WHERE id = v_ob.id;
      -- review (data-arch HIGH / security MEDIUM): a notificação reflete o estado REAL retomado —
      -- nunca aponta uma data passada como prazo ativo nem mensageia um membro já desligado.
      PERFORM public.create_notification(v_ob.member_id, 'governance_reacceptance_objection_rejected',
        'Objecao nao acolhida',
        'O Comite nao acolheu sua objecao (ata: ' || COALESCE(p_minutes_ref,'-') || '). ' ||
        CASE WHEN v_new_state = 'in_window'
          THEN 'O prazo de re-aceite foi retomado e estendido pelo periodo de deliberacao. Novo prazo: ' || to_char(v_new_window,'DD/MM/YYYY') || '.'
          ELSE 'A janela de re-aceite ja encerrou (em ' || to_char(v_new_window,'DD/MM/YYYY') || '). Voce ainda pode re-aceitar tardiamente ate ' || to_char(v_new_suspended,'DD/MM/YYYY') || ' (Termo 15.3(c)); apos esse prazo, ha desligamento.'
        END,
        '/governance/reacceptance', 'reacceptance_objection', p_objection_id);
    END IF;
  END IF;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes)
  VALUES (v_caller.id, 'reacceptance.objection_responded', 'reacceptance_objection', p_objection_id,
    jsonb_strip_nulls(jsonb_build_object('decision', p_decision, 'obligation_id', v_ob.id, 'minutes_ref', p_minutes_ref,
      -- review (legal HIGH): aceitar a objeção NÃO recircula automaticamente — força visibilidade do passo manual do GP.
      'action_required_by_gp', CASE WHEN p_decision = 'accepted'
        THEN 'criar draft revisado -> lock_document_version(change_class=material) -> recirculate_governance_doc -> open_reacceptance_obligations(doc, nova versao); depois link_reacceptance_recirculation(objection, chain) p/ fechar o audit trail'
        ELSE NULL END)));

  RETURN jsonb_build_object('success', true, 'decision', p_decision, 'obligation_id', v_ob.id);
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.respond_reacceptance_objection(uuid, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.respond_reacceptance_objection(uuid, text, text) TO authenticated, service_role;

-- 10b. link_reacceptance_recirculation — review (legal HIGH): fecha a trilha de auditoria 15.4.3(a).
--      Após aceitar uma objeção, o GP recircula o instrumento (cria draft revisado -> lock material ->
--      recirculate_governance_doc); este RPC vincula a chain de recirculação resultante à objeção
--      acolhida, para que reacceptance_objections.recirculated_chain_id deixe de ser NULL permanente.
CREATE OR REPLACE FUNCTION public.link_reacceptance_recirculation(p_objection_id uuid, p_chain_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_caller record; v_updated int;
BEGIN
  SELECT m.id INTO v_caller FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_caller.id IS NULL THEN RAISE EXCEPTION 'Not authenticated' USING ERRCODE = 'insufficient_privilege'; END IF;
  IF NOT public.can_by_member(v_caller.id, 'manage_platform') THEN
    RAISE EXCEPTION 'Access denied: manage_platform required' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.approval_chains ac WHERE ac.id = p_chain_id) THEN
    RAISE EXCEPTION 'approval_chain not found (id=%)', p_chain_id USING ERRCODE = 'no_data_found';
  END IF;

  UPDATE public.reacceptance_objections SET recirculated_chain_id = p_chain_id, updated_at = now()
  WHERE id = p_objection_id AND committee_decision = 'accepted';
  GET DIAGNOSTICS v_updated = ROW_COUNT;
  IF v_updated = 0 THEN
    RETURN jsonb_build_object('success', false, 'error', 'objection_not_found_or_not_accepted');
  END IF;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes)
  VALUES (v_caller.id, 'reacceptance.recirculation_linked', 'reacceptance_objection', p_objection_id,
    jsonb_build_object('recirculated_chain_id', p_chain_id));

  RETURN jsonb_build_object('success', true, 'objection_id', p_objection_id, 'recirculated_chain_id', p_chain_id);
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.link_reacceptance_recirculation(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.link_reacceptance_recirculation(uuid, uuid) TO authenticated, service_role;

-- =====================================================================
-- 11. refuse_reacceptance — recusa expressa (15.3(e)). Desligamento IMEDIATO,
--     independente da cascata, licenças preservadas.
-- =====================================================================
CREATE OR REPLACE FUNCTION public.refuse_reacceptance(p_obligation_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_member record; v_ob record; v_disengage jsonb;
BEGIN
  SELECT m.id INTO v_member FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_member.id IS NULL THEN RAISE EXCEPTION 'Not authenticated' USING ERRCODE = 'insufficient_privilege'; END IF;

  SELECT * INTO v_ob FROM public.member_reacceptance_obligations WHERE id = p_obligation_id FOR UPDATE;
  IF v_ob.id IS NULL THEN RAISE EXCEPTION 'obligation not found' USING ERRCODE = 'no_data_found'; END IF;
  IF v_ob.member_id <> v_member.id THEN RAISE EXCEPTION 'not your obligation' USING ERRCODE = 'insufficient_privilege'; END IF;
  IF v_ob.state IN ('re_accepted','refused','lapsed_disengaged','superseded') THEN
    RETURN jsonb_build_object('success', false, 'error', 'already_resolved', 'state', v_ob.state);
  END IF;

  -- review (senior-eng MEDIUM): recusa a partir de objection_pending resolve a objeção pendente,
  -- senão ela fica órfã para sempre no índice ro_pending_due (committee_decision IS NULL) e o Comitê
  -- não sabe que a obrigação já foi encerrada.
  IF v_ob.state = 'objection_pending' AND v_ob.objection_id IS NOT NULL THEN
    UPDATE public.reacceptance_objections SET
      committee_decision = 'rejected', committee_responded_at = now(),
      minutes_ref = COALESCE(minutes_ref, 'Superada por recusa expressa do membro (Termo 15.3(e))'),
      updated_at = now()
    WHERE id = v_ob.objection_id AND committee_decision IS NULL;
  END IF;

  v_disengage := public._reacceptance_disengage(v_member.id, 'reacceptance_refusal', true);

  UPDATE public.member_reacceptance_obligations SET
    state = 'refused', resolved_at = now(), resolution = 'refused',
    license_preservation_noted = true, updated_at = now()
  WHERE id = p_obligation_id;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes)
  VALUES (v_member.id, 'reacceptance.refused', 'member_reacceptance_obligation', p_obligation_id,
    jsonb_build_object('document_id', v_ob.document_id, 'disengage', v_disengage,
      'legal_basis', 'Termo 15.3(e); licencas preservadas 15.4.5'));

  RETURN jsonb_build_object('success', true, 'disengaged', true, 'licenses_preserved', true);
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.refuse_reacceptance(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.refuse_reacceptance(uuid) TO authenticated, service_role;

-- =====================================================================
-- 12. get_my_reacceptance_obligations — leitura self-service p/ a UI (banner/
--     countdown). Member-scoped via auth.uid(); só obrigações abertas do próprio.
-- =====================================================================
CREATE OR REPLACE FUNCTION public.get_my_reacceptance_obligations()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_member record; v_rows jsonb;
BEGIN
  SELECT m.id INTO v_member FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_member.id IS NULL THEN RETURN '[]'::jsonb; END IF;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'obligation_id', o.id, 'document_id', o.document_id, 'document_title', gd.title,
    'to_version_id', o.to_version_id, 'version_label', dv.version_label, 'summary_pt', dv.summary_pt,
    'state', o.state, 'effective_from', o.effective_from, 'window_closes_at', o.window_closes_at,
    'suspended_until', o.suspended_until,
    'accommodation_window_closes_at', obj.accommodation_window_closes_at,
    -- review (senior-eng LOW): durante a acomodação o countdown corre contra a janela de 5 úteis da
    -- objeção, não contra window_closes_at (que já é passado quando há acomodação).
    'business_days_remaining', CASE
      WHEN o.state = 'accommodation_window' AND obj.accommodation_window_closes_at IS NOT NULL AND obj.accommodation_window_closes_at > now()
        THEN public.business_days_between(now(), obj.accommodation_window_closes_at)
      WHEN o.window_closes_at IS NOT NULL AND o.window_closes_at > now()
        THEN public.business_days_between(now(), o.window_closes_at)
      ELSE 0 END,
    'objection_id', o.objection_id
  ) ORDER BY o.window_closes_at), '[]'::jsonb)
  INTO v_rows
  FROM public.member_reacceptance_obligations o
  JOIN public.governance_documents gd ON gd.id = o.document_id
  JOIN public.document_versions dv ON dv.id = o.to_version_id
  LEFT JOIN public.reacceptance_objections obj ON obj.id = o.objection_id
  WHERE o.member_id = v_member.id
    AND o.state IN ('notified','in_window','objection_pending','accommodation_window','suspended');

  RETURN v_rows;
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.get_my_reacceptance_obligations() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_my_reacceptance_obligations() TO authenticated, service_role;

-- =====================================================================
-- 13. reacceptance_lifecycle_sweep_cron — varredura diária idempotente. Transições:
--     notified->in_window (effective_from) / in_window->suspended (window_closes_at) /
--     suspended->lapsed_disengaged (suspended_until, via _reacceptance_disengage) /
--     accommodation expirada -> suspended ou lapsed. objection_pending NÃO avança
--     (cascata congelada). FOR UPDATE nas linhas que disparam desligamento.
-- =====================================================================
CREATE OR REPLACE FUNCTION public.reacceptance_lifecycle_sweep_cron()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_now timestamptz := now();
  v_to_inwindow int := 0;
  v_to_suspended int := 0;
  v_lapsed int := 0;
  v_accom_resolved int := 0;
  v_overdue int := 0;
  v_new_suspended timestamptz;
  v_ob record;
BEGIN
  -- 1. notified -> in_window (vigência atingida). Set-based.
  UPDATE public.member_reacceptance_obligations
    SET state = 'in_window', updated_at = v_now
    WHERE state = 'notified' AND effective_from IS NOT NULL AND effective_from <= v_now;
  GET DIAGNOSTICS v_to_inwindow = ROW_COUNT;

  -- 2. in_window -> suspended (janela fechou). Set-based. (SSOT = obligation.state;
  --    NÃO espelha engagements.status='suspended'.)
  UPDATE public.member_reacceptance_obligations
    SET state = 'suspended', updated_at = v_now
    WHERE state = 'in_window' AND window_closes_at IS NOT NULL AND window_closes_at <= v_now;
  GET DIAGNOSTICS v_to_suspended = ROW_COUNT;

  -- 3. suspended -> lapsed_disengaged (suspensão expirou). Loop (chama disengage/membro).
  FOR v_ob IN
    SELECT id, member_id, suspended_until FROM public.member_reacceptance_obligations
    WHERE state = 'suspended' AND suspended_until IS NOT NULL AND suspended_until <= v_now
    FOR UPDATE
  LOOP
    PERFORM public._reacceptance_disengage(v_ob.member_id, 'reacceptance_lapse', true);
    UPDATE public.member_reacceptance_obligations
      SET state = 'lapsed_disengaged', resolved_at = v_now, resolution = 'lapsed',
          license_preservation_noted = true, updated_at = v_now
      WHERE id = v_ob.id;
    -- review (security LOW / ADR-0013): audit no GRÃO da obrigação (paridade com refuse_reacceptance);
    -- _reacceptance_disengage já registra no grão do membro.
    INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes)
    VALUES (NULL, 'reacceptance.lapsed_disengaged', 'member_reacceptance_obligation', v_ob.id,
      jsonb_build_object('member_id', v_ob.member_id, 'triggered_by', 'cron:reacceptance_lifecycle_sweep',
        'suspended_until', v_ob.suspended_until, 'ran_at', v_now));
    v_lapsed := v_lapsed + 1;
  END LOOP;

  -- 4. accommodation_window expirada sem re-aceite -> retoma a suspensão com o clock RECALCULADO
  --    (§9.5: new suspended_until = accommodation_window_closes_at + (suspended_until_orig − committee_responded_at));
  --    a acomodação é uma PAUSA, não pode encurtar a suspensão. Se já esgotou -> lapsed.
  FOR v_ob IN
    SELECT o.id, o.member_id, o.suspended_until,
           obj.committee_responded_at AS obj_responded_at,
           obj.accommodation_window_closes_at AS obj_accom_closes
    FROM public.member_reacceptance_obligations o
    JOIN public.reacceptance_objections obj ON obj.id = o.objection_id
    WHERE o.state = 'accommodation_window'
      AND obj.accommodation_window_closes_at IS NOT NULL
      AND obj.accommodation_window_closes_at <= v_now
    FOR UPDATE OF o
  LOOP
    -- defensivo: committee_responded_at só é NULL se a linha for inconsistente (não deveria — só
    -- entra em accommodation via respond, que o seta); nesse caso preserva o suspended_until original.
    IF v_ob.obj_responded_at IS NOT NULL AND v_ob.suspended_until IS NOT NULL THEN
      v_new_suspended := v_ob.obj_accom_closes + (v_ob.suspended_until - v_ob.obj_responded_at);
    ELSE
      v_new_suspended := v_ob.suspended_until;
    END IF;

    IF v_new_suspended IS NOT NULL AND v_new_suspended <= v_now THEN
      PERFORM public._reacceptance_disengage(v_ob.member_id, 'reacceptance_lapse', true);
      UPDATE public.member_reacceptance_obligations
        SET state = 'lapsed_disengaged', suspended_until = v_new_suspended, resolved_at = v_now,
            resolution = 'lapsed', license_preservation_noted = true, updated_at = v_now
        WHERE id = v_ob.id;
      INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes)
      VALUES (NULL, 'reacceptance.lapsed_disengaged', 'member_reacceptance_obligation', v_ob.id,
        jsonb_build_object('member_id', v_ob.member_id, 'triggered_by', 'cron:reacceptance_lifecycle_sweep:accommodation_expiry',
          'suspended_until', v_new_suspended, 'ran_at', v_now));
      v_lapsed := v_lapsed + 1;
    ELSE
      UPDATE public.member_reacceptance_obligations
        SET state = 'suspended', suspended_until = v_new_suspended, updated_at = v_now WHERE id = v_ob.id;
    END IF;
    v_accom_resolved := v_accom_resolved + 1;
  END LOOP;

  -- 5. Objeção vencida sem decisão (SLA de 10 úteis do Comitê estourado): log IDEMPOTENTE (guarda de
  --    1 dia) p/ o dashboard do GP. NÃO auto-avança a cascata — objection_pending fica congelado por
  --    design (a extensão de prazo é aplicada em respond quando o Comitê eventualmente decide). (legal MEDIUM)
  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes)
  SELECT NULL, 'reacceptance.committee_overdue', 'reacceptance_objection', obj.id,
    jsonb_build_object('obligation_id', obj.obligation_id, 'member_id', obj.member_id,
      'committee_due_at', obj.committee_due_at,
      'days_overdue', extract(day from v_now - obj.committee_due_at)::int)
  FROM public.reacceptance_objections obj
  WHERE obj.committee_decision IS NULL
    AND obj.committee_due_at < v_now
    AND NOT EXISTS (
      SELECT 1 FROM public.admin_audit_log al
      WHERE al.action = 'reacceptance.committee_overdue'
        AND al.target_id = obj.id
        AND al.created_at > v_now - INTERVAL '1 day');
  GET DIAGNOSTICS v_overdue = ROW_COUNT;

  RETURN jsonb_build_object('ran_at', v_now, 'to_in_window', v_to_inwindow, 'to_suspended', v_to_suspended,
    'lapsed_disengaged', v_lapsed, 'accommodation_resolved', v_accom_resolved, 'committee_overdue_flagged', v_overdue);
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.reacceptance_lifecycle_sweep_cron() FROM PUBLIC, anon, authenticated;

-- Schedule daily 07:15 UTC (after ratification-window-close-daily 07:00). Idempotent by name.
SELECT cron.schedule('reacceptance-lifecycle-sweep-daily', '15 7 * * *',
  $$SELECT public.reacceptance_lifecycle_sweep_cron();$$);

-- =====================================================================
-- 14. LICENSE PRESERVATION GUARD (invariante §4.11 / 15.4.5) — Opção B (§9.1):
--     guard nas crons de anonimização que tocam MEMBROS, pulando quem detém uma
--     member_document_signatures is_current=true (licença viva). Corpos VERBATIM da
--     captura ao vivo + o predicado de guard. anonymize_premember_applications (jobid
--     71) NÃO recebe guard: opera em pré-membros (selection_applications), sem ledger
--     de assinatura por member_id => o guard seria dead-code.
-- =====================================================================

-- 14a. anonymize_by_engagement_kind (jobid 17): guard como skip in-loop + audit de visibilidade ao DPO.
CREATE OR REPLACE FUNCTION public.anonymize_by_engagement_kind(p_dry_run boolean DEFAULT true, p_limit integer DEFAULT 500)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_person record;
  v_count int := 0;
  v_skipped int := 0;
  v_results jsonb := '[]'::jsonb;
  v_errors jsonb := '[]'::jsonb;
  v_strictest_policy text;
BEGIN
  FOR v_person IN
    SELECT
      p.id AS person_id,
      p.name AS person_name,
      p.legacy_member_id,
      CASE
        WHEN bool_or(ek.anonymization_policy = 'retain_for_legal') THEN 'retain_for_legal'
        WHEN bool_or(ek.anonymization_policy = 'anonymize') THEN 'anonymize'
        ELSE 'delete'
      END AS effective_policy,
      max(e.end_date + make_interval(days => COALESCE(ek.retention_days_after_end, 1825))) AS latest_retention_end,
      count(*) AS engagement_count
    FROM public.persons p
    JOIN public.engagements e ON e.person_id = p.id
    JOIN public.engagement_kinds ek ON ek.slug = e.kind
    WHERE p.anonymized_at IS NULL
      AND e.status IN ('offboarded', 'expired')
      AND e.end_date IS NOT NULL
      AND (e.end_date + make_interval(days => COALESCE(ek.retention_days_after_end, 1825))) < CURRENT_DATE
    GROUP BY p.id, p.name, p.legacy_member_id
    HAVING NOT EXISTS (
      SELECT 1 FROM public.engagements e2
      WHERE e2.person_id = p.id AND e2.status IN ('active', 'suspended')
    )
    ORDER BY max(e.end_date) ASC
    LIMIT p_limit
  LOOP
    BEGIN
      v_strictest_policy := v_person.effective_policy;

      -- #976 PR-4 (15.4.5 / §9.1 Opção B): preserva quem detém licença viva (signature is_current).
      -- In-loop skip (não WHERE-exclusion) p/ dar VISIBILIDADE ao DPO (review legal HIGH): registra o
      -- deferimento e sinaliza que requisições LGPD Art.18(IV) desse titular roteiam ao DPO (tradeoff
      -- Art.16(I) base de retenção por licença de PI × Art.18(IV) apagamento). legacy_member_id NULL
      -- (pessoa sem member) => sem ledger possível => segue p/ anonimização normal.
      IF v_person.legacy_member_id IS NOT NULL AND EXISTS (
           SELECT 1 FROM public.member_document_signatures mds
           WHERE mds.member_id = v_person.legacy_member_id AND mds.is_current = true) THEN
        v_skipped := v_skipped + 1;
        IF NOT p_dry_run THEN
          INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes)
          VALUES (NULL, 'lgpd.anonymization_deferred_ip_license', 'member', v_person.legacy_member_id,
            jsonb_build_object('person_id', v_person.person_id,
              'legal_basis', 'LGPD Art. 16(I) — IP license enforcement (Termo 15.4.5)',
              'art18_requests_require_dpo_review', true, 'signature_is_current', true,
              'source', 'cron:anonymize_by_engagement_kind'));
        END IF;
        v_results := v_results || jsonb_build_object(
          'person_id', v_person.person_id, 'action', 'license_preserved', 'reason', 'member_document_signatures is_current'
        );
        CONTINUE;
      END IF;

      IF v_strictest_policy = 'retain_for_legal' THEN
        v_skipped := v_skipped + 1;
        v_results := v_results || jsonb_build_object(
          'person_id', v_person.person_id, 'action', 'retained', 'reason', 'retain_for_legal policy'
        );
        CONTINUE;
      END IF;

      IF NOT p_dry_run THEN
        UPDATE public.persons SET
          name = 'Pessoa Anonimizada #' || SUBSTR(v_person.person_id::text, 1, 8),
          email = 'anon_' || SUBSTR(v_person.person_id::text, 1, 8) || '@removed.local',
          auth_id = NULL, anonymized_at = now()
        WHERE id = v_person.person_id;

        IF v_person.legacy_member_id IS NOT NULL THEN
          UPDATE public.members SET
            name = 'Membro Anonimizado #' || SUBSTR(v_person.legacy_member_id::text, 1, 8),
            email = 'anon_' || SUBSTR(v_person.legacy_member_id::text, 1, 8) || '@removed.local',
            phone = NULL, phone_encrypted = NULL, pmi_id = NULL, pmi_id_encrypted = NULL,
            linkedin_url = NULL, photo_url = NULL, credly_url = NULL, credly_badges = NULL,
            address = NULL, city = NULL, birth_date = NULL, state = NULL, country = NULL,
            signature_url = NULL, secondary_emails = NULL, last_active_pages = NULL,
            auth_id = NULL, secondary_auth_ids = NULL, is_active = false,
            member_status = 'archived', anonymized_at = now(), anonymized_by = NULL, updated_at = now()
          WHERE id = v_person.legacy_member_id;
          DELETE FROM public.notifications WHERE member_id = v_person.legacy_member_id;
          DELETE FROM public.notification_preferences WHERE member_id = v_person.legacy_member_id;
        END IF;

        UPDATE public.engagements SET status = 'anonymized', updated_at = now()
        WHERE person_id = v_person.person_id;

        IF v_strictest_policy = 'delete' THEN
          DELETE FROM public.persons WHERE id = v_person.person_id;
        END IF;

        INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes)
        VALUES (NULL, 'lgpd_v4_anonymization', 'person', v_person.person_id,
          jsonb_build_object(
            'policy', v_strictest_policy, 'engagement_count', v_person.engagement_count,
            'retention_end', v_person.latest_retention_end, 'legacy_member_id', v_person.legacy_member_id,
            'legal_basis', 'LGPD Art. 16 — retention limit per engagement_kind (ADR-0008)',
            'source', 'cron:anonymize_by_engagement_kind'
          ));
      END IF;

      v_count := v_count + 1;
      v_results := v_results || jsonb_build_object(
        'person_id', v_person.person_id, 'action', v_strictest_policy,
        'retention_end', v_person.latest_retention_end, 'engagements', v_person.engagement_count
      );
    EXCEPTION WHEN OTHERS THEN
      v_skipped := v_skipped + 1;
      v_errors := v_errors || jsonb_build_object('person_id', v_person.person_id, 'error', SQLERRM);
    END;
  END LOOP;

  RETURN jsonb_build_object(
    'dry_run', p_dry_run, 'processed', v_count, 'skipped', v_skipped,
    'results', v_results, 'errors', v_errors, 'executed_at', now()
  );
END;
$function$;

-- 14b. anonymize_inactive_members (jobid 15): guard como skip por-candidato no loop.
CREATE OR REPLACE FUNCTION public.anonymize_inactive_members(p_dry_run boolean DEFAULT true, p_years integer DEFAULT 5, p_limit integer DEFAULT 100)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'storage', 'pg_temp'
AS $function$
DECLARE
  v_candidate record;
  v_count int := 0;
  v_skipped int := 0;
  v_license_preserved int := 0;  -- #976 PR-4
  v_ids uuid[] := '{}';
  v_errors jsonb := '[]'::jsonb;
  v_resume_paths text[];
  v_resume_deleted_total int := 0;
  v_resume_deleted_this_loop int := 0;
  v_aff_scrubbed int := 0;  -- #625
BEGIN
  FOR v_candidate IN
    SELECT * FROM public.list_anonymization_candidates(p_years) LIMIT p_limit
  LOOP
    BEGIN
      -- #976 PR-4 (15.4.5 / §9.1 Opção B): preserva quem detém licença viva (signature
      -- is_current). Um voluntário desligado por recusa/lapso de re-aceite mantém suas
      -- licenças; a linha de assinatura (que materializa a licença de PI) não pode ser
      -- anonimizada enquanto a licença vigorar.
      IF EXISTS (SELECT 1 FROM public.member_document_signatures mds
                 WHERE mds.member_id = v_candidate.member_id AND mds.is_current = true) THEN
        v_skipped := v_skipped + 1;
        v_license_preserved := v_license_preserved + 1;
        -- review (legal HIGH): visibilidade ao DPO — o deferimento por licença de PI não é silencioso;
        -- requisições LGPD Art.18(IV) desse titular roteiam ao DPO (Art.16(I) × Art.18(IV)).
        IF NOT p_dry_run THEN
          INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes)
          VALUES (NULL, 'lgpd.anonymization_deferred_ip_license', 'member', v_candidate.member_id,
            jsonb_build_object(
              'legal_basis', 'LGPD Art. 16(I) — IP license enforcement (Termo 15.4.5)',
              'art18_requests_require_dpo_review', true, 'signature_is_current', true,
              'source', 'cron:anonymize_inactive_members'));
        END IF;
        CONTINUE;
      END IF;

      IF NOT p_dry_run THEN
        UPDATE public.members SET
          name = 'Membro Anonimizado #' || SUBSTR(v_candidate.member_id::text, 1, 8),
          email = 'anon_' || SUBSTR(v_candidate.member_id::text, 1, 8) || '@removed.local',
          phone = NULL, phone_encrypted = NULL,
          pmi_id = NULL, pmi_id_encrypted = NULL,
          linkedin_url = NULL, photo_url = NULL,
          credly_url = NULL, credly_badges = NULL,
          address = NULL, city = NULL, birth_date = NULL,
          state = NULL, country = NULL,
          signature_url = NULL, secondary_emails = NULL,
          last_active_pages = NULL, auth_id = NULL, secondary_auth_ids = NULL,
          is_active = false, member_status = 'archived',
          anonymized_at = now(), anonymized_by = NULL,
          updated_at = now()
        WHERE id = v_candidate.member_id;

        UPDATE public.member_offboarding_records SET
          reason_detail = NULL, exit_interview_full_text = NULL,
          return_window_suggestion = NULL, lessons_learned = NULL,
          recommendation_for_future = NULL, attachment_urls = '{}'::text[],
          updated_at = now()
        WHERE member_id = v_candidate.member_id;

        -- BUG FIX: column is `recipient_id`, not `member_id`.
        DELETE FROM public.notifications WHERE recipient_id = v_candidate.member_id;
        DELETE FROM public.notification_preferences WHERE member_id = v_candidate.member_id;

        -- p195 LGPD storage extension: capture resume paths + delete binaries.
        SELECT array_agg(resume_storage_path)
        INTO v_resume_paths
        FROM public.selection_applications
        WHERE email = v_candidate.email
          AND resume_storage_path IS NOT NULL;

        v_resume_deleted_this_loop := 0;
        IF v_resume_paths IS NOT NULL AND array_length(v_resume_paths, 1) > 0 THEN
          DELETE FROM storage.objects
          WHERE bucket_id = 'selection-resumes'
            AND name = ANY(v_resume_paths);
          GET DIAGNOSTICS v_resume_deleted_this_loop = ROW_COUNT;
          v_resume_deleted_total := v_resume_deleted_total + v_resume_deleted_this_loop;
        END IF;

        UPDATE public.selection_applications SET
          applicant_name = 'Candidato Anonimizado',
          email = 'anon@removed.local',
          phone = NULL, linkedin_url = NULL,
          resume_url = NULL,
          resume_storage_path = NULL,  -- p195
          resume_synced_at = NULL,      -- p195
          motivation_letter = NULL
        WHERE email = v_candidate.email;

        -- #625 F1: de-identifica a trilha de verificação de filiação do titular (subject).
        -- A linha de members já foi anonimizada acima (in-place), então member_id/verified_by
        -- de-referenciam para registro neutro; aqui só zera os campos livres/técnicos.
        UPDATE public.member_affiliation_verifications SET
          verification_obs = NULL,
          source_ref = CASE WHEN source_ref IS NOT NULL THEN md5(source_ref) ELSE NULL END,
          verified_by_member_id = NULL  -- #625: desreferencia o verificador (minimização Art. 6º III)
        WHERE member_id = v_candidate.member_id;
        GET DIAGNOSTICS v_aff_scrubbed = ROW_COUNT;

        -- #625: remove notificações de filiação SOBRE o titular enviadas a TERCEIROS (ex.: diretor),
        -- cujo body carrega o nome e não é limpo pela deleção das notificações do próprio titular acima.
        DELETE FROM public.notifications
        WHERE source_type = 'affiliation' AND source_id = v_candidate.member_id;

        INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes)
        VALUES (NULL, 'lgpd_automated_anonymization', 'member', v_candidate.member_id,
          jsonb_build_object(
            'anonymized_at', now(),
            'years_inactive', v_candidate.years_inactive,
            'inactivity_anchor', v_candidate.inactivity_anchor,
            'retention_years', p_years,
            'legal_basis', 'LGPD Lei 13.709/2018 Art. 16 — retention limit reached',
            'source', 'cron:anonymize_inactive_members',
            'offboarding_record_cleared', true,
            'resume_objects_deleted', v_resume_deleted_this_loop,
            'affiliation_rows_scrubbed', v_aff_scrubbed
          ));
      END IF;

      v_count := v_count + 1;
      v_ids := array_append(v_ids, v_candidate.member_id);
    EXCEPTION WHEN OTHERS THEN
      v_skipped := v_skipped + 1;
      v_errors := v_errors || jsonb_build_object('member_id', v_candidate.member_id, 'error', SQLERRM);
    END;
  END LOOP;

  RETURN jsonb_build_object(
    'dry_run', p_dry_run,
    'years_threshold', p_years,
    'processed', v_count,
    'skipped', v_skipped,
    'license_preserved', v_license_preserved,  -- #976 PR-4
    'member_ids', to_jsonb(v_ids),
    'resume_objects_deleted_total', v_resume_deleted_total,
    'errors', v_errors,
    'executed_at', now()
  );
END;
$function$;

-- =====================================================================
-- 15. PostgREST schema reload (novas tabelas + RPCs + assinaturas alteradas).
-- =====================================================================
NOTIFY pgrst, 'reload schema';
