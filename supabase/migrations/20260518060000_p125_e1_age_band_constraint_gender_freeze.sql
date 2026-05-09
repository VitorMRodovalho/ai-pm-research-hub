-- p125 E1 Migration 6/8 — age_band CHECK constraint + gender out-of-scope freeze
-- Decision S1 (Wave 3 synth 2026-05-09): gender NÃO usado em analytics; age_band voluntário enum
-- ADR-0076 Princípio 8 (revised)
-- Wave 1 draft (Wave 3 synth additions)
--
-- Adds:
--   1. CHECK constraint enum em age_band: ('18-25','26-35','36-50','50+','prefer_not_to_say')
--   2. COMMENT ON COLUMN documentando gender out-of-scope para analytics
--   3. COMMENT ON COLUMN documentando age_band escopo voluntário
--
-- Status legacy gender data (70/103 Cycle 3): mantido para human review individual,
-- mas EXCLUDED de qualquer pipeline analytics. Termo voluntariado v3 NÃO pede gender.
--
-- Rollback: ALTER TABLE selection_applications DROP CONSTRAINT age_band_enum_check;
--           COMMENT ON COLUMN ... reset.

BEGIN;

-- ─── age_band CHECK constraint enum ────────────────────────────────────────
-- Existing column age_band is text NULLABLE. Add CHECK constraint enforcing enum.
-- NOT NULL não usado — age_band é VOLUNTÁRIO (opt-in via termo v3 ou survey)
ALTER TABLE public.selection_applications
  ADD CONSTRAINT age_band_enum_check
  CHECK (age_band IS NULL OR age_band IN ('18-25','26-35','36-50','50+','prefer_not_to_say'));

COMMENT ON COLUMN public.selection_applications.age_band IS
  'Optional self-declared age band. Enum: 18-25 / 26-35 / 36-50 / 50+ / prefer_not_to_say. NULL = não declarado (sem implicação). Base legal: Art. 7 IX (LIA específica para analytics). Capture: voluntário no termo voluntariado v3 ou survey post-submit. NUNCA capturar birth_date ou idade exata. ADR-0076 Princípio 8 (revised Decision S1) + Decision 6.';

-- ─── gender out-of-scope COMMENT ────────────────────────────────────────────
COMMENT ON COLUMN public.selection_applications.gender IS
  'Legacy field (Cycle 3: 70/103 populated). OUT OF E4 ANALYTICS SCOPE per Decision S1 (Wave 3 synth 2026-05-09). Mantido para human review individual em admin UI. NÃO entra em get_diversity_aggregate_csv() nem qualquer RPC SECDEF agregado. Cycle 4+ termo voluntariado v3 NÃO pede gender. Diversity reporting via gender (se desejado): survey voluntário separado pós-decisão de seleção, fora escopo p125. Rationale: nome PT-BR já implicitamente revela gender; coletar separado adiciona LGPD risk (ANPD interpreta gender em analytics agregada como Art. 11 sensível) sem ganho analítico real. ADR-0076 Princípio 8.';

-- ─── Forward-looking: trigger guarding gender from analytics RPCs ───────────
-- Implementação ficará a cargo do E4a Wave 1 (RPC SECDEF que NÃO inclui gender em columns selecionadas).
-- Defense em depth aqui: COMMENT serve de signal documental. Pode evoluir para column-level
-- security GRANT REVOKE em Cycle 5+ se desejado (mas YAGNI hoje).

COMMIT;

-- Post-apply checklist:
--   1. supabase migration repair --status applied 20260518060000
--   2. Verify constraint: SELECT conname, pg_get_constraintdef(oid) FROM pg_constraint
--      WHERE conrelid = 'public.selection_applications'::regclass AND conname = 'age_band_enum_check';
--   3. Smoke test: INSERT com age_band='invalid' deve falhar
--   4. Smoke test: INSERT com age_band='30-40' deve falhar (não é enum)
--   5. Smoke test: INSERT com age_band='26-35' deve passar
