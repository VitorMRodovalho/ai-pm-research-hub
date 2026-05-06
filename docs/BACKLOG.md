# Backlog — Onde rastrear o quê

> Este arquivo é um **ponteiro**, não um backlog. O backlog operacional vive em GitHub Issues.
> Snapshot histórico do antigo `BACKLOG.md` (v2.9.4, 09/Abr/2026) preservado em
> [`archive/BACKLOG_v2.9.4_snapshot_2026-04-09.md`](archive/BACKLOG_v2.9.4_snapshot_2026-04-09.md).

---

## Fontes de verdade

| O que você procura | Onde está | Como acessar |
|---|---|---|
| **Bugs / features / tasks acionáveis** (com prioridade, tipo, label) | GitHub Issues | `gh issue list --state open --label "priority:high"` |
| **Contexto cross-session** (gaps de design, oportunidades, dívida técnica não-issuável) | Memory (Claude Code) | `memory/project_issue_gap_opportunity_log.md` |
| **Decisões arquiteturais** (immutable, com rationale) | ADRs | `docs/adr/ADR-NNNN-*.md` (70 ADRs) |
| **Estado da última sessão** (handoff entre conversas) | Memory (Claude Code) | `memory/handoff_p<N>_*.md` (mais recente) |
| **Roadmap estratégico de longo prazo** (3 Paths Trentim, Detroit, LIM) | Memory + council decisions | `memory/project_nucleo_*.md` + `docs/council/decisions/` |
| **Specs em execução** | docs/specs | `docs/specs/p<N>-*.md` |

---

## Comandos rápidos

```bash
# HIGH priority abertas
gh issue list --state open --label "priority:high"

# Todas governance-tagged
gh issue list --state open --label "governance"

# Issues criadas nas últimas 2 semanas
gh issue list --state open --search "created:>$(date -d '2 weeks ago' +%Y-%m-%d)"

# Contagem por prioridade
gh issue list --state open --json labels --jq '[.[].labels[].name] | group_by(.) | map({label:.[0], count:length}) | .[] | select(.label | startswith("priority:"))'
```

---

## Fluxo de criação

1. **Bug acionável ou feature definida?** → GitHub Issue com labels `priority:*`, `type:*`, `governance` (se aplicável)
2. **Gap de design / oportunidade ainda fluida?** → linha em `memory/project_issue_gap_opportunity_log.md`
3. **Decisão estrutural?** → novo ADR seguindo template `docs/adr/`
4. **Trabalho de longo prazo / multi-sessão?** → handoff doc no fim da sessão

---

## Convenções

- **Issue labels:** `priority:high|medium|low` · `type:bug|feature|task` · `governance` (cross-cuts)
- **Status flags:** `status:blocked` · `status:in-progress` (raramente usado — preferimos comentário)
- **Memory log decay:** entradas resolvidas viram `[x] **RESOLVIDO** (commit hash)` — não delete, dá histórico
- **ADR numbering:** sequencial (ADR-0070+ próximos), nunca renumere

---

## Ver também
- [INDEX.md](INDEX.md) — toda a documentação
- [adr/README.md](adr/README.md) — decisões arquiteturais
- [council/README.md](council/README.md) — multi-agent council structure
