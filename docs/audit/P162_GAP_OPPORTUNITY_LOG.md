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
| 10 | leaderboard exclui current_cycle_active=false | **p170** | Commit `9d15a29` — hybrid scope (current_cycle_active OR has XP cycle) via PM Option C, migration `20260675000000` |
| 11 | ADR-0080 PROPOSED + test contract ausente | p166 | `tests/contracts/v4-engagement-canonical.test.mjs` exists, ratcheting allowlist |
| 12 | event_showcases_manage policy V3 | unknown | Verified 2026-05-16: policy uses `rls_is_superadmin() OR rls_can('write')` |
| 15 | Showcase vs Champion semantic ADR | **p170** | Commit `9890457` — ADR-0084 ratified Option C (Showcase = eligibility/nudge), helper RPC `get_recent_showcases_by_member` + UI nudge no modal Champion |
| 16 | platform-guardian doc 8→15 invariantes | p166 | Doc refreshed; baseline 1186→1434 pass |
| 17 | get_weekly_tribe_digest V3 cache | **p170** | Migration `20260674500000` — `_v4_tribe_leader_member_id()` helper |
| 18 | meeting_artifacts RLS V3 | unknown | Verified 2026-05-16: policy uses `rls_can_for_initiative('write', initiative_id)` |
| 19 | recurrence grouping só ata_pending | **p170** | Migration `20260674800000` — attendance+champion now group |

**Still open (10 items):**
- #4 sync_operational_role_cache collision (Track E root, M effort)
- #5 Onboarding sem seed_member_engagement template (M effort)
- #6 Profile XP cycle vs lifetime invisível (S effort, Track A)
- #7 20+19 ternários inline i18n profile (M effort)
- #8 champion.criteria_met sem catálogo canônico (S effort)
- #9 Champion capture no flow ata-publish (M effort, Track B)
- #13 /admin/gamification recent activity panel (S effort)
- #14 gamification_rules.pillar CRUD form (S effort, future-proof)
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

### 4. GAP — `sync_operational_role_cache` collision observer + pending-cert leader [Track E root] ⏸ DEFERRED p173
- **Tipo:** gap · **Effort:** M · **Track E precondition**
- **Trigger:** `20260413430000_v4_phase4_role_cache_sync.sql:28-44`. Membro com `observer is_authoritative=true` (no agreement required) + `study_group_owner role=leader is_authoritative=false` (cert pending) → trigger mapeia para `observer`. Herlon é o caso.
- **Impact:** qualquer onboarding via observer prévio + promotion para kind com `requires_agreement=true` sem cert → trava em observer.
- **Fix opções:**
  - (a) `AND e.kind != 'observer'` no predicado (quebra semântica observer)
  - (b) adicionar `is_primary` column em engagements
  - (c) re-ordenar: kinds com requires_agreement=true → "pending" não bloqueia
- **Cross-ref:** ADR-0080 (PROPOSED), ADR-0008.
- **Resolution p173 (2026-05-16):** PM ratificou **defer para dedicated session C** (handoff rank C: operational_role single-value cache cleanup, MID-HIGH impact, M effort). Razão: memory `feedback_operational_role_changes_require_pm_confirmation.md` (p163) expressa princípio — "cache global single-value não modela isso; pessoa pode ter funções diferentes em tribo/iniciativa/workgroup". Patches (a)/(b)/(c) acomodam modelo sabidamente errado. Herlon current state (`operational_role='observer'` com study_group_owner auth=false pending) NÃO quebra permissions (cert não-assinada = sem privilege grant). UX hint "você tem N promoções pendentes" candidato follow-up separado. Session C decidirá: oficializar como cache restrito OU plan remoção pós-V4 full cutover.

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

### 10. GAP — `get_gamification_leaderboard` exclui `current_cycle_active=false` ✅ RESOLVED p170
- **Tipo:** gap · **Effort:** S
- **Trigger:** `20260513050000:104` — `WHERE m.current_cycle_active = true`. Membros entre ciclos / offboarding-in-flight desaparecem.
- **Fix:** mudar pra `is_active=true OR EXISTS(gamification_points current cycle)`. PM input.
- **Resolution:** p170 commit `9d15a29` — migration `20260675000000` aplica hybrid scope (PM Option C): `current_cycle_active=true OR (member tem XP no ciclo corrente)`. Mantém leaderboard relevante; cobre alumni com XP residual e membros offboarding-in-flight.

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

### 15. GAP — Showcase vs Champion: sobreposição semântica sem ADR delimitando ✅ RESOLVED p170
- **Tipo:** gap · **Effort:** S · **Track D**
- **Trigger:** SEMANTIC_TAXONOMY.md seção 6. Líder pode dar showcase E Champion ao mesmo membro no mesmo evento — sem constraint.
- **Fix:** Decisão PM Track D: showcase é input pra Champion (eligibility) ou independente?
- **Resolution:** p170 commit `9890457` — **ADR-0084 ratified Option C**: Showcase = eligibility hint/nudge (não constraint). Migration `20260675200000` adicionou `get_recent_showcases_by_member(p_member_id, p_window_days=30)` RPC + UI nudge no modal Champion grant em `/admin/gamification` mostrando showcases recentes do membro. Mantém liberdade líder + reduz Champion-blind-spot.

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

### 21. OPPORTUNITY — Multi-leader per initiative (V4 N:N) digest delivery ✅ RESOLVED p173 (extended scope)
- **Tipo:** opportunity · **Effort:** M
- **Trigger:** hoje cron itera tribes com 1 leader_member_id. V4 permite múltiplos líderes ativos (leader + co_leader). Digest enviado só para 1.
- **Fix:** query V4 retornar todos os leaders ativos por initiative, enviar email para cada.
- **Não-bloqueador:** quando V4 cutover (ADR-0080 Fase A) acontecer.
- **Resolution p172 commit `17ece3a`:** multi-leader per tribe (leader + co_leader via `_v4_initiative_leader_member_ids` helper SETOF). Tribes ainda single-source-of-truth pra cron iteration.
- **Resolution p173 commit `7956e84`:** initiative-aware cron extension. PM ask 2026-05-17 surfaced que tribes-only era subset — Herlon (CPMAI study_group), Mayanna/Leticia/Maria Luiza (Hub Comunicação workgroup), Fabricio cross 3 inits (Curadoria/Newsletter/Publicações), Roberto/Sarah (Curadoria/Publicações), Vitor (LATAM LIM) ficavam invisíveis. Refactor: `_v4_active_initiatives_with_leaders()` + `_v4_leader_member_ids_by_initiative(uuid)` + `get_weekly_initiative_digest(uuid)` + cron LOOP por initiative. Sat 2026-05-23 09:30 BRT cobre 15 leaders (era 7). Notification type unchanged pra email handler back-compat. Tribes is_active=false still auto-excluded.

### 22. GAP — A3 drift 7 membros após Track E trigger extension (continuation Track E) ✅ RESOLVED p173
- **Tipo:** gap · **Effort:** S
- **Membros afetados:** Sarah, Roberto, Fabricio, Leticia, Maria Luiza, Mayanna, Eder
- **Trigger:** Track E migration `20260652` estendeu CASE chain do trigger sync_operational_role_cache para cobrir 5 V4 kinds. Mas o trigger só dispara em INSERT/UPDATE de engagements — rows existentes ficam stale.
- **Fix:** backfill manual via `UPDATE members SET operational_role = <expected> WHERE id IN (7)`. Ou: trigger artificial em todos os engagements para forçar recompute.
- **Impact:** Sarah/Roberto/Fabricio operacionalmente perdem privilégios tribe_leader que mereciam ter via committee/workgroup engagements. Affecta gates RLS e `admin.gamification` permission visibility.
- **Cross-ref:** Track E (item #4 original), continuation p163.
- **Resolution p173 (2026-05-16):** 7/7 membros verificados em expected state (operational_role = A3 expected_role derivation). Backfill organico via p163 seletivo + p170 dropout fixes + p172 #5 RPC dogfood (Eder chapter_liaison). A3 invariant = 0 violations. Audit query: `SELECT m.id, m.name, m.operational_role, (...expected_role...) FROM members m WHERE m.name ~* 'Sarah|Roberto|Fabricio|Leticia|Maria Luiza|Mayanna|Eder'` — 8 rows (inclui Matheus Frederico já alinhado). Não há ação pendente.

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

**Carryforward (10 items still open):** #4, #5, #6, #7, #8, #9, #13, #14, #21, #22. PM deferred items. (#10 + #15 fechados em commits posteriores ao log housekeeping inicial — atualizados retroativamente em p171 boot.)

**Migrations head p170:** `20260675300000` (14 migrations p170: ATT-1 sync + cleanup + ATT-2 + ATT-3 + HOI canonical + Item #17 V4 + VEP linkage + OQ-B1 #2 + #19 recurrence + Workspace Fix D + #10 hybrid scope + future events fix + #15 showcase nudge + curator/typology).

**Commits p170:** 15 (1625e55 → bcacfed). Worker deploy: 5f6619cc (active prod).

**Invariantes DB:** 16 total (A1-A3, B-F, J-Q new — `Q_expired_engagement_end_date` shipped p170).

**Tests baseline:** 1438 pass / 0 fail / 39 skip.

## p171 housekeeping (2026-05-16)

- #10 + #15 marked ✅ RESOLVED retroactively (closure happened in p170 commits 9d15a29 + 9890457 after `3f7adea` log housekeeping commit).
- Open count corrected: 12 → 10.
- Migrations head corrected: `20260674800000` → `20260675300000`.
- Commits/deploys corrected: 9 → 15 / `ba764141` → `5f6619cc`.

---

## Onda 4 — p201 MCP + guardian QA/QC audit (2026-05-19)

**Runtime evidence collected:** Supabase Edge Function logs show recent `nucleo-mcp/mcp` calls returning HTTP `200/202`; live `tools/list` returns **293 tools**; `check_schema_invariants()` returns **16/16 invariants with 0 violations**; `mcp_usage_log` has **0 failures in the last 14 days**. Historical MCP failures confirm the expected post-migration drift class (`tribe_id`, `member_status_transitions`, `cpmai_sessions`) but no active recurrence.

### 29. GAP — `document_*` RLS policies retêm V3 gates sem backlog formal — SCAFFOLDED (ADR-0092, p202)
- **Tipo:** gap · **Severity:** HIGH · **Effort:** M
- **Trigger:** Migration `20260721000000_p201_gap_200_a_v4_curator_rls_swap.sql` explicitly preserves three `document_*` policies with `operational_role IN ('manager','deputy_manager','tribe_leader')` and `chapter_board` / `chapter_witness` designation checks, marked as out of scope for ADR-0087 and "tracked separately".
- **Impact:** When chapter-board style authority is granted only through V4 engagements, these governance document policies can silently deny access.
- **Proposta:** Create ADR-0088 or an equivalent backlog item for the final document-permissions V4 sweep; include smoke tests proving V4 chapter-board access before removing the carry gates.
- **Cross-ref:** ADR-0011, ADR-0087, migration `20260721000000`.
- **Follow-up p202 (issue #166):** ADR-0092 scaffolded (`docs/adr/ADR-0092-document-permissions-v4-sweep.md`) com 3 V3 policies identificadas + mapping V3→V4 actions + shadow window 48-72h + smoke 22 governance MCP tools. Implementation deferida para session dedicada após PM Q4 (deprecation horizon V3 policies).

### 30. GAP — Platform Guardian spec desatualizado: 15 invariantes / 83 ADRs / 289 tools — RESOLVED
- **Tipo:** gap · **Severity:** MEDIUM · **Effort:** XS
- **Trigger:** `.claude/agents/platform-guardian.md` still expects 15 invariants, 83 ADRs, and 289 MCP tools. Runtime/code reality is 16 invariants, 86 ADR files plus ADR-0082 reserved, and 293 MCP tools.
- **Impact:** Future guardian runs can produce false-positive drift reports or miss invariant Q in the expected set.
- **Fix:** Update the guardian spec pins to: 16 invariants (A1-A3, B-F, J-Q), MCP 293 tools, ADR coverage through ADR-0087.
- **Resolution p201 coordinator (2026-05-19):** Fixed in commit `bc14694f`. Guardian spec now pinned to 16 invariants, 293 tools, ADR-0087 coverage; subsequent guardian run (this session close) confirmed no drift.

### 31. ISSUE — `docs/RELEASE_LOG.md` sem backfill pós-Sprint 34
- **Tipo:** issue · **Severity:** HIGH · **Effort:** L for backfill / XS for process
- **Trigger:** Guardian p201 audit found release history not reflecting the V4 refactor era, MCP v2.x growth, LGPD cycle, selection AI/video screening, curation pipeline, and recent ADR/invariant additions.
- **Impact:** External auditability and internal onboarding depend on scattered git history instead of the formal release channel required by project rules.
- **Proposta:** Backfill 5-10 milestone entries, then restore sprint-closure discipline for release entries after production-impacting changes.

### 32. GAP — Missing contract tests for curation review RPCs
- **Tipo:** gap · **Severity:** MEDIUM · **Effort:** S
- **Trigger:** `complete_peer_review` and `complete_leader_review` shipped as part of the curation FSM work but remain without focused DB contract tests.
- **Impact:** Regressions in ADR-0086 curation state transitions can pass unnoticed.
- **Proposta:** Add contract tests for invalid assignee, leader approval transition to `curation_pending`, and invariant preservation after review workflow operations.

### 33. OPPORTUNITY — Comitê Curadoria workspace full scope still deferred
- **Tipo:** opportunity · **Severity:** LOW · **Effort:** L
- **Trigger:** Curadoria workspace board exists, but the broader OPP-196.D cross-pipeline RPC/UI tabs scope remains deferred.
- **Impact:** Curators still lack a unified queue across governance docs, manuals, webinars, and board items.
- **Proposta:** Prioritize only after curator feedback confirms the workspace board is being used.

### 34. GAP — `gamification_points` lacks `initiative_id` for strict semantic scoping — SCAFFOLDED (ADR-0088, p202)
- **Tipo:** gap · **Severity:** MEDIUM · **Effort:** M
- **Trigger:** ADR-0085 documents that XP metrics in `exec_cross_initiative_comparison` remain cohort-scoped because `gamification_points` has no `initiative_id`.
- **Impact:** Initiative/tribe gamification can overstate or misattribute XP across initiatives.
- **Proposta:** Add `initiative_id uuid` to `gamification_points` with backfill/trigger strategy from event or award context; create ADR if this becomes a semantic contract change.
- **Cross-ref:** ADR-0085, GAP-194.B.
- **Follow-up p202 (issue #166):** ADR-0088 scaffolded (`docs/adr/ADR-0088-gamification-points-initiative-scoping.md`) com schema change + backfill rules (4 sources) + trigger forward-strategy + RPC update plan + acceptance test. Implementation deferida para session dedicada após PM Q1 (NULLable forever vs eventual NOT NULL).

### 35. GAP — User-facing MCP docs drift from runtime tool inventory
- **Tipo:** gap · **Severity:** MEDIUM · **Effort:** XS
- **Trigger:** Runtime `tools/list` returns 293 tools and `/health` reports 293. `README.md` still says 284, while `docs/MCP_SETUP_GUIDE.md` still says 68 tools and "Available Tools (29 total)".
- **Impact:** AI/client onboarding docs understate capability and confuse QA baselines.
- **Fix:** Update `README.md` and `docs/MCP_SETUP_GUIDE.md`; avoid manually maintained exhaustive counts where possible and point to runtime `tools/list` as the source of truth.
- **Resolution p201 audit follow-up:** `README.md` and `docs/MCP_SETUP_GUIDE.md` updated to 293 tools; MCP guide now labels the table as representative examples and names `tools/list` as runtime source of truth.

### 36. GAP — MCP tool inventory source is manual and duplicated — RESOLVED (p202, 2026-05-19)
- **Tipo:** gap · **Severity:** MEDIUM · **Effort:** S
- **Trigger:** Runtime is 293 tools, `.claude/rules/mcp.md` is current, but README/MCP guide and old comments drifted. `supabase/functions/nucleo-mcp/index.ts` also still has a stale comment `Register 94 tools`.
- **Impact:** Audits rely on grep/manual counts and stale docs instead of a single canonical generated inventory.
- **Proposta:** Add a small QA script that calls `tools/list` and compares against `/health`, `.claude/rules/mcp.md`, README, and MCP setup docs.
- **Partial resolution p201 audit follow-up:** stale `Register 94 tools` comment updated to 293. QA script remains open.
- **Resolution p202 (issue #162 close):** `scripts/audit-mcp-tool-matrix.mjs` agora calls `tools/list` em runtime e cross-checks vs static parser de `index.ts`. Drift gate adicionado a `.claude/rules/mcp.md` §4 "Contract matrix drift". Output canonical em `docs/reference/MCP_TOOL_MATRIX.md` (markdown) + `docs/reference/mcp-tool-matrix.json` (structured). Re-run via `node scripts/audit-mcp-tool-matrix.mjs --runtime` antes de qualquer deploy ou após migrations que mudem RPC signatures. Drift atual: 0 (293 ≡ 293).

### 37. ISSUE — Debug instrumentation residue in `nucleo-mcp/index.ts` must not ship — RESOLVED
- **Tipo:** issue · **Severity:** HIGH before deploy · **Effort:** XS
- **Trigger:** Debug-mode instrumentation introduced `agentDebugLog(...)` calls posting to local session endpoint `127.0.0.1:7888` with session `edf848`.
- **Impact:** The fetch is fail-silent in production-like runtimes but is still debug residue, adds unnecessary request attempts, and leaks implementation detail into production code if deployed.
- **Status:** Intentionally left in place during active debug mode until the current reproduction/verification loop is closed. Must be removed before commit/deploy unless explicitly retained for a local-only debug run.
- **Guardrail:** Add pre-deploy grep/check for `agentDebugLog`, `X-Debug-Session-Id`, and `.cursor/debug-*.log` references in source.
- **Resolution p201 coordinator (2026-05-19):** Removed before `bc14694f`. Pre-commit grep for `agentDebugLog|X-Debug-Session-Id|127\.0\.0\.1:7888|edf848` against `supabase/functions/nucleo-mcp/index.ts` returned 0 hits; instrumentation never reached `origin/main`. Guardrail (pre-deploy grep) remains a backlog item for `.claude/rules/mcp.md`.

### 38. OPPORTUNITY — Semantic layer contracts for MCP domains
- **Tipo:** opportunity · **Severity:** MEDIUM · **Effort:** M
- **Trigger:** `nucleo-mcp/index.ts` exposes 293 tools from a monolithic file and mixes direct table reads (`members`, `public_members`, `events`, `project_boards`, `board_items`) with RPC-backed semantic operations. Runtime is healthy, but schema drift history shows failures occur when domain primitives migrate faster than MCP callsites.
- **Impact:** Future migrations can break MCP behavior while HTTP still returns 200, making failures visible only inside tool payloads or `mcp_usage_log`.
- **Proposta:** Define domain-level semantic contracts for `member`, `initiative`, `board`, `selection`, `governance`, `curation`, and `gamification`; prefer stable RPC/view envelopes for AI-facing tools; add smoke tests that call a representative tool per domain and assert envelope shape plus no `mcp_usage_log.success=false`.
- **Cross-ref:** ADR-0005, ADR-0007, ADR-0011, ADR-0012, ADR-0015, ADR-0085.
- **Follow-up p202 (issue #162 partial input ready):** `docs/reference/MCP_TOOL_MATRIX.md` agora documenta direct-table-access hotspots (24 tools, com `members`/`board_items`/`project_boards`/`events` no topo) + 83 canV4-gated + 4 external fetch + 4 service_role. Esse mapa é upstream para o semantic layer roadmap (issue #166). Próximo passo (issue #166): definir envelope contracts per-domain + smoke tests por domínio.
- **Follow-up p202 (issue #166 — roadmap ADOPTED):** `docs/architecture/SEMANTIC_LAYER_ROADMAP.md` adopted com inventory facts/dimensions/snapshots + 7-rank drift risk table + P0/P1/P2 prioritization. 5 P1 scaffolds em `docs/adr/`: ADR-0088 (gamification_points.initiative_id), ADR-0089 (champion_criteria_catalog), ADR-0090 (effective_cycle_bounds), ADR-0091 (tribe bridge remaining), ADR-0092 (document permissions V4 sweep). P2 (direct-table-MCP encapsulation + envelope contracts + per-domain smoke) carry para próximo roadmap pass quando P1 100% landed. Status: opportunity #38 RESOLVED como roadmap-format; implementation per-ADR triggers individual sessions.

### 39. ISSUE — Local Supabase stack cannot start from migrations — RESOLVED (p202, 2026-05-19)
- **Tipo:** issue · **Severity:** HIGH for local debug/QA · **Effort:** M
- **Trigger:** `supabase start` during p201 MCP debug failed while applying `00000000_baseline_rpcs.sql` with `ERROR: type "public.members" does not exist (SQLSTATE 42704)`. The failing statement creates `get_member_by_auth()` returning `SETOF public.members` before the `members` table exists in the local migration order.
- **Impact:** Local Edge Function debugging via `supabase functions serve` is blocked, forcing QA to rely on production/remoto logs and making debug instrumentation hard to verify before deployment.
- **Proposta:** Rework the local baseline migration order or split baseline RPCs so table types exist before functions returning table row types. Add a local-stack smoke check to pre-QA runbooks.
- **Extra evidence:** Direct Deno fallback also failed because `deno` is not installed in the local PATH, so the Supabase CLI local stack is currently the only intended path for Edge Function local execution.
- **Resolution p202 (issue #164 close, PM Option C):** Split baseline RPCs into post-schema migration via additive path. New file `supabase/migrations/20260723000000_baseline_rpcs_after_schema.sql` contém os 14 RPCs (CREATE OR REPLACE idempotente) com timestamp posterior ao schema; `supabase/migrations/00000000_baseline_rpcs.sql` reduzido a marker/deprecation header (zero DDL, preserva schema_migrations record). Production effect = zero (idempotent reapply). Local stack agora não falha em 00000000; mas ainda requer `supabase db pull --linked` one-time bootstrap pra capturar schema (members/events/etc não existem em nenhuma migration do repo — historicamente foi criado direto em prod). Runbook completo em `docs/operations/LOCAL_QA.md` (novo) com Workflow A remote-linked como default + Workflow B local stack opcional. Link em `.claude/rules/deploy.md` + `AGENTS.md`. Deno install instructions inclusas para contributors que querem `supabase functions serve`.

### 40. ISSUE — Cloudflare Browser Integrity blocks MCP/OAuth discovery for banned client signatures — RESOLVED (p202, 2026-05-19)
- **Tipo:** issue · **Severity:** HIGH for MCP client onboarding · **Effort:** S
- **Trigger:** p201 MCP connection debug reproduced against production domain. Requests to `https://nucleoia.vitormr.dev/mcp`, `/.well-known/oauth-protected-resource`, and `/.well-known/oauth-authorization-server` with a default Python client signature returned Cloudflare `403` / `Error 1010: browser_signature_banned` before reaching Astro. The same protected-resource endpoint returned `200` with browser/Claude-like/curl user-agents; `/mcp` with a Claude-like user-agent returned the expected `401` plus `WWW-Authenticate: Bearer resource_metadata="https://nucleoia.vitormr.dev/.well-known/oauth-protected-resource"`.
- **Impact:** Some AI clients can fail during initial MCP connection/discovery without any `mcp_usage_log` entry, because Cloudflare blocks them before the request reaches `/mcp` or OAuth routes.
- **Proposta:** Add Cloudflare WAF/Bot/BIC skip rule for MCP/OAuth bootstrap routes (`/mcp`, `/.well-known/oauth-*`, `/oauth/*`) or otherwise allow known MCP client signatures. Re-test with the exact Claude.ai connector user-agent/fingerprint after rule change.
- **Cross-ref:** ADR-0018 MCP threat model, CLAUDE.md decision #2 (custom domain used to avoid `.workers.dev` Bot Fight Mode issues).
- **Follow-up p201 21:01Z:** Rule not yet effective for the blocked signature. Retest without user-agent still returned `403 Error 1010` for `GET /mcp` (Ray `9fe609cc68361518`), `GET /.well-known/oauth-protected-resource` (Ray `9fe609ccdfea7bf3`), `GET /.well-known/oauth-authorization-server` (Ray `9fe609cd4f7b6ac3`), and `POST /mcp` initialize (Ray `9fe609cdbc83181e`). Expected post-fix behavior: `/.well-known/*` returns `200`; unauthenticated `/mcp` returns `401` with `WWW-Authenticate`.
- **Follow-up p201 21:02Z:** Still blocked. Retest without user-agent returned `403 Error 1010` for `GET /mcp` (Ray `9fe60b21aeaf181c`), `POST /mcp` initialize (Ray `9fe60b220e7d1824`), `GET /.well-known/oauth-protected-resource` (Ray `9fe60b229ebf1820`), `GET /.well-known/oauth-authorization-server` (Ray `9fe60b22f8d41521`), and `GET /oauth/authorize?...` (Ray `9fe60b236fc71818`). This confirms the skip/allow rule must include both `.well-known` and `/oauth/*`, and must skip Browser Integrity/Bot checks, not only WAF custom rules.
- **Cloudflare docs check:** Official Error 1010 docs state the cause is access denied based on browser signature and the owner-side resolution is to turn off Browser Integrity Check in Security settings. Cloudflare WAF docs also confirm custom rules can use `Skip`, but the selected skip options must include the relevant security features (Bot/BIC/managed challenge as applicable).
- **Follow-up p201 21:04Z:** Still blocked after another reproduction. Retest without user-agent returned `403 Error 1010` for `GET /mcp` (Ray `9fe60dc55ef31516`), `POST /mcp` initialize (Ray `9fe60dc61b331826`), `GET /.well-known/oauth-protected-resource` (Ray `9fe60dc69abc151c`), `GET /.well-known/oauth-authorization-server` (Ray `9fe60dc71aec1518`), and `GET /oauth/authorize?...` (Ray `9fe60dc7a8ad151e`). No request reaches Astro, so no `mcp_usage_log` or app-side debug log is expected.
- **Follow-up p201 21:05Z:** Browser-like and `Claude-User/1.0` user-agents pass the bootstrap chain: `GET /mcp` returns expected `401 + WWW-Authenticate`, `/.well-known/oauth-*` returns `200`, `POST /oauth/register` returns `201`, and `/oauth/authorize` renders consent `200`. `Python-urllib` default signature remains blocked by `1010`. If the real Claude connector still fails, capture its exact error/Ray ID because its production fingerprint may differ from the synthetic `Claude-User/1.0` test.
- **Follow-up p201 21:07Z:** App-side telemetry still empty (`mcp_usage_log` last 5 min = 0 rows). Synthetic comparison unchanged: blocked default signature receives `403 Error 1010` on `/mcp` (Ray `9fe612d38c4b1514`), while `Claude-User/1.0` receives expected `401 + WWW-Authenticate`. Next required artifact is the Ray ID/error from the real Claude connector or Cloudflare Security Events filtered by path `/mcp` and action `browser_signature_banned`.
- **Follow-up p201 21:08Z:** Cloudflare Worker Observability confirms only requests that pass the edge reach Worker `platform`: `/mcp` appears as `401` (for allowed synthetic signatures), `/.well-known/oauth-*` as `200`, `/oauth/authorize` as `302`, `/oauth/consent` as `200`. The blocked synthetic Ray `9fe6142a0c891518` does not appear in Worker logs, confirming the `1010` decision happens before Worker execution. Real Claude connector failures must be found in Cloudflare Security Events, not Worker Observability or `mcp_usage_log`.
- **Follow-up p202 2026-05-19 (~21:53Z):** Re-confirmação pré-aplicação de regra. `Python-urllib/3.11` UA reproduz `HTTP 403` em duas rotas: `/.well-known/oauth-authorization-server` (Ray `9fe75d560886181e-RIC`) e `/oauth/authorize` (Ray `9fe75d585a2f181e-RIC`). UAs alternativas confirmam comportamento pré-fix esperado: default `curl/X.Y.Z` → `200` em `/.well-known/oauth-protected-resource` (Ray `9fe75d569a9a6ac3-RIC`); empty UA → `401` em `POST /mcp` (Ray `9fe75d573a501826-RIC`); `Claude-User/1.0` → `200` (Ray `9fe75d57cfb81820-RIC`). Issue persistente; spec completa de regra preparada em `docs/infra/CLOUDFLARE_MCP_RULES.md` (WAF custom rule `mcp-oauth-skip-bic` + rate limit `mcp-rate-limit`). GC-146 atualizada com `Status: Implementado (p202)` referenciando este audit log.
- **Resolution p202 (Rule 1 applied, smoke green):** WAF Custom Rule `mcp-oauth-skip-bic` aplicada via dashboard Cloudflare zone `vitormr.dev` (PM, 2026-05-19). Skip components marcados: Browser Integrity Check + All Super Bot Fight Mode Rules (cobre Bot Fight Mode + Super Bot Fight Mode). Skip components NÃO marcados (intencionais): Rate Limiting, Managed Rules, custom rules — mantém defesa em profundidade.
- **Smoke pós-fix p202 (~21:55Z) — todos 4 paths PASS com `Python-urllib/3.11` UA (mesmo UA que pré-fix retornava 403):**
  - `GET /.well-known/oauth-authorization-server` → **HTTP 200** (Ray `9fe793db1e9b151a-RIC`) — era 403 Ray `9fe75d560886181e-RIC`
  - `GET /oauth/authorize?...` → **HTTP 302** (redirect to login, comportamento OAuth correto) (Ray `9fe793dbab751514-RIC`) — era 403 Ray `9fe75d585a2f181e-RIC`
  - `POST /mcp` initialize → **HTTP/2 401** + `WWW-Authenticate: Bearer resource_metadata="https://nucleoia.vitormr.dev/.well-known/oauth-protected-resource"` (Ray `9fe793dc4c057bea-RIC`) — comportamento correto (sem token Bearer)
  - `GET /.well-known/oauth-protected-resource` → **HTTP 200** (Ray `9fe793dcdc437bea-RIC`)
- **Rule 2 applied (Rate Limit, Free plan adapted, p202 2026-05-19):** `mcp-rate-limit` ativa via Cloudflare Rate Limiting rules. Expression: `(http.host eq "nucleoia.vitormr.dev") and starts_with(http.request.uri.path, "/mcp")`. Threshold: 50 requests / 10 segundos per IP, Action Block, Duration 10s. Free plan não permite janelas maiores que 10s; original spec 100 req/1min foi adaptada mantendo ordem de magnitude (~300 req/min effective). Backlog: re-tunar para 100 req/1min se PM upgradar Pro plan futuro.
- **Burst smoke pós-Rule-2 (~21:58Z):** Loop de 120 requests sem auth para `POST /mcp`. Resultado exato: **50 × HTTP 401** (primeiros, dentro do window) + **70 × HTTP 429** (a partir do 51º, rate-limited). Sample 429 Ray IDs capturados: `9fe7a4903c0c151e-RIC`, `9fe7a490afc97bea-RIC`, `9fe7a4912df87bf3-RIC`. Comportamento exatamente conforme configuração — match contagem 50+70=120 total.
- **Sanity check legitimate UA (~21:58Z):** Após window recovery 12s, `Claude-User/1.0` UA em `POST /mcp` retorna HTTP/2 401 + `WWW-Authenticate: Bearer resource_metadata=...` (Ray `9fe7a4dd7fed6ac4-RIC`). Browser-like fingerprints continuam funcionando normalmente; Claude.ai connector + outros clientes legítimos não foram afetados.
- **Status:** RESOLVED. /mcp e /.well-known/oauth-* e /oauth/* agora aceitam fingerprints programáticos legítimos (Python-urllib, etc.) sem 1010. Rate limit 50/10s protege contra burst abuse single-IP. OAuth/PKCE/JWT/RLS continuam como gates reais de autorização.

### 41. ISSUE — `/rest/v1/rpc/get_attendance_grid` returns HTTP 400 — RESOLVED
- **Tipo:** issue · **Severity:** HIGH user-facing attendance page · **Effort:** S/M
- **Trigger:** Browser/runtime console reported `ldrfrvwhxsmgaabwmaik.supabase.co/rest/v1/rpc/get_attendance_grid:1 Failed to load resource: the server responded with a status of 400 ()`.
- **Runtime evidence:** Live DB contract check confirms function exists as `public.get_attendance_grid(p_tribe_id integer, p_event_type text) RETURNS jsonb`. Supabase API log confirms `POST /rest/v1/rpc/get_attendance_grid` returned 400 at `2026-05-19T21:08:09.148Z` (request id `8ccdde21-432b-4b57-be92-0d85bf1b0a13`). Postgres log at the same timestamp reports `ERROR: column reference "status" is ambiguous`.
- **Root cause:** Migration `20260722000000_p201_bug_201_a_cancelled_event_attendance_display.sql` added `e.status` to `grid_events` while `cell_status` already emitted a `status` column. Nested `detractor_calc` subqueries still selected bare `status` after joining `cell_status` and `grid_events`.
- **Impact:** Attendance grid can fail to load for affected authenticated users/routes even though the RPC exists.
- **Fix:** Migration `20260722010000_p201_fix_attendance_grid_status_ambiguity.sql` qualifies nested selectors as `cs2.status` and `cs3.status` without changing the RPC signature.
- **Resolution p201 live fix:** SQL applied directly via Supabase MCP because `supabase db push` is blocked by older remote-only migration history drift; migration history repaired with `supabase migration repair --status applied 20260722010000`.
- **Validation:** `pg_get_functiondef` confirms both `SELECT cs2.status` and `SELECT cs3.status` are live; simulated authenticated SQL call returns a JSON object with `summary`, `events`, and `tribes`; `check_schema_invariants()` remains 16/16 with 0 violations. Post-fix browser reproduction still required to confirm no new PostgREST 400 in API logs.
- **Follow-up p201 21:34Z:** After user reproduction, Supabase API logs contained no new `POST /rest/v1/rpc/get_attendance_grid` 400 entries and Postgres logs contained no new ambiguous `status` error. Function body still confirmed live with `cs2.status`/`cs3.status`. Visual/browser confirmation still pending.
- **Resolution p201 coordinator (2026-05-19):** Migration `20260722010000` committed in `9c4a01db`; live function body confirmed with `cs2.status`/`cs3.status` qualifiers; `check_schema_invariants()` 16/16 with 0 violations at session close.

### 42. ISSUE — Tribe attendance grid shows N/A for empty same-day tribe meeting — RESOLVED
- **Tipo:** issue · **Severity:** HIGH user-facing tribe leader attendance · **Effort:** S
- **Trigger:** Marcos Klemz reported that the 2026-05-19 Tribe 7 meeting showed `—`/N/A for all participants, including himself, while the global/admin view showed `X`/absence until attendance is marked.
- **Runtime evidence:** Event `4b31e97d-2b63-4548-91af-65adbec6fb46` (`Governança & Trustworthy AI — Reunião Semanal`) is `type='tribo'`, `status='scheduled'`, initiative `legacy_tribe_id=7`. Marcos and active Tribe 7 members are eligible and have no attendance rows. Before fix, `get_tribe_attendance_grid(7, NULL)` returned `na` for Marcos/Antonio Marcos because `cell_status` had `WHEN COALESCE(erc.row_count, 0) = 0 THEN 'na'`.
- **Root cause:** Tribe-specific RPC treated an event with zero attendance rows as not applicable. For same-day/past eligible events, zero rows means "not marked yet" and should render as `absent`; future events are already handled by the `ge.date > CURRENT_DATE` branch.
- **Fix:** Migration `20260722020000_p201_fix_tribe_attendance_empty_event_absent.sql` removes the empty-event `na` branch from `get_tribe_attendance_grid`.
- **Validation:** `pg_get_functiondef` confirms the branch is gone; simulated Marcos auth returns `today_status='absent'` for the Tribe 7 event; `check_schema_invariants()` remains 16/16 with 0 violations.
- **Rollback:** Reinsert `WHEN COALESCE(erc.row_count, 0) = 0 THEN 'na'` before the final `ELSE CASE` in `cell_status` of `get_tribe_attendance_grid`.
- **Resolution p201 coordinator (2026-05-19):** Migration `20260722020000` committed in `9c4a01db`; live function body confirmed via `pg_get_functiondef` with the empty-event `na` branch removed. See LOW-201.A for an idempotence note on the DO-block text-patch approach.

### 43. ISSUE — Curatorship UI gate ignores V4 `curate_content` — RESOLVED
- **Tipo:** issue · **Severity:** HIGH for curator access · **Effort:** XS
- **Trigger:** Roberto reported inability to access admin curatorship. Live DB confirms Roberto and Sarah both have `can_by_member(..., 'curate_content') = true` and `participate_in_governance_review = true` via active Curadoria engagements.
- **Root cause:** `CuratorshipBoardIsland` derived access only from legacy `hasPermission(authMember, 'admin.curation')`, which depends on local role/designation permission maps. It did not check the V4 capability cache populated by `get_caller_capabilities()`.
- **Fix:** `src/components/boards/CuratorshipBoardIsland.tsx` now accepts `canFor('curate_content')` or `canFor('participate_in_governance_review')` in addition to the legacy `hasPermission` check. `src/components/nav/AdminNav.astro` now applies the same V4 curatorship exception for the admin subnav link.
- **Validation:** `ReadLints` clean. DB evidence: Roberto/Sarah have V4 curation actions. Browser confirmation pending.
- **Follow-up:** `AdminNav` fallback is disabled during superadmin simulation (`!isSimulating`) so simulated profiles do not inherit the real user's capability cache.
- **Rollback:** Revert the import/use of `canFor` and restore `return hasPermission(authMember, 'admin.curation')` plus the legacy AdminNav permission map only; this would reintroduce the V4 access bug for curators whose UI permission map is stale.
- **Resolution p201 coordinator (2026-05-19):** Shipped in commits `a6f10cdb` (initial V4 fallback) + `<HEAD>` (MED-201.A guard for superadmin simulation). See MED-201.A (item #45) for the followon.

### 44. GAP — Herlon `study_group_owner/leader` active but non-authoritative
- **Tipo:** gap · **Severity:** MEDIUM/HIGH permission architecture · **Effort:** M
- **Trigger:** Herlon appears as `operational_role='observer'` with no V4 capabilities, despite active engagement `study_group_owner` / `leader` in `Preparatório CPMAI — Ciclo 3 (2026)`.
- **Runtime evidence:** `engagement_kind_permissions` grants `study_group_owner/leader` actions (`manage_event`, `manage_member`, `write`, `write_board`, `participate_in_governance_review`, etc.), but `auth_engagements` shows Herlon's `study_group_owner/leader` row as `requires_agreement=true`, `agreement_certificate_id=NULL`, `is_authoritative=false`. Therefore `get_caller_capabilities()` returns empty `org_actions`, `tribe_actions`, and `initiative_actions`.
- **Impact:** Herlon is visibly a leader of a study group but receives no operational capabilities, and the single-value `operational_role` cache remains `observer`.
- **Decision needed:** Either (a) issue/sign the required agreement/certificate for the study group owner engagement; (b) amend `engagement_kind_permissions` / agreement requirements for `study_group_owner`; or (c) treat this as intentional pending-authority state and add UX explaining "leadership pending agreement".
- **Cross-ref:** Existing Item #4 Track E root and ADR-0080 pending cutover.
- **Follow-up p202:** Investigation by Claude Code confirmed Herlon did **not** receive or sign a current volunteer agreement/certificate. The active term/template exists and 41 volunteers already signed it, while newer documents are under review. PM position: Herlon should sign the current term now; if/when the new term is approved, he signs an addendum or the new term as applicable.
- **Expanded scope:** This is not just Herlon. The April admin_attestation batch covered only `engagement_kind='volunteer'`; special engagement kinds are orphaned from certificate issuance. Approximate active missing-cert backlog: `chapter_board/board_member` (9), `ambassador` (12), `workgroup_member/researcher` (6), `observer/observer` (5), `sponsor/sponsor` (5), `chapter_board/liaison` (4), `committee_*` (6), `study_group_owner/leader` (1 — Herlon), plus other cases. `volunteer/researcher`, `volunteer/leader`, `volunteer/co_gp` are covered.
- **Decision status:** Deferred for PM/team review. Do not shortcut authority by toggling `is_authoritative`; fix issuance/onboarding flow first.
- **Cross-ref:** Recent migration `20260722000000_p201_bug_201_a_cancelled_event_attendance_display.sql` touched `get_attendance_grid`; regression check should compare before/after payload shape and function signature.

### 45. MED-201.A — CuratorshipBoardIsland canFor() inconsistent with AdminNav under superadmin simulation — RESOLVED
- **Tipo:** issue (UX inconsistency) · **Severity:** MEDIUM · **Effort:** XS
- **Trigger:** Council code-reviewer p201 close (commit `a6f10cdb` introduced `canFor('curate_content')` fallback in CuratorshipBoardIsland without the `!isSimulating` guard that AdminNav already had). The capability cache is module-level and reflects the real user, so when a superadmin simulated a tier without curation access the legacy `hasPermission` correctly returned false but the V4 fallback returned true, rendering the curatorship UI inconsistently with the simulated tier.
- **Impact:** UX-only inconsistency (no security breach — DB RLS still uses real `auth.uid()`). Confuses simulation-based QA for any tier below curator.
- **Fix:** Add `getSimulation().active` gate around the `canFor` branch, mirroring `AdminNav.astro` line 122. Legacy `hasPermission(authMember, 'admin.curation')` already honours simulation via `getSimulation()` internally.
- **Resolution p201 coordinator (2026-05-19):** Shipped in `<HEAD>` together with the lane-naming cleanup and the housekeeping resolutions in this section.

### 46. MED-201.B — get_attendance_grid eligibility CTE preserves V3 operational_role hardcoded lists
- **Tipo:** gap (ADR-0011 carry) · **Severity:** MEDIUM · **Effort:** M
- **Trigger:** Council platform-guardian + code-reviewer p201 close both flagged that `eligibility` CTE in `get_attendance_grid` (lines 90-92 of `20260722010000`) preserves V3-style hardcoded role lists: `m.operational_role IN ('manager','deputy_manager')`, `m.operational_role IN ('manager','deputy_manager','tribe_leader')`, `m.designations && ARRAY['comms_team','comms_leader','comms_member']`.
- **Classification:** Pre-existing carry, not a regression introduced by p201. The hotfix migration only fixed `status` ambiguity; the eligibility logic was identical to migration `20260722000000`. The predicates are event eligibility classification (who should appear on the grid), not authority gates — caller authority uses `can_by_member()` correctly. ADR-0011 spirit (no hardcoded role lists in SECURITY DEFINER) applies more directly to auth gates than to eligibility filters, but the inconsistency remains.
- **Impact:** When V4 grants `manage_event` / `tribe_leader` capabilities through engagements without flipping the cached `operational_role`, eligibility classification may understate or misattribute. Limited blast radius because the cache trigger `sync_operational_role_cache` keeps role aligned in typical paths.
- **Proposta:** Refactor eligibility to derive from `auth_engagements` (or designations source-of-truth) instead of cached `operational_role`. Header of any future migration that touches this function should reference this item.
- **Cross-ref:** ADR-0011 (V4 cutover invariants), migration `20260722010000` lines 90-92.

### 47. LOW-201.A — get_tribe_attendance_grid DO-block text-patch idempotence is whitespace-sensitive
- **Tipo:** opportunity (migration robustness) · **Severity:** LOW · **Effort:** XS
- **Trigger:** Council code-reviewer flagged that `20260722020000_p201_fix_tribe_attendance_empty_event_absent.sql` uses `pg_get_functiondef` + `LIKE` + `replace()` to remove a single line from the live function body. The `LIKE` precondition guards against re-apply, but the `replace()` is whitespace-sensitive (exact string `'        WHEN COALESCE(erc.row_count, 0) = 0 THEN \'na\'\n        ELSE CASE'`). If the live body's indentation drifts (tab vs spaces, trailing whitespace), the `LIKE` may still match while `replace()` silently fails, leaving the bug in place with no error raised.
- **Impact:** Low for this specific migration (live body is known and matches), but the pattern is fragile if reused.
- **Proposta:** Prefer full `CREATE OR REPLACE FUNCTION` (the pattern used by `20260722010000`) for future similar fixes; or add a post-patch assertion that confirms the new body no longer contains the removed string.
- **Cross-ref:** Migration `20260722020000` lines 45-53.

### 48. P0 — Selection approval UI bypasses complete lifecycle orchestration
- **Tipo:** issue/architecture · **Severity:** CRITICAL · **Effort:** L
- **Trigger:** Lifecycle audit found `/admin/selection` approving via `admin_update_application`, while the richer `finalize_decisions` path is not referenced by the frontend.
- **Impact:** Approval from the real admin UI can update application/member status without guaranteeing the complete side effects expected by the volunteer lifecycle: new `members`, canonical onboarding seed, V4 `persons`, `engagements`, notifications, agreement issuance and audit trace.
- **Production evidence (2026-05-19):** 38 applications are `approved`/`converted`; 1 converted application has no matching `members` row by email. Among the 37 matched members, 0 are missing `person_id`.
- **Proposta:** Introduce a canonical approval RPC (`approve_selection_application` or equivalent) and move UI/MCP/bulk actions to it. Deprecate or wrap `admin_update_application` and `finalize_decisions` so there is one source of truth.
- **Validation gate:** Contract test for "candidate approved from UI" must assert `selection_applications`, `members`, `persons`, `engagements`, onboarding and notification effects.
- **Cross-ref:** GitHub #179; `docs/audit/P201_MCP_ARCHITECTURE_AUDIT.md` section 6; `tests/contracts/selection-interview-decision.test.mjs`.

### 49. P0 — Approved members can remain outside authoritative V4 graph
- **Tipo:** gap · **Severity:** CRITICAL · **Effort:** M/L
- **Trigger:** Lifecycle audit found approval paths that do not guarantee `members.person_id` and do not provision `engagements` linked to `selection_application_id`.
- **Impact:** A member may look approved or active through legacy/cache fields while `can()` / `can_by_member()` returns no operational capability. Herlon is the visible instance of the broader pending-authority class, but this also affects future approvals and re-engagements.
- **Production evidence (2026-05-19):** 52 active `auth_engagements` require agreement; 16 are missing `agreement_certificate_id` and are non-authoritative. Current pending mix: `ambassador/ambassador` (6), `ambassador/founder` (6), `study_group_owner/leader` (1), `study_group_participant/participant` (1), `volunteer/coordinator` (1), `volunteer/manager` (1).
- **Proposta:** Add an invariant/backfill strategy for approved/converted applicants: ensure `person_id`, create scoped engagement from template, link `engagements.selection_application_id`, and surface explicit waivers where an engagement is intentionally non-authoritative.
- **Validation gate:** Extend schema invariants or add DB-aware contract tests for approved applications without `person_id` / engagement.
- **Cross-ref:** GitHub #180; ADR-0007, ADR-0011, p170 VEP engagement linkage, item #44.

### 50. P0 — `counter_signature_hash` is computed but not persisted
- **Tipo:** security/auditability issue · **Severity:** CRITICAL for formal non-repudiation · **Effort:** S/M
- **Trigger:** Certificate governance audit found `counter_sign_certificate()` computes a counter-signature hash but returns it to the caller without writing it to the certificate row.
- **Impact:** The platform records who countersigned and when, but the cryptographic proof of the counter-signature is not persisted. Operational audit remains usable; formal non-repudiation claims should remain conditional until fixed.
- **Production evidence (2026-05-19):** `certificates` has 42 rows, 33 with `counter_signed_at`, and no `counter_signature_hash` column. Function `counter_sign_certificate()` computes `v_hash`, updates only `counter_signed_by/counter_signed_at`, and returns the hash in JSON.
- **Proposta:** Add/persist `counter_signature_hash` (or use existing column if present but unwritten), update `counter_sign_certificate()`, add audit log assertion and regression test.
- **Validation gate:** Counter-sign a certificate in test and assert persisted hash, audit log row, notification, and unchanged member-facing certificate payload.
- **Cross-ref:** GitHub #181; `docs/project-governance/P202_AGREEMENT_ISSUANCE_GAP.md`, certificates RPC cluster.

### 51. P1 — Volunteer agreement evidence fields are incomplete
- **Tipo:** compliance gap · **Severity:** HIGH · **Effort:** M
- **Trigger:** Certificate governance audit found `signed_ip` and `signed_user_agent` columns exist but are not populated by the Termo flow. It also raised a period derivation concern that needed live verification.
- **Production evidence (2026-05-19):** all 42 issued/signed certificates have `signed_ip IS NULL` and `signed_user_agent IS NULL`; 1 certificate is missing `signature_hash`. Live `sign_volunteer_agreement()` derives `period_end` from VEP/cycle/history rather than a simple 30-Jun hardcode, but 1 historical certificate still has `period_end='2026-06-30'`.
- **Impact:** Evidence package for signature context is weaker than the schema suggests. Period derivation is mostly correct in the live function, but legacy data still needs review/backfill.
- **Proposta:** Capture IP/user-agent through a safe server-side path or document these columns as intentionally unused; audit/backfill the residual certificate with missing hash and the historical 30-Jun period; keep tests for period derivation.
- **Validation gate:** New signature test must assert IP/user-agent handling decision, period derivation and user export payload shape.
- **Cross-ref:** GitHub #181; LGPD Art. 18 workflow, `sign_volunteer_agreement`, `get_my_signatures`.

### 52. P1 — Lifecycle cron/campaign coverage is incomplete for special kinds and renewals
- **Tipo:** gap · **Severity:** HIGH · **Effort:** M
- **Trigger:** Crons/campaigns audit mapped existing notification routines but found no consistent automation for special engagement agreement issuance, pending-authority reminders, renewal reminders and re-engagement communication.
- **Impact:** Volunteers can be approved or assigned to leadership-like engagements without receiving the right agreement/onboarding communication. Failures appear as permission problems instead of lifecycle state problems.
- **Production evidence (2026-05-19):** among 16 active pending-agreement engagements, 14 have a detectable term/agreement/certificate notification and 2 do not (`ambassador/founder` and `study_group_participant/participant`).
- **Proposta:** Build a lifecycle transition matrix (`selected`, `approved`, `agreement_pending`, `signed`, `countersigned`, `authoritative`, `renewal_due`, `offboarded`) mapped to cron/campaign/RPC owners.
- **Validation gate:** For each transition, define owner table, idempotency key, notification template and observable audit log.
- **Cross-ref:** GitHub #182; `/admin/campaigns`, Resend send pipeline, p202 agreement issuance.

### 53. P1 — MCP lacks canonical lifecycle tools for approval and agreement workflows
- **Tipo:** semantic-layer gap · **Severity:** HIGH · **Effort:** M
- **Trigger:** MCP lifecycle audit found tools around members, selection, interviews, initiatives and offboarding, but no canonical wrappers for `finalize_decisions`, agreement signing/issuance/countersign, or the proposed approval orchestration.
- **Impact:** AI agents can inspect lifecycle state and operate around it, but cannot safely complete the critical transition from candidate to authoritative volunteer without falling back to partial tools or manual admin actions.
- **Proposta:** After the approval/agreement RPC contracts are stabilized, add MCP tools with explicit gates and stable envelopes: approve application, list pending agreement engagements, issue current agreement, countersign certificate, explain pending authority.
- **Validation gate:** MCP contract matrix must include dependencies, gates, expected payload and smoke test for each lifecycle tool.
- **Cross-ref:** GitHub #183, #162, #166; `supabase/functions/nucleo-mcp/index.ts`, `docs/audit/P201_MCP_ARCHITECTURE_AUDIT.md`.

### 54. P1 — Admin surfaces do not present pending-authority state coherently
- **Tipo:** UX/governance gap · **Severity:** HIGH · **Effort:** M
- **Trigger:** Admin surfaces audit found `/admin/selection`, `/admin/members`, `/admin/certificates` and related panels each show fragments of the lifecycle, but they do not explain "engagement active, authority blocked pending agreement/countersign" as a coherent state.
- **Impact:** GP/admins may interpret Herlon-style cases as permission bugs or manually adjust roles, instead of completing the agreement flow that unlocks V4 authority.
- **Proposta:** Add a shared pending-authority component or dashboard card sourced from `auth_engagements` / pending agreement query. Show next action, responsible role and link to certificate/term workflow.
- **Validation gate:** Herlon-class fixture should show explicit pending agreement state in member detail/admin certificate surfaces, without granting capabilities before signature/countersign.
- **Cross-ref:** Items #44, #177, #48-#53.

### 55. P1 — Opportunity: canonical `volunteer_lifecycle_state` semantic layer
- **Tipo:** opportunity · **Severity:** HIGH · **Effort:** M
- **Trigger:** Gap assessment showed the same lifecycle state is inferred separately from `selection_applications`, `members`, `persons`, `engagements`, `auth_engagements`, `certificates`, `notifications`, onboarding tables and offboarding records.
- **Impact:** Admin UI, MCP tools, crons/campaigns and QA queries can disagree about whether a person is a candidate, approved, pending member creation, pending agreement, pending countersign, authoritative, renewal due, offboarded or re-engaging.
- **Proposta:** Create a stable view/RPC such as `get_volunteer_lifecycle_state()` or `volunteer_lifecycle_state` with one row per person/application engagement context and an explicit enum-like state. Use it as the semantic source for admin dashboards, MCP summaries, notifications and smoke tests.
- **Validation gate:** State machine covers at least: `candidate`, `approved_pending_member`, `approved_pending_person`, `agreement_pending`, `countersign_pending`, `authoritative`, `renewal_due`, `offboarded`, `reengagement_pending`.
- **Cross-ref:** GitHub #166, #179, #180, #182, #183; `docs/audit/P201_MCP_ARCHITECTURE_AUDIT.md` section 6.

### 56. P0 — Curatorship queue RPC gates still require `write_board`, blocking V4 curators
- **Tipo:** issue · **Severity:** CRITICAL for curator access · **Effort:** S/M
- **Trigger:** p203 curadoria audit after Roberto reported "Sem acesso". Frontend gate was fixed in p201 to accept `canFor('curate_content')`, but live RPC bodies for `get_curation_dashboard()` and `list_curation_pending_board_items()` still require `can_by_member(v_member_id, 'write_board')`.
- **Production evidence (2026-05-19):** Fabricio has `curate_content=true` and `write_board=true`; Roberto and Sarah have `curate_content=true` but `write_board=false`. Therefore the UI may allow access while the backend queue denies or errors.
- **Impact:** Curators without broad board-write authority cannot reliably load `/admin/curatorship`, despite ADR-0087 making `curate_content` the canonical authority.
- **Proposta:** Change reader RPC gates to `curate_content OR participate_in_governance_review OR manage_member` (or a narrower accepted contract), keeping write gates separate for mutations.
- **Validation gate:** Roberto/Sarah persona smoke can load queue but cannot mutate outside allowed curation actions.
- **Cross-ref:** GitHub #185; `docs/audit/P203_CURATION_JOURNEY_AUDIT.md` C-001; ADR-0087; issue #161.

### 57. P0 — Canonical `submit_for_curation` does not notify the Comitê de Curadoria
- **Tipo:** issue · **Severity:** CRITICAL for operational workflow · **Effort:** M
- **Trigger:** ADR-0086 says tribe leaders should submit without naming curators. Live SQL/function audit shows `submit_for_curation(p_item_id)` only updates status and lifecycle events; notification trigger only notifies existing `board_item_assignments` rows.
- **Production evidence (2026-05-19):** Live item `642fe90f` has 11 notifications, all tied to assignment/status triggers because curators were assigned. The three V4 curators each got digest/in-app notifications (`assignment_new`, `card_assigned`, `card_moved`), all `delivery_mode='digest_weekly'`, `email_sent_at=NULL`. If the canonical button is used without assignments, there may be zero curator recipients.
- **Impact:** New submissions can silently enter `curation_pending` without curators receiving email or explicit committee broadcast, making SLA dependent on someone manually checking `/admin/curatorship`.
- **Proposta:** Add idempotent committee broadcast when a card enters `curation_pending`, targeting active members with `can_by_member('curate_content')`; decide `transactional_immediate` vs digest explicitly.
- **Validation gate:** Submitting via button creates notification rows for all active curators and expected delivery mode; no duplicate notifications on retry.
- **Cross-ref:** GitHub #186; `docs/audit/P203_CURATION_JOURNEY_AUDIT.md` C-002; ADR-0086.

### 58. P1 — `curation_reviewer` picker still filters by V3 `members.designations`
- **Tipo:** gap · **Severity:** HIGH · **Effort:** S/M
- **Trigger:** `MemberPickerMulti.tsx` filters `selectedRole === 'curation_reviewer'` with `m.designations?.includes('curator')`.
- **Impact:** A new curator onboarded through V4 engagement permissions (`curate_content`) but without legacy designation will not appear as selectable reviewer in the card UI.
- **Proposta:** Use V4 eligibility (`can_curate_content` payload, dedicated RPC, or semantic reviewer list) instead of raw designation filtering.
- **Validation gate:** A member with `curate_content=true` and no `curator` designation appears in the picker; a non-curator does not.
- **Cross-ref:** GitHub #187; `docs/audit/P203_CURATION_JOURNEY_AUDIT.md` C-003; ADR-0087.

### 59. P1 — MCP curatorship surface is admin-only and lacks curation actions
- **Tipo:** semantic-layer gap · **Severity:** HIGH · **Effort:** M
- **Trigger:** MCP tool `get_curation_dashboard` is gated by `manage_member` and calls a reader RPC that currently requires `write_board`; MCP has no canonical tools for `submit_for_curation`, `submit_curation_review`, `complete_peer_review`, or `complete_leader_review`.
- **Impact:** AI agents cannot assist curators with the real operational queue unless they have admin-style authority, and cannot perform or inspect the structured review flow through stable curation-native contracts.
- **Proposta:** After SQL/RPC gates are corrected, add MCP tools for list queue, explain item state, submit review, return with feedback, and summarize SLA using a stable `curation_queue_state` envelope.
- **Validation gate:** Curator persona can call MCP queue read; non-curator cannot; mutations use explicit V4 gates.
- **Cross-ref:** GitHub #188, #162, #166; `docs/audit/P203_CURATION_JOURNEY_AUDIT.md` C-004.

### 60. P2 — Card curation pipeline visual still uses aspirational states
- **Tipo:** UX gap · **Severity:** MEDIUM · **Effort:** XS/S
- **Trigger:** `CardDetail.tsx` renders visual pipeline states `ideation/research/drafting/author_review/peer_review/leader_review/curation/published`, while DB/type enum is `draft/peer_review/leader_review/curation_pending/published`.
- **Impact:** Items in `curation_pending` may not mark the current visual stage correctly, confusing authors and leaders about where the card is in the process.
- **Proposta:** Align visual states with DB or map `curation_pending -> curation` explicitly.
- **Validation gate:** The live Débora-style item in `curation_pending` highlights the curadoria stage.
- **Cross-ref:** GitHub #189; `docs/audit/P203_CURATION_JOURNEY_AUDIT.md` C-005; ADR-0086.

### 61. P1 — Opportunity: canonical `curation_queue_state` semantic layer
- **Tipo:** opportunity · **Severity:** HIGH · **Effort:** M
- **Trigger:** p203 audit found curation state distributed across `board_items`, `curation_review_log`, `board_lifecycle_events`, `board_item_assignments`, `notifications`, `project_boards`, `engagements`, `engagement_kind_permissions`, MCP and the committee workspace.
- **Impact:** `/admin/curatorship`, committee workspace, notifications, MCP and QA can disagree about queue state, notification coverage, required reviews and eligible actions.
- **Proposta:** Create a view/RPC `curation_queue_state` with item, origin type, status, SLA, review counts, required review count, curators_notified, email_sent, next_action and caller-eligible actions.
- **Validation gate:** `/admin/curatorship`, workspace queue and MCP read from the same envelope.
- **Cross-ref:** GitHub #190, #166; `docs/audit/P203_CURATION_JOURNEY_AUDIT.md`.

### 62. P1 — Curadoria has parallel APIs/FSMs that can drift
- **Tipo:** gap · **Severity:** HIGH · **Effort:** M
- **Trigger:** p203 frontend/backend/MCP audit found active `CardDetail` path uses p197 RPCs, while `TribeKanbanIsland` and MCP `advance_card_curation` still point to legacy `advance_board_item_curation`.
- **Impact:** Agents or future UI work can call outdated actions (`request_review`, `approve_peer`, `approve_leader`) or documented-but-invalid MCP actions, bypassing the structured ADR-0086 peer/leader review path.
- **Proposta:** Deprecate legacy API/tool or rewrite them to delegate to `complete_peer_review`, `complete_leader_review`, `submit_for_curation`, and `submit_curation_review`.
- **Validation gate:** No mounted UI or MCP tool advertises actions that do not exist in the target RPC; board curation tests exercise only the accepted path.
- **Cross-ref:** GitHub #191; `docs/audit/P203_CURATION_JOURNEY_AUDIT.md` C-007/C-009.

### 63. P1 — `curation_review_log` lacks duplicate-review guard
- **Tipo:** data integrity gap · **Severity:** HIGH · **Effort:** S/M
- **Trigger:** Backend audit found consensus counts approvals in `curation_review_log`, but there is no documented UNIQUE guard for one review per curator per item/round.
- **Impact:** A single curator could potentially submit repeated approvals and satisfy `reviewers_required`, weakening the two-reviewer governance model.
- **Proposta:** Decide key (`board_item_id`, `curator_id`, `review_round`) and add DB constraint or RPC guard. Include backfill/dedup audit first.
- **Validation gate:** Duplicate review attempt fails predictably; consensus count uses distinct curators.
- **Cross-ref:** GitHub #192; `docs/audit/P203_CURATION_JOURNEY_AUDIT.md` C-010; ADR-0086.

### 64. P2 — Curadoria vocabulary drift: `revision_requested` and `auto_publish_approved_article`
- **Tipo:** drift/cleanup · **Severity:** MEDIUM · **Effort:** S
- **Trigger:** `get_curation_dashboard()` filters `revision_requested`, which is not in the `board_items.curation_status` CHECK; ADR-0086 also notes `auto_publish_approved_article` expects `approved`, also absent from the CHECK.
- **Impact:** Dead branches and phantom states confuse audits, agents and UI work. Devoluções currently become `curation_status='draft'` + `status='review'`.
- **Proposta:** Remove phantom states or add explicit mapping in one semantic layer. Drop dead trigger if no longer part of the accepted FSM.
- **Validation gate:** Static grep shows no unhandled phantom state in active reader/writer RPCs; live FSM states are exactly documented.
- **Cross-ref:** GitHub #193; `docs/audit/P203_CURATION_JOURNEY_AUDIT.md` C-008/C-011; ADR-0086.

### 65. P1 — Curadoria contract tests missing for accepted p197 flow
- **Tipo:** gap · **Severity:** HIGH · **Effort:** M
- **Trigger:** Existing log item #32 covers `complete_peer_review`/`complete_leader_review`; p203 audit expands scope to include `submit_for_curation`, `submit_curation_review`, duplicate review prevention and curator notification side effects.
- **Impact:** Critical governance flow can regress without breaking generic UI/build tests.
- **Proposta:** Add DB-aware or static contract tests for authorization, state transitions, returned reset behavior, SLA creation, notification recipients, and consensus by distinct curators.
- **Validation gate:** Tests fail if reader gates revert to `write_board`-only or if canonical submit does not notify committee.
- **Cross-ref:** GitHub #194; existing P162 #32; `docs/audit/P203_CURATION_JOURNEY_AUDIT.md` C-006/C-010.

### 66. P1 — Curadoria email policy lacks dedicated notification type
- **Tipo:** gap · **Severity:** HIGH · **Effort:** S/M
- **Trigger:** Wave 2 audit found `_delivery_mode_for('assignment_new')`, `card_assigned`, `card_moved`, and hypothetical `curation_submitted` all route to `digest_weekly`; live item notifications had `email_sent_at=NULL`.
- **Impact:** Comitê may not receive timely email for a 7-day SLA item. Current notification semantics piggyback on generic card assignment/move types, not curation intent.
- **Proposta:** Create a dedicated type (`curation_item_submitted` or equivalent) and decide its delivery policy (`transactional_immediate` vs digest). If digest, add a dedicated curation section to the canonical weekly digest.
- **Validation gate:** Submitting a card creates a notification with explicit curation type and expected email/digest behavior.
- **Cross-ref:** GitHub #186; `docs/audit/P203_CURATION_JOURNEY_AUDIT.md` C-012.

### 67. P1 — Cross-pipeline curation queue omits publication/governance review states
- **Tipo:** gap · **Severity:** HIGH · **Effort:** L
- **Trigger:** Wave 2 audit found `publication_submissions` has 21 `under_review` + 8 `submitted`, `publication_ideas` has 1 `approved`, `governance_documents` has 6 `under_review`, and `change_requests` has 15 pending-ish rows, but `/admin/curatorship` only surfaces `board_items`.
- **Impact:** Curators still need to inspect multiple surfaces; the "one place" workspace remains a pointer board, not a unified operational queue.
- **Proposta:** Make `curation_queue_state` cross-pipeline with `origin_type`/`origin_id` for `board_item`, `publication_submission`, `publication_idea`, `governance_document`, `change_request`, `webinar_proposal`.
- **Validation gate:** Committee workspace and `/admin/curatorship` show at least board items + publication submissions + governance docs with consistent next actions.
- **Cross-ref:** GitHub #190; `docs/audit/P203_CURATION_JOURNEY_AUDIT.md` C-013; OPP-196.D.

### 68. P2 — Weekly digest implementations diverge for curation follow-up
- **Tipo:** drift/opportunity · **Severity:** MEDIUM · **Effort:** M
- **Trigger:** Repo has rich DB-driven `get_weekly_member_digest()` and a separate `send-notification-digest` Edge Function that queries unread notifications and renders its own grouped HTML.
- **Impact:** Adding curation to one path may not affect the other; digest behavior can drift or duplicate logic.
- **Proposta:** Ratify the canonical digest path for members. Then add a curation-specific section in the chosen path and deprecate/mark the other path if legacy.
- **Validation gate:** One documented digest path owns curation weekly summaries; cron/job references match the chosen path.
- **Cross-ref:** GitHub #195; `docs/audit/P203_CURATION_JOURNEY_AUDIT.md` C-014; ADR-0022.

### 69. P1 — Curadoria permissions/docs drift from V4 reality
- **Tipo:** docs/governance drift · **Severity:** HIGH · **Effort:** S/M
- **Trigger:** p203 Wave 2 found `PERMISSIONS_MATRIX.md` still dated 2026-03-15 and describing curadoria via observer/designation, while `SITE_MAP.md` lists `/admin/curatorship` as observer-only and still has stale platform counts (MCP 64, Edge Functions 21, pg_cron 4).
- **Impact:** Docs imply curator access is `curator` designation/tier-based, while runtime should be V4 `curate_content` / `participate_in_governance_review`. This can lead future agents/humans to reintroduce wrong gates.
- **Proposta:** Update permissions/site docs to distinguish nav discoverability from backend authority and pin current runtime counts or point to runtime sources.
- **Validation gate:** Docs mention `curate_content`, do not claim `/admin/curatorship` is generic observer access, and no stale 64-tool MCP count remains in current docs.
- **Cross-ref:** GitHub #196; `docs/audit/P203_CURATION_JOURNEY_AUDIT.md` C-015; ADR-0087.

### 70. P1 — Curadoria tests crystallize legacy access contracts
- **Tipo:** test gap · **Severity:** HIGH · **Effort:** M
- **Trigger:** `tests/contracts/rpc-acl.test.mjs` expects curation RPCs to check `curator`/`designations` or admin role; `tests/contracts/rls-v4-phase4-1.test.mjs` still asserts `curation_review_log_write` uses `write_board`.
- **Impact:** Tests can pass while the desired V4 curator contract is broken, or fail once #185 correctly moves queue readers toward `curate_content`.
- **Proposta:** Fold into #194: update static tests to assert V4 `curate_content` / `participate_in_governance_review` according to accepted reader/writer contract, plus persona smoke for Roberto/Sarah.
- **Validation gate:** Tests fail on `write_board`-only reader queue and on V3 `designations.includes('curator')` as sole eligibility source.
- **Cross-ref:** GitHub #194; `docs/audit/P203_CURATION_JOURNEY_AUDIT.md` C-016.

### 70.1 P1 — Curadoria modal hides submitted artifact links and source context
- **Tipo:** bug / UX gap · **Severity:** HIGH · **Effort:** S/M
- **Trigger:** Fabricio reported the Débora/Agentes Autônomos item in `/admin/curatorship` does not show the article link or source folder/context needed for review. Live DB confirmed the item has `board_items.attachments` with a Google Doc link and `get_curation_dashboard()` includes `attachments`, but `ReviewRubricDialog` renders only title, tribe, SLA, assignee and description.
- **Impact:** Curators cannot review the actual artifact without hunting in the tribe board/Drive. This breaks the "one place" curation promise and can recur for any item whose key context lives in `attachments`, `board_item_files`, checklist, Drive folder links or lifecycle history.
- **Proposta:** Render submitted artifact links and context in the curation modal; extend future `curation_queue_state` to include `artifact_links`, `drive_links`, `checklist_summary`, source board/initiative/tribe and missing-context flags.
- **Validation gate:** The live Débora card shows the Google Doc link in `/admin/curatorship`; an item without artifact link shows an explicit "no artifact link attached" warning.
- **Cross-ref:** GitHub #201, #190, #188; `docs/audit/P203_CURATION_JOURNEY_AUDIT.md` C-012.

### 71. OPP-181.A — sign_volunteer_agreement re-emits is_superadmin + hardcoded operational_role
- **Tipo:** opportunity / ADR-0011 carry · **Severity:** MEDIUM · **Effort:** S
- **Trigger:** Council code-reviewer audit of PR #184 found that `sign_volunteer_agreement` notification fan-out uses `m.is_superadmin = true` and `m.operational_role = 'manager'` predicates plus an issuer-fallback `operational_role IN ('manager','tribe_leader')` block, all of which violate ADR-0011 (no hardcoded role lists; emergency-break `is_superadmin` outside its narrow scope). The body in this migration is byte-equivalent to the prior `20260513070000_adr0022_w1_producer_updates.sql` capture — pre-existing carry, NOT introduced by p203 #181 — but the DROP+CREATE in `20260724000000` re-emits and implicitly endorses the legacy pattern.
- **Impact:** Future contributors editing the body inherit the antipattern. Notification fan-out can fail to reach intended audience if `operational_role` cache lags V4 reality.
- **Proposta:** Replace `is_superadmin` and `operational_role = 'manager'` predicates with `can_by_member(m.id, 'manage_member')` subquery or a `WITH has_perm AS (SELECT m.id FROM members m JOIN can_by_member …) `CTE pattern. Same for issuer-resolution lookup at lines 249-256.
- **Validation gate:** New static contract test verifies no `is_superadmin` / no bare `operational_role = 'manager'` in sign_volunteer_agreement body.
- **Cross-ref:** PR #184 council close; ADR-0011; `20260513070000_adr0022_w1_producer_updates.sql`.

### 72. WATCH-181.B — search_path asymmetry between counter_sign_certificate and sign_volunteer_agreement
- **Tipo:** watch · **Severity:** LOW · **Effort:** XS
- **Trigger:** Council platform-guardian audit of PR #184: `counter_sign_certificate` uses `SET search_path TO ''` (fully qualified, explicit `public.` prefix on every object); `sign_volunteer_agreement` uses `SET search_path TO 'public', 'pg_temp'` (unqualified references like `members`, `sha256`, `convert_to`). Both preserved from prior bodies; intentional difference. But a future contributor "harmonizing" them to `''` would silently break sign-side unqualified refs.
- **Impact:** Latent risk if a mechanical refactor harmonizes search_path without rewriting unqualified object references.
- **Proposta:** Add `COMMENT ON FUNCTION public.sign_volunteer_agreement(text, text, text)` explaining the intentional `public, pg_temp` search_path. Optionally a paragraph in ADR-0039 Amendment A documenting the asymmetry.
- **Validation gate:** Visual review only; no automated gate proposed.
- **Cross-ref:** PR #184 council close; ADR-0039 Amendment A.

### 73. LOW-181.C — Server-side UA cap rationale lacks data assertion
- **Tipo:** test gap · **Severity:** LOW · **Effort:** XS
- **Trigger:** PR #184 added `p_signed_user_agent := left(p_signed_user_agent, 500)` to both certificate-evidence RPCs. Static contract test asserts the line is present, but no DB-aware test passes a 600+ char UA and verifies the stored `signed_user_agent` is exactly 500 chars.
- **Impact:** Future regression where the cap is bypassed (e.g. via `coalesce` rewrite or accidental removal) would not fail any test.
- **Proposta:** Either (a) add a DB-aware test that signs a term with `'A'.repeat(600)` UA and asserts `length(signed_user_agent) = 500`, OR (b) add `COMMENT ON COLUMN public.certificates.signed_user_agent` documenting the 500-char ceiling.
- **Validation gate:** Either DB-aware regression test or column COMMENT present.
- **Cross-ref:** PR #184 council close.

### 74. LOW-181.D — Migration rollback comment references ephemeral PR URL
- **Tipo:** doc drift · **Severity:** LOW · **Effort:** XS
- **Trigger:** Migration `20260724000000` rollback note says "Re-create prior bodies from migration history (pg_get_functiondef capture preserved at issue #181 PR description)" — the PR description on GitHub is mutable and the URL may rot.
- **Impact:** If rollback is ever needed, the canonical prior body location is not durable.
- **Proposta:** Replace with explicit migration filename: `-- prior bodies in 20260513070000_adr0022_w1_producer_updates.sql (sign_volunteer_agreement) and original counter_sign_certificate definition`.
- **Validation gate:** Visual review.
- **Cross-ref:** PR #184 council close.

### 75. WATCH-203.C — MCP tool list_pending_agreement_engagements deferred
- **Tipo:** watch / planned · **Severity:** MEDIUM · **Effort:** S (when triggered)
- **Trigger:** PR #197 (#177) implemented `get_pending_agreement_engagements()` RPC but per P202_VOLUNTEER_LIFECYCLE_REMEDIATION_SPEC §5, MCP tool exposure was deferred until lifecycle RPCs (#179, #180, #181) stabilize. No issue auto-tracks the eventual tool add — purely doc-tracked today.
- **Impact:** When #179/#180/#181 close, the lifecycle MCP wrappers (per #183) need to include `list_pending_agreement_engagements`. Without explicit tracking, this can fall through the cracks.
- **Proposta:** When closing #183, audit pending lifecycle RPCs (including `get_pending_agreement_engagements`) and add MCP tool wrappers for each. Update MCP_TOOL_MATRIX from 293 → 294+.
- **Validation gate:** MCP matrix audit shows `get_pending_agreement_engagements` exposed via `list_pending_agreement_engagements` tool.
- **Cross-ref:** GitHub #183; PR #197 council close; `P202_VOLUNTEER_LIFECYCLE_REMEDIATION_SPEC` §5.

### 76. LOW-203.D — Triple-scan of auth_engagements in get_pending_agreement_engagements
- **Tipo:** opportunity / perf · **Severity:** LOW · **Effort:** S
- **Trigger:** Council code-reviewer audit of PR #197: `total` count, `by_kind_role` aggregation, and `pending` list each re-execute the same WHERE clause (status='active' + requires_agreement IS TRUE + agreement_certificate_id IS NULL) against `auth_engagements`. At 16 rows today this is irrelevant; as the queue grows (or as PMI cycles produce more engagements requiring agreements), three full scans add up.
- **Impact:** Latent perf bloat.
- **Proposta:** Refactor to a single `WITH pending_base AS (SELECT … FROM auth_engagements WHERE …)` CTE feeding all three output fields.
- **Validation gate:** Function still returns the same shape (tested via contract test) but only one CTE scan.
- **Cross-ref:** PR #197 council close.

### 77. BUG-203.A — 8 pre-existing test fails in security-lgpd.test.mjs — **RESOLVED p220 (PR #225)**
- **Tipo:** test drift · **Severity:** MEDIUM · **Effort:** S (turned out)
- **Trigger:** `npm test` returns 1441 pass / 8 fail / 46 skip offline (deploy.md baseline was 1449/0/46). The 8 fails are in `tests/contracts/security-lgpd.test.mjs` covering `mark_member_present` (4 assertions) and `create_event` (4 assertions). Both code-reviewer + platform-guardian audits of PRs #184 and #197 confirmed: NOT introduced by p203 PRs. Likely sediment from p199-b/c Paulo Alves attendance fix that refactored `mark_member_present` body without updating the anti-assertion in the test.
- **DIAGNOSIS REVISED p220 (2026-05-21)**: actual root cause was `supabase/migrations/20260723000000_baseline_rpcs_after_schema.sql` (added at p202 issue #164 for local supabase start ordering fix). This file contains the ORIGINAL pre-W125 bodies of `create_event` + `mark_member_present` (bare INSERT/UPDATE with NO auth gate). Since 20260723 sorts LAST in lex order, the test's `findFunctionBody()` extracted THIS body as canonical, missing the auth gates that the live hardened body (`20260319100029_w125_*` + `20260679000000_p174_*` + `20260684000000_p178_*`) actually has. Production state was never affected — 20260723 is local-stack-only and was NOT in `supabase_migrations.schema_migrations` (verified via MCP). Sediment trace was misleading: the assertion drift was not from p199-b/c Paulo Alves fix, but from p202's baseline file ordering.
- **Fix:** Removed `create_event` + `mark_member_present` blocks from 20260723000000 (kept the other 12 baseline functions). Test now finds 20260684 (p178) + 20260679 (p174) hardened bodies as canonical → all 8 assertions pass. Local stack `supabase start` still works because W125 + p149 + p174 + p178 migrations CREATE OR REPLACE these functions at earlier timestamps with hardened bodies.
- **Validation gate:** `npm test` returns 1487+ pass / 0 fail / 46 skip offline ✓ (Local validation 2026-05-21).
- **Cross-ref:** PR #184, #197 council close (where it was first flagged); p199-b/c handoff; PR #225 (issue #220 combo); migration 20260723000000 inline comment at slot 4 + 8.

### 78. OPP-204.A — Cloudflare traffic analytics tab for `nucleoia.vitormr.dev`
- **Tipo:** opportunity / feature · **Severity:** MEDIUM · **Effort:** M
- **Trigger:** PM noted Cloudflare Analytics is collected at the `vitormr.dev` zone level and should contain traffic for the Hub subdomain. The personal site project (`~/Documents/vitormr-site`) already has a reference admin metrics surface at `vitormr.dev/admin/metrics`.
- **Impact:** `/admin/analytics` currently covers platform/product analytics but lacks web traffic visibility: requests/pageviews over time, top paths, referrers, countries/devices and period-over-period deltas for the public Hub. Without this, public interest in `nucleoia.vitormr.dev` is invisible to governance decisions.
- **Proposta:** Add a Cloudflare traffic tab/section under `/admin/analytics` (not `/admin/adoption`). Filter Cloudflare data by `hostname = nucleoia.vitormr.dev`; show aggregate cards, overtime chart, period comparison, top paths/referrers/countries/devices/status codes. Keep data aggregate-only and cache server-side via RPC/Edge Function/table; never expose Cloudflare tokens in frontend.
- **Non-goal:** Do not merge anonymous Cloudflare traffic with member identities in MVP. Keep `/admin/adoption` focused on authenticated product usage.
- **Validation gate:** `/admin/analytics` shows traffic data filtered to the Hub hostname, with no zone-wide `vitormr.dev` mixing and no Cloudflare secret in client code.
- **Cross-ref:** GitHub #200; reference project `~/Documents/vitormr-site` (`/admin/metrics`) for implementation pattern only.

<!-- NOTE: items 79-81 reserved for issue-182 PR (WATCH-182.A / GAP-182.B / WATCH-182.C). This worktree was branched before that PR; renumber at merge time if it merges first. -->

### 82. WATCH-205.A — workgroup_coordinator not in congress.allowed_engagement_kinds
- **Tipo:** watch · **Severity:** LOW (advisory only) · **Effort:** XS-S
- **Trigger:** Council platform-guardian audit of PR #169 (Vassouras initiative seed). João Coelho's engagement uses `kind='workgroup_coordinator'` on a `kind='congress'` initiative, but `engagement_kinds.metadata.allowed_engagement_kinds` for congress only lists `{volunteer,speaker,guest,observer}` (per migration `20260413600000` line 41-43). Since `allowed_engagement_kinds` is **advisory only** (no DB trigger enforces it on INSERT), the seed succeeded. But this creates conceptual drift between the schema definition and actual usage.
- **Impact:** Future kind-aware UI/tooling reading `allowed_engagement_kinds` will not show workgroup_coordinator as a valid option, even though the live DB has one. View_pii scope resolution at congress initiative scope may behave inconsistently with what `engagement_kind_permissions` seed implies.
- **Proposta:** Either (a) add `workgroup_coordinator` to congress's `allowed_engagement_kinds` via follow-up migration (preferred — aligns schema with usage; ADR-0009 "config not code"); OR (b) ADR addendum documenting that `congress` kind can host workgroup coordinator engagements with `metadata.initiative_subtype='external_event_collaboration'` as discriminator; OR (c) accept drift and rely on `committee_coordinator` permissions inheritance.
- **Validation gate:** PR title includes `congress` AC update OR ADR addendum committed.
- **Cross-ref:** PR #169 council close; migration `20260728000000`; engagement_kinds + permissions cross-table.

### 83. LOW-205.B — metadata.angle dual semantic (engagement-level vs initiative array element)
- **Tipo:** doc drift · **Severity:** LOW · **Effort:** XS
- **Trigger:** Council code-reviewer audit of PR #169. `metadata.angle` is used as a JSONB key in TWO different shapes: (1) at engagement-level (`engagements.metadata.angle` on Vitor + Sarah's speaker engagements), and (2) inside `initiatives.metadata.confirmed_speakers[].angle` array elements. No schema constraint; dual use is semantic.
- **Impact:** Future queries joining both paths need to UNION two different shapes. Subtle gotcha.
- **Proposta:** Document the dual usage in ADR-0093 or a short addendum.
- **Validation gate:** ADR amendment committed.
- **Cross-ref:** PR #169 council close.

### 84. LOW-205.C — initiative.metadata.open_questions duplicates board cards
- **Tipo:** opportunity · **Severity:** LOW · **Effort:** S
- **Trigger:** Council code-reviewer audit. `initiatives.metadata.open_questions` is a JSONB string array (5 entries for Vassouras). 3 of 5 map directly to existing board cards. Completing a card does not auto-clear the question. Mirror of LATAM LIM precedent.
- **Impact:** Stale `open_questions` after cards are resolved; admin UI showing question alongside the card it duplicates.
- **Proposta:** Either (a) periodic admin UI clear; OR (b) board card UUIDs as references in `open_questions`; OR (c) drop `open_questions` and rely on board cards.
- **Validation gate:** Pattern decision documented.
- **Cross-ref:** PR #169 council close.

### 85. LOW-205.D — Board card 4 sub-tasks belong in board_item_checklists
- **Tipo:** modeling · **Severity:** LOW · **Effort:** S
- **Trigger:** Council code-reviewer audit. Board card #169-104 ("Operação day-of") has 4 discrete sub-tasks (camisas + coffee-break + sorteio + bolsa-pós) in description free text. `board_item_checklists` table exists for this with assignment + completion semantics. Same applies to cards 1 + 3.
- **Impact:** Student collaboration value (teaching scope) degrades when sub-tasks aren't trackable individually. Students can't claim "camisas" without claiming the whole operational card.
- **Proposta:** Companion admin UI op or follow-up migration before T-5d (2026-05-28): create `board_item_checklists` rows for sub-tasks.
- **Validation gate:** Sub-tasks split into checklist rows before student collaboration begins.
- **Cross-ref:** PR #169 council close.

### 86. WATCH-205.E — partner_entities.contact_email PII governance pattern
- **Tipo:** watch / policy · **Severity:** MED · **Effort:** S
- **Trigger:** Council code-reviewer audit of PR #169. Initial seed had `contact_email='j_coelho@id.uff.br'` in a public-repo migration. Fixed inline by removing the column from the INSERT (nullified live row). Raises broader question: what's the policy for `partner_entities.contact_email` in future seeds?
- **Impact:** Without governance, future PRs may seed partner contacts with real emails. LGPD-adjacent risk even for external/institutional contacts (individual still identifiable).
- **Proposta:** Document policy: "partner_entities.contact_email MUST be NULL in seed migrations; admin UI is the only entry point post-merge." Add contract test or pre-commit grep to enforce.
- **Validation gate:** Policy doc + pre-commit grep added.
- **Cross-ref:** PR #169 council close; LGPD posture for external contacts.

### 87. GAP-204.B — Behavioural DB-aware tests for invariants R + S forward-defense [RESOLVED p206 PR #215]
- **Tipo:** test gap · **Severity:** MEDIUM · **Effort:** M
- **Trigger:** p204 council Tier 1 close (PR #199 / Issue #180) carried this item: R + S invariants added to `check_schema_invariants()` were validated only via static contract tests (text-matching the migration SQL) — no behavioural exercise of (a) R=0/S=0 at deploy or (b) synthetic-breach detection.
- **Impact:** Silent CTE drift in either invariant would pass static tests. Forward-defense regression catcher missing.
- **Resolution (p206):** Migration `20260731000000_p206_gap_204_b_invariant_breach_helper.sql` adds `_test_invariants_with_synthetic_breach(text)` SECURITY DEFINER + GRANT EXECUTE TO service_role only. Mirror of p186 `_test_detect_inactive_with_threshold` pattern (Prefer: tx=rollback hermetic seeding). 4 behavioural tests at `tests/contracts/volunteer-authority-invariants-behavioural.test.mjs` cover R=0+S=0 deploy state AND R/S synthetic-breach detection. Live verification via MCP DO-block with subtransaction-savepoint pattern confirmed: R breach → R.count=1, S.count=0; S breach → R.count=0, S.count=1; post-state clean (R=0, S=0).
- **Validation gate:** `node --test tests/contracts/volunteer-authority-invariants-behavioural.test.mjs` returns 4 pass when `SUPABASE_SERVICE_ROLE_KEY` env set; 4 skip cleanly otherwise.
- **Cross-ref:** PR #215 (this — Issue #213); PRs #198 + #199 (V4 lifecycle backbone in QA); p186 OPP-185.A pattern source; `feedback_contract_test_ci_skip_silent` for the CI skip class.

### 88. WATCH-213.A — Behavioural test post-leak assertion depends on baseline ordering
- **Tipo:** test design / doc · **Severity:** LOW · **Effort:** XS
- **Trigger:** Council code-reviewer HIGH finding on PR #215. Tests #3 + #4 of `volunteer-authority-invariants-behavioural.test.mjs` re-read live invariants after the synthetic breach test and assert `postR.violation_count = 0`. This assertion correctly discriminates "tx=rollback failed" from "real prod violation" ONLY when tests #1 + #2 have run first and confirmed baseline=0. Resolved inline via test-file docstring noting the ordering dependency, but no runtime enforcement.
- **Impact:** Future test runners that shuffle or run subsets (e.g., `--test-name-pattern='detects synthetic'`) may misidentify a pre-existing prod R/S violation as a helper leak.
- **Proposta:** Either (a) add a `before()` hook to each forward-defense test that asserts baseline R=0+S=0 explicitly (belt-and-suspenders), OR (b) accept the ordering dependency and rely on the docstring (cheapest option already shipped).
- **Validation gate:** Visual review of test file header note OR `before()` hook present.
- **Cross-ref:** PR #215 council code-reviewer HIGH; test file lines 30-44 (docstring note).

### 89. WATCH-213.B — `_test_*` helper RPC pattern uncodified
- **Tipo:** doc drift / governance · **Severity:** LOW · **Effort:** S
- **Trigger:** Council platform-guardian F4 on PR #215. Two `_test_*` helpers now exist in `public` schema: `_test_detect_inactive_with_threshold` (p186) and `_test_invariants_with_synthetic_breach` (p206). No ADR or addendum codifies the canonical contract (naming `_test_*` prefix + GRANT scope service_role-only + in-body role guard + caller-side `Prefer: tx=rollback` expectation + LEAK CLEANUP query in migration header).
- **Impact:** Future `_test_*` helpers may deviate from the established pattern. A `_test_*` function with `GRANT EXECUTE TO authenticated` would silently expand attack surface; no automated gate today.
- **Proposta:** Either (a) ADR-0094 codifying `_test_*` helper RPC contract, OR (b) ADR-0028 Amendment D extending the service_role bypass section to cover the test-helper subclass, AND (c) extend `tests/contracts/rpc-migration-coverage.test.mjs` to verify each `_test_*` function has a corresponding `REVOKE FROM PUBLIC` and `GRANT TO service_role` clause in its capture.
- **Validation gate:** ADR doc + contract test extension shipped together.
- **Cross-ref:** PR #215 council platform-guardian F4 + F5; p186 migration `20260694000000`; p206 migration `20260731000000`.

### 90. WATCH-213.C — Static volunteer-authority-invariants test not wired to npm test — **RESOLVED p207 (2026-05-20)**
- **Tipo:** test infrastructure · **Severity:** HIGH (blocks coverage delivery) · **Effort:** XS
- **Trigger:** Council platform-guardian F6 on PR #215. The static contract test `tests/contracts/volunteer-authority-invariants.test.mjs` exists on `agent/issue-180` branch but is NOT added to `package.json` `test` + `test:contracts` scripts. When PR #199 merges, the file will land in repo but be silently excluded from CI test runs.
- **Impact:** Until corrected, the 10 static contract tests for invariants R+S coverage will not execute in CI. PR #199's claimed coverage (per its description) will be falsely advertised.
- **Proposta:** When PR #199 merges, immediately add the test file path to both `test` and `test:contracts` in package.json — either as a sub-commit of the merged work or as a separate follow-up commit. Verify via `npm test 2>&1 | grep -c volunteer-authority-invariants` returning ≥1.
- **Validation gate:** `npm test` output includes `volunteer-authority-invariants.test.mjs` execution.
- **Cross-ref:** PR #215 council platform-guardian F6; PR #199; `agent/issue-180` branch HEAD.
- **Resolution (p207 2026-05-20):** PR #199 merged via `c191254e` (admin bypass — pre-existing browser_guards env CI failure on main HEAD too). Immediately followed by direct main commit `a1fc43ce fix(p207): wire volunteer-authority-invariants static test into npm scripts` adding the file to both `test` (between member-cycle-history-self-read and edge-functions group) and `test:contracts` (at end of contracts list). Local verification: `node --test tests/contracts/volunteer-authority-invariants.test.mjs` runs 10/10 pass cleanly offline (static, no DB env). Pattern matches PR #203 fa8b7a12 + 741511ce/0ca7910a post-merge direct fixes.

### 91. OPP-213.D — `test:contracts` script missing 4 pre-existing files
- **Tipo:** test infrastructure / pre-existing · **Severity:** LOW · **Effort:** XS
- **Trigger:** Council code-reviewer LOW on PR #215. Four contract test files are present in `npm test` but absent from `npm run test:contracts`: `ip-gate-templates`, `preview-gate-eligibles-cache-equivalence`, `weekly-card-digest`, `worker-mapper-db-update-coverage`. Pre-existing drift on main; PR #215 correctly adds the new file to both scripts (58/54 ratio after merge).
- **Impact:** `test:contracts` reports a smaller suite than reality. Developers running only `test:contracts` may miss regressions in 4 contract files.
- **Proposta:** Either (a) add the 4 files to `test:contracts`, OR (b) replace both scripts with a glob: `node --test 'tests/contracts/*.test.mjs'` (would also need to handle the `--experimental-strip-types` flag asymmetry).
- **Validation gate:** Both scripts iterate the same file set (diff returns empty).
- **Cross-ref:** PR #215 council code-reviewer LOW.

### 92. BUG-207.A — /profile ReferenceError "t is not defined" — **RESOLVED p207 (PR #223 bb95bb03), DIAGNOSIS REVISED**
- **Tipo:** bug · **Severity:** HIGH (user-facing critical, member profile page) · **Effort:** XS (1-line import — real fix; spec scoping was wrong)
- **Trigger:** PM reported live error on `/profile` at p207 boot 2026-05-20.
- **DIAGNOSIS REVISED during execution (p207 close)**: spec hypothesized TS annotation × Vite minify (3rd recurrence of p158/p184 lp class). **Empirically disproven**: stripped all 22 module-level annotations → bundle byte-identical to broken prod (same hash `v3Zqq7wC.js` + same md5). Conclusion: esbuild strips TS annotations BEFORE Vite minification in current Astro+Vite stack, so source-level annotations are no-op for output bundle.
- **REAL ROOT CAUSE**: Inline `<script>` in `profile.astro:237+` calls `t('profile.xp.howToEarn', lang)` ~25× at runtime (XP pillars + champion + journey labels) but never imports `t`. Frontmatter imports server-side; client-side script needed own import. Without it, minified bundle has unresolved `t` references → `ReferenceError`.
- **REAL FIX** (PR #223 `bb95bb03`): `import { t } from '../i18n/utils';` added at top of `<script>` block. 1 file changed, +9 lines (1 import + 8-line comment explaining the class). Bundle hash CHANGED `v3Zqq7wC` → `CGuhpcmD`, +40 bytes; bundle now has `import{t as x}from"./utils.CUL6moXM.js"`.
- **Verification**: `astro build` PASS + `astro preview /profile` HTTP 200 + bundle byte-comparison proves real fix.
- **Validation gate**: PM browser smoke `/profile` (signed-in member) — no `ReferenceError: t is not defined` in console, XP pillars + champion + journey labels render.
- **Cross-ref:** Issue #216; PR #223 (`bb95bb03`); spec doc `docs/project-governance/sessions/p207_issue_216_profile_ts_annotation_minify.md` (now SUPERSEDED — filename misleading, real fix doc in PR description); `[[feedback-bundle-byte-identity-diagnostic]]` (NEW sediment to capture).
- **Note on p158/p184 historicals**: those commits ALSO stripped TS annotations (on `lp`) — based on the bundle-byte test in p207, those edits were ALSO no-op. The fixes must have coincided with browser cache invalidation / CDN purge / unrelated changes that gave illusion of "TS annotation strip = fix". Real cause of those was likely also missing/broken bindings, just on different vars.

### 93. OPP-207.B — Forward defense audit for inline-script runtime-bound identifiers without imports
- **Tipo:** opportunity / forward defense · **Severity:** MED · **Effort:** S
- **Trigger:** BUG-207.A revealed a CLASS of bug: inline `<script>` blocks in `.astro` files use runtime identifiers (`t`, `lp`, etc.) that need to be imported separately from the frontmatter. Without explicit import in the script, minified bundle has unresolved references. **3rd recurrence of this class** (p158 `lp` TDZ + p184 `lp` re-issue + p207 `t`); needs preventive surface.
- **REFRAMED (was: "audit module-level TS annotations")**: original framing scoped wrong class. After BUG-207.A diagnostic revision (TS annotations are no-op for output bundle), the real forward-defense need is auditing inline `<script>` blocks for **runtime-bound identifiers that are USED but not IMPORTED/DEFINED in script scope**.
- **Impact:** 4th recurrence will happen when next developer adds another runtime call (e.g., `formatDate(...)`, `getRoleLabel(...)`) without importing in script scope. Each costs: prod ReferenceError + Sentry alert + investigation + diagnostic-error cycle (PM was bitten 3× already).
- **Proposta:** `scripts/audit-astro-script-runtime-bindings.mjs` — for each `.astro` file with `<script>` (non-`is:inline`), parse the script body, extract all CallExpressions where callee is an Identifier, check if that identifier is imported/declared in script scope. Report orphan calls. Pre-commit hook + CI gate (warn first, block after 1 quarter).
- **Validation gate:** Script catches `t()` call in `<script>` without `import { t }`. Output reproducible.
- **Cross-ref:** Issue #216 + PR #223 (revised diagnostic); BUG-207.A note about p158/p184 historicals; `[[feedback-astro-define-vars-no-ts]]` p169 (adjacent class, NOT same).

### 94. BUG-207.C — browser_guards CI broken 75+ runs since 2026-05-18 — **RESOLVED p220 (PR #225)**
- **Tipo:** bug · **Severity:** HIGH (CI gate effectively disabled; obriga --admin bypass para todos os merges) · **Effort:** M (~3h combined Phase 1 + Phase 2)
- **Trigger:** PM perguntou em p207 (2026-05-20) por que browser_guards falha. **Investigação p207 (sessão de ~45min)** descartou 2 hipóteses iniciais + refinou diagnostic. Ver Issue #220 comment para detalhes completos. Resumo das camadas:
  - **L1 (workerd DNS strict)**: `kj/async-io-unix.c++:1298: DNS lookup failed; params.host = mock.supabase.co`. Workerd novo (CI runner image cache invalidation em 2026-05-18 — commit gatilho `7fa3ea1c` é **docs-only**, não código) aborta dev server fatalmente em DNS unresolvable.
  - **L2 (test brittleness)**: mesmo com L1 fix aplicado, test failed at line 520 (`#analytics-quality-banner` visible). **p207 finding "line 66" was wrong** — error message lacked stack trace, attribution was misleading. Real cause: p190 BUG-190.B (commit `46aefd15`, 2026-05-18 same day) replaced 5 of 6 analytics RPCs with `Promise.resolve(null)` to suppress 404 noise. `browser-guards.test.mjs`'s fakeSb mocks for `exec_funnel_summary` + `exec_analytics_v2_quality` became dead code → quality/funnel rendered null → banner hidden → assertions fail. The L1 workerd crash MASKED this for 3 days.
- **Impact:** `validate` + `browser_guards` falham em todos os PRs + main pushes → `quality_gate` SKIPPED em cascade. Merges (#199 + #184/#197/#198/#223) precisam `--admin` bypass. Cada bypass consolida o pattern como aceitável → erosão de gates (WATCH-207.D).
- **Fix p220 (2026-05-21)**:
  - **Phase 1 (L1)**: 4 occurrences of `https://mock.supabase.co` → `http://127.0.0.1:9999` in `.github/workflows/ci.yml` (Build + Smoke routes em validate; browser_guards env; visual_dark_mode env). Workerd survives DNS lookup on localhost. ECONNREFUSED is OK — fetch errors are recoverable, DNS errors are fatal in new workerd.
  - **Phase 2 (L2)**: restored `safeRpc('exec_funnel_summary')` + `safeRpc('exec_analytics_v2_quality')` in `analytics.astro` `loadAnalyticsV2()`; silenced `safeRpc` toast (replaced `toast(...)` with comment + `console.warn` only). Preserves p190's no-user-noise intent (no toast) while restoring browser-guards test coverage via fakeSb mocks. Anti-assertions at `tests/ui-stabilization.test.mjs:343,347` updated to assert `true` for these 2 RPCs. Other 3 (impact, cert, roi) stay hardcoded null (no test asserts their UI).
  - **Side fix (BUG-220.A discovered)**: 4 obsolete tests in `tests/contracts/selection-interview-decision.test.mjs:199-241` RELOCATED — comments cross-ref to `canonical-approval-orchestration.test.mjs` which already covers what `finalize_decisions` USED TO do before p204 (PR #198) introduced canonical orchestration. 4 pre-existing fails were silent because workerd L1 overshadowed in CI logs.
- **Validation gate**: `gh run list --workflow=ci.yml --branch agent/issue-220 --limit 3` mostra browser_guards=SUCCESS + PR mergeable sem --admin. Local: `npm test` 1487/0/46 + `astro build` complete + browser-guards.test.mjs "passed" with localhost:9999 env.
- **Cross-ref:** Issue #220 + p207 forensics comment; runs falhos como `26167448636`; commits gatilho `7fa3ea1c` (docs-only — CI infra externo é o verdadeiro gatilho); PR #199 merge (`c191254e`) primeiro a usar --admin; PR #225 (this fix); WATCH-207.D (--admin erosion now auditable).

### 95. WATCH-207.D — --admin bypass pattern erosão (PRs #199/#184/#197/#198 em sequência)
- **Tipo:** watch / governance debt · **Severity:** MED · **Effort:** XS (após CI fix)
- **Trigger:** BUG-207.C força `--admin` bypass em série. Sediment risk: PMs/agents futuros podem normalizar bypass mesmo após fix do CI infra.
- **Impact:** Branch protection serves to prevent regressões; bypass repetido (mesmo com causa identificada) cria precedente de "ignore o checkmark se incomodar". Confusão de governance.
- **Proposta:** Após Issue #220 resolved (browser_guards ✓ verde), auditar: (a) listar quantos PRs subiram via --admin no intervalo (esperado ≥4); (b) confirmar que cada --admin tem justificativa documentada em PR comment; (c) revogar --admin merge permission a partir de X data como sinal explícito de "voltamos ao normal".
- **Validation gate:** PRs pós-fix passam CI sem --admin; --admin merges são raros e justificados.
- **Cross-ref:** BUG-207.C #94 above; Issue #220; sediment desde PR #199 (c191254e p207).

### 96. WATCH-207.E — Test files wiring follow-on recurrence (4/4 lifecycle PRs)
- **Tipo:** watch / forward defense · **Severity:** MED · **Effort:** S
- **Trigger:** P207 close revealed that **4 of 4 lifecycle PRs** (#199 + #184 + #197 + #198) shipped contract test files without wiring them into `package.json` `test` + `test:contracts` scripts. Each required a separate follow-on commit on main (`a1fc43ce` for #199, `158a7ebd` for the consolidated #184/#197/#198 wiring). Pattern first identified as WATCH-213.C (HIGH carry for #199); now recurrence-of-4 confirms it's a class issue not a one-off.
- **Impact:** Without wiring, the contract tests land as dead files: CI doesn't invoke them, regressions slip through, PR description's "10 new tests added" claim is silently false. Forward-defense gap.
- **Proposta:** Either (a) Add a contract test in `tests/contracts/rpc-migration-coverage.test.mjs` (or sibling) that asserts every `*.test.mjs` file in `tests/contracts/` IS in `package.json` `test` script — fail CI if any new file is unwired. Or (b) Replace both scripts with glob: `node --test 'tests/contracts/*.test.mjs'` (requires handling `--experimental-strip-types` asymmetry). Or (c) Add a pre-commit hook that lints the same. Recommended: (a) since it's contract-style and matches existing patterns.
- **Validation gate:** Adding an unwired test file to tests/contracts/ causes CI to fail with clear message.
- **Cross-ref:** WATCH-213.C (resolved); a1fc43ce (PR #199 wiring); 158a7ebd (PRs #184/#197/#198 wiring); OPP-213.D (related test:contracts script missing 4 pre-existing files).

### 97. RESOLVED-209.A — Codex parallel work governance framework adopted (commit d1009d70)
- **Tipo:** governance / coordination · **Severity:** N/A (ADOPTED) · **Effort:** S (committed)
- **Trigger:** During p208 close window (post-PR #225 merge), Codex (OpenAI) created untracked files in main worktree: `docs/project-governance/ISSUE_REGISTRY.md` (90 lines, dispatch board) + `docs/audit/2026-05-21_ISSUES_REGISTRY_AND_PARALLEL_WORK_AUDIT.md` (237 lines, audit). Both produced via parallel session not coordinated with Claude.
- **Impact:** Codex audit triaged ~60 open issues into 7 registry_status values (active/qa-window/blocked/spec-only/ready-leaf/defer/close-candidate) with lane/blocks/blocked_by per row. Wave 0/1/2/3 stabilization sequence proposed. Identifies Codex finding that `p201_PARALLEL_AGENT_ROADMAP` is directionally correct but needs registry layer to avoid duplicate work + merge friction.
- **Resolution:** p209 boot, PM Option A streak 74/75 (Recommended) — commit the docs to main as governance reference. Commits d1009d70 (governance docs), 46267ae1 (Codex selection.astro panel toggle UX fix), cbc0a07b (Codex browser-guards error.stack diagnostic improvement). All 3 with `Assisted-By: Codex (OpenAI)` attribution preserved.
- **Forward-defense:** ISSUE_REGISTRY.md updated as PRs merge / issues close. New "registry_status" column in mental model when triaging. Dispatch rules in audit doc (max concurrent per lane while CI red) inform parallel-agent capacity.
- **Validation gate:** Codex/Claude/Cursor parallel work checks ISSUE_REGISTRY before claiming new issue; no duplicate worktree-per-issue conflicts.
- **Cross-ref:** Codex initiated 2026-05-20 23:15-23:23; commits d1009d70/46267ae1/cbc0a07b at p209 boot; aligns with [[feedback-qa-window-before-close-parallel-agent]].

### 98. RESOLVED-209.B — BUG-225.A Phase A + B (PR #228) — 2 of 3 CI validate fail classes closed
- **Tipo:** bug / drift cleanup · **Severity:** P1 (CI green precondition for --admin revoke per WATCH-207.D) · **Effort:** L (~3h investigation + execution)
- **Trigger:** Per Issue #226 (filed at p208 close, BUG-225.A). 3 CI validate fail classes: orphan + SECDEF + body-hash drift. PM Option A streak 75/76 at p209 picked #226 as primary direction.
- **Investigation:** Survey via `_audit_list_public_function_bodies()` RPC + `loadLatestCaptures()` parser. Real numbers: 26 driftedDefinite (allowlist=0, all NEW) + 2 orphansTrue + 36 orphansOverload + 142 extinct. Phase C test only counts driftedDefinite + driftedSuspect → 26 to fix. Q-C orphan test by NAME (not args) → only 2 fail (orphansOverload pass).
- **Fix Phase A (storage SECDEF)**: Migration `20260802000000` DROP+CREATE `selection_resumes_read_view_pii` policy USING `rls_can('view_pii')` (SECDEF wrapper GRANTed to authenticated/anon resolving auth.uid()→persons.id) replacing direct `can(auth.uid(), 'view_pii')` (was BOTH wrong type AND REVOKE'd from authenticated → silent empty bucket for all users). **PM Dashboard apply gated** — MCP service_role cannot ALTER storage.objects ownership (`supabase_storage_admin` only).
- **Fix Phase B (body-hash drift)**: Migration `20260802000001` (2988 lines, 26 CREATE OR REPLACE FUNCTION). Per [[feedback-pg-get-functiondef-idempotent-capture]] (p174 sediment), captures via `pg_get_functiondef(oid)` are byte-equivalent to live → skipped `apply_migration` call; registered version directly via `INSERT INTO supabase_migrations.schema_migrations`. Drift audit re-verified post-write: driftedDefinite=0. Drift origins: 7 from baseline_rpcs_after_schema.sql stale + 19 from mid-session apply_migration without re-capture (ADR-0029 gap).
- **Out of scope (auto-resolve on PR merge):**
  - Orphan #1 `_test_invariants_with_synthetic_breach` → PR #215 (Open, awaits PM smoke)
  - Orphan #2 `_trg_pmi_video_screening_voice_consent_check` → PR #222 (DRAFT, awaits Angeline legal review per p208 #221 Whisper Art. 11)
- **Validation gate:** After PM applies Phase A SQL via Dashboard: `gh run list --workflow=ci.yml --branch agent/issue-226` shows validate with only 2 orphan fails (down from 3 fail classes). After PR #215 + #222 merge → validate fully green → revoke --admin merge permission per WATCH-207.D close criteria.
- **Cross-ref:** Issue #226 BUG-225.A; PR #228; commits f3cd3b19 (Phase A) + c56577c4 (Phase B); WATCH-207.D (--admin audit) precondition; ADR-0029 (drift governance).

### 99. WATCH-209.C — --admin bypass count incremented again (now ~9 events in 3-day window)
- **Tipo:** watch / governance debt · **Severity:** MED (escalando) · **Effort:** XS (after #226 close)
- **Trigger:** p209 boot reconciliation committed 3 governance docs + UX fixes directly to main without PR (commits d1009d70, 46267ae1, cbc0a07b). GitHub flagged "Bypassed rule violations: 2 of 2 required status checks are expected" on push. These are NOT --admin merges but ARE PR-bypass equivalents.
- **Impact:** WATCH-207.D bypass audit now must count: 6 --admin PR merges (PRs #199/#184/#197/#198/#223/#225) + 3 direct push commits at p209 boot = **9 bypass events in 3-day window** (2026-05-18 → 2026-05-21). Increasing erosion risk.
- **Justification (for record):** Each was reconciliation/cleanup work not appropriate for fresh PR (governance docs, UX fixes from prior session); CI validate still red on pre-existing drift (Phase C + orphans), so PR would have required --admin anyway. Direct commit was equivalent but more transparent (no false-positive admin override).
- **Proposta:** WATCH-207.D audit should distinguish between "admin override on red PR" vs "direct push when no isolated issue exists" — latter may be acceptable maintenance pattern. Document criteria.
- **Validation gate:** After #226 closes (Phase C drift → 0 + orphans resolve) + branch protection re-tested, direct-push events should drop to ~0/week.
- **Cross-ref:** WATCH-207.D (parent); commits d1009d70/46267ae1/cbc0a07b (p209 boot reconciliation).

### 100. OPP-209.D — Phase C drift forward-defense: pre-deploy drift sweep
- **Tipo:** opportunity / forward defense · **Severity:** LOW · **Effort:** S
- **Trigger:** Phase B drift recovery at p209 captured 26 functions — 19 from mid-session apply_migration without re-capture. The recurrence pattern is the original ADR-0029 gap. Without forward-defense, every multi-session migration cluster (p178+19fns, p195+5fns, p197+4fns, p204+4fns, etc.) accrues drift.
- **Impact:** Drift accumulates silently until a Phase C contract test failure forces cleanup. Drift recovery is mechanical but expensive (1 file per ~25 functions, ~3h for batch). Forward-defense would prevent re-emergence.
- **Proposta:** Add npm script `npm run drift:check` that runs `scripts/audit-rpc-body-drift.mjs` + auto-generates capture migration if driftedDefinite > 0. Make pre-deploy GC-097 item: "Before tagging release, run drift:check; if non-zero, run drift:capture which generates migration file ready for review." Integrate with deploy.md GC-097 list.
- **Alt:** Add to `.github/workflows/ci.yml` a `drift-check` job that runs on every push and creates a PR comment with "X functions drifted since main" — soft warning before hard fail.
- **Validation gate:** Adding intentional drift via apply_migration shows in pre-deploy drift:check; comment appears in PR.
- **Cross-ref:** ADR-0029 drift governance; CLAUDE.md GC-097; .claude/rules/database.md; p209 Phase B precedent.

### 101. WATCH-226.A — No automated deadline for Phase B drift captures post apply_migration (platform-guardian PR #228 finding)
- **Tipo:** watch / forward defense · **Severity:** LOW · **Effort:** S
- **Trigger:** platform-guardian review of PR #228 surfaced gap: Phase B header says "future Phase B captures should follow this pattern" but no CI gate enforces capture deadline. The Phase C body-hash drift test surfaces drift on next run, but only AFTER unapplied session introduces it. Manual ratchet → drift accumulates silently across marathon sessions.
- **Impact:** Phase B at p209 captured 26 functions, 19 of which were "mid-session apply_migration without re-capture" (the original ADR-0029 gap). Pattern recurs unless forward-defense added.
- **Proposta:** Two paths: (a) commit-msg lint rule — grep recent commits for `apply_migration` mentions without corresponding `*drift_capture*.sql` file in same window; warn if missing. (b) Session-close checklist rule — `/audit` skill adds drift:check as mandatory close step. Both lighter-weight than full CI gate.
- **Alt to OPP-209.D:** OPP-209.D proposes full pre-deploy drift:check. WATCH-226.A is a softer per-session rule. Together = layered defense.
- **Validation gate:** Apply_migration in session N → drift-capture file in session N or N+1; otherwise lint warning.
- **Cross-ref:** OPP-209.D (related fuller proposal); platform-guardian PR #228 review (background agent at p209 close); ADR-0029 drift governance.

### 102. OPP-226.B — `sign_volunteer_agreement` notification recipient cleanup (code-reviewer PR #228 finding)
- **Tipo:** opportunity / ADR-0011 cleanup · **Severity:** MED · **Effort:** S
- **Trigger:** code-reviewer review of PR #228 surfaced pattern in captured `sign_volunteer_agreement` body (Phase B line 2779): notification recipient WHERE clause uses `m.operational_role = 'manager' OR m.is_superadmin = true` instead of canonical V4 `can_by_member('manage_member')` query. Pre-existing pattern (since p203 PR #184), captured faithfully in Phase B without forward-fix annotation (modifying inline would cause re-drift).
- **Impact:** Per ADR-0011 V4 authority cleanup, all hardcoded `operational_role IN (...)` + `is_superadmin = true` checks should be replaced with `can_by_member(...)` queries. Notification recipient filter is lower-severity than authority gate (it's "who gets notified", not "who can do this"), but the pattern is identical to p65 incident class. Canonicalizing in new migration without forward-fix annotation makes the gap less visible.
- **Proposta:** Future ADR-0011 cleanup batch should refactor `sign_volunteer_agreement` recipient filter to:
  ```sql
  SELECT DISTINCT m.id FROM members m
  WHERE can_by_member(m.id, 'manage_member')
    AND m.id IN (SELECT signer_id FROM ...);
  ```
  Pattern alignment with other notification dispatchers.
- **Validation gate:** Code-reviewer follow-up flags this body as no longer matching the pattern.
- **Cross-ref:** PR #228 Phase B line ~2779; ADR-0011 V4 authority cleanup; p180 sweep work; code-reviewer review at p209 close.

### 103. WATCH-226.B (renamed) — GRANT EXECUTE not repeated in Phase B capture files (code-reviewer PR #228 LOW)
- **Tipo:** watch / documentation · **Severity:** LOW · **Effort:** XS (clarified inline)
- **Trigger:** code-reviewer noted Phase B capture file (20260802000001) does NOT include GRANT EXECUTE statements for the 26 captured functions. Relies on grants from original CREATE FUNCTION migrations remaining in effect after CREATE OR REPLACE. Same pattern as 20260723000000 baseline + other Phase B captures (p178, p176).
- **Impact:** For fresh-DB applies (`supabase db reset` or local stack bootstrap), grants are correctly preserved because all migrations replay in order. No production impact. Documentation gap addressed inline (Phase B header amended at PR #228 amendment commit).
- **Resolution:** Phase B file header updated with explicit caveat (commit pending). No new migration needed.
- **Validation gate:** Fresh `supabase db reset` test in next deploy validates grants intact for captured functions.
- **Cross-ref:** Code-reviewer PR #228 review (background agent at p209 close); WATCH-226.A is different (platform-guardian finding re drift capture deadline).

### 104. RESOLVED-209.E — A1 cycle4-2026 leader_extra max:5→10 + RPC validation (PM ask 2026-05-21)
- **Tipo:** bug / silent data corruption · **Severity:** HIGH (would have continued to corrupt cohort comparisons + accepted invalid scores silently) · **Effort:** S (~30 min discovery + apply)
- **Trigger:** PM chat at p209 mid-session: "Henrique continua claramente acima do band superior (219 vs 170.96). Tres anomalias ainda em aberto. Anomalia 1 — schema leader_extra ainda em max: 5". Investigation revealed 3 distinct issues; A1 fixed in-session via 2 migrations.
- **Root cause (A1)**: historical drift in `selection_cycles.leader_extra_criteria`. Original seed (cycle3, migration 20260319100024) had ALL criteria max:5. Migration 20260401090000_evaluation_rubrics_advisory_panel.sql bumped `objective_criteria` to max:10 with anchored guides for inter-rater reliability — but `leader_extra_criteria` was FORGOTTEN in that pass. ~7 weeks of drift (2026-04-01 → 2026-05-21). `submit_evaluation` RPC didn't validate score against schema max, so evaluators using max:10 scale (Fabricio: Francisleila scores 7-8) had submissions silently accepted with weighted_subtotal=162 (when ostensible "valid" max would be 110).
- **Fix**:
  - Migration 20260802000002 — UPDATE selection_cycles SET leader_extra_criteria with jsonb_set max:10 for active cycles (cycle3-2026-b2 + cycle4-2026). Idempotent. Applied via execute_sql (DML).
  - Migration 20260802000003 — CREATE OR REPLACE submit_evaluation adding `v_max := COALESCE((v_criterion->>'max')::numeric, 10);` + `IF v_score < 0 OR v_score > v_max THEN RAISE EXCEPTION` inside scores loop. Applied via apply_migration MCP. Body re-verified live post-apply.
- **Impact preserved**: Cycle4-2026 had 2 existing leader_extra evals. Vitor's William (scores 1-4) valid under both scales. Fabricio's Francisleila (scores 5-8) valid under max:10. Both preserved per PM Option A.
- **A2 deferred**: PM Option A for cohort separation refactor (leader_extra mutates objective_score_avg) — filed as Issue #229. Scope ~3-5h (new columns + RPC branch + UI changes + backfill + tests).
- **A3 NOT a bug**: Henrique cutoff null because zero evaluations submitted (application created 2026-05-21 03:07).
- **Direct apply pattern**: per PM instruction "vc consegue fazer aplicacao por aqui que é muito mais controlada". Increments WATCH-209.C count by 2 (commit fd322767 + apply_migration call) — now 10 bypass events total in 4-day window. PM-authorized for isolated fixes; documented per WATCH-209.C distinction.
- **Cross-ref:** Issue #229 (A2 cohort separation); migration 20260802000002 + 20260802000003; PM chat 2026-05-21 p209 mid-session; PR #228 (#226 work in same window).

### 105. RESOLVED-211.A — /admin/analytics 404 console noise reverted (p209 L2 over-restore unwound)
- **Tipo:** bug / dev console noise from feedback_drop_function_audit_wrappers.md anti-pattern recurrence · **Severity:** LOW (no user-visible UX impact; only DevTools network log) · **Effort:** XS (~30 min discovery + fix)
- **Trigger:** PM smoke 2026-05-21 p211 boot ran browser checklist; /admin/analytics surfaced 2× PGRST202 404 errors in console for `exec_funnel_summary` + `exec_analytics_v2_quality` despite p210 handoff claiming all smokes OK.
- **Root cause:** Migration `20260426171855_drop_dead_analytics_chain_p59.sql` (p59, 2026-04-26) dropped 5 RPCs as "dead chain" — audit missed `safeRpc('NAME')` wrapper callers in analytics.astro (canonical pattern from `feedback_drop_function_audit_wrappers.md`). p190 BUG-190.B response replaced calls with `Promise.resolve(null)`. p209/p220 L2 fix (commit `abe7e965`, PR #225) RESTORED the safeRpc calls solely to satisfy `browser-guards.test.mjs` mock assertions — but real PostgREST schema cache has no record of those functions, so the calls returned 404 in prod, polluting DevTools console (mocks only intercept in test environment).
- **Fix (PM Option A):** Reverted analytics.astro:913,918 to `Promise.resolve(null)` (restored p190 state). Updated `ui-stabilization.test.mjs:349,353` from `true → false`. Removed 4 brittle assertions from `browser-guards.test.mjs:520,522,531,532` that depended on mock data from RPCs that don't exist in prod (kept #analytics-interpretation-card visibility + transition matrix data flow + copy button Scope: line). Net diff: +20/-25 lines across 3 files.
- **Why not Option B/C:** Recreating the 5 dropped RPCs (Option B, 2-3h) or building canonical replacements on `volunteer_funnel_summary` + `analytics_role_bucket` (Option C, 3-5h) deferred — PM picked A as honest alignment of code+tests to reality. Canonical rebuild still tracked OPP-190.I.
- **Sediment-level lesson:** Test mocks must not lock frontend into calling dropped RPCs. When a feedback memory documents an anti-pattern, the FIX direction matters as much as the diagnosis — p209 L2 "restored calls" was the wrong vector; should have been "removed test assertions that demanded broken calls."
- **Cross-ref:** PR #225 (p209 L2 restore, now partially unwound); migration 20260426171855_drop_dead_analytics_chain_p59.sql; `feedback_drop_function_audit_wrappers.md` (recurrence #3 of same anti-pattern); OPP-190.I (canonical analytics rebuild backlog); Issue #220 (CI noise context, distinct concern — CI green now); Issue #233 (canonical analytics rebuild spec-blocked).

### 106. RESOLVED-212.A — Engagement welcome email link 404 (Issue #217, p211)
- **Tipo:** bug / user-visible 404 since ADR-0060 G7 deploy · **Severity:** HIGH (every engagement-welcome email since deploy landed on 404) · **Effort:** XS (~20 min)
- **Trigger:** PM 2026-05-20: "robo mandou email aos participantes da iniciativa, link cai em página 404." URL `https://nucleoia.vitormr.dev/iniciativas/<uuid>`. Real route is `/initiative/[id]` (English singular). Bug filed as #217 by p207 boot.
- **Root cause:** `_enqueue_engagement_welcome` SQL function (SECURITY DEFINER) generated `v_link := '/iniciativas/' || COALESCE(v_eng.initiative_id::text, '');`. The PT-BR plural path never existed as a route — only `/initiative/[id]` singular. ADR-0060 G7 author likely confused PT-BR/EN naming.
- **Fix:** Migration `20260802000007_fix_engagement_welcome_url.sql` — CREATE OR REPLACE `_enqueue_engagement_welcome` with `'/initiative/'` literal. Body byte-equivalent to pre-fix except for the literal. Applied via `apply_migration` MCP + local file written + `supabase migration repair --status applied 20260802000007` + `NOTIFY pgrst`. Post-apply check: `pg_get_functiondef LIKE '%/initiative/%' AND NOT LIKE '%/iniciativas/%'` = PASS. Contract test added at `tests/contracts/enqueue-engagement-welcome-url.test.mjs` — locates latest CREATE OR REPLACE block for this function across migrations dir and asserts URL canonicalization; catches future regression.
- **Why not broader sweep:** `grep -r "'/iniciativas/'" --include="*.sql"` returned ONLY this function (in original create migration + p178 drift capture, both historical). No other notification template uses the bad path. Forward defense: contract test guards the canonical function body.
- **Cross-ref:** Issue #217 BUG-212.A; ADR-0060 G7 (engagement welcome email spec); migration `20260514310000_adr_0060_g7_engagement_welcome_email_trigger.sql` (original create with bad URL); `20260686000000_p178_phase_b_drift_capture_1_touch_q_z_underscore_63fns.sql` (drift capture preserving bad URL); Issue #212 spec (Initiative Collaboration Hub — references this as G0 notification primitive gap).

### 107. RESOLVED-216.A — /profile ReferenceError 3rd recurrence — TS-annotation × Vite-minify sweep (Issue #216, p211)
- **Tipo:** bug / module-scope variable lost in minified bundle · **Severity:** HIGH (user-visible — `/profile` ReferenceError blocks XP pillars + champions + cycle history sections) · **Effort:** S (~30 min surgical strip + verify)
- **Trigger:** PM smoke 2026-05-20: `Uncaught ReferenceError: t is not defined at pt (profile.astro_astro_type_script_index_0_lang.v3Zqq7wC.js:116:1585)`. 3rd recurrence of same class — p158 (`e098c398`), p184 (inline annotation in profile.astro), p211 (this fix). Spec doc: `docs/project-governance/sessions/p207_issue_216_profile_ts_annotation_minify.md`.
- **Root cause:** Module-level `const X: SomeType = value` and `let Y: any = null` patterns in the `<script>` block of `src/pages/profile.astro` (NOT `is:inline`, so Astro+Vite minifies it). Vite's minify strips type annotations but in doing so loses the module-scope binding of the variable when used by sibling functions (TDZ + minifier interaction). Symptom: variable name is undefined in minified bundle even though declared at module top.
- **Fix (PM Option A2026-05-21):** Reverted the over-aggressive WIP working-tree esbuild-rewrite of the entire script block (which had collapsed quotes single→double + lost source comments + inflated diff to 2700 lines). Instead, surgical Edit ops stripped 24 module-level TS annotations on const/let declarations: 5× `: Record<string, string>`, 12× `: any`, `: any[]`, `: any | null`, 4× `: string`, 1× `: 'lifetime' | 'cycle'`, 1× multi-line `: { ... } | null`, 1× `: ReturnType<typeof setTimeout> | null`. Inline comment block at the top updated with p211 sweep line documenting the 3rd-recurrence context. Function-scoped annotations LEFT UNTOUCHED (safe per spec).
- **Test wiring (WATCH-213.C pattern):** New contract test `tests/contracts/enqueue-engagement-welcome-url.test.mjs` (from #217 fix in same session) added to BOTH `npm test` and `npm run test:contracts` scripts in package.json. Without explicit wiring, contract tests outside the hardcoded list silently SKIP — see WATCH-213.C precedent.
- **Forward-defense backlog:** WATCH-216.A — audit script that grep's `^\s+(const|let|var)\s+\w+:\s*` inside any `<script>` block (not `is:inline` not `define:vars`) across `.astro` pages + fail CI if found. Pattern is mechanical; ESLint rule overkill for a 1-line grep. Alternative: file `scripts/audit-astro-script-ts-annotations.mjs` + npm script + add to GC-097 pre-commit list.
- **Why not WIP keep:** esbuild full-rewrite normalized quotes (broke 3 ui-stabilization test assertions on `case 'verify-credly':` etc); injected `/* @__PURE__ */ __name(...)` boilerplate everywhere; lost source comments documenting p158/p184 history. Spec said "surgical — strip annotation, manter inicialização" — WIP went far beyond. Reverted via `git checkout HEAD --` + did surgical Edit ops per spec.
- **Cross-ref:** Issue #216 spec; commit `e098c398` (p158 fix#8); P162 #105 (analytics 404 — same p211 session); Spec doc `docs/project-governance/sessions/p207_issue_216_profile_ts_annotation_minify.md`; `feedback_astro_define_vars_no_ts.md` (adjacent class — p169 sediment).

### 108. RESOLVED-227.A — selection-resumes RLS already fixed by p209 Phase A; forward-defense contract test added (Issue #227, p211)
- **Tipo:** verification + forward-defense (bug pre-resolved by prior session) · **Severity:** N/A (resolved) · **Effort:** XS (~15 min verify + test write)
- **Trigger:** Per PM 2026-05-21 p211: next focus = #227. Investigation showed the bug described in #227 (`can(auth.uid(), 'view_pii')` direct call) had ALREADY been fixed by p209 PR #228 commit `658e09de` (Phase A SECDEF migration `20260802000000_p209_issue_226_phase_a_storage_policy_use_rls_can.sql`), applied via Supabase Studio UI Storage > Policies tab per `storage.objects` ownership chain.
- **Verification:** Live `pg_policies` query at p211 confirmed `selection_resumes_read_view_pii` uses `rls_can('view_pii')` (NOT `can(auth.uid(), 'view_pii')`). Direct probe via `can_by_member(m.id, 'view_pii')` + `can(m.person_id, 'view_pii')` both return TRUE for Vitor + Fabricio (the 2 users mentioned in #227). Forward-defense scan: `pg_policies` WHERE qual ILIKE '%can(auth.uid()%' returned 0 rows. Clean.
- **Forward-defense contract test:** Created `tests/contracts/storage-rls-can-auth-uid-forbidden.test.mjs` with 2 static checks: (1) Phase A migration `20260802000000` MUST exist + use `rls_can('view_pii')` for the corrected policy; (2) no migration AFTER cutover `20260802000000` may introduce a `CREATE POLICY ... USING (... can(auth.uid() ...))` block. Cutover approach used because 4 historical migrations legitimately contain the buggy text (p195 original + p178 drift capture + Phase A DROP + v4 phase7 RPC) — grepping all would false-flag. Wired into both `npm test` + `npm run test:contracts`.
- **Why static not behavioural:** PostgREST does not expose system catalogs (pg_policies). Adding a SECDEF helper just for this test would be overkill. Live audit via `pg_policies` query lives in `/audit` skill instead.
- **Closing evidence:** rls_can() definition reads `SELECT can((SELECT p.id FROM persons p WHERE p.auth_id = auth.uid() LIMIT 1), p_action)` — the canonical translation #227 said was needed. PM smoke `/admin/selection` 2026-05-21 returned "selection ok" (page loads — CV button click test still pending).
- **Cross-ref:** Issue #227; PR #228 (`658e09de` Phase A SECDEF + Phase B drift capture 26 fns); ADR-0007 (V4 canonical authority); migration `20260802000000_p209_issue_226_phase_a_storage_policy_use_rls_can.sql`; `rls_can(p_action)` helper definition; commit `46267ae1` (Codex p208 — UI race fix that masked symptom).

### 109. RESOLVED-232.A — Bypass-audit week 2026-W21 reviewed + closed; v2 detection filed (Issue #232, p211)
- **Tipo:** governance / first weekly audit review · **Severity:** N/A (procedural) · **Effort:** XS (~30 min review + comment + close + v2 issue)
- **Trigger:** PM ask 2026-05-21 p211: focus on #232. Issue auto-generated by `.github/workflows/bypass-audit-weekly.yml` (manual workflow_dispatch test run at p209 close 06:13 UTC) reported 61 events for 7-day window — threshold (2) exceeded.
- **Investigation findings:** v1 detection has 2 issues. (1) **Direct-push over-count** (61 vs ~7 real): counts every commit on main with parents=1 not in a PR, including doc updates + drift captures + post-merge cleanups + pre-window commits. (2) **--admin under-count** (0 vs 9 real): `gh api check-runs --jq 'first'` returns LATEST validate run, not at-merge-time; when --admin bypassed FAILED validate but CI re-ran later and passed, audit sees "success" and doesn't flag.
- **Legitimacy review for 16 real bypasses (per p210 handoff):** All 9 --admin merges (#199 #184 #197 #198 #223 #225 #215 #228 #222) had pre-existing CI red (#220 workerd DNS blocker since 2026-05-18) OR PM-authorized emergency (Whisper Art. 11 LGPD). All 7 direct pushes were post-merge drift captures + Codex reconciliation + emergency hotfixes during marathon. No impatient bypass pattern.
- **Decision per protocol step 3 (all legitimate → document + acknowledge):** Closed #232 as audited. Documented cause (8h marathon during multi-day CI red), pattern (justified bypasses with at-merge documentation), no erosion (p210/p211 sessions required 0 --admin merges).
- **v2 detection filed:** Issue #235 — refine direct-push filter (check parent validate=FAILURE) + --admin at-merge-time check_runs semantics. Effort S (1-2h). When shipped, audit output will normalize to ~16 (real) instead of 61.
- **Stop-gap for 2026-W22 audit (Mon 2026-05-25):** PM cross-references session handoffs to identify real bypasses; applies criteria only to real subset; ignores v1 noise. Documented in #235 issue body.
- **Cross-ref:** Issue #232 (closed); Issue #235 (v2 detection); commit `a443a77d` (Option C Híbrido governance origin); `.claude/rules/bypass-protocol.md` (criteria); `.github/workflows/bypass-audit-weekly.yml` (v1 script to refine); p209/p210 handoffs (16 real bypass catalog).

### 110. RESOLVED-224.A — /admin/selection JSON import observability (Issue #224, PR #236, p212)
- **Tipo:** observability / user-visible UX (admin) — generic "ver detalhes no cron_run_log do worker" hint replaced with structured inline errors · **Severity:** HIGH (real-world impact discovered) · **Effort:** M (~2.5h full scope C end-to-end)
- **Trigger:** PM ask 2026-05-21 p212 (post-p211 close): focus on #224. Sample JSON `/home/vitormrodovalho/Downloads/A/pmi_volunteer_full_enriched_2026-05-21.json` already pre-loaded by Codex curation comment.
- **What shipped:**
  - **UI (selection.astro)**: 3 new render helpers — `renderWorkerErrorsBlock(errors)` groups worker errors by scope with ref + sanitized message; `renderIngestResultWarning(payload)` surfaces Phase A extract result as yellow info banner (narrowed to `{error}` only per code-reviewer M1); `renderCorrelationFooter(d, appliedAt)` shows cycle_code + run_id (clipboard-copyable) + ISO timestamp. `renderJsonApplyResult` palette switches amber-vs-emerald by `errs > 0`. Same treatment in dry-run preview path (warning + correlation; errors not populated in dry-run path). Clipboard handler wired in both paths.
  - **Worker (pmi-vep-sync /ingest)**: `IngestSummary.run_id` + `IngestSummary.ingest_result_warning` + same on `IngestDryRunSummary`. Both stamped before return in apply + dry-run paths. `ScriptIngestPayload.ingestResult` declared so worker can pass through.
  - **i18n**: 6 new keys (pt-BR + en-US + es-LATAM) — `importJsonResultPartialTitle`, `importJsonCorrelationCycle/RunId/Applied`, `importJsonErrorsHeader`, `importJsonIngestResultWarning`. SEL_I18N bundle exposes `importJson.*` subpath.
  - **Contract test**: `tests/contracts/admin-selection-import-error-rendering.test.mjs` — 9 static assertions wired to npm test + npm run test:contracts.
- **Pipeline discovery (separate issue):** Reproducer via `cron_run_log` snapshot exposed **BUG-224.A** — 3 cycle4-2026 candidates missed welcome emails between 2026-05-19 → 2026-05-21 because `issueOnboardingToken` was throwing constraint violation. The observability fix made this visible; BUG-224.A was filed as Issue #237 + fixed in PR #238 (entry #111) + manually backfilled in same session.
- **Council Tier 1 (PR #236):** platform-guardian GO-WITH-AMENDMENTS (LOW deploy.md baseline bump + 4 pre-existing test:contracts gaps backlog) + code-reviewer GO-WITH-AMENDMENTS (M1 PII narrow on renderIngestResultWarning + M2 verified non-issue + L1 dry-run clipboard handler + L2 test regex robustness + L3 strip phaseB). All applied inline in amendment commit `405b3080` before merge.
- **Validation:** npm test 1499/0/50 (+9 from p211 baseline 1490); npx astro build clean; new contract test 9/9 in isolation. Worker redeployed Version `cd7ea6d8`.
- **Merge:** Squash `704fa2f0` 2026-05-21 08:01 UTC. No --admin bypass (CI green except pre-existing CodeQL fail).
- **Cross-ref:** Issue #224 (closed); PR #236 (merged); Issue #237 (BUG-224.A filed + fixed); deploy worker Version cd7ea6d8; council code-reviewer M2 (esc on attr) verified non-issue with HTML5 entity-decoding spec; feedback memory candidates: not promoted yet (4 inline lessons in PR commit body).

### 111. RESOLVED-237.A — BUG-224.A onboarding_tokens.organization_id pass-through fix (Issue #237, PR #238, p212)
- **Tipo:** bug / hidden data loss (3 missed welcome emails) · **Severity:** HIGH (cycle4-2026 NEW applicants did not receive onboarding emails 2026-05-19 → 2026-05-21) · **Effort:** S (~1h fix + backfill)
- **Trigger:** Discovered during #224 reproducer (P162 #110). Filed as #237 after-merge of #236, fixed + backfilled same session.
- **Root cause:** `onboarding_tokens.organization_id` is `NOT NULL DEFAULT auth_org()`. The pmi-vep-sync worker connects via `SUPABASE_SERVICE_ROLE_KEY` which has no JWT / `auth.uid()` context — so `auth_org()` returns NULL and the constraint fires. `issueOnboardingToken()` in `cloudflare-workers/pmi-vep-sync/src/onboarding-token.ts` did NOT pass `organization_id` explicitly. Result: every NEW applicant in cycle4-2026 since worker deploy had failed token issuance → no welcome email. Hidden by generic UI hint (until #224 fixed observability).
- **Fix:**
  - **Worker (onboarding-token.ts)**: `IssueTokenOpts.organization_id` declared as REQUIRED `string` (no `?:`). Insert payload literal includes `organization_id: opts.organization_id`. Comment block documents the auth_org() ↔ JWT-context pattern.
  - **Worker (index.ts /ingest)**: caller passes `organization_id: env.ORG_ID`. `env.ORG_ID` was already a bound env var (confirmed at deploy "env.ORG_ID (\"2b4f58ab-7c45-4170-8718-b77ee69ff906\")"), so no env config change needed.
  - **Council code-reviewer HIGH amendment**: early guard `if (!env.ORG_ID) return server_misconfig 500` added in handleIngest. Wrangler doesn't enforce `[vars]` presence at deploy time; this surfaces misconfig at request time with clear actionable message instead of Postgres 22P02 buried in per-app error log.
  - **Contract test**: `tests/contracts/onboarding-token-organization-id.test.mjs` — 4 static assertions (interface field required, insert payload key, /ingest caller passes env.ORG_ID, guard against missing env.ORG_ID).
- **Manual backfill (same session):** Direct SQL via MCP `execute_sql` — DO block iterated 3 application_ids, generated tokens via `gen_random_bytes(32)` + base64url + `digest(... 'sha256')`, INSERTed onboarding_tokens with `organization_id` explicit, called `campaign_send_one_off(p_template_slug := 'pmi_welcome_with_token', ...)`. Result: 3 onboarding_tokens created + 3 campaign_sends `status='sent'` (Resend accepted delivery). Issued_by_worker stamped as 'pmi-vep-sync-backfill-bug224a' for traceability.
- **Council Tier 1 (PR #238):** platform-guardian GO (no schema impact + class-of-bugs scan confirmed only this caller affected, all other `onboarding_tokens` inserts already pass org_id) + code-reviewer GO-WITH-AMENDMENTS (HIGH env.ORG_ID guard + LOW UUID-in-test-comment cleanup). All applied inline in amendment commit `8d5d9e95` before merge.
- **Validation:** npm test 1503/0/50 (+4 from p212 #224 baseline 1499); npx astro build clean; new contract test 4/4 in isolation. Worker redeployed Version `26a850e4`.
- **Merge:** Squash `f47a1428` 2026-05-21 08:19 UTC. No --admin bypass (CI green).
- **Backfill verification:** 3 onboarding_tokens with organization_id correctly set + expires_at 2026-05-28 + scopes correct + issued_by_worker traceable. 3 campaign_sends status='sent'. 18/18 invariants = 0 violations post-backfill. 0 synth leaks.
- **Cross-ref:** Issue #237 (closed); PR #238 (merged); Issue #224 + PR #236 (parent observability that surfaced this bug); deploy worker Version 26a850e4; council audit script `_audit_list_public_function_bodies` lookups for class-of-bugs scan; GAP-237.A LOW backlog (sync-artia hardcodes PMI_GO_ORG_ID — single-tenant safe today, sweep at multi-tenant milestone); WATCH-237.A LOW backlog (architecturally: derive `organization_id` from `selection_cycles.organization_id` instead of `env.ORG_ID` pass-through; multi-tenant cleaner future path).

### 112. WATCH-224.A — observability invariant for welcome dispatch completeness (p212 backlog)
- **Tipo:** test gap / WATCH · **Severity:** LOW · **Effort:** S (~1h DB-aware contract test)
- **Trigger:** code-reviewer suggested during PR #236 review. Not addressed in #237 fix (scope discipline).
- **Description:** DB-aware contract test that asserts `applications_new === welcome_dispatched + welcomes_skipped_non_submitted` after every successful /ingest apply. If violated → constraint or downstream failure exists (the exact class that hid BUG-224.A for 22+ days).
- **Where to add:** `tests/contracts/worker-ingest-welcome-dispatch-completeness.test.mjs` (new), DB-aware path. Requires `SUPABASE_URL` + `SUPABASE_SERVICE_ROLE_KEY` env (skips silently without per WATCH-213.C).
- **When to ship:** Next maintenance session; not blocking.
- **Cross-ref:** P162 #110 (PR #236 observability); P162 #111 (PR #238 fix); council code-reviewer flag in PR #236 review.

### 113. WATCH-237.A — multi-tenant ORG_ID derivation from selection_cycles (p212 backlog)
- **Tipo:** architectural backlog · **Severity:** LOW · **Effort:** M (~2h refactor + test)
- **Trigger:** code-reviewer flagged during PR #238 review. Not addressed in this session (single-tenant safe today).
- **Description:** `env.ORG_ID` hardcoded pass-through is correct for single-tenant deployment. If multi-tenant: derive `organization_id` from `selection_cycles.organization_id` row (one DB round-trip per ingest run) — single source of truth, no env-binding drift risk.
- **When to ship:** At multi-tenant milestone (not before — single-tenant means env.ORG_ID is correct by definition).
- **Cross-ref:** P162 #111 (PR #238 fix); GAP-237.A (related: sync-artia hardcoded PMI_GO_ORG_ID); ADR-0007 (V4 authority — engagement-derived authority resolves org via canonical query path).

### 114. GAP-237.A — sync-artia worker hardcodes PMI_GO_ORG_ID literal (p212 backlog)
- **Tipo:** dev-time tech-debt / sweep-on-multi-tenant · **Severity:** LOW · **Effort:** XS (~15 min env var)
- **Trigger:** platform-guardian flagged during PR #238 review. Not in this PR's scope.
- **Description:** `supabase/functions/sync-artia/index.ts:12` hardcodes `PMI_GO_ORG_ID = '2b4f58ab-7c45-4170-8718-b77ee69ff906'` as string literal rather than reading from env. Carries inline comment documenting the JWT-context root cause, but does not abstract to env. Will need sweep if second tenant onboards.
- **When to ship:** At multi-tenant milestone (single-tenant safe today).
- **Cross-ref:** P162 #111 (PR #238 fix); WATCH-237.A; `supabase/functions/sync-artia/index.ts:12`.

### 115. RESOLVED-205.A — Alternate member emails subsystem + 3 RPCs + 3 MCP tools + invariant T (Issue #205, PR #240, p213)
- **Tipo:** structural feature ship · **Severity:** N/A (resolved) · **Effort:** L (delivered)
- **Trigger:** PM ask 2026-05-21 — modernize identity resolution to support members with multiple email addresses (personal/institutional/chapter/other) for DocuSign + Credly + chapter integrations.
- **Description:** PR #240 merges agent/p212-close-log (af378809 + ec988042 + de109c7b). Net change:
  - New table `public.member_emails` (citext UNIQUE, partial unique idx on `is_primary`, FK CASCADE to members)
  - Trigger `sync_member_email_trigger_fn` keeps `members.email` ↔ `member_emails` primary in sync
  - 3 SECDEF RPCs: `member_resolve_email` (auth-gated) / `member_list_emails` (self / manage_member / view_pii) / `member_add_alternate_email` (self / manage_member)
  - 3 MCP tools: 293 → **296**
  - Invariant T added to `check_schema_invariants()`: 18 → **19**, all violation_count=0 live; synthetic test members filtered from A1/A2/A3/B/T per defense-in-depth
  - ADR-0095 ratified
  - Council Tier 1 BLOCKERs + HIGHs all resolved via 3 migrations (008/009/010) + ec988042 test refactor + de109c7b HTTP 204 fix
- **Live verified:** member_emails 73 rows, 1-to-1 primary backfill, MCP tools/list = 296, invariant T = 0 violations, trigger cross-member guard live, REVOKE SELECT FROM authenticated took effect.
- **Cross-ref:** ADR-0095; PR #240; commits af378809 + ec988042 + de109c7b; migrations 20260802000008-10.

### 116. GAP-205.A — RLS cross-tenant authenticated read test missing (member_emails)
- **Tipo:** test coverage gap · **Severity:** MED · **Effort:** S (~30 min)
- **Trigger:** code-reviewer HIGH-4 + platform-guardian LOW-2 in PR #240 council review.
- **Description:** `tests/contracts/member_emails.test.mjs` Step 7 only tests no-Authorization-header rejection (trivial 401). The RESTRICTIVE policy `member_emails_v4_org_scope` (auth_org() isolation) is never exercised. Multi-tenant defense is the actual concern when 2nd tenant onboards.
- **Fix:** add sub-test that creates a member in a different org or uses an anon-key+authenticated-JWT-for-different-org pair, calls direct GET on `/rest/v1/member_emails?member_id=eq.<id>` and asserts result is empty.
- **When to ship:** At multi-tenant milestone OR sooner if PR #240 backlog burndown.
- **Cross-ref:** ADR-0095 §3; `member_emails_v4_org_scope` policy in migration `20260802000008`.

### 117. GAP-205.B — `member_emails.organization_id` has no FK to `organizations(id)`
- **Tipo:** schema integrity gap · **Severity:** LOW · **Effort:** XS (~5 min ALTER TABLE)
- **Trigger:** code-reviewer MED-1 + platform-guardian LOW-3 in PR #240 council review.
- **Description:** Other multi-tenant tables use `organization_id uuid REFERENCES public.organizations(id)`. `member_emails.organization_id` is just `uuid` (nullable, no FK). Dangling org refs possible if a bad insert happens. Currently the only writer is the sync trigger which copies `members.organization_id` (FK-enforced), so risk is low — but explicit FK is defense in depth.
- **Fix:** `ALTER TABLE public.member_emails ADD CONSTRAINT member_emails_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE SET NULL;` via new migration.
- **When to ship:** Backlog (next session that touches member_emails).

### 118. GAP-205.C — `member_emails.verified_at` column has no verification flow
- **Tipo:** dead schema / future surface · **Severity:** LOW · **Effort:** S-M (workflow design)
- **Trigger:** code-reviewer LOW in PR #240 council review.
- **Description:** `verified_at timestamptz` column exists in `member_emails` per ADR-0095 §1 but no write path sets it. Currently the column is dead. Either:
  - (a) Ship the verification flow: email confirmation token → RPC `member_verify_alternate_email` → sets `verified_at`
  - (b) Drop the column before downstream assumptions accumulate
- **When to ship:** At the moment the first integration needs verified-only emails (e.g., DocuSign signing).

### 119. WATCH-205.D — `database.gen.ts` regen added `graphql_public` schema surface (PR #240)
- **Tipo:** surface expansion / observability · **Severity:** LOW · **Effort:** XS (audit only)
- **Trigger:** platform-guardian MED-2 + code-reviewer LOW-3 in PR #240 council review.
- **Description:** PR #240's `database.gen.ts` regen included a new `graphql_public` schema block, which comes from Supabase's `pg_graphql` extension detection. Not a defect but a surface expansion — the type layer now exposes graphql_public types that weren't previously visible. Verify whether this causes unintended PostgREST/type-surface exposure downstream.
- **Fix:** sanity-check that `pg_graphql` is intentionally enabled + no UI/RPC accidentally consumes graphql_public types.
- **When to ship:** Backlog (passive audit, no urgency).

### 120. WATCH-205.E — Concurrent agent workflow: 20260802000008 file modified post-apply created file/live drift (resolved by 20260802000010)
- **Tipo:** workflow / sediment lesson · **Severity:** MED (pattern recurrence risk) · **Effort:** docs only
- **Trigger:** mid-session discovery during PR #240 amendments — concurrent agent's `ec988042` modified `20260802000008` file body (added `_synthetic` filter to invariants) but did not apply the change to live DB.
- **Description:** Modifying already-applied migration files is an anti-pattern — the schema_migrations.statements[V] is the at-apply snapshot (immutable), and any file edit after apply causes file/live drift that Phase C body-hash gate would flag. The correct pattern: NEW migration with `CREATE OR REPLACE FUNCTION` block for the function update. This session resolved the drift by adding `20260802000010` to apply the filter to live; the modified `20260802000008` file is now historical documentation of intent.
- **Sediment lesson:** When a council finding requires changes to an already-applied function, ALWAYS author a new follow-up migration (next-greater timestamp); never edit the original file's body. Update CLAUDE.md or `.claude/rules/database.md` to document explicitly.
- **Cross-ref:** P162 #115 (PR #240); commits ec988042 + de109c7b; migrations 20260802000008-10.

### 121. RESOLVED-205.C — Drop dead-schema `member_emails.verified_at` column (Issue #205 GAP-205.C, PR #242, p215)
- **Tipo:** YAGNI cleanup / dead schema · **Severity:** LOW · **Effort:** XS (completed)
- **Trigger:** P162 #118 GAP-205.C deferred at p214 close — PM ABCD pick "Drop column (Recommended)" at p215 boot.
- **Description:** `member_emails.verified_at timestamptz` had 0 write paths anywhere in migrations/RPCs/EFs/src/tests; 0 of 73 rows non-NULL; 0 readers apart from `member_list_emails` return TABLE projection. Migration `20260802000012_p215_205c_drop_member_emails_verified_at.sql` performed `DROP FUNCTION member_list_emails(uuid)` + `ALTER TABLE member_emails DROP COLUMN verified_at` + rebuilt `member_list_emails` without verified_at in return TABLE (SECDEF body byte-identical otherwise). 2 forward-defense contract tests added (`member-emails-rls-multi-tenant.test.mjs` #12 + #13) asserting column absence in canonical migration + RPC return TABLE. ADR-0095 amended with "Amendment 2026-05-21 (GAP-205.C)" section documenting rationale + reversibility. `database.gen.ts` regenerated via canonical `npm run db:types`.
- **Smoke:** PM verified via MCP host (resolve + list + add all green, smoke row `7e96d90a-8b26-4ddd-9875-2aa44bb0cbbb` `vitor@vitormr.dev` kind=personal kept as legitimate alternate).
- **Cross-ref:** Issue #205, PR #242 squash `4be3ad83`, ADR-0095, migration 20260802000012, P162 #118.

### 122. WATCH-215.A — Static-analysis test convention: accept both `CREATE FUNCTION` (post-DROP per GC-097) and `CREATE OR REPLACE FUNCTION`
- **Tipo:** test convention / sediment · **Severity:** LOW · **Effort:** S (1-2h sweep)
- **Trigger:** platform-guardian PR #242 BLOCKER B-1 — `member-emails-rls-multi-tenant.test.mjs` regex required `CREATE OR REPLACE FUNCTION` but migration 20260802000012 correctly used `CREATE FUNCTION` after explicit DROP (per GC-097 when changing return type). Test silently latched onto stale 20260802000008 body; assertions coincidentally passed because auth-gate logic is unchanged.
- **Description:** Other contract tests that perform static migration analysis may still use the strict `CREATE OR REPLACE FUNCTION` regex. The shared parser at `tests/helpers/rpc-body-drift-parser.mjs:43` is already pattern-agnostic (accepts both forms). Test files should follow the same convention to avoid false-pass on DROP+CREATE migrations.
- **Resolution this session:** all 4 regex blocks in `member-emails-rls-multi-tenant.test.mjs` updated to `CREATE(?:\\s+OR\\s+REPLACE)?\\s+FUNCTION` + inline comment with rationale + sediment ref. Project-wide sweep pending.
- **Cross-ref:** PR #242 amendment commit `89aed393`; tests/helpers/rpc-body-drift-parser.mjs:43; GC-097.

### 123. WATCH-215.B — `apply_migration` MCP body MUST be byte-identical to canonical migration file (including inline comments)
- **Tipo:** workflow sediment / CI gate · **Severity:** MED (Phase C drift gate fires on next CI) · **Effort:** S (no code change; pattern reinforcement)
- **Trigger:** mid-PR #242 — CI run 26245524978 failed Phase C body-hash drift: `[2x] member_list_emails(p_member_id uuid) live_len=941 mig_len=1056 latest=20260802000012`. Gap of 115 chars = 2 inline comments (`-- Determine if service_role...` + `-- Check if self...`) that I had in the migration file but omitted from the `apply_migration` MCP call body.
- **Description:** When invoking `mcp__supabase__apply_migration`, the `query` parameter MUST be byte-identical to the canonical migration file (including all inline comments inside SECDEF function bodies, since `pg_get_functiondef` preserves them in `prosrc`). Omitting comments creates file/live drift that Phase C body-hash gate detects on next CI run. This is the third recurrence of an apply_migration-related sediment (after WATCH-205.E and Q-C). Either: paste-the-file-verbatim convention OR pre-deploy script that diffs file hash vs MCP call hash.
- **Resolution this session:** removed the 2 inline comments from migration file (file = feature branch, not merged yet, so editing is OK per WATCH-205.E pre-merge clause). Live body now byte-matches file body (md5 `7147ef6a96eb1cc38c9058f6e1963c4d`, len=941). Commit `d631abb0`.
- **Cross-ref:** WATCH-205.E, Q-C (apply_migration MCP doesn't auto-register schema_migrations), CI run 26245524978, commit d631abb0.

### 124. WATCH-205.F — `database.gen.ts` regen source parity: MCP `generate_typescript_types` omits `graphql_public` schema block
- **Tipo:** tool divergence / observability · **Severity:** LOW · **Effort:** M (investigation + potential CI addition)
- **Trigger:** code-reviewer PR #242 MED finding — initial regen via `mcp__supabase__generate_typescript_types` dropped the `graphql_public` schema block that canonical `npm run db:types` (`supabase gen types typescript --linked`) includes. File was 21159 lines vs 21187 with CLI; `graphql_public` block (lines 15 + 21151) absent.
- **Description:** Two regen tools produce different outputs. Currently no consumer depends on `graphql_public` types (grep returns 0 hits), so impact is null. But future drift undetected. Consider: (a) CI parity check comparing MCP regen output vs CLI; (b) ADR/deploy.md note declaring CLI canonical; (c) project script to enforce.
- **Resolution this session:** regenerated via canonical `npm run db:types` for PR #242. PR description + amendment commit `89aed393` document the choice.
- **Cross-ref:** PR #242 amendment, package.json:31 (db:types script), WATCH-205.D (related graphql_public discovery).

### 125. WATCH-205.G — ADR `Migrations` field uses absolute `file:///` paths that break GitHub rendering
- **Tipo:** docs convention · **Severity:** LOW · **Effort:** S (sed sweep across ADRs with absolute paths)
- **Trigger:** code-reviewer PR #242 LOW finding — ADR-0095 Migrations field at line 8 uses `file:///home/vitormrodovalho/projects/ai-pm-research-hub/supabase/migrations/...` absolute paths. PR #242 extended the list to 5 entries, perpetuating the pattern. Renders as broken links on GitHub and any non-local viewer.
- **Description:** Project-wide sweep needed to replace with relative paths (`../../supabase/migrations/...`) or bare filenames. ADR-0095 is the immediate offender; other ADRs may have similar pattern.
- **Cross-ref:** ADR-0095 line 8, PR #242 amendment context.

### 126. GAP-205.D — MCP write surface incomplete: no `member_remove_alternate_email` / `member_set_primary_email` / `member_update_alternate_email` RPCs
- **Tipo:** missing CRUD surface · **Severity:** MED · **Effort:** M (1 migration + 3 MCP tools + tests, ~2-3h)
- **Trigger:** mid-session smoke discovery — PM ran `member_add_alternate_email` via MCP host with kind=personal (intent was institutional). No update RPC exists to correct kind without direct SQL bypass. Same gap for removal + primary promotion.
- **Description:** ADR-0095 §5 shipped 3 tools (resolve / list / add). Mutation paths missing for: (a) removing an alternate email, (b) promoting an alternate to primary (with cascade trigger to demote current primary + sync members.email), (c) correcting kind on an existing alternate. Direct SQL is the only current path, which is LGPD-sensitive (admin bypass of RLS not auditable via MCP usage log). Pairs with ADR-0095 §5 surface gap.
- **When to ship:** Backlog. Recommended next time a user-correction case surfaces (e.g., institutional kind correction, mistyped alternate to remove). Mid-priority — not blocking #205 closure but quality-of-life gap.
- **Cross-ref:** ADR-0095 §5, PR #242 smoke session, Issue #205.

### 127. OPP-215.A — Forward-defense test pattern (column absence via static migration analysis) as project convention
- **Tipo:** test pattern / convention · **Severity:** LOW · **Effort:** S (documentation only — convention establishment)
- **Trigger:** PR #242 amendment commit `89aed393` added 2 forward-defense assertions (#12 + #13 in `member-emails-rls-multi-tenant.test.mjs`) confirming `verified_at` is absent from all migration files touching member_emails + from the RPC return TABLE.
- **Description:** Pattern is novel in the test suite — asserts a column does NOT exist in canonical migration text. Lightweight regression guard against accidental re-add of YAGNI-removed columns. No DB access required (pure static analysis). Propose as project convention for future column removals — every DROP COLUMN migration ships with paired "absence assertion" test.
- **When to ship:** Backlog. Doc-only; codify in `.claude/rules/database.md` or new ADR amendment if next column drop occurs.
- **Cross-ref:** PR #242 commit 89aed393, tests/contracts/member-emails-rls-multi-tenant.test.mjs assertions #12-#13, ADR-0012.

### 128. RESOLVED-205.D — `member_emails` write surface complete (remove + set_primary + update_kind) — Issue #205 fully closed (PR #244, p216)
- **Tipo:** missing CRUD surface / closure · **Severity:** MED (closed) · **Effort:** M (~3h, completed)
- **Trigger:** P162 #126 GAP-205.D filed at p215 close. PM ABCD pick at p216 boot: "GAP-205.D (Recommended)" → end-to-end implementation chosen over deferral.
- **Description:** Issue #205 final closure via 4-PR sequence: PR #240 core (p213) + PR #241 GAP-A/B (p214) + PR #242 GAP-C (p215) + PR #244 GAP-D (p216, this session). Migration 20260802000013 ships 3 SECDEF VOLATILE RPCs following the existing self-OR-`manage_member` auth pattern from `member_add_alternate_email`: (a) `member_remove_alternate_email(uuid, text) → boolean` — rejects primary (caller must demote via set_primary first); (b) `member_set_primary_email(uuid, text) → boolean` — routes via `UPDATE public.members SET email` to fire `sync_member_email_trigger_fn`, preserving alt kind via ON CONFLICT DO UPDATE; idempotent on already-primary; raises if email not registered for member; (c) `member_update_alternate_email_kind(uuid, text, text) → boolean` — rejects primary mutation (primary kind follows backfill convention). Migration 20260802000014 applies Council Tier 1 amendments (HIGH LGPD + MED concurrency + MED org boundary + LOW msg) via CREATE OR REPLACE FUNCTION. MCP surface 296 → 299 tools + version 2.77.0 → 2.78.0 + /health label updated. Test baseline 1558 → 1587 (+29 assertions across original write surface + council amendments). Council Tier 1 paralelo: platform-guardian GO-WITH-AMENDMENTS (1 MED 2 LOW) + code-reviewer APPROVE-WITH-AMENDMENTS (1 HIGH 2 MED 2 LOW). All HIGH/MED resolved inline pre-merge; 2 LOWs deferred to WATCH-216.C/D.
- **Smoke:** 11 (initial via DO block) + 9 (amendments via DO block) = 20/20 PASS; 0 leak; invariants 19/19=0 unchanged; MCP tools/list = 299 live; serverInfo.version = 2.78.0 live.
- **PM ABCD design call:** set_primary routes through `UPDATE members.email` (Option A Recommended) — single source of truth, reuses cross-member theft guard from mig 20260802000009.
- **Cross-ref:** P162 #126 (the open entry this resolves), Issue #205 (now closed across 4 PRs), PR #244 squash `4b843779`, migrations 20260802000013 + 20260802000014, ADR-0095 (§5 + Amendment 2026-05-21 GAP-205.D + Council Tier 1 amendments subsection).

### 129. WATCH-216.A — `audit-mcp-tool-matrix.mjs` H1 was hardcoded "293-Tool" — root cause fixed; preventive sweep for other generated docs with hardcoded counts
- **Tipo:** docs drift / generated-doc sediment · **Severity:** MED (root cause fixed) · **Effort:** S (project-wide grep for hardcoded count patterns in scripts)
- **Trigger:** platform-guardian Tier 1 review on PR #244 (MED-1) — `docs/reference/MCP_TOOL_MATRIX.md` H1 read `# MCP 293-Tool Contract Matrix` while body line 7 showed `Total tools (static parser): 299`. Caused by `scripts/audit-mcp-tool-matrix.mjs:124` having a hardcoded string literal instead of a dynamic count. Same root cause as the `.claude/rules/mcp.md` pre-deploy section 4 prose drift (see #130).
- **Description:** When a generated doc's header includes the count of items it tracks, the script that generates it must interpolate the count dynamically. Hardcoded counts in generation scripts decay silently — body updates every run, header stays stale. Same drift class as WATCH-205.G (ADR absolute paths) but for generated-doc headers. Preventive sweep across `scripts/audit-*.mjs` and `scripts/regen-*.mjs` for similar hardcoded counts/totals/numbers in line-level string literals.
- **Resolution this session:** `scripts/audit-mcp-tool-matrix.mjs:124` changed to `lines.push(\`# MCP ${tools.length}-Tool Contract Matrix\`)`. Matrix regenerated → H1 now "299-Tool". Manual fix in `.claude/rules/mcp.md` (#130). Project-wide preventive sweep pending.
- **Cross-ref:** PR #244 platform-guardian MED-1, commit `1ad45506`, docs/reference/MCP_TOOL_MATRIX.md, scripts/audit-mcp-tool-matrix.mjs:124.

### 130. WATCH-216.B — `.claude/rules/mcp.md` pre-deploy section 4 prose had same hardcoded "293-tool contract matrix" count (consolidates with #129)
- **Tipo:** docs drift · **Severity:** LOW (manual fix applied) · **Effort:** XS (resolved this session)
- **Trigger:** Same platform-guardian Tier 1 review (MED-1, consolidated finding) — `.claude/rules/mcp.md` line 53 read "The MCP 293-tool contract matrix is generated by..." while live count was 299.
- **Description:** Same root cause as #129 (hardcoded count in human-maintained doc that should track an auto-counted reality). Manual fix in this session drops the hardcoded count and points at WATCH-216.A as the long-term pattern. Future docs that reference a count should either (a) be auto-generated, or (b) reference the live source ("see `scripts/audit-mcp-tool-matrix.mjs` output for current count") rather than embedding a number.
- **Resolution this session:** `.claude/rules/mcp.md:53` prose updated to drop the count + reference WATCH-216.A.
- **Cross-ref:** WATCH-216.A (parent), PR #244 commit `1ad45506`, .claude/rules/mcp.md:53.

### 131. WATCH-216.C — `test:contracts` npm script lacks `--experimental-strip-types` flag — inconsistent with `test` script
- **Tipo:** test config inconsistency · **Severity:** LOW · **Effort:** XS (one-line edit when next contract test adds TS syntax)
- **Trigger:** platform-guardian Tier 1 review on PR #244 (LOW-2) — `test` script in `package.json:14` uses `node --experimental-strip-types --test ...`; `test:contracts` script in `package.json:16` uses `node --test ...` without the flag. No current failure because all contract files are `.mjs` (no TypeScript syntax).
- **Description:** Asymmetric. If a future contract test ships with a `.ts` extension or adds `.mjs` TS-style type annotations + is added only to `test:contracts` (without `npm test` cross-check), it would silently fail to parse. Either both scripts should have the flag, or the convention should be `.mjs` only for contracts (and enforced by a contract test). Pre-existing inconsistency this PR did not introduce — flagged for backlog.
- **When to ship:** When next contract test adds TS syntax OR project-wide normalization pass.
- **Cross-ref:** PR #244 platform-guardian LOW-2, package.json:14 + :16.

### 132. WATCH-216.D — Test body-block regex `([\\s\\S]+?)\\$\\$;` could terminate early on nested `$$` literals
- **Tipo:** test regex robustness · **Severity:** LOW · **Effort:** S (project-wide sweep for body-extraction regexes; standardize on the shared parser at `tests/helpers/rpc-body-drift-parser.mjs:43` if applicable)
- **Trigger:** code-reviewer Tier 1 review on PR #244 (LOW #2) — `tests/contracts/member-emails-write-surface.test.mjs` uses non-greedy `([\\s\\S]+?)\\$\\$;` to extract function bodies between `CREATE FUNCTION public.<name>(` and the closing `$$;`. If a function body contained a nested `$$` literal (different tag style, e.g., `$tag$...$tag$` or just a string with `$$` in it), the regex would terminate at the first `$$;` encountered, yielding a truncated body and silently passing assertions on partial text.
- **Description:** No nested `$$` in this PR's migration files (all bodies use single `$$` quoting), so no current risk. But the pattern would silently degrade on future migrations that use alternative dollar-tag styles. Either (a) anchor the regex on `$$;\\s*(?:GRANT|COMMENT|DROP|NOTIFY|END\\s*$)` for stronger termination, or (b) use the shared parser at `tests/helpers/rpc-body-drift-parser.mjs:43` which is already pattern-agnostic for dollar-tags. Backlog: project-wide sweep across `tests/contracts/*.test.mjs` for body-extraction regexes.
- **Cross-ref:** PR #244 code-reviewer LOW #2, tests/contracts/member-emails-write-surface.test.mjs body-extractor blocks, tests/helpers/rpc-body-drift-parser.mjs:43.

### 133. DECISION-160 — Path A' picked: catalog reconciliation for ambassador + R3-C3 batch only for the real 4 (Issue #160, p217, 2026-05-21)
- **Tipo:** decision log · **Severity:** N/A · **Effort:** XS (decision capture)
- **Trigger:** PM ABCD pick at p217 boot: chose Path A' (Recommended) over original Path A after p217 discovery surfaced catalog drift on `ambassador.requires_agreement`. Path A' = two-step: (1) catalog fix for ambassador (this session, RESOLVED-160.A); (2) R3-C3 notification batch for the 4 actually-needing-termo engagements (deferred OPP-160.B).
- **Description:** Original p202 PM guidance ("fix issuance/onboarding flow first; do not shortcut by flipping authority") framed the 16-engagement backlog as a termo-issuance gap. p217 investigation found 12 of those 16 were `ambassador` kind, which per ADR-0006 line 55 + the row's own `description` field ("Reconhecimento honorário / mérito. Sem termo obrigatório.") + `legal_basis=consent` was never supposed to require termo. The `requires_agreement=true` flag was a seed bug from V4 cutover (2026-04-13). Path A' fixes the catalog (zero V4 capability side-effects since `engagement_kind_permissions` has 0 rows for ambassador kind) and scopes the R3-C3 batch to the 4 engagements that genuinely need termo (Herlon SGO + Fernando SGP + Vitor volunteer x2 = 3 distinct members).
- **Cross-ref:** Issue #160 (parent), Issue #182 (lifecycle mapping unblocked by this decision), ADR-0006 §"Reconciliação de catálogo" 2026-05-21, P162 #134 (RESOLVED-160.A — the catalog fix), P162 #135 (OPP-160.B — the deferred R3-C3 batch).

### 134. RESOLVED-160.A — `engagement_kinds(ambassador).requires_agreement` corrigido true→false (Issue #160 path A' step 1, p217)
- **Tipo:** catalog reconciliation / drift fix · **Severity:** MED (resolved) · **Effort:** XS (~1h migration + tests + governance, completed)
- **Trigger:** P162 #133 DECISION-160. Surfaced organically during p217 investigation when verifying which engagements actually needed termo issuance.
- **Description:** Migration `20260803000001_p217_160_ambassador_catalog_fix.sql` applies `UPDATE engagement_kinds SET requires_agreement=false WHERE slug='ambassador'` with idempotent guard + in-tx sanity DO block. Smoke pre-state: `requires_agreement=TRUE`, `legal_basis=consent`, `description="Reconhecimento honorário / mérito. Sem termo obrigatório."`, `agreement_template=NULL`, `engagement_kind_permissions WHERE kind='ambassador'` = 0 rows, 12 engagements pending. Post-state: `requires_agreement=FALSE` ✓, 0 ambassador pending ✓, 12 ambassador now `is_authoritative=true` ✓, total backlog 16→4 ✓, invariants 19/19=0 unchanged ✓. Zero V4 capability side-effects (engagement_kind_permissions for ambassador has 0 rows — no actions granted by this kind regardless of authoritative status). 8 members affected via flip: Andressa Martins (PMI-GO), Antonio Marcos Costa (PMI-GO), Fabricio Costa (PMI-GO), Herlon Alves de Sousa (PMI-CE), Ivan Lourenço (PMI-GO), Roberto Macêdo (PMI-CE), Sarah Faria Alcantara Macedo Rodovalho (PMI-GO), Vitor Maia Rodovalho (PMI-GO).
- **Forward-defense:** `tests/contracts/engagement-kinds-catalog-invariants.test.mjs` (+9 assertions: 8 subtests on migration body presence/correctness + 1 invariant on no future re-flip). Test count 1587 → 1596 offline.
- **Governance:** ADR-0006 amended with §"Reconciliação de catálogo" 2026-05-21 documenting the seed bug + fix + zero-capability-impact rationale.
- **Issue #160 status:** partially closed — 8 ambassadors now authoritative (including Herlon's ambassador role); Herlon's `study_group_owner / leader` engagement remains pending termo (handed off to OPP-160.B).
- **Cross-ref:** Issue #160, Issue #182 (lifecycle mapping unblocked), ADR-0006, migration 20260803000001, test file engagement-kinds-catalog-invariants.test.mjs, P162 #133 (parent decision), P162 #135 (sibling — remaining 4-person batch).

### 135. OPP-160.B — R3-C3 Termo notification batch for the 4 remaining real-termo engagements (3 distinct members) [**DISPATCHED 2026-05-21 p217 — see #138**]
- **Tipo:** notification batch / operational follow-up · **Severity:** MED · **Effort:** S (1-2h: 4 individual notifications + 4 self-signs + 4 GP countersigns)
- **Trigger:** P162 #133 DECISION-160 path A' step 2 (originally deferred from p217 close to a dedicated session, but PM picked "OPP-160.B agora" mid-session — see #138 for dispatch record). Backlog after RESOLVED-160.A: 4 engagements / 3 distinct members.
- **Description:** Pending real-termo engagements (per `get_pending_agreement_engagements()` post p217 catalog fix):
  - Herlon Alves de Sousa (PMI-CE) — `study_group_owner / leader` for CPMAI (the original #160 case)
  - Fernando Maquiaveli (PMI-DF) — `study_group_participant / participant`
  - Vitor Maia Rodovalho (PMI-GO) — `volunteer / coordinator` + `volunteer / manager` (2 engagements)
  - All 4 covered by R3-C3 template `a78311fd-cf87-4bee-b0f1-e117a36095c5` "Termo de Voluntariado — Template Ciclo 3" (status=active).
- **Approach (recommended):** Given the small N, prefer individual notifications + existing `sign_volunteer_agreement(lang, ip, ua)` flow over building a full campaign_templates entry. Sequence per person: (1) direct notification (Slack/email) with deeplink to sign UI; (2) member self-signs; (3) GP countersigns via `counter_sign_certificate(cert_id, ip, ua)`; (4) verify `auth_engagements.is_authoritative=true` post-countersign. Vitor's 2 engagements use a single signed certificate (same person, same termo version).
- **Why deferred from p217:** PM ABCD path A' was scoped explicitly as "catalog fix + R3-C3 batch only for the real 4". Catalog fix shipped this session as RESOLVED-160.A. The notification batch is operational (1:1 ping work, no code change) and benefits from a separate dedicated session with PM in the loop.
- **When to ship:** Backlog. Open issue + assign owner. Once executed, this entry becomes RESOLVED-160.B and Issue #160 fully closes.
- **Cross-ref:** Issue #160 (parent, partially closed), Issue #182 (lifecycle mapping consumer), P162 #133 (DECISION-160), P162 #134 (RESOLVED-160.A), governance_documents.id `a78311fd-cf87-4bee-b0f1-e117a36095c5`.

### 136. WATCH-217.A — `validate_privacy_policy_consistency()` flags ambassador as error post-RESOLVED-160.A (false positive)
- **Tipo:** validation drift / docs · **Severity:** MED (alert visible) · **Effort:** S (1-2h: add `is_merit_only` boolean OR exemption list in RPC OR test assertion documenting expected false positive)
- **Trigger:** PR #250 platform-guardian MED-1 + code-reviewer corroborating note. The RPC at `migration 20260418010000` lines 268-276 raises severity=`error` for any kind where `legal_basis='consent' AND NOT requires_agreement`, with message "Consent-based kind does not require agreement. LGPD Art. 8 requires explicit consent documentation." Post-RESOLVED-160.A, ambassador (legal_basis=consent, requires_agreement=false) trips this branch.
- **Description:** The RPC was written under the assumption that any kind with `legal_basis='consent'` corresponds to LGPD Art. 7 I (data processing consent requiring written documentation per Art. 8). Ambassador uses "consent" in the colloquial sense — member accepts a merit recognition (no written instrument required). ADR-0008 line 25 is the canonical source: ambassador = "Nomeação → Sem termo → Indefinido (revogável) → Delete on request | Consent". The RPC is currently dormant (not in MCP, not called from any page or test, only in `database.gen.ts` type gen), so no live breakage. Risk: a future session runs the RPC as a health check, sees the "error", and reverts the catalog fix to clear the alert.
- **Mitigations applied this session:**
  - Migration `20260803000001` header explicitly documents the false positive + warning to future maintainers.
  - ADR-0006 §"Reconciliação de catálogo" 2026-05-21 documents the false positive + cross-refs this WATCH entry.
- **Recommended long-term fix (choose one):**
  - (A) Add `is_merit_only boolean` column to `engagement_kinds` + skip the consent check when true.
  - (B) Add an explicit exemption list `kinds_consent_without_agreement = ARRAY['ambassador', ...]` inside the RPC.
  - (C) Refactor the RPC to distinguish LGPD Art. 7 I consent from merit-recognition consent — possibly by reading `description` for "honorário/mérito" markers (brittle).
- **When to ship:** Backlog. Mid-priority — no live breakage today, but addressing it removes a foot-gun that could undo a deliberate architectural decision.
- **Cross-ref:** PR #250 platform-guardian MED-1, migration 20260418010000:268-276, ADR-0006 §"Reconciliação de catálogo" 2026-05-21, RESOLVED-160.A (#134).

### 137. WATCH-217.B — `engagement-kinds-catalog-invariants.test.mjs` future-pattern coverage extension (resolved inline for ON CONFLICT + VALUES-tuple; MERGE pending)
- **Tipo:** test robustness · **Severity:** LOW (resolved 2 of 3 cases inline) · **Effort:** XS (MERGE pattern when first MERGE migration ships)
- **Trigger:** PR #250 platform-guardian LOW-1 (multi-row INSERT false positive) + code-reviewer LOW (ON CONFLICT DO UPDATE bypass; MERGE bypass).
- **Description:** The original `insertReflipPattern` used `[\s\S]*?` lazy matching across an entire INSERT statement, which:
  - **Multi-row false positive:** `INSERT INTO engagement_kinds VALUES ('ambassador', false), ('sponsor', true)` would match (ambassador followed by true somewhere downstream).
  - **ON CONFLICT bypass:** `INSERT ... ON CONFLICT (slug) DO UPDATE SET requires_agreement=true` matches neither the UPDATE pattern (no WHERE) nor the original INSERT pattern.
  - **MERGE bypass (theoretical):** Postgres 15+ MERGE statements not covered.
- **Mitigations applied this session (PR #250 amendments commit):**
  - Replaced `insertReflipPattern` with VALUES-tuple-scoped `/VALUES\s*\([^)]*'ambassador'[^)]*,\s*true[^)]*\)/i` (no multi-row false positive).
  - Added `onConflictReflipPattern` for the upsert bypass case.
  - Inline comment noting the MERGE gap + codebase status (zero MERGE usage today).
- **Backlog item:** Add MERGE coverage when the first migration adopts MERGE patterns. Until then, accepted gap.
- **Cross-ref:** PR #250 platform-guardian LOW-1, code-reviewer LOW (table row 2-3), tests/contracts/engagement-kinds-catalog-invariants.test.mjs line 105-117.

### 138. DISPATCH-160.B — Notification batch sent for OPP-160.B (3 notifications, 3 members, transactional_immediate)
- **Tipo:** notification dispatch / operational milestone · **Severity:** N/A (action record) · **Effort:** XS (~15min — completed)
- **Trigger:** PM ABCD pick mid-p217 session "OPP-160.B agora — batch R3-C3 para os 4 (Recommended)" after PR #250 merge. Replaces the originally-deferred timing in #135.
- **Description:** 3 rows inserted into `public.notifications` table 2026-05-21 23:43 UTC with type=`engagement_termo_due`, link=`/volunteer-agreement`, delivery_mode=`transactional_immediate`, actor_id=Vitor Maia Rodovalho (PM-initiated dispatch):
  - **Herlon Alves de Sousa** (`c8e76355-...`) — notification id `8bc80cec-b808-4408-a60d-f51132ef7b65` — body references CPMAI study_group_owner role
  - **Fernando Maquiaveli** (`c8b930c3-...`) — notification id `166280fa-a30a-43f9-a4cf-ccd885eb9873` — body references CPMAI study_group_participant role
  - **Vitor Maia Rodovalho** (`880f736c-...`) — notification id `7da2bf52-e109-4fdc-bcd8-cb15c7e9aa4c` — body references both volunteer engagements (LATAM LIM 2026 + CPMAI) + notes single signature covers both
- **Pre-dispatch idempotency:** confirmed 0 prior `engagement_termo_due` notifications in last 30 days for these 3 recipients (no duplicate spam).
- **Body strategy:** per-member contextualized body (mentions specific initiative + role) rather than generic template — keeps message actionable for N=3 without building a full `campaign_templates` row (overkill per PM's path A' framing).
- **Email delivery:** `transactional_immediate` mode triggers the platform's outbound email pipeline (Resend integration). `email_sent_at` will populate when the cron/EF processes the queue. Manual verification possible via `SELECT email_sent_at FROM notifications WHERE id IN (...)` in 5-10 minutes.
- **Expected next flow (per ADR-0039 volunteer agreement countersign subsystem):**
  1. Recipient clicks notification link → `/volunteer-agreement` UI
  2. Recipient reviews termo + clicks "Sign" → triggers `sign_volunteer_agreement(language, ip, ua)` RPC
  3. RPC creates a `certificates` row + sets `engagements.agreement_certificate_id`
  4. GP (PM) sees pending countersign via `get_pending_countersign()` → calls `counter_sign_certificate(cert_id, ip, ua)`
  5. `auth_engagements.is_authoritative` flips to `true` for that engagement
  6. When all 4 engagements have signed+countersigned certs, OPP-160.B becomes RESOLVED-160.B and Issue #160 fully closes.
- **Note on Vitor self-cert:** As member + PM (GP) of the platform, Vitor signs his own termo via member flow, then countersigns via GP flow. Whether the system permits self-countersign depends on ADR-0039 countersign chain rules — not investigated this session (PM territory, low-impact if requires another GP).
- **Cross-ref:** Issue #160, OPP-160.B (#135 — original entry, marked DISPATCHED), DECISION-160 (#133), RESOLVED-160.A (#134), `public.notifications` rows 8bc80cec / 166280fa / 7da2bf52, governance_documents.id `a78311fd-cf87-4bee-b0f1-e117a36095c5` (R3-C3 template).

