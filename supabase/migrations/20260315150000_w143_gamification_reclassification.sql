-- W143: Gamification Category Reclassification
-- CRITICAL ORDER: Schema → Functions → VIEW → Data migration
-- Must execute in this order to prevent duplicates and data corruption.

BEGIN;

-- ═══════════════════════════════════════════════════════════════
-- BLOCO 1: Schema — courses table evolution
-- ═══════════════════════════════════════════════════════════════

-- Update CHECK constraint to allow new categories
ALTER TABLE public.gamification_points DROP CONSTRAINT IF EXISTS gamification_points_category_check;
ALTER TABLE public.gamification_points ADD CONSTRAINT gamification_points_category_check
  CHECK (category = ANY (ARRAY[
    'attendance', 'course', 'artifact', 'bonus',
    'trail', 'cert_pmi_senior', 'cert_cpmai', 'cert_pmi_mid',
    'cert_pmi_practitioner', 'cert_pmi_entry', 'specialization',
    'knowledge_ai_pm', 'badge'
  ]));

ALTER TABLE public.courses
  ADD COLUMN IF NOT EXISTS credly_badge_name text,
  ADD COLUMN IF NOT EXISTS is_trail boolean DEFAULT true;

-- Populate credly_badge_name for the 6 trail courses (have Credly badges)
UPDATE public.courses SET credly_badge_name = 'Generative AI Overview for Project Managers' WHERE code = 'GENAI_OVERVIEW';
UPDATE public.courses SET credly_badge_name = 'Data Landscape of GenAI for Project Managers' WHERE code = 'DATA_LANDSCAPE';
UPDATE public.courses SET credly_badge_name = 'Talking to AI: Prompt Engineering for Project Managers' WHERE code = 'PROMPT_ENG';
UPDATE public.courses SET credly_badge_name = 'Practical Application of Gen AI for Project Managers' WHERE code = 'PRACTICAL_GENAI';
UPDATE public.courses SET credly_badge_name = 'AI in Infrastructure & Construction Projects' WHERE code = 'AI_INFRA';
UPDATE public.courses SET credly_badge_name = 'AI in Agile Delivery' WHERE code = 'AI_AGILE';

-- Trail = 6 badges. CPMAI_INTRO and CDBA_INTRO are optional (no Credly badge)
UPDATE public.courses SET is_trail = false WHERE code IN ('CDBA_INTRO', 'CPMAI_INTRO');
UPDATE public.courses SET is_trail = true WHERE code IN (
  'GENAI_OVERVIEW', 'DATA_LANDSCAPE', 'PROMPT_ENG',
  'PRACTICAL_GENAI', 'AI_INFRA', 'AI_AGILE'
);

-- ═══════════════════════════════════════════════════════════════
-- BLOCO E: Trail Data Reconciliation (addendum)
-- Clean false bulk-inserted data BEFORE functions/reclassification
-- ═══════════════════════════════════════════════════════════════

-- E.2 Delete false course_progress entries (bulk insert 2026-03-05 20:36:58)

-- Italo: 0 real badges, delete all bulk entries
DELETE FROM course_progress
WHERE member_id = (SELECT id FROM members WHERE full_name LIKE '%Italo%Soares%')
AND completed_at = '2026-03-05 20:36:58.893954+00';

-- Luciana: 0 real badges, delete all bulk entries
DELETE FROM course_progress
WHERE member_id = (SELECT id FROM members WHERE full_name LIKE '%Luciana%Dutra%')
AND completed_at = '2026-03-05 20:36:58.893954+00';

-- Marcelo: 0 real badges
DELETE FROM course_progress
WHERE member_id = (SELECT id FROM members WHERE full_name LIKE '%Marcelo%Ferreira%')
AND completed_at = '2026-03-05 20:36:58.893954+00';

-- Rodrigo Grilo: 0 real badges
DELETE FROM course_progress
WHERE member_id = (SELECT id FROM members WHERE full_name LIKE '%Rodrigo%Grilo%')
AND completed_at = '2026-03-05 20:36:58.893954+00'
AND course_id NOT IN (
  SELECT c.id FROM courses c
  JOIN gamification_points gp ON gp.member_id = (SELECT id FROM members WHERE full_name LIKE '%Rodrigo%Grilo%')
    AND gp.reason LIKE 'Credly:%' AND gp.reason LIKE '%' || c.credly_badge_name || '%'
  WHERE c.is_trail = true
);

-- Lídia: 0 real badges
DELETE FROM course_progress
WHERE member_id = (SELECT id FROM members WHERE full_name LIKE '%Lídia%Vale%')
AND completed_at = '2026-03-05 20:36:58.893954+00';

-- Fabricio: only delete CPMAI_INTRO (the other 6 are real)
DELETE FROM course_progress
WHERE member_id = (SELECT id FROM members WHERE full_name LIKE '%Fabricio%Costa%')
AND course_id = (SELECT id FROM courses WHERE code = 'CPMAI_INTRO');

-- Vitor: only delete CPMAI_INTRO
DELETE FROM course_progress
WHERE member_id = (SELECT id FROM members WHERE full_name LIKE '%Vitor%Maia%')
AND course_id = (SELECT id FROM courses WHERE code = 'CPMAI_INTRO');

-- Leticia: delete CPMAI_INTRO if no matching Credly badge
DELETE FROM course_progress
WHERE member_id = (SELECT id FROM members WHERE full_name LIKE '%Leticia%Clemente%')
AND course_id = (SELECT id FROM courses WHERE code = 'CPMAI_INTRO')
AND NOT EXISTS (
  SELECT 1 FROM gamification_points gp
  WHERE gp.member_id = (SELECT id FROM members WHERE full_name LIKE '%Leticia%Clemente%')
  AND gp.reason LIKE 'Credly:%'
  AND gp.reason LIKE '%CPMAI%'
);

-- E.3 Delete orphaned gamification_points from false progress

-- Italo: delete all course-related gamification
DELETE FROM gamification_points
WHERE member_id = (SELECT id FROM members WHERE full_name LIKE '%Italo%Soares%')
AND reason LIKE 'Curso:%';

-- Luciana
DELETE FROM gamification_points
WHERE member_id = (SELECT id FROM members WHERE full_name LIKE '%Luciana%Dutra%')
AND reason LIKE 'Curso:%';

-- Marcelo
DELETE FROM gamification_points
WHERE member_id = (SELECT id FROM members WHERE full_name LIKE '%Marcelo%Ferreira%')
AND reason LIKE 'Curso:%';

-- Rodrigo Grilo
DELETE FROM gamification_points
WHERE member_id = (SELECT id FROM members WHERE full_name LIKE '%Rodrigo%Grilo%')
AND reason LIKE 'Curso:%';

-- Lídia
DELETE FROM gamification_points
WHERE member_id = (SELECT id FROM members WHERE full_name LIKE '%Lídia%Vale%')
AND reason LIKE 'Curso:%';

-- Fabricio: only CPMAI_INTRO and CDBA_INTRO "Curso:" entries
DELETE FROM gamification_points
WHERE member_id = (SELECT id FROM members WHERE full_name LIKE '%Fabricio%Costa%')
AND reason IN ('Curso: CPMAI_INTRO', 'Curso: CDBA_INTRO');

-- Vitor: same
DELETE FROM gamification_points
WHERE member_id = (SELECT id FROM members WHERE full_name LIKE '%Vitor%Maia%')
AND reason IN ('Curso: CPMAI_INTRO', 'Curso: CDBA_INTRO');

-- E.4 Repopulate course_progress from Credly badges (source of truth)
INSERT INTO course_progress (member_id, course_id, status, completed_at, updated_at)
SELECT DISTINCT
  gp.member_id,
  c.id as course_id,
  'completed' as status,
  gp.earned_at as completed_at,
  now() as updated_at
FROM gamification_points gp
JOIN courses c ON gp.reason LIKE '%' || c.credly_badge_name || '%'
WHERE gp.reason LIKE 'Credly:%'
  AND c.is_trail = true
  AND NOT EXISTS (
    SELECT 1 FROM course_progress cp
    WHERE cp.member_id = gp.member_id AND cp.course_id = c.id
  );

-- ═══════════════════════════════════════════════════════════════
-- BLOCO 2: Functions — update BEFORE data migration
-- ═══════════════════════════════════════════════════════════════

-- 2.1 sync_attendance_points — trail-aware with dual-category duplicate check
CREATE OR REPLACE FUNCTION public.sync_attendance_points()
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_att INTEGER := 0; v_crs INTEGER := 0; v_art INTEGER := 0;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM members WHERE auth_id = auth.uid() AND is_superadmin = true) THEN
    RETURN json_build_object('error', 'Acesso negado');
  END IF;

  -- Attendance points (unchanged)
  INSERT INTO gamification_points (member_id, points, reason, category, ref_id)
  SELECT a.member_id, 10, 'Presença: ' || e.title, 'attendance', a.event_id
  FROM attendance a JOIN events e ON e.id = a.event_id
  WHERE a.present = true AND NOT EXISTS (
    SELECT 1 FROM gamification_points gp
    WHERE gp.member_id = a.member_id AND gp.category = 'attendance' AND gp.ref_id = a.event_id
  );
  GET DIAGNOSTICS v_att = ROW_COUNT;

  -- Course completion points — trail-aware
  INSERT INTO gamification_points (member_id, points, reason, category, ref_id)
  SELECT cp.member_id,
    CASE WHEN c.is_trail = true THEN 20 ELSE 15 END,
    'Curso: ' || c.code,
    CASE WHEN c.is_trail = true THEN 'trail' ELSE 'course' END,
    cp.course_id
  FROM course_progress cp JOIN courses c ON c.id = cp.course_id
  WHERE cp.status = 'completed' AND NOT EXISTS (
    -- Check BOTH old and new categories to prevent duplicates during transition
    SELECT 1 FROM gamification_points gp
    WHERE gp.member_id = cp.member_id
    AND gp.ref_id = cp.course_id
    AND gp.category IN ('course', 'trail')
  );
  GET DIAGNOSTICS v_crs = ROW_COUNT;

  -- Artifact points (unchanged)
  INSERT INTO gamification_points (member_id, points, reason, category, ref_id)
  SELECT art.member_id, 30, 'Artefato: ' || art.title, 'artifact', art.id
  FROM artifacts art WHERE art.status = 'published' AND NOT EXISTS (
    SELECT 1 FROM gamification_points gp
    WHERE gp.member_id = art.member_id AND gp.category = 'artifact' AND gp.ref_id = art.id
  );
  GET DIAGNOSTICS v_art = ROW_COUNT;

  RETURN json_build_object('success', true, 'points_created', v_att + v_crs + v_art);
END; $function$;

-- 2.2 get_member_cycle_xp — expanded categories
CREATE OR REPLACE FUNCTION public.get_member_cycle_xp(p_member_id uuid)
 RETURNS json
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
AS $function$
declare
  cycle_start_date date;
  result json;
begin
  select cycle_start into cycle_start_date
  from public.cycles where is_current = true limit 1;

  if cycle_start_date is null then
    cycle_start_date := '2026-01-01';
  end if;

  select json_build_object(
    'lifetime_points', coalesce(sum(points), 0)::int,
    'cycle_points', coalesce(sum(points) filter (where created_at >= cycle_start_date), 0)::int,
    'cycle_attendance', coalesce(sum(points) filter (where category = 'attendance' and created_at >= cycle_start_date), 0)::int,
    -- New expanded fields
    'cycle_learning', coalesce(sum(points) filter (where category in ('trail', 'course', 'knowledge_ai_pm') and created_at >= cycle_start_date), 0)::int,
    'cycle_certs', coalesce(sum(points) filter (where category in ('cert_pmi_senior', 'cert_cpmai', 'cert_pmi_mid', 'cert_pmi_practitioner', 'cert_pmi_entry') and created_at >= cycle_start_date), 0)::int,
    -- Backward compat alias
    'cycle_courses', coalesce(sum(points) filter (where category in ('trail', 'course', 'knowledge_ai_pm') and created_at >= cycle_start_date), 0)::int,
    'cycle_artifacts', coalesce(sum(points) filter (where category = 'artifact' and created_at >= cycle_start_date), 0)::int,
    'cycle_bonus', coalesce(sum(points) filter (where category not in ('attendance','trail','course','knowledge_ai_pm','cert_pmi_senior','cert_cpmai','cert_pmi_mid','cert_pmi_practitioner','cert_pmi_entry','artifact') and created_at >= cycle_start_date), 0)::int,
    'cycle_code', (select cycle_code from public.cycles where is_current = true limit 1),
    'cycle_label', (select cycle_label from public.cycles where is_current = true limit 1)
  ) into result
  from public.gamification_points
  where member_id = p_member_id;

  return coalesce(result, '{}');
end;
$function$;

-- 2.3 Recreate gamification_leaderboard VIEW with expanded categories
-- Preserves ALL existing columns + adds new ones
DROP VIEW IF EXISTS public.gamification_leaderboard;
CREATE VIEW public.gamification_leaderboard AS
WITH current_cycle AS (
  SELECT cycle_start FROM cycles WHERE is_current = true LIMIT 1
)
SELECT
  m.id AS member_id,
  m.name,
  m.chapter,
  m.photo_url,
  m.operational_role,
  m.designations,
  -- Lifetime totals
  COALESCE(SUM(gp.points), 0)::integer AS total_points,
  COALESCE(SUM(gp.points) FILTER (WHERE gp.category = 'attendance'), 0)::integer AS attendance_points,
  -- Learning (trail + course + knowledge_ai_pm)
  COALESCE(SUM(gp.points) FILTER (WHERE gp.category IN ('trail', 'course', 'knowledge_ai_pm')), 0)::integer AS learning_points,
  -- Certifications (all cert_* tiers)
  COALESCE(SUM(gp.points) FILTER (WHERE gp.category IN ('cert_pmi_senior', 'cert_cpmai', 'cert_pmi_mid', 'cert_pmi_practitioner', 'cert_pmi_entry')), 0)::integer AS cert_points,
  -- Badges + Specializations
  COALESCE(SUM(gp.points) FILTER (WHERE gp.category IN ('badge', 'specialization')), 0)::integer AS badge_points,
  -- Artifacts (unchanged)
  COALESCE(SUM(gp.points) FILTER (WHERE gp.category = 'artifact'), 0)::integer AS artifact_points,
  -- Backward compat: course_points = learning_points
  COALESCE(SUM(gp.points) FILTER (WHERE gp.category IN ('trail', 'course', 'knowledge_ai_pm')), 0)::integer AS course_points,
  -- Bonus (anything not in known categories)
  COALESCE(SUM(gp.points) FILTER (WHERE gp.category NOT IN (
    'attendance', 'trail', 'course', 'knowledge_ai_pm',
    'cert_pmi_senior', 'cert_cpmai', 'cert_pmi_mid', 'cert_pmi_practitioner', 'cert_pmi_entry',
    'badge', 'specialization', 'artifact'
  )), 0)::integer AS bonus_points,
  -- Cycle totals
  COALESCE(SUM(gp.points) FILTER (WHERE gp.created_at >= (SELECT cycle_start FROM current_cycle)), 0)::integer AS cycle_points,
  COALESCE(SUM(gp.points) FILTER (WHERE gp.category = 'attendance' AND gp.created_at >= (SELECT cycle_start FROM current_cycle)), 0)::integer AS cycle_attendance_points,
  COALESCE(SUM(gp.points) FILTER (WHERE gp.category IN ('trail', 'course', 'knowledge_ai_pm') AND gp.created_at >= (SELECT cycle_start FROM current_cycle)), 0)::integer AS cycle_course_points,
  COALESCE(SUM(gp.points) FILTER (WHERE gp.category = 'artifact' AND gp.created_at >= (SELECT cycle_start FROM current_cycle)), 0)::integer AS cycle_artifact_points,
  COALESCE(SUM(gp.points) FILTER (WHERE gp.category NOT IN (
    'attendance', 'trail', 'course', 'knowledge_ai_pm',
    'cert_pmi_senior', 'cert_cpmai', 'cert_pmi_mid', 'cert_pmi_practitioner', 'cert_pmi_entry',
    'badge', 'specialization', 'artifact'
  ) AND gp.created_at >= (SELECT cycle_start FROM current_cycle)), 0)::integer AS cycle_bonus_points,
  -- New cycle columns
  COALESCE(SUM(gp.points) FILTER (WHERE gp.category IN ('trail', 'course', 'knowledge_ai_pm') AND gp.created_at >= (SELECT cycle_start FROM current_cycle)), 0)::integer AS cycle_learning_points,
  COALESCE(SUM(gp.points) FILTER (WHERE gp.category IN ('cert_pmi_senior', 'cert_cpmai', 'cert_pmi_mid', 'cert_pmi_practitioner', 'cert_pmi_entry') AND gp.created_at >= (SELECT cycle_start FROM current_cycle)), 0)::integer AS cycle_cert_points,
  COALESCE(SUM(gp.points) FILTER (WHERE gp.category IN ('badge', 'specialization') AND gp.created_at >= (SELECT cycle_start FROM current_cycle)), 0)::integer AS cycle_badge_points
FROM public.members m
LEFT JOIN public.gamification_points gp ON gp.member_id = m.id
WHERE m.current_cycle_active = true
GROUP BY m.id, m.name, m.chapter, m.photo_url, m.operational_role, m.designations;

-- Grant access
GRANT SELECT ON public.gamification_leaderboard TO authenticated, anon;

-- ═══════════════════════════════════════════════════════════════
-- BLOCO 3: Data Migration — reclassify entries
-- ORDER: most-specific first, always filter category='course'
-- ═══════════════════════════════════════════════════════════════

-- 3.1a Trail: course completions from course_progress (6 trail codes)
UPDATE public.gamification_points
SET category = 'trail', points = 20
WHERE category = 'course'
AND (
  reason LIKE '%GENAI_OVERVIEW%'
  OR reason LIKE '%DATA_LANDSCAPE%'
  OR reason LIKE '%PROMPT_ENG%'
  OR reason LIKE '%PRACTICAL_GENAI%'
  OR reason LIKE '%AI_INFRA%'
  OR reason LIKE '%AI_AGILE%'
);

-- 3.1b Trail: Credly badges matching trail course names (6 badges)
UPDATE public.gamification_points
SET category = 'trail', points = 20
WHERE category = 'course'
AND (
  reason LIKE '%Generative AI Overview for Project Managers%'
  OR reason LIKE '%Data Landscape of GenAI for Project Managers%'
  OR reason LIKE '%Talking to AI: Prompt Engineering for Project Managers%'
  OR reason LIKE '%Practical Application of Gen AI for Project Managers%'
  OR reason LIKE '%AI in Infrastructure%Construction%'
  OR reason LIKE '%AI in Agile Delivery%'
);

-- 3.2 cert_pmi_senior (50 XP) — PMP, PMI-RMP, PMI-SP
UPDATE public.gamification_points
SET category = 'cert_pmi_senior', points = 50
WHERE category = 'course'
AND (
  reason LIKE '%Project Management Professional (PMP)%'
  OR reason LIKE '%PMI Risk Management Professional%'
  OR reason LIKE '%PMI-RMP%'
  OR reason LIKE '%PMI Scheduling Professional%'
  OR reason LIKE '%PMI-SP%'
);

-- 3.3 cert_cpmai (45 XP) — CPMAI v7, PMI-CPMAI
UPDATE public.gamification_points
SET category = 'cert_cpmai', points = 45
WHERE category = 'course'
AND (
  reason LIKE '%CPMAI%v7%'
  OR reason LIKE '%PMI-CPMAI%'
  OR reason LIKE '%PMI Certified Professional in Managing AI%'
);

-- 3.4 cert_pmi_mid (40 XP) — PMI-PMOCP
UPDATE public.gamification_points
SET category = 'cert_pmi_mid', points = 40
WHERE category = 'course'
AND (
  reason LIKE '%PMI-PMOCP%'
  OR reason LIKE '%PMI PMO Certified Professional%'
);

-- 3.5 cert_pmi_practitioner (35 XP) — DASSM, PMO-CP
UPDATE public.gamification_points
SET category = 'cert_pmi_practitioner', points = 35
WHERE category = 'course'
AND (
  reason LIKE '%DASSM%'
  OR reason LIKE '%Disciplined Agile Senior Scrum Master%'
  OR reason LIKE '%PMO Certified Practitioner%'
  OR reason LIKE '%PMO-CP%'
);

-- 3.6 cert_pmi_entry (30 XP) — DASM (not DASSM)
UPDATE public.gamification_points
SET category = 'cert_pmi_entry', points = 30
WHERE category = 'course'
AND (reason LIKE '%Disciplined Agile Scrum Master (DASM)%');

-- 3.7 knowledge_ai_pm (20 XP) — AI/PM courses, GenAI, Design Thinking, Agile fundamentals
UPDATE public.gamification_points
SET category = 'knowledge_ai_pm', points = 20
WHERE category = 'course'
AND (
  reason LIKE '%AI-Driven Project Manager%'
  OR reason LIKE '%GenAI for Exec%'
  OR reason LIKE '%Generative AI Essentials%'
  OR reason LIKE '%Generative AI Professional%'
  OR reason LIKE '%Generative AI: Prompt Engineering%'
  OR reason LIKE '%Prompt Engineering Foundation%'
  OR reason LIKE '%Enterprise Design Thinking%'
  OR reason LIKE '%Agile Metrics for Success%'
  OR reason LIKE '%Fundamentals of Agile%'
  OR reason LIKE '%Fundamentals of Predictive%'
  OR reason LIKE '%Fundamentos de Gerenciamento Ágil%'
  OR reason LIKE '%Fundamentos do Gerenciamento de Projetos Predictive%'
  OR reason LIKE '%Generative AI for Data Scientists%'
  OR reason LIKE '%Generative AI for Business Intelligence%'
  OR reason LIKE '%Data Science%'
  OR reason LIKE '%Machine Learning%'
  OR reason LIKE '%Python for Data Science%'
  OR reason LIKE '%Python Project for Data Science%'
  OR reason LIKE '%Databases and SQL%'
  OR reason LIKE '%Tools for Data Science%'
  OR reason LIKE '%IBM Data Science%'
  OR reason LIKE '%IBM Program Manager%'
  OR reason LIKE '%Program Manager Capstone%'
  OR reason LIKE '%Agile Coach%'
  OR reason LIKE '%Design Sprint%'
  OR reason LIKE '%Value Stream Management%'
);

-- 3.8 specialization (25 XP) — AWS, Azure, Microsoft certs, Prosci, PSM, PSPO, FinOps, ATP, Scrum, security
UPDATE public.gamification_points
SET category = 'specialization', points = 25
WHERE category = 'course'
AND (
  reason LIKE '%AWS%'
  OR reason LIKE '%Azure%'
  OR reason LIKE '%Microsoft Certified%'
  OR reason LIKE '%Microsoft 365 Certified%'
  OR reason LIKE '%Microsoft Certified Trainer%'
  OR reason LIKE '%Power BI%'
  OR reason LIKE '%Power Platform%'
  OR reason LIKE '%Professional Scrum Master%'
  OR reason LIKE '%Professional Scrum Product Owner%'
  OR reason LIKE '%PSM%'
  OR reason LIKE '%PSPO%'
  OR reason LIKE '%Prosci%'
  OR reason LIKE '%FinOps%'
  OR reason LIKE '%Authorized Training Partner%'
  OR reason LIKE '%SAFe%'
  OR reason LIKE '%ITIL%'
  OR reason LIKE '%Prince2%'
  OR reason LIKE '%Lean Six Sigma%'
  OR reason LIKE '%Scrum Alliance%'
  OR reason LIKE '%Scrum Foundation%'
  OR reason LIKE '%Remote Work Professional%'
  OR reason LIKE '%Fortinet%'
  OR reason LIKE '%ISC2%'
  OR reason LIKE '%Cybersecurity%'
  OR reason LIKE '%Threat Landscape%'
  OR reason LIKE '%MTA:%'
  OR reason LIKE '%MCSA:%'
  OR reason LIKE '%Exam 3%'
  OR reason LIKE '%Exam 5%'
  OR reason LIKE '%MD-100%'
  OR reason LIKE '%IBM Business Automation%'
);

-- 3.9 badge (10 XP) — anything remaining with "Credly:" prefix that wasn't classified
UPDATE public.gamification_points
SET category = 'badge', points = 10
WHERE category = 'course'
AND reason LIKE 'Credly:%';

-- 3.10 CDBA stays as course (15 XP) — should be untouched, verify by not updating

-- 3.11 Delete Pedro's CPMAI v7 duplicate (keep only PMI-CPMAI)
DELETE FROM public.gamification_points
WHERE category = 'cert_cpmai'
AND reason LIKE '%CPMAI%v7%';

COMMIT;
