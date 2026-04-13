-- ============================================================================
-- V4 Phase 3 — Migration 1/3: engagement_kinds config table
-- ADR: ADR-0006 (Person + Engagement Identity Model)
-- Rollback: DROP TABLE public.engagement_kinds CASCADE;
-- ============================================================================

-- Each kind defines a type of relationship between a person and an initiative/org.
-- Legal basis, agreement requirements, and lifecycle are properties of the kind.
-- See ADR-0008 for per-kind lifecycle configuration (Fase 5).

CREATE TABLE public.engagement_kinds (
  slug              text PRIMARY KEY,
  display_name      text NOT NULL,
  description       text,
  legal_basis       text NOT NULL DEFAULT 'consent'
                    CHECK (legal_basis IN ('contract_volunteer', 'consent', 'legitimate_interest')),
  requires_agreement boolean NOT NULL DEFAULT false,
  agreement_template text,
  default_duration_days integer,
  retention_days_after_end integer DEFAULT 1825, -- 5 years LGPD default
  is_initiative_scoped boolean NOT NULL DEFAULT true, -- false = org-wide (e.g. manager)
  organization_id   uuid NOT NULL DEFAULT '2b4f58ab-7c45-4170-8718-b77ee69ff906'::uuid
                    REFERENCES public.organizations(id) ON DELETE RESTRICT,
  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.engagement_kinds IS 'V4: Types of person-initiative relationships with legal basis and lifecycle config (ADR-0006/ADR-0008)';

ALTER TABLE public.engagement_kinds ENABLE ROW LEVEL SECURITY;

CREATE POLICY "engagement_kinds_select_authenticated"
  ON public.engagement_kinds FOR SELECT TO authenticated
  USING (true);

CREATE POLICY "engagement_kinds_org_scope"
  ON public.engagement_kinds AS RESTRICTIVE FOR ALL TO authenticated
  USING (organization_id = public.auth_org() OR organization_id IS NULL)
  WITH CHECK (organization_id = public.auth_org());

-- Seed: 12 kinds covering all current and near-future member profiles
INSERT INTO public.engagement_kinds (slug, display_name, description, legal_basis, requires_agreement, is_initiative_scoped, default_duration_days) VALUES
  ('volunteer',              'Voluntário Ativo',        'Membro voluntário em tribo de pesquisa ou iniciativa. Requer VEP + termo.',  'contract_volunteer', true,  true,  180),
  ('observer',               'Observador',              'Acompanha atividades sem compromisso formal.',                                'consent',            false, true,  NULL),
  ('alumni',                 'Alumni',                  'Ex-membro ativo. Mantém histórico e certificados.',                           'legitimate_interest', false, false, NULL),
  ('ambassador',             'Embaixador',              'Reconhecimento honorário / mérito. Sem termo obrigatório.',                   'consent',            false, false, NULL),
  ('chapter_board',          'Diretoria de Capítulo',   'Membro de diretoria de capítulo PMI federado.',                               'legitimate_interest', false, false, NULL),
  ('sponsor',                'Patrocinador',            'Apoiador institucional ou financeiro.',                                        'legitimate_interest', false, false, NULL),
  ('guest',                  'Convidado',               'Acesso temporário limitado.',                                                 'consent',            false, true,  30),
  ('candidate',              'Candidato',               'Em processo seletivo. Dados retidos até decisão + prazo recursal.',            'consent',            false, false, 90),
  ('study_group_participant','Participante Grupo Estudos','Inscrito em grupo de estudos (ex: CPMAI).',                                  'consent',            false, true,  120),
  ('study_group_owner',      'GP Grupo de Estudos',     'Gerente de projeto de grupo de estudos.',                                     'contract_volunteer', true,  true,  180),
  ('speaker',                'Palestrante',             'Palestrante externo de webinar ou evento.',                                   'consent',            false, true,  1),
  ('partner_contact',        'Contato Parceiro',        'Ponto focal de organização parceira.',                                        'legitimate_interest', false, false, NULL);

NOTIFY pgrst, 'reload schema';
