-- ============================================================================
-- Migration: volunteer_funnel_summary — refactor to selection_applications
-- Date:      2026-04-26
-- Eixo:      Post-V4 / Issue log P2 (stale data fix)
-- Depends:   20260425030000_b9_drop_unused_volunteer_rpc (kept table as historical)
-- ADR:       0011 (V4 auth via can_by_member) + 0012 (reader alignment)
--
-- Why:
--   `volunteer_funnel_summary` hoje lê de `volunteer_applications` (frozen 10/Mar,
--   143 rows). A tabela ativa de seleção é `selection_applications` (80 rows vivas,
--   atualizada pelo /admin/selection e cycle Batch 2 aberto 28/Mar). MCP tool #62
--   `get_volunteer_funnel` está servindo dados stale silenciosamente.
--
-- What:
--   - DROP old integer-param version (p_cycle integer) + CREATE text-param version
--     (p_cycle_code text) ler de selection_applications + selection_cycles.
--   - V4 auth pattern: can_by_member(caller, 'manage_member') em vez de role list.
--   - Return shape mantém chaves by_cycle/certifications/geography + adiciona
--     by_status (novos stages: approved/submitted/objective_cutoff/etc) e source tag.
--   - certifications é text no novo schema (ex: "PMP,PMI-RMP"): string_to_array
--     + trim + upper para normalizar antes do GROUP BY.
--   - matched_members derivado via email match em members (linked_application_id
--     é uuid para returning applicants, não identidade member).
--
-- Rollback:
--   DROP FUNCTION public.volunteer_funnel_summary(text);
--   Recriar versão integer lendo de volunteer_applications (ver
--   20260312010000_volunteer_applications.sql).
-- ============================================================================

BEGIN;

-- 1) Drop old signature (integer param)
DROP FUNCTION IF EXISTS public.volunteer_funnel_summary(integer);

-- 2) New implementation
CREATE OR REPLACE FUNCTION public.volunteer_funnel_summary(
  p_cycle_code text DEFAULT NULL
)
RETURNS json
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_caller record;
  v_result json;
BEGIN
  SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
  IF NOT public.can_by_member(v_caller.id, 'manage_member') THEN
    RAISE EXCEPTION 'insufficient_authority: manage_member';
  END IF;

  SELECT json_build_object(
    'source', 'selection_applications',
    'by_cycle', (
      SELECT json_agg(row_to_json(c) ORDER BY c.open_date DESC)
      FROM (
        SELECT
          sc.cycle_code,
          sc.title                                                           AS cycle_title,
          sc.status                                                          AS cycle_status,
          sc.open_date,
          sc.close_date,
          COUNT(sa.id)                                                       AS total_applications,
          COUNT(DISTINCT sa.email)                                           AS unique_applicants,
          COUNT(sa.id) FILTER (
            WHERE EXISTS (
              SELECT 1 FROM public.members m
              WHERE m.email IS NOT NULL
                AND lower(m.email) = lower(sa.email)
            )
          )                                                                  AS matched_members,
          COUNT(sa.id) FILTER (
            WHERE sa.status NOT IN ('cancelled','withdrawn','rejected')
          )                                                                  AS active_applications,
          COUNT(sa.id) FILTER (WHERE sa.status = 'converted')                AS converted,
          COUNT(sa.id) FILTER (WHERE sa.status = 'approved')                 AS approved,
          MIN(sa.created_at)::date                                           AS earliest_application,
          MAX(sa.created_at)::date                                           AS latest_application
        FROM public.selection_cycles sc
        LEFT JOIN public.selection_applications sa ON sa.cycle_id = sc.id
        WHERE (p_cycle_code IS NULL OR sc.cycle_code = p_cycle_code)
        GROUP BY sc.id, sc.cycle_code, sc.title, sc.status, sc.open_date, sc.close_date
      ) c
    ),
    'by_status', (
      SELECT json_agg(row_to_json(s) ORDER BY s.cnt DESC)
      FROM (
        SELECT sa.status, COUNT(*)::bigint AS cnt
        FROM public.selection_applications sa
        JOIN public.selection_cycles sc ON sc.id = sa.cycle_id
        WHERE (p_cycle_code IS NULL OR sc.cycle_code = p_cycle_code)
        GROUP BY sa.status
      ) s
    ),
    'certifications', (
      SELECT json_agg(row_to_json(ct) ORDER BY ct.cnt DESC)
      FROM (
        SELECT cert, COUNT(*)::bigint AS cnt
        FROM (
          SELECT trim(upper(x.cert)) AS cert
          FROM public.selection_applications sa
          JOIN public.selection_cycles sc ON sc.id = sa.cycle_id
          CROSS JOIN LATERAL unnest(string_to_array(sa.certifications, ',')) AS x(cert)
          WHERE sa.certifications IS NOT NULL
            AND sa.certifications <> ''
            AND (p_cycle_code IS NULL OR sc.cycle_code = p_cycle_code)
        ) y
        WHERE cert <> ''
        GROUP BY cert
        LIMIT 20
      ) ct
    ),
    'geography', (
      SELECT json_agg(row_to_json(g) ORDER BY g.cnt DESC)
      FROM (
        SELECT sa.state, sa.country, COUNT(*)::bigint AS cnt
        FROM public.selection_applications sa
        JOIN public.selection_cycles sc ON sc.id = sa.cycle_id
        WHERE (p_cycle_code IS NULL OR sc.cycle_code = p_cycle_code)
        GROUP BY sa.state, sa.country
        LIMIT 20
      ) g
    )
  ) INTO v_result;

  RETURN v_result;
END;
$$;

COMMENT ON FUNCTION public.volunteer_funnel_summary(text) IS
  'Selection funnel analytics. Reads from selection_applications (post-14/Mar active data). V4 auth via can_by_member(manage_member). Param: cycle_code (e.g. cycle3-2026). Replaces stale volunteer_applications reader (frozen 10/Mar).';

GRANT EXECUTE ON FUNCTION public.volunteer_funnel_summary(text) TO authenticated;

-- 3) Reload PostgREST schema cache (MCP tool consumes via RPC)
NOTIFY pgrst, 'reload schema';

COMMIT;
