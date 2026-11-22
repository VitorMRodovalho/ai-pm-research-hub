-- #3147: o acesso ao Drive dado por iniciativa termina com o vínculo com a iniciativa (decisões do GP de 21 e 22/11/2026).
--
-- Até aqui o reconcile diário (ADR-0124) só concedia: quem saía de uma tribo e seguia membro ficava com a pasta, e a
-- trilha de desligamento (ADR-0107) só cobre quem sai do Núcleo. Esta migration:
--
-- 1. drive_membership_grants ganha o estado `revoked` (#3135), com revoked_at, revoked_by e revoked_via. Os leitores
--    que contam acesso ativo já contam só `granted`, então uma linha revogada sai deles sem mudar nenhum.
-- 2. drive_membership_revocations: a fila, uma linha por pedido de revogação de uma concessão, com o histórico.
--    Entra por fim de vínculo (o ciclo) ou por pedido avulso da gestão.
-- 3. enqueue_membership_drive_revocations(), de hora em hora pelo pg_cron:
--    a. alinha o ledger com a trilha de desligamento: concessão cuja permissão aquela trilha já revogou, DEPOIS do
--       último envio da concessão, vira `revoked`. O id da permissão do Drive é o mesmo quando o acesso volta, e por
--       isso a hora entra na comparação;
--    b. cancela o item que deixou de valer: vínculo ativo de novo, manage_platform, concessão já fechada, ou a
--       trilha de desligamento com item aberto na mesma permissão;
--    c. põe na fila a concessão cuja pessoa saiu do roster da iniciativa (o MESMO predicado de
--       get_initiative_drive_roster), fora quem tem manage_platform (exceção nomeada do GP);
--    d. com a chave ligada, avisa a pessoa e marca o prazo: 7 dias, ou o próprio ciclo em iniciativa confidencial;
--    e. com a chave ligada, aprova o item vencido e não segurado, conferindo a condição de novo no UPDATE.
-- 4. O executor é o que já existe: a EF revoke-drive-permission, sem mudança de código. get_drive_revocation_row e
--    mark_drive_revocation_done passam a achar também o item da fila nova pelo id, e o cron revoke-drive-drain-hourly
--    drena as duas filas.
-- 5. Quatro funções de gestão (manage_platform): listar as duas filas, segurar ou soltar, desfazer, aprovar e pedir
--    uma revogação avulsa.
-- 6. A chave site_config.drive_membership_revoke_enabled nasce DESLIGADA: a fila se forma, mas ninguém é avisado nem
--    revogado até o GP ver a primeira lista (decisão 4).
-- 7. _delivery_mode_for: o aviso novo é imediato.

-- ── 1. O estado revogada na concessão (#3135) ──
ALTER TABLE public.drive_membership_grants DROP CONSTRAINT drive_membership_grants_status_check;
ALTER TABLE public.drive_membership_grants ADD CONSTRAINT drive_membership_grants_status_check
  CHECK (status IN ('pending_grant','granted','failed','already_present','skipped','revoked'));

ALTER TABLE public.drive_membership_grants
  ADD COLUMN IF NOT EXISTS revoked_at  timestamptz,
  ADD COLUMN IF NOT EXISTS revoked_by  uuid REFERENCES public.members(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS revoked_via text CHECK (revoked_via IN ('membership_queue','offboarding_audit'));

-- Uma linha revogada diz quando e por qual trilha; uma linha que não é revogada não carrega nenhum dos dois.
ALTER TABLE public.drive_membership_grants ADD CONSTRAINT drive_membership_grants_revoked_coherence
  CHECK ((status = 'revoked') = (revoked_at IS NOT NULL AND revoked_via IS NOT NULL));

COMMENT ON COLUMN public.drive_membership_grants.revoked_via IS
  '#3147: membership_queue = a fila de fim de vínculo (drive_membership_revocations); offboarding_audit = a trilha de desligamento (ADR-0107) já tinha revogado a mesma permissão.';

-- ── 2. A fila ──
CREATE TABLE IF NOT EXISTS public.drive_membership_revocations (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  grant_id        uuid NOT NULL REFERENCES public.drive_membership_grants(id) ON DELETE CASCADE,
  initiative_id   uuid NOT NULL REFERENCES public.initiatives(id) ON DELETE CASCADE,
  member_id       uuid REFERENCES public.members(id) ON DELETE CASCADE,
  reason          text NOT NULL CHECK (reason IN ('engagement_ended','manual')),
  is_confidential boolean NOT NULL DEFAULT false,
  status          text NOT NULL DEFAULT 'pending'
                    CHECK (status IN ('pending','approved','revoked','already_absent','failed','cancelled')),
  detected_at     timestamptz NOT NULL DEFAULT now(),
  notified_at     timestamptz,
  due_at          timestamptz,
  held_at         timestamptz,
  held_by         uuid REFERENCES public.members(id) ON DELETE SET NULL,
  hold_note       text,
  approval_mode   text CHECK (approval_mode IN ('manual','auto')),
  approved_by     uuid REFERENCES public.members(id) ON DELETE SET NULL,
  approved_at     timestamptz,
  revoked_at      timestamptz,
  google_error    jsonb,
  cancelled_at    timestamptz,
  cancelled_by    uuid REFERENCES public.members(id) ON DELETE SET NULL,
  cancel_reason   text CHECK (cancel_reason IN ('engagement_restored','management_kept','manage_platform_exception',
                                                'grant_closed','offboarding_lane')),
  note            text,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  -- passou da aprovação: sabe-se quem e quando (auto não tem pessoa, como na ADR-0107 Emenda 1)
  CONSTRAINT dmr_approved_has_provenance CHECK (status IN ('pending','cancelled') OR (approval_mode IS NOT NULL AND approved_at IS NOT NULL)),
  CONSTRAINT dmr_auto_has_no_person      CHECK (approval_mode IS DISTINCT FROM 'auto' OR approved_by IS NULL),
  CONSTRAINT dmr_cancelled_has_reason    CHECK ((status = 'cancelled') = (cancel_reason IS NOT NULL AND cancelled_at IS NOT NULL)),
  CONSTRAINT dmr_revoked_has_time        CHECK (status NOT IN ('revoked','already_absent') OR revoked_at IS NOT NULL),
  CONSTRAINT dmr_notified_has_due        CHECK ((notified_at IS NULL) = (due_at IS NULL))
);

COMMENT ON TABLE public.drive_membership_revocations IS
  '#3147: fila de revogação do acesso por iniciativa (drive_membership_grants) quando o vínculo com a iniciativa termina, ou por pedido avulso da gestão. Executada pela EF revoke-drive-permission (a mesma da ADR-0107). Sem dado pessoal próprio: o e-mail fica na concessão.';

-- No máximo um item aberto por concessão.
CREATE UNIQUE INDEX IF NOT EXISTS drive_membership_revocations_open_uidx
  ON public.drive_membership_revocations (grant_id) WHERE status IN ('pending','approved');
CREATE INDEX IF NOT EXISTS drive_membership_revocations_status_idx ON public.drive_membership_revocations (status);
CREATE INDEX IF NOT EXISTS drive_membership_revocations_member_idx ON public.drive_membership_revocations (member_id);

ALTER TABLE public.drive_membership_revocations ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS drive_membership_revocations_deny_all ON public.drive_membership_revocations;
CREATE POLICY drive_membership_revocations_deny_all ON public.drive_membership_revocations
  AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
REVOKE ALL ON public.drive_membership_revocations FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.drive_membership_revocations TO service_role;

-- ── 6. A chave, desligada ──
INSERT INTO public.site_config (key, value)
VALUES ('drive_membership_revoke_enabled', 'false'::jsonb)
ON CONFLICT (key) DO NOTHING;

-- ── 3. O predicado do roster, num lugar só ──
-- Fica com acesso quem get_initiative_drive_roster põe no roster: vínculo ativo NAQUELA iniciativa e membro ativo.
-- Uma segunda via de vínculo ativo na mesma iniciativa basta, e é o caso que o guard afirma.
CREATE OR REPLACE FUNCTION public._drive_grant_keeps_access(p_person_id uuid, p_initiative_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT EXISTS (
    SELECT 1 FROM public.engagements e
    JOIN public.members m ON m.person_id = e.person_id
    WHERE e.person_id = p_person_id AND e.initiative_id = p_initiative_id AND e.status = 'active'
      AND m.member_status = 'active'
  );
$function$;
REVOKE ALL ON FUNCTION public._drive_grant_keeps_access(uuid, uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._drive_grant_keeps_access(uuid, uuid) TO service_role;

CREATE OR REPLACE FUNCTION public.enqueue_membership_drive_revocations()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  c_notice      constant interval := interval '7 days';
  v_cfg         jsonb;
  v_on          boolean;
  v_backfilled  int := 0;
  v_cancelled   int := 0;
  v_queued      int := 0;
  v_notified    int := 0;
  v_approved    int := 0;
  v_ids         uuid[];
  r             record;
BEGIN
  -- pg_cron chama por SQL, sem JWT: aceita o cron e o service_role, recusa usuário REST (ADR-0028 p89).
  IF public._request_is_rest_caller() THEN
    RAISE EXCEPTION 'service-role or cron only';
  END IF;

  SELECT value INTO v_cfg FROM public.site_config WHERE key = 'drive_membership_revoke_enabled';
  -- chave ausente = desligada
  v_on := coalesce(v_cfg, 'false'::jsonb) IS NOT DISTINCT FROM 'true'::jsonb;

  -- a. a trilha de desligamento já revogou a mesma permissão depois do último envio desta concessão
  WITH done AS (
    UPDATE public.drive_membership_grants g
       SET status = 'revoked', revoked_at = a.revoked_at, revoked_by = a.approved_by,
           revoked_via = 'offboarding_audit', updated_at = now()
      FROM public.drive_offboarding_audit a
     WHERE g.status = 'granted'
       AND a.drive_file_id = g.drive_folder_id AND a.permission_id = g.permission_id
       AND a.status IN ('revoked','already_absent') AND a.revoked_at IS NOT NULL
       AND a.revoked_at > coalesce(g.last_dispatched_at, g.granted_at)
    RETURNING g.id
  )
  SELECT count(*) INTO v_backfilled FROM done;

  -- b. o item aberto que deixou de valer
  WITH c AS (
    UPDATE public.drive_membership_revocations q
       SET status = 'cancelled', cancelled_at = now(), updated_at = now(),
           cancel_reason = CASE
             WHEN g.status IS DISTINCT FROM 'granted' THEN 'grant_closed'
             WHEN EXISTS (SELECT 1 FROM public.drive_offboarding_audit a
                          WHERE a.drive_file_id = g.drive_folder_id AND a.permission_id = g.permission_id
                            AND a.status IN ('pending_revoke','approved')) THEN 'offboarding_lane'
             WHEN coalesce(public.can_by_member(q.member_id, 'manage_platform'), false) THEN 'manage_platform_exception'
             ELSE 'engagement_restored' END
      FROM public.drive_membership_grants g
     WHERE g.id = q.grant_id AND q.status IN ('pending','approved')
       AND ( g.status IS DISTINCT FROM 'granted'
          OR ( q.reason = 'engagement_ended'
               AND ( public._drive_grant_keeps_access(g.grantee_person_id, g.initiative_id)
                  OR coalesce(public.can_by_member(q.member_id, 'manage_platform'), false)
                  OR EXISTS (SELECT 1 FROM public.drive_offboarding_audit a
                             WHERE a.drive_file_id = g.drive_folder_id AND a.permission_id = g.permission_id
                               AND a.status IN ('pending_revoke','approved')) ) ) )
    RETURNING q.id
  )
  SELECT count(*) INTO v_cancelled FROM c;

  -- c. entra na fila a concessão cuja pessoa saiu do roster da iniciativa
  WITH ins AS (
    INSERT INTO public.drive_membership_revocations (grant_id, initiative_id, member_id, reason, is_confidential)
    SELECT g.id, g.initiative_id, g.grantee_member_id, 'engagement_ended', (i.visibility = 'confidential')
      FROM public.drive_membership_grants g
      JOIN public.initiatives i ON i.id = g.initiative_id
     WHERE g.status = 'granted' AND g.permission_id IS NOT NULL
       AND NOT public._drive_grant_keeps_access(g.grantee_person_id, g.initiative_id)
       -- exceção nomeada (GP, 22/11/2026): quem tem manage_platform vê a iniciativa confidencial pela ADR-0105
       AND NOT coalesce(public.can_by_member(g.grantee_member_id, 'manage_platform'), true)
       -- já tem item aberto, falhou (vai à tela, e repetir só reavisaria) ou a gestão decidiu manter
       AND NOT EXISTS (SELECT 1 FROM public.drive_membership_revocations x
                       WHERE x.grant_id = g.id
                         AND (x.status IN ('pending','approved','failed') OR x.cancel_reason = 'management_kept'))
       -- a trilha de desligamento já tem a mesma permissão aberta
       AND NOT EXISTS (SELECT 1 FROM public.drive_offboarding_audit a
                       WHERE a.drive_file_id = g.drive_folder_id AND a.permission_id = g.permission_id
                         AND a.status IN ('pending_revoke','approved'))
    ON CONFLICT DO NOTHING
    RETURNING id
  )
  SELECT count(*) INTO v_queued FROM ins;

  IF v_on THEN
    -- d. o aviso e o prazo. Item segurado não é avisado até soltar.
    FOR r IN
      SELECT x.id, x.member_id, x.is_confidential, i.title
        FROM public.drive_membership_revocations x
        JOIN public.initiatives i ON i.id = x.initiative_id
       WHERE x.status = 'pending' AND x.reason = 'engagement_ended'
         AND x.notified_at IS NULL AND x.held_at IS NULL
       FOR UPDATE OF x
    LOOP
      UPDATE public.drive_membership_revocations
         SET notified_at = now(),
             due_at = CASE WHEN r.is_confidential THEN now() ELSE now() + c_notice END,
             updated_at = now()
       WHERE id = r.id;
      IF r.member_id IS NOT NULL THEN
        PERFORM public.create_notification(
          p_recipient_id => r.member_id,
          p_type         => 'drive_access_revocation_scheduled'::text,
          p_title        => CASE WHEN r.is_confidential
                              THEN 'Seu acesso à pasta de ' || r.title || ' no Drive foi encerrado'
                              ELSE 'Seu acesso à pasta de ' || r.title || ' no Drive termina em 7 dias' END,
          p_body         => CASE WHEN r.is_confidential
                              THEN 'Seu vínculo com ' || r.title || ' terminou, e o acesso à pasta dela no Drive sai hoje. Se for engano, fale com a gestão do Núcleo.'
                              ELSE 'Seu vínculo com ' || r.title || ' terminou, então o acesso à pasta dela no Drive será removido em '
                                   || to_char((now() + c_notice) AT TIME ZONE 'America/Sao_Paulo', 'DD/MM/YYYY')
                                   || '. Se você continua na iniciativa, fale com a liderança dela ou com a gestão do Núcleo antes dessa data.' END,
          p_link         => NULL::text,
          p_source_type  => 'drive_membership_revocations'::text,
          p_source_id    => r.id);
      END IF;
      v_notified := v_notified + 1;
    END LOOP;

    -- e. vencido, avisado e não segurado: aprova, conferindo a condição de novo no próprio UPDATE
    WITH ap AS (
      UPDATE public.drive_membership_revocations x
         SET status = 'approved', approval_mode = 'auto', approved_at = now(), updated_at = now()
        FROM public.drive_membership_grants g
       WHERE g.id = x.grant_id AND x.status = 'pending' AND x.reason = 'engagement_ended'
         AND x.held_at IS NULL AND x.notified_at IS NOT NULL AND x.due_at <= now()
         AND g.status = 'granted'
         AND NOT public._drive_grant_keeps_access(g.grantee_person_id, g.initiative_id)
         AND NOT coalesce(public.can_by_member(g.grantee_member_id, 'manage_platform'), true)
      RETURNING x.id
    )
    SELECT array_agg(id) INTO v_ids FROM ap;
    v_approved := coalesce(cardinality(v_ids), 0);
  END IF;

  IF v_backfilled + v_cancelled + v_queued + v_notified + v_approved > 0 THEN
    INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
    VALUES (NULL, 'drive_membership_revocation_cycle', 'drive_membership_revocations', NULL, '{}'::jsonb,
            jsonb_build_object('enabled', v_on, 'ledger_aligned', v_backfilled, 'cancelled', v_cancelled,
                               'queued', v_queued, 'notified', v_notified, 'auto_approved', v_approved,
                               'approved_ids', to_jsonb(coalesce(v_ids, ARRAY[]::uuid[]))));
  END IF;

  RETURN jsonb_build_object('enabled', v_on, 'ledger_aligned', v_backfilled, 'cancelled', v_cancelled,
                            'queued', v_queued, 'notified', v_notified, 'auto_approved', v_approved);
END;
$function$;
REVOKE ALL ON FUNCTION public.enqueue_membership_drive_revocations() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.enqueue_membership_drive_revocations() TO service_role;

-- ── 4. O executor da ADR-0107, sem mudar a EF ──
-- A EF revoke-drive-permission recebe um id, lê a linha por get_drive_revocation_row, só age em status 'approved',
-- apaga a permissão e grava o resultado por mark_drive_revocation_done. As duas passam a achar também o item da fila
-- nova pelo mesmo id (uuid, sem colisão entre as tabelas). O ramo de drive_offboarding_audit fica byte a byte o da
-- captura 20260805000262 (md5 vivo conferido em 22/11/2026).
CREATE OR REPLACE FUNCTION public.get_drive_revocation_row(p_audit_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public','pg_temp'
AS $$
DECLARE v_row public.drive_offboarding_audit; v_m record;
BEGIN
  IF public.current_caller_role() IS DISTINCT FROM 'service_role' THEN RAISE EXCEPTION 'service-role only'; END IF;
  SELECT * INTO v_row FROM public.drive_offboarding_audit WHERE id=p_audit_id;
  IF v_row.id IS NOT NULL THEN
    RETURN jsonb_build_object(
      'id', v_row.id, 'status', v_row.status, 'drive_file_id', v_row.drive_file_id,
      'permission_id', v_row.permission_id, 'permission_email', v_row.permission_email::text,
      'is_shared_drive', v_row.is_shared_drive, 'approved_by', v_row.approved_by);
  END IF;

  -- #3147: item da fila de fim de vínculo. A concessão que já não está 'granted' devolve outro status, e a EF não age.
  SELECT r.id, CASE WHEN g.status = 'granted' THEN r.status ELSE 'grant_' || g.status END AS status,
         g.drive_folder_id, g.permission_id, g.permission_email, r.approved_by
    INTO v_m
    FROM public.drive_membership_revocations r
    JOIN public.drive_membership_grants g ON g.id = r.grant_id
   WHERE r.id = p_audit_id;
  IF v_m.id IS NULL THEN RETURN NULL; END IF;
  RETURN jsonb_build_object(
    'id', v_m.id, 'status', v_m.status, 'drive_file_id', v_m.drive_folder_id,
    'permission_id', v_m.permission_id, 'permission_email', v_m.permission_email::text,
    'is_shared_drive', NULL, 'approved_by', v_m.approved_by, 'queue', 'membership');
END;
$$;

CREATE OR REPLACE FUNCTION public.mark_drive_revocation_done(p_audit_id uuid, p_status text, p_google_error jsonb DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public','pg_temp'
AS $$
DECLARE v_row public.drive_offboarding_audit; v_rev public.drive_membership_revocations;
BEGIN
  IF public.current_caller_role() IS DISTINCT FROM 'service_role' THEN RAISE EXCEPTION 'service-role only'; END IF;
  IF p_status NOT IN ('revoked','already_absent','failed') THEN
    RAISE EXCEPTION 'invalid terminal status: %', p_status;
  END IF;

  -- Idempotency guard: act only on a still-open row, so a concurrent caller (synchronous MCP approve +
  -- the drain cron) cannot overwrite an already-terminal outcome with a different status.
  UPDATE public.drive_offboarding_audit
     SET status = p_status,
         google_error = p_google_error,
         revoked_at = CASE WHEN p_status IN ('revoked','already_absent') THEN now() ELSE revoked_at END,
         updated_at = now()
   WHERE id = p_audit_id AND status IN ('approved','pending_revoke')
   RETURNING * INTO v_row;

  IF v_row.id IS NULL THEN
    -- #3147: item da fila de fim de vínculo. Só o aprovado chega ao fim; a concessão vira 'revoked' na mesma transação.
    UPDATE public.drive_membership_revocations
       SET status = p_status,
           google_error = p_google_error,
           revoked_at = CASE WHEN p_status IN ('revoked','already_absent') THEN now() ELSE revoked_at END,
           updated_at = now()
     WHERE id = p_audit_id AND status = 'approved'
     RETURNING * INTO v_rev;
    IF v_rev.id IS NOT NULL THEN
      IF p_status IN ('revoked','already_absent') THEN
        UPDATE public.drive_membership_grants
           SET status = 'revoked', revoked_at = now(), revoked_by = v_rev.approved_by,
               revoked_via = 'membership_queue', updated_at = now()
         WHERE id = v_rev.grant_id AND status = 'granted';
        INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
        VALUES (v_rev.approved_by, 'drive_membership_access_revoked', 'drive_membership_revocations', v_rev.id,
                jsonb_build_object('status_after', p_status),
                jsonb_build_object('grant_id', v_rev.grant_id, 'initiative_id', v_rev.initiative_id,
                                   'member_id', v_rev.member_id, 'reason', v_rev.reason,
                                   'approval_mode', v_rev.approval_mode));
      END IF;
      RETURN jsonb_build_object('audit_id', v_rev.id, 'status', v_rev.status, 'queue', 'membership');
    END IF;
    SELECT * INTO v_rev FROM public.drive_membership_revocations WHERE id = p_audit_id;
    IF v_rev.id IS NOT NULL THEN
      RETURN jsonb_build_object('audit_id', v_rev.id, 'status', v_rev.status, 'noop', true, 'queue', 'membership');
    END IF;

    -- already terminal or missing → graceful no-op (no overwrite, no spurious audit row)
    SELECT * INTO v_row FROM public.drive_offboarding_audit WHERE id = p_audit_id;
    IF v_row.id IS NULL THEN RAISE EXCEPTION 'Audit row % not found', p_audit_id; END IF;
    RETURN jsonb_build_object('audit_id', v_row.id, 'status', v_row.status, 'noop', true);
  END IF;

  IF p_status IN ('revoked','already_absent') THEN
    INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
    VALUES (v_row.approved_by, 'drive_permission_revoked', 'drive_offboarding_audit', v_row.id,
            jsonb_build_object('status_after', p_status),
            jsonb_build_object('drive_file_id', v_row.drive_file_id, 'permission_id', v_row.permission_id,
                               'member_id', v_row.member_id));
  END IF;

  RETURN jsonb_build_object('audit_id', v_row.id, 'status', v_row.status);
END;
$$;

REVOKE ALL ON FUNCTION public.get_drive_revocation_row(uuid) FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.get_drive_revocation_row(uuid) TO service_role;
REVOKE ALL ON FUNCTION public.mark_drive_revocation_done(uuid,text,jsonb) FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.mark_drive_revocation_done(uuid,text,jsonb) TO service_role;

-- ── 5. A tela da gestão (manage_platform) ──
-- As duas filas numa leitura: a de fim de vínculo, com a iniciativa e o motivo, confidencial primeiro; e a de
-- desligamento (drive_offboarding_audit) aberta ou falha, para nada ficar parado sem aparecer.
CREATE OR REPLACE FUNCTION public.admin_list_drive_revocation_queue(p_include_closed boolean DEFAULT false)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_rows jsonb;
  v_offb jsonb;
  v_ids uuid[];
  v_cfg jsonb;
BEGIN
  v_caller_id := (SELECT id FROM public.members WHERE auth_id = auth.uid());
  IF v_caller_id IS NULL OR NOT public.can_by_member(v_caller_id, 'manage_platform') THEN
    RAISE EXCEPTION 'Unauthorized: GP only (manage_platform)';
  END IF;
  SELECT value INTO v_cfg FROM public.site_config WHERE key = 'drive_membership_revoke_enabled';

  SELECT coalesce(jsonb_agg(to_jsonb(q) ORDER BY q.is_confidential DESC, q.ord, q.due_at NULLS LAST, q.detected_at), '[]'::jsonb),
         coalesce(array_agg(DISTINCT q.member_id) FILTER (WHERE q.member_id IS NOT NULL), ARRAY[]::uuid[])
    INTO v_rows, v_ids
    FROM (
      SELECT r.id, r.grant_id, r.initiative_id, i.title AS initiative_title, r.is_confidential,
             r.member_id, m.name AS member_name, m.member_status, g.permission_email::text AS permission_email,
             g.drive_folder_url, r.reason, r.status, r.detected_at, r.notified_at, r.due_at,
             r.held_at, r.hold_note, r.approval_mode, r.approved_at, r.revoked_at, r.google_error,
             r.cancel_reason, r.cancelled_at, r.note,
             CASE r.status WHEN 'failed' THEN 0 WHEN 'approved' THEN 1 WHEN 'pending' THEN 2 ELSE 3 END AS ord
        FROM public.drive_membership_revocations r
        JOIN public.drive_membership_grants g ON g.id = r.grant_id
        JOIN public.initiatives i ON i.id = r.initiative_id
        LEFT JOIN public.members m ON m.id = r.member_id
       WHERE (p_include_closed OR r.status IN ('pending','approved','failed'))
         AND public.rls_can_see_initiative(r.initiative_id)
       ORDER BY r.detected_at DESC
       LIMIT 500
    ) q;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'id', a.id, 'member_id', a.member_id, 'member_name', m.name, 'member_status', m.member_status,
           'permission_email', a.permission_email::text, 'drive_file_name', a.drive_file_name,
           'drive_file_url', a.drive_file_url, 'status', a.status, 'approval_mode', a.approval_mode,
           'google_error', a.google_error, 'detected_at', a.detected_at, 'approved_at', a.approved_at
         ) ORDER BY a.detected_at), '[]'::jsonb),
         v_ids || coalesce(array_agg(DISTINCT a.member_id), ARRAY[]::uuid[])
    INTO v_offb, v_ids
    FROM public.drive_offboarding_audit a
    JOIN public.members m ON m.id = a.member_id
   WHERE a.status IN ('pending_revoke','approved','failed');

  IF cardinality(v_ids) > 0 THEN
    PERFORM public.log_pii_access_batch(v_ids, ARRAY['email'], 'admin_list_drive_revocation_queue',
      'GP review of Drive revocation queues (#3147 end of initiative engagement + ADR-0107 offboarding)');
  END IF;

  RETURN jsonb_build_object(
    'enabled', coalesce(v_cfg, 'false'::jsonb) IS NOT DISTINCT FROM 'true'::jsonb,
    'notice_days', 7,
    'rows', v_rows,
    'offboarding_open', v_offb,
    'summary', jsonb_build_object(
      'pending',  (SELECT count(*) FROM jsonb_array_elements(v_rows) x WHERE x->>'status' = 'pending' AND x->>'held_at' IS NULL),
      'held',     (SELECT count(*) FROM jsonb_array_elements(v_rows) x WHERE x->>'status' = 'pending' AND x->>'held_at' IS NOT NULL),
      'approved', (SELECT count(*) FROM jsonb_array_elements(v_rows) x WHERE x->>'status' = 'approved'),
      'failed',   (SELECT count(*) FROM jsonb_array_elements(v_rows) x WHERE x->>'status' = 'failed'),
      'confidential_open', (SELECT count(*) FROM jsonb_array_elements(v_rows) x
                            WHERE (x->>'is_confidential')::boolean AND x->>'status' IN ('pending','approved')),
      'offboarding_open', jsonb_array_length(v_offb)));
END;
$function$;
REVOKE ALL ON FUNCTION public.admin_list_drive_revocation_queue(boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_list_drive_revocation_queue(boolean) TO authenticated, service_role;

-- Segurar (o item fica na fila, sem aviso nem aprovação automática) ou soltar.
CREATE OR REPLACE FUNCTION public.admin_hold_drive_revocation(p_revocation_id uuid, p_hold boolean, p_note text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_caller_id uuid; v_rev public.drive_membership_revocations;
BEGIN
  v_caller_id := (SELECT id FROM public.members WHERE auth_id = auth.uid());
  IF v_caller_id IS NULL OR NOT public.can_by_member(v_caller_id, 'manage_platform') THEN
    RAISE EXCEPTION 'Unauthorized: GP only (manage_platform)';
  END IF;
  IF p_hold AND nullif(btrim(coalesce(p_note, '')), '') IS NULL THEN
    RAISE EXCEPTION 'Segurar pede um motivo';
  END IF;
  UPDATE public.drive_membership_revocations
     SET held_at = CASE WHEN p_hold THEN now() END,
         held_by = CASE WHEN p_hold THEN v_caller_id END,
         hold_note = CASE WHEN p_hold THEN btrim(p_note) END,
         updated_at = now()
   WHERE id = p_revocation_id AND status = 'pending'
   RETURNING * INTO v_rev;
  IF v_rev.id IS NULL THEN RAISE EXCEPTION 'Item % não está pendente', p_revocation_id; END IF;
  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
  VALUES (v_caller_id, CASE WHEN p_hold THEN 'drive_membership_revocation_held' ELSE 'drive_membership_revocation_released' END,
          'drive_membership_revocations', v_rev.id, jsonb_build_object('held', p_hold),
          jsonb_build_object('note', v_rev.hold_note, 'grant_id', v_rev.grant_id));
  RETURN jsonb_build_object('id', v_rev.id, 'status', v_rev.status, 'held', p_hold);
END;
$function$;
REVOKE ALL ON FUNCTION public.admin_hold_drive_revocation(uuid, boolean, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_hold_drive_revocation(uuid, boolean, text) TO authenticated, service_role;

-- Desfazer: a gestão decide manter o acesso desta concessão. O ciclo não põe a mesma concessão na fila de novo.
CREATE OR REPLACE FUNCTION public.admin_cancel_drive_revocation(p_revocation_id uuid, p_note text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_caller_id uuid; v_rev public.drive_membership_revocations;
BEGIN
  v_caller_id := (SELECT id FROM public.members WHERE auth_id = auth.uid());
  IF v_caller_id IS NULL OR NOT public.can_by_member(v_caller_id, 'manage_platform') THEN
    RAISE EXCEPTION 'Unauthorized: GP only (manage_platform)';
  END IF;
  IF nullif(btrim(coalesce(p_note, '')), '') IS NULL THEN
    RAISE EXCEPTION 'Desfazer pede um motivo';
  END IF;
  -- o aprovado ainda pode ser desfeito até a EF agir: ela relê o status e só age em 'approved'
  UPDATE public.drive_membership_revocations
     SET status = 'cancelled', cancel_reason = 'management_kept', cancelled_at = now(),
         cancelled_by = v_caller_id, note = btrim(p_note), updated_at = now()
   WHERE id = p_revocation_id AND status IN ('pending','approved')
   RETURNING * INTO v_rev;
  IF v_rev.id IS NULL THEN RAISE EXCEPTION 'Item % não está aberto', p_revocation_id; END IF;
  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
  VALUES (v_caller_id, 'drive_membership_revocation_cancelled', 'drive_membership_revocations', v_rev.id,
          jsonb_build_object('status_after', 'cancelled', 'cancel_reason', 'management_kept'),
          jsonb_build_object('note', v_rev.note, 'grant_id', v_rev.grant_id));
  RETURN jsonb_build_object('id', v_rev.id, 'status', v_rev.status);
END;
$function$;
REVOKE ALL ON FUNCTION public.admin_cancel_drive_revocation(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_cancel_drive_revocation(uuid, text) TO authenticated, service_role;

-- Aprovar já: a gestão executa antes do prazo (a primeira lista, o item confidencial). A EF roda pelo dreno, em até 1 h.
CREATE OR REPLACE FUNCTION public.admin_approve_drive_membership_revocation(p_revocation_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_caller_id uuid; v_rev public.drive_membership_revocations;
BEGIN
  v_caller_id := (SELECT id FROM public.members WHERE auth_id = auth.uid());
  IF v_caller_id IS NULL OR NOT public.can_by_member(v_caller_id, 'manage_platform') THEN
    RAISE EXCEPTION 'Unauthorized: GP only (manage_platform)';
  END IF;
  UPDATE public.drive_membership_revocations
     SET status = 'approved', approval_mode = 'manual', approved_by = v_caller_id, approved_at = now(),
         held_at = NULL, held_by = NULL, hold_note = NULL, updated_at = now()
   WHERE id = p_revocation_id AND status = 'pending'
   RETURNING * INTO v_rev;
  IF v_rev.id IS NULL THEN RAISE EXCEPTION 'Item % não está pendente', p_revocation_id; END IF;
  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
  VALUES (v_caller_id, 'drive_membership_revocation_approved', 'drive_membership_revocations', v_rev.id,
          jsonb_build_object('status_after', 'approved', 'approval_mode', 'manual'),
          jsonb_build_object('grant_id', v_rev.grant_id, 'reason', v_rev.reason));
  RETURN jsonb_build_object('id', v_rev.id, 'status', v_rev.status);
END;
$function$;
REVOKE ALL ON FUNCTION public.admin_approve_drive_membership_revocation(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_approve_drive_membership_revocation(uuid) TO authenticated, service_role;

-- Revogação avulsa: a gestão revoga uma concessão viva, de membro ativo ou não, fora do ciclo. Entra aprovada.
-- Um item aberto da mesma concessão é aprovado em vez de duplicado.
CREATE OR REPLACE FUNCTION public.admin_request_drive_revocation(p_grant_id uuid, p_note text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_caller_id uuid; v_g public.drive_membership_grants; v_rev public.drive_membership_revocations; v_conf boolean;
BEGIN
  v_caller_id := (SELECT id FROM public.members WHERE auth_id = auth.uid());
  IF v_caller_id IS NULL OR NOT public.can_by_member(v_caller_id, 'manage_platform') THEN
    RAISE EXCEPTION 'Unauthorized: GP only (manage_platform)';
  END IF;
  IF nullif(btrim(coalesce(p_note, '')), '') IS NULL THEN
    RAISE EXCEPTION 'A revogação avulsa pede um motivo';
  END IF;
  SELECT * INTO v_g FROM public.drive_membership_grants WHERE id = p_grant_id FOR UPDATE;
  IF v_g.id IS NULL THEN RAISE EXCEPTION 'Concessão % não encontrada', p_grant_id; END IF;
  IF v_g.status <> 'granted' OR v_g.permission_id IS NULL THEN
    RAISE EXCEPTION 'Concessão % não está ativa (status %)', p_grant_id, v_g.status;
  END IF;
  SELECT (i.visibility = 'confidential') INTO v_conf FROM public.initiatives i WHERE i.id = v_g.initiative_id;

  UPDATE public.drive_membership_revocations
     SET status = 'approved', approval_mode = 'manual', approved_by = v_caller_id, approved_at = now(),
         held_at = NULL, held_by = NULL, hold_note = NULL,
         note = btrim(p_note), updated_at = now()
   WHERE grant_id = p_grant_id AND status = 'pending'
   RETURNING * INTO v_rev;
  IF v_rev.id IS NULL THEN
    SELECT * INTO v_rev FROM public.drive_membership_revocations WHERE grant_id = p_grant_id AND status = 'approved';
  END IF;
  IF v_rev.id IS NULL THEN
    INSERT INTO public.drive_membership_revocations
      (grant_id, initiative_id, member_id, reason, is_confidential, status, approval_mode, approved_by, approved_at, note)
    VALUES (v_g.id, v_g.initiative_id, v_g.grantee_member_id, 'manual', coalesce(v_conf, false),
            'approved', 'manual', v_caller_id, now(), btrim(p_note))
    RETURNING * INTO v_rev;
  END IF;
  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
  VALUES (v_caller_id, 'drive_membership_revocation_requested', 'drive_membership_revocations', v_rev.id,
          jsonb_build_object('status_after', v_rev.status, 'reason', v_rev.reason),
          jsonb_build_object('grant_id', v_g.id, 'note', btrim(p_note)));
  RETURN jsonb_build_object('id', v_rev.id, 'status', v_rev.status, 'reason', v_rev.reason);
END;
$function$;
REVOKE ALL ON FUNCTION public.admin_request_drive_revocation(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_request_drive_revocation(uuid, text) TO authenticated, service_role;

-- ── Os crons ──
-- O ciclo, de hora em hora no minuto 50: o aprovado ali passa dos 5 minutos do dreno do minuto 7 seguinte.
SELECT cron.schedule('membership-drive-revocation-queue-hourly', '50 * * * *',
  $cron$ SELECT public.enqueue_membership_drive_revocations(); $cron$);

-- O dreno de sempre (cron 64, ADR-0107), agora com as duas filas. Mesmo nome, então substitui o comando.
SELECT cron.schedule('revoke-drive-drain-hourly', '7 * * * *', $cron$
  DO $drain$
  DECLARE r record;
  BEGIN
    FOR r IN
      SELECT q.id FROM (
        SELECT id, approved_at FROM public.drive_offboarding_audit
         WHERE status = 'approved' AND approved_at < now() - interval '5 minutes'
        UNION ALL
        SELECT id, approved_at FROM public.drive_membership_revocations
         WHERE status = 'approved' AND approved_at < now() - interval '5 minutes'
      ) q
      ORDER BY q.approved_at
      LIMIT 50
    LOOP
      PERFORM net.http_post(
        url := 'https://ldrfrvwhxsmgaabwmaik.supabase.co/functions/v1/revoke-drive-permission',
        body := jsonb_build_object('audit_id', r.id),
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'Authorization', 'Bearer ' || (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1)
        ),
        timeout_milliseconds := 30000
      );
    END LOOP;
  END
  $drain$;
$cron$);


-- ── 7. O aviso novo é imediato ──
-- Corpo gerado da captura 20261107121211_alerta_de_divergencia_do_piloto.sql (md5 vivo conferido em 22/11/2026), com uma linha a mais.
CREATE OR REPLACE FUNCTION public._delivery_mode_for(p_type text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
  SELECT CASE p_type
    -- PR-2 (email audit): the per-signing leadership alert is now in-app only; the daily
    -- digest (volunteer_term_signed_digest) carries the single aggregated email.
    WHEN 'volunteer_agreement_signed'    THEN 'suppress'
    WHEN 'volunteer_term_signed_digest'  THEN 'transactional_immediate'
    WHEN 'ip_ratification_gate_pending'  THEN 'transactional_immediate'
    WHEN 'system_alert'                  THEN 'transactional_immediate'
    -- #1169: ready is redundant with issued at the email layer (issued carries the single email);
    -- kept in-app only. Every ready-cert already fired an issued email (0 ready-without-issued/60d).
    WHEN 'certificate_ready'             THEN 'suppress'
    WHEN 'certificate_issued'            THEN 'transactional_immediate'
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
    -- #2325 (2026-09-16): o LEMBRETE de que o termo segue aberto. Tipo proprio, separado de
    -- `selection_termo_due` (que anuncia a ABERTURA, no aceite do VEP, e e alvo de replay).
    -- Nasceu porque a cobranca saia como `system`, que o catalogo manda suprimir: 26 avisos a
    -- 16 pessoas que nunca deixaram a plataforma. Catalogado de proposito em vez de cair no
    -- ELSE: o ELSE e `digest_weekly`, que carimba como entregue o que nao renderiza (#2286).
    WHEN 'volunteer_term_pending'        THEN 'transactional_immediate'
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
    -- #2013 (2026-08-26): o teto de lembretes de reagendamento foi atingido e o caso vira
    -- trabalho de gente. Imediato de proposito: e o unico aviso, e o digest semanal so
    -- entrega a quem tem OUTRO conteudo na semana (#2010).
    WHEN 'selection_reschedule_escalated' THEN 'transactional_immediate'
    -- #186 (2026-06-05): curation committee broadcast when an item enters curation_pending
    WHEN 'curation_item_submitted'       THEN 'transactional_immediate'
    WHEN 'engagement_renewal_d30'        THEN 'digest_weekly'
    WHEN 'engagement_renewal_d60_gp_aggregate' THEN 'digest_weekly'
    -- #625 F3 (2026-06-11): radar de renovação de filiação
    WHEN 'affiliation_renewal_d7_urgent'  THEN 'transactional_immediate'
    WHEN 'affiliation_renewal_d30'        THEN 'digest_weekly'
    WHEN 'affiliation_verification_stale' THEN 'digest_weekly'
    -- #1855 (2026-08-18): faixa de filiacao ja VENCIDA. Catalogado de proposito, e nao deixado
    -- cair no ELSE, pelo mesmo motivo registrado no bloco 5b da #625: o ELSE e um default de
    -- conveniencia e um dia muda. digest_weekly porque o PM decidiu 'so lembrete, mesmo tom'.
    WHEN 'affiliation_renewal_expired'    THEN 'digest_weekly'
    -- #2152 (2026-09-03): a verificacao ficou atras do VEP. Vai para a diretoria, nao para o
    -- membro, e no mesmo modo da faixa irma de verificacao obsoleta: e trabalho de fila, nao
    -- urgencia. Catalogado em vez de cair no ELSE, pelo motivo registrado acima.
    WHEN 'affiliation_vep_divergence'     THEN 'digest_weekly'
    -- #1224 PR2 (2026-07-09): one-time onboarding nudge when the PMI enrichment cannot resolve
    -- an entry chapter (profile_private / no_fetch / not_affiliated / ambiguous-no-choice).
    WHEN 'entry_chapter_action_needed'    THEN 'transactional_immediate'
    -- #740 Wave 3c-i (B8): agreement rejected / reissued: member must re-sign, deliver immediately
    WHEN 'volunteer_agreement_rejected'  THEN 'transactional_immediate'
    WHEN 'volunteer_agreement_reissued'  THEN 'transactional_immediate'
    WHEN 'attendance_detractor'          THEN 'suppress'
    WHEN 'info'                          THEN 'suppress'
    WHEN 'system'                        THEN 'suppress'
    -- #2285 (2026-09-14): o detector de contas nao ligadas passou a ter cron. Catalogado de
    -- proposito, e nao deixado cair no ELSE, pelo mesmo motivo registrado acima para #625,
    -- #1855 e #2152. Aqui o ELSE e pior que um default inconveniente: digest_weekly monta as
    -- secoes por lista branca de tipos e carimba como entregue o que nao renderizou (#2286).
    -- #2580 C1 (2026-10-08): no sino na hora; o e-mail sai no resumo diario da gestao. `suppress` e nao
    -- digest_weekly: o resumo semanal so le digest_weekly, entao nao ha carimbo sem renderizar (#2286).
    WHEN 'unlinked_accounts_detected'     THEN 'suppress'
    -- #2580 C: o resumo diario da gestao e um e-mail proprio.
    WHEN 'management_daily_digest'        THEN 'transactional_immediate'
    -- #2444 (2026-09-24): rodizio de pareceristas da curadoria. Imediato de proposito: a
    -- designacao e o lembrete sao o que da dono ao parecer; o digest semanal chegaria depois do
    -- prazo de 7 dias. O vencido vai para quem gere a plataforma, tambem imediato: e decisao.
    WHEN 'curation_review_assigned'       THEN 'transactional_immediate'
    WHEN 'curation_review_overdue'        THEN 'transactional_immediate'
    -- #2496 (2026-09-27): aviso a tribo (participantes do card e lideranca da iniciativa) de que o
    -- item entrou em curadoria. Imediato de proposito: caia em card_moved (digest_weekly), com o
    -- codigo cru do status e link generico, e nenhuma das 3 pessoas da tribo recebeu e-mail.
    WHEN 'curation_submitted_to_tribe'    THEN 'transactional_immediate'
    -- #2621 (2026-10-09): a DECISAO da curadoria volta para a mesma audiencia do aviso de entrada
    -- (participantes do card e lideranca ativa da iniciativa). Imediatos de proposito: devolucao e
    -- rejeicao nao avisavam ninguem, e o primeiro parecer real da plataforma passou mudo; no ELSE
    -- (digest_weekly) o pedido de ajuste chegaria dias depois, com o prazo do autor correndo.
    WHEN 'curation_decision_returned'     THEN 'transactional_immediate'
    WHEN 'curation_decision_rejected'     THEN 'transactional_immediate'
    WHEN 'curation_decision_approved'     THEN 'transactional_immediate'
    -- #2495 (2026-09-27): piloto do wiki vivo (ADR-0129, emenda 2). Imediatos de proposito: a
    -- lideranca publica na hora e o comite audita em 14 dias; um aviso que chegasse no digest
    -- semanal comeria metade do prazo. O vencido vai para quem gere a plataforma.
    WHEN 'wiki_review_requested'          THEN 'transactional_immediate'
    WHEN 'wiki_page_decision'             THEN 'transactional_immediate'
    WHEN 'wiki_audit_requested'           THEN 'transactional_immediate'
    WHEN 'wiki_audit_overdue'             THEN 'transactional_immediate'
    -- #2495 fase B2 (2026-09-29): "Sugerir melhoria". Imediatos pelo mesmo motivo dos avisos do wiki
    -- acima: a sugestao vai a quem decide sobre a pagina, e a resposta volta a quem sugeriu; um aviso
    -- no digest semanal chegaria depois de a pessoa ter esquecido o que sugeriu.
    WHEN 'wiki_suggestion_received'       THEN 'transactional_immediate'
    WHEN 'wiki_suggestion_decision'       THEN 'transactional_immediate'
    -- #2444 (2026-09-24): a revisao do lider e a devolucao ao autor. Imediatos de proposito: caiam no
    -- ELSE (digest_weekly) e, medido, leader_review_requested nunca gerou uma linha sequer; sem aviso,
    -- 16 cards ficaram parados em leader_review desde maio.
    WHEN 'leader_review_requested'        THEN 'transactional_immediate'
    WHEN 'leader_review_returned'         THEN 'transactional_immediate'
    -- #2454 (2026-09-24): falha de acesso ao Drive. Imediatos: a pessoa esta sem acesso a pasta da
    -- iniciativa agora (e nao sabia: 3 casos medidos), e a falha da conta de servico e acao do
    -- administrador do Workspace.
    WHEN 'drive_access_action_needed'     THEN 'transactional_immediate'
    WHEN 'drive_access_admin_needed'      THEN 'transactional_immediate'
    -- #3147 (22/11/2026): o acesso à pasta da iniciativa vai sair (7 dias, ou o próprio ciclo em iniciativa
    -- confidencial). Imediato: a pessoa tem o prazo para dizer que continua, e no ELSE (digest_weekly) o e-mail
    -- chegaria no fim do prazo.
    WHEN 'drive_access_revocation_scheduled' THEN 'transactional_immediate'
    -- Varredura de dado pessoal no tracker publico (10/10/2026). Imediato de proposito: o dado segue publico
    -- enquanto ninguem age, e no ELSE (digest_weekly) o e-mail chegaria em ate sete dias.
    WHEN 'tracker_pii_found'              THEN 'transactional_immediate'
    -- #2593 (C2, decisão do GP 11/10/2026): o dono do bloco da Agenda Viva sabe pelo sino, não por e-mail, quando
    -- a coordenação confirma ou cancela o bloco dele. Catalogados para não cair no ELSE (digest_weekly), que
    -- mandaria um resumo semanal de algo que só serve na hora.
    WHEN 'agenda_block_confirmed'         THEN 'suppress'
    WHEN 'agenda_block_cancelled'         THEN 'suppress'
    -- #2593 (C3b, 16/10/2026): convidado externo de reunião próxima que ainda não recebeu o convite (sem e-mail,
    -- bloco reservado ou convite não entregue). No sino do dono e da coordenação; o cron repete a cada 2 dias
    -- enquanto durar. Catalogado para não cair no ELSE (digest_weekly), que chegaria depois da reunião.
    WHEN 'agenda_guest_attention'         THEN 'suppress'
    -- #2701 (16/10/2026): certificado revogado; o membro sabe pelo sino, com o motivo. Decisão do GP: sem e-mail.
    WHEN 'certificate_revoked'            THEN 'suppress'
    -- #2782 (24/10/2026): pedido de capítulo ou de organização pelo formulário da home, para quem gere a plataforma
    -- (manage_platform). Imediato de propósito: a home promete resposta em até 5 dias úteis, e no ELSE (digest_weekly)
    -- o aviso chegaria no sábado. O aviso não leva nome, e-mail, telefone nem a mensagem de quem pediu.
    WHEN 'partner_lead_received'          THEN 'transactional_immediate'
    -- #2393 fatia 3 (02/11/2026): candidaturas novas na vaga do líder. No sino na hora e no resumo de sábado,
    -- sem e-mail imediato: o líder age em dias (ADR-0134 §8), e o 1º lote de uma vaga não vira rajada.
    -- Explícito, e não deixado no ELSE, para o modo não mudar se o ELSE mudar. Sem nome de candidato.
    WHEN 'selection_opening_new_applications' THEN 'digest_weekly'
    WHEN 'selection_evaluator_assigned'       THEN 'transactional_immediate'  -- #2393 M2
    WHEN 'selection_pilot_divergence'         THEN 'transactional_immediate'  -- #2393, emenda de 06/11/2026 à ADR-0134 §4
    -- Onboarding, onda 0, PR-2 (#2891, 03/11/2026): os avisos do pedido de tribo e o de boas-vindas ao vinculo
    -- gravavam 'transactional_immediate' literal no proprio INSERT e caiam no ELSE (digest_weekly) para quem perguntasse
    -- ao catalogo. Catalogados com o modo que ja usam. tribe_request_expired e novo (#2888): quem pediu sabe na hora que
    -- o pedido passou do prazo e que isso nao e uma recusa.
    WHEN 'tribe_request'                  THEN 'transactional_immediate'
    WHEN 'tribe_request_reviewed'         THEN 'transactional_immediate'
    WHEN 'tribe_request_nudge'            THEN 'transactional_immediate'
    WHEN 'tribe_request_expired_gp'       THEN 'transactional_immediate'
    WHEN 'tribe_request_expired'          THEN 'transactional_immediate'
    WHEN 'engagement_welcome'             THEN 'transactional_immediate'
    -- Onda 0 PR-5 (#2890, 03/11/2026): a resposta ao convite de retorno, para quem gere a plataforma. O INSERT nao
    -- declarava o modo e caia no default da coluna (digest_weekly), que o resumo semanal renderiza no balde
    -- other_notifications (#2286). Catalogados com o mesmo modo, para nao depender do default nem do ELSE.
    WHEN 're_engagement_accepted'         THEN 'digest_weekly'
    WHEN 're_engagement_declined'         THEN 'digest_weekly'
    ELSE 'digest_weekly'
  END;
$function$;

NOTIFY pgrst, 'reload schema';
