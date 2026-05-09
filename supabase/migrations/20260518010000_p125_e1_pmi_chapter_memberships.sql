-- p125 E1 Migration 2/5 — pmi_chapter_memberships table (canonical multi-chapter)
-- ADR-0076 Princípio 1: filiação ATUAL multi-chapter (canonical, queryable)
-- Decision 2: HÍBRIDO — snapshot in selection_applications.pmi_memberships JSONB +
--              canonical here. Cron compliance E3 queries here (B-tree index).
-- Wave 1 draft (council review pending Wave 2)
--
-- Atomicity: this table standalone — não bloqueia by E2 worker (mapper UPSERTs into it).
--
-- Rollback: DROP TABLE pmi_chapter_memberships CASCADE.

BEGIN;

CREATE TABLE IF NOT EXISTS public.pmi_chapter_memberships (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  person_id uuid NOT NULL REFERENCES public.persons(id) ON DELETE CASCADE,
  chapter_name text NOT NULL,
  chapter_id_pmi integer,  -- PMI chapter numeric ID (optional, from Community API)
  expiry_date date NOT NULL,
  source text NOT NULL CHECK (source IN ('pmi_community','pmi_vep','manual')),
  captured_at timestamptz NOT NULL DEFAULT now(),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (person_id, chapter_name)
);

COMMENT ON TABLE public.pmi_chapter_memberships IS
  'Canonical live registry of candidate''s multi-chapter PMI membership. Source for E3 cron compliance D-60/D-30/D-7 queries. Mutable — evolves with renewals. Snapshot at submission preserved separately em selection_applications.pmi_memberships JSONB. ADR-0076 Princípio 1 + Decision 2.

  Trentim Path B firewall: data persisted under este modelo é para selection + operational governance only. Commercial use (consulting, white-label, sale) requires new CR approved by all 5 ratifying chapters via approval_chains workflow. ADR-0076 Princípio 7.

  LGPD base legal: Art. 7 IX (legítimo interesse) — LIA documentada em ADR-0076 Princípio 2. Retention: linked to persons retention (5y inactivity) — anonymize_inactive_members extension required to CASCADE clear (Risk 2 pre-mortem; migration 5/5).';

COMMENT ON COLUMN public.pmi_chapter_memberships.expiry_date IS
  'PMI membership expiry per chapter. Source for compliance reminders. NOT same as engagements.end_date (Núcleo termo) — TWO timelines per ADR-0076 Princípio 5.';

COMMENT ON COLUMN public.pmi_chapter_memberships.source IS
  'Provenance: pmi_community (Phase B scrape) | pmi_vep (Phase A) | manual (chapter VP entry). Affects cron alert confidence per ADR-0076 Princípio 5.';

-- ─── Indexes ────────────────────────────────────────────────────────────────
-- Primary access pattern: E3 cron query "expiring soon for person X"
CREATE INDEX IF NOT EXISTS idx_pmi_chapter_memberships_person_expiry
  ON public.pmi_chapter_memberships (person_id, expiry_date);

-- Secondary: aggregate "expiring soon across all" for cron sweep
CREATE INDEX IF NOT EXISTS idx_pmi_chapter_memberships_expiry_only
  ON public.pmi_chapter_memberships (expiry_date)
  WHERE expiry_date >= current_date - interval '30 days';

-- Tertiary: source filtering for confidence-aware queries
CREATE INDEX IF NOT EXISTS idx_pmi_chapter_memberships_source
  ON public.pmi_chapter_memberships (source);

-- ─── updated_at trigger ─────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.set_pmi_chapter_memberships_updated_at()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END $$;

CREATE TRIGGER trg_pmi_chapter_memberships_updated_at
BEFORE UPDATE ON public.pmi_chapter_memberships
FOR EACH ROW EXECUTE FUNCTION public.set_pmi_chapter_memberships_updated_at();

-- ─── RLS at-creation (security-engineer Wave 2 watch-out) ───────────────────
ALTER TABLE public.pmi_chapter_memberships ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pmi_chapter_memberships FORCE ROW LEVEL SECURITY;

-- Default deny (anon, authenticated without view_pii)
CREATE POLICY pmi_chapter_memberships_deny_anon
ON public.pmi_chapter_memberships
FOR ALL
TO anon
USING (false);

-- Authenticated members with view_pii action via rls_can helper (ADR-0011)
CREATE POLICY pmi_chapter_memberships_view_pii_select
ON public.pmi_chapter_memberships
FOR SELECT
TO authenticated
USING (public.rls_can('view_pii'));

-- Service role for worker E2 ingest + admin tools
CREATE POLICY pmi_chapter_memberships_service_role_all
ON public.pmi_chapter_memberships
FOR ALL
TO service_role
USING (true)
WITH CHECK (true);

-- ─── pii_access_log integration (audit on SELECT — handled at RPC layer) ────
-- Per security-engineer recommendation: log per-RPC call não per row read.
-- RPCs that return pmi_chapter_memberships data MUST insert into pii_access_log.
-- Pattern documented em ADR-0076 + reference RPCs in E3 Wave 1.

COMMIT;

-- Post-apply checklist (CLAUDE.md GC-097):
--   1. supabase migration repair --status applied 20260518010000
--   2. NOTIFY pgrst, 'reload schema'
--   3. Verify: SELECT relrowsecurity, relforcerowsecurity FROM pg_class
--             WHERE relname='pmi_chapter_memberships' (both should be true)
--   4. Verify: SELECT polname FROM pg_policy WHERE polrelid =
--             'public.pmi_chapter_memberships'::regclass (3 policies expected)
--   5. Verify FK CASCADE: \d pmi_chapter_memberships shows
--             "ON DELETE CASCADE" for person_id
