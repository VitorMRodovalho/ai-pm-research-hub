# EXEC_ROI_DASHBOARDS_V1_RUNBOOK

## Arquivos
- `supabase/migrations/20260308102010_exec_roi_dashboards_v1.sql`
- `docs/migrations/exec-roi-dashboards-v1-audit.sql`
- `docs/migrations/exec-roi-dashboards-v1-rollback.sql`

## Ordem de execução (produção)
1. Aplicar migration:
   - `supabase db push --linked`
2. Rodar auditoria:
   - `docs/migrations/exec-roi-dashboards-v1-audit.sql`
3. Smoke funcional:
   - validar RPCs retornando dados com usuário `admin+`

## Critérios de aceite
- Views executivas presentes:
  - `vw_exec_funnel`
  - `vw_exec_cert_timeline`
  - `vw_exec_skills_radar`
- RPCs executivas presentes com grant para `authenticated`:
  - `exec_funnel_summary()`
  - `exec_cert_timeline(p_months)`
  - `exec_skills_radar()`
- Gate de acesso ativo: `has_min_tier(4)`.

## Rollback
- Executar `docs/migrations/exec-roi-dashboards-v1-rollback.sql`.
