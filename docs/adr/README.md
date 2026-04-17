# ADR Index

Este diretório separa decisões técnicas duráveis das notas de governança geral.

## Como usar

- Cada ADR deve focar em uma decisão arquitetural específica.
- O formato é curto: contexto, decisão, consequências.
- Quando a decisão mudar, criar um novo ADR que substitui o anterior (não reescrever histórico).

## ADRs ativos

- `ADR-0001-source-of-truth-and-cycle-history.md` — Hub como fonte única de verdade + separação snapshot/histórico.
- `ADR-0002-role-model-v3-operational-role-and-designations.md` — Modelo v3 (substituído por ADR-0007).
- `ADR-0003-admin-analytics-internal-readonly-surface.md` — `/admin/analytics` como leitura interna sem abrir trilhas de escrita.
- `ADR-0010-wiki-scope-narrative-knowledge-only.md` — Fronteira wiki vs SQL: wiki só para conhecimento narrativo (ADRs, governança), dados operacionais ficam em SQL.
- `ADR-0011-v4-auth-pattern-rpcs-mcp.md` — `can()` / `can_by_member()` é a única fonte de verdade de autoridade em todas as camadas (RPC, MCP, RLS). Padrão canônico pós-V4, substitui role list hardcoded.

## Domain Model V4 — Refatoração Arquitetural (Complete, 2026-04-13)

Pacote coeso que refez o modelo de domínio para habilitar: plataforma nacional, multi-org, governança máxima, LGPD by design, e extensibilidade via configuração. Deve ser lido em ordem.

- `ADR-0004-multi-tenancy-posture.md` — Organizations como entidade first-class.
- `ADR-0005-initiative-as-domain-primitive.md` — Initiative substitui Tribe como contêiner raiz.
- `ADR-0006-person-engagement-identity-model.md` — Person + Engagement substituem members catch-all.
- `ADR-0007-authority-as-engagement-grant.md` — Autoridade derivada de engagements ativos (substitui ADR-0002).
- `ADR-0008-per-kind-engagement-lifecycle.md` — Lifecycle e base legal LGPD como config por kind.
- `ADR-0009-config-driven-initiative-kinds.md` — Extensibilidade por configuração, não por código.

**Histórico de execução:** ver `docs/refactor/DOMAIN_MODEL_V4_MASTER.md`. Concluído em 7 fases, 30 migrations, 2026-04-11 → 2026-04-13.

## Processo mínimo

1. Criar novo ADR em `docs/adr/`.
2. Atualizar este índice.
3. Registrar o sprint em `docs/RELEASE_LOG.md` e `docs/GOVERNANCE_CHANGELOG.md`.
