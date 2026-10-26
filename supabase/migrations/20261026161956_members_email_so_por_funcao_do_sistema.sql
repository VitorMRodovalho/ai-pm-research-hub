-- members.email só muda por função do sistema (item interno, 26/10/2026).
--
-- PLACEHOLDER: a orquestradora aplica, adota a versão que o apply_migration registrar e renomeia o arquivo.
--
-- Por quê: members_update_own deixa o membro logado gravar qualquer coluna da própria linha pela PostgREST,
-- inclusive email. O caminho dos objetos de assinatura no Storage (e o de foto, até a migração para nomes opacos) é
-- derivado do e-mail com @ e . trocados por _, então dois e-mails diferentes podem dar o mesmo caminho.
-- sync_member_email_trigger já recusa adotar o e-mail de outro membro, mas não recusa um e-mail novo que colide no
-- caminho de outro.
-- A troca legítima pelo próprio membro passa por member_set_primary_email (SECURITY DEFINER, roda como o dono), e as
-- rotinas de backend usam service_role: nenhuma das duas executa o UPDATE como authenticated ou anon.
--
-- (1) gatilho BEFORE UPDATE OF email: se o e-mail muda e quem executa o comando é authenticated ou anon, recusa com
--     42501. A função do gatilho NÃO é SECURITY DEFINER, para current_user ser quem executa o comando.
-- (2) pós-condição: como authenticated, a troca direta do próprio e-mail é recusada; como o dono (o caminho das
--     funções do sistema), a mesma troca passa (controle). As duas sondas rodam em subblocos que sempre desfazem.
--
-- Rollback: DROP TRIGGER trg_lock_members_email ON public.members; DROP FUNCTION public._tg_lock_members_email();

-- ── (1) a trava ────────────────────────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public._tg_lock_members_email()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  IF OLD.email IS DISTINCT FROM NEW.email AND current_user IN ('authenticated', 'anon') THEN
    RAISE EXCEPTION 'members.email só muda por member_set_primary_email ou pela administração'
      USING ERRCODE = 'insufficient_privilege';
  END IF;
  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION public._tg_lock_members_email() FROM PUBLIC, anon, authenticated;

COMMENT ON FUNCTION public._tg_lock_members_email() IS
  'Item interno (26/10/2026): recusa a troca de members.email feita direto por authenticated ou anon. A troca pelo próprio membro passa por member_set_primary_email; o backend usa service_role.';

DROP TRIGGER IF EXISTS trg_lock_members_email ON public.members;
CREATE TRIGGER trg_lock_members_email
  BEFORE UPDATE OF email ON public.members
  FOR EACH ROW EXECUTE FUNCTION public._tg_lock_members_email();

-- ── (2) pós-condição ───────────────────────────────────────────────────────────────────────────────────────────
DO $postcondition$
DECLARE
  v_role text := current_user;
  v_auth uuid;
  v_member uuid;
  v_n int;
  v_outcome text;
  v_control text;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_trigger t
                 WHERE t.tgrelid = 'public.members'::regclass AND t.tgname = 'trg_lock_members_email'
                   AND NOT t.tgisinternal AND t.tgenabled = 'O'
                   AND t.tgfoid = 'public._tg_lock_members_email()'::regprocedure)
     OR (SELECT p.prosecdef FROM pg_proc p WHERE p.oid = 'public._tg_lock_members_email()'::regprocedure)
  THEN
    RAISE EXCEPTION 'trava de e-mail: catálogo fora do esperado';
  END IF;

  SELECT m.auth_id, m.id INTO v_auth, v_member FROM public.members m
  WHERE m.auth_id IS NOT NULL AND m.email IS NOT NULL
  ORDER BY m.created_at, m.id LIMIT 1;
  IF v_auth IS NULL THEN
    RAISE EXCEPTION 'trava de e-mail: nenhum membro com login para exercer';
  END IF;

  -- como authenticated, o próprio membro: a troca direta é recusada
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_auth, 'role', 'authenticated')::text, true);
  EXECUTE 'SET LOCAL ROLE authenticated';
  BEGIN
    UPDATE public.members SET email = 'probe-' || md5(random()::text) || '@example.invalid' WHERE auth_id = v_auth;
    GET DIAGNOSTICS v_n = ROW_COUNT;
    RAISE EXCEPTION 'probe-rollback' USING ERRCODE = CASE WHEN v_n = 0 THEN 'P0002' ELSE 'P0001' END;
  EXCEPTION
    WHEN insufficient_privilege THEN v_outcome := 'denied';
    WHEN no_data_found THEN v_outcome := 'no_row';
    WHEN raise_exception THEN v_outcome := 'allowed';
  END;
  EXECUTE format('SET LOCAL ROLE %I', v_role);
  PERFORM set_config('request.jwt.claims', '', true);

  -- controle: como o dono, o caminho das funções do sistema, a mesma troca passa
  BEGIN
    UPDATE public.members SET email = 'probe-' || md5(random()::text) || '@example.invalid' WHERE id = v_member;
    GET DIAGNOSTICS v_n = ROW_COUNT;
    RAISE EXCEPTION 'probe-rollback' USING ERRCODE = CASE WHEN v_n = 0 THEN 'P0002' ELSE 'P0001' END;
  EXCEPTION
    WHEN insufficient_privilege THEN v_control := 'denied';
    WHEN no_data_found THEN v_control := 'no_row';
    WHEN raise_exception THEN v_control := 'allowed';
  END;

  IF v_outcome IS DISTINCT FROM 'denied' OR v_control IS DISTINCT FROM 'allowed' THEN
    RAISE EXCEPTION 'trava de e-mail: authenticated=% dono=% (esperado denied e allowed)', v_outcome, v_control;
  END IF;
END;
$postcondition$;
