-- p125 E1 Migration 3/8 — selection_application_service_history (1:N HISTÓRICA)
-- ADR-0076 Princípio 1: filiação HISTÓRICA / service history (append-only at submission)
-- Decision 2 (data-architect): table 1:N. The 4 denormalized counter columns
-- (service_history_count etc.) DO exist on selection_applications mas são SNAPSHOT-ONLY
-- (point-in-time at import, NOT live cache — ADR-0012 Principle 2 não aplica per Decision S5 Wave 3 synth).
-- Wave 1 draft (Wave 3 synth contradiction resolved via COMMENT-based snapshot semantics)
--
-- 171 historical roles for 97 candidates (avg 1.76, max 20 — LEONARDO CHAVES).
-- Append-only at submission. Retention 12 months per Decision 7 + cron extension migration 5/5.
--
-- Rollback: DROP TABLE selection_application_service_history CASCADE.

BEGIN;

CREATE TABLE IF NOT EXISTS public.selection_application_service_history (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  application_id uuid NOT NULL REFERENCES public.selection_applications(id) ON DELETE CASCADE,
  chapter_name text NOT NULL,
  role_name text,
  start_date date,
  end_date date,
  source text NOT NULL CHECK (source IN ('pmi_community','pmi_vep','manual')),
  captured_at timestamptz NOT NULL DEFAULT now(),
  created_at timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.selection_application_service_history IS
  '1:N historical PMI volunteer service per application. Append-only at submission. AI triage signal V2 (Cycle 4+) — distinct chapters served, total count, recency. ADR-0076 Princípio 1.

  Não normalizar chapter_name para FK contra chapter_registry — international chapters (ex: Silicon Valley, Washington DC) não existem no registry brasileiro.

  LGPD base legal: Art. 7 IX (legítimo interesse). Retention: linked to selection_applications retention. Applicant rejected 12+ months → DELETE rows via cron (Decision 7 + ADR-0076 Princípio 6).

  Trentim Path B firewall: data persisted under este modelo é para selection only. Commercial use requires new CR. ADR-0076 Princípio 7.';

COMMENT ON COLUMN public.selection_application_service_history.chapter_name IS
  'Free text chapter name from PMI source. NOT FK normalized — international chapters preserved as-is.';

COMMENT ON COLUMN public.selection_application_service_history.source IS
  'Provenance: pmi_community (Phase B) | pmi_vep (Phase A) | manual.';

-- ─── Indexes ────────────────────────────────────────────────────────────────
-- Primary: aggregate per application (count, distinct chapters, etc.)
CREATE INDEX IF NOT EXISTS idx_service_history_application_id
  ON public.selection_application_service_history (application_id);

-- Secondary: analytics queries (which chapters most represented)
CREATE INDEX IF NOT EXISTS idx_service_history_chapter_role
  ON public.selection_application_service_history (chapter_name, role_name);

-- Tertiary: temporal queries (recent service)
CREATE INDEX IF NOT EXISTS idx_service_history_start_date
  ON public.selection_application_service_history (start_date DESC NULLS LAST)
  WHERE start_date IS NOT NULL;

-- ─── RLS at-creation ────────────────────────────────────────────────────────
ALTER TABLE public.selection_application_service_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.selection_application_service_history FORCE ROW LEVEL SECURITY;

CREATE POLICY service_history_deny_anon
ON public.selection_application_service_history
FOR ALL
TO anon
USING (false);

-- Authenticated com view_pii OR promote (selection committee scope)
CREATE POLICY service_history_view_pii_select
ON public.selection_application_service_history
FOR SELECT
TO authenticated
USING (public.rls_can('view_pii') OR public.rls_can('promote'));

CREATE POLICY service_history_service_role_all
ON public.selection_application_service_history
FOR ALL
TO service_role
USING (true)
WITH CHECK (true);

COMMIT;

-- Post-apply checklist:
--   1. supabase migration repair --status applied 20260518020000
--   2. NOTIFY pgrst, 'reload schema'
--   3. Verify RLS + policies (3 policies expected)
--   4. Verify FK CASCADE on application_id
