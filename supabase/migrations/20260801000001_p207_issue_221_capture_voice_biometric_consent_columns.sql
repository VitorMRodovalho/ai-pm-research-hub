-- P207 issue #221 — Whisper Art. 11 RETROATIVO Phase 2 of 3
-- Capture voice biometric consent columns + add evidence column
--
-- DRIFT CAPTURE: `consent_voice_biometric_at` + `consent_voice_biometric_revoked_at`
-- already exist on public.selection_applications but NO MIGRATION FILE captures
-- their DDL (grep `voice_biometric` in supabase/migrations/ returned empty).
-- This violates GC-097 (DDL must go through apply_migration, never execute_sql).
-- Phase 2 captures the drift idempotently via ADD COLUMN IF NOT EXISTS.
--
-- NEW: `consent_voice_biometric_evidence` text column added so audit chain
-- can capture HOW consent was attested (e.g., URL to signed termo PDF, email
-- thread ID with Angeline's notification template, or video-recorded verbal
-- consent reference).
--
-- Pattern mirrors p197d_a `consent_ai_analysis_at` + `consent_ai_analysis_evidence`
-- already in place for generic AI analysis consent. Voice biometric needs ITS OWN
-- column tracked separately (Art. 11 §I requires explicit + destacado consent;
-- cannot be inferred from broader AI consent per Phase 2 legal-counsel).
--
-- After this migration:
--   - 3 columns on selection_applications:
--     consent_voice_biometric_at         timestamptz (when consent captured)
--     consent_voice_biometric_revoked_at timestamptz (Art. 9 §V revogabilidade)
--     consent_voice_biometric_evidence   text        (URL/ID/notes audit trail)
--   - Helper `analyze_application_video_async` will gate on these in Phase 3
--
-- LGPD Art. 8 §6: consent specificity for sensitive data must be per-finalidade.
-- LGPD Art. 9 §V: data subject can revoke consent at any time. Revoked_at column
-- maintains revocation timestamp for Art. 18 deletion audit chain.
--
-- Rollback: ALTER TABLE public.selection_applications DROP COLUMN IF EXISTS
--   consent_voice_biometric_evidence; (the AT + revoked_at columns predate this
--   migration via drift and should not be dropped on rollback).
--
-- Refs: issue #221 · #212 ADR-0094 G1.6 (consent log architecture)
--   docs/council/2026-05-20-p207-tier3-strategic-review-212.md §1.5

ALTER TABLE public.selection_applications
  ADD COLUMN IF NOT EXISTS consent_voice_biometric_at        timestamptz,
  ADD COLUMN IF NOT EXISTS consent_voice_biometric_revoked_at timestamptz,
  ADD COLUMN IF NOT EXISTS consent_voice_biometric_evidence  text;

COMMENT ON COLUMN public.selection_applications.consent_voice_biometric_at IS
  'p207 #221 (2026-05-20, drift-captured from earlier execute_sql): timestamp when candidate gave explicit Art. 11 §I consent to process voice biometric (Whisper transcription + downstream multimodal analysis). NULL = no consent = analyze_application_video pipeline MUST refuse to dispatch.';

COMMENT ON COLUMN public.selection_applications.consent_voice_biometric_revoked_at IS
  'p207 #221 (2026-05-20, drift-captured): timestamp when candidate revoked Art. 11 consent (LGPD Art. 9 §V). When non-NULL, pipeline must refuse new analyses AND audit-chain must trigger deletion per Art. 18 §IV.';

COMMENT ON COLUMN public.selection_applications.consent_voice_biometric_evidence IS
  'p207 #221 (2026-05-20): audit trail of how consent was captured — URL to signed termo PDF in Drive, email thread ID with Angeline notification, or video-recorded verbal-consent reference. REQUIRED for ANPD audit defense (Art. 37 record-keeping).';

NOTIFY pgrst, 'reload schema';
