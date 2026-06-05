-- P207 issue #221 — Whisper Art. 11 RETROATIVO Phase 1 of 3
-- DROP TRIGGER trg_video_ai_analysis_on_upload
--
-- Tier 3 strategic council (5/5 GO-WITH-AMENDMENTS, 2026-05-20 p207) ordered
-- this trigger DROPPED unconditionally as P0 LGPD remediation. The trigger
-- dispatches `analyze_application_video_async` on `pmi_video_screenings`
-- INSERT/UPDATE, which calls OpenAI Whisper to transcribe candidate video
-- audio (voice biometric, LGPD Art. 11 §I = sensitive data).
--
-- Current `consent_ai_analysis_at` gate covers generic "AI analysis" intent
-- but NOT explicit Art. 11 voice biometric consent (Art. 11 §II hypotheses
-- are taxative; only consentimento explícito + destacado per Art. 8 applies).
--
-- Empirical state (live query 2026-05-20):
--   pmi_video_screenings.transcribed=0; has_transcription_text=1; in_flight=5
--   distinct_applications=18; ai_processing_log video_screening rows=3 (1c/2f)
--
-- The intent to process without Art. 11 consent IS the violation, independent
-- of OpenAI 429 quota having intervened. DROP the trigger first; rebuilds
-- come after Angeline's Art. 48 written determination + Termo de Speaker
-- ratification (sequence per accountability §2.1 A1).
--
-- Rollback: re-CREATE the trigger via Phase 3 migration once consent gate is
-- in place. Until then, manual `analyze_application_video(p_application_id)`
-- MCP tool calls continue to be blocked at Phase 3 (helper gate update).
--
-- Refs: issue #221 · ADR-0094 (Draft) · #212 Tier 3 synthesis
--   docs/council/2026-05-20-p207-tier3-strategic-review-212.md

DROP TRIGGER IF EXISTS trg_video_ai_analysis_on_upload ON public.pmi_video_screenings;

-- Audit comment on the now-orphaned helper function until Phase 3 updates body
COMMENT ON FUNCTION public._trg_video_ai_analysis_on_upload() IS
  'p207 issue #221 (2026-05-20): trigger BODY preserved but trigger DROPPED for LGPD Art. 11 RETROACTIVE remediation. Function no longer fires automatically. Will be re-attached at Phase 3 (consent_voice_biometric_at gate) after Angeline Art. 48 determination.';

NOTIFY pgrst, 'reload schema';
