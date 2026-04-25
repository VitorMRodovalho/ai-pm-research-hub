-- ADR-0022 W1 — producer updates (set delivery_mode at INSERT time).
--
-- Spec: docs/specs/SPEC_ADR_0022_W1.md §4 (producer touch-points).
-- Scope (Q6): minimal update — only the 5 mandatory-immediate types.
-- The 3 suppress types (attendance_detractor, info, system) are also
-- mapped here so future inserts route correctly. Conditional types
-- (attendance_reminder, governance_vote_reminder, tribe_broadcast) fall to
-- the column default 'digest_weekly' until W2/W3 implements per-row decisions.
--
-- Strategy:
--   1. Add helper `_delivery_mode_for(p_type)` — pure SQL function returning
--      the catalog-defined delivery_mode for a given type.
--   2. Update the 3 overloaded `create_notification(...)` variants to set
--      delivery_mode via the helper at INSERT time. (Helper used so all
--      callsites get routing for free without listing types per producer.)
--   3. Update the 3 direct-INSERT producers (notify_offboard_cascade,
--      sign_volunteer_agreement, counter_sign_certificate) to include
--      delivery_mode.

-- ============================================================================
-- 1. Helper: _delivery_mode_for(p_type)
-- ============================================================================

CREATE OR REPLACE FUNCTION public._delivery_mode_for(p_type text)
RETURNS text
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
AS $function$
  SELECT CASE p_type
    -- Mandatory transactional_immediate (W1 catalog Q6)
    WHEN 'volunteer_agreement_signed'   THEN 'transactional_immediate'
    WHEN 'ip_ratification_gate_pending' THEN 'transactional_immediate'
    WHEN 'system_alert'                 THEN 'transactional_immediate'
    WHEN 'certificate_ready'            THEN 'transactional_immediate'
    WHEN 'member_offboarded'            THEN 'transactional_immediate'
    -- In-app only (suppressed from email)
    WHEN 'attendance_detractor'         THEN 'suppress'
    WHEN 'info'                         THEN 'suppress'
    WHEN 'system'                       THEN 'suppress'
    -- Default: digest_weekly (12 conditional/digest types)
    ELSE 'digest_weekly'
  END;
$function$;

COMMENT ON FUNCTION public._delivery_mode_for(text) IS
  'ADR-0022 W1 — single source of truth for type→delivery_mode mapping. Mirrors docs/adr/ADR-0022-notification-types-catalog.json. Producers call this helper at INSERT time so adding a new type only requires editing the catalog + this function (or the catalog and contract test will flag the drift).';

REVOKE ALL ON FUNCTION public._delivery_mode_for(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public._delivery_mode_for(text) TO authenticated, anon, service_role;

-- ============================================================================
-- 2. Update the 3 create_notification overloads to set delivery_mode
-- ============================================================================

-- 2a. 6-param variant: (recipient, type, source_type, source_id, source_title, actor_id)
CREATE OR REPLACE FUNCTION public.create_notification(
  p_recipient_id uuid,
  p_type text,
  p_source_type text DEFAULT NULL::text,
  p_source_id uuid DEFAULT NULL::uuid,
  p_source_title text DEFAULT NULL::text,
  p_actor_id uuid DEFAULT NULL::uuid
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE v_notif_id uuid; v_prefs record;
BEGIN
  IF p_recipient_id = p_actor_id THEN RETURN NULL; END IF;
  SELECT * INTO v_prefs FROM notification_preferences WHERE member_id = p_recipient_id;
  IF FOUND THEN
    IF v_prefs.in_app = false THEN RETURN NULL; END IF;
    IF p_type = ANY(v_prefs.muted_types) THEN RETURN NULL; END IF;
  END IF;
  INSERT INTO notifications (recipient_id, type, source_type, source_id, title, actor_id, delivery_mode)
  VALUES (p_recipient_id, p_type, p_source_type, p_source_id, p_source_title, p_actor_id,
          public._delivery_mode_for(p_type))
  RETURNING id INTO v_notif_id;
  RETURN v_notif_id;
END;
$function$;

-- 2b. 7-param variant: (recipient, type, title, body, link, source_type, source_id)
CREATE OR REPLACE FUNCTION public.create_notification(
  p_recipient_id uuid,
  p_type text,
  p_title text,
  p_body text DEFAULT NULL::text,
  p_link text DEFAULT NULL::text,
  p_source_type text DEFAULT NULL::text,
  p_source_id uuid DEFAULT NULL::uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_prefs notification_preferences%ROWTYPE;
BEGIN
  SELECT * INTO v_prefs FROM notification_preferences WHERE member_id = p_recipient_id;
  IF FOUND THEN
    IF NOT v_prefs.in_app THEN RETURN; END IF;
    IF p_type = ANY(v_prefs.muted_types) THEN RETURN; END IF;
  END IF;

  INSERT INTO notifications (recipient_id, type, title, body, link, source_type, source_id, delivery_mode)
  VALUES (p_recipient_id, p_type, p_title, p_body, p_link, p_source_type, p_source_id,
          public._delivery_mode_for(p_type));
END;
$function$;

-- 2c. 7-param body variant: (recipient, type, source_type, source_id, source_title, actor_id, body)
CREATE OR REPLACE FUNCTION public.create_notification(
  p_recipient_id uuid,
  p_type text,
  p_source_type text,
  p_source_id uuid,
  p_source_title text,
  p_actor_id uuid,
  p_body text DEFAULT NULL::text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE v_notif_id uuid; v_prefs record;
BEGIN
  IF p_recipient_id = p_actor_id THEN RETURN NULL; END IF;
  SELECT * INTO v_prefs FROM notification_preferences WHERE member_id = p_recipient_id;
  IF FOUND THEN
    IF v_prefs.in_app = false THEN RETURN NULL; END IF;
    IF p_type = ANY(v_prefs.muted_types) THEN RETURN NULL; END IF;
  END IF;
  INSERT INTO notifications (recipient_id, type, source_type, source_id, title, body, actor_id, delivery_mode)
  VALUES (p_recipient_id, p_type, p_source_type, p_source_id, p_source_title, p_body, p_actor_id,
          public._delivery_mode_for(p_type))
  RETURNING id INTO v_notif_id;
  RETURN v_notif_id;
END;
$function$;

-- ============================================================================
-- 3. Update direct-INSERT producers to include delivery_mode
-- ============================================================================

-- 3a. notify_offboard_cascade: emits 'member_offboarded' to GP/DM/leaders
CREATE OR REPLACE FUNCTION public.notify_offboard_cascade()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_actor         uuid;
  v_title         text;
  v_body          text;
  v_link          text;
  v_stakeholders  uuid[];
BEGIN
  IF NEW.member_status NOT IN ('alumni','observer','inactive') THEN
    RETURN NEW;
  END IF;

  v_actor := NEW.offboarded_by;

  v_title := CASE NEW.member_status
    WHEN 'alumni'   THEN COALESCE(NEW.name,'Membro') || ' saiu da equipe (alumni)'
    WHEN 'observer' THEN COALESCE(NEW.name,'Membro') || ' passou a observador(a)'
    WHEN 'inactive' THEN COALESCE(NEW.name,'Membro') || ' foi desativado(a)'
  END;
  v_body := NULLIF(TRIM(COALESCE(NEW.status_change_reason,'')), '');
  v_link := '/admin/members/' || NEW.id::text;

  SELECT array_agg(DISTINCT m.id)
  INTO v_stakeholders
  FROM public.members m
  WHERE m.is_active = true
    AND m.id <> NEW.id
    AND m.id IS DISTINCT FROM v_actor
    AND (
      m.operational_role IN ('manager','deputy_manager')
      OR (
        NEW.tribe_id IS NOT NULL
        AND m.tribe_id = NEW.tribe_id
        AND m.operational_role IN ('tribe_leader','co_leader')
      )
    );

  IF v_stakeholders IS NOT NULL AND cardinality(v_stakeholders) > 0 THEN
    INSERT INTO public.notifications
      (recipient_id, type, title, body, link, source_type, source_id, actor_id, delivery_mode)
    SELECT rid, 'member_offboarded', v_title, v_body, v_link, 'member', NEW.id, v_actor,
           public._delivery_mode_for('member_offboarded')
    FROM unnest(v_stakeholders) AS rid;
  END IF;

  PERFORM public.detect_orphan_assignees_from_offboards(NEW.id);

  RETURN NEW;
END;
$function$;

COMMENT ON FUNCTION public.notify_offboard_cascade() IS
  'fast-path stakeholder fan-out per ADR-0011 Amendment A — enumerates GPs/DMs/leaders to notify on member offboard. ADR-0022: delivery_mode derived via _delivery_mode_for(member_offboarded) → transactional_immediate.';

-- 3b. sign_volunteer_agreement: emits 'volunteer_agreement_signed' to chapter_board + manager
-- (preserve full body; only the final INSERT INTO notifications block changes)
CREATE OR REPLACE FUNCTION public.sign_volunteer_agreement(p_language text DEFAULT 'pt-BR'::text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_member record; v_template record; v_cert_id uuid; v_code text; v_hash text;
  v_content jsonb; v_cycle int; v_existing uuid; v_issuer_id uuid; v_vep record;
  v_period_start date; v_period_end date;
  v_member_role_for_vep text; v_history record; v_source text;
  v_missing_fields text[] := '{}';
  v_engagement_updated boolean := false;
  v_chapter_cnpj text; v_chapter_legal_name text;
BEGIN
  SELECT m.id, m.name, m.email, m.operational_role, m.pmi_id, m.chapter,
    m.phone, m.address, m.city, m.state, m.country, m.birth_date,
    t.name as tribe_name
  INTO v_member
  FROM members m LEFT JOIN tribes t ON t.id = public.get_member_tribe(m.id)
  WHERE m.auth_id = auth.uid();
  IF v_member.id IS NULL THEN RETURN jsonb_build_object('error', 'not_authenticated'); END IF;

  IF v_member.pmi_id IS NULL OR length(trim(v_member.pmi_id)) = 0 THEN
    v_missing_fields := array_append(v_missing_fields, 'pmi_id');
  END IF;
  IF v_member.phone IS NULL OR length(trim(v_member.phone)) = 0 THEN
    v_missing_fields := array_append(v_missing_fields, 'phone');
  END IF;
  IF v_member.address IS NULL OR length(trim(v_member.address)) = 0 THEN
    v_missing_fields := array_append(v_missing_fields, 'address');
  END IF;
  IF v_member.city IS NULL OR length(trim(v_member.city)) = 0 THEN
    v_missing_fields := array_append(v_missing_fields, 'city');
  END IF;
  IF v_member.state IS NULL OR length(trim(v_member.state)) = 0 THEN
    v_missing_fields := array_append(v_missing_fields, 'state');
  END IF;
  IF v_member.country IS NULL OR length(trim(v_member.country)) = 0 THEN
    v_missing_fields := array_append(v_missing_fields, 'country');
  END IF;
  IF v_member.birth_date IS NULL THEN
    v_missing_fields := array_append(v_missing_fields, 'birth_date');
  END IF;

  IF array_length(v_missing_fields, 1) > 0 THEN
    RETURN jsonb_build_object(
      'error', 'profile_incomplete',
      'message', 'Você precisa completar seu perfil antes de assinar o Termo de Voluntariado.',
      'missing_fields', to_jsonb(v_missing_fields),
      'profile_url', '/profile'
    );
  END IF;

  SELECT cr.cnpj, cr.legal_name INTO v_chapter_cnpj, v_chapter_legal_name
  FROM chapter_registry cr
  WHERE cr.chapter_code = v_member.chapter AND cr.is_active = true;

  IF v_chapter_cnpj IS NULL THEN
    SELECT cr.cnpj, cr.legal_name INTO v_chapter_cnpj, v_chapter_legal_name
    FROM chapter_registry cr
    WHERE cr.is_contracting_chapter = true AND cr.is_active = true
    LIMIT 1;
  END IF;

  IF v_chapter_cnpj IS NULL THEN
    v_chapter_cnpj := '06.065.645/0001-99';
    v_chapter_legal_name := 'PMI Goias';
  END IF;

  v_cycle := EXTRACT(YEAR FROM now())::int;
  SELECT id INTO v_existing FROM certificates
  WHERE member_id = v_member.id AND type = 'volunteer_agreement' AND cycle = v_cycle AND status = 'issued';
  IF v_existing IS NOT NULL THEN RETURN jsonb_build_object('error', 'already_signed', 'certificate_id', v_existing); END IF;

  SELECT * INTO v_template FROM governance_documents
  WHERE doc_type = 'volunteer_term_template' AND status = 'active'
  ORDER BY created_at DESC LIMIT 1;
  IF v_template.id IS NULL THEN RETURN jsonb_build_object('error', 'template_not_found'); END IF;

  SELECT id INTO v_issuer_id FROM members
  WHERE chapter = v_member.chapter AND 'chapter_board' = ANY(designations) AND is_active = true
  ORDER BY operational_role = 'sponsor' DESC LIMIT 1;
  IF v_issuer_id IS NULL THEN
    SELECT id INTO v_issuer_id FROM members WHERE operational_role = 'manager' AND is_active = true LIMIT 1;
  END IF;

  v_member_role_for_vep := CASE
    WHEN v_member.operational_role IN ('manager', 'deputy_manager') THEN 'manager'
    WHEN v_member.operational_role = 'tribe_leader' THEN 'leader'
    ELSE 'researcher'
  END;

  SELECT vo.* INTO v_vep FROM selection_applications sa
  JOIN vep_opportunities vo ON vo.opportunity_id = sa.vep_opportunity_id
  WHERE lower(trim(sa.email)) = lower(trim(v_member.email))
    AND vo.role_default = v_member_role_for_vep
    AND EXTRACT(YEAR FROM vo.start_date) = v_cycle
  ORDER BY sa.created_at DESC LIMIT 1;

  IF v_vep.opportunity_id IS NOT NULL THEN
    v_period_start := v_vep.start_date; v_period_end := v_vep.end_date; v_source := 'application_match';
  ELSE
    SELECT vo.* INTO v_vep FROM selection_applications sa
    JOIN vep_opportunities vo ON vo.opportunity_id = sa.vep_opportunity_id
    WHERE lower(trim(sa.email)) = lower(trim(v_member.email))
      AND EXTRACT(YEAR FROM vo.start_date) = v_cycle
    ORDER BY sa.created_at DESC LIMIT 1;
    IF v_vep.opportunity_id IS NOT NULL THEN
      v_period_start := v_vep.start_date; v_period_end := v_vep.end_date; v_source := 'application_year_match';
    ELSE
      SELECT cycle_code, cycle_start, cycle_end INTO v_history
      FROM member_cycle_history WHERE member_id = v_member.id
      ORDER BY cycle_start DESC LIMIT 1;
      IF v_history.cycle_code IS NOT NULL THEN
        v_period_start := v_history.cycle_start;
        v_period_end := (v_history.cycle_start + interval '12 months' - interval '1 day')::date;
        v_source := 'cycle_history:' || v_history.cycle_code;
      ELSE
        SELECT * INTO v_vep FROM vep_opportunities
        WHERE EXTRACT(YEAR FROM start_date) = v_cycle
          AND role_default = v_member_role_for_vep AND is_active = true
        ORDER BY start_date DESC LIMIT 1;
        IF v_vep.opportunity_id IS NOT NULL THEN
          v_period_start := v_vep.start_date; v_period_end := v_vep.end_date; v_source := 'founder_role_vep';
        ELSE
          RETURN jsonb_build_object('error', 'cannot_derive_period',
            'message', 'No application, cycle history, or matching VEP found. Admin must set period manually.',
            'member_id', v_member.id, 'member_name', v_member.name);
        END IF;
      END IF;
    END IF;
  END IF;

  v_content := jsonb_build_object(
    'template_id', v_template.id, 'template_version', v_template.version, 'template_title', v_template.title,
    'member_name', v_member.name, 'member_email', v_member.email, 'member_role', v_member.operational_role,
    'member_tribe', v_member.tribe_name, 'member_pmi_id', v_member.pmi_id, 'member_chapter', v_member.chapter,
    'member_phone', v_member.phone, 'member_address', v_member.address,
    'member_city', v_member.city, 'member_state', v_member.state,
    'member_country', v_member.country, 'member_birth_date', v_member.birth_date,
    'language', p_language, 'signed_at', now(),
    'chapter_cnpj', v_chapter_cnpj, 'chapter_name', v_chapter_legal_name,
    'vep_opportunity_id', v_vep.opportunity_id, 'vep_title', v_vep.title,
    'period_start', v_period_start::text, 'period_end', v_period_end::text,
    'period_source', v_source
  );

  v_code := 'TERM-' || EXTRACT(YEAR FROM now())::text || '-' || UPPER(SUBSTRING(gen_random_uuid()::text FROM 1 FOR 6));
  v_hash := encode(sha256(convert_to(v_content::text || v_member.id::text || now()::text || 'nucleo-ia-volunteer-salt', 'UTF8')), 'hex');

  INSERT INTO certificates (
    member_id, type, title, description, cycle, issued_at, issued_by, verification_code,
    period_start, period_end, function_role, language, status, signature_hash, content_snapshot, template_id
  ) VALUES (
    v_member.id, 'volunteer_agreement',
    CASE p_language WHEN 'en-US' THEN 'Volunteer Agreement — Cycle ' || v_cycle
      WHEN 'es-LATAM' THEN 'Acuerdo de Voluntariado — Ciclo ' || v_cycle
      ELSE 'Termo de Voluntariado — Ciclo ' || v_cycle END,
    v_template.description, v_cycle, now(), v_issuer_id, v_code,
    v_period_start::text, v_period_end::text,
    v_member.operational_role, p_language, 'issued', v_hash, v_content, v_template.id::text
  ) RETURNING id INTO v_cert_id;

  UPDATE public.engagements
  SET agreement_certificate_id = v_cert_id
  WHERE person_id = (SELECT id FROM public.persons WHERE legacy_member_id = v_member.id)
    AND kind = 'volunteer'
    AND status = 'active'
    AND agreement_certificate_id IS NULL;

  IF FOUND THEN v_engagement_updated := true; END IF;

  INSERT INTO admin_audit_log (actor_id, action, target_type, target_id, changes)
  VALUES (v_member.id, 'volunteer_agreement_signed', 'certificate', v_cert_id,
    jsonb_build_object('verification_code', v_code, 'cycle', v_cycle, 'chapter', v_member.chapter,
      'chapter_cnpj', v_chapter_cnpj,
      'period_source', v_source, 'engagement_linked', v_engagement_updated));

  INSERT INTO notifications (recipient_id, type, title, body, link, source_type, source_id, delivery_mode)
  SELECT m.id, 'volunteer_agreement_signed',
    v_member.name || ' assinou o Termo de Voluntariado',
    'Capitulo: ' || COALESCE(v_member.chapter, '—') || '. Codigo: ' || v_code,
    '/admin/certificates', 'certificate', v_cert_id,
    public._delivery_mode_for('volunteer_agreement_signed')
  FROM members m
  WHERE m.is_active = true AND m.id != v_member.id
    AND (m.operational_role = 'manager' OR m.is_superadmin = true
         OR ('chapter_board' = ANY(m.designations) AND m.chapter = v_member.chapter));

  RETURN jsonb_build_object('success', true, 'certificate_id', v_cert_id, 'verification_code', v_code,
    'signature_hash', v_hash, 'signed_at', now(),
    'period_start', v_period_start, 'period_end', v_period_end, 'period_source', v_source,
    'engagement_linked', v_engagement_updated,
    'chapter_cnpj', v_chapter_cnpj, 'chapter_name', v_chapter_legal_name);
END;
$function$;

-- 3c. counter_sign_certificate: emits 'certificate_ready' to recipient
CREATE OR REPLACE FUNCTION public.counter_sign_certificate(p_certificate_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_member_id uuid; v_member_chapter text;
  v_is_manager boolean; v_is_chapter_board boolean;
  v_cert record; v_contracting_chapter text; v_hash text;
BEGIN
  SELECT m.id, m.chapter,
    (m.operational_role IN ('manager') OR m.is_superadmin = true),
    ('chapter_board' = ANY(m.designations))
  INTO v_member_id, v_member_chapter, v_is_manager, v_is_chapter_board
  FROM members m WHERE m.auth_id = auth.uid();

  IF NOT COALESCE(v_is_manager, false) AND NOT COALESCE(v_is_chapter_board, false) THEN
    RETURN jsonb_build_object('error', 'not_authorized');
  END IF;

  SELECT * INTO v_cert FROM certificates WHERE id = p_certificate_id;
  IF v_cert IS NULL THEN RETURN jsonb_build_object('error', 'not_found'); END IF;
  IF v_cert.counter_signed_by IS NOT NULL THEN RETURN jsonb_build_object('error', 'already_counter_signed'); END IF;

  v_contracting_chapter := COALESCE(
    v_cert.content_snapshot->>'contracting_chapter',
    (SELECT m.chapter FROM members m WHERE m.id = v_cert.member_id)
  );

  IF v_is_chapter_board AND NOT v_is_manager THEN
    IF v_contracting_chapter IS DISTINCT FROM v_member_chapter THEN
      RETURN jsonb_build_object('error', 'not_authorized_different_chapter');
    END IF;
  END IF;

  v_hash := encode(sha256(convert_to(
    COALESCE(v_cert.signature_hash,'') || v_member_id::text || now()::text || 'nucleo-ia-countersign-salt', 'UTF8'
  )), 'hex');

  UPDATE certificates SET counter_signed_by = v_member_id, counter_signed_at = now() WHERE id = p_certificate_id;

  INSERT INTO admin_audit_log (actor_id, action, target_type, target_id, changes)
  VALUES (v_member_id, 'certificate_counter_signed', 'certificate', p_certificate_id,
    jsonb_build_object('verification_code', v_cert.verification_code, 'type', v_cert.type, 'contracting_chapter', v_contracting_chapter));

  INSERT INTO notifications (recipient_id, type, title, body, link, source_type, source_id, delivery_mode)
  VALUES (v_cert.member_id, 'certificate_ready',
    'Seu ' || v_cert.title || ' esta pronto!',
    'O documento foi contra-assinado e esta disponivel. Codigo: ' || v_cert.verification_code,
    '/certificates', 'certificate', p_certificate_id,
    public._delivery_mode_for('certificate_ready'));

  RETURN jsonb_build_object('success', true, 'counter_signature_hash', v_hash, 'counter_signed_at', now());
END;
$function$;

NOTIFY pgrst, 'reload schema';
