-- #2022 — contra-assinar INVALIDA o PDF congelado, para o arquivo parar de dizer "pendente".
--
-- O caminho de download serve o artefato congelado (`pdf_url`) primeiro e so reconstroi quando ele
-- nao existe. Como a contra-assinatura nao mexia em `pdf_url`, o PDF servido continuava sendo o que
-- foi renderizado ANTES dela — dizendo "Pendente contra-assinatura" num documento ja assinado.
-- Medido em 27/08/2026: 47 de 85 termos contra-assinados exibiam "pendente".
--
-- O conserto e uma linha na UPDATE. O que exigiu medicao foi a SEGURANCA dela: perder o congelado
-- so e aceitavel se a reconstrucao sempre achar o texto acordado, porque o guard do #648 recusa
-- renderizar um termo em branco — e um termo sem fonte ficaria sem PDF NENHUM.
-- Medido em 27/08 sobre os 94 termos: 94 com `content_snapshot->'clauses'->>'clause1'`, 53 com
-- `html_body`, 94 com template vivo, e **0 sem nenhuma fonte**.
--
-- Essa invariante e afirmada por contract test, NAO reimplementada aqui: um segundo predicado de
-- "e reconstruivel?" em SQL poderia divergir do guard em TypeScript, e a divergencia so apareceria
-- no dia em que alguem perdesse o documento.
--
-- O caminho em LOTE (`bulk_counter_sign_certificates`) delega para esta RPC num laco, entao herda
-- o conserto, o portao de autoridade, o hash, a auditoria e a notificacao. Conferido no corpo vivo.

CREATE OR REPLACE FUNCTION public.counter_sign_certificate(p_certificate_id uuid, p_signed_ip text DEFAULT NULL::text, p_signed_user_agent text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_caller_id uuid;
  v_caller_chapter text;
  v_caller_person_id uuid;
  v_is_manage_member boolean;
  v_is_chapter_board boolean;
  v_cert record;
  v_contracting_chapter text;
  v_hash text;
  v_signed_at timestamptz := now();
  v_ip inet := NULL;
BEGIN
  p_signed_user_agent := left(p_signed_user_agent, 500);

  SELECT m.id, m.chapter, m.person_id
    INTO v_caller_id, v_caller_chapter, v_caller_person_id
  FROM public.members m WHERE m.auth_id = auth.uid();

  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('error', 'not_authenticated');
  END IF;

  v_is_manage_member := public.can_by_member(v_caller_id, 'manage_member');
  v_is_chapter_board := EXISTS (
    SELECT 1 FROM public.auth_engagements ae
    WHERE ae.person_id = v_caller_person_id
      AND ae.kind = 'chapter_board'
      AND ae.status = 'active'
  );

  IF NOT v_is_manage_member AND NOT v_is_chapter_board THEN
    RETURN jsonb_build_object('error', 'not_authorized');
  END IF;

  SELECT * INTO v_cert FROM public.certificates WHERE id = p_certificate_id;
  IF v_cert IS NULL THEN RETURN jsonb_build_object('error', 'not_found'); END IF;
  -- 3c-i: only a valid (issued) term is counter-signable; rejected/superseded/revoked/draft are not.
  IF v_cert.status IS DISTINCT FROM 'issued' THEN
    RETURN jsonb_build_object('error', 'not_signable', 'status', v_cert.status);
  END IF;
  IF v_cert.counter_signed_by IS NOT NULL THEN
    RETURN jsonb_build_object('error', 'already_counter_signed');
  END IF;

  -- 3c-i (security review): the contracting party is ALWAYS the contracting chapter (PMI-GO, C3).
  -- When a legacy term's snapshot omits contracting_chapter, fall back to the registry contracting
  -- chapter — NOT the target member's chapter (which would let a board of the member's own chapter
  -- counter-sign/reject a term whose real contracting party is PMI-GO).
  v_contracting_chapter := COALESCE(
    v_cert.content_snapshot->>'contracting_chapter',
    (SELECT 'PMI-' || cr.chapter_code FROM public.chapter_registry cr
      WHERE cr.is_contracting_chapter AND cr.is_active LIMIT 1)
  );

  IF v_is_chapter_board AND NOT v_is_manage_member THEN
    IF v_contracting_chapter IS DISTINCT FROM v_caller_chapter THEN
      RETURN jsonb_build_object('error', 'not_authorized_different_chapter');
    END IF;
  END IF;

  -- 3c-i bugfix: convert_to/sha256 live in pg_catalog, not public. The prior body called
  -- public.convert_to/public.sha256 under SET search_path TO '' → unresolvable, so EVERY
  -- counter-sign raised "function public.convert_to does not exist". Unqualified names resolve
  -- via pg_catalog (always in the implicit path). The 33 counter-signed certs in prod came from
  -- bulk paths, not this RPC (only 1 counter_sign audit event existed). #740 Wave 3c-i.
  v_hash := encode(sha256(convert_to(
    COALESCE(v_cert.signature_hash,'') || v_caller_id::text || v_signed_at::text || 'nucleo-ia-countersign-salt', 'UTF8'
  )), 'hex');

  BEGIN
    IF p_signed_ip IS NOT NULL AND length(trim(p_signed_ip)) > 0 THEN
      v_ip := p_signed_ip::inet;
    END IF;
  EXCEPTION WHEN OTHERS THEN
    v_ip := NULL;
  END;

  -- #2022: o PDF congelado foi renderizado ANTES desta assinatura, entao ele diz "Pendente
  -- contra-assinatura" — e o caminho de download serve o congelado primeiro, sem nunca reconstruir.
  -- Medido em 27/08/2026: 47 de 85 termos contra-assinados exibiam "pendente" depois de assinados.
  -- Limpar `pdf_url` devolve o artefato ao caminho de reconstrucao, que le o estado vivo.
  --
  -- Isto so e seguro porque TODO termo e reconstruivel: o guard do #648 recusa renderizar sem o
  -- texto acordado, e um termo sem fonte ficaria SEM PDF nenhum ao perder o congelado. Medido em
  -- 27/08: 94 de 94 termos tem `content_snapshot->'clauses'->>'clause1'`, 0 sem nenhuma fonte.
  -- Essa invariante e afirmada por contract test, em vez de reimplementada aqui como um segundo
  -- predicado que pode divergir do guard em TypeScript.
  UPDATE public.certificates
  SET counter_signed_by = v_caller_id,
      counter_signed_at = v_signed_at,
      counter_signature_hash = v_hash,
      pdf_url = NULL
  WHERE id = p_certificate_id;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes)
  VALUES (v_caller_id, 'certificate_counter_signed', 'certificate', p_certificate_id,
    jsonb_build_object(
      'verification_code', v_cert.verification_code,
      'type', v_cert.type,
      'contracting_chapter', v_contracting_chapter,
      'counter_signature_hash', v_hash,
      'counter_signed_at', v_signed_at,
      'counter_signer_ip', v_ip::text,
      'counter_signer_user_agent', p_signed_user_agent,
      -- #2022: registra que o congelado foi invalidado, para o log dizer POR QUE o arquivo mudou.
      'frozen_pdf_invalidated', (v_cert.pdf_url IS NOT NULL)
    ));

  INSERT INTO public.notifications (recipient_id, type, title, body, link, source_type, source_id, delivery_mode)
  VALUES (v_cert.member_id, 'certificate_ready',
    'Seu ' || v_cert.title || ' esta pronto!',
    'O documento foi contra-assinado e esta disponivel. Codigo: ' || v_cert.verification_code,
    '/certificates', 'certificate', p_certificate_id,
    public._delivery_mode_for('certificate_ready'));

  RETURN jsonb_build_object(
    'success', true,
    'counter_signature_hash', v_hash,
    'counter_signed_at', v_signed_at,
    'frozen_pdf_invalidated', (v_cert.pdf_url IS NOT NULL)
  );
END;
$function$;

NOTIFY pgrst, 'reload schema';
