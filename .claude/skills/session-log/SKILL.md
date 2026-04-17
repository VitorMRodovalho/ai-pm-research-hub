---
name: session-log
description: Append new items to the consolidated issue/gap/opportunity log e atualiza MEMORY.md. Use no fim de sessão depois do guardian quando novos bugs/gaps/oportunidades foram identificados e precisam ser registrados para handoff. Mandato explícito do PM (2026-04-18) — cada sessão deve atualizar esse log.
user_invocable: true
---

Update the backlog log for handoff between sessions.

## Target files

1. `/home/vitormrodovalho/.claude/projects/-home-vitormrodovalho-Desktop-ai-pm-research-hub/memory/project_issue_gap_opportunity_log.md`
2. `/home/vitormrodovalho/.claude/projects/-home-vitormrodovalho-Desktop-ai-pm-research-hub/memory/MEMORY.md` (se nova sessão memory foi criada)

## Workflow

1. **Inventariar o que mudou nesta sessão:**
   - Read the current log file to see what's already tracked
   - Ask the user (or infer from conversation) which items fall into each bucket:
     - **ISSUE** — bug encontrado (comportamento não-esperado)
     - **GAP** — estrutura ausente (feature incompleta, missing coverage)
     - **OPPORTUNITY** — melhoria identificada (não é bug nem gap, mas ideia valiosa)
     - **BACKLOG** — feature planejada com prioridade (P0/P1/P2/P3)

2. **Para cada novo item:**
   - Phrase como statement acionável
   - Include: what + where (file:line or area) + why it matters
   - Categorizar por severity (P0 urgent / P1 next sprint / P2 nice to have / P3 someday)
   - Se resolvido na sessão: mover para "Resolvidos na sessão DD/Mês"

3. **Edit the log file** — append sob a seção apropriada (ISSUE / GAP / BACKLOG / OPPORTUNITY). Preserve chronological order dentro de cada seção.

4. **Atualizar MEMORY.md index** se nova session memory foi criada nesta sessão — adicionar linha com link + 1-line hook.

## Anti-patterns (não faça)

- Não duplicar item que já existe no log — verificar antes de adicionar
- Não inventar itens sem evidência da sessão — só itens que REALMENTE surgiram
- Não remover itens antigos mesmo se parecerem "stale" — preserve history
- Não marcar algo como "Resolvido" sem confirmar evidência (grep commit, test run, migration applied)

## Formato de output (para o usuário aprovar antes de editar)

Proponha primeiro em markdown:

```
## Proposta de update ao log

### Novos ISSUE
- [ ] ...

### Novos GAP
- [ ] ...

### Novos OPPORTUNITY
- ...

### Resolvidos nesta sessão
- [x] ... (commit `hash`)

### MEMORY.md index update
- Adicionar: `[session_xx_apr.md](...) — resumo`

Confirma para aplicar?
```

Só edite depois de "sim" do usuário.

## Referência

- Log consolidado: `memory/project_issue_gap_opportunity_log.md` (criado 16/Abr, 125 linhas)
- Formato do log: seções ISSUE / GAP / BACKLOG / OPPORTUNITY com P0-P3 e key IDs no final
