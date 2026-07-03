-- #1080 fix(gamification): realign get_member_cycle_xp buckets with the canonical pillar taxonomy.
--
-- Root cause: the JSON bucket filters used hardcoded bare category names ('showcase', 'artifact')
-- that predate the granular slug taxonomy. The write side emits canonical slugs matching
-- gamification_rules.slug (showcase_case_study, showcase_tool_review, showcase_awareness,
-- champion_deliverable, artifact_published, deliverable_completed, action_resolved,
-- agenda_block_*, curation_*). Consequence: cycle_artifacts was ALWAYS 0 (no row uses bare
-- 'artifact'), showcase_* fell into cycle_bonus, and champions/curadoria/protagonismo were all
-- dumped into cycle_bonus. badge/specialization landed in no bucket at all.
--
-- Fix: derive the buckets by LEFT JOIN to gamification_rules.pillar, so buckets partition
-- cycle_points cleanly and future slugs auto-route by pillar. TOTAL (cycle_points/lifetime_points)
-- and the RANK computation are UNCHANGED — this only fixes the per-bucket breakdown.
--
-- Bucket mapping (canonical, from gamification_rules.pillar):
--   cycle_attendance      = pillar 'presenca'
--   cycle_learning        = pillar 'trilha'            (trail/course/knowledge_ai_pm/specialization)
--   cycle_courses         = pillar 'trilha'            (legacy duplicate of learning; kept)
--   cycle_certs           = pillar 'certificacoes'     (badge + cert_* — badge is canonically certs)
--   cycle_showcase        = pillar 'producao' AND category LIKE 'showcase%'
--   cycle_artifacts       = pillar 'producao' AND category NOT LIKE 'showcase%'
--   cycle_bonus           = everything else (champions + curadoria + protagonismo + any orphan/future)

CREATE OR REPLACE FUNCTION public.get_member_cycle_xp(p_member_id uuid)
 RETURNS json
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  cycle_start_date date;
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

  -- Cycle window comes solely from the current cycle (the prior hardcoded literal fallback was removed).
  select cycle_start into cycle_start_date
  from public.cycles where is_current = true limit 1;

  -- M5 (#419 D1): rank by THIS cycle's XP (matches the displayed cycle_points), with a
  -- deterministic member_id tiebreak. Previously ranked on lifetime SUM(points), which
  -- contradicted the cycle_points shown and reshuffled ties non-deterministically.
  WITH ranked AS (
    SELECT member_id,
           COALESCE(SUM(points) FILTER (WHERE created_at >= cycle_start_date), 0) as cycle_pts,
           ROW_NUMBER() OVER (
             ORDER BY COALESCE(SUM(points) FILTER (WHERE created_at >= cycle_start_date), 0) DESC,
                      member_id
           ) as pos
    FROM public.gamification_points
    GROUP BY member_id
  )
  SELECT pos, (SELECT COUNT(DISTINCT member_id) FROM public.gamification_points)
  INTO v_rank, v_total
  FROM ranked WHERE member_id = p_member_id;

  -- #1080: buckets derived from the canonical pillar taxonomy via LEFT JOIN to gamification_rules.
  -- cycle_points/lifetime_points remain a plain SUM over all categories (bucket-independent).
  select json_build_object(
    'lifetime_points', coalesce(sum(gp.points), 0)::int,
    'cycle_points', coalesce(sum(gp.points) filter (where gp.created_at >= cycle_start_date), 0)::int,
    'cycle_attendance', coalesce(sum(gp.points) filter (where r.pillar = 'presenca' and gp.created_at >= cycle_start_date), 0)::int,
    'cycle_learning', coalesce(sum(gp.points) filter (where r.pillar = 'trilha' and gp.created_at >= cycle_start_date), 0)::int,
    'cycle_certs', coalesce(sum(gp.points) filter (where r.pillar = 'certificacoes' and gp.created_at >= cycle_start_date), 0)::int,
    'cycle_courses', coalesce(sum(gp.points) filter (where r.pillar = 'trilha' and gp.created_at >= cycle_start_date), 0)::int,
    'cycle_artifacts', coalesce(sum(gp.points) filter (where r.pillar = 'producao' and gp.category not like 'showcase%' and gp.created_at >= cycle_start_date), 0)::int,
    'cycle_showcase', coalesce(sum(gp.points) filter (where r.pillar = 'producao' and gp.category like 'showcase%' and gp.created_at >= cycle_start_date), 0)::int,
    'cycle_bonus', coalesce(sum(gp.points) filter (where (r.pillar is null or r.pillar not in ('presenca','trilha','certificacoes','producao')) and gp.created_at >= cycle_start_date), 0)::int,
    'cycle_code', (select cycle_code from public.cycles where is_current = true limit 1),
    'cycle_label', (select cycle_label from public.cycles where is_current = true limit 1),
    'rank_position', coalesce(v_rank, 0),
    'total_ranked', coalesce(v_total, 0)
  ) into result
  from public.gamification_points gp
  left join public.gamification_rules r
    on r.slug = gp.category and r.organization_id = gp.organization_id
  where gp.member_id = p_member_id;

  return coalesce(result, '{}');
end;
$function$;
