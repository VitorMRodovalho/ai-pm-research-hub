# ADR-0069: Artia Bidirectional Sync Pattern (Phase C of PMO Audit Remediation)

**Status**: Accepted
**Date**: 2026-05-05
**Decider**: PM Vitor Maia Rodovalho (GP Núcleo IA & GP)
**Trigger**: Auditoria de Governança PMO PMI-GO 2026 (Núcleo IA = 17% conformidade · 14 não-conformidades · severidade Crítica)

---

## Context

A Auditoria PMO PMI-GO 2026 (gerada 2026-05-04) avaliou 14 projetos do capítulo em 7 blocos de governança institucional. O projeto Núcleo IA recebeu **17% de conformidade** (último dos 14 — pior score):

| Bloco PMO | Score Núcleo |
|---|---|
| TAP | 0% |
| Cadastros | 100% (único bloco OK) |
| Templates | 0% |
| Kick-off | 0% |
| Uso do Artia | 0% |
| Monitoramento | 0% (apenas 9 KPIs sincronizados via cron weekly desde p82) |
| Lições Aprendidas | N/A (aplicável só em encerramento) |

**Causa raiz**: o Núcleo opera principalmente na plataforma própria (`nucleoia.vitormr.dev`) e Drive PMI-GO, mas o auditor PMI-GO usa Artia como fonte de verdade institucional para evidência. Havia drift entre realidade operacional do programa e representação no Artia — dados existiam mas em formatos/localizações que o auditor não consultava.

A platform Artia da PMI-GO usa estrutura WBS-PMBOK clássica (5 grupos de processo + sub-folders hierárquicas + activities granulares por entrega). O projeto-template de alta conformidade do capítulo (PMLab, 64% — visível para nosso `CLIENT_ID/SECRET`) estabelece o padrão expected.

## Decision

Implementar **5-layer Artia bidirectional sync pattern** com automação por cron + event-driven trigger, mantendo a plataforma `nucleoia.vitormr.dev` como source of truth e Artia como **espelho institucional** consumido pela auditoria.

### Arquitetura

```
┌─────────────────────────────────────────────────────────────────┐
│  Plataforma Núcleo (source of truth)                            │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │ Tables: initiatives, governance_documents, events,       │    │
│  │         board_items, program_risks, annual_kpi_targets, │    │
│  │         artia_status_reports                            │    │
│  │ Each row has artia_*_id + artia_synced_at columns       │    │
│  └─────────────────────────────────────────────────────────┘    │
└────────────────────┬────────────────────────────────────────────┘
                     │ (1) Push via 5 layers
                     ▼
┌─────────────────────────────────────────────────────────────────┐
│  Edge Function: sync-artia (10 modes)                           │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │ default        → 13 KPIs (weekly Sun 05:30 UTC)          │   │
│  │ cron-daily     → Project.lastInformations + atas tribos  │   │
│  │ cron-monthly   → Status Report + 11 risks (1st 07:00 UTC)│   │
│  │ create-structure → Phase C.2 build-out (one-shot)        │   │
│  │ reorganize-kpis  → Phase C.2.5 expand 9→13 (one-shot)    │   │
│  │ + 5 introspect/discover/verify modes (audit/dev tools)   │   │
│  └──────────────────────────────────────────────────────────┘   │
└────────────────────┬────────────────────────────────────────────┘
                     │ (2) GraphQL mutations (LGPD-safe via helpers)
                     ▼
┌─────────────────────────────────────────────────────────────────┐
│  Artia Project: Núcleo de IA & GP (id 6391775)                  │
│  ├── 01 - Iniciação (TAP / RACI / Kick-off / Templates)          │
│  ├── 02 - Planejamento (5 sub-folders)                           │
│  ├── 03 - Execução (initiatives backfilled C.5)                  │
│  ├── 04 - Monitoramento (KPIs / Status Report / Atas / Risks)    │
│  └── 05 - Encerramento (Lições / TEP placeholders Dez/2026)      │
└─────────────────────────────────────────────────────────────────┘
                     │ (3) Auditor consume
                     ▼
                ┌────────────┐
                │ PMO PMI-GO │
                │   Audit    │
                └────────────┘
```

### 5 Layers de Sync

**Layer 1 — Structure build-out (one-shot)**:
- 15 sub-folders + 33 activities + Project metadata via mutations `createFolder` / `createActivity` / `updateProject`
- Idempotent via tracking de IDs em `artia_discovery_dumps` + `artia_*_id` columns

**Layer 2 — KPIs weekly (existing pattern p82)**:
- Cron `sync-artia-weekly` (Sun 05:30 UTC) → 13 KPIs (9 originals + 4 added Phase C.2.5)
- Each KPI = 1 Artia activity com `completedPercent` + `customStatus` baseado em platform compute

**Layer 3 — Daily monitoring**:
- Cron `sync-artia-monitoring-daily` (06:00 UTC) → updateProject.lastInformations (rolling status snapshot)
- Plus folder 04.04 atas tribos com last 7d events grouped by type
- LGPD-safe: agregados via `_artia_safe_event_summary` helper (no PII names)

**Layer 4 — Monthly Status Report + Risks**:
- Cron `sync-artia-status-report-monthly` (1st day 07:00 UTC) → gera relatório Markdown ≤5KB
- INSERT em `artia_status_reports` (idempotency cache) + updateActivity folder 04.02
- Sync 11 program_risks → 04.06 activities via updateActivity per risk
- Compute via `_artia_safe_monthly_metrics` helper (LGPD-safe agregados)

**Layer 5 — Event-driven trigger**:
- `trg_artia_sync_on_govdoc_ratified` AFTER UPDATE OF current_ratified_at ON governance_documents
- Quando Política IP (ou outro doc) ratifica → enqueue async cron-daily refresh
- Try/catch + RAISE NOTICE garantem que UPDATE original NUNCA bloqueia

### Patterns canônicos

1. **`artia_*_id` columns** em todas tables que push para Artia — rastreabilidade bidirecional sem hardcoded mappings
2. **`artia_synced_at`** + partial indexes WHERE `artia_activity_id IS NOT NULL` — sync diff em scale
3. **LGPD safe helpers SECDEF** (`_artia_safe_event_summary`, `_artia_safe_monthly_metrics`) — gateway obrigatório antes de qualquer PUSH para Artia
4. **Hardcoded folder/activity IDs apenas para Phase C.0/C.1 baseline**; daí em diante via registry table OR per-row column
5. **Per-KPI folderId** em `KPI_ACTIVITY_MAP` (não constante única) — permite KPIs em múltiplos folders pós descoberta de movement infeasibility (vide §"Limitations")
6. **Idempotency via `ON CONFLICT DO NOTHING`** em INSERT de risks + status reports
7. **Recurrence via `ActivityRecurrenceInput`** para Status Reports mensais (1 activity, recurring) e Atas semanais — economiza criação de N activities

## Alternatives Considered

### A1. Manual maintenance no Artia (rejected)
**Pros**: zero dev cost, controle total humano.
**Cons**: drift garantido (auditor 04-05 já marcou 17%), dependência GP/Vice-GP availability, sem evidência sistêmica de "atividades atualizadas ≤10d". Inviável em scale 7 tribos / 4 frentes / 13 iniciativas / 11 riscos.

### A2. Full Artia replacement por nossa plataforma como fonte de auditoria (rejected)
**Pros**: zero double-write.
**Cons**: PMO PMI-GO não muda processo institucional. Capítulo está padronizado em Artia há anos. Fight-the-current vs. Mirror-and-comply trade-off: optamos por mirror.

### A3. Hardcoded activity/folder IDs no código (current Layer 2 — to be deprecated em Phase C.6)
**Pros**: zero schema migrations.
**Cons**: cada novo KPI = code change + redeploy. **Phase C.6 future**: registry table `artia_object_registry` com (object_kind, logical_key, artia_id, folder_id) → EF reads at runtime. Diferido para depois de Phase C.3 estabilizar.

### A4. Synchronous trigger (rejected)
Trigger AFTER UPDATE poderia chamar Artia sync sincronamente, bloqueando UPDATE original até resposta GraphQL. Rejected por:
- Latência: ~200-500ms por mutation Artia
- Rate limits Artia podem timeout transação
- Falha Artia bloqueia UPDATE platform (anti-pattern p89 ADR-0028 amendment já estabelecido)

**Decisão**: async via `net.http_post` + `try/catch + RAISE NOTICE` — Artia falha NÃO afeta plataforma.

## Consequences

### Positive

- **Cobertura auditoria projetada**: 17% Crítica → 75-85% (provável Atenção/Conforme)
- **Sustentabilidade**: 3 crons + 1 trigger mantém estrutura viva sem intervenção GP/Vice-GP
- **Evidência sistêmica**: cada cron persiste audit trail em `mcp_usage_log` + `artia_discovery_dumps`
- **LGPD**: helpers `_artia_safe_*` blindam PII em todos os crons (auditável via SECDEF + GRANT EXECUTE)
- **Rastreabilidade**: cada row platform tem `artia_*_id` — diff queries triviais
- **Re-uso**: pattern aplicável a outros sistemas externos (PMI Global Artia? PMOGA? PMI Latam tools?)

### Negative

- **Rate limit Artia não-documentado** — observamos ~60 req/min OK; se violado, cron retry com `pg_sleep`. Mitigação: cron monthly distribui carga (1 status report + 11 risks = 12 mutations); cron daily distribui carga (1 updateProject + 1 listActivities + 1 updateActivity = 3 mutations); cron weekly distribui carga (13 KPIs = 26 mutations com status changes).
- **Folder movement infeasible** — `updateActivity(folderId)` valida ownership (atividade deve já estar na pasta indicada). 9 KPIs originais ficam em folder 6399649; 4 novos em sub-folder 6516663. Auditor não diferencia. Documentado em ADR.
- **Auth scope limitado** — `CLIENT_ID/SECRET` vê 4/14 projetos do account 6345833. PMO ampliação dependeria pedido formal — não-bloqueante para Núcleo (escopo é projeto 6391775).
- **Description text length ~5KB** — não documentado pelo Artia. Status Report pode encostar; mitigação: comments para detalhe + description para resumo.
- **Sem retry/backoff em GraphQL falhas** — se mutation falha, log no errors array + cron próxima execução tenta novamente. Phase C.6 future: implement exponential backoff + dead-letter queue.

### Neutral

- **9 KPIs em folder 04 + 4 em sub-folder 04.01** — split estrutural mas auditor não diferencia
- **`Project.lastInformations` rolling** — cada cron daily sobrescreve. Histórico via Comments adicionados (Phase C.6 future)
- **Trigger event-driven** — só dispara em `current_ratified_at` change. Outros eventos (kick-off, document_versions) ainda manual. Phase C.6 expansion possível.

## Compliance & Security

- **LGPD**: `_artia_safe_event_summary` + `_artia_safe_monthly_metrics` SECDEF + STABLE — agregados only, no PII. Helpers grantados `authenticated` (via service role, nunca via user JWT direta).
- **Authentication**: Artia OAuth client_credentials grant via `authenticationByClient(clientId, secret)` — credentials em Deno env (sem log).
- **Authorization**: Artia API gates "Projeto não encontrado" para IDs fora do scope — fail-closed.
- **Idempotency**: `ON CONFLICT DO NOTHING` em INSERTs de risks + status reports + UNIQUE (cycle_year, risk_code) constraints.
- **Audit trail**: cada mutation logged em `mcp_usage_log` com tool_name, success, error_message.

## Implementation Reference

| Phase | Commit | Deliverable |
|---|---|---|
| C.0 | `4074ce9` | CLAUDE.md slim + TAP draft + spec |
| C.1 | `350467b` | Discovery (introspect + discover modes) |
| C.1.5 | `57be735` | Verify-access (4/14 projects scope) |
| C.1.7 | `002360c` | Type introspection (Activity/Comment/mutations) |
| C.2 | `3554d7d` | 15 folders + 33 activities + Project metadata |
| C.2.5 | `668ca95` | KPIs 9→13 + sub-folder 04.01 |
| C.3 | `3b0ba98` | 2 crons + event trigger sustainability |
| C.4 | (this commit) | ADR-0069 documenting pattern |
| C.5 | (this commit) | Backfill 13 initiatives → folder 03 Execução |

**EF**: `supabase/functions/sync-artia/index.ts` (v5, 10 modes)
**Migrations**: `20260516530000-530005` (6 migrations)
**Spec**: `docs/specs/p94-sync-artia-7blocks.md`

## Future Work (post-p94)

- **Phase C.6**: registry table `artia_object_registry` (deprecate hardcoded `KPI_ACTIVITY_MAP`)
- **Phase C.7**: Comments for longitudinal history (vs description rolling overwrite)
- **Phase C.8**: Activities movement via destroyActivity + createActivity (preserve activity_id mapping)
- **Phase C.9**: Cross-project benchmark via expanded `CLIENT_ID/SECRET` scope (request to PMO)
- **Phase C.10**: ActivityRecurrenceInput for status reports (test recurrence='monthly' input shape)
- **Operational**: avisar PMO PMI-GO when stable + request re-audit
