# p201 Parallel Agent Roadmap

**Data:** 2026-05-19  
**Status:** Adopted (ratificado em 2026-05-19 — issue #159, p202)  
**Fonte de contexto:** `docs/audit/P201_MCP_ARCHITECTURE_AUDIT.md`, `docs/audit/P162_GAP_OPPORTUNITY_LOG.md`, `docs/RELEASE_LOG.md`, `docs/GOVERNANCE_CHANGELOG.md`

---

## 1. Objetivo

Permitir que Claude Code, Cursor, Codex, Gemini e outros agentes/modelos trabalhem em paralelo no mesmo projeto sem quebrar governança, auditabilidade, RLS, migrations ou documentação institucional.

O objetivo não é maximizar alterações simultâneas. O objetivo é maximizar **trabalho paralelo isolado, rastreável e reversível**.

---

## 2. Princípios de Operação

1. **Uma issue por agente.** Nenhum agente começa trabalho sem issue/escopo explícito.
2. **Um worktree/branch por agente.** Agentes não compartilham a mesma working tree.
3. **Um domínio por branch.** Evitar misturar SQL/RPC, frontend, docs e infra no mesmo PR.
4. **Main loop decide.** Subagentes/modelos são consultivos ou executores isolados; PM/main loop decide merge/deploy.
5. **Sem DDL invisível.** Toda alteração SQL aplicada em produção precisa ter migration, registro no release log e rollback.
6. **Sem deploy direto por agente secundário.** Deploy, Cloudflare rules e `supabase migration repair` exigem aprovação explícita.
7. **Runtime evidence > opinião.** Bugs só são fechados com evidência de logs, smoke ou reprodução validada.

---

## 3. Modelo de Lanes

| Lane | Escopo | Pode tocar | Não pode tocar |
|---|---|---|---|
| Foundation | DB, RPC, RLS, migrations, invariants | `supabase/`, `tests/contracts/`, `docs/migrations/` | UI, copy, design |
| Frontend | Astro/React/i18n/nav | `src/pages/`, `src/components/`, `src/i18n/`, `src/lib/navigation.config.ts` | DB schema sem spec |
| MCP/AI | MCP tools, prompts, resources, AI functions | `supabase/functions/nucleo-mcp/`, AI EFs, MCP docs | RLS/migrations sem Foundation review |
| Governance | ADR, release, audit, runbooks | `docs/`, `AGENTS.md`, `README*` | App behavior |
| Infra/Security | Cloudflare, CI, Supabase local, WAF | `.github/`, `wrangler.toml`, Cloudflare/Supabase config docs | Product UI |
| QA | smoke, tests, contracts, route inventory | `tests/`, `scripts/`, QA docs | Production DDL |

### Mapeamento Lane → Labels GitHub (ratificado #159, p202)

Cada lane usa um label primário existente. Não foram criados labels `lane:*` dedicados para evitar abstração nova sem necessidade comprovada.

| Lane | Label primário | Labels secundários comuns |
|---|---|---|
| Foundation | `data-integrity` | `audit-trail`, `certificates` |
| Frontend | `ux` | (none) |
| MCP/AI | `mcp-server` | (none) |
| Governance | `governance` | `documentation` |
| Infra/Security | `infrastructure` | (none) |
| QA | `audit` | (none) |

**Promotion rule (PM #159, 2026-05-19):** se a ambiguidade do mapeamento atrapalhar triagem dentro de 1 sprint pós-adoption (ex.: confusão entre `data-integrity` puramente de DB e `data-integrity` como sinônimo de Foundation lane), promover para labels `lane:foundation`, `lane:frontend`, `lane:mcp-ai`, `lane:governance`, `lane:infra-security`, `lane:qa` dedicados e migrar as issues do programa p201 (#159-#166). Trigger: PM ou main loop observa friction em triage; decisão registrada em commit subsequente + atualização desta tabela.

---

## 4. Handoff Obrigatório por Agente

Cada agente deve entregar:

- Issue trabalhada.
- Branch/worktree.
- Arquivos tocados.
- Decisões tomadas.
- Evidência runtime ou teste.
- Riscos e rollback.
- Documentos atualizados.
- Pendências e bloqueios.

Formato mínimo:

```md
## Handoff

Issue:
Branch:
Escopo:
Arquivos:
Validação:
Riscos:
Rollback:
Docs:
Próximo passo:
```

---

## 5. Gates Antes de Merge

| Tipo de mudança | Gate mínimo |
|---|---|
| SQL/RPC/RLS | `check_schema_invariants()`, RPC smoke, migration + rollback, `NOTIFY pgrst` quando assinatura muda |
| Frontend | lint no arquivo, `npm run build`, route smoke quando rota muda |
| i18n | três dicionários atualizados |
| MCP | `tools/list`/`/health`, tool smoke, `mcp_usage_log` sem falha nova |
| Cloudflare | Security Events antes/depois, Ray ID, regra documentada |
| Docs | links válidos, sem contagens defasadas contra pins canônicos |

---

## 6. Backlog Priorizado para Execução Paralela

### P0 — Volunteer Lifecycle Orchestration

- Executar a spec `docs/project-governance/P202_VOLUNTEER_LIFECYCLE_REMEDIATION_SPEC.md`.
- Usar o pack `docs/audit/P202_VOLUNTEER_LIFECYCLE_SQL_AUDIT.md` como baseline read-only antes/depois.
- Unificar aprovação de candidatos em uma RPC canônica usada por UI, bulk actions e MCP.
- Garantir que aprovação gere `members`, `persons`, `engagements`, onboarding, notification e agreement queue.
- Persistir prova de contra-assinatura (`counter_signature_hash`) e corrigir evidências do termo antes de claims formais de não-repúdio.
- Criar matriz de transições lifecycle para termo, renovação, pending-authority e offboarding.

### P1 — Permission/Tiers/RLS

- Resolver estado de autoridade pendente de Herlon (`study_group_owner/leader`).
- Auditar gates `hasPermission(...)` em superfícies sensíveis e migrar para `canFor(...)` quando a decisão é V4/scoped.
- Criar smoke tests de personas: Roberto, Sarah, Marcos, Herlon, leader genérico, curator, chapter_liaison.

### P1 — MCP Contract Matrix

- Gerar matriz 293 tools:
  - tool;
  - domínio;
  - RPC/tabela;
  - gate;
  - output shape;
  - drift flags;
  - smoke test.
- Regenerar `tool-reference` ou trocar por resource derivado de runtime.

### P1 — Cloudflare MCP Access

- Criar regra Cloudflare de skip para Browser Integrity/Bot checks em:
  - `/mcp`
  - `/.well-known/oauth-*`
  - `/oauth/*`
- Validar com Security Events e Ray ID real.
- Adicionar rate limit compensatório.

### P1 — Local QA / Migration Drift

- Resolver `supabase start` quebrado por ausência de schema baseline.
- Documentar decisão: QA remoto como padrão vs bootstrap local.
- Reconciliar migration history drift que bloqueia `supabase db push`.

### P2 — Docs/Governance Backfill

- Expandir `RELEASE_LOG.md` p40-p201 além do resumo atual.
- Atualizar `GOVERNANCE_CHANGELOG.md` com entradas detalhadas quando ADRs virarem decisões institucionais.
- Atualizar `docs/SITE_MAP.md`, `docs/INDEX.md`, skills e i18n com contagens MCP atuais ou referência a `tools/list`.

### P2 — Semantic Layer

- ADR para `gamification_points.initiative_id`.
- ADR/decisão para `champion_criteria_catalog`.
- Plano de execução ADR-0015 fases restantes.
- Classificar direct table reads do MCP: aceitar, encapsular em RPC, ou retirar.

---

## 7. Issues Sugeridas

Issues abertas:

| Issue | Título | Lane |
|---|---|---|
| #159 | `gov: p201 parallel agent operating model` | Governance |
| #160 | `permissions: resolve Herlon study_group_owner authority state` | Foundation/Governance |
| #161 | `permissions: audit sensitive UI gates against V4 canFor` | Frontend/Foundation |
| #162 | `mcp: generate 293-tool contract matrix and refresh tool reference` | MCP/AI |
| #163 | `infra/security: Cloudflare BIC blocks MCP OAuth bootstrap` | Infra/Security |
| #164 | `infra: restore local Supabase QA stack or document remote-only workflow` | Infra/QA |
| #165 | `docs: complete governance and release backfill p40-p201` | Governance |
| #166 | `architecture: semantic layer roadmap for facts dimensions snapshots` | Foundation/Governance |
| #168 | `ops: triage WhatsApp action intake into governed backlog` | Governance/QA |
| #169 | `event/initiative: João Coelho IA & Competências 02 Jun 2026` | Governance/Frontend/Foundation |
| #170 | `mcp: investigate corrupted meeting notes inserted via Claude/MCP` | MCP/AI/Foundation |
| #171 | `access: Ana Carla cannot read governance document` | Governance/Security |
| #172 | `webinars/comms: repact webinar calendar and Sympla lead time` | Governance/Frontend |
| #173 | `member lifecycle: Rogério Peixoto reintegration as observer in Tribe 07` | Foundation/Governance |
| #177 | `governance: issue current volunteer agreements for special engagement kinds` | Foundation/Governance |
| #179 | `selection: canonical approval orchestration for volunteer lifecycle` | Foundation/Frontend |
| #180 | `authority: ensure approved volunteers enter authoritative V4 graph` | Foundation/Governance |
| #181 | `certificates: persist counter-signature proof and agreement evidence` | Foundation/Security |
| #182 | `lifecycle: map agreement notifications renewals and pending-authority campaigns` | Governance/Frontend |
| #183 | `mcp: add canonical lifecycle tools after approval agreement contracts stabilize` | MCP/AI/Foundation |

As issues devem usar os labels existentes:

- `type:bug`
- `type:task`
- `priority:high`
- `priority:medium`
- `governance`
- `mcp-server`
- `infrastructure`
- `data-integrity`
- `ux`
- `audit`

---

## 8. Definição de Done do Programa

O programa p201 estará encerrado quando:

1. Todas as issues P1 tiverem owner e status.
2. MCP contract matrix existir e for reexecutável.
3. Persona smoke tests cobrirem Roberto, Sarah, Marcos e Herlon.
4. Cloudflare MCP bootstrap for validado sem `1010`.
5. `supabase start` tiver decisão documentada ou correção.
6. Docs principais não tiverem drift de contagem contra pins canônicos.
7. Release/governance backfill mínimo estiver aceito.
