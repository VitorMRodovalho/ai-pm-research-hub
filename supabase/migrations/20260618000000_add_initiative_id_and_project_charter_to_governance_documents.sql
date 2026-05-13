-- Wave 1 / OPP-153.1: TAP digital
-- Adds initiative_id link + 'project_charter' as accepted doc_type for governance_documents.
-- See docs/drafts/v2.7_p153_tap_cpmai_handoff.md

-- 1) Add initiative_id column (nullable; existing docs are organization-scoped, not initiative-scoped)
ALTER TABLE public.governance_documents
  ADD COLUMN IF NOT EXISTS initiative_id uuid REFERENCES public.initiatives(id) ON DELETE SET NULL;

-- 2) Index for queries by initiative
CREATE INDEX IF NOT EXISTS idx_governance_documents_initiative_id
  ON public.governance_documents(initiative_id)
  WHERE initiative_id IS NOT NULL;

-- 3) Extend doc_type CHECK to include 'project_charter' (TAP)
ALTER TABLE public.governance_documents
  DROP CONSTRAINT IF EXISTS governance_documents_doc_type_check;

ALTER TABLE public.governance_documents
  ADD CONSTRAINT governance_documents_doc_type_check
  CHECK (doc_type = ANY (ARRAY[
    'manual'::text,
    'cooperation_agreement'::text,
    'framework_reference'::text,
    'cooperation_addendum'::text,
    'volunteer_addendum'::text,
    'policy'::text,
    'volunteer_term_template'::text,
    'executive_summary'::text,
    'project_charter'::text
  ]));

COMMENT ON COLUMN public.governance_documents.initiative_id IS
  'Optional link to initiatives table. Populated for project-scoped governance docs (e.g. project_charter / TAP). NULL for organization-wide docs (cooperation, manuals, policies).';
