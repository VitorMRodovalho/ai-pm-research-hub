-- ISSUE #218: LGPD Art. 11 §I emergency block — voice biometric consent gate
-- Filed 2026-05-20 p206 via #212 council legal-counsel review.
-- Adds consent_voice_biometric_at + consent_voice_biometric_revoked_at columns on selection_applications.
-- Adds BEFORE INSERT OR UPDATE OF transcription trigger on pmi_video_screenings that RAISES
-- if voice biometric consent missing or revoked.
-- Live impact at time of apply: 1 candidate already transcribed, 89 video uploads pending.
-- Existing transcribed row is preserved (trigger doesn't fire on existing rows; only on transcription transition NULL→NOT NULL).
-- Pending Wave 2: UI capture for new column + privacy text update.
-- Pending Wave 3: retroactive notification of 1 affected candidate (Art. 18 §IV offer).
--
-- Rollback (idempotent):
--   DROP TRIGGER IF EXISTS trg_pmi_video_screening_voice_consent ON public.pmi_video_screenings;
--   DROP FUNCTION IF EXISTS public._trg_pmi_video_screening_voice_consent_check();
--   ALTER TABLE public.selection_applications DROP COLUMN IF EXISTS consent_voice_biometric_revoked_at;
--   ALTER TABLE public.selection_applications DROP COLUMN IF EXISTS consent_voice_biometric_at;
-- Note: dropping consent columns is LGPD-destructive; retain unless re-architecting.

ALTER TABLE public.selection_applications
  ADD COLUMN IF NOT EXISTS consent_voice_biometric_at timestamptz NULL,
  ADD COLUMN IF NOT EXISTS consent_voice_biometric_revoked_at timestamptz NULL;

COMMENT ON COLUMN public.selection_applications.consent_voice_biometric_at IS
  'LGPD Art. 11 §I specific destacado consent for voice biometric processing (Whisper transcription). NULL = no consent given. Separate from consent_ai_analysis_at (which covers Art. 7 §V text-based analysis only).';

COMMENT ON COLUMN public.selection_applications.consent_voice_biometric_revoked_at IS
  'LGPD Art. 11 §I consent revocation timestamp. NOT NULL = consent withdrawn; further processing blocked + retroactive Art. 18 §IV deletion required.';

-- Block transcription INSERT/UPDATE without explicit voice biometric consent
CREATE OR REPLACE FUNCTION public._trg_pmi_video_screening_voice_consent_check()
RETURNS TRIGGER AS $$
DECLARE
  v_consent_at timestamptz;
  v_revoked_at timestamptz;
  v_transcription_being_set boolean;
BEGIN
  -- Only check when transcription is being set (NULL → NOT NULL) or replaced
  v_transcription_being_set := (
    TG_OP = 'INSERT' AND NEW.transcription IS NOT NULL
  ) OR (
    TG_OP = 'UPDATE' AND NEW.transcription IS NOT NULL
    AND (OLD.transcription IS DISTINCT FROM NEW.transcription)
  );

  IF NOT v_transcription_being_set THEN
    RETURN NEW;
  END IF;

  -- Lookup consent on selection_applications
  SELECT consent_voice_biometric_at, consent_voice_biometric_revoked_at
  INTO v_consent_at, v_revoked_at
  FROM public.selection_applications
  WHERE id = NEW.application_id;

  IF v_consent_at IS NULL THEN
    RAISE EXCEPTION 'LGPD Art. 11 §I: voice biometric consent required before transcription. selection_applications.consent_voice_biometric_at IS NULL for application_id = %. See issue #218 + ADR-0094.', NEW.application_id
      USING ERRCODE = 'check_violation', HINT = 'Capture explicit destacado consent (Art. 11 §I) via /portal-aplicacao or admin override before allowing Whisper transcription.';
  END IF;

  IF v_revoked_at IS NOT NULL THEN
    RAISE EXCEPTION 'LGPD Art. 11 §I: voice biometric consent revoked at % for application_id = %. Transcription blocked + retroactive deletion required (Art. 18 §IV).', v_revoked_at, NEW.application_id
      USING ERRCODE = 'check_violation';
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = 'public';

DROP TRIGGER IF EXISTS trg_pmi_video_screening_voice_consent ON public.pmi_video_screenings;

CREATE TRIGGER trg_pmi_video_screening_voice_consent
BEFORE INSERT OR UPDATE OF transcription ON public.pmi_video_screenings
FOR EACH ROW
EXECUTE FUNCTION public._trg_pmi_video_screening_voice_consent_check();

COMMENT ON TRIGGER trg_pmi_video_screening_voice_consent ON public.pmi_video_screenings IS
  'Issue #218 emergency block (2026-05-20 p206): refuses transcription write without explicit Art. 11 §I voice biometric consent. Fires only when transcription field transitions NULL→NOT NULL or value changes. Existing transcribed rows preserved.';

-- Reload PostgREST schema to expose new columns
NOTIFY pgrst, 'reload schema';
