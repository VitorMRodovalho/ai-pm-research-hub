-- #2023 — o registro de entrega da via assinada do Termo.
--
-- Pre-requisito do parecer juridico (27/08): nada dispara antes disto. Hoje nao ha registro nem de
-- DOWNLOAD (`downloaded_at` nulo em 100% dos 168 certificados, e a coluna nunca e escrita), entao a
-- propria entrega nao teria como ser provada.
--
-- ── Por que dentro de `admin_audit_log`, e nao numa tabela nova ───────────────────────────────
-- O parecer pediu "log de auditoria, nao notificacao", pela retencao: a politica declara 5 anos ao
-- audit log administrativo e so 6 meses a notificacoes, e aqui o valor e probatorio. Usar a tabela
-- que ja carrega essa retencao evita criar uma segunda superficie com prazo proprio a declarar — a
-- politica acabou de ser ajustada (#2039) e nao precisa de mais uma linha.
-- Medido: `purge_expired_logs` apaga a LINHA INTEIRA aos 5 anos, entao o que estiver em `changes`
-- desaparece junto. E a contra-assinatura ja escreve nesta mesma tabela, entao o ato e a entrega
-- ficam lado a lado e uma consulta so reconstitui a cadeia.
--
-- ── Por que o endereco do voluntario NAO entra na linha ───────────────────────────────────────
-- A convencao da casa esta escrita no proprio codigo (`anonymize_premember_applications`):
-- "audit (NO PII in the audit row: ids, anchors, counts only)". Guardar o e-mail de um titular numa
-- tabela de 5 anos contrariaria isso.
--
-- A linha guarda entao: o id do membro (referencia, nao contato) e um HASH com sal do endereco. Isso
-- prova QUAL endereco foi usado — da para recalcular o hash de um candidato e comparar — sem
-- armazenar o contato. Sal, e nao sha256 cru, porque hash de e-mail sem sal e reversivel por
-- dicionario; mesmo padrao ja usado em `counter_sign_certificate`.
-- Endereco INSTITUCIONAL (caixa de papel) entra em claro: nao e dado pessoal.

CREATE OR REPLACE FUNCTION public.log_certificate_delivery(
  p_certificate_id     uuid,
  p_channel            text,                      -- 'email' | 'drive'
  p_recipient_kind     text,                      -- 'volunteer' | 'institutional'
  p_recipient_member_id uuid    DEFAULT NULL,     -- quando o destinatario e pessoa
  p_recipient_ref      text     DEFAULT NULL,     -- e-mail INSTITUCIONAL, ou id da pasta/arquivo
  p_recipient_secret   text     DEFAULT NULL,     -- endereco pessoal: vira HASH, nunca e gravado
  p_details            jsonb    DEFAULT '{}'::jsonb
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_cert   record;
  v_id     uuid;
  v_hash   text := NULL;
BEGIN
  IF p_channel NOT IN ('email','drive') THEN
    RAISE EXCEPTION 'canal invalido: % (esperado email|drive)', p_channel;
  END IF;
  IF p_recipient_kind NOT IN ('volunteer','institutional') THEN
    RAISE EXCEPTION 'tipo de destinatario invalido: %', p_recipient_kind;
  END IF;

  SELECT id, verification_code, type, counter_signed_at, content_snapshot
    INTO v_cert
  FROM public.certificates WHERE id = p_certificate_id;

  IF v_cert.id IS NULL THEN
    RAISE EXCEPTION 'certificado nao encontrado: %', p_certificate_id;
  END IF;

  -- O parecer condiciona a entrega ao artefato ja refletir AS DUAS assinaturas (#2022). Registrar
  -- entrega de documento incompleto seria registrar a coisa errada com aparencia de prova.
  IF v_cert.counter_signed_at IS NULL THEN
    RAISE EXCEPTION 'termo ainda sem contra-assinatura: entrega nao pode ser registrada (#2022)';
  END IF;

  IF p_recipient_secret IS NOT NULL AND length(trim(p_recipient_secret)) > 0 THEN
    v_hash := encode(sha256(convert_to(
      lower(trim(p_recipient_secret)) || 'nucleo-ia-delivery-salt', 'UTF8')), 'hex');
  END IF;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes)
  VALUES (
    NULL, 'certificate.delivered', 'certificate', p_certificate_id,
    jsonb_build_object(
      'channel',              p_channel,
      'recipient_kind',       p_recipient_kind,
      'recipient_member_id',  p_recipient_member_id,
      'recipient_ref',        p_recipient_ref,
      'recipient_hash',       v_hash,
      'verification_code',    v_cert.verification_code,
      'certificate_type',     v_cert.type,
      'template_version',     v_cert.content_snapshot->>'body_version_label',
      'delivered_at',         now()
    ) || COALESCE(p_details, '{}'::jsonb)
  )
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$function$;

COMMENT ON FUNCTION public.log_certificate_delivery(uuid,text,text,uuid,text,text,jsonb) IS
  '#2023 — registra a entrega da via assinada. Endereco pessoal entra como HASH com sal, nunca em '
  'claro: a convencao da casa e "no PII in the audit row". Recusa se o termo ainda nao tem '
  'contra-assinatura (#2022).';

REVOKE ALL ON FUNCTION public.log_certificate_delivery(uuid,text,text,uuid,text,text,jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.log_certificate_delivery(uuid,text,text,uuid,text,text,jsonb) TO service_role;

-- ─────────────────────────────────────────────────────────────────────────────────────────────
-- Leitura: o que ja foi entregue deste certificado, e por onde.
-- Gate: quem administra membro, ou o PROPRIO titular. Sem isto, a existencia da entrega seria
-- legivel por qualquer autenticado.
-- ─────────────────────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.get_certificate_delivery_log(p_certificate_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller uuid;
  v_owner  uuid;
BEGIN
  SELECT id INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller IS NULL THEN
    RETURN jsonb_build_object('error', 'not_authenticated');
  END IF;

  SELECT member_id INTO v_owner FROM public.certificates WHERE id = p_certificate_id;
  IF v_owner IS NULL THEN
    RETURN jsonb_build_object('error', 'not_found');
  END IF;

  IF v_owner IS DISTINCT FROM v_caller
     AND NOT public.can_by_member(v_caller, 'manage_member'::text) THEN
    RETURN jsonb_build_object('error', 'not_authorized');
  END IF;

  RETURN jsonb_build_object(
    'certificate_id', p_certificate_id,
    'deliveries', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'at',             l.created_at,
        'channel',        l.changes->>'channel',
        'recipient_kind', l.changes->>'recipient_kind',
        'recipient_ref',  l.changes->>'recipient_ref',
        'provider_ref',   COALESCE(l.changes->>'message_id', l.changes->>'drive_file_id'),
        'content_hash',   l.changes->>'content_hash'
      ) ORDER BY l.created_at)
      FROM public.admin_audit_log l
      WHERE l.action = 'certificate.delivered' AND l.target_id = p_certificate_id
    ), '[]'::jsonb),
    -- o hash do destinatario NAO sai na leitura: ele existe para CONFERIR um endereco candidato,
    -- nao para ser distribuido. Quem precisa conferir recalcula e compara no banco.
    'delivered_count', (
      SELECT count(*) FROM public.admin_audit_log l
      WHERE l.action = 'certificate.delivered' AND l.target_id = p_certificate_id)
  );
END;
$function$;

COMMENT ON FUNCTION public.get_certificate_delivery_log(uuid) IS
  '#2023 — o que ja foi entregue deste certificado. Gate: manage_member ou o proprio titular. '
  'Nao devolve o hash do destinatario: ele serve para CONFERIR, nao para distribuir.';

REVOKE ALL ON FUNCTION public.get_certificate_delivery_log(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_certificate_delivery_log(uuid) TO authenticated, service_role;

NOTIFY pgrst, 'reload schema';
