-- ============================================================================
-- WHAT: Wave 1b first leaf — synthetic approval_chains + approval_signoffs
-- backfill for 7 legacy pre-chain governance_documents per PM-ratified
-- signer-of-record convention (#367 Step 2 closed pos-p256). Anchors invariant
-- V coherence so the V activation migration (20260805000039) can enforce
-- status=approved/active → current_ratified_chain_id IS NOT NULL with NO
-- carve-out (PM Q1=C, rejected metadata.legacy_pre_chain flag).
--
-- WHY: 7 docs were INSERTed in pre-chain-system era with status='active' and
-- ZERO approval_chains rows. PM ratified 3-class convention (DocuSign /
-- gov.br template / internal attestation), all with PM/Vitor as
-- migration-attester (NOT new content approver). Signoff is `acknowledge`
-- (NOT `approval`) to preserve semantic distinction; metadata.role =
-- migration_attestation + metadata.legacy_migration=true mark provenance.
-- Originals stay authoritative in external evidence.
--
-- SPEC: docs/specs/SPEC_GOVERNANCE_DOCUMENTS_END_TO_END.md §19.5 (Wave 1b
-- first leaf scope) + #367 issue body (6-step protocol) + #367
-- comment-4530953843 (PM convention RATIFICADA).
--
-- SCOPE LOCK (per feedback_wave_1a_scope_confine_governance):
--   IN-SCOPE:  7 docs synthetic backfill (1 placeholder version + 7 chains +
--              7 signoffs + 7 governance_documents UPDATE +
--              7 admin_audit_log) + sanity DO + NOTIFY pgrst.
--   OUT-OF-SCOPE: V invariant activation (separate migration 039);
--                 document_version_dependencies (different Wave 1b leaf);
--                 governance_document_artifacts (different Wave 1b leaf);
--                 curator-draft-access mitigation (separate leaf);
--                 Wave 2 admin UI / Wave 3 member library — SEQUENCED AFTER
--                 #367 close per PM directive p256.
--
-- CLASSIFICATION (PM convention #367 comment-4530953843):
--   Classe 1 (DocuSign source — 5 docs):
--     - 3bff9307 Acordo PMI-GO ↔ PMI-CE
--     - 04e3e894 Acordo PMI-GO ↔ PMI-DF
--     - ac5b5cb5 Acordo PMI-GO ↔ PMI-MG
--     - c32b174d Acordo PMI-GO ↔ PMI-RS
--     - 7a8d47a1 Manual de Governança e Operações — R2
--     source_evidence='docusign', role='migration_attestation'
--   Classe 2 (gov.br template — 1 doc):
--     - a78311fd Termo de Voluntariado — Template Ciclo 3
--     source_evidence='gov_br_template', role='interim_external_template',
--     future_action='supersede_by_nucleo_specific_term'
--   Classe 3 (internal attestation — 1 doc):
--     - 9a0e5000 Sumario Executivo CR-050 v2.1 — PI
--     source_evidence='internal_attestation', role='migration_attestation'
--
-- SUB-DECISION A (implementer call, per #367 convention text):
--   Classe 2 (Termo Voluntariado) has current_version_id IS NULL pre-backfill.
--   approval_chains.version_id is NOT NULL FK to document_versions(id) ON DELETE
--   RESTRICT — chain INSERT requires a version_id. Two implementer options
--   per PM convention text:
--     (a) Create placeholder document_versions row representing the gov.br
--         template (recommended if gov.br PDF accessible)
--     (b) Keep current_version_id IS NULL + metadata.no_current_version_intentional=true
--   PICK (a) because (b) requires either a carve-out in chain.version_id FK
--   (not acceptable per PM no-carve-out directive) OR skipping Termo from V
--   scope (also rejected). Placeholder approach: locked from inception
--   (locked_at=now()), content_html documents gov.br envelope as authoritative
--   source, notes field flags placeholder + future_action. Invariant J is
--   preserved: locked_at IS NOT NULL on the version pointed by current_version_id.
--
-- TRIGGER HANDLING:
--   trg_sync_ratification_cache (AFTER INSERT/UPDATE OF status ON approval_chains)
--     LET FIRE: auto-populates governance_documents.{first,current}_ratified_*
--     cache fields from chain INSERT. Saves manual UPDATE for cache columns.
--   trg_approval_signoff_xp (AFTER INSERT ON approval_signoffs)
--     DISABLE during backfill: would award 'curation_ratification' XP to Vitor
--     for 7 synthetic signoffs, polluting XP ranking.
--   trg_approval_signoff_notify (AFTER INSERT ON approval_signoffs)
--     DISABLE during backfill: would enqueue chain_approved / gate_advanced
--     notifications via _enqueue_gate_notifications — synthetic migration
--     attestation should NOT trigger notifications to other involved parties.
--   trg_artia_sync_on_govdoc_ratified (AFTER UPDATE OF current_ratified_at)
--     DISABLE during backfill: trg_sync_ratification_cache will UPDATE
--     governance_documents.current_ratified_at — would cascade-fire Artia
--     net.http_post 7x. Synthetic legacy attestation should NOT push to
--     external project management system.
--   trg_approval_signoff_immutable (BEFORE UPDATE ON approval_signoffs)
--     NO ACTION: only fires on UPDATE, this migration only INSERTs signoffs.
--   notify_project_charter_chain_approved (AFTER UPDATE ON approval_chains)
--     NO ACTION: only fires on UPDATE to status='approved' AND doc_type=
--     'project_charter'. None of the 7 docs are project_charter; this
--     migration INSERTs with status='active' (not UPDATEs to 'approved').
--
-- ROLLBACK (idempotent, requires re-enabling V invariant carve-out OR
-- reverting V activation migration first):
--   -- Re-enable triggers (in case rollback runs in mid-state):
--   ALTER TABLE public.approval_signoffs ENABLE TRIGGER approval_signoff_xp;
--   ALTER TABLE public.approval_signoffs ENABLE TRIGGER trg_approval_signoff_notify;
--   ALTER TABLE public.governance_documents ENABLE TRIGGER trg_artia_sync_on_govdoc_ratified;
--   -- Revert governance_documents cache:
--   UPDATE public.governance_documents
--      SET current_ratified_chain_id=NULL, current_ratified_version_id=NULL,
--          current_ratified_at=NULL, first_ratified_chain_id=NULL,
--          first_ratified_version_id=NULL, first_ratified_at=NULL,
--          closing_gate_signoff_id=NULL, approved_at=NULL
--    WHERE id IN (<7 ids>);
--   -- Revert Termo's current_version_id (placeholder):
--   UPDATE public.governance_documents SET current_version_id=NULL
--    WHERE id='a78311fd-cf87-4bee-b0f1-e117a36095c5';
--   -- DELETE synthetic rows (FK ordering — closing_gate_signoff_id FK is
--   -- RESTRICT, so UPDATE above must happen FIRST):
--   ALTER TABLE public.approval_signoffs DISABLE TRIGGER trg_approval_signoff_immutable;
--   DELETE FROM public.approval_signoffs
--    WHERE (content_snapshot->>'p257_migration_marker')::boolean = true;
--   ALTER TABLE public.approval_signoffs ENABLE TRIGGER trg_approval_signoff_immutable;
--   DELETE FROM public.approval_chains
--    WHERE notes LIKE '%[p257 #367 Wave 1b first leaf]%';
--   DELETE FROM public.document_versions
--    WHERE notes LIKE '%[p257 #367 Wave 1b first leaf]%placeholder%';
--   DELETE FROM public.admin_audit_log
--    WHERE action='governance.legacy_chain_synthesized'
--      AND metadata->>'migration'='20260805000038_p257_315_w1b_legacy_chain_backfill';
--
-- INVARIANTS:
--   - This migration alone does NOT change check_schema_invariants() body.
--     V is added by 20260805000039_p257_315_w1b_v_invariant_activation.sql.
--   - All 20 prior invariants (A1, A2, A3, B, C, D, E, F, J, K, L, M, N, O,
--     P, Q, R, S, T, V') stay byte-identical (Phase C body hash drift gate).
--   - Post-backfill state pre-V-activation: 7 docs go from
--     `status=active AND current_ratified_chain_id IS NULL` to
--     `status=active AND current_ratified_chain_id IS NOT NULL`. Sanity DO
--     at bottom RAISES if any of the 7 still has NULL — blocking V activation
--     downstream.
--
-- CROSS-REF: #367 issue body + comment-4530953843 (PM convention RATIFICADA);
-- p256 handoff (memory/handoff_p256_wave_1a_foundation_close.md);
-- 20260805000036 M2 (V' deferred V); ADR-0007 (member-derived authority);
-- ADR-0004 (organization_id); ISSUE_REGISTRY §0 #315 row + §4 Program Cluster
-- "Governance Documents v1".
-- ============================================================================

-- ─── M1.1: Placeholder document_versions row for Termo Voluntariado (Classe 2, sub-decision A) ───
INSERT INTO public.document_versions (
  document_id, version_number, version_label, content_html, content_markdown,
  authored_by, authored_at, published_at, published_by,
  locked_at, locked_by, notes, organization_id
)
SELECT
  'a78311fd-cf87-4bee-b0f1-e117a36095c5'::uuid,                                       -- document_id (Termo Voluntariado Ciclo 3)
  1,                                                                                  -- version_number (first version of placeholder series)
  'gov-br-template-ciclo3-legacy-placeholder',                                        -- version_label
  '<h1>Termo de Voluntariado — Template Ciclo 3 (Placeholder Legacy)</h1>' ||         -- content_html
  '<p><strong>Atestação de migração histórica</strong> — p257 #367 Wave 1b first leaf.</p>' ||
  '<p>Esta linha de <code>document_versions</code> existe para satisfazer a coerência da invariante V ' ||
  '(<code>status=active</code> deve ter <code>current_ratified_chain_id IS NOT NULL</code>), que por sua vez requer ' ||
  '<code>approval_chains.version_id</code> NOT NULL (FK RESTRICT).</p>' ||
  '<p><strong>Conteúdo autoritativo</strong>: o template oficial PMI-GO assinado via gov.br pré-existia este sistema. ' ||
  'O envelope gov.br original IS a autoridade do conteúdo. Esta linha NÃO substitui o template legal — ela apenas ' ||
  'ancora a invariante V no banco de dados.</p>' ||
  '<p><strong>Ação futura</strong>: quando o Núcleo IA publicar o Termo de Voluntariado específico do Núcleo, ' ||
  'esse novo termo deverá <code>supersede</code> este placeholder (transição de status para <code>superseded</code>).</p>',
  '# Termo de Voluntariado — Template Ciclo 3 (Placeholder Legacy)' || E'\n\n' ||
  '**Atestação de migração histórica** — p257 #367 Wave 1b first leaf.' || E'\n\n' ||
  'Esta linha existe para satisfazer coerência da invariante V. Conteúdo autoritativo lives no envelope gov.br original ' ||
  'pré-existente este sistema. Esta linha NÃO substitui o template legal — ela apenas ancora V no banco de dados.' || E'\n\n' ||
  '**Ação futura**: futuro Termo Núcleo-específico deverá supersede este placeholder.',
  '880f736c-3e76-4df4-9375-33575c190305'::uuid,                                       -- authored_by (PM/Vitor)
  (SELECT created_at FROM public.governance_documents WHERE id='a78311fd-cf87-4bee-b0f1-e117a36095c5'::uuid),
  (SELECT created_at FROM public.governance_documents WHERE id='a78311fd-cf87-4bee-b0f1-e117a36095c5'::uuid),
  '880f736c-3e76-4df4-9375-33575c190305'::uuid,                                       -- published_by
  now(),                                                                              -- locked_at (locked from inception per Sub-decision A constraint)
  '880f736c-3e76-4df4-9375-33575c190305'::uuid,                                       -- locked_by (PM)
  '[p257 #367 Wave 1b first leaf] Placeholder legacy version — gov.br template anchor. ' ||
  'Autoridade real lives no envelope gov.br original. Será superseded quando termo Núcleo-específico for ratificado. ' ||
  'NÃO editar via UI — Sub-decision A.',
  '2b4f58ab-7c45-4170-8718-b77ee69ff906'::uuid                                        -- organization_id (Núcleo IA)
WHERE NOT EXISTS (
  -- Idempotency: skip if a placeholder already exists for this doc
  SELECT 1 FROM public.document_versions
  WHERE document_id='a78311fd-cf87-4bee-b0f1-e117a36095c5'::uuid
    AND version_label='gov-br-template-ciclo3-legacy-placeholder'
);

-- ─── M1.2: Update Termo Voluntariado.current_version_id → placeholder ───
UPDATE public.governance_documents
   SET current_version_id = (
     SELECT id FROM public.document_versions
     WHERE document_id='a78311fd-cf87-4bee-b0f1-e117a36095c5'::uuid
       AND version_label='gov-br-template-ciclo3-legacy-placeholder'
   ),
       updated_at = now()
 WHERE id='a78311fd-cf87-4bee-b0f1-e117a36095c5'::uuid
   AND current_version_id IS NULL;                                                    -- idempotent

-- ─── M1.3: Disable side-effecting triggers for synthetic backfill ───
ALTER TABLE public.approval_signoffs DISABLE TRIGGER approval_signoff_xp;
ALTER TABLE public.approval_signoffs DISABLE TRIGGER trg_approval_signoff_notify;
ALTER TABLE public.governance_documents DISABLE TRIGGER trg_artia_sync_on_govdoc_ratified;

-- ─── M1.4: Backfill — 7 chains + 7 signoffs + 7 gd UPDATEs + 7 audit ───
DO $migration$
DECLARE
  v_org_id        constant uuid := '2b4f58ab-7c45-4170-8718-b77ee69ff906';
  v_pm_id         constant uuid := '880f736c-3e76-4df4-9375-33575c190305';
  v_doc           record;
  v_chain_id      uuid;
  v_signoff_id    uuid;
  v_version_id    uuid;
  v_class         text;
  v_source_ev     text;
  v_role          text;
  v_orig_provenance text;
  v_migration_note text;
  v_extra_kv      jsonb;
BEGIN
  FOR v_doc IN
    SELECT gd.id, gd.title, gd.doc_type, gd.created_at, gd.current_version_id
    FROM public.governance_documents gd
    WHERE gd.id IN (
      '3bff9307-c47a-4ec7-9502-c97a2d27ee53'::uuid,
      '04e3e894-5155-4ac8-b844-fcac4c9de431'::uuid,
      'ac5b5cb5-8dab-45eb-81d0-a1707fbc8ddb'::uuid,
      'c32b174d-bf32-4692-afc6-34a27cebbf99'::uuid,
      '9a0e5000-0000-0000-0000-000000000000'::uuid,
      '7a8d47a1-e733-4cda-ad1c-cf35334931cf'::uuid,
      'a78311fd-cf87-4bee-b0f1-e117a36095c5'::uuid
    )
    ORDER BY gd.id
  LOOP
    -- ── Class detection (PM convention) ──────────────────────────────────
    IF v_doc.id = 'a78311fd-cf87-4bee-b0f1-e117a36095c5'::uuid THEN
      v_class := 'classe_2_gov_br_template';
      v_source_ev := 'gov_br_template';
      v_role := 'interim_external_template';
      v_orig_provenance := 'PMI-GO official template, gov.br signature flow';
      v_migration_note := 'PMI-GO official volunteer term template signed via gov.br; used by Núcleo as interim until Núcleo-specific term lands. Synthetic row anchors invariant V coherence only.';
      v_extra_kv := jsonb_build_object(
        'original_attestation', v_orig_provenance,
        'interim_usage_note', 'Used by Núcleo as interim until Núcleo-specific volunteer term lands',
        'future_action', 'supersede_by_nucleo_specific_term',
        'placeholder_version_label', 'gov-br-template-ciclo3-legacy-placeholder'
      );
    ELSIF v_doc.id = '9a0e5000-0000-0000-0000-000000000000'::uuid THEN
      v_class := 'classe_3_internal_attestation';
      v_source_ev := 'internal_attestation';
      v_role := 'migration_attestation';
      v_orig_provenance := 'Internal executive summary (Núcleo IA CR-050 v2.1 PI)';
      v_migration_note := 'Internal executive summary; PM attests legacy status for invariant V coherence.';
      v_extra_kv := jsonb_build_object(
        'attester_member_id', v_pm_id::text,
        'risk_assessment', 'low'
      );
    ELSIF v_doc.id = '7a8d47a1-e733-4cda-ad1c-cf35334931cf'::uuid THEN
      v_class := 'classe_1_docusign_manual';
      v_source_ev := 'docusign';
      v_role := 'migration_attestation';
      v_orig_provenance := 'PMI-GO board ratification of Manual R2 (DocuSign envelope, pre-chain era)';
      v_migration_note := 'Pre-chain-workflow doc; original DocuSign envelope IS the authority; this synthetic row anchors invariant V coherence only.';
      v_extra_kv := jsonb_build_object('original_signers', v_orig_provenance);
    ELSE
      -- 4 cooperation agreements (PMI-GO ↔ CE/DF/MG/RS)
      v_class := 'classe_1_docusign_cooperation';
      v_source_ev := 'docusign';
      v_role := 'migration_attestation';
      v_orig_provenance := 'PMI-GO + counterpart chapter (DocuSign envelope, pre-chain era) — see ' || v_doc.title;
      v_migration_note := 'Pre-chain-workflow doc; original DocuSign envelope IS the authority; this synthetic row anchors invariant V coherence only.';
      v_extra_kv := jsonb_build_object('original_signers', v_orig_provenance);
    END IF;

    -- ── Resolve version_id for chain (gd.current_version_id post-Termo placeholder UPDATE) ──
    SELECT current_version_id INTO v_version_id
    FROM public.governance_documents WHERE id = v_doc.id;
    IF v_version_id IS NULL THEN
      RAISE EXCEPTION 'p257 #367 backfill: doc % has current_version_id IS NULL post placeholder update — backfill BLOCKED (% / %)', v_doc.id, v_doc.title, v_class;
    END IF;

    -- ── INSERT approval_chains (status='active' triggers trg_sync_ratification_cache) ──
    INSERT INTO public.approval_chains (
      document_id, version_id, organization_id, status, gates,
      opened_at, approved_at, activated_at, closed_at, opened_by, closed_by, notes
    ) VALUES (
      v_doc.id,
      v_version_id,
      v_org_id,
      'active',                                                                       -- triggers cache sync
      jsonb_build_array(jsonb_build_object(
        'kind', 'member_ratification',
        'order', 1,
        'threshold', 1,
        'status', 'completed',
        'completed_at', v_doc.created_at,
        'actor_member_id', v_pm_id::text,
        'actor_name', 'Vitor Maia Rodovalho',
        'role_label', 'PM · Synthetic Migration Attestation (legacy V invariant anchor)',
        'legacy_migration_p257', true,
        'class', v_class,
        'source_evidence', v_source_ev
      )),
      v_doc.created_at,                                                               -- opened_at (preserve temporal coherence)
      v_doc.created_at,                                                               -- approved_at (synthetic — chain "approved" at doc creation)
      v_doc.created_at,                                                               -- activated_at (synthetic — chain "active" at doc creation)
      NULL,                                                                           -- closed_at (status='active' is currently in flight)
      v_pm_id,                                                                        -- opened_by
      NULL,                                                                           -- closed_by
      '[p257 #367 Wave 1b first leaf] Synthetic legacy chain — pre-chain-workflow doc anchored for invariant V coherence. ' ||
      'Classe: ' || v_class || '. Source evidence: ' || v_source_ev || '. ' ||
      'Original authority lives in external evidence (DocuSign / gov.br / internal). ' ||
      'PM (Vitor) é o migration attester, NÃO um novo content approver. ' ||
      'Signoff intencionalmente acknowledge (não approval) preserva distinção semântica.'
    )
    ON CONFLICT (document_id, version_id) DO NOTHING                                  -- idempotency on (doc, version) UNIQUE
    RETURNING id INTO v_chain_id;

    -- Idempotent re-run: lookup existing chain if INSERT was skipped
    IF v_chain_id IS NULL THEN
      SELECT id INTO v_chain_id
      FROM public.approval_chains
      WHERE document_id = v_doc.id AND version_id = v_version_id
      ORDER BY created_at DESC LIMIT 1;
    END IF;

    -- ── INSERT approval_signoffs (gate_kind matches chain.gates[0].kind) ──
    INSERT INTO public.approval_signoffs (
      approval_chain_id, gate_kind, signer_id, signoff_type,
      signed_at, signature_hash, organization_id,
      content_snapshot, sections_verified, comment_body
    ) VALUES (
      v_chain_id,
      'member_ratification',                                                          -- matches chain.gates[0].kind
      v_pm_id,
      'acknowledge',                                                                  -- NOT 'approval' — PM convention
      v_doc.created_at,                                                               -- signed_at preserves temporal coherence
      md5(v_chain_id::text || '-legacy-attestation-p257-issue-367'),                  -- deterministic placeholder hash
      v_org_id,
      jsonb_build_object(
        'doc_id', v_doc.id::text,
        'doc_type', v_doc.doc_type,
        'doc_title', v_doc.title,
        'version_id', v_version_id::text,
        'gate_kind', 'member_ratification',
        'signoff_type', 'acknowledge',
        'signer_id', v_pm_id::text,
        'signer_name', 'Vitor Maia Rodovalho',
        'signer_role', 'manager',
        'signed_at', v_doc.created_at,
        'legacy_migration', true,
        'source_evidence', v_source_ev,
        'role', v_role,
        'class', v_class,
        'migration_note', v_migration_note,
        'p257_migration_marker', true,
        'invariant_anchor', 'V_status_chain_coherence'
      ) || v_extra_kv,                                                                -- merge per-class extras
      NULL,
      '[p257 #367 Wave 1b] Synthetic migration attestation — anchor para invariante V (NÃO content approval). Original authority preserved as external evidence reference em content_snapshot.'
    )
    ON CONFLICT (approval_chain_id, gate_kind, signer_id) DO NOTHING                  -- idempotency on UNIQUE
    RETURNING id INTO v_signoff_id;

    -- Idempotent re-run: lookup existing signoff if INSERT was skipped
    IF v_signoff_id IS NULL THEN
      SELECT id INTO v_signoff_id
      FROM public.approval_signoffs
      WHERE approval_chain_id = v_chain_id
        AND gate_kind = 'member_ratification'
        AND signer_id = v_pm_id
      ORDER BY created_at DESC LIMIT 1;
    END IF;

    -- ── UPDATE governance_documents: closing_gate_signoff_id + approved_at (cache trigger handles ratified_*) ──
    UPDATE public.governance_documents
       SET closing_gate_signoff_id = v_signoff_id,
           approved_at = v_doc.created_at,
           updated_at = now()
     WHERE id = v_doc.id
       AND (closing_gate_signoff_id IS NULL OR closing_gate_signoff_id <> v_signoff_id);  -- idempotency

    -- ── INSERT admin_audit_log (per-doc trace) ──
    INSERT INTO public.admin_audit_log (
      actor_id, action, target_type, target_id, changes, metadata
    ) VALUES (
      v_pm_id,
      'governance.legacy_chain_synthesized',
      'governance_document',
      v_doc.id,
      jsonb_build_object(
        'chain_id', v_chain_id::text,
        'signoff_id', v_signoff_id::text,
        'version_id', v_version_id::text
      ),
      jsonb_build_object(
        'migration', '20260805000038_p257_315_w1b_legacy_chain_backfill',
        'issue', '#367',
        'parent_umbrella', '#315',
        'class', v_class,
        'source_evidence', v_source_ev,
        'role', v_role,
        'signer_of_record_convention', 'pm_vitor_as_migration_attester',
        'doc_title', v_doc.title,
        'doc_type', v_doc.doc_type,
        'note', 'Synthetic chain/signoff anchora invariante V coherence. Original authority preserved as external evidence reference. PM attests legacy status (NÃO content approval).'
      )
    );
  END LOOP;
END $migration$;

-- ─── M1.5: Re-enable triggers ───
ALTER TABLE public.approval_signoffs ENABLE TRIGGER approval_signoff_xp;
ALTER TABLE public.approval_signoffs ENABLE TRIGGER trg_approval_signoff_notify;
ALTER TABLE public.governance_documents ENABLE TRIGGER trg_artia_sync_on_govdoc_ratified;

-- ─── M1.6: Sanity DO — all 7 docs must have current_ratified_chain_id NOT NULL ───
DO $sanity$
DECLARE
  v_orphan_count int;
  v_audit_count int;
  v_signoff_count int;
  v_chain_count int;
BEGIN
  SELECT COUNT(*) INTO v_orphan_count
  FROM public.governance_documents
  WHERE id IN (
    '3bff9307-c47a-4ec7-9502-c97a2d27ee53'::uuid,
    '04e3e894-5155-4ac8-b844-fcac4c9de431'::uuid,
    'ac5b5cb5-8dab-45eb-81d0-a1707fbc8ddb'::uuid,
    'c32b174d-bf32-4692-afc6-34a27cebbf99'::uuid,
    '9a0e5000-0000-0000-0000-000000000000'::uuid,
    '7a8d47a1-e733-4cda-ad1c-cf35334931cf'::uuid,
    'a78311fd-cf87-4bee-b0f1-e117a36095c5'::uuid
  )
  AND current_ratified_chain_id IS NULL;

  IF v_orphan_count > 0 THEN
    RAISE EXCEPTION 'p257 #367 backfill sanity FAIL: % docs ainda têm current_ratified_chain_id IS NULL — V invariant activation BLOCKED', v_orphan_count;
  END IF;

  SELECT COUNT(*) INTO v_chain_count
  FROM public.approval_chains ac
  WHERE ac.document_id IN (
    '3bff9307-c47a-4ec7-9502-c97a2d27ee53'::uuid,
    '04e3e894-5155-4ac8-b844-fcac4c9de431'::uuid,
    'ac5b5cb5-8dab-45eb-81d0-a1707fbc8ddb'::uuid,
    'c32b174d-bf32-4692-afc6-34a27cebbf99'::uuid,
    '9a0e5000-0000-0000-0000-000000000000'::uuid,
    '7a8d47a1-e733-4cda-ad1c-cf35334931cf'::uuid,
    'a78311fd-cf87-4bee-b0f1-e117a36095c5'::uuid
  )
  AND ac.status='active'
  AND ac.notes LIKE '%[p257 #367 Wave 1b first leaf]%';

  IF v_chain_count <> 7 THEN
    RAISE EXCEPTION 'p257 #367 backfill sanity FAIL: expected 7 synthetic chains, got %', v_chain_count;
  END IF;

  SELECT COUNT(*) INTO v_signoff_count
  FROM public.approval_signoffs asg
  JOIN public.approval_chains ac ON ac.id = asg.approval_chain_id
  WHERE ac.document_id IN (
    '3bff9307-c47a-4ec7-9502-c97a2d27ee53'::uuid,
    '04e3e894-5155-4ac8-b844-fcac4c9de431'::uuid,
    'ac5b5cb5-8dab-45eb-81d0-a1707fbc8ddb'::uuid,
    'c32b174d-bf32-4692-afc6-34a27cebbf99'::uuid,
    '9a0e5000-0000-0000-0000-000000000000'::uuid,
    '7a8d47a1-e733-4cda-ad1c-cf35334931cf'::uuid,
    'a78311fd-cf87-4bee-b0f1-e117a36095c5'::uuid
  )
  AND (asg.content_snapshot->>'p257_migration_marker')::boolean IS TRUE
  AND asg.signoff_type = 'acknowledge'
  AND asg.gate_kind = 'member_ratification';

  IF v_signoff_count <> 7 THEN
    RAISE EXCEPTION 'p257 #367 backfill sanity FAIL: expected 7 synthetic signoffs (acknowledge + member_ratification + p257_migration_marker), got %', v_signoff_count;
  END IF;

  SELECT COUNT(*) INTO v_audit_count
  FROM public.admin_audit_log
  WHERE action='governance.legacy_chain_synthesized'
    AND metadata->>'migration'='20260805000038_p257_315_w1b_legacy_chain_backfill'
    AND target_type='governance_document';

  IF v_audit_count <> 7 THEN
    RAISE EXCEPTION 'p257 #367 backfill sanity FAIL: expected 7 admin_audit_log rows, got %', v_audit_count;
  END IF;
END $sanity$;

-- ─── M1.7: Reload PostgREST schema (cache invalidation) ───
NOTIFY pgrst, 'reload schema';
