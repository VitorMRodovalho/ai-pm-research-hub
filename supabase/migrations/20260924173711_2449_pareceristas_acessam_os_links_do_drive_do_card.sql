-- ============================================================================
-- #2449 fatia B — o parecerista recebe acesso ao artefato que esta no card
-- ============================================================================
--
-- WHAT:
--   * _card_drive_files(item): os arquivos do Drive do card, das DUAS fontes: board_item_files
--     (o que a concessao ja lia) e os links do Google Drive/Docs colados em board_items.attachments
--     (id extraido de /d/<id> ou /folders/<id>).
--   * enqueue_curation_drive_grants e enqueue_curation_drive_grant_for_member passam a ler desse
--     helper, em vez de so board_item_files.
--   * Quando a concessao a um parecerista DESIGNADO falha (a conta de servico nao pode compartilhar
--     arquivo de Drive pessoal: 403), o parecerista e avisado para usar "Solicitar acesso" do proprio
--     Google; o dono do arquivo recebe o pedido. Nenhum e-mail de ninguem e exposto.
-- WHY: medido em 24/09/2026, 0 linhas em drive_curation_grants na historia. A concessao lia so
--   board_item_files, que so o MCP grava (ultima linha 10/08), e os artefatos reais ficam em
--   attachments: 78 anexos em 51 cards, 21 deles links do Google Drive/Docs.
-- O aviso de falha fica num gatilho da propria tabela (e nao em mark_curation_grant_done) para nao
--   reescrever a funcao que o EF chama.
-- ROLLBACK: reaplicar as versoes anteriores das duas funcoes de enfileirar; DROP do gatilho, da
--   funcao de aviso e de _card_drive_files.
-- CROSS-REF: #2449 · #301 · ADR-0108 · #2444
-- ============================================================================

-- (1) Os arquivos do Drive do card, das duas fontes ------------------------------------------
CREATE OR REPLACE FUNCTION public._card_drive_files(p_item_id uuid)
RETURNS TABLE (drive_file_id text, drive_file_url text)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $fn$
  SELECT DISTINCT ON (x.drive_file_id) x.drive_file_id, x.drive_file_url
    FROM (
      SELECT f.drive_file_id::text AS drive_file_id, f.drive_file_url::text AS drive_file_url
        FROM public.board_item_files f
       WHERE f.board_item_id = p_item_id AND f.deleted_at IS NULL
      UNION ALL
      SELECT coalesce(substring(a->>'url' FROM '/d/([A-Za-z0-9_-]{19,})'),
                      substring(a->>'url' FROM '/folders/([A-Za-z0-9_-]{19,})')),
             a->>'url'
        FROM public.board_items bi,
             jsonb_array_elements(coalesce(bi.attachments, '[]'::jsonb)) a
       WHERE bi.id = p_item_id
         AND a->>'url' ~* '^https://(drive|docs)\.google\.com/'
    ) x
   WHERE x.drive_file_id IS NOT NULL
   ORDER BY x.drive_file_id;
$fn$;

REVOKE ALL ON FUNCTION public._card_drive_files(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._card_drive_files(uuid) TO service_role;

-- (2) Comite, na entrada da curadoria: le das duas fontes ------------------------------------
CREATE OR REPLACE FUNCTION public.enqueue_curation_drive_grants(p_item_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_org uuid;
  v_inserted int := 0;
BEGIN
  v_org := (SELECT id FROM public.organizations ORDER BY created_at LIMIT 1);
  IF v_org IS NULL THEN RETURN; END IF;

  WITH curators AS (
    SELECT m.id AS member_id, lower(m.email)::citext AS email
    FROM public.members m
    WHERE m.member_status = 'active'
      AND m.email IS NOT NULL AND m.email <> ''
      AND public.can_by_member(m.id, 'curate_content')
  ),
  ins AS (
    INSERT INTO public.drive_curation_grants (
      organization_id, board_item_id, drive_file_id, drive_file_url,
      grantee_member_id, permission_email, role, grant_reason, status
    )
    SELECT v_org, p_item_id, f.drive_file_id, f.drive_file_url,
           c.member_id, c.email, 'commenter', 'committee_handoff', 'pending_grant'
    -- #2449: board_item_files E os links do Drive colados no card
    FROM public._card_drive_files(p_item_id) f
    CROSS JOIN curators c
    ON CONFLICT (drive_file_id, permission_email)
      WHERE status IN ('pending_grant','granted','pending_revoke')
    DO NOTHING
    RETURNING 1
  )
  SELECT count(*) INTO v_inserted FROM ins;

  IF v_inserted > 0 THEN
    INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
    VALUES (NULL, 'curation_drive_grant_queued', 'drive_curation_grants', p_item_id, '{}'::jsonb,
            jsonb_build_object('queued', v_inserted, 'reason', 'committee_handoff'));
  END IF;
END;
$function$;

-- (3) Parecerista designado: le das duas fontes --------------------------------------------
CREATE OR REPLACE FUNCTION public.enqueue_curation_drive_grant_for_member(p_item_id uuid, p_member_id uuid, p_reason text DEFAULT 'reviewer_assignment'::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_org uuid;
  v_inserted int := 0;
BEGIN
  IF p_reason NOT IN ('committee_handoff','reviewer_assignment','manual') THEN
    p_reason := 'reviewer_assignment';
  END IF;
  v_org := (SELECT id FROM public.organizations ORDER BY created_at LIMIT 1);
  IF v_org IS NULL THEN RETURN; END IF;

  WITH ins AS (
    INSERT INTO public.drive_curation_grants (
      organization_id, board_item_id, drive_file_id, drive_file_url,
      grantee_member_id, permission_email, role, grant_reason, status
    )
    SELECT v_org, p_item_id, f.drive_file_id, f.drive_file_url,
           m.id, lower(m.email)::citext, 'commenter', p_reason, 'pending_grant'
    -- #2449: board_item_files E os links do Drive colados no card
    FROM public._card_drive_files(p_item_id) f
    JOIN public.members m ON m.id = p_member_id
    WHERE m.email IS NOT NULL AND m.email <> ''
    ON CONFLICT (drive_file_id, permission_email)
      WHERE status IN ('pending_grant','granted','pending_revoke')
    DO NOTHING
    RETURNING 1
  )
  SELECT count(*) INTO v_inserted FROM ins;

  IF v_inserted > 0 THEN
    INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
    VALUES (NULL, 'curation_drive_grant_queued', 'drive_curation_grants', p_item_id, '{}'::jsonb,
            jsonb_build_object('queued', v_inserted, 'reason', p_reason, 'member_id', p_member_id));
  END IF;
END;
$function$;

-- (4) Falhou a concessao ao parecerista designado: ele e avisado a pedir acesso ---------------
CREATE OR REPLACE FUNCTION public.trg_notify_curation_grant_failed()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $fn$
DECLARE
  v_title text;
BEGIN
  IF NEW.status = 'failed' AND OLD.status = 'pending_grant'
     AND NEW.grant_reason IN ('reviewer_assignment', 'manual') THEN
    SELECT title INTO v_title FROM public.board_items WHERE id = NEW.board_item_id;
    PERFORM public.create_notification(
      NEW.grantee_member_id,
      'curation_review_assigned',
      'Acesso ao arquivo do seu parecer',
      '"' || coalesce(v_title, 'Card') || '": a plataforma não conseguiu te dar acesso automático a um arquivo do card '
        || '(ele provavelmente está num Drive pessoal). Abra o link e use "Solicitar acesso" do Google; o dono do arquivo recebe o pedido. Link: '
        || coalesce(NEW.drive_file_url, ''),
      '/admin/curatorship',
      'board_item',
      NEW.board_item_id
    );
  END IF;
  RETURN NEW;
END;
$fn$;

REVOKE ALL ON FUNCTION public.trg_notify_curation_grant_failed() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_notify_curation_grant_failed ON public.drive_curation_grants;
CREATE TRIGGER trg_notify_curation_grant_failed
  AFTER UPDATE OF status ON public.drive_curation_grants
  FOR EACH ROW EXECUTE FUNCTION public.trg_notify_curation_grant_failed();
