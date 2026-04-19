-- ============================================================================
-- Phase IP-3d — Version editor (WYSIWYG) + notifications on gate advance
--
-- Escopo:
--   1. upsert_document_version — cria/atualiza draft (locked_at IS NULL)
--   2. lock_document_version — atomic lock + create approval_chain + notify gate 1
--   3. delete_document_version_draft — cleanup de draft nao usado
--   4. list_my_document_drafts — rascunhos do caller para secao "Seus rascunhos"
--   5. get_previous_locked_version — previous locked para diff viewer
--   6. _enqueue_gate_notifications — helper que enfileira notifications por gate
--   7. Trigger AFTER INSERT em approval_signoffs — detecta gate satisfied,
--      notifica gate seguinte OU submitter (chain completa)
--
-- Decisoes:
--   * Pipeline de email: reuso do send-notification-email cron (drain 5-min
--     latency acceptable for governance). Pattern alinha com feedback
--     pgcron_url_pattern (URL hardcoded, vault key).
--   * Nao criar EF dedicada ip-ratification-notify (senior-SWE audit p33b).
--   * URL per gate_kind: admin gates -> /admin/governance/documents/[chainId];
--     member/external gates -> /governance/ip-agreement?chain_id=X.
--   * Trigger em signoffs elimina double-notif (sign_ip_ratification ja
--     auto-advances review->approved; trigger cobre notif piece).
--
-- Rollback:
--   DROP FUNCTION upsert_document_version, lock_document_version,
--     delete_document_version_draft, list_my_document_drafts,
--     get_previous_locked_version, _enqueue_gate_notifications,
--     trg_approval_signoff_notify_fn;
--   DROP TRIGGER trg_approval_signoff_notify ON approval_signoffs;
-- ============================================================================

-- ---------------------------------------------------------------------------
-- Novos types de notification — documentacao inline para o drain cron
-- ---------------------------------------------------------------------------
-- Os types abaixo sao usados em INSERT INTO notifications e consumidos por
-- send-notification-email (extensao da EF na secao pos-migration):
--   * ip_ratification_gate_pending    — signer de gate ativo deve assinar
--   * ip_ratification_gate_advanced   — gate satisfeito, proximo ativado
--   * ip_ratification_chain_approved  — chain aprovada (submitter notification)
--   * ip_ratification_awaiting_members — gate member_ratification ativo (broadcast)

-- ---------------------------------------------------------------------------
-- Helper: resolver URL de call-to-action por gate_kind
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public._ip_ratify_cta_link(
  p_chain_id uuid,
  p_gate_kind text
) RETURNS text
LANGUAGE sql
STABLE
AS $function$
  -- Member-facing gates direcionam a /governance/ip-agreement (rota publica).
  -- Admin gates direcionam a /admin/governance/documents/[chainId] (rota admin).
  SELECT CASE
    WHEN p_gate_kind IN ('member_ratification', 'external_signer')
      THEN '/governance/ip-agreement?chain_id=' || p_chain_id::text
    WHEN p_gate_kind IN ('curator', 'leader', 'leader_awareness',
                         'submitter_acceptance', 'president_go',
                         'president_others', 'chapter_witness')
      THEN '/admin/governance/documents/' || p_chain_id::text
    ELSE '/admin/governance/documents/' || p_chain_id::text
  END;
$function$;

COMMENT ON FUNCTION public._ip_ratify_cta_link(uuid, text) IS
  'Resolve CTA URL por gate_kind. Admin gates -> /admin/governance/documents; member/external -> /governance/ip-agreement. Phase IP-3d.';

-- ---------------------------------------------------------------------------
-- Helper: enqueue notifications for a gate activation
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public._enqueue_gate_notifications(
  p_chain_id uuid,
  p_event text,
  p_gate_kind text DEFAULT NULL
) RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $function$
DECLARE
  v_chain record;
  v_doc record;
  v_version record;
  v_submitter record;
  v_gate jsonb;
  v_target record;
  v_link text;
  v_title text;
  v_body text;
  v_notif_type text;
  v_enqueued int := 0;
BEGIN
  -- Validate event
  IF p_event NOT IN ('chain_opened','gate_advanced','chain_approved') THEN
    RAISE EXCEPTION 'Invalid event: % (allowed: chain_opened, gate_advanced, chain_approved)', p_event
      USING ERRCODE = 'invalid_parameter_value';
  END IF;

  -- Load chain context
  SELECT ac.id, ac.status, ac.gates, ac.document_id, ac.version_id, ac.opened_by
  INTO v_chain
  FROM public.approval_chains ac WHERE ac.id = p_chain_id;
  IF v_chain.id IS NULL THEN RETURN 0; END IF;

  SELECT gd.id, gd.title, gd.doc_type INTO v_doc
  FROM public.governance_documents gd WHERE gd.id = v_chain.document_id;

  SELECT dv.id, dv.version_label INTO v_version
  FROM public.document_versions dv WHERE dv.id = v_chain.version_id;

  SELECT m.id, m.name, m.email INTO v_submitter
  FROM public.members m WHERE m.id = v_chain.opened_by;

  -- Case 1: chain_opened — notify FIRST gate eligibles
  IF p_event = 'chain_opened' THEN
    SELECT g INTO v_gate
    FROM jsonb_array_elements(v_chain.gates) g
    ORDER BY (g->>'order')::int ASC
    LIMIT 1;
    IF v_gate IS NULL THEN RETURN 0; END IF;

    v_link := public._ip_ratify_cta_link(p_chain_id, v_gate->>'kind');
    v_notif_type := 'ip_ratification_gate_pending';

    FOR v_target IN
      SELECT m.id AS member_id, m.name
      FROM public.members m
      WHERE m.is_active = true
        AND public._can_sign_gate(m.id, p_chain_id, v_gate->>'kind')
        AND NOT EXISTS (
          SELECT 1 FROM public.approval_signoffs s
          WHERE s.approval_chain_id = p_chain_id
            AND s.gate_kind = v_gate->>'kind'
            AND s.signer_id = m.id
        )
    LOOP
      v_title := v_doc.title || ' aguarda sua acao';
      v_body := 'Voce foi identificado(a) como elegivel para assinar o gate "' ||
                (v_gate->>'kind') || '" da cadeia de ratificacao do documento "' ||
                v_doc.title || '" versao ' || COALESCE(v_version.version_label,'') || '.';

      PERFORM public.create_notification(
        v_target.member_id, v_notif_type, v_title, v_body, v_link,
        'approval_chain', p_chain_id
      );
      v_enqueued := v_enqueued + 1;
    END LOOP;
    RETURN v_enqueued;
  END IF;

  -- Case 2: gate_advanced — notify NEXT gate eligibles + submitter
  IF p_event = 'gate_advanced' AND p_gate_kind IS NOT NULL THEN
    -- Find next gate (strictly greater order than the advanced one)
    SELECT g INTO v_gate
    FROM jsonb_array_elements(v_chain.gates) g
    WHERE (g->>'order')::int > (
      SELECT (g2->>'order')::int FROM jsonb_array_elements(v_chain.gates) g2
      WHERE g2->>'kind' = p_gate_kind LIMIT 1
    )
    ORDER BY (g->>'order')::int ASC
    LIMIT 1;

    IF v_gate IS NOT NULL THEN
      v_link := public._ip_ratify_cta_link(p_chain_id, v_gate->>'kind');

      -- Broadcast type for member_ratification (open to all active members)
      IF (v_gate->>'kind') = 'member_ratification' THEN
        v_notif_type := 'ip_ratification_awaiting_members';
      ELSE
        v_notif_type := 'ip_ratification_gate_pending';
      END IF;

      FOR v_target IN
        SELECT m.id AS member_id, m.name
        FROM public.members m
        WHERE m.is_active = true
          AND public._can_sign_gate(m.id, p_chain_id, v_gate->>'kind')
          AND NOT EXISTS (
            SELECT 1 FROM public.approval_signoffs s
            WHERE s.approval_chain_id = p_chain_id
              AND s.gate_kind = v_gate->>'kind'
              AND s.signer_id = m.id
          )
      LOOP
        v_title := v_doc.title || ' — sua assinatura e necessaria';
        v_body := 'O gate "' || p_gate_kind || '" foi satisfeito. Voce agora esta elegivel para o gate "' ||
                  (v_gate->>'kind') || '" do documento "' || v_doc.title ||
                  '" versao ' || COALESCE(v_version.version_label,'') || '.';

        PERFORM public.create_notification(
          v_target.member_id, v_notif_type, v_title, v_body, v_link,
          'approval_chain', p_chain_id
        );
        v_enqueued := v_enqueued + 1;
      END LOOP;
    END IF;

    -- Always notify submitter of gate advance (GP-leader RC-2 from stakeholder-persona p33b)
    IF v_submitter.id IS NOT NULL THEN
      v_link := '/admin/governance/documents/' || p_chain_id::text;
      v_title := v_doc.title || ' — gate satisfeito';
      v_body := 'O gate "' || p_gate_kind || '" foi satisfeito na cadeia de ratificacao do documento "' ||
                v_doc.title || '" versao ' || COALESCE(v_version.version_label,'') ||
                '. Acompanhe o avanco dos proximos gates.';
      PERFORM public.create_notification(
        v_submitter.id, 'ip_ratification_gate_advanced', v_title, v_body, v_link,
        'approval_chain', p_chain_id
      );
      v_enqueued := v_enqueued + 1;
    END IF;
    RETURN v_enqueued;
  END IF;

  -- Case 3: chain_approved — submitter final notification
  IF p_event = 'chain_approved' AND v_submitter.id IS NOT NULL THEN
    v_link := '/admin/governance/documents/' || p_chain_id::text;
    v_title := v_doc.title || ' — cadeia de aprovacao concluida';
    v_body := 'Todos os gates da cadeia de ratificacao do documento "' || v_doc.title ||
              '" versao ' || COALESCE(v_version.version_label,'') ||
              ' foram satisfeitos. O documento pode ser ativado.';
    PERFORM public.create_notification(
      v_submitter.id, 'ip_ratification_chain_approved', v_title, v_body, v_link,
      'approval_chain', p_chain_id
    );
    RETURN 1;
  END IF;

  RETURN 0;
END;
$function$;

COMMENT ON FUNCTION public._enqueue_gate_notifications(uuid, text, text) IS
  'Helper: enfileira notifications no notifications table por evento de chain. Events: chain_opened (notify gate 1 eligibles), gate_advanced (notify next gate eligibles + submitter), chain_approved (notify submitter final). Drain via send-notification-email cron (5min latency). Phase IP-3d.';

-- ---------------------------------------------------------------------------
-- RPC: upsert_document_version — create or update a draft version
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.upsert_document_version(
  p_document_id uuid,
  p_content_html text,
  p_content_markdown text DEFAULT NULL,
  p_version_label text DEFAULT NULL,
  p_version_id uuid DEFAULT NULL,
  p_notes text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $function$
DECLARE
  v_member record;
  v_version record;
  v_version_id uuid;
  v_version_number int;
  v_version_label text;
  v_doc record;
BEGIN
  -- Auth
  SELECT m.id, m.name INTO v_member FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_member.id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF NOT public.can_by_member(v_member.id, 'manage_member') THEN
    RAISE EXCEPTION 'Access denied: manage_member required' USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- Validate doc
  SELECT gd.id, gd.title INTO v_doc FROM public.governance_documents gd WHERE gd.id = p_document_id;
  IF v_doc.id IS NULL THEN
    RAISE EXCEPTION 'governance_document not found (id=%)', p_document_id USING ERRCODE = 'no_data_found';
  END IF;

  IF length(coalesce(p_content_html,'')) = 0 THEN
    RAISE EXCEPTION 'content_html cannot be empty' USING ERRCODE = 'invalid_parameter_value';
  END IF;

  -- Update branch: existing draft
  IF p_version_id IS NOT NULL THEN
    SELECT dv.id, dv.document_id, dv.version_number, dv.version_label, dv.locked_at, dv.authored_by
    INTO v_version
    FROM public.document_versions dv WHERE dv.id = p_version_id;

    IF v_version.id IS NULL THEN
      RAISE EXCEPTION 'document_version not found (id=%)', p_version_id USING ERRCODE = 'no_data_found';
    END IF;
    IF v_version.document_id <> p_document_id THEN
      RAISE EXCEPTION 'document_version % does not belong to document %', p_version_id, p_document_id
        USING ERRCODE = 'invalid_parameter_value';
    END IF;
    IF v_version.locked_at IS NOT NULL THEN
      RAISE EXCEPTION 'document_version % is locked at % — immutable', p_version_id, v_version.locked_at
        USING ERRCODE = 'check_violation';
    END IF;

    UPDATE public.document_versions
      SET content_html = p_content_html,
          content_markdown = coalesce(p_content_markdown, content_markdown),
          version_label = coalesce(p_version_label, version_label),
          notes = coalesce(p_notes, notes),
          updated_at = now()
      WHERE id = p_version_id;

    v_version_id := p_version_id;
    v_version_number := v_version.version_number;
    v_version_label := coalesce(p_version_label, v_version.version_label);
  ELSE
    -- Insert branch: new draft, version_number = MAX+1 per document
    SELECT COALESCE(MAX(version_number), 0) + 1
    INTO v_version_number
    FROM public.document_versions WHERE document_id = p_document_id;

    v_version_label := coalesce(p_version_label, 'Rascunho v' || v_version_number::text);

    INSERT INTO public.document_versions (
      document_id, version_number, version_label, content_html, content_markdown,
      authored_by, authored_at, notes
    ) VALUES (
      p_document_id, v_version_number, v_version_label, p_content_html, p_content_markdown,
      v_member.id, now(), p_notes
    ) RETURNING id INTO v_version_id;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'version_id', v_version_id,
    'document_id', p_document_id,
    'version_number', v_version_number,
    'version_label', v_version_label,
    'authored_by', v_member.id,
    'updated_at', now()
  );
END;
$function$;

COMMENT ON FUNCTION public.upsert_document_version(uuid, text, text, text, uuid, text) IS
  'Cria ou atualiza draft de document_version (locked_at IS NULL). Se p_version_id provided: UPDATE (erro se locked). Else: INSERT com version_number = MAX+1. Auth: manage_member. Phase IP-3d.';

GRANT EXECUTE ON FUNCTION public.upsert_document_version(uuid, text, text, text, uuid, text) TO authenticated;

-- ---------------------------------------------------------------------------
-- RPC: lock_document_version — atomic lock + create chain + enqueue notif
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.lock_document_version(
  p_version_id uuid,
  p_gates jsonb
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $function$
DECLARE
  v_member record;
  v_version record;
  v_chain_id uuid;
  v_existing_chain uuid;
  v_notif_count int;
BEGIN
  -- Auth
  SELECT m.id, m.name INTO v_member FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_member.id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF NOT public.can_by_member(v_member.id, 'manage_member') THEN
    RAISE EXCEPTION 'Access denied: manage_member required' USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- Validate version
  SELECT dv.id, dv.document_id, dv.version_number, dv.version_label, dv.locked_at
  INTO v_version
  FROM public.document_versions dv WHERE dv.id = p_version_id;

  IF v_version.id IS NULL THEN
    RAISE EXCEPTION 'document_version not found (id=%)', p_version_id USING ERRCODE = 'no_data_found';
  END IF;
  IF v_version.locked_at IS NOT NULL THEN
    RAISE EXCEPTION 'document_version already locked at % — create a new version instead', v_version.locked_at
      USING ERRCODE = 'check_violation';
  END IF;

  -- Validate gates config shape (non-empty array with kind/order/threshold)
  IF p_gates IS NULL OR jsonb_typeof(p_gates) <> 'array' OR jsonb_array_length(p_gates) = 0 THEN
    RAISE EXCEPTION 'gates must be a non-empty jsonb array' USING ERRCODE = 'invalid_parameter_value';
  END IF;
  IF EXISTS (
    SELECT 1 FROM jsonb_array_elements(p_gates) g
    WHERE NOT (g ? 'kind' AND g ? 'order' AND g ? 'threshold')
  ) THEN
    RAISE EXCEPTION 'each gate must have kind, order, threshold keys' USING ERRCODE = 'invalid_parameter_value';
  END IF;

  -- Idempotence: if a chain for this version already exists, return it
  SELECT ac.id INTO v_existing_chain
  FROM public.approval_chains ac
  WHERE ac.version_id = p_version_id LIMIT 1;
  IF v_existing_chain IS NOT NULL THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'chain_already_exists',
      'chain_id', v_existing_chain,
      'version_id', p_version_id
    );
  END IF;

  -- Atomic: lock version + create chain + audit + enqueue notifications
  UPDATE public.document_versions
    SET locked_at = now(),
        locked_by = v_member.id,
        published_at = now(),
        published_by = v_member.id,
        updated_at = now()
    WHERE id = p_version_id;

  INSERT INTO public.approval_chains (
    document_id, version_id, status, gates, opened_at, opened_by
  ) VALUES (
    v_version.document_id, p_version_id, 'review', p_gates, now(), v_member.id
  ) RETURNING id INTO v_chain_id;

  -- Also update governance_documents.current_version_id (invariant J)
  UPDATE public.governance_documents
    SET current_version_id = p_version_id,
        updated_at = now()
    WHERE id = v_version.document_id;

  -- Audit (ADR-0016 D5 camada 2: document_version lifecycle)
  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes)
  VALUES (
    v_member.id, 'document_version.locked', 'document_version', p_version_id,
    jsonb_build_object(
      'document_id', v_version.document_id,
      'version_number', v_version.version_number,
      'version_label', v_version.version_label,
      'chain_id', v_chain_id,
      'gates', p_gates
    )
  );

  -- Notify first gate eligibles
  v_notif_count := public._enqueue_gate_notifications(v_chain_id, 'chain_opened', NULL);

  RETURN jsonb_build_object(
    'success', true,
    'version_id', p_version_id,
    'chain_id', v_chain_id,
    'notifications_enqueued', v_notif_count,
    'locked_at', now()
  );
END;
$function$;

COMMENT ON FUNCTION public.lock_document_version(uuid, jsonb) IS
  'Atomic: lock version (locked_at/by) + create approval_chain (status=review) + update current_version_id + audit + enqueue notifications gate 1. Auth: manage_member. Phase IP-3d.';

GRANT EXECUTE ON FUNCTION public.lock_document_version(uuid, jsonb) TO authenticated;

-- ---------------------------------------------------------------------------
-- RPC: delete_document_version_draft — cleanup draft (not locked)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.delete_document_version_draft(
  p_version_id uuid
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $function$
DECLARE
  v_member record;
  v_version record;
BEGIN
  SELECT m.id INTO v_member FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_member.id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF NOT public.can_by_member(v_member.id, 'manage_member') THEN
    RAISE EXCEPTION 'Access denied: manage_member required' USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT dv.id, dv.document_id, dv.version_number, dv.version_label, dv.authored_by, dv.locked_at
  INTO v_version
  FROM public.document_versions dv WHERE dv.id = p_version_id;

  IF v_version.id IS NULL THEN
    RAISE EXCEPTION 'document_version not found (id=%)', p_version_id USING ERRCODE = 'no_data_found';
  END IF;
  IF v_version.locked_at IS NOT NULL THEN
    RAISE EXCEPTION 'cannot delete locked version (locked at %)', v_version.locked_at
      USING ERRCODE = 'check_violation';
  END IF;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes)
  VALUES (
    v_member.id, 'document_version.draft_deleted', 'document_version', p_version_id,
    jsonb_build_object(
      'document_id', v_version.document_id,
      'version_number', v_version.version_number,
      'version_label', v_version.version_label,
      'authored_by', v_version.authored_by
    )
  );

  DELETE FROM public.document_versions WHERE id = p_version_id;

  RETURN jsonb_build_object('success', true, 'deleted_id', p_version_id);
END;
$function$;

COMMENT ON FUNCTION public.delete_document_version_draft(uuid) IS
  'Deleta rascunho (locked_at IS NULL) com audit log. Auth: manage_member. Phase IP-3d.';

GRANT EXECUTE ON FUNCTION public.delete_document_version_draft(uuid) TO authenticated;
-- Required for DELETE operation on document_versions
GRANT DELETE ON public.document_versions TO authenticated;

-- RLS: allow DELETE only for admin-capable members on non-locked drafts
DROP POLICY IF EXISTS document_versions_delete_drafts ON public.document_versions;
CREATE POLICY document_versions_delete_drafts ON public.document_versions
  FOR DELETE TO authenticated
  USING (
    locked_at IS NULL
    AND EXISTS (
      SELECT 1 FROM public.members m
      WHERE m.auth_id = auth.uid() AND public.can_by_member(m.id, 'manage_member')
    )
  );

-- ---------------------------------------------------------------------------
-- RPC: list_my_document_drafts — rascunhos do caller
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.list_my_document_drafts()
RETURNS TABLE (
  version_id uuid,
  document_id uuid,
  document_title text,
  doc_type text,
  version_number int,
  version_label text,
  authored_at timestamptz,
  updated_at timestamptz,
  notes text
)
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = public, pg_temp
AS $function$
DECLARE
  v_member_id uuid;
BEGIN
  SELECT m.id INTO v_member_id FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_member_id IS NULL THEN RETURN; END IF;

  RETURN QUERY
  SELECT
    dv.id AS version_id,
    dv.document_id,
    gd.title AS document_title,
    gd.doc_type,
    dv.version_number,
    dv.version_label,
    dv.authored_at,
    dv.updated_at,
    dv.notes
  FROM public.document_versions dv
  JOIN public.governance_documents gd ON gd.id = dv.document_id
  WHERE dv.locked_at IS NULL
    AND dv.authored_by = v_member_id
  ORDER BY dv.updated_at DESC;
END;
$function$;

COMMENT ON FUNCTION public.list_my_document_drafts() IS
  'Lista rascunhos (locked_at IS NULL) authored_by the current member. Phase IP-3d.';

GRANT EXECUTE ON FUNCTION public.list_my_document_drafts() TO authenticated;

-- ---------------------------------------------------------------------------
-- RPC: get_previous_locked_version — for diff viewer
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_previous_locked_version(
  p_version_id uuid
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = public, pg_temp
AS $function$
DECLARE
  v_current record;
  v_prev record;
BEGIN
  SELECT dv.id, dv.document_id, dv.version_number
  INTO v_current
  FROM public.document_versions dv WHERE dv.id = p_version_id;
  IF v_current.id IS NULL THEN
    RETURN jsonb_build_object('error','version_not_found');
  END IF;

  SELECT dv.id, dv.version_number, dv.version_label, dv.content_html,
         dv.content_markdown, dv.locked_at, dv.published_at
  INTO v_prev
  FROM public.document_versions dv
  WHERE dv.document_id = v_current.document_id
    AND dv.version_number < v_current.version_number
    AND dv.locked_at IS NOT NULL
  ORDER BY dv.version_number DESC
  LIMIT 1;

  IF v_prev.id IS NULL THEN
    RETURN jsonb_build_object('exists', false);
  END IF;

  RETURN jsonb_build_object(
    'exists', true,
    'version_id', v_prev.id,
    'version_number', v_prev.version_number,
    'version_label', v_prev.version_label,
    'content_html', v_prev.content_html,
    'content_markdown', v_prev.content_markdown,
    'locked_at', v_prev.locked_at,
    'published_at', v_prev.published_at
  );
END;
$function$;

COMMENT ON FUNCTION public.get_previous_locked_version(uuid) IS
  'Retorna previous locked document_version for diff viewer. Returns {exists:false} if this is v1. Phase IP-3d.';

GRANT EXECUTE ON FUNCTION public.get_previous_locked_version(uuid) TO authenticated;

-- ---------------------------------------------------------------------------
-- Trigger: AFTER INSERT approval_signoffs — detect gate satisfied, notify next
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.trg_approval_signoff_notify_fn()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $function$
DECLARE
  v_chain record;
  v_gate jsonb;
  v_signed_count int;
  v_threshold_num int;
  v_threshold_text text;
  v_gate_satisfied boolean := false;
  v_all_satisfied_after boolean := false;
  v_remaining_unsatisfied int;
BEGIN
  -- Only fire for approval/acknowledge signoffs (rejection doesn't advance)
  IF NEW.signoff_type NOT IN ('approval','acknowledge') THEN
    RETURN NEW;
  END IF;

  -- Load chain + gate config
  SELECT ac.id, ac.status, ac.gates INTO v_chain
  FROM public.approval_chains ac WHERE ac.id = NEW.approval_chain_id;
  IF v_chain.id IS NULL THEN RETURN NEW; END IF;

  -- Find the gate config matching the signoff
  SELECT g INTO v_gate
  FROM jsonb_array_elements(v_chain.gates) g
  WHERE g->>'kind' = NEW.gate_kind LIMIT 1;
  IF v_gate IS NULL THEN RETURN NEW; END IF;

  v_threshold_text := v_gate->>'threshold';

  -- Count satisfying signoffs for this gate (includes the row we just inserted)
  SELECT COUNT(*) INTO v_signed_count
  FROM public.approval_signoffs s
  WHERE s.approval_chain_id = NEW.approval_chain_id
    AND s.gate_kind = NEW.gate_kind
    AND s.signoff_type IN ('approval','acknowledge');

  -- Determine if this signoff tipped the gate to satisfied (exactly once: =, not >=)
  IF v_threshold_text ~ '^[0-9]+$' THEN
    v_threshold_num := v_threshold_text::int;
    IF v_threshold_num = 0 THEN
      v_gate_satisfied := (v_signed_count = 1);  -- first acknowledge
    ELSE
      v_gate_satisfied := (v_signed_count = v_threshold_num);
    END IF;
  ELSIF v_threshold_text = 'all' THEN
    -- member_ratification is open-ended; do not fire per-member notif.
    -- Notification happens only when chain is fully approved.
    v_gate_satisfied := false;
  END IF;

  -- Compute "all gates satisfied" post-insert. Mirror logic in sign_ip_ratification:
  -- threshold='all' counts as never-satisfied in this check (consistent with
  -- existing behavior — chain advances review->approved via 'all' only if all
  -- numeric gates satisfied AND the 'all' gate is logically terminal).
  SELECT COUNT(*) INTO v_remaining_unsatisfied
  FROM jsonb_array_elements(v_chain.gates) g
  WHERE (g->>'threshold') = 'all'
     OR ((g->>'threshold') ~ '^[0-9]+$'
        AND (g->>'threshold')::int > 0
        AND (SELECT COUNT(*) FROM public.approval_signoffs s
             WHERE s.approval_chain_id = NEW.approval_chain_id
               AND s.gate_kind = (g->>'kind')
               AND s.signoff_type IN ('approval','acknowledge')) < (g->>'threshold')::int)
     OR ((g->>'threshold') = '0'
        AND NOT EXISTS (SELECT 1 FROM public.approval_signoffs s
                       WHERE s.approval_chain_id = NEW.approval_chain_id
                         AND s.gate_kind = (g->>'kind')
                         AND s.signoff_type IN ('approval','acknowledge')));

  v_all_satisfied_after := (v_remaining_unsatisfied = 0);

  -- Fire exactly one notification event per trigger invocation:
  --   * chain_approved wins over gate_advanced (avoid double notif)
  IF v_all_satisfied_after AND v_gate_satisfied THEN
    PERFORM public._enqueue_gate_notifications(NEW.approval_chain_id, 'chain_approved', NEW.gate_kind);
  ELSIF v_gate_satisfied THEN
    PERFORM public._enqueue_gate_notifications(NEW.approval_chain_id, 'gate_advanced', NEW.gate_kind);
  END IF;

  RETURN NEW;
END;
$function$;

COMMENT ON FUNCTION public.trg_approval_signoff_notify_fn() IS
  'Trigger fn: on INSERT approval_signoffs, detect if gate threshold atingido (=, not >=) e enfileira notifications para proximo gate + submitter, OR chain_approved notif se todos gates satisfeitos. Phase IP-3d.';

DROP TRIGGER IF EXISTS trg_approval_signoff_notify ON public.approval_signoffs;
CREATE TRIGGER trg_approval_signoff_notify
  AFTER INSERT ON public.approval_signoffs
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_approval_signoff_notify_fn();

NOTIFY pgrst, 'reload schema';
