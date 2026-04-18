# Núcleo IA Council — Multi-agent review structure

**Status:** Active since 2026-04-18 (sessão p27)
**Approved by:** Vitor Rodovalho (PM, Núcleo IA)
**Rationale:** Preservar optionality dos 3 caminhos Trentim (A PMI-internal / B consulting / C community) enquanto plataforma escala para multi-capítulos e prepara LIM/Detroit/whitepaper.

## O que é

Council é um conjunto de **12 sub-agents especializados** (em `.claude/agents/`) que funcionam como conselheiros por domínio. Invocação é **tiered** para não pesar o projeto:

```
Tier 1 (always):     platform-guardian + code-reviewer
Tier 2 (triggered):  council members invocados conforme domínio da mudança
Tier 3 (strategic):  /council-review full sweep em milestones
```

Cada agent é **conselheiro, não executor**. Outputs são documentos markdown com veredito, rationale, e ações recomendadas. Main loop (Claude no driver seat) decide qual ação tomar.

## Composição (12 agents)

### Business & Product (4)
| Agent | Scope |
|---|---|
| `product-leader` | Priorização, roadmap, trade-offs UX vs dívida técnica, métricas de sucesso |
| `ux-leader` | Friction audit, journey maps, onboarding, progressive disclosure, mobile/a11y |
| `c-level-advisor` | Visão 3-5 anos, sustentabilidade, optionality A/B/C, positioning LIM/Detroit |
| `stakeholder-persona` | Rotating: gp-leader / active-volunteer / sponsor-liaison — voz do usuário real |

### Tech (4)
| Agent | Scope |
|---|---|
| `senior-software-engineer` | Code quality, SOLID, maintainability, test coverage, refactor hygiene |
| `ai-engineer` | MCP tools, prompts, Claude SDK patterns, RAG, agent orchestration |
| `data-architect` | Schema, invariants, performance, analytics arquitetura |
| `security-engineer` | LGPD, auth, RLS, PII, OWASP |

### Advisory (4 — on-demand)
| Agent | Scope |
|---|---|
| `startup-advisor` | GTM, parcerias, positioning community↔commercial, MVP discipline |
| `vc-angel-lens` | Scale, moat, monetization, capital efficiency, pitch readiness |
| `legal-counsel` | IP, LGPD, direito autoral BR, termos, acordos (output PT-BR) |
| `accountability-advisor` | PMI governance conformity, risk, audit readiness, chapter impact |

## Quando invocar cada tier

### Tier 1 (automático)
- `platform-guardian`: início/fim de sessão tocando SQL/RPC/MCP
- `code-reviewer`: mudanças em código de negócio

### Tier 2 (domain-triggered)

**Mudança dispara agent(s)**:

| Tipo de mudança | Agents relevantes |
|---|---|
| DB migration nova | `data-architect` + (`security-engineer` se toca PII/RLS) |
| Nova MCP tool | `ai-engineer` + `senior-software-engineer` + (`security-engineer` se PII) |
| UI/frontend change | `ux-leader` + (`stakeholder-persona` se afeta journey) |
| Auth/consent flow | `security-engineer` + `legal-counsel` |
| Policy/terms doc | `legal-counsel` + `accountability-advisor` + (`c-level-advisor` se institutional) |
| Refactor grande (>400 LOC) | `senior-software-engineer` + `product-leader` (ROI) |
| Parceria/spinoff | `c-level-advisor` + `startup-advisor` + `accountability-advisor` |
| Fundraising/monetização | `vc-angel-lens` + `startup-advisor` + `c-level-advisor` |

### Tier 3 (strategic)
Invocar `/council-review [topic]` em milestones:
- Pre-launch: entrada de novo capítulo, CPMAI launch, feature major
- Pre-submission: LIM abstract, whitepaper, PMI Global Summit
- Audit periódico: Q1/Q2 platform sweep, governance review anual
- Pivot consideration: mudança de path Trentim A↔B↔C

Output agregado em `docs/council/YYYY-MM-DD-topic.md`.

## Circuit breaker

Se um agent é invocado **>5x por semana** sem delivery resultante, há scope creep. Alerta para `product-leader` fazer triagem.

Se o council produz **memo mas nada é executado em 30 dias**, indica decisão parada. `c-level-advisor` reavalia prioridade.

## Decision log format

Toda decisão major resultante de council review vira entrada em `docs/council/decisions/YYYY-MM-DD-decision-slug.md`:

```markdown
# Decision: [título]

**Date:** YYYY-MM-DD
**Status:** Proposed | Accepted | Deprecated | Superseded
**Context:** 1-2 parágrafos
**Council members consulted:** agent-1, agent-2
**Path impact (Trentim A/B/C):** preserva / neutro / fecha

## Recommendation
[council's merged view]

## Alternatives considered
[what else was on the table + why not]

## Consequences
[good / bad / risks]

## Next steps
[action items com owner]
```

## Como invocar

### Via Claude Code main loop
Main loop decide Tier 2 automaticamente. Você pode dizer:

> "Audite esta migration via data-architect e security-engineer"
> "Revise este doc IP com legal-counsel e accountability-advisor"
> "Council review full da plataforma"

### Via Agent tool (direto)
```
Agent({
  description: "data-architect review of migration",
  subagent_type: "data-architect",
  prompt: "Review supabase/migrations/20260428090000_*.sql ..."
})
```

### Parallel dispatch
Para Tier 3 (strategic), invocar múltiplos agents em paralelo via single message com múltiplas `Agent` calls.

## Princípios

1. **Conselho não bloqueia execução trivial** — PR de 10 linhas não precisa council
2. **Disagreement é feature, não bug** — council members podem discordar; `c-level-advisor` ou `product-leader` faz tie-break conforme domínio
3. **Output é artefato reutilizável** — decisions viram reference para próximas sessões
4. **Agents evoluem** — após 3 meses, review qual agent foi útil e ajustar mandates
5. **Humano no loop** — council é **consultivo**, Vitor/PM é decisão final sempre

## Referências

- Padrões estudados: LangGraph multi-agent, CrewAI, AutoGen, Anthropic Computer Use / Project Vend
- Governance patterns: Rust RFC process, Kubernetes SIGs, Python PEP, CNCF Technical Oversight
- Academic: Du et al. (2023) "Improving Factuality and Reasoning in Language Models through Multiagent Debate"

## Roadmap do council

- ✅ **Phase 0 (2026-04-18)**: 12 agents specs created, tiering documentado
- ⏸ **Phase 1**: Primeiro `/council-review platform-audit` pós-Phase-5 Option A completion
- ⏸ **Phase 2**: Decision log popular com 3-5 decisões de milestones passados para referência
- ⏸ **Phase 3**: After 3 months of use, retrospective — quais agents foram úteis, quais overhead
