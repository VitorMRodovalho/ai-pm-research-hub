-- Pertencimento, parte 2 (GP 26/10/2026): o card de cada linha e a fileira de rostos de "Quem faz" passam a se
-- apoiar no consentimento de imagem e voz da Cláusula 11, filtrado por pessoa, decidido e revogado no perfil.
-- Caminho A (GP, "segue pelo caminho A"): quem assinou o termo antes da Cláusula 11 dá o consentimento no PERFIL, pelo
-- ledger que já existe; o termo não é reemitido.
--
-- PLACEHOLDER: a orquestradora aplica, adota a versão que o apply_migration registrar e renomeia o arquivo.
--
-- UMA REGRA, NUMA FUNÇÃO: _member_has_image_consent(member). Vale a decisão explícita mais recente da pessoa em
-- consent_records (policy_type 'image_voice_publicity', o ledger de #570, #729 e #1024):
--   - há linha ativa (revoked_at nulo)  => verdadeiro (a pessoa autorizou e não revogou depois);
--   - há linhas, todas revogadas          => falso (a última decisão foi revogar);
--   - nenhuma linha                       => decide o termo assinado: o volunteer_agreement vigente (o mais recente
--                                            com status 'issued' e sem revoked_at) traz, no texto que a pessoa
--                                            assinou, a frase operativa da Cláusula 11 ("autoriza o uso de sua imagem
--                                            e de sua voz"). Medido em 26/10: a frase está 1 vez no corpo do termo
--                                            ativo, 0 nas versões anteriores e 0 no modelo antigo.
-- "Linha ativa vale" e "a última decisão vale" são a mesma coisa neste ledger: autorizar só grava linha nova quando
-- não há linha ativa, e revogar fecha a linha ativa; por isso há no máximo uma linha ativa e ela é a decisão mais
-- recente. O ramo "revogado" é o mesmo predicado que a liberação de comunicação (get_member_comms_card) já usa.
--
-- OS DOIS CAMINHOS DE ESCRITA SÃO OS QUE JÁ EXISTEM (#570), sem duplicação:
--   - autorizar: grant_image_voice_consent(p_evidence), sem mudança. O perfil manda evidence.displayed_version com o
--     identificador do texto exato da Cláusula 11 exibido (versão do termo, "cl11", md5 do texto e língua da tela).
--     Autorizar de novo depois de revogar grava uma linha NOVA: o ledger não se reescreve.
--   - revogar: revoke_image_voice_consent(p_reason), redefinida aqui com um ramo a mais. Antes, sem linha ativa, ela
--     não gravava nada; quem consente pelo termo (sem nenhuma linha) não conseguia revogar. Agora, sem linha ativa E sem
--     decisão anterior, ela grava uma linha nascida revogada, cuja aceitação é a assinatura do termo (o consentimento
--     que está sendo revogado é o do termo). Com uma revogação já registrada, segue sem gravar nada. Nunca apaga.
-- consent_records é só por RPC (authenticated tem só SELECT e a única política permissiva é false); não há coluna nova
-- em members, então members_update_own não alcança a decisão.
--
-- A FOTO SÓ SAI COM NOME OPACO. _public_member_photo_url devolve a URL só quando ela é exatamente o objeto
-- avatars/<32 hex>.(jpg|png) no bucket público member-photos deste projeto (com o ?t= numérico opcional do upload);
-- qualquer outra forma, inclusive a que codifica o e-mail, vira NULL, seja qual for a ordem de merge com a PR das
-- fotos opacas.
--
-- (0) pré-condições: o corpo vivo de get_public_home_team é o da captura medida (os predicados de grupo são copiados
--     dela); a frase da cláusula aparece uma vez no corpo do termo ativo; o corpo vivo de revoke_image_voice_consent é
--     o da captura de #570 (é ele que esta migration redefine).
-- (1) os ajudantes, sem EXECUTE para PUBLIC, anon e authenticated.
-- (2) o perfil: get_my_image_consent (lê o estado e o texto da cláusula) e revoke_image_voice_consent redefinida.
-- (3) get_public_line_leaders: por linha ativa, nome, foto opaca e vídeo de quem lidera, só com consentimento.
-- (4) get_public_team_faces: por grupo de "Quem faz", até 8 rostos de quem consentiu e tem foto opaca; para as
--     presidências e pontos focais, só os nomes dos capítulos.
-- (5) pós-condição: catálogo, controles dos casadores, leitura como anon, e o perfil exercido numa subtransação desfeita
--     no fim: quem assinou antes autoriza, revoga e autoriza de novo; quem tem a cláusula revoga. Resíduo zero.
--
-- Rollback: DROP FUNCTION public.get_public_team_faces(); DROP FUNCTION public.get_public_line_leaders();
--   DROP FUNCTION public.get_my_image_consent(); DROP FUNCTION public._member_has_image_consent(uuid);
--   DROP FUNCTION public._member_term_has_image_clause(uuid); DROP FUNCTION public._member_current_term(uuid);
--   DROP FUNCTION public._current_term_image_clause(); DROP FUNCTION public._public_member_photo_url(text);
--   e recriar revoke_image_voice_consent pelo corpo de 20260805000298 (o ramo novo some; as linhas que ele gravou
--   ficam, porque são prova de revogação, LGPD art. 8º, § 5º).

-- ── (0) pré-condições ───────────────────────────────────────────────────────────────────────────────────────────
DO $precondition$
BEGIN
  IF (SELECT md5(regexp_replace(p.prosrc, '\s+', ' ', 'g')) FROM pg_proc p
      WHERE p.oid = 'public.get_public_home_team()'::regprocedure)
     IS DISTINCT FROM '3d628ba07fef3c63481a04470197731a' THEN
    RAISE EXCEPTION 'clausula 11: get_public_home_team no banco não é a captura medida (20261025160648)';
  END IF;
  IF (SELECT md5(regexp_replace(p.prosrc, '\s+', ' ', 'g')) FROM pg_proc p
      WHERE p.oid = 'public.revoke_image_voice_consent(text)'::regprocedure)
     IS DISTINCT FROM '00dc696134ac416332e62ea4229503bd' THEN
    RAISE EXCEPTION 'clausula 11: revoke_image_voice_consent no banco não é a captura de #570 (20260805000298)';
  END IF;
  IF (SELECT count(*) FROM regexp_matches(
        (SELECT dv.content_html FROM public.governance_documents gd
         JOIN public.document_versions dv ON dv.id = gd.current_version_id
         WHERE gd.doc_type = 'volunteer_term_template' AND gd.status = 'active'
         ORDER BY gd.created_at DESC LIMIT 1),
        'autoriza o uso de sua imagem e de sua voz', 'g')) <> 1 THEN
    RAISE EXCEPTION 'clausula 11: a frase da cláusula não aparece exatamente uma vez no corpo do termo ativo';
  END IF;
END;
$precondition$;

-- ── (1) os ajudantes ────────────────────────────────────────────────────────────────────────────────────────────
-- o termo vigente: o volunteer_agreement mais recente que está em vigor
CREATE OR REPLACE FUNCTION public._member_current_term(p_member_id uuid)
 RETURNS uuid
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT c.id
  FROM public.certificates c
  WHERE c.member_id = p_member_id
    AND c.type = 'volunteer_agreement'
    AND c.status = 'issued'
    AND c.revoked_at IS NULL
  ORDER BY c.issued_at DESC, c.id DESC
  LIMIT 1;
$function$;

-- o termo vigente traz, no texto assinado, a frase operativa da Cláusula 11
CREATE OR REPLACE FUNCTION public._member_term_has_image_clause(p_member_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT coalesce((
    SELECT strpos(coalesce(c.content_snapshot->>'html_body', ''), 'autoriza o uso de sua imagem e de sua voz') > 0
    FROM public.certificates c
    WHERE c.id = public._member_current_term(p_member_id)
  ), false);
$function$;

-- a regra única: a decisão explícita mais recente no ledger; sem decisão, o termo assinado
CREATE OR REPLACE FUNCTION public._member_has_image_consent(p_member_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT p_member_id IS NOT NULL AND coalesce(
    CASE
      WHEN EXISTS (
        SELECT 1 FROM public.consent_records cr
        WHERE cr.member_id = p_member_id AND cr.policy_type = 'image_voice_publicity' AND cr.revoked_at IS NULL)
      THEN true
      WHEN EXISTS (
        SELECT 1 FROM public.consent_records cr
        WHERE cr.member_id = p_member_id AND cr.policy_type = 'image_voice_publicity')
      THEN false
    END,
    public._member_term_has_image_clause(p_member_id));
$function$;

-- o texto da Cláusula 11 da versão ativa do termo (caput, § 1º e § 2º), em texto puro, e o identificador desse texto,
-- que o perfil manda como displayed_version ao autorizar. Fora da forma esperada, NULL: o perfil não pede autorização
-- sobre texto que não conseguiu mostrar.
CREATE OR REPLACE FUNCTION public._current_term_image_clause()
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  WITH v AS (
    SELECT dv.version_number, dv.content_html AS html,
           strpos(dv.content_html, '<p><strong>Cláusula 11.</strong>') AS s
    FROM public.governance_documents gd
    JOIN public.document_versions dv ON dv.id = gd.current_version_id
    WHERE gd.doc_type = 'volunteer_term_template' AND gd.status = 'active'
    ORDER BY gd.created_at DESC
    LIMIT 1
  ),
  blk AS (
    SELECT v.version_number,
           CASE WHEN v.s > 0 AND strpos(substr(v.html, v.s), '<p><strong>§ 3º</strong>') > 0
                THEN substr(v.html, v.s, strpos(substr(v.html, v.s), '<p><strong>§ 3º</strong>') - 1) END AS block
    FROM v
  ),
  paras AS (
    SELECT blk.version_number,
           (SELECT jsonb_agg(btrim(replace(replace(regexp_replace(t.m[1], '<[^>]+>', '', 'g'), '&nbsp;', ' '), '&amp;', '&'))
                             ORDER BY t.ord)
            FROM regexp_matches(blk.block, '<p>(.*?)</p>', 'g') WITH ORDINALITY AS t(m, ord)) AS list
    FROM blk
  )
  SELECT CASE
    WHEN jsonb_array_length(p.list) = 3
     AND p.list->>0 LIKE 'Cláusula 11. %' AND p.list->>1 LIKE '§ 1º %' AND p.list->>2 LIKE '§ 2º %'
    THEN jsonb_build_object(
      'paragraphs', p.list,
      'version', 'termo-v' || p.version_number || ':cl11:' || left(md5(p.list::text), 8))
  END
  FROM paras p;
$function$;

-- a foto pública só com o nome opaco, neste projeto e neste bucket
CREATE OR REPLACE FUNCTION public._public_member_photo_url(p_url text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT CASE
    WHEN p_url ~ '^https://ldrfrvwhxsmgaabwmaik\.supabase\.co/storage/v1/object/public/member-photos/avatars/[0-9a-f]{32}\.(jpg|png)(\?t=[0-9]{1,16})?$'
    THEN p_url
  END;
$function$;

REVOKE ALL ON FUNCTION public._member_current_term(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._member_term_has_image_clause(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._member_has_image_consent(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._current_term_image_clause() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._public_member_photo_url(text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._member_current_term(uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public._member_term_has_image_clause(uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public._member_has_image_consent(uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public._current_term_image_clause() TO service_role;
GRANT EXECUTE ON FUNCTION public._public_member_photo_url(text) TO service_role;

COMMENT ON FUNCTION public._member_has_image_consent(uuid) IS
  'Pertencimento (GP 26/10/2026, caminho A): fonte única do consentimento de imagem e voz para superfície pública. Vale a decisão explícita mais recente em consent_records image_voice_publicity (linha ativa = sim; só linhas revogadas = não); sem decisão, vale o termo vigente com a Cláusula 11 no texto assinado.';
COMMENT ON FUNCTION public._public_member_photo_url(text) IS
  'Pertencimento (GP 26/10/2026): devolve a URL da foto só quando é o objeto avatars/<32 hex>.(jpg|png) do bucket member-photos deste projeto; qualquer outra forma vira NULL.';

-- ── (2) o perfil: ler o próprio consentimento e revogá-lo ───────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.get_my_image_consent()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_member_id uuid;
BEGIN
  SELECT m.id INTO v_member_id FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_member_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = 'insufficient_privilege';
  END IF;
  RETURN jsonb_build_object(
    'active', public._member_has_image_consent(v_member_id),
    'term_signed', public._member_current_term(v_member_id) IS NOT NULL,
    'term_has_clause', public._member_term_has_image_clause(v_member_id),
    'clause', public._current_term_image_clause()
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.get_my_image_consent() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_my_image_consent() TO authenticated, service_role;

-- revoke_image_voice_consent: o corpo de #570, com um ramo a mais quando não há linha ativa
CREATE OR REPLACE FUNCTION public.revoke_image_voice_consent(p_reason text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_member_id uuid;
  v_revoked_id uuid;
  v_revoked_at timestamptz;
  v_reason text;
  v_term record;
BEGIN
  SELECT id INTO v_member_id FROM public.members WHERE auth_id = auth.uid();
  IF v_member_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = 'insufficient_privilege';
  END IF;

  v_reason := COALESCE(NULLIF(p_reason, ''), 'member self-service revocation');

  UPDATE public.consent_records
     SET revoked_at = now(),
         revocation_reason = v_reason
   WHERE member_id = v_member_id
     AND policy_type = 'image_voice_publicity'
     AND revoked_at IS NULL
  RETURNING id, revoked_at INTO v_revoked_id, v_revoked_at;

  IF v_revoked_id IS NULL THEN
    -- Já há uma revogação registrada: nada a gravar.
    IF EXISTS (SELECT 1 FROM public.consent_records cr
               WHERE cr.member_id = v_member_id AND cr.policy_type = 'image_voice_publicity') THEN
      RETURN jsonb_build_object('success', true, 'no_active_consent', true, 'is_active', false);
    END IF;
    -- Pertencimento (GP 26/10/2026, caminho A): sem nenhuma decisão no ledger, o consentimento vigente é o do termo
    -- assinado. A revogação nasce como linha revogada cuja aceitação é a assinatura do termo.
    SELECT c.id, c.issued_at, c.template_id, c.content_snapshot->>'body_version_id' AS body_version_id
      INTO v_term
    FROM public.certificates c
    WHERE c.id = public._member_current_term(v_member_id);
    INSERT INTO public.consent_records (
      member_id, policy_type, policy_version, policy_document_id, accepted_at, channel,
      revoked_at, revocation_reason, evidence, organization_id
    ) VALUES (
      v_member_id, 'image_voice_publicity', coalesce('termo:' || v_term.body_version_id, 'unversioned'),
      (SELECT gd.id FROM public.governance_documents gd WHERE gd.id::text = v_term.template_id),
      coalesce(v_term.issued_at, now()), 'platform_action', now(), v_reason,
      jsonb_strip_nulls(jsonb_build_object('basis', 'termo_clausula_11', 'certificate_id', v_term.id,
        'term_has_clause', public._member_term_has_image_clause(v_member_id))),
      (SELECT m.organization_id FROM public.members m WHERE m.id = v_member_id)
    ) RETURNING id, revoked_at INTO v_revoked_id, v_revoked_at;
  END IF;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes)
  VALUES (v_member_id, 'image_voice_consent_revoked', 'member', v_member_id,
    jsonb_build_object('consent_id', v_revoked_id, 'policy_type', 'image_voice_publicity',
                       'revoked_at', v_revoked_at, 'revocation_reason', v_reason));

  RETURN jsonb_build_object(
    'success', true, 'no_active_consent', false,
    'consent_id', v_revoked_id, 'revoked_at', v_revoked_at, 'is_active', false);
END;
$function$;

REVOKE ALL ON FUNCTION public.revoke_image_voice_consent(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.revoke_image_voice_consent(text) FROM anon;
GRANT EXECUTE ON FUNCTION public.revoke_image_voice_consent(text) TO authenticated, service_role;

COMMENT ON FUNCTION public.revoke_image_voice_consent(text) IS
  '#570 + pertencimento (GP 26/10/2026, caminho A): o membro revoga o consentimento de imagem e voz. Fecha a linha ativa; sem linha ativa e sem decisão anterior (consentimento pelo termo com a Cláusula 11), grava uma linha nascida revogada cuja aceitação é a assinatura do termo. Nunca apaga; sem efeito retroativo.';

-- ── (3) a liderança de cada linha, para o visitante ─────────────────────────────────────────────────────────────
-- Por linha ativa: nome, foto opaca e vídeo de apresentação de quem lidera (papel leader ou co_leader, a mesma
-- janela de vigência e o mesmo portão de confidencial da contagem da home), só quando a pessoa consentiu. O vídeo
-- sai só na linha de papel leader (é o pitch de quem lidera) e só no formato de vídeo único do YouTube. Sem id de
-- membro, sem contato.
CREATE OR REPLACE FUNCTION public.get_public_line_leaders()
 RETURNS TABLE(tribe_id integer, leader_name text, photo_url text, video_url text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  WITH live_engagements AS (
    SELECT e.person_id, e.role, i.legacy_tribe_id, i.kind, i.metadata
    FROM public.engagements e
    JOIN public.initiatives i ON i.id = e.initiative_id
    WHERE e.status = 'active'
      AND e.start_date <= CURRENT_DATE
      AND (e.end_date IS NULL OR e.end_date >= CURRENT_DATE)
      AND i.status = 'active'
      AND coalesce(i.visibility, 'standard') <> 'confidential'
      AND public.rls_can_see_initiative(i.id)
  ),
  leaders AS (
    SELECT DISTINCT ON (le.legacy_tribe_id, le.person_id) le.legacy_tribe_id, le.person_id, le.role
    FROM live_engagements le
    WHERE le.legacy_tribe_id IS NOT NULL AND le.role IN ('leader', 'co_leader')
    ORDER BY le.legacy_tribe_id, le.person_id, (le.role = 'leader') DESC
  )
  SELECT t.id,
         d.name,
         public._public_member_photo_url(d.photo_url),
         CASE WHEN l.role = 'leader'
               AND t.video_url ~ '^https://(www\.)?(youtube\.com/watch\?v=|youtu\.be/)[A-Za-z0-9_-]{11}$'
              THEN t.video_url END
  FROM leaders l
  JOIN public.tribes t ON t.id = l.legacy_tribe_id AND t.is_active = true
  JOIN LATERAL (
    SELECT mm.id, mm.name, mm.photo_url
    FROM public.members mm
    WHERE mm.person_id = l.person_id AND mm.is_active = true AND mm.current_cycle_active = true
    ORDER BY mm.id
    LIMIT 1
  ) d ON true
  WHERE public._member_has_image_consent(d.id)
    AND coalesce(d.name, '') <> ''
  ORDER BY t.id, (l.role = 'leader') DESC, d.name;
$function$;

REVOKE ALL ON FUNCTION public.get_public_line_leaders() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_public_line_leaders() TO anon, authenticated, service_role;

COMMENT ON FUNCTION public.get_public_line_leaders() IS
  'Pertencimento (GP 26/10/2026): por linha ativa, nome, foto opaca e vídeo de apresentação de quem lidera, só para quem tem o consentimento da Cláusula 11 (_member_has_image_consent). Sem id de membro e sem contato; lido ao vivo.';

-- ── (4) os rostos de "Quem faz", para o visitante ───────────────────────────────────────────────────────────────
-- Os grupos e os predicados são os de get_public_home_team (a home mostra a contagem dela; o "+N" é a contagem menos
-- os rostos). Por grupo, até 8 pessoas com consentimento e foto opaca, numa ordem que gira por dia (md5 do id com a
-- data), sem viés de nome. Presidências e pontos focais não são voluntários do termo: só os nomes dos capítulos.
CREATE OR REPLACE FUNCTION public.get_public_team_faces()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  WITH active_members AS (
    SELECT m.id, m.operational_role, coalesce(m.designations, '{}'::text[]) AS designations
    FROM public.members m
    WHERE m.is_active = true AND m.current_cycle_active = true
  ),
  live_engagements AS (
    SELECT e.person_id, e.role, i.legacy_tribe_id, i.kind, i.metadata
    FROM public.engagements e
    JOIN public.initiatives i ON i.id = e.initiative_id
    WHERE e.status = 'active'
      AND e.start_date <= CURRENT_DATE
      AND (e.end_date IS NULL OR e.end_date >= CURRENT_DATE)
      AND i.status = 'active'
      AND coalesce(i.visibility, 'standard') <> 'confidential'
      AND public.rls_can_see_initiative(i.id)
  ),
  roster AS (
    SELECT 'management'::text AS team_group, a.id AS who, a.id AS member_id, NULL::uuid AS person_id
    FROM active_members a
    WHERE a.operational_role IN ('manager', 'deputy_manager') OR 'co_gp' = ANY (a.designations)
    UNION ALL
    SELECT 'line_leaders', le.person_id, NULL, le.person_id
    FROM live_engagements le
    WHERE le.legacy_tribe_id IS NOT NULL AND le.role IN ('leader', 'co_leader')
    UNION ALL
    SELECT 'initiative_leaders', le.person_id, NULL, le.person_id
    FROM live_engagements le
    WHERE le.legacy_tribe_id IS NULL AND le.kind <> 'community_vertical'
        AND le.role IN ('leader', 'co_leader', 'coordinator', 'owner')
    UNION ALL
    SELECT 'curators', le.person_id, NULL, le.person_id
    FROM live_engagements le WHERE le.role = 'curator'
    UNION ALL
    SELECT 'curators', coalesce(m.person_id, m.id), m.id, m.person_id
    FROM public.members m WHERE m.id IN (SELECT public._wiki_committee_ids())
    UNION ALL
    SELECT 'hub_members', le.person_id, NULL, le.person_id
    FROM live_engagements le
    WHERE le.kind = 'workgroup' AND coalesce((le.metadata->>'landing_arm')::boolean, false) = true
    UNION ALL
    SELECT 'researchers', om.id, om.id, NULL
    FROM public.v_operational_members om
  ),
  focal AS (
    SELECT a.id AS who
    FROM active_members a
    WHERE a.operational_role IN ('sponsor', 'chapter_liaison')
         OR a.designations && ARRAY['sponsor', 'chapter_liaison']::text[]
  ),
  resolved AS (
    SELECT DISTINCT ON (r.team_group, r.who) r.team_group, r.who, d.id AS member_id, d.name, d.photo_url
    FROM roster r
    JOIN LATERAL (
      SELECT mm.id, mm.name, mm.photo_url
      FROM public.members mm
      WHERE (mm.id = r.member_id OR (r.member_id IS NULL AND mm.person_id = r.person_id))
        AND mm.is_active = true AND mm.current_cycle_active = true
      ORDER BY mm.id
      LIMIT 1
    ) d ON true
    ORDER BY r.team_group, r.who, r.member_id NULLS LAST
  ),
  faces AS (
    SELECT x.team_group, x.name, x.photo_url,
           row_number() OVER (PARTITION BY x.team_group ORDER BY md5(x.who::text || CURRENT_DATE::text)) AS rn
    FROM (
      SELECT r.team_group, r.who, r.name, public._public_member_photo_url(r.photo_url) AS photo_url
      FROM resolved r
      WHERE public._member_has_image_consent(r.member_id)
    ) x
    WHERE x.photo_url IS NOT NULL AND coalesce(x.name, '') <> ''
  )
  SELECT jsonb_build_object(
    'faces', (
      SELECT jsonb_object_agg(g.team_group, coalesce((
               SELECT jsonb_agg(jsonb_build_object('name', f.name, 'photo_url', f.photo_url) ORDER BY f.rn)
               FROM faces f
               WHERE f.team_group = g.team_group AND f.rn <= 8
             ), '[]'::jsonb))
      FROM unnest(ARRAY['management', 'line_leaders', 'initiative_leaders', 'curators', 'hub_members', 'researchers']) AS g(team_group)
    ),
    'focal_point_chapters', (
      SELECT coalesce(jsonb_agg(DISTINCT mm.chapter ORDER BY mm.chapter), '[]'::jsonb)
      FROM focal f
      JOIN public.members mm ON mm.id = f.who
      WHERE coalesce(mm.chapter, '') <> ''
    )
  );
$function$;

REVOKE ALL ON FUNCTION public.get_public_team_faces() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_public_team_faces() TO anon, authenticated, service_role;

COMMENT ON FUNCTION public.get_public_team_faces() IS
  'Pertencimento (GP 26/10/2026): por grupo de "Quem faz" (os predicados de get_public_home_team), até 8 rostos (nome e foto opaca) de quem tem o consentimento da Cláusula 11; para presidências e pontos focais, só os nomes dos capítulos. Sem id, sem contato; lido ao vivo.';

-- ── (5) pós-condição ────────────────────────────────────────────────────────────────────────────────────────────
DO $postcondition$
DECLARE
  v_role text := current_user;
  v_with int;
  v_without int;
  v_rejected uuid;
  v_leaders jsonb;
  v_faces jsonb;
  v_clause jsonb;
  v_expected int;
  v_bad int;
  v_denied int := 0;
  -- quem tem a cláusula no termo e lidera uma linha
  v_new uuid; v_new_auth uuid; v_new_line int; v_new_name text;
  -- quem assinou antes da cláusula
  v_old uuid; v_old_auth uuid; v_old_line int; v_old_name text;
  v_steps text[] := '{}';
  v_comms_consistent boolean := true;
BEGIN
  -- catálogo: as leitoras são SECURITY DEFINER com search_path fixo e EXECUTE para anon; os ajudantes não executam
  -- para anon nem authenticated; as funções do perfil não executam para anon
  IF NOT EXISTS (SELECT 1 FROM pg_proc p WHERE p.oid = 'public.get_public_line_leaders()'::regprocedure AND p.prosecdef
                   AND p.proconfig @> ARRAY['search_path=public, pg_temp'])
     OR NOT EXISTS (SELECT 1 FROM pg_proc p WHERE p.oid = 'public.get_public_team_faces()'::regprocedure AND p.prosecdef
                   AND p.proconfig @> ARRAY['search_path=public, pg_temp'])
     OR NOT has_function_privilege('anon', 'public.get_public_line_leaders()', 'EXECUTE')
     OR NOT has_function_privilege('anon', 'public.get_public_team_faces()', 'EXECUTE')
     OR has_function_privilege('anon', 'public._member_has_image_consent(uuid)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public._member_has_image_consent(uuid)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public._current_term_image_clause()', 'EXECUTE')
     OR has_function_privilege('anon', 'public._public_member_photo_url(text)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.get_my_image_consent()', 'EXECUTE')
     OR has_function_privilege('anon', 'public.grant_image_voice_consent(jsonb)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.revoke_image_voice_consent(text)', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.grant_image_voice_consent(jsonb)', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.revoke_image_voice_consent(text)', 'EXECUTE')
     OR pg_get_function_result('public.get_public_line_leaders()'::regprocedure)
        IS DISTINCT FROM 'TABLE(tribe_id integer, leader_name text, photo_url text, video_url text)'
  THEN
    RAISE EXCEPTION 'clausula 11: catálogo fora do esperado';
  END IF;

  -- o casador da foto: o nome opaco passa; e-mail no nome, outro bucket, outro host e sufixo estranho não passam
  IF public._public_member_photo_url('https://ldrfrvwhxsmgaabwmaik.supabase.co/storage/v1/object/public/member-photos/avatars/0123456789abcdef0123456789abcdef.jpg?t=1790000000000') IS NULL
     OR public._public_member_photo_url('https://ldrfrvwhxsmgaabwmaik.supabase.co/storage/v1/object/public/member-photos/avatars/0123456789abcdef0123456789abcdef.png') IS NULL
     OR public._public_member_photo_url('https://ldrfrvwhxsmgaabwmaik.supabase.co/storage/v1/object/public/member-photos/avatars/fulano_example_com.jpg') IS NOT NULL
     OR public._public_member_photo_url('https://ldrfrvwhxsmgaabwmaik.supabase.co/storage/v1/object/public/outro-bucket/avatars/0123456789abcdef0123456789abcdef.jpg') IS NOT NULL
     OR public._public_member_photo_url('https://example.supabase.co/storage/v1/object/public/member-photos/avatars/0123456789abcdef0123456789abcdef.jpg') IS NOT NULL
     OR public._public_member_photo_url('https://ldrfrvwhxsmgaabwmaik.supabase.co/storage/v1/object/public/member-photos/avatars/0123456789abcdef0123456789abcdef.jpg?email=x') IS NOT NULL
  THEN
    RAISE EXCEPTION 'clausula 11: o casador da foto não discrimina';
  END IF;

  -- o texto da cláusula exibido no perfil: caput, § 1º e § 2º da versão ativa, com identificador
  v_clause := public._current_term_image_clause();
  IF v_clause IS NULL OR jsonb_array_length(v_clause->'paragraphs') <> 3 OR coalesce(v_clause->>'version', '') !~ '^termo-v[0-9]+:cl11:[0-9a-f]{8}$' THEN
    RAISE EXCEPTION 'clausula 11: o texto da cláusula não foi lido do termo ativo';
  END IF;

  -- o casador da cláusula, com controle nos dois lados: há quem tenha (positivo) e quem não tenha (negativo) a
  -- cláusula no termo vigente, e um termo fora de vigor com a cláusula não conta
  SELECT count(*) FILTER (WHERE public._member_term_has_image_clause(m.id)),
         count(*) FILTER (WHERE public._member_current_term(m.id) IS NOT NULL AND NOT public._member_term_has_image_clause(m.id))
    INTO v_with, v_without
  FROM public.members m WHERE m.is_active;
  IF v_with = 0 OR v_without = 0 THEN
    RAISE EXCEPTION 'clausula 11: o casador não tem controle nos dois lados (com % / sem %)', v_with, v_without;
  END IF;
  SELECT c.member_id INTO v_rejected FROM public.certificates c
  WHERE c.type = 'volunteer_agreement' AND c.status <> 'issued'
    AND strpos(coalesce(c.content_snapshot->>'html_body', ''), 'autoriza o uso de sua imagem e de sua voz') > 0
    AND NOT EXISTS (SELECT 1 FROM public.certificates c2 WHERE c2.member_id = c.member_id
                    AND c2.type = 'volunteer_agreement' AND c2.status = 'issued')
    AND NOT EXISTS (SELECT 1 FROM public.consent_records cr WHERE cr.member_id = c.member_id
                    AND cr.policy_type = 'image_voice_publicity')
  LIMIT 1;
  IF v_rejected IS NOT NULL AND public._member_has_image_consent(v_rejected) THEN
    RAISE EXCEPTION 'clausula 11: termo fora de vigor com a cláusula contou como consentimento';
  END IF;

  -- como anon: as duas leitoras respondem; o que anon recebe vai para variáveis, lidas depois como o dono
  PERFORM set_config('request.jwt.claims', '{"role":"anon"}', true);
  EXECUTE 'SET LOCAL ROLE anon';
  SELECT coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) INTO v_leaders FROM public.get_public_line_leaders() x;
  v_faces := public.get_public_team_faces();
  BEGIN
    PERFORM public._member_has_image_consent(NULL::uuid);
  EXCEPTION WHEN insufficient_privilege THEN v_denied := v_denied + 1;
  END;
  BEGIN
    PERFORM public.revoke_image_voice_consent(NULL);
  EXCEPTION WHEN insufficient_privilege THEN v_denied := v_denied + 1;
  END;
  EXECUTE format('SET LOCAL ROLE %I', v_role);
  PERFORM set_config('request.jwt.claims', '', true);
  IF v_denied <> 2 THEN
    RAISE EXCEPTION 'clausula 11: anon executou ajudante ou função do perfil (% de 2 recusas)', v_denied;
  END IF;

  -- a liderança: só as quatro chaves, só linha ativa, foto só opaca, vídeo só do YouTube, e a contagem bate com a
  -- mesma regra escrita por outro caminho (EXISTS)
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(v_leaders) r, jsonb_object_keys(r) k
             WHERE k NOT IN ('tribe_id', 'leader_name', 'photo_url', 'video_url')) THEN
    RAISE EXCEPTION 'clausula 11: a liderança levou chave além das quatro';
  END IF;
  SELECT count(*) INTO v_bad FROM jsonb_array_elements(v_leaders) r
  WHERE NOT EXISTS (SELECT 1 FROM public.tribes t WHERE t.id = (r->>'tribe_id')::int AND t.is_active)
     OR coalesce(r->>'leader_name', '') = ''
     OR (r->>'photo_url' IS NOT NULL AND public._public_member_photo_url(r->>'photo_url') IS NULL)
     OR (r->>'video_url' IS NOT NULL AND r->>'video_url' !~ '^https://(www\.)?(youtube\.com/watch\?v=|youtu\.be/)');
  IF v_bad > 0 THEN
    RAISE EXCEPTION 'clausula 11: % linhas da liderança fora da regra', v_bad;
  END IF;
  SELECT count(*) INTO v_expected
  FROM public.tribes t
  JOIN public.members m ON EXISTS (
    SELECT 1 FROM public.engagements e JOIN public.initiatives i ON i.id = e.initiative_id
    WHERE i.legacy_tribe_id = t.id AND i.status = 'active' AND coalesce(i.visibility, 'standard') <> 'confidential'
      AND e.person_id = m.person_id AND e.role IN ('leader', 'co_leader') AND e.status = 'active'
      AND e.start_date <= CURRENT_DATE AND (e.end_date IS NULL OR e.end_date >= CURRENT_DATE))
  WHERE t.is_active AND m.is_active AND m.current_cycle_active AND public._member_has_image_consent(m.id);
  IF jsonb_array_length(v_leaders) <> v_expected THEN
    RAISE EXCEPTION 'clausula 11: anon leu % lideranças e a regra por outro caminho dá %', jsonb_array_length(v_leaders), v_expected;
  END IF;

  -- os rostos: os seis grupos, cada um com até 8, cada rosto só com nome e foto opaca, nunca mais que a contagem da
  -- home; os pontos focais só como nomes de capítulo
  IF (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(v_faces) k) IS DISTINCT FROM ARRAY['faces', 'focal_point_chapters']
     OR (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(v_faces->'faces') k)
        IS DISTINCT FROM ARRAY['curators', 'hub_members', 'initiative_leaders', 'line_leaders', 'management', 'researchers']
  THEN
    RAISE EXCEPTION 'clausula 11: forma dos rostos fora do esperado';
  END IF;
  SELECT count(*) INTO v_bad
  FROM jsonb_each(v_faces->'faces') g
  WHERE jsonb_array_length(g.value) > 8
     OR jsonb_array_length(g.value) > (public.get_public_home_team()->>g.key)::int
     OR EXISTS (SELECT 1 FROM jsonb_array_elements(g.value) f, jsonb_object_keys(f) k WHERE k NOT IN ('name', 'photo_url'))
     OR EXISTS (SELECT 1 FROM jsonb_array_elements(g.value) f
                WHERE coalesce(f->>'name', '') = '' OR public._public_member_photo_url(f->>'photo_url') IS NULL);
  IF v_bad > 0 THEN
    RAISE EXCEPTION 'clausula 11: % grupos de rostos fora da regra', v_bad;
  END IF;
  IF jsonb_array_length(v_faces->'focal_point_chapters') = 0
     OR EXISTS (SELECT 1 FROM jsonb_array_elements(v_faces->'focal_point_chapters') c WHERE jsonb_typeof(c) <> 'string')
  THEN
    RAISE EXCEPTION 'clausula 11: os capítulos dos pontos focais não vieram como lista de nomes';
  END IF;

  -- as sondas (achadas aqui, sem id fixo): uma liderança com a cláusula, com login e sem decisão no ledger; e alguém que
  -- assinou antes da cláusula, com login e sem decisão no ledger, de preferência uma liderança de linha
  SELECT m.id, m.auth_id, t.id, m.name INTO v_new, v_new_auth, v_new_line, v_new_name
  FROM public.tribes t
  JOIN public.initiatives i ON i.legacy_tribe_id = t.id AND i.status = 'active'
  JOIN public.engagements e ON e.initiative_id = i.id AND e.role = 'leader' AND e.status = 'active'
    AND e.start_date <= CURRENT_DATE AND (e.end_date IS NULL OR e.end_date >= CURRENT_DATE)
  JOIN public.members m ON m.person_id = e.person_id AND m.is_active AND m.current_cycle_active
  WHERE t.is_active AND m.auth_id IS NOT NULL AND public._member_term_has_image_clause(m.id)
    AND NOT EXISTS (SELECT 1 FROM public.consent_records cr WHERE cr.member_id = m.id AND cr.policy_type = 'image_voice_publicity')
  ORDER BY t.id, m.id LIMIT 1;
  SELECT m.id, m.auth_id, t.id, m.name INTO v_old, v_old_auth, v_old_line, v_old_name
  FROM public.members m
  LEFT JOIN LATERAL (
    SELECT t.id FROM public.tribes t
    JOIN public.initiatives i ON i.legacy_tribe_id = t.id AND i.status = 'active'
    JOIN public.engagements e ON e.initiative_id = i.id AND e.role = 'leader' AND e.status = 'active'
      AND e.start_date <= CURRENT_DATE AND (e.end_date IS NULL OR e.end_date >= CURRENT_DATE)
    WHERE t.is_active AND e.person_id = m.person_id
    ORDER BY t.id LIMIT 1
  ) t ON true
  WHERE m.is_active AND m.current_cycle_active AND m.auth_id IS NOT NULL
    AND public._member_current_term(m.id) IS NOT NULL AND NOT public._member_term_has_image_clause(m.id)
    AND NOT EXISTS (SELECT 1 FROM public.consent_records cr WHERE cr.member_id = m.id AND cr.policy_type = 'image_voice_publicity')
  ORDER BY (t.id IS NULL), t.id, m.id LIMIT 1;
  IF v_new IS NULL OR v_old IS NULL THEN
    RAISE EXCEPTION 'clausula 11: sem sonda para exercer o perfil (com cláusula %, antes da cláusula %)', v_new IS NOT NULL, v_old IS NOT NULL;
  END IF;

  -- o perfil exercido numa subtransação desfeita no fim; cada passo guarda "nome do passo=consentimento depois"
  BEGIN
    -- quem assinou antes: sem decisão, o termo decide (não); autoriza, revoga, autoriza de novo
    v_steps := v_steps || ('antes:inicio=' || public._member_has_image_consent(v_old));
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_old_auth, 'role', 'authenticated')::text, true);
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM public.grant_image_voice_consent(jsonb_build_object('displayed_version', (v_clause->>'version') || ':pt-BR'));
    EXECUTE format('SET LOCAL ROLE %I', v_role);
    v_steps := v_steps || ('antes:autoriza=' || public._member_has_image_consent(v_old));
    IF v_old_line IS NOT NULL THEN
      v_steps := v_steps || ('antes:linha=' || (SELECT count(*) FROM public.get_public_line_leaders() x
                                                WHERE x.tribe_id = v_old_line AND x.leader_name = v_old_name));
    END IF;
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM public.revoke_image_voice_consent('perfil');
    EXECUTE format('SET LOCAL ROLE %I', v_role);
    v_steps := v_steps || ('antes:revoga=' || public._member_has_image_consent(v_old));
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM public.grant_image_voice_consent(jsonb_build_object('displayed_version', (v_clause->>'version') || ':pt-BR'));
    EXECUTE format('SET LOCAL ROLE %I', v_role);
    v_steps := v_steps || ('antes:reautoriza=' || public._member_has_image_consent(v_old));
    v_steps := v_steps || ('antes:linhas_no_ledger=' || (SELECT count(*) FROM public.consent_records cr
                                                         WHERE cr.member_id = v_old AND cr.policy_type = 'image_voice_publicity'));
    -- quem tem a cláusula: sem decisão, o termo decide (sim); revoga e sai da linha
    v_steps := v_steps || ('clausula:inicio=' || public._member_has_image_consent(v_new));
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_new_auth, 'role', 'authenticated')::text, true);
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM public.revoke_image_voice_consent('perfil');
    EXECUTE format('SET LOCAL ROLE %I', v_role);
    v_steps := v_steps || ('clausula:revoga=' || public._member_has_image_consent(v_new));
    v_steps := v_steps || ('clausula:linha=' || (SELECT count(*) FROM public.get_public_line_leaders() x
                                                 WHERE x.tribe_id = v_new_line AND x.leader_name = v_new_name));
    -- a regra e a liberação de comunicação (#729) concordam nas duas sondas: revogado lá é "não" aqui
    v_comms_consistent := (SELECT bool_and(
        (NOT public._member_has_image_consent(s.id)) = (
          EXISTS (SELECT 1 FROM public.consent_records cr WHERE cr.member_id = s.id
                    AND cr.policy_type = 'image_voice_publicity' AND cr.revoked_at IS NOT NULL)
          AND NOT EXISTS (SELECT 1 FROM public.consent_records cr WHERE cr.member_id = s.id
                    AND cr.policy_type = 'image_voice_publicity' AND cr.revoked_at IS NULL)))
      FROM (VALUES (v_old), (v_new)) s(id));
    PERFORM set_config('request.jwt.claims', '', true);
    RAISE EXCEPTION USING ERRCODE = 'ZC011', MESSAGE = 'desfaz a sonda';
  EXCEPTION WHEN SQLSTATE 'ZC011' THEN
    NULL;
  END;

  IF v_steps IS DISTINCT FROM (ARRAY['antes:inicio=false', 'antes:autoriza=true']
       || CASE WHEN v_old_line IS NOT NULL THEN ARRAY['antes:linha=1'] ELSE '{}'::text[] END
       || ARRAY['antes:revoga=false', 'antes:reautoriza=true', 'antes:linhas_no_ledger=2',
                'clausula:inicio=true', 'clausula:revoga=false', 'clausula:linha=0'])
     OR NOT v_comms_consistent THEN
    RAISE EXCEPTION 'clausula 11: o perfil não mudou a regra como esperado (passos %, comunicação %)', v_steps, v_comms_consistent;
  END IF;
  -- resíduo zero: a sonda foi desfeita, o ledger e o audit não ganharam linha das sondas, e o consentimento voltou
  IF EXISTS (SELECT 1 FROM public.consent_records cr WHERE cr.member_id IN (v_old, v_new) AND cr.policy_type = 'image_voice_publicity')
     OR EXISTS (SELECT 1 FROM public.admin_audit_log a WHERE a.target_id IN (v_old, v_new)
                AND a.action IN ('image_voice_consent_granted', 'image_voice_consent_revoked') AND a.created_at >= now())
     OR public._member_has_image_consent(v_old) OR NOT public._member_has_image_consent(v_new) THEN
    RAISE EXCEPTION 'clausula 11: a sonda deixou rastro';
  END IF;

  RAISE NOTICE 'clausula 11: % lideranças com consentimento; rostos por grupo %; % capítulos de pontos focais; perfil %',
    jsonb_array_length(v_leaders),
    (SELECT jsonb_object_agg(g.key, jsonb_array_length(g.value)) FROM jsonb_each(v_faces->'faces') g),
    jsonb_array_length(v_faces->'focal_point_chapters'), v_steps;
END;
$postcondition$;

NOTIFY pgrst, 'reload schema';
