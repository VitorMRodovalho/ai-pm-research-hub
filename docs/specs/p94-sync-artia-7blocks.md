# Spec p94 — Expansão `sync-artia` para 7 blocos da auditoria PMO

**Data**: 2026-05-05
**Trigger**: Auditoria de Governança PMO PMI-GO 2026 (Núcleo IA = 17% conformidade · 14 não-conformidades)
**Status**: 🔄 Spec inicial — aguardando discovery Artia + decisão PM
**Origem session**: p94 (handoff `memory/handoff_p94_artia_sync_audit.md`)

---

## 1. Objetivo

Expandir a EF `sync-artia` para enviar evidência institucional cobrindo **todos os 7 blocos** avaliados pelo PMO (não apenas KPIs de Monitoramento), permitindo que a próxima auditoria refleta a realidade operacional do programa Núcleo IA.

## 2. Estado atual (baseline)

### 2.1 Infraestrutura
- **EF**: `supabase/functions/sync-artia/index.ts` (218 linhas, Deno)
- **Cron**: `sync-artia-weekly` schedule `30 5 * * 0` (Domingo 05:30 UTC = 02:30 BRT)
- **Últimos 4 runs** (validados em p94 discovery): TODOS sucesso, 12-62ms duração
- **Tabela de log**: `mcp_usage_log.tool_name = 'sync-artia'`

### 2.2 Constantes Artia
| Variável | Valor | Significado |
|---|---|---|
| `ARTIA_GQL` | `https://api.artia.com/graphql` | Endpoint GraphQL |
| `ARTIA_ACCOUNT_ID` | `6345833` | Conta PMI-GO (account-level, compartilhada com 30 outros projetos) |
| `ARTIA_PROJECT_ID` | `6391775` | Projeto "Núcleo IA & GP" (project-level) |
| `ARTIA_KPI_FOLDER` | `6399649` | Folder 04 — Monitoramento (KPIs) |
| `ARTIA_RESPONSIBLE_ID` | `298786` | "GP Projeto Núcleo IA" (responsible by default) |
| `ARTIA_STATUS` | `A_INICIAR=317052` / `ANDAMENTO=328049` / `ENCERRADO=317054` | Custom status IDs PMI-GO |

### 2.3 Escopo atual (1 bloco de 7)
- ✅ **Monitoramento (KPIs)**: 9 activity IDs hardcoded em `KPI_ACTIVITY_MAP`:
  - `chapters_participating: 32528756` — KPI 8 Capítulos
  - `entities_partners: 32528757` — KPI 3 Entidades Parceiras
  - `trail_completion: 32528758` — KPI 70% Trilha
  - `cpmai_certified: 32528759` — KPI CPMAI
  - `articles_published: 32528760` — KPI Artigos
  - `webinars_realized: 32528762` — KPI Webinares
  - `pilots_ia_copilot: 32528763` — KPI Pilotos
  - `hours_meetings: 32528764` — KPI 90h Encontros
  - `hours_impact: 32528765` — KPI 1.800h Impacto
- ❌ **TAP** (0%) — não há sync
- ❌ **Templates** (0%) — não há sync
- ❌ **Kick-off** (0%) — não há sync
- ❌ **Uso do Artia** (0%) — só o sync de KPI conta como "uso", não cobre TAP/Plano/Riscos/Custos
- ❌ **Lições Aprendidas** (N/A neste ciclo, mas precisa de placeholder para Dez/2026)
- ✅ **Cadastros** (100%) — feito manualmente fora da EF (PMI-GO mantém em Artia)

### 2.4 Direção
**1-way push** (plataforma → Artia). Não há leitura/sync reverso de Artia → plataforma.

### 2.5 Schema platform — gap de rastreabilidade
**Não existe nenhuma coluna `artia_*` em nenhuma tabela platform.** Não conseguimos rastrear "qual TAP/kick-off/risco da plataforma corresponde a qual activity Artia". Este é um gap fundamental que precisa migration.

---

## 3. Mapeamento dos 7 blocos da auditoria → estrutura Artia esperada

### 3.1 Pre-condição: Discovery da estrutura Artia de outros projetos PMI-GO

**Necessário antes de implementar** — para descobrir como projetos com score alto (Pacto pela Inovação 100% Templates · PMO 74% · PM Lab 64%) estruturam suas folders e activities. Veja seção 5 (Discovery).

### 3.2 Mapeamento por bloco (hipótese a validar com discovery)

| # | Bloco PMO | Critério auditoria | Origem na plataforma | Destino Artia (hipótese) |
|--:|---|---|---|---|
| 1 | TAP | TAP no Drive · aprovado pela Diretoria · template PMI · aprovação documentada | `docs/TAP_CICLO3_2026.md` → Google Doc no Drive institucional | Activity em **Folder 01 (Iniciação)** com link para Drive Doc · status=ENCERRADO quando assinado |
| 2 | Cadastros | Drive · email · membros Artia · aceite convites | (já 100% — manual) | (n/a) |
| 3 | Templates | Templates institucionais utilizados | TAP + Manual Governança + Política IP + Acordos Cooperação | Activity(ies) em **Folder 01** referenciando templates · status=ENCERRADO |
| 4 | Kick-off | Reunião kick-off realizada (com evidência) | `events` table com `type='kick_off'` OR `meeting_notes` table OR pasta Drive `2026-03-05 17:15 [...] Kick-off` | Activity em **Folder 01** com link para Drive folder · status=ENCERRADO |
| 5 | Uso do Artia | TAP repassado · Planejamento · Riscos · Custos | (a) TAP via #1 acima · (b) `initiatives` table como WBS · (c) `decision_log` + ADRs WARN como riscos · (d) custos = R$ 0,00 declarado | Activities distribuídas em **Folder 02 (Planejamento)** · **Folder 06 (Riscos)** · **Folder 07 (Custos)** |
| 6 | Monitoramento | Atividades atualizadas (≤10d) · Status report formal · Ritos · Critérios sucesso | (a) `board_items.updated_at` ≥ now()-10d · (b) status report mensal gerado a partir de `weekly_member_digest` + `cycle_evolution` · (c) `events` realizados último mês como ritos · (d) 9 KPIs atuais | (a) sync de boards como activities em **Folder 02** com last-touch ≤10d · (b) status_report mensal como activity em **Folder 04** · (c) atas como activities em **Folder 05 (Atas)** · (d) já feito |
| 7 | Lições Aprendidas | Lições documentadas | (encerramento Dez/2026) — futura `cycle_lessons_learned` table OR `meeting_notes` com tag | Activity em **Folder 08 (Encerramento)** ao final do Ciclo 3 |

### 3.3 Folders Artia esperadas (hipótese — confirmar via discovery)

```
Núcleo IA & GP (PROJECT_ID 6391775)
├── Folder 01 — Iniciação
│   ├── TAP
│   ├── Templates
│   └── Kick-off
├── Folder 02 — Planejamento
│   ├── Plano (WBS por tribo)
│   └── Atualizações de atividades (≤10d)
├── Folder 03 — Execução [se existir]
├── Folder 04 — Monitoramento ⭐ (já populado com 9 KPIs)
├── Folder 05 — Atas / Ritos [se existir]
├── Folder 06 — Riscos [se existir]
├── Folder 07 — Custos [se existir]
└── Folder 08 — Encerramento [futuro]
```

---

## 4. Schema platform — migrations propostas

### 4.1 Adicionar colunas `artia_*_id` para rastreabilidade bidirecional

```sql
-- Migration: 20260516530000_artia_traceability_columns.sql

ALTER TABLE governance_documents
  ADD COLUMN IF NOT EXISTS artia_activity_id BIGINT,
  ADD COLUMN IF NOT EXISTS artia_synced_at TIMESTAMPTZ;

ALTER TABLE initiatives
  ADD COLUMN IF NOT EXISTS artia_activity_id BIGINT,
  ADD COLUMN IF NOT EXISTS artia_folder_id BIGINT,
  ADD COLUMN IF NOT EXISTS artia_synced_at TIMESTAMPTZ;

ALTER TABLE events
  ADD COLUMN IF NOT EXISTS artia_activity_id BIGINT,
  ADD COLUMN IF NOT EXISTS artia_synced_at TIMESTAMPTZ;

ALTER TABLE board_items
  ADD COLUMN IF NOT EXISTS artia_activity_id BIGINT,
  ADD COLUMN IF NOT EXISTS artia_synced_at TIMESTAMPTZ;

ALTER TABLE meeting_notes
  ADD COLUMN IF NOT EXISTS artia_activity_id BIGINT,
  ADD COLUMN IF NOT EXISTS artia_synced_at TIMESTAMPTZ;

-- Index para sync diff (busca por sync stale)
CREATE INDEX IF NOT EXISTS idx_initiatives_artia_stale 
  ON initiatives(artia_synced_at NULLS FIRST) 
  WHERE artia_activity_id IS NOT NULL;
```

### 4.2 Tabela `artia_status_reports` (nova) — Bloco 6

```sql
CREATE TABLE artia_status_reports (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  cycle_year INT NOT NULL,
  report_month DATE NOT NULL, -- truncado para mês
  body_md TEXT NOT NULL,
  generated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  generated_by_cron BOOLEAN DEFAULT true,
  artia_activity_id BIGINT,
  artia_synced_at TIMESTAMPTZ,
  UNIQUE(cycle_year, report_month)
);

ALTER TABLE artia_status_reports ENABLE ROW LEVEL SECURITY;

CREATE POLICY "v4_status_reports_read" ON artia_status_reports
  FOR SELECT USING (rls_can('manage_member') OR rls_can('view_internal_analytics'));
```

---

## 5. Discovery — descobrir estrutura Artia de outros projetos

### 5.1 Por que precisamos
- Outros 13 projetos PMI-GO usam o mesmo `ARTIA_ACCOUNT_ID 6345833`
- Projetos com score alto (PMO 74%, PM Lab 64%) já têm folders/activities corretas
- **Replicar estrutura deles** = caminho mais barato + alinhado ao que o auditor procura

### 5.2 Opções de discovery

**Opção A — Discovery mode na EF `sync-artia`** (recomendada)
Adicionar suporte a query param `?mode=discover`. Quando invocada nesse modo, em vez de fazer push de KPIs, ela:
1. Lista todos os projetos do account `6345833` (`projects(accountId: ...)`)
2. Para cada projeto, lista todas as folders (`folders(projectId: ...)`)
3. Para cada folder, lista até 20 activities (sample)
4. Persiste o resultado em uma nova tabela `artia_discovery_dumps` para análise

**Vantagens**: usa OAuth+secret já configurado; não requer ação manual do PM; dump auditável e re-rodável.

**Implementação esperada**: ~80 linhas TypeScript + 1 migration (table) + cron one-shot.

**Opção B — Curl manual via PM**
Vitor roda os comandos abaixo localmente (precisa `ARTIA_CLIENT_ID` + `ARTIA_CLIENT_SECRET` em `.env` ou na conta dele):

```bash
# 1. Authenticate
TOKEN=$(curl -s -X POST https://api.artia.com/graphql \
  -H "Content-Type: application/json" \
  -d "{\"query\":\"mutation { authenticationByClient(clientId: \\\"$ARTIA_CLIENT_ID\\\", secret: \\\"$ARTIA_CLIENT_SECRET\\\") { token } }\"}" \
  | jq -r '.data.authenticationByClient.token')

# 2. List projects in account
curl -s -X POST https://api.artia.com/graphql \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"query":"{ projects(accountId: 6345833, page: 1, pageSize: 50) { id name customStatus { id name } } }"}' \
  | jq

# 3. List folders of a high-conformance project (e.g., PMO project ID)
PMO_PROJECT_ID=<descobrir no #2>
curl -s -X POST https://api.artia.com/graphql \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"query\":\"{ folders(projectId: $PMO_PROJECT_ID) { id name accountId } }\"}" \
  | jq

# 4. Sample activities of a folder (Iniciação / Templates / Kick-off)
FOLDER_ID=<descobrir no #3>
curl -s -X POST https://api.artia.com/graphql \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"query\":\"{ activities(folderId: $FOLDER_ID, page: 1, pageSize: 20) { id title description completedPercent customStatus { id name } } }\"}" \
  | jq
```

**Vantagens**: zero código deploy; resultado imediato. **Desvantagens**: não auditável após execução; depende disponibilidade do PM.

**Opção C — Pedir ao PMO PMI-GO**
Vitor solicita ao analista de PMO uma planilha com a árvore folders+activities esperada para o projeto Núcleo. **Mais lento** (depende cooperação humana) mas **mais alinhado** ao que o auditor checará.

### 5.3 Recomendação
Combinar **Opção A** (Discovery mode na EF) para visibilidade técnica + **Opção C** (PMO solicitação) para alinhamento institucional. Opção B fica como fallback emergencial.

---

## 6. Implementação proposta — fases C.1 a C.5

### Fase C.1 — Discovery (sem decisão final ainda)
- [ ] Implementar Opção A (discovery mode na EF) — 30-60min
- [ ] Rodar discovery uma vez · armazenar em `artia_discovery_dumps`
- [ ] Análise: identificar folders padrão (Iniciação · Planejamento · Monitoramento · etc) e suas activities

### Fase C.2 — Schema migration (depende de C.1)
- [ ] Migration `20260516530000_artia_traceability_columns.sql` (vide §4.1)
- [ ] Migration `20260516530001_artia_status_reports.sql` (vide §4.2)

### Fase C.3 — EF expansion (depende de C.2)
- [ ] Refactor `sync-artia/index.ts` — separar em módulos:
  - `kpi-sync.ts` (atual lógica preservada)
  - `tap-sync.ts` (TAP + Templates + Kick-off → Folder 01)
  - `planning-sync.ts` (initiatives WBS → Folder 02)
  - `monitoring-sync.ts` (atividades ≤10d + atas + status reports → Folders 02/04/05)
  - `risk-sync.ts` (decisões + ADRs WARN → Folder 06)
  - `cost-sync.ts` (R$ 0,00 declarado → Folder 07)
- [ ] Adicionar `?blocks=tap,kpi,...` query param para sync seletivo
- [ ] Manter retro-compatibilidade: invocação sem query params = comportamento atual (KPIs only)

### Fase C.4 — Cron review
- **Decisão pendente**: manter `30 5 * * 0` (semanal) OU acelerar para diário (`30 5 * * *`)?
  - **Pro semanal**: low cost, baseline atual, batch suficiente para artigos publicados, KPIs
  - **Pro diário**: Bloco 6 (Atividades atualizadas ≤10d) precisa freshness · status report mensal precisa janela
  - **Recomendação**: split em 2 crons — `sync-artia-kpi-weekly` (KPIs · domingo 05:30 UTC, mantém atual) + `sync-artia-monitoring-daily` (board_items + atas · diário 06:00 UTC).

### Fase C.5 — Backfill histórico
- [ ] TAP Ciclo 3 → push para Folder 01 (link Google Doc)
- [ ] Manual de Governança · Política IP (em revisão) · 4 Acordos Cooperação → Folder 01 Templates
- [ ] Pasta Kick-off Drive (depois de migrar para institucional) → Folder 01 Kick-off
- [ ] Atas tribos 2026 (Drive `Atas/`) → Folder 05 (se existir)
- [ ] Riscos do TAP §13 → Folder 06 (cada risco = 1 activity)

---

## 7. Riscos e dependências

### 7.1 Dependências externas
- **Migração da pasta Kick-off** Drive pessoal → institucional **antes** de Fase C.5
- **Aprovação do TAP** (assinatura Ivan) **antes** de Fase C.5 push de TAP
- **Política IP aprovada** Comitê de Curadoria **antes** de Fase C.5 push de Templates (atualmente em revisão — paralelo independente)

### 7.2 Riscos técnicos
- **Rate limit Artia GraphQL** — não documentado pela Artia; assumir 60 req/min como Resend (5rps) para safety. Migration C.5 backfill pode precisar `pg_sleep` entre batches.
- **Schema PMI-GO Artia diferente do esperado** — folders 01/02/03/etc podem ter nomes/IDs diferentes. Discovery (Fase C.1) descobre a verdade antes de coding.
- **Activity IDs hardcoded em código** — mantém o anti-pattern atual (9 KPIs hardcoded). Recomendação: criar tabela `artia_activity_registry` com mapping logical_key → activity_id, atualizado via UI admin.
- **Conformidade LGPD** — atas com nomes de voluntários enviadas para Artia? Verificar com data-architect/security-engineer agents antes de Fase C.5.

### 7.3 Risco governance
- Ações da plataforma agora afetam outro sistema institucional (Artia) com auditor externo (PMO). Cada falha de sync vira não-conformidade na próxima auditoria. Adicionar **cron health monitoring** (similar a `get_invitation_health`, `get_lgpd_cron_health`, `get_digest_health`) — RPC `get_artia_sync_health` reportando: last sync time per block · sync errors last 7d · stale activities count.

---

## 8. Decisões pendentes para PM (Vitor)

1. **Discovery — Opção A (EF) ou B (curl manual) ou C (PMO)?** Recomendação: A + C em paralelo.
2. **Cron — manter semanal ou split em weekly+daily?** Recomendação: split.
3. **Hardcoded vs registry table — cadastrar activity IDs em DB ou manter no código?** Recomendação: registry table (manutenibilidade).
4. **LGPD nas atas** — atas com nomes voluntários podem ir para Artia? Recomendação: revisar com legal-counsel/security-engineer agents.
5. **Backfill histórico Ciclos 1-2** — vamos popular Artia com dados retroativos de 2024-2025 ou só do Ciclo 3 atual? Recomendação: só Ciclo 3 (auditoria atual avalia ciclo atual).
6. **ADR amendment** — esta expansão atualiza o pattern de sync external. Recomendação: novo ADR `ADR-0070 Artia bi-block sync expansion` capturando decisão.

---

## 9. Estimativa de esforço

| Fase | Esforço | Bloqueador |
|---|---|---|
| C.1 Discovery (Opção A) | 1h | nenhum |
| C.2 Migrations | 30min | C.1 |
| C.3 EF refactor | 4-6h | C.2 |
| C.4 Cron split + health RPC | 1h | C.3 |
| C.5 Backfill | 2-3h | C.4 + TAP assinado + kick-off migrado |
| **Total** | **9-12h** | |

Phase C tem 5 sub-fases independentes — podem ser distribuídas em 2-3 sessões dedicadas (não é monobloc).

---

## 10. Referências

- TAP Ciclo 3 2026: `docs/TAP_CICLO3_2026.md` (apêndice B mapeia auditoria → remediação)
- Auditoria PMO PDF: `~/Downloads/A/Relatório de Auditoria PMO – PMI-GO 2026.pdf`
- EF atual: `supabase/functions/sync-artia/index.ts`
- Cron atual: `cron.job` jobname `sync-artia-weekly` schedule `30 5 * * 0`
- Anti-pattern detectado: hardcoded activity IDs (9 KPIs em `KPI_ACTIVITY_MAP`)
- Pattern reuso: cron-bypass JWT context (ADR-0028 amendment) já aplicado · health RPC pattern (`get_invitation_health`/`get_lgpd_cron_health`/`get_digest_health` — Pattern 43 4th reuse from p78)
