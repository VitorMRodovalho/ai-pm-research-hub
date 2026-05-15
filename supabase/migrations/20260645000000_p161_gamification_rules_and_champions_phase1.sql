-- p161 Fase 1 — Gamification rules (config-driven) + Champions ledger
-- Refs: docs/reference/SEMANTIC_TAXONOMY.md Q6+Q7+Q5.1-5.7
-- PM ratification: 2026-05-15 (sessão p161, batch 4)
-- Rollback: see footer

-- ════════════════════════════════════════════════════════════
-- 1. gamification_rules — config-driven
-- ════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS public.gamification_rules (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  slug text NOT NULL,
  display_name_i18n jsonb NOT NULL DEFAULT '{}'::jsonb,
  description_i18n jsonb NOT NULL DEFAULT '{}'::jsonb,
  base_points integer NOT NULL CHECK (base_points >= 0),
  bonus_per_criterion integer NOT NULL DEFAULT 0 CHECK (bonus_per_criterion >= 0),
  cap_points integer NULL CHECK (cap_points IS NULL OR cap_points >= base_points),
  trigger_source text NOT NULL CHECK (trigger_source IN ('manual','auto_trigger','rpc_callback')),
  active boolean NOT NULL DEFAULT true,
  effective_from timestamptz NOT NULL DEFAULT now(),
  organization_id uuid NOT NULL REFERENCES public.organizations(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid NULL REFERENCES public.members(id),
  updated_by uuid NULL REFERENCES public.members(id),
  CONSTRAINT gamification_rules_slug_org_unique UNIQUE (organization_id, slug)
);

CREATE INDEX gamification_rules_active_idx
  ON public.gamification_rules (organization_id, slug)
  WHERE active = true;

ALTER TABLE public.gamification_rules ENABLE ROW LEVEL SECURITY;

CREATE POLICY gamification_rules_read_auth ON public.gamification_rules
  FOR SELECT TO authenticated
  USING (organization_id = public.auth_org());

CREATE POLICY gamification_rules_write_manage_platform ON public.gamification_rules
  FOR ALL TO authenticated
  USING (organization_id = public.auth_org() AND public.rls_can('manage_platform'))
  WITH CHECK (organization_id = public.auth_org() AND public.rls_can('manage_platform'));

GRANT SELECT ON public.gamification_rules TO authenticated;

COMMENT ON TABLE public.gamification_rules IS
'Config-driven gamification rules (ADR-0009 pattern). '
'Admin tunes points per category via /admin/gamification/rules. '
'Changes apply FORWARD-ONLY (effective_from timestamp). XP earned before is immutable. '
'Ver docs/reference/SEMANTIC_TAXONOMY.md Q6+Q7.';

COMMENT ON COLUMN public.gamification_rules.trigger_source IS
'How XP is earned: manual = RPC explicit grant (champion_*) | auto_trigger = AFTER trigger on source table | rpc_callback = inline in domain RPC.';

COMMENT ON COLUMN public.gamification_rules.effective_from IS
'Forward-only semantics: rule applies to earnings AFTER this timestamp. Older earnings preserved with their original points.';

-- ════════════════════════════════════════════════════════════
-- 2. Seed 23 rules
-- ════════════════════════════════════════════════════════════
INSERT INTO public.gamification_rules (slug, display_name_i18n, description_i18n, base_points, trigger_source, organization_id) VALUES
  ('attendance',
   '{"pt-BR":"Presença em evento","en-US":"Event attendance","es-LATAM":"Asistencia a evento"}'::jsonb,
   '{"pt-BR":"Pontos por presença confirmada em reunião/evento."}'::jsonb,
   10, 'auto_trigger', '2b4f58ab-7c45-4170-8718-b77ee69ff906'),
  ('badge',
   '{"pt-BR":"Badge externa (Credly)","en-US":"External badge (Credly)","es-LATAM":"Insignia externa (Credly)"}'::jsonb,
   '{"pt-BR":"Badge Credly linkada ao perfil do membro."}'::jsonb,
   10, 'rpc_callback', '2b4f58ab-7c45-4170-8718-b77ee69ff906'),
  ('course',
   '{"pt-BR":"Curso PMI/externo","en-US":"PMI/external course","es-LATAM":"Curso PMI/externo"}'::jsonb,
   '{"pt-BR":"Conclusão de curso PMI ou externo registrado no perfil."}'::jsonb,
   15, 'rpc_callback', '2b4f58ab-7c45-4170-8718-b77ee69ff906'),
  ('trail',
   '{"pt-BR":"Etapa de trilha","en-US":"Trail step","es-LATAM":"Etapa de ruta"}'::jsonb,
   '{"pt-BR":"Avanço em etapa da trilha de onboarding."}'::jsonb,
   20, 'auto_trigger', '2b4f58ab-7c45-4170-8718-b77ee69ff906'),
  ('knowledge_ai_pm',
   '{"pt-BR":"Módulo Knowledge IA & GP","en-US":"AI & PM Knowledge module","es-LATAM":"Módulo Conocimiento IA & GP"}'::jsonb,
   '{"pt-BR":"Conclusão de módulo da plataforma Knowledge IA & GP."}'::jsonb,
   20, 'auto_trigger', '2b4f58ab-7c45-4170-8718-b77ee69ff906'),
  ('specialization',
   '{"pt-BR":"Especialização concluída","en-US":"Specialization completed","es-LATAM":"Especialización concluida"}'::jsonb,
   '{"pt-BR":"Conclusão de track de especialização."}'::jsonb,
   25, 'auto_trigger', '2b4f58ab-7c45-4170-8718-b77ee69ff906'),
  ('showcase',
   '{"pt-BR":"Showcase em evento","en-US":"Event showcase","es-LATAM":"Showcase en evento"}'::jsonb,
   '{"pt-BR":"Apresentação em evento (variável por tipo: case=25, tool review=20, prompt=20, insight=15, awareness=15)."}'::jsonb,
   20, 'rpc_callback', '2b4f58ab-7c45-4170-8718-b77ee69ff906'),
  ('cert_cpmai',
   '{"pt-BR":"Certificação CPMAI","en-US":"CPMAI certification","es-LATAM":"Certificación CPMAI"}'::jsonb,
   '{"pt-BR":"Certificação Cognitive Project Management in AI."}'::jsonb,
   45, 'rpc_callback', '2b4f58ab-7c45-4170-8718-b77ee69ff906'),
  ('cert_pmi_entry',
   '{"pt-BR":"Certificação PMI Entry","en-US":"PMI Entry certification","es-LATAM":"Certificación PMI Entry"}'::jsonb,
   '{"pt-BR":"Certificação PMI nível Entry."}'::jsonb,
   30, 'rpc_callback', '2b4f58ab-7c45-4170-8718-b77ee69ff906'),
  ('cert_pmi_mid',
   '{"pt-BR":"Certificação PMI Mid","en-US":"PMI Mid certification","es-LATAM":"Certificación PMI Mid"}'::jsonb,
   '{"pt-BR":"Certificação PMI nível Mid."}'::jsonb,
   40, 'rpc_callback', '2b4f58ab-7c45-4170-8718-b77ee69ff906'),
  ('cert_pmi_practitioner',
   '{"pt-BR":"Certificação PMI Practitioner","en-US":"PMI Practitioner certification","es-LATAM":"Certificación PMI Practitioner"}'::jsonb,
   '{"pt-BR":"Certificação PMI nível Practitioner."}'::jsonb,
   35, 'rpc_callback', '2b4f58ab-7c45-4170-8718-b77ee69ff906'),
  ('cert_pmi_senior',
   '{"pt-BR":"Certificação PMI Senior","en-US":"PMI Senior certification","es-LATAM":"Certificación PMI Senior"}'::jsonb,
   '{"pt-BR":"Certificação PMI nível Senior."}'::jsonb,
   50, 'rpc_callback', '2b4f58ab-7c45-4170-8718-b77ee69ff906')
ON CONFLICT (organization_id, slug) DO NOTHING;

INSERT INTO public.gamification_rules (slug, display_name_i18n, description_i18n, base_points, bonus_per_criterion, cap_points, trigger_source, organization_id) VALUES
  ('champion_general',
   '{"pt-BR":"Champion em reunião geral","en-US":"General meeting Champion","es-LATAM":"Champion en reunión general"}'::jsonb,
   '{"pt-BR":"Reconhecimento manual por destaque em reunião geral. Base 30 pts + 5 pts por critério marcado (cap 50)."}'::jsonb,
   30, 5, 50, 'manual', '2b4f58ab-7c45-4170-8718-b77ee69ff906'),
  ('champion_tribe',
   '{"pt-BR":"Champion em reunião de tribo","en-US":"Tribe meeting Champion","es-LATAM":"Champion en reunión de tribu"}'::jsonb,
   '{"pt-BR":"Reconhecimento manual por destaque em reunião de tribo. Base 20 pts + 5 pts por critério marcado (cap 40)."}'::jsonb,
   20, 5, 40, 'manual', '2b4f58ab-7c45-4170-8718-b77ee69ff906'),
  ('champion_deliverable',
   '{"pt-BR":"Champion por entregável","en-US":"Deliverable Champion","es-LATAM":"Champion por entregable"}'::jsonb,
   '{"pt-BR":"Reconhecimento manual por qualidade de entregável. Base 40 pts + 5 pts por critério marcado (cap 60)."}'::jsonb,
   40, 5, 60, 'manual', '2b4f58ab-7c45-4170-8718-b77ee69ff906')
ON CONFLICT (organization_id, slug) DO NOTHING;

INSERT INTO public.gamification_rules (slug, display_name_i18n, description_i18n, base_points, trigger_source, organization_id) VALUES
  ('deliverable_completed',
   '{"pt-BR":"Entregável de tribo concluído","en-US":"Tribe deliverable completed","es-LATAM":"Entregable de tribu concluido"}'::jsonb,
   '{"pt-BR":"Trigger ao mudar tribe_deliverables.status para completed. Pago ao assigned_member."}'::jsonb,
   30, 'auto_trigger', '2b4f58ab-7c45-4170-8718-b77ee69ff906'),
  ('artifact_published',
   '{"pt-BR":"Ata rica publicada","en-US":"Rich minutes published","es-LATAM":"Acta rica publicada"}'::jsonb,
   '{"pt-BR":"Trigger ao mudar meeting_artifacts.is_published para true. Pago ao created_by."}'::jsonb,
   15, 'auto_trigger', '2b4f58ab-7c45-4170-8718-b77ee69ff906'),
  ('action_resolved',
   '{"pt-BR":"Ação da reunião resolvida","en-US":"Meeting action resolved","es-LATAM":"Acción de reunión resuelta"}'::jsonb,
   '{"pt-BR":"Trigger ao preencher meeting_action_items.resolved_at. Pago ao assignee_id."}'::jsonb,
   5, 'auto_trigger', '2b4f58ab-7c45-4170-8718-b77ee69ff906')
ON CONFLICT (organization_id, slug) DO NOTHING;

INSERT INTO public.gamification_rules (slug, display_name_i18n, description_i18n, base_points, trigger_source, organization_id) VALUES
  ('curation_doc_published',
   '{"pt-BR":"Versão de doc publicada (curador)","en-US":"Doc version published (curator)","es-LATAM":"Versión de doc publicada (curador)"}'::jsonb,
   '{"pt-BR":"Peak curatorial: publicar versão canônica de doc institucional."}'::jsonb,
   30, 'auto_trigger', '2b4f58ab-7c45-4170-8718-b77ee69ff906'),
  ('curation_ratification',
   '{"pt-BR":"Ratificação de gate assinada","en-US":"Ratification gate signed","es-LATAM":"Ratificación de gate firmada"}'::jsonb,
   '{"pt-BR":"Assinatura formal em gate de governança."}'::jsonb,
   25, 'auto_trigger', '2b4f58ab-7c45-4170-8718-b77ee69ff906'),
  ('curation_doc_authored',
   '{"pt-BR":"Versão de doc proposta (autor)","en-US":"Doc version proposed (author)","es-LATAM":"Versión de doc propuesta (autor)"}'::jsonb,
   '{"pt-BR":"Drafting de nova versão de doc (substantivo)."}'::jsonb,
   20, 'auto_trigger', '2b4f58ab-7c45-4170-8718-b77ee69ff906'),
  ('curation_doc_locked',
   '{"pt-BR":"Versão de doc travada","en-US":"Doc version locked","es-LATAM":"Versión de doc bloqueada"}'::jsonb,
   '{"pt-BR":"Lock formal de versão antes de publicação."}'::jsonb,
   10, 'auto_trigger', '2b4f58ab-7c45-4170-8718-b77ee69ff906'),
  ('curation_comment_resolved',
   '{"pt-BR":"Comentário em doc resolvido (resolver)","en-US":"Doc comment resolved (resolver)","es-LATAM":"Comentario en doc resuelto (resolvedor)"}'::jsonb,
   '{"pt-BR":"Resolver ganha o ponto (não o commenter — anti-farm)."}'::jsonb,
   5, 'auto_trigger', '2b4f58ab-7c45-4170-8718-b77ee69ff906')
ON CONFLICT (organization_id, slug) DO NOTHING;

-- ════════════════════════════════════════════════════════════
-- 3. champions_awarded — manual award ledger
-- ════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS public.champions_awarded (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  recipient_id uuid NOT NULL REFERENCES public.members(id),
  awarded_by uuid NOT NULL REFERENCES public.members(id),
  surface text NOT NULL CHECK (surface IN ('general','tribe','deliverable')),
  context_kind text NOT NULL CHECK (context_kind IN ('event','deliverable','artifact')),
  context_id uuid NOT NULL,
  criteria_met text[] NOT NULL CHECK (cardinality(criteria_met) >= 1 AND cardinality(criteria_met) <= 4),
  justification text NOT NULL CHECK (length(trim(justification)) >= 50),
  points_awarded integer NOT NULL CHECK (points_awarded >= 0),
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('active','revoked')),
  revoked_at timestamptz NULL,
  revoked_by uuid NULL REFERENCES public.members(id),
  revoked_reason text NULL,
  organization_id uuid NOT NULL REFERENCES public.organizations(id),
  initiative_id uuid NULL REFERENCES public.initiatives(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT champions_revocation_consistency CHECK (
    (status = 'revoked' AND revoked_at IS NOT NULL AND revoked_by IS NOT NULL AND revoked_reason IS NOT NULL)
    OR (status = 'active' AND revoked_at IS NULL AND revoked_by IS NULL AND revoked_reason IS NULL)
  ),
  CONSTRAINT champions_surface_initiative_consistency CHECK (
    (surface = 'general' AND initiative_id IS NULL)
    OR (surface IN ('tribe','deliverable') AND initiative_id IS NOT NULL)
  ),
  CONSTRAINT champions_no_self_award CHECK (recipient_id != awarded_by)
);

CREATE INDEX champions_awarded_recipient_idx
  ON public.champions_awarded (recipient_id, created_at DESC)
  WHERE status = 'active';

CREATE INDEX champions_awarded_awarded_by_idx
  ON public.champions_awarded (awarded_by, created_at DESC);

CREATE INDEX champions_awarded_initiative_idx
  ON public.champions_awarded (initiative_id, surface, status)
  WHERE initiative_id IS NOT NULL;

CREATE INDEX champions_awarded_context_idx
  ON public.champions_awarded (context_kind, context_id);

CREATE INDEX champions_awarded_org_status_idx
  ON public.champions_awarded (organization_id, status, created_at DESC);

ALTER TABLE public.champions_awarded ENABLE ROW LEVEL SECURITY;

CREATE POLICY champions_read_auth ON public.champions_awarded
  FOR SELECT TO authenticated
  USING (organization_id = public.auth_org());

GRANT SELECT ON public.champions_awarded TO authenticated;

COMMENT ON TABLE public.champions_awarded IS
'Ledger de Champions manuais com auditoria completa. Status=revoked preserva row para audit; XP é deletado de gamification_points via revoke_champion RPC. '
'Surfaces: general | tribe | deliverable. '
'Ver docs/reference/SEMANTIC_TAXONOMY.md Q5.';

COMMENT ON COLUMN public.champions_awarded.criteria_met IS
'Array de criterios objetivos marcados pelo grantor (1-4 itens). Ver SEMANTIC_TAXONOMY.md Q5.4.';

COMMENT ON COLUMN public.champions_awarded.justification IS
'Justificativa textual obrigatoria do grantor (>=50 chars). Audit-load-bearing.';

COMMENT ON COLUMN public.champions_awarded.points_awarded IS
'Pontuacao computada no momento do grant via gamification_rules. Imutavel apos criacao.';

-- ════════════════════════════════════════════════════════════
-- 4. V4 action 'award_champion' seed
-- ════════════════════════════════════════════════════════════
INSERT INTO public.engagement_kind_permissions (kind, role, action, scope, description, organization_id) VALUES
  ('volunteer','manager','award_champion','organization','GP — Champion em qualquer superficie','2b4f58ab-7c45-4170-8718-b77ee69ff906'),
  ('volunteer','co_gp','award_champion','organization','co-GP — Champion em qualquer superficie','2b4f58ab-7c45-4170-8718-b77ee69ff906'),
  ('volunteer','deputy_manager','award_champion','organization','Deputy manager — Champion em qualquer superficie','2b4f58ab-7c45-4170-8718-b77ee69ff906'),
  ('volunteer','comms_leader','award_champion','organization','Comms leader — Champion em qualquer superficie','2b4f58ab-7c45-4170-8718-b77ee69ff906'),
  ('volunteer','leader','award_champion','initiative','Lider de tribo — Champion na propria tribo + nos entregaveis dela','2b4f58ab-7c45-4170-8718-b77ee69ff906'),
  ('committee_member','leader','award_champion','initiative','Lider de committee — Champion nas reunioes/entregaveis do committee','2b4f58ab-7c45-4170-8718-b77ee69ff906'),
  ('study_group_owner','leader','award_champion','initiative','Lider de study group — Champion nas reunioes/entregaveis do grupo','2b4f58ab-7c45-4170-8718-b77ee69ff906'),
  ('study_group_owner','owner','award_champion','initiative','Owner de study group — Champion nas reunioes/entregaveis do grupo','2b4f58ab-7c45-4170-8718-b77ee69ff906'),
  ('workgroup_member','leader','award_champion','initiative','Lider de workgroup — Champion nas reunioes/entregaveis do workgroup','2b4f58ab-7c45-4170-8718-b77ee69ff906')
ON CONFLICT (kind, role, action) DO NOTHING;

NOTIFY pgrst, 'reload schema';

-- ════════════════════════════════════════════════════════════
-- Rollback
-- ════════════════════════════════════════════════════════════
-- DELETE FROM engagement_kind_permissions WHERE action = 'award_champion';
-- DROP TABLE IF EXISTS public.champions_awarded CASCADE;
-- DROP TABLE IF EXISTS public.gamification_rules CASCADE;
