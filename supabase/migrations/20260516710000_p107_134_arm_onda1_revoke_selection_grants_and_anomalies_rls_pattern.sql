-- ARM Onda 1 #134: defesa em profundidade para tabelas do funil de seleção
--
-- Auditoria p107 (docs/strategy/ARM_PILLARS_AUDIT_P107.md §R3) confirmou:
--   - RLS habilitado em todas tabelas selection_* + onboarding_progress + ai_analysis_runs
--   - Pattern rpc_only_deny_all (PERMISSIVE qual=false) presente em 8/9
--   - selection_evaluation_anomalies tem RLS habilitado mas policies=0 — default deny
--     funciona, mas falta o pattern explícito
--   - Grants DML (INSERT/UPDATE/DELETE/REFERENCES/TRIGGER/TRUNCATE) over-permissive
--     em anon e authenticated em todas 9 tabelas. Neutralizados pela RLS, mas defesa
--     em profundidade requer REVOKE (RPC pode ser comprometido futuramente).
--   - SELECT grant para anon em ai_analysis_runs e selection_evaluation_anomalies
--     (RLS retorna 0 rows mesmo assim, mas REVOKE explícito é cleaner)
--
-- Não há leak ativo confirmado (smoke: anon SELECT em selection_applications
-- retornou 42501 permission denied). Esta migration é hardening preventivo.
--
-- Rollback:
--   GRANT INSERT, UPDATE, DELETE, REFERENCES, TRIGGER, TRUNCATE ON ALL TABLES
--     IN SCHEMA public TO anon, authenticated;
--   GRANT SELECT ON public.ai_analysis_runs TO anon;
--   GRANT SELECT ON public.selection_evaluation_anomalies TO anon;
--   DROP POLICY rpc_only_deny_all ON public.selection_evaluation_anomalies;

-- 1) Adicionar pattern rpc_only_deny_all em selection_evaluation_anomalies
DROP POLICY IF EXISTS rpc_only_deny_all ON public.selection_evaluation_anomalies;
CREATE POLICY rpc_only_deny_all
  ON public.selection_evaluation_anomalies
  AS PERMISSIVE FOR ALL TO public
  USING (false);

-- 2) REVOKE DML grants over-permissive em anon e authenticated
DO $func$
DECLARE
  v_tables text[] := ARRAY[
    'selection_applications','selection_evaluations','selection_interviews',
    'selection_committee','selection_cycles','selection_evaluation_anomalies',
    'selection_diversity_snapshots','onboarding_progress','ai_analysis_runs'
  ];
  v_table text;
BEGIN
  FOREACH v_table IN ARRAY v_tables LOOP
    EXECUTE format('REVOKE INSERT, UPDATE, DELETE, REFERENCES, TRIGGER, TRUNCATE ON public.%I FROM anon', v_table);
    EXECUTE format('REVOKE INSERT, UPDATE, DELETE, REFERENCES, TRIGGER, TRUNCATE ON public.%I FROM authenticated', v_table);
  END LOOP;
END
$func$;

-- 3) REVOKE SELECT de anon nas tabelas onde foi over-granted
REVOKE SELECT ON public.ai_analysis_runs FROM anon;
REVOKE SELECT ON public.selection_evaluation_anomalies FROM anon;

-- 4) Document RPC-only pattern em tabelas-chave
COMMENT ON TABLE public.selection_applications IS
  'Candidate applications per selection cycle. RLS pattern: RPC-only access via SECURITY DEFINER functions. Direct DML/SELECT denied for all roles via rpc_only_deny_all (PERMISSIVE qual=false) + selection_applications_v4_org_scope (RESTRICTIVE). Access pattern: get_my_application_status / update_my_application (candidato), get_application_detail / get_selection_dashboard / submit_evaluation (avaliador, comitê), admin_* (admin). See docs/strategy/ARM_PILLARS_AUDIT_P107.md §R3.';

COMMENT ON TABLE public.selection_evaluation_anomalies IS
  'Evaluation anomaly alerts (>2σ from average). RLS pattern: RPC-only access via SECURITY DEFINER. Direct access denied via rpc_only_deny_all (PERMISSIVE qual=false). Added p107 ARM Onda 1 #134 — hardening defesa em profundidade.';

NOTIFY pgrst, 'reload schema';
