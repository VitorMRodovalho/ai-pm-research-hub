# p162 Gap + Opportunity Log (platform-guardian audit)

**Date:** 2026-05-15 (sessão p162, agent run a4e2ed537cd2cbafe)
**Methodology:** 18 targeted greps + reading: handoff p162 · SEMANTIC_TAXONOMY.md · ADR-0080/0081/0077 · migrations 20260403→20260651 · profile.astro · sync_attendance_points · auth_engagements view · sync_operational_role_cache trigger · get_gamification_leaderboard RPC · issue_gap_opportunity_log.md
**Author:** platform-guardian agent (background)

---

## Status update 2026-05-16 (p170 close)

**Resolved since original audit:**
| # | Item | Closed | Evidence |
|---|------|--------|----------|
| 1 | leaderboard stale (11 categorias) | p165 | Migration `2026066x` — JOIN gamification_rules.pillar config-driven (Pattern 47) |
| 2 | register_event_showcase XP hardcoded | p165 | Migration p165 — 5 dedicated showcase_* slugs + `_grant_auto_xp` helper |
| 3 | sync_attendance_points sem filtro events.type | p161 | Verified 2026-05-16: function tem `e.type IN ('tribo','geral','lideranca','kickoff')` |
| 11 | ADR-0080 PROPOSED + test contract ausente | p166 | `tests/contracts/v4-engagement-canonical.test.mjs` exists, ratcheting allowlist |
| 12 | event_showcases_manage policy V3 | unknown | Verified 2026-05-16: policy uses `rls_is_superadmin() OR rls_can('write')` |
| 16 | platform-guardian doc 8→15 invariantes | p166 | Doc refreshed; baseline 1186→1434 pass |
| 17 | get_weekly_tribe_digest V3 cache | **p170** | Migration `20260674500000` — `_v4_tribe_leader_member_id()` helper |
| 18 | meeting_artifacts RLS V3 | unknown | Verified 2026-05-16: policy uses `rls_can_for_initiative('write', initiative_id)` |
| 19 | recurrence grouping só ata_pending | **p170** | Migration `20260674800000` — attendance+champion now group |

**Still open (5 items):**
- #4 sync_operational_role_cache collision (Track E root, M effort)
- #5 Onboarding sem seed_member_engagement template (M effort)
- #6 Profile XP cycle vs lifetime invisível (S effort, Track A)
- #7 20+19 ternários inline i18n profile (M effort)
- #8 champion.criteria_met sem catálogo canônico (S effort)
- #9 Champion capture no flow ata-publish (M effort, Track B)
- #10 leaderboard exclui current_cycle_active=false (S effort, PM decisão pendente)
- #13 /admin/gamification recent activity panel (S effort)
- #14 gamification_rules.pillar CRUD form (S effort, future-proof)
- #15 Showcase vs Champion semantic ADR (S effort, Track D)
- #21 Multi-leader per initiative digest (M effort, pos-ADR-0080 cutover)
- #22 A3 drift 7 members (continuation Track E)

**New items emerged in p170 (4 closed in session):**
- BUG-HOI: divergência Horas de Impacto entre 3 superfícies → fixed via `get_impact_hours_canonical()` RPC (migration `20260674400000`)
- ATT-1/2/3: Attendance × Selection portal sync — 3 migrations closing causa raiz (`20260674000000`-`20260674300000`)
- VEP→engagement explicit FK + invariant Q: PM ask 2026-05-16 (`20260674600000`)
- OQ-B1 #2: auto-clear invariant drift baselines (`20260674700000`)

**Backlog rotation pending:** create P170_GAP_OPPORTUNITY_LOG.md when p170 closes or carry items move to next session.

---

## 15 items coletados

### 1. RISK — `get_gamification_leaderboard` stale para as 11 novas categorias ✅ RESOLVED p165
- **Tipo:** risk · **Effort:** M
- **Trigger:** `20260513050000_gamification_leaderboard_to_secdef_rpc.sql:92-93` — `bonus_points` é catch-all `category <> ALL (ARRAY['attendance','trail','course',...,'showcase'])`. As 11 categorias p161 caem no bonus bucket.
- **Impact:** leaderboard distorce sinal de diversificação; champion + curation aparecem como "bônus".
- **Cross-ref:** ADR-0081 Componente 1, ADR-0050.
- **Resolution:** p165 migration refactorou RPC pra JOIN `gamification_rules.pillar` (Pattern 47: "reader RPCs join the rules table — never literal slug lists").

### 2. GAP — `register_event_showcase` migrou para V4 mas XP é hardcoded ✅ RESOLVED p165
- **Tipo:** gap · **Effort:** S
- **Trigger:** `20260516070000_phase_b_batch17_register_event_showcase_v4.sql` migrou gate auth, mas `case_study=25, tool_review=20, prompt_seven=20, insight=15, awareness=15` ainda hardcoded em `20260403020000_showcase_gamification.sql:78-81`.
- **Impact:** admin altera `gamification_rules.base_points` do showcase via UI, RPC ignora — viola ADR-0081.
- **Fix:** `v_xp := (SELECT base_points FROM gamification_rules WHERE slug='showcase' AND active=true AND org=...);`
- **Resolution:** p165 introduziu 5 dedicated `showcase_*` slugs + `_grant_auto_xp` helper que SELECT base_points do gamification_rules.

### 3. RISK — `sync_attendance_points` sem filtro `events.type` ✅ RESOLVED p161-ish
- **Tipo:** risk · **Effort:** S · **Track C precursor**
- **Trigger:** `20260515040000_phase_b_batch14_..._sync_points_v4.sql:53-60` — INSERT pra attendance sem filtrar `e.type`. Entrevista (35) + evento_externo (2) + webinar (4) podem gerar XP.
- **Impact:** candidatos em entrevista ganham XP de presença.
- **Fix:** `AND e.type IN ('tribo','geral','lideranca','1on1','parceria','webinar','kickoff')`. (PM ratificou excluir 1on1+entrevista+parceria; agent recomenda revisar.)
- **Resolution:** verified 2026-05-16 — function has `AND e.type IN ('tribo','geral','lideranca','kickoff')` (entrevista/1on1/parceria/webinar/evento_externo all excluded).

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

### 11. GAP — ADR-0080 PROPOSED + test contract `v4-engagement-canonical.test.mjs` ausente ✅ RESOLVED p166
- **Tipo:** gap · **Effort:** M
- **Trigger:** ADR-0080 PROPOSED desde p159, Fase A frontend cutover não executada. Sem test contract.
- **Impact:** drift V3/V4 hybrid sedimenta. Track E é sintoma.
- **Resolution:** p166 criou `tests/contracts/v4-engagement-canonical.test.mjs` (ratcheting allowlist, 4 arquivos baseline). ADR-0080 Fase A frontend cutover ainda PROPOSED (separate item).

### 12. RISK — `event_showcases_manage` policy V3 após RPC migrada V4 ✅ RESOLVED
- **Tipo:** risk · **Effort:** S · **ADR-0011 invariante violation**
- **Trigger:** `20260415010000_v4_phase4_rls_policy_rewrite.sql:282` — `operational_role IN (...)` hardcoded. RPC migrada para `can_by_member('manage_event')` mas policy ficou V3.
- **Impact:** edge cases (observer com manage_event grant) bloqueados; `comms_leader` com award_champion não tem tier `tribe_leader` → bloqueio possível.
- **Resolution:** verified 2026-05-16 — policy uses `rls_is_superadmin() OR rls_can('write')`. Multi-org isolation via `event_showcases_v4_org_scope` with `auth_org()`. V4 ✓.

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

---

## Onda 2 — items adicionados via 2ª deliberação council (digest pivot, 2026-05-15)

### 16. RISK — `.claude/agents/platform-guardian.md` cita "8 invariantes" mas DB tem 15 (após O+P p162) ✅ RESOLVED p166
- **Tipo:** risk · **Effort:** XS
- **Trigger:** system prompt do agente outdated (A1/A2/A3/B/C/D/E/F = 8). DB tem A1/A2/A3/B/C/D/E/F/J/K/L/M/N/O/P = 15.
- **Impact:** audit reports do guardiao checam contagem errada.
- **Fix:** update system prompt do agente: "15 invariantes".
- **Resolution:** p166 doc refresh — guardian doc updated, baseline 1186→1434 pass, ADR coverage 0001-0083, source-of-truth → `.claude/rules/*.md`. p170 added invariant Q → DB now has 16 invariantes (separate carry).

### 17. RISK — `get_weekly_tribe_digest:47` identifica líder via `tribes.leader_member_id` (V3) ✅ RESOLVED p170
- **Tipo:** risk · **Effort:** S
- **File:** `supabase/migrations/20260516490001` + `20260655000000` (G2a herda)
- **Impact:** digest pode ir para ex-líder após mudança V4 sem sync para V3 cache.
- **Fix:** substituir lookup por `auth_engagements WHERE kind='volunteer' AND role='leader' AND status='active' AND is_authoritative=true` filtrado por initiative_id correspondente.
- **Não-bloqueador:** smoke com 1 líder/tribo. Pre-req para rollout multi-chapter.
- **Resolution:** p170 migration `20260674500000` criou helper `_v4_tribe_leader_member_id()` (engagements role=leader status=active via legacy_tribe_id bridge). `get_weekly_tribe_digest` + `generate_weekly_leader_digest_cron` refactored. Audit revelou Tribe #3 (TMO) com V3 cache aponta Marcel Fleming (alumni) — tribe is_active=false já filtra do cron. 7 active tribes V3 cache ≡ V4 active leader (no drift).

### 18. GAP — `meeting_artifacts` RLS V3 hardcoded (item #12 reflag como pre-req crítico) ✅ RESOLVED
- Mesmo do item #12 original. Reflag: Track B' não tocou meeting_artifacts (D-arq-1 = events.event_champion_waived em vez de jsonb em ma). G0 deferred.
- **Quando torna-se bloqueador:** próxima track que ALTER meeting_artifacts.
- **Resolution:** verified 2026-05-16 — policies use `rls_can_for_initiative('write', initiative_id)`, `rls_can('manage_member')`, `rls_is_superadmin()`. `meeting_artifacts.tribe_id` migrou para `initiative_id` (V4 primitive). Multi-org isolation via `meeting_artifacts_v4_org_scope` + `auth_org()`. V4 ✓.

### 19. GAP — Recurrence grouping aplicado SÓ em ata_pending ✅ RESOLVED p170
- **Tipo:** gap · **Effort:** S
- **Trigger:** G2a aplica GROUP BY recurrence_group apenas em ata_pending. attendance_pending e champion_pending stayed flat per-event.
- **Impact:** se série recorrente tem 10 ocorrências sem presença registrada, digest mostra apenas top-3 events (não top-3 séries agrupadas).
- **Fix:** estender pattern de grouping para as 2 outras seções em p163+ se PM ratificar.
- **Resolution:** p170 migration `20260674800000` — attendance_pending + champion_pending agora usam mesma CTE pending→grouped→top3 pattern de ata_pending. Backward compat via `count` alias + `top_events` (legacy flat shape) preservados. Smoke tribe 1: 17 champion_pending events → 2 groups.

### 20. GAP — `champion_decision` semantic PM decision (resolvido pela D-arq-1)
- ✅ RESOLVIDO: PM ratificou alternativa (b) — `events.event_champion_waived` boolean + trio, NÃO `meeting_artifacts.champion_decision jsonb`.
- G1 migration deferred (não load-bearing para G2). Adicionar quando G3 UI requerir distinção pending vs deliberate-none.

### 21. OPPORTUNITY — Multi-leader per initiative (V4 N:N) digest delivery
- **Tipo:** opportunity · **Effort:** M
- **Trigger:** hoje cron itera tribes com 1 leader_member_id. V4 permite múltiplos líderes ativos (leader + co_leader). Digest enviado só para 1.
- **Fix:** query V4 retornar todos os leaders ativos por initiative, enviar email para cada.
- **Não-bloqueador:** quando V4 cutover (ADR-0080 Fase A) acontecer.

### 22. GAP — A3 drift 7 membros após Track E trigger extension (continuation Track E)
- **Tipo:** gap · **Effort:** S
- **Membros afetados:** Sarah, Roberto, Fabricio, Leticia, Maria Luiza, Mayanna, Eder
- **Trigger:** Track E migration `20260652` estendeu CASE chain do trigger sync_operational_role_cache para cobrir 5 V4 kinds. Mas o trigger só dispara em INSERT/UPDATE de engagements — rows existentes ficam stale.
- **Fix:** backfill manual via `UPDATE members SET operational_role = <expected> WHERE id IN (7)`. Ou: trigger artificial em todos os engagements para forçar recompute.
- **Impact:** Sarah/Roberto/Fabricio operacionalmente perdem privilégios tribe_leader que mereciam ter via committee/workgroup engagements. Affecta gates RLS e `admin.gamification` permission visibility.
- **Cross-ref:** Track E (item #4 original), continuation p163.

### 23. RESOLVED — Invariantes O + P shipped p162 Track B' G2b
- ✅ `O_meeting_artifact_event_orphan` (medium, 0 violations)
- ✅ `P_tribe_initiative_bridge_complete` (medium, 0 violations)
- Total invariantes em DB: 15 (era 13 antes do p162).

---

## Onda 3 — p170 emergent items (2026-05-16, ATIVO close)

### 24. BUG — Divergência Horas de Impacto entre 3 superfícies ✅ RESOLVED p170
- **Tipo:** bug (P0 user-visible) · **Effort:** S
- **Trigger:** PM ask 2026-05-16: /attendance mostra 656h, /admin 666h, /#kpis 598h. 3 implementações independentes da mesma métrica.
- **Root cause:**
  - /attendance view `impact_hours_total`: SUM(duration_minutes/60) WHERE present=true AND excused IS NOT TRUE (falta COALESCE duration_actual)
  - /admin `get_impact_hours_excluding_excused()`: NÃO filtra present=true (BUG; conta 8 unexcused absences)
  - /#kpis `exec_portfolio_health(impact_hours)`: correto mas inline (drift possível)
- **Resolution:** Migration `20260674400000` criou `get_impact_hours_canonical(start, end)` RPC + refactor 3 surfaces (view + 2 RPCs delegate). Fórmula: SUM(COALESCE(duration_actual, duration_minutes)/60) WHERE present=true AND excused IS NOT TRUE. Convergência confirmada: 597.8h em todas.

### 25. BUG — /attendance entrevista pollution + selection portal sync gap ✅ RESOLVED p170 (ATT-1/2/3)
- **Tipo:** bug + arquitetura · **Effort:** M
- **Trigger:** PM 2026-05-16: entrevistas individuais aparecem em /attendance como events com "0/49 presentes" (49 active members tratados como expected pra 1:1) + status não sync com selection_interviews.
- **Root cause:** sistemas paralelos `events` (calendar/attendance) + `selection_interviews` (portal seleção) sem mecanismo de sync. 4 paths de write em selection_interviews; nenhum INSERT em events.
- **Resolution (3 migrations):**
  - ATT-1 (`20260674000000`): trigger AFTER INSERT/UPDATE em selection_interviews → cria/sincroniza events row (idempotente, calendar_event_id + date+time fallback, skip mirror). 51/59 historical interviews backfilled.
  - ATT-2 (`20260674200000`): `list_orphan_interview_events()` + `link_interview_event()` RPCs admin-only + UI section em DataHealthIsland (selectorpicker com pg_trgm sugestões).
  - ATT-3 (`20260674300000`): trigger BEFORE INSERT/UPDATE on events.title type='entrevista' selection_application_id IS NULL → auto-link via pg_trgm similarity (threshold 0.7 + gap 0.15 anti-ambiguidade). 6 órfãs auto-linked no backfill.
- **Cleanup migration:** `20260674100000` — 8 historical interviews with placeholder scheduled_at='2026-04-02' deduplicated; scheduled_at corrigido para data real.

### 26. ARCH — VEP→engagement explicit FK + invariant Q ✅ RESOLVED p170
- **Tipo:** arquitetura · **Effort:** S · **PM ask 2026-05-16**
- **Trigger:** Marcel Fleming audit revelou gaps: engagements.vep_opportunity_id era uuid (0 rows, mismatch vs selection_applications text), sem FK reverso explícito; traceability dependia de fuzzy email join.
- **PM clarificação:** VEP JSON é fonte canônica de identidade (pmi_id, application_id) E fato (status + datas application/aceite/start/end). Make relationship explicit.
- **Resolution:** Migration `20260674600000`:
  - ADD `engagements.selection_application_id uuid FK → selection_applications(id)`
  - Backfill: 53/129 engagements linked via person → email → cycle window match
  - DROP `engagements.vep_opportunity_id` (uuid wrong type, 0 rows)
  - COMMENT ON TABLE + COLUMN documentando flow VEP JSON → selection_applications → engagements
  - Invariante Q novo: `engagements.status='expired' AND end_date > CURRENT_DATE` (impossible state). 0 violations atual.

### 27. UX — OQ-B1 #2 auto-clear invariant drift baselines ✅ RESOLVED p170
- **Tipo:** ux/observability · **Effort:** XS
- **Trigger:** Carry de p168 OQ-B1. `get_invariant_alerts()` inserir `.detected` mas nunca `.cleared` quando violation resolvia → baselines abertos lingering indefinidamente em admin_audit_log.
- **Resolution:** Migration `20260674700000` — adicionou 2º loop após violation loop. Iterates open baselines (detected sem cleared) cujo invariant_name NÃO está em current violating set, e auto-insere `.cleared` com `duration_hours` computed. Smoke (rollback): A1 fake .detected → .cleared inserted with auto_cleared=true.

### 28. INVESTIGATION — Discrepância "Cycle 2 entrants" entre VEP and members.cycles
- **Tipo:** investigation finding · **Effort:** XS (documentation only)
- **Trigger:** PM ask 2026-05-16 (cycle 2 expiring members list). Minha 1ª query usou VEP `service_first_start_date` (filter Jul-Dez 2025) → 3 members. PM apontou ~10 esperados (Débora etc).
- **Root cause:** VEP `service_first_start_date` é NULL pra members pre-VEP-sync (entrados via convite manual / pilot). Source canonical = `members.cycles` array (populado por multiple paths: selection_apps approval + manual admin + auto-promote).
- **Finding documented:** `members.cycles` é source-of-truth pra histórico cíclico, VEP é source-of-truth pra VEP-routed flow apenas. Não bug — gap de visibility/naming.
- **Final list:** 8 active members first-cycle-2 needing renewal reminder + 1 already reapplied (João Coelho) + 4 inactive.

---

## Status final p170 close (2026-05-16)

**Carryforward (12 items still open):** #4, #5, #6, #7, #8, #9, #10, #13, #14, #15, #21, #22 (more above). PM deferred items.

**Migrations head p170:** `20260674800000` (9 migrations p170: ATT-1 sync + cleanup + ATT-2 + ATT-3 + HOI canonical + Item #17 V4 + VEP linkage + OQ-B1 #2 + #19 recurrence).

**Commits p170:** 9 (1625e55 → ab851ea). Worker deploy: ba764141 (active prod).

**Invariantes DB:** 16 total (A1-A3, B-F, J-Q new — `Q_expired_engagement_end_date` shipped p170).

**Tests baseline:** 1438 pass / 0 fail / 39 skip.
