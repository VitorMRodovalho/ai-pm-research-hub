-- =====================================================================================
-- #625 — Loop de Verificação de Filiação (F1) + Radar de Renovação (F3, dry-run)
-- SPEC: docs/specs/SPEC_625_AFFILIATION_VERIFICATION_LOOP.md
-- ADRs: 0004 (organization_id) · 0007 (can()) · 0012 (cache columns) · 0076 (PMI data/LIA/opt-out) · GC-162 (RLS/LGPD)
--
-- Decisões PM 2026-06-11 (kickoff F1):
--   • Designation da Diretoria de Filiação = `filiacao_director` (segue a convenção *_director
--     dos diretores existentes — supersede o `diretoria_filiacao` da spec §2.7; reconciliado no doc).
--   • Periodicidade = AMBAS → radar contínuo (membership_expires_on D-30/D-7) + sinal de
--     "verificação obsoleta" (>11 meses) no MESMO cron (cobre a varredura anual sem 2º cron).
--   • Escopo = F1 + radar F3 em dry-run (p_dry_run := true até sign-off do PM — lição Gap-1).
--
-- Autoridade (V4_AUTHORITY_MODEL.md): gate por designation (Path 2) `filiacao_director`
--   OU `can_by_member(caller,'manage_member')` (Path 1 PM/superadmin). NÃO há seed novo em
--   engagement_kind_permissions (anti-pattern documentado).
--
-- ROLLBACK:
--   DROP FUNCTION IF EXISTS public.v4_notify_expiring_affiliations(boolean);
--   DROP FUNCTION IF EXISTS public.get_member_affiliation_status(uuid);
--   DROP FUNCTION IF EXISTS public.verify_member_affiliations_bulk(uuid[],text,text);
--   DROP FUNCTION IF EXISTS public.verify_member_affiliation(uuid,text,boolean,date,text,text,text);
--   DROP TABLE IF EXISTS public.member_affiliation_verifications;
--   SELECT cron.unschedule('v4-affiliation-expiry-notify');
--   -- + restaurar bodies anteriores de admin_list_members / export_my_data /
--   --   anonymize_inactive_members / sign_volunteer_agreement / _delivery_mode_for.
--   --   Estes NÃO estão na mig 147 — buscar a captura anterior de cada um no git:
--   --   git log -p --all -- supabase/migrations | grep -B2 -A300 'CREATE OR REPLACE FUNCTION public.<fn>'
-- =====================================================================================

-- -------------------------------------------------------------------------------------
-- 1. Tabela append-only `member_affiliation_verifications` (§4.1)
-- -------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.member_affiliation_verifications (
  id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id       uuid NOT NULL DEFAULT '2b4f58ab-7c45-4170-8718-b77ee69ff906'::uuid
                          REFERENCES public.organizations(id) ON DELETE RESTRICT,
  member_id             uuid NOT NULL REFERENCES public.members(id) ON DELETE RESTRICT,
  -- nullable de propósito: a anonimização do titular desreferencia o verificador (→NULL),
  -- minimização Art. 6º III. RPCs SEMPRE populam em escrita; só o cron LGPD zera.
  verified_by_member_id uuid REFERENCES public.members(id) ON DELETE RESTRICT,
  chapter_verified      text,
  membership_active     boolean NOT NULL,
  membership_expires_on date,                                  -- âncora do radar de renovação (F3)
  method                text NOT NULL CHECK (method IN ('vep_sync','sede_manual','self_attested')),
  source_ref            text,                                  -- APENAS identificador técnico (lote/relatório); nunca texto livre sobre pessoas
  verification_obs      text CHECK (verification_obs IS NULL OR char_length(verification_obs) <= 500),
  created_at            timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.member_affiliation_verifications IS
  '#625 F1. Histórico APPEND-ONLY de verificações de filiação PMI feitas pela Diretoria de '
  'Filiação da sede (PMI-GO). RLS deny-all; acesso exclusivamente via SECURITY DEFINER RPCs '
  '(verify_member_affiliation / verify_member_affiliations_bulk / get_member_affiliation_status). '
  'LGPD: dado GERADO PELO NÚCLEO (não linha do ThoughtSpot) — controladora PMI-GO, operadora '
  'plataforma. Bases: Art. 7º II+IX (pré-onboarding, c/ LIA) e Art. 7º V+IX (membro/renovação). '
  'Retenção: anonimizado junto com o membro após 5y de inatividade (cron anonymize_inactive_members '
  '— verification_obs→NULL, source_ref→hash, verified_by_member_id→NULL; member_id mantido pois a '
  'linha de members é anonimizada in-place (FK RESTRICT preservada); chapter_verified + '
  'membership_expires_on retidos como estatística não-nominal). Direito de acesso Art. 18 II via '
  'export_my_data. RoPA: entrada "verificação de filiação PMI" — a LIA do Art. 7º IX deve estar '
  'documentada nessa entrada do RoPA ANTES de habilitar o acesso de escrita da Diretoria (critério §8).';
COMMENT ON COLUMN public.member_affiliation_verifications.membership_expires_on IS
  'Âncora do radar de renovação (F3). NULL para method=vep_sync (VEP não expõe expiração).';
COMMENT ON COLUMN public.member_affiliation_verifications.verification_obs IS
  'Observação EXCLUSIVAMENTE sobre o RESULTADO da verificação (≤500 chars). UI avisa "não incluir '
  'dados pessoais além do necessário". É dado de terceiro sobre o titular → exportado no Art. 18 II.';

CREATE INDEX IF NOT EXISTS idx_mav_member_created
  ON public.member_affiliation_verifications (member_id, created_at DESC);
-- (índice de expiry removido — council data-architect: a query do radar usa DISTINCT ON (member_id)
--  ORDER BY member_id, created_at DESC → serve-se de idx_mav_member_created; um índice parcial por
--  expiry ficaria órfão (ADR-0012). Adicionar quando existir hot path de push-down por expiry.)
CREATE INDEX IF NOT EXISTS idx_mav_org
  ON public.member_affiliation_verifications (organization_id);

-- RLS deny-all (GC-162): RLS habilitada, ZERO policies → nenhum acesso direto de
-- authenticated/anon. SECURITY DEFINER RPCs (owner) e service_role acessam (bypass RLS).
ALTER TABLE public.member_affiliation_verifications ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.member_affiliation_verifications FROM anon, authenticated;

-- -------------------------------------------------------------------------------------
-- 2. RPC verify_member_affiliation — verificação individual (§5 F1)
-- -------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.verify_member_affiliation(
  p_member_id  uuid,
  p_chapter    text    DEFAULT NULL,
  p_active     boolean DEFAULT NULL,
  p_expires_on date    DEFAULT NULL,
  p_method     text    DEFAULT 'sede_manual',
  p_obs        text    DEFAULT NULL,
  p_source_ref text    DEFAULT NULL   -- identificador técnico (lote/relatório PMI); paridade com o bulk
) RETURNS jsonb
  LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id           uuid;
  v_caller_designations text[];
  v_chapter             text;
  v_active              boolean;
  v_verified            boolean;
  v_verification_id     uuid;
BEGIN
  SELECT m.id, m.designations INTO v_caller_id, v_caller_designations
  FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Forbidden: authentication required';
  END IF;

  -- Gate: Path 2 (designation filiacao_director) OU Path 1 (manage_member = PM/superadmin)
  IF NOT ('filiacao_director' = ANY(COALESCE(v_caller_designations, '{}'::text[])))
     AND NOT public.can_by_member(v_caller_id, 'manage_member') THEN
    RAISE EXCEPTION 'Forbidden: requires filiacao_director designation or platform manager authority';
  END IF;

  -- Vedação de uso próprio (spec §6.2.3): um verificador NÃO pode verificar a si mesmo
  -- (fecha auto-atribuição de pmi_id_verified). Exceção: manage_member (PM/superadmin).
  IF p_member_id = v_caller_id AND NOT public.can_by_member(v_caller_id, 'manage_member') THEN
    RAISE EXCEPTION 'Forbidden: self-verification not permitted';
  END IF;

  IF p_method NOT IN ('vep_sync','sede_manual','self_attested') THEN
    RAISE EXCEPTION 'Invalid method: %', p_method;
  END IF;
  IF p_obs IS NOT NULL AND char_length(p_obs) > 500 THEN
    RAISE EXCEPTION 'verification_obs exceeds 500 chars';
  END IF;

  SELECT m.chapter INTO v_chapter FROM public.members m WHERE m.id = p_member_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Member not found: %', p_member_id;
  END IF;

  v_chapter  := COALESCE(p_chapter, v_chapter);
  v_active   := COALESCE(p_active, false);
  -- cache rule §2.9
  v_verified := v_active AND (p_expires_on IS NULL OR p_expires_on > CURRENT_DATE);

  -- Trilha de leitura nominal de PII (Art. 37). Helper ignora self/anon internamente.
  PERFORM public.log_pii_access(
    p_member_id,
    ARRAY['pmi_id','chapter','membership_status'],
    'affiliation_verification',
    'Diretoria de Filiação (sede) — verificação de filiação PMI');

  INSERT INTO public.member_affiliation_verifications
    (member_id, verified_by_member_id, chapter_verified, membership_active,
     membership_expires_on, method, source_ref, verification_obs)
  VALUES
    (p_member_id, v_caller_id, v_chapter, v_active, p_expires_on, p_method, p_source_ref, p_obs)
  RETURNING id INTO v_verification_id;

  UPDATE public.members
  SET pmi_id_verified = v_verified, updated_at = now()
  WHERE id = p_member_id;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes)
  VALUES (v_caller_id, 'affiliation.verified', 'member', p_member_id,
    jsonb_build_object(
      'verification_id', v_verification_id,
      'method', p_method,
      'membership_active', v_active,
      'chapter_verified', v_chapter,
      'membership_expires_on', p_expires_on,
      'pmi_id_verified', v_verified));

  RETURN jsonb_build_object(
    'ok', true,
    'verification_id', v_verification_id,
    'pmi_id_verified', v_verified);
END;
$function$;

-- -------------------------------------------------------------------------------------
-- 3. RPC verify_member_affiliations_bulk — verificação em massa via VEP (§5 F1, council HIGH)
--    Deriva chapter + filiação-ativa server-side a partir do VEP (vep_status_raw='Active').
--    "25 em ≤1h" → seleção múltipla + 1 clique.
-- -------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.verify_member_affiliations_bulk(
  p_member_ids uuid[],
  p_method     text DEFAULT 'vep_sync',
  p_obs        text DEFAULT NULL
) RETURNS jsonb
  LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id           uuid;
  v_caller_designations text[];
  v_batch_ref           text;
  v_count               int := 0;
  v_ids                 uuid[] := '{}';
  v_no_vep              uuid[] := '{}';
  v_not_found           uuid[] := '{}';
  v_active              boolean;
  r                     record;
BEGIN
  SELECT m.id, m.designations INTO v_caller_id, v_caller_designations
  FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Forbidden: authentication required';
  END IF;

  IF NOT ('filiacao_director' = ANY(COALESCE(v_caller_designations, '{}'::text[])))
     AND NOT public.can_by_member(v_caller_id, 'manage_member') THEN
    RAISE EXCEPTION 'Forbidden: requires filiacao_director designation or platform manager authority';
  END IF;

  IF p_method NOT IN ('vep_sync','sede_manual','self_attested') THEN
    RAISE EXCEPTION 'Invalid method: %', p_method;
  END IF;
  IF p_member_ids IS NULL OR cardinality(p_member_ids) = 0 THEN
    RAISE EXCEPTION 'No members supplied';
  END IF;
  IF p_obs IS NOT NULL AND char_length(p_obs) > 500 THEN
    RAISE EXCEPTION 'verification_obs exceeds 500 chars';
  END IF;

  -- Vedação de uso próprio (spec §6.2.3): o verificador não pode estar no próprio lote
  -- (auto-atribuição de pmi_id_verified). Exceção: manage_member (PM/superadmin).
  IF v_caller_id = ANY(p_member_ids) AND NOT public.can_by_member(v_caller_id, 'manage_member') THEN
    RAISE EXCEPTION 'Forbidden: self-verification not permitted (remova seu próprio id do lote)';
  END IF;

  v_batch_ref := 'bulk:' || gen_random_uuid()::text;

  FOR r IN
    SELECT m.id, m.chapter,
      (SELECT a.vep_status_raw
       FROM public.selection_applications a
       WHERE lower(a.email) = lower(m.email) AND a.vep_status_raw IS NOT NULL
       ORDER BY a.vep_last_seen_at DESC NULLS LAST
       LIMIT 1) AS vep_status
    FROM public.members m
    WHERE m.id = ANY(p_member_ids)
  LOOP
    -- vep_sync deriva a filiação do VEP; sem registro VEP NÃO fabricamos "inativo" —
    -- reporta em no_vep_ids para verificação manual (council LOW).
    IF p_method = 'vep_sync' AND r.vep_status IS NULL THEN
      v_no_vep := array_append(v_no_vep, r.id);
      CONTINUE;
    END IF;
    v_active := (r.vep_status = 'Active');
    INSERT INTO public.member_affiliation_verifications
      (member_id, verified_by_member_id, chapter_verified, membership_active,
       membership_expires_on, method, source_ref, verification_obs)
    VALUES
      (r.id, v_caller_id, r.chapter, v_active, NULL, p_method, v_batch_ref, p_obs);

    -- vep_sync não tem expiração → pmi_id_verified = membership_active
    UPDATE public.members
    SET pmi_id_verified = v_active, updated_at = now()
    WHERE id = r.id;

    v_count := v_count + 1;
    v_ids := array_append(v_ids, r.id);
  END LOOP;

  -- ids fornecidos que não existem como membro (council LOW: não silenciar typo de UUID)
  v_not_found := ARRAY(
    SELECT x FROM unnest(p_member_ids) x
    EXCEPT
    SELECT y FROM unnest(array_cat(v_ids, v_no_vep)) y);

  -- Trilha de leitura nominal (Art. 37) — só dos membros que existiram e tiveram PII lida
  -- (NIT: logar após o loop com ids reais, não os de entrada que podem incluir UUIDs inválidos).
  PERFORM public.log_pii_access_batch(
    array_cat(v_ids, v_no_vep),
    ARRAY['pmi_id','chapter','membership_status'],
    'affiliation_verification_bulk',
    'Diretoria de Filiação (sede) — verificação de filiação PMI em massa via VEP');

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes)
  VALUES (v_caller_id, 'affiliation.verified_bulk', 'member', NULL,
    jsonb_build_object(
      'batch_ref', v_batch_ref,
      'method', p_method,
      'count', v_count,
      'member_ids', to_jsonb(v_ids),
      'no_vep_ids', to_jsonb(v_no_vep),
      'not_found_ids', to_jsonb(v_not_found)));

  RETURN jsonb_build_object(
    'ok', true,
    'count', v_count,
    'batch_ref', v_batch_ref,
    'member_ids', to_jsonb(v_ids),
    'no_vep_ids', to_jsonb(v_no_vep),
    'not_found_ids', to_jsonb(v_not_found));
END;
$function$;

-- -------------------------------------------------------------------------------------
-- 4. RPC get_member_affiliation_status — leitura da última verificação (fila/card admin)
-- -------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_member_affiliation_status(p_member_id uuid)
RETURNS jsonb
  LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id           uuid;
  v_caller_designations text[];
  v_is_self             boolean;
  v_result              jsonb;
BEGIN
  SELECT m.id, m.designations INTO v_caller_id, v_caller_designations
  FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Forbidden: authentication required';
  END IF;

  v_is_self := (v_caller_id = p_member_id);

  -- Self pode ver o próprio status; demais precisam de designation/manage_member/admin analytics.
  IF NOT v_is_self
     AND NOT ('filiacao_director' = ANY(COALESCE(v_caller_designations, '{}'::text[])))
     AND NOT public.can_by_member(v_caller_id, 'manage_member')
     AND NOT public.can_by_member(v_caller_id, 'view_internal_analytics') THEN
    RAISE EXCEPTION 'Forbidden';
  END IF;

  -- Trilha de leitura nominal por terceiro (Art. 37). Self é isento (dado do próprio titular).
  IF NOT v_is_self THEN
    PERFORM public.log_pii_access(p_member_id,
      ARRAY['chapter','membership_active','membership_expires_on','verification_obs'],
      'affiliation_status_read',
      'Diretoria de Filiação / administrador — leitura de status de filiação');
  END IF;

  SELECT jsonb_build_object(
    'member_id', p_member_id,
    'pmi_id_verified', (SELECT m.pmi_id_verified FROM public.members m WHERE m.id = p_member_id),
    'latest', (
      SELECT jsonb_build_object(
        'id', mav.id,
        'chapter_verified', mav.chapter_verified,
        'membership_active', mav.membership_active,
        'membership_expires_on', mav.membership_expires_on,
        'method', mav.method,
        -- self vê só metadados: verification_obs (nota operacional da Diretoria) só via export_my_data
        -- (Art. 18 II); verified_by mostrado como PAPEL ao self (não expõe nome do agente interno).
        'verification_obs', CASE WHEN v_is_self THEN NULL ELSE mav.verification_obs END,
        'verified_by', CASE WHEN v_is_self THEN 'Diretoria de Filiação' ELSE vb.name END,
        'created_at', mav.created_at)
      FROM public.member_affiliation_verifications mav
      LEFT JOIN public.members vb ON vb.id = mav.verified_by_member_id
      WHERE mav.member_id = p_member_id
      ORDER BY mav.created_at DESC LIMIT 1),
    'history_count', (SELECT count(*) FROM public.member_affiliation_verifications mav WHERE mav.member_id = p_member_id)
  ) INTO v_result;

  RETURN v_result;
END;
$function$;

-- -------------------------------------------------------------------------------------
-- 5. RPC v4_notify_expiring_affiliations — Radar de renovação (F3). DRY-RUN por padrão.
--    Sinais: (A) expiração D-30/D-7 sobre membership_expires_on (contínuo);
--            (B) verificação obsoleta > 11 meses com filiação tida como ativa (varredura anual).
--    Espelha o PADRÃO de v4_notify_expiring_engagements (council MEDIUM: NÃO estender aquele —
--    tabela diferente). Em dry-run NÃO insere notificações; retorna o relatório p/ preview do PM.
-- -------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.v4_notify_expiring_affiliations(p_dry_run boolean DEFAULT true)
RETURNS jsonb
  LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_count_d30  int := 0;
  v_count_d7   int := 0;
  v_count_stale int := 0;
  v_sent       int := 0;
  v_filiacao_member_id uuid;
  r            record;
BEGIN
  -- Diretora de Filiação (sede) — destinatária de awareness quando não-dry-run.
  SELECT m.id INTO v_filiacao_member_id
  FROM public.members m
  WHERE m.is_active = true AND 'filiacao_director' = ANY(m.designations)
  LIMIT 1;

  -- Última verificação por membro (a trilha é append-only).
  FOR r IN
    SELECT DISTINCT ON (mav.member_id)
      mav.member_id, mav.membership_active, mav.membership_expires_on, mav.created_at,
      m.name AS member_name, m.is_active,
      (mav.membership_expires_on - CURRENT_DATE) AS days_until_expiry,
      (CURRENT_DATE - mav.created_at::date) AS days_since_verification
    FROM public.member_affiliation_verifications mav
    JOIN public.members m ON m.id = mav.member_id
    WHERE m.is_active = true
    ORDER BY mav.member_id, mav.created_at DESC
  LOOP
    -- (A) Expiração D-30
    IF r.membership_active AND r.membership_expires_on IS NOT NULL
       AND r.days_until_expiry BETWEEN 8 AND 30 THEN
      v_count_d30 := v_count_d30 + 1;
      IF NOT p_dry_run AND NOT EXISTS (
        SELECT 1 FROM public.notifications n
        WHERE n.recipient_id = r.member_id AND n.type = 'affiliation_renewal_d30'
          AND n.source_id = r.member_id AND n.created_at > (now() - interval '7 days')
      ) THEN
        INSERT INTO public.notifications (recipient_id, type, title, body, link, source_type, source_id, delivery_mode)
        VALUES (r.member_id, 'affiliation_renewal_d30',
          'Sua filiação PMI vence em 30 dias',
          'PMI Goiás (Programa Núcleo IA): sua filiação ao PMI vence em ' || r.membership_expires_on ||
          '. O Termo de Voluntariado exige filiação PMI ativa — renove em pmi.org. '
          'Para parar estes lembretes, ajuste em /profile (não afeta seu voluntariado).',
          '/profile', 'affiliation', r.member_id,
          public._delivery_mode_for('affiliation_renewal_d30'));
        v_sent := v_sent + 1;
      END IF;
    END IF;

    -- (A) Expiração D-7 URGENTE
    IF r.membership_active AND r.membership_expires_on IS NOT NULL
       AND r.days_until_expiry BETWEEN 1 AND 7 THEN
      v_count_d7 := v_count_d7 + 1;
      IF NOT p_dry_run AND NOT EXISTS (
        SELECT 1 FROM public.notifications n
        WHERE n.recipient_id = r.member_id AND n.type = 'affiliation_renewal_d7_urgent'
          AND n.source_id = r.member_id AND n.created_at > (now() - interval '7 days')
      ) THEN
        INSERT INTO public.notifications (recipient_id, type, title, body, link, source_type, source_id, delivery_mode)
        VALUES (r.member_id, 'affiliation_renewal_d7_urgent',
          'URGENTE: sua filiação PMI vence em 7 dias',
          'PMI Goiás (Programa Núcleo IA): sua filiação ao PMI vence em ' || r.membership_expires_on ||
          '. Renove imediatamente em pmi.org para manter seu Termo de Voluntariado vigente. '
          'Para ajustar lembretes, acesse /profile (não afeta seu voluntariado).',
          '/profile', 'affiliation', r.member_id,
          public._delivery_mode_for('affiliation_renewal_d7_urgent'));
        v_sent := v_sent + 1;
      END IF;
    END IF;

    -- (B) Verificação obsoleta > 11 meses (cobre a varredura anual no mesmo radar).
    IF r.days_since_verification > 330 THEN
      v_count_stale := v_count_stale + 1;
      IF NOT p_dry_run AND v_filiacao_member_id IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM public.notifications n
        WHERE n.recipient_id = v_filiacao_member_id AND n.type = 'affiliation_verification_stale'
          AND n.source_id = r.member_id AND n.created_at > (now() - interval '30 days')
      ) THEN
        INSERT INTO public.notifications (recipient_id, type, title, body, link, source_type, source_id, delivery_mode)
        VALUES (v_filiacao_member_id, 'affiliation_verification_stale',
          'Re-verificar filiação: ' || r.member_name,
          r.member_name || ' não tem verificação de filiação há ' || r.days_since_verification ||
          ' dias. Re-verifique na fila de /admin/members.',
          '/admin/members?filter=affiliation', 'affiliation', r.member_id,
          public._delivery_mode_for('affiliation_verification_stale'));
        v_sent := v_sent + 1;
      END IF;
    END IF;
  END LOOP;

  RETURN jsonb_build_object(
    'dry_run', p_dry_run,
    'candidates_d30', v_count_d30,
    'candidates_d7', v_count_d7,
    'candidates_stale', v_count_stale,
    'notifications_sent', v_sent,
    'run_at', now());
END;
$function$;

-- -------------------------------------------------------------------------------------
-- 5b. _delivery_mode_for — cataloga os 3 novos tipos de notificação de filiação (F3).
--     Sem isso caem no ELSE 'digest_weekly' e o d7_urgent perde a urgência (council HIGH).
--     CREATE OR REPLACE preserva os tipos já catalogados + adiciona os novos antes do ELSE.
-- -------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public._delivery_mode_for(p_type text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE PARALLEL SAFE
 SET search_path TO ''
AS $function$
  SELECT CASE p_type
    WHEN 'volunteer_agreement_signed'    THEN 'transactional_immediate'
    WHEN 'ip_ratification_gate_pending'  THEN 'transactional_immediate'
    WHEN 'system_alert'                  THEN 'transactional_immediate'
    WHEN 'certificate_ready'             THEN 'transactional_immediate'
    WHEN 'member_offboarded'             THEN 'transactional_immediate'
    WHEN 'ip_ratification_gate_advanced'    THEN 'transactional_immediate'
    WHEN 'ip_ratification_chain_approved'   THEN 'transactional_immediate'
    WHEN 'ip_ratification_awaiting_members' THEN 'transactional_immediate'
    WHEN 'webinar_status_confirmed'      THEN 'transactional_immediate'
    WHEN 'webinar_status_completed'      THEN 'transactional_immediate'
    WHEN 'webinar_status_cancelled'      THEN 'transactional_immediate'
    WHEN 'weekly_card_digest_member'     THEN 'transactional_immediate'
    WHEN 'governance_cr_new'             THEN 'transactional_immediate'
    WHEN 'governance_cr_vote'            THEN 'transactional_immediate'
    WHEN 'governance_cr_approved'        THEN 'transactional_immediate'
    WHEN 'sponsor_finance_entry_logged'  THEN 'transactional_immediate'
    WHEN 'governance_manual_proposed'    THEN 'transactional_immediate'
    WHEN 'engagement_renewal_d7_urgent'  THEN 'transactional_immediate'
    -- p153 OPP-153.1: project_charter (TAP) notifications
    WHEN 'project_charter_invite'        THEN 'transactional_immediate'
    WHEN 'project_charter_approved'      THEN 'transactional_immediate'
    -- p159 S#1 T1 (2026-05-14): selection_termo_due é o "email principal" pós-VEP-Active
    WHEN 'selection_termo_due'           THEN 'transactional_immediate'
    -- p228 #260 W2 Leaf 1 (2026-05-23): Selection funnel Policy Matrix
    WHEN 'selection_approved'            THEN 'transactional_immediate'
    WHEN 'selection_interview_scheduled' THEN 'transactional_immediate'
    WHEN 'peer_review_requested'         THEN 'transactional_immediate'
    WHEN 'selection_evaluation_complete' THEN 'suppress'
    WHEN 'selection_interview_noshow'    THEN 'digest_weekly'
    -- p228 #260 W2 Leaf 2 (2026-05-23): admin reminder for overdue interviews
    WHEN 'selection_interview_overdue'   THEN 'digest_weekly'
    -- p228 #260 W2 Leaf 4 (2026-05-23): candidate invite to book interview after
    -- objective evaluations cleared + research_score >= cycle cutoff.
    WHEN 'selection_cutoff_approved'     THEN 'transactional_immediate'
    -- (end p228)
    -- #186 (2026-06-05): curation committee broadcast when an item enters curation_pending
    WHEN 'curation_item_submitted'       THEN 'transactional_immediate'
    WHEN 'engagement_renewal_d30'        THEN 'digest_weekly'
    WHEN 'engagement_renewal_d60_gp_aggregate' THEN 'digest_weekly'
    -- #625 F3 (2026-06-11): radar de renovação de filiação
    WHEN 'affiliation_renewal_d7_urgent'  THEN 'transactional_immediate'
    WHEN 'affiliation_renewal_d30'        THEN 'digest_weekly'
    WHEN 'affiliation_verification_stale' THEN 'digest_weekly'
    WHEN 'attendance_detractor'          THEN 'suppress'
    WHEN 'info'                          THEN 'suppress'
    WHEN 'system'                        THEN 'suppress'
    ELSE 'digest_weekly'
  END;
$function$;

-- Grants (defesa em profundidade — os gates internos já barram, mas REVOKE de anon).
REVOKE ALL ON FUNCTION public.verify_member_affiliation(uuid,text,boolean,date,text,text,text) FROM public, anon;
REVOKE ALL ON FUNCTION public.verify_member_affiliations_bulk(uuid[],text,text) FROM public, anon;
REVOKE ALL ON FUNCTION public.get_member_affiliation_status(uuid) FROM public, anon;
REVOKE ALL ON FUNCTION public.v4_notify_expiring_affiliations(boolean) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.verify_member_affiliation(uuid,text,boolean,date,text,text,text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.verify_member_affiliations_bulk(uuid[],text,text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_member_affiliation_status(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.v4_notify_expiring_affiliations(boolean) TO service_role;

-- Cron F3 (dry-run até sign-off do PM). Idempotente por nome.
DO $cron$
BEGIN
  PERFORM cron.unschedule('v4-affiliation-expiry-notify');
EXCEPTION WHEN OTHERS THEN NULL;
END
$cron$;
SELECT cron.schedule('v4-affiliation-expiry-notify', '0 9 * * *',
  $$SELECT public.v4_notify_expiring_affiliations(p_dry_run := true)$$);

-- =====================================================================================
-- EDITS verbatim+delta (CREATE OR REPLACE — corpo preservado, deltas marcados com -- #625)
-- =====================================================================================

-- -------------------------------------------------------------------------------------
-- 6. admin_list_members — expõe pmi_id_verified + última verificação (farol da fila)
-- -------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_list_members(p_search text DEFAULT NULL::text, p_tier text DEFAULT NULL::text, p_tribe_id integer DEFAULT NULL::integer, p_status text DEFAULT 'active'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_caller_id uuid;
BEGIN
  SELECT m.id INTO v_caller_id
  FROM public.members m
  WHERE m.auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Forbidden: authentication required';
  END IF;

  IF NOT public.can_by_member(v_caller_id, 'view_internal_analytics') THEN
    RAISE EXCEPTION 'Admin only';
  END IF;

  RETURN (
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'id', m.id,
      'full_name', m.name,
      'email', m.email,
      'photo_url', m.photo_url,
      'operational_role', m.operational_role,
      'designations', m.designations,
      'is_superadmin', m.is_superadmin,
      'is_active', m.is_active,
      'member_status', m.member_status,
      'tribe_id', m.tribe_id,
      'tribe_name', tc.name,
      'chapter', m.chapter,
      'auth_id', m.auth_id,
      'last_seen_at', m.last_seen_at,
      'total_sessions', COALESCE(m.total_sessions, 0),
      'credly_username', m.credly_url,
      'offboarded_at', m.offboarded_at,
      'status_change_reason', m.status_change_reason,
      'vep_status_raw', vep.vep_status_raw,
      'vep_last_seen_at', vep.vep_last_seen_at,
      'is_pre_onboarding', COALESCE(pre.flag, false),
      -- #625 F1: farol de filiação (cache + última verificação da trilha append-only)
      'pmi_id_verified', COALESCE(m.pmi_id_verified, false),
      'affiliation_last_verified_at', aff.last_verified_at,
      'affiliation_active', aff.membership_active,
      'affiliation_expires_on', aff.membership_expires_on,
      'affiliation_method', aff.method
    ) ORDER BY m.name), '[]'::jsonb)
    FROM public.members m
    LEFT JOIN public.tribes tc ON tc.id = m.tribe_id
    LEFT JOIN LATERAL (
      SELECT a.vep_status_raw, a.vep_last_seen_at
      FROM public.selection_applications a
      WHERE lower(a.email) = lower(m.email)
        AND a.vep_status_raw IS NOT NULL
      ORDER BY a.vep_last_seen_at DESC NULLS LAST
      LIMIT 1
    ) vep ON true
    -- #625 C0: pré-onboarding = ativo cujo ÚNICO vínculo são engagements aguardando termo.
    -- Operacional = kind sem exigência de termo OU termo satisfeito; existir 1 operacional
    -- tira o membro da coorte (papel lateral pendente não rebaixa membro existente).
    LEFT JOIN LATERAL (
      SELECT (
        m.member_status = 'active'
        AND EXISTS (
          SELECT 1 FROM public.engagements e
          WHERE e.person_id = m.person_id AND e.status = 'active'
        )
        AND NOT EXISTS (
          SELECT 1 FROM public.engagements e
          JOIN public.engagement_kinds ek ON ek.slug = e.kind
          WHERE e.person_id = m.person_id AND e.status = 'active'
            AND (ek.requires_agreement IS NOT TRUE OR e.agreement_certificate_id IS NOT NULL)
        )
      ) AS flag
    ) pre ON true
    -- #625 F1: última verificação de filiação (trilha append-only)
    LEFT JOIN LATERAL (
      SELECT mav.created_at AS last_verified_at, mav.membership_active,
             mav.membership_expires_on, mav.method
      FROM public.member_affiliation_verifications mav
      WHERE mav.member_id = m.id
      ORDER BY mav.created_at DESC
      LIMIT 1
    ) aff ON true
    WHERE (p_status = 'all'
        OR (p_status = 'active' AND m.member_status = 'active')
        OR (p_status = 'inactive' AND m.member_status = 'inactive')
        OR (p_status = 'observer' AND m.member_status = 'observer')
        OR (p_status = 'alumni' AND m.member_status = 'alumni')
        OR (p_status = 'pre_onboarding' AND m.member_status = 'active' AND COALESCE(pre.flag, false)))
      AND (p_tier IS NULL OR m.operational_role = p_tier)
      AND (p_tribe_id IS NULL OR m.tribe_id = p_tribe_id)
      AND (p_search IS NULL OR m.name ILIKE '%' || p_search || '%' OR m.email ILIKE '%' || p_search || '%')
  );
END;
$function$;

-- -------------------------------------------------------------------------------------
-- 7. export_my_data — inclui as verificações de filiação do titular (Art. 18 II)
-- -------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.export_my_data()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_member_id uuid;
  v_person_id uuid;
  v_result jsonb;
BEGIN
  SELECT id INTO v_member_id
  FROM public.members WHERE auth_id = auth.uid();
  IF v_member_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  SELECT id INTO v_person_id FROM public.persons WHERE legacy_member_id = v_member_id;

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
    'board_assignments', COALESCE((SELECT jsonb_agg(row_to_json(ba)::jsonb) FROM public.board_item_assignments ba WHERE ba.member_id = v_member_id), '[]'::jsonb),
    'cycle_history', COALESCE((SELECT jsonb_agg(row_to_json(mch)::jsonb) FROM public.member_cycle_history mch WHERE mch.member_id = v_member_id), '[]'::jsonb),
    'certificates', COALESCE((SELECT jsonb_agg(row_to_json(c)::jsonb) FROM public.certificates c WHERE c.member_id = v_member_id), '[]'::jsonb),
    'selection_applications', COALESCE((
      SELECT jsonb_agg(row_to_json(sa)::jsonb)
      FROM public.selection_applications sa
      WHERE lower(trim(sa.email)) IN (
        SELECT lower(trim(m.email::text))  FROM public.members m        WHERE m.id = v_member_id         AND m.email IS NOT NULL
        UNION
        SELECT lower(trim(me.email::text)) FROM public.member_emails me WHERE me.member_id = v_member_id AND me.email IS NOT NULL
      )
    ), '[]'::jsonb),
    'onboarding', COALESCE((SELECT jsonb_agg(row_to_json(op)::jsonb) FROM public.onboarding_progress op WHERE op.member_id = v_member_id), '[]'::jsonb),
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
        'created_at', cr.created_at
      ) ORDER BY cr.accepted_at DESC)
      FROM public.consent_records cr WHERE cr.member_id = v_member_id
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

-- -------------------------------------------------------------------------------------
-- 8. anonymize_inactive_members — estende o escopo para a nova tabela (§4.1)
--    Reconciliação FK-safe (vs spec "UUID neutro"): a linha de members é anonimizada IN-PLACE
--    (UPDATE, não DELETE) → member_id/verified_by já de-referenciam para registro neutro;
--    scrub só dos campos livres/técnicos (verification_obs→NULL, source_ref→hash).
--    chapter_verified + membership_expires_on mantidos (estatística não-nominal).
-- -------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.anonymize_inactive_members(p_dry_run boolean DEFAULT true, p_years integer DEFAULT 5, p_limit integer DEFAULT 100)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'storage', 'pg_temp'
AS $function$
DECLARE
  v_candidate record;
  v_count int := 0;
  v_skipped int := 0;
  v_ids uuid[] := '{}';
  v_errors jsonb := '[]'::jsonb;
  v_resume_paths text[];
  v_resume_deleted_total int := 0;
  v_resume_deleted_this_loop int := 0;
  v_aff_scrubbed int := 0;  -- #625
BEGIN
  FOR v_candidate IN
    SELECT * FROM public.list_anonymization_candidates(p_years) LIMIT p_limit
  LOOP
    BEGIN
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

        UPDATE public.member_offboarding_records SET
          reason_detail = NULL, exit_interview_full_text = NULL,
          return_window_suggestion = NULL, lessons_learned = NULL,
          recommendation_for_future = NULL, attachment_urls = '{}'::text[],
          updated_at = now()
        WHERE member_id = v_candidate.member_id;

        -- BUG FIX: column is `recipient_id`, not `member_id`.
        DELETE FROM public.notifications WHERE recipient_id = v_candidate.member_id;
        DELETE FROM public.notification_preferences WHERE member_id = v_candidate.member_id;

        -- p195 LGPD storage extension: capture resume paths + delete binaries.
        SELECT array_agg(resume_storage_path)
        INTO v_resume_paths
        FROM public.selection_applications
        WHERE email = v_candidate.email
          AND resume_storage_path IS NOT NULL;

        v_resume_deleted_this_loop := 0;
        IF v_resume_paths IS NOT NULL AND array_length(v_resume_paths, 1) > 0 THEN
          DELETE FROM storage.objects
          WHERE bucket_id = 'selection-resumes'
            AND name = ANY(v_resume_paths);
          GET DIAGNOSTICS v_resume_deleted_this_loop = ROW_COUNT;
          v_resume_deleted_total := v_resume_deleted_total + v_resume_deleted_this_loop;
        END IF;

        UPDATE public.selection_applications SET
          applicant_name = 'Candidato Anonimizado',
          email = 'anon@removed.local',
          phone = NULL, linkedin_url = NULL,
          resume_url = NULL,
          resume_storage_path = NULL,  -- p195
          resume_synced_at = NULL,      -- p195
          motivation_letter = NULL
        WHERE email = v_candidate.email;

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
            'resume_objects_deleted', v_resume_deleted_this_loop,
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
    'member_ids', to_jsonb(v_ids),
    'resume_objects_deleted_total', v_resume_deleted_total,
    'errors', v_errors,
    'executed_at', now()
  );
END;
$function$;

-- -------------------------------------------------------------------------------------
-- 9. sign_volunteer_agreement — grava o estado do farol de filiação no audit (§2.8)
--    Delta: +m.pmi_id_verified no SELECT do v_member; +affiliation_unverified no audit changes.
-- -------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sign_volunteer_agreement(p_language text DEFAULT 'pt-BR'::text, p_signed_ip text DEFAULT NULL::text, p_signed_user_agent text DEFAULT NULL::text)
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
  v_ip inet := NULL;
BEGIN
  -- Server-side cap on UA length to prevent storage abuse via direct PostgREST
  -- or MCP callers that bypass the frontend's 500-char trim.
  p_signed_user_agent := left(p_signed_user_agent, 500);

  SELECT m.id, m.name, m.email, m.operational_role, m.pmi_id, m.chapter,
    m.phone, m.address, m.city, m.state, m.country, m.birth_date,
    m.pmi_id_verified,  -- #625: estado do farol de filiação no momento da assinatura
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

  BEGIN
    IF p_signed_ip IS NOT NULL AND length(trim(p_signed_ip)) > 0 THEN
      v_ip := p_signed_ip::inet;
    END IF;
  EXCEPTION WHEN OTHERS THEN
    v_ip := NULL;
  END;

  INSERT INTO certificates (
    member_id, type, title, description, cycle, issued_at, issued_by, verification_code,
    period_start, period_end, function_role, language, status, signature_hash, content_snapshot, template_id,
    signed_ip, signed_user_agent
  ) VALUES (
    v_member.id, 'volunteer_agreement',
    CASE p_language WHEN 'en-US' THEN 'Volunteer Agreement — Cycle ' || v_cycle
      WHEN 'es-LATAM' THEN 'Acuerdo de Voluntariado — Ciclo ' || v_cycle
      ELSE 'Termo de Voluntariado — Ciclo ' || v_cycle END,
    v_template.description, v_cycle, now(), v_issuer_id, v_code,
    v_period_start::text, v_period_end::text,
    v_member.operational_role, p_language, 'issued', v_hash, v_content, v_template.id::text,
    v_ip, p_signed_user_agent
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
      'period_source', v_source, 'engagement_linked', v_engagement_updated,
      'signed_ip', v_ip::text, 'signed_user_agent', p_signed_user_agent,
      -- #625 §2.8: farol de filiação no momento da assinatura (v1 = farol, não bloqueio).
      -- Permite ao v2 distinguir termos pré-loop × pós-loop ao avaliar política de bloqueio.
      'affiliation_unverified', NOT COALESCE(v_member.pmi_id_verified, false)));

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

NOTIFY pgrst, 'reload schema';
