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
- `ADR-0012-schema-consolidation-principles.md` — Single source of truth por conceito + cache columns com trigger de sync explícito. Elimina drift silencioso como o caso Wellington 16/Abr (3 colunas para o mesmo status).
- `ADR-0013-log-table-taxonomy.md` — Taxonomia em 5 categorias (Admin Audit / Domain Lifecycle / High-Volume / Distinct Retention / External Ingestion) para decidir quando uma tabela log consolida em `admin_audit_log` vs existe separada. Fecha a questão deixada aberta por ADR-0012 P5 + B8.
- `ADR-0014-log-retention-policy.md` — Janelas de retenção (archive/purge) por categoria do ADR-0013: Cat A 5y→archive+7y→drop; Cat B indefinido; Cat C 90-180d drop; Cat D 5y anonymize+6y drop (LGPD Art. 37); Cat E 180d-2y drop. RPC `purge_expired_logs` + pg_cron mensal.
- `ADR-0015-tribes-bridge-consolidation.md` — Deprecação do `tribe_id` legacy em 11 tabelas droppable (C3: events, announcements, webinars, etc.), mantendo 7 bridge-locked (C2: tribe_deliverables, member_cycle_history) + `tribes` table + `members.tribe_id` (C4 deferred). Plano em 5 fases multi-sessão.
- `ADR-0023-sync-operational-role-cache-trigger-contract.md` — Contrato formal do `sync_operational_role_cache()` trigger: priority ladder canônica, paridade mandatória com invariant A3, fast-path usages (Amendment A de ADR-0011), regras de amendment.

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
