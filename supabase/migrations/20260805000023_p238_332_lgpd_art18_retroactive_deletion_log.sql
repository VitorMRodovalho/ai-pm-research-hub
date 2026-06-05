-- =====================================================================
-- Migration: p238_332_lgpd_art18_retroactive_deletion_log
-- Issue: #332 (Wave 3 of #221/#218 Whisper Art. 11 voice biometric remediation)
-- Date: 2026-05-23 (slot 20260805000023)
--
-- WHY: Wave 1 emergency block (p207, canonical row 20260520231254) blocked
-- all NEW transcriptions absent voice biometric consent. But at the moment
-- the block landed, 1 pre-existing pmi_video_screenings row already had
-- transcription text generated under the OLDER generic ai_analysis consent
-- regime (Eduardo Luz / application e780d8a9 / Background pillar /
-- video_screening 6afb7e26 / 2428 chars / drive_file 14bA9rCe...).
-- LGPD Art. 18 §IV gives the data subject the right to deletion; we must
-- (a) notify the affected candidate, (b) offer a deletion path, and (c)
-- record both steps in an auditable chain. Sibling C1 (#331, shipped p238)
-- covers forward consent capture. Sibling C4 (#334) is producing the
-- legal-grade notification template via Angeline async — until then this PR
-- ships a PM-approved interim text (file
-- `docs/audit/lgpd-art11-remediation/notification_eduardo_luz_p238_interim.md`).
--
-- This migration ships the audit-log infrastructure + 2 SECDEF RPCs to
-- record the notification dispatch and (later, if requested) execute the
-- deletion atomically with audit:
--   1. ALTER public.pii_access_log ADD COLUMN deletion_artifacts jsonb
--      (nullable; existing rows untouched; used only by the deletion RPC).
--   2. CREATE OR REPLACE FUNCTION public.lgpd_record_retroactive_notification(
--        p_application_id uuid, p_template_version text, p_lang text,
--        p_notification_method text DEFAULT 'email',
--        p_dispatched_at timestamptz DEFAULT NULL
--      ) RETURNS jsonb — gates on can_by_member('manage_member'); writes one
--      pii_access_log row (context='lgpd_art_18_retroactive_notification').
--   3. CREATE OR REPLACE FUNCTION public.lgpd_execute_retroactive_deletion(
--        p_application_id uuid, p_video_id uuid, p_deletion_reason text,
--        p_drive_deletion_ref text DEFAULT NULL
--      ) RETURNS jsonb — gates on can_by_member('manage_member'); clears
--      pmi_video_screenings.transcription for the affected row and writes
--      one pii_access_log row (context='lgpd_art_18_deletion_executed')
--      with deletion_artifacts jsonb capturing: video_id, application_id,
--      old_transcription_len, drive_file_id, drive_file_name,
--      drive_deletion_ref, deleted_at, deletion_reason, reversible=false.
--
-- Why two RPCs (not one combined): notification and deletion are decoupled
-- events. PM dispatches the notification once; deletion only fires IF
-- candidate requests it within the 30-day window (PM-approved default).
-- Both must produce a verifiable audit row in pii_access_log even if
-- Eduardo never responds.
--
-- Drive file removal is NOT in the SQL RPC scope — it requires Drive admin
-- auth + manual confirmation. The deletion RPC captures the drive_file_id
-- + the drive_deletion_ref (e.g., Drive trash confirmation URL or
-- message-id from Workspace audit log) but does NOT call the Drive API.
-- Operational checklist in the docs file documents the manual step.
--
-- ROLLBACK: ALTER public.pii_access_log DROP COLUMN deletion_artifacts;
-- DROP FUNCTION public.lgpd_record_retroactive_notification; DROP FUNCTION
-- public.lgpd_execute_retroactive_deletion. This is safe ONLY if no
-- deletion_artifacts rows have been written — otherwise dropping the
-- column destroys audit evidence. Existing pii_access_log rows without
-- the column are unaffected.
--
-- INVARIANTS: 19/19 = 0 expected post-apply (no FK changes, no constraint
-- additions on existing tables, only a nullable column + 2 new RPCs).
-- =====================================================================

ALTER TABLE public.pii_access_log
  ADD COLUMN IF NOT EXISTS deletion_artifacts jsonb;

COMMENT ON COLUMN public.pii_access_log.deletion_artifacts IS
  'JSON evidence captured at the time of a Art. 18 deletion execution. Includes pre-deletion lengths, identifiers of removed artifacts (DB rows + Drive file ids), drive_deletion_ref (operator confirmation), deletion_reason, and reversibility flag. NULL for all non-deletion events (e.g., reads, notifications).';


-- =====================================================================
-- RPC 1: lgpd_record_retroactive_notification
-- =====================================================================
CREATE OR REPLACE FUNCTION public.lgpd_record_retroactive_notification(
  p_application_id uuid,
  p_template_version text,
  p_lang text,
  p_notification_method text DEFAULT 'email',
  p_dispatched_at timestamptz DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public', 'pg_temp'
AS $$
DECLARE
  v_caller_member_id uuid;
  v_app selection_applications%ROWTYPE;
  v_log_id uuid;
  v_target_member_id uuid;
BEGIN
  v_caller_member_id := (SELECT id FROM members WHERE auth_id = auth.uid());
  IF v_caller_member_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: no member record for caller'
      USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF NOT can_by_member(v_caller_member_id, 'manage_member') THEN
    RAISE EXCEPTION 'Unauthorized: lgpd_record_retroactive_notification requires manage_member capability'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT * INTO v_app
  FROM public.selection_applications
  WHERE id = p_application_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'application_id % not found in selection_applications', p_application_id;
  END IF;

  IF p_template_version IS NULL OR length(trim(p_template_version)) = 0 THEN
    RAISE EXCEPTION 'p_template_version is required';
  END IF;
  IF p_lang IS NULL OR length(trim(p_lang)) = 0 THEN
    RAISE EXCEPTION 'p_lang is required (e.g., pt-BR, en-US)';
  END IF;
  IF p_notification_method NOT IN ('email', 'whatsapp', 'in_person', 'other') THEN
    RAISE EXCEPTION 'p_notification_method must be one of: email, whatsapp, in_person, other (got %)', p_notification_method;
  END IF;

  -- Best-effort link to a member record if the applicant has become one
  v_target_member_id := (
    SELECT m.id
    FROM public.members m
    WHERE lower(m.email) = lower(v_app.email)
    LIMIT 1
  );

  INSERT INTO public.pii_access_log (
    accessor_id, target_member_id, fields_accessed, context, reason, accessed_at
  ) VALUES (
    auth.uid(),
    v_target_member_id,
    ARRAY['email'],
    'lgpd_art_18_retroactive_notification',
    format(
      'template=%s; lang=%s; method=%s; application_id=%s; applicant_email=%s',
      p_template_version, p_lang, p_notification_method, p_application_id::text, v_app.email
    ),
    COALESCE(p_dispatched_at, now())
  )
  RETURNING id INTO v_log_id;

  RETURN jsonb_build_object(
    'success', true,
    'pii_access_log_id', v_log_id,
    'application_id', p_application_id,
    'template_version', p_template_version,
    'lang', p_lang,
    'notification_method', p_notification_method,
    'dispatched_at', COALESCE(p_dispatched_at, now()),
    'target_member_id', v_target_member_id
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.lgpd_record_retroactive_notification(uuid, text, text, text, timestamptz) TO authenticated;

COMMENT ON FUNCTION public.lgpd_record_retroactive_notification(uuid, text, text, text, timestamptz) IS
  'Records a retroactive Art. 18 notification dispatch in pii_access_log (context=lgpd_art_18_retroactive_notification). PM-only (manage_member gate). Does NOT send the email — PM dispatches via official channel and then calls this RPC to anchor the audit chain. Optional p_dispatched_at lets PM backdate to the actual send moment.';


-- =====================================================================
-- RPC 2: lgpd_execute_retroactive_deletion
-- =====================================================================
CREATE OR REPLACE FUNCTION public.lgpd_execute_retroactive_deletion(
  p_application_id uuid,
  p_video_id uuid,
  p_deletion_reason text,
  p_drive_deletion_ref text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public', 'pg_temp'
AS $$
DECLARE
  v_caller_member_id uuid;
  v_app selection_applications%ROWTYPE;
  v_vs pmi_video_screenings%ROWTYPE;
  v_old_transcription_len int;
  v_log_id uuid;
  v_target_member_id uuid;
  v_artifacts jsonb;
BEGIN
  v_caller_member_id := (SELECT id FROM members WHERE auth_id = auth.uid());
  IF v_caller_member_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: no member record for caller'
      USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF NOT can_by_member(v_caller_member_id, 'manage_member') THEN
    RAISE EXCEPTION 'Unauthorized: lgpd_execute_retroactive_deletion requires manage_member capability'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF p_deletion_reason IS NULL OR length(trim(p_deletion_reason)) < 8 THEN
    RAISE EXCEPTION 'p_deletion_reason must be a non-trivial string (>= 8 chars)';
  END IF;

  SELECT * INTO v_app FROM public.selection_applications WHERE id = p_application_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'application_id % not found', p_application_id;
  END IF;

  SELECT * INTO v_vs FROM public.pmi_video_screenings WHERE id = p_video_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'pmi_video_screenings.id % not found', p_video_id;
  END IF;
  IF v_vs.application_id <> p_application_id THEN
    RAISE EXCEPTION 'video_id % does not belong to application %', p_video_id, p_application_id;
  END IF;
  IF v_vs.transcription IS NULL THEN
    RAISE EXCEPTION 'pmi_video_screenings.id % already has NULL transcription (idempotent no-op rejected to avoid duplicate audit rows)', p_video_id;
  END IF;

  v_old_transcription_len := length(v_vs.transcription);

  v_artifacts := jsonb_build_object(
    'video_id', p_video_id,
    'application_id', p_application_id,
    'pillar', v_vs.pillar,
    'question_index', v_vs.question_index,
    'old_transcription_len', v_old_transcription_len,
    'drive_file_id', v_vs.drive_file_id,
    'drive_file_name', v_vs.drive_file_name,
    'drive_deletion_ref', p_drive_deletion_ref,
    'deleted_at', now(),
    'deletion_reason', p_deletion_reason,
    'reversible', false,
    'lgpd_basis', 'Art. 18 §IV'
  );

  -- Clear the transcription text. Drive file removal is a separate operator
  -- step (Drive admin, captured in p_drive_deletion_ref). We do NOT touch
  -- selection_evaluation_ai_suggestions here — those rows already record
  -- consumed_at=NULL for non-consumed suggestions, which means they did not
  -- influence any evaluator's final score; they are inert audit history.
  UPDATE public.pmi_video_screenings
     SET transcription = NULL,
         updated_at = now()
   WHERE id = p_video_id;

  v_target_member_id := (
    SELECT m.id FROM public.members m
    WHERE lower(m.email) = lower(v_app.email)
    LIMIT 1
  );

  INSERT INTO public.pii_access_log (
    accessor_id, target_member_id, fields_accessed, context, reason, accessed_at,
    deletion_artifacts
  ) VALUES (
    auth.uid(),
    v_target_member_id,
    ARRAY['transcription', 'drive_file_id', 'drive_file_name'],
    'lgpd_art_18_deletion_executed',
    format(
      'video_id=%s; pillar=%s; reason=%s; drive_deletion_ref=%s',
      p_video_id::text, v_vs.pillar, p_deletion_reason, COALESCE(p_drive_deletion_ref, '<not-supplied>')
    ),
    now(),
    v_artifacts
  )
  RETURNING id INTO v_log_id;

  RETURN jsonb_build_object(
    'success', true,
    'pii_access_log_id', v_log_id,
    'video_id', p_video_id,
    'application_id', p_application_id,
    'old_transcription_len', v_old_transcription_len,
    'drive_file_id', v_vs.drive_file_id,
    'drive_deletion_ref', p_drive_deletion_ref,
    'cleared_at', now()
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.lgpd_execute_retroactive_deletion(uuid, uuid, text, text) TO authenticated;

COMMENT ON FUNCTION public.lgpd_execute_retroactive_deletion(uuid, uuid, text, text) IS
  'Atomically clears pmi_video_screenings.transcription for a specified row and writes a pii_access_log row (context=lgpd_art_18_deletion_executed) with the full deletion_artifacts jsonb evidence. PM-only (manage_member gate). Validates video_id belongs to application_id and transcription is not already NULL (rejects to keep audit clean). Drive file removal is a separate operator step — the drive_file_id + drive_deletion_ref are recorded so the chain stays complete.';


-- =====================================================================
-- Sanity: confirm new surface is in place
-- =====================================================================
DO $sanity$
DECLARE
  v_has_column boolean;
  v_record_body text;
  v_delete_body text;
BEGIN
  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns
     WHERE table_schema = 'public'
       AND table_name = 'pii_access_log'
       AND column_name = 'deletion_artifacts'
       AND data_type = 'jsonb'
  ) INTO v_has_column;
  IF NOT v_has_column THEN
    RAISE EXCEPTION 'sanity: pii_access_log.deletion_artifacts jsonb column missing post-apply';
  END IF;

  SELECT prosrc INTO v_record_body
    FROM pg_proc
   WHERE proname = 'lgpd_record_retroactive_notification'
     AND pronamespace = 'public'::regnamespace;
  IF v_record_body IS NULL
     OR position('lgpd_art_18_retroactive_notification' in v_record_body) = 0 THEN
    RAISE EXCEPTION 'sanity: lgpd_record_retroactive_notification missing or context literal not present';
  END IF;
  IF position('manage_member' in v_record_body) = 0 THEN
    RAISE EXCEPTION 'sanity: lgpd_record_retroactive_notification missing manage_member gate';
  END IF;

  SELECT prosrc INTO v_delete_body
    FROM pg_proc
   WHERE proname = 'lgpd_execute_retroactive_deletion'
     AND pronamespace = 'public'::regnamespace;
  IF v_delete_body IS NULL
     OR position('lgpd_art_18_deletion_executed' in v_delete_body) = 0 THEN
    RAISE EXCEPTION 'sanity: lgpd_execute_retroactive_deletion missing or context literal not present';
  END IF;
  IF position('manage_member' in v_delete_body) = 0 THEN
    RAISE EXCEPTION 'sanity: lgpd_execute_retroactive_deletion missing manage_member gate';
  END IF;
  IF position('deletion_artifacts' in v_delete_body) = 0 THEN
    RAISE EXCEPTION 'sanity: lgpd_execute_retroactive_deletion does not write deletion_artifacts';
  END IF;

  -- Single-overload defense (SEDIMENT-232.A): both RPCs are first-of-name;
  -- guard against future migrations adding a stale overload.
  IF (SELECT count(*) FROM pg_proc
       WHERE proname = 'lgpd_record_retroactive_notification'
         AND pronamespace = 'public'::regnamespace) <> 1 THEN
    RAISE EXCEPTION 'sanity: lgpd_record_retroactive_notification has more than one overload — drop the stale one';
  END IF;
  IF (SELECT count(*) FROM pg_proc
       WHERE proname = 'lgpd_execute_retroactive_deletion'
         AND pronamespace = 'public'::regnamespace) <> 1 THEN
    RAISE EXCEPTION 'sanity: lgpd_execute_retroactive_deletion has more than one overload — drop the stale one';
  END IF;
END;
$sanity$;

NOTIFY pgrst, 'reload schema';
