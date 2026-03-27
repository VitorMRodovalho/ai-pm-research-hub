-- ============================================================================
-- GC-148: CR-043/044/045 Platform-Manual Alignment
-- ============================================================================

-- CR-043: VERIFIED — selection_evaluations.scores maps 1:1 to Tables 1-3
-- All 11 criteria from the manual are implemented:
-- Objective (7): certification, research_exp, gp_knowledge, ai_knowledge,
--   tech_skills, availability, motivation
-- Interview (4): communication, proactivity, teamwork, culture_alignment
-- No schema change needed.

-- CR-044: VERIFIED — submission_status enum maps to 7-step workflow
-- draft → submitted → under_review → revision_requested/accepted → published/presented
-- Minor gap: peer_review and leader_review share under_review state
-- Acceptable for Cycle 3. Consider splitting in Cycle 4.
-- No schema change needed.

-- CR-045: Expand certificates.type to include institutional_declaration
ALTER TABLE certificates DROP CONSTRAINT IF EXISTS certificates_type_check;
ALTER TABLE certificates ADD CONSTRAINT certificates_type_check
  CHECK (type IN ('participation', 'completion', 'contribution', 'excellence',
    'volunteer_agreement', 'institutional_declaration'));

NOTIFY pgrst, 'reload schema';
