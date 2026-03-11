# ADR Index

Este diretório separa decisões técnicas duráveis das notas de governança geral.

## Como usar

- Cada ADR deve focar em uma decisão arquitetural específica.
- O formato é curto: contexto, decisão, consequências.
- Quando a decisão mudar, criar um novo ADR que substitui o anterior (não reescrever histórico).

## ADRs ativos

- `ADR-0001-source-of-truth-and-cycle-history.md` — Hub como fonte única de verdade + separação snapshot/histórico.
- `ADR-0002-role-model-v3-operational-role-and-designations.md` — Modelo v3 com `operational_role` e `designations`.
- `ADR-0003-admin-analytics-internal-readonly-surface.md` — `/admin/analytics` como leitura interna sem abrir trilhas de escrita.

## Processo mínimo

1. Criar novo ADR em `docs/adr/`.
2. Atualizar este índice.
3. Registrar o sprint em `docs/RELEASE_LOG.md` e `docs/GOVERNANCE_CHANGELOG.md`.
