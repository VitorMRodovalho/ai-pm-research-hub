# Deploy Checklist — O que falta para produção

Checklist único para concluir a configuração e deploy dos itens pendentes.

**Validação QA/QC**: Após deploy, executar `docs/QA_RELEASE_VALIDATION.md` (console + cross-browser).

**Issues no board:** #56 (HF5), #57 (sync-comms), #58 (Credly secrets)

---

## 0. Code scanning (CodeQL) — habilitar no GitHub [#59](https://github.com/VitorMRodovalho/ai-pm-research-hub/issues/59)

O workflow `codeql-analysis.yml` roda em todo push/PR. Enquanto Code scanning não estiver habilitado, os resultados não são exibidos na aba Security, mas a análise executa.

**Para habilitar alertas na aba Security:**
1. GitHub → Repo → **Settings** → **Security** → **Code security and analysis**
2. Em **Code scanning**, clicar em **Set up** ou **Enable**
3. Escolher **Advanced** e associar ao workflow existente
4. Depois, em `.github/workflows/codeql-analysis.yml`, remover `upload: false` do step `Perform CodeQL Analysis`

---

## 1. HF5 — Data Patch (ação manual em produção) — [#56](https://github.com/VitorMRodovalho/ai-pm-research-hub/issues/56)

**Artefatos**: `docs/migrations/hf5-apply-data-patch.sql`, `docs/migrations/HF5_PRODUCTION_RUNBOOK.md`

### Passos
- [ ] Abrir Supabase SQL Editor (projeto de produção)
- [ ] Executar `docs/migrations/hf5-audit-data-patch.sql` (pré-auditoria)
- [ ] Executar `docs/migrations/hf5-apply-data-patch.sql`
- [ ] Executar novamente `hf5-audit-data-patch.sql` (pós-auditoria)
- [ ] Registrar em `docs/RELEASE_LOG.md`

---

## 2. sync-comms-metrics — Edge Function — [#57](https://github.com/VitorMRodovalho/ai-pm-research-hub/issues/57)

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

## 3. Credly Auto Sync (S10) — [#58](https://github.com/VitorMRodovalho/ai-pm-research-hub/issues/58)

**Workflow**: `.github/workflows/credly-auto-sync.yml`

### Secrets no GitHub (Settings → Secrets and variables → Actions)
- [ ] `SUPABASE_URL` — URL do projeto Supabase
- [ ] `SUPABASE_SERVICE_ROLE_KEY` — chave service role (permite invocar Edge Functions)

O workflow roda toda segunda às 08:00 UTC e pode ser disparado manualmente.

---

## 4. Variáveis de ambiente (frontend)

### Cloudflare Workers (via GitHub Actions + Wrangler)
Env vars are set in `.github/workflows/deploy.yml` build step:

| Variável | Obrigatório | Descrição |
|----------|-------------|-----------|
| `PUBLIC_SUPABASE_URL` | Sim | URL do Supabase |
| `PUBLIC_SUPABASE_ANON_KEY` | Sim | Chave anônima |
| `PUBLIC_POSTHOG_PRODUCT_DASHBOARD_URL` | ~~Não~~ Superseded | ~~URL do dashboard PostHog~~ — Substituído por Chart.js nativo (S-AN1, Wave 4-8) |
| `PUBLIC_LOOKER_COMMS_DASHBOARD_URL` | ~~Não~~ Superseded | ~~URL do dashboard Looker~~ — Substituído por Chart.js nativo (S-AN1, Wave 4-8) |

**Nota (Wave 8):** Dashboards PostHog e Looker foram completamente substituídos por gráficos nativos Chart.js. As variáveis acima não são mais necessárias.

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

## 6. Workflows GitHub Actions — visão geral

| Workflow | Gatilho | Status esperado |
|----------|---------|-----------------|
| **CI Validate** | push/PR em `main` e `dev` | ✅ `quality_gate` aprovado (validate + browser_guards) |
| **Issue Reference Gate** | push/PR em `main` e `dev` | ✅ exige issue link em trilha crítica |
| **CodeQL Analysis** | push/PR em main | ✅ Passa (upload: false até Code scanning habilitado) |
| **Project Governance Sync** | diário 09:15 UTC, push em gov paths | ✅ Passa (usa GITHUB_TOKEN) |
| **Knowledge Insights** | seg/qui 10:30 UTC | ✅ Passa (skip quando secrets ausentes) |
| **Credly Auto Sync** | seg 08:00 UTC | ✅ Passa (skip até #58) |
| **Comms Metrics Sync** | diário 07:30 UTC | ✅ Passa (skip até #57) |
| **Dependabot Updates** | PRs do Dependabot | Padrão GitHub ao abrir PR de deps |

**Nenhum workflow é legado/Codex** — todos têm propósito atual. Dependabot não é nosso workflow, é o fluxo padrão do GitHub.

---

## 7. Supabase Storage — bucket `board-attachments`

O upload de anexos em cards do BoardEngine requer o bucket `board-attachments` no Supabase Storage.

### Passos
- [ ] Abrir Supabase Dashboard → Storage
- [ ] Criar bucket **`board-attachments`** (público ou com RLS conforme necessidade)
- [ ] Verificar políticas de acesso:
  - `INSERT`: membros autenticados (RLS via `auth.uid()`)
  - `SELECT`: membros autenticados ou público (conforme política de compartilhamento)
  - `DELETE`: apenas owner do card ou admin
- [ ] Limite de upload configurado no frontend: **5 MB**, extensões: `pdf, png, jpg, jpeg, docx, xlsx, pptx`

**Sem este bucket, uploads de anexos em cards falharão silenciosamente.**

---

## 8. PostHog Analytics (opcional)

Para habilitar analytics PostHog, configurar nas env vars do deploy:

| Variável | Obrigatório | Descrição |
|----------|-------------|-----------|
| `PUBLIC_POSTHOG_KEY` | Sim (se usar PostHog) | API key do projeto PostHog |
| `PUBLIC_POSTHOG_HOST` | Sim (se usar PostHog) | Ex: `https://us.i.posthog.com` |

**Sem estas variáveis, PostHog é desabilitado automaticamente (sem erros no console).**

---

## Resumo de prioridade

| # | Item | Bloqueia? |
|---|------|-----------|
| 1 | HF5 data patch | Dados inconsistentes (Sarah, Roberto, deputy hierarchy) |
| 2 | SUPABASE_* no build | App não inicia |
| 3 | sync-comms-metrics deploy + secret | `/admin/comms` tabela vazia até primeira ingestão |
| 4 | Credly workflow secrets | S10 não executa |
| 5 | Bucket `board-attachments` | Uploads de anexos em cards falham |
| 6 | PostHog env vars | Analytics desabilitado (sem erros, funcional sem) |
