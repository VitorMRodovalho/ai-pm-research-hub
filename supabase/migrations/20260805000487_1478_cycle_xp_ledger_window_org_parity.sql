-- #1478 (follow-up do audit de pontuacao / Onda 5a #1473): unificar a janela/org de
-- get_member_cycle_xp com o ledger auditavel (_points_statement_json).
--
-- ANTES: cycle_points (e todos os buckets cycle_*) somavam
--   COALESCE(occurred_at, created_at) >= cycle_start  -- SEM teto superior, SEM filtro de org
-- enquanto o ledger usa a janela canonica [cycle_start, cycle_end+1d) com organization_id.
-- Em operacao normal (ciclo atual com cycle_end NULL, org unica) os dois batem; divergem
-- quando o ciclo "current" ja tem cycle_end setado (lag de rotacao) ou o membro tem fatos
-- em outra org. Como a Onda 5a poe /minha-pontuacao (ledger) lado a lado com o card de
-- profile.astro (cycle_points), esse e o cenario de "duas fontes divergentes" a evitar.
--
-- DEPOIS (Opcao 1, ratificada): a mesma convencao de get_member_xp_pillars/award_champion:
--   COALESCE(occurred_at, created_at) >= cycle_start
--     AND (cycle_end IS NULL OR COALESCE(occurred_at, created_at) < cycle_end + 1 day)
--   AND organization_id = <org do membro alvo>
-- aplicada uniformemente a cycle_points, a cada bucket cycle_* E ao ranking (que ranqueia
-- "por este ciclo"), para que cycle_points == total de ciclo do ledger por construcao.
-- Janela plana (SEM a isencao vitalicia de certificacoes do #1448): o ledger nao a tem, e o
-- objetivo e paridade cycle_points == ledger.
--
-- Comportamento HOJE: identico (ciclo 4 aberto -> teto NULL; org unica -> filtro no-op).

CREATE OR REPLACE FUNCTION public.get_member_cycle_xp(p_member_id uuid)
 RETURNS json
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  cycle_start_date date;
  cycle_end_date date;
  v_org_id uuid;
  v_rank int;
  v_total int;
  result json;
  v_caller_id uuid;
  v_scope text;
begin
  -- XP gate: SECDEF + authenticated-grant allowed enumerating any member's XP/rank by id.
  select id into v_caller_id from public.members where auth_id = auth.uid() and is_active = true;
  if v_caller_id is null then
    raise exception 'Not authenticated' using errcode = 'insufficient_privilege';
  end if;
  if p_member_id <> v_caller_id and not public.can_by_member(v_caller_id, 'view_pii') then
    raise exception 'Unauthorized' using errcode = 'insufficient_privilege';
  end if;

  -- FU-2 Slice A: chapter-scope — non-GP/non-sede callers may not read out-of-chapter XP.
  if p_member_id <> v_caller_id then
    v_scope := public.caller_chapter_scope();
    if v_scope is not null
       and (select chapter from public.members where id = p_member_id) is distinct from v_scope then
      raise exception 'Unauthorized' using errcode = 'insufficient_privilege';
    end if;
  end if;

  -- #1478: org do membro alvo (ledger usa a org do caller; single-org hoje -> mesma).
  select organization_id into v_org_id from public.members where id = p_member_id;

  -- Cycle window comes solely from the current cycle (the prior hardcoded literal fallback was removed).
  -- #1478: captura tambem cycle_end para o teto superior [cycle_start, cycle_end+1d).
  select cycle_start, cycle_end into cycle_start_date, cycle_end_date
  from public.cycles where is_current = true limit 1;

  -- M5 (#419 D1): rank by THIS cycle's XP (matches the displayed cycle_points), with a
  -- deterministic member_id tiebreak. Previously ranked on lifetime SUM(points), which
  -- contradicted the cycle_points shown and reshuffled ties non-deterministically.
  -- #1478: mesma janela [cycle_start, cycle_end+1d) + filtro de org que cycle_points.
  WITH ranked AS (
    SELECT member_id,
           COALESCE(SUM(points) FILTER (WHERE COALESCE(occurred_at, created_at) >= cycle_start_date
             AND (cycle_end_date IS NULL OR COALESCE(occurred_at, created_at) < (cycle_end_date + interval '1 day'))), 0) as cycle_pts,
           ROW_NUMBER() OVER (
             ORDER BY COALESCE(SUM(points) FILTER (WHERE COALESCE(occurred_at, created_at) >= cycle_start_date
               AND (cycle_end_date IS NULL OR COALESCE(occurred_at, created_at) < (cycle_end_date + interval '1 day'))), 0) DESC,
                      member_id
           ) as pos
    FROM public.gamification_points
    WHERE organization_id = v_org_id
    GROUP BY member_id
  )
  SELECT pos, (SELECT COUNT(DISTINCT member_id) FROM public.gamification_points WHERE organization_id = v_org_id)
  INTO v_rank, v_total
  FROM ranked WHERE member_id = p_member_id;

  -- #1080: buckets derived from the canonical pillar taxonomy via LEFT JOIN to gamification_rules.
  -- cycle_points/lifetime_points remain a plain SUM over all categories (bucket-independent).
  -- #1478: cada bucket cycle_* usa a janela canonica [cycle_start, cycle_end+1d).
  select json_build_object(
    'lifetime_points', coalesce(sum(gp.points), 0)::int,
    'cycle_points', coalesce(sum(gp.points) filter (where COALESCE(gp.occurred_at, gp.created_at) >= cycle_start_date and (cycle_end_date is null or COALESCE(gp.occurred_at, gp.created_at) < (cycle_end_date + interval '1 day'))), 0)::int,
    'cycle_attendance', coalesce(sum(gp.points) filter (where r.pillar = 'presenca' and COALESCE(gp.occurred_at, gp.created_at) >= cycle_start_date and (cycle_end_date is null or COALESCE(gp.occurred_at, gp.created_at) < (cycle_end_date + interval '1 day'))), 0)::int,
    'cycle_learning', coalesce(sum(gp.points) filter (where r.pillar = 'trilha' and COALESCE(gp.occurred_at, gp.created_at) >= cycle_start_date and (cycle_end_date is null or COALESCE(gp.occurred_at, gp.created_at) < (cycle_end_date + interval '1 day'))), 0)::int,
    'cycle_certs', coalesce(sum(gp.points) filter (where r.pillar = 'certificacoes' and COALESCE(gp.occurred_at, gp.created_at) >= cycle_start_date and (cycle_end_date is null or COALESCE(gp.occurred_at, gp.created_at) < (cycle_end_date + interval '1 day'))), 0)::int,
    'cycle_courses', coalesce(sum(gp.points) filter (where r.pillar = 'trilha' and COALESCE(gp.occurred_at, gp.created_at) >= cycle_start_date and (cycle_end_date is null or COALESCE(gp.occurred_at, gp.created_at) < (cycle_end_date + interval '1 day'))), 0)::int,
    'cycle_artifacts', coalesce(sum(gp.points) filter (where r.pillar = 'producao' and gp.category not like 'showcase%' and COALESCE(gp.occurred_at, gp.created_at) >= cycle_start_date and (cycle_end_date is null or COALESCE(gp.occurred_at, gp.created_at) < (cycle_end_date + interval '1 day'))), 0)::int,
    'cycle_showcase', coalesce(sum(gp.points) filter (where r.pillar = 'producao' and gp.category like 'showcase%' and COALESCE(gp.occurred_at, gp.created_at) >= cycle_start_date and (cycle_end_date is null or COALESCE(gp.occurred_at, gp.created_at) < (cycle_end_date + interval '1 day'))), 0)::int,
    'cycle_bonus', coalesce(sum(gp.points) filter (where (r.pillar is null or r.pillar not in ('presenca','trilha','certificacoes','producao')) and COALESCE(gp.occurred_at, gp.created_at) >= cycle_start_date and (cycle_end_date is null or COALESCE(gp.occurred_at, gp.created_at) < (cycle_end_date + interval '1 day'))), 0)::int,
    'cycle_code', (select cycle_code from public.cycles where is_current = true limit 1),
    'cycle_label', (select cycle_label from public.cycles where is_current = true limit 1),
    'rank_position', coalesce(v_rank, 0),
    'total_ranked', coalesce(v_total, 0)
  ) into result
  from public.gamification_points gp
  left join public.gamification_rules r
    on r.slug = gp.category and r.organization_id = gp.organization_id
  where gp.member_id = p_member_id
    and gp.organization_id = v_org_id
  ;

  return coalesce(result, '{}');
end;
$function$;

-- PostgREST schema reload (RPC surface changed)
NOTIFY pgrst, 'reload schema';
