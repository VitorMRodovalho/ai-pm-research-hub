-- Leitura por papel: tabelas de membro deixam de responder a quem nao tem linha em members.
--
-- Regra aplicada, por superficie:
--   * "membro" = public.rls_is_member() (existe linha em members para auth.uid()). Nao muda o
--     acesso de nenhum membro, alumni ou convidado; so tira quem nao e membro.
--   * certificates: o dono do certificado, ou quem tem as capacidades das RPCs de certificado
--     (curate_content emite/edita, manage_member contra-assina/rejeita, manage_platform emite em lote).
--   * meeting_action_items: membro, e o gate de confidencialidade da ADR-0105 pelo evento e pelo
--     card de origem (helpers SECURITY DEFINER existentes, que resolvem o pai sem depender da RLS
--     dele: uma subconsulta direta em events devolveria NULL para evento invisivel, e
--     rls_can_see_initiative(NULL) e verdadeiro).
--   * events: as linhas geral/webinar seguem publicas (Track R); ata, notas, historico de edicao da
--     ata e participantes externos deixam de ser colunas legiveis por anon/authenticated. A home le
--     so colunas da lista abaixo, e as views sobre events tambem. As RPCs SECURITY DEFINER que
--     servem a ata a membros nao dependem deste grant.
--     ⚠️ Grant por coluna NAO cobre coluna nova: quem adicionar coluna a events e quiser que anon ou
--     authenticated a leiam diretamente precisa de GRANT SELECT (coluna) explicito.
--   * Storage: partner-attachments le com view_partner/manage_partner/manage_platform e escreve com
--     manage_partner/manage_platform (os gates das RPCs de parceria); upload em documents/knowledge-pdfs
--     exige can_manage_knowledge().
--   * RPCs do wiki passam a SECURITY INVOKER: so leem wiki_pages, entao a RLS dela decide. O MCP chama
--     com o JWT do membro e segue funcionando.
--   * Funcoes de auditoria/teste: EXECUTE so para service_role (todos os chamadores usam essa chave).
--   * member_resolve_email: sai do anon; o MCP chama autenticado.

-- ── certificates ────────────────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS read_own_certificates ON public.certificates;
CREATE POLICY read_own_certificates ON public.certificates
  FOR SELECT TO authenticated
  USING (
    member_id IN (SELECT m.id FROM public.members m WHERE m.auth_id = (SELECT auth.uid()))
    OR (SELECT public.rls_can('curate_content'))
    OR (SELECT public.rls_can('manage_member'))
    OR (SELECT public.rls_can('manage_platform'))
  );

-- anon nao tem GRANT em certificates; a verificacao publica e pela RPC verify_certificate.
DROP POLICY IF EXISTS public_verify_certificates ON public.certificates;

-- ── meeting_action_items ────────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "Authenticated can read action items" ON public.meeting_action_items;
CREATE POLICY action_items_read_member ON public.meeting_action_items
  FOR SELECT TO authenticated
  USING ((SELECT public.rls_is_member()));

CREATE POLICY action_items_confidential_visibility ON public.meeting_action_items
  AS RESTRICTIVE FOR SELECT
  USING (
    public.rls_can_see_artifact_link(NULL::uuid, event_id)
    AND (board_item_id IS NULL OR public.rls_can_see_item(board_item_id))
  );

-- ── wiki_pages ──────────────────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS wiki_pages_read ON public.wiki_pages;
CREATE POLICY wiki_pages_read ON public.wiki_pages
  FOR SELECT TO authenticated
  USING ((SELECT public.rls_is_member()));

ALTER FUNCTION public.get_wiki_page(text) SECURITY INVOKER;
ALTER FUNCTION public.search_wiki_pages(text, integer, text, text) SECURITY INVOKER;
ALTER FUNCTION public.get_decision_log(text) SECURITY INVOKER;
ALTER FUNCTION public.wiki_health_report() SECURITY INVOKER;

-- ── hub_resources ───────────────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS hub_resources_select_authenticated ON public.hub_resources;
CREATE POLICY hub_resources_select_authenticated ON public.hub_resources
  FOR SELECT TO authenticated
  USING (((is_active = true) AND (SELECT public.rls_is_member())) OR public.can_manage_knowledge());

-- ── credly_badge_decisions ──────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS credly_badge_decisions_read_auth ON public.credly_badge_decisions;
CREATE POLICY credly_badge_decisions_read_auth ON public.credly_badge_decisions
  FOR SELECT TO authenticated
  USING ((SELECT public.rls_is_member()));

-- ── knowledge_* ─────────────────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS knowledge_insights_read ON public.knowledge_insights;
CREATE POLICY knowledge_insights_read ON public.knowledge_insights
  FOR SELECT TO authenticated
  USING ((SELECT public.rls_is_member()));

DROP POLICY IF EXISTS knowledge_assets_read ON public.knowledge_assets;
CREATE POLICY knowledge_assets_read ON public.knowledge_assets
  FOR SELECT TO authenticated
  USING ((is_active = true) AND (SELECT public.rls_is_member()));

DROP POLICY IF EXISTS knowledge_chunks_read ON public.knowledge_chunks;
CREATE POLICY knowledge_chunks_read ON public.knowledge_chunks
  FOR SELECT TO authenticated
  USING (
    (SELECT public.rls_is_member())
    AND EXISTS (SELECT 1 FROM public.knowledge_assets a WHERE a.id = knowledge_chunks.asset_id AND a.is_active = true)
  );

-- ── site_config ─────────────────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS site_config_read_authenticated ON public.site_config;
CREATE POLICY site_config_read_authenticated ON public.site_config
  FOR SELECT TO authenticated
  USING (
    public.rls_is_superadmin()
    OR public.rls_can('manage_member'::text)
    OR (
      (SELECT public.rls_is_member())
      AND key = ANY (ARRAY['whatsapp_gp'::text, 'general_meeting_link'::text, 'group_term'::text,
                           'attendance_risk_threshold'::text, 'attendance_weight_geral'::text,
                           'attendance_weight_tribo'::text, 'comms_calendar_embed_url'::text])
    )
  );

-- ── events: colunas legiveis ────────────────────────────────────────────────────────────────────
REVOKE SELECT ON public.events FROM anon, authenticated;
GRANT SELECT (
  id, type, title, date, duration_minutes, created_by, created_at, updated_at, meeting_link,
  recurrence_group, is_recorded, youtube_url, audience_level, duration_actual, source,
  calendar_event_id, curation_status, agenda_text, agenda_url, agenda_posted_at, agenda_posted_by,
  minutes_url, minutes_posted_at, minutes_posted_by, recording_url, recording_type, visibility,
  invited_member_ids, selection_application_id, nature, time_start, organization_id, initiative_id,
  minutes_edited_at, artia_activity_id, artia_synced_at, external_calendar_provider, timezone,
  last_synced_at, sync_status, rescheduled_from, title_i18n, status, cancelled_at, cancelled_by,
  cancellation_reason, suggested_champion_ids, roster_sealed_at
) ON public.events TO anon, authenticated;

-- ── Storage ─────────────────────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "Authenticated users can read partner attachments" ON storage.objects;
CREATE POLICY "Authenticated users can read partner attachments" ON storage.objects
  FOR SELECT TO authenticated
  USING (
    bucket_id = 'partner-attachments'
    AND ((SELECT public.rls_can('view_partner')) OR (SELECT public.rls_can('manage_partner'))
         OR (SELECT public.rls_can('manage_platform')))
  );

DROP POLICY IF EXISTS "Authenticated users can upload partner attachments" ON storage.objects;
CREATE POLICY "Authenticated users can upload partner attachments" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'partner-attachments'
    AND ((SELECT public.rls_can('manage_partner')) OR (SELECT public.rls_can('manage_platform')))
  );

DROP POLICY IF EXISTS "Authenticated users can delete partner attachments" ON storage.objects;
CREATE POLICY "Authenticated users can delete partner attachments" ON storage.objects
  FOR DELETE TO authenticated
  USING (
    bucket_id = 'partner-attachments'
    AND ((SELECT public.rls_can('manage_partner')) OR (SELECT public.rls_can('manage_platform')))
  );

DROP POLICY IF EXISTS "Authenticated upload to knowledge-pdfs" ON storage.objects;
CREATE POLICY "Authenticated upload to knowledge-pdfs" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'documents'
    AND (storage.foldername(name))[1] = 'knowledge-pdfs'
    AND public.can_manage_knowledge()
  );

-- ── RPCs de auditoria/teste: so service_role ────────────────────────────────────────────────────
REVOKE EXECUTE ON FUNCTION public._audit_list_public_function_bodies() FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public._audit_list_public_function_bodies() TO service_role;
REVOKE EXECUTE ON FUNCTION public._audit_list_schema_migrations() FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public._audit_list_schema_migrations() TO service_role;
REVOKE EXECUTE ON FUNCTION public._audit_secdef_initiative_reader_gates() FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public._audit_secdef_initiative_reader_gates() TO service_role;
REVOKE EXECUTE ON FUNCTION public.check_schema_invariants() FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.check_schema_invariants() TO service_role;
REVOKE EXECUTE ON FUNCTION public._credly_health_rows() FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public._credly_health_rows() TO service_role;
REVOKE EXECUTE ON FUNCTION public._audit_merit_transfer_on_completed_cards() FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public._audit_merit_transfer_on_completed_cards() TO service_role;
REVOKE EXECUTE ON FUNCTION public._test_detect_inactive_with_threshold(integer) FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public._test_detect_inactive_with_threshold(integer) TO service_role;

REVOKE EXECUTE ON FUNCTION public.member_resolve_email(text) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.member_resolve_email(text) TO authenticated, service_role;

-- ── Instrumento do guard: leitura como nao-membro, derivada do catalogo ─────────────────────────
-- Lista toda relacao de public legivel por authenticated. has_any_column_privilege, e nao
-- has_table_privilege: uma tabela com grant so por coluna (events, acima) sumiria da lista.
CREATE OR REPLACE FUNCTION public._audit_ghost_read_catalog()
RETURNS TABLE (relname text, relkind text, est_rows bigint)
LANGUAGE sql
STABLE
SET search_path = ''
AS $$
  SELECT c.relname::text, c.relkind::text, greatest(c.reltuples, 0)::bigint
    FROM pg_catalog.pg_class c
    JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
   WHERE n.nspname = 'public'
     AND c.relkind IN ('r', 'p', 'v', 'm')
     AND pg_catalog.has_any_column_privilege('authenticated', c.oid, 'SELECT')
   ORDER BY 1
$$;

-- Le UMA relacao como um usuario autenticado sem linha em members (uuid sintetico), pelo motor de
-- RLS de verdade: SET LOCAL ROLE authenticated com os claims do sintetico. Por isso e SECURITY
-- INVOKER (SET ROLE e proibido dentro de SECURITY DEFINER) e so service_role executa.
-- Tabela com mais de 5000 linhas estimadas e lida por amostra BERNOULLI de ~2000 linhas: a RLS e
-- avaliada por linha e algumas policies custam ~1,4 ms/linha, o que estouraria o statement_timeout.
-- A amostra pega policy aberta por inteiro; vazamento de poucas linhas numa tabela grande pode
-- escapar, e o retorno diz `sampled` para o leitor saber qual foi o caso.
CREATE OR REPLACE FUNCTION public._audit_ghost_read_probe(p_relname text)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SET search_path = ''
AS $$
DECLARE
  v_orig_role   text := current_user;
  v_orig_claims text := current_setting('request.jwt.claims', true);
  v_kind        text;
  v_est         bigint;
  v_sample      text := '';
  v_n           int;
  v_err         text;
  v_t0          timestamptz := clock_timestamp();
BEGIN
  SELECT c.relkind::text, greatest(c.reltuples, 0)::bigint INTO v_kind, v_est
    FROM pg_catalog.pg_class c
    JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
   WHERE n.nspname = 'public' AND c.relname = p_relname;
  IF v_kind IS NULL THEN
    RETURN jsonb_build_object('relname', p_relname, 'error', 'relation not found');
  END IF;

  IF v_kind IN ('r', 'p', 'm') AND v_est > 5000 THEN
    v_sample := format(' TABLESAMPLE BERNOULLI (%s)', round(200000.0 / v_est, 4));
  END IF;

  PERFORM pg_catalog.set_config('request.jwt.claims',
    pg_catalog.json_build_object('sub', '00000000-0000-4000-8000-000000000000',
                                 'role', 'authenticated', 'aud', 'authenticated',
                                 'email', 'ghost-probe@audit.invalid')::text, true);
  EXECUTE 'SET LOCAL ROLE authenticated';
  BEGIN
    EXECUTE format('SELECT count(*) FROM (SELECT 1 FROM public.%I%s LIMIT 1) s', p_relname, v_sample)
      INTO v_n;
  EXCEPTION WHEN OTHERS THEN
    v_err := SQLERRM;
  END;
  EXECUTE format('SET LOCAL ROLE %I', v_orig_role);
  PERFORM pg_catalog.set_config('request.jwt.claims', coalesce(v_orig_claims, ''), true);

  RETURN jsonb_build_object(
    'relname', p_relname, 'relkind', v_kind, 'ghost_rows', v_n,
    'sampled', v_sample <> '', 'ms', (extract(epoch FROM clock_timestamp() - v_t0) * 1000)::int,
    'ran_as', v_orig_role, 'error', v_err);
END;
$$;

REVOKE EXECUTE ON FUNCTION public._audit_ghost_read_catalog() FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public._audit_ghost_read_catalog() TO service_role;
REVOKE EXECUTE ON FUNCTION public._audit_ghost_read_probe(text) FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public._audit_ghost_read_probe(text) TO service_role;
