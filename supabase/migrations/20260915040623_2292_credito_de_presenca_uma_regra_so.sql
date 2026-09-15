-- #2292 — o credito de presenca passa a ter UMA regra executada, e a de-duplicacao
-- passa a ser por (PESSOA, EVENTO) em vez de por id de linha.
--
-- O QUE FOI MEDIDO (2026-09-15), e que decidiu o desenho:
--
--   224 pares duplicados / 2.240 pontos / 40 pessoas. E 100% deles tem a MESMA forma:
--   uma linha de formato evento (ref_id = events.id, escrita pela RPC) mais uma de
--   formato presenca (ref_id = attendance.id, escrita pela EF). Nao existe UM par de
--   outra forma, nao existe grupo de 3, e nao existe UMA SO linha de formato evento
--   que nao seja duplicata. Ou seja: cada linha que a RPC ja escreveu na vida e a
--   segunda copia de um credito que a EF ja tinha dado.
--
--   A causa e a assimetria das duas de-duplicacoes: a RPC checa os DOIS formatos
--   (ref_id = a.event_id OU ref_id = a.id) e grava o formato ANTIGO; a EF so conhece
--   ref_id = a.id. Rodar as duas em qualquer ordem produz o par, por construcao.
--
-- AS CINCO DIVERGENCIAS entre a regra declarada (RPC) e a executada (EF), sendo que a
-- issue nomeava duas:
--   1. filtro de evento cancelado ....... RPC sim,  EF NAO
--   2. filtro de e.type ................. RPC sim,  EF NAO   (nao estava na issue)
--   3. de-duplicacao .................... RPC dois formatos, EF um so
--   4. pontos ........................... RPC le gamification_rules, EF usa constante
--                                         (nao estava na issue; hoje ambos dao 10)
--   5. formato gravado .................. RPC ref_id=evento, EF ref_id=presenca
--
-- O DESENHO: uma fonte so. O worker abaixo E a regra; a RPC vira portao que delega, e
-- a EF (que e quem o cron chama) passa a chamar o worker em vez de reimplementa-lo.
--
-- POLITICA DE REMOCAO (decisao do dono, 2026-09-15: "depende do motivo"). Os dois
-- caminhos que apagam presenca ja SAO os dois motivos, e por isso nenhum parametro
-- novo foi preciso:
--   - cancelar reuniao  -> a pessoa compareceu, a reuniao e que sumiu. O credito e
--                          PRESERVADO, repontando ref_id para o EVENTO.
--   - limpar presenca   -> alguem esta dizendo que o registro esta errado. O credito
--                          e APAGADO junto.
-- Isso tambem fecha a raiz do credito em dobro na restauracao: o cancelamento deixa de
-- produzir orfa, e a de-duplicacao por (pessoa, evento) enxerga o credito repontado.

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. O worker: a regra, uma vez so.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public._sync_attendance_points_worker(p_member_id uuid DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
-- search_path VAZIO, como as irmas sync_attendance_points e clear_member_attendance
-- (medido em pg_proc.proconfig). Tudo aqui e qualificado por schema.
SET search_path = ''
AS $fn$
DECLARE
  v_pts int;
  v_ins int := 0;
BEGIN
  -- Fonte unica dos pontos: o catalogo. A constante POINTS_PER_ATTENDANCE da EF era a
  -- segunda fonte, e uma segunda fonte so parece inofensiva enquanto os dois numeros
  -- coincidem (hoje coincidem: 10).
  SELECT base_points INTO v_pts
    FROM public.gamification_rules
   WHERE slug = 'attendance' AND active = true AND effective_from <= now()
   ORDER BY effective_from DESC LIMIT 1;
  IF v_pts IS NULL THEN v_pts := 10; END IF;

  INSERT INTO public.gamification_points (member_id, points, reason, category, ref_id)
  SELECT a.member_id, v_pts, 'Presença em evento', 'attendance', a.id
    FROM public.attendance a
    JOIN public.events e ON e.id = a.event_id
   WHERE a.present = true
     AND (p_member_id IS NULL OR a.member_id = p_member_id)
     AND e.type IN ('tribo','geral','lideranca','kickoff')
     AND (e.status IS NULL OR e.status <> 'cancelled')
     -- De-duplicacao por (PESSOA, EVENTO). O LEFT JOIN resolve o ref_id polimorfico:
     -- se aponta para uma presenca, o evento vem dela; se aponta para o evento, o
     -- COALESCE devolve o proprio ref_id. Os dois formatos passam a se enxergar, que e
     -- exatamente o que faltava.
     AND NOT EXISTS (
       SELECT 1
         FROM public.gamification_points gp
         LEFT JOIN public.attendance a2 ON a2.id = gp.ref_id
        WHERE gp.category = 'attendance'
          AND gp.member_id = a.member_id
          AND COALESCE(a2.event_id, gp.ref_id) = a.event_id
     );
  GET DIAGNOSTICS v_ins = ROW_COUNT;

  -- occurred_at e ref_kind NAO sao passados de proposito: os triggers
  -- _gp_set_occurred_at (#1464) e derive_gamification_ref_kind (#1537) os derivam,
  -- independente do caminho de escrita. Passa-los aqui criaria a terceira fonte.
  RETURN jsonb_build_object('success', true, 'points_created', v_ins, 'points_per_attendance', v_pts);
END;
$fn$;

COMMENT ON FUNCTION public._sync_attendance_points_worker(uuid) IS
  '#2292 — a regra do credito de presenca, em UM lugar so. De-duplica por (member_id, evento), '
  'nao por id de linha, para que os dois formatos historicos de ref_id se enxergem. '
  'Worker interno sem portao: quem chama e a RPC sync_attendance_points() (portao manage_platform) '
  'ou a EF sync-attendance-points (que faz a sua propria autenticacao e escopo). p_member_id NULL = todos.';

REVOKE ALL ON FUNCTION public._sync_attendance_points_worker(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._sync_attendance_points_worker(uuid) TO service_role;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. A RPC vira portao, e para de ser uma segunda implementacao.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.sync_attendance_points()
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_caller_id uuid;
  v_res jsonb;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RETURN json_build_object('error', 'Not authenticated');
  END IF;
  IF NOT public.can_by_member(v_caller_id, 'manage_platform') THEN
    RETURN json_build_object('error', 'Acesso negado');
  END IF;

  v_res := public._sync_attendance_points_worker(NULL);

  -- Chaves antigas mantidas para nao quebrar chamador nenhum; nada no frontend chama
  -- esta RPC hoje (medido: so database.gen.ts casa com o nome), mas o contrato sai de
  -- graca.
  RETURN json_build_object(
    'success', true,
    'attendance_inserted', (v_res->>'points_created')::int,
    'pts_per_event',       (v_res->>'points_per_attendance')::int
  );
END;
$fn$;

COMMENT ON FUNCTION public.sync_attendance_points() IS
  '#2292 — PORTAO (manage_platform) sobre _sync_attendance_points_worker(). Ate 2026-09-15 esta '
  'funcao era uma SEGUNDA implementacao da regra, gravava o formato antigo (ref_id = events.id) e '
  'foi por isso a origem das 224 duplicatas: 100% delas eram um par uma-linha-desta-funcao mais '
  'uma-linha-da-EF. Nao reimplemente a regra aqui.';

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. Cancelar reuniao PRESERVA o credito, repontando para o evento.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public._cleanup_cancelled_event_attendance()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $fn$
DECLARE
  v_deleted int;
  v_repointed int;
BEGIN
  IF NEW.status = 'cancelled' AND (OLD.status IS DISTINCT FROM 'cancelled') THEN
    -- ORDEM IMPORTA: repontar ANTES de apagar, porque o vinculo credito->evento so
    -- existe atraves da linha de presenca que estamos prestes a apagar.
    --
    -- O comentario que estava aqui afirmava que as linhas "had no irreplaceable signal".
    -- Em 14/09 esse caso apareceu: uma reuniao cancelada por engano levou presenca
    -- legitima junto, e o XP correspondente ficou apontando para um id morto — 22
    -- linhas assim, de 14 pessoas, sem UM rastro em admin_audit_log. Vinte e uma delas
    -- so foram recuperadas em 15/09 lendo dumps de backup: 12 no artefato de 22/08 e 9
    -- no objeto de R2 de 27/07. A 22a caiu numa janela sem backup e nao foi recuperada.
    -- O credito agora sobrevive ao cancelamento, apontando para o EVENTO.
    UPDATE public.gamification_points gp
       SET ref_id = NEW.id
      FROM public.attendance a
     WHERE a.event_id = NEW.id
       AND gp.category = 'attendance'
       AND gp.ref_id = a.id;
    GET DIAGNOSTICS v_repointed = ROW_COUNT;

    DELETE FROM public.attendance WHERE event_id = NEW.id;
    GET DIAGNOSTICS v_deleted = ROW_COUNT;

    IF v_repointed > 0 THEN
      RAISE NOTICE '_cleanup_cancelled_event_attendance: evento % — % presencas apagadas, % creditos repontados para o evento',
        NEW.id, v_deleted, v_repointed;
    END IF;
  END IF;
  RETURN NEW;
END;
$fn$;

COMMENT ON FUNCTION public._cleanup_cancelled_event_attendance() IS
  '#2292 — cancelar reuniao apaga a presenca mas PRESERVA o credito, repontando ref_id para o '
  'evento (ref_kind derivado passa a ''event''). Motivo: quem compareceu compareceu; a reuniao e '
  'que sumiu. Efeito colateral desejado: nunca mais nasce orfa por cancelamento, e a '
  'de-duplicacao por (pessoa, evento) torna a restauracao idempotente.';

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. Limpar presenca APAGA o credito junto.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.clear_member_attendance(p_event_id uuid, p_member_id uuid)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_caller_id uuid;
  v_removed int;
  v_xp int;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  IF v_caller_id = p_member_id THEN
    NULL;
  ELSIF NOT public._can_manage_event(p_event_id) THEN
    RAISE EXCEPTION 'Unauthorized: can only clear own attendance or requires manage_event permission for this event';
  END IF;

  -- ANTES do DELETE: depois dele nao ha mais como ligar credito a evento.
  -- Os dois formatos de ref_id sao cobertos; limpar presenca e afirmar que o registro
  -- esta errado, e um placar que continua contando presenca que a tabela nega e
  -- exatamente o defeito 1 da #2292.
  DELETE FROM public.gamification_points gp
   WHERE gp.category = 'attendance'
     AND gp.member_id = p_member_id
     AND (
       gp.ref_id = p_event_id
       OR gp.ref_id IN (SELECT a.id FROM public.attendance a
                         WHERE a.event_id = p_event_id AND a.member_id = p_member_id)
     );
  GET DIAGNOSTICS v_xp = ROW_COUNT;

  DELETE FROM public.attendance WHERE event_id = p_event_id AND member_id = p_member_id;
  GET DIAGNOSTICS v_removed = ROW_COUNT;

  RETURN json_build_object('success', true, 'cleared', v_removed, 'xp_removed', v_xp);
END;
$fn$;

COMMENT ON FUNCTION public.clear_member_attendance(uuid, uuid) IS
  '#2292 — limpar presenca agora apaga TAMBEM o credito de XP correspondente (os dois formatos de '
  'ref_id). Contraste deliberado com o cancelamento de reuniao, que PRESERVA o credito: limpar e '
  'dizer que o registro esta errado, cancelar e dizer que a reuniao sumiu.';

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. O medidor, para que o guard de CI nao precise reimplementar a consulta.
--    Devolve o numero que interessa E o controle positivo na MESMA leitura: um
--    "0 duplicatas" lido de uma tabela vazia nao e a mesma coisa que um "0" lido
--    de 2.361 linhas, e sem o total na mesma linha nao da para distinguir.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public._audit_attendance_xp_duplicates()
RETURNS TABLE (duplicated_pairs int, duplicated_points int, total_attendance_points int, orphan_rows int)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $fn$
  WITH r AS (
    SELECT gp.id, gp.member_id, gp.points,
           COALESCE(a.event_id, e.id) AS evento
      FROM public.gamification_points gp
      LEFT JOIN public.attendance a ON a.id = gp.ref_id
      LEFT JOIN public.events     e ON e.id = gp.ref_id
     WHERE gp.category = 'attendance'
  ),
  g AS (
    SELECT member_id, evento, count(*) AS n, sum(points) AS pts
      FROM r WHERE evento IS NOT NULL GROUP BY 1, 2 HAVING count(*) > 1
  )
  SELECT (SELECT count(*) FROM g)::int,
         (SELECT COALESCE(sum(pts - (pts / n)), 0) FROM g)::int,
         (SELECT count(*) FROM r)::int,
         (SELECT count(*) FROM r WHERE evento IS NULL)::int;
$fn$;

COMMENT ON FUNCTION public._audit_attendance_xp_duplicates() IS
  '#2292 — medidor do credito de presenca. Devolve duplicatas por (pessoa, evento), pontos '
  'duplicados, o TOTAL de linhas da categoria (controle positivo: sem ele, um zero lido de tabela '
  'vazia parece saude) e as orfas (ref_id que nao resolve em presenca nem em evento).';

REVOKE ALL ON FUNCTION public._audit_attendance_xp_duplicates() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public._audit_attendance_xp_duplicates() TO service_role;
