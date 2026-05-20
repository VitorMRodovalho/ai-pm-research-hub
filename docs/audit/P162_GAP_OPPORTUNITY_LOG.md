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
- **Proposta:** Introduce a canonical approval RPC (`approve_selection_application` or equivalent) and move UI/MCP/bulk actions to it. Deprecate or wrap `admin_update_application` and `finalize_decisions` so there is one source of truth.
- **Validation gate:** Contract test for "candidate approved from UI" must assert `selection_applications`, `members`, `persons`, `engagements`, onboarding and notification effects.
- **Cross-ref:** GitHub #179; `docs/audit/P201_MCP_ARCHITECTURE_AUDIT.md` section 6; `tests/contracts/selection-interview-decision.test.mjs`.

### 49. P0 — Approved members can remain outside authoritative V4 graph
- **Tipo:** gap · **Severity:** CRITICAL · **Effort:** M/L
- **Trigger:** Lifecycle audit found approval paths that do not guarantee `members.person_id` and do not provision `engagements` linked to `selection_application_id`.
- **Impact:** A member may look approved or active through legacy/cache fields while `can()` / `can_by_member()` returns no operational capability. Herlon is the visible instance of the broader pending-authority class, but this also affects future approvals and re-engagements.
- **Proposta:** Add an invariant/backfill strategy for approved/converted applicants: ensure `person_id`, create scoped engagement from template, link `engagements.selection_application_id`, and surface explicit waivers where an engagement is intentionally non-authoritative.
- **Validation gate:** Extend schema invariants or add DB-aware contract tests for approved applications without `person_id` / engagement.
- **Cross-ref:** GitHub #180; ADR-0007, ADR-0011, p170 VEP engagement linkage, item #44.

### 50. P0 — `counter_signature_hash` is computed but not persisted
- **Tipo:** security/auditability issue · **Severity:** CRITICAL for formal non-repudiation · **Effort:** S/M
- **Trigger:** Certificate governance audit found `counter_sign_certificate()` computes a counter-signature hash but returns it to the caller without writing it to the certificate row.
- **Impact:** The platform records who countersigned and when, but the cryptographic proof of the counter-signature is not persisted. Operational audit remains usable; formal non-repudiation claims should remain conditional until fixed.
- **Proposta:** Add/persist `counter_signature_hash` (or use existing column if present but unwritten), update `counter_sign_certificate()`, add audit log assertion and regression test.
- **Validation gate:** Counter-sign a certificate in test and assert persisted hash, audit log row, notification, and unchanged member-facing certificate payload.
- **Cross-ref:** GitHub #181; `docs/project-governance/P202_AGREEMENT_ISSUANCE_GAP.md`, certificates RPC cluster.

### 51. P1 — Volunteer agreement evidence fields are incomplete
- **Tipo:** compliance gap · **Severity:** HIGH · **Effort:** M
- **Trigger:** Certificate governance audit found `signed_ip` and `signed_user_agent` columns exist but are not populated by the Termo flow; `period_end` is hardcoded to 30-Jun, which breaks terms signed after July.
- **Impact:** Evidence package for signature context is weaker than the schema suggests, and term validity periods can be wrong for later-cycle signatures or off-cycle engagements.
- **Proposta:** Capture IP/user-agent through a safe server-side path, derive `period_end` from cycle/engagement/template rules, and update `get_my_signatures()` to expose a complete LGPD Art. 18-friendly view.
- **Validation gate:** New signature test must assert IP/user-agent handling, period derivation and user export payload shape.
- **Cross-ref:** GitHub #181; LGPD Art. 18 workflow, `sign_volunteer_agreement`, `get_my_signatures`.

### 52. P1 — Lifecycle cron/campaign coverage is incomplete for special kinds and renewals
- **Tipo:** gap · **Severity:** HIGH · **Effort:** M
- **Trigger:** Crons/campaigns audit mapped existing notification routines but found no consistent automation for special engagement agreement issuance, pending-authority reminders, renewal reminders and re-engagement communication.
- **Impact:** Volunteers can be approved or assigned to leadership-like engagements without receiving the right agreement/onboarding communication. Failures appear as permission problems instead of lifecycle state problems.
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

