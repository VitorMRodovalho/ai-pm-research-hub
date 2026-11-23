-- #3178 e #3179: a revogação por iniciativa passa a olhar a pasta, e o acesso à pasta de trabalho que não veio do
-- ledger vai para a revisão da gestão. Uma migration só, porque as duas mexem no executor (get_drive_revocation_row).
--
-- #3178 (pasta de trabalho de mais de uma iniciativa)
-- 1. _drive_grant_keeps_access ganha a pasta: fica com o acesso quem está no roster da iniciativa da concessão OU de
--    qualquer iniciativa ativa com vínculo de trabalho vivo naquela pasta (o mesmo "usa a pasta" de
--    get_membership_drive_targets). O predicado do roster é o mesmo: vínculo ativo e membro ativo. A versão de dois
--    argumentos sai no fim, para não sobrar um segundo predicado.
-- 2. Os chamadores passam a pasta da concessão: o ciclo (passos b, b2, c e e), o executor e o "aprovar já".
--
-- #3179 (acesso fora do ledger)
-- 3. drive_folder_access_findings: a permissão de usuário numa pasta de trabalho que não tem concessão viva no ledger e
--    cuja pessoa não fica com o acesso pelo predicado acima. Sem revogação automática, porque a origem é desconhecida:
--    a gestão revisa, mantém ou pede a revogação.
-- 4. record_drive_folder_acl: o reconcile manda a ACL lida da pasta, e a classificação é toda aqui, num lugar só. Fora
--    da revisão: o dono da pasta, quem não é usuário (grupo, domínio, link), a conta de serviço, quem tem concessão viva,
--    quem fica pelo roster e quem tem manage_platform (a exceção nomeada do GP). Abre o item novo, renova o visto e
--    fecha o que deixou de valer. Com p_dry_run só conta.
-- 5. O executor da ADR-0107 acha também o item aprovado desta revisão, e reconfere antes do Drive: concessão viva, roster
--    ou manage_platform devolvem stale_keeps_access. O dreno das :07 passa a drenar as três filas.
-- 6. A tela: admin_list_drive_folder_access_findings (leitura, manage_platform e rls_can_see_initiative) e
--    admin_review_drive_folder_access (manter, reabrir ou revogar, com motivo). Revogar recusa a permissão herdada da
--    pasta-mãe, que só sai lá.
--
-- A chave site_config.drive_membership_revoke_enabled não muda e não manda nesta revisão: registrar não tem efeito fora
-- do banco, e revogar é sempre uma ação da gestão, como a avulsa.

-- ── 1. Quem fica com o acesso olha a pasta (#3178) ──
CREATE OR REPLACE FUNCTION public._drive_grant_keeps_access(p_person_id uuid, p_initiative_id uuid, p_drive_folder_id text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT EXISTS (
    SELECT 1 FROM public.engagements e
    JOIN public.members m ON m.person_id = e.person_id
    WHERE e.person_id = p_person_id AND e.status = 'active' AND m.member_status = 'active'
      AND ( e.initiative_id = p_initiative_id
         OR EXISTS (SELECT 1 FROM public.initiative_drive_links l
                    JOIN public.initiatives i ON i.id = l.initiative_id
                    WHERE l.initiative_id = e.initiative_id AND l.drive_folder_id = p_drive_folder_id
                      AND l.link_purpose = 'workspace' AND l.unlinked_at IS NULL AND i.status = 'active') )
  );
$function$;
REVOKE ALL ON FUNCTION public._drive_grant_keeps_access(uuid, uuid, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._drive_grant_keeps_access(uuid, uuid, text) TO service_role;

-- ── 3. A revisão do acesso fora do ledger (#3179) ──
CREATE TABLE IF NOT EXISTS public.drive_folder_access_findings (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  drive_folder_id  text NOT NULL,
  permission_id    text NOT NULL,
  permission_email citext NOT NULL,
  permission_role  text,
  inherited        boolean,
  person_id        uuid REFERENCES public.persons(id) ON DELETE SET NULL,
  member_id        uuid REFERENCES public.members(id) ON DELETE SET NULL,
  status           text NOT NULL DEFAULT 'open'
                     CHECK (status IN ('open','kept','approved','revoked','already_absent','failed','closed')),
  first_seen_at    timestamptz NOT NULL DEFAULT now(),
  last_seen_at     timestamptz NOT NULL DEFAULT now(),
  reviewed_by      uuid REFERENCES public.members(id) ON DELETE SET NULL,
  reviewed_at      timestamptz,
  review_note      text,
  approved_by      uuid REFERENCES public.members(id) ON DELETE SET NULL,
  approved_at      timestamptz,
  revoked_at       timestamptz,
  google_error     jsonb,
  closed_at        timestamptz,
  close_reason     text CHECK (close_reason IN ('permission_gone','covered_by_grant','on_roster','manage_platform_exception')),
  created_at       timestamptz NOT NULL DEFAULT now(),
  updated_at       timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT dfaf_kept_has_review       CHECK (status <> 'kept' OR (reviewed_at IS NOT NULL AND review_note IS NOT NULL)),
  CONSTRAINT dfaf_approved_has_person   CHECK (status NOT IN ('approved','revoked','already_absent','failed')
                                               OR (approved_by IS NOT NULL AND approved_at IS NOT NULL)),
  CONSTRAINT dfaf_closed_has_reason     CHECK ((status = 'closed') = (close_reason IS NOT NULL AND closed_at IS NOT NULL)),
  CONSTRAINT dfaf_revoked_has_time      CHECK (status NOT IN ('revoked','already_absent') OR revoked_at IS NOT NULL)
);

COMMENT ON TABLE public.drive_folder_access_findings IS
  '#3179: permissão de usuário numa pasta de trabalho sem concessão viva no ledger e de quem não fica com o acesso pelo roster. Para a gestão revisar; nunca revogada sozinha. permission_email é dado pessoal (deny-all, leitura só por SECDEF).';

-- No máximo um item aberto por permissão da pasta.
CREATE UNIQUE INDEX IF NOT EXISTS drive_folder_access_findings_open_uidx
  ON public.drive_folder_access_findings (drive_folder_id, permission_id) WHERE status IN ('open','kept','approved','failed');
CREATE INDEX IF NOT EXISTS drive_folder_access_findings_status_idx ON public.drive_folder_access_findings (status);
CREATE INDEX IF NOT EXISTS drive_folder_access_findings_folder_idx ON public.drive_folder_access_findings (drive_folder_id);

ALTER TABLE public.drive_folder_access_findings ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS drive_folder_access_findings_deny_all ON public.drive_folder_access_findings;
CREATE POLICY drive_folder_access_findings_deny_all ON public.drive_folder_access_findings
  AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
REVOKE ALL ON public.drive_folder_access_findings FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.drive_folder_access_findings TO service_role;

-- ── 4. A ACL lida pelo reconcile, classificada aqui ──
-- p_permissions: a lista do Drive (id, type, role, emailAddress, deleted, inherited). p_ignore_emails: a conta de serviço.
CREATE OR REPLACE FUNCTION public.record_drive_folder_acl(p_drive_folder_id text, p_permissions jsonb,
                                                         p_ignore_emails text[] DEFAULT ARRAY[]::text[],
                                                         p_dry_run boolean DEFAULT false)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_cls     jsonb;
  v_counts  jsonb;
  v_new     int := 0;
  v_seen    int := 0;
  v_closed  int := 0;
  v_members uuid[];
BEGIN
  IF public.current_caller_role() IS DISTINCT FROM 'service_role' THEN RAISE EXCEPTION 'service-role only'; END IF;
  IF jsonb_typeof(p_permissions) IS DISTINCT FROM 'array' THEN RAISE EXCEPTION 'p_permissions must be a json array'; END IF;
  -- só a pasta de trabalho viva: a revisão não registra pasta que a plataforma não reconhece
  IF NOT EXISTS (SELECT 1 FROM public.initiative_drive_links l
                  WHERE l.drive_folder_id = p_drive_folder_id AND l.link_purpose = 'workspace' AND l.unlinked_at IS NULL) THEN
    RAISE EXCEPTION 'not an active workspace folder: %', p_drive_folder_id;
  END IF;

  -- a classificação, uma vez: cada permissão de usuário recebe um veredito
  WITH p AS (
    SELECT DISTINCT ON (x.id) x.id AS permission_id, lower(btrim(x."emailAddress")) AS email, x.role, x.inherited
      FROM jsonb_to_recordset(p_permissions) AS x(id text, type text, role text, "emailAddress" text,
                                                   deleted boolean, inherited boolean)
     WHERE x.type = 'user' AND coalesce(x.deleted, false) = false AND x.id IS NOT NULL
       AND nullif(btrim(x."emailAddress"), '') IS NOT NULL
       AND x.role IS DISTINCT FROM 'owner'
       AND lower(btrim(x."emailAddress")) NOT IN (SELECT lower(btrim(e)) FROM unnest(coalesce(p_ignore_emails, ARRAY[]::text[])) e
                                                  WHERE e IS NOT NULL)
     ORDER BY x.id
  ), who AS (
    SELECT p.*, mm.member_id, mm.person_id
      FROM p
      LEFT JOIN LATERAL (
        SELECT m.id AS member_id, m.person_id
          FROM public.members m
         WHERE lower(m.email) = p.email
            OR EXISTS (SELECT 1 FROM public.member_emails me WHERE me.member_id = m.id AND me.email = p.email::citext)
         ORDER BY (lower(m.email) = p.email) DESC, (m.member_status = 'active') DESC, m.id
         LIMIT 1) mm ON true
  )
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'permission_id', w.permission_id, 'email', w.email, 'role', w.role, 'inherited', w.inherited,
           'member_id', w.member_id, 'person_id', w.person_id,
           'verdict', CASE
             WHEN EXISTS (SELECT 1 FROM public.drive_membership_grants g
                           WHERE g.drive_folder_id = p_drive_folder_id AND g.permission_email = w.email::citext
                             AND g.status = 'granted') THEN 'covered_by_grant'
             WHEN w.person_id IS NOT NULL
              AND public._drive_grant_keeps_access(w.person_id, NULL, p_drive_folder_id) THEN 'on_roster'
             WHEN w.member_id IS NOT NULL
              AND coalesce(public.can_by_member(w.member_id, 'manage_platform'), false) THEN 'manage_platform_exception'
             ELSE 'finding' END)), '[]'::jsonb)
    INTO v_cls
    FROM who w;

  SELECT jsonb_build_object(
           'user_permissions', jsonb_array_length(v_cls),
           'findings',  count(*) FILTER (WHERE c.verdict = 'finding'),
           'findings_inherited', count(*) FILTER (WHERE c.verdict = 'finding' AND c.inherited IS TRUE),
           'covered_by_grant', count(*) FILTER (WHERE c.verdict = 'covered_by_grant'),
           'on_roster', count(*) FILTER (WHERE c.verdict = 'on_roster'),
           'manage_platform_exception', count(*) FILTER (WHERE c.verdict = 'manage_platform_exception'),
           'unknown_person', count(*) FILTER (WHERE c.verdict = 'finding' AND c.member_id IS NULL))
    INTO v_counts
    FROM jsonb_to_recordset(v_cls) AS c(permission_id text, verdict text, inherited boolean, member_id uuid);

  IF p_dry_run THEN
    RETURN v_counts || jsonb_build_object('dry_run', true, 'drive_folder_id', p_drive_folder_id);
  END IF;

  -- fecha o que deixou de valer: a permissão sumiu da pasta, ou o veredito mudou (concessão viva, roster, exceção).
  -- O item aprovado também fecha: o executor lê 'closed' e não age.
  WITH cur AS (
    SELECT c.permission_id, c.verdict
      FROM jsonb_to_recordset(v_cls) AS c(permission_id text, verdict text)
  ), cl AS (
    UPDATE public.drive_folder_access_findings f
       SET status = 'closed', closed_at = now(), updated_at = now(),
           close_reason = coalesce((SELECT cur.verdict FROM cur WHERE cur.permission_id = f.permission_id
                                     AND cur.verdict <> 'finding'), 'permission_gone')
     WHERE f.drive_folder_id = p_drive_folder_id
       AND f.status IN ('open','kept','approved','failed')
       AND NOT EXISTS (SELECT 1 FROM cur WHERE cur.permission_id = f.permission_id AND cur.verdict = 'finding')
    RETURNING f.id
  )
  SELECT count(*) INTO v_closed FROM cl;

  -- renova o visto do item que segue aberto
  WITH cur AS (
    SELECT c.* FROM jsonb_to_recordset(v_cls) AS c(permission_id text, email text, role text, inherited boolean,
                                                    member_id uuid, person_id uuid, verdict text)
     WHERE c.verdict = 'finding'
  ), up AS (
    UPDATE public.drive_folder_access_findings f
       SET last_seen_at = now(), updated_at = now(), permission_email = cur.email::citext,
           permission_role = cur.role, inherited = cur.inherited, member_id = cur.member_id, person_id = cur.person_id
      FROM cur
     WHERE f.drive_folder_id = p_drive_folder_id AND f.permission_id = cur.permission_id
       AND f.status IN ('open','kept','approved','failed')
    RETURNING f.id
  )
  SELECT count(*) INTO v_seen FROM up;

  -- abre o item novo
  WITH ins AS (
    INSERT INTO public.drive_folder_access_findings
      (drive_folder_id, permission_id, permission_email, permission_role, inherited, person_id, member_id)
    SELECT p_drive_folder_id, c.permission_id, c.email::citext, c.role, c.inherited, c.person_id, c.member_id
      FROM jsonb_to_recordset(v_cls) AS c(permission_id text, email text, role text, inherited boolean,
                                           member_id uuid, person_id uuid, verdict text)
     WHERE c.verdict = 'finding'
       AND NOT EXISTS (SELECT 1 FROM public.drive_folder_access_findings f
                        WHERE f.drive_folder_id = p_drive_folder_id AND f.permission_id = c.permission_id
                          AND f.status IN ('open','kept','approved','failed'))
    ON CONFLICT DO NOTHING
    RETURNING id
  )
  SELECT count(*) INTO v_new FROM ins;

  -- o e-mail de membro foi lido para casar a permissão com a pessoa (#2185: a origem é a automação)
  SELECT coalesce(array_agg(DISTINCT c.member_id) FILTER (WHERE c.member_id IS NOT NULL), ARRAY[]::uuid[])
    INTO v_members
    FROM jsonb_to_recordset(v_cls) AS c(member_id uuid);
  IF cardinality(v_members) > 0 THEN
    INSERT INTO public.pii_access_log (accessor_id, target_member_id, fields_accessed, context, reason, actor_kind)
    SELECT NULL, mid, ARRAY['email'], 'record_drive_folder_acl',
           'drive folder ACL review: match a folder permission to a member', 'automation'
      FROM unnest(v_members) AS mid;
  END IF;

  IF v_new + v_closed > 0 THEN
    INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
    VALUES (NULL, 'drive_folder_acl_recorded', 'drive_folder_access_findings', NULL, '{}'::jsonb,
            v_counts || jsonb_build_object('drive_folder_id', p_drive_folder_id, 'opened', v_new, 'closed', v_closed));
  END IF;

  RETURN v_counts || jsonb_build_object('dry_run', false, 'drive_folder_id', p_drive_folder_id,
                                        'opened', v_new, 'still_open', v_seen, 'closed', v_closed);
END;
$function$;
REVOKE ALL ON FUNCTION public.record_drive_folder_acl(text, jsonb, text[], boolean) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.record_drive_folder_acl(text, jsonb, text[], boolean) TO service_role;

-- ── 2. O ciclo passa a pasta (#3178). Corpo da captura 20261123024251, só com a pasta nas quatro chamadas. ──
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
  v_released    int := 0;
  v_notified    int := 0;
  v_sent        int := 0;
  v_approved    int := 0;
  v_ids         uuid[];
  v_early       uuid[];
  v_closed_early int := 0;
  v_id          uuid;
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
               AND ( public._drive_grant_keeps_access(g.grantee_person_id, g.initiative_id, g.drive_folder_id)
                  OR coalesce(public.can_by_member(q.member_id, 'manage_platform'), false)
                  OR EXISTS (SELECT 1 FROM public.drive_offboarding_audit a
                             WHERE a.drive_file_id = g.drive_folder_id AND a.permission_id = g.permission_id
                               AND a.status IN ('pending_revoke','approved')) ) ) )
    RETURNING q.id
  )
  SELECT count(*) INTO v_cancelled FROM c;

  -- b2. o bloqueio que deixou de importar. Uma falha ou um "manter" da gestão impede a concessão de voltar à fila
  -- (passo c). Quando a pessoa volta ao roster, o bloqueio já não protege nada: o item fecha como engagement_restored,
  -- e se o vínculo terminar de novo a concessão entra limpa. Cada item liberado ganha uma linha no admin_audit_log com o
  -- estado de antes (lido de o, a mesma linha antes do UPDATE), porque o próprio item passa a dizer engagement_restored.
  WITH rel AS (
    UPDATE public.drive_membership_revocations q
       SET status = 'cancelled', cancel_reason = 'engagement_restored',
           cancelled_at = coalesce(q.cancelled_at, now()), updated_at = now()
      FROM public.drive_membership_grants g, public.drive_membership_revocations o
     WHERE g.id = q.grant_id AND o.id = q.id
       AND ( (q.status = 'failed' AND q.reason = 'engagement_ended') OR q.cancel_reason = 'management_kept' )
       AND public._drive_grant_keeps_access(g.grantee_person_id, g.initiative_id, g.drive_folder_id)
    RETURNING q.id, q.grant_id, o.status AS status_before, o.cancel_reason AS cancel_reason_before
  ), rel_audit AS (
    INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
    SELECT NULL, 'drive_membership_revocation_released', 'drive_membership_revocations', rel.id,
           jsonb_build_object('status_before', rel.status_before, 'cancel_reason_before', rel.cancel_reason_before,
                              'status_after', 'cancelled', 'cancel_reason_after', 'engagement_restored'),
           jsonb_build_object('grant_id', rel.grant_id, 'via', 'enqueue_membership_drive_revocations')
      FROM rel
    RETURNING 1
  )
  SELECT count(*) INTO v_released FROM rel;

  -- c. entra na fila a concessão cuja pessoa saiu do roster da iniciativa e de toda iniciativa que usa a pasta (#3178)
  WITH ins AS (
    INSERT INTO public.drive_membership_revocations (grant_id, initiative_id, member_id, reason, is_confidential)
    SELECT g.id, g.initiative_id, g.grantee_member_id, 'engagement_ended', (i.visibility = 'confidential')
      FROM public.drive_membership_grants g
      JOIN public.initiatives i ON i.id = g.initiative_id
     WHERE g.status = 'granted' AND g.permission_id IS NOT NULL
       AND g.grantee_person_id IS NOT NULL AND g.grantee_member_id IS NOT NULL
       AND NOT public._drive_grant_keeps_access(g.grantee_person_id, g.initiative_id, g.drive_folder_id)
       -- exceção nomeada (GP, 22/11/2026): quem tem manage_platform vê a iniciativa confidencial pela ADR-0105
       AND NOT public.can_by_member(g.grantee_member_id, 'manage_platform')
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
    -- d. o aviso e o prazo. Item segurado não é avisado até soltar. A confidencialidade é a de agora, não a da entrada.
    -- A pausa (inactive) fica fora: é reversível sem portão (ADR-0107 Emenda 1, item 2), e a gestão decide na tela.
    FOR r IN
      SELECT x.id, (i.visibility = 'confidential') AS conf_now
        FROM public.drive_membership_revocations x
        JOIN public.initiatives i ON i.id = x.initiative_id
        JOIN public.members m ON m.id = x.member_id
       WHERE x.status = 'pending' AND x.reason = 'engagement_ended'
         AND x.notified_at IS NULL AND x.held_at IS NULL
         AND m.member_status IN ('active','alumni')
       ORDER BY x.detected_at, x.id
       FOR UPDATE OF x
    LOOP
      UPDATE public.drive_membership_revocations
         SET notified_at = now(),
             due_at = CASE WHEN r.conf_now THEN now() ELSE now() + c_notice END,
             is_confidential = r.conf_now,
             updated_at = now()
       WHERE id = r.id;
      IF public._drive_revocation_notify(r.id, r.conf_now) THEN
        v_sent := v_sent + 1;
      END IF;
      v_notified := v_notified + 1;
    END LOOP;

    -- e. vencido, avisado e não segurado, de quem é active ou alumni: aprova, conferindo a condição de novo no UPDATE.
    -- A visibilidade é relida aqui: o item avisado com 7 dias cuja iniciativa ficou confidencial depois do aviso sai
    -- neste ciclo, como sairia se já fosse confidencial na entrada (decisão do GP de 22/11/2026). O prazo de antes vem de
    -- o, a mesma linha antes do UPDATE: quem sai antes do prazo avisado recebe o "foi encerrado" (GP, 23/11/2026).
    WITH ap AS (
      UPDATE public.drive_membership_revocations x
         SET status = 'approved', approval_mode = 'auto', approved_at = now(), updated_at = now(),
             is_confidential = (i.visibility = 'confidential'),
             due_at = LEAST(x.due_at, now())
        FROM public.drive_membership_grants g, public.members m, public.initiatives i, public.drive_membership_revocations o
       WHERE g.id = x.grant_id AND m.id = g.grantee_member_id AND i.id = x.initiative_id AND o.id = x.id
         AND x.status = 'pending' AND x.reason = 'engagement_ended'
         AND x.held_at IS NULL AND x.notified_at IS NOT NULL
         AND (x.due_at <= now() OR i.visibility = 'confidential')
         AND g.status = 'granted'
         AND m.member_status IN ('active','alumni')
         AND NOT public._drive_grant_keeps_access(g.grantee_person_id, g.initiative_id, g.drive_folder_id)
         AND NOT public.can_by_member(g.grantee_member_id, 'manage_platform')
      RETURNING x.id, (o.due_at > now()) AS closing_early
    )
    SELECT array_agg(id ORDER BY id), array_agg(id ORDER BY id) FILTER (WHERE closing_early) INTO v_ids, v_early FROM ap;
    v_approved := coalesce(cardinality(v_ids), 0);

    -- o aviso de "foi encerrado" de quem saiu antes do prazo avisado. A hora do aviso vai para notified_at ANTES de
    -- avisar, item a item: o segundo item do mesmo par vê o primeiro como "foi encerrado" e não avisa de novo.
    FOREACH v_id IN ARRAY coalesce(v_early, ARRAY[]::uuid[]) LOOP
      UPDATE public.drive_membership_revocations SET notified_at = now(), updated_at = now() WHERE id = v_id;
      IF public._drive_revocation_notify(v_id, true) THEN
        v_sent := v_sent + 1;
      END IF;
      v_closed_early := v_closed_early + 1;
    END LOOP;
  END IF;

  IF v_backfilled + v_cancelled + v_released + v_queued + v_notified + v_approved > 0 THEN
    INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
    VALUES (NULL, 'drive_membership_revocation_cycle', 'drive_membership_revocations', NULL, '{}'::jsonb,
            jsonb_build_object('enabled', v_on, 'ledger_aligned', v_backfilled, 'cancelled', v_cancelled,
                               'released', v_released, 'queued', v_queued, 'notified', v_notified,
                               'notices_sent', v_sent, 'auto_approved', v_approved,
                               'closed_early', v_closed_early,
                               'approved_ids', to_jsonb(coalesce(v_ids, ARRAY[]::uuid[]))));
  END IF;

  RETURN jsonb_build_object('enabled', v_on, 'ledger_aligned', v_backfilled, 'cancelled', v_cancelled,
                            'released', v_released, 'queued', v_queued, 'notified', v_notified,
                            'notices_sent', v_sent, 'auto_approved', v_approved,
                            'closed_early', v_closed_early);
END;
$function$;
REVOKE ALL ON FUNCTION public.enqueue_membership_drive_revocations() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.enqueue_membership_drive_revocations() TO service_role;

-- ── 5. O executor da ADR-0107 acha também o item da revisão (#3179), e o de fim de vínculo olha a pasta (#3178) ──
CREATE OR REPLACE FUNCTION public.get_drive_revocation_row(p_audit_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public','pg_temp'
AS $$
DECLARE v_row public.drive_offboarding_audit; v_m record; v_f record;
BEGIN
  IF public.current_caller_role() IS DISTINCT FROM 'service_role' THEN RAISE EXCEPTION 'service-role only'; END IF;
  SELECT * INTO v_row FROM public.drive_offboarding_audit WHERE id=p_audit_id;
  IF v_row.id IS NOT NULL THEN
    RETURN jsonb_build_object(
      'id', v_row.id, 'status', v_row.status, 'drive_file_id', v_row.drive_file_id,
      'permission_id', v_row.permission_id, 'permission_email', v_row.permission_email::text,
      'is_shared_drive', v_row.is_shared_drive, 'approved_by', v_row.approved_by);
  END IF;

  -- #3147: item da fila de fim de vínculo. A EF só age em 'approved', e esta leitura é a última conferência antes do
  -- Drive: a concessão que já não está 'granted' devolve grant_<status>; o item de fim de vínculo cuja pessoa voltou
  -- ao roster de uma iniciativa que usa a pasta (#3178), ou ganhou manage_platform, devolve stale_keeps_access.
  SELECT r.id,
         CASE WHEN g.status IS DISTINCT FROM 'granted' THEN 'grant_' || g.status
              WHEN r.reason = 'engagement_ended'
               AND ( public._drive_grant_keeps_access(g.grantee_person_id, g.initiative_id, g.drive_folder_id)
                  OR coalesce(public.can_by_member(g.grantee_member_id, 'manage_platform'), false) )
                THEN 'stale_keeps_access'
              ELSE r.status END AS status,
         g.drive_folder_id, g.permission_id, g.permission_email, r.approved_by
    INTO v_m
    FROM public.drive_membership_revocations r
    JOIN public.drive_membership_grants g ON g.id = r.grant_id
   WHERE r.id = p_audit_id;
  IF v_m.id IS NOT NULL THEN
    RETURN jsonb_build_object(
      'id', v_m.id, 'status', v_m.status, 'drive_file_id', v_m.drive_folder_id,
      'permission_id', v_m.permission_id, 'permission_email', v_m.permission_email::text,
      'is_shared_drive', NULL, 'approved_by', v_m.approved_by, 'queue', 'membership');
  END IF;

  -- #3179: item da revisão do acesso fora do ledger. A mesma última conferência: se a permissão ganhou concessão viva,
  -- se a pessoa entrou no roster de uma iniciativa que usa a pasta, ou se tem manage_platform, devolve stale_keeps_access.
  SELECT f.id,
         CASE WHEN f.status = 'approved'
               AND ( EXISTS (SELECT 1 FROM public.drive_membership_grants g
                              WHERE g.drive_folder_id = f.drive_folder_id AND g.permission_email = f.permission_email
                                AND g.status = 'granted')
                  OR (f.person_id IS NOT NULL AND public._drive_grant_keeps_access(f.person_id, NULL, f.drive_folder_id))
                  OR (f.member_id IS NOT NULL AND coalesce(public.can_by_member(f.member_id, 'manage_platform'), false)) )
                THEN 'stale_keeps_access'
              ELSE f.status END AS status,
         f.drive_folder_id, f.permission_id, f.permission_email, f.approved_by
    INTO v_f
    FROM public.drive_folder_access_findings f
   WHERE f.id = p_audit_id;
  IF v_f.id IS NULL THEN RETURN NULL; END IF;
  RETURN jsonb_build_object(
    'id', v_f.id, 'status', v_f.status, 'drive_file_id', v_f.drive_folder_id,
    'permission_id', v_f.permission_id, 'permission_email', v_f.permission_email::text,
    'is_shared_drive', NULL, 'approved_by', v_f.approved_by, 'queue', 'folder_acl');
END;
$$;

CREATE OR REPLACE FUNCTION public.mark_drive_revocation_done(p_audit_id uuid, p_status text, p_google_error jsonb DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public','pg_temp'
AS $$
DECLARE v_row public.drive_offboarding_audit; v_rev public.drive_membership_revocations;
        v_f public.drive_folder_access_findings;
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

    -- #3179: item da revisão do acesso fora do ledger. Só o aprovado chega ao fim.
    UPDATE public.drive_folder_access_findings
       SET status = p_status,
           google_error = p_google_error,
           revoked_at = CASE WHEN p_status IN ('revoked','already_absent') THEN now() ELSE revoked_at END,
           updated_at = now()
     WHERE id = p_audit_id AND status = 'approved'
     RETURNING * INTO v_f;
    IF v_f.id IS NOT NULL THEN
      IF p_status IN ('revoked','already_absent') THEN
        INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
        VALUES (v_f.approved_by, 'drive_folder_access_revoked', 'drive_folder_access_findings', v_f.id,
                jsonb_build_object('status_after', p_status),
                jsonb_build_object('drive_folder_id', v_f.drive_folder_id, 'permission_id', v_f.permission_id,
                                   'member_id', v_f.member_id));
      END IF;
      RETURN jsonb_build_object('audit_id', v_f.id, 'status', v_f.status, 'queue', 'folder_acl');
    END IF;
    SELECT * INTO v_f FROM public.drive_folder_access_findings WHERE id = p_audit_id;
    IF v_f.id IS NOT NULL THEN
      RETURN jsonb_build_object('audit_id', v_f.id, 'status', v_f.status, 'noop', true, 'queue', 'folder_acl');
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

-- O "aprovar já" passa a pasta (#3178). Corpo da captura 20261123013234.
CREATE OR REPLACE FUNCTION public.admin_approve_drive_membership_revocation(p_revocation_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_caller_id uuid; v_rev public.drive_membership_revocations; v_g public.drive_membership_grants;
        v_notify_now boolean; v_sent boolean := false;
BEGIN
  v_caller_id := (SELECT id FROM public.members WHERE auth_id = auth.uid());
  IF v_caller_id IS NULL OR NOT public.can_by_member(v_caller_id, 'manage_platform') THEN
    RAISE EXCEPTION 'Unauthorized: GP only (manage_platform)';
  END IF;
  SELECT * INTO v_rev FROM public.drive_membership_revocations WHERE id = p_revocation_id FOR UPDATE;
  IF v_rev.id IS NULL OR v_rev.status <> 'pending' THEN
    RAISE EXCEPTION 'Item % não está pendente', p_revocation_id;
  END IF;
  SELECT * INTO v_g FROM public.drive_membership_grants WHERE id = v_rev.grant_id;
  IF v_g.status IS DISTINCT FROM 'granted' THEN
    RAISE EXCEPTION 'A concessão do item % já não está ativa', p_revocation_id;
  END IF;
  IF coalesce(public.can_by_member(v_g.grantee_member_id, 'manage_platform'), false) THEN
    RAISE EXCEPTION 'O titular tem manage_platform e fica com o acesso';
  END IF;
  IF v_rev.reason = 'engagement_ended' AND public._drive_grant_keeps_access(v_g.grantee_person_id, v_g.initiative_id, v_g.drive_folder_id) THEN
    RAISE EXCEPTION 'A pessoa voltou ao roster da iniciativa; o item será cancelado no próximo ciclo';
  END IF;
  v_notify_now := v_rev.reason = 'engagement_ended' AND v_rev.notified_at IS NULL;
  UPDATE public.drive_membership_revocations
     SET status = 'approved', approval_mode = 'manual', approved_by = v_caller_id, approved_at = now(),
         held_at = NULL, held_by = NULL, hold_note = NULL,
         notified_at = CASE WHEN v_notify_now THEN now() ELSE notified_at END,
         due_at      = CASE WHEN v_notify_now THEN now() ELSE due_at END,
         updated_at = now()
   WHERE id = p_revocation_id AND status = 'pending'
   RETURNING * INTO v_rev;
  IF v_rev.id IS NULL THEN RAISE EXCEPTION 'Item % não está pendente', p_revocation_id; END IF;
  IF v_notify_now THEN
    v_sent := public._drive_revocation_notify(v_rev.id, true);
  END IF;
  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
  VALUES (v_caller_id, 'drive_membership_revocation_approved', 'drive_membership_revocations', v_rev.id,
          jsonb_build_object('status_after', 'approved', 'approval_mode', 'manual'),
          jsonb_build_object('grant_id', v_rev.grant_id, 'reason', v_rev.reason,
                             'notified_now', v_notify_now, 'notice_sent', v_sent));
  RETURN jsonb_build_object('id', v_rev.id, 'status', v_rev.status, 'notified_now', v_notify_now, 'notice_sent', v_sent);
END;
$function$;
REVOKE ALL ON FUNCTION public.admin_approve_drive_membership_revocation(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_approve_drive_membership_revocation(uuid) TO authenticated, service_role;

-- ── 6. A tela da gestão (manage_platform) para a revisão (#3179) ──
-- A leitura: cada item com as iniciativas que usam a pasta (só as que quem lê pode ver, ADR-0105), confidencial primeiro.
CREATE OR REPLACE FUNCTION public.admin_list_drive_folder_access_findings(p_include_closed boolean DEFAULT false)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_rows jsonb;
  v_ids uuid[];
BEGIN
  v_caller_id := (SELECT id FROM public.members WHERE auth_id = auth.uid());
  IF v_caller_id IS NULL OR NOT public.can_by_member(v_caller_id, 'manage_platform') THEN
    RAISE EXCEPTION 'Unauthorized: GP only (manage_platform)';
  END IF;

  SELECT coalesce(jsonb_agg(to_jsonb(q) - 'ord' ORDER BY q.is_confidential DESC, q.ord, q.first_seen_at), '[]'::jsonb),
         coalesce(array_agg(DISTINCT q.member_id) FILTER (WHERE q.member_id IS NOT NULL), ARRAY[]::uuid[])
    INTO v_rows, v_ids
    FROM (
      SELECT f.id, f.drive_folder_id, f.permission_id, f.permission_email::text AS permission_email,
             f.permission_role, f.inherited, f.member_id, m.name AS member_name, m.member_status,
             f.status, f.first_seen_at, f.last_seen_at, f.reviewed_at, f.review_note, f.approved_at,
             f.revoked_at, f.google_error, f.closed_at, f.close_reason,
             ini.initiatives, ini.drive_folder_url, coalesce(ini.is_confidential, false) AS is_confidential,
             coalesce(ini.folder_linked, false) AS folder_linked,
             CASE f.status WHEN 'failed' THEN 0 WHEN 'approved' THEN 1 WHEN 'open' THEN 2 WHEN 'kept' THEN 3 ELSE 4 END AS ord
        FROM public.drive_folder_access_findings f
        LEFT JOIN public.members m ON m.id = f.member_id
        JOIN LATERAL (
          SELECT jsonb_agg(jsonb_build_object('id', i.id, 'title', i.title,
                                              'is_confidential', i.visibility = 'confidential',
                                              'linked', l.unlinked_at IS NULL) ORDER BY i.title) AS initiatives,
                 (array_agg(l.drive_folder_url ORDER BY l.unlinked_at IS NULL DESC, l.linked_at DESC))[1] AS drive_folder_url,
                 bool_or(i.visibility = 'confidential') AS is_confidential,
                 bool_or(l.unlinked_at IS NULL) AS folder_linked
            FROM public.initiative_drive_links l
            JOIN public.initiatives i ON i.id = l.initiative_id
           WHERE l.drive_folder_id = f.drive_folder_id AND l.link_purpose = 'workspace'
             AND public.rls_can_see_initiative(l.initiative_id)
        ) ini ON ini.initiatives IS NOT NULL
       WHERE (p_include_closed OR f.status IN ('open','kept','approved','failed'))
       ORDER BY f.first_seen_at DESC
       LIMIT 500
    ) q;

  IF cardinality(v_ids) > 0 THEN
    PERFORM public.log_pii_access_batch(v_ids, ARRAY['email'], 'admin_list_drive_folder_access_findings',
      'GP review of Drive workspace access outside the grant ledger (#3179)');
  END IF;

  RETURN jsonb_build_object(
    'rows', v_rows,
    'summary', jsonb_build_object(
      'open',     (SELECT count(*) FROM jsonb_array_elements(v_rows) x WHERE x->>'status' = 'open'),
      'kept',     (SELECT count(*) FROM jsonb_array_elements(v_rows) x WHERE x->>'status' = 'kept'),
      'approved', (SELECT count(*) FROM jsonb_array_elements(v_rows) x WHERE x->>'status' = 'approved'),
      'failed',   (SELECT count(*) FROM jsonb_array_elements(v_rows) x WHERE x->>'status' = 'failed'),
      'unknown_person', (SELECT count(*) FROM jsonb_array_elements(v_rows) x
                         WHERE x->>'member_id' IS NULL AND x->>'status' IN ('open','kept','approved','failed')),
      'confidential_open', (SELECT count(*) FROM jsonb_array_elements(v_rows) x
                            WHERE (x->>'is_confidential')::boolean AND x->>'status' IN ('open','approved','failed'))));
END;
$function$;
REVOKE ALL ON FUNCTION public.admin_list_drive_folder_access_findings(boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_list_drive_folder_access_findings(boolean) TO authenticated, service_role;

-- A decisão da gestão sobre um item: manter (o acesso é legítimo), reabrir (desfaz o manter) ou revogar (pelo executor
-- da ADR-0107, no dreno seguinte). Manter e revogar pedem motivo. Revogar reconfere a pessoa e recusa a permissão
-- herdada da pasta-mãe, que só sai lá.
CREATE OR REPLACE FUNCTION public.admin_review_drive_folder_access(p_finding_id uuid, p_action text, p_note text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_caller_id uuid; v_f public.drive_folder_access_findings; v_before text; v_note text;
BEGIN
  v_caller_id := (SELECT id FROM public.members WHERE auth_id = auth.uid());
  IF v_caller_id IS NULL OR NOT public.can_by_member(v_caller_id, 'manage_platform') THEN
    RAISE EXCEPTION 'Unauthorized: GP only (manage_platform)';
  END IF;
  IF p_action IS NULL OR p_action NOT IN ('keep','reopen','revoke') THEN
    RAISE EXCEPTION 'Ação inválida: % (keep, reopen ou revoke)', p_action;
  END IF;
  v_note := nullif(btrim(coalesce(p_note, '')), '');
  IF p_action IN ('keep','revoke') AND v_note IS NULL THEN
    RAISE EXCEPTION 'Manter ou revogar pede um motivo';
  END IF;
  SELECT * INTO v_f FROM public.drive_folder_access_findings WHERE id = p_finding_id FOR UPDATE;
  IF v_f.id IS NULL THEN RAISE EXCEPTION 'Item % não encontrado', p_finding_id; END IF;
  v_before := v_f.status;

  IF p_action = 'keep' THEN
    IF v_f.status NOT IN ('open','failed') THEN RAISE EXCEPTION 'Item % não está aberto (status %)', p_finding_id, v_f.status; END IF;
    UPDATE public.drive_folder_access_findings
       SET status = 'kept', reviewed_by = v_caller_id, reviewed_at = now(), review_note = v_note, updated_at = now()
     WHERE id = p_finding_id RETURNING * INTO v_f;
  ELSIF p_action = 'reopen' THEN
    IF v_f.status <> 'kept' THEN RAISE EXCEPTION 'Só um item mantido é reaberto (status %)', v_f.status; END IF;
    UPDATE public.drive_folder_access_findings
       SET status = 'open', reviewed_by = v_caller_id, reviewed_at = now(), review_note = coalesce(v_note, review_note),
           updated_at = now()
     WHERE id = p_finding_id RETURNING * INTO v_f;
  ELSE
    IF v_f.status NOT IN ('open','kept','failed') THEN
      RAISE EXCEPTION 'Item % não pode ser revogado (status %)', p_finding_id, v_f.status;
    END IF;
    IF v_f.inherited IS TRUE THEN
      RAISE EXCEPTION 'A permissão vem da pasta-mãe e só sai lá';
    END IF;
    IF EXISTS (SELECT 1 FROM public.drive_membership_grants g
                WHERE g.drive_folder_id = v_f.drive_folder_id AND g.permission_email = v_f.permission_email
                  AND g.status = 'granted') THEN
      RAISE EXCEPTION 'A permissão tem concessão viva no ledger; use a fila de fim de vínculo';
    END IF;
    IF v_f.person_id IS NOT NULL AND public._drive_grant_keeps_access(v_f.person_id, NULL, v_f.drive_folder_id) THEN
      RAISE EXCEPTION 'A pessoa está no roster de uma iniciativa que usa a pasta e fica com o acesso';
    END IF;
    IF v_f.member_id IS NOT NULL AND coalesce(public.can_by_member(v_f.member_id, 'manage_platform'), false) THEN
      RAISE EXCEPTION 'O titular tem manage_platform e fica com o acesso';
    END IF;
    UPDATE public.drive_folder_access_findings
       SET status = 'approved', approved_by = v_caller_id, approved_at = now(), google_error = NULL,
           reviewed_by = v_caller_id, reviewed_at = now(), review_note = v_note, updated_at = now()
     WHERE id = p_finding_id RETURNING * INTO v_f;
  END IF;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
  VALUES (v_caller_id, 'drive_folder_access_reviewed', 'drive_folder_access_findings', v_f.id,
          jsonb_build_object('status_before', v_before, 'status_after', v_f.status, 'action', p_action),
          jsonb_build_object('drive_folder_id', v_f.drive_folder_id, 'note', v_note));
  RETURN jsonb_build_object('id', v_f.id, 'status', v_f.status, 'action', p_action);
END;
$function$;
REVOKE ALL ON FUNCTION public.admin_review_drive_folder_access(uuid, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_review_drive_folder_access(uuid, text, text) TO authenticated, service_role;

-- ── O dreno de sempre (cron 64, ADR-0107), agora com as três filas. Mesmo nome, então substitui o comando. ──
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
        UNION ALL
        SELECT id, approved_at FROM public.drive_folder_access_findings
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

-- ── 2. A versão de dois argumentos sai: os chamadores acima já passam a pasta (#3178) ──
DROP FUNCTION IF EXISTS public._drive_grant_keeps_access(uuid, uuid);

NOTIFY pgrst, 'reload schema';
