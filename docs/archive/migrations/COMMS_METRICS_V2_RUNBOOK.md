# COMMS_METRICS_V2 Runbook

## Objetivo
Automatizar a ingestão de métricas de comunicação para `comms_metrics_daily` com rastreabilidade operacional.

## Artefatos
- `supabase/functions/sync-comms-metrics/index.ts`
- `supabase/migrations/20260308003330_comms_metrics_v2_ingestion.sql`
- `docs/migrations/comms-metrics-v2-ingestion-audit.sql`
- `docs/migrations/comms-metrics-v2-ingestion-rollback.sql`

## Ordem de execução
1. Deploy da edge function:
   - `supabase functions deploy sync-comms-metrics`
2. Configurar secrets da function:
   - `SYNC_COMMS_METRICS_SECRET`
   - `COMMS_METRICS_SOURCE_URL`
   - `COMMS_METRICS_SOURCE_TOKEN` (opcional)
3. Aplicar migration V2 no banco:
   - `supabase db push`
4. Rodar sync manual de smoke:
   - `curl -X POST "${SUPABASE_URL}/functions/v1/sync-comms-metrics" -H "Authorization: Bearer ${SYNC_COMMS_METRICS_SECRET}" -H "Content-Type: application/json" -d '{"dry_run": true, "triggered_by":"manual_smoke"}'`
5. Rodar auditoria SQL:
   - `docs/migrations/comms-metrics-v2-ingestion-audit.sql`

## DoD
- ingestão diária funcionando via edge function
- tabela `comms_metrics_ingestion_log` com status por execução
- `/admin/analytics` pode consumir `comms_metrics_latest_by_channel(...)` em próxima etapa UI
- rollback disponível e testado em ambiente não-produtivo
