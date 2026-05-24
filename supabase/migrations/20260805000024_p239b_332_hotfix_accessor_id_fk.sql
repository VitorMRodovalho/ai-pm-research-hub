-- =====================================================================
-- Migration: p239b_332_hotfix_accessor_id_fk
-- Issue: #332 (Wave 3 of #221/#218 Whisper Art. 11 voice biometric remediation)
-- Date: 2026-05-24 (slot 20260805000024)
--
-- WHY: Hotfix for FK violation discovered in p239b live test of the p238b
-- audit-log RPCs (lgpd_record_retroactive_notification +
-- lgpd_execute_retroactive_deletion, migration 20260805000023).
--
-- Bug: both RPCs INSERT into pii_access_log with `accessor_id := auth.uid()`,
-- but the FK constraint `pii_access_log_accessor_id_fkey` targets `members(id)`
-- (NOT `auth.users(id)`). Both RPCs already declare `v_caller_member_id` at
-- the top of the body (resolved via `SELECT id FROM members WHERE auth_id =
-- auth.uid()`) and use it for the `can_by_member('manage_member')` gate — they
-- just forgot to use the same value in the INSERT.
--
-- Why this wasn't caught at p238b smoke:
--   * Service-role context returns `auth.uid() = NULL`, so the gate ladder's
--     `IF v_caller_member_id IS NULL THEN RAISE` fires BEFORE the INSERT can
--     trigger the FK check. p238b smoke ran via service-role + got the
--     "Unauthorized: no member record" error, declared PASS, and shipped.
--   * The sanity DO block validated context literal + gate presence + dual-
--     overload defense, but did NOT validate the INSERT column source.
--   * p239b first PM-authenticated invocation triggered the latent bug.
--
-- Canonical pattern (from `public.log_pii_access`):
--   SELECT id INTO v_accessor_id FROM members WHERE auth_id = auth.uid();
--   INSERT INTO pii_access_log (accessor_id, ...) VALUES (v_accessor_id, ...);
--
-- FIX: CREATE OR REPLACE both RPCs with the only change being
-- `auth.uid()` → `v_caller_member_id` in the VALUES of the pii_access_log
-- INSERT. Signature preserved (CREATE OR REPLACE permitted, no DROP needed
-- since we are NOT changing parameter types or count). All other body logic
-- (gates, validations, sanity, deletion_artifacts construction) preserved
-- byte-for-byte. This means the gate ladder still fires correctly + audit
-- chain stays intact + idempotent rejection of pre-NULL transcription still
-- works.
--
-- Sanity DO at end re-asserts both bodies use `v_caller_member_id` (not
-- `auth.uid()`) in the INSERT statements + RPCs still have exactly 1
-- overload each. Contract test ratchet added in
-- `tests/contracts/mcp-lgpd-retroactive-operator-tools.test.mjs` guards
-- against regression of this exact pattern going forward.
--
-- ROLLBACK: re-apply 20260805000023 to revert to the buggy bodies (would
-- restore the FK violation for any PM-authenticated call). Safer rollback
-- = leave this hotfix in place + write a fresh DROP+CREATE if a different
-- accessor source becomes needed.
--
-- INVARIANTS: 19/19 = 0 expected post-apply (no schema changes, no FK
-- changes, no constraint additions; only function body rewrites).
-- =====================================================================


-- =====================================================================
-- RPC 1 FIX: lgpd_record_retroactive_notification
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

  -- p239b hotfix: accessor_id uses v_caller_member_id (members.id) to satisfy
  -- pii_access_log_accessor_id_fkey → members(id). Previous version used
  -- auth.uid() (auth.users.id) which violated the FK on first PM-authenticated
  -- call. Pattern matches canonical log_pii_access helper.
  INSERT INTO public.pii_access_log (
    accessor_id, target_member_id, fields_accessed, context, reason, accessed_at
  ) VALUES (
    v_caller_member_id,
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

COMMENT ON FUNCTION public.lgpd_record_retroactive_notification(uuid, text, text, text, timestamptz) IS
  'Records a retroactive Art. 18 notification dispatch in pii_access_log (context=lgpd_art_18_retroactive_notification). PM-only (manage_member gate). Does NOT send the email — PM dispatches via official channel and then calls this RPC to anchor the audit chain. Optional p_dispatched_at lets PM backdate to the actual send moment. p239b hotfix: accessor_id uses members.id (was auth.users.id — FK violation).';


-- =====================================================================
-- RPC 2 FIX: lgpd_execute_retroactive_deletion
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

  -- p239b hotfix: accessor_id uses v_caller_member_id (members.id) to satisfy
  -- pii_access_log_accessor_id_fkey → members(id). Previous version used
  -- auth.uid() (auth.users.id) which violated the FK on first PM-authenticated
  -- call. Pattern matches canonical log_pii_access helper.
  INSERT INTO public.pii_access_log (
    accessor_id, target_member_id, fields_accessed, context, reason, accessed_at,
    deletion_artifacts
  ) VALUES (
    v_caller_member_id,
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

COMMENT ON FUNCTION public.lgpd_execute_retroactive_deletion(uuid, uuid, text, text) IS
  'Atomically clears pmi_video_screenings.transcription for a specified row and writes a pii_access_log row (context=lgpd_art_18_deletion_executed) with the full deletion_artifacts jsonb evidence. PM-only (manage_member gate). Validates video_id belongs to application_id and transcription is not already NULL (rejects to keep audit clean). Drive file removal is a separate operator step — the drive_file_id + drive_deletion_ref are recorded so the chain stays complete. p239b hotfix: accessor_id uses members.id (was auth.users.id — FK violation).';


-- =====================================================================
-- Sanity: confirm both bodies now use v_caller_member_id (not auth.uid())
-- in the pii_access_log INSERT statements.
-- =====================================================================
DO $sanity$
DECLARE
  v_record_body text;
  v_delete_body text;
BEGIN
  SELECT prosrc INTO v_record_body
    FROM pg_proc
   WHERE proname = 'lgpd_record_retroactive_notification'
     AND pronamespace = 'public'::regnamespace;
  IF v_record_body IS NULL THEN
    RAISE EXCEPTION 'sanity: lgpd_record_retroactive_notification missing post-apply';
  END IF;
  -- The INSERT block must use v_caller_member_id, not auth.uid(), as accessor_id.
  -- The simplest invariant: the literal `auth.uid()` should NOT appear inside
  -- the INSERT INTO pii_access_log ... VALUES (...) clause. It still appears
  -- in the gate ladder (`SELECT id FROM members WHERE auth_id = auth.uid()`),
  -- which is fine.
  IF v_record_body !~ 'INSERT\s+INTO\s+public\.pii_access_log[\s\S]*?VALUES\s*\(\s*v_caller_member_id' THEN
    RAISE EXCEPTION 'sanity: lgpd_record_retroactive_notification INSERT does not use v_caller_member_id as accessor_id';
  END IF;

  SELECT prosrc INTO v_delete_body
    FROM pg_proc
   WHERE proname = 'lgpd_execute_retroactive_deletion'
     AND pronamespace = 'public'::regnamespace;
  IF v_delete_body IS NULL THEN
    RAISE EXCEPTION 'sanity: lgpd_execute_retroactive_deletion missing post-apply';
  END IF;
  IF v_delete_body !~ 'INSERT\s+INTO\s+public\.pii_access_log[\s\S]*?VALUES\s*\(\s*v_caller_member_id' THEN
    RAISE EXCEPTION 'sanity: lgpd_execute_retroactive_deletion INSERT does not use v_caller_member_id as accessor_id';
  END IF;

  -- Single-overload defense preserved
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
