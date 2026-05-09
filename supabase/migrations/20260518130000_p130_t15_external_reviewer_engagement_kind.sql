-- p130 T-15: engagement_kind external_reviewer
-- ============================================================================
--
-- Driver: handoff p130 (Tier 1 sprint). Sucessor estratégico do D2 DOCX
-- (governance DOCX export para revisores offline). Em vez de exportar manual
-- DOCX e re-importar comentários, agora podemos onboardar revisores externos
-- (Ângelina advogada PMI-GO voluntária, especialistas convidados, peer-reviewers
-- de outros chapters) diretamente na plataforma com escopo restrito a comentar
-- em document_comments — sem dar sign authority em chains.
--
-- Distinção de external_signer (já existe):
--   external_signer: ASSINA chains (gate 'external_signer' no _can_sign_gate)
--   external_reviewer (este): COMENTA mas NÃO assina (action
--     `participate_in_governance_review` dá comment authority via
--     create_document_comment, mas gates de chain checam designations/role
--     que reviewer externo não tem — fail-closed).
--
-- LGPD:
--   - legal_basis: 'consent' — reviewer assina termo de revisão antes (NDA-lite).
--     Diferente de partner_contact (legitimate_interest) porque o conteúdo
--     revisado pode ser pre-publication / não-público.
--   - retention_days_after_end: 730 (2y) — alinhado com candidate (LGPD-min).
--   - anonymization_policy: 'anonymize'.
--   - default_duration_days: 90 — janela típica de revisão jurídica/técnica.
--   - renewable: true — re-convidar para próximas versões/documents.
--
-- Permissions:
--   external_reviewer × reviewer × participate_in_governance_review × organization
--   Dá comment authority (create_document_comment, list_document_comments).
--   Não dá sign — _can_sign_gate checa designations específicas que reviewer
--   externo não tem por convenção.
--
-- Rollback: DELETE permission row + DELETE engagement_kind row (ambos sem
-- referência fora). Engagements ativos (se já houver) precisam ser end-dated.
-- ============================================================================

-- 1) engagement_kind
INSERT INTO public.engagement_kinds (
  slug, display_name, description, legal_basis,
  requires_agreement, agreement_template,
  default_duration_days, max_duration_days, retention_days_after_end,
  is_initiative_scoped, requires_vep, requires_selection,
  anonymization_policy, renewable, auto_expire_behavior,
  notify_before_expiry_days, created_by_role, revocable_by_role,
  initiative_kinds_allowed, metadata_schema
) VALUES (
  'external_reviewer',
  'Revisor Externo',
  'Revisor externo (advogado, especialista, peer-reviewer) com escopo de comentar em drafts de governança sem autoridade de assinatura. Sucessor do fluxo DOCX-offline. Sem onboarding VEP — agreement-light termo de revisão.',
  'consent',
  true,
  'external_reviewer_agreement_v1',  -- placeholder; template pode ser criado depois
  90,
  365,
  730,
  false,  -- não scope-bound a iniciativa (revisão pode ser org-wide)
  false,  -- sem VEP
  false,  -- sem selection
  'anonymize',
  true,   -- renewable para próximas versões/docs
  'notify_only',  -- after expiry, só notifica (não offboard automático — revisor pode renovar)
                  -- valid values: 'suspend', 'offboard', 'notify_only'
  14,
  ARRAY['manager']::text[],
  ARRAY['manager']::text[],
  ARRAY[]::text[],  -- accept any initiative_kind ou nenhum (org-wide)
  jsonb_build_object(
    'type', 'object',
    'properties', jsonb_build_object(
      'review_scope', jsonb_build_object('type', 'string', 'enum',
        jsonb_build_array('legal','technical','editorial','peer'),
        'description', 'Tipo de revisão contratada'),
      'review_target_doc_type', jsonb_build_object('type', 'string',
        'description', 'doc_type da governance_documents alvo (policy, cooperation_agreement, etc.)'),
      'organization_affiliation', jsonb_build_object('type', 'string',
        'description', 'Vínculo institucional do revisor (ex: PMI-GO Diretoria Jurídica) — informativo, não cria engagement adicional')
    ),
    'required', jsonb_build_array('review_scope')
  )
)
ON CONFLICT (slug) DO NOTHING;

-- 2) Permission seed: comment authority via canonical V4 action
INSERT INTO public.engagement_kind_permissions (kind, role, action, scope, description) VALUES
  ('external_reviewer', 'reviewer', 'participate_in_governance_review', 'organization',
   'p130 T-15: External reviewer × reviewer engagement grants comment authority on document chains org-wide. Diferente do observer × reviewer (que tem comment + sign), aqui o reviewer NÃO tem designations curator/legal_signer/chapter_board necessárias para _can_sign_gate. Comment-only por design — fluxo Ângelina/peer-reviewer.')
ON CONFLICT (kind, role, action) DO NOTHING;

-- 3) Schema reload
NOTIFY pgrst, 'reload schema';
