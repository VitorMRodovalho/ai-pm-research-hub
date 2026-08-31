-- #2104 itens 1 e 2: o Termo de Adesao ao Servico Voluntario passa a ser contra-assinado pela
-- diretoria de voluntarios do capitulo contratante, com escalada explicita a presidencia e veto
-- de auto-contra-assinatura.
--
-- Regra do PM (30/08/2026): o Termo e contra-assinado pela diretoria de voluntarios do capitulo
-- sede; a presidencia entra SO quando precisa escalar.
--
-- MEDIDO EM PRODUCAO IMEDIATAMENTE ANTES DE APLICAR (31/08/2026):
--   portao de entao .................. 9 pessoas (2 por manage_member + 7 por board do contratante)
--   diretoria de voluntarios ......... 1 titular, do capitulo contratante
--   presidencia do contratante ....... 1 (chapter_board + legal_signer)
--   perdem acesso ao Termo ........... 7
--   corpo anterior ................... 5461 chars, md5 4c5c5de38ae092e5a568f7ff71e5e760
--
-- ESCOPO POR TIPO, E ELE E O PONTO CRITICO DESTA MIGRATION.
-- `counter_sign_certificate` contra-assina CINCO tipos e nao filtrava por nenhum:
--   volunteer_agreement 96 | participation 46 | excellence 14 | alumni_recognition 11 | contribution 4
-- Sao 96 Termos contra 75 certificados de outros tipos. Estreitar sem escopo tiraria a
-- contra-assinatura desses 75, que nada tem com o Termo. Por isso o portao novo mora dentro de
-- `IF v_cert.type = 'volunteer_agreement'`, e o ramo ELSE preserva o comportamento anterior para
-- os outros quatro tipos.
--
-- DERIVACAO, NAO LITERAL. O capitulo contratante e resolvido por
-- `chapter_registry.is_contracting_chapter`, mesma forma que a #2104 ja aplicou em `_can_sign_gate`
-- e que o `cert_director_go` (ADR-0016 Amendment 4) usa. Nenhum codigo de capitulo entra no codigo.
--
-- Refs #2104, #2094, #632.

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
  v_caller_designations text[];
  v_is_manage_member boolean;
  v_is_chapter_board boolean;
  v_caller_is_contracting boolean;
  v_is_vol_director boolean;
  v_is_president boolean;
  v_holder_is_director boolean;
  v_director_vacant boolean;
  v_route text;
  v_cert record;
  v_contracting_chapter text;
  v_hash text;
  v_signed_at timestamptz := now();
  v_ip inet := NULL;
BEGIN
  p_signed_user_agent := left(p_signed_user_agent, 500);

  SELECT m.id, m.chapter, m.person_id, COALESCE(m.designations, ARRAY[]::text[])
    INTO v_caller_id, v_caller_chapter, v_caller_person_id, v_caller_designations
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

  -- #2104: a diretoria de voluntarios entra no portao GROSSO para o portao nao depender de ela
  -- ter, por acidente, engajamento de board. O titular de hoje tem; um sucessor pode nao ter.
  -- O ramo ELSE abaixo RE-NEGA para os outros tipos, entao isto nao amplia autoridade sobre nada
  -- alem do Termo.
  v_is_vol_director := 'voluntariado_director' = ANY(v_caller_designations);

  IF NOT v_is_manage_member AND NOT v_is_chapter_board AND NOT v_is_vol_director THEN
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

  -- 3c-i (security review): the contracting party is ALWAYS the contracting chapter.
  -- When a legacy term's snapshot omits contracting_chapter, fall back to the registry contracting
  -- chapter — NOT the target member's chapter (which would let a board of the member's own chapter
  -- counter-sign/reject a term whose real contracting party is the contracting chapter).
  v_contracting_chapter := COALESCE(
    v_cert.content_snapshot->>'contracting_chapter',
    (SELECT 'PMI-' || cr.chapter_code FROM public.chapter_registry cr
      WHERE cr.is_contracting_chapter AND cr.is_active LIMIT 1)
  );

  IF v_cert.type = 'volunteer_agreement' THEN
    -- ============ #2104 item 2: veto de auto-contra-assinatura ============
    -- Medido antes desta migration: ZERO checagens `caller = member` no corpo, entao a mesma
    -- pessoa podia ocupar os dois polos do instrumento. Vem ANTES da escolha de rota de proposito:
    -- se viesse depois, a presidencia escaparia dele pela via de escalada.
    IF v_cert.member_id = v_caller_id THEN
      RETURN jsonb_build_object('error', 'cannot_counter_sign_own_term');
    END IF;

    v_caller_is_contracting := EXISTS (
      SELECT 1 FROM public.partner_chapters pc
      JOIN public.chapter_registry cr ON cr.chapter_code = pc.registry_chapter_code
      WHERE pc.chapter_code = v_caller_chapter
        AND cr.is_contracting_chapter);

    -- ============ #2104 item 1: via ordinaria ============
    v_is_vol_director := v_caller_is_contracting
      AND 'voluntariado_director' = ANY(v_caller_designations);

    -- ============ #2104 item 2: escalada ============
    -- A presidencia do capitulo contratante, com o MESMO predicado que `_can_sign_gate` usa em
    -- `president_go`: chapter_board + legal_signer no contratante.
    v_is_president := v_caller_is_contracting
      AND 'chapter_board' = ANY(v_caller_designations)
      AND 'legal_signer'  = ANY(v_caller_designations);

    -- (a) o caso nomeado pelo PM: o Termo e da propria diretoria de voluntarios.
    v_holder_is_director := EXISTS (
      SELECT 1 FROM public.members m2
      JOIN public.partner_chapters pc ON pc.chapter_code = m2.chapter
      JOIN public.chapter_registry cr ON cr.chapter_code = pc.registry_chapter_code
      WHERE m2.id = v_cert.member_id
        AND cr.is_contracting_chapter
        AND 'voluntariado_director' = ANY(COALESCE(m2.designations, ARRAY[]::text[])));

    -- (b) vacancia: sem titular ativo a via ordinaria fica vazia e a fila travaria inteira.
    -- Com 1 titular, a vacancia e um evento de UMA saida.
    v_director_vacant := NOT EXISTS (
      SELECT 1 FROM public.members m3
      JOIN public.partner_chapters pc ON pc.chapter_code = m3.chapter
      JOIN public.chapter_registry cr ON cr.chapter_code = pc.registry_chapter_code
      WHERE m3.is_active
        AND cr.is_contracting_chapter
        AND 'voluntariado_director' = ANY(COALESCE(m3.designations, ARRAY[]::text[])));

    IF v_is_vol_director THEN
      v_route := 'volunteer_director';
    ELSIF v_is_president AND (v_holder_is_director OR v_director_vacant) THEN
      v_route := CASE WHEN v_holder_is_director THEN 'president_escalation_holder_is_director'
                      ELSE 'president_escalation_vacancy' END;
    ELSE
      -- manage_member NAO e via de contra-assinatura do Termo (decisao do PM, 30/08). Ele segue
      -- fazendo toda a administracao de plataforma; so deixou de firmar ESTE instrumento.
      RETURN jsonb_build_object('error', 'not_authorized_term_requires_volunteer_director');
    END IF;
  ELSE
    -- Os outros quatro tipos seguem com o portao ANTERIOR, sem alteracao de comportamento.
    -- O RE-NEGA existe porque a diretoria de voluntarios passou a atravessar o portao grosso
    -- acima: sem esta linha, ela ganharia autoridade sobre certificados que nao sao o Termo.
    IF NOT v_is_manage_member AND NOT v_is_chapter_board THEN
      RETURN jsonb_build_object('error', 'not_authorized');
    END IF;
    IF v_is_chapter_board AND NOT v_is_manage_member THEN
      IF v_contracting_chapter IS DISTINCT FROM v_caller_chapter THEN
        RETURN jsonb_build_object('error', 'not_authorized_different_chapter');
      END IF;
    END IF;
    v_route := 'standard';
  END IF;

  -- 3c-i bugfix: convert_to/sha256 live in pg_catalog, not public. The prior body called
  -- public.convert_to/public.sha256 under SET search_path TO '' → unresolvable, so EVERY
  -- counter-sign raised "function public.convert_to does not exist". Unqualified names resolve
  -- via pg_catalog (always in the implicit path). #740 Wave 3c-i.
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
  -- Limpar `pdf_url` devolve o artefato ao caminho de reconstrucao, que le o estado vivo.
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
      -- #2104: QUAL rota autorizou. Sem isto a escalada e indistinguivel da via ordinaria no log,
      -- e a escalada e justamente o caso que alguem vai querer auditar depois.
      'authority_route', v_route,
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
    'authority_route', v_route,
    'frozen_pdf_invalidated', (v_cert.pdf_url IS NOT NULL)
  );
END;
$function$;

-- ============ POS-CONDICAO DA ASSINATURA ============
-- Aprendido em 30/08 nesta mesma issue: `CREATE OR REPLACE` reconstroi a funcao a partir do que se
-- DECLARA, e atributo omitido volta ao default em silencio. Naquele dia `STABLE` virou `VOLATILE`
-- num corpo protegido por seis assercoes, todas sobre o CORPO. A assinatura tem de ser afirmada.
--
-- ⚠️ Os dois literais abaixo foram MEDIDOS no catalogo, nao supostos. A primeira tentativa desta
-- migration ABORTOU porque eu escrevi `search_path=` (o valor real e `search_path=""`, com aspas)
-- e `'uuid, text, text'` (o real inclui os NOMES dos parametros). Nada foi aplicado: o erro foi meu,
-- e a pos-condicao estrita e o que o revelou em vez de deixar passar.
DO $$
BEGIN
  PERFORM 1 FROM pg_proc p
   WHERE p.proname = 'counter_sign_certificate'
     AND p.pronamespace = 'public'::regnamespace
     AND p.prosecdef
     AND p.provolatile = 'v'
     AND p.proconfig @> ARRAY['search_path=""']
     AND pg_get_function_identity_arguments(p.oid)
         = 'p_certificate_id uuid, p_signed_ip text, p_signed_user_agent text';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'pos-condicao da ASSINATURA falhou: counter_sign_certificate perdeu atributo';
  END IF;

  PERFORM 1 FROM pg_proc p
   WHERE p.proname = 'counter_sign_certificate'
     AND p.pronamespace = 'public'::regnamespace
     AND p.pronargdefaults = 2;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'pos-condicao falhou: os 2 defaults de parametro nao sobreviveram';
  END IF;
END $$;
