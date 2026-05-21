-- p209 / A1.1 — leader_extra_criteria max:5 → max:10 for active cycles
--
-- BUG context (PM-surfaced 2026-05-21, post-PR #225 deploy):
-- ===========================================================
-- Henrique e Francisleila tiveram scores > 5 em leader_extra criteria. UI
-- mostrou "out_of_range" mas o RPC submit_evaluation aceitou silentemente
-- (sem validação de max). Resultado: Francisleila weighted_subtotal=162 com
-- scores 7-8 (válidos sob max:10, inválidos sob max:5 do schema atual).
--
-- Historical archaeology:
-- - Seed migration 20260319100024_w124_seed_cycle3_data.sql definiu TODOS os
--   criteria (objective + interview + leader_extra) com max:5.
-- - Migration 20260401090000_evaluation_rubrics_advisory_panel.sql atualizou
--   objective_criteria para max:10 (com guides anchored).
-- - leader_extra_criteria foi ESQUECIDO nessa atualização → ficou órfão em max:5
--   por ~7 semanas (de 2026-04-01 até 2026-05-21).
-- - Cycle4-2026 leader_extra weights × max=5 = 110 ponderado max declarado;
--   evaluators usaram max=10 escala → 220 ponderado max real (Fabricio's submit).
--
-- Fix: bump max:5 → max:10 em leader_extra_criteria de todos os ciclos ATIVOS
-- (status IN open/evaluation/interview/decision). Idempotente via jsonb_set.
-- Não toca closed cycles (cycle3-2026 fechado preserva histórico).
--
-- Impact on existing submissions:
-- - Cycle4-2026: 2 leader_extra evals existem. Vitor avaliou William scores 1-4
--   (válidos em ambas escalas, weighted=60). Fabricio avaliou Francisleila scores
--   5-8 (válidos sob max:10 novo schema, weighted=162). Ambos preservados.
-- - Cycle3-2026-b2: zero leader_extra evals submetidas até agora.
--
-- PM decision (2026-05-21 A/B/C/D Option A): preserve existing submissions
-- (Option A); align leader_extra max with objective_criteria max:10.
--
-- Pairs with migration 20260802000003 (RPC submit_evaluation max validation gate).
--
-- Rollback (if any field reports scores being downgraded):
--   UPDATE selection_cycles
--   SET leader_extra_criteria = (
--     SELECT jsonb_agg(jsonb_set(c, '{max}', '5'::jsonb))
--     FROM jsonb_array_elements(leader_extra_criteria) c
--   )
--   WHERE status IN ('open','evaluation','interview','decision');
--   -- Note: rollback restores BROKEN pre-fix state (max:5 with UI/RPC misalignment).
--   -- Only use if a downstream regression appears; prefer fix-forward.

UPDATE public.selection_cycles
SET leader_extra_criteria = (
  SELECT jsonb_agg(jsonb_set(criterion, '{max}', '10'::jsonb))
  FROM jsonb_array_elements(leader_extra_criteria) criterion
),
updated_at = now()
WHERE status IN ('open', 'evaluation', 'interview', 'decision')
  AND leader_extra_criteria IS NOT NULL
  AND jsonb_array_length(leader_extra_criteria) > 0;

-- Register version (apply via MCP execute_sql; supabase db push would auto-register).
INSERT INTO supabase_migrations.schema_migrations (version, name)
VALUES ('20260802000002', 'p209_a1_1_leader_extra_max_5_to_10')
ON CONFLICT (version) DO NOTHING;
