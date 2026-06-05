-- WHAT: Wave 1b leaf #312-W4a (p262 — #378 SHIPS) — minimum gate templates for 6 doc_types
-- Currently resolve_default_gates(p_doc_type) returns NULL for: editorial_guide,
-- governance_guideline, project_charter, manual, executive_summary, framework_reference.
-- DocumentVersionEditor.tsx:117 sets gatesUnsupported=true when NULL → lock modal disabled.
-- This migration adds 6 new CASE branches with PM-ratified minimum templates so the editor
-- lock flow works end-to-end for these doc_types (especially Frontiers editorial_guide which
-- transitioned to draft via #377).
--
-- WHY: p260 audit §10.1 + §5 surfaced gate template coverage gap (6 of 11 NULL). PM ratified
-- D1 at audit close as v1-must Wave 4a; dispatch sequence 2/7 (after #377 sign_proposer_consent).
-- After #378 ships, Frontiers editorial_guide can advance draft → under_review via editor lock.
--
-- SPEC: SPEC_GOVERNANCE_DOCUMENTS_END_TO_END.md §4.3 (approval flow) + §5.2 (status transitions)
-- + §10 #312 + p260 audit §11 #312-W4a proposed templates (PM ratified in this PR).
--
-- SCOPE LOCK: 1 RPC body change adding 6 CASE branches. Existing 5 doc_type branches preserved
-- byte-identical. No new tables, columns, RLS, or invariants. Frontend DocumentVersionEditor.tsx
-- unchanged (it already handles non-NULL gate arrays correctly).
--
-- PM-RATIFIED GATE TEMPLATES (audit doc §11 proposals):
--   editorial_guide:      curator(1,all) + leader_awareness(2,0) + submitter_acceptance(3,1)
--   governance_guideline: curator(1,all) + leader_awareness(2,0) + submitter_acceptance(3,1)
--   manual:               curator(1,all) + leader_awareness(2,0) + submitter_acceptance(3,1)
--                         + president_go(4,1) + president_others(5,4)  (mirrors policy)
--   executive_summary:    curator(1,all) + submitter_acceptance(2,1)  (minimal — consumer)
--   framework_reference:  curator(1,all) + leader_awareness(2,0) + submitter_acceptance(3,1)
--   project_charter:      curator(1,all) + leader_awareness(2,0)  (initiative-internal — TAPs)
--
-- ROLLBACK: CREATE OR REPLACE FUNCTION public.resolve_default_gates(p_doc_type text)
--   with body equal to the live state pre-p262 (5 covered + ELSE NULL).
--
-- INVARIANTS: No invariant change. V'_prime + V_status_chain_coherence continue to report
-- violation_count=0 (this RPC is a pure helper, doesn't touch any governed table state).
--
-- CROSS-REF: #312 audit umbrella + #315 Governance Documents v1 + #96 Frontiers + #378
-- (this child) + #377 (predecessor sequence 1/7) + p260 audit §11 proposals + p262 PM ratify.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.resolve_default_gates(p_doc_type text)
RETURNS jsonb
LANGUAGE sql
SET search_path TO 'public', 'pg_temp'
AS $$
  SELECT CASE p_doc_type
    WHEN 'cooperation_agreement' THEN '[
      {"kind":"curator","order":1,"threshold":"all"},
      {"kind":"leader_awareness","order":2,"threshold":0},
      {"kind":"submitter_acceptance","order":3,"threshold":1},
      {"kind":"chapter_witness","order":4,"threshold":5},
      {"kind":"president_go","order":5,"threshold":1},
      {"kind":"president_others","order":6,"threshold":4}
    ]'::jsonb
    WHEN 'cooperation_addendum' THEN '[
      {"kind":"curator","order":1,"threshold":"all"},
      {"kind":"leader_awareness","order":2,"threshold":0},
      {"kind":"submitter_acceptance","order":3,"threshold":1},
      {"kind":"chapter_witness","order":4,"threshold":5},
      {"kind":"president_go","order":5,"threshold":1},
      {"kind":"president_others","order":6,"threshold":4}
    ]'::jsonb
    WHEN 'volunteer_term_template' THEN '[
      {"kind":"curator","order":1,"threshold":"all"},
      {"kind":"leader_awareness","order":2,"threshold":0},
      {"kind":"submitter_acceptance","order":3,"threshold":1},
      {"kind":"president_go","order":4,"threshold":1},
      {"kind":"volunteers_in_role_active","order":5,"threshold":"all"}
    ]'::jsonb
    WHEN 'volunteer_addendum' THEN '[
      {"kind":"curator","order":1,"threshold":"all"},
      {"kind":"leader_awareness","order":2,"threshold":0},
      {"kind":"submitter_acceptance","order":3,"threshold":1},
      {"kind":"president_go","order":4,"threshold":1},
      {"kind":"volunteers_in_role_active","order":5,"threshold":"all"}
    ]'::jsonb
    WHEN 'policy' THEN '[
      {"kind":"curator","order":1,"threshold":"all"},
      {"kind":"leader_awareness","order":2,"threshold":0},
      {"kind":"submitter_acceptance","order":3,"threshold":1},
      {"kind":"president_go","order":4,"threshold":1},
      {"kind":"president_others","order":5,"threshold":4}
    ]'::jsonb
    WHEN 'editorial_guide' THEN '[
      {"kind":"curator","order":1,"threshold":"all"},
      {"kind":"leader_awareness","order":2,"threshold":0},
      {"kind":"submitter_acceptance","order":3,"threshold":1}
    ]'::jsonb
    WHEN 'governance_guideline' THEN '[
      {"kind":"curator","order":1,"threshold":"all"},
      {"kind":"leader_awareness","order":2,"threshold":0},
      {"kind":"submitter_acceptance","order":3,"threshold":1}
    ]'::jsonb
    WHEN 'manual' THEN '[
      {"kind":"curator","order":1,"threshold":"all"},
      {"kind":"leader_awareness","order":2,"threshold":0},
      {"kind":"submitter_acceptance","order":3,"threshold":1},
      {"kind":"president_go","order":4,"threshold":1},
      {"kind":"president_others","order":5,"threshold":4}
    ]'::jsonb
    WHEN 'executive_summary' THEN '[
      {"kind":"curator","order":1,"threshold":"all"},
      {"kind":"submitter_acceptance","order":2,"threshold":1}
    ]'::jsonb
    WHEN 'framework_reference' THEN '[
      {"kind":"curator","order":1,"threshold":"all"},
      {"kind":"leader_awareness","order":2,"threshold":0},
      {"kind":"submitter_acceptance","order":3,"threshold":1}
    ]'::jsonb
    WHEN 'project_charter' THEN '[
      {"kind":"curator","order":1,"threshold":"all"},
      {"kind":"leader_awareness","order":2,"threshold":0}
    ]'::jsonb
    ELSE NULL
  END;
$$;

-- Sanity DO RAISES if any of the 11 expected doc_types still returns NULL post-deploy.
DO $$
DECLARE
  v_dt text;
  v_doc_types text[] := ARRAY[
    'cooperation_agreement', 'cooperation_addendum', 'volunteer_term_template',
    'volunteer_addendum', 'policy', 'editorial_guide', 'governance_guideline',
    'manual', 'executive_summary', 'framework_reference', 'project_charter'
  ];
  v_null_count int := 0;
BEGIN
  FOREACH v_dt IN ARRAY v_doc_types LOOP
    IF public.resolve_default_gates(v_dt) IS NULL THEN
      v_null_count := v_null_count + 1;
      RAISE WARNING 'p262 #312-W4a: resolve_default_gates returns NULL for %', v_dt;
    END IF;
  END LOOP;
  IF v_null_count > 0 THEN
    RAISE EXCEPTION 'p262 #312-W4a: % of 11 doc_types still return NULL from resolve_default_gates', v_null_count;
  END IF;
END $$;

NOTIFY pgrst, 'reload schema';
