# KNOWLEDGE_INSIGHTS_SYNC_RUNBOOK

## Objetivo
Operar ingestão automática de fricções/insights em `knowledge_insights` usando heurísticas sem LLM em tempo real (baixo custo).

## Arquivos
- `supabase/functions/sync-knowledge-insights/index.ts`
- `.github/workflows/knowledge-insights-auto-sync.yml`

## Deploy
1. Deploy da função:
   - `supabase functions deploy sync-knowledge-insights --no-verify-jwt`
2. Configurar secret da função:
   - `supabase secrets set SYNC_KNOWLEDGE_INSIGHTS_SECRET=<valor-forte>`
3. Configurar secret no GitHub repo:
   - `SYNC_KNOWLEDGE_INSIGHTS_SECRET`

## Smoke test (produção)
```bash
curl -sS -X POST "$SUPABASE_URL/functions/v1/sync-knowledge-insights" \
  -H "Content-Type: application/json" \
  -H "apikey: $SUPABASE_ANON_KEY" \
  -H "Authorization: Bearer $SUPABASE_ANON_KEY" \
  -H "x-sync-secret: $SYNC_KNOWLEDGE_INSIGHTS_SECRET" \
  --data '{"dry_run":true,"triggered_by":"manual_smoke","days":45,"limit":120,"source":"youtube"}'
```

## Query de auditoria rápida
```sql
select source, insight_type, taxonomy_area, status, count(*) as qty
from public.knowledge_insights
group by source, insight_type, taxonomy_area, status
order by qty desc;

select run_key, status, rows_received, rows_upserted, rows_chunked, created_at
from public.knowledge_ingestion_runs
where source = 'insights'
order by created_at desc
limit 20;
```

## Guardrails
- Função é secret-gated (`SYNC_KNOWLEDGE_INSIGHTS_SECRET`).
- `dry_run` suportado.
- Deduplicação por `chunk_id + insight_type + taxonomy_area + title`.
- Regra versionada em `metadata.rule_version`.
