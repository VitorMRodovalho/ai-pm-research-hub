-- #2292 emenda 2 — "duplicata" passa a ser definida por SALDO, nao por contagem de linhas.
--
-- Por que agora: a decisao do dono de 15/09 foi restaurar as 224 duplicatas do backup e emitir
-- ESTORNO sobre elas, em vez de deixa-las apagadas, para que o ledger consiga explicar o que
-- aconteceu com aqueles 2.240 pontos (e a #2297 e exatamente sobre nao conseguir).
--
-- Isso quebra a definicao anterior. Com o par restaurado mais o estorno, uma (pessoa, evento)
-- passa a ter TRES linhas — +10 (linha da RPC, restaurada), +10 (linha da EF) e -10 (estorno) —
-- e a versao anterior contava "mais de uma linha POSITIVA" como duplicata. Ela acusaria 224
-- duplicatas sobre um placar que esta correto.
--
-- A definicao certa nao e sobre linhas, e sim sobre o que a pessoa TEM: ha duplicata quando o
-- SALDO de (pessoa, evento) excede UM credito. Comparar contra o maior credito positivo do
-- proprio grupo, em vez de contra `gamification_rules`, mantem a medida correta para linhas
-- historicas escritas quando o valor base era outro.
--
--   +10, +10        -> saldo 20, maior 10 -> 20 > 10  -> DUPLICATA, excesso 10
--   +10, +10, -10   -> saldo 10, maior 10 -> 10 > 10  -> nao
--   +10             -> saldo 10, maior 10 -> 10 > 10  -> nao
--   +10, -10        -> saldo  0, maior 10 ->  0 > 10  -> nao
--
-- Este e o mesmo movimento que a emenda anterior fez na de-duplicacao do worker (`HAVING
-- SUM(points) > 0`): num ledger append-only, todo leitor que contava LINHAS precisa passar a
-- ler SALDO, senao o proprio mecanismo de correcao aparece como defeito.

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
    SELECT member_id, evento,
           SUM(points) AS saldo,
           COALESCE(MAX(points) FILTER (WHERE points > 0), 0) AS maior_credito
      FROM r WHERE evento IS NOT NULL
     GROUP BY 1, 2
    HAVING SUM(points) > COALESCE(MAX(points) FILTER (WHERE points > 0), 0)
  )
  SELECT (SELECT count(*) FROM g)::int,
         (SELECT COALESCE(sum(saldo - maior_credito), 0) FROM g)::int,
         (SELECT count(*) FROM r)::int,
         (SELECT count(*) FROM r WHERE evento IS NULL)::int;
$fn$;

COMMENT ON FUNCTION public._audit_attendance_xp_duplicates() IS
  '#2292 — medidor do credito de presenca. Duplicata e SALDO de (pessoa, evento) acima de UM '
  'credito, nao contagem de linhas: num ledger append-only o estorno e o mecanismo de correcao, e '
  'um medidor que conta linhas acusa a propria correcao. Compara contra o maior credito positivo '
  'do grupo, nao contra gamification_rules, para nao errar em linhas historicas escritas quando o '
  'valor base era outro. Devolve tambem o TOTAL de linhas da categoria (controle positivo: sem ele, '
  'um zero lido de tabela vazia parece saude) e as orfas (ref_id que nao resolve em presenca nem '
  'em evento).';
