-- p162 Fase A.1 — pillar column on gamification_rules
-- Refs: docs/adr/ADR-0081 + PM ratification (p162 batch 5) — transparency UI
-- Maps each rule to a pillar for member-facing XP breakdown
-- 6 pillars: presenca | trilha | certificacoes | producao | curadoria | champions

ALTER TABLE public.gamification_rules
  ADD COLUMN IF NOT EXISTS pillar text;

UPDATE public.gamification_rules SET pillar = CASE slug
  WHEN 'attendance' THEN 'presenca'
  WHEN 'trail' THEN 'trilha'
  WHEN 'knowledge_ai_pm' THEN 'trilha'
  WHEN 'specialization' THEN 'trilha'
  WHEN 'course' THEN 'trilha'
  WHEN 'cert_pmi_entry' THEN 'certificacoes'
  WHEN 'cert_pmi_mid' THEN 'certificacoes'
  WHEN 'cert_pmi_practitioner' THEN 'certificacoes'
  WHEN 'cert_pmi_senior' THEN 'certificacoes'
  WHEN 'cert_cpmai' THEN 'certificacoes'
  WHEN 'badge' THEN 'certificacoes'
  WHEN 'deliverable_completed' THEN 'producao'
  WHEN 'artifact_published' THEN 'producao'
  WHEN 'action_resolved' THEN 'producao'
  WHEN 'showcase' THEN 'producao'
  WHEN 'curation_doc_authored' THEN 'curadoria'
  WHEN 'curation_doc_locked' THEN 'curadoria'
  WHEN 'curation_doc_published' THEN 'curadoria'
  WHEN 'curation_ratification' THEN 'curadoria'
  WHEN 'curation_comment_resolved' THEN 'curadoria'
  WHEN 'champion_general' THEN 'champions'
  WHEN 'champion_tribe' THEN 'champions'
  WHEN 'champion_deliverable' THEN 'champions'
END
WHERE pillar IS NULL;

ALTER TABLE public.gamification_rules
  ALTER COLUMN pillar SET NOT NULL;

ALTER TABLE public.gamification_rules
  ADD CONSTRAINT gamification_rules_pillar_check
    CHECK (pillar IN ('presenca','trilha','certificacoes','producao','curadoria','champions'));

CREATE INDEX IF NOT EXISTS gamification_rules_pillar_idx
  ON public.gamification_rules (organization_id, pillar)
  WHERE active = true;

COMMENT ON COLUMN public.gamification_rules.pillar IS
'Pillar grouping for member-facing XP transparency UI. 6 buckets: presenca|trilha|certificacoes|producao|curadoria|champions. Config-driven (admin can regroup via /admin/gamification rules edit form). Ver ADR-0081 + SEMANTIC_TAXONOMY.md.';

NOTIFY pgrst, 'reload schema';

-- Rollback:
-- DROP INDEX IF EXISTS public.gamification_rules_pillar_idx;
-- ALTER TABLE public.gamification_rules DROP CONSTRAINT IF EXISTS gamification_rules_pillar_check;
-- ALTER TABLE public.gamification_rules DROP COLUMN IF EXISTS pillar;
