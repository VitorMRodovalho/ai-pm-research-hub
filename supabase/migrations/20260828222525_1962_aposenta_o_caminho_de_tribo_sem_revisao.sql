-- #1962 — o caminho de entrada em tribo SEM revisao de lider e aposentado.
--
-- Decisao do PM (28/08): opcao A. Duas portas para o mesmo ato, com garantias diferentes, e o
-- defeito — nao a data.
--
-- ── O que existia, medido em 28/08/2026 ──────────────────────────────────────────────────────
--                              | request_tribe_assignment | select_tribe
--   prazo que le               | platform_settings        | home_schedule
--   valor hoje                 | 2026-09-15               | 2026-07-18 (vencido ha 41 dias)
--   barra quem JA tem tribo    | sim                      | NAO
--   escreve                    | pedido -> revisao        | direto, sem revisao
--   repetir                    | recusa                   | ON CONFLICT DO UPDATE = TROCA
--   EXECUTE                    | authenticated            | **PUBLIC, anon**, authenticated
--
--   linhas em tribe_selections ......... 43, ultima em 2026-07-10 (49 dias)
--   linhas em initiative_invitations ... 47, ultima em 2026-08-27 (ontem)
--
-- ── O achado que a issue nao registrava ──────────────────────────────────────────────────────
-- `select_tribe` e `deselect_tribe` tinham EXECUTE para **PUBLIC e anon**. E a armadilha do
-- `reference-create-function-nasce-com-execute-para-anon`: a funcao nasce aberta e ninguem revoga.
-- `select_tribe` e justamente a que le o prazo vencido E faz a troca silenciosa de tribo.
--
-- ── Por que aposentar nao custa UI ───────────────────────────────────────────────────────────
-- O front ja migrou no #1247 (ADR-0123): `TribeRequestBlock` e `TribesSection` chamam
-- `request_tribe_assignment`, e sair da tribo passa por `withdraw_from_initiative` (#1256), ambos
-- restritos a `authenticated`. O que sobrou foram as duas RPCs legadas, chamaveis e abertas.
--
-- ── Cinto e suspensorio ──────────────────────────────────────────────────────────────────────
-- Revogar sozinho bastaria hoje, mas um `GRANT` distraido reabriria a porta em silencio. Por isso o
-- corpo tambem passa a RECUSAR, nomeando o caminho canonico: quem chamar recebe instrucao, nao um
-- erro de permissao que nao explica nada.
--
-- O retorno de cada uma e PRESERVADO (`jsonb` e `json`, respectivamente). Trocar o tipo exigiria
-- DROP + CREATE (GC-097) e derrubaria dependencias por um detalhe que nao importa para uma funcao
-- que so levanta. O primeiro apply falhou exatamente por isso, ao tentar unificar em `jsonb`.

CREATE OR REPLACE FUNCTION public.select_tribe(p_tribe_id integer)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public','pg_temp'
AS $function$
BEGIN
  RAISE EXCEPTION
    'select_tribe foi aposentada (#1962): entrada em tribo passa por request_tribe_assignment, que '
    'le o prazo vigente, barra quem ja tem tribo e exige revisao do lider'
    USING ERRCODE = 'feature_not_supported';
END;
$function$;

CREATE OR REPLACE FUNCTION public.deselect_tribe()
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public','pg_temp'
AS $function$
BEGIN
  RAISE EXCEPTION
    'deselect_tribe foi aposentada (#1962): sair da tribo passa por withdraw_from_initiative (#1256), '
    'que grava estado terminal valido e deixa rastro'
    USING ERRCODE = 'feature_not_supported';
END;
$function$;

COMMENT ON FUNCTION public.select_tribe(integer) IS
  '#1962 APOSENTADA — use request_tribe_assignment. Ela lia um prazo proprio (vencido), nao barrava '
  'quem ja tinha tribo, trocava a tribo com ON CONFLICT DO UPDATE e tinha EXECUTE para anon.';
COMMENT ON FUNCTION public.deselect_tribe() IS
  '#1962 APOSENTADA — use withdraw_from_initiative (#1256). Tinha EXECUTE para anon.';

-- A porta, alem do aviso.
REVOKE ALL ON FUNCTION public.select_tribe(integer) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.deselect_tribe() FROM PUBLIC, anon, authenticated;

NOTIFY pgrst, 'reload schema';
