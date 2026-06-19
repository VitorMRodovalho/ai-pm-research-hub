-- Ciclo 4 — Fatia A: vertical de comunidade como initiative_kind (ADR-0103, ADR-0009 config-driven)
-- Modelagem de arquitetura para o kickoff do Ciclo 4. Zero impacto em features existentes (aditivo).
-- A vertical-piloto (Construção) e o engagement do líder (Henrique) NÃO entram aqui:
--   - a vertical é criada via create_initiative em runtime (dado de produção, não schema);
--   - o líder só é engajado após o termo de voluntário assinado (decisão PM 2026-06-19).
-- Adiado p/ a ativação (kickoff/termo, documentado no ADR-0103): seeds de engagement_kind_permissions
-- do vertical_lead (manage_member/view_pii/write), elevação de operational_role e o invariante
-- AJ_vertical_no_tribe_child (guard parent — só relevante quando houver criação de filhos).

-- 1) O kind community_vertical (catálogo curado; teto 8 ajustável via config ADR-0009 sem migration)
INSERT INTO public.initiative_kinds (
  slug, display_name, description, icon, icon_emoji,
  default_duration_days, max_concurrent_per_org,
  has_board, has_meeting_notes, has_deliverables, has_attendance, has_certificate,
  custom_fields_schema, lifecycle_states,
  allowed_engagement_kinds, required_engagement_kinds,
  organization_id
) VALUES (
  'community_vertical',
  'Vertical de Comunidade',
  'Comunidade durável organizada em torno de uma credencial PMI (ex.: Construção/PMI-CP). É o eixo "para quem / onde aterrissa" (Eixo B): conecta a produção das tribos ao mercado da credencial via parceria. Não produz nem contém entregas — referencia (ADR-0103, anti-silo).',
  'layers', '🏛️',
  NULL, 8,
  false, false, false, false, false,
  '{"$schema":"http://json-schema.org/draft-07/schema#","type":"object","required":["anchor_credential","status"],"additionalProperties":false,"properties":{"anchor_credential":{"type":"string","description":"Credencial PMI atual que ancora a vertical (ex.: PMI-CP, PMI-PMOCP, PMI-ACP, CSPP)"},"predecessor_credential":{"type":"string","description":"Credencial predecessora na linha de sucessão (ex.: PMO-CP -> PMI-PMOCP). Nullable."},"credential_body":{"type":"string","description":"Organismo certificador (ex.: PMI, PMI+GPM, Agile Alliance)"},"partner_org":{"type":"string","description":"Organização parceira estratégica (ex.: Global Construction Ambassadors). Nullable."},"status":{"type":"string","enum":["forming","open","paused"],"description":"Estado público da vertical que dirige o CTA da landing: forming = chamada de protagonistas; open = operacional; paused = inativa temporariamente"},"pmi_registry_url":{"type":"string","format":"uri","description":"URL da página oficial PMI da credencial"}}}'::jsonb,
  ARRAY['draft','active','concluded','archived'],
  ARRAY['vertical_lead','vertical_member'],
  ARRAY[]::text[],
  '2b4f58ab-7c45-4170-8718-b77ee69ff906'
);

-- 2) Engagement kinds da vertical (par dedicado — não reusar committee_*/workgroup_* p/ não
--    contaminar a CASE WHEN de operational_role nem a semântica legal; ver ADR-0103 §Consequences).
-- vertical_lead: líder fundador, relação com parceiro PMI e curadoria da comunidade. legal_basis=consent.
INSERT INTO public.engagement_kinds (
  slug, display_name, description,
  legal_basis, requires_agreement, agreement_template,
  default_duration_days, retention_days_after_end, is_initiative_scoped,
  requires_vep, requires_selection, max_duration_days,
  anonymization_policy, renewable, auto_expire_behavior, notify_before_expiry_days,
  created_by_role, revocable_by_role, initiative_kinds_allowed,
  metadata_schema, display_i18n, organization_id
) VALUES (
  'vertical_lead', 'Líder de Vertical',
  'Responsável por uma vertical de comunidade: curadoria do hub, relação com o parceiro PMI e convite da coorte fundadora.',
  'consent', false, NULL,
  NULL, 1825, true,
  false, false, NULL,
  'anonymize', false, 'notify_only', 90,
  ARRAY['manager','deputy_manager'], ARRAY['manager','deputy_manager'], ARRAY['community_vertical'],
  NULL, '{"en":"Vertical Lead","es":"Líder de Vertical"}'::jsonb, '2b4f58ab-7c45-4170-8718-b77ee69ff906'
);

-- vertical_member: membro da comunidade da vertical. legal_basis=legitimate_interest. Gestão GP-only
-- por ora (created_by_role sem vertical_lead) — self-service do líder fica p/ a ativação (decisão PM).
INSERT INTO public.engagement_kinds (
  slug, display_name, description,
  legal_basis, requires_agreement, agreement_template,
  default_duration_days, retention_days_after_end, is_initiative_scoped,
  requires_vep, requires_selection, max_duration_days,
  anonymization_policy, renewable, auto_expire_behavior, notify_before_expiry_days,
  created_by_role, revocable_by_role, initiative_kinds_allowed,
  metadata_schema, display_i18n, organization_id
) VALUES (
  'vertical_member', 'Membro de Vertical',
  'Membro da comunidade de uma vertical PMI: acesso ao hub, conteúdo e conexão com o parceiro.',
  'legitimate_interest', false, NULL,
  NULL, 1825, true,
  false, false, NULL,
  'anonymize', false, 'notify_only', 90,
  ARRAY['manager','deputy_manager'], ARRAY['manager','deputy_manager'], ARRAY['community_vertical'],
  NULL, '{"en":"Vertical Member","es":"Miembro de Vertical"}'::jsonb, '2b4f58ab-7c45-4170-8718-b77ee69ff906'
);
