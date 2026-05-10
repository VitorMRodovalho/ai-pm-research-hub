# Ω-A Sweep — Docs Audit Report (p134)

**Data**: 2026-05-09
**Agent**: docs-refresher (Ω-A)
**Escopo**: Auditar staleness de README.md, docs/INDEX.md, wiki_pages, ADRs, CLAUDE.md
**Modo**: read-only — relatório com texto sugerido pronto, sem edições.

---

## Sumário executivo

| Doc | Tamanho | Staleness | Severidade |
|---|---|---|---|
| `README.md` | 270 L | 5 ocorrências de "266 tools" (real: 284); EF count 32 (real: 35); cron 4 (real: 34); GC 135+ (real: 141) | Alta |
| `docs/INDEX.md` | 44 L | Lista ADRs 0001-0010 (real: 0001-0076); GC 131+ (real: 141); falta strategy/audit/refactor/specs/drafts/reference/research/reports | Alta |
| `wiki_pages` (DB) | 40 pages | 100% stale (>14 d), mais recente 2026-04-18 | Média (cron sync ausente?) |
| `docs/adr/README.md` | 100 L | Vai até ADR-0075. Falta ADR-0076 (PROPOSED p125) | Baixa |
| `CLAUDE.md` | 80 L | Geral OK. Counts não pinados por design (anti-bloat) | OK |
| `.claude/rules/mcp.md` | linha 9 | "283 tools" (real: 284 per p133 v2.69.0) | Baixa |

---

## 1. README.md — refresh sugerido

### 1.1 Stats incorretos detectados (5 hits "266 tools")

| Linha | Atual | Correto |
|---|---|---|
| 14 | `[![MCP](https://img.shields.io/badge/MCP-266%20Tools-D97757...)]` | `MCP-284%20Tools` |
| 47 | `\| MCP tools \| 266 \|` | `\| MCP tools \| 284 \|` |
| 48 | `\| Edge Functions \| 32 \|` | `\| Edge Functions \| 35 \|` (real: 35 dirs em `supabase/functions/` excluindo `_shared`) |
| 50 | `\| Tests \| 1,418 passing (1,456 with service-role) \|` | `\| Tests \| 1,383 passing (1,415 with service-role) \|` (per `.claude/rules/deploy.md`) |
| 85 | `Edge Functions<br/>31 deployed` (mermaid) | `Edge Functions<br/>35 deployed` |
| 112 | `**MCP** \| Custom server (266 tools)` | `(284 tools)` |
| 113 | `Supabase Edge Functions (32)` | `(35)` |
| 116 | `pg_cron (4 jobs)` | `pg_cron (34 jobs)` (real: 34 active jobs em cron.job) |
| 124 | `266 tools authenticated via OAuth 2.1` | `284 tools authenticated via OAuth 2.1` |
| 161 | `Claude.ai \| Verified (266 tools)` | `(284 tools)` |
| 200 | `Governance Changelog — 135+ entries (GC-001 → GC-135+)` | `141+ entries (GC-001 → GC-141+)` |
| 237 | `functions/      # 32 Edge Functions` | `# 35 Edge Functions` |
| 239 | `tests/              # 1,418 passing tests` | `# 1,383 passing tests` |

### 1.2 Claims de volume sub-reportados

- Linha 84 (mermaid): `PostgreSQL<br/>500+ RPC` — real: **795 functions** em `pg_proc` schema public. Sugestão: `PostgreSQL<br/>700+ RPC` ou explicit `795 functions`.
- Linha 110: `200+ SECURITY DEFINER functions` — provável undercount; manter "200+" é seguro mas considerar `400+` se for auditável.
- Linha 116: descrição de pg_cron lista só `Credly sync, attendance, detractor alerts, reminders` — falta backup-to-r2, drive-discover-atas, mcp-anomaly-detection, lgpd-anonymize, log-retention, retry-pending-ai-{analyses,triages}, send-notification-emails, dispatch-pending-emails, sync-artia-*, send-weekly-{member,leader}-digest, v4_engagement_*, etc.

### 1.3 Faltas estratégicas (anchor PMIS multi-client)

- README **não menciona** vertical PMIS/SaaS para PMI chapters (per `memory/project_chapter_pmis_saas_vision_p133.md` — STRATEGIC ANCHOR p133).
- README **não menciona** Domain Model V4 (concluído 2026-04-13). Linha 31 ainda fala "alliance of 5 PMI chapters" como narrative principal — verdadeiro mas não captura a evolução para multi-client architecture.
- Sugestão: adicionar uma seção curta após "Overview" (linha 33-35) ou substituir parágrafo final do "Overview":

```markdown
> **Project Manager:** Vitor Maia Rodovalho

### Architectural posture (post-V4, 2026-04-13)

The platform was refactored in April 2026 to support multi-tenant operation
(Domain Model V4 — see [`docs/refactor/DOMAIN_MODEL_V4_MASTER.md`](docs/refactor/DOMAIN_MODEL_V4_MASTER.md)).
Initiatives are the domain primitive; tribes are a bridge; authority derives
from active engagements via `can()`. This positions the codebase as a
candidate vertical PMIS/SaaS substrate for PMI chapters globally.
```

### 1.4 "Founded in 2024" precisão

Linha 31: `Founded in 2024 as a pilot within PMI Goiás` — verificar com PM se 2024 é a data correta vs 2025 (pilot) ou 2026 (multi-chapter consolidation). Não tenho fonte primária no codebase; deferir à confirmação humana.

### 1.5 Suggested replacement text — Key Numbers (linhas 37-52)

```markdown
## Key Numbers

| Indicator | Value |
|-----------|-------|
| Active researchers (Cycle 3) | 52 |
| Research streams (Tribos) | 7 |
| PMI chapters | 5 (GO · CE · DF · MG · RS) |
| Events held | 209 |
| Governance entries | 141+ (GC-001 → GC-141+) |
| Blog posts | 9 |
| MCP tools | 284 |
| Edge Functions | 35 |
| pg_cron jobs | 34 |
| RPCs (SECURITY DEFINER + helpers) | 795 |
| i18n keys | 4,000+ (3 locales) |
| Tests | 1,383 passing (1,415 with service-role env) |
| Monthly cost | $0 |
```

### 1.6 Suggested replacement text — Technical Stack (linhas 104-119)

Linha 116, substituir descrição de pg_cron:

```markdown
| **Cron** | pg_cron (34 jobs) | Credly sync, attendance batch, detractor alerts, weekly digests (member + leader + tribe), MCP anomaly detection, LGPD anonymize, log retention, R2 backup, AI retry queues, Artia sync, drive-discover-atas, V4 engagement expiry/anonymize |
```

### 1.7 Compatibility table (linhas 159-166)

Linha 161: `Claude.ai | Verified (266 tools)` → `(284 tools)`.

---

## 2. docs/INDEX.md — entries faltando + new sections sugeridas

INDEX está magro (44 L). Lista apenas ADR-0001..0010 (linha 19) e GC-001→GC-131+ (linha 26), enquanto a realidade é ADR-0001..0076 e GC-001..GC-141+. Faltam várias subdirs inteiras.

### 2.1 ADRs não-linkadas — ADR-0070 a ADR-0076

INDEX.md linha 19: `[adr/README.md](adr/README.md) | Architecture Decision Records (ADR-0001..0010)`

Real: ADRs vão até **ADR-0076**. Substituir por:

```markdown
| [adr/README.md](adr/README.md) | Architecture Decision Records (ADR-0001..0076, including Domain Model V4 pacote 0004-0009) |
```

ADRs recentes (0070+) — todos já estão no `docs/adr/README.md` exceto ADR-0076:

| ADR | Title | Status | No INDEX.md? | No adr/README.md? |
|---|---|---|---|---|
| ADR-0070 | external-speaker-artifact-conventions | Proposed/Accepted | Não (não-individual) | Sim (linha 76) |
| ADR-0071 | member-lifecycle-state-machine | Accepted | Não | Sim (77) |
| ADR-0072 | arm1-lead-capture-funnel | Accepted | Não | Sim (78) |
| ADR-0073 | issue116-calendar-booking-sync-apps-script | Accepted | Não | Sim (79) |
| ADR-0074 | onda3-arm-dual-model-ai-architecture | Accepted | Não | Sim (80) |
| ADR-0075 | cv-extraction-pipeline | Accepted (2026-05-07) | Não | Sim (81) |
| ADR-0076 | pmi-3d-volunteer-model-and-phase-b-base-legal | **PROPOSED** (p125, pending Ivan DPO sign-off Wave 4) | Não | **NÃO** — gap |

**Ação A**: adicionar ADR-0076 ao `docs/adr/README.md` como entry pré-aceitação:

```markdown
- `ADR-0076-pmi-3d-volunteer-model-and-phase-b-base-legal.md` — PMI 3-d volunteer model + Phase B base legal Art. 7 IX + retention bifurcated 5y/12m/90d + Trentim Path B firewall + 11 princípios. **Status: Proposed (2026-05-09 p125), pending Ivan DPO sign-off Wave 4.**
```

### 2.2 Subdirs ausentes do INDEX.md

INDEX referencia apenas: README, ARCHITECTURE, CLAUDE, adr/, RUNBOOK, GOVERNANCE_CHANGELOG, BACKLOG, council/. Falta:

| Subdir | Quantidade | Sugestão entry |
|---|---|---|
| `docs/strategy/` | 5 docs (ARM_PILLARS_AUDIT_P107, p126_issue_*_×3, p129_cycle3_to_cycle4_cohort_prep) | Strategic audits e cohort preps por sessão |
| `docs/specs/` | 19 docs incl SPEC_ADR_0022_W1, SPEC_ENGAGEMENT_WELCOME_EMAIL, p84-wave5-*, p87-*, p91-selection-journey-audit, p94-sync-artia-7blocks, PMI_JOURNEY_V4_REVIEW, COMMS_PAGES_REDESIGN_SPEC, DATA_COLLECTION_GOVERNANCE | Specs de feature por onda |
| `docs/drafts/` | 8 docs incl IP policy v2.7 handoff, p131_email_*, blog-mcp-framework-outline | Drafts em curso (HTML staging per pattern p128) |
| `docs/audit/` | 22 docs incl RPC_BODY_DRIFT_AUDIT_P50, ROUTE_INVENTORY, TABLE_INVENTORY, TECHNICAL_DEBT_INVENTORY, MASTER_SUMMARY, LGPD_ROPA_PUBLIC_SURFACES, MPP_AUDIT_P74, SPEC_VS_DEPLOYED_*×4 | Audits cross-session |
| `docs/refactor/` | 5 docs (DOMAIN_MODEL_V4_MASTER, CUTOVER_FASE4_PLAN, HERLON_VEP_PARALLEL_TRACK, PHASE5_C4_BLAST_RADIUS, TRIBE_ID_READERS_AUDIT) | Histórico do V4 refactor |
| `docs/reference/` | 1 doc (V4_AUTHORITY_MODEL.md) | **Load-bearing** — citado em `.claude/rules/database.md` para audit anti-false-positive |
| `docs/research/` | 2 docs (peer_review_briefing_cycle3_2026_b2, raises_the_bar_validation) | Validações peer review |
| `docs/reports/` | 2 docs (HANDOVER_2026-04-23_DEV_TEAM, USABILITY_HUB_COMMS_MAYANA_2026-04-22) | Reports estratégicos |
| `docs/editorial/` | 1 doc (CONTENT_PIPELINE_PLAYBOOK) | Editorial pipeline |
| `docs/instrumentos-ip/` | 4 HTML drafts (TERMO_REVISADO, ADENDOS, POLITICA_PUBLICACAO) | Drafts IP estatutários |
| `docs/blog/` | 2 docs (CBGPL_BLOG_POST, v4-blog-post-insert.sql) | Blog source content |
| `docs/scripts/` | 1 (`extract_pmi_volunteer.js`) | Scripts utilitários |
| `docs/sessions/` | 0 (vazio) | Pode remover ou popular |
| `docs/migrations/` | 1 dir (Mar 26) | Migrations docs (legado?) |
| `docs/project-governance/` | 1 dir (Mar 26) | Project governance docs (legado?) |
| `docs/archive/` | 1 dir (May 5) | Archived docs |

### 2.3 Top-level docs ausentes do INDEX.md

INDEX só lista: ARCHITECTURE, CLAUDE, adr/README, RUNBOOK, GOVERNANCE_CHANGELOG, BACKLOG, council/. Faltam (top-level docs/*.md):

- `ADMIN_ARCHITECTURE.md` (referenciado em README.md linha 260)
- `BRIEFING_IVAN_*.md` (3 docs — históricos)
- `BRIEFING_LIDERANCA_16ABR2026.md`
- `CBGPL_*.md` (5 docs — histórico CBGPL p43-p48)
- `DEPENDENCY_AUDIT.md`
- `DEPLOY_CHECKLIST.md`
- `DISASTER_RECOVERY.md` (referenciado em README linha 258)
- `GC097_QA_GATE_PRE_DEPLOY.md`
- `GITHUB_SETTINGS.md`
- `KPI_AGREEMENT.md`
- `MCP_SETUP_GUIDE.md` (referenciado em README linha 256)
- `PAUTA_*.html/md` (2 docs — históricos reuniões)
- `PERMISSIONS_MATRIX.md`
- `RELEASE_LOG.md`
- `RELEASE_PROCESS.md`
- `REPLICATION_GUIDE.md`
- `RESTORE_DATABASE.md`
- `RPC_REGISTRY.md`
- `SITE_MAP.md` (referenciado em README linha 21 + 259)
- `ATA_REUNIAO_TRENTIM_15ABR2026.md`

### 2.4 Suggested INDEX.md replacement (full rewrite)

Estrutura proposta:

```markdown
# Documentação — AI & PM Research Hub

Índice de toda a documentação do projeto.

---

## Para todos
| [../README.md](../README.md) | Visão geral, stack, início rápido |
| [SITE_MAP.md](SITE_MAP.md) | Mapa do site & access tiers (trilingual) |

## Para desenvolvedores
| [ARCHITECTURE.md](ARCHITECTURE.md) | Arquitetura do sistema |
| [ADMIN_ARCHITECTURE.md](ADMIN_ARCHITECTURE.md) | Admin panel (21 components) |
| [../CLAUDE.md](../CLAUDE.md) | Project rules (validation, i18n, database, MCP, deploy) |
| [adr/README.md](adr/README.md) | ADRs 0001-0076 (incl. V4 pacote 0004-0009) |
| [reference/V4_AUTHORITY_MODEL.md](reference/V4_AUTHORITY_MODEL.md) | V4 authority audit methodology (anti false-positive) |
| [refactor/DOMAIN_MODEL_V4_MASTER.md](refactor/DOMAIN_MODEL_V4_MASTER.md) | V4 refactor master tracking (concluído 2026-04-13) |

## Para operadores (GP / Deputy)
| [RUNBOOK.md](RUNBOOK.md) | Deploy, pg_cron, email, auth, monitoring |
| [DEPLOY_CHECKLIST.md](DEPLOY_CHECKLIST.md) | Pre-deploy gates |
| [DISASTER_RECOVERY.md](DISASTER_RECOVERY.md) | Backup & recovery |
| [RESTORE_DATABASE.md](RESTORE_DATABASE.md) | DB restore procedure |
| [GOVERNANCE_CHANGELOG.md](GOVERNANCE_CHANGELOG.md) | GC-001 → GC-141+ |
| [RELEASE_LOG.md](RELEASE_LOG.md) | Release log per session |
| [PERMISSIONS_MATRIX.md](PERMISSIONS_MATRIX.md) | Action × kind × role matrix |
| [MCP_SETUP_GUIDE.md](MCP_SETUP_GUIDE.md) | MCP server setup |

## Specs (por feature/onda)
| [specs/](specs/) | 19 specs — engagement welcome email, weekly digest, frontiers newsletter, selection dual ranking, sync-artia 7-blocks, PMI Journey V4 review, etc. |

## Audits
| [audit/](audit/) | 22 docs — RPC body drift, route inventory, table drift, LGPD ROPA, technical debt |

## Strategy
| [strategy/](strategy/) | Strategic audits (ARM pillars P107, cycle3→cycle4 cohort prep, omega-A docs audit p134) |

## Drafts (em curso, HTML staging)
| [drafts/](drafts/) | IP policy v2.7 handoff, governance review emails, blog outlines |

## Research
| [research/](research/) | Peer review briefings, raises-the-bar validation |

## Council (multi-agent review)
| [council/README.md](council/README.md) | 12 sub-agents em 3 tiers |
| [council/decisions/](council/decisions/) | Decision log de revisões estratégicas |

## Planning & Tracking
| [BACKLOG.md](BACKLOG.md) | Ponteiro: GitHub Issues + memory log + ADRs + handoffs |

---

## Convenções

- **GC-XXX:** Governance Changelog entry — decisão estrutural documentada
- **CR-XXX:** Change Request — proposta de mudança pendente de aprovação
- **S-XXX:** Sprint/spec identifier (ex: S-SENTRY-1, S-RM1)
- **W-XXX:** Work item identifier (ex: W106, W139)
- **ADR-XXXX:** Architecture Decision Record (4-digit, sequential)
- **H-X:** Horizon item (H3, H4 = short/medium-term goals)
- **p<NNN>:** Session number (handoff_p<NNN>.md em `~/.claude/projects/.../memory/`)
```

---

## 3. Wiki — top 10+ pages a atualizar

**Status global**: 40 pages total, **40/40 stale** (>14 d). Mais recente: `2026-04-18 18:52` (`STATUS_REPORT.md`). Oldest: `2026-04-14 11:38`. Significa que o `sync-wiki` cron (provavelmente desabilitado ou nunca rodou após 2026-04-18) não está pegando upstream changes — wiki repo `nucleo-ia-gp/wiki` (Obsidian vault) ou `frameworks` (public).

### 3.1 Pages mais antigas (top 20 — ordenadas por last_update ASC)

| Path | Title | Last update | Sugestão de refresh |
|---|---|---|---|
| `README.md` | Núcleo de IA em Gestão de Projetos — Wiki | 2026-04-14 | Re-sync upstream wiki repo |
| `governance/adr/ADR-0001-source-of-truth-and-cycle-history.md` | ADR-0001 | 2026-04-14 | Re-sync (sem mudança no source ADR-0001 confirma) |
| `governance/adr/ADR-0002-role-model-v3-...md` | ADR-0002: Role Model V3 | 2026-04-14 | Marcar como "substituído por ADR-0007" — atualizar summary |
| `governance/adr/ADR-0003-admin-analytics-...md` | ADR-0003 | 2026-04-14 | Re-sync |
| `governance/adr/ADR-0004-multi-tenancy-posture.md` | ADR-0004 | 2026-04-14 | Re-sync |
| `governance/adr/ADR-0005-initiative-as-domain-primitive.md` | ADR-0005 | 2026-04-14 | Re-sync |
| `governance/adr/ADR-0006-person-engagement-identity-model.md` | ADR-0006 | 2026-04-14 | Re-sync |
| `governance/adr/ADR-0007-authority-as-engagement-grant.md` | ADR-0007 | 2026-04-14 | Re-sync |
| `governance/adr/ADR-0008-per-kind-engagement-lifecycle.md` | ADR-0008 | 2026-04-14 | Re-sync |
| `governance/adr/ADR-0009-config-driven-initiative-kinds.md` | ADR-0009 | 2026-04-14 | Re-sync |
| `governance/adr/README.md` | ADR Index | 2026-04-14 | **Re-sync URGENTE** — falta ADR-0010..0076 (66 ADRs ausentes!) |
| `platform/README.md` | Plataforma | 2026-04-14 | Re-sync — provavelmente menciona stack pré-V4 |
| `research/README.md` | Research | 2026-04-14 | Re-sync |
| `governance/ip-policy.md` | Politica de Publicacao e PI | 2026-04-14 | **Re-sync URGENTE** — IP policy v2.7 foi shipped p128 D1; wiki tem versão pré-Roberto |
| `governance/manual.md` | Manual de Governanca e Operacoes | 2026-04-14 | Re-sync |
| `governance/volunteer-term.md` | Termo de Voluntariado — Template | 2026-04-14 | **Re-sync URGENTE** — Termo Voluntário tem revisão pendente Roberto (5 comments p128) |
| `tribes/tribo-1-radar-tecnologico.md` | Tribo 1: Radar Tecnologico | 2026-04-14 | Re-sync |
| `tribes/tribo-2-agentes-autonomos.md` | Tribo 2: Agentes Autonomos | 2026-04-14 | Re-sync |
| `tribes/tribo-4-cultura-change.md` | Tribo 4: Cultura & Change | 2026-04-14 | Re-sync |
| `tribes/tribo-5-talentos-upskilling.md` | Tribo 5: Talentos & Upskilling | 2026-04-14 | Re-sync |

### 3.2 Pages mais recentes (top 10 — ordenadas por last_update DESC)

| Path | Domain | Last update |
|---|---|---|
| `STATUS_REPORT.md` | governance | 2026-04-18 |
| `2026-04-17.md` | governance | 2026-04-17 |
| `strategy/trentim-tech-collaboration.md` | governance | 2026-04-16 |
| `strategy/benchmark-trentim-mindmap.md` | governance | 2026-04-16 |
| `strategy/3-caminhos-framework.md` | governance | 2026-04-16 |
| `governance/strategic-direction-3-paths.md` | governance | 2026-04-16 |
| `partnerships/strategic-mentors.md` | partnerships | 2026-04-16 |
| `partnerships/README.md` | partnerships | 2026-04-15 |
| `partnerships/aipm-ambassadors.md` | partnerships | 2026-04-15 |
| `platform/canva-mcp-integration.md` | platform | 2026-04-15 |

### 3.3 Recomendação operacional

Wiki sync defer para fora desta sweep — **investigar `sync-wiki` EF logs**:
1. Verificar `mcp__supabase__get_logs` para EF `sync-wiki` (ver se cron ainda dispara).
2. Verificar se cron job correspondente foi desativado (não vi `sync-wiki-*` em `cron.job` lista — só 34 jobs, nenhum prefixo wiki).
3. **Hipótese**: cron foi descontinuado em algum momento entre 2026-04-18 e hoje (3 semanas). Re-habilitar OU executar `sync-wiki` manualmente uma vez para flush backlog.
4. Pages críticas para forçar re-sync prioritário: `governance/adr/README.md` (66 ADRs faltando), `governance/ip-policy.md` (v2.7 shipped p128), `governance/volunteer-term.md` (revisão Roberto p128).

---

## 4. ADRs (0070+) cross-ref status

| ADR | Title | Status | Linked from INDEX? | Linked from adr/README? | Linked from README? |
|---|---|---|---|---|---|
| ADR-0070 | external-speaker-artifact-conventions | Accepted | Não | Sim (linha 76) | Não |
| ADR-0071 | member-lifecycle-state-machine (ARM-9) | Accepted | Não | Sim (77) | Não |
| ADR-0072 | arm1-lead-capture-funnel | Accepted | Não | Sim (78) | Não |
| ADR-0073 | issue116-calendar-booking-sync-apps-script | Accepted | Não | Sim (79) | Não |
| ADR-0074 | onda3-arm-dual-model-ai-architecture | Accepted | Não | Sim (80) | Não |
| ADR-0075 | cv-extraction-pipeline | Accepted (2026-05-07) | Não | Sim (81) | Não |
| **ADR-0076** | **pmi-3d-volunteer-model-and-phase-b-base-legal** | **PROPOSED (p125)** | **Não** | **NÃO — gap** | **Não** |

### 4.1 Recomendações ADR cross-ref

1. **README.md**: README **não linka nenhum ADR individualmente** — apenas referencia "GC-001 → GC-135+" via GOVERNANCE_CHANGELOG.md (linha 200). Considerar adicionar link `[docs/adr/](docs/adr/)` na seção "Documentation" (linha 248-261).
2. **adr/README.md**: adicionar entry para ADR-0076 (mesmo PROPOSED, marca pendência) — ver texto sugerido em §2.1 acima.
3. **INDEX.md**: substituir `(ADR-0001..0010)` por `(ADR-0001..0076)` ou simplesmente `(76 ADRs incluindo Domain Model V4 pacote)`.

---

## 5. CLAUDE.md — discrepâncias state real vs documented

| Item | Documented | Real | Status |
|---|---|---|---|
| MCP server tools count | Não menciona explicitamente em CLAUDE.md (delegado a `.claude/rules/mcp.md`) | 284 (per p133) | OK por design (anti-bloat) |
| `.claude/rules/mcp.md` linha 9 | `283 tools + 4 prompts + 3 resources (p117 +get_extraction_health)` | **284 tools** (per handoff p133 v2.69.0) | **Drift +1**: precisa atualizar |
| AI Model | Claude Opus 4.7 (`claude-opus-4-7`), released 2026-04-16 | Confirma per env (`Opus 4.7 (1M context)`) | OK |
| Domain Model V4 | concluído 2026-04-13 — 6 ADRs (0004-0009), 30 migrations, 7 fases | Confirma per `docs/refactor/DOMAIN_MODEL_V4_MASTER.md` | OK |
| Stack | Astro v6 (Cloudflare Workers) · Supabase · Worker `pmi-vep-sync` (wrangler 4.x) | Confirma | OK |
| Supabase ref | `ldrfrvwhxsmgaabwmaik` (sa-east-1) | Confirma | OK |
| Council | 12 sub-agents em 3 tiers, ativo desde 2026-04-18 | Confirma (`.claude/agents/`) | OK |
| LGPD | Art. 18 cycle complete | Confirma + ADR-0076 amplia para Art. 7 IX | Adicionar nota: "Art. 7 IX base legal Phase B em ADR-0076 PROPOSED" |
| Strategic anchor PMIS | **Não mencionado** em CLAUDE.md | Per `memory/project_chapter_pmis_saas_vision_p133.md` (STRATEGIC ANCHOR p133) | **Considerar adicionar** uma linha curta sob "Platform" |

### 5.1 Sugestão minimalista (1 linha extra)

CLAUDE.md linha 17 (após LGPD): adicionar:

```
- **Strategic posture (p133+):** Codebase é vertical PMIS/SaaS substrate para PMI chapters globais — multi-client by design (whitelabel-ready). Ver `memory/project_chapter_pmis_saas_vision_p133.md`.
```

### 5.2 `.claude/rules/mcp.md` linha 9 fix

Substituir:

```
- **283 tools + 4 prompts + 3 resources** (p117 +get_extraction_health for ADR-0075 observability; was 266 post p106 #97 W3 G4; ...)
```

por:

```
- **284 tools + 4 prompts + 3 resources** (p133 v2.69.0 +get_extraction_health p117 ADR-0075 observability; was 283 p117; was 266 post p106 #97 W3 G4; was 217 = 141R + 76W at p77 marathon close — R/W split tracking dropped p106 since heuristic unreliable; total + canonical commit log replaces it)
```

---

## 6. Recommended apply order (pra main loop)

| Prioridade | Doc | Mudança | Esforço | Risco |
|---|---|---|---|---|
| **P0 — High** | `README.md` | 13 stat fixes (266→284, 32→35, etc.) + Key Numbers table replacement | ~10 min Edit ops | Baixo (factual) |
| **P0 — High** | `docs/adr/README.md` | Adicionar ADR-0076 entry (1 linha após ADR-0075) | <1 min | Baixo |
| **P1 — Med** | `docs/INDEX.md` | Full rewrite (ver §2.4) | ~5 min Write | Baixo (informacional) |
| **P1 — Med** | `.claude/rules/mcp.md` | linha 9: 283→284 + atualizar history | <1 min | Baixo |
| **P2 — Low** | `CLAUDE.md` | adicionar 1 linha Strategic posture (opcional) | <1 min | Baixo (PM call) |
| **P3 — Defer** | `wiki_pages` (DB) | Investigar `sync-wiki` cron health, executar manual sync, wiki repo upstream | ~30 min investigação | Médio (touch infra) |
| **P3 — Defer** | `README.md` Architectural posture nota | Adicionar parágrafo V4 + PMIS anchor (opcional) | ~3 min | Baixo (PM call) |

### 6.1 Rationale priorização

- **P0 README + adr/README**: facts visíveis publicamente (badge MCP-266 está errado em hero do repo). Fix é mecânico.
- **P1 INDEX**: atualmente quase inútil (44 L) — rewrite expande utilidade ~3x sem touch em código.
- **P2 CLAUDE strategic anchor**: opcional, depende se PM quer "PMIS vision" no on-boarding context (vs deferir a memory file).
- **P3 wiki**: deferida porque é problema de **infra cron health**, não doc drift. Não bloqueia outras frentes Ω-A.

### 6.2 Não recomendado nesta sweep

- **NÃO** rewrite parágrafo "Founded in 2024" sem confirmação humana (preciso fonte primária).
- **NÃO** auto-sync wiki (precisa investigar primeiro se cron foi desabilitado intencionalmente — pode ter razão LGPD ou IP track).
- **NÃO** linkar todos os ADRs individualmente em README (sobrecarrega) — manter pointer para `docs/adr/README.md` é suficiente.

---

## Anexo A — Comandos de verificação executados

| Comando | Resultado |
|---|---|
| `wc -l README.md INDEX.md CLAUDE.md` | 270 / 44 / 80 |
| `ls docs/adr/` | 77 ADR files (0001-0076 + README) |
| `grep -c "mcp.tool(" supabase/functions/nucleo-mcp/index.ts` | **284** |
| `ls supabase/functions/ \| grep -v _shared \| wc -l` | **35** |
| `SELECT COUNT(*) FROM cron.job WHERE active=true` | **34** ativos |
| `SELECT COUNT(*) FROM pg_proc WHERE pronamespace='public'::regnamespace AND prokind='f'` | **795** |
| `SELECT COUNT(*) FROM wiki_pages WHERE updated_at < now()-'14d'` | **40/40** stale |
| `grep -oE "GC-1[0-9][0-9]" docs/GOVERNANCE_CHANGELOG.md \| sort -u \| tail -5` | GC-141 (highest) |

## Anexo B — Inventário docs/ subdirs (atual)

```
docs/
├── adr/             (77 files: ADR-0001..0076 + README + ADR-0022 JSON catalog)
├── archive/         (May 5 — não inspecionado)
├── audit/           (22 docs)
├── blog/            (2 docs)
├── council/         (decision logs + README)
├── drafts/          (8 docs)
├── editorial/       (1 doc — CONTENT_PIPELINE_PLAYBOOK)
├── instrumentos-ip/ (4 HTML drafts)
├── migrations/      (Mar 26 — legado)
├── project-governance/ (Mar 26 — legado)
├── refactor/        (5 docs)
├── reference/       (1 doc — V4_AUTHORITY_MODEL.md)
├── reports/         (2 docs)
├── research/        (2 docs)
├── scripts/         (1 file — extract_pmi_volunteer.js)
├── sessions/        (vazio)
├── specs/           (19 docs incl. p90-comms/ subdir)
├── strategy/        (5 docs — incluindo este p134_omega_a_docs_audit.md)
└── (top-level *.md ~30 docs)
```

---

**Fim do relatório.** Sweep Ω-A — docs-refresher agent. Read-only — nenhum arquivo source editado.
