-- Os links do portal do candidato (/pmi-onboarding/<token>) passam a sair em https://nucleoia.org.
--
-- Antes, três funções montavam o link em https://nucleoia.vitormr.dev e o lembrete do piloto em
-- https://nucleoia.pmigo.org.br. O host agora vem de um lugar só, public._portal_origin(), e as quatro
-- funções o chamam.
--
-- Cada função abaixo é a definição VIVA (pg_get_functiondef, lida em 07/11/2026), e a única mudança é
-- o host. A de dispatch_pending_welcomes difere da última migration que a define (20260516510003): o
-- vivo não tem os comentários de linha e traz rpc_version 'p92_phase_f_v2'. Esta migration registra o
-- vivo.
--
-- Só o link novo muda: o token é o mesmo, e um e-mail já enviado continua com o host em que saiu.

CREATE OR REPLACE FUNCTION public._portal_origin()
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$ SELECT 'https://nucleoia.org'::text $function$;

REVOKE ALL ON FUNCTION public._portal_origin() FROM PUBLIC, anon, authenticated;

COMMENT ON FUNCTION public._portal_origin() IS
  'Origem dos links do portal do candidato (/pmi-onboarding/<token>) nos e-mails. Lida pelas funções que montam o link.';

-- dispatch_pending_welcomes: corpo vivo md5 4629b24798ecf58e7288a02f3f86ea85; muda só o host do link.
CREATE OR REPLACE FUNCTION public.dispatch_pending_welcomes(p_dry_run boolean DEFAULT true, p_max_count integer DEFAULT NULL::integer, p_ttl_days integer DEFAULT 14)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_caller record;
  v_app record;
  v_token text;
  v_token_hash text;
  v_onboarding_url text;
  v_first_name text;
  v_role_label text;
  v_dispatched int := 0;
  v_skipped int := 0;
  v_processed jsonb := '[]'::jsonb;
  v_errors jsonb := '[]'::jsonb;
  v_count int := 0;
  v_role_labels jsonb := jsonb_build_object(
    'leader', 'Líder de Tribo',
    'researcher', 'Pesquisador',
    'manager', 'Gerente de Projeto',
    'both', 'Pesquisador / Líder'
  );
BEGIN
  SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: member not found';
  END IF;
  IF NOT public.can_by_member(v_caller.id, 'manage_member'::text) THEN
    RAISE EXCEPTION 'Unauthorized: requires manage_member';
  END IF;

  FOR v_app IN
    SELECT a.id, a.applicant_name, a.email, a.role_applied, a.chapter,
           a.organization_id, a.cycle_id
    FROM public.selection_applications a
    JOIN public.selection_cycles c ON c.id = a.cycle_id
    WHERE a.status = 'submitted'
      AND c.status = 'open'
      AND a.ai_analysis IS NULL
      AND a.consent_ai_analysis_at IS NULL
      AND NOT EXISTS (
        SELECT 1 FROM public.onboarding_tokens t
        WHERE t.source_id = a.id
          AND t.source_type = 'pmi_application'
          AND t.expires_at > now()
          AND t.consumed_at IS NULL
      )
    ORDER BY a.created_at ASC
  LOOP
    v_count := v_count + 1;
    IF p_max_count IS NOT NULL AND v_count > p_max_count THEN
      EXIT;
    END IF;

    v_first_name := split_part(v_app.applicant_name, ' ', 1);
    v_role_label := COALESCE(v_role_labels->>v_app.role_applied, v_app.role_applied, 'Voluntário');

    IF p_dry_run THEN
      v_processed := v_processed || jsonb_build_object(
        'application_id', v_app.id,
        'applicant_name', v_app.applicant_name,
        'email', v_app.email,
        'chapter', v_app.chapter,
        'role_applied', v_app.role_applied,
        'role_label', v_role_label,
        'first_name', v_first_name,
        'would_dispatch', true
      );
      v_dispatched := v_dispatched + 1;
      CONTINUE;
    END IF;

    BEGIN
      v_token := translate(
        regexp_replace(encode(extensions.gen_random_bytes(32), 'base64'), '=+$', '', 'g'),
        '+/',
        '-_'
      );
      v_token_hash := encode(extensions.digest(v_token, 'sha256'), 'hex');

      INSERT INTO public.onboarding_tokens (
        token, source_type, source_id, scopes,
        issued_at, expires_at, issued_by, organization_id
      ) VALUES (
        v_token, 'pmi_application', v_app.id,
        ARRAY['profile_completion', 'video_screening', 'consent_giving'],
        now(), now() + (p_ttl_days || ' days')::interval,
        v_caller.id, v_app.organization_id
      );

      v_onboarding_url := public._portal_origin() || '/pmi-onboarding/' || v_token;

      PERFORM public.campaign_send_one_off(
        p_template_slug := 'pmi_welcome_with_token',
        p_to_email := v_app.email,
        p_variables := jsonb_build_object(
          'first_name', v_first_name,
          'role_label', v_role_label,
          'chapter', COALESCE(v_app.chapter, 'Núcleo IA & GP'),
          'onboarding_url', v_onboarding_url,
          'expires_in_days', p_ttl_days
        ),
        p_metadata := jsonb_build_object(
          'source', 'dispatch_pending_welcomes',
          'application_id', v_app.id,
          'onboarding_token_hash', v_token_hash,
          'rpc_version', 'p92_phase_f_v2'
        )
      );

      v_dispatched := v_dispatched + 1;
      v_processed := v_processed || jsonb_build_object(
        'application_id', v_app.id,
        'applicant_name', v_app.applicant_name,
        'email', v_app.email,
        'token_hash', v_token_hash,
        'expires_at', (now() + (p_ttl_days || ' days')::interval)::text,
        'dispatched', true
      );

      INSERT INTO public.admin_audit_log (
        actor_id, action, target_type, target_id, changes, metadata
      ) VALUES (
        v_caller.id,
        'selection.bulk_welcome_dispatched',
        'selection_application',
        v_app.id,
        jsonb_build_object(
          'token_hash', v_token_hash,
          'expires_in_days', p_ttl_days,
          'email', v_app.email
        ),
        jsonb_build_object(
          'source', 'dispatch_pending_welcomes',
          'rpc_version', 'p92_phase_f_v2',
          'cycle_id', v_app.cycle_id,
          'incident', 'p91-bulk-import-skip-welcome'
        )
      );

      -- p92 v2: throttle Resend (5 req/sec hard cap). 0.3s = 3.3 req/sec, safe.
      -- Sem isso, batch >5 hits 429 rate_limit_exceeded (caught p92 round 1).
      PERFORM pg_sleep(0.3);

    EXCEPTION WHEN OTHERS THEN
      v_skipped := v_skipped + 1;
      v_errors := v_errors || jsonb_build_object(
        'application_id', v_app.id,
        'applicant_name', v_app.applicant_name,
        'error', SQLERRM
      );
    END;
  END LOOP;

  RETURN jsonb_build_object(
    'success', true,
    'dry_run', p_dry_run,
    'dispatched', v_dispatched,
    'skipped', v_skipped,
    'processed', v_processed,
    'errors', v_errors,
    'run_at', now()
  );
END;
$function$;

-- dispatch_consent_nudge: corpo vivo md5 37a27337876f5790888158a9249bc935; muda só o host do link.
CREATE OR REPLACE FUNCTION public.dispatch_consent_nudge(p_dry_run boolean DEFAULT true, p_max_count integer DEFAULT NULL::integer, p_ttl_days integer DEFAULT 14)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_caller record;
  v_app record;
  v_token text;
  v_token_hash text;
  v_onboarding_url text;
  v_first_name text;
  v_role_label text;
  v_dispatched int := 0;
  v_skipped int := 0;
  v_processed jsonb := '[]'::jsonb;
  v_errors jsonb := '[]'::jsonb;
  v_count int := 0;
  v_existing_token record;
  v_path text;
  v_role_labels jsonb := jsonb_build_object(
    'leader', 'Líder de Tribo',
    'researcher', 'Pesquisador',
    'manager', 'Gerente de Projeto',
    'both', 'Pesquisador / Líder'
  );
BEGIN
  -- Authority gate (mirrors dispatch_pending_welcomes)
  SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: member not found';
  END IF;
  IF NOT public.can_by_member(v_caller.id, 'manage_member'::text) THEN
    RAISE EXCEPTION 'Unauthorized: requires manage_member';
  END IF;

  FOR v_app IN
    SELECT a.id, a.applicant_name, a.email, a.role_applied, a.chapter,
           a.organization_id, a.cycle_id
    FROM public.selection_applications a
    JOIN public.selection_cycles c ON c.id = a.cycle_id
    WHERE a.status = 'submitted'
      AND c.status = 'open'
      AND a.consent_ai_analysis_at IS NULL
      AND a.consent_ai_analysis_revoked_at IS NULL
      -- At least one token was issued (ensures phase F dispatcher already covered this app)
      AND EXISTS (
        SELECT 1 FROM public.onboarding_tokens t
        WHERE t.source_id = a.id AND t.source_type = 'pmi_application'
      )
      -- NEVER accessed any token (excludes "declined at portal" intentional opt-out signal)
      AND NOT EXISTS (
        SELECT 1 FROM public.onboarding_tokens t
        WHERE t.source_id = a.id AND t.source_type = 'pmi_application'
          AND t.last_accessed_at IS NOT NULL
      )
      -- No nudge in last 7 days (idempotency)
      AND NOT EXISTS (
        SELECT 1 FROM public.admin_audit_log al
        WHERE al.target_type = 'selection_application'
          AND al.target_id = a.id
          AND al.action = 'selection.consent_nudge_dispatched'
          AND al.created_at > now() - interval '7 days'
      )
    ORDER BY a.created_at ASC
  LOOP
    v_count := v_count + 1;
    IF p_max_count IS NOT NULL AND v_count > p_max_count THEN
      EXIT;
    END IF;

    v_first_name := split_part(v_app.applicant_name, ' ', 1);
    v_role_label := COALESCE(v_role_labels->>v_app.role_applied, v_app.role_applied, 'Voluntário');

    -- Prefer reusing a still-valid token; else re-issue
    SELECT t.token, t.expires_at INTO v_existing_token
    FROM public.onboarding_tokens t
    WHERE t.source_id = v_app.id AND t.source_type = 'pmi_application'
      AND t.expires_at > now()
      AND t.consumed_at IS NULL
    ORDER BY t.expires_at DESC
    LIMIT 1;

    IF v_existing_token.token IS NOT NULL THEN
      v_path := 'reuse_valid_token';
      v_token := v_existing_token.token;
      v_onboarding_url := public._portal_origin() || '/pmi-onboarding/' || v_token;
      v_token_hash := encode(extensions.digest(v_token, 'sha256'), 'hex');
    ELSE
      v_path := 'reissue_expired_token';
      v_token := translate(
        regexp_replace(encode(extensions.gen_random_bytes(32), 'base64'), '=+$', '', 'g'),
        '+/',
        '-_'
      );
      v_token_hash := encode(extensions.digest(v_token, 'sha256'), 'hex');
      v_onboarding_url := public._portal_origin() || '/pmi-onboarding/' || v_token;
    END IF;

    IF p_dry_run THEN
      v_processed := v_processed || jsonb_build_object(
        'application_id', v_app.id,
        'applicant_name', v_app.applicant_name,
        'email', v_app.email,
        'chapter', v_app.chapter,
        'path', v_path,
        'would_dispatch', true
      );
      v_dispatched := v_dispatched + 1;
      CONTINUE;
    END IF;

    BEGIN
      -- Re-issue token if needed
      IF v_path = 'reissue_expired_token' THEN
        INSERT INTO public.onboarding_tokens (
          token, source_type, source_id, scopes,
          issued_at, expires_at, issued_by, organization_id
        ) VALUES (
          v_token,
          'pmi_application',
          v_app.id,
          ARRAY['profile_completion', 'video_screening', 'consent_giving'],
          now(),
          now() + (p_ttl_days || ' days')::interval,
          v_caller.id,
          v_app.organization_id
        );
      END IF;

      PERFORM public.campaign_send_one_off(
        p_template_slug := 'pmi_consent_nudge',
        p_to_email := v_app.email,
        p_variables := jsonb_build_object(
          'first_name', v_first_name,
          'role_label', v_role_label,
          'chapter', COALESCE(v_app.chapter, 'Núcleo IA & GP'),
          'onboarding_url', v_onboarding_url,
          'expires_in_days', p_ttl_days
        ),
        p_metadata := jsonb_build_object(
          'source', 'dispatch_consent_nudge',
          'application_id', v_app.id,
          'onboarding_token_hash', v_token_hash,
          'path', v_path,
          'rpc_version', 'p117_consent_nudge_v1'
        )
      );

      v_dispatched := v_dispatched + 1;
      v_processed := v_processed || jsonb_build_object(
        'application_id', v_app.id,
        'applicant_name', v_app.applicant_name,
        'email', v_app.email,
        'token_hash', v_token_hash,
        'path', v_path,
        'dispatched', true
      );

      INSERT INTO public.admin_audit_log (
        actor_id, action, target_type, target_id, changes, metadata
      ) VALUES (
        v_caller.id,
        'selection.consent_nudge_dispatched',
        'selection_application',
        v_app.id,
        jsonb_build_object(
          'token_hash', v_token_hash,
          'path', v_path,
          'expires_in_days', p_ttl_days,
          'email', v_app.email
        ),
        jsonb_build_object(
          'source', 'dispatch_consent_nudge',
          'rpc_version', 'p117_consent_nudge_v1',
          'cycle_id', v_app.cycle_id
        )
      );

      -- Resend rate-limit guard (5 req/sec hard cap; 0.3s = 3.3 req/sec safe)
      PERFORM pg_sleep(0.3);

    EXCEPTION WHEN OTHERS THEN
      v_skipped := v_skipped + 1;
      v_errors := v_errors || jsonb_build_object(
        'application_id', v_app.id,
        'applicant_name', v_app.applicant_name,
        'path', v_path,
        'error', SQLERRM
      );
    END;
  END LOOP;

  RETURN jsonb_build_object(
    'success', true,
    'dry_run', p_dry_run,
    'dispatched', v_dispatched,
    'skipped', v_skipped,
    'processed', v_processed,
    'errors', v_errors,
    'run_at', now()
  );
END;
$function$;

-- reissue_onboarding_link: corpo vivo md5 5cbb66097dee79ef68f47518438b79fd; muda só o host do link.
CREATE OR REPLACE FUNCTION public.reissue_onboarding_link(p_application_id uuid, p_ttl_days integer DEFAULT 14, p_dry_run boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_caller record;
  v_app record;
  v_token text;
  v_token_hash text;
  v_url text;
  v_first_name text;
  v_role_label text;
  v_expires timestamptz;
  v_ativos int;
  v_role_labels jsonb := jsonb_build_object(
    'leader', 'Líder de Tribo',
    'researcher', 'Pesquisador',
    'manager', 'Gerente de Projeto',
    'both', 'Pesquisador / Líder'
  );
BEGIN
  -- Mesmo portao de `dispatch_pending_welcomes`: reemitir link de acesso e ato de ciclo de vida.
  SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: member not found';
  END IF;
  IF NOT public.can_by_member(v_caller.id, 'manage_member'::text) THEN
    RAISE EXCEPTION 'Unauthorized: requires manage_member';
  END IF;

  IF p_ttl_days IS NULL OR p_ttl_days < 1 OR p_ttl_days > 90 THEN
    RAISE EXCEPTION 'p_ttl_days fora da faixa 1..90: %', p_ttl_days;
  END IF;

  SELECT a.id, a.applicant_name, a.email, a.role_applied, a.chapter,
         a.organization_id, a.status
    INTO v_app
  FROM public.selection_applications a
  WHERE a.id = p_application_id;

  IF v_app IS NULL THEN
    RAISE EXCEPTION 'Candidatura nao encontrada: %', p_application_id;
  END IF;

  -- Aceita `submitted` E `approved`. O recorte so-`submitted` do dispatch e exatamente o defeito:
  -- ele assume que o onboarding acontece ANTES da aprovacao, e a coorte de 13/09 mostra 4 pessoas
  -- aprovadas e travadas DEPOIS dela.
  IF v_app.status NOT IN ('submitted', 'approved') THEN
    RAISE EXCEPTION 'Reemissao so vale para candidatura submitted ou approved; esta esta em %', v_app.status;
  END IF;

  -- Nao reemite por cima de link VIVO: dois links validos para a mesma pessoa e convite para usar o
  -- errado, e o mais antigo continuaria valendo ate expirar.
  SELECT count(*) INTO v_ativos
  FROM public.onboarding_tokens t
  WHERE t.source_id = v_app.id
    AND t.source_type = 'pmi_application'
    AND t.scopes @> ARRAY['profile_completion']::text[]
    AND t.consumed_at IS NULL
    AND t.expires_at > now();

  IF v_ativos > 0 AND NOT p_dry_run THEN
    RETURN jsonb_build_object(
      'success', false,
      'reason', 'link_ativo_existente',
      'detail', format('%s link(s) de onboarding ainda valido(s); reemitir criaria ambiguidade', v_ativos),
      'application_id', v_app.id
    );
  END IF;

  v_first_name := split_part(v_app.applicant_name, ' ', 1);
  v_role_label := COALESCE(v_role_labels->>v_app.role_applied, v_app.role_applied, 'Voluntário');
  v_expires := now() + (p_ttl_days || ' days')::interval;

  IF p_dry_run THEN
    RETURN jsonb_build_object(
      'success', true,
      'dry_run', true,
      'application_id', v_app.id,
      'status', v_app.status,
      'to_email', v_app.email,
      'role_label', v_role_label,
      'links_ativos_hoje', v_ativos,
      'would_expire_at', v_expires
    );
  END IF;

  v_token := translate(
    regexp_replace(encode(extensions.gen_random_bytes(32), 'base64'), '=+$', '', 'g'),
    '+/', '-_'
  );
  v_token_hash := encode(extensions.digest(v_token, 'sha256'), 'hex');

  INSERT INTO public.onboarding_tokens (
    token, source_type, source_id, scopes,
    issued_at, expires_at, issued_by, organization_id
  ) VALUES (
    v_token, 'pmi_application', v_app.id,
    ARRAY['profile_completion', 'video_screening', 'consent_giving'],
    now(), v_expires, v_caller.id, v_app.organization_id
  );

  v_url := public._portal_origin() || '/pmi-onboarding/' || v_token;

  PERFORM public.campaign_send_one_off(
    p_template_slug := 'pmi_welcome_with_token',
    p_to_email := v_app.email,
    p_variables := jsonb_build_object(
      'first_name', v_first_name,
      'role_label', v_role_label,
      'chapter', COALESCE(v_app.chapter, 'Núcleo IA & GP'),
      'onboarding_url', v_url,
      'expires_in_days', p_ttl_days
    ),
    p_metadata := jsonb_build_object(
      'source', 'reissue_onboarding_link',
      'application_id', v_app.id,
      'onboarding_token_hash', v_token_hash,
      'application_status', v_app.status,
      'rpc_version', 'i2265_v1'
    )
  );

  INSERT INTO public.admin_audit_log (
    actor_id, action, target_type, target_id, changes, metadata
  ) VALUES (
    v_caller.id,
    'selection.onboarding_link_reissued',
    'selection_application',
    v_app.id,
    jsonb_build_object(
      'token_hash', v_token_hash,
      'expires_in_days', p_ttl_days,
      'application_status', v_app.status
    ),
    jsonb_build_object(
      'source', 'reissue_onboarding_link',
      'rpc_version', 'i2265_v1',
      'incident', 'i2265-sem-caminho-de-volta'
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'dry_run', false,
    'application_id', v_app.id,
    'status', v_app.status,
    'token_hash', v_token_hash,
    'expires_at', v_expires
  );
END;
$function$;

-- _lembrete_do_portal_do_piloto_cron: corpo vivo md5 4c77e4016f52968db76591472b572c96; muda só o host do link.
CREATE OR REPLACE FUNCTION public._lembrete_do_portal_do_piloto_cron()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  r record;
  v_enviados int := 0;
  v_falhas int := 0;
BEGIN
  -- Uma vez por candidatura: o token do portal tem de 4 a 6 dias, nenhum token da candidatura foi aberto, ela segue
  -- inscrita e o lembrete ainda não saiu. A janela curta deixa de fora quem já recebeu aviso manual.
  FOR r IN
    SELECT DISTINCT ON (sa.id) sa.id AS application_id, sa.email, sa.applicant_name, t.token, vo.title, vo.video_invite_by
      FROM public.selection_applications sa
      JOIN public.vep_opportunities vo ON vo.opportunity_id = sa.vep_opportunity_id
       AND vo.evaluation_track = 'line_pilot' AND vo.video_invite_by IS NOT NULL
      JOIN public.onboarding_tokens t ON t.source_type = 'pmi_application' AND t.source_id = sa.id
       AND t.scopes && ARRAY['profile_completion', 'consent_giving']::text[] AND t.expires_at > now()
     WHERE sa.status = 'submitted'
       AND sa.pilot_portal_reminder_at IS NULL
       AND sa.email IS NOT NULL
       AND t.issued_at <= now() - interval '4 days'
       AND t.issued_at > now() - interval '6 days'
       AND NOT EXISTS (SELECT 1 FROM public.onboarding_tokens t2
                        WHERE t2.source_type = 'pmi_application' AND t2.source_id = sa.id AND t2.access_count > 0)
     ORDER BY sa.id, t.issued_at DESC
  LOOP
    BEGIN
      PERFORM public.campaign_send_one_off(
        'pmi_pilot_portal_reminder', r.email,
        jsonb_build_object(
          'first_name', split_part(btrim(r.applicant_name), ' ', 1),
          'role_label', btrim(regexp_replace(r.title, '\s+-\s+Núcleo\y.*$', '')),
          'onboarding_url', public._portal_origin() || '/pmi-onboarding/' || r.token,
          'video_invite_by', to_char(r.video_invite_by, 'DD/MM/YYYY')),
        jsonb_build_object('source', 'pilot_portal_reminder', 'application_id', r.application_id));
      UPDATE public.selection_applications SET pilot_portal_reminder_at = now() WHERE id = r.application_id;
      v_enviados := v_enviados + 1;
    EXCEPTION WHEN OTHERS THEN
      v_falhas := v_falhas + 1;
      RAISE WARNING '_lembrete_do_portal_do_piloto_cron: % falhou: %', left(r.application_id::text, 8), SQLERRM;
    END;
  END LOOP;
  RETURN jsonb_build_object('sent', v_enviados, 'failed', v_falhas);
END;
$function$;
