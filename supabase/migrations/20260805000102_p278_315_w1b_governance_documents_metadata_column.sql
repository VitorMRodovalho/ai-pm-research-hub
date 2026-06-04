-- #315 Wave-1b foundation — add governance_documents.metadata jsonb.
--
-- WHY (ratified 2026-05-24, SPEC_GOVERNANCE_DOCUMENTS_END_TO_END.md §19.2):
--   P1-Q1: ip_policy / privacy_policy are doc_type='policy' + metadata.subtype (NOT new doc_types).
--   P1-Q3: template_role = 'instance' | 'template' lives in metadata (avoids a 'template' doc_type
--          that would collide with volunteer_term_template).
--   Neither could be persisted: governance_documents had no metadata column. This is the Wave-1b
--   blocker the PM re-affirmed (do NOT re-decide taxonomy / do NOT re-run legal — already ratified).
--
-- SCOPE: foundation only — the storage substrate + ratified-shape guards. Wiring the intake RPC
--   (create_governance_document_intake) to persist subtype/template_role and the reader RPCs to
--   surface them is the next leaf (follow-up), not this PR.
--
-- The CHECK guards ONLY the two ratified keys WHEN present; metadata stays a free bag for other
-- keys (e.g. legacy_migration, method). NOT NULL DEFAULT '{}' so consumers never null-check.
--
-- ROLLBACK:
--   ALTER TABLE public.governance_documents DROP CONSTRAINT governance_documents_metadata_ratified_keys_check;
--   ALTER TABLE public.governance_documents DROP COLUMN metadata;
--
-- NOTE: ADD COLUMN is idempotent (IF NOT EXISTS); ADD CONSTRAINT is forward-only (Postgres has no
-- IF NOT EXISTS for CHECK constraints) — standard for this repo's forward-only apply_migration flow.
-- FOLLOW-UP (intake RPC leaf, NOT this PR): create_governance_document_intake must (a) require
-- doc_type='policy' before writing metadata.subtype, and (b) never write an explicit JSON null for
-- a guarded key (the CHECK treats null-in-list as a violation).

ALTER TABLE public.governance_documents
  ADD COLUMN IF NOT EXISTS metadata jsonb NOT NULL DEFAULT '{}'::jsonb;

ALTER TABLE public.governance_documents
  ADD CONSTRAINT governance_documents_metadata_ratified_keys_check
  CHECK (
    (NOT (metadata ? 'template_role') OR metadata->>'template_role' IN ('instance', 'template'))
    AND
    (NOT (metadata ? 'subtype') OR metadata->>'subtype' IN ('ip_policy', 'privacy_policy'))
  );

COMMENT ON COLUMN public.governance_documents.metadata IS
  '#315 Wave-1b foundation. JSONB bag for ratified taxonomy keys: subtype (P1-Q1: ip_policy|privacy_policy, for doc_type=policy) and template_role (P1-Q3: instance|template). Other keys allowed; only these two are value-guarded by governance_documents_metadata_ratified_keys_check.';

NOTIFY pgrst, 'reload schema';
