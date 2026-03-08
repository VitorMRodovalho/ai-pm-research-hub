# COMMS_METRICS_V1 Runbook

## Objetivo
Transformar o `/admin/comms` em fluxo DB-backed com métricas nativas no Supabase.

## Artefatos
- `docs/migrations/comms-metrics-v1.sql`
- `docs/migrations/comms-metrics-v1-audit.sql`
- `docs/migrations/comms-metrics-v1-rollback.sql`

## Ordem de execução
1. Aplicar migration: `comms-metrics-v1.sql`
2. Rodar auditoria: `comms-metrics-v1-audit.sql`
3. Inserir 1-2 linhas de teste em `comms_metrics_daily` (canal + data)
4. Validar retorno de `select * from public.comms_metrics_latest();`
5. Validar `/admin/comms` sem `PUBLIC_COMMS_KPI_API_URL` (fallback RPC)

## DoD
- tabela `comms_metrics_daily` criada com RLS habilitado
- policies admin+ ativas
- função `comms_metrics_latest()` executável por `authenticated`
- `/admin/comms` exibindo KPIs via RPC quando endpoint externo não configurado

## Rollback
- executar `comms-metrics-v1-rollback.sql`
