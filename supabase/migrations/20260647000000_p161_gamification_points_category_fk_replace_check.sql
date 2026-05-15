-- p161 Fase 2 hotfix — Replace gamification_points.category CHECK with FK to gamification_rules
-- Refs: docs/reference/SEMANTIC_TAXONOMY.md Q7 (config-driven) + Fase 1 (rules table)
-- Discovery: smoke caught CHECK constraint blocking champion_* categories.
-- Decision: align category surface with rules config table; FK enforces "rule exists before points use category".

-- 1. Drop the hardcoded CHECK
ALTER TABLE public.gamification_points
  DROP CONSTRAINT IF EXISTS gamification_points_category_check;

-- 2. Add composite FK enforcing (org_id, category) maps to (org_id, slug) in rules
--    ON DELETE RESTRICT: prevent rule deletion if points exist (preserve audit)
--    ON UPDATE CASCADE: allow slug rename to propagate (rare; admin operation)
ALTER TABLE public.gamification_points
  ADD CONSTRAINT gamification_points_category_fk
    FOREIGN KEY (organization_id, category)
    REFERENCES public.gamification_rules (organization_id, slug)
    ON DELETE RESTRICT
    ON UPDATE CASCADE
    DEFERRABLE INITIALLY DEFERRED;

COMMENT ON CONSTRAINT gamification_points_category_fk ON public.gamification_points IS
'FK to gamification_rules ensures category must reference a seeded rule (admin adds via /admin/gamification/rules). Replaces hardcoded CHECK (Fase 1+2 ADR-0009 alignment). ON DELETE RESTRICT preserves audit; ON UPDATE CASCADE handles rare slug renames. Deferred for trigger-friendly atomicity.';

NOTIFY pgrst, 'reload schema';

-- Rollback:
-- ALTER TABLE gamification_points DROP CONSTRAINT gamification_points_category_fk;
-- ALTER TABLE gamification_points ADD CONSTRAINT gamification_points_category_check
--   CHECK (category IN ('attendance','course','artifact','bonus','trail','cert_pmi_senior',
--     'cert_cpmai','cert_pmi_mid','cert_pmi_practitioner','cert_pmi_entry','specialization',
--     'knowledge_ai_pm','badge','showcase'));
