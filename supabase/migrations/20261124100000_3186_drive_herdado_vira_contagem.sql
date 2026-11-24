-- #3186: a permissão herdada da pasta de cima não abre item da revisão (#3179). Vira contagem por pasta de trabalho,
-- no retorno de record_drive_folder_acl e na tela, com a indicação de que a decisão é na pasta de cima.
-- A permissão direta segue como antes. A volta do cron sem skip_acl_review é a migration seguinte (3186b), aplicada
-- depois do ensaio da EF.
--
-- 1. close_reason ganha 'inherited': um item aberto antes, de permissão agora lida como herdada, fecha com esse motivo.
-- 2. drive_folder_inherited_access: a contagem por pasta, sem e-mail nem pessoa (não é dado pessoal).
-- 3. record_drive_folder_acl: veredito 'inherited' depois das conferências de quem fica; 'findings' passa a ser só a
--    direta; 'findings_inherited' sai, entram 'inherited' e 'inherited_unknown_person'; regrava a contagem da pasta.
-- 4. admin_list_drive_folder_access_findings: devolve 'inherited_by_folder' (gate rls_can_see_initiative) e o total.
-- Corpos das capturas 20261124014334 (iguais ao vivo em 24/11), só com os trechos marcados #3186.

-- ── 1. O motivo de fechamento do herdado ──
ALTER TABLE public.drive_folder_access_findings DROP CONSTRAINT IF EXISTS drive_folder_access_findings_close_reason_check;
ALTER TABLE public.drive_folder_access_findings ADD CONSTRAINT drive_folder_access_findings_close_reason_check
  CHECK (close_reason IN ('permission_gone','covered_by_grant','offboarding_lane','on_roster',
                          'manage_platform_exception','inherited'));

-- ── 2. A contagem do herdado, por pasta ──
CREATE TABLE IF NOT EXISTS public.drive_folder_inherited_access (
  drive_folder_id          text PRIMARY KEY,
  inherited_count          integer NOT NULL CHECK (inherited_count >= 0),
  inherited_unknown_person integer NOT NULL CHECK (inherited_unknown_person >= 0
                                                   AND inherited_unknown_person <= inherited_count),
  first_seen_at            timestamptz NOT NULL DEFAULT now(),
  last_seen_at             timestamptz NOT NULL DEFAULT now(),
  updated_at               timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE public.drive_folder_inherited_access IS
  '#3186: quantas permissões de usuário a pasta de trabalho herda da pasta de cima sem concessão viva e de quem não fica pelo roster. Só a contagem, sem e-mail; a decisão é na pasta de cima. Gravada por record_drive_folder_acl.';
ALTER TABLE public.drive_folder_inherited_access ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS drive_folder_inherited_access_deny_all ON public.drive_folder_inherited_access;
CREATE POLICY drive_folder_inherited_access_deny_all ON public.drive_folder_inherited_access
  AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
REVOKE ALL ON public.drive_folder_inherited_access FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.drive_folder_inherited_access TO service_role;

-- ── 3. A classificação ──
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
             -- a trilha de desligamento já tem a mesma permissão aberta: uma fila só por permissão (como o passo c)
             WHEN EXISTS (SELECT 1 FROM public.drive_offboarding_audit a
                           WHERE a.drive_file_id = p_drive_folder_id AND a.permission_id = w.permission_id
                             AND a.status IN ('pending_revoke','approved')) THEN 'offboarding_lane'
             -- o mesmo predicado da última conferência (todo membro com o e-mail, não só o primeiro casado), para que
             -- nenhum item aberto aqui seja um que a revogação depois recusa
             WHEN public._drive_finding_keeps_access(p_drive_folder_id, w.email)
              THEN CASE WHEN w.member_id IS NOT NULL
                         AND coalesce(public.can_by_member(w.member_id, 'manage_platform'), false)
                        THEN 'manage_platform_exception' ELSE 'on_roster' END
             -- #3186: herdada da pasta de cima. Não abre item: a revisão não revoga aqui, e a decisão é lá em cima.
             -- Vira contagem por pasta (drive_folder_inherited_access). Sem o "herdado" do Drive (NULL), segue direta.
             WHEN w.inherited IS TRUE THEN 'inherited'
             ELSE 'finding' END)), '[]'::jsonb)
    INTO v_cls
    FROM who w;

  SELECT jsonb_build_object(
           'user_permissions', jsonb_array_length(v_cls),
           'findings',  count(*) FILTER (WHERE c.verdict = 'finding'),
           'inherited', count(*) FILTER (WHERE c.verdict = 'inherited'),
           'inherited_unknown_person', count(*) FILTER (WHERE c.verdict = 'inherited' AND c.member_id IS NULL),
           'covered_by_grant', count(*) FILTER (WHERE c.verdict = 'covered_by_grant'),
           'offboarding_lane', count(*) FILTER (WHERE c.verdict = 'offboarding_lane'),
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

  -- #3186: o herdado da pasta, agregado, sem e-mail. Uma linha por pasta, regravada a cada leitura (zero também).
  INSERT INTO public.drive_folder_inherited_access (drive_folder_id, inherited_count, inherited_unknown_person)
  VALUES (p_drive_folder_id, (v_counts->>'inherited')::int, (v_counts->>'inherited_unknown_person')::int)
  ON CONFLICT (drive_folder_id) DO UPDATE
     SET inherited_count = EXCLUDED.inherited_count,
         inherited_unknown_person = EXCLUDED.inherited_unknown_person,
         last_seen_at = now(), updated_at = now();

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

-- ── 4. A tela ──
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
  v_inh jsonb;
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

  -- #3186: o herdado, por pasta de trabalho viva, só das iniciativas que quem lê pode ver (ADR-0105). Sem e-mail.
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'drive_folder_id', h.drive_folder_id, 'inherited_count', h.inherited_count,
           'unknown_person', h.inherited_unknown_person, 'last_seen_at', h.last_seen_at,
           'initiatives', ini.initiatives, 'drive_folder_url', ini.drive_folder_url,
           'is_confidential', coalesce(ini.is_confidential, false))
           ORDER BY coalesce(ini.is_confidential, false) DESC, h.inherited_count DESC, h.drive_folder_id), '[]'::jsonb)
    INTO v_inh
    FROM public.drive_folder_inherited_access h
    JOIN LATERAL (
      SELECT jsonb_agg(jsonb_build_object('id', i.id, 'title', i.title,
                                          'is_confidential', i.visibility = 'confidential') ORDER BY i.title) AS initiatives,
             (array_agg(l.drive_folder_url ORDER BY l.linked_at DESC))[1] AS drive_folder_url,
             bool_or(i.visibility = 'confidential') AS is_confidential
        FROM public.initiative_drive_links l
        JOIN public.initiatives i ON i.id = l.initiative_id
       WHERE l.drive_folder_id = h.drive_folder_id AND l.link_purpose = 'workspace' AND l.unlinked_at IS NULL
         AND public.rls_can_see_initiative(l.initiative_id)
    ) ini ON ini.initiatives IS NOT NULL
   WHERE h.inherited_count > 0;

  RETURN jsonb_build_object(
    'rows', v_rows,
    'inherited_by_folder', v_inh,
    'summary', jsonb_build_object(
      'open',     (SELECT count(*) FROM jsonb_array_elements(v_rows) x WHERE x->>'status' = 'open'),
      'kept',     (SELECT count(*) FROM jsonb_array_elements(v_rows) x WHERE x->>'status' = 'kept'),
      'approved', (SELECT count(*) FROM jsonb_array_elements(v_rows) x WHERE x->>'status' = 'approved'),
      'failed',   (SELECT count(*) FROM jsonb_array_elements(v_rows) x WHERE x->>'status' = 'failed'),
      'unknown_person', (SELECT count(*) FROM jsonb_array_elements(v_rows) x
                         WHERE x->>'member_id' IS NULL AND x->>'status' IN ('open','kept','approved','failed')),
      'confidential_open', (SELECT count(*) FROM jsonb_array_elements(v_rows) x
                            WHERE (x->>'is_confidential')::boolean AND x->>'status' IN ('open','approved','failed')),
      'inherited', (SELECT coalesce(sum((x->>'inherited_count')::int), 0) FROM jsonb_array_elements(v_inh) x),
      'inherited_folders', jsonb_array_length(v_inh)));
END;
$function$;
REVOKE ALL ON FUNCTION public.admin_list_drive_folder_access_findings(boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_list_drive_folder_access_findings(boolean) TO authenticated, service_role;
