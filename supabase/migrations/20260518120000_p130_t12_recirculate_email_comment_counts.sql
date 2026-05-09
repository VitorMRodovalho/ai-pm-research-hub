-- p130 T-12: governance recirculate email — incluir comment counts da versão anterior
-- ============================================================================
--
-- Driver: handoff p130 (Vitor 2026-05-09 11:00 BRT). Curadores reportaram via
-- WhatsApp que ao receber email de re-circulação não conseguiam dimensionar o
-- esforço de revisão — quantos comentários da rodada anterior foram endereçados
-- vs ainda abertos. Tier 1 sprint item T-12.
--
-- Mudança 1 (template): adiciona 3 variáveis + bloco "Comentários endereçados
-- nesta versão" no body_html.
-- Mudança 2 (RPC recirculate_governance_doc): computa counts via subquery sobre
-- prior versions locked + passa ao campaign_send_one_off.
--
-- Idempotente: UPDATE em template só preenche body novo se não tem o marcador
-- {{prior_resolved_count}} (re-runs no-op). RPC é OR REPLACE (sempre seguro).
-- Compatível com chains existentes — counts default 0 quando não há prior versions.
-- ============================================================================

-- 1) Atualiza template + variáveis declaradas
UPDATE public.campaign_templates
SET
  body_html = jsonb_build_object('pt', $body$<p>Olá {{first_name}},</p>
<p>O documento de governança <strong>{{document_title}}</strong> foi atualizado para a versão <strong>{{version_label}}</strong> e precisa de sua revisão e re-assinatura na nova chain de revisão.</p>
<h3>Mudanças aplicadas</h3>
<div>{{changelog}}</div>
<h3>Comentários da rodada anterior</h3>
<p>Esta re-circulação leva em conta <strong>{{prior_resolved_count}}</strong> comentário(s) já marcado(s) como endereçado(s) na nova versão e <strong>{{prior_open_count}}</strong> ainda em aberto.</p>
<div>{{prior_addressed_summary}}</div>
<h3>Revisar e assinar</h3>
<p><a href="{{new_chain_url}}">Abrir chain v{{version_label}} para revisão e assinatura</a></p>
<p>A interface abre direto na versão nova — você pode comparar com a versão lacrada anterior via tab "Diff atual ↔ Draft" a qualquer momento.</p>
<h3>Comentários da chain anterior preservados</h3>
<p>Os comentários da chain anterior (status: superseded) permanecem disponíveis para você marcar cada ponto como resolvido conforme verificar nos novos textos:</p>
<p><a href="{{old_chain_url}}">Acessar chain anterior (comentários preservados)</a></p>
<p>Glossário canônico do Núcleo (espelho dinâmico): <a href="{{platform_url}}/governance/glossario">{{platform_url}}/governance/glossario</a></p>
<p>Qualquer dúvida ou nova ressalva, abra comentário na chain v{{version_label}} ou responda este email.</p>
<p>—<br>{{sender_name}}<br>Gerente de Projeto — Núcleo IA &amp; GP</p>$body$),
  variables = jsonb_build_object(
    'first_name', jsonb_build_object('type', 'text', 'required', true),
    'document_title', jsonb_build_object('type', 'text', 'required', true),
    'version_label', jsonb_build_object('type', 'text', 'required', true),
    'new_chain_url', jsonb_build_object('type', 'url', 'required', true),
    'old_chain_url', jsonb_build_object('type', 'url', 'required', true),
    'changelog', jsonb_build_object('type', 'html', 'required', false),
    'prior_resolved_count', jsonb_build_object('type', 'text', 'required', false),
    'prior_open_count', jsonb_build_object('type', 'text', 'required', false),
    'prior_addressed_summary', jsonb_build_object('type', 'html', 'required', false),
    'platform_url', jsonb_build_object('type', 'url', 'required', false),
    'sender_name', jsonb_build_object('type', 'text', 'required', false)
  ),
  updated_at = now()
WHERE slug='governance_recirculation_request'
  AND (body_html->>'pt')::text NOT LIKE '%{{prior_resolved_count}}%';

-- 2) RPC com computação dos counts
CREATE OR REPLACE FUNCTION public.recirculate_governance_doc(
  p_chain_id uuid,
  p_dry_run boolean DEFAULT true,
  p_recipient_emails text[] DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_member record;
  v_chain record;
  v_document record;
  v_current_version record;
  v_draft record;
  v_first_gate jsonb;
  v_first_gate_kind text;
  v_recipients jsonb := '[]'::jsonb;
  v_recipient_count int := 0;
  v_send_results jsonb := '[]'::jsonb;
  v_send record;
  v_send_result jsonb;
  v_warnings jsonb := '[]'::jsonb;
  v_lock_result jsonb;
  v_new_chain_id uuid;
  v_platform_url text := 'https://nucleoia.vitormr.dev';
  v_changelog_html text;
  v_prior_resolved_count int := 0;
  v_prior_open_count int := 0;
  v_prior_summary_html text := '';
BEGIN
  SELECT m.id, m.name INTO v_member FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_member.id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF NOT public.can_by_member(v_member.id, 'manage_member') THEN
    RAISE EXCEPTION 'Access denied: manage_member required' USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT ac.id, ac.document_id, ac.version_id, ac.status, ac.gates, ac.opened_at
  INTO v_chain
  FROM public.approval_chains ac WHERE ac.id = p_chain_id;
  IF v_chain.id IS NULL THEN
    RAISE EXCEPTION 'approval_chain not found (id=%)', p_chain_id USING ERRCODE = 'no_data_found';
  END IF;
  IF v_chain.status NOT IN ('review','active') THEN
    RAISE EXCEPTION 'approval_chain status=% — recirculation requires status review or active', v_chain.status
      USING ERRCODE = 'check_violation';
  END IF;

  SELECT gd.id, gd.title, gd.doc_type INTO v_document
  FROM public.governance_documents gd WHERE gd.id = v_chain.document_id;

  SELECT dv.id, dv.version_label, dv.version_number INTO v_current_version
  FROM public.document_versions dv WHERE dv.id = v_chain.version_id;

  SELECT dv.id, dv.version_number, dv.version_label, dv.notes, dv.locked_at
  INTO v_draft
  FROM public.document_versions dv
  WHERE dv.document_id = v_chain.document_id
    AND dv.version_number > v_current_version.version_number
    AND dv.locked_at IS NULL
  ORDER BY dv.version_number ASC LIMIT 1;
  IF v_draft.id IS NULL THEN
    RAISE EXCEPTION 'no pending draft version found for document_id=% (current version_number=%)',
      v_chain.document_id, v_current_version.version_number USING ERRCODE = 'no_data_found';
  END IF;

  SELECT g INTO v_first_gate
  FROM jsonb_array_elements(v_chain.gates) g
  ORDER BY (g->>'order')::int ASC LIMIT 1;
  v_first_gate_kind := v_first_gate->>'kind';

  IF p_recipient_emails IS NOT NULL AND array_length(p_recipient_emails, 1) IS NOT NULL THEN
    SELECT jsonb_agg(jsonb_build_object(
      'email', lower(e.email),
      'first_name', split_part(COALESCE(m.name, e.email), ' ', 1),
      'member_id', m.id,
      'source', 'explicit'
    )) INTO v_recipients
    FROM unnest(p_recipient_emails) AS e(email)
    LEFT JOIN public.members m ON lower(m.email) = lower(e.email);
  ELSE
    SELECT jsonb_agg(jsonb_build_object(
      'email', lower(m.email),
      'first_name', split_part(m.name, ' ', 1),
      'member_id', m.id,
      'source', 'auto_first_gate_eligible'
    )) INTO v_recipients
    FROM public.members m
    WHERE m.is_active = true
      AND m.email IS NOT NULL
      AND public._can_sign_gate(m.id, p_chain_id, v_first_gate_kind);
  END IF;

  IF v_recipients IS NULL OR jsonb_array_length(v_recipients) = 0 THEN
    v_warnings := v_warnings || jsonb_build_array(jsonb_build_object(
      'code', 'no_recipients',
      'message', 'No recipients computed — execution will skip email step'
    ));
    v_recipients := '[]'::jsonb;
    v_recipient_count := 0;
  ELSE
    v_recipient_count := jsonb_array_length(v_recipients);
  END IF;

  IF v_draft.notes IS NOT NULL THEN
    v_changelog_html := '<pre style="white-space:pre-wrap; font-family:monospace; font-size:13px; background:#f9fafb; padding:12px; border-radius:6px; border:1px solid #e5e7eb;">' ||
                        replace(replace(v_draft.notes, '<', '&lt;'), '>', '&gt;') ||
                        '</pre>';
  ELSE
    v_changelog_html := '<p><em>(Sem changelog detalhado nas notes do draft.)</em></p>';
  END IF;

  -- p130 T-12: counts + summary HTML dos comments das versions anteriores.
  -- Conta comments em document_versions com version_number < current AND locked_at IS NOT NULL
  -- (mesma janela usada por list_document_comments quando p_include_prior_versions=true).
  SELECT
    COUNT(*) FILTER (WHERE dc.resolved_at IS NOT NULL),
    COUNT(*) FILTER (WHERE dc.resolved_at IS NULL)
  INTO v_prior_resolved_count, v_prior_open_count
  FROM public.document_comments dc
  JOIN public.document_versions dv2 ON dv2.id = dc.document_version_id
  WHERE dv2.document_id = v_document.id
    AND dv2.locked_at IS NOT NULL
    AND dv2.version_number < v_current_version.version_number;

  -- Summary HTML — top 5 resolved + top 5 open (preview), with author + clause + body excerpt.
  -- Visibility: só curator_only/public — change_notes excluído (são notas do GP, não comments).
  IF v_prior_resolved_count + v_prior_open_count > 0 THEN
    SELECT
      '<details><summary style="cursor:pointer; font-weight:600;">' ||
      'Ver detalhe (' || (v_prior_resolved_count + v_prior_open_count)::text || ' comentário(s))' ||
      '</summary><ul style="font-size:12px; margin:8px 0; padding-left:20px;">' ||
      string_agg(
        '<li style="margin:6px 0;">' ||
        CASE WHEN dc.resolved_at IS NOT NULL
          THEN '<span style="color:#059669;">✓ endereçado</span>'
          ELSE '<span style="color:#dc2626;">⚠ ainda aberto</span>'
        END ||
        ' — <strong>' || COALESCE(m.name, '?') || '</strong>' ||
        CASE WHEN dc.clause_anchor IS NOT NULL
          THEN ' (§ ' || dc.clause_anchor || ')'
          ELSE ''
        END ||
        ': <em>"' ||
        replace(replace(LEFT(dc.body, 140), '<', '&lt;'), '>', '&gt;') ||
        CASE WHEN length(dc.body) > 140 THEN '…' ELSE '' END ||
        '"</em>' ||
        '</li>',
        ''
        ORDER BY dc.resolved_at IS NULL DESC, dc.created_at DESC
      ) ||
      '</ul></details>'
    INTO v_prior_summary_html
    FROM public.document_comments dc
    JOIN public.document_versions dv2 ON dv2.id = dc.document_version_id
    LEFT JOIN public.members m ON m.id = dc.author_id
    WHERE dv2.document_id = v_document.id
      AND dv2.locked_at IS NOT NULL
      AND dv2.version_number < v_current_version.version_number
      AND dc.visibility IN ('curator_only', 'public');
  ELSE
    v_prior_summary_html := '<p style="font-size:12px; color:#6b7280; font-style:italic;">(Sem comentários em versões anteriores.)</p>';
  END IF;

  IF p_dry_run THEN
    RETURN jsonb_build_object(
      'dry_run', true,
      'valid', true,
      'document', jsonb_build_object(
        'id', v_document.id,
        'title', v_document.title,
        'doc_type', v_document.doc_type
      ),
      'current_chain', jsonb_build_object(
        'id', v_chain.id,
        'status', v_chain.status,
        'version_id', v_chain.version_id,
        'version_label', v_current_version.version_label,
        'version_number', v_current_version.version_number,
        'opened_at', v_chain.opened_at
      ),
      'draft_version', jsonb_build_object(
        'id', v_draft.id,
        'version_number', v_draft.version_number,
        'version_label', v_draft.version_label,
        'notes_present', v_draft.notes IS NOT NULL,
        'notes_length', COALESCE(length(v_draft.notes), 0)
      ),
      'gates_to_copy', v_chain.gates,
      'first_gate_kind', v_first_gate_kind,
      'recipients', v_recipients,
      'recipient_count', v_recipient_count,
      'prior_comments_summary', jsonb_build_object(
        'resolved_count', v_prior_resolved_count,
        'open_count', v_prior_open_count
      ),
      'warnings', v_warnings,
      'next_step_summary', 'Execute with p_dry_run=false to: (1) supersede chain, (2) lock draft + create new chain via lock_document_version, (3) email recipients, (4) audit log.'
    );
  END IF;

  UPDATE public.approval_chains
    SET status = 'superseded',
        closed_at = now(),
        closed_by = v_member.id,
        notes = COALESCE(notes,'') || E'\n[recirculated at ' || now()::text ||
                ' by ' || v_member.name || ' — superseded by new draft v' || v_draft.version_label || ']',
        updated_at = now()
    WHERE id = p_chain_id;

  v_lock_result := public.lock_document_version(v_draft.id, v_chain.gates);
  IF NOT (v_lock_result->>'success')::boolean THEN
    RAISE EXCEPTION 'lock_document_version failed: %', v_lock_result::text USING ERRCODE = 'integrity_constraint_violation';
  END IF;
  v_new_chain_id := (v_lock_result->>'chain_id')::uuid;

  IF v_recipient_count > 0 THEN
    FOR v_send IN SELECT * FROM jsonb_to_recordset(v_recipients) AS x(
      email text, first_name text, member_id uuid, source text
    ) LOOP
      BEGIN
        v_send_result := public.campaign_send_one_off(
          'governance_recirculation_request',
          v_send.email,
          jsonb_build_object(
            'first_name', COALESCE(v_send.first_name, 'Curador'),
            'document_title', v_document.title,
            'version_label', v_draft.version_label,
            'new_chain_url', v_platform_url || '/admin/governance/documents/' || v_new_chain_id::text,
            'old_chain_url', v_platform_url || '/admin/governance/documents/' || p_chain_id::text,
            'changelog', v_changelog_html,
            'prior_resolved_count', v_prior_resolved_count::text,
            'prior_open_count', v_prior_open_count::text,
            'prior_addressed_summary', v_prior_summary_html,
            'platform_url', v_platform_url,
            'sender_name', v_member.name
          ),
          jsonb_build_object(
            'source', 'governance_recirculation',
            'document_id', v_document.id,
            'old_chain_id', p_chain_id,
            'new_chain_id', v_new_chain_id,
            'recipient_name', v_send.first_name
          )
        );
        v_send_results := v_send_results || jsonb_build_array(jsonb_build_object(
          'email', v_send.email,
          'send_id', v_send_result->>'send_id',
          'status', 'enqueued'
        ));
      EXCEPTION WHEN OTHERS THEN
        v_send_results := v_send_results || jsonb_build_array(jsonb_build_object(
          'email', v_send.email,
          'send_id', NULL,
          'status', 'failed',
          'error', SQLERRM
        ));
      END;
    END LOOP;
  END IF;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
  VALUES (
    v_member.id,
    'governance.recirculated',
    'governance_document',
    v_document.id,
    jsonb_build_object(
      'old_chain_id', p_chain_id,
      'new_chain_id', v_new_chain_id,
      'old_version', v_current_version.version_label,
      'new_version', v_draft.version_label,
      'recipients_count', v_recipient_count,
      'recipient_emails', (SELECT jsonb_agg(r->>'email') FROM jsonb_array_elements(v_recipients) r),
      'prior_resolved_count', v_prior_resolved_count,
      'prior_open_count', v_prior_open_count,
      'send_results', v_send_results
    ),
    jsonb_build_object(
      'doc_type', v_document.doc_type,
      'first_gate_kind', v_first_gate_kind,
      'sender_member_id', v_member.id
    )
  );

  RETURN jsonb_build_object(
    'dry_run', false,
    'success', true,
    'old_chain_id', p_chain_id,
    'new_chain_id', v_new_chain_id,
    'version_id_locked', v_draft.id,
    'document_id', v_document.id,
    'recipients_count', v_recipient_count,
    'prior_comments_summary', jsonb_build_object(
      'resolved_count', v_prior_resolved_count,
      'open_count', v_prior_open_count
    ),
    'send_results', v_send_results,
    'warnings', v_warnings
  );
END;
$function$;

COMMENT ON FUNCTION public.recirculate_governance_doc(uuid, boolean, text[]) IS
  'Re-circulação de documento governance pós-redraft. Lock draft pendente + supersede chain atual + cria chain nova com gates copiadas + notifica recipients via email parametrizado. Authority: manage_member (mesmo gate de lock_document_version). Default recipients = all members eligible to sign first gate of chain (via _can_sign_gate, ignora signoffs prévios — re-assinatura). Use p_dry_run=true para preview. Sediment p88 ADR-0068 Round 5 (#122). p130 T-12: email agora reporta counts de comments resolved/open das versions anteriores + summary HTML expansível.';

NOTIFY pgrst, 'reload schema';
