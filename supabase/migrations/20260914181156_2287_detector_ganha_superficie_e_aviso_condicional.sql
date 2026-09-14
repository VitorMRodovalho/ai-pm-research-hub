-- #2287: o detector ganha superficie, e o aviso para de anunciar urgencia que nao existe.
--
-- Duas coisas, e a primeira e a que fecha o laco da #2285.
--
-- (a) SUPERFICIE. `detect_unlinked_accounts()` existe desde a #2273 e o cron da #2285 avisa quando
--     ela acha algo, mas NENHUMA superficie a alcancava: varrendo `src/` e `supabase/functions/`,
--     ela so aparecia em `src/lib/database.gen.ts`, que e tipo gerado. O alerta chegava e nao havia
--     onde agir sem abrir o banco. A ferramenta passa a existir como
--     `admin_dashboard scope='unlinked_accounts'` no MCP (mudanca fora desta migration, no
--     `nucleo-mcp/index.ts`). A RPC ja mascara o endereco e ja tem portao de manage_platform; o MCP
--     roda com a chave anon mais o Bearer da pessoa, entao o portao e real, nao decorativo.
--
-- (b) REDACAO. Na primeira execucao real (14/09 16:59) o corpo saiu assim:
--
--       "1 pessoa(s) tem conta de acesso criada ... Dessas, 0 ja entrou na plataforma alguma vez,
--        e esse e o caso urgente: ..."
--
--     Fato certo, tom errado: anuncia urgencia com o numero em zero. A frase de urgencia passa a
--     ser condicional, e o ramo de zero diz o que de fato e o caso (fila, nao urgencia).
--
-- Nada mais muda: mesmo portao (nenhum), mesmo ACL, mesma auditoria fora do IF, mesmo p_dry_run.
CREATE OR REPLACE FUNCTION public.detect_unlinked_accounts_cron(p_dry_run boolean DEFAULT false)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public, pg_temp, auth
AS $function$
DECLARE
  v_total     int := 0;
  v_signed_in int := 0;
  v_alvos     int := 0;
  v_inserted  int := 0;
BEGIN
  SELECT count(*)::int,
         count(*) FILTER (WHERE x.last_sign_in_at IS NOT NULL)::int
    INTO v_total, v_signed_in
    FROM public._unlinked_accounts_rows() x;

  -- Quem receberia: mesmo predicado do INSERT, contado antes. Serve ao dry-run e ao retorno.
  SELECT count(*)::int INTO v_alvos
    FROM public.members m
   WHERE m.is_active = true
     AND public.can_by_member(m.id, 'manage_platform')
     AND NOT EXISTS (
       SELECT 1 FROM public.notifications n
        WHERE n.recipient_id = m.id
          AND n.type = 'unlinked_accounts_detected'
          AND n.created_at >= now() - interval '25 days'
     );

  IF v_total > 0 AND NOT p_dry_run THEN
    -- A notificacao carrega CONTAGEM, nunca endereco: o detalhe fica atras do portao de
    -- detect_unlinked_accounts(), que mascara. Janela de 25 dias = lembrete mensal sobre um
    -- cron semanal, de proposito: a serie tem de ser medida toda semana, mas a fila fica
    -- parada por semanas, e avisar toda semana sobre decisao ja tomada e como nao avisar.
    INSERT INTO public.notifications (recipient_id, type, title, body, link, delivery_mode, created_at)
    SELECT m.id,
           'unlinked_accounts_detected',
           format('%s conta(s) de acesso sem vinculo com o cadastro', v_total),
           format('%s pessoa(s) tem conta de acesso criada e nenhum cadastro apontando para ela.%s A lista, com o endereco mascarado, sai de admin_dashboard scope=''unlinked_accounts'' no MCP (#2287) ou da RPC detect_unlinked_accounts(). Ligar conta a cadastro exige prova de posse da caixa, nunca so o e-mail bater.',
                  v_total,
                  -- #2287: a frase de urgencia so aparece quando HA urgencia. Na primeira execucao
                  -- real (14/09) o texto dizia "Dessas, 0 ja entrou ... e esse e o caso urgente",
                  -- anunciando urgencia onde nao havia. Fato certo, tom errado.
                  CASE WHEN v_signed_in > 0
                    THEN format(' Dessas, %s ja entrou na plataforma alguma vez, e esse e o caso urgente: a pessoa entra, nao se reconhece, e toda contagem de "membro sem conta" fica errada.', v_signed_in)
                    ELSE ' Nenhuma delas chegou a entrar ainda, entao e trabalho de fila e nao urgencia. Quando alguma entrar, este aviso passa a dizer quantas.'
                  END),
           -- Sem link de proposito. /admin/data-health mostra anomalias, invariantes e eventos
           -- de entrevista orfaos, e NAO contas nao ligadas (conferido no DataHealthIsland em
           -- 14/09): apontar para la seria mandar o GP a uma tela que nao responde a pergunta.
           NULL,
           public._delivery_mode_for('unlinked_accounts_detected'),
           now()
    FROM public.members m
    WHERE m.is_active = true
      AND public.can_by_member(m.id, 'manage_platform')
      AND NOT EXISTS (
        SELECT 1 FROM public.notifications n
        WHERE n.recipient_id = m.id
          AND n.type = 'unlinked_accounts_detected'
          AND n.created_at >= now() - interval '25 days'
      );
    GET DIAGNOSTICS v_inserted = ROW_COUNT;
  END IF;

  -- A auditoria fica FORA do IF de contagem, ao contrario dos irmaos. Um detector que so
  -- registra quando acha nao deixa como separar "rodou e nao achou nada" de "nunca rodou",
  -- que e exatamente o defeito que a #2285 consertou. A serie tem de existir no zero.
  IF NOT p_dry_run THEN
    INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
    VALUES (
      NULL, 'cron.detect_unlinked_accounts_run', 'system_event', NULL,
      jsonb_build_object('unlinked_total', v_total,
                         'already_signed_in', v_signed_in,
                         'managers_notified', v_inserted),
      jsonb_build_object('source', 'cron_detect_unlinked_accounts', 'issue', 2285)
    );
  END IF;

  RETURN jsonb_build_object(
    'unlinked_total',         v_total,
    'already_signed_in',      v_signed_in,
    'would_notify',           v_alvos,
    'notifications_inserted', v_inserted,
    'dry_run',                p_dry_run,
    'run_at',                 now()
  );
END;
$function$;
REVOKE ALL ON FUNCTION public.detect_unlinked_accounts_cron(boolean) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.detect_unlinked_accounts_cron(boolean) FROM anon;
REVOKE ALL ON FUNCTION public.detect_unlinked_accounts_cron(boolean) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.detect_unlinked_accounts_cron(boolean) TO service_role;
