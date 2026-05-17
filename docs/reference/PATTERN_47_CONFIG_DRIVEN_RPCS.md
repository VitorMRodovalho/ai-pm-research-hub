# Pattern 47 — Config-Driven RPCs (Reader joins canonical rules table)

**Status:** Sedimentado (p165 leaderboard + p173 cron iniciativas)
**Anchor commit:** p165 `8f4a04f` (`get_gamification_leaderboard` config-driven), p173 `7956e84` (initiative-aware cron)

## Princípio

**Reader RPCs join the rules table — never hard-code literal slug lists.**

Quando uma feature tem catálogo canônico em DB (`gamification_rules.pillar`, `engagement_seed_templates`, `engagement_kind_permissions`, `champion_criteria_catalog`, etc.), os RPCs que consomem essa feature devem **JOIN nesse catálogo** em vez de manter um array de slugs hardcoded.

## Anti-pattern (NÃO fazer)

```sql
-- get_gamification_leaderboard pré-p165 #1
WHERE category IN (
  'attendance_xp', 'specialization_badge', 'curation_ratification_bonus',
  'showcase_grant', 'champion_award', 'event_artifact_xp'
  -- ... 12 slugs literais
)
```

**Por que ruim:**
- Nova categoria seedada em `gamification_rules` mas RPC continua excluding → bug "categoria sumiu do leaderboard"
- 2 fontes de verdade (DB rules + RPC array) podem desviar silenciosamente
- Cada nova categoria = 1 migration de tabela + 1 migration do RPC

## Pattern (FAZER)

```sql
-- get_gamification_leaderboard pós-p165 #1
JOIN gamification_rules r ON r.category = gp.category
WHERE r.pillar IS NOT NULL AND r.active = true
```

**Por que correto:**
- 1 fonte de verdade (tabela rules)
- Insert/update em rules basta — RPC pega automatic
- Pillar surfacing config-driven (curation_ratification_bonus → curadoria; specialization_badge → learning; etc.)

## Casos canônicos (lista live)

| Feature | Reader RPC(s) | Rules table | Shipped |
|---------|---------------|-------------|---------|
| Gamification leaderboard | `get_gamification_leaderboard`, `get_tribe_gamification`, `get_initiative_gamification` | `gamification_rules.pillar` | p165 commit `8f4a04f` |
| Engagement onboarding seed | `seed_member_engagement_by_role(person_id, template_slug)` | `engagement_seed_templates` | p172 commit `09831c4` |
| Champion criteria catalog | `award_champion`, `get_champions_ranking` (validation) | `champion_criteria_catalog(surface, criteria_text)` | p171 commit `9a3a5ba` |
| Cron leader digest | `generate_weekly_leader_digest_cron`, `_v4_active_initiatives_with_leaders` | `initiatives.status='active'` + `engagements` | p173 commit `7956e84` |

## Checklist pra novos RPCs

Antes de write RPC que recebe lista de domínio (categories, kinds, slugs, types), pergunte:

- [ ] Existe tabela canônica desses valores? (search `*_catalog`, `*_rules`, `*_templates`)
- [ ] Posso JOIN nessa tabela em vez de literal array?
- [ ] Se ainda não existe, **criar a tabela primeiro** + seedar valores antes do RPC
- [ ] A tabela tem flag `active` ou `deprecated_at`? RPC filter por isso

## Counter-example: literal acceptable

Listas pequenas, estáveis, semanticamente fechadas (não vão crescer) — manter literal é OK:

```sql
WHERE event.type IN ('tribo', 'geral', 'lideranca')  -- catálogo fechado
```

Threshold: > 4 valores OU domain-defined (admin pode editar) → catalog → JOIN.

## Sediment hits

- p138 — `supabase-js INSERT silencioso 400`: `gamification_rules.pillar NOT NULL` exposto pq RPC reader esperava pillar mas form de admin não setava. Trigger evidence: forms agora `.throwOnError()` + pillar field obrigatório em CRUD.
- p165 — leaderboard surfacing bug: `curation_ratification` mostrava em "bonus_points" em vez de "curadoria" pq RPC hard-coded array não incluiu. Fix via JOIN rules.pillar.
- p173 — cron digest tribe-centric: PM intuition "Herlon/Mayanna não recebem digest" surfaced que cron filtrava `tribes` em vez de `initiatives` (config primitivo do V4). Fix via JOIN initiatives + helper config-driven.

## Cross-refs

- ADR-0009 — Config-driven kinds (admin edita sem deploy)
- ADR-0080 — Engagement primitives V4 (initiatives = primitivo de domínio)
- ADR-0022 Amendment C — Cron iteration sobre initiatives canonical (p173)
- `docs/reference/ENGAGEMENT_SEED_TEMPLATES.md` — exemplo de catalog table
- `docs/reference/V4_AUTHORITY_MODEL.md` — `engagement_kind_permissions` é outro catalog
