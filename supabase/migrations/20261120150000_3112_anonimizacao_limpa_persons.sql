-- #3112: as três anonimizações limpam também a pessoa em persons.
--
-- admin_anonymize_member e anonymize_inactive_members anonimizavam members e não tocavam persons: a
-- ponte da #2732 leva só o nome, então e-mail, auth_id, telefone, endereço, cidade, nascimento, pmi_id e
-- perfis ficavam na linha da pessoa. anonymize_by_engagement_kind trocava em persons só nome, e-mail e
-- auth_id. Desde a #2556, update_my_profile grava o dado pessoal também em persons.
--
-- _anonymize_person_pii faz a limpeza de persons num lugar só, com o mesmo padrão de nome e e-mail
-- anônimos que anonymize_by_engagement_kind já usava. As três funções o chamam. O resto dos corpos é a
-- captura vigente (20260805000419 e 20260805000313), sem outra mudança. Consentimento fica: é registro.
-- Correção preventiva: medido em 20/11/2026, nenhuma linha anonimizada hoje.

CREATE OR REPLACE FUNCTION public._anonymize_person_pii(p_person_id uuid, p_member_id uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_n integer;
BEGIN
  UPDATE public.persons p SET
    name = 'Pessoa Anonimizada #' || SUBSTR(p.id::text, 1, 8),
    email = 'anon_' || SUBSTR(p.id::text, 1, 8) || '@removed.local',
    auth_id = NULL,
    phone = NULL, address = NULL, city = NULL, birth_date = NULL,
    pmi_id = NULL, linkedin_url = NULL, photo_url = NULL,
    credly_url = NULL, credly_badges = NULL, credly_verified_at = NULL,
    state = NULL, country = NULL, secondary_emails = '{}'::text[],
    share_whatsapp = false, share_address = false, share_birth_date = false,
    anonymized_at = now(), updated_at = now()
  WHERE p.id = p_person_id
     OR (p_member_id IS NOT NULL AND p.legacy_member_id = p_member_id);
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n;
END;
$function$;

CREATE OR REPLACE FUNCTION public.admin_anonymize_member(p_member_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'storage', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_target_email text;
  v_target_name text;
  -- #1017: route applications through the shared _erase_application_pii helper
  v_app_ids uuid[];
  v_app_id uuid;
  v_child jsonb;
  v_c_resume int := 0;
  v_c_video int := 0;
  v_c_children int := 0;
  v_c_calib int := 0;
  v_c_apps int := 0;
BEGIN
  SELECT id INTO v_caller_id FROM public.members
  WHERE auth_id = auth.uid() AND is_superadmin = true;

  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: only superadmin can anonymize members';
  END IF;

  IF NOT public.can_by_member(v_caller_id, 'manage_member') THEN
    RAISE EXCEPTION 'Unauthorized: superadmin must also have manage_member engagement';
  END IF;

  SELECT email, name INTO v_target_email, v_target_name
  FROM public.members WHERE id = p_member_id;

  IF v_target_email IS NULL THEN
    RAISE EXCEPTION 'Member not found';
  END IF;

  UPDATE public.members SET
    name = 'Membro Anonimizado #' || SUBSTR(p_member_id::text, 1, 8),
    email = 'anon_' || SUBSTR(p_member_id::text, 1, 8) || '@removed.local',
    phone = NULL, phone_encrypted = NULL,
    pmi_id = NULL, pmi_id_encrypted = NULL,
    linkedin_url = NULL, photo_url = NULL,
    credly_url = NULL, credly_badges = NULL,
    address = NULL, city = NULL, birth_date = NULL,
    state = NULL, country = NULL,
    signature_url = NULL, secondary_emails = NULL,
    last_active_pages = NULL, auth_id = NULL, secondary_auth_ids = NULL,
    is_active = false, member_status = 'archived',
    anonymized_at = now(), anonymized_by = v_caller_id,
    updated_at = now()
  WHERE id = p_member_id;

  -- #3112: a mesma pessoa em persons. A ponte da #2732 copia só o nome; e-mail, auth_id e o dado pessoal ficavam.
  PERFORM public._anonymize_person_pii(
    (SELECT m.person_id FROM public.members m WHERE m.id = p_member_id), p_member_id);

  UPDATE public.member_offboarding_records SET
    reason_detail = NULL, exit_interview_full_text = NULL,
    return_window_suggestion = NULL, lessons_learned = NULL,
    recommendation_for_future = NULL, attachment_urls = '{}'::text[],
    updated_at = now()
  WHERE member_id = p_member_id;

  -- BUG FIX: column is `recipient_id`, not `member_id` (notification_preferences IS member_id).
  DELETE FROM public.notifications WHERE recipient_id = p_member_id;
  DELETE FROM public.notification_preferences WHERE member_id = p_member_id;

  -- #1017: erase the member's selection application(s) uniformly via the shared helper (was a
  -- LIGHT ~6-field scrub that left child tables + full mother-row + calibration name). Resolve the
  -- ids by the captured (pre-scrub) email, snapshot first (the helper mutates the mother-row email).
  SELECT array_agg(id) INTO v_app_ids
  FROM public.selection_applications WHERE email = v_target_email;
  IF v_app_ids IS NOT NULL THEN
    FOREACH v_app_id IN ARRAY v_app_ids LOOP
      v_child := public._erase_application_pii(v_app_id);
      v_c_resume   := v_c_resume   + COALESCE((v_child->>'resume_objects_deleted')::int, 0);
      v_c_video    := v_c_video    + COALESCE((v_child->>'video_screenings_deleted')::int, 0);
      v_c_children := v_c_children + COALESCE((v_child->>'child_rows_deleted')::int, 0);
      v_c_calib    := v_c_calib    + COALESCE((v_child->>'calibration_runs_scrubbed')::int, 0);
      v_c_apps     := v_c_apps + 1;
    END LOOP;
  END IF;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes)
  VALUES (v_caller_id, 'lgpd_manual_anonymization', 'member', p_member_id,
    jsonb_build_object(
      'anonymized_at', now(),
      'original_name_hash', md5(COALESCE(v_target_name, '')),
      'legal_basis', 'LGPD Lei 13.709/2018 Art. 18 — manual admin anonymization',
      'offboarding_record_cleared', true,
      'applications_erased', v_c_apps,
      'resume_objects_deleted', v_c_resume,
      'video_screenings_deleted', v_c_video,
      'child_rows_deleted', v_c_children,
      'calibration_runs_scrubbed', v_c_calib
    ));

  RETURN jsonb_build_object(
    'anonymized', true,
    'member_id', p_member_id,
    'applications_erased', v_c_apps,
    'resume_objects_deleted', v_c_resume,
    'video_screenings_deleted', v_c_video,
    'child_rows_deleted', v_c_children,
    'calibration_runs_scrubbed', v_c_calib
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.anonymize_inactive_members(
  p_dry_run boolean DEFAULT true,
  p_years integer DEFAULT 5,
  p_limit integer DEFAULT 100
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'storage', 'pg_temp'
AS $function$
DECLARE
  v_candidate record;
  v_count int := 0;
  v_skipped int := 0;
  v_license_preserved int := 0;  -- #976 PR-4
  v_ids uuid[] := '{}';
  v_errors jsonb := '[]'::jsonb;
  v_aff_scrubbed int := 0;  -- #625
  -- #946 shared-helper aggregation
  v_app_ids uuid[];
  v_app_id uuid;
  v_child jsonb;
  v_resume_deleted_total int := 0;
  v_video_deleted_total int := 0;
  v_children_deleted_total int := 0;
  v_calib_scrubbed_total int := 0;
  v_c_resume int;
  v_c_video int;
  v_c_children int;
  v_c_calib int;
  v_c_apps int;
BEGIN
  FOR v_candidate IN
    SELECT * FROM public.list_anonymization_candidates(p_years) LIMIT p_limit
  LOOP
    BEGIN
      -- #976 PR-4 (15.4.5 / §9.1 Opção B): preserva quem detém licença viva (signature
      -- is_current). Um voluntário desligado por recusa/lapso de re-aceite mantém suas
      -- licenças; a linha de assinatura (que materializa a licença de PI) não pode ser
      -- anonimizada enquanto a licença vigorar.
      IF EXISTS (SELECT 1 FROM public.member_document_signatures mds
                 WHERE mds.member_id = v_candidate.member_id AND mds.is_current = true) THEN
        v_skipped := v_skipped + 1;
        v_license_preserved := v_license_preserved + 1;
        -- review (legal HIGH): visibilidade ao DPO — o deferimento por licença de PI não é silencioso;
        -- requisições LGPD Art.18(IV) desse titular roteiam ao DPO (Art.16(I) × Art.18(IV)).
        IF NOT p_dry_run THEN
          INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes)
          VALUES (NULL, 'lgpd.anonymization_deferred_ip_license', 'member', v_candidate.member_id,
            jsonb_build_object(
              'legal_basis', 'LGPD Art. 16(I) — IP license enforcement (Termo 15.4.5)',
              'art18_requests_require_dpo_review', true, 'signature_is_current', true,
              'source', 'cron:anonymize_inactive_members'));
        END IF;
        CONTINUE;
      END IF;

      IF NOT p_dry_run THEN
        UPDATE public.members SET
          name = 'Membro Anonimizado #' || SUBSTR(v_candidate.member_id::text, 1, 8),
          email = 'anon_' || SUBSTR(v_candidate.member_id::text, 1, 8) || '@removed.local',
          phone = NULL, phone_encrypted = NULL,
          pmi_id = NULL, pmi_id_encrypted = NULL,
          linkedin_url = NULL, photo_url = NULL,
          credly_url = NULL, credly_badges = NULL,
          address = NULL, city = NULL, birth_date = NULL,
          state = NULL, country = NULL,
          signature_url = NULL, secondary_emails = NULL,
          last_active_pages = NULL, auth_id = NULL, secondary_auth_ids = NULL,
          is_active = false, member_status = 'archived',
          anonymized_at = now(), anonymized_by = NULL,
          updated_at = now()
        WHERE id = v_candidate.member_id;

        -- #3112: a mesma pessoa em persons (a ponte da #2732 copia só o nome).
        PERFORM public._anonymize_person_pii(
          (SELECT m.person_id FROM public.members m WHERE m.id = v_candidate.member_id), v_candidate.member_id);

        UPDATE public.member_offboarding_records SET
          reason_detail = NULL, exit_interview_full_text = NULL,
          return_window_suggestion = NULL, lessons_learned = NULL,
          recommendation_for_future = NULL, attachment_urls = '{}'::text[],
          updated_at = now()
        WHERE member_id = v_candidate.member_id;

        -- BUG FIX: column is `recipient_id`, not `member_id`.
        DELETE FROM public.notifications WHERE recipient_id = v_candidate.member_id;
        DELETE FROM public.notification_preferences WHERE member_id = v_candidate.member_id;

        -- #946: erase the member's prior selection application(s) uniformly via the shared helper.
        -- Resolve the application ids by the candidate's (pre-scrub) email — the SAME set the old
        -- light scrub reached — snapshotting the ids first (the helper mutates the mother-row email).
        -- The helper covers the resume binary, ALL child tables, the full mother-row scrub, and the
        -- ai_calibration_runs.sample_payload name scrub (previously the member path left all of these).
        v_c_resume := 0; v_c_video := 0; v_c_children := 0; v_c_calib := 0; v_c_apps := 0;
        SELECT array_agg(id) INTO v_app_ids
        FROM public.selection_applications WHERE email = v_candidate.email;
        IF v_app_ids IS NOT NULL THEN
          FOREACH v_app_id IN ARRAY v_app_ids LOOP
            v_child := public._erase_application_pii(v_app_id);
            v_c_resume   := v_c_resume   + COALESCE((v_child->>'resume_objects_deleted')::int, 0);
            v_c_video    := v_c_video    + COALESCE((v_child->>'video_screenings_deleted')::int, 0);
            v_c_children := v_c_children + COALESCE((v_child->>'child_rows_deleted')::int, 0);
            v_c_calib    := v_c_calib    + COALESCE((v_child->>'calibration_runs_scrubbed')::int, 0);
            v_c_apps     := v_c_apps + 1;
          END LOOP;
        END IF;
        v_resume_deleted_total   := v_resume_deleted_total   + v_c_resume;
        v_video_deleted_total    := v_video_deleted_total    + v_c_video;
        v_children_deleted_total := v_children_deleted_total  + v_c_children;
        v_calib_scrubbed_total   := v_calib_scrubbed_total   + v_c_calib;

        -- #625 F1: de-identifica a trilha de verificação de filiação do titular (subject).
        -- A linha de members já foi anonimizada acima (in-place), então member_id/verified_by
        -- de-referenciam para registro neutro; aqui só zera os campos livres/técnicos.
        UPDATE public.member_affiliation_verifications SET
          verification_obs = NULL,
          source_ref = CASE WHEN source_ref IS NOT NULL THEN md5(source_ref) ELSE NULL END,
          verified_by_member_id = NULL  -- #625: desreferencia o verificador (minimização Art. 6º III)
        WHERE member_id = v_candidate.member_id;
        GET DIAGNOSTICS v_aff_scrubbed = ROW_COUNT;

        -- #625: remove notificações de filiação SOBRE o titular enviadas a TERCEIROS (ex.: diretor),
        -- cujo body carrega o nome e não é limpo pela deleção das notificações do próprio titular acima.
        DELETE FROM public.notifications
        WHERE source_type = 'affiliation' AND source_id = v_candidate.member_id;

        INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes)
        VALUES (NULL, 'lgpd_automated_anonymization', 'member', v_candidate.member_id,
          jsonb_build_object(
            'anonymized_at', now(),
            'years_inactive', v_candidate.years_inactive,
            'inactivity_anchor', v_candidate.inactivity_anchor,
            'retention_years', p_years,
            'legal_basis', 'LGPD Lei 13.709/2018 Art. 16 — retention limit reached',
            'source', 'cron:anonymize_inactive_members',
            'offboarding_record_cleared', true,
            'applications_erased', v_c_apps,
            'resume_objects_deleted', v_c_resume,
            'video_screenings_deleted', v_c_video,
            'child_rows_deleted', v_c_children,
            'calibration_runs_scrubbed', v_c_calib,
            'affiliation_rows_scrubbed', v_aff_scrubbed
          ));
      END IF;

      v_count := v_count + 1;
      v_ids := array_append(v_ids, v_candidate.member_id);
    EXCEPTION WHEN OTHERS THEN
      v_skipped := v_skipped + 1;
      v_errors := v_errors || jsonb_build_object('member_id', v_candidate.member_id, 'error', SQLERRM);
    END;
  END LOOP;

  RETURN jsonb_build_object(
    'dry_run', p_dry_run,
    'years_threshold', p_years,
    'processed', v_count,
    'skipped', v_skipped,
    'license_preserved', v_license_preserved,  -- #976 PR-4
    'member_ids', to_jsonb(v_ids),
    'resume_objects_deleted_total', v_resume_deleted_total,
    'video_screenings_deleted_total', v_video_deleted_total,
    'child_rows_deleted_total', v_children_deleted_total,
    'calibration_runs_scrubbed_total', v_calib_scrubbed_total,
    'errors', v_errors,
    'executed_at', now()
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.anonymize_by_engagement_kind(p_dry_run boolean DEFAULT true, p_limit integer DEFAULT 500)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_person record;
  v_count int := 0;
  v_skipped int := 0;
  v_results jsonb := '[]'::jsonb;
  v_errors jsonb := '[]'::jsonb;
  v_strictest_policy text;
  -- #1016: route the person's application(s) through the shared _erase_application_pii helper
  v_member_email text;
  v_emails text[];
  v_app_ids uuid[];
  v_app_id uuid;
  v_child jsonb;
  v_c_resume int;
  v_c_video int;
  v_c_children int;
  v_c_calib int;
  v_c_apps int;
  v_apps_erased_total int := 0;
  v_child_rows_erased_total int := 0;
BEGIN
  FOR v_person IN
    SELECT
      p.id AS person_id,
      p.name AS person_name,
      p.email AS person_email,
      p.legacy_member_id,
      CASE
        WHEN bool_or(ek.anonymization_policy = 'retain_for_legal') THEN 'retain_for_legal'
        WHEN bool_or(ek.anonymization_policy = 'anonymize') THEN 'anonymize'
        ELSE 'delete'
      END AS effective_policy,
      max(e.end_date + make_interval(days => COALESCE(ek.retention_days_after_end, 1825))) AS latest_retention_end,
      count(*) AS engagement_count
    FROM public.persons p
    JOIN public.engagements e ON e.person_id = p.id
    JOIN public.engagement_kinds ek ON ek.slug = e.kind
    WHERE p.anonymized_at IS NULL
      AND e.status IN ('offboarded', 'expired')
      AND e.end_date IS NOT NULL
      AND (e.end_date + make_interval(days => COALESCE(ek.retention_days_after_end, 1825))) < CURRENT_DATE
    GROUP BY p.id, p.name, p.email, p.legacy_member_id
    HAVING NOT EXISTS (
      SELECT 1 FROM public.engagements e2
      WHERE e2.person_id = p.id AND e2.status IN ('active', 'suspended')
    )
    ORDER BY max(e.end_date) ASC
    LIMIT p_limit
  LOOP
    BEGIN
      v_strictest_policy := v_person.effective_policy;

      -- #976 PR-4 (15.4.5 / §9.1 Opção B): preserva quem detém licença viva (signature is_current).
      -- In-loop skip (não WHERE-exclusion) p/ dar VISIBILIDADE ao DPO (review legal HIGH): registra o
      -- deferimento e sinaliza que requisições LGPD Art.18(IV) desse titular roteiam ao DPO (tradeoff
      -- Art.16(I) base de retenção por licença de PI × Art.18(IV) apagamento). legacy_member_id NULL
      -- (pessoa sem member) => sem ledger possível => segue p/ anonimização normal.
      IF v_person.legacy_member_id IS NOT NULL AND EXISTS (
           SELECT 1 FROM public.member_document_signatures mds
           WHERE mds.member_id = v_person.legacy_member_id AND mds.is_current = true) THEN
        v_skipped := v_skipped + 1;
        IF NOT p_dry_run THEN
          INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes)
          VALUES (NULL, 'lgpd.anonymization_deferred_ip_license', 'member', v_person.legacy_member_id,
            jsonb_build_object('person_id', v_person.person_id,
              'legal_basis', 'LGPD Art. 16(I) — IP license enforcement (Termo 15.4.5)',
              'art18_requests_require_dpo_review', true, 'signature_is_current', true,
              'source', 'cron:anonymize_by_engagement_kind'));
        END IF;
        v_results := v_results || jsonb_build_object(
          'person_id', v_person.person_id, 'action', 'license_preserved', 'reason', 'member_document_signatures is_current'
        );
        CONTINUE;
      END IF;

      IF v_strictest_policy = 'retain_for_legal' THEN
        v_skipped := v_skipped + 1;
        v_results := v_results || jsonb_build_object(
          'person_id', v_person.person_id, 'action', 'retained', 'reason', 'retain_for_legal policy'
        );
        CONTINUE;
      END IF;

      IF NOT p_dry_run THEN
        -- #1016: erase the person's selection application(s) via the shared helper BEFORE scrubbing
        -- the person/member emails (resolution is email-anchored). person email + optional member email.
        v_emails := '{}';
        IF v_person.person_email IS NOT NULL THEN v_emails := array_append(v_emails, v_person.person_email); END IF;
        IF v_person.legacy_member_id IS NOT NULL THEN
          SELECT email INTO v_member_email FROM public.members WHERE id = v_person.legacy_member_id;
          IF v_member_email IS NOT NULL THEN v_emails := array_append(v_emails, v_member_email); END IF;
        END IF;
        v_c_resume := 0; v_c_video := 0; v_c_children := 0; v_c_calib := 0; v_c_apps := 0;
        IF array_length(v_emails, 1) > 0 THEN
          SELECT array_agg(DISTINCT id) INTO v_app_ids
          FROM public.selection_applications WHERE email = ANY(v_emails);
          IF v_app_ids IS NOT NULL THEN
            FOREACH v_app_id IN ARRAY v_app_ids LOOP
              v_child := public._erase_application_pii(v_app_id);
              v_c_resume   := v_c_resume   + COALESCE((v_child->>'resume_objects_deleted')::int, 0);
              v_c_video    := v_c_video    + COALESCE((v_child->>'video_screenings_deleted')::int, 0);
              v_c_children := v_c_children + COALESCE((v_child->>'child_rows_deleted')::int, 0);
              v_c_calib    := v_c_calib    + COALESCE((v_child->>'calibration_runs_scrubbed')::int, 0);
              v_c_apps     := v_c_apps + 1;
            END LOOP;
          END IF;
        END IF;
        v_apps_erased_total := v_apps_erased_total + v_c_apps;
        v_child_rows_erased_total := v_child_rows_erased_total + v_c_children;

        -- #3112: o helper troca nome, e-mail e auth_id como antes e limpa também o dado pessoal.
        PERFORM public._anonymize_person_pii(v_person.person_id, NULL);

        IF v_person.legacy_member_id IS NOT NULL THEN
          UPDATE public.members SET
            name = 'Membro Anonimizado #' || SUBSTR(v_person.legacy_member_id::text, 1, 8),
            email = 'anon_' || SUBSTR(v_person.legacy_member_id::text, 1, 8) || '@removed.local',
            phone = NULL, phone_encrypted = NULL, pmi_id = NULL, pmi_id_encrypted = NULL,
            linkedin_url = NULL, photo_url = NULL, credly_url = NULL, credly_badges = NULL,
            address = NULL, city = NULL, birth_date = NULL, state = NULL, country = NULL,
            signature_url = NULL, secondary_emails = NULL, last_active_pages = NULL,
            auth_id = NULL, secondary_auth_ids = NULL, is_active = false,
            member_status = 'archived', anonymized_at = now(), anonymized_by = NULL, updated_at = now()
          WHERE id = v_person.legacy_member_id;
          DELETE FROM public.notifications WHERE member_id = v_person.legacy_member_id;
          DELETE FROM public.notification_preferences WHERE member_id = v_person.legacy_member_id;
        END IF;

        UPDATE public.engagements SET status = 'anonymized', updated_at = now()
        WHERE person_id = v_person.person_id;

        IF v_strictest_policy = 'delete' THEN
          DELETE FROM public.persons WHERE id = v_person.person_id;
        END IF;

        INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes)
        VALUES (NULL, 'lgpd_v4_anonymization', 'person', v_person.person_id,
          jsonb_build_object(
            'policy', v_strictest_policy, 'engagement_count', v_person.engagement_count,
            'retention_end', v_person.latest_retention_end, 'legacy_member_id', v_person.legacy_member_id,
            'legal_basis', 'LGPD Art. 16 — retention limit per engagement_kind (ADR-0008)',
            'source', 'cron:anonymize_by_engagement_kind',
            'applications_erased', v_c_apps,
            'resume_objects_deleted', v_c_resume,
            'video_screenings_deleted', v_c_video,
            'child_rows_deleted', v_c_children,
            'calibration_runs_scrubbed', v_c_calib
          ));
      END IF;

      v_count := v_count + 1;
      v_results := v_results || jsonb_build_object(
        'person_id', v_person.person_id, 'action', v_strictest_policy,
        'retention_end', v_person.latest_retention_end, 'engagements', v_person.engagement_count
      );
    EXCEPTION WHEN OTHERS THEN
      v_skipped := v_skipped + 1;
      v_errors := v_errors || jsonb_build_object('person_id', v_person.person_id, 'error', SQLERRM);
    END;
  END LOOP;

  RETURN jsonb_build_object(
    'dry_run', p_dry_run, 'processed', v_count, 'skipped', v_skipped,
    'applications_erased_total', v_apps_erased_total,
    'child_rows_erased_total', v_child_rows_erased_total,
    'results', v_results, 'errors', v_errors, 'executed_at', now()
  );
END;
$function$;

REVOKE ALL ON FUNCTION public._anonymize_person_pii(uuid, uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._anonymize_person_pii(uuid, uuid) TO service_role;
