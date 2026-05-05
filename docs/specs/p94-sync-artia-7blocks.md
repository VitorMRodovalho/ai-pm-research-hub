# Spec p94 — Expansão `sync-artia` para 7 blocos da auditoria PMO

**Data**: 2026-05-05
**Trigger**: Auditoria de Governança PMO PMI-GO 2026 (Núcleo IA = 17% conformidade · 14 não-conformidades)
**Status**: 🟢 Phase C.1 (discovery) ✅ + Phase C.2 (build-out) ✅ COMPLETOS 2026-05-05 · Phase C.3 (crons sustentabilidade) + C.4 (ADR amendment) + C.5 (backfill avulso) próximos
**Origem session**: p94 (handoff `memory/handoff_p94_artia_sync_audit.md`)

---

## ✅ Phase C.1 Discovery — Findings (2026-05-05)

### 1. Artia GraphQL schema descoberto (via introspection)

**Query fields (READ)**:
- `listingProjects(accountId)` — projetos do account
- `listingFolders(accountId, page)` — folders no account (NÃO project-scoped)
- `listingActivities(accountId, folderId)` — activities em uma folder
- `showProject(accountId, id)` · `showFolder(id)` · `showActivity(accountId, id, folderId)`
- + listingFinances, listingTimeEntries, listingCostCenters, listingServiceOrders

**Mutation fields (WRITE)** — relevantes para Phase C.5:
- `createProject` · `updateProject` · `destroyProject`
- `createFolder` · `updateFolder` · `destroyFolder` · `changeFolderStatus`
- `createActivity` · `updateActivity` ✓ (já usado) · `destroyActivities` · `changeCustomStatusActivity` ✓
- `createComment` · `createTimeEntry` · `createFinance`

> **Insight**: o naming convention é `listing*`/`show*` para reads e `create*`/`update*`/`destroy*` para writes. NÃO segue convenção GraphQL clássica (`projects`, `findProjects`, etc).

### 2. Visibilidade limitada do client_id

Nosso `ARTIA_CLIENT_ID/SECRET` enxerga apenas **4 projects** (de ~14 esperados pela auditoria):
| Project ID | Nome | Conformidade na auditoria |
|---|---|---|
| 6391775 | Núcleo de IA & GP | **17% (Crítica) ⚠️** |
| 6354910 | PMLab | 64% |
| 6399637 | Programa PMThanks | (não auditado) |
| 6399640 | Student Club | (não auditado) |

**Não visíveis** (porém na auditoria PMO): Seminário, Curso GP, Imersão, PM Day, GP em Campo, Meetup, Pacto Inovação, Webinar, Almoço Projetos, Melhores do Ano, Projeto Liderança, **PMO (74%)**.

→ Para benchmark da estrutura "ideal", usaremos **PMLab** (64%, tem estrutura completa).

### 3. PMLab — estrutura WBS-PMBOK descoberta (template a replicar)

**5 fases-mãe** (PMBOK process groups):
- `01- Iniciação` (id 6354911)
- `02- Planejamento` (id 6354912)
- `03- Execução` (id 6355334)
- `04- Monitoramento e Controle` (id 6354915)
- `05- Encerramento` (id 6354916)

**Sub-folders hierárquicas** com naming `XX.YY-Nome` e `XX.YY.ZZ-Nome`:

```
01- Iniciação
├── 01.01-Elaborar Termo de Abertura do Projeto
│   └── 01.01.01-Termo de Abertura do Projeto (TAP)
│       ├── Activity: Elaborar TAP
│       ├── Activity: Revisar TAP
│       ├── Activity: Aprovar TAP
│       └── Activity: Enviar TAP para o marketing
└── 01.02-Identificar as Partes Interessadas
    └── 01.02.01-Registro das Partes Interessadas
        └── Activity: Identificar e registar no TAP

02- Planejamento
├── 02.01-Planejar orçamento → Activities: Planejar orçamento, Aprovar orçamento
├── 02.02-Planejar analistas
├── 02.03-Planejar cronograma completo
├── 02.04-Planejar divulgação → Activities: Planejar Divulgação, Aprovar Divulgação
├── 02.05-Planejar 1ª edição
└── 02.06-Planejar 2ª edição

03- Execução
├── (root) Activity: Divulgação 1ª Edição
├── 03.01-Selecionar analistas
├── 03.02-Realizar 1ª edição → Activities: Execução, Contratar Local, Organizar Lanches, Organizar local, Certificados
└── 03.03-Realizar 2ª edição

04- Monitoramento e Controle
├── 04.01-Status Report 1ª Edição
└── 04.02-Status Report 2ª Edição

05- Encerramento
├── Activity: Reunião de lições aprendidas
├── Activity: Elaboração do Termo de Encerramento do Projeto (TEP)
└── Activity: Aprovação do TEP
```

### 4. Núcleo de IA & GP — estrutura ATUAL descoberta

**Apenas 2 folders top-level visíveis no listing** (vs PMLab's ~22):
- `01 - Iniciação` (id 6391776) — vazio ou quase vazio
- `02 - Planejamento` (id 6391777)

**Folder oculto em uso**: ARTIA_KPI_FOLDER `6399649` (hardcoded em sync-artia EF) — onde os 9 KPIs vivem. NÃO aparece em `listingFolders(page: 1)` — provável paginação ou folder archived/hidden.

**Faltando completamente**:
- ❌ `03 - Execução`
- ❌ `04 - Monitoramento e Controle` (KPI folder existe mas isolado · sem sub-pastas Status Report)
- ❌ `05 - Encerramento`
- ❌ Sub-folder `01.01-Elaborar TAP` + `01.01.01-TAP` com activities Elaborar/Revisar/Aprovar TAP
- ❌ Sub-folder `01.02-Partes Interessadas`
- ❌ Sub-folders Planejamento (orçamento, cronograma, divulgação)
- ❌ Sub-folders Status Report periódicos

### 5. Por que a auditoria deu 17% — explicado pela estrutura

| Bloco PMO | Score | Razão estrutural Artia |
|---|---|---|
| TAP 0% | Crítico | Não existe folder `01.01.01-TAP` nem activities Elaborar/Revisar/Aprovar TAP |
| Templates 0% | Crítico | Não existe sub-folder com TAP template institutional anexado |
| Kick-off 0% | Crítico | Não existe activity "Kick-off realizado" em folder `01- Iniciação` |
| Uso do Artia 0% | Crítico | TAP não está repassado · Planejamento sem WBS · Riscos/Custos sem activities |
| Monitoramento 0% | Crítico | Não existe folder `04.01-Status Report` periódico |
| Lições Aprendidas N/A | (em curso) | Será aplicável em Dez/2026 (folder `05- Encerramento`) |
| Cadastros 100% ✓ | OK | Único bloco já feito (membros + email + Drive) |

### 6. Plano de remediação (Phase C.2-C.5) baseado nos findings

**Phase C.2 — Replicar estrutura PMBOK no projeto Núcleo (Artia)**:
1. Criar 3 folders top-level faltando: `03 - Execução`, `04 - Monitoramento e Controle`, `05 - Encerramento`
2. Criar sub-folders WBS sob `01 - Iniciação`:
   - `01.01-Elaborar Termo de Abertura do Projeto`
     - `01.01.01-Termo de Abertura do Projeto (TAP)` com activities (Elaborar/Revisar/Aprovar/Anexar Drive)
   - `01.02-Identificar as Partes Interessadas`
     - `01.02.01-Registro das Partes Interessadas` com activity referenciando TAP §14 RACI
   - `01.03-Reunião de Kick-off Ciclo 3` com activity "Kick-off realizado 2026-03-05" + link para Drive `1. Iniciação/Kick-off`
3. Criar sub-folders sob `02 - Planejamento`:
   - `02.01-Planejar orçamento` (R$ 0,00 baseline, 2 activities: Planejar/Aprovar)
   - `02.02-Planejar voluntários` (cf. processo seletivo metrificado)
   - `02.03-Planejar cronograma anual` (Q1-Q4 marcos do TAP §9)
   - `02.04-Planejar publicações` (pipeline 10 artigos)
   - `02.05-Planejar webinares` (6 + LIM Lima + Detroit)
4. Criar sub-folders sob `04 - Monitoramento e Controle`:
   - Mover ARTIA_KPI_FOLDER `6399649` para sub-folder `04.01-KPIs anuais`
   - `04.02-Status Report Mensal` (12 activities — uma por mês 2026)
   - `04.03-Atas Plenárias Mensais` (12 activities)
   - `04.04-Atas Tribos Mensais` (sub-grupos por tribo)

**Phase C.3 — EF push automation** (já especificado em §6 do doc original)

### 7. Decisões PM (2026-05-05)

1. ✅ EF mutations (não manual)
2. ✅ NÃO pedir acesso PMO ampliado — scope dos 4 projetos visíveis suficiente para Phase C.2-C.5
3. ✅ Naming `YYYY.S` (ano/semestre) — `Ciclo 3 (2026.1)` etc

---

## ✅ Phase C.2 SHIPPED (2026-05-05)

### 1. Migrations executadas (3 + 1 hotfix)
- `20260516530000` — `artia_discovery_dumps` (Phase C.1 já)
- `20260516530001` — artia_*_id columns em governance_documents/initiatives/events/board_items + 4 indexes
- `20260516530002` — `program_risks` table + RLS V4 + 11 risks seed do TAP §13 + trigger updated_at
- `20260516530003` + `_3b_fix` — `artia_status_reports` cache + 2 LGPD-safe helpers `_artia_safe_event_summary` e `_artia_safe_monthly_metrics`

### 2. EF sync-artia v3 (5 modes)
- `default` (existente — KPI weekly sync)
- `?mode=introspect` — dump GraphQL schema
- `?mode=verify-access` — pagination + Folder/Project type intro
- `?mode=show-childs` — showProject + scope test
- `?mode=introspect-types` — Activity/Comment/mutation args
- `?mode=create-structure&dry_run=true|false` — Phase C.2 build-out

### 3. Estrutura criada no Artia (live, 0 erros)

**Project metadata atualizado** (description/justification/premise/restriction/lastInformations) — 1 mutation `updateProject(6391775)` ✓

**15 sub-folders novos** (IDs sequenciais 6516550-6516564):

```
01 - Iniciação (parent 6391776)
├── 01.01 - Termo de Abertura do Projeto (TAP) [6516550]
│     └─ 4 activities: Elaborar / Revisar / Aprovar / Anexar Drive
├── 01.02 - Registro das Partes Interessadas [6516551]
│     └─ 1 activity: Matriz RACI consolidada TAP §14
├── 01.03 - Reunião de Kick-off Ciclo 3 (2026.1) [6516552]
│     └─ 1 activity: Kick-off realizado 2026-03-05 17:15
└── 01.04 - Templates Institucionais [6516553]
      └─ 4 activities: TAP / Manual Governança / Política IP (em revisão) / Acordos Cooperação

02 - Planejamento (parent 6391777)
├── 02.01 - Planejar Orçamento Ciclo 3 [6516554] (1 activity R$ 0,00)
├── 02.02 - Planejar Voluntários [6516555] (1 activity 48 ativos)
├── 02.03 - Planejar Cronograma Anual 2026 [6516556] (1 activity)
├── 02.04 - Planejar Publicações [6516557] (1 activity 0/10 artigos)
└── 02.05 - Planejar Webinares e Eventos Externos [6516558] (1 activity 0/6 + LIM + Detroit)

04 - Monitoramento e Controle (parent 6399649)
├── 04.02 - Status Reports Mensais 2026 [6516559] (1 activity recurrence='monthly')
├── 04.03 - Atas Plenárias Mensais [6516560] (1 activity recurrence='monthly')
├── 04.04 - Atas de Tribos Semanais [6516561] (1 activity recurrence='weekly')
└── 04.06 - Riscos do Programa 2026 [6516562]
      └─ 11 activities (1 por risco TAP §13, status workflow ABERTO/EM_TRATAMENTO/MITIGADO)

05 - Encerramento (parent 6399650)
├── 05.01 - Lições Aprendidas Ciclo 3 [6516563] (2 activities A_INICIAR Dez/2026)
└── 05.02 - Termo de Encerramento (TEP) Ciclo 3 [6516564] (2 activities A_INICIAR Dez/2026)
```

**33 activities criadas** distribuídas conforme estrutura acima.

### 4. Verificação end-to-end (2026-05-05)
- listingFolders pre-Phase C.2: 35 folders total
- listingFolders pós-Phase C.2: **50 folders** (+15 ✓ confirmadas)
- updateProject ok=true (id 6391775)
- 0 erros em todas 49 mutations (1 updateProject + 15 createFolder + 33 createActivity)
- LGPD helpers testados em produção (April 39 events/43.8h · May 35 events/48 vol)

### 5. Mapeamento auditoria 7 blocos → cobertura Phase C.2

| Bloco PMO | Score atual | Estrutura criada Phase C.2 | Cobertura esperada na próxima auditoria |
|---|---|---|---|
| TAP (1) | 0% | 01.01 + 01.04 (TAP) + Project metadata | ≥75% (depende assinatura Ivan) |
| Cadastros (2) | 100% | (já OK) | 100% |
| Templates (3) | 0% | 01.04 (TAP/Manual/Política IP/Acordos) + Project metadata | ≥75% |
| Kick-off (4) | 0% | 01.03 (Kick-off realizado 2026-03-05) | 100% (Drive folder migrado + activity criada) |
| Uso do Artia (5) | 0% | 01.01 TAP + 02.0X Planejamento + 04.06 Riscos + Custos no metadata | ≥80% (TAP repassado ✓ Plano ✓ Riscos ✓ Custos ✓) |
| Monitoramento (6) | 0% | 04.02 Status Reports (recurrence) + 04.03 Atas + 04.04 Atas Tribos + 04 KPIs (já existe) | ≥75% após Phase C.3 crons rodarem |
| Lições (7) | N/A | 05.01 + 05.02 placeholders Dez/2026 | N/A até encerramento |

**Score esperado pós-Phase C.2**: 17% → ~70-80% (depende crons C.3 popularem descriptions periodicamente)

---

## 🔜 Phase C.3 (próxima) — Crons de sustentabilidade

5 crons + 1 trigger event-driven a implementar:
1. `sync-artia-kpi-weekly` (existente — manter)
2. `sync-artia-monitoring-daily` (NOVO) — atividades ≤10d
3. `sync-artia-status-report-monthly` (NOVO) — gera + sync para folder 04.02 activity ID 6516559+
4. `sync-artia-rituals-weekly` (NOVO) — atas + ritos para folders 04.03/04.04
5. `sync-artia-risks-monthly` (NOVO) — sync program_risks → 04.06 activities
6. **Event-driven**: trigger SQL AFTER UPDATE em governance_documents (atualiza folder 01.04 activities) + AFTER INSERT em events.type='kick_off' (atualiza 01.03)

Cada cron usa LGPD helpers + atualiza `artia_synced_at` em platform tables. Estimativa: 4-5h em sessão p95 dedicada.

---

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
