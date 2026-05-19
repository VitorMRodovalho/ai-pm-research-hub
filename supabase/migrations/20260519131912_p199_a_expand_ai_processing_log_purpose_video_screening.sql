-- p199 A (2026-05-19): expand ai_processing_log.purpose CHECK to allow 'video_screening'.
--
-- Root cause discovered while smoking the p197d D1 analyze-application-video EF (committed
-- p199 commit 27e08ad4): the EF inserts ai_processing_log with purpose='video_screening'
-- (line 242) as the first action of the for-loop, but the pre-existing CHECK only allowed
-- ['triage','briefing','qualitative','enrichment','other']. INSERT raised check_violation
-- silently inside the for-loop's try/catch, aborting before Drive/Whisper/Claude were ever
-- called. Result: 202 OK from EF + 0 rows in any of {ai_processing_log,
-- selection_evaluation_ai_suggestions, pmi_video_screenings.transcription}.
--
-- 'video_screening' is the semantic match for p197d D1 — video pillar analysis is a distinct
-- purpose from triage (CV+form) / briefing (interviewer prep) / qualitative (LLM long-form
-- on candidate) / enrichment (PMI/LinkedIn). Adding it preserves the existing audit trail
-- + analytics breakdowns by purpose.
--
-- ROLLBACK:
--   ALTER TABLE public.ai_processing_log DROP CONSTRAINT ai_processing_log_purpose_check;
--   ALTER TABLE public.ai_processing_log ADD CONSTRAINT ai_processing_log_purpose_check
--     CHECK (purpose = ANY (ARRAY['triage','briefing','qualitative','enrichment','other']));
--   (rollback only safe if no rows have purpose='video_screening' yet)
--
ALTER TABLE public.ai_processing_log DROP CONSTRAINT ai_processing_log_purpose_check;

ALTER TABLE public.ai_processing_log
  ADD CONSTRAINT ai_processing_log_purpose_check
  CHECK (purpose = ANY (ARRAY['triage'::text, 'briefing'::text, 'qualitative'::text, 'enrichment'::text, 'video_screening'::text, 'other'::text]));

NOTIFY pgrst, 'reload schema';
