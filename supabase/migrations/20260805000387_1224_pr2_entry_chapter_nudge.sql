-- #1224 PR 2 — entry-chapter nudge (in-app diagnosis + Resend email channel)
--
-- Builds on PR 1 (mig 386): PR 1 gave the pure classifier classify_entry_chapter() and the
-- admin cohort diagnosis get_entry_chapter_diagnosis(cycle). PR 2 adds the two surfaces that
-- ACT on that diagnosis:
--
--   1. get_my_entry_chapter_diagnosis() — SELF-scoped read for the /workspace in-app nudge.
--      Finds the caller's own selection application (by email) and returns the classifier
--      bucket + active BR codes + the member's current entry_chapter_code / chapter. The
--      EntryChapterNudge island renders bucket-specific copy from this (PMI-side action for
--      profile_private / no_fetch / not_affiliated; the choice card for ambiguous).
--
--   2. nudge_entry_chapter_cohort(cycle, dry_run) — admin PRODUCER of the email blast. Reuses
--      get_entry_chapter_diagnosis + create_notification. Targets only the genuinely stuck:
--      member exists, entry_chapter_code IS NULL, and bucket is actionable. Each recipient
--      gets one notification of the new type entry_chapter_action_needed with bucket-specific
--      title/body; create_notification stamps delivery_mode = transactional_immediate (via the
--      _delivery_mode_for change below), so the jobid-9 send-notification-email cron delivers
--      the email. dry_run=true (default) returns the plan WITHOUT inserting, so the blast is
--      previewed and approved before it fires (outward-facing = explicit approval). A 30-day
--      per-recipient dedup guard prevents an accidental double-fire on re-run.
--
--   3. _delivery_mode_for(text) — add entry_chapter_action_needed => transactional_immediate.
--      Kept byte-identical to the live body except the one new WHEN line (ADR-0022 catalog +
--      contract test adr-0022-delivery-mode kept in sync in this same PR).
--
-- SSOT stays the PMI enrichment (selection_applications.pmi_memberships), never free text
-- (PM #1224). member.chapter may hold a self-declared chapter that the enrichment cannot
-- confirm; the nudge copy is honest about that ("we could not confirm from your PMI profile").
--
-- ROLLBACK:
--   DROP FUNCTION public.nudge_entry_chapter_cohort(uuid, boolean);
--   DROP FUNCTION public.get_my_entry_chapter_diagnosis();
--   -- restore _delivery_mode_for to the mig-386-era body (remove the entry_chapter_action_needed WHEN).

-- ── 1. Self-scoped diagnosis for the in-app nudge ────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.get_my_entry_chapter_diagnosis()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_member   public.members%ROWTYPE;
  v_app      public.selection_applications%ROWTYPE;
  v_classify jsonb;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  SELECT * INTO v_member FROM public.members WHERE auth_id = auth.uid();
  IF v_member.id IS NULL THEN
    RETURN jsonb_build_object(
      'bucket', 'no_application', 'active_br_codes', '[]'::jsonb,
      'entry_chapter_code', NULL, 'member_chapter', NULL
    );
  END IF;

  -- The caller's own application, preferring an approved one, then most recent.
  SELECT * INTO v_app
  FROM public.selection_applications sa
  WHERE lower(sa.email) = lower(v_member.email)
  ORDER BY (sa.status = 'approved') DESC, sa.created_at DESC
  LIMIT 1;

  IF v_app.id IS NULL THEN
    RETURN jsonb_build_object(
      'bucket', 'no_application', 'active_br_codes', '[]'::jsonb,
      'entry_chapter_code', v_member.entry_chapter_code, 'member_chapter', v_member.chapter
    );
  END IF;

  v_classify := public.classify_entry_chapter(
    v_app.pmi_memberships, v_app.community_profile_private, v_app.pmi_data_fetched_at
  );

  RETURN jsonb_build_object(
    'bucket', v_classify->>'bucket',
    'active_br_codes', v_classify->'active_br_codes',
    'entry_chapter_code', v_member.entry_chapter_code,
    'member_chapter', v_member.chapter
  );
END;
$function$;

COMMENT ON FUNCTION public.get_my_entry_chapter_diagnosis() IS
  '#1224 PR2 — self-scoped entry-chapter diagnosis for the /workspace nudge. Returns {bucket, active_br_codes, entry_chapter_code, member_chapter} from the caller''s own selection application via classify_entry_chapter. SSOT is the PMI enrichment, not free text. SECDEF; authenticated only.';

REVOKE ALL ON FUNCTION public.get_my_entry_chapter_diagnosis() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_my_entry_chapter_diagnosis() TO authenticated;

-- ── 2. delivery_mode: add the new transactional type ─────────────────────────────────────────
-- Rebuilt from the live body (mig 360 era) plus the one new WHEN, so no prior type mapping is
-- dropped (the earlier draft was based on a stale mig-386-era capture that lacked the whole
-- selection/affiliation policy matrix — caught by adr-0022-delivery-mode contract test).
CREATE OR REPLACE FUNCTION public._delivery_mode_for(p_type text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE PARALLEL SAFE
 SET search_path TO ''
AS $function$
  SELECT CASE p_type
    -- PR-2 (email audit): the per-signing leadership alert is now in-app only; the daily
    -- digest (volunteer_term_signed_digest) carries the single aggregated email.
    WHEN 'volunteer_agreement_signed'    THEN 'suppress'
    WHEN 'volunteer_term_signed_digest'  THEN 'transactional_immediate'
    WHEN 'ip_ratification_gate_pending'  THEN 'transactional_immediate'
    WHEN 'system_alert'                  THEN 'transactional_immediate'
    -- #1169: ready is redundant with issued at the email layer (issued carries the single email);
    -- kept in-app only. Every ready-cert already fired an issued email (0 ready-without-issued/60d).
    WHEN 'certificate_ready'             THEN 'suppress'
    WHEN 'certificate_issued'            THEN 'transactional_immediate'
    WHEN 'member_offboarded'             THEN 'transactional_immediate'
    WHEN 'ip_ratification_gate_advanced'    THEN 'transactional_immediate'
    WHEN 'ip_ratification_chain_approved'   THEN 'transactional_immediate'
    WHEN 'ip_ratification_awaiting_members' THEN 'transactional_immediate'
    WHEN 'webinar_status_confirmed'      THEN 'transactional_immediate'
    WHEN 'webinar_status_completed'      THEN 'transactional_immediate'
    WHEN 'webinar_status_cancelled'      THEN 'transactional_immediate'
    WHEN 'weekly_card_digest_member'     THEN 'transactional_immediate'
    WHEN 'governance_cr_new'             THEN 'transactional_immediate'
    WHEN 'governance_cr_vote'            THEN 'transactional_immediate'
    WHEN 'governance_cr_approved'        THEN 'transactional_immediate'
    WHEN 'sponsor_finance_entry_logged'  THEN 'transactional_immediate'
    WHEN 'governance_manual_proposed'    THEN 'transactional_immediate'
    WHEN 'engagement_renewal_d7_urgent'  THEN 'transactional_immediate'
    -- p153 OPP-153.1: project_charter (TAP) notifications
    WHEN 'project_charter_invite'        THEN 'transactional_immediate'
    WHEN 'project_charter_approved'      THEN 'transactional_immediate'
    -- p159 S#1 T1 (2026-05-14): selection_termo_due é o "email principal" pós-VEP-Active
    WHEN 'selection_termo_due'           THEN 'transactional_immediate'
    -- p228 #260 W2 Leaf 1 (2026-05-23): Selection funnel Policy Matrix
    WHEN 'selection_approved'            THEN 'transactional_immediate'
    WHEN 'selection_interview_scheduled' THEN 'transactional_immediate'
    WHEN 'peer_review_requested'         THEN 'transactional_immediate'
    WHEN 'selection_evaluation_complete' THEN 'suppress'
    WHEN 'selection_interview_noshow'    THEN 'digest_weekly'
    -- p228 #260 W2 Leaf 2 (2026-05-23): admin reminder for overdue interviews
    WHEN 'selection_interview_overdue'   THEN 'digest_weekly'
    -- p228 #260 W2 Leaf 4 (2026-05-23): candidate invite to book interview after
    -- objective evaluations cleared + research_score >= cycle cutoff.
    WHEN 'selection_cutoff_approved'     THEN 'transactional_immediate'
    -- (end p228)
    -- #186 (2026-06-05): curation committee broadcast when an item enters curation_pending
    WHEN 'curation_item_submitted'       THEN 'transactional_immediate'
    WHEN 'engagement_renewal_d30'        THEN 'digest_weekly'
    WHEN 'engagement_renewal_d60_gp_aggregate' THEN 'digest_weekly'
    -- #625 F3 (2026-06-11): radar de renovação de filiação
    WHEN 'affiliation_renewal_d7_urgent'  THEN 'transactional_immediate'
    WHEN 'affiliation_renewal_d30'        THEN 'digest_weekly'
    WHEN 'affiliation_verification_stale' THEN 'digest_weekly'
    -- #1224 PR2 (2026-07-09): one-time onboarding nudge when the PMI enrichment cannot resolve
    -- an entry chapter (profile_private / no_fetch / not_affiliated / ambiguous-no-choice).
    WHEN 'entry_chapter_action_needed'    THEN 'transactional_immediate'
    -- #740 Wave 3c-i (B8): agreement rejected / reissued — member must re-sign, deliver immediately
    WHEN 'volunteer_agreement_rejected'  THEN 'transactional_immediate'
    WHEN 'volunteer_agreement_reissued'  THEN 'transactional_immediate'
    WHEN 'attendance_detractor'          THEN 'suppress'
    WHEN 'info'                          THEN 'suppress'
    WHEN 'system'                        THEN 'suppress'
    ELSE 'digest_weekly'
  END;
$function$;

-- ── 3. Admin producer of the entry-chapter nudge blast ───────────────────────────────────────
CREATE OR REPLACE FUNCTION public.nudge_entry_chapter_cohort(
  p_cycle_id uuid DEFAULT NULL,
  p_dry_run  boolean DEFAULT true
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_rec       record;
  v_title     text;
  v_body      text;
  v_sent      int := 0;
  v_skipped   int := 0;
  v_plan      jsonb := '[]'::jsonb;
BEGIN
  -- manage_platform, or service_role/postgres (cron/tests) — same gate as get_entry_chapter_diagnosis.
  IF auth.uid() IS NOT NULL THEN
    SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
    IF v_caller_id IS NULL OR NOT public.can_by_member(v_caller_id, 'manage_platform') THEN
      RAISE EXCEPTION 'Unauthorized: nudge_entry_chapter_cohort requires manage_platform';
    END IF;
  ELSIF current_setting('role', true) NOT IN ('service_role', 'postgres')
        AND current_user NOT IN ('postgres', 'supabase_admin') THEN
    RAISE EXCEPTION 'Unauthorized: nudge_entry_chapter_cohort requires authentication';
  END IF;

  FOR v_rec IN
    SELECT d.member_id, d.applicant_name, d.bucket
    FROM public.get_entry_chapter_diagnosis(p_cycle_id) d
    WHERE d.member_id IS NOT NULL
      AND d.entry_chapter_code IS NULL
      AND d.bucket IN ('ambiguous', 'profile_private', 'no_fetch', 'not_affiliated')
    ORDER BY d.applicant_name
  LOOP
    v_title := CASE v_rec.bucket
      WHEN 'ambiguous'       THEN 'Escolha seu capítulo de entrada no Núcleo'
      WHEN 'profile_private' THEN 'Deixe seu perfil PMI público para confirmarmos seu capítulo'
      WHEN 'no_fetch'        THEN 'Vincule seu perfil PMI para definir seu capítulo de entrada'
      ELSE                        'Confirme sua filiação PMI para definir seu capítulo de entrada'
    END;
    v_body := CASE v_rec.bucket
      WHEN 'ambiguous' THEN
        'Encontramos mais de um capítulo PMI ativo na sua filiação. Escolha por qual capítulo você entra no Núcleo para ajustarmos a governança e os indicadores do seu capítulo. Leva um clique no seu perfil.'
      WHEN 'profile_private' THEN
        'Seu perfil no community.pmi.org está com a visibilidade privada, então não conseguimos ler seus capítulos para definir seu capítulo de entrada no Núcleo. Acesse community.pmi.org, deixe seu perfil público (ao menos a seção de capítulos) e nós atualizamos automaticamente.'
      WHEN 'no_fetch' THEN
        'Ainda não localizamos seu perfil no community.pmi.org. Se você tem filiação PMI, confira se o perfil está criado e público em community.pmi.org para confirmarmos seu capítulo de entrada no Núcleo automaticamente.'
      ELSE
        'Não conseguimos confirmar uma filiação PMI ativa no seu perfil do community.pmi.org. Para registrarmos seu capítulo de entrada no Núcleo, verifique se sua filiação PMI está ativa e se o capítulo aparece no seu perfil em community.pmi.org. Assim que estiver regular, atualizamos automaticamente.'
    END;

    v_plan := v_plan || jsonb_build_object(
      'member_id', v_rec.member_id,
      'name', v_rec.applicant_name,
      'bucket', v_rec.bucket,
      'title', v_title
    );

    IF p_dry_run THEN
      CONTINUE;
    END IF;

    -- Dedup: do not re-fire if this member already got the nudge in the last 30 days.
    IF EXISTS (
      SELECT 1 FROM public.notifications n
      WHERE n.recipient_id = v_rec.member_id
        AND n.type = 'entry_chapter_action_needed'
        AND n.created_at > now() - interval '30 days'
    ) THEN
      v_skipped := v_skipped + 1;
      CONTINUE;
    END IF;

    PERFORM public.create_notification(
      v_rec.member_id,
      'entry_chapter_action_needed',
      v_title,
      v_body,
      '/profile#entry-chapter-card'
    );
    v_sent := v_sent + 1;
  END LOOP;

  RETURN jsonb_build_object(
    'dry_run', p_dry_run,
    'cycle_id', p_cycle_id,
    'candidates', jsonb_array_length(v_plan),
    'sent', v_sent,
    'skipped_recent', v_skipped,
    'plan', v_plan
  );
END;
$function$;

COMMENT ON FUNCTION public.nudge_entry_chapter_cohort(uuid, boolean) IS
  '#1224 PR2 — producer of the entry-chapter nudge blast. Reuses get_entry_chapter_diagnosis + create_notification. Targets members with entry_chapter_code IS NULL and an actionable bucket (ambiguous | profile_private | no_fetch | not_affiliated). Type entry_chapter_action_needed => transactional_immediate => jobid-9 email cron. dry_run=true (default) returns the plan without inserting (blast is approved before firing). 30-day per-recipient dedup guard. manage_platform-gated; service_role/postgres allowed.';

REVOKE ALL ON FUNCTION public.nudge_entry_chapter_cohort(uuid, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.nudge_entry_chapter_cohort(uuid, boolean) TO authenticated, service_role;
