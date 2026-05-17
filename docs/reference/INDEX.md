# Reference Docs — Index

Source-of-truth para padrões, taxonomias, catálogos e modelos. Mantenha cada doc com 1 owner-claim per ADR/sediment.

## Domain primitives

| Doc | Scope | Anchor |
|-----|-------|--------|
| [V4_AUTHORITY_MODEL.md](./V4_AUTHORITY_MODEL.md) | Authority derivation (`can()` / `can_by_member()`), 3 paths paralelos, anti-pattern "seed expansion como atalho" | ADR-0007, sediment p122e |
| [SEMANTIC_TAXONOMY.md](./SEMANTIC_TAXONOMY.md) | Engagement kinds + roles + designations + status (V4 N:N). Champion vs Showcase delimitation. | ADR-0080, ADR-0084 |
| [ENGAGEMENT_SEED_TEMPLATES.md](./ENGAGEMENT_SEED_TEMPLATES.md) | 12 templates canônicos (researcher, tribe_leader, co_leader, manager, etc) + `seed_member_engagement_by_role` RPC | p172 #5, ADR-0009 |

## Patterns

| Doc | Topic | Anchor |
|-----|-------|--------|
| [PATTERN_47_CONFIG_DRIVEN_RPCS.md](./PATTERN_47_CONFIG_DRIVEN_RPCS.md) | Reader RPCs JOIN canonical rules tables — never literal slug lists | p165 leaderboard, p173 cron |

## Tribute / live catalogs (DB tables)

- `gamification_rules` — XP categories × pillar mapping (`get_gamification_leaderboard` joins this)
- `engagement_kind_permissions` — kind × role × action seeded permissions (V4 authority path 1)
- `engagement_seed_templates` — onboarding seed bundles (12 canonical, see doc above)
- `champion_criteria_catalog` — surface × criteria_text catalog (p171 #8)
- `initiatives` — primitivo de domínio V4. Tribe é bridge (legacy_tribe_id). Cron weekly leader digest itera initiatives + filtra leaders ativos.

## Cross-domain pointers

- `docs/adr/` — Architecture Decision Records (Accepted/PROPOSED/Abandoned)
- `docs/refactor/DOMAIN_MODEL_V4_MASTER.md` — V4 refactor master tracking (HISTORICAL, complete 2026-04-13)
- `docs/audit/P162_GAP_OPPORTUNITY_LOG.md` — Gap/Opportunity tracking (canonical live: `memory/project_issue_gap_opportunity_log.md`)
- `.claude/rules/` — operational rules (mcp.md, database.md, deploy.md, i18n.md, refactor-in-progress.md)

## Convenção de novos docs

1. Sediment ≥3 sessions → candidato para reference doc (move from memory/feedback_*)
2. Cross-link via `[[name]]` em memory entries
3. Update este INDEX quando criar novo arquivo em `docs/reference/`
