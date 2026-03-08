# Deploy Checklist — O que falta para produção

Checklist único para concluir a configuração e deploy dos itens pendentes.

**Issues no board:** #56 (HF5), #57 (sync-comms), #58 (Credly secrets)

---

## 1. HF5 — Data Patch (ação manual em produção) — [#56](https://github.com/VitorMRodovalho/ai-pm-hub-v2/issues/56)

**Artefatos**: `docs/migrations/hf5-apply-data-patch.sql`, `docs/migrations/HF5_PRODUCTION_RUNBOOK.md`

### Passos
- [ ] Abrir Supabase SQL Editor (projeto de produção)
- [ ] Executar `docs/migrations/hf5-audit-data-patch.sql` (pré-auditoria)
- [ ] Executar `docs/migrations/hf5-apply-data-patch.sql`
- [ ] Executar novamente `hf5-audit-data-patch.sql` (pós-auditoria)
- [ ] Registrar em `docs/RELEASE_LOG.md`

---

## 2. sync-comms-metrics — Edge Function — [#57](https://github.com/VitorMRodovalho/ai-pm-hub-v2/issues/57)

**Runbook**: `docs/migrations/COMMS_METRICS_V2_RUNBOOK.md`

### 2.1 Deploy da função
```bash
supabase functions deploy sync-comms-metrics
```

### 2.2 Secrets no Supabase (Dashboard → Project Settings → Edge Functions)
- [ ] `SYNC_COMMS_METRICS_SECRET` — token para autenticar chamadas (gerar UUID ou string forte)
- [ ] `COMMS_METRICS_SOURCE_URL` — (opcional) URL que retorna JSON de métricas
- [ ] `COMMS_METRICS_SOURCE_TOKEN` — (opcional) Bearer para a URL acima

### 2.3 Migrations no banco
```bash
supabase db push
```
Ou aplicar manualmente: `20260308002252`, `20260308002810`, `20260308003330`

### 2.4 Smoke test
```bash
# Ou usar o script:
SUPABASE_URL=... SYNC_COMMS_METRICS_SECRET=... ./scripts/smoke-sync-comms.sh

# Ou curl direto:
curl -X POST "${SUPABASE_URL}/functions/v1/sync-comms-metrics" \
  -H "Authorization: Bearer ${SYNC_COMMS_METRICS_SECRET}" \
  -H "Content-Type: application/json" \
  -d '{"dry_run": true, "triggered_by":"manual_smoke", "rows":[]}'
```

### 2.5 GitHub Actions (opcional)
Se usar o workflow `.github/workflows/comms-metrics-sync.yml`, configurar secrets:
- [ ] `SUPABASE_URL`
- [ ] `SYNC_COMMS_METRICS_SECRET`
- [ ] `COMMS_METRICS_SOURCE_URL` (se ingestão via URL externa)

---

## 3. Credly Auto Sync (S10) — [#58](https://github.com/VitorMRodovalho/ai-pm-hub-v2/issues/58)

**Workflow**: `.github/workflows/credly-auto-sync.yml`

### Secrets no GitHub (Settings → Secrets and variables → Actions)
- [ ] `SUPABASE_URL` — URL do projeto Supabase
- [ ] `SUPABASE_SERVICE_ROLE_KEY` — chave service role (permite invocar Edge Functions)

O workflow roda toda segunda às 08:00 UTC e pode ser disparado manualmente.

---

## 4. Variáveis de ambiente (frontend)

### Cloudflare Pages (ou ambiente de build)
Em Cloudflare Pages → Settings → Environment variables:

| Variável | Obrigatório | Descrição |
|----------|-------------|-----------|
| `PUBLIC_SUPABASE_URL` | Sim | URL do Supabase |
| `PUBLIC_SUPABASE_ANON_KEY` | Sim | Chave anônima |
| `PUBLIC_POSTHOG_PRODUCT_DASHBOARD_URL` | Não | URL do dashboard PostHog (embed em `/admin/analytics`) |
| `PUBLIC_LOOKER_COMMS_DASHBOARD_URL` | Não | URL do dashboard Looker (embed em `/admin/analytics` e `/admin/comms`) |

Sem as URLs de dashboard, as rotas mostram placeholder ou tabela nativa.

---

## 5. Knowledge Insights (se em uso)

**Workflow**: `.github/workflows/knowledge-insights-auto-sync.yml`

### Secrets
- [ ] `SUPABASE_URL`
- [ ] `SUPABASE_ANON_KEY`
- [ ] `SYNC_KNOWLEDGE_INSIGHTS_SECRET`
- [ ] `SUPABASE_SERVICE_ROLE_KEY` (ou anon)
- [ ] `KNOWLEDGE_INSIGHTS_FUNCTION_NAME` (opcional, default: `sync-knowledge-insights`)

---

## Resumo de prioridade

| # | Item | Bloqueia? |
|---|------|-----------|
| 1 | HF5 data patch | Dados inconsistentes (Sarah, Roberto, deputy hierarchy) |
| 2 | SUPABASE_* no build | App não inicia |
| 3 | sync-comms-metrics deploy + secret | `/admin/comms` tabela vazia até primeira ingestão |
| 4 | Credly workflow secrets | S10 não executa |
| 5 | Looker/PostHog URLs | Dashboards em branco (placeholders ok) |
