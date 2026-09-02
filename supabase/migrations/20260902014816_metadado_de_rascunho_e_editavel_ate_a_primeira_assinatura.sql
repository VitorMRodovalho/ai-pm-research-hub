-- WHAT: cria update_governance_document_meta(uuid, text, text) e corrige title/description do TAP
-- WHY:  governance_documents e read-only para `authenticated` (gd_deny_insert/update/delete USING(false))
--       e NENHUMA das 18 funcoes *document* escreve title ou description. Consequencia medida em
--       2026-09-02: um documento em `status='draft'`, com signed_at/approved_at/valid_from/pdf_url/
--       docusign_envelope_id/first_ratified_at TODOS nulos, ZERO assinaturas e ZERO cadeias ativas,
--       tem o nome congelado como se ja tivesse sido assinado. A imutabilidade existe para proteger a
--       integridade do que alguem assinou; antes da primeira assinatura ela nao protege nada, so
--       impede correcao. Decisao do dono 2026-09-02: a imutabilidade segue o CICLO DE VIDA.
-- SCOPE LOCK: a regra mora na RPC. A tabela CONTINUA negando insert/update/delete a `authenticated`;
--       este patch NAO afrouxa nenhuma policy de RLS.
-- ROLLBACK: DROP FUNCTION public.update_governance_document_meta(uuid, text, text);
--       (a correcao de dados abaixo e retroativa e nao se desfaz automaticamente)
-- INVARIANTS: congela quando status<>'draft' OU ha assinatura OU ha cadeia ativa OU ha ratificacao.
-- CROSS-REF: #2126 (o editor destroi tabelas) · CR de ciclo de vida do TAP (nao submetido)

CREATE OR REPLACE FUNCTION public.update_governance_document_meta(
  p_document_id uuid,
  p_title       text DEFAULT NULL,
  p_description text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_caller_id      uuid;
  v_doc            record;
  v_assinaturas    int;
  v_cadeias_ativas int;
BEGIN
  SELECT m.id INTO v_caller_id
  FROM public.members m WHERE m.auth_id = auth.uid();

  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('error', 'authentication_required');
  END IF;

  IF NOT public.can_by_member(v_caller_id, 'manage_member') THEN
    RETURN jsonb_build_object('error', 'Unauthorized: requires manage_member');
  END IF;

  SELECT * INTO v_doc FROM public.governance_documents WHERE id = p_document_id;
  IF v_doc IS NULL THEN
    RETURN jsonb_build_object('error', 'Document not found');
  END IF;

  IF p_title IS NULL AND p_description IS NULL THEN
    RETURN jsonb_build_object('error', 'nothing_to_update');
  END IF;

  SELECT count(*) INTO v_assinaturas
  FROM public.member_document_signatures s WHERE s.document_id = p_document_id;

  SELECT count(*) INTO v_cadeias_ativas
  FROM public.approval_chains ac
  WHERE ac.document_id = p_document_id AND ac.status = 'active';

  -- A REGRA: metadado de rascunho e editavel; a partir da primeira assinatura, congela.
  IF v_doc.status <> 'draft'
     OR v_assinaturas > 0
     OR v_cadeias_ativas > 0
     OR v_doc.first_ratified_at IS NOT NULL
     OR v_doc.signed_at IS NOT NULL THEN
    RETURN jsonb_build_object(
      'error', 'frozen: document metadata is immutable once signed or out of draft',
      'status', v_doc.status,
      'signatures', v_assinaturas,
      'active_chains', v_cadeias_ativas,
      'first_ratified_at', v_doc.first_ratified_at
    );
  END IF;

  UPDATE public.governance_documents SET
    title       = COALESCE(p_title, title),
    description = COALESCE(p_description, description),
    updated_at  = now()
  WHERE id = p_document_id;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes)
  VALUES (v_caller_id, 'governance_document_meta_change', 'governance_document', p_document_id,
    jsonb_build_object(
      'from', jsonb_build_object('title', v_doc.title, 'description', v_doc.description),
      'to',   jsonb_build_object('title', COALESCE(p_title, v_doc.title),
                                 'description', COALESCE(p_description, v_doc.description))));

  RETURN jsonb_build_object('ok', true, 'document_id', p_document_id,
    'title', COALESCE(p_title, v_doc.title));
END;
$function$;

-- CREATE FUNCTION nasce com EXECUTE para PUBLIC (logo, anon). Fechar.
REVOKE ALL ON FUNCTION public.update_governance_document_meta(uuid, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.update_governance_document_meta(uuid, text, text) TO authenticated, service_role;

COMMENT ON FUNCTION public.update_governance_document_meta(uuid, text, text) IS
  'Edita title/description de documento de governanca ENQUANTO ele e rascunho nao assinado. Congela a partir da primeira assinatura, de cadeia ativa, de ratificacao ou de status<>draft. Gate: manage_member. Escreve admin_audit_log. A tabela segue read-only via RLS; esta e a unica porta.';

-- Correcao retroativa dos dois valores que ficaram errados por nao existir caminho quando foram
-- definidos. "Prep Course" foi vetado pela Diretoria de Certificacao (regra de ATP) e a numeracao de
-- ciclo saiu do nome porque e interna ao Nucleo e o projeto atravessa mais de um ciclo. O "R00" da
-- description referenciava o template, e no espaco de numeracao vigente R00 nomeia a primeira versao
-- APROVADA, que este documento ainda nao tem. O campo `version` NAO e tocado: ele nomeia o alvo.
UPDATE public.governance_documents
SET title = 'TAP - Grupo de Estudos CPMAI · Piloto · PMI-GO',
    description = 'Termo de Abertura do Projeto (template do PMO-GO). Iniciativa do Núcleo IA & GP sediada pelo PMI-GO; inter-capítulos com meta de 8 de 15 capítulos PMI Brasil. Render fiel ao template do PMO-GO + Anexos A/B/C.',
    updated_at = now()
WHERE title = 'TAP — Grupo de Estudos CPMAI Prep Course · Ciclo 4 (2026)'
  AND status = 'draft';
