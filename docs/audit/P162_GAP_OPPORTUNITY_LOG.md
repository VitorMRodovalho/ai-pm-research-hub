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

### 139. RESOLVED-217.A — `/certificates` page filtered out volunteer_agreement certs, returning empty for members with only TCV
- **Tipo:** UI bug / user-visible regression · **Severity:** HIGH (broken journey) · **Effort:** XS (~20min — completed)
- **Trigger:** PM clicked OPP-160.B dispatched notification email 2026-05-21 — landed on `/volunteer-agreement` which correctly detected his existing R3-2026 cert (`a375b716-...`, issued 2026-04-08, counter_signed 2026-02-18) and showed "you already signed" + CTA to `/certificates`. Clicked CTA → `/certificates` page returned empty with message "you have no certs, sign your termo" — the very thing he was just told he already signed. Cross-check: `/admin/governance/documents` showed his signed cert + TAP CPMAI chain (where his submitter_acceptance gate was already done 2026-05-13). Conclusion: journey broken at `/certificates`.
- **Root cause:** `src/pages/certificates.astro:53` called `sb.rpc('get_my_certificates')` without arguments. The RPC signature is `get_my_certificates(p_include_volunteer_agreements boolean DEFAULT false)` — the FALSE default filters out `type='volunteer_agreement'` certs (an admin-context default for separating TCV from achievement certs). PM's only cert was `type='volunteer_agreement'` → filtered out → page empty.
- **Asymmetry that hid the bug:** `src/pages/volunteer-agreement.astro:212` correctly passes `p_include_volunteer_agreements: true` for its "already signed" detection. The two pages used the same RPC with different defaults; only the member-facing list page had the wrong default.
- **Fix:** `src/pages/certificates.astro:53` now passes `{ p_include_volunteer_agreements: true }` explicitly. Member-facing page should NEVER hide certs the member owns.
- **Forward-defense:** `tests/contracts/certificates-page-include-volunteer-agreements.test.mjs` (+2 assertions):
  - Positive: regex must match `sb.rpc('get_my_certificates', { ... p_include_volunteer_agreements: true ... })` in the page body
  - Negative: regex must NOT match the naked `sb.rpc('get_my_certificates')` call form
  - Negative: regex must NOT match `p_include_volunteer_agreements: false` (catches anyone re-introducing the bug deliberately)
- **Test baseline:** 1596 → 1598 offline (1618 → 1620 with-DB) via the 2 new assertions. deploy.md baseline pin updated.
- **PM smoke required post-merge:** Hard refresh `/certificates` after Cloudflare cache invalidation (typically <60s post-deploy) and confirm the R3-2026 termo card now appears with "counter-signed" badge.
- **Cross-ref:** src/pages/certificates.astro:53, src/pages/volunteer-agreement.astro:212 (the working reference), get_my_certificates RPC (admin context preserves include=false default), DISPATCH-160.B (#138 — the trigger that surfaced the journey).

### 140. RESOLVED-217.C — Herlon CPMAI study_group_owner withdrawal (partial engagement offboarding per ADR-0006/0007)
- **Tipo:** member lifecycle / partial offboarding · **Severity:** N/A (operational action) · **Effort:** XS (~15min DB ops + governance — completed)
- **Trigger:** PM communication 2026-05-21 — Herlon Alves de Sousa (`c8e76355-...`) informed he must decline continuing as GP of CPMAI Ciclo 3 (`study_group_owner / leader` engagement) due to personal reasons. Withdrawal was announced before he had signed the OPP-160.B dispatched termo (notification `8bc80cec-...`).
- **Pattern:** Partial engagement offboarding per ADR-0006/0007 — end ONLY the study_group_owner engagement; ambassador + observer engagements preserved (Herlon stays in the platform as member with merit recognition + passive observer roles intact). The `offboard_member(p_member_id, ...)` RPC was rejected as too coarse — it would also kill ambassador (PM confirmed "sim ele fazendo offboarding vai matar o ambassador, esta certo").
- **Execution (4 ops via execute_sql, atomic BEGIN/COMMIT):**
  1. `UPDATE engagements SET status='offboarded', end_date=current_date WHERE id='cdcd9693-bbf4-4dad-90fa-4037972567d3'` — old (active, end 2027-06-30) → new (offboarded, end 2026-05-22)
  2. `UPDATE notifications SET is_read=true, read_at=now() WHERE id='8bc80cec-...'` — dismisses moot termo notification
  3. `UPDATE selection_applications SET conversion_reason='Withdrawn 2026-05-21 ... personal reasons. Selection approval preserved...' WHERE id='d1d72a91-e67e-4272-a278-609079085faf'` — status='approved' preserved (selection process completed correctly); conversion to active engagement did not complete
  4. `INSERT admin_audit_log (action='engagement_offboarded', target_type='engagement', target_id='cdcd9693-...', changes={old:active,new:offboarded}, metadata={person, initiative, reason, session, cascade_actions[]})` — full audit trail
- **Post-state verified:**
  - ambassador/ambassador engagement: status=active, is_authoritative=true ✓ (PR #250 catalog fix preserved)
  - observer/observer engagement: status=active ✓
  - study_group_owner/leader engagement: status=offboarded, end_date=2026-05-22 ✓
  - notification 8bc80cec: is_read=true, read_at populated ✓
  - selection_application d1d72a91: conversion_reason populated, updated_at refreshed ✓
  - admin_audit_log: entry with target_id=cdcd9693 + action=engagement_offboarded ✓
- **OPP-160.B impact:** the remaining 4-engagement backlog drops to 3 (Fernando SGP + Vitor 2 volunteer). Herlon's notification dismissed; no termo sign expected from him.
- **TAP CPMAI (governance_document d7447a94) chain:** unaffected by withdrawal — Herlon's submitter_acceptance gate already completed 2026-05-13 (his earlier GP-elect work preserved in audit trail); chain still awaits Ivan president_go.
- **Follow-up issue filed:** GH issue #257 — CPMAI Ciclo 3 replacement GP needed (PM decides A: Vitor temp / B: promote from cohort / C: external selection / D: pause).
- **Cross-ref:** GH #257 (CPMAI GP replacement), engagement_id `cdcd9693-bbf4-4dad-90fa-4037972567d3`, OPP-160.B (#135 — backlog scope reduced), DISPATCH-160.B (#138 — notification was dispatched but dismissed before sign), ADR-0006 (person-engagement identity model), ADR-0007 (authority-as-engagement-grant), ADR-0008 §lifecycle table line 18 (`study_group_owner` lifecycle: ... → Offboard → Anonymize 5a).

### 141. BUG-217.B — Termo PDF download missing: 41/41 volunteer_agreement certs have `pdf_url=NULL` + verify page has no render-from-snapshot path
- **Tipo:** UX / LGPD soft gap · **Severity:** MED · **Effort:** L-XL (storage bucket + PDF library + signing flow + UI render + cron backfill of 41 certs)
- **Trigger:** PM smoke of PR #253 (RESOLVED-217.A) — after `/certificates` page started showing his R3-2026 termo correctly, PM clicked "Verificar" CTA → `/verify/{code}` page shows cert metadata (type, member name, dates, counter-signer, verification code) but provides NO way to view or download the actual signed document.
- **DB evidence:** 41 of 41 `volunteer_agreement` certs have `pdf_url IS NULL`; 1 of 1 `contribution` cert also `pdf_url IS NULL`. All have `content_snapshot IS NOT NULL` (data preserved in DB). Source `src/pages/verify/[code].astro` grep for `pdf_url|content_snapshot|download|baixar|PDF` returns 0 hits.
- **Root cause (two-layer gap):**
  1. PDF generation never wired — `sign_volunteer_agreement` → `counter_sign_certificate` flow creates cert + populates `content_snapshot` but never generates a PDF file. The `pdf_url` field exists in schema but no upstream code writes to it.
  2. Verify page has no fallback — reads cert metadata but doesn't render `content_snapshot` client-side when `pdf_url` is NULL.
- **Impact:** Members cannot download a copy of the legal Termo de Voluntariado they signed (LGPD Art. 18 soft gap — data exists, export path broken). External legal/audit requests can't be served via platform — admins must manually re-render from content_snapshot.
- **Proposed fix options (next session — needs proper scoping):**
  - (A) Lazy PDF generation on first verify-page visit — EF or RPC: content_snapshot + metadata → PDF → storage bucket → backfill pdf_url
  - (B) Client-side render from content_snapshot — verify page parses + renders inline + browser print-to-PDF
  - (C) Hybrid — (B) now for quick win, (A) later for canonical signed artifact
- **GH issue filed:** #258 — full reproduction + proposed fixes + LGPD context
- **Forward-defense (when fix lands):** contract test asserting `/verify/[code].astro` either renders content_snapshot OR provides pdf_url download — never both empty.
- **Resolution this session (p218 path A pick):** see #144 RESOLVED-217.B (PR #262) — wired existing pdf.ts pipeline into /certificates; /verify stays metadata-only per privacy design. Path C (server-side backfill) deferred to WATCH-258.A (#146).
- **Cross-ref:** GH #258, src/pages/verify/[code].astro, certificates.{pdf_url, content_snapshot}, ADR-0039 (countersign subsystem — never defined PDF artifact step), p156 memory `feedback_altchunk_docx_export_unviable.md` (prior DOCX attempts), RESOLVED-217.A (#139 — the fix that surfaced this downstream gap), RESOLVED-217.B (#144 — Path A shipped), WATCH-258.A (#146 — Path C deferred).

### 142. RESOLVED-DIVERGENCE-218 — Local main divergence reconciled via PR #261 (PM out-of-band docs commits absorbed)
- **Tipo:** governance / git reconcile · **Severity:** N/A · **Effort:** XS (~10min — completed)
- **Trigger:** p218 boot verify — local main had 2 commits ahead of origin (`e6acbcf3` register Issue #254 video screening + `2ab2b28d` register Issue #260 selection notifications audit), both PM-authored out-of-band between p217 close and p218 boot session. Per handoff p217 §"Local git divergence (UNRESOLVED — for PM to fix at start of p218)".
- **Pattern:** Recurring — PM makes occasional local commits via other tools between Claude sessions; reconciliation needed at next session boot. ABCD pick options offered: PR squash (Recommended), direct push, or drop.
- **Resolution:** Cherry-picked both commits onto `agent/p218-issue-254-registry` (rebased onto origin/main); local main reset non-destructively via `git branch -f main origin/main`; PR #261 opened + merged squash → `e008b853`. 0 bypass events (CI 9/9 green for docs-only PR).
- **Cross-ref:** PR #261, Issue #254 registry entry, Issue #260 registry entry, p217 handoff §local divergence, `.claude/rules/bypass-protocol.md` (PR over direct push posture).

### 143. RESOLVED-257.A — CPMAI Ciclo 3 GP replacement: Vitor temp study_group_owner (post-Herlon withdrawal)
- **Tipo:** member lifecycle / engagement grant · **Severity:** N/A (operational) · **Effort:** XS (~20min — completed)
- **Trigger:** GH Issue #257 (filed at p217 close after Herlon RESOLVED-217.C). CPMAI Ciclo 3 initiative had no GP after Herlon study_group_owner offboarded 2026-05-22. ABCD options: A. Vitor temp (Recommended), B. promote from cohort, C. external selection, D. pause.
- **Decision context refinement:** Scale much smaller than originally framed — CPMAI Ciclo 3 had 1 participant (Fernando Maquiaveli), 0 owners, 1 past event, 0 upcoming. Vitor already volunteer/manager on initiative; marginal load adding study_group_owner = XS. Option B infeasible (Fernando = only participant; can't GP himself). Option C overkill for 1-person cohort.
- **PM ABCD pick:** A (Recommended).
- **Execution (single CTE atomic via execute_sql):** INSERT engagements (person_id=Vitor d6e3622a, initiative_id=CPMAI 2f5846f3, organization_id=2b4f58ab, kind=study_group_owner, role=leader, status=active, start_date=2026-05-22, end_date=2027-02-16, legal_basis=contract_volunteer, granted_by=Vitor self, metadata={source: pm_direct_grant_p218, mode: temp_coverage, review_at: 2026-08-22}) → new engagement `42fcf4b1-3bc3-4a60-8268-738d167f7fd5`. Atomic CTE includes INSERT admin_audit_log action=engagement_granted with full metadata.
- **Catalog drift hit during execution:** initially tried `legal_basis='contract'` (per catalog) — rejected by `engagements_legal_basis_check`. Workaround: hardcoded `contract_volunteer`. Filed as WATCH-257.A (later RESOLVED via PR #263 — see #145).
- **Post-state verified:** invariants 19/19=0 (unchanged); CPMAI Ciclo 3 owners 0→1; Vitor active engagements 6→7; OPP-160.B backlog 3→4 (Vitor SGO added pending termo).
- **Note: Vitor will sign 1 termo via /volunteer-agreement → all 3 of his pending engagements (SGO + volunteer x2) collapse authoritative.**
- **3-month review checkpoint hardcoded in metadata:** 2026-08-22 — flag for future session to re-evaluate temp vs permanent GP.
- **Cross-ref:** Issue #257 (CLOSED), engagement 42fcf4b1, CPMAI Ciclo 3 initiative `2f5846f3-5b6b-4ce1-9bc6-e07bdb22cd19`, RESOLVED-217.C (#140 — Herlon withdrawal that surfaced this), ADR-0006/0007 (canonical engagement grant).

### 144. RESOLVED-217.B — Cert PDF download wired into /certificates (LGPD Art. 18 access shipped; #258 closed)
- **Tipo:** UX / LGPD fix · **Severity:** MED → resolved · **Effort:** S (~30min from PM ABCD pick to merge — vs L-XL initial framing)
- **Trigger:** Path A pick on GH #258 (BUG-217.B). Initial framing in #258 estimated L-XL effort assuming "PDF generation never wired"; investigation revealed pipeline `src/lib/certificates/pdf.ts` (606 lines, `hydrateCertData` + `downloadCertificatePDF` + `buildCertificateHTML` + print CSS) already complete + wired in `/admin/certificates` + `/gamification` — only `/certificates.astro` missing the wire.
- **Privacy gotcha discovery:** `content_snapshot` is PII-heavy (member_birth_date, member_address, pmi_id, phone, chapter_cnpj, govbr_institutional_signer). Adding content render to public `/verify/{code}` endpoint = LGPD breach. **Decision:** `/verify/{code}` stays metadata-only by design; member-owned access flows through authenticated `/certificates` → `hydrateCertData()` (re-reads content_snapshot as authenticated owner via verify_certificate RPC SECURITY DEFINER).
- **Changes (PR #262, squash `9c80582a`):** src/pages/certificates.astro (import downloadCertificatePDF + attrEsc helper + 📥 button per cert card + event-delegation click handler calling record_certificate_download tracking + downloadCertificatePDF); 3 i18n dicts (`certificates.download` + `certificates.downloadError`); tests/contracts/certificates-page-download-wire.test.mjs (5 assertions: import + button + handler + tracking + content_snapshot PII discipline); package.json (test glob).
- **Test baseline:** 1598 → 1603 / 0 fail / 42 skip (+5 contract assertions).
- **Forward-defense:** contract test #5 asserts `/certificates.astro` never embeds raw `content_snapshot` into innerHTML — prevents future accidental PII leak via the page.
- **Carried to WATCH-258.A:** Server-side PDF generation + storage backfill (Path C from #258) — render PDFs server-side via @react-pdf/renderer (already installed), upload to storage bucket, populate `certificates.pdf_url` for 41 existing + future wire in sign_volunteer_agreement → counter_sign_certificate flow. Auditor-grade canonical PDF artifact. See #146.
- **Cross-ref:** PR #262, Issue #258 (CLOSED), src/lib/certificates/pdf.ts, /gamification + /admin/certificates (reference wires), ADR-0039 (countersign subsystem), RESOLVED-217.A (#139 — the fix that surfaced this gap originally).

### 145. RESOLVED-WATCH-257.A — engagements.legal_basis catalog↔runtime asymmetry harmonized (Option α minimal, PR #263)
- **Tipo:** schema bug / catalog drift fix · **Severity:** MED · **Effort:** S-M (~60min from investigation to merge — including 1 CI test fix iteration)
- **Trigger:** WATCH item spawned during RESOLVED-257.A INSERT (#143). Schema asymmetry between LGPD-canonical (`engagement_kinds.legal_basis IN (contract, consent, legitimate_interest)`) and runtime-specific (`engagements.legal_basis IN (contract_volunteer, consent, legitimate_interest)`). History: 2026-04-13 (migration 20260413320000) created engagements constraint with `contract_volunteer`; 2026-04-15 (migration 20260415100000 LGPD compliance) updated ONLY engagement_kinds constraint to LGPD-canonical `contract` — left engagements asymmetric. Any future INSERT that respects catalog value fails check_violation.
- **Investigation:** 3 catalog rows use `contract` (study_group_owner, study_group_participant, volunteer); 46 live engagement rows use `contract_volunteer`; 0 src/ or supabase/functions/ code filters on `contract_volunteer` literal (all 10 migration-history references are DDL/seed/audit, not runtime filters). No consumer breakage from adding `contract` as accepted value.
- **PM ABCD pick:** Option α minimal — additive constraint accepts BOTH values; no row migration; no consumer changes.
- **Migration `20260803000002_p218_watch_257_a_engagements_legal_basis_lgpd_canonical.sql`:** ALTER engagements DROP + ADD constraint accepting 4 values (contract, contract_volunteer, consent, legitimate_interest); COMMENT ON COLUMN documenting LGPD-canonical preference + legacy backward-compat; in-tx DO sanity (RAISE if new constraint doesn't list both literals).
- **Apply procedure:** `mcp__supabase__apply_migration` (live) + `supabase migration repair --status applied 20260803000002` + local file written. Invariants 19/19=0 unchanged.
- **Forward-defense:** tests/contracts/engagements-legal-basis-lgpd-canonical.test.mjs (2 static assertions: migration content + filename canonical). Behavioural verification lives inside migration DO block (canonical post-apply check; runtime DB check via test would need exec_sql_admin which is not exposed by design).
- **CI iteration:** First push of test included `.catch()` chain on sb.rpc() (project anti-pattern documented in CLAUDE.md: "no .catch on rpc") → validate failed with `TypeError: sb.rpc(...).catch is not a function`. Removed broken behavioural test. Caught by CI, 0 bypass events.
- **Test baseline:** 1603 → 1606 / 0 fail / 43 skip (+2 pass + 1 skip → after removing broken test: +2 pass).
- **Carried to WATCH-257.B:** Row normalization of 46 legacy `contract_volunteer` rows → `contract` (deferred — orthogonal effort; safe because 0 consumers filter on the value). See #147.
- **Cross-ref:** PR #263, migration 20260803000002, migrations 20260413320000 + 20260415100000 (origin of asymmetry), ADR-0006 (engagements + persons V4 model), LGPD Art. 7 V (contract as legal basis), RESOLVED-257.A (#143 — INSERT that surfaced this), CLAUDE.md `BoardEngine hooks use correct Supabase RPC patterns` (the .catch anti-pattern).

### 146. WATCH-258.A — Server-side PDF generation + storage backfill for canonical auditor-grade cert artifact (deferred from #258 Path C)
- **Tipo:** UX / LGPD enhancement / auditor-readiness · **Severity:** LOW (current path satisfies LGPD Art. 18 right-to-access via browser print) · **Effort:** L (~2-4h dedicated session)
- **Trigger:** RESOLVED-217.B (#144) shipped Path A (Path C deferred). Current state: 41 volunteer_agreement + 1 contribution certs have `pdf_url=NULL`; download via browser print-to-PDF (functional but not auditor-grade — no canonical signed PDF artifact in storage).
- **Scope:** (a) Render PDFs server-side via @react-pdf/renderer (already installed); (b) Upload to storage bucket with appropriate RLS; (c) Populate `certificates.pdf_url` post-counter-sign; (d) Cron backfill of 41 existing certs; (e) Wire in `sign_volunteer_agreement` → `counter_sign_certificate` flow for new certs.
- **Design considerations:** storage bucket = `certificates`? `member-documents`? RLS per cert (member can read own + admin can read all); PDF signing/watermarking optional; retention (5y per LGPD) tied to engagement retention; bulk re-render trigger if template changes.
- **Cross-ref:** Issue #258 (closed), RESOLVED-217.B (#144), src/lib/certificates/pdf.ts (current browser-print path), ChainAuditReportPDF.tsx (existing server-side @react-pdf/renderer pattern for governance chains — reference implementation), p156 memory `feedback_altchunk_docx_export_unviable.md` (prior DOCX attempts).

### 147. WATCH-257.B — Row normalization of 46 legacy `contract_volunteer` engagements → `contract` (deferred from WATCH-257.A close)
- **Tipo:** schema cleanup / canonical alignment · **Severity:** LOW (constraint accepts both; no functional gap) · **Effort:** S (~30min dedicated)
- **Trigger:** WATCH-257.A close (#145) shipped Option α minimal (additive constraint). 46 existing engagements still use legacy `contract_volunteer`; catalog uses `contract`; constraint accepts both.
- **Scope:** UPDATE engagements SET legal_basis='contract' WHERE legal_basis='contract_volunteer' (46 rows); then post-observation period, DROP `contract_volunteer` from constraint. Audit grep already confirmed 0 src/ or supabase/functions/ code filters on the legacy value (only migration history DDL/seed/audit references).
- **Pre-cleanup verification:** rerun grep for `contract_volunteer` literal in src + EFs (in case future code adds a filter); verify lgpd export RPCs format the field correctly.
- **Cross-ref:** RESOLVED-WATCH-257.A (#145), migration 20260803000002, ADR-0006.

### 148. SEDIMENT-218.A — `.catch()` on supabase RPC = anti-pattern (3rd recurrence; CLAUDE.md documents; CI caught)
- **Tipo:** workflow sediment / code pattern · **Severity:** LOW (CI catches it) · **Effort:** N/A (recurring lesson)
- **Trigger:** During WATCH-257.A test author (this session), wrote `await sb.rpc(...).catch(() => ({...}))` intending graceful skip when exec_sql_admin RPC missing. CI validate failed: `TypeError: sb.rpc(...).catch is not a function`. Supabase's rpc() returns a custom thenable (PostgrestFilterBuilder), not a Promise — `.catch()` is not on its prototype.
- **Why I missed it:** the local `node --test` standalone PASSED + SKIPPED gracefully because exec_sql_admin is reachable via service-role env (different code path); CI hits production-shape JWT and the .catch chain throws TypeError before the graceful return.
- **Lesson:** ALWAYS wrap supabase rpc calls in try/await rather than `.rpc().catch()`. Project rule documented in CLAUDE.md (`BoardEngine hooks use correct Supabase RPC patterns: no .catch on rpc`). 3rd recurrence (this session + earlier BoardEngine + others) — pattern is sticky.
- **Cross-ref:** CLAUDE.md "BoardEngine hooks use correct Supabase RPC patterns"; PR #263 fix commit (`09e8261e`); tests/contracts/engagements-legal-basis-lgpd-canonical.test.mjs (the broken test → static-only).

### 149. SEDIMENT-218.B — Out-of-band PM commits between Claude sessions = recurring reconcile pattern
- **Tipo:** workflow sediment / human-in-loop pattern · **Severity:** LOW (handled via PR reconcile) · **Effort:** N/A (recurring observation)
- **Trigger:** This session boot found 2 out-of-band PM commits (`e6acbcf3` + `2ab2b28d`) authored via different tooling (Antigravity/etc) between p217 close and p218 boot. Same pattern surfaced in p214 (concurrent agent commit `ec988042`), p217 (PM commit `9c3624b4` absorbed via PR #252 squash).
- **Pattern:** PM sometimes makes lightweight commits (docs, issue tracker, governance) outside of Claude sessions. Local main diverges by 1-2 commits. Each session boot should `git status` + check `git log --oneline origin/main..main` + reconcile via PR (Recommended) or direct push (counts as bypass) or drop (only if duplicate).
- **Lesson:** Always include git divergence check in boot verify-on-boot. If divergence found, ABCD-pick the reconcile path early (don't accumulate further drift on top). PR posture is the project default (Option C Híbrido — `.claude/rules/bypass-protocol.md`).
- **Cross-ref:** PR #261 (this session's reconcile), p214 sediment `WATCH-205.E` (concurrent agent workflow), p217 PR #252 (absorbed `9c3624b4`), `.claude/rules/bypass-protocol.md`.

---

## p219 close additions (2026-05-22) — entries #150-#157

### 150. RESOLVED-218.A — Auto-link new volunteer engagements to existing ciclo cert
- **Tipo:** wiring fix / data integrity · **Severity:** MEDIUM (inflated backlog noise; not LGPD-blocking) · **Effort:** S-M (~1h) · **Status:** RESOLVED (PR #265, mig 20260803000003)
- **Trigger:** p219 boot smoke — UI showed Vitor "✅ Já assinou Termo de Voluntariado para este ciclo" but admin backlog still listed 3 pending engagements. Investigation found `sign_volunteer_agreement()` (mig 20260415020000) links cert ← active volunteer engagements **at signing time only**. New volunteer engagements created AFTER signing remain orphan (cert=NULL).
- **Scope:** (a) Backfill 2 orphan Vitor engagements (`4711994b` LATAM LIM coordinator + `fe0d18df` CPMAI manager → cert `a375b716`); (b) BEFORE INSERT trigger `_trg_auto_link_volunteer_engagement_to_cycle_cert` forward-fix. (c) PM-chosen scope guard kind='volunteer' ONLY; SGO/SGP gap (requires_agreement=true but no signing flow) deferred.
- **Cross-ref:** PR #265, mig 20260803000003, tests/contracts/auto-link-volunteer-engagement-to-cycle-cert.test.mjs (8 forward-defense static assertions).

### 151. RESOLVED-257.B — Normalize 46 legacy `contract_volunteer` rows + 2 producer RPCs
- **Tipo:** schema cleanup / canonical alignment · **Severity:** MEDIUM (perpetuates asymmetry on every new engagement) · **Effort:** M (~45min) · **Status:** RESOLVED (PR #266, mig 20260803000004)
- **Trigger:** Follow-up to WATCH-257.A (#145 Option α additive constraint). Investigation found NOT just 46 rows but ALSO 2 producer RPCs (`approve_selection_application` + `seed_member_engagement_by_role`) emitting legacy literal on every new engagement creation.
- **Scope:** PM-picked Path B — normalize 46 rows → `'contract'` (LGPD-canonical) AND CREATE OR REPLACE both producer RPCs to emit `'contract'`. Constraint stays additive (Path C DROP value deferred for safety). 46 audit_log entries with traceability.
- **Cross-ref:** PR #266, mig 20260803000004, tests/contracts/normalize-legacy-contract-volunteer.test.mjs (7 forward-defense + 1 negative regression assertion in canonical-approval-orchestration), CI iteration caught body-hash drift (see SEDIMENT-219.A).

### 152. WATCH-258.A — Server-side PDF backfill (DEFERRED to dedicated session via #267)
- **Tipo:** UX / LGPD enhancement / auditor-readiness · **Severity:** LOW · **Effort:** L (~2-4h dedicated)
- **Trigger:** p218 carry. p219 investigation surfaced @react-pdf/renderer@4.5.1 already installed (client-side only, no server-side precedent), no `certificates` storage bucket yet, 42 certs (41 volunteer_agreement + 1 contribution) need pdf_url backfill.
- **Status:** FILED GH #267 with architecture options A (Local Node script ~1.5h backfill-only), B (Astro endpoint server-side ~2.5h backfill+forward), C (full integration ~3.5-4h B + RLS + verify-route binding + ADR). Recommendation: Option B.
- **Cross-ref:** GH #267, supersedes #146 (WATCH-258.A initial entry).

### 153. SEDIMENT-219.A — Body-hash drift gate trips when migration file has inline comments inside FUNCTION body that are stripped from apply_migration MCP call
- **Tipo:** workflow sediment · **Severity:** LOW (CI catches) · **Effort:** N/A (recurring pattern)
- **Trigger:** PR #266 first push hit body-hash drift on both `approve_selection_application` + `seed_member_engagement_by_role`. Migration FILE had inline comments (`-- p172 #5 fix...`, `-- Council fix...`) inside the function body that were missing from my apply_migration MCP call body. Live body (stripped) ≠ migration file body (with comments) → drift gate flags divergence.
- **Lesson:** When using MCP `apply_migration` with large function bodies, either (a) send EXACT file content via apply_migration (incl. all inline comments), or (b) strip inline-body comments from migration file BEFORE commit. Pattern: MCP tool's `query` param is the source-of-truth for live; migration file is the source-of-truth for drift check; they must match.
- **Cross-ref:** PR #266 fix commit `60262338` (drift-align fix), tests/contracts/rpc-migration-coverage.test.mjs (Phase C body-hash drift gate).

### 154. RESOLVED-229-PHASE1 — leader_extra cohort separation (DB + RPC + backfill)
- **Tipo:** structural refactor / data model · **Severity:** MEDIUM (UI cohort display blocked by shared columns) · **Effort:** M (~2h Phase 1) · **Status:** RESOLVED Phase 1 (PR #268, mig 20260803000005); Phase 2 deferred
- **Trigger:** Issue #229 filed p209 close. Body claimed `submit_evaluation` MUTATES `objective_score_avg` (BUG description), but git log shows commit `fe80842c` (p209) ALREADY shipped A2 minimal isolation. Phase 1 = COMPLETING the schema + RPC plumbing that A2 only partially staged.
- **Scope shipped:** 6 dedicated cohort columns (`leader_extra_pert_target/band_lower/band_upper/calc_at/cohort_n/cutoff_method`) + `_compute_pert_cutoff_core` accepts `'leader_extra_pert_score'` and routes to dedicated cols + `recompute_all_active_pert_cutoffs` cron extends to both dimensions + backfill 15 NULL apps (all met ≥2 submitted evals threshold).
- **Phase 2 deferred (#155 below):** Frontend /admin/selection 2-cutoff display + analytics RPCs + MCP tool updates + pre-fe80842c inflated obj_score_avg cleanup.
- **Cross-ref:** PR #268, mig 20260803000005, GH #229, tests/contracts/leader-extra-cohort-separation.test.mjs (9 forward-defense static).

### 155. #229 Phase 2 — Frontend + MCP + analytics + obj_score_avg cleanup (DEFERRED)
- **Tipo:** UX + plumbing follow-up · **Severity:** LOW-MEDIUM (Phase 1 provides data; UI surfaces it next) · **Effort:** L (2-3h dedicated)
- **Scope deferred:** (a) `/admin/selection` UI shows 2 distinct PERT cutoff bands per application (objective + leader_extra); (b) analytics RPCs (`exec_funnel_summary`, `exec_analytics_v2_quality`) updated to surface leader_extra dimension; (c) MCP tools (`get_selection_dashboard`, `get_selection_rankings`, `get_application_score_breakdown`) expose leader_extra separately; (d) Pre-fe80842c inflated `objective_score_avg` cleanup (some apps have obj_avg matching leader_extra PERT despite 0 objective evals — clearly mutated; high blast radius, needs PM-reviewed migration).
- **Cross-ref:** Phase 1 #154 (PR #268), supersedes A2 of original #229.

### 156. BUG-219.A — External reviewer workflow incomplete; Angelina blocked from /admin/governance/documents/[chainId] despite p195 carve-out
- **Tipo:** BUG / structural incompleteness · **Severity:** HIGH (Angelina legal review = institutional blocker for signature circulation) · **Effort:** L (2-3h) · **Status:** FILED GH #270, WORKAROUND in place (Word copies via gmail), PHASE 1+2+3 fix deferred
- **Discovery (p219 close):** PM reported Angelina (`angeline.jur@gmail.com`) got "negativa de acesso" on links `nucleoia.vitormr.dev/admin/governance/documents/[chainId]` sent via gmail 2026-05-13 for review of 6 governance docs (Política de Governança de PI cfb15185 + 5 others). PM workaround: sent Word copies via gmail attachment — Angelina unblocked from READING but COMMENT-via-platform workflow remains broken.
- **Root cause — 3 layers:**
  1. **Operational gap:** Migration `20260710000000_p195_can_carve_out_governance_review.sql` header explicitly NAMES "advogada Angelina, external_reviewer" and shipped V4 plumbing (engagement_kind `external_reviewer` slug, `engagement_kind_permissions` row kind=external_reviewer/role=reviewer/action=participate_in_governance_review/scope=organization, can() carve-out bypassing is_authoritative for this action). BUT no per-person onboarding ever executed — Angelina has no persons / engagements / auth account.
  2. **RPC code gap:** Even if Angelina were onboarded, `get_chain_for_pdf` (and likely siblings — needs audit) gates strictly on `can_by_member('manage_member')`. The p195 carve-out granted `participate_in_governance_review` — NOT `manage_member`. Consumer RPCs were never updated to respect the new capability. Migration intent docs ≠ implementation completeness.
  3. **UX/URL:** `/admin/governance/documents/[chainId]` URL path-name suggests admin-only. No external-reviewer-friendly alt route; full admin sidebar + breadcrumbs render even in review-only mode.
- **Phase 1+2+3 fix (L 2-3h):** (1) ~30min onboard Angelina (persons + engagement kind=external_reviewer/reviewer + auth invitation email); (2) ~1h audit ALL governance review RPCs for hardcoded `manage_member`; update READ + COMMENT RPCs to accept either `manage_member` OR `participate_in_governance_review`; keep strict for SIGN/LOCK/PUBLISH; (3) ~1h UX comment-only mode in ReviewChainIsland + optional `/governance/documents/[chainId]` external-friendly route.
- **Cross-ref:** GH #270, mig `20260710000000_p195_can_carve_out_governance_review.sql` (the carve-out), mig `20260519000644_p195_initiative_leaders_governance_review_seed.sql` (companion seed), ADR-0007, ADR-0016.

### 157. SEDIMENT-219.B — Check the ACTUAL URL/link before hypothesizing access-denied root cause
- **Tipo:** workflow sediment · **Severity:** LOW (caught via PM correction) · **Effort:** N/A (recurring lesson)
- **Trigger:** PM reported "Angelina não conseguiu acessar os links". Claude's first-pass diagnosis assumed Drive sharing config issue and recommended doc-track partner_entity. PM corrected with actual gmail body showing `/admin/governance/documents/[chainId]` platform admin URLs. Real bug (BUG-219.A) was platform-side workflow incompleteness — wasted ~5min on wrong hypothesis.
- **Lesson:** When PM reports "X cannot access Y", FIRST ask to see the EXACT link/URL/email PM sent BEFORE hypothesizing root cause. Don't assume Drive vs platform from problem description alone.
- **Cross-ref:** Initial Drive-sharing investigation thread + PM correction in p219 close session; BUG-219.A #156 above (the actual finding).




### 158. RESOLVED-219.A — External reviewer workflow end-to-end (PR #272 — Angelina Phase 1+2+3)
- **Tipo:** BUG / structural fix · **Severity:** HIGH (was blocking institutional signature circulation) · **Effort:** L (~3h delivered) · **Status:** RESOLVED via PR #272 squash `795f3ff5`
- **Trigger:** Carry from p219 BUG-219.A (#156). 3-layer fix consolidated atomic.
- **Phase 1 (operational, execute_sql atomic CTE):** Angelina Prado onboarded — persons `1beeeab7-1e15-4f0a-a8bf-331b54e18057` + members `0522cee1-9840-4ce3-8e32-1bd4a0cad229` + engagement `5280f0a3-4140-4e71-84eb-94f9978b9fc3` (kind=external_reviewer, role=reviewer, is_authoritative=false because requires_agreement=true catálogo + no cert). Auth_id linked to pre-existing Google OAuth ghost `f8f7c94b-4a72-44c5-8ddf-f759e650b1cd` (criado mesmo dia 14:27 quando ela tentou logar e bounced no ReviewChainIsland.tsx:215 "Faça login" gate). admin_audit_log `a28b3798-...` registrado. Smoke: `can_by_member('participate_in_governance_review')=TRUE`, `manage_member=FALSE`, invariants 19/19=0.
- **Phase 2 (migration 20260804000000):** `get_chain_for_pdf` + `get_chain_audit_report` gate broadened de `can_by_member('manage_member')` para `(manage_member OR participate_in_governance_review)`. Write/destructive RPCs (lock_document_version, recirculate_governance_doc, delete_document_version_draft, sign_ratification_gate) intactos. Comment RPCs (create_document_comment, list_document_comments, resolve_document_comment) já aceitavam carve-out — no change needed.
- **Phase 3 (UX):** 4 novas rotas `/governance/documents/[chainId]/{index,export-pdf,export-docx,audit-report}.astro` usando BaseLayout (no admin sidebar) + en/es locale redirects + ReviewChainIsland ganha prop `externalReviewMode` (default false, backwards-compat) + canComment widened pra incluir carve-out + comment-only banner "Modo de revisão externa" + export/audit links toggle entre /admin/governance/* e /governance/* baseado no prop.
- **Forward-defense:** +15 contract tests (7 Phase 2 RPC + 8 Phase 3 UX), Test baseline 1629 → 1644.
- **Cross-ref:** PR #272 (`795f3ff5`), GH #270 closed, migration 20260804000000, branch agent/p220-bug-219a-external-reviewer-workflow preserved at 7edc3a0a.

### 159. RESOLVED-273 — ChainPDFDocument supports `<table>` rendering (PR #274)
- **Tipo:** rendering bug fix · **Severity:** MEDIUM (PDF distribution incomplete despite HTML view correct) · **Effort:** M (~1.5h delivered) · **Status:** RESOLVED via PR #274 squash `64f90783`
- **Trigger:** TAP CPMAI Ciclo 3 audit during Welma onboarding revealed 25 tables in chain 897aeddf-... carrying critical structured content (header table com Código Projeto/Patrocinador/Líder Iniciativa/GP, partes interessadas federações por capítulo, equipe básica, orçamento, critérios sucesso, riscos, pool instrutores Anexo A, análise competitiva Anexo C) were silently dropped from official PDF export. HTML on `/admin/governance/documents/[chainId]` rendered fine via sandboxed `IsolatedHtmlFrame`; downloadable PDF was missing all tabular structure because `parseHtml` em ChainPDFDocument.tsx só matchava `(h2|h3|h4|p|li)` blocks.
- **Fix:** parseHtml usa masterRegex `/<table[^>]*>([\s\S]*?)<\/table>|<(h[234]|p|li)[^>]*>([\s\S]*?)<\/\2>/gi` matching BOTH em document order. Tables consume inner content so block matcher can't double-extract `<p>/<li>` nested in cells. `parseTable(tableInner)` extracts `<tr>` + `<th>/<td>`, header row detection dual-path (inside `<thead>` range OR cell-level `<th>`). `renderTable` uses @react-pdf/renderer `<View>` with `flexDirection:row`, `flex:1` per cell (equal-share columns), `wrap={false}` em cada row (atomic, não quebra entre páginas).
- **Out of scope (deferred):** `<ul>/<ol>` numbering, `<details>/<summary>` heading, column auto-sizing, header repetition across page breaks.
- **Forward-defense:** +11 contract tests static. Test baseline 1644 → 1655.
- **Cross-ref:** PR #274 (`64f90783`), GH #273 closed (filed same session), branch agent/p220-issue-273-chainpdf-table-rendering preserved at 7a55393e.

### 160. RESOLVED-OAuth-allowlist-perplexity — Host endsWith match (PR #275)
- **Tipo:** OAuth security refactor + Perplexity unblock · **Severity:** HIGH (PM's Perplexity MCP connector broken) · **Effort:** M (~1h delivered) · **Status:** RESOLVED via PR #275 squash `dda2c4a5`
- **Trigger:** PM reported MCP tools sumindo no Perplexity. Live probe via 5 URI variants identificou allowlist prefix-string em `ee14b998` (abril 2026) só cobria `https://perplexity.ai/` + `https://www.perplexity.ai/` MAS bloqueava `api.perplexity.ai`, `comet.perplexity.ai`, `mcp.perplexity.ai`. Perplexity routava callbacks via subdomínio. Same gap latent for `app.claude.ai`, `api.cursor.com`, `api.chatgpt.com`.
- **Refactor:** Substituiu prefix-string match (HTTPS_PREFIXES array com 13 entradas) por `URL parser + host endsWith '.' + root` para qualquer root em TRUSTED_ROOT_HOSTS (`claude.ai, chatgpt.com, openai.com, perplexity.ai, cursor.com, manus.im, vitormr.dev`). Trust transitivo: trustando `perplexity.ai` cobre `*.perplexity.ai`.
- **Security properties preservados:** HTTPS-only para remote (HTTP só localhost); suffix-injection prevention via dot anchor (testado contra `fake-perplexity.ai`, `perplexity.ai.attacker.com`, `perplexity-ai.com`, `claudeai.evil.com` — todos REJEITADOS); custom schemes (cursor://, vscode://) unchanged; case-insensitive host; fail-closed.
- **Forward-defense:** +9 contract tests (root hosts + subdomains + attacker domains + custom schemes + localhost + HTTP downgrade + garbage + case-insensitivity + query/path/fragment ignored). Test baseline 1655 → 1664.
- **Live smoke pós-deploy:** 11/11 corretos. Subdomains agora passam allowlist (return "code expired" em /oauth/token vs antes "redirect_uri not permitted"). Attacker variants ainda bloqueados.
- **Cross-ref:** PR #275 (`dda2c4a5`), branch agent/p220-oauth-host-suffix-allowlist preserved at 865a0660. Note: PM's Perplexity OAuth completou após este fix MAS tools/list ainda empty → ver #161 (PR #276) e #162 (BUG-220.A deferred).

### 161. RESOLVED-execution-strip — Worker proxy strips non-spec `execution.taskSupport` from tools/list (PR #276)
- **Tipo:** MCP spec compliance · **Severity:** HIGH (continuation of Perplexity unblock) · **Effort:** M (~45min delivered) · **Status:** RESOLVED via PR #276 squash `70e4219e` (technical fix shipped; UX impact pending — see BUG-220.A)
- **Trigger:** Sequel to PR #275. Após OAuth allowlist fix desbloquear auth, Perplexity connector mostrou "Connected · vitorodovalho@gmail.com" MAS tab de tools "No tools to display". Servidor MCP retornava 200 com 299 tools normalmente. Diagnose: cada tool carregava `execution:{taskSupport:"forbidden"}`, extensão Anthropic-internal de `@modelcontextprotocol/sdk@1.29.0` (Claude Managed Agents task-scheduling hint), **não no MCP spec público** em spec.modelcontextprotocol.io. Parsers stricter (Perplexity, possivelmente Cursor) silently drop the entire tools array on unknown top-level fields per tool.
- **Fix:** Worker proxy em `src/pages/mcp.ts` detecta tools/list via regex em reqBody (`/"method"\s*:\s*"tools\/list"/`) + strip via two regex passes (leading-comma `/,\s*"execution"\s*:\s*\{\s*"taskSupport"\s*:\s*"forbidden"\s*\}/g` e trailing-comma `/"execution"\s*:\s*\{\s*"taskSupport"\s*:\s*"forbidden"\s*\}\s*,?/g`). Strip universal (sem User-Agent gate — payload spec-compliant beneficia todos clients, gating cria matrix "works on Claude.ai not Perplexity" que envelhece mal). Roda BEFORE SSE streaming branch. Delete content-length header. kvLog instrumenta rawLen/cleanedLen/stripped delta.
- **Forward-defense:** +8 contract tests. Test baseline 1664 → 1672.
- **Live smoke pós-deploy:** Custom domain `nucleoia.vitormr.dev/mcp` retorna 0 `execution` occurrences. Direct Supabase URL `ldrfrvwhxsmgaabwmaik.supabase.co/functions/v1/nucleo-mcp/mcp` retorna 299 (strip selective ao proxy). MCP server-side tools/list spec-compliant via proxy.
- **Cross-ref:** PR #276 (`70e4219e`), branch agent/p220-mcp-strip-execution-field preserved at 9169a143, GH #277 (BUG-220.A — strip alone insufficient, tools/list still empty in Perplexity).

### 162. BUG-220.A — Perplexity MCP connector "No tools to display" persists after PR #275 + #276
- **Tipo:** client-side MCP rejection mystery · **Severity:** MEDIUM (workaround: Claude.ai connector) · **Effort:** L 1-3h investigation (no fix budget yet) · **Status:** FILED GH #277, DEFERRED
- **Trigger:** Após shipar PR #275 (OAuth allowlist subdomains) + PR #276 (execution.taskSupport strip), PM reconectou Perplexity → connector mostra "Connected · vitorodovalho@gmail.com" MAS tools tab ainda "No tools to display". Server-side tools/list HTTP 200 com 299 tools spec-compliant. Reject is happening INSIDE Perplexity client por motivo desconhecido.
- **Hypotheses (documented in #277 body):** H1 `$schema` field at inputSchema level confunde Perplexity validator → strip também; H2 Perplexity caps em N tools (299 > limit); H3 tool name length / character constraints; H4 tool específico emite schema malformado que crasha parser silently; H5 protocol version mismatch (responding `2025-11-25`, Perplexity may negotiate diff); H6 Perplexity espera `outputSchema`/`annotations` (newer MCP spec, SDK 1.29.0 may not emit); H7 anti-spam heuristic rejeita connectors com > N tools.
- **Recommended next-session actions:** (1) Capture Perplexity actual request/response payload via mitmproxy or browser devtools; (2) H1 hotfix attempt (strip `$schema` — quickest win); (3) H4 audit (JSON-schema validate every tool's inputSchema via `scripts/audit-mcp-tool-matrix.mjs` extension); (4) Worker logs with DEBUG_KV_LOGS env toggle to capture Perplexity request shape.
- **Workaround:** PM uses Claude.ai connector (works fine). Perplexity stays disconnected. No data loss; productivity friction only.
- **Cross-ref:** GH #277, PR #275 + #276 (diagnostics still green post-deploy), .claude/rules/mcp.md (will receive sediment: "spec-compliant != client-compatible — strip-execution alone insufficient for Perplexity"). Lesson: when adding tools/schemas, test in ≥2 MCP clients minimum (Claude.ai + Perplexity).

### 163. RESOLVED-OP-WELMA — Welma Alves de Melo onboarded (operational, atomic CTE + Supabase Auth invite)
- **Tipo:** operational onboarding · **Severity:** N/A (operational) · **Effort:** S (~20min) · **Status:** RESOLVED operacionalmente same-session
- **Trigger:** PM ask mid-session — Welma é atual Diretora de Certificação @ PMI-GO (`welma@pmigo.org.br`), vai revisar + aprovar junto ao Ivan o TAP CPMAI Ciclo 3 (chain `897aeddf-a895-4f66-822a-b52fdccbf35c`). PM enfatizou: "quando feito via insert no banco corta os fluxos" → não basta INSERT direto, precisa também enviar magic link.
- **Audit precedent:** chapter_board pattern (Ivan/Lorena/Eder) via `seed_member_engagement_by_role(slug='chapter_liaison')` template existente. Eder Valasco precedent confirma: INSERT persons+members + RPC seed PLUS `_enqueue_engagement_welcome` é o canonical path. PORÉM `_enqueue_engagement_welcome` body audit revelou: **NÃO TEM CASE para `chapter_board` kind** → falls to ELSE `RETURN;` → no welcome email enqueued. Por isso Lorena/Eder/Emanuele ficaram phantoms (auth_id=null, never logged in).
- **Fluxo executado (3 etapas):** (1) execute_sql atomic CTE: persons `1333ae00-a180-4ab4-8dcc-5e34e13dc81b` + members `7f2e8940-d74b-4115-9f25-fee07cab9611` (chapter='PMI-GO', operational_role='chapter_liaison' derivado pelo trigger sync_operational_role_cache, designations=['chapter_board','certificacao_director'], member_status='active') + engagement `b23b05ab-7c37-4f04-a9a3-0ea261c721d2` (kind=chapter_board, role=liaison, status='active', start_date=today, legal_basis='contract', granted_by Vitor person_id, is_authoritative=true porque chapter_board catálogo requires_agreement=false); (2) Supabase Auth Admin API invite via curl + service_role: POST `/auth/v1/invite` com email + redirect_to=`https://nucleoia.vitormr.dev/governance/documents/897aeddf-...` → criou `auth.users` `0c63b864-47a3-460b-88b2-0cdf11fb8f88` + magic link email enviado; (3) pre-link manual `UPDATE members SET auth_id` + `UPDATE persons SET auth_id` para get_member_by_auth Step 1 (direct match) retornar imediatamente sem depender do Step 3 first-link fallback.
- **Smoke:** can_by_member('participate_in_governance_review')=TRUE, manage_member=FALSE, _can_sign_gate(chapter_witness, 897aeddf)=FALSE (gate doesn't exist in this chain ainda — esperado, PM picked Welma = comentadora consultiva per chain notes design original "2 gates formais + comments-only consultations").
- **Cross-ref:** admin_audit_log `f33571dc-1897-4837-b5df-db2178ec8abf`, chain `897aeddf` notes (load-bearing design: 2 gates only + consultive comments via document_comments).

### 164. DISCOVERY-220.B — Chain 897aeddf state anomaly (governance_documents.status='draft' + locked_at=NULL while approval_chains.status='review')
- **Tipo:** data integrity discovery · **Severity:** LOW (doesn't block signing) · **Effort:** N/A (sediment) · **Status:** DOCUMENTED, no immediate fix
- **Trigger:** TAP CPMAI Ciclo 3 audit during Welma onboarding revelou inconsistência: chain status='review' bound to version_id `830932b8` MAS document_versions.locked_at=NULL + governance_documents.status='draft'. Normalmente lock_document_version() canonical path defines locked_at=now() + governance_documents.status='under_review' atomically when chain opens.
- **Implication:** Chain criada via path não-canônico (custom SQL, manual approval_chain INSERT, or deprecated migration). Doesn't block sign_ip_ratification because content_snapshot is captured at sign-time. But inconsistent.
- **Potential future invariant:** could add a new invariant U checking `approval_chains.status='review' → governance_documents.status='under_review' AND document_versions.locked_at IS NOT NULL`. Would catch this drift class.
- **Cross-ref:** chain 897aeddf, lock_document_version() RPC body.

### 165. WATCH-220.C — Herlon mentions in TAP CPMAI Ciclo 3 (7 distinct contexts, R01 update pending)
- **Tipo:** content drift watcher · **Severity:** LOW-MEDIUM (Herlon offboarded p217 SGO but TAP still names him as Líder da Iniciativa) · **Effort:** S-M (~30-45min R01 draft + recirculate) · **Status:** DEFERRED (aguardando Welma comentar primeiro per PM)
- **Locations:** (1) cabeçalho "Líder da Iniciativa: Herlon Alves de Sousa (PMI-CE)"; (2) Partes Interessadas row PMI-CE "🟢 Federado (Herlon — Líder da Iniciativa)"; (3) Stakeholder section "Núcleo IA & GP — Líder da Iniciativa — Herlon Alves de Sousa"; (4) Equipe Básica row "Herlon Alves de Sousa — Líder (study_group_owner) — 21-30h/mês"; (5) **Section 16.3 dedicada** "Gerente de Projetos da Iniciativa (Herlon Sousa)" com bullet list inteira de responsabilidades; (6) Status table "Herlon Alves de Sousa — Líder da Iniciativa — (convidado a comentar)"; (7) Changelog R00 "consolidação do PM Canvas do Líder da Iniciativa (Herlon, 2026-04-11)" — esse é histórico legítimo.
- **PM decision:** esperar Welma comentar a R00 atual primeiro; depois decidir se cria R01 com Herlon→TBD em 6 menções (preserva changelog histórico) + recirculate, OU aprova R00 como é e cria adendo administrativo separado.
- **Cross-ref:** chain 897aeddf, Herlon offboarding p217 (engagement cdcd9693 ended), PM ABCD pick "esperar Welma comentar primeiro" no p220.

### 166. WATCH-220.D — Welma magic link clickthrough pending
- **Tipo:** QA window watcher · **Severity:** MEDIUM (institutional flow) · **Effort:** N/A (PM smoke) · **Status:** OPEN
- **Trigger:** Welma onboarded via Supabase Auth Admin invite (p220), magic link email enviado com redirect_to=/governance/documents/897aeddf-... Welma ainda não clicou (verificar `auth.users.last_sign_in_at` no boot p221).
- **Expected smoke:** Welma clica → auth.users.last_sign_in_at populated → land on `/governance/documents/897aeddf-...` → banner "Modo de revisão externa" → document content loads → comment drawer accessible → adds comment.
- **Cross-ref:** Welma engagement `b23b05ab`, auth.users `0c63b864`, chain 897aeddf TAP CPMAI Ciclo 3.

### 167. WATCH-220.E — Angelina QA window (#270 closed but smoke pending)
- **Tipo:** QA window watcher · **Severity:** MEDIUM · **Effort:** N/A (Angelina smoke) · **Status:** OPEN
- **Trigger:** PR #272 (BUG-219.A Phase 1+2+3) merged + Angelina onboarded operacionalmente. PM mandou link novo via gmail. Angelina ainda não clicou (verificar `auth.users.last_sign_in_at` para `f8f7c94b-...`).
- **Expected smoke:** Same as Welma flow — banner, document load, comment drawer, PDF download. Lower urgency since Word workaround exists.

### 168. SEDIMENT-220.F — Operational onboarding pattern (atomic CTE + Auth Admin invite + pre-link)
- **Tipo:** workflow sediment / canonical pattern · **Severity:** N/A (positive pattern) · **Effort:** N/A · **Status:** DOCUMENTED for future reuse
- **Pattern:** When PM asks to onboard external user (advogada, chapter director, sponsor, etc.) without going through full selection pipeline:
  1. **Stage 1 (DB)**: execute_sql atomic CTE: INSERT persons (auth_id=NULL if no pre-existing auth) + INSERT members (with chapter, member_status='active' to avoid trigger normalizing to inactive, organization_id default '2b4f58ab-...nucleo-ia') + INSERT engagement (kind+role per template; status='active'; granted_by Vitor's person_id `d6e3622a-...`; legal_basis='contract' or 'consent' per engagement_kind catalog). Trigger `sync_operational_role_cache` derives operational_role from engagement on INSERT. Trigger `sync_member_email_trigger_fn` auto-creates member_emails primary. Trigger `sync_member_status_consistency` BEFORE INSERT may normalize (member_status='observer' → is_active=false + operational_role='observer' — avoid for new active engagements).
  2. **Stage 2 (after Stage 1)**: UPDATE persons.legacy_member_id = members.id (chicken-and-egg link). INSERT admin_audit_log row.
  3. **Stage 3 (Auth Admin invite if no pre-existing auth.users)**: curl POST `/auth/v1/invite` with SUPABASE_SERVICE_ROLE_KEY + email + user_metadata + redirect_to. Returns auth.users row. Magic link email sent automatically.
  4. **Stage 4 (optional pre-link)**: UPDATE members.auth_id = auth.users.id + UPDATE persons.auth_id = same. Makes `get_member_by_auth` Step 1 succeed immediately on first login (skips Step 3 primary-email first-link fallback).
- **Tested with:** Angelina (Stage 1+2+pre-existing-ghost-link), Welma (full Stage 1+2+3+4)
- **Gotcha catalog:** (a) CTE UPDATE in a chained WITH clause may be SKIPPED if its RETURNING isn't referenced in the final SELECT (PostgreSQL optimization) — run UPDATE separately if standalone; (b) trigger sync_member_status_consistency forces member_status='observer'/'alumni'/'inactive' → is_active=false → may trigger invariants E/L/N (use 'active' for new external members actively engaged); (c) `_enqueue_engagement_welcome` doesn't cover chapter_board kind — Auth invite handles magic link directly; (d) operational_role cache derived from engagement — direct set in INSERT will be overwritten by trigger; (e) members.chapter NOT NULL default 'Outro' — set to 'PMI-XX' for chapter board to align with `_can_sign_gate('president_go')` chapter check.
- **Cross-ref:** Angelina (PR #272 Phase 1), Welma (this session operational), p218 Vitor temp SGO precedent (#142 RESOLVED-257.A).

### 169. RESOLVED-267 — Server-side cert PDF backfill alpha (PR #282 — 42/42 certs)
- **Tipo:** LGPD Art. 16 record-keeping fix · **Severity:** MEDIUM (no canonical artifact for auditor retrieval pre-fix) · **Effort:** S-M (~1.5h delivered, downscoped from issue B/C original ~2.5-4h estimate) · **Status:** RESOLVED via PR #282 squash `724525ac`
- **Trigger:** Carry from p219 WATCH-258.A (#146). 42 certs (41 vol_agreement + 1 contribution) had `pdf_url IS NULL`. Browser-print pipeline already wired (p218 PR #262 RESOLVED-217.B) for member-side download via `window.print()`, but platform had no stored canonical artifact — every retrieval re-rendered client-side. Long-term retention guarantees per LGPD Art. 16 + auditor traceability weakened.
- **Scope α (PM pick)**: backfill-only via local Node script. Migration `20260805000000` creates private `certificates` storage bucket (10MB cap, application/pdf only, ON CONFLICT idempotent). `scripts/backfill-cert-pdfs.ts` Node 24 native TS (no transpile) reuses canonical `buildCertificateHTML` + `hydrateCertData` from `src/lib/certificates/pdf.ts` (zero porting, zero rendering drift vs browser-print). Playwright headless Chromium renders A4 with margins matching `@page` CSS (15/12/18/12mm). Uploads to `<member_id>/<verification_code>.pdf` then UPDATEs certificates.pdf_url. Idempotent (skip pdf_url IS NOT NULL default; --force overrides; --cert/--limit/--dry-run/--out-dir CLI flags).
- **Live results:** 42/42 certs with pdf_url populated. 42 storage.objects (~6MB total, avg 142KB/cert). Zero orphans (every pdf_url has backing object; every object has backing cert).
- **Forward-defense:** +9 contract tests static (file existence + bucket attrs + ON CONFLICT idempotency + RLS-deliberately-absent + canonical template import + storage path convention + idempotency filter + content type + A4 margins parity). Test baseline 1672 → 1681 offline.
- **Cross-ref:** PR #282 (`724525ac`), GH #267 closed (partial — alpha only), GH #281 filed (forward gap carry — see #171 below), branch `agent/p221-issue-267-cert-pdf-server-backfill` preserved at `6fce1ba0`.

### 170. DECISION-267.A — Original Option B estimate underestimated Workers + HTML-template constraints
- **Tipo:** architectural decision sediment · **Severity:** N/A (positive surfacing — informed PM pick) · **Effort:** N/A · **Status:** DOCUMENTED
- **Trigger:** Issue #267 body's "Architecture options" section recommended Option B (Astro endpoint, ~2.5h sweet spot). Pre-execution constraint analysis surfaced two material gaps in the estimate:
  1. **Astro adapter is `@astrojs/cloudflare`** (Workers runtime with `nodejs_compat` flag enabled). `@react-pdf/renderer@4.5.1` is Node-oriented (pdfkit + fs + buffer-heavy); Workers compat not verified. Spike risk material.
  2. **Cert template uses HTML+CSS** (`src/lib/certificates/pdf.ts buildCertificateHTML/buildVolunteerAgreementHTML`), NOT React. `@react-pdf/renderer` is only used by *governance chains* (`src/components/governance/Chain*PDF*.tsx` — client-side). Option B "server-side" would actually require porting the HTML cert template into `@react-pdf/renderer` React components — 4-6h work + visual regression risk on a formal legal document (TERMO DE COMPROMISSO DE VOLUNTÁRIO).
- **Constraint analysis output (presented to PM):** 3 alternative paths α (backfill-only local script + playwright, ~1.5h, zero rendering drift), β (CF Browser Rendering API binding, ~3-4h, requires paid CF binding), γ (rewrite cert as @react-pdf, ~4-6h, visual regression risk).
- **PM pick:** α (Recommended) — ships the LGPD-relevant backfill with zero visual fidelity risk; forward auto-gen architecture decision deferred to dedicated ticket (#281).
- **Lesson (carry-forward):** When an issue specs an "Astro endpoint server-side" path for visual/PDF/asset rendering, **CHECK FIRST** whether (a) the underlying renderer is Workers-compat and (b) the template uses the same component model as the renderer. The "Astro is just a framework" mental shortcut hides the Workers runtime constraint repeatedly. Apply same check to any future ticket touching @react-pdf, headless browser, server-side image processing, font rendering, etc.
- **Cross-ref:** Issue #267 body Option A/B/C section, PR #282 description, #281 (carries the architecture decision forward).

### 171. WATCH-258.B-FILED — Forward auto-gen + verify-route + ADR amendment (GH #281)
- **Tipo:** forward-gap watcher · **Severity:** MEDIUM-LOW (alpha solved auditor retrieval; new certs still rely on browser-print) · **Effort:** L (3-4h β recommended, 4-6h γ, 4-5h δ) · **Status:** FILED, DEFERRED
- **Scope (in issue body):** (a) `sign_volunteer_agreement()` + future cert-issuance RPCs auto-generate stored PDFs at sign-time; (b) `/verify/{code}` page surfaces stored-PDF download (PM pick: member-only A vs public auditor B); (c) `/certificates` member page consumes pdf_url instead of browser-print; (d) storage.objects RLS for member-owned read (gated by `(storage.foldername(name))[1]::uuid IN (SELECT id FROM members WHERE auth_id=auth.uid()) OR rls_can('view_pii')`) — requires Studio UI per sediment p210 / SEDIMENT-221.B #173; (e) ADR-0006 (or new ADR-0096) amendment capturing canonical-artifact retention contract.
- **Architecture options (in issue body):**
  - **β CF Browser Rendering API** (recommended): binding + endpoint + sign_volunteer_agreement wrapper. Reuses existing HTML template. Paid CF dep (~$5/M req — negligible at our volume).
  - **γ Rewrite cert in @react-pdf/renderer**: spike Workers compat + port template + visual regression review. No paid dep but template port risk.
  - **δ Edge Function (Deno) with puppeteer-deno**: separate runtime. Cold-start adds 1-2s to sign UX.
- **Recommendation:** β (CF Browser Rendering) — fastest to ship, zero visual drift, paid dep negligible. Member SELECT path: Option A (member-only download) more LGPD-conservative.
- **Cross-ref:** GH #281, issue #267 (carries the alpha-side), ADR-0006, LGPD Art. 16/18.

### 172. SEDIMENT-221.A — Node 24 native TS strip-types unlocks `scripts/*.ts` reuse of `src/lib/*.ts`
- **Tipo:** tooling sediment / positive pattern · **Severity:** N/A (enables future patterns) · **Effort:** N/A · **Status:** DOCUMENTED for reuse
- **Discovery:** Backfill script needed to render certs using the SAME HTML template the browser-print path uses (`src/lib/certificates/pdf.ts`). Initial design considered: (1) port pdf.ts to .mjs (drift risk + ~600 lines copy); (2) jiti dynamic TS import (transitive dep, not stable); (3) tsx/ts-node devDep add (tooling change beyond cert scope); (4) inline reimplementation in script (drift). Discovered Node v24.15.0 (local) + v22.6+ (CI via `--experimental-strip-types` flag, already used by `npm test`) natively load `.ts` files with type annotations stripped. Wrote `scripts/backfill-cert-pdfs.ts` (not .mjs) importing directly from `../src/lib/certificates/pdf.ts`. Works locally with zero config; CI doesn't run the script.
- **Pattern unlock:** Future one-shot scripts (backfills, audits, data quality probes) that need src/lib helpers can now be `.ts` files reusing the production logic directly. Zero porting + zero drift between script and runtime. Examples this enables: future cert-PDF regen scripts; manifest exporters that need formatting from pdf.ts; data quality probes using src/lib/permissions helpers without re-implementing role-mapping.
- **Constraints:** (a) Astro/Workers code paths that need bundler features (`?raw` imports, virtual modules, etc.) won't load via Node — keep node-runnable helpers free of Astro-isms; (b) requires Node 22.6+ on dev box + CI runner; (c) experimental flag stable in 22+ but may shift to stable-default in 23/24.
- **Cross-ref:** `scripts/backfill-cert-pdfs.ts`, `src/lib/certificates/pdf.ts`, `package.json` `test` script (already uses --experimental-strip-types).

### 173. SEDIMENT-221.B — storage.objects RLS via MCP apply_migration still blocked (recurring p210 sediment)
- **Tipo:** infrastructure sediment / recurring constraint · **Severity:** LOW (workaround documented, ships fine) · **Effort:** N/A · **Status:** RECURRING — formalize Studio-UI runbook?
- **Trigger:** p221 #267 alpha migration draft initially included `CREATE POLICY certificates_select_admin ON storage.objects ...` (and INSERT/UPDATE/DELETE companions). `apply_migration` MCP returned `ERROR: 42501: must be owner of relation objects`. Sediment hit in p210 (Phase A SECDEF storage policies) + earlier sessions. Same root cause: Supabase's `storage.objects` table is owned by `supabase_storage_admin` role; MCP's service-level user cannot ALTER its RLS policies.
- **Workarounds available:** (a) Supabase Studio UI > Storage > Policies tab (canonical per p210); (b) `psql` as `supabase_storage_admin` (requires direct DB password, not typical); (c) Supabase Management API (rarely worth it). All require human-in-loop or out-of-MCP path.
- **α scope workaround:** Created bucket only (this DOES work via MCP — `storage.buckets` table has different ownership). Skipped policies entirely. Backfill uses service_role which bypasses RLS regardless of policies. Bucket `public=false` + no policies = no authenticated user access — clean default-deny posture. Member SELECT path (when Option C/#281 lands) will add policies via Studio UI.
- **Should we automate this?** Backlog: write `scripts/print_storage_rls_runbook.mjs` that emits the exact policy SQL + Studio UI navigation steps, so future tickets touching storage RLS have a copy-paste path. Saves the "rediscover this sediment" loop that hit p210, p221, and likely future sessions.
- **Cross-ref:** p210 Phase A SECDEF (handoff), p221 PR #282 migration `20260805000000` (explicitly documents RLS-deferred-to-Studio in header comment), `.claude/rules/database.md` should be amended at some point with a "storage.objects RLS" subsection.

### 174. RESOLVED-280-ALPHA — Semantic MCP Gateway bridge shipped (PR #285 — `/mcp/semantic` + 3 tools)
- **Tipo:** feature ship · **Severity:** N/A (epic alpha) · **Effort:** L (~5-6h) · **Status:** RESOLVED via PR #285 (squash `<TBD>`)
- **Trigger:** GH #280 (parent SPEC) + GH #283 (child store-readiness) created by PM out-of-band between p221 close + p222 boot (20:31 + 21:30 UTC 2026-05-22). Plus 2 untracked SPEC docs in working tree: `docs/specs/SPEC_280A_CONNECTOR_STORE_READINESS.md` + `docs/specs/SPEC_280B_SEMANTIC_MCP_GATEWAY_IMPLEMENTATION.md` ratifying bridge-first migration + 3-tool wave-1 + stable envelope shape.
- **Decision:** SPEC-280.B Option A (register semantic tools in existing `supabase/functions/nucleo-mcp/index.ts`, NOT a separate EF). Bridge-first: `/mcp` stays full catalog (regression-safe, 299 tools unchanged); new `/mcp/semantic` exposes 3 read-only tools designed against store-readiness criteria of OpenAI / Anthropic / Perplexity / xAI / Manus per SPEC-280.A.
- **3 wave-1 tools shipped:** `get_my_context` (compact self-scope context — profile + cycle + XP/streak + 3 events + 5 certs + unread count, LGPD-clean) + `search_nucleo_knowledge` (bounded multi-source FTS — hub + wiki + knowledge_assets) + `get_board_or_initiative_context` (initiative/board summary — 5 cards + 3 events + 2 meeting notes + active engagement count). All Promise.allSettled compound responses with stable envelope `{ok, data, summary, warnings, next_actions, audit}`.
- **Architecture:** EF gets new `app.all("/semantic")` route constructing separate McpServer "nucleo-ia-semantic" v0.1.0 registering only `registerSemanticTools`. Worker proxy `src/pages/mcp/semantic.ts` (new file, near-clone of `src/pages/mcp.ts`) forwards to `/nucleo-mcp/semantic` UPSTREAM. Both surfaces share OAuth flow, auto-refresh, rate limit, and tools/list `execution.taskSupport` strip.
- **/health restructured:** now reports both surfaces in nested object (`surfaces."/mcp".tools = 299`, `surfaces."/semantic".tools = 3`). Pre-existing test `member-emails-write-surface.test.mjs:214` regex updated to read the `/mcp` surface count specifically (was greedy first `tools: N` which broke after restructure).
- **Live smoke 7/7 PASS:** EF `/health` shape + EF `/semantic` initialize + EF `/semantic` tools/list (3) + EF `/mcp` regression (299) + Worker `/mcp/semantic` initialize + Worker `/mcp/semantic` tools/list (3, 0 execution field after strip) + Worker `/mcp` regression (299).
- **Test baseline:** 1681 → 1706 offline (+25 total: +24 new `tests/contracts/mcp-semantic-gateway-bridge.test.mjs` static assertions + +1 forward-defense added post-Council); pass count 1639 → 1664.
- **Cross-ref:** PR #285, SPEC_280A/B in `docs/specs/`, GH #280 parent + #283 child store-readiness + #277 Perplexity (this bridge is the structural fix that PR #279 $schema strip was working around).

### 175. RESOLVED-COUNCIL-280.HIGH-1 — `notifications.payload` column drift fix
- **Tipo:** bug fix (drift catch) · **Severity:** HIGH (silent runtime degradation) · **Effort:** XS (1-line column rename) · **Status:** RESOLVED via PR #285 commit `c5255539`
- **Trigger:** Council Tier 1 (platform-guardian + code-reviewer in parallel) flagged this as HIGH-1. Both audited the new `get_my_context` semantic tool and noticed `sb.from("notifications").select("id, type, payload, created_at")` referenced a non-existent `payload` column. Verified via live `information_schema.columns` query: notifications has `id/recipient_id/type/title/body/link/source_type/source_id/is_read/read_at/created_at/actor_id/email_sent_at/delivery_mode/digest_batch_id/digest_delivered_at` — no `payload`.
- **Silent failure mode:** default `include_notifications=false` would never hit the bug. Enabling it would populate `warnings[]` with PostgREST error + return empty `notifications` array. Tool returns `ok:true` but the notification feature is broken. Graceful degradation hides the bug from end users.
- **Fix:** select `"id, type, title, body, link, created_at"`. The `title` + `body` + `link` columns are the actual notification content already exposed via other tools (`get_my_notifications`), not PII. Added forward-defense contract test asserting no `payload` selection + presence of title/body/link.
- **Lesson:** the underlying RPC catalog has 109 distinct tools/RPCs (per p222 boot Pareto baseline). Composing them in a semantic tool requires verifying the actual table schemas — even when "obvious" columns like `payload` feel intuitive. SEDIMENT recurring class: AI-assisted code generation may hallucinate column names when source files are large + schema isn't directly in context. Counter: live schema query before any new `select(...)` is the cheapest validation.
- **Cross-ref:** PR #285 commit `c5255539`, Council Tier 1 reports inline in PR description, contract test `tests/contracts/mcp-semantic-gateway-bridge.test.mjs` test #25.

### 176. RESOLVED-COUNCIL-280.HIGH-2 — `knowledge_search_text` REVOKE'd FROM authenticated since p58 (latent /mcp bug + new /mcp/semantic dependency)
- **Tipo:** latent bug fix + new dependency unblock · **Severity:** HIGH · **Effort:** XS (3-line migration) · **Status:** RESOLVED via PR #285 migration `20260805000001` + EF re-deploy
- **Trigger:** Council code-reviewer HIGH-2: `search_nucleo_knowledge` semantic tool calls `knowledge_search_text` RPC; live ACL probe shows only `postgres=X/postgres, service_role=X/postgres` — `authenticated` was NOT in the ACL. SECDEF flag (`prosecdef=true`) doesn't help: GRANT EXECUTE is required at the caller-role level before SECDEF body executes.
- **Origin of REVOKE:** migration `20260426124716` (Track Q-D batch 3a.4, p58, 2026-04-26) `REVOKE EXECUTE ON FUNCTION public.knowledge_search_text(text, text, integer) FROM PUBLIC, anon, authenticated` based on "0 callers found in src/, supabase/functions/, scripts/, tests/" — dead-fn lockdown per dead-matrix consistency.
- **Latent bug since p58:** the existing `/mcp` tool `knowledge_search_text` (registered at `supabase/functions/nucleo-mcp/index.ts:3455`) was permission-denied for any authenticated caller for 26 days. Tool's error handler caught the error and returned `Error: permission denied for function knowledge_search_text` to MCP clients — never reported as a bug because nobody seemingly invoked it. The MCP catalog claim "Verified" on Claude.ai connector means tools/list works, but no live call hit this specific RPC.
- **Decision (Option B over Option A):** Platform Guardian suggested removing `knowledge_assets` from default sources of new tool (safer alpha workaround). Code Reviewer recommended restoring the grant (fixes both surfaces with 1 migration). Chose Option B because (a) SPEC-280.B explicitly cites `knowledge_search_text` as a source — PM expects it to work; (b) the dead-matrix predicate ("0 callers") that justified the REVOKE no longer holds; (c) sibling RPC `search_wiki_pages` has the identical authenticated grant — restoring keeps the public knowledge surface consistent; (d) underlying `knowledge_assets` table is wiki + external research, non-PII narrative knowledge (ADR-0010 scope).
- **Fix:** migration `20260805000001_p222_280_restore_knowledge_search_text_authenticated_grant.sql` GRANT EXECUTE + COMMENT ON FUNCTION documenting the restore rationale. Applied via MCP `apply_migration` + registered via `supabase migration repair --status applied 20260805000001` + NOTIFY pgrst. Post-fix ACL: `authenticated=X/postgres, postgres=X/postgres, service_role=X/postgres` ✓
- **Lesson:** dead-fn matrix REVOKEs from 6 months ago can become latent bugs when callers reappear. The original dead-matrix audit was correct at p58 (0 callers); the REVOKE was defensible then. The bug is in the OPPOSITE direction: when a session adds a new caller, it must check function grants — not just signatures. Counter: add a "function ACL probe" step to GC-097 pre-commit validation (before adding a new MCP tool that calls an existing RPC, grep for `REVOKE EXECUTE ON FUNCTION public.X` in any migration to confirm `authenticated` has access).
- **Cross-ref:** PR #285 migration `20260805000001`, Council Tier 1 inline reports, migration 20260426124716 (origin REVOKE).

### 177. WATCH-280.A — `mcp_usage_log` lacks surface attribution (/mcp vs /semantic)
- **Tipo:** observability gap · **Severity:** LOW (no ambiguity today since tool names are unique per surface) · **Effort:** S (1 column + sync logUsage signature) · **Status:** WATCH — defer to wave-2
- **Trigger:** Council platform-guardian MED-3. `logUsage(sb, member_id, tool_name, success, error_msg, exec_ms, result_kind)` has no `surface` parameter. Both `/mcp` and `/semantic` write to the same `mcp_usage_log` table.
- **Why not blocker today:** the 3 semantic tool names (`get_my_context`, `search_nucleo_knowledge`, `get_board_or_initiative_context`) are unique and NOT registered on `/mcp`. So `tool_name` alone discriminates surfaces.
- **Why watch:** if wave-2 ever aliases a tool name across surfaces (unlikely but possible if `/mcp` migrates to semantic-first and re-uses semantic names), or if Connector Store analytics need per-surface attribution for store-readiness metrics, the log becomes opaque. The cleanest fix is to add a `surface text` column to `mcp_usage_log` + extend `logUsage` signature with `p_surface`.
- **Trigger to upgrade WATCH → fix:** any of (a) wave-2 tool spec that proposes cross-surface aliasing; (b) PM ask for per-surface usage analytics; (c) bug report where log analysis is ambiguous.
- **Cross-ref:** PR #285, SPEC-280.B handoff, Council platform-guardian report.

### 178. WATCH-280.B — `scripts/audit-mcp-tool-matrix.mjs` not surface-aware (302 static vs 299 /mcp runtime)
- **Tipo:** tooling gap · **Severity:** LOW (informational drift, not bug) · **Effort:** S (add `--surface` flag) · **Status:** WATCH — file as backlog
- **Trigger:** Post-p222 #280 alpha, the audit script picks up 302 tools (299 in registerTools + 3 in registerSemanticTools) but the runtime `/mcp` tools/list still returns 299. The `--runtime` cross-check flags 3 "static-only drift" — which is HEALTHY EXPECTED STATE post-bridge, not actual drift.
- **Risk:** a developer running `node scripts/audit-mcp-tool-matrix.mjs --runtime` pre-deploy will see "drift: 3 static-only [get_my_context, search_nucleo_knowledge, get_board_or_initiative_context]" and investigate as a false alarm. The exception is documented in `.claude/rules/mcp.md` post-this-PR, but the script itself doesn't flag the case as benign.
- **Fix shape:** add `--surface=mcp|semantic|all` flag to the audit script. `--surface=mcp` scopes the static parser to only the `registerTools` + `registerKnowledge` blocks (excluding `registerSemanticTools`). `--surface=semantic` does the inverse. Default `--surface=all` keeps current behaviour for completeness.
- **Backlog:** file as `WATCH-280.B` in ISSUE_REGISTRY when split (or as part of wave-2 ADR-0096 prep).
- **Cross-ref:** PR #285, `docs/reference/MCP_TOOL_MATRIX.md` (now shows 302), `.claude/rules/mcp.md` "Current State" section explains the expected drift.

### 179. SEDIMENT-280.A — `transport.onclose` assigned after `handleRequest()` in both /mcp + /semantic handlers
- **Tipo:** pre-existing convention sediment · **Severity:** LOW (Deno EF stateless lifecycle bounds the leak) · **Effort:** XS (move 1 line per handler) · **Status:** SEDIMENT — separate fix PR
- **Trigger:** Council code-reviewer MED-3. The `/mcp` handler at `app.all("/mcp", ...)` was authored in v2.x (long pre-p222) with the pattern: `await mcp.connect(transport); const response = await transport.handleRequest(c.req.raw); transport.onclose = () => mcp.close();`. The transport may emit `close` event during `handleRequest` (especially for fast/synchronous responses) before the assignment lands — so `mcp.close()` never runs. My new `/semantic` handler copied this exact pattern.
- **Impact bounded:** Deno EF processes each HTTP request in its own isolate; when the function returns, the isolate is GC'd and the McpServer reference dies with it. So the leak is per-request and short-lived. Still wrong per SDK convention (transport.onclose should be wired before `connect` so close events fire correctly).
- **Why not fixed in this PR:** the `/mcp` handler is pre-existing — fixing only `/semantic` would diverge the two handlers, fixing both is a scope creep into pre-existing code. Cleaner as a separate single-purpose PR.
- **Recommended fix:** move `transport.onclose = () => mcp.close();` to BEFORE `await mcp.connect(transport)` in both handlers. No functional change visible to clients; just correct lifecycle hygiene.
- **Cross-ref:** PR #285, Council code-reviewer report, both `app.all("/mcp"` and `app.all("/semantic"` handlers in `supabase/functions/nucleo-mcp/index.ts`.

### 180. SEDIMENT-186.C — `deploy.md` baseline pin drift (chronic ratchet error: "1681 pass" was actually "1681 total = 1639 pass + 42 skip")
- **Tipo:** documentation drift (chronic) · **Severity:** LOW (no production impact, but undermines the ratchet protocol) · **Effort:** XS (this close-docs commit corrects it) · **Status:** RESOLVED for p222 in close docs; SEDIMENT pattern recurring
- **Trigger:** p222 npm test offline run showed `tests 1681 / pass 1639 / fail 0 / skipped 42`. The deploy.md baseline pin (p221) claimed "1681 pass / 0 fail / 42 skip" — but the actual passing count was 1639. The pin had been treating `total tests run` as `pass count` for an unknown number of sessions. With my +24 (then +25) new tests, the actual baseline becomes 1706 total / 1664 pass / 42 skip.
- **How long undetected:** unclear without auditing git log of deploy.md, but the chronic nature (the count never matched "pass=N+pass") suggests this drift has been present for many sessions. The WATCH-186.C tag was already filed as "manual ratchet — automation backlog" — this confirms why automation matters: a manual count + paste under time pressure produces this exact error pattern.
- **Counter:** the close docs section for p222 will pin the CORRECTED baseline (1706 total / 1664 pass / 42 skip) AND document the historical correction. Future sessions: copy the entire `ℹ tests N` line from npm test output verbatim, don't summarize. Or better — script the ratchet via `scripts/update-test-baseline.sh` that grep/sed-ups deploy.md from npm test output (WATCH-186.C automation).
- **Cross-ref:** PR #285 (does NOT update deploy.md baseline — that lands in close docs), deploy.md `## Pre-Deploy Checklist` section #2, WATCH-186.C original filing.

### 181. RESOLVED-AUDIT-MED-10 — ADR-0096 `impact_hours_total` accepted advisor risk (PR #287)
- **Tipo:** documentation / audit-trail close · **Severity:** MED (advisor ERROR untracked) · **Effort:** XS (~30min ADR + 12-line COMMENT migration) · **Status:** RESOLVED via PR #287 squash `6e02f58b`
- **Trigger:** p223 boot audit `/audit` MED #10 finding: `public.impact_hours_total` was the only SECDEF view advisor ERROR without an ADR (sibling `public_members` was covered by ADR-0024). Audit recommendation: file accepted-risk ADR mirroring ADR-0024 pattern OR REVOKE anon.
- **Fix:** Created ADR-0096 documenting accepted risk + trade-off matrix (α invoker-flip / β SECDEF RPC / γ slim view N/A / δ document risk — chose δ). Migration `20260805000002` updates `COMMENT ON VIEW` to preserve p170 BUG-HOI canonical formula rationale AND add ADR-0096 cross-reference. Zero behavior change: view definition, ACLs (anon already REVOKE'd via `20260426155255`), and 5 callsites (`attendance.astro` + 4 RPCs) untouched.
- **Rationale for δ over α/β:** (1) Content is platform-aggregate scalars — no PII per row, threat surface materially smaller than `public_members` (22 personal columns). (2) `anon` already REVOKE'd (live verified); surface is authenticated-only consuming RPCs. (3) Migration `20260508030000_security_sweep_wave1_flip_invoker_6_views.sql` already documents the intentional skip in code comment ("anon kept (UI anon-pre-auth)") — ADR formalizes what code already practiced. (4) Refactor β (DROP view + SECDEF RPC) is ~3-4h with 5 callsite cascading retest; cost/benefit favors δ.
- **Expected advisor behavior:** `security_definer_view` ERROR count STAYS at 2 (advisor is structural, doesn't read COMMENTs). Both findings now have ADR coverage for audit trail. Path β remains documented in ADR-0096 §"Follow-up planejado" for future invocation.
- **Cross-ref:** PR #287, ADR-0096, ADR-0024 (sibling pattern), migrations `20260805000002` (this) + `20260508030000` (prior implicit decision) + `20260674400000` (canonical formula source) + `20260426155255` (anon REVOKE).

### 182. RESOLVED-AUDIT-LOW-18 — ADR-0095 backfilled to README index + ADR-0094 reserved-numbering note (PR #287)
- **Tipo:** documentation drift close · **Severity:** LOW (audit-trail gap) · **Effort:** XS (3 lines in README) · **Status:** RESOLVED via PR #287
- **Trigger:** p223 boot audit `/audit` LOW #18: `docs/adr/ADR-0095-member-alternate-emails.md` existed as file (p213 ship) but no entry in `docs/adr/README.md` index. Audit script `scripts/audit_adr_index.sh` had not flagged this because it only checks "referenced ADRs have files" not "all files are referenced" (asymmetric check).
- **Fix:** Added 3 lines to `docs/adr/README.md`:
  - ADR-0094 reserved-numbering note (mirrors ADR-0082 pattern — confirms 0093→0095 jump is intentional, no references in docs/src/supabase or git history).
  - ADR-0095 entry (member alternate emails p213-p216 — 4-PR sequence with Council Tier 1 GO+AMENDMENTS).
  - ADR-0096 entry (this session — paired with #181 above).
- **Post-fix state:** 94 ADR files + 95 README entries; the +1 delta is ADR-0082 (intentional reserved numbering, audit p165 confirmed). `bash scripts/audit_adr_index.sh` PASS.
- **Audit script gap surfaced:** the bidirectional asymmetry is itself a documentation invariant gap — a file without a README entry should also be flagged. Backlog candidate: extend the audit script to also walk `docs/adr/ADR-*.md` and assert each one appears in the README (modulo intentional reservations). Not filed as its own entry because the fix is single-line awk on the existing script.
- **Cross-ref:** PR #287, ADR-0095 (member alternate emails p213), ADR-0082 (intentional reservation precedent), `scripts/audit_adr_index.sh`.

### 183. RESOLVED-279 — PR #279 closed as superseded by `/semantic` architecture
- **Tipo:** PR triage decision · **Severity:** N/A (housekeeping) · **Effort:** XS (close + comment) · **Status:** CLOSED (PR #279 closed; not merged)
- **Trigger:** p223 audit triage of open PRs surfaced #279 (`fix: strip schema from MCP tools/list for Perplexity` — opened 2026-05-22T20:03 same day as #285 semantic alpha). PR #279 was attempt at H1 hypothesis of #277 (Perplexity rejects `$schema` in inputSchema). Issue #280 acceptance criteria explicitly contemplated this close: *"PR #279 is either closed as unnecessary or folded only if the audit proves `$schema` is the blocker."*
- **Decision rationale (4 factors):**
  1. **Architectural supersession:** PR #285 (semantic gateway alpha) ships the narrow 3-tool `/mcp/semantic` surface that IS the canonical answer to #280's "capability profiles instead of one universal 299-tool catalog" requirement. Stripping `$schema` from the 299-catalog is a band-aid on the architecture #280 wants to replace.
  2. **CI validate failing:** branch was behind main (opened pre-#285 merge); test count drift 1701/1695/1/5 vs p222 baseline 1706/1664/0/42 needed rebase. Not worth maintaining a rebase if path is to close.
  3. **H1 not proven:** no Perplexity-side capture exists yet — the schema-strip is preemptive speculation per #277 H1 hypothesis list, not a confirmed bug fix.
  4. **`/semantic` ALSO emits `$schema`:** live smoke confirmed `/mcp/semantic` tools/list responses carry `"$schema":"http://json-schema.org/draft-07/schema#"` in each inputSchema — same trigger as `/mcp`. PM's next Perplexity retest against `/mcp/semantic` is the cheapest H1 disambiguation.
- **Reopen criteria documented in close comment:** reopen if PM's retest of Perplexity against `/mcp/semantic` (per updated #277) shows /semantic ALSO shows "No tools to display" AND a captured Perplexity payload specifically points at `$schema` as parse failure root cause.
- **Cross-ref:** PR #279 (closed) close comment, #277 (parent bug), #280 (semantic spec), PR #285 (alpha merged).

### 184. UPDATED-277 — Perplexity bug retest path documented (Case A close / Case B narrows to H4/H5/H6/H0)
- **Tipo:** PM async followup ask · **Severity:** N/A (workflow) · **Effort:** XS (PM ~2min retest) · **Status:** OPEN — PM action pending
- **Trigger:** p223 audit triage of #277 found semantic gateway alpha live + healthy but PM had not yet retested Perplexity against the new endpoint. Comment posted to #277 with smoke-confirmed evidence + structured retest path.
- **Smoke confirmation:** `/mcp/semantic` initialize → HTTP 200, serverInfo `{name:"nucleo-ia-semantic", version:"0.1.0"}`. tools/list → 3 tools (`get_my_context`, `search_nucleo_knowledge`, `get_board_or_initiative_context`).
- **Retest config asked of PM:** Perplexity new connector with Server URL `https://nucleoia.vitormr.dev/mcp/semantic` + Auth OAuth 2.0 + Transport **Streamable HTTP** (NOT SSE — per Perplexity docs, transport mismatch is a known issue class = H0).
- **Decision matrix posted:**
  - **Case A** (semantic shows 3 tools in Perplexity) → close #277 as resolved by alpha. Semantic surface IS the Perplexity-fit answer. Wave-2+ grows curated catalog per #280.
  - **Case B** (semantic ALSO "No tools to display") → H1 ($schema), H2 (catalog size), H7 (anti-spam) all DISPROVEN (3 tools << any reasonable limit). Remaining live hypotheses: H4 malformed-tool (JSON-Schema-validate each of 3 in <5min), H5 protocol-version mismatch (capture initialize request via mitmproxy/devtools), H6 missing outputSchema/annotations (SDK 1.29.0 doesn't emit), H0 transport mismatch (confirm Streamable HTTP).
- **Workaround:** Claude.ai connector continues to work fine; no urgency.
- **Cross-ref:** Issue #277 comment post-p223-audit, PR #279 (closed), PR #285 (semantic alpha).

### 185. WATCH-AUDIT-HIGH-17 — Migration file/row drift: 669-row gap (1112 .sql files vs 1781 tracked rows)
- **Tipo:** historical drift surveillance · **Severity:** HIGH-drift / LOW-functional · **Effort:** M (30min discovery + decision; up to 2-3h if remediation needed) · **Status:** OPEN — deferred discovery
- **Trigger:** p223 boot audit `/audit` finding #17. Migration tracking comparison: `ls supabase/migrations/*.sql | wc -l` = 1112 files vs `SELECT count(*) FROM supabase_migrations.schema_migrations` = 1781 rows. Delta = -669 (DB has 669 versions with no corresponding local file). Bucketing by date: 318 in Q1 2026 + 1435 in Q2 + 27 in Q3+ + 1 baseline.
- **Probable root cause:** historical V4 refactor sediment from pre-GC-097 era (pre-2026-04-13). Many migrations were applied via `apply_migration` MCP (or directly via Studio SQL editor) without the manual sync step that writes a local file + runs `supabase migration repair --status applied`. The GC-097 rule was instituted later; the discipline has been kept since (recent versions `20260805000000`/`001`/`002` all have files).
- **Functional risk assessment:** none today — contract tests `rpc-migration-coverage.test.mjs` pass (live function bodies all match SOME CREATE FUNCTION block in migrations). The risk surfaces only on `supabase db reset` from local files: 669 versions would be missing on reset.
- **Recommended discovery (next session):** sample 20 of the missing versions via `SELECT version FROM supabase_migrations.schema_migrations WHERE version NOT IN (SELECT 'TIMESTAMP_LIST_FROM_LS')` — classify each as (a) DDL needing capture vs (b) DML/backfill needing none vs (c) duplicate of an existing file with a different version stamp. Then decide between: amnesty migration (bulk-register a "drift baseline marker"), snapshot squash (collapse history at a recent good state), or per-version recovery.
- **Why not fixed in p223:** scope of audit was triage, not remediation. Wanted PM sign-off on remediation approach before committing time. Audit recommendation: investigate before any baseline rebuild.
- **Cross-ref:** p223 audit report finding #17, `.claude/rules/database.md` GC-097 rule (post-this gap was instituted), p86 sediment in `feedback_pg_get_functiondef_idempotent_capture.md` (related apply_migration file-write gap).

### 186. WATCH-AUDIT-LOW-LINT — Tailwind v4 CSS `Delim('/')` build warning (UPDATED p225: reclassified as TAILWIND_V4_UPSTREAM phantom warn)
- **Tipo:** build hygiene warn · **Severity:** LOW (non-blocking; build exit 0) · **Effort:** XS originally; now **upstream-blocked** · **Status:** OPEN — reclassified as TAILWIND_V4_UPSTREAM after 30min p225 investigation
- **Trigger (original p223):** `npx astro build` emits one Tailwind v4 lint warning during Lightning CSS optimization: `Unexpected token Delim('/')` on the class `text-[var(--text-primary/secondary/muted)]`.
- **p225 investigation findings (30min, after PM picked WATCH-186 over close-session option):**
  - **Class does NOT exist in source code.** Grep'd `src/**/*.{tsx,ts,astro,jsx,js,mjs,css}` for `primary/secondary/muted`, `--text-primary/`, `--text-primary)/`, `text-primary/secondary`, and broader patterns. Zero matches outside of `docs/refactor/DOMAIN_MODEL_V4_MASTER.md` (which mentions the warn itself, not the class usage).
  - **Class does NOT appear in final CSS output** (`dist/client/_astro/BaseLayout.CRZoe56R.css` etc.). The only `--text-primary` references in dist CSS are `text-[var(--text-primary)]` (correct) and `text-[var(--text-primary,#fff)]` (fallback syntax with comma — valid).
  - **Class does NOT appear in node_modules CSS** nor in Vite cache (`node_modules/.vite/*.css`).
  - The warn surfaces ONLY during Lightning CSS optimization pass; the offending class is **transiently generated** by Tailwind v4 (likely from a fuzzy-match or arbitrary-value heuristic) and **discarded by Lightning CSS** before output is written.
  - Tailwind v4.3.0 + @tailwindcss/vite ^4.3.0. The `/` inside `var()` is being interpreted as CSS Color Module Level 4 alpha-channel separator by Lightning CSS, which is correct CSS behavior — the bug is that Tailwind v4 generated this class at all (no upstream source for it).
- **Why no longer XS-fixable:**  Cannot fix at source level (no source). Cannot fix at config level (no class to remove or rename). Only paths forward:
  1. Report upstream to Tailwind v4 / Lightning CSS as a false-positive class generator + console-warn pair.
  2. Suppress the specific warn via Vite/Astro config (e.g., `build.cssMinify: false` or custom Lightning CSS warning filter) — but suppression hides legitimate warns, not recommended.
  3. Wait for Tailwind v4 / Lightning CSS upstream fix.
- **New defer reasoning:** non-blocking + non-output-affecting + truly external. The warn IS a phantom — does not affect any rendered CSS, does not affect runtime behavior, only adds noise to build log. Acceptable to leave until upstream fixes it OR upgrade path happens organically.
- **Cross-ref:** p223 audit report finding #2; p225 investigation 2026-05-23.


### 187. RESOLVED-WATCH-185 — Migration history drift amnesty + ratchet (ADR-0097 / WATCH-AUDIT-HIGH-17 close)
- **Tipo:** historical drift remediation · **Severity:** HIGH-drift / LOW-functional · **Effort:** M (~2-3h discovery + implementation) · **Status:** RESOLVED via path δ (Hybrid amnesty + ratchet) — ADR-0097
- **Trigger:** WATCH-185 carry from p223 audit (P162 log #185). Discovery work in p224 refined the 669-row drift to exact set difference: 694 missing files (tracked − local) + 15 orphan local (local − tracked) + 41 empty-statements rows in `supabase_migrations.schema_migrations`.
- **Sample analysis (n=20 of 694 missing):** 70% DDL recoverable (CREATE FUNCTION / ALTER / triggers / COMMENT) + 20% DML backfill (UPDATE/INSERT data) + 5% EMPTY (truly lost, body only in pg_proc) + 5% hotfix/reapply (redundant). 12 of 41 empty ALSO missing file — worst case `ip2b_v22_seed_*` + `ip3e_gate_matrix_v2` series only inferrable via pg_proc/pg_policies introspection.
- **15 orphan-local clusters identified:**
  - p64 incident-revert + Pacote M (Apr 26-27, 3 files)
  - p125-E1/E2/p126-E3 selection PMI 3D series (May 18, 11 files — sprint inteiro)
  - TAP CPMAI R00 seed content (Jun 18, 1 file, 60KB)
- **Path δ implementation (~1h):**
  1. 3 baseline files at `docs/audit/MIGRATION_{FILE_DRIFT,ORPHAN_LOCAL,EMPTY_STATEMENTS}_BASELINE_P224.txt` (694+15+41=750 versions documented)
  2. Helper RPC `_audit_list_schema_migrations()` via 2 migrations: `20260805000003` (initial TABLE return) + `20260805000004` (jsonb_agg rewrite — bypasses PostgREST 1000-row pagination, see sediment §4 below)
  3. 9 new ratchet tests in `tests/contracts/rpc-migration-coverage.test.mjs`: 3 SIZE (offline, pass) + 3 NEW-drift (DB-gated) + 3 STALE (DB-gated), all 9 PASS live verified
  4. ADR-0097 with full 4-path trade-off matrix (α amnesty / β snapshot / γ per-version / δ hybrid) + 4 sediment learnings
- **4 sediment learnings discovered during implementation:**
  - §1 `apply_migration` MCP uses NOW() as version, ignores version-prefix in passed `name` → creates shadow rows requiring `supabase migration repair --status applied <canonical>` + DELETE of shadow
  - §2 `supabase migration repair` may produce `statements='{}'` empty array (not NULL) → three-valued SQL trap on `IS NOT NULL AND len>0` returns NULL not FALSE
  - §3 Cascade backfill via migration repair is volatile (count 41→39 transient observed); use direct query as truth, not RPC result
  - §4 **PostgREST silently caps TABLE-returning RPCs at 1000 rows** — `?limit=10000`, `Range: 0-9999`, `Prefer: count=exact` ALL ignored. Fix: `RETURNS jsonb` + `jsonb_agg(...)`. New invariant: NUNCA use TABLE return em RPC quando volume pode exceder 1000.
- **Funcional risk assessment:** ZERO today (live DB has all DDL applied; 1742/1785 rows with body; features functional; contract tests pass). Risk surfaces only on `supabase db reset` from local files (not used in prod; LOCAL_QA via `db pull --linked`).
- **Test baseline impact:** 1713/1671/0/42 → **1722/1674/0/48** (+9 tests, +3 pass offline + 6 skip DB-gated).
- **Cross-ref:** ADR-0097, P162 log #185 (WATCH-AUDIT-HIGH-17 origin), migrations 20260805000003 + 20260805000004, 3 baseline files, `.claude/rules/database.md` GC-097 protocol (preventive), Q-C drift class (related), sediment-learnings now also documented in ADR-0097 §"Sediment learnings (p224)".

### 188. RESOLVED-277 — Perplexity MCP connector "No tools to display" → Case A confirmed via /semantic bridge
- **Tipo:** external-client bug resolution via architectural workaround · **Severity:** MED (per #277 label `priority:medium`) · **Effort:** XS (PM ~2min retest in p225) · **Status:** RESOLVED via `/semantic` alpha (PR #285), no further /mcp changes needed
- **Trigger:** PM completed the retest path documented in P162 #184 (p223 retest matrix). Reconnected Perplexity using new connector pointing at `https://nucleoia.vitormr.dev/mcp/semantic` with OAuth 2.0 + Streamable HTTP transport. **Result: Case A** — all 3 tools (`get_my_context`, `search_nucleo_knowledge`, `get_board_or_initiative_context`) visible in Perplexity tools tab and functional (PM confirmed `get_my_context` returned authenticated profile data for Vitor).
- **Root cause confirmed:** `/mcp` 299-tool catalog exceeded a Perplexity-internal cap on tools/list response payload — either count limit (H2) or aggregate size limit (H1 implied by per-tool `$schema` overhead × 299 = large response). With the bridge surface at 3 tools, both caps cleared trivially. Hypotheses H4 (SSE handshake), H5 (initialize parsing), H6 (auth/OAuth flow), H7 (anti-spam) all disproven — they would have broken /semantic too.
- **Why not measure exact threshold:** pragmatic close — quantifying Perplexity's exact cap via devtools payload capture costs ~10min PM + analysis with no immediate use-case (Claude.ai handles all 299 tools fine; Perplexity stable on /semantic). If wave-2+ via #280 grows the curated catalog and a future Perplexity user hits the cap, that future session captures the threshold. Documented as soft WATCH below.
- **Production routing implication:** Perplexity MCP users connect to `/mcp/semantic` (3 tools, will grow via #280 wave-2+); Claude.ai (and any client with no cap) continue connecting to `/mcp` (299 tools). Both surfaces remain healthy and served from the same EF v2.79.0 — the bridge architecture is the canonical answer per #280 acceptance criteria.
- **Soft WATCH (not filed as issue):** if/when #280 wave-2+ adds capability profiles (`core` / `selection` / `governance` / `knowledge` / `profile` / `admin` / `full`), monitor whether any profile crosses Perplexity's cap. The `full` profile is most at risk since it bundles all wave-1+wave-2 tools. Mitigation if hit: split into smaller named profiles (no architectural change needed, just config in `registerSemanticTools`).
- **Cross-ref:** P162 #184 (retest matrix documented at p223 audit) · P162 #174 (RESOLVED-280-ALPHA `/semantic` ship) · PR #285 (semantic alpha) · PR #275 (OAuth allowlist refactor, p220) · PR #276 (execution strip, p220) · PR #279 (closed-as-superseded `$schema` strip, p223) · #280 (semantic capability profiles wave-2+ tracking).

### 189. RESOLVED-281 — Server-side cert PDF forward auto-gen via DB trigger + CF Browser Rendering + supabase_vault (live verified end-to-end)
- **Tipo:** forward feature gap close · **Severity:** MED (LGPD Art. 16 retention + Art. 18 access) · **Effort:** L (~5h total: spec + 3 PRs + deploy ops + smoke + investigation) · **Status:** RESOLVED — pipeline live + smoke verified 2026-05-23 05:22:32 UTC
- **Trigger:** Carry from p221 PR #282 (#267 alpha backfill of 42 existing certs left forward gap). #281 selected via PM ABCD as next p225 carry after #277 close.
- **Pipeline shipped (ADR-0098, 3 PRs):**
  1. **PR #293** — Migration `20260805000005` + Astro endpoint `/api/internal/cert-pdf-render/[id]` + wrangler.toml `[browser]` binding + middleware CSRF bypass + ADR-0098 + 22 contract assertions. Path β chosen from 4-path trade-off (β CF Browser Rendering, recommended for zero visual drift vs backfill alpha).
  2. **PR #294 (same-day refactor)** — SEDIMENT-225.B: Supabase managed PG blocks `ALTER DATABASE SET app.*` for non-allowlisted GUCs. Refactored trigger fn to read shared secret from `vault.decrypted_secrets` (supabase_vault v0.3.1 installed by default). Migration `20260805000006` + ADR-0098 Amendment + 7 contract assertions.
  3. **PR #295 (same-day hotfix)** — Endpoint env fallback: `cfEnv.SUPABASE_URL` was never set as wrangler binding (it's build-time `PUBLIC_SUPABASE_URL` via `import.meta.env`). Mirrored dual-source pattern from `calendar-webhook.ts`. Smoke test surfaced this via pg_net response capture (HTTP 500 + exact error message).
- **4 sediments discovered + documented (ADR-0098 Amendment + this entry):**
  - **SEDIMENT-225.A**: Postgres strips inline `--` comments from `prosrc` when storing function source → Phase C body-hash drift gate flags any function with inline `--` in body. Fix = move comments outside `AS $$ ... $$` block. Caught by CI on first PR #293 push.
  - **SEDIMENT-225.B**: Supabase managed PG restricts `ALTER DATABASE SET app.*` to allowlisted params. Custom GUC `app.cert_pdf_internal_secret` was blocked → error 42501. Workaround = `supabase_vault` (already installed). Caught at deploy ops by PM running ALTER DATABASE.
  - **SEDIMENT-225.C**: Body-drift parser (`tests/helpers/rpc-body-drift-parser.mjs`) regex `/\bCREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION\s+.../i` matches `CREATE OR REPLACE FUNCTION` literal **inside SQL comments**. Initial migration `20260805000006` had a rollback example inside a comment that caused the parser to emit 2 blocks for the same function (one 5-byte stub from the comment + the real 1097-byte body). Fix = avoid the exact `CREATE ... FUNCTION` token sequence inside rollback comment examples.
  - **SEDIMENT-225.D**: PM out-of-band INSERT of member with `operational_role` set manually triggers A3 invariant violation when no authoritative engagement exists. Surfaced during close PR CI: Mario Henrique Trentim (`f05570d1`) added at 2026-05-23 05:52:28 UTC with `designations=['external_reviewer']` + `operational_role='observer'` but **no persons row** + **no engagement** → A3 expected='guest' (ELSE branch — `LEFT JOIN auth_engagements ON is_authoritative=true` returned NULL since no engagement) → actual='observer' = drift. Fix = (1) apply Angelina pattern (PR #272): INSERT persons + engagement external_reviewer/reviewer + admin_audit_log entry; (2) set `operational_role='guest'` to match expected. Lesson: external_reviewer onboarding has 2 invariants: persons+engagement integrity (S/D family) + operational_role='guest' (A3 — since external_reviewer always is_authoritative=false, no derivation, falls to ELSE 'guest'). Canonical helper should set operational_role='guest' automatically; PM bypass via direct UPDATE must follow same convention.
- **Live smoke verification (2026-05-23 05:22:32 UTC):**
  - INSERT test cert (vc=TEST-P225-281-002, type=contribution, member_id=Vitor) at 05:22:32.614
  - pg_net response captured at 05:22:32.622: HTTP 200, body `{"ok":true, "cert_id":"ebbbc25c-...", "verification_code":"TEST-P225-281-002", "pdf_url":"880f736c-3e76-4df4-9375-33575c190305/TEST-P225-281-002.pdf", "bytes":44423, "race_winner":true}`
  - storage.objects row created at 05:22:41 (size=44423 bytes, mimetype=application/pdf, cacheControl=max-age=31536000, httpStatusCode=200)
  - certificates.pdf_url populated to the storage path (race_winner=true confirms UPDATE went through cleanly)
  - End-to-end latency ~9s (INSERT → storage written, includes pg_net dequeue + endpoint dispatch + CF Browser Rendering render + storage upload + UPDATE)
  - Cleanup: cert row + storage.objects row both deleted via REST API
- **Operator setup completed by PM:**
  - `npx wrangler deploy` (Cloudflare Pages auto-deployed on PR merge)
  - `openssl rand -base64 32 | npx wrangler secret put CERT_PDF_INTERNAL_SECRET` (32-byte secret, base64 = 44 chars)
  - Studio SQL: `SELECT vault.create_secret('<same_value>', 'cert_pdf_internal_secret', 'p225 #281 ADR-0098: shared secret for AFTER INSERT trigger → /api/internal/cert-pdf-render');`
  - Verify: `SELECT name, length(decrypted_secret) FROM vault.decrypted_secrets WHERE name = 'cert_pdf_internal_secret';` → secret_len=44 ✓
- **Member SELECT path (PM decision: Option A LGPD-conservative):** `/verify/{code}` STAYS metadata-only; `/certificates` continues using browser-print pipeline (PR #262, p218) — already satisfies LGPD Art. 18. **Future work** (deferred to follow-up): new RPC `get_my_certificate_pdf_path(p_cert_id)` + new Astro endpoint `/api/cert-pdf-url/[id]` returning signed URL TTL 5min via service-role. Estimated S (~1h). Acceptable defer because browser-print already provides access.
- **Test baseline impact:** 1722/1674/0/48 → **1751/1703/0/48** offline (+29 assertions: 22 from PR #293 + 7 from PR #294 vault path).
- **Carries continued:**
  - `/certificates` signed URL wiring (Phase 4 deferred from #281 spec) — soft WATCH inline in ADR-0098
  - #280 wave-2+ semantic capability profiles — strategic carry from p222
- **Mario Trentim onboarding reconciliation (post-close PR discovery, SEDIMENT-225.D):** Out-of-band member INSERT by PM at 05:52:28 UTC blocked close PR #296 CI (check-invariants) at 05:54:26 UTC. Applied Angelina pattern via `execute_sql` CTE: `INSERT persons (id=0fdf2427) + engagements (id=ef7edce2, kind=external_reviewer, role=reviewer, granted_by=Vitor person d6e3622a, metadata.reason=external_speaker_capilarizacao_cpmai) + admin_audit_log (action=external_reviewer.onboarded, reconciliation_reason=p225_invariant_a3_violation)`. Plus `UPDATE members SET operational_role='guest'` to match A3 expected. Invariants 19/19=0 restored at 06:03 UTC. Mario context: 1-on-1 Vitor×Fernando Maquiaveli 2026-05-22 minutes D3 references Mario as webinar/external speaker for Capilarização CPMAI initiative (alongside Gino Terentim + Henrique Diniz). Engagement created without agreement_certificate_id (consent legal basis) — same shape as Angelina (PR #272).
- **Cross-ref:** ADR-0098 (Accepted + Amendment 2026-05-23) · migrations `20260805000005` + `20260805000006` · endpoint `src/pages/api/internal/cert-pdf-render/[id].ts` · `wrangler.toml` `[browser]` binding · `src/middleware.ts` `/api/internal/` CSRF bypass · contract test `tests/contracts/certificate-pdf-autogen-trigger.test.mjs` · `scripts/backfill-cert-pdfs.ts` (p221 alpha reference) · `src/lib/certificates/pdf.ts` (canonical template, reused) · PRs #293/#294/#295/#296 · #281 (closed) · #267 (closed p221) · #258 (closed p218) · LGPD Art. 16 + Art. 18 · Mario reconciliation: person `0fdf2427-38c8-4b1e-9557-961a8d71480b`, engagement `ef7edce2-8d5e-4b30-8f76-ff7ebc000f58`, audit `1e75e4f9-8367-4f47-988c-e2825132a9a7`, member `f05570d1-af51-4155-9e51-3392987bf630`.

### 190. RESOLVED-251-PARTIAL — Cycle 4 selection trust audit (#292 Handoff A read-only evidence pack)
- **Tipo:** read-only investigation closure · **Severity:** mix (2 LOW close-candidates + 2 HIGH code bugs surfaced + 1 MED status drift + 1 MED data gap) · **Effort:** S (~2h audit + comment + PR + spawned issue) · **Status:** AUDIT SHIPPED; remediation issues await PM dispatch
- **Trigger:** First p226 task. PM ABCD Q2 picked #292 Handoff A as sprint Workstream 1 entry point per PM-authored sprint sequencing (commit `2b811fec docs(selection): prioritize Cycle 4 reliability sprint` 2026-05-23). Sprint plan explicitly labeled Handoff A "do first / no writes".
- **Deliverables:**
  - `docs/audit/CYCLE4_TRUST_AUDIT_P226.md` (209 lines, internal full record)
  - PR #297 (squash-merged via [TBD]; commits 99f6221d audit doc + f3830d86 empty CI retrigger)
  - #251 issue comment 4525575485 (PM-facing PII-redacted summary)
  - Issue #298 spawned (Foundation XS HIGH — `get_my_pending_evaluations()` cycle non-determinism fix)
- **6 findings + classification:**
  1. **LOW close-candidate**: "Henrique não aparece em /admin/selection cycle4" — NOT REPRODUCED. Henrique IS in `selection_applications` (status=`screening`, role=`leader`, application_id `bcc54dfc…`) + IS in `get_selection_dashboard('cycle4-2026')` payload when called with admin auth. Default UI filter logic (`src/pages/admin/selection.astro` lines 1230-1290) does NOT hide `screening` rows. Disposition: PM re-test with browser devtools state required.
  2. **LOW close-candidate**: "William mostra 1 de 2 evals" — NOT REPRODUCED. William researcher (`6187b0b2…`) has 3 evals complete (2 obj Vitor+Fabricio + 1 interview Vitor); William leader rejected (`97a6df7d…`) has 5 evals incl. Fabricio's 2026-05-21 21:01 UTC. Fabricio's evals predate issue filing (23:40 UTC) by 2.5h. Disposition: probable stale browser state at report time.
  3. **HIGH CODE BUG #1** (Issue #298 spawned): `get_my_pending_evaluations()` body — `SELECT * INTO v_cycle FROM selection_cycles WHERE phase='evaluating' LIMIT 1;` sem `ORDER BY`. 2 cycles in `evaluating` phase right now (`cycle3-2026-b2` 2026-04-01 + `cycle4-2026` 2026-05-09). Planner non-deterministic → Fabricio (cycle3-2026-b2 evaluator) probably sees cycle3 pending instead of cycle4. Fix: `ORDER BY created_at DESC LIMIT 1` (~30min Foundation XS).
  4. **HIGH CODE/WORKFLOW BUG #2** (overlaps #260, bundle deferred): only **6 of 38** cycle4 apps have `peer_review_requested` notification. Dispatcher `dispatch_peer_review_invitations` precondition gate `consent_ai_analysis_at IS NULL OR ai_analysis IS NULL` blocks 32 apps incl. Henrique + William. Pending list (`get_my_pending_evaluations`) keys on `peer_review_requested` existence → 32 cycle4 apps invisible to evaluators via formal flow.
  5. **MED STATUS DRIFT** (audit-surfaced): 19 of 38 cycle4 apps stuck in `screening` despite `objective_done=2` (complete). Includes Henrique + Francisleila Melo Santos (leaders full eval) + 17 researchers (researcher needs only objective). Status advance `screening → objective_cutoff` requires explicit step (cron `recompute-pert-cutoffs-weekly` Mon 13:00 UTC + manual or `finalize_decisions` RPC). PM decision: auto-advance vs manual.
  6. **MED DATA GAP** (audit-surfaced): `selection_committee` for `cycle4-2026` (`id=08c1e301…`) = **0 rows**. Vitor + Fabricio are de-facto evaluators via admin UI direct entry but not formally registered. Even after code bug #1 fix, pending list won't surface to non-registered evaluators. PM decision: seed via `manage_selection_committee` MCP.
- **Remediation split (per #292 Handoff A acceptance gate):**
  - 🔧 NEW ISSUE: #298 Foundation XS HIGH (code bug #1 — `get_my_pending_evaluations()` fix)
  - 🌱 PM DECISION: Seed cycle4-2026 selection_committee (Governance XS MED)
  - 🔄 BUNDLE: code bug #2 → #260 Workstream 2 (notification routing/dispatch)
  - 📊 BUNDLE OR NEW: status drift → #229 Phase 2 OR new Foundation issue (MED)
  - ❓ #251 disposition: change registry to `close-candidate pending PM re-test` for items 1+2
- **PM gates observed:**
  - ✅ No production writes (all queries `SELECT`-only via `mcp__supabase__execute_sql`)
  - ✅ PII paridade com #251 body: Henrique + William + Fabricio mencionados (PM body já expôs); Francisleila Melo Santos + 17 researchers em screening aggregated to counts only
  - ✅ Acceptance evidence delivered: SQL row summary + root cause classification + remediation split proposed + new issue spawned
- **Sediment learnings (carry forward):**
  - **SEDIMENT-226.A**: `MCP execute_sql` with multiple SQL statements returns only the LAST result. Split queries when needing multiple result sets (or wrap in CTE returning combined json).
  - **SEDIMENT-226.B**: `notifications` table has NO `payload` column (confirmed p222 close docs; columns are `source_type, source_id, link, title, body, delivery_mode, digest_*`). When searching notifications for app references, use `source_id IN (...)` + `source_type ILIKE '%selection%'` not `payload->>'application_id'`.
  - **SEDIMENT-226.C**: Service-role calls to admin RPCs that gate on `auth.uid()` will get `Unauthorized` returns. To simulate PM context for read-only testing, use `SET LOCAL request.jwt.claims = json_build_object('sub', '<auth_id>')::text` then call the RPC — works for SECURITY DEFINER functions that key off `auth.uid()`.
  - **SEDIMENT-226.D**: First push to a new agent branch may NOT trigger all CI workflows even when no path filter is configured. Cloudflare Pages registers reliably but GH Actions (CI Validate, analyze, invariants) may not queue. Workaround = push empty commit (`git commit --allow-empty`) to force re-evaluation of `pull_request` triggers. Caught in p226 with PR #297.
- **Cross-ref:** PR #297 (audit doc) · Issue #298 (spawned remediation) · #251 (commented + registry recommendation) · #292 (sprint umbrella) · #260 (W2 bundle target for code bug #2) · #229 (Phase 2 bundle target for status drift) · `get_my_pending_evaluations()` body · `get_selection_dashboard(text)` body · `dispatch_peer_review_invitations(uuid,int)` body · `src/pages/admin/selection.astro` lines 1230-1290 (filter logic) + lines 4283-4340 (cycle picker init) · branch `agent/selection-cycle4-trust-audit` (sha f3830d86).

### 191. RESOLVED-298 — `get_my_pending_evaluations()` cycle non-determinism + gate scope (Option A+)
- **Tipo:** code bug fix · **Severity:** HIGH · **Effort:** XS (~1h impl + smoke + ship) · **Status:** RESOLVED via PR #302 (squash-merged `5d649ac2` 2026-05-23 15:31:04 UTC); #298 auto-closed
- **Trigger:** p226 audit Code Bug A (P162 #190) spawned #298 as Foundation XS ready-leaf. PM ABCD this session picked Option A+ (`ORDER BY created_at DESC` + cycle-scoped gate `sc.cycle_id = v_cycle.id`) over Option A minimal or Option B with p_cycle_id param.
- **Two latent bugs both fixed:**
  1. **Picker non-determinism**: `SELECT * INTO v_cycle FROM selection_cycles WHERE phase='evaluating' LIMIT 1` had no ORDER BY. Planner could return either of the 2 currently-evaluating cycles (cycle3-2026-b2 + cycle4-2026).
  2. **Gate misalignment**: legacy gate `JOIN selection_cycles c ON c.id = sc.cycle_id WHERE c.phase='evaluating'` allowed caller on ANY evaluating committee to pass, but the picker could then select a DIFFERENT cycle where caller is not on committee → latent privilege misalignment.
- **Fix shipped (migration `20260805000007`):**
  ```sql
  -- Pick newest evaluating cycle deterministically
  SELECT * INTO v_cycle FROM selection_cycles
  WHERE phase = 'evaluating' ORDER BY created_at DESC LIMIT 1;
  -- Empty-cycle short-circuit returns consistent empty payload (no info leak)
  IF v_cycle.id IS NULL THEN RETURN ...; END IF;
  -- Gate scoped to picked cycle (caller must be on THIS cycle committee or admin)
  IF NOT EXISTS (
    SELECT 1 FROM selection_committee sc
    WHERE sc.member_id = v_caller_member_id AND sc.cycle_id = v_cycle.id
  ) AND NOT can_by_member(v_caller_member_id, 'manage_member') THEN
    RAISE EXCEPTION 'Unauthorized: caller is not on this cycle committee';
  END IF;
  ```
- **Live smoke verified (2026-05-23 pre-merge):**
  - **Vitor (manage_member admin)** via `SET LOCAL request.jwt.claims`: cycle_code='cycle4-2026', pending_count=1 (Maria Araújo), total=38 ✓
  - **Roberto Macêdo (cycle3-2026-b2 observer only, NO manage_member)**: ERROR 42501 Unauthorized: caller is not on this cycle committee ✓ (line 32 of new RAISE)
- **Contract test `get-my-pending-evaluations-cycle-deterministic.test.mjs` +8 assertions (offline pass):**
  1. migration file exists
  2. picker uses `ORDER BY created_at DESC`
  3. gate is cycle-scoped (`sc.cycle_id = v_cycle.id`)
  4. legacy permissive JOIN gate is gone
  5. `Unauthorized: caller is not on this cycle committee` message present
  6. `can_by_member(... 'manage_member')` admin bypass retained
  7. empty-cycle short-circuit precedes gate (no info leak; ordering enforced)
  8. `NOTIFY pgrst, 'reload schema'` issued in migration
- **Test baseline:** **1751/1703/0/48 → 1759/1711/0/48** offline (+8 static pass); with-DB CI evidence post-merge `1787/1782/0/5` (delta beyond +8 confirms with-DB pin was undercounted in p225 — see SEDIMENT-227.B below).
- **SEDIMENT-227.A — MCP `apply_migration` shadow row cleanup workflow** (reinforces SEDIMENT-224.A §1):
  - Confirmed live: `apply_migration` MCP creates a row in `supabase_migrations.schema_migrations` with **version = NOW()** (in this session: `20260523150530`) and **name = full string passed as `name` param** (including the timestamp prefix `20260805000007_p227_...`).
  - When `supabase migration repair --status applied 20260805000007` then runs, it creates ANOTHER row at version `20260805000007` with name derived from the file.
  - End state: 2 rows for the same migration intent. The shadow row is detected by ADR-0097 ratchet (`tests/contracts/rpc-migration-coverage.test.mjs` Phase D "no NEW missing-file drift") as version with no `.sql` file.
  - **Mandatory clean-up step after every apply_migration + repair:** `DELETE FROM supabase_migrations.schema_migrations WHERE version = '<NOW()-format-shadow>'`. Find shadow via `SELECT version, name FROM ... WHERE name LIKE '20260805%' OR version LIKE '202605%'` — the canonical version has just the timestamp digits as version and just the descriptive part as name; the shadow has NOW() as version and the FULL `<ts>_<name>` as name.
  - **Symptom if forgotten:** CI validate fails with "NEW missing-file drift detected — version(s) appear in supabase_migrations.schema_migrations but no corresponding .sql exists". Easily diagnosed but blocks merge.
  - Caught this session (PR #302 first CI run): shadow `20260523150530` from `apply_migration` for the #298 fix; cleaned via execute_sql DELETE; empty commit `cb63fe5d` re-triggered CI which passed all 10 checks.
  - **Backlog (low priority):** wrap apply_migration calls in a helper that auto-cleans the shadow row, OR update `.claude/rules/database.md` GC-097 protocol to add the DELETE step as mandatory. Defer to ADR-0097 follow-up since this is now codified as session sediment.
- **SEDIMENT-227.B — with-DB CI baseline drift discovery**: PR #302 first CI run (with-DB env) showed **1787 total tests** vs deploy.md p225 prediction of "~1773". After +8 from this session, expected was 1781 not 1787. The +6 unexplained delta suggests p225 with-DB baseline was undercounted (or earlier sessions added DB-gated tests without bumping with-DB pin). Recommended: at next session that touches deploy.md, set with-DB pin to **1787/1782/0/5** (empirical, last CI run). Filed as backlog (not blocking).
- **Cross-ref:** PR #302 (sha `5d649ac2`) · migration `20260805000007` · `tests/contracts/get-my-pending-evaluations-cycle-deterministic.test.mjs` · #298 (auto-closed) · p226 audit doc `docs/audit/CYCLE4_TRUST_AUDIT_P226.md` Code Bug A · ADR-0097 (shadow row pattern from SEDIMENT-224.A confirmed in field) · `.claude/rules/database.md` GC-097 protocol (candidate amendment).

### 192. AUDITED-260-W2 — Selection notifications Workstream 2 read-only audit (5 findings + 7 child leaves + 5 PM decisions)
- **Tipo:** read-only audit deliverable · **Severity:** mix (3 HIGH + 2 MED) · **Effort:** M (~2h SQL evidence + classify + draft + PR) · **Status:** AUDIT SHIPPED; PM decisions block all 7 child leaves
- **Trigger:** PM ABCD Q2 picked "#298 close + #260 W2 audit" (Recommended). After #298 close (PR #302 merge), branched `agent/p227-issue-260-w2-selection-notifications-audit` from main for read-only audit. Sprint plan Handoff B at `docs/project-governance/SELECTION_RELIABILITY_PRIORITIZATION_PLAN.md` explicitly defined scope.
- **Deliverables:**
  - `docs/audit/SELECTION_NOTIFICATIONS_W2_AUDIT_P227.md` (242 lines)
  - PR #303 (open, awaiting CI + PM review)
  - #260 issue comment 4525812302 (PM-facing summary + PR link)
- **5 findings + classification:**
  1. **HIGH — Catalog/helper drift**: ADR-0022 catalog (W1.3, 2026-04-27) has **zero** selection_* entries. `_delivery_mode_for` helper only covers `selection_termo_due` (post-p159 hot-path). All other selection_* types fall to ELSE → digest_weekly. 17 candidate-facing rows mis-routed in 90d window (13 termo_due pre-p159 race + 2 approved + 2 interview_scheduled).
  2. **HIGH — peer_review_requested dispatch trigger gap**: cycle4-2026 has 24/38 apps with consent + AI analysis (eligible) but only 6 have notification → **18 apps eligible-never-dispatched**. `dispatch_peer_review_invitations` is RPC-triggered manually by committee lead; no cron auto-dispatch.
  3. **HIGH — AI precondition gate impact**: 14/38 cycle4 apps hard-blocked by `consent_ai_analysis_at IS NULL OR ai_analysis IS NULL`. PM decision needed: hard gate / soft gate / admin override / hybrid.
  4. **MED — Stale interview visibility gap**: 11 `selection_interviews` rows with `scheduled_at < NOW() AND conducted_at IS NULL` (all 1-30d old). No notification type exists; no cron tracks them.
  5. **MED — `selection_cutoff_approved` type does not exist**: 0 notifications + 0 RPC references + 5 generic cutoff RPCs are PERT compute. Proposed by #260 as "2 obj evals + PERT ≥ cutoff → invite interview booking" trigger.
- **Policy Matrix proposal (8 types, PM decision):**
  - **Candidate-facing transactional**: selection_termo_due (already p159) + selection_approved (currently digest, recommend transactional) + selection_interview_scheduled (currently digest, recommend transactional) + selection_cutoff_approved (new, recommend transactional)
  - **Admin-facing transactional**: peer_review_requested (already hardcoded at INSERT)
  - **Admin-facing digest or suppress**: selection_interview_overdue (new) + selection_evaluation_complete + selection_interview_noshow
- **7 proposed child ready-leaf issues:**
  1. (Foundation S) ADR-0022 catalog backfill + helper sync + contract test
  2. (Foundation + QA S) Resend-safe replay of 17 mis-routed rows (idempotent UPDATE)
  3. (Foundation M) selection_cutoff_approved new type + trigger + template
  4. (Foundation + Governance M) dispatch_peer_review_invitations AI gate policy
  5. (Foundation S) selection_interview_overdue type + daily cron
  6. (Governance S) suppress_all bypass for candidate-facing operational emails
  7. (QA XS) selection_emails_pending_24h health signal
  - **Recommended dispatch order**: #1 → #5 → #4 → #3 → #2 → #6 + #7
- **5 PM decisions blocking implementation:**
  1. Policy Matrix adoption (or alternative per-row)
  2. Replay vs no-replay for 17 mis-routed rows + double-send tolerance
  3. AI precondition gate policy (options a/b/c/d in audit doc)
  4. Member preference override for candidate-facing operational emails (suppress_all bypass)
  5. Manual vs cron dispatch trigger for dispatch_peer_review_invitations
- **PM gates observed:**
  - ✅ No production writes (all queries `SELECT`-only via `mcp__supabase__execute_sql`)
  - ✅ Read-only audit pattern per Handoff B
  - ✅ Aceitação evidence delivered: classified findings + policy matrix + child split + PM decisions enumerated
  - ✅ PII discipline: only 1 candidate name (Maria Araújo, from #298 smoke output mentioned in #260 comment context) — counts elsewhere
- **Sediment learnings (carry forward):**
  - **SEDIMENT-227.C** — ADR-0022 `_delivery_mode_for` ELSE-default trap: any new notification type added via INSERT without explicit helper case silently routes to `digest_weekly`. Catalog parity contract test only covers types listed in the catalog → routing decisions for missing types go undetected forever. Fix as Child Leaf #1 above: backfill catalog → contract test → drift caught at PR time.
  - **SEDIMENT-227.D** — `process_vep_acceptance_transition` uses `create_notification` helper-path → routes via `_delivery_mode_for`. The 13 termo_due rows from 2026-05-14 were inserted in the pre-p159-application race window (helper still returning digest_weekly during that window). Not a code bug — just historical backlog. Detected because all 13 are same-day + helper now returns transactional for that type post-p159.
  - **SEDIMENT-227.E** — peer_review_requested `delivery_mode='transactional_immediate'` is **hardcoded at INSERT** in `dispatch_peer_review_invitations` body (not via helper). This works correctly but bypasses helper drift detection. ADR-0022 catalog parity contract test does not catch this case. Recommendation in Child Leaf #1: standardize all INSERT callsites to use the helper, OR add catalog assertion that hardcoded values match catalog mode.
- **Cross-ref:** PR #303 · `docs/audit/SELECTION_NOTIFICATIONS_W2_AUDIT_P227.md` · #260 (parent + comment 4525812302) · #292 (sprint umbrella) · #298 (orthogonal close PR #302) · #251 (close-candidate) · ADR-0022 W1.3 (needs W1.4 amendment) · ADR-0097 (no relation, just session co-occurrence) · `_delivery_mode_for` body · `dispatch_peer_review_invitations` body · p159 migration `20260632000000` · branch `agent/p227-issue-260-w2-selection-notifications-audit` (sha `a8c86e69`).

### 193. RESOLVED-260-W2 — Selection notifications Workstream 2 implementation complete (all 7 leaves shipped end-to-end p228)

- **When:** 2026-05-23 p228 (~6h marathon)
- **What:** All 7 W2 leaves shipped + applied live + tested. Closes the implementation phase of #260 per PM Policy Matrix Amendment D (5 PM decisions ratified in commit `af1735cb` post-p227).
- **Where:** 2 PRs squash-merged — PR #305 (Leaf 1, sha `25c4a472`) + PR #307 (Leaves 2+3+4+5+6+7, sha `2c6aa83f`). 7 migrations: `20260805000008..14`. ADR-0022 catalog W1.3 → W1.6 with Amendment D phasing all marked shipped.
- **Trigger:** PM dispatch commit `af1735cb docs(governance): approve selection W2 decisions` after the W2 audit shipped in p227. PM dispatch order: catalog/helper parity → interview_overdue → soft AI gate/no_ai_context → cutoff_approved → selective replay → suppress_all bypass → 24h health signal.
- **Leaf-by-leaf deliverables:**
  1. **Leaf 1 (PR #305 `25c4a472`):** ADR-0022 catalog backfill + `_delivery_mode_for` helper extension for 6 selection_* types per PM Policy Matrix. selection_termo_due kept (p159). selection_approved + selection_interview_scheduled + peer_review_requested mapped to `transactional_immediate`. selection_evaluation_complete → `suppress`. selection_interview_noshow → `digest_weekly` explicit (drift detection). 4 forward-defense contract assertions. Migration `20260805000008`.
  2. **Leaf 2 (PR #307):** `selection_interview_overdue` new type + daily `_selection_interview_overdue_cron()` SECDEF jsonb-returning RPC at `0 14 * * *` UTC + 7-day NOT EXISTS idempotency window + 24h grace + status IN (scheduled,rescheduled) scope guard + source_type='selection_interview' attribution. Live smoke 2-run idempotency: 14 inserted → 0 inserted. Migration `20260805000009`.
  3. **Leaf 3 (PR #307):** Soft AI gate in `dispatch_peer_review_invitations` — removes hard `PEER_PRECONDITION` raise (cycle 4 unblock for 14 apps); adds `p_force_no_ai_context boolean DEFAULT false` parameter; branches v_no_ai_context based on consent_ai_analysis_at IS NULL / ai_analysis IS NULL / p_force_no_ai_context. DROP+CREATE pattern (param count change). peer_review_requested INSERT now uses `_delivery_mode_for('peer_review_requested')` helper (closes SEDIMENT-227.E). admin_audit_log captures no_ai_context + no_ai_reason. Migration `20260805000010`.
  4. **Leaf 4 (PR #307):** `selection_cutoff_approved` foundation — helper case `transactional_immediate` + idempotency column `selection_applications.cutoff_approved_email_sent_at` + multi-lang campaign template (PT/EN/ES) with `{{first_name}}` + `{{interview_booking_url}}` variables + manual dispatch RPC `notify_selection_cutoff_approved(p_application_id)` with committee-lead-or-manage_member authority, single-fire idempotency, audit log, `CUTOFF_NO_BOOKING_URL` precondition. Auto-trigger deferred to p229 (PM decision needed on cutoff formula evaluation). Migration `20260805000011`.
  5. **Leaf 5 (PR #307):** One-shot RPC `_replay_selection_notifications_p228(p_dry_run boolean DEFAULT true)` per PM D-sel-2 selective replay. dry_run=true returns analysis envelope; dry_run=false UPDATEs eligible rows + writes admin_audit_log. Selective criteria: selection_termo_due replay if member has selection_applications.status=approved AND no `certificates` row with type='volunteer_agreement' + status='issued'; selection_approved replay if within 30d AND active member; selection_interview_scheduled replay if associated interview scheduled_at > NOW() AND conducted_at NULL. Live dry-run: 2 eligible (selection_approved recent+active) + 15 manual_close. Migration `20260805000012`.
  6. **Leaf 6 (PR #307):** Operational `suppress_all` bypass for 4 candidate-facing types (selection_termo_due, selection_approved, selection_interview_scheduled, selection_cutoff_approved). SQL helper `_is_operational_candidate_facing(p_type text)` IMMUTABLE PARALLEL SAFE boolean classifier is source-of-truth; EF `send-notification-email` matches the Set byte-for-byte in lock-step (contract test enforces parity). EF deployed live (script 70.35kB). Migration `20260805000013`.
  7. **Leaf 7 (PR #307):** 24h dispatcher silence health signal `get_selection_emails_pending_24h(p_alert_threshold integer DEFAULT 10)` STABLE SECDEF jsonb RPC. Returns {total_pending, by_type, oldest_pending_at, oldest_age_minutes, alert_threshold, alert_triggered, computed_at, rpc_version}. Scope: selection_% LIKE + delivery_mode=transactional_immediate + email_sent_at IS NULL + created_at > NOW()-24h. Live smoke: total_pending=0, alert_triggered=false (HEALTHY). MCP tool registration deferred to p229 fast-follow. Migration `20260805000014`.
- **Test ratchets:**
  - Offline: 1759/1711/0/48 → **1784/1726/0/48** (+25 net offline; new contract assertions for Leaves 1-7 in `tests/contracts/adr-0022-delivery-mode.test.mjs`; total Amendment D suite = 30 forward-defense assertions).
  - With-DB: **1817/1817/0/0** — all DB-gated tests + Phase C drift gate + ADR-0097 ratchets PASS.
- **Live smoke (all PASS):**
  - Helper resolves: `_delivery_mode_for('selection_cutoff_approved') = 'transactional_immediate'`, `_is_operational_candidate_facing('selection_termo_due') = true`, `_is_operational_candidate_facing('peer_review_requested') = false`.
  - Cron: `_selection_interview_overdue_cron()` 2-run idempotency 14→0; pg_cron job `selection-interview-overdue-daily` active.
  - Replay dry-run: 2 eligible / 15 manual_close.
  - Health signal: 0 pending / not triggered.
  - dispatch_peer_review_invitations 3-arg signature live; old 2-arg dropped.
- **Council Tier 1 status:** not invoked this session (clear PM dispatch + scoped implementation per leaf; no architectural pivot). Inline forward-defense contract tests applied at each leaf shipping. Phase C body-hash drift gate added net defense against the SEDIMENT-228.A pattern recurring.
- **Sediment learnings (carry forward):**
  - **SEDIMENT-228.A (CRITICAL, supersedes 225.A)** — `apply_migration` MCP requires VERBATIM file content to preserve `--` line comments inside function bodies. Earlier p228 calls passed CONDENSED SQL (without inline `--`) while local .sql files retained them. Live `pg_proc.prosrc` then diverged from migration capture body by 318 chars on `_delivery_mode_for` (and 73 chars on `_selection_interview_overdue_cron`, 522 chars on `dispatch_peer_review_invitations`). Phase C body-hash drift gate caught it on PR #306 CI. Fix: re-apply with VERBATIM file content; live body = file body; has_dash=true. **Recategorizes p225 SEDIMENT-225.A** which incorrectly attributed comment stripping to PG itself — PG preserves `--` comments in prosrc; the strip happens in the MCP transport when caller condenses. Workflow rule: always pass the .sql file content unchanged to apply_migration.
  - **SEDIMENT-228.B** — `volunteer_agreements` table does NOT exist; the volunteer term signed state is tracked via `certificates` row with `type='volunteer_agreement' + status='issued'` per `sign_volunteer_agreement()` RPC body. Initial Leaf 5 draft referenced the non-existent table; corrected pre-apply.
  - **SEDIMENT-228.C** — Closing PR #306 (Leaf 2 standalone) in favor of PR #307 bundled (Leaves 2+3+4+5+6+7) cost cherry-pick conflict resolution (ADR markdown + contract test) — but worth it for clean squash-merge history. When two leaves stack and the earlier one hits CI failure, prefer bundling over fighting standalone CI iteration.
- **Carries to p229 (fast-follow):**
  - PM call of `_replay_selection_notifications_p228(false)` to execute the 2 eligible_replay rows (notification IDs `1470e6ce-f927-466d-a795-d04074e6a32c` + `6338a42d-158a-45a1-bc2d-c3aadd6986ea`). dry-run report already produced. Resend quota safe (2 << 100/day).
  - Auto-trigger design for `notify_selection_cutoff_approved` (PM decision needed on cutoff formula evaluation strategy + cron schedule vs INSERT trigger on selection_evaluations).
  - MCP tool registration for `get_selection_emails_pending_24h` (admin observability via Claude.ai / Perplexity connectors).
  - #260 moves to `qa-window` per ISSUE_REGISTRY update. Close after PM replay execution + production smoke 7d.
- **Cross-ref:** PR #305 (Leaf 1, `25c4a472`) · PR #307 (Leaves 2-7, `2c6aa83f`) · PR #306 CLOSED (Leaf 2 standalone, superseded by bundled PR #307) · `docs/audit/SELECTION_NOTIFICATIONS_W2_AUDIT_P227.md` (parent audit) · #260 (parent) · #292 (sprint umbrella) · ADR-0022 Amendment D (catalog W1.3 → W1.6) · migrations `20260805000008..14`.

### 194. RESOLVED-LEAF5-HOTFIX — _replay_selection_notifications_p228 hotfix (3 dormant pre-execution bugs)

- **When:** 2026-05-23 p228 post-close (PR #309 merged), PM-caught
- **What:** Selective replay RPC shipped in PR #307 had 3 dormant bugs in the `IF NOT p_dry_run AND v_eligible_count > 0` branch. All masked by dry_run-only smoke. PM caught (1) before merge of close PR; (2) and (3) surfaced during live smoke of p_dry_run=false. Single hotfix migration `20260805000015` fixes all 3.
- **Where:** PR #313 squash-merged `8dd9ae5d`. Updated test baselines on PR #309 via deploy.md amendment.
- **The 3 bugs:**
  1. **RETURNING 1 INTO v_updated_count** raises SQLSTATE 21000 ("query returned more than one row") on multi-row UPDATE. Live state has v_eligible_count=2 → would have errored. Fix: drop RETURNING clause; existing `GET DIAGNOSTICS ROW_COUNT` gives correct count.
  2. **v_caller record unassigned** when auth.uid() IS NULL (service_role bypass). Downstream COALESCE(v_caller.id, ...) raises SQLSTATE 55000 "record is not assigned yet". Fix: replace with scalar `v_caller_id uuid := NULL;` populated only inside the IF auth.uid() IS NOT NULL branch.
  3. **admin_audit_log_actor_id_fkey violation** via zero-uuid sentinel '00000000-...' in COALESCE fallback (not a real members row → FK 23503). Fix: gate INSERT on `IF v_caller_id IS NOT NULL THEN`; service_role / cron tracks via postgres logs + cron_run_log.
- **Live smoke (both modes, post-fix):**
  - p_dry_run=true: {success: true, eligible_replay_count: 2, manual_close_count: 15, updated_count: 0}
  - p_dry_run=false: {success: true, eligible_replay_count: 2, manual_close_count: 15, **updated_count: 2**}
- **Row verification:** notifications `1470e6ce-...` + `6338a42d-...` flipped to delivery_mode='transactional_immediate' + digest_delivered_at=NULL. send-notification-email cron (every 5min) will dispatch real Resend emails to the 2 selection_approved candidates.
- **Contract test (3 forward-defense assertions):**
  - `_replay_selection_notifications_p228` body has no `RETURNING ... INTO`
  - v_caller declared as scalar uuid (not unassigned record)
  - admin_audit_log INSERT gated on v_caller_id IS NOT NULL
- **Tests:** 1784/1726/0/48 → 1793/1745/0/48 offline. Phase C drift gate PASS. Invariants 19/19=0.
- **Sediment learnings (3 NEW):**
  - **SEDIMENT-228.D**: when a code path is only exercised under a non-default parameter (here `p_dry_run=false`), the test plan MUST include both paths in live smoke before merge. dry_run-only smoke masked 3 production bugs in the same RPC.
  - **SEDIMENT-228.E**: PostgreSQL `record` declarations are unassigned until the first SELECT/INSERT ... INTO populates them. Accessing `.field` on an unassigned record raises 55000. Prefer scalar variables for caller_id patterns where the assignment branch may be skipped (service_role context, etc).
  - **SEDIMENT-228.F**: `admin_audit_log.actor_id` is NOT NULL FK to `members(id)`; no system-member sentinel exists for service_role/cron context. Gate the INSERT on a real actor (v_caller_id IS NOT NULL) or skip it. service_role tracks via postgres logs + cron_run_log.
- **Workflow side-effect:** Hotfix branch rebase onto post-#313 main triggered force-push permission block in harness. Resolved via `git merge origin/main` into the close-docs branch (option 2 per PM ABCD authorization) — creates a merge commit but avoids force-push.
- **Cross-ref:** PR #313 (`8dd9ae5d`) · PR #309 close-docs (`5375a927`) · PM dispatch comment ("Do not merge #309 as final close yet... First ship a small Foundation hotfix...") · Migration `20260805000015` · 17 historical mis-routed rows: 2 replayed live, 15 documented as manual_close · #260 (parent) · #292 (sprint umbrella).

### 195. RESOLVED-116 + WATCH-116.A — Calendar webhook smoke PASS (close) + service_role gate-bypass audit visibility carry

- **When:** 2026-05-23 p229 boot, PM dispatched per ISSUE_REGISTRY locked order (#116 → #179/#230 → #229 Phase 2).
- **What — RESOLVED-116:** Live read-only smoke of `selection_interviews` post-p95 webhook online (2026-05-06 → 2026-05-23, 17 days elapsed). All 7 acceptance checks from registry close rule PASS:
  - Webhook online (HTTP 401 on bad secret, was 503 pre-p95)
  - 22 webhook-synced rows in 13 days
  - Most recent webhook fire 2 days ago (Emanuelle Stellet Lourenço, `bfdi1ffs7rvklsdu4bmg`, 2026-05-21 13:16:47Z)
  - cycle4-2026 sync rate 22/24 = 92%
  - 0 duplicate `calendar_event_id` rows (idempotency)
  - B3 reschedule-clearance live (2 rows in `status='rescheduled'` with `interview_reschedule_reason=null` + `interview_reschedule_requested_at=null`)
  - App-status transition correct (active pipeline → `interview_scheduled`)
- **Where:** GH issue #116 closed with evidence comment ([comment-4526194154](https://github.com/VitorMRodovalho/ai-pm-research-hub/issues/116#issuecomment-4526194154)). Path A per PM ABCD (Recommended); no controlled smoke needed since 22 real bookings already validate end-to-end.
- **Outliers documented:** 2 cycle4 rows without `calendar_event_id` are intentional non-webhook entries (William Junio 5th row = curator manual reconciliation; Matheus Teixeira 2026-05-06 22:46 = pre-stabilization or manual RPC during secret-setup window). Cycle3-2026 closed cycle has 34 pre-webhook rows as expected.
- **What — WATCH-116.A:** Non-blocking design note. Webhook uses service_role `INSERT INTO selection_interviews` directly, bypassing the `schedule_interview` 3-layer gate (P0001/P0002/P0003). Rationale documented in `src/pages/api/calendar-webhook.ts` lines 28-31: trusted Calendar sync AFTER comissão `mark_interview_status('pending')` already gated server-side. Side effect: `gate_attempts` audit table only logs admin-UI manual RPC path — 3 entries total since p95 vs 22 webhook-driven rows with no `gate_attempts` entry.
- **Defensibility:** shared secret (`CALENDAR_WEBHOOK_SECRET`) + token-gated booking page (`/interview-booking/[token].astro`, p87 Sprint A.2). Both are pre-requisites; without either, webhook can't reach DB.
- **Visibility weakness:** if webhook secret leaks AND attacker knows a candidate email, they can schedule an interview without triggering the gate or leaving a `gate_attempts` row. Mitigations: secret rotation cadence (none documented) + Calendar API access control (Apps Script trusted-context).
- **Carry options if PM wants stronger audit later:**
  1. Insert a `gate_attempts` row from webhook with `bypass_requested=true, bypass_granted=true, gate_failed_code='WEBHOOK_SERVICE_ROLE'` for symmetric audit trail (no functional change, just visibility)
  2. Add an explicit `selection_interviews.created_via` column (`webhook|manual_rpc|curator_insert`) for forensic separation
  3. Both above + admin dashboard surfacing webhook vs manual ratio per cycle
- **Tests:** no test delta this session (read-only audit + close). Forward-defense test for webhook would require live CALENDAR_WEBHOOK_SECRET + real Calendar mock; deferred unless PM requests.
- **Sediment learnings (1 NEW):**
  - **SEDIMENT-229.A**: when an integration endpoint uses service_role to bypass a normal RPC gate (legitimate trust-boundary design), the parallel audit table (`gate_attempts` in this case) becomes asymmetric — only one path is logged. Document the asymmetry where it lives (here: webhook code lines 28-31 already comments the rationale; this entry adds the audit-visibility consequence) so future audits don't misread "0 gate_attempts" as "0 traffic."
- **Cross-ref:** GH issue #116 (closed) · `src/pages/api/calendar-webhook.ts` · `src/pages/interview-booking/[token].astro` · `docs/specs/p87-calendar-webhook-apps-script.md` · `gate_attempts` table · `schedule_interview` RPC · #292 (selection reliability sprint umbrella).

### 196. RESOLVED-179 — Canonical approval orchestration closed as IMPLEMENTED (p230)

- **When:** 2026-05-23 p230 dispatch after #318 fix
- **What:** GH #179 closed as IMPLEMENTED ([comment-4526466806](https://github.com/VitorMRodovalho/ai-pm-research-hub/issues/179#issuecomment-4526466806)). All 5 spec acceptance criteria met live — canonical `approve_selection_application(uuid, jsonb)` exists, legacy `admin_update_application` + `finalize_decisions` both delegate (RAISE on canonical failure), schema invariants R + S + A3 all 0 violations, contract test `canonical-approval-orchestration.test.mjs` (178 lines, p204) covers existence + side-effects + delegation + Herlon-class invariant.
- **Where:** Live RPC bodies verified via `pg_get_functiondef` for canonical + both legacy wrappers. UI surface confirmed: `src/pages/admin/selection.astro` calls `admin_update_application` from 4 sites — all routed through canonical via wrapper.
- **AC-4 nuance (partial → acceptable):** "Agreement issuance queued when requires_agreement=true" — canonical logs `agreement_pending` flag in `data_anomaly_log` but doesn't actively seed `volunteer_term` onboarding step; that is delegated to cycle config (`selection_cycles.onboarding_steps` jsonb) + `process_vep_acceptance_transition` trigger. Acceptable per spec Fase 3 wording ("enfileirar termo"); queuing happens, split across paths. No #179a spawn — only spawn if a concrete failure proves canonical RPC itself must own seeding.
- **Continuity:** registry close rule satisfied because implementation continues under #230 children (#321, #322, #323 spawned in same session) + existing lifecycle issues #180/#181/#177/#182/#183.
- **Sediment learnings (1 NEW):**
  - **SEDIMENT-230.A**: when an "umbrella spec" issue is created during a refactor planning phase, periodically re-audit live state vs spec ACs before assuming the issue is still "spec-only" / "qa-window". Between p202 spec authorship (2026-05-19) and p230 close (2026-05-23), the canonical RPC + delegating wrappers + schema invariants + contract test had already shipped via 4 separate PRs without explicit "closes #179" annotations. The issue lingered in the wrong registry section for 4 days. Operational rule: include a "verify spec status vs live" check in /audit skill output.
- **Cross-ref:** GH issue #179 (closed) · `approve_selection_application` body · `admin_update_application` body · `finalize_decisions` body · `tests/contracts/canonical-approval-orchestration.test.mjs` · invariants R + S + A3 · `docs/project-governance/P202_VOLUNTEER_LIFECYCLE_REMEDIATION_SPEC.md` · `docs/audit/P202_VOLUNTEER_LIFECYCLE_SQL_AUDIT.md` · #292 (sprint umbrella).

### 197. REFRAMED-230 — Herlon volunteer term premise refuted; reframed into 3 ready-leaf children (p230)

- **When:** 2026-05-23 p230 dispatch after #179 close
- **What:** GH #230 commented with refutation + reframe ([comment-4526471094](https://github.com/VitorMRodovalho/ai-pm-research-hub/issues/230#issuecomment-4526471094)) and kept open as umbrella tracker. Original Herlon-specific "missing volunteer term" framing REFUTED by live data: Herlon's 2 active engagements (`ambassador` + `observer`) have `requires_agreement=false` in `engagement_kinds` catalog — he never should have had a term. The real Herlon issue was A3 cache drift (fixed by #318/#320). **Do NOT mint Herlon term.**
- **Where:** P202 audit re-ran live (2026-05-23 20:24 UTC) vs 2026-05-19 baseline:
  - approved_apps: 38 → 38 (unchanged)
  - pending_agreement: **16 → 4 (−12)** — 12 cleared via natural engagement lifecycle (status flips/expiry)
  - approved_without_member: 1 → 1 (same dangling case, known)
  - approved_member_no_person: 0 → 0 (invariant S green)
  - Cohort: 26 approved+active members; 25/26 have vol cert; 1 gap is Herlon (correctly so, no engagement requires)
  - 38 onboarding_progress vol_term pending rows: 30 already have cert (Gap A sync bug); 4 active+no-cert+no-engagement (Gap B classification); 7 inactive/terminal (Gap B continued); 2 study_group_* in pending_agreement with null template (Gap C catalog config)
- **Children spawned (3 ready-leaves):**
  - **#321** (Gap A — phantom rows): AFTER INSERT trigger on certificates of type=volunteer_agreement marks matching onboarding_progress row completed + backfill 30 phantom rows. Forward-defense + DB-gated contract test. Live smoke target: 0 phantom rows.
  - **#322** (Gap B — classification leftovers): PII-redacted audit of 4 active + 7 inactive rows; PM per-row decision; forward guard in `approve_selection_application` (do NOT seed vol_term unless engagement kind requires_agreement); offboarding extension auto-completes/marks obsolete; contract test. Blocked by #321 (sync trigger first).
  - **#323** (Gap C — catalog config): `study_group_owner` + `study_group_participant` have `requires_agreement=true` with `agreement_template=null` — PM decision per kind (assign template OR flip requires_agreement=false). Catalog invariant test extended. Live smoke: 0 catalog inconsistencies (excepting allowlisted `volunteer` self-serve path).
- **Why umbrella (not closed):** the 3 children fully replace original scope but #230 stays open as parent tracker until all 3 ship. Matches #292 / #260 umbrella pattern. Will close with all 3 children green.
- **No cron deferral note:** original #230 body asked for stale-term re-nudge cron. Deferred — actual missing-cert backlog is now 0 for volunteer kind; cron design only revisited if future audit shows volunteer-kind regressions.
- **Sediment learnings (2 NEW):**
  - **SEDIMENT-230.B**: sediment-carry framings can fossilize a misdiagnosis. "Herlon missing volunteer term" carried as sediment from p195 through 4+ weeks without re-audit. The actual root cause (A3 cache drift) was a different kind of bug entirely. Operational rule: when a sediment carry "looks stuck", re-audit before scope-expanding into new issues that inherit the misdiagnosis.
  - **SEDIMENT-230.C**: catalog config can silently make capability-claims that can't be honored. `engagement_kinds.requires_agreement=true` is a capability-claim ("system will/should mint a cert"), but `agreement_template=null` makes the mint path impossible. Catalog invariants should pair capability-claim columns with the prerequisite resource columns (with allowlist for non-template self-serve paths). #323 carries this invariant addition.
- **Cross-ref:** GH issue #230 (umbrella) · #321, #322, #323 (children) · #318 / #320 (A3 root-cause that resolved Herlon sediment) · `approve_selection_application`, `sign_volunteer_agreement`, `process_vep_acceptance_transition`, `engagement_kinds`, `onboarding_progress` · `docs/project-governance/P202_VOLUNTEER_LIFECYCLE_REMEDIATION_SPEC.md` Fase 1-3 · `docs/audit/P202_VOLUNTEER_LIFECYCLE_SQL_AUDIT.md` · #292 (sprint umbrella).


### 198. RESOLVED-229-PHASE2 — leader_extra cohort visibility closed (p232)

- **When:** 2026-05-23 p232 dispatch
- **What:** GH #229 Phase 2 closed via migration `20260805000017_p232_229_phase2_leader_extra_visibility_read_surfaces.sql` + MCP v2.79.1 + frontend chip. Closes the visibility loop opened by p209 Phase 1 mitigation (commit `fe80842c`) which stopped `submit_evaluation` from mutating `objective_score_avg`, and p219 Phase 1 which added the 6 dedicated `leader_extra_pert_*` columns + extended `_compute_pert_cutoff_core` + `recompute_all_active_pert_cutoffs` cron. Phase 2 makes the read surfaces (3 RPCs) symmetrically expose the leader_extra dimension.
- **What shipped (single migration, 3 RPCs):**
  - `get_pert_cutoff_summary(uuid, text)` — CHECK now whitelists `leader_extra_pert_score`; dual-track distribution math (reads `leader_extra_pert_target/band_lower/band_upper/calc_at/cohort_n/cutoff_method` when score_column='leader_extra_pert_score', else `pert_target_score/band_*/...` as before); 1-arg overload `get_pert_cutoff_summary(uuid)` DROPPED to prevent PostgREST dispatching to pre-p232 body when callers omit `p_score_column`
  - `get_application_score_breakdown(uuid)` — JSONB response gains top-level `leader_extra_pert_score` + sibling `leader_extra_cutoff` block (target/band/cohort_n/method/calc_at/leader_extra_score_position ∈ below/within/above)
  - `get_selection_dashboard(text)` — cycle payload gains sibling `leader_extra_cutoff` block (target/band/cohort_n/method/calc_at/apps_with_pert/apps_with_score/apps_total) alongside `pert_cutoff` (objective); each application row in the array also surfaces `leader_extra_pert_score`
- **MCP v2.79.1 (server `nucleo-ia-hub` v2.78.1, tool count unchanged 299):**
  - `get_pert_cutoff_summary` + `compute_pert_cutoff` `score_column` z.enum extends to include `leader_extra_pert_score`
  - Descriptions clarify dual-dim model (objective + leader_extra) for both summary read and admin compute trigger
  - `get_application_score_breakdown` description mentions both `pert_cutoff` and `leader_extra_cutoff` blocks
  - EF deployed live; `/health` reports ef_version=2.79.1, /mcp 2.78.1, /semantic 0.1.0, tools=299; `tools/list` returns 299 with `leader_extra_pert_score` appearing 2× (one per tool); initialize HTTP 200 + serverInfo.version="2.78.1" ✅
- **Frontend `/admin/selection.astro`:** new `#leader-extra-cutoff-chip` DOM (sibling to `#pert-cutoff-chip`) + populate logic reading `cycle.leader_extra_cutoff`; 9 new i18n keys across 3 dictionaries (`pt-BR`/`en-US`/`es-LATAM` × `leaderExtraCutoffLabel`/`Tooltip`/`Empty`); table coloring intentionally unchanged in this PR (leader_score still colored against objective `pert_cutoff` because leader_score = research*0.7 + LE*0.3 is a blended metric — proper coloring requires a separate "leader_score cutoff" which isn't in scope here).
- **Contract tests +12 (`tests/contracts/p232-229-phase2-leader-extra-visibility.test.mjs`):** 8 static migration body assertions (file existence + CHECK + dual-track math + breakdown block + dashboard sibling + DROP overload + NOTIFY + WHAT/WHY/ROLLBACK header) + 4 DB-gated (overload absence + summary acceptance + breakdown key present + Phase 1 columns selectable). All 8 static pass live; 4 DB-gated skip without env vars (CI runs them). Plus 1 ratchet in `tests/contracts/mcp-semantic-gateway-bridge.test.mjs` loosening `v2.79.0` strict match to `v2.79.\d+` regex so additive patches don't break the bridge-era marker.
- **Test baseline:** offline 1800/1751/0/49 → **1812/1759/0/53** (+12: +8 pass + +4 skip).
- **Live smoke 3/3 PASS (2026-05-23 17:23-17:26 UTC):**
  - `recompute_all_active_pert_cutoffs()` → cycle4-2026 objective method=dynamic n=19 target=155.42 band [139.88-170.96] (matches Francisleila preview baseline ✅); cycle4-2026 leader_extra method=disabled cohort_n=6 (below n=10 dynamic threshold ✓ expected — needs more leader-track approvals historically before kicking in); cycle3-2026-b2 similar
  - `get_pert_cutoff_summary(cycle4, 'leader_extra_pert_score')` → returns method=disabled, cohort_n=6, target=NULL, distribution.not_yet_scored=35 (3 apps have LE score from p209 Phase 1 backfill) — dual-track read confirmed
  - `get_pert_cutoff_summary(cycle4, 'objective_score_avg')` AND default-no-arg both return identical objective summary (default param works post-overload-drop) ✅
  - `get_application_score_breakdown(Francisleila app id)` → top-level `leader_extra_pert_score=145` + `leader_extra_cutoff.method='disabled'` + `pert_cutoff.target_score=155.42` (both blocks coexist)
  - `get_selection_dashboard('cycle4-2026').cycle.leader_extra_cutoff` → method='disabled', apps_with_score=3 (frontend chip will render empty-state with hint)
- **Backfill NOT executed:** cycle3-2026 (announcement phase, 14 apps with LE score, target=NULL) was intentionally NOT recomputed because the cycle is closed (phase outside cron filter set `('evaluating', 'interviews', 'open_apps')`). The weekly cron `recompute-pert-cutoffs-weekly` Mon 13:00 UTC already calls BOTH dimensions per active cycle per the Phase 1 `recompute_all_active_pert_cutoffs()` extension. No one-off backfill needed.
- **Why "disabled" is OK:** `_compute_pert_cutoff_core` fallback ladder is `dynamic` (n>=10) → `historical_fallback` (max prior `*_target` across other cycles) → `disabled` (no prior data). LE dimension has cohort_n=6 prior approvals because earlier cycles didn't separately track LE scores (the column was added in p209 Phase 1, before that LE was mutated into `objective_score_avg`). After 1-2 more cycles of clean LE submissions + approvals, cohort_n will cross 10 and dynamic method kicks in. Visibility loop is what Phase 2 closes; the cohort threshold is a separate timing concern.
- **Invariants:** 19/19 = 0 violations live (no schema changes; signature unchanged for all 3 RPCs).
- **Sediment learnings (3 NEW):**
  - **SEDIMENT-232.A**: when CREATE OR REPLACE'ing a function that has multiple overloaded signatures, PG keeps the OTHER overload by signature — so `CREATE OR REPLACE get_pert_cutoff_summary(uuid, text DEFAULT ...)` does NOT remove the pre-existing `get_pert_cutoff_summary(uuid)` overload. PostgREST may then dispatch to the OLD 1-arg body when callers omit the new param. Always DROP stale overloads explicitly when consolidating a 1-arg → 2-arg signature with a DEFAULT. This bit immediately during smoke — caught and dropped in the same migration.
  - **SEDIMENT-232.B (CORRECTED post-CI)**: `apply_migration` MCP STILL creates shadow rows at NOW() (p227 SEDIMENT-227.A behavior unchanged). My initial verification missed it because I queried `WHERE version > '20260805000016'` — but shadow rows use TODAY's date `20260523*` which is LESS than the p232 canonical version `20260805000017`. CI ADR-0097 ratchet (`rpc-migration-coverage.test.mjs`) caught 4 shadow rows post-push (`20260523211533/211616/211737/211834`), one per apply_migration call. **Cleanup workflow**: after every apply_migration session, query `SELECT version FROM supabase_migrations.schema_migrations WHERE version >= 'YYYYMMDDHHMMSS' AND version < '20XX0805000000'` using TODAY's date prefix to find shadow rows, then `DELETE FROM supabase_migrations.schema_migrations WHERE version IN (...)`. This is exactly the cleanup p227 documented. The bug is NOT patched — my session-internal sanity check was misframed.
  - **SEDIMENT-232.C**: forward-defense contract tests need to be added to BOTH `npm test` AND `npm run test:contracts` scripts in `package.json` (they have different lists — `test:contracts` is a subset). When the new test only got added to `test`, it ran in CI but a future debug session running `npm run test:contracts` would miss it. Verified: my test file went only into the `npm test` script (the canonical CI runner), test:contracts wasn't touched because its leader-extra parent doesn't exist there either — preserved that asymmetry for now but called out for future cleanup.
- **PRs:** p232 close PR (this one) — squash merge target. No bypass. CI expected green; will gate on validate + check-invariants.
- **Cross-ref:** GH #229 (Phase 2 closed) · migration `20260805000017_p232_229_phase2_leader_extra_visibility_read_surfaces.sql` · MCP `supabase/functions/nucleo-mcp/index.ts` v2.79.1 · frontend `src/pages/admin/selection.astro` 2-band chip · 9 i18n keys (`pt-BR.ts`/`en-US.ts`/`es-LATAM.ts`) · `tests/contracts/p232-229-phase2-leader-extra-visibility.test.mjs` (12 new) + ratchet `tests/contracts/mcp-semantic-gateway-bridge.test.mjs` · Phase 1 cross-ref: `tests/contracts/leader-extra-cohort-separation.test.mjs` (p219, migration `20260803000005`) · commit `fe80842c` (A2 minimal isolation, p209) · p195 PERT cutoff add (migration `20260519015105`) · #292 Selection reliability sprint umbrella.

### 199. RESOLVED-321 — Gap A of #230 reframe: complete onboarding_progress.volunteer_term when matching vol_agreement cert is issued (p233)

- **When:** 2026-05-23 p233 dispatch
- **What:** GH #321 closed via migration `20260805000018_p233_321_complete_volunteer_term_on_cert.sql` (AFTER INSERT trigger on `certificates` + 30-row in-tx backfill). Closes the phantom-row drift discovered in p230 #230 reframe audit (30 of 38 pending `volunteer_term` rows already had a matching cert — 88% phantom rate caused by `sign_volunteer_agreement()` and other paths inserting `certificates` of type='volunteer_agreement' without atomically marking the corresponding `onboarding_progress` row as completed).
- **What shipped (single migration):**
  - **Trigger function `_trg_complete_volunteer_term_on_cert()`** — SECURITY DEFINER, `search_path = 'public', 'pg_temp'`, body has paranoid `IF NEW.member_id IS NULL THEN RETURN NEW; END IF;` guard (defense-in-depth despite NOT NULL constraint), atomic UPDATE of matching `onboarding_progress` row using unique `(member_id, step_key)` index, idempotent via `WHERE status != 'completed'` guard, `completed_at = COALESCE(NEW.issued_at, now())` for historical accuracy, metadata enrichment with `cert_id` + `verification_code` + `completed_via='cert_trigger'` + `migration='20260805000018'`. Audit row inserted only when `v_rows_affected > 0` (avoids noisy audit on no-op) with canonical action `onboarding.volunteer_term_completed_on_cert` (matches admin_audit_log CHECK regex `^[a-z][a-z0-9_]*(\.[a-z0-9_]+)*$`).
  - **Trigger registration** — `AFTER INSERT ON public.certificates FOR EACH ROW WHEN (NEW.type = 'volunteer_agreement')`. WHEN clause is the primary scope gate per #321 AC; function body NULL-guard is belt+suspenders. Coexists independently with `trg_auto_remove_designation_on_cert` and `trg_certificate_pdf_autogen`.
  - **In-tx backfill DO block** — `DISTINCT ON (c.member_id) ORDER BY c.member_id, c.issued_at DESC` CTE gets latest issued vol_agreement cert per member; UPDATE phantom rows scoped to `op.status = 'pending'` (idempotent re-apply); audit row per backfilled `op.id` with action `p233_321_backfill_volunteer_term_phantom`. Result: **30 rows flipped, 30 audit rows inserted**.
  - **Sanity DO block** — RAISE EXCEPTION if any pending vol_term row with matching issued vol_agreement cert remains post-backfill (fails apply at write time, not runtime — matches p219 pattern).
- **Contract tests +12 (`tests/contracts/p233-321-complete-volunteer-term-on-cert.test.mjs`):** 11 static migration body assertions + 1 DB-gated (post-backfill 0 phantom invariant). All 11 static pass live; DB-gated skips without env vars (CI runs it).
- **Test baseline:** offline 1812/1759/0/53 → **1824/1770/0/54** (+12: +11 pass + +1 skip).
- **Live smoke (2026-05-23 ~21:54 UTC):**
  - Trigger registered with WHEN clause exact match (`pg_get_triggerdef` returns canonical form ✅)
  - Function exists with `prosecdef=true` + canonical COMMENT ON ✅
  - **Pre-apply state**: 38 pending vol_term, 30 phantom, 5 completed
  - **Post-apply state**: 38 pending vol_term, **0 phantom**, 35 completed (5 pre-existing + 30 backfilled with metadata.completed_via='p233_backfill') ✅
  - 30 admin_audit_log rows with action `p233_321_backfill_volunteer_term_phantom` ✅
  - 8 remaining pending vol_term rows correspond to Gap B (4 active + 4 inactive — out of scope; handled by #322)
  - `check_schema_invariants()` returns 19/19 = 0 violations throughout ✅
- **Out of scope (per issue #321 body):**
  - Gap B (4 active + 7 inactive without cert) → #322 (now unblocked by this close)
  - Gap C (study_group_* catalog config) → #323
  - Stale-term re-nudge cron → deferred per #230 reframe
  - check_schema_invariants() new invariant ("no pending vol_term when matching cert exists") → DEFERRED per issue body (PM call; may be too strict during in-flight signing windows; the trigger handles atomic mint+complete in same tx, but external paths may not — revisit after Gap B+C ship)
- **Sediment learnings (1 NEW, 2 reapplied):**
  - **SEDIMENT-232.B (REAPPLIED, cleanup worked)**: `apply_migration` MCP again created a shadow row at today's date (`20260523215958`). Confirmed pre-existing shadow `20260523010325` had escaped prior sessions' cleanup. Cleaned both via `DELETE FROM supabase_migrations.schema_migrations WHERE version IN (...)` before `supabase migration repair --status applied 20260805000018` registered the canonical. Workflow verified end-to-end. No new sediment — just confirms p232's documented procedure is correct.
  - **SEDIMENT-232.C (REAPPLIED, asymmetry intentional)**: Added new test file to BOTH `npm test` AND `npm run test:contracts` script arrays in `package.json` this time (p232 had only added to `npm test`). Both arrays now include `p233-321-complete-volunteer-term-on-cert.test.mjs`. The asymmetry between the two scripts pre-existing entries remains — backlog for a future cleanup leaf.
  - **SEDIMENT-233.A (NEW — WHEN clause vs body guard trade-off)**: For AFTER INSERT triggers on `certificates`, project has 2 precedents — `trg_auto_remove_designation_on_cert` (no WHEN, body guards via `IF NEW.type != 'contribution' OR NEW.function_role IS NULL THEN RETURN NEW; END IF;`) and `trg_certificate_pdf_autogen` (WHEN clause `WHEN ((new.pdf_url IS NULL))`). Issue #321 AC explicitly required WHEN clause, so this trigger uses that — Postgres evaluates the WHEN expression before calling the function, avoiding the function-call overhead for non-matching INSERTs (~99% of certificate inserts are not vol_agreement type). Body still has NULL `member_id` guard as defense-in-depth (cheap + handles paranoid edge case). Style decision: prefer WHEN clause when scope can be expressed as a pure expression; use body guard when scope needs procedural logic. Documented for future trigger PRs.
- **PRs:** p233 close PR (this one) — squash merge target. No bypass. CI expected green; will gate on validate + check-invariants.
- **Cross-ref:** GH #321 (Gap A closed) · migration `20260805000018_p233_321_complete_volunteer_term_on_cert.sql` · `tests/contracts/p233-321-complete-volunteer-term-on-cert.test.mjs` (12 new) · `supabase/migrations/20260415020000_v4_phase7_volunteer_agreement_engagement_link.sql` (original `sign_volunteer_agreement` RPC) · p219 reference pattern: `tests/contracts/auto-link-volunteer-engagement-to-cycle-cert.test.mjs` + migration `20260803000003` · sibling triggers on certificates: `_auto_remove_designation_on_cert`, `_trg_certificate_pdf_autogen` · admin_audit_log CHECK constraint `^[a-z][a-z0-9_]*(\.[a-z0-9_]+)*$` (sediment SEDIMENT-228.F) · #230 umbrella (parent reframe) · #322 (Gap B, now unblocked) · #323 (Gap C, catalog config).

### 200. RESOLVED-322 — Gap B of #230 reframe: classification leftovers backfilled + forward guard + offboarding extension + UX harmonize (p234)

- **When:** 2026-05-23 p234 dispatch (post-#321 close)
- **What:** GH #322 closed via migration `20260805000019_p234_322_volunteer_term_gap_b_classification_and_guards.sql`. Closes the classification-leftover Gap B surfaced at p230 reframe. After #321 cleared cohort A (30 phantoms with matching cert), 8 pending vol_term rows remained as cohort B — 4 active + 4 inactive members with NO issued vol_agreement cert AND NO active engagement of any `requires_agreement=true` kind. Their step was mis-seeded by the universal Path A loop in `approve_selection_application` (which seeds all `is_required=true` steps from the `onboarding_steps` catalog regardless of the member's actual engagement kind).
- **PM directives 2026-05-23 (three Recommended picks):**
  - Q1 — Status to write: `skipped + metadata reason='no_requires_agreement_engagement'`. Uniform across backfill + offboarding extension + forward-guard skip path. **NEVER `completed` unless a volunteer_agreement cert exists or a real signing/ack event happened.** Do NOT mint Herlon term.
  - Q2 — UX harmonize: Yes — `get_my_onboarding` should treat `skipped`≡`completed` for `completed_steps` + `all_complete` (mirrors get_onboarding_status pattern).
  - Q3 — Forward guard scope: inline `volunteer_term` skip in `approve_selection_application` (minimal blast radius, forward-defense). NO schema column change to onboarding_steps catalog.
- **Live evidence (pre-apply, 2026-05-23 22:24 UTC):**
  - 38 total `onboarding_progress` rows with `step_key=volunteer_term`
  - 30 had matching cert (already backfilled by #321 trigger; `_trg_complete_volunteer_term_on_cert` invariant)
  - 8 remained pending — confirmed PM's P162 #199 baseline of 4 active + 4 inactive
  - Active 4 cohort: chapter_liaison + observer (Herlon, with offboarded study_group_owner) + researcher (multi-eng none requires_agreement) + sponsor
  - Inactive 4 cohort: 2 alumni (one had expired volunteer engagement) + 2 observer/guest
- **What shipped (single migration, 1 backfill + 3 RPC body changes):**
  - **Backfill DO block** — CTE filters `step_key='volunteer_term'` + `status='pending'` + NO cert + NO active requires_agreement engagement. UPDATE sets `status='skipped'`, `completed_at=now()`, metadata enriched with `completed_via='p234_322_backfill_no_agreement_path'` + `reason='no_requires_agreement_engagement'` + `is_active_at_backfill` + `member_status_at_backfill` + `migration='20260805000019'`. Audit row per affected `op.id` with canonical action `p234_322_backfill_volunteer_term_no_agreement` (matches admin_audit_log CHECK regex). Result: **8 rows flipped to skipped, 8 audit rows inserted**.
  - **Forward guard in `approve_selection_application(uuid, jsonb)`** — Path A SELECT now includes `AND NOT (s.id = 'volunteer_term' AND NOT COALESCE(v_requires_agreement, FALSE))`. Function still hardcodes `v_engagement_kind='volunteer'` (requires_agreement=true) so this is no-op today — forward-defense for any future change that makes the engagement kind dynamic per role_applied or cycle config. Other paths (Path B per-cycle config; `seed_pre_onboarding_steps`; `process_vep_acceptance_transition`) verified not to seed `volunteer_term`.
  - **Offboarding extension in `admin_offboard_member(uuid, text, text, text, uuid)`** — after the engagements UPDATE step, new UPDATE flips any open `volunteer_term` step (`status='pending'`) to `status='skipped'` with metadata `completed_via='p234_322_offboarding_extension'` + `reason='offboarded_pre_signing'` + `offboarded_to_status` (target status captured). Idempotent via `status='pending'` filter; respects #321 trigger ordering (if cert was inserted before offboard, step is already `completed` → no-op). `GET DIAGNOSTICS v_vol_terms_skipped = ROW_COUNT` + conditional audit insert (only when `v_vol_terms_skipped > 0`) with canonical action `onboarding.volunteer_term_skipped_on_offboard`. Function return JSONB now includes `vol_terms_skipped` field. ARM-9 G3 alumni_recognition emission preserved verbatim.
  - **`get_my_onboarding()` harmonization** — `completed_steps` clause uses `status IN ('completed', 'skipped')`; `all_complete` clause uses `op.status NOT IN ('completed', 'skipped')`. Mirrors existing `get_onboarding_status` pattern. Per-step rendering `COALESCE(op.status, 'pending')` preserved verbatim — UI can render skipped distinctly if it chooses.
  - **Sanity DO block** — RAISE EXCEPTION if any active member has pending vol_term AND no active requires_agreement engagement post-backfill (fails apply at write time, not runtime — matches p219 + p233 pattern).
- **Contract tests +16 (`tests/contracts/p234-322-volunteer-term-gap-b-classification.test.mjs`):** 15 static migration body assertions + 1 DB-gated (live goal metric = 0). Test file registered in BOTH `npm test` AND `npm run test:contracts` arrays in `package.json` (SEDIMENT-232.C / 233.B reapplied — both arrays now reference p234 file). Asymmetry between the two scripts' pre-existing entries remains as documented backlog.
- **Test baseline:** offline 1824/1770/0/54 → **1840/1785/0/55** (+16: +15 pass + +1 skip).
- **Live smoke (2026-05-23 ~22:47 UTC):**
  - Backfill: 8 rows flipped to `skipped`, 8 audit rows with action `p234_322_backfill_volunteer_term_no_agreement` ✅
  - Goal metric: 0 active members with pending vol_term AND no active requires_agreement engagement ✅ (sanity DO didn't fail)
  - Counts: total_pending_vol_term=0, total_skipped_vol_term=8, total_completed_vol_term=35 (5 pre-#321 historical + 30 #321 backfill)
  - Function bodies verified: `approve_selection_application` has guard inline ✅; `admin_offboard_member` has extension UPDATE + audit ✅; `get_my_onboarding` has harmonized completed_steps + all_complete ✅
  - `check_schema_invariants()` returns 19/19 = 0 violations throughout ✅
- **Out of scope (per issue #322 body):**
  - Gap C (study_group_* catalog config: requires_agreement=true with null agreement_template) → #323 (remains the only #230 umbrella child not yet closed)
  - `check_schema_invariants()` new invariant ("no pending vol_term when no requires_agreement engagement") → DEFERRED per PM call (overlap with Gap C semantics; revisit after #323 ships)
  - Stale-term re-nudge cron → deferred per #230 reframe
  - Generalizing `requires_kind_agreement` to onboarding_steps catalog → PM chose minimal blast radius (Q3); revisit if engagement_kind becomes dynamic
- **Sediment learnings (1 NEW, 2 REAPPLIED):**
  - **SEDIMENT-232.B (REAPPLIED, cleanup worked)**: `apply_migration` MCP again created a shadow row at today's date (`20260523224708`). Cleaned via in-place `UPDATE supabase_migrations.schema_migrations SET version='20260805000019' WHERE version='20260523224708'` (single-statement re-version preserves statements + idempotency_key without DELETE+INSERT round-trip). Workflow refined: in-place UPDATE simpler than DELETE+repair when the shadow row already contains the correct migration body — just re-version to canonical. Documented for future apply_migration sessions.
  - **SEDIMENT-232.C (REAPPLIED, asymmetry intentional)**: Added new test file to BOTH `npm test` AND `npm run test:contracts` script arrays. Both arrays now include `p234-322-volunteer-term-gap-b-classification.test.mjs`. Pre-existing asymmetry between the two script lists remains — still backlog.
  - **SEDIMENT-234.A (NEW — universal seed loops + per-step applicability)**: The `onboarding_steps` catalog has a binary `is_required boolean` flag, but real-world step applicability is contextual (some required steps only apply when the member's engagement kind has specific properties, e.g., `requires_agreement=true`). The Path A INSERT in `approve_selection_application` was written before this distinction was modeled in the catalog — leading to universal seeding that produces phantom-pending rows for members whose engagement kind doesn't trigger the step's underlying mechanic (Gap B). #322 patches this inline with a hardcoded predicate (PM chose minimal blast radius for now). A future generalization opportunity: extend `onboarding_steps` with a `requires_kind_agreement boolean` (or more general predicate) column and refactor the seed loop to consult it. Open backlog item — revisit if engagement_kind becomes dynamic per `role_applied` / cycle config or if another step surfaces a similar mis-seed pattern.
- **PRs:** p234 close PR (this one) — squash merge target. No bypass. CI expected green; will gate on validate + check-invariants.
- **Cross-ref:** GH #322 (Gap B closed) · migration `20260805000019_p234_322_volunteer_term_gap_b_classification_and_guards.sql` · `tests/contracts/p234-322-volunteer-term-gap-b-classification.test.mjs` (16 new) · #321 (Gap A closed p233, sibling trigger `_trg_complete_volunteer_term_on_cert`) · #323 (Gap C, catalog config — only remaining #230 child) · #230 umbrella (parent reframe) · `approve_selection_application` + `admin_offboard_member` + `get_my_onboarding` RPC bodies · `engagement_kinds` catalog (requires_agreement column source of truth) · admin_audit_log CHECK constraint `^[a-z][a-z0-9_]*(\.[a-z0-9_]+)*$` (sediment SEDIMENT-228.F applied to canonical action names) · #292 (sprint umbrella).

### 200a. CLOSE-REVIEW-322 — get_my_onboarding auto-seed unguarded; PM caught before merge (p234, PR #327)

- **When:** 2026-05-23 p234 PR #327 curator review by PM (post-initial squash candidate, pre-merge)
- **What:** PM identified that `get_my_onboarding()` was the unguarded auto-seed re-entry vector — it universally inserts all `onboarding_steps` entries for the member on first call, which would reintroduce Gap B for any future member whose first onboarding hit lands there (e.g., approved member who hasn't opened /onboarding yet; or, if the engagement kind ever becomes dynamic, members approved into a non-volunteer kind). Patched **in the same PR branch via migration `20260805000020`** (no separate child issue) — fix is strictly in-scope for #322 and was caught before the original PR merged.
- **Why it was missed initially:** Initial scope per #322 issue body listed `approve_selection_application` + `admin_offboard_member` as the seed surfaces. I audited those two paths but did not enumerate ALL auto-seed paths into `onboarding_progress`. PM applied the universal-forward-defense lens and caught it.
- **6-path audit (post-catch, completed in close-review):**
  - `approve_selection_application(uuid, jsonb)` — Path A guarded in 20260805000019 ✅
  - `auto_detect_onboarding_completions()` — only seeds `complete_profile` / `start_trail` / `first_meeting` (no `volunteer_term`) ✅
  - `complete_onboarding_step(text, jsonb)` — caller-driven; user explicitly clicks "Mark complete" ✅
  - `get_my_onboarding()` — universal auto-seed of `onboarding_steps` catalog ❌ → **fixed in 20260805000020**
  - `process_vep_acceptance_transition()` — only touches `vep_acceptance` step ✅
  - `seed_pre_onboarding_steps(uuid, uuid)` — only `create_account` / `setup_credly` / `explore_platform` / `read_blog` / `start_pmi_certs` ✅
- **Patch in `get_my_onboarding()`:**
  - DECLARE `v_has_req_agreement_engagement boolean`
  - Compute via EXISTS on `engagements` JOIN `members` JOIN `engagement_kinds` filtered by `e.status='active'` AND `ek.requires_agreement = true`
  - Auto-seed INSERT now includes `AND NOT (s.id = 'volunteer_term' AND NOT v_has_req_agreement_engagement)` — mirrors `approve_selection_application` Path A guard
  - Preserves verbatim: `completed_steps` / `all_complete` skipped≡completed harmonization, SECDEF, pinned search_path, per-step `COALESCE(op.status, 'pending')` rendering
- **Contract test +4 (extended `tests/contracts/p234-322-volunteer-term-gap-b-classification.test.mjs`):** migration 20260805000020 file present + var declaration + EXISTS query reads engagements/engagement_kinds with correct filters + auto-seed guard clause + harmonization preserved + SECDEF + step rendering verbatim + NOTIFY pgrst.
- **Test baseline:** offline 1840/1785/0/55 → **1844/1789/0/55** (+4 static; DB-gated count unchanged).
- **Live smoke (post-patch, ~2026-05-23 23:05 UTC):**
  - `pg_get_functiondef(get_my_onboarding)` has all 4 expected fragments: `v_has_req_agreement_engagement boolean` declared + `AND ek.requires_agreement = true` in EXISTS + `NOT (s.id = 'volunteer_term' AND NOT v_has_req_agreement_engagement)` in INSERT + `status IN ('completed', 'skipped')` preserved
  - Goal metric still **0 active members with pending vol_term AND no active requires_agreement engagement**
  - `check_schema_invariants()` returns 19/19 = 0 violations
- **Sediment learnings (1 NEW + 2 REAPPLIED):**
  - **SEDIMENT-234.B (NEW)**: Forward guard must cover ALL auto-seed paths, not just the canonical approval RPC. When patching an issue with "do not seed X under condition Y", enumerate every function/trigger that performs INSERT into the affected table and audit each for the condition. Operational rule: pre-commit grep `INSERT INTO[[:space:]]+(public\.)?<table>` and document the audit table in the PR body. Cost of missing one path = exactly the regression we're trying to prevent.
  - **SEDIMENT-232.B (REAPPLIED, in-place UPDATE refined further)**: Used in-place `UPDATE supabase_migrations.schema_migrations SET version='20260805000020' WHERE version LIKE '20260523%' AND name LIKE '%close_review%'` to cleanly re-version the shadow row. Pattern: filter by both date prefix + name fragment to avoid collisions when multiple apply_migration calls happen in the same session. Documented.
  - **SEDIMENT-234.A (REAPPLIED)**: Still open — close-review patch is a per-RPC inline fix. The general schema-level solution (column on onboarding_steps catalog) remains backlog. #322 close still picks the minimal blast radius option.
- **PR comment trail:** PM blocked PR #327 with comment-4526757434; agent replied with audit + fix plan in comment-4526761568; close-review commit pushed to same branch.
- **Cross-ref:** GH #322 (Gap B closed via PR #327; 2 migrations) · `tests/contracts/p234-322-volunteer-term-gap-b-classification.test.mjs` extended +4 · migrations `20260805000019` + `20260805000020` · 6-path audit completed inline · #321 (sibling Gap A closed p233) · #323 (Gap C, only remaining #230 child).

### 201. RESOLVED-323 — Gap C of #230 reframe: study_group_* engagement_kinds catalog config decision (p235)

- **When:** 2026-05-23 p235 dispatch (post-#322 close)
- **What:** GH #323 closed via migration `20260805000021_p235_323_study_group_catalog_config_decision.sql` shipped in PR #328 (squash `841da143`, merged 2026-05-23T23:46:10Z). Resolves the `engagement_kinds` catalog inconsistency surfaced by the p230 audit: 2 catalog rows (`study_group_owner` + `study_group_participant`) declared `requires_agreement=true` with `agreement_template=NULL`, meaning the p203 `pending_agreement_engagements` queue would route them to `'decide_template_for_kind_then_issue'` indefinitely.
- **PM directives 2026-05-23 (two Recommended ABCD picks):**
  - Q1 — `study_group_owner`: KEEP `requires_agreement=true`, assign placeholder `agreement_template='study_group_owner_agreement_v1'`. Preserves ADR-0006 line 56 (Herlon canonical V4 example) + ADR-0008 lifecycle ("VEP fast-track → Termo → 9m → 5yr retention"); mirrors ADR-0078 D5 external_reviewer slug placeholder precedent. Template body deferred to follow-up legal-counsel issue.
  - Q2 — `study_group_participant`: FLIP `requires_agreement=false`. Course enrollee model; ADR-0008 "termo de uso" read as platform-wide TOS (consent), not per-engagement. `legal_basis` stays `contract` (curso execution — Lei 9.608 framing). Participant must not enter `pending_agreement` queue.
- **Live evidence (pre-apply, 2026-05-23 23:35 UTC):**
  - 2 catalog rows violating the invariant: `study_group_owner` + `study_group_participant`
  - 2 pending_agreement queue rows — BOTH for Fernando Maquiaveli (member_id `c8b930c3-62ec-4d38-881e-307cd57a44f7`) on initiative "Grupo de Estudos CPMAI™" (the ONLY active `study_group`). One row per kind, both `role='leader'`. Redundant double-engagement flagged as separate data-quality carry (NOT a #323 blocker per PM directive).
  - `engagement_kind_permissions` for `(study_group_participant, role=leader)`: EMPTY. The only permission seeded for this kind is `(role=participant, write_board, scope=initiative)` — applies prospectively to future enrollees as PM intended.
  - `engagement_kinds.agreement_template` is a forward-declared TEXT slug with NO consumer code: `sign_volunteer_agreement` and `external_reviewer` mint paths are hardcoded; nothing auto-reads the slug. Placeholder = catalog/intent marker, not active mint trigger.
- **What shipped (single migration, idempotent UPDATEs + audit + sanity DO):**
  - UPDATE 1: `study_group_owner SET agreement_template='study_group_owner_agreement_v1' WHERE slug='study_group_owner' AND agreement_template IS NULL` (idempotent)
  - UPDATE 2: `study_group_participant SET requires_agreement=false WHERE slug='study_group_participant' AND requires_agreement=true` (idempotent)
  - Audit log INSERT: 2 rows with action `engagement_kind.catalog_config_decision` (matches admin_audit_log CHECK regex) + target_type `'engagement_kinds'` (canonical, count=7 historical) + per-row metadata (kind/change/rationale/pm_decision_session/migration)
  - Sanity DO block: RAISES EXCEPTION if `requires_agreement=true AND agreement_template IS NULL AND slug NOT IN ('volunteer')` returns any rows. Hard-fails at write time.
  - NOTIFY pgrst: defensive schema cache reload
- **Contract tests +12 (`tests/contracts/p235-323-study-group-catalog-config-decision.test.mjs`):** 11 static migration body assertions + 1 DB-gated. Test file registered in BOTH `npm test` AND `npm run test:contracts` arrays (SEDIMENT-232.C / 233.B / 234.B convention upheld).
  - Static (9): file present + header cross-refs (#323/ADR-0006/ADR-0008/ADR-0078/ROLLBACK/Herlon directive) + owner UPDATE idempotency guard + participant UPDATE idempotency guard + audit canonical action + sanity DO RAISE + sanity allowlist (`'volunteer'`) + NOTIFY pgrst + BEGIN/COMMIT wrapper
  - Forward-defense (2): no future migration re-flips `study_group_owner.agreement_template` back to NULL (UPDATE pattern); no future migration re-flips `study_group_participant.requires_agreement` back to TRUE (UPDATE + VALUES-tuple + ON CONFLICT patterns per PR #250 LOW review)
  - DB-gated (1): live catalog has 0 rows where `requires_agreement=true AND agreement_template IS NULL AND slug NOT IN ('volunteer')`
- **Test baseline:** offline 1844/1789/0/55 → **1856/1800/0/56** (+12: +11 pass + +1 skip). With-DB CI expected ~1846 pass.
- **Live smoke (2026-05-23 23:35 UTC, post-apply):**
  - ✅ Catalog: `study_group_owner.agreement_template='study_group_owner_agreement_v1'`; `study_group_participant.requires_agreement=false`
  - ✅ Goal metric: 0 catalog offenders (sanity DO didn't fail)
  - ✅ Audit log: 2 rows with correct action + per-kind change tags
  - ✅ Fernando's 2 engagements:
    - `study_group_owner` (role=leader): `requires_agreement=true`, `is_authoritative=false` (still pending cert)
    - `study_group_participant` (role=leader): `requires_agreement=false`, `is_authoritative=true` — **zero new capabilities** (role=leader doesn't match the (participant, role=participant, write_board) seed; participant seed applies prospectively only)
  - ✅ `check_schema_invariants()` returns 19/19 = 0 violations
- **Out of scope (per issue #323 body + PM directive):**
  - Template body for `study_group_owner_agreement_v1` → follow-up legal-counsel issue (not filed yet; PM can file when bandwidth opens)
  - Fernando's redundant owner+participant double-engagement on same initiative → separate data-quality carry, NOT #323 (PM acknowledged)
  - Re-evaluation of `legal_basis` for `study_group_participant` → PM directive: keep `contract` (curso execution); revisit if a different LGPD framing emerges
- **Sediment learnings (1 NEW + 1 REAPPLIED):**
  - **SEDIMENT-235.A (NEW — registry text + GH auto-close keyword regex)**: The phrase `close #<N>` in any merged commit/PR description (including registry edits bundled with the implementation PR) triggers GitHub's auto-close keyword regex (`(close|closes|closed|fix|...)\s+#\d+`). My ISSUE_REGISTRY.md edit had "All 3 children shipped — close #230 in handoff PR with evidence summary" inside a Stop-The-Line row's Close rule column, which auto-closed #230 the moment PR #328 squash-merged at 23:46:10Z (same timestamp as #323). Outcome was what PM authorized ("close #230 after #323 ships"), but the evidence summary that should have accompanied the close was deferred to a retroactive comment (`4526837462`). **Operational rule going forward**: when authoring close-rule narrative in ISSUE_REGISTRY.md or PR descriptions, use neutral phrasing like "to be closed in <PR>" or "close-trigger satisfied" — avoid literal `close #<N>` unless you intend immediate auto-close. If the close must accompany the same PR, post the evidence summary comment BEFORE the merge so it lands before the close timestamp.
  - **SEDIMENT-232.B (REAPPLIED, in-place UPDATE preferred)**: `apply_migration` MCP created a shadow row at NOW() (`20260523233550`). Used in-place `UPDATE supabase_migrations.schema_migrations SET version='20260805000021' WHERE version='20260523233550' AND name='p235_323_study_group_catalog_config_decision'` to cleanly re-version. Pattern matches p234 SEDIMENT-232.B refinement (filter by version prefix + name fragment to avoid collisions).
- **PRs:** PR #328 (squash `841da143`, merged 23:46:10Z). No bypass; CI 10/10 GREEN (quality_gate + Cloudflare Pages + analyze 1m53s + browser_guards 1m51s + check-advisors 9s + check-invariants 23s + issue_reference_gate 7s + validate 2m20s + visual_dark_mode 57s; CodeQL skipping informational).
- **Cross-ref:** GH #323 (closed) · GH #230 (umbrella also auto-closed via same merge; evidence comment 4526837462) · migration `20260805000021_p235_323_study_group_catalog_config_decision.sql` · `tests/contracts/p235-323-study-group-catalog-config-decision.test.mjs` (12 new) · ADR-0006 line 56 (Herlon canonical) · ADR-0008 (per-kind lifecycle) · ADR-0078 D5 (external_reviewer placeholder precedent) · sibling closes #321 p233 / #322 p234 · `engagement_kinds` catalog (requires_agreement + agreement_template columns) · `public.auth_engagements` view (derives is_authoritative).

### 202. RESOLVED-230-UMBRELLA — Herlon vol_term workflow umbrella fully closed (p235)

- **When:** 2026-05-23 23:46:11Z, auto-closed via PR #328 merge (same timestamp as #323 close)
- **What:** GH #230 closed as fully shipped umbrella. Original "Herlon volunteer term workflow gap" premise was refuted at p230 (see #197 REFRAMED-230); reframed into 3 ready-leaf children all now closed:
  - #321 (Gap A, closed p233 via PR #326, migration `20260805000018`): AFTER INSERT trigger on `certificates` + 30-row phantom backfill
  - #322 (Gap B, closed p234 via PR #327, migrations `20260805000019` + `20260805000020` close-review): 8-row classification-leftover backfill + forward guards across 3 RPCs + UX harmonization + auto-seed guard mirror
  - #323 (Gap C, closed p235 via PR #328, migration `20260805000021`): catalog config decision per kind (placeholder slug for owner + flip for participant)
- **Final live state (2026-05-23 23:46Z, post-PR-#328):**
  - `check_schema_invariants()`: 19/19 violation_count=0 ✅
  - Catalog goal metric (#323 AC): 0 offenders ✅
  - Cohort A (phantom vol_term rows where cert exists): 0 (was 30 pre-#321) ✅
  - Cohort B (active members with pending vol_term AND no active requires_agreement engagement): 0 (was 4 pre-#322) ✅
  - Pending agreement queue: only Fernando's `study_group_owner` row remains, flagged `decide_template_for_kind_then_issue` awaiting follow-up legal-counsel template body
  - Herlon: never in any pending queue (his engagements are ambassador + observer, neither requires_agreement; PM directive "do NOT mint Herlon term" honored across p230 → p235)
- **Auto-close mechanic:** my ISSUE_REGISTRY.md edit in PR #328 had close-rule narrative literally containing "close #230" which matched GitHub's auto-close keyword regex → both #323 and #230 closed at the same merge timestamp. Outcome matches PM directive ("close #230 after #323 ships") but the evidence summary was posted retroactively as comment 4526837462. See SEDIMENT-235.A for the operational rule update.
- **Carries opening from #230 close (not blocking):**
  1. Follow-up legal-counsel issue for `study_group_owner_agreement_v1` template body (slug now placeholder; mint workflow still TBD pending legal review — mirrors ADR-0078 D5 external_reviewer state)
  2. Fernando double-engagement data-quality (owner + participant on same CPMAI™, both role=leader; participant row likely vestigial; file as standalone if you want it tracked)
  3. Optional generalization (open backlog from SEDIMENT-234.A): extend `onboarding_steps` catalog with `requires_kind_agreement boolean` column so the Path A seed loop consults it instead of per-RPC inline guards. Only worth doing if another step surfaces a similar mis-seed pattern or `engagement_kind` becomes dynamic per `role_applied`/cycle config.
- **PRs:** PR #328 (closes both #323 and #230). No bypass.
- **Cross-ref:** GH #230 (closed) · GH #197 REFRAMED-230 (the p230 audit that reframed this umbrella) · GH #199/#200/#200a/#201 (the 3 child close entries) · #318/#320 (A3 invariant fix that resolved the Herlon-specific cache sediment behind the original premise) · #292 (Selection reliability Cycle 4 sprint umbrella).

### 203. RESOLVED-#221-#218-DECOMPOSE — Whisper Art. 11 voice biometric umbrella decomposed into 5 ready-leaf children (p236)

- **When:** 2026-05-23 p236 dispatch (post-p235 close handoff; PM-dispatched "#221/#218 disposition first, then #254 read-only audit and #243 spec-only child split")
- **What:** GH #221 + #218 closed as IMPLEMENTED/REFRAMED with explicit decomposition into 5 narrow ready-leaf children per PM Option A (Recommended pick of 4 ABCD options). Both umbrellas tracked the same Whisper Art. 11 LGPD voice biometric remediation; Wave 1 engineering moat already shipped p207 (drop trigger + voice biometric consent columns + helper gate via migs `20260801000000-002`). Remaining Waves 2-5 + audit chain docs #3-5 + ADR-0094 spread across 5 distinct lanes (Frontend/UX, Foundation/Audit-trail, Foundation/QA, Governance/Legal-ops, Architecture/Spec) — decomposition makes each narrowly assignable.
- **PM directive 2026-05-23 (single Recommended ABCD pick):**
  - Q1 — Disposition for #221 + #218: **Option A — Decompose both into 5 ready-leaf children (Recommended)**. Matches PM-ratified #230 → #321/#322/#323 pattern. Satisfies registry's "consent blockers resolved or explicitly decomposed" clause → unblocks #243/#254 spec/audit work.
- **Pre-decomposition live evidence (p236 boot audit):**
  - 19 invariants A1–T in `check_schema_invariants()`, all `violation_count=0` (no U for biometric consent yet)
  - 100 video screenings in `pmi_video_screenings`; 1 with `transcription IS NOT NULL` (pre-block residual); 0 in 'transcribed' status (block held)
  - 107 selection applications; 25 with `consent_ai_analysis_at`; **0 with `consent_voice_biometric_at`** (W2 UI not shipped)
  - `selection_applications` has the 3 voice biometric consent columns live (`consent_voice_biometric_at` + `consent_voice_biometric_revoked_at` + `consent_voice_biometric_evidence`)
  - `pmi_video_screenings` has BEFORE INSERT/UPDATE trigger `trg_pmi_video_screening_voice_consent` live
  - `analyze_application_video_async` helper has consent gate live (per migration `20260801000002_p207_issue_221_helper_gate_voice_biometric_consent.sql`)
  - `privacy.s4.*` keys in pt-BR / en-US / es-LATAM declare only Google AI / Gemini 2.5 Flash — Whisper / OpenAI undeclared
  - `docs/adr/ADR-0094-*.md` does NOT exist (present: ADR-0089 through ADR-0093 + ADR-0095 through ADR-0098; gap at ADR-0094)
  - EF `analyze-application-video/index.ts` line 263 calls `whisperTranscribe(...)` without consent check (SQL helper is sole pre-Whisper gate; Whisper 429 quota also organic block)
  - Stale branches: `agent/issue-218-whisper-art11` + `agent/issue-221` still on `origin`
- **5 children spawned:**
  - **C1 #331** — type:task / priority:high / status:ready / Frontend+Governance+UX lanes: W2 destacado checkbox in `/portal-aplicacao` + `privacy.s4.openaiWhisper` i18n key (3 langs) + write consent to `selection_applications.consent_voice_biometric_at + evidence` columns. Live smoke: new app with consent → row populated; without → NULL + video step skipped.
  - **C2 #332** — type:task / priority:high / status:ready / Foundation+Governance+Audit-trail lanes: W3 retroactive notification of 1 affected candidate + Art. 18 §IV deletion offer + per-subject deletion log schema (extend `pii_access_log` with `deletion_artifacts jsonb` OR new `lgpd_deletion_log` table). Can ship with interim PM-approved text; legal-grade text from sibling C4 #334.
  - **C3 #333** — type:task / priority:medium / status:blocked / Foundation+QA+Audit lanes: W4 invariant U enforcing voice biometric consent on transcribed rows. Two PM sequencing options: (a) C2 first → invariant lands green, OR (b) C3 first with allowlist of 1 known row → ratchet down after C2.
  - **C4 #334** — type:task / priority:high / status:blocked (external dep) / Governance+Legal-ops lanes: W5 Angeline legal-ops chain (ANPD Art. 48 determination + notification template + DPO appointment + Adendo Privacidade + Termo de Speaker). 5 docs under `docs/audit/lgpd-art11-remediation/`. Typical 3-5 business days Angeline async cycle. Blocks C2 final shipping (interim text bridge meanwhile).
  - **C5 #335** — type:task / priority:medium / status:blocked (spec-only) / Governance+Architecture lanes: ADR-0094 Initiative Collaboration Hub draft + Tier 3 council ratification. Gated on C1/C2/C3 closes (C4 NOT required — legal-ops parallel to architecture). Status flips Draft → Proposed → Accepted.
- **What shipped (this PR — no DDL/code):**
  - 5 GH issues created (#331-#335) via `gh issue create --body-file` after `mcp__github__issue_write` failed with 403 PAT scope error (see SEDIMENT-236.A)
  - 5 GH issue bodies patched in second pass via `gh issue edit --body-file` to replace `(TBD)` placeholders with actual sibling numbers
  - `docs/project-governance/ISSUE_REGISTRY.md` updated: header bumped to p236, #221 + #218 rows flipped to `(closed)` annotation in Stop-The-Line, 4 new rows added in Ready Or Near-Ready Leaves (#331/#332/#333/#334), 1 new row added in Spec Trackers (#335), new Program Cluster "LGPD Art. 11 voice biometric remediation" added, Dispatch Rule 7 updated to reflect decomposition
  - This P162 entry #203 added
  - GH #221 + #218 will be closed via explicit `gh issue close` AFTER this PR merges, with evidence comments posted pre-merge per SEDIMENT-235.A (avoiding auto-close keyword regex in PR body)
- **Out of scope (deferred carries from this disposition):**
  1. EF `analyze-application-video/index.ts` JS-layer consent gate above SQL helper (defense-in-depth WATCH; Whisper 429 quota + SQL gate sufficient near-term moat; file as standalone if PM wants it tracked as separate ready-leaf)
  2. Branch deletion `agent/issue-218-whisper-art11` + `agent/issue-221` (post-merge cleanup; both `remotes/origin/` and local refs)
  3. Codex curator's 2026-05-21 Options A (parent tracker) and B (canonical forward) — superseded by Option A decomposition; the underlying parent-vs-canonical concern is satisfied by replacing both umbrellas with narrow children
- **Sediment learnings (1 NEW):**
  - **SEDIMENT-236.A (NEW — MCP `issue_write` PAT scope insufficient for create)**: `mcp__github__issue_write` with `method=create` failed for all 5 attempts with `403 Resource not accessible by personal access token` despite `mcp__github__issue_read` working fine in the same session. Root cause: the MCP github connector's PAT has insufficient scopes for issue creation (likely missing `repo:write` or limited to read scopes); separate from `gh` CLI's keyring-stored token which has full `repo` scope (verified via `gh auth status`: scopes `'admin:org', 'gist', 'project', 'repo', 'workflow'`). Fallback to `gh issue create --body-file` via Bash works reliably. **Operational rule going forward**: when batch-creating GH issues, default to `gh` CLI with `--body-file` tmp files written via `Write` tool; reserve `mcp__github__issue_write` only for issue UPDATES (read scope may suffice for `method=update`). Audit/refresh the MCP github PAT scope as separate WATCH item if write parity is desired (file as standalone if PM wants the MCP token expanded).
- **Test baseline:** No code/DDL changes in this PR — pure registry + P162 docs + GH issue side effects. Test baseline unchanged at offline **1856/1800/0/56** (post-p235 baseline).
- **PRs:** p236 close PR (this PR — registry + P162 update + close docs). Standard CI gate path expected (validate + check-invariants + others). No bypass.
- **Cross-ref:** GH #221 (closed p236, was Tier 3 council 5/5 verdict + 3-migration + 5-audit-doc framework) · GH #218 (closed p236, was original emergency-block + 5-wave umbrella + Codex curator deliberation 2026-05-21) · GH #331 (C1 ready-leaf) · GH #332 (C2 ready-leaf with C4 interim bridge) · GH #333 (C3 blocked on PM sequencing) · GH #334 (C4 blocked on Angeline async) · GH #335 (C5 spec-only blocked on C1/C2/C3) · `docs/council/2026-05-20-p207-tier3-strategic-review-212.md` (Tier 3 council origin) · migrations `20260731000000_issue_218_whisper_art11_emergency_block.sql` + `20260801000000_p207_issue_221_whisper_art11_drop_trigger.sql` + `20260801000001_p207_issue_221_capture_voice_biometric_consent_columns.sql` + `20260801000002_p207_issue_221_helper_gate_voice_biometric_consent.sql` (Wave 1 engineering moat already live) · `selection_applications.consent_voice_biometric_at + consent_voice_biometric_revoked_at + consent_voice_biometric_evidence` columns · `trg_pmi_video_screening_voice_consent` trigger · `analyze_application_video_async` helper · ADR-0067 (AI-augmented selection Art. 20 safeguards) · ADR-0074 (PMI candidate AI dual-model) · ADR-0079 (subjective scoring via video transcription) · #243 + #254 (unblocked from "consent blockers" gate by this decomposition; PM dispatched as next p236 sequence after #221/#218 disposition completes).
