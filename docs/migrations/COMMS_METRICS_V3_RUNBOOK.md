# COMMS_METRICS_V3 Runbook

## Objetivo
Adicionar fluxo de publicação e auditoria para lotes manuais (`manual_admin` / `manual_csv`).

## Artefatos
- `supabase/migrations/20260308012510_comms_metrics_v3_publish_workflow.sql`
- `docs/migrations/comms-metrics-v3-publish-workflow.sql`
- `docs/migrations/comms-metrics-v3-publish-workflow-audit.sql`
- `docs/migrations/comms-metrics-v3-publish-workflow-rollback.sql`

## Fluxo
1. `supabase db push`
2. Inserir/ajustar métricas em `/admin/comms/data-entry`
3. Publicar lote via botão `Publicar Lote` (RPC `publish_comms_metrics_batch`)
4. Validar logs em `comms_metrics_publish_log`
5. Rodar auditoria SQL V3

## DoD
- lotes pendentes aparecem no painel
- publicação escreve `published_at`, `published_by`, `publish_batch_id`
- log registrado em `comms_metrics_publish_log`
- RPC restrita a `authenticated` com verificação `can_manage_comms_metrics()`
