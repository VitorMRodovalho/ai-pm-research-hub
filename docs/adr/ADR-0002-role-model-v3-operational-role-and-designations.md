# ADR-0002: Role Model V3 (operational_role + designations)

- Status: Accepted
- Data: 2026-03-11

## Contexto

O modelo legado com `role`/`roles` gerava ambiguidade entre função operacional e reconhecimento organizacional, além de aumentar custo de ACL em frontend e backend.

## Decisão

1. Adotar `operational_role` e `designations` como modelo oficial.
2. Não introduzir lógica nova com `role`/`roles`.
3. ACL de rotas e ações deve derivar do modelo v3 (com exceções explícitas e auditáveis).

## Consequências

- Menos duplicidade semântica no domínio.
- Melhora previsibilidade de autorização em nav, páginas e RPCs.
- Facilita evolução de tiers/designações sem reabrir dívida técnica legada.
