-- Wave 3a (DB foundation) #740 — durable chapter model: member_chapter_affiliations + entry_chapter_code
--
-- WHAT (additive, zero behavior change to existing reads):
--   1. Seed the BR chapters that appear in live member/affiliation data into
--      chapter_registry (so the new FK targets exist). GO stays the ONLY
--      is_contracting_chapter (the signatory — see C3, Wave 3a-ii).
--   2. Create public.member_chapter_affiliations (N:N FACT): one row per chapter a
--      person is affiliated with. Keyed on person_id (ADR-0006 identity primitive).
--   3. Add members.entry_chapter_code (single GOVERNANCE choice; FK chapter_registry;
--      NULL until the member chooses — the choice UI + BR-only enforcement land in
--      Wave 3b's set_my_entry_chapter RPC).
--   4. Backfill the FACT table from the legacy single value members.chapter
--      (source='legacy', is_primary=true). The richer multi-chapter population from
--      the reliable pmi_memberships snapshot is owned by the pmi-vep-sync worker
--      (Wave 3a-iii), which already maps "<State>, Brazil Chapter" → PMI-XX codes —
--      so we do NOT duplicate that name→code map in SQL here.
--
-- WHY: Issue #740 Wave 3, per ADR-0104. A member's chapter had 4 inconsistent
--      derivations, none canonical. This establishes the two canonical sources:
--      member_chapter_affiliations (fact) + members.entry_chapter_code (choice).
--      members.chapter is NOT yet repointed to a derived value (kept as-is); that
--      repoint happens once entry_chapter_code is populated (later step), to keep
--      this migration purely additive.
--
-- NOTE on chapter_registry seed: legal_name / CNPJ for the non-contracting chapters
--      are informational (only GO signs the volunteer agreement). legal_name uses the
--      canonical PMI chapter display name; CNPJ stays NULL pending confirmation.
--
-- RLS: rpc_only_deny_all (USING false) — the table is reachable only by SECURITY
--      DEFINER RPCs (definer bypasses RLS) and the worker (service_role bypasses RLS),
--      mirroring the member_emails pattern (ADR-0095). anon SELECT revoked (LGPD).
--
-- ROLLBACK (in order): DROP TABLE public.member_chapter_affiliations (CASCADE removes
--      its FK rows so the seeded chapters become deletable); ALTER TABLE public.members
--      DROP COLUMN entry_chapter_code; then DELETE the 8 seeded chapter_registry rows
--      (PE/PR/RJ/SP/BA/ES/SC/SE).

BEGIN;

-- 1. Seed BR chapters present in live data (members.chapter + pmi_memberships).
INSERT INTO public.chapter_registry (chapter_code, legal_name, state, country, is_contracting_chapter, is_active, display_order)
VALUES
  ('PE', 'PMI Pernambuco, Brazil Chapter',      'Pernambuco',       'BR', false, true, 6),
  ('PR', 'PMI Paraná, Brazil Chapter',          'Paraná',           'BR', false, true, 7),
  ('RJ', 'PMI Rio de Janeiro, Brazil Chapter',  'Rio de Janeiro',   'BR', false, true, 8),
  ('SP', 'PMI São Paulo, Brazil Chapter',       'São Paulo',        'BR', false, true, 9),
  ('BA', 'PMI Bahia, Brazil Chapter',           'Bahia',            'BR', false, true, 10),
  ('ES', 'PMI Espírito Santo, Brazil Chapter',  'Espírito Santo',   'BR', false, true, 11),
  ('SC', 'PMI Santa Catarina, Brazil Chapter',  'Santa Catarina',   'BR', false, true, 12),
  ('SE', 'PMI Sergipe, Brazil Chapter',         'Sergipe',          'BR', false, true, 13)
ON CONFLICT (chapter_code) DO NOTHING;

-- 2. Durable N:N fact table.
CREATE TABLE IF NOT EXISTS public.member_chapter_affiliations (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  person_id    uuid NOT NULL REFERENCES public.persons(id) ON DELETE CASCADE,
  chapter_code text NOT NULL REFERENCES public.chapter_registry(chapter_code) ON DELETE RESTRICT,
  source       text NOT NULL CHECK (source IN ('pmi_vep', 'admin_import', 'self_declared', 'legacy')),
  is_primary   boolean NOT NULL DEFAULT false,
  verified_at  timestamptz,
  created_at   timestamptz NOT NULL DEFAULT now(),
  updated_at   timestamptz NOT NULL DEFAULT now(),
  UNIQUE (person_id, chapter_code)
);

COMMENT ON TABLE public.member_chapter_affiliations IS
  'Wave 3a #740 / ADR-0104 — FACT: chapters a person is affiliated with (N:N). Fed by the pmi-vep-sync worker (source=pmi_vep) + legacy backfill (source=legacy). NOT the member''s entry choice — that is members.entry_chapter_code.';

-- Exactly one primary affiliation per person.
CREATE UNIQUE INDEX IF NOT EXISTS member_chapter_affiliations_one_primary_idx
  ON public.member_chapter_affiliations (person_id) WHERE (is_primary = true);
CREATE INDEX IF NOT EXISTS member_chapter_affiliations_chapter_idx
  ON public.member_chapter_affiliations (chapter_code);

ALTER TABLE public.member_chapter_affiliations ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS rpc_only_deny_all ON public.member_chapter_affiliations;
CREATE POLICY rpc_only_deny_all
  ON public.member_chapter_affiliations
  AS PERMISSIVE FOR ALL TO public
  USING (false);
-- Full lockdown for anon + authenticated (incl. SELECT) — mirrors member_emails
-- 20260802000009. RLS USING(false) is the primary guard (verified: a SET ROLE
-- authenticated SELECT returns "permission denied"); this REVOKE is defense-in-depth.
REVOKE ALL ON public.member_chapter_affiliations FROM anon;
REVOKE ALL ON public.member_chapter_affiliations FROM authenticated;

-- 3. Member's chosen chapter of entry (governance). NULL until chosen (Wave 3b).
ALTER TABLE public.members
  ADD COLUMN IF NOT EXISTS entry_chapter_code text REFERENCES public.chapter_registry(chapter_code) ON DELETE SET NULL;
COMMENT ON COLUMN public.members.entry_chapter_code IS
  'Wave 3a #740 / ADR-0104 — member-chosen chapter of entry (single GOVERNANCE value). FK chapter_registry. BR-only enforced by set_my_entry_chapter RPC (Wave 3b). NULL until chosen; members.chapter stays the legacy/compat value for now.';

-- 4. Backfill the fact table from the legacy single value members.chapter
--    (strip the "PMI-" prefix → chapter_registry code). DISTINCT ON guarantees one
--    primary row per person; the IN (...) filter skips non-chapter values like 'Outro'.
INSERT INTO public.member_chapter_affiliations (person_id, chapter_code, source, is_primary)
SELECT DISTINCT ON (m.person_id)
  m.person_id,
  regexp_replace(m.chapter, '^PMI-', '') AS code,
  'legacy',
  true
FROM public.members m
WHERE m.is_active
  AND m.person_id IS NOT NULL
  AND m.chapter IS NOT NULL
  AND regexp_replace(m.chapter, '^PMI-', '') IN (SELECT chapter_code FROM public.chapter_registry)
ORDER BY m.person_id, m.created_at
ON CONFLICT (person_id, chapter_code) DO NOTHING;

NOTIFY pgrst, 'reload schema';

COMMIT;
