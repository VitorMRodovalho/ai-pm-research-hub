-- Foto de membro com nome opaco (item interno, decisão do GP em 26/10/2026).
--
-- PLACEHOLDER: a orquestradora aplica, adota a versão que o apply_migration registrar e renomeia o arquivo.
--
-- Por quê: o bucket member-photos é PÚBLICO, e o objeto da foto era nomeado pelo e-mail do membro
-- (avatars/<e-mail com @ e . trocados por _>.<ext>). members.photo_url guarda a URL pública, então a URL carregava o
-- e-mail. As três políticas de escrita do Storage para esse bucket também casavam o caminho pelo e-mail.
--
-- O que esta migration faz:
-- (1) public.member_photo_keys: uma chave por membro, 128 bits aleatórios em 32 hex, gerada pelo banco. Não deriva
--     de dado pessoal nem público (nem e-mail, nem nome, nem id do membro, nem hash deles). Tabela FECHADA: RLS ligada
--     sem política, sem privilégio para anon e authenticated; service_role lê e insere; ninguém tem UPDATE. A chave
--     não mora em members de propósito: members_update_own deixa o membro escrever qualquer coluna da própria
--     linha, e uma chave ali poderia ser trocada pela de outro membro.
-- (2) backfill: uma chave para cada membro que existe agora. Membro novo ganha a sua no primeiro upload (a EF cria).
-- (3) public.member_photo_key_of_caller(): a chave de quem chama, pelo auth.uid(). SECURITY DEFINER porque a tabela
--     é fechada para authenticated; devolve só a chave do próprio chamador, e NULL para quem não tem membro.
-- (4) member_photos_own_{upload,update,delete} reescritas: o nome do objeto tem de ser IGUAL a
--     avatars/<chave do chamador>.jpg ou .png. Igualdade, não LIKE: não sobra curinga para escapar, que é a lição da
--     20260805000256 levada ao fim. A UPDATE confere o antes (USING) e o depois (WITH CHECK).
-- (5) public._member_photo_swap_url(membro, de, para): troca a URL da foto em members e persons na MESMA transação,
--     só para service_role. É o passo por membro do script scripts/member-photos-opaque.mjs.
-- (6) pós-condição: catálogo, backfill e as políticas exercidas como membro, nos dois sentidos, num subbloco que
--     sempre desfaz o que escreveu.
--
-- Fora daqui: member-signatures (bucket privado) segue com o caminho por e-mail; o recorte de public_members para
-- visitante é outra PR.
--
-- Rollback (só antes de o script trocar as URLs; depois disso, a EF antiga voltaria a gravar pelo e-mail):
--   restaurar as três políticas com o corpo da 20260805000256; DROP FUNCTION public._member_photo_swap_url(uuid, text,
--   text); DROP FUNCTION public.member_photo_key_of_caller(); DROP TABLE public.member_photo_keys.

-- ── (1) a chave por membro ─────────────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.member_photo_keys (
  member_id  uuid PRIMARY KEY REFERENCES public.members(id) ON DELETE CASCADE,
  object_key text NOT NULL DEFAULT encode(extensions.gen_random_bytes(16), 'hex'),
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT member_photo_keys_object_key_key UNIQUE (object_key),
  CONSTRAINT member_photo_keys_object_key_shape CHECK (object_key ~ '^[0-9a-f]{32}$')
);

ALTER TABLE public.member_photo_keys ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.member_photo_keys FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT, INSERT ON TABLE public.member_photo_keys TO service_role;

COMMENT ON TABLE public.member_photo_keys IS
  'Item interno (GP 26/10/2026): chave aleatória de 128 bits por membro que nomeia o objeto da foto no bucket público member-photos (avatars/<chave>.jpg|png). Fechada: sem privilégio para anon/authenticated; service_role lê e insere; sem UPDATE para ninguém. A política de escrita do Storage lê a chave por member_photo_key_of_caller().';

-- ── (2) backfill ───────────────────────────────────────────────────────────────────────────────────────────────
INSERT INTO public.member_photo_keys (member_id)
SELECT m.id FROM public.members m
ON CONFLICT (member_id) DO NOTHING;

-- ── (3) a chave de quem chama ──────────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.member_photo_key_of_caller()
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT k.object_key
  FROM public.member_photo_keys k
  JOIN public.members m ON m.id = k.member_id
  WHERE auth.uid() IS NOT NULL
    AND m.auth_id = auth.uid()
  ORDER BY m.created_at, m.id
  LIMIT 1;
$function$;

REVOKE ALL ON FUNCTION public.member_photo_key_of_caller() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.member_photo_key_of_caller() TO authenticated, service_role;

COMMENT ON FUNCTION public.member_photo_key_of_caller() IS
  'Item interno (GP 26/10/2026): a chave da foto do próprio chamador (auth.uid()), ou NULL. Lida pelas políticas member_photos_own_* em storage.objects.';

-- ── (4) as políticas de escrita do bucket member-photos ─────────────────────────────────────────────────────────
DROP POLICY IF EXISTS member_photos_own_upload ON storage.objects;
CREATE POLICY member_photos_own_upload ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'member-photos'
    AND storage.objects.name IN (
      'avatars/' || (SELECT public.member_photo_key_of_caller()) || '.jpg',
      'avatars/' || (SELECT public.member_photo_key_of_caller()) || '.png'
    )
  );

DROP POLICY IF EXISTS member_photos_own_update ON storage.objects;
CREATE POLICY member_photos_own_update ON storage.objects
  FOR UPDATE TO authenticated
  USING (
    bucket_id = 'member-photos'
    AND storage.objects.name IN (
      'avatars/' || (SELECT public.member_photo_key_of_caller()) || '.jpg',
      'avatars/' || (SELECT public.member_photo_key_of_caller()) || '.png'
    )
  )
  WITH CHECK (
    bucket_id = 'member-photos'
    AND storage.objects.name IN (
      'avatars/' || (SELECT public.member_photo_key_of_caller()) || '.jpg',
      'avatars/' || (SELECT public.member_photo_key_of_caller()) || '.png'
    )
  );

DROP POLICY IF EXISTS member_photos_own_delete ON storage.objects;
CREATE POLICY member_photos_own_delete ON storage.objects
  FOR DELETE TO authenticated
  USING (
    bucket_id = 'member-photos'
    AND storage.objects.name IN (
      'avatars/' || (SELECT public.member_photo_key_of_caller()) || '.jpg',
      'avatars/' || (SELECT public.member_photo_key_of_caller()) || '.png'
    )
  );

-- ── (5) a troca de URL, um membro por vez, numa transação ──────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public._member_photo_swap_url(p_member_id uuid, p_from_url text, p_to_url text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_marker constant text := '/storage/v1/object/public/member-photos/';
  v_from text := split_part(coalesce(p_from_url, ''), '?', 1);
  v_members int;
  v_persons int;
BEGIN
  -- só service_role (script da orquestradora); usuário de PostgREST nunca chega aqui
  IF public._request_is_rest_caller() THEN
    RAISE EXCEPTION '_member_photo_swap_url: só para service_role' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF p_member_id IS NULL
     OR position(v_marker IN coalesce(p_from_url, '')) = 0
     OR position(v_marker IN coalesce(p_to_url, '')) = 0 THEN
    RAISE EXCEPTION '_member_photo_swap_url: argumento fora do formato' USING ERRCODE = 'invalid_parameter_value';
  END IF;

  -- members: exatamente a linha do membro, e só se a URL atual (sem a query) for a de origem
  UPDATE public.members SET photo_url = p_to_url
   WHERE id = p_member_id AND split_part(photo_url, '?', 1) = v_from;
  GET DIAGNOSTICS v_members = ROW_COUNT;
  IF v_members <> 1 THEN
    RAISE EXCEPTION '_member_photo_swap_url: a foto atual do membro não é a de origem (% linha)', v_members
      USING ERRCODE = 'no_data_found';
  END IF;

  -- persons: toda linha que guarda a URL de origem (a cópia de members.photo_url do ADR-0006)
  UPDATE public.persons SET photo_url = p_to_url
   WHERE split_part(photo_url, '?', 1) = v_from;
  GET DIAGNOSTICS v_persons = ROW_COUNT;

  RETURN jsonb_build_object('members', v_members, 'persons', v_persons);
END;
$function$;

REVOKE ALL ON FUNCTION public._member_photo_swap_url(uuid, text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._member_photo_swap_url(uuid, text, text) TO service_role;

COMMENT ON FUNCTION public._member_photo_swap_url(uuid, text, text) IS
  'Item interno (GP 26/10/2026): troca a URL da foto de um membro em members e persons numa transação, só se a URL atual for a de origem. Só service_role; chamada por scripts/member-photos-opaque.mjs (--apply e --rollback).';

-- ── (6) pós-condição ──────────────────────────────────────────────────────────────────────────────────────────
DO $postcondition$
DECLARE
  v_role text := current_user;
  v_a_auth uuid;
  v_a_key text;
  v_a_legacy text;
  v_b_key text;
  v_probe text;
  v_outcome text;
  v_n int;
  v_results text := '';
BEGIN
  -- catálogo: tabela fechada
  IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid = 'public.member_photo_keys'::regclass)
     OR EXISTS (SELECT 1 FROM pg_policy WHERE polrelid = 'public.member_photo_keys'::regclass)
     OR has_table_privilege('anon', 'public.member_photo_keys', 'SELECT')
     OR has_table_privilege('authenticated', 'public.member_photo_keys', 'SELECT')
     OR has_table_privilege('authenticated', 'public.member_photo_keys', 'INSERT')
     OR has_table_privilege('authenticated', 'public.member_photo_keys', 'UPDATE')
     OR has_table_privilege('service_role', 'public.member_photo_keys', 'UPDATE')
     OR NOT has_table_privilege('service_role', 'public.member_photo_keys', 'SELECT')
     OR NOT has_table_privilege('service_role', 'public.member_photo_keys', 'INSERT')
  THEN
    RAISE EXCEPTION 'fotos opacas: privilégios de member_photo_keys fora do esperado';
  END IF;

  -- catálogo: funções
  IF NOT EXISTS (SELECT 1 FROM pg_proc p WHERE p.oid = 'public.member_photo_key_of_caller()'::regprocedure
                 AND p.prosecdef AND p.proconfig @> ARRAY['search_path=public, pg_temp'])
     OR NOT EXISTS (SELECT 1 FROM pg_proc p WHERE p.oid = 'public._member_photo_swap_url(uuid, text, text)'::regprocedure
                    AND p.prosecdef AND p.proconfig @> ARRAY['search_path=public, pg_temp'])
     OR has_function_privilege('anon', 'public.member_photo_key_of_caller()', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.member_photo_key_of_caller()', 'EXECUTE')
     OR has_function_privilege('anon', 'public._member_photo_swap_url(uuid, text, text)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public._member_photo_swap_url(uuid, text, text)', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'public._member_photo_swap_url(uuid, text, text)', 'EXECUTE')
  THEN
    RAISE EXCEPTION 'fotos opacas: catálogo das funções fora do esperado';
  END IF;

  -- backfill: uma chave por membro, todas no formato e distintas
  IF (SELECT count(*) FROM public.members m
      WHERE NOT EXISTS (SELECT 1 FROM public.member_photo_keys k WHERE k.member_id = m.id)) <> 0
     OR (SELECT count(*) FROM public.member_photo_keys) <> (SELECT count(DISTINCT object_key) FROM public.member_photo_keys)
  THEN
    RAISE EXCEPTION 'fotos opacas: backfill incompleto ou chave repetida';
  END IF;

  -- catálogo: as três políticas existem e não leem mais o e-mail
  IF (SELECT count(*) FROM pg_policy
      WHERE polrelid = 'storage.objects'::regclass
        AND polname IN ('member_photos_own_upload', 'member_photos_own_update', 'member_photos_own_delete')
        AND polroles = ARRAY[(SELECT r.oid FROM pg_roles r WHERE r.rolname = 'authenticated')]
        AND coalesce(pg_get_expr(polqual, polrelid), '') || coalesce(pg_get_expr(polwithcheck, polrelid), '')
            LIKE '%member_photo_key_of_caller%'
        AND coalesce(pg_get_expr(polqual, polrelid), '') || coalesce(pg_get_expr(polwithcheck, polrelid), '')
            NOT LIKE '%email%') <> 3
  THEN
    RAISE EXCEPTION 'fotos opacas: as três políticas de member-photos não estão no formato novo';
  END IF;

  -- dois membros com login, achados aqui (sem id fixo): A escreve, B é o outro
  SELECT m.auth_id, k.object_key,
         'avatars/' || regexp_replace(coalesce(m.email, 'x'), '[@.]', '_', 'g') || '.jpg'
    INTO v_a_auth, v_a_key, v_a_legacy
  FROM public.members m JOIN public.member_photo_keys k ON k.member_id = m.id
  WHERE m.auth_id IS NOT NULL
  ORDER BY m.created_at, m.id LIMIT 1;
  SELECT k.object_key INTO v_b_key
  FROM public.members m JOIN public.member_photo_keys k ON k.member_id = m.id
  WHERE m.auth_id IS NOT NULL AND m.auth_id IS DISTINCT FROM v_a_auth
  ORDER BY m.created_at, m.id LIMIT 1;
  IF v_a_auth IS NULL OR v_b_key IS NULL THEN
    RAISE EXCEPTION 'fotos opacas: não há dois membros com login para exercer as políticas';
  END IF;

  -- cada sonda escreve como authenticated num subbloco que SEMPRE termina em exceção: a linha nunca fica.
  -- t = a escrita passou (chegou ao RAISE final, P0001; ou bateu no índice único, que vem DEPOIS do WITH CHECK);
  -- f = o Postgres recusou pela RLS (42501); 0 = o UPDATE não enxergou a linha (member-photos não tem política de
  -- SELECT para authenticated, e UPDATE com WHERE também passa pela de SELECT).
  FOR v_probe IN SELECT unnest(ARRAY['own_jpg', 'own_png', 'other', 'legacy', 'webp', 'no_member', 'rename_to_other']) LOOP
    PERFORM set_config('request.jwt.claims',
      json_build_object('sub', CASE WHEN v_probe = 'no_member' THEN '00000000-0000-4000-8000-000000000000'::uuid
                                    ELSE v_a_auth END,
                        'role', 'authenticated')::text, true);
    EXECUTE 'SET LOCAL ROLE authenticated';
    BEGIN
      INSERT INTO storage.objects (bucket_id, name)
      VALUES ('member-photos', CASE v_probe
        WHEN 'own_jpg'         THEN 'avatars/' || v_a_key || '.jpg'
        WHEN 'own_png'         THEN 'avatars/' || v_a_key || '.png'
        WHEN 'other'           THEN 'avatars/' || v_b_key || '.jpg'
        WHEN 'legacy'          THEN v_a_legacy
        WHEN 'webp'            THEN 'avatars/' || v_a_key || '.webp'
        WHEN 'no_member'       THEN 'avatars/' || v_a_key || '.jpg'
        WHEN 'rename_to_other' THEN 'avatars/' || v_a_key || '.jpg'
      END);
      IF v_probe = 'rename_to_other' THEN
        -- a própria linha existe agora; renomeá-la para o caminho de B tem de falhar no WITH CHECK
        UPDATE storage.objects SET name = 'avatars/' || v_b_key || '.jpg'
         WHERE bucket_id = 'member-photos' AND name = 'avatars/' || v_a_key || '.jpg';
        GET DIAGNOSTICS v_n = ROW_COUNT;
        IF v_n = 0 THEN
          RAISE EXCEPTION 'probe-rollback' USING ERRCODE = 'P0002';
        END IF;
      END IF;
      RAISE EXCEPTION 'probe-rollback' USING ERRCODE = 'P0001';
    EXCEPTION
      WHEN insufficient_privilege THEN v_outcome := 'f';
      WHEN no_data_found THEN v_outcome := '0';
      WHEN raise_exception OR unique_violation THEN v_outcome := 't';
    END;
    EXECUTE format('SET LOCAL ROLE %I', v_role);
    v_results := v_results || CASE WHEN v_results = '' THEN '' ELSE ',' END || v_probe || '=' || v_outcome;
  END LOOP;
  PERFORM set_config('request.jwt.claims', '', true);

  -- o próprio caminho passa nas duas extensões; o do outro, o antigo pelo e-mail, outra extensão e quem não é membro
  -- são recusados; renomear a própria foto para o caminho do outro não acontece (recusado ou invisível)
  IF v_results !~ '^own_jpg=t,own_png=t,other=f,legacy=f,webp=f,no_member=f,rename_to_other=[f0]$' THEN
    RAISE EXCEPTION 'fotos opacas: as políticas não se comportam como o esperado: %', v_results;
  END IF;
END;
$postcondition$;

NOTIFY pgrst, 'reload schema';
