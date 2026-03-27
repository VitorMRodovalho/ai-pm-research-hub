# BRANCH_ENFORCEMENT.md

Guia curto de enforcement para branches críticas (`main` e `dev`).

## Objetivo

Padronizar o gate mínimo de qualidade e rastreabilidade antes de integração/deploy.

## Branches cobertas

- `main`
- `dev`

## Checks obrigatórios recomendados

1. **CI Validate / quality_gate**
   - depende de:
     - `validate` (unit tests + build + smoke routes)
     - `browser_guards` (Playwright guard)
2. **Issue Reference Gate / issue_reference_gate**
   - exige referência de issue para alterações em trilha crítica.

## Como aplicar no GitHub (Branch protection)

Para cada branch (`main` e `dev`):

1. Settings -> Branches -> Add branch protection rule.
2. Marcar:
   - Require a pull request before merging (quando PR workflow for obrigatório no time).
   - Require status checks to pass before merging.
3. Selecionar checks:
   - `quality_gate`
   - `issue_reference_gate`
4. (Opcional recomendado) Require branches to be up to date before merging.

## Racional

- `quality_gate` garante que testes/build/smoke/browser guard passaram.
- `issue_reference_gate` garante trilha de auditoria por issue.
- Cobertura em `dev` evita que regressão acumule antes de promoção para `main`.
