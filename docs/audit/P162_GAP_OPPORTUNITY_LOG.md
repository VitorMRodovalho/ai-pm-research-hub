# p162 Gap + Opportunity Log (platform-guardian audit)

**Date:** 2026-05-15 (sessão p162, agent run a4e2ed537cd2cbafe)
**Methodology:** 18 targeted greps + reading: handoff p162 · SEMANTIC_TAXONOMY.md · ADR-0080/0081/0077 · migrations 20260403→20260651 · profile.astro · sync_attendance_points · auth_engagements view · sync_operational_role_cache trigger · get_gamification_leaderboard RPC · issue_gap_opportunity_log.md
**Author:** platform-guardian agent (background)

## 15 items coletados

### 1. RISK — `get_gamification_leaderboard` stale para as 11 novas categorias
- **Tipo:** risk · **Effort:** M
- **Trigger:** `20260513050000_gamification_leaderboard_to_secdef_rpc.sql:92-93` — `bonus_points` é catch-all `category <> ALL (ARRAY['attendance','trail','course',...,'showcase'])`. As 11 categorias p161 caem no bonus bucket.
- **Impact:** leaderboard distorce sinal de diversificação; champion + curation aparecem como "bônus".
- **Cross-ref:** ADR-0081 Componente 1, ADR-0050.

### 2. GAP — `register_event_showcase` migrou para V4 mas XP é hardcoded
- **Tipo:** gap · **Effort:** S
- **Trigger:** `20260516070000_phase_b_batch17_register_event_showcase_v4.sql` migrou gate auth, mas `case_study=25, tool_review=20, prompt_seven=20, insight=15, awareness=15` ainda hardcoded em `20260403020000_showcase_gamification.sql:78-81`.
- **Impact:** admin altera `gamification_rules.base_points` do showcase via UI, RPC ignora — viola ADR-0081.
- **Fix:** `v_xp := (SELECT base_points FROM gamification_rules WHERE slug='showcase' AND active=true AND org=...);`

### 3. RISK — `sync_attendance_points` sem filtro `events.type`
- **Tipo:** risk · **Effort:** S · **Track C precursor**
- **Trigger:** `20260515040000_phase_b_batch14_..._sync_points_v4.sql:53-60` — INSERT pra attendance sem filtrar `e.type`. Entrevista (35) + evento_externo (2) + webinar (4) podem gerar XP.
- **Impact:** candidatos em entrevista ganham XP de presença.
- **Fix:** `AND e.type IN ('tribo','geral','lideranca','1on1','parceria','webinar','kickoff')`. (PM ratificou excluir 1on1+entrevista+parceria; agent recomenda revisar.)

### 4. GAP — `sync_operational_role_cache` collision observer + pending-cert leader [Track E root]
- **Tipo:** gap · **Effort:** M · **Track E precondition**
- **Trigger:** `20260413430000_v4_phase4_role_cache_sync.sql:28-44`. Membro com `observer is_authoritative=true` (no agreement required) + `study_group_owner role=leader is_authoritative=false` (cert pending) → trigger mapeia para `observer`. Herlon é o caso.
- **Impact:** qualquer onboarding via observer prévio + promotion para kind com `requires_agreement=true` sem cert → trava em observer.
- **Fix opções:**
  - (a) `AND e.kind != 'observer'` no predicado (quebra semântica observer)
  - (b) adicionar `is_primary` column em engagements
  - (c) re-ordenar: kinds com requires_agreement=true → "pending" não bloqueia
- **Cross-ref:** ADR-0080 (PROPOSED), ADR-0008.

### 5. GAP — Onboarding sem `seed_member_engagement_by_role` template
- **Tipo:** gap · **Effort:** M
- **Trigger:** ADR-0080 menciona PMO capítulo affected, mas não há template. Manual case-by-case garante drift.
- **Impact:** drift à medida que Núcleo expande (PMI-CE pilot, PMI-GO).
- **Fix:** `docs/reference/ENGAGEMENT_SEED_TEMPLATES.md` + RPC `seed_member_engagement_by_role(p_person_id, p_template)`.

### 6. RISK — Profile XP cycle vs lifetime invisível ao membro [Track A pending]
- **Tipo:** risk · **Effort:** S · **Track A em execução p162**
- **Trigger:** `src/pages/profile.astro:866` mostra lifetime no card de ciclo, mas pilares (novos p162) chamam `get_member_xp_pillars` sem cycle param → mistura.
- **Impact:** membro entrado tardio no ciclo 3 vê pouco mesmo sendo ativo.

### 7. GAP — 20+19 ternários inline i18n na seção gamification do profile
- **Tipo:** gap · **Effort:** M
- **Trigger:** `src/pages/profile.astro:900-1120` — 20 `lang === 'en-US'` + 19 `lang === 'es-LATAM'` ternários. Strings de pillar/Champion/surface/"How to earn"/etc fora do dict.
- **Impact:** viola `.claude/rules/i18n.md`. Risk de PT-BR vazar p124-style.
- **Fix:** migrar para ~15-20 chaves `profile.xp.*` em 3 dicionários.

### 8. GAP — `champion.criteria_met` text[] livre sem catálogo canônico
- **Tipo:** gap · **Effort:** S
- **Trigger:** `20260645000000:174` — apenas valida cardinalidade. Checklist hardcoded no frontend, não DB.
- **Impact:** 2 líderes podem usar critérios textuais diferentes para mesmo Champion → audit incoerente.
- **Fix:** `champion_criteria_catalog(surface, criteria_text, display_name_i18n, active)` OR `gamification_rules.criteria_options_per_surface jsonb`.

### 9. OPPORTUNITY — Champion capture no flow ata-publish [Track B]
- **Tipo:** opportunity · **Effort:** M · **Track B**
- **Trigger:** `meeting_close` RPC + `upsert_event_minutes` não abrem prompt de "dar Champion". Conexão só via `champions_awarded.context_id`.
- **Fix:** `suggested_champion_ids[]` opcional em `meeting_close` payload + grant modal pré-populado.

### 10. GAP — `get_gamification_leaderboard` exclui `current_cycle_active=false`
- **Tipo:** gap · **Effort:** S
- **Trigger:** `20260513050000:104` — `WHERE m.current_cycle_active = true`. Membros entre ciclos / offboarding-in-flight desaparecem.
- **Fix:** mudar pra `is_active=true OR EXISTS(gamification_points current cycle)`. PM input.

### 11. GAP — ADR-0080 PROPOSED + test contract `v4-engagement-canonical.test.mjs` ausente
- **Tipo:** gap · **Effort:** M
- **Trigger:** ADR-0080 PROPOSED desde p159, Fase A frontend cutover não executada. Sem test contract.
- **Impact:** drift V3/V4 hybrid sedimenta. Track E é sintoma.

### 12. RISK — `event_showcases_manage` policy V3 após RPC migrada V4
- **Tipo:** risk · **Effort:** S · **ADR-0011 invariante violation**
- **Trigger:** `20260415010000_v4_phase4_rls_policy_rewrite.sql:282` — `operational_role IN (...)` hardcoded. RPC migrada para `can_by_member('manage_event')` mas policy ficou V3.
- **Impact:** edge cases (observer com manage_event grant) bloqueados; `comms_leader` com award_champion não tem tier `tribe_leader` → bloqueio possível.

### 13. OPPORTUNITY — `/admin/gamification` sem painel "Atividade Recente por categoria"
- **Tipo:** opportunity · **Effort:** S
- **Fix:** aba com `SELECT category, count(*), max(created_at) FROM gamification_points GROUP BY category` + alerta se nova categoria tem count=0 após deploy.

### 14. GAP — `gamification_rules.pillar` NOT NULL — CRUD form futuro deve incluir
- **Tipo:** gap · **Effort:** S
- **Risk pattern:** sediment p138 — `supabase-js INSERT silencioso 400`. Form precisa `.throwOnError()` + campo `pillar` obrigatório.

### 15. GAP — Showcase vs Champion: sobreposição semântica sem ADR delimitando
- **Tipo:** gap · **Effort:** S · **Track D**
- **Trigger:** SEMANTIC_TAXONOMY.md seção 6. Líder pode dar showcase E Champion ao mesmo membro no mesmo evento — sem constraint.
- **Fix:** Decisão PM Track D: showcase é input pra Champion (eligibility) ou independente?

## Bloqueadores apontados

- **Item 4** é a real causa da Track E. Fix de trigger CASE-chain (commit p162 `20260652`) é defensivo mas não resolve a collision. Decisão de design pendente.
- **Item 12** é ADR-0011 violation ativo não detectado por `check_schema_invariants()`. Deve ser corrigido antes de feature novas em event_showcases.

## Recomendação para issue_gap_opportunity_log.md

Itens 1, 2, 3, 4, 7, 8, 10, 11, 12 = P2 ou maior. Items 3 + 4 + 12 são pré-condições para Tracks C/E. Item 7 é debt da Phase E i18n p163.
