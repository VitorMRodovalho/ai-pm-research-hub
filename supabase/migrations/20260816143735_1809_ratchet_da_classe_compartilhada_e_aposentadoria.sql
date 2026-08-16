-- #1809 — parte 2: literal morto de efeito zero, aposentadoria, e o ratchet da classe
--
-- Separada da parte 1 de proposito: recalculate_cycle_rankings e a unica funcao do caminho
-- critico de ranking, e uma limpeza de efeito ZERO nao viaja junto com mudanca de predicado.

CREATE OR REPLACE FUNCTION public.recalculate_cycle_rankings(p_cycle_id uuid, p_reason text DEFAULT 'manual'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_researcher_count int;
  v_leader_count int;
  v_snapshot_id uuid;
BEGIN
  -- Auth (admin only)
  SELECT id INTO v_caller_id FROM members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  IF NOT public.can_by_member(v_caller_id, 'manage_platform') THEN
    RAISE EXCEPTION 'Unauthorized: requires manage_platform permission for ranking recalc';
  END IF;

  -- Reset ranks
  UPDATE selection_applications
  SET rank_researcher = NULL, rank_leader = NULL
  WHERE cycle_id = p_cycle_id;

  -- Ranking 1: researcher track (Standard Competition Ranking via RANK())
  -- Includes: role_applied='researcher' OR promotion_path='direct_researcher'
  -- Excludes: promoted to leader AND leader app already approved/converted (they're not researchers anymore)
  WITH ranked AS (
    SELECT a.id,
      RANK() OVER (
        ORDER BY a.research_score DESC NULLS LAST, a.applicant_name ASC
      ) as rnk
    FROM selection_applications a
    WHERE a.cycle_id = p_cycle_id
      AND a.role_applied = 'researcher'
      AND a.research_score IS NOT NULL
      AND a.status NOT IN ('withdrawn','rejected','cancelled')
      AND NOT EXISTS (
        -- Exclude if linked leader app is approved/converted
        SELECT 1 FROM selection_applications la
        WHERE la.id = a.linked_application_id
          AND la.role_applied = 'leader'
          AND la.status IN ('approved','converted')
      )
  )
  UPDATE selection_applications a
  SET rank_researcher = r.rnk
  FROM ranked r WHERE a.id = r.id;

  GET DIAGNOSTICS v_researcher_count = ROW_COUNT;

  -- Ranking 2: leader track
  WITH ranked AS (
    SELECT a.id,
      RANK() OVER (
        ORDER BY a.leader_score DESC NULLS LAST, a.applicant_name ASC
      ) as rnk
    FROM selection_applications a
    WHERE a.cycle_id = p_cycle_id
      AND (a.role_applied = 'leader' OR a.promotion_path = 'triaged_to_leader')
      AND a.leader_score IS NOT NULL
      AND a.status NOT IN ('withdrawn','rejected','cancelled')
  )
  UPDATE selection_applications a
  SET rank_leader = r.rnk
  FROM ranked r WHERE a.id = r.id;

  GET DIAGNOSTICS v_leader_count = ROW_COUNT;

  -- Audit snapshot
  INSERT INTO selection_ranking_snapshots (cycle_id, triggered_by, reason, rankings, formula_version)
  SELECT p_cycle_id, v_caller_id, p_reason,
    jsonb_agg(jsonb_build_object(
      'application_id', id,
      'applicant_name', applicant_name,
      'role_applied', role_applied,
      'promotion_path', promotion_path,
      'research_score', research_score,
      'leader_score', leader_score,
      'rank_researcher', rank_researcher,
      'rank_leader', rank_leader,
      'status', status
    )),
    'v1.0-cr047'
  FROM selection_applications
  WHERE cycle_id = p_cycle_id
  RETURNING id INTO v_snapshot_id;

  RETURN jsonb_build_object(
    'success', true,
    'cycle_id', p_cycle_id,
    'researcher_ranked', v_researcher_count,
    'leader_ranked', v_leader_count,
    'snapshot_id', v_snapshot_id,
    'formula_version', 'v1.0-cr047',
    'formula', jsonb_build_object(
      'research_score', 'objective_pert + interview_pert',
      'leader_score', 'research_score * 0.7 + leader_extra_pert * 0.3',
      'tiebreaker', 'RANK() OVER (..., applicant_name ASC) — Standard Competition Ranking ISO 80000-2'
    )
  );
END;
$function$;

-- admin_run_retention_cleanup: aposentada (decisao do PM, 16/08).
-- Citava TRES colunas inexistentes — notifications.read (e is_read), data_anomaly_log.status
-- (a tabela nao tem status) e selection_applications.applied_at (e application_date) — e falhava
-- na primeira. Sem chamador no app ou no MCP, e fora de qualquer cron. A retencao que importa
-- roda nos crons de LGPD, que sao independentes e seguem de pe.
DROP FUNCTION IF EXISTS public.admin_run_retention_cleanup();

CREATE OR REPLACE FUNCTION public._audit_shared_state_literal_domain()
RETURNS TABLE(funcao text, args text, coluna text, literal text, tabela_resolvida text, fora_do_dominio boolean)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
  WITH shared AS MATERIALIZED (
    SELECT a.attname::text AS col
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    JOIN pg_attribute a ON a.attrelid = c.oid AND a.attnum > 0 AND NOT a.attisdropped
    WHERE n.nspname = 'public' AND c.relkind IN ('r', 'p')
    GROUP BY a.attname
    HAVING count(*) > 1
  ),
  rels AS MATERIALIZED (
    SELECT c.oid AS reloid, n.nspname::text AS sch, c.relname::text AS tbl, s.col, a.attnum
    FROM shared s
    JOIN pg_attribute a ON a.attname = s.col AND a.attnum > 0 AND NOT a.attisdropped
    JOIN pg_class c ON c.oid = a.attrelid AND c.relkind IN ('r', 'p', 'v', 'm')
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname NOT IN ('pg_catalog', 'information_schema')
  ),
  dom AS MATERIALIZED (
    SELECT r.reloid, r.col,
           (regexp_matches(pg_get_constraintdef(ct.oid), '''([a-zA-Z_0-9 -]+)''::text', 'g'))[1] AS allowed
    FROM rels r
    JOIN pg_constraint ct ON ct.conrelid = r.reloid AND ct.contype = 'c' AND ct.conkey = ARRAY[r.attnum]::int2[]
    WHERE pg_get_constraintdef(ct.oid) ~ '= ANY \(ARRAY\['
      AND pg_get_constraintdef(ct.oid) !~ '(jsonb|numeric|integer|->>|~)'
  ),
  colcheck AS MATERIALIZED (SELECT DISTINCT col FROM dom),
  fn AS MATERIALIZED (
    SELECT p.oid, p.proname::text AS nm,
           pg_get_function_identity_arguments(p.oid) AS fargs,
           regexp_replace(p.prosrc, '--[^\n]*', ' ', 'g') AS src
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.prokind = 'f'
      AND p.proname NOT IN ('_audit_state_literal_domain', '_audit_shared_state_literal_domain')
  ),
  cand AS MATERIALIZED (
    SELECT f.oid, f.nm, f.fargs, f.src, k.col
    FROM fn f
    JOIN colcheck k ON f.src ~ ('\y' || k.col || '\s*(=|<>|!=|IN\y)')
  ),
  trg AS MATERIALIZED (
    SELECT DISTINCT f.oid, c.relname::text AS tbl
    FROM fn f
    JOIN pg_trigger t ON t.tgfoid = f.oid
    JOIN pg_class c ON c.oid = t.tgrelid
  ),
  refs AS MATERIALIZED (
    SELECT c.oid, c.col, r.reloid FROM cand c JOIN rels r ON r.col = c.col AND c.src ~ ('\y' || r.tbl || '\y')
    UNION
    SELECT c.oid, c.col, r.reloid FROM cand c JOIN trg g ON g.oid = c.oid JOIN rels r ON r.col = c.col AND r.tbl = g.tbl
  ),
  solo AS MATERIALIZED (
    SELECT oid, col, min(reloid) AS reloid
    FROM refs GROUP BY oid, col HAVING count(DISTINCT reloid) = 1
  ),
  pairs AS MATERIALIZED (
    SELECT s.oid, s.col, s.reloid, (m)[1] AS lit
    FROM solo s JOIN cand c ON c.oid = s.oid AND c.col = s.col,
         regexp_matches(c.src, '\y' || s.col || '\s*(?:=|<>|!=)\s*''([a-zA-Z_0-9 -]{0,60})''', 'g') AS m
    UNION
    SELECT s.oid, s.col, s.reloid, (regexp_matches((m)[1], '''([a-zA-Z_0-9 -]*)''', 'g'))[1]
    FROM solo s JOIN cand c ON c.oid = s.oid AND c.col = s.col,
         regexp_matches(c.src, '\y' || s.col || '\s+(?:NOT\s+)?IN\s*\(([^)]{0,250})\)', 'g') AS m
  )
  SELECT (SELECT p.proname::text FROM pg_proc p WHERE p.oid = pr.oid),
         (SELECT pg_get_function_identity_arguments(p.oid) FROM pg_proc p WHERE p.oid = pr.oid),
         pr.col,
         pr.lit,
         (SELECT n.nspname || '.' || c.relname FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace WHERE c.oid = pr.reloid),
         NOT EXISTS (SELECT 1 FROM dom d WHERE d.reloid = pr.reloid AND d.col = pr.col AND d.allowed = pr.lit)
  FROM pairs pr
  WHERE pr.lit <> ''
    AND EXISTS (SELECT 1 FROM dom d WHERE d.reloid = pr.reloid AND d.col = pr.col)
  ORDER BY 6 DESC, 1, 3, 4;
$function$;

COMMENT ON FUNCTION public._audit_shared_state_literal_domain() IS
  'Ratchet do #1809, irmao do _audit_state_literal_domain (#1805). Aquele cobre coluna de estado cujo NOME tem dono UNICO em public; este cobre a outra metade, a de nome COMPARTILHADO -- status existe em ~50 tabelas, cada uma com seu dominio. A ambiguidade e sobre a TABELA, e aqui ela e resolvida POR CONSULTA, nao por regex: para cada funcao, quais relacoes que possuem aquela coluna o corpo referencia. Exatamente uma = o literal so pode ser daquela tabela. Duas armadilhas medidas no #1809 estao fechadas por construcao. (a) Gatilho: NEW./OLD. nao citam a tabela no texto, entao a tabela do trigger entra no conjunto por pg_trigger -- sem isso tres gatilhos resolviam para a tabela VIZINHA. (b) Schema nao-public entra em rels de proposito: e o que torna cron.job_run_details um segundo dono e derruba a funcao para ambigua, em vez de resolve-la errado. O preco e ser conservador: funcao que referencia duas relacoes com a coluna sai da cobertura (get_invitation_health saiu assim). Devolve TODOS os pares examinados, com fora_do_dominio, para que lista vazia seja distinguivel de guard cego.';

REVOKE ALL ON FUNCTION public._audit_shared_state_literal_domain() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._audit_shared_state_literal_domain() TO service_role;
