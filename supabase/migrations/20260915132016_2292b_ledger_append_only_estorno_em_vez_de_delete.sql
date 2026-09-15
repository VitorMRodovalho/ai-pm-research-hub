-- #2292 emenda — o ledger e APPEND-ONLY, e o conserto anterior nao sabia disso.
--
-- A migration 20260915040623 fez `clear_member_attendance` APAGAR a linha de XP. Isso e a
-- direcao 2 que a issue propunha ("fazer a limpeza de presenca remover o XP"), e ela viola
-- uma invariante ratificada que nenhuma das duas conhecia: a onda 3 da #1087 estabelece que
-- `gamification_points` e um ledger APPEND-ONLY, e o guard
-- `tests/contracts/1087-wave3-ledger-append-only.test.mjs` reprova qualquer corpo de funcao
-- que de DELETE nele. O unico carve-out e apagamento por Art. 18 da LGPD, e o proprio
-- comentario do guard diz: "Add a function name here ONLY for a real Art. 18 erasure path,
-- never for a business revoke."
--
-- O guard achou isto em CI, nao em revisao. Ficou verde localmente porque `npm test` roda
-- DOIS blocos e o primeiro terminou verde: ler o primeiro sumario e chamar de suite passou.
--
-- O padrao correto ja existia no repo, em `revoke_agenda_block_xp`: ESTORNO — uma linha de
-- pontos NEGATIVOS que zera o saldo e preserva a historia. O efeito no placar e identico ao
-- do DELETE; o que muda e que o ledger continua podendo dizer o que aconteceu, que e o
-- motivo de a invariante existir.
--
-- Tres consequencias, e as tres estao abaixo:
--   1. `clear_member_attendance` estorna em vez de apagar;
--   2. a de-duplicacao do worker passa a olhar o SALDO (SUM > 0), nao a existencia de linha:
--      +10 seguido de -10 e saldo zero, e uma presenca re-adicionada depois DEVE poder ser
--      creditada de novo;
--   3. o medidor passa a contar so linhas POSITIVAS como credito, senao o par credito+estorno
--      seria lido como duplicata — o mesmo criterio que `get_member_xp_pillars` ja usa
--      (`FILTER (WHERE p.points > 0)`).

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Limpar presenca ESTORNA, nao apaga.
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
  v_estorno_rows int := 0;
  v_estorno_pts  int := 0;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  IF v_caller_id = p_member_id THEN
    NULL;
  ELSIF NOT public._can_manage_event(p_event_id) THEN
    RAISE EXCEPTION 'Unauthorized: can only clear own attendance or requires manage_event permission for this event';
  END IF;

  -- ANTES do DELETE da presenca: depois dele nao ha mais como ligar credito a evento.
  -- #1087 onda 3: ledger append-only. Estorno de pontos negativos, no molde de
  -- `revoke_agenda_block_xp`. Os DOIS formatos historicos de ref_id entram no saldo, e o
  -- `HAVING <> 0` evita estornar quem ja esta zerado (chamada repetida vira no-op).
  WITH saldo AS (
    SELECT gp.member_id, gp.organization_id, SUM(gp.points) AS pts
      FROM public.gamification_points gp
      LEFT JOIN public.attendance a2 ON a2.id = gp.ref_id
     WHERE gp.category = 'attendance'
       AND gp.member_id = p_member_id
       AND COALESCE(a2.event_id, gp.ref_id) = p_event_id
     GROUP BY gp.member_id, gp.organization_id
    HAVING SUM(gp.points) <> 0
  ), estorno AS (
    INSERT INTO public.gamification_points (member_id, organization_id, points, category, reason, ref_id, granted_by)
    SELECT s.member_id, s.organization_id, -s.pts, 'attendance',
           'Estorno (presença removida do registro)', p_event_id, v_caller_id
      FROM saldo s
    RETURNING points
  )
  SELECT count(*), COALESCE(SUM(points), 0)::int INTO v_estorno_rows, v_estorno_pts FROM estorno;

  DELETE FROM public.attendance WHERE event_id = p_event_id AND member_id = p_member_id;
  GET DIAGNOSTICS v_removed = ROW_COUNT;

  RETURN json_build_object('success', true, 'cleared', v_removed,
                           'xp_reversed_rows', v_estorno_rows, 'xp_reversed_points', v_estorno_pts);
END;
$fn$;

COMMENT ON FUNCTION public.clear_member_attendance(uuid, uuid) IS
  '#2292 — limpar presenca ESTORNA o credito de XP (linha de pontos negativos, ref_id = evento), '
  'nunca apaga: gamification_points e ledger append-only (#1087 onda 3), e o unico carve-out de '
  'DELETE e apagamento por Art. 18 da LGPD. Contraste deliberado com o cancelamento de reuniao, '
  'que PRESERVA o credito inteiro: limpar e dizer que o registro esta errado, cancelar e dizer que '
  'a reuniao sumiu.';

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. A de-duplicacao passa a olhar SALDO, nao existencia de linha.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public._sync_attendance_points_worker(p_member_id uuid DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_pts int;
  v_ins int := 0;
BEGIN
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
     -- De-duplicacao por (PESSOA, EVENTO), pelo SALDO. O LEFT JOIN resolve o ref_id
     -- polimorfico: se aponta para uma presenca, o evento vem dela; se aponta para o evento,
     -- o COALESCE devolve o proprio ref_id.
     --
     -- SUM > 0, e nao EXISTS: com o ledger append-only um credito estornado deixa DUAS linhas
     -- (+10 e -10) com saldo zero. Um EXISTS leria "ja tem credito" e recusaria para sempre
     -- re-creditar alguem cuja presenca foi removida por engano e depois re-adicionada.
     AND NOT EXISTS (
       SELECT 1
         FROM public.gamification_points gp
         LEFT JOIN public.attendance a2 ON a2.id = gp.ref_id
        WHERE gp.category = 'attendance'
          AND gp.member_id = a.member_id
          AND COALESCE(a2.event_id, gp.ref_id) = a.event_id
        HAVING SUM(gp.points) > 0
     );
  GET DIAGNOSTICS v_ins = ROW_COUNT;

  RETURN jsonb_build_object('success', true, 'points_created', v_ins, 'points_per_attendance', v_pts);
END;
$fn$;

COMMENT ON FUNCTION public._sync_attendance_points_worker(uuid) IS
  '#2292 — a regra do credito de presenca, em UM lugar so. De-duplica por (member_id, evento) e '
  'pelo SALDO (SUM > 0), nao por id de linha nem por existencia: com o ledger append-only (#1087) '
  'um credito estornado deixa +N e -N, e quem for re-creditado depois precisa poder ser. '
  'Worker interno sem portao: quem chama e a RPC sync_attendance_points() (portao manage_platform) '
  'ou a EF sync-attendance-points (que faz a sua propria autenticacao e escopo). p_member_id NULL = todos.';

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. O medidor conta so linha POSITIVA como credito.
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
    -- So linhas POSITIVAS contam como credito: um par credito+estorno (+10, -10) e o ledger
    -- funcionando, nao duplicata. Mesmo criterio de get_member_xp_pillars (#1087 onda 3).
    SELECT member_id, evento,
           count(*) FILTER (WHERE points > 0) AS n,
           COALESCE(sum(points) FILTER (WHERE points > 0), 0) AS pts
      FROM r WHERE evento IS NOT NULL GROUP BY 1, 2
    HAVING count(*) FILTER (WHERE points > 0) > 1
  )
  SELECT (SELECT count(*) FROM g)::int,
         (SELECT COALESCE(sum(pts - (pts / n)), 0) FROM g)::int,
         (SELECT count(*) FROM r)::int,
         (SELECT count(*) FROM r WHERE evento IS NULL)::int;
$fn$;

COMMENT ON FUNCTION public._audit_attendance_xp_duplicates() IS
  '#2292 — medidor do credito de presenca. Conta como credito so linha de pontos POSITIVOS, '
  'porque o ledger e append-only e um estorno (-N) e o mecanismo, nao o defeito. Devolve '
  'duplicatas por (pessoa, evento), pontos duplicados, o TOTAL de linhas da categoria (controle '
  'positivo: sem ele, um zero lido de tabela vazia parece saude) e as orfas (ref_id que nao '
  'resolve em presenca nem em evento).';
