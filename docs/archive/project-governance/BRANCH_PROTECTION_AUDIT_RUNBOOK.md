# BRANCH_PROTECTION_AUDIT_RUNBOOK.md

Runbook operacional para auditar branch protection em `main` e `dev`.

## Objetivo

Garantir que os gates definidos no projeto estejam realmente aplicados no GitHub:

- `quality_gate`
- `issue_reference_gate`

## Execução manual

```bash
scripts/audit_branch_protection.sh
```

Opcional (repo custom):

```bash
scripts/audit_branch_protection.sh owner/repo
```

## Resultado esperado

Para `main` e `dev`, a resposta de proteção deve mostrar:

1. `required_status_checks` ativo;
2. checks contendo:
   - `quality_gate`
   - `issue_reference_gate`;
3. política de PR/review conforme padrão do time.

## Frequência recomendada

- semanal;
- após alterações em workflows;
- após ajustes de governança no GitHub.

## Evidência mínima

- output do script;
- data/hora;
- branch auditada;
- referência no `docs/RELEASE_LOG.md`.
