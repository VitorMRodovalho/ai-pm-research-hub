-- #2806, fatia A (banco): inscrição de push web por aparelho, com RLS e dentro do ciclo do art. 18.
--
-- Primeiro dos dois veículos de deploy: este pacote sai antes da PR do site (manifest, service worker e o botão de
-- ativar o push). O envio (Edge Function com a chave VAPID em segredo) vem depois e lê esta tabela com service_role.
--
-- Decisões do GP (27/10/2026), registradas na #2806:
--   * o site fica instalável em https://nucleoia.org, e só lá a inscrição é aceita (platform_settings, não literal);
--   * vão por push só os avisos que o catálogo já marca como imediatos (delivery_mode = 'transactional_immediate').
--
-- (1) push_subscriptions: uma linha por aparelho. RLS ligado, nada para anon, e o membro autenticado lê só as
--     próprias. Escrita só pelas duas funções abaixo. O endpoint é único: se outra pessoa entrar no mesmo navegador,
--     a inscrição passa para quem está logado agora.
-- (2) register_push_subscription / unregister_push_subscription / list_my_push_subscriptions. A origem aceita é a do
--     cabeçalho Origin que o PostgREST expõe em request.headers, e o parâmetro precisa bater com ela. A lista não
--     devolve endpoint nem chaves.
-- (3) notifications.push_dispatched_at: a marca de "já tentei o push desta notificação", para o envio ser idempotente.
--     As notificações imediatas que já existem nascem marcadas: são anteriores ao push e nunca vão por ele.
-- (4) Art. 18: a inscrição sai quando o membro é anonimizado ou desativado (gatilho em members), sai na autoexclusão
--     (delete_my_personal_data, que NÃO marca anonymized_at e por isso não é coberta pelo gatilho) e entra na
--     exportação (export_my_data) sem as chaves: endpoint mais chaves é uma credencial de envio, e a exportação não
--     deve criar uma.
--
-- Rollback: DROP TRIGGER trg_push_subscriptions_purge ON public.members; DROP FUNCTION
--   public._push_subscriptions_purge(), public.register_push_subscription(text,text,text,text,text),
--   public.unregister_push_subscription(text), public.list_my_push_subscriptions(); DROP TABLE
--   public.push_subscriptions; ALTER TABLE public.notifications DROP COLUMN push_dispatched_at; DELETE das duas chaves
--   de platform_settings; reaplicar as capturas anteriores de export_my_data (20260808000100) e
--   delete_my_personal_data (20260514520000).

-- ── (1) tabela ────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.push_subscriptions (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  member_id       uuid NOT NULL REFERENCES public.members(id) ON DELETE CASCADE,
  endpoint        text NOT NULL UNIQUE CHECK (endpoint ~ '^https://' AND length(endpoint) <= 2048),
  p256dh          text NOT NULL CHECK (length(p256dh) BETWEEN 1 AND 256),
  auth_secret     text NOT NULL CHECK (length(auth_secret) BETWEEN 1 AND 64),
  origin          text NOT NULL CHECK (origin ~ '^https://[a-z0-9.-]+$'),
  user_agent      text CHECK (user_agent IS NULL OR length(user_agent) <= 512),
  created_at      timestamptz NOT NULL DEFAULT now(),
  last_success_at timestamptz,
  failure_count   integer NOT NULL DEFAULT 0 CHECK (failure_count >= 0),
  disabled_at     timestamptz
);
CREATE INDEX IF NOT EXISTS idx_push_subscriptions_member_active
  ON public.push_subscriptions (member_id) WHERE disabled_at IS NULL;

ALTER TABLE public.push_subscriptions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.push_subscriptions FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.push_subscriptions TO authenticated;
DROP POLICY IF EXISTS push_subscriptions_select_own ON public.push_subscriptions;
CREATE POLICY push_subscriptions_select_own ON public.push_subscriptions
  FOR SELECT TO authenticated
  USING (member_id IN (SELECT m.id FROM public.members m WHERE m.auth_id = auth.uid()));
COMMENT ON TABLE public.push_subscriptions IS
  '#2806: inscrição de push web por aparelho. Dado pessoal: exportada sem as chaves (export_my_data), apagada na autoexclusão (delete_my_personal_data) e na anonimização ou desativação do membro (trg_push_subscriptions_purge).';

INSERT INTO public.platform_settings (key, value, description) VALUES
  ('push_allowed_origins', '["https://nucleoia.org"]'::jsonb,
   '#2806: origens em que o site aceita inscrição de push (o app fica instalável só nelas).'),
  ('push_max_subscriptions_per_member', to_jsonb(10),
   '#2806: quantos aparelhos ativos um membro pode inscrever no push.')
ON CONFLICT (key) DO NOTHING;

-- ── (2) funções do membro ─────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.register_push_subscription(
  p_endpoint text, p_p256dh text, p_auth text, p_origin text, p_user_agent text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_member_id uuid;
  v_allowed jsonb;
  v_hdr_origin text;
  v_limit integer;
  v_active integer;
  v_id uuid;
BEGIN
  SELECT m.id INTO v_member_id FROM public.members m WHERE m.auth_id = auth.uid() AND m.is_active = true;
  IF v_member_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- A origem que vale é a do cabeçalho que o navegador manda ao PostgREST, não o parâmetro, que vem do cliente.
  -- O parâmetro precisa bater com ela; sem cabeçalho (chamada fora do navegador), recusa.
  v_hdr_origin := current_setting('request.headers', true)::json ->> 'origin';
  SELECT ps.value INTO v_allowed FROM public.platform_settings ps WHERE ps.key = 'push_allowed_origins';
  IF v_hdr_origin IS NULL OR v_allowed IS NULL OR NOT (v_allowed ? v_hdr_origin) OR p_origin IS DISTINCT FROM v_hdr_origin THEN
    RAISE EXCEPTION 'Origin not allowed for push: %', COALESCE(v_hdr_origin, '(none)') USING ERRCODE = 'check_violation';
  END IF;

  SELECT COALESCE((ps.value #>> '{}')::integer, 10) INTO v_limit
  FROM public.platform_settings ps WHERE ps.key = 'push_max_subscriptions_per_member';
  SELECT count(*) INTO v_active FROM public.push_subscriptions s
  WHERE s.member_id = v_member_id AND s.disabled_at IS NULL AND s.endpoint IS DISTINCT FROM p_endpoint;
  IF v_active >= COALESCE(v_limit, 10) THEN
    RAISE EXCEPTION 'Device limit of % reached', COALESCE(v_limit, 10) USING ERRCODE = 'check_violation';
  END IF;

  INSERT INTO public.push_subscriptions AS s (member_id, endpoint, p256dh, auth_secret, origin, user_agent)
  VALUES (v_member_id, p_endpoint, p_p256dh, p_auth, v_hdr_origin, left(p_user_agent, 512))
  ON CONFLICT (endpoint) DO UPDATE
    SET member_id = EXCLUDED.member_id, p256dh = EXCLUDED.p256dh, auth_secret = EXCLUDED.auth_secret,
        origin = EXCLUDED.origin, user_agent = EXCLUDED.user_agent,
        failure_count = 0, disabled_at = NULL
  RETURNING s.id INTO v_id;

  RETURN jsonb_build_object('ok', true, 'subscription_id', v_id);
END;
$function$;

CREATE OR REPLACE FUNCTION public.unregister_push_subscription(p_endpoint text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_member_id uuid;
  v_deleted integer;
BEGIN
  SELECT m.id INTO v_member_id FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_member_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = 'insufficient_privilege';
  END IF;

  DELETE FROM public.push_subscriptions s WHERE s.endpoint = p_endpoint AND s.member_id = v_member_id;
  GET DIAGNOSTICS v_deleted = ROW_COUNT;

  RETURN jsonb_build_object('ok', true, 'deleted', v_deleted);
END;
$function$;

CREATE OR REPLACE FUNCTION public.list_my_push_subscriptions()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_member_id uuid;
BEGIN
  SELECT m.id INTO v_member_id FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_member_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = 'insufficient_privilege';
  END IF;

  RETURN COALESCE((
    SELECT jsonb_agg(jsonb_build_object(
      'id', s.id, 'origin', s.origin, 'user_agent', s.user_agent, 'created_at', s.created_at,
      'last_success_at', s.last_success_at, 'disabled_at', s.disabled_at
    ) ORDER BY s.created_at DESC)
    FROM public.push_subscriptions s WHERE s.member_id = v_member_id
  ), '[]'::jsonb);
END;
$function$;

REVOKE ALL ON FUNCTION public.register_push_subscription(text, text, text, text, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.unregister_push_subscription(text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.list_my_push_subscriptions() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.register_push_subscription(text, text, text, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.unregister_push_subscription(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_my_push_subscriptions() TO authenticated;

-- ── (3) idempotência do envio ─────────────────────────────────────────────────
ALTER TABLE public.notifications ADD COLUMN IF NOT EXISTS push_dispatched_at timestamptz;
-- Estoque: toda notificação imediata que já existe é ANTERIOR ao push e nunca vai por push. Sem esta marca, o envio
-- veria o estoque inteiro como pendente, e quem ativasse o push receberia avisos antigos. Também mantém o índice
-- parcial abaixo pequeno. A Edge Function tem a segunda defesa: nunca envia notificação criada antes da inscrição.
UPDATE public.notifications SET push_dispatched_at = created_at
WHERE delivery_mode = 'transactional_immediate' AND push_dispatched_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_notifications_push_pending
  ON public.notifications (created_at)
  WHERE delivery_mode = 'transactional_immediate' AND push_dispatched_at IS NULL;

-- ── (4) art. 18: anonimização e desativação ───────────────────────────────────
CREATE OR REPLACE FUNCTION public._push_subscriptions_purge()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  DELETE FROM public.push_subscriptions WHERE member_id = NEW.id;
  RETURN NEW;
END;
$function$;
REVOKE ALL ON FUNCTION public._push_subscriptions_purge() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_push_subscriptions_purge ON public.members;
CREATE TRIGGER trg_push_subscriptions_purge
  AFTER UPDATE OF anonymized_at, is_active ON public.members
  FOR EACH ROW
  WHEN ((OLD.anonymized_at IS NULL AND NEW.anonymized_at IS NOT NULL)
        OR (OLD.is_active IS TRUE AND NEW.is_active IS NOT TRUE))
  EXECUTE FUNCTION public._push_subscriptions_purge();

-- ── (4b) art. 18: autoexclusão (captura 20260514520000 + DELETE da inscrição) ─────
CREATE OR REPLACE FUNCTION public.delete_my_personal_data(p_confirm_text text DEFAULT NULL::text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller record;
  v_cleared text[];
  v_push_deleted integer;
BEGIN
  SELECT id, name, email, phone, address, city, state, country, birth_date
  INTO v_caller
  FROM members WHERE auth_id = auth.uid();
  IF v_caller.id IS NULL THEN
    RETURN jsonb_build_object('error', 'not_authenticated');
  END IF;

  IF p_confirm_text IS NULL OR upper(trim(p_confirm_text)) != 'DELETAR MEUS DADOS PESSOAIS' THEN
    RETURN jsonb_build_object(
      'error', 'confirmation_required',
      'message', 'Confirme enviando o parâmetro p_confirm_text com o texto: DELETAR MEUS DADOS PESSOAIS',
      'warning', 'Esta ação é IRREVERSÍVEL. Limpa endereço, cidade, telefone, aniversário. Preserva nome, email, contribuições, certificados emitidos.'
    );
  END IF;

  v_cleared := '{}';
  IF v_caller.phone IS NOT NULL THEN v_cleared := array_append(v_cleared, 'phone'); END IF;
  IF v_caller.address IS NOT NULL THEN v_cleared := array_append(v_cleared, 'address'); END IF;
  IF v_caller.city IS NOT NULL THEN v_cleared := array_append(v_cleared, 'city'); END IF;
  IF v_caller.birth_date IS NOT NULL THEN v_cleared := array_append(v_cleared, 'birth_date'); END IF;

  UPDATE members SET
    phone = NULL,
    address = NULL,
    city = NULL,
    birth_date = NULL,
    updated_at = now()
  WHERE id = v_caller.id;

  -- #2806: a inscrição de push do aparelho é dado pessoal e sai na autoexclusão. Esta função não marca
  -- anonymized_at, então o gatilho trg_push_subscriptions_purge não a cobre: o DELETE fica aqui.
  DELETE FROM public.push_subscriptions WHERE member_id = v_caller.id;
  GET DIAGNOSTICS v_push_deleted = ROW_COUNT;
  IF v_push_deleted > 0 THEN v_cleared := array_append(v_cleared, 'push_subscriptions'); END IF;

  -- Audit trail único em admin_audit_log (member_role_changes ref removida — tabela nunca existiu)
  INSERT INTO admin_audit_log (actor_id, action, target_type, target_id, changes)
  VALUES (v_caller.id, 'lgpd_self_erasure', 'member', v_caller.id,
    jsonb_build_object(
      'cleared_fields', to_jsonb(v_cleared),
      'cleared_at', now(),
      'legal_basis', 'LGPD Lei 13.709/2018 Art. 18 — Direito ao esquecimento',
      'preserved', 'name, email, pmi_id, state, country, historical contributions'
    ));

  RETURN jsonb_build_object(
    'success', true,
    'cleared_fields', to_jsonb(v_cleared),
    'preserved', jsonb_build_array('name', 'email', 'pmi_id', 'state', 'country', 'photo_url', 'linkedin_url', 'credly_url'),
    'message', 'Dados pessoais limpos. Histórico de contribuições e certificados preservados. Para excluir completamente sua conta, contate o gestor do projeto.',
    'legal_basis', 'LGPD Lei 13.709/2018 Art. 18'
  );
END;
$function$;

-- ── (4c) art. 18: exportação (captura 20260808000100 + bloco push_subscriptions) ───
CREATE OR REPLACE FUNCTION public.export_my_data()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_member_id uuid;
  v_person_id uuid;
  v_emails text[];
  v_result jsonb;
BEGIN
  SELECT id INTO v_member_id
  FROM public.members WHERE auth_id = auth.uid();
  IF v_member_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  SELECT id INTO v_person_id FROM public.persons WHERE legacy_member_id = v_member_id;

  -- #1682: os e-mails do titular, resolvidos UMA vez. O cadastro e a candidatura podem ter
  -- chegado por endereços diferentes, e o ledger de consentimento é endereçado pela candidatura.
  -- COALESCE porque um titular sem e-mail algum deve alcançar ZERO candidaturas, não todas.
  SELECT COALESCE(array_agg(DISTINCT s.e), ARRAY[]::text[]) INTO v_emails
  FROM (
    SELECT lower(trim(m.email::text))  AS e FROM public.members m        WHERE m.id = v_member_id         AND m.email IS NOT NULL
    UNION
    SELECT lower(trim(me.email::text))      FROM public.member_emails me WHERE me.member_id = v_member_id AND me.email IS NOT NULL
  ) s;

  SELECT jsonb_build_object(
    'profile', (SELECT row_to_json(m)::jsonb FROM public.members m WHERE m.id = v_member_id),
    'person', CASE WHEN v_person_id IS NOT NULL THEN
      (SELECT row_to_json(p)::jsonb FROM public.persons p WHERE p.id = v_person_id)
    ELSE NULL END,
    'engagements', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', e.id, 'kind', e.kind, 'role', e.role, 'status', e.status,
        'initiative_name', i.title, 'start_date', e.start_date, 'end_date', e.end_date,
        'legal_basis', e.legal_basis, 'has_agreement', (e.agreement_certificate_id IS NOT NULL),
        'granted_at', e.granted_at, 'revoked_at', e.revoked_at, 'revoke_reason', e.revoke_reason
      ) ORDER BY e.start_date DESC)
      FROM public.engagements e LEFT JOIN public.initiatives i ON i.id = e.initiative_id
      WHERE e.person_id = v_person_id
    ), '[]'::jsonb),
    'attendance', COALESCE((SELECT jsonb_agg(row_to_json(a)::jsonb) FROM public.attendance a WHERE a.member_id = v_member_id), '[]'::jsonb),
    'gamification', COALESCE((SELECT jsonb_agg(row_to_json(g)::jsonb) FROM public.gamification_points g WHERE g.member_id = v_member_id), '[]'::jsonb),
    'notifications', COALESCE((SELECT jsonb_agg(row_to_json(n)::jsonb) FROM public.notifications n WHERE n.recipient_id = v_member_id), '[]'::jsonb),
    -- #2806: inscrições de push por aparelho, SEM p256dh e auth_secret (endpoint + chaves = credencial de envio).
    'push_subscriptions', COALESCE((SELECT jsonb_agg(jsonb_build_object(
        'id', ps.id, 'origin', ps.origin, 'endpoint', ps.endpoint, 'user_agent', ps.user_agent,
        'created_at', ps.created_at, 'last_success_at', ps.last_success_at,
        'failure_count', ps.failure_count, 'disabled_at', ps.disabled_at
      ) ORDER BY ps.created_at) FROM public.push_subscriptions ps WHERE ps.member_id = v_member_id), '[]'::jsonb),
    'board_assignments', COALESCE((SELECT jsonb_agg(row_to_json(ba)::jsonb) FROM public.board_item_assignments ba WHERE ba.member_id = v_member_id), '[]'::jsonb),
    'cycle_history', COALESCE((SELECT jsonb_agg(row_to_json(mch)::jsonb) FROM public.member_cycle_history mch WHERE mch.member_id = v_member_id), '[]'::jsonb),
    'certificates', COALESCE((SELECT jsonb_agg(row_to_json(c)::jsonb) FROM public.certificates c WHERE c.member_id = v_member_id), '[]'::jsonb),
    'selection_applications', COALESCE((
      SELECT jsonb_agg(row_to_json(sa)::jsonb)
      FROM public.selection_applications sa
      WHERE lower(trim(sa.email)) = ANY (v_emails)
    ), '[]'::jsonb),
    'onboarding', COALESCE((SELECT jsonb_agg(row_to_json(op)::jsonb) FROM public.onboarding_progress op WHERE op.member_id = v_member_id), '[]'::jsonb),
    -- #1682: o ledger alcança o titular por member_id OU pela candidatura que é dele. Enquanto
    -- `give_consent_via_token` não carimbar o member_id no ato do aceite, a segunda perna é o
    -- único caminho; depois dela, vira o fallback de quem consentiu antes do carimbo existir.
    'consent_records', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', cr.id,
        'policy_type', cr.policy_type,
        'policy_version', cr.policy_version,
        'policy_document_id', cr.policy_document_id,
        'accepted_at', cr.accepted_at,
        'channel', cr.channel,
        'email_hash', cr.email_hash,
        'ip_hash', cr.ip_hash,
        'user_agent_hash', cr.user_agent_hash,
        'revoked_at', cr.revoked_at,
        'revocation_reason', cr.revocation_reason,
        'is_active', (cr.revoked_at IS NULL),
        'created_at', cr.created_at,
        -- #1682: a origem do vínculo e a prova. `evidence` NULL não é omissão — é o registro de
        -- que o aceite chegou sem prova do texto exibido (ver `unversioned` em #1666).
        'application_id', cr.application_id,
        'linked_by', CASE WHEN cr.member_id = v_member_id THEN 'member_id' ELSE 'application_email' END,
        'evidence', cr.evidence
      ) ORDER BY cr.accepted_at DESC)
      FROM public.consent_records cr
      WHERE cr.member_id = v_member_id
         OR cr.application_id IN (
              SELECT sa.id FROM public.selection_applications sa
              WHERE lower(trim(sa.email)) = ANY (v_emails)
            )
    ), '[]'::jsonb),
    -- #569 S4c (ADR-0101 deferred L57): the declarant's PI-exclusion registry — LGPD Art. 18 II
    -- portability. Digest/status/anchor METADATA only; the .ots bytea is not inlined (binary
    -- proof artifact — export it via export_anexo_i por declaration_id), its PRESENCE is
    -- flagged per asset. eficacia_plena (doc7 Cl.4.1) = ALL assets confirmed — surfaced per
    -- declaration so the titular never mis-reads 'pending' as already-efficacious (legal fold).
    'pi_exclusion', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'declaration_id', d.id,
        'title', d.title,
        'status', d.status,
        'created_at', d.created_at,
        'updated_at', d.updated_at,
        'revoked_at', d.revoked_at,
        'total_assets', (SELECT count(*) FROM public.pi_exclusion_assets a WHERE a.declaration_id = d.id),
        'confirmed_assets', (SELECT count(*) FROM public.pi_exclusion_assets a WHERE a.declaration_id = d.id AND a.ots_status = 'confirmed'),
        'eficacia_plena', COALESCE((
          SELECT bool_and(a.ots_status = 'confirmed') AND count(*) > 0
          FROM public.pi_exclusion_assets a WHERE a.declaration_id = d.id
        ), false),
        'assets', COALESCE((
          SELECT jsonb_agg(jsonb_build_object(
            'seq', a.seq,
            'titulo', a.title,
            'natureza', a.nature,
            'autor_capitulo', a.author_label,
            'data_criacao', a.work_created_on,
            'caminho_url', a.source_ref,
            'sha256', a.sha256,
            'status', a.ots_status,
            'prova_ots', (a.ots_proof IS NOT NULL),
            'ancoragem', CASE WHEN a.ots_status = 'confirmed'
              THEN jsonb_build_object('bloco', a.bitcoin_block, 'utc', a.attested_at) ELSE NULL END
          ) ORDER BY a.seq)
          FROM public.pi_exclusion_assets a WHERE a.declaration_id = d.id
        ), '[]'::jsonb)
      ) ORDER BY d.created_at DESC)
      FROM public.pi_exclusion_declarations d WHERE d.declarant_member_id = v_member_id
    ), '[]'::jsonb),
    -- #625 F1: verificações de filiação do titular (Art. 18 II; inclui verification_obs = dado de terceiro sobre o titular)
    'affiliation_verifications', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', mav.id,
        'chapter_verified', mav.chapter_verified,
        'membership_active', mav.membership_active,
        'membership_expires_on', mav.membership_expires_on,
        'method', mav.method,
        'verification_obs', mav.verification_obs,
        'verified_by_name', COALESCE(vb.name, 'Verificador não disponível'),  -- #625: contexto p/ Art. 18 III
        'created_at', mav.created_at
      ) ORDER BY mav.created_at DESC)
      FROM public.member_affiliation_verifications mav
      LEFT JOIN public.members vb ON vb.id = mav.verified_by_member_id
      WHERE mav.member_id = v_member_id
    ), '[]'::jsonb),
    'exported_at', now()
  ) INTO v_result;
  RETURN v_result;
END;
$function$;

NOTIFY pgrst, 'reload schema';
