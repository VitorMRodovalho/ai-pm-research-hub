-- #2696: admin_manage_publication decide pela iniciativa DONA da publicacao, e a escrita direta na
-- tabela fica com quem administra a plataforma.
--
-- Antes (medido em 15/10/2026):
--   * o portao da RPC era can_by_member(member, 'write_board') SEM recurso, que passa para quem tem
--     write_board em QUALQUER tribo: 76 de 101 membros ativos com login. Editar, despublicar e
--     apagar publicacao de outra iniciativa passava;
--   * a policy pub_admin_manage_v4 (FOR ALL) deixava a mesma populacao fazer INSERT, UPDATE e
--     DELETE direto na tabela pelo PostgREST, sem passar pela RPC;
--   * o delete era fisico e nenhuma acao deixava rastro.
--
-- Depois:
--   * create/update/publish/unpublish: manage_platform, ou write_board na iniciativa dona. O can()
--     concede o escopo organization/global sem olhar o recurso, entao quem tem esse escopo segue
--     alcancando toda publicacao. Publicacao sem iniciativa: manage_platform ou write_board de
--     escopo organization (mesma regra do _can_write_board para board sem iniciativa);
--   * delete: so manage_platform, com a linha inteira gravada na auditoria;
--   * toda acao grava admin_audit_log com o autor;
--   * create/update aceitam collection_id, collection_position, slug e license, e a colecao tem de
--     ser da mesma iniciativa da publicacao;
--   * a policy FOR ALL passa a exigir superadmin ou manage_platform. A leitura de rascunho por quem
--     tem write ou write_board segue igual, numa policy de SELECT propria.

CREATE OR REPLACE FUNCTION public.admin_manage_publication(p_action text, p_data jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_member_id uuid; v_id uuid; v_tribe_id int; v_initiative_id uuid;
  v_row public.public_publications%ROWTYPE;
  v_collection_id uuid; v_collection_initiative uuid;
  v_platform boolean;
BEGIN
  SELECT id INTO v_member_id FROM public.members WHERE auth_id = auth.uid() LIMIT 1;
  IF v_member_id IS NULL THEN RAISE EXCEPTION 'Unauthorized: not authenticated'; END IF;

  IF p_action IS NULL OR p_action NOT IN ('create', 'update', 'publish', 'unpublish', 'delete') THEN
    RAISE EXCEPTION 'invalid_action';
  END IF;

  -- A iniciativa que decide: a informada no create, a DONA da linha nas demais acoes.
  IF p_action = 'create' THEN
    v_initiative_id := NULLIF(p_data->>'initiative_id', '')::uuid;
    v_tribe_id := (p_data->>'tribe_id')::int;
    IF v_initiative_id IS NULL AND v_tribe_id IS NOT NULL THEN
      SELECT id INTO v_initiative_id FROM public.initiatives
      WHERE legacy_tribe_id = v_tribe_id LIMIT 1;
    END IF;
  ELSE
    v_id := (p_data->>'id')::uuid;
    SELECT * INTO v_row FROM public.public_publications WHERE id = v_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'publication_not_found'; END IF;
    v_initiative_id := v_row.initiative_id;
  END IF;

  v_platform := public.can_by_member(v_member_id, 'manage_platform');

  IF p_action = 'delete' THEN
    -- Apagar e fisico: fica com quem administra a plataforma, e a linha inteira vai para a auditoria.
    IF NOT v_platform THEN
      RAISE EXCEPTION 'Unauthorized: delete requires manage_platform';
    END IF;
  ELSIF NOT v_platform THEN
    -- p_resource_type tem de ser nao-nulo e diferente de 'tribe': com NULL, o ramo legado do can()
    -- casta o UUID para integer e estoura justamente no caminho de negacao (ver _manage_event_scope_ok).
    IF v_initiative_id IS NULL THEN
      IF NOT public.can_org_by_member(v_member_id, 'write_board') THEN
        RAISE EXCEPTION 'Unauthorized: a publication without initiative requires organization-wide write_board';
      END IF;
    ELSIF NOT public.can_by_member(v_member_id, 'write_board', 'initiative', v_initiative_id) THEN
      RAISE EXCEPTION 'Unauthorized: requires write_board on the initiative that owns the publication';
    END IF;
  END IF;

  -- A colecao tem de ser da mesma iniciativa: a autoridade foi decidida sobre ESTA iniciativa.
  IF p_action IN ('create', 'update') THEN
    v_collection_id := NULLIF(p_data->>'collection_id', '')::uuid;
    IF v_collection_id IS NOT NULL THEN
      SELECT initiative_id INTO v_collection_initiative
      FROM public.publication_collections WHERE id = v_collection_id;
      IF NOT FOUND THEN RAISE EXCEPTION 'collection_not_found'; END IF;
      IF v_collection_initiative IS DISTINCT FROM v_initiative_id THEN
        RAISE EXCEPTION 'collection_initiative_mismatch: the collection belongs to another initiative';
      END IF;
    END IF;
  END IF;

  IF p_action = 'create' THEN
    INSERT INTO public.public_publications (
      title, abstract, authors, author_member_ids, publication_date, publication_type,
      external_url, external_platform, doi, keywords,
      initiative_id, cycle_code,
      language, thumbnail_url, pdf_url, is_featured, is_published,
      collection_id, collection_position, slug, license
    ) VALUES (
      p_data->>'title', p_data->>'abstract',
      ARRAY(SELECT jsonb_array_elements_text(COALESCE(p_data->'authors','[]'::jsonb))),
      ARRAY(SELECT (jsonb_array_elements_text(COALESCE(p_data->'author_member_ids','[]'::jsonb)))::uuid),
      (p_data->>'publication_date')::date, COALESCE(p_data->>'publication_type','article'),
      p_data->>'external_url', p_data->>'external_platform', p_data->>'doi',
      ARRAY(SELECT jsonb_array_elements_text(COALESCE(p_data->'keywords','[]'::jsonb))),
      v_initiative_id, p_data->>'cycle_code',
      COALESCE(p_data->>'language','pt-BR'), p_data->>'thumbnail_url', p_data->>'pdf_url',
      COALESCE((p_data->>'is_featured')::boolean, false),
      COALESCE((p_data->>'is_published')::boolean, false),
      v_collection_id, (p_data->>'collection_position')::int,
      NULLIF(p_data->>'slug', ''), NULLIF(p_data->>'license', '')
    ) RETURNING * INTO v_row;
    v_id := v_row.id;
    INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
    VALUES (v_member_id, 'publication.created', 'publication', v_id, to_jsonb(v_row),
            jsonb_build_object('initiative_id', v_initiative_id));
    RETURN jsonb_build_object('ok', true, 'id', v_id);

  ELSIF p_action = 'update' THEN
    UPDATE public.public_publications SET
      title = COALESCE(p_data->>'title', title),
      abstract = COALESCE(p_data->>'abstract', abstract),
      external_url = COALESCE(p_data->>'external_url', external_url),
      external_platform = COALESCE(p_data->>'external_platform', external_platform),
      doi = COALESCE(p_data->>'doi', doi),
      thumbnail_url = COALESCE(p_data->>'thumbnail_url', thumbnail_url),
      pdf_url = COALESCE(p_data->>'pdf_url', pdf_url),
      is_featured = COALESCE((p_data->>'is_featured')::boolean, is_featured),
      publication_date = COALESCE((p_data->>'publication_date')::date, publication_date),
      collection_id = COALESCE(v_collection_id, collection_id),
      collection_position = COALESCE((p_data->>'collection_position')::int, collection_position),
      slug = COALESCE(NULLIF(p_data->>'slug', ''), slug),
      license = COALESCE(NULLIF(p_data->>'license', ''), license),
      updated_at = now()
    WHERE id = v_id;
    INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
    VALUES (v_member_id, 'publication.updated', 'publication', v_id,
            jsonb_build_object('before', to_jsonb(v_row), 'input', p_data - 'id'),
            jsonb_build_object('initiative_id', v_initiative_id));
    RETURN jsonb_build_object('ok', true, 'id', v_id);

  ELSIF p_action = 'publish' THEN
    UPDATE public.public_publications SET is_published = true, updated_at = now() WHERE id = v_id;
    INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
    VALUES (v_member_id, 'publication.published', 'publication', v_id,
            jsonb_build_object('is_published', jsonb_build_object('from', v_row.is_published, 'to', true)),
            jsonb_build_object('initiative_id', v_initiative_id));
    RETURN jsonb_build_object('ok', true, 'action', 'published');

  ELSIF p_action = 'unpublish' THEN
    UPDATE public.public_publications SET is_published = false, updated_at = now() WHERE id = v_id;
    INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
    VALUES (v_member_id, 'publication.unpublished', 'publication', v_id,
            jsonb_build_object('is_published', jsonb_build_object('from', v_row.is_published, 'to', false)),
            jsonb_build_object('initiative_id', v_initiative_id));
    RETURN jsonb_build_object('ok', true, 'action', 'unpublished');

  ELSE
    DELETE FROM public.public_publications WHERE id = v_id;
    INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
    VALUES (v_member_id, 'publication.deleted', 'publication', v_id, to_jsonb(v_row),
            jsonb_build_object('initiative_id', v_initiative_id));
    RETURN jsonb_build_object('ok', true, 'action', 'deleted');
  END IF;
END;
$function$;

-- Anon nunca passou do primeiro portao (sem membro); tirar o EXECUTE fecha a porta na entrada.
REVOKE ALL ON FUNCTION public.admin_manage_publication(text, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_manage_publication(text, jsonb) TO authenticated, service_role;

-- A escrita direta na tabela fica com quem administra a plataforma; quem tem write_board escreve
-- pela RPC, que decide pela iniciativa dona. A leitura de rascunho por write/write_board nao muda.
DROP POLICY IF EXISTS pub_admin_manage_v4 ON public.public_publications;
CREATE POLICY pub_admin_manage_v4 ON public.public_publications FOR ALL TO authenticated
  USING (public.rls_is_superadmin() OR public.rls_can('manage_platform'))
  WITH CHECK (public.rls_is_superadmin() OR public.rls_can('manage_platform'));

CREATE POLICY pub_curator_read_v4 ON public.public_publications FOR SELECT TO authenticated
  USING (public.rls_can('write') OR public.rls_can('write_board'));

-- Exercicio da RPC como membro, nos dois sentidos, sem deixar rastro (sub-transacao que termina em
-- RAISE, mesmo padrao do _test_meeting_close_summary_roundtrip). Existe porque supabase-js nao
-- consegue setar request.jwt.claims e chamar a RPC na mesma transacao.
--   FORA:  tem write_board em alguma iniciativa (passava no portao antigo), nao na dona da publicacao.
--   DONO:  tem write_board SO pelo escopo da iniciativa dona (nem organization, nem manage_platform),
--          para o controle positivo provar o ramo escopado e nao o organizacional.
CREATE OR REPLACE FUNCTION public._test_2696_publication_authority_roundtrip()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $function$
DECLARE
  v_pub public.public_publications%ROWTYPE;
  v_out_id uuid; v_out_auth uuid;
  v_own_id uuid; v_own_auth uuid;
  v_canary text := '__test_2696_' || replace(gen_random_uuid()::text, '-', '');
  v_out_update jsonb; v_out_unpublish jsonb; v_own_update jsonb; v_own_delete jsonb;
  v_title_after text; v_audit_rows int; v_row_after_delete int;
  v_sentinel constant text := '__ROLLBACK_2696__';
BEGIN
  IF public._request_is_rest_caller() THEN
    RAISE EXCEPTION 'Unauthorized: _test_2696_publication_authority_roundtrip requires service_role';
  END IF;

  SELECT * INTO v_pub FROM public.public_publications
  WHERE initiative_id IS NOT NULL ORDER BY created_at, id LIMIT 1;
  IF NOT FOUND THEN RAISE EXCEPTION 'not_measured: no publication with an initiative'; END IF;

  SELECT m.id, m.auth_id INTO v_out_id, v_out_auth FROM public.members m
  WHERE m.is_active AND m.auth_id IS NOT NULL
    AND public.can_by_member(m.id, 'write_board')
    AND NOT public.can_by_member(m.id, 'write_board', 'initiative', v_pub.initiative_id)
    AND NOT public.can_by_member(m.id, 'manage_platform')
  ORDER BY m.id LIMIT 1;

  SELECT m.id, m.auth_id INTO v_own_id, v_own_auth FROM public.members m
  WHERE m.is_active AND m.auth_id IS NOT NULL
    AND public.can_by_member(m.id, 'write_board', 'initiative', v_pub.initiative_id)
    AND NOT public.can_org_by_member(m.id, 'write_board')
    AND NOT public.can_by_member(m.id, 'manage_platform')
  ORDER BY m.id LIMIT 1;

  IF v_out_id IS NULL OR v_own_id IS NULL THEN
    RAISE EXCEPTION 'not_measured: outsider=% owner=%', v_out_id IS NOT NULL, v_own_id IS NOT NULL;
  END IF;

  BEGIN
    -- FORA: editar e despublicar a publicacao de outra iniciativa.
    PERFORM set_config('request.jwt.claims',
            json_build_object('sub', v_out_auth, 'role', 'authenticated')::text, true);
    BEGIN
      PERFORM public.admin_manage_publication('update', jsonb_build_object('id', v_pub.id, 'title', v_canary || '_FORA'));
      v_out_update := jsonb_build_object('allowed', true);
    EXCEPTION WHEN OTHERS THEN
      v_out_update := jsonb_build_object('allowed', false, 'error', SQLERRM);
    END;
    BEGIN
      PERFORM public.admin_manage_publication('unpublish', jsonb_build_object('id', v_pub.id));
      v_out_unpublish := jsonb_build_object('allowed', true);
    EXCEPTION WHEN OTHERS THEN
      v_out_unpublish := jsonb_build_object('allowed', false, 'error', SQLERRM);
    END;

    -- DONO (controle positivo): editar passa e deixa rastro; apagar segue recusado.
    PERFORM set_config('request.jwt.claims',
            json_build_object('sub', v_own_auth, 'role', 'authenticated')::text, true);
    BEGIN
      PERFORM public.admin_manage_publication('update', jsonb_build_object('id', v_pub.id, 'title', v_canary || '_DONO'));
      v_own_update := jsonb_build_object('allowed', true);
    EXCEPTION WHEN OTHERS THEN
      v_own_update := jsonb_build_object('allowed', false, 'error', SQLERRM);
    END;
    SELECT title INTO v_title_after FROM public.public_publications WHERE id = v_pub.id;
    SELECT count(*) INTO v_audit_rows FROM public.admin_audit_log
    WHERE target_id = v_pub.id AND actor_id = v_own_id AND action = 'publication.updated'
      AND changes->'input'->>'title' = v_canary || '_DONO';
    BEGIN
      PERFORM public.admin_manage_publication('delete', jsonb_build_object('id', v_pub.id));
      v_own_delete := jsonb_build_object('allowed', true);
    EXCEPTION WHEN OTHERS THEN
      v_own_delete := jsonb_build_object('allowed', false, 'error', SQLERRM);
    END;
    SELECT count(*) INTO v_row_after_delete FROM public.public_publications WHERE id = v_pub.id;

    RAISE EXCEPTION '%', v_sentinel;
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> v_sentinel THEN RAISE; END IF;
  END;

  RETURN jsonb_build_object(
    'publication_id', v_pub.id,
    'canary', v_canary,
    'outsider_update', v_out_update,
    'outsider_unpublish', v_out_unpublish,
    'owner_update', v_own_update || jsonb_build_object(
      'title_has_canary', COALESCE(v_title_after, '') = v_canary || '_DONO',
      'audit_rows', v_audit_rows),
    'owner_delete', v_own_delete || jsonb_build_object('row_still_there', v_row_after_delete = 1)
  );
END;
$function$;

REVOKE ALL ON FUNCTION public._test_2696_publication_authority_roundtrip() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._test_2696_publication_authority_roundtrip() TO service_role;
