-- p158 hotfix #3: add 'proposed_theme_quality' criterion to leader_extra_criteria for active cycles
--
-- PM directive (live test 2026-05-14): "avaliacao do tema proposto para lider de pesquisa nao vi
-- no frontend para eu avaliar". Currently leader_extra_criteria has 5 standard criteria
-- (research_and_gp_exp, leadership, technical_knowledge, pmi_involvement, language) — none
-- captures the QUALITY OF THE PROPOSED THEME that leader candidates submit as a key
-- differentiator (proposed_theme + leadership_experience essay fields). PM noted this gap
-- specifically because for William the theme assessment is what tilts researcher vs leader
-- decision (his theme is described but PM judged him "imaturo ainda para ser lider de tema").
--
-- This migration appends one criterion to leader_extra_criteria of all currently-active
-- cycles (status IN open/evaluation/interview/decision). Idempotent via NOT EXISTS guard.
--
-- New criterion:
--   key:    proposed_theme_quality
--   label:  Qualidade do Tema Proposto
--   max:    5
--   weight: 4   (medium-high — comparable to 'leadership' which is weight=4)
--
-- Impact on existing evaluations:
--   - Past leader_extra submissions (e.g. William's: 5 criteria scored, weighted_subtotal=45)
--     will now show 1 missing score when re-opened. Evaluator can re-submit including the new
--     6th score; weighted_subtotal recomputes. UI form iterates cycle config so the new
--     criterion appears automatically.
--   - Approved leaders (e.g. Herlon) NOT retro-scored per PM directive — only forward path.
--   - The criterion is leader-only (lives in leader_extra_criteria, evaluated when role_applied
--     includes 'leader' or via dual_track leader app).

UPDATE public.selection_cycles
SET    leader_extra_criteria = leader_extra_criteria || jsonb_build_array(
         jsonb_build_object(
           'key',    'proposed_theme_quality',
           'label',  'Qualidade do Tema Proposto',
           'max',    5,
           'weight', 4
         )
       ),
       updated_at = now()
WHERE  status IN ('open','evaluation','interview','decision')
  AND  NOT EXISTS (
    SELECT 1
    FROM   jsonb_array_elements(leader_extra_criteria) c
    WHERE  c->>'key' = 'proposed_theme_quality'
  );

NOTIFY pgrst, 'reload schema';
