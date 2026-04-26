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
- `ADR-0016-ip-ratification-governance-model.md` — Modelo de ratificação multi-gate de documentos de governança: gates como data + autoridade em camadas + assinatura externa + imutabilidade de versões. Fundamenta o subsistema CR-050 / IP Policy.
- `ADR-0017-schema-code-contract-audit-methodology.md` — Checklist obrigatório pré-`DROP COLUMN`: audit pg_proc.prosrc + views + policies + triggers + EFs + frontend. Padroniza dimensões de busca para evitar falsos-negativos (origens das issues #79/#80). **Status: Accepted (2026-04-24 p43) — ratificada pela prática: sessões p40-p43 seguiram a metodologia sem regressão tipo #79/#80.**
- `ADR-0018-mcp-threat-model.md` — Análise de risco do `nucleo-mcp` (EF + Cloudflare proxy) contra vulnerabilidade MCP reportada em abril/2026. Vetores aplicáveis vs não-aplicáveis, mitigações canônicas (OAuth 2.1, CSRF middleware, canV4 gate). **Status: Accepted (2026-04-24 p44 R+T+W3+S) — todas as mitigações shipped**: **W1 confirmation step (MCP v2.24.0, Track R)** (5 destructive tools default to preview); **W2 rate limit no Cloudflare Worker (`src/lib/mcp-rate-limit.ts` + `src/pages/mcp.ts`, Track S)** (100/min general + 10/min destructive, KV counters, caveat eventual consistency); **W3 anomaly detection cron (migration `20260511020000`, pg_cron `mcp-anomaly-detection-15min`, Track W3)** (4 patterns, alerts em admin_audit_log).
- `ADR-0019-portfolio-as-projection-principle.md` — Portfólio executivo é VIEW agregada sobre `board_items.is_portfolio_item=true`, NÃO entidade com lifecycle próprio. Não existe workflow formal de "portfolio request/approval" — governance via board tier + audit log. **Status: Accepted (2026-04-24 p43) — D1 enforcement presente em `update_board_item`, D3 6 event types ativos em `board_lifecycle_events`, D6 tools expostas. D5 cron e D7 coluna opcional continuam explicitamente opt-in.**
- `ADR-0020-publication-pipeline.md` — Pipeline unificado de publicação: `publication_ideas` + `publication_series` como primitivos. Consolida 5 flows paralelos (hub_resources, wiki, submissions, publications, newsletter). Inspirado em padrões de 10 cases de mercado. **Status: Proposed.**
- `ADR-0021-newsletter-frontiers-governance.md` — Addendum operacional ao Pipeline (ADR-0020) para Newsletter "Frontiers in AI & Project Mgmt". Decisões editoriais + operacionais + licensing + cadência biweekly + trilíngue. **Status: Partially Accepted, pending Termo R3.**
- `ADR-0022-communication-batching-weekly-digest-default.md` — Weekly digest é default; transactional email é exceção. Governa integrações de notificação (issues #97, #98, #88, #91). **Status: Proposed.**
- `ADR-0023-sync-operational-role-cache-trigger-contract.md` — Contrato formal do `sync_operational_role_cache()` trigger: priority ladder canônica, paridade mandatória com invariant A3, fast-path usages (Amendment A de ADR-0011), regras de amendment.
- `ADR-0028-service-role-bypass-adapter-pattern.md` — Padrão canônico V4 para 30 admin_* fns chamáveis via cron/EF (service_role) E por usuários admin. Adapter pattern: `IF auth.role()='service_role' THEN bypass; ELSE can_by_member(...)`. Closes "29 service-role-bypass" backlog. **Status: Proposed (drafted p63 ext, awaiting PM ratify).**

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
