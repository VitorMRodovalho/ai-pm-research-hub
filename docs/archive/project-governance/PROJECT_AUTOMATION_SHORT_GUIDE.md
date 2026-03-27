# PROJECT_AUTOMATION_SHORT_GUIDE.md

Guia curto de governança para waves/sprints no project + gate de issue linkage.

## Campos mínimos no Project

- Wave
- Sprint
- Module
- SQL Required (ou SQL impact)
- Start date
- End date
- Status

## Fluxo recomendado

1. Criar/ajustar issue com escopo claro e DoD.
2. Vincular issue ao Project com os campos de Wave/Sprint.
3. Mover para `In progress` somente quando houver owner e janela definida.
4. Ao concluir, mover para `Done` e anexar evidências (build/test/smoke/release log).

## Gate automático de issue reference

Workflow: `.github/workflows/issue-reference-gate.yml`

- Dispara em `push` e `pull_request` para `main`/`dev`.
- Se houver mudanças em trilha crítica (`src/`, `supabase/`, `scripts/`, `.github/workflows/` etc), exige referência de issue:
  - `#123`
  - `GH-123`
  - URL de issue do GitHub

Script de validação: `scripts/require_issue_reference.sh`

## Observações

- O gate não substitui review técnico; ele garante rastreabilidade mínima.
- Mudanças apenas documentais fora de trilha crítica não bloqueiam o pipeline.
