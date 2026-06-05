# ADR-0022: Communication Batching — Weekly Digest como Default, Transactional como Exceção

- Status: Accepted (2026-04-26 p48 — W1 substrate shipped)
- Data: 2026-04-22 (proposta) / 2026-04-26 (aceitação após W1 deploy)
- Autor: Claude (parallel tracking com PM Vitor Rodovalho)
- Escopo: Estabelece princípio arquitetural para toda comunicação email da plataforma aos members. Governa integrações futuras incluindo issue [#97 G7](https://github.com/VitorMRodovalho/ai-pm-research-hub/issues/97) (engagement welcome), [#98](https://github.com/VitorMRodovalho/ai-pm-research-hub/issues/98) (weekly card digest), [#88](https://github.com/VitorMRodovalho/ai-pm-research-hub/issues/88) (invitation flow), [#91](https://github.com/VitorMRodovalho/ai-pm-research-hub/issues/91) (offboarding cascade), e qualquer nova feature que envolva notificação.

## Contexto

### Estado em 2026-04-22

A plataforma hoje envia (ou se propõe a enviar, via issues abertas) múltiplos emails dispersos ao mesmo member ao longo da semana:

- `attendance_reminder` — disparado antes de cada evento (pode ser 2-3x/semana por member)
- `attendance_detractor` — weekly Monday 14h
- `assignment_new` / `card_assigned` / `card_status_changed` — evento a evento conforme board movement
- `certificate_ready` / `certificate_issued` — por ratificação
- `ip_ratification_gate_pending` — por gate
- `governance_vote_reminder` — por votação ativa
- `tribe_broadcast` — toda vez que líder dispara
- `volunteer_agreement_signed` / `webinar_status_confirmed` — transacional
- `publication` / `system` / `system_alert` — misc
- **Futuros: welcome (G7), weekly card digest (#98), invitation (#88)**

Paralelamente, o PM mantém "mala direta" manual (weekly broadcast via WhatsApp + email individual) com: próximos eventos, cards esperados, anúncios gerais, lembretes de prazos, publicações novas.

### Problema

1. **Fricção do usuário** — receber 5-10 emails por semana da mesma plataforma reduz abertura e engajamento. Email fatigue crescente.
2. **Duplicação de esforço** — PM preenche manualmente o que a plataforma já tem em dados estruturados (eventos, cards, publicações).
3. **Efetividade decrescente** — 1 email consolidado semanal tem open rate + action rate tipicamente 2-3× maior que N emails transacionais mesma semana (benchmark Substack/GitHub/Linear).
4. **Inconsistência de voz** — PM voice + platform voice + broadcast voice = 3 fontes. Member confunde o que é oficial.
5. **Economia operacional** — GP gasta 1-2h/semana curando a mala direta; trabalho repetível.

### Tensões

- Nem toda comunicação pode esperar sábado. Emails transacionais time-sensitive (password reset, OAuth verification, IP ratification deadline < 24h, certificate pronto para counter-sign em janela de 48h, offboarding notice) precisam ir imediatamente.
- Members que são também **líderes** precisam de visão agregada diferente (tribe health, overdue de outros), não lista pessoal.
- Alguns members podem preferir receber tudo imediatamente (high-engagement power users) — opt-out do digest deve existir.

## Decisão

### Princípio

> **Por default, toda comunicação ao member consolida num digest semanal no sábado 09:00 BRT (12:00 UTC). Exceções são notificações transacionais time-critical, explicitamente classificadas.**

### Classificação — 3 delivery modes

Toda nova `notifications.type` deve declarar explicitamente seu delivery mode:

| Mode | Quando entregar | Exemplos |
|---|---|---|
| `transactional_immediate` | ASAP (< 5min via cron `send-notification-emails`) | password reset, OAuth verify, certificate counter-sign < 48h window, IP ratification < 24h, security alert, urgent system_alert |
| `digest_weekly` | **Default.** Acumula até sábado 12:00 UTC, entregue consolidado | card assigned, card status changed, engagement welcome, attendance reminder upcoming week, tribe broadcast non-urgent, webinar announcement, publication published, routine governance reminders |
| `suppress` | Não enviar email (só in-app) | low-priority info, system logs, detractor flags (in-app only) |

### Novo schema

```sql
ALTER TABLE public.notifications
  ADD COLUMN IF NOT EXISTS delivery_mode text NOT NULL DEFAULT 'digest_weekly'
    CHECK (delivery_mode IN ('transactional_immediate','digest_weekly','suppress')),
  ADD COLUMN IF NOT EXISTS digest_delivered_at timestamptz,
  ADD COLUMN IF NOT EXISTS digest_batch_id uuid;

CREATE INDEX IF NOT EXISTS idx_notifications_digest_pending
  ON public.notifications (recipient_id, created_at)
  WHERE delivery_mode = 'digest_weekly' AND digest_delivered_at IS NULL;
```

### Catálogo inicial de mapping (para review do time dev)

| notifications.type atual | Delivery mode proposto |
|---|---|
| `assignment_new`, `card_assigned`, `card_status_changed` | `digest_weekly` |
| `attendance_reminder` | `digest_weekly` (se evento > 48h) / `transactional_immediate` (se ≤ 48h e crítico) |
| `attendance_detractor` | `suppress` (só in-app) |
| `certificate_ready` | `transactional_immediate` (janela curta de counter-sign) |
| `certificate_issued` | `digest_weekly` |
| `ip_ratification_gate_pending` | `transactional_immediate` (time-bound) |
| `governance_vote_reminder` | `digest_weekly` (se > 7d) / `transactional_immediate` (se ≤ 7d) |
| `tribe_broadcast` | Decidido pelo líder ao enviar: flag `urgent=true` → immediate / default → digest |
| `info`, `system` | `suppress` (só in-app) |
| `system_alert` | `transactional_immediate` |
| `publication` | `digest_weekly` |
| `volunteer_agreement_signed` | `transactional_immediate` (confirmation é time-sensitive) |
| `webinar_status_confirmed` | `digest_weekly` |
| **`engagement_welcome` (novo, G7)** | **`transactional_immediate`** (ver tensão abaixo) |
| **`weekly_card_digest_member` (novo, #98)** | É o próprio digest — delivery natural |
| **`weekly_card_digest_leader` (V2, #98)** | É o próprio digest (versão leader) |

### Integração com #97 G7 e #98

#### G7 engagement welcome

Tensão: welcome idealmente é timely (member acabou de ser adicionado, quer feedback). Mas se N welcomes caem na semana, bundling faz sentido.

Recomendação: **`transactional_immediate` como default**, mas com regras:
- Se kind tem `requires_agreement=true` (volunteer, external_signer) → sempre immediate (termo para assinar)
- Se kind é `speaker` de congress com deadline externo < 14d → immediate
- Caso contrário (observer, committee_member, study_group_participant, guest) → pode ser `digest_weekly` (first-section do digest destaca "você foi adicionado a X esta semana")

Implementação: EF `send-notification-email` decide com base em `delivery_mode` da row + fallback para digest se delivery_mode='digest_weekly'.

#### #98 weekly card digest → **renomear escopo**

Antes: só cards assignados ao member.

Agora (pós-ADR-0022): **member weekly digest** unificado incluindo:
1. Cards: this_week_pending + next_week_due + overdue_7plus (escopo original #98)
2. Engagements novos da semana (se `engagement_welcome` foi batched)
3. Eventos próxima semana onde member é elegível (da tribo + iniciativas)
4. Publicações novas da semana (series que member segue)
5. Broadcasts da tribo (não-urgentes que acumularam)
6. Governance pendente (votes/ratifications abertas, não-urgentes)
7. Achievements: certificados emitidos, XP ganho, leaderboard position

Renomear spec: `SPEC_WEEKLY_CARD_DIGEST.md` → **`SPEC_WEEKLY_MEMBER_DIGEST.md`**. RPC renomeia: `get_weekly_card_digest` → `get_weekly_member_digest`.

Leader version (V2): digest dedicado inclui aggregate tribe stats (parcerias que tem IP/auth pendentes, eventos agendados, health score) em vez de replicar o member digest.

### Substituição da mala direta do PM

GP tem hoje workflow manual de weekly broadcast. Com ADR-0022 executado:
- **PM não precisa mais escrever email semanal de rotina.** A plataforma gera automaticamente.
- PM pode intervir via `tribe_broadcast` com flag `urgent=true` para entrega imediata; ou adicionar conteúdo customizado que entra no digest do sábado como "mensagem do GP" (nova seção opcional).
- Tempo economizado: 1-2h/semana.

## Consequências

### Positivas

- **-60% a -80% no volume de emails/member/semana** (estimativa inicial: de ~6-8 emails → 1-2 emails)
- **PM libera 1-2h/semana** de curation manual
- **Open rate + action rate** tipicamente 2-3× maior com digest vs scattered (benchmark setor)
- **Voice consistency** — plataforma tem 1 voz semanal ao invés de N
- **Data-driven broadcast** — conteúdo sai de dados estruturados já existentes; reduz drift entre "o que a plataforma sabe" vs "o que o PM comunica"
- **Opt-out granular** — member escolhe digest_weekly, immediate_all (legacy), ou só in-app

### Negativas / Custos

- Member em zona de tempo extrema (UTC-10, UTC+12) pode receber sábado local = terça-feira às 23h — aceito como trade-off MVP; V3 endereça timezone per-member.
- `delivery_mode` forçado em toda nova notification.type futura — contract test deve validar que migrations novas declaram explicitamente.
- EF `send-notification-email` fica mais complexo (roteamento por mode). Mitigação: dividir em 2 EFs? `send-transactional-email` (a cada 5min, só `transactional_immediate`) + `send-weekly-digest` (sábado 12:00 UTC) — mais limpo operacionalmente. Team dev decide.
- Legacy notifications já na tabela (antes do ADR) precisam backfill de `delivery_mode`. Pragma: default `digest_weekly` via column default já resolve; não-processadas serão entregues no próximo digest.

### Riscos

- **Member expecta reativo para algo que caiu no digest** (ex: "achei que ia receber email assim que virei observer"). Mitigação: UX claro nas settings explicando o tradeoff; option "immediate_all" como escape hatch.
- **Digest muito cheio em weeks de alta atividade** → scroll fadigue. Mitigação: UI hierárquico (collapsible sections), limite N items por seção com link "ver todos".
- **Integração com `tribe_broadcast` pode virar abuso** — líder marca tudo urgent. Mitigação: rate-limit de urgent broadcasts por líder (ex: 1/semana) ou flag review.

## Implementação proposta — 3 waves

### W0 (0 migration, documental)

- [x] ADR-0022 este doc (Proposed)
- [x] Atualizar SPEC_ENGAGEMENT_WELCOME_EMAIL.md com seção "Delivery mode" e matriz de kinds
- [x] Renomear SPEC_WEEKLY_CARD_DIGEST.md → SPEC_WEEKLY_MEMBER_DIGEST.md com escopo expandido
- [ ] Team dev review ADR em sprint planning

### W1 (schema aditivo + EF split, ~1 sprint) — **SHIPPED 2026-04-26 p48**

- [x] Migration: `notifications.delivery_mode` + `digest_delivered_at` + `digest_batch_id` + partial index (`20260513060000`)
- [x] Backfill: 5 mandatory-immediate types + 3 suppress types em migration inicial; expansão para 15 transactional_immediate em `20260513080000` para preservar V1 EF behavior
- [x] Split EF: `send-notification-email` agora filtra `WHERE delivery_mode='transactional_immediate' AND email_sent_at IS NULL` (catalog-driven em vez de hardcoded CRITICAL_TYPES); `send-weekly-member-digest` deployed como W1 stub (não envia email — apenas conta pending; W2 implementa conteúdo)
- [x] Producer updates: helper `public._delivery_mode_for(p_type)` central + 3 overloads de `create_notification` + 3 producers diretos (`notify_offboard_cascade`, `sign_volunteer_agreement`, `counter_sign_certificate`) setam delivery_mode no INSERT
- [x] Contract test: `tests/contracts/adr-0022-delivery-mode.test.mjs` (7 tests) — catalog parity + CHECK constraint + index existência + helper function shape
- [x] Catalog: `docs/adr/ADR-0022-notification-types-catalog.json` — 19 types mapeados com rationale
- [x] Cron entry: `send-weekly-member-digest` Saturday 12:00 UTC (jobid 26); `send-notification-email` cron 5min preserved (jobid 9)
- [x] Behavior change accepted: `attendance_detractor` movido de "EF emailed" para `suppress` per ADR-0022 §Pendências (PM accepted)

### W2 (digest content + UX, ~1 sprint)

- Implementar `get_weekly_member_digest(p_member_id)` com as 7 seções
- Template HTML rico (responsive, brand Núcleo, collapsible sections)
- Settings UI: toggles per-type + global "preferência de entrega: digest_weekly | immediate_all | suppress_all"
- Migration RLS: member vê/edita só seu próprio `notify_*` preferences

### W3 (leader digest + smart, ~1 sprint)

- Leader digest V2 (issue #98 V2)
- Smart skip: digest vazio (0 items em todas seções) não é enviado
- Rate limit tribe_broadcast urgent: 1/semana/líder
- Analytics dashboard: open rate, action rate, unsubscribe rate

## Cross-ref

- [#97](https://github.com/VitorMRodovalho/ai-pm-research-hub/issues/97) G7 — engagement welcome delivery mode definido
- [#98](https://github.com/VitorMRodovalho/ai-pm-research-hub/issues/98) — escopo expandido (card digest → member digest unificado)
- [#88](https://github.com/VitorMRodovalho/ai-pm-research-hub/issues/88) — invitation/convocação deve seguir mesma matriz (accept/decline = transactional, reminder = digest)
- [#91](https://github.com/VitorMRodovalho/ai-pm-research-hub/issues/91) — notification cascade pós-offboarding: offboard notice = transactional, bye-bye recap = digest
- [#82](https://github.com/VitorMRodovalho/ai-pm-research-hub/issues/82) — `idx_notif_recipient_unread` (198k scans) será hit massivamente; novo `idx_notifications_digest_pending` parcial reduz scan cost

## Pendências

- [x] **W1 PM defaults aplicados (2026-04-26)**: digest_weekly como default único (UI 4-mode deferred to W2); EF split = Option A (2 EFs); column name = `delivery_mode`; 5 mandatory-immediate producers updated em W1 (12 outros opportunistic em W2/W3); attendance_detractor → suppress; tribe_broadcast urgent rate-limit deferred to W3.
- [ ] W2 dev team review: settings UI para opt-out (4 modos: immediate_all / weekly_digest / suppress_all / custom_per_type)
- [ ] W2: implementar `get_weekly_member_digest` RPC + send-weekly-member-digest EF body (atual = stub)
- [ ] W3: leader digest, smart-skip empty digest, rate-limit tribe_broadcast urgent (1/week/leader)
- [ ] Stakeholder review: validar com Roberto+Ivan+Fabricio+Sarah+curadoria se algum kind de notification é sensível a latência (ex: review gate pending) — review window pós-W2
- [ ] CR-051 (formal): converter ADR-0022 para CR formal de ratificação ainda? Ou ADR-0022 Accepted suficiente até CBGPL?

---

## Amendment B — W3 Leader Digest Sections v2 (p162 Track B', 2026-05-15)

**Status:** Accepted (PM ratified after council deliberation)
**Driver:** Initial Track B proposed gate-at-publish UI modal for Champion capture in ata flow. Council (6 lenses: 3 personas + product-leader + ux-leader + data-architect) flagged friction + mobile + dual-write risks. PM pivoted to **digest-based reminder** — non-blocking, recurring rhythm, multi-domain coverage.

### Adições ao W3 Leader Digest

`get_weekly_tribe_digest(p_tribe_id integer)` ganha 3 seções além dos 8 agregados de cards existentes:

1. **`ata_pending`** — eventos `type IN (tribo,geral,lideranca)` no ciclo atual, passados, sem `meeting_artifacts.is_published=true`. **Recurrence-grouped** por `events.recurrence_group` (uma série de 4 ocorrências sem ata aparece como 1 grupo, não 4 alertas). Top-3 grupos com `sample_title`, `occurrence_count`, `latest_date`, `latest_event_id`.

2. **`attendance_pending`** — eventos do ciclo passados, mesmo escopo de tipos, com **zero rows em `attendance`** (`NOT EXISTS`). Distinção semântica: NÃO inclui eventos com `present=false + excused=true` (ausência justificada já é registro). Top-3 events com event_id/title/date.

3. **`champion_pending`** — eventos do ciclo passados, mesmo escopo, com **zero `champions_awarded` ativos** (heurística pura). Aceita falso positivo: líder que decidiu verbalmente "Nenhum" aparece pendente eternamente. Coluna `events.event_champion_waived` futura (G1 deferred) elimina.

### Decisões PM ratificadas (D-arq-1 a D-arq-7)

| ID | Decisão | Justificativa |
|---|---|---|
| D-arq-1 | **NÃO** adicionar `meeting_artifacts.champion_decision jsonb`. Alternativa: `events.event_champion_waived boolean` + trio (waived_at/by/reason) pattern p160 soft-cancel — **G1 deferred opcional** | Evita TOAST composto em ma; tipo boolean explícito; predicate index seletivo |
| D-arq-2 | G1 não é load-bearing para G2. Digest funciona com heurística pura | Senior-engineer: ata pendente detecta por is_published ausente, não precisa champion column |
| D-arq-3 | G0 (RLS V3 fix de meeting_artifacts, item #12) deferred pois Track B' não toca a tabela | RLS violation continua aberta no log, mas não bloqueia digest |
| D-arq-4 | Recurrence GROUP BY na ata_pending; COALESCE para eventos `type=geral` sem initiative_id | Reduz noise no email; cobre eventos institucionais sem tribe binding |
| D-arq-5 | Extender este ADR-0022 como Amendment B, NÃO criar ADR novo | Track B' é concretização de W3 W3 existente; ADR-0081 = domínio errado (Champion ledger) |
| D-arq-6 | Adicionar invariantes O + P agora (defesa anti-drift FK + V3-V4 bridge cron) | Baratas, independentes de Track B' funcionamento |
| D-arq-7 | Phasing: G2a + G2b nesta sessão (foundation); G3 + G3b + G4 + G5 em p163 | Splita 7.5h em 2 sessões; permite smoke real Sat 12:30 entre elas |

### Migrations shipped (p162 ondas)

- `20260655000000` G2a — `get_weekly_tribe_digest` com 3 seções novas
- `20260656000000` G2b — `generate_weekly_leader_digest_cron` v_has_signal estendido + invariantes O + P em check_schema_invariants
- `20260657000000` — Hotfix invariant P (integer→uuid cast removed)

### Pendências (p163+)

- G3a: extend `send-notification-email` HTML template com 3 sections + CTAs (Publicar Ata / Marcar Presença / Conferir Champion) — PT-BR inline + tech debt i18n trilingual
- G3b: URLSearchParams deep link readers em `/attendance` e `/admin/gamification` para pre-fill modal
- G4: smoke real cron Sat 12:30 + verify email render para Roberto/Sarah/Fabricio/líderes
- G5: contract test `tests/contracts/weekly-tribe-digest.test.mjs` (cobertura 3 sections + recurrence grouping + hide-if-empty)
- G1 (opcional): migration `events.event_champion_waived` + trio para eliminar falso positivo de champion_pending
- Backlog item #17 (V4 leader identification): `get_weekly_tribe_digest:47` ainda usa `tribes.leader_member_id` (V3) em vez de auth_engagements. Não bloqueia smoke; pre-req para rollout multi-chapter.
- Backlog A3 drift (7 membros): Sarah, Roberto, Fabricio, Leticia, Maria Luiza, Mayanna, Eder — operational_role precisa backfill após Track E trigger extension (continuation Track E).

### Cross-refs

- `docs/council/p162_track_b_design_call.md` — deliberação 6 lenses (1ª rodada gate-at-publish)
- `docs/council/p162_track_b_prime_architecture_audit.md` — auditoria 3 lenses (data-arch + guardian + senior) que motivou pivot
- `docs/audit/P162_GAP_OPPORTUNITY_LOG.md` — itens 16-21 novos + carry-forward
- ADR-0081 — Champion ledger (NÃO host do digest; cross-ref domain)
- ADR-0028 — privacy-preserving aggregates (princípio honrado nas 3 seções: nenhuma exposição individual)
- ADR-0012 Princípio 2 — cache column requires trigger (champion_decision evitada por essa razão)

---

## Amendment C — Multi-leader + Initiative-aware Digest (p172 #21 + p173, 2026-05-16/17)

**Status:** Accepted (PM ratified inline durante shipping)
**Driver:** V4 N:N model permite múltiplos líderes ativos por initiative (item #21 OPPORTUNITY no P162_GAP_LOG) + cron tribe-centric era subset; non-tribe initiatives (workgroup/committee/study_group/congress) com leaders eram invisíveis (PM ask 2026-05-17).

### Evolução semântica do cron

| Versão | Iteração | Cardinalidade líder/digest | Cobertura |
|--------|----------|---------------------------|-----------|
| Pré-p172 | `tribes WHERE is_active=true` | 1 líder por tribo (`tribes.leader_member_id` V3 cache) | 7 tribos |
| p172 #21 | `tribes WHERE is_active=true` | N líderes via `_v4_initiative_leader_member_ids` (leader + co_leader engagements V4) | 7 tribos |
| p173 | `_v4_active_initiatives_with_leaders()` | N líderes por initiative via `_v4_leader_member_ids_by_initiative(uuid)` (leader/co_leader/coordinator/owner) | 13 initiatives (tribes + workgroups + committee + study_group + congress) |

### Decisões PM ratificadas

| ID | Decisão | Justificativa |
|---|---|---|
| D-mc-1 | p172: substituir `_v4_tribe_leader_member_id` (single uuid) por `_v4_initiative_leader_member_ids` (SETOF uuid) | V4 N:N requer plural. Backward compat preservada via tribe-id parameter |
| D-mc-2 | p173: refactor cron de tribe-centric pra initiative-centric. Helper `_v4_active_initiatives_with_leaders()` retorna todas inits ativas com >=1 leader | PM ask 2026-05-17 surfaced gap: 8 leaders non-tribe invisíveis pre-p173 |
| D-mc-3 | Notification type permanece `'weekly_tribe_digest_leader'` mesmo após p173 refactor | Email handler `send-notification-email` reads tribe_name/tribe_health_pct. Mudar type = handler refactor + risk. Back-compat via payload aliases (tribe_name=initiative_name, tribe_id=legacy_tribe_id). Title atualizado pra "Resumo semanal: <initiative_name>" |
| D-mc-4 | RPC novo `get_weekly_initiative_digest(uuid)` em vez de modificar `get_weekly_tribe_digest(integer)` | Latter ainda usado por MCP tool + frontend. Coexist é cheap; deprecation pode vir em session dedicated futura |
| D-mc-5 | Leader roles incluem `leader/co_leader/coordinator/owner` em p173 (vs `leader/co_leader` em p172) | Workgroups usam `coordinator` (Hub Comm), congress usa `coordinator` (LATAM LIM). `owner` reserved p futuro |
| D-mc-6 | NÃO filtrar por `is_authoritative=true` em helpers de leader-membership | Cert-pending leaders (Herlon CPMAI study_group_owner auth=false, Vitor LATAM LIM coord auth=false) ainda devem receber digest. Digest = notification, não permission grant |
| D-mc-7 | Eventos `type='geral' AND initiative_id IS NULL` incluídos APENAS para initiatives tribe (legacy_tribe_id NOT NULL) | Pre-p173 todos digests incluíam geral events (1 tribe → 1 digest). Post-p173 múltiplas initiatives → cada digest somaria N× → ruído. Decision: keep geral em tribes (back-compat) + exclude de non-tribe |

### Migrations shipped

- `20260676000000` (p172) — `_v4_initiative_leader_member_ids` SETOF helper + cron LOOP per leader em tribes
- `20260678000000` (p173) — `_v4_active_initiatives_with_leaders()` + `_v4_leader_member_ids_by_initiative(uuid)` + `get_weekly_initiative_digest(uuid)` + cron DROP+CREATE com new signature (initiative_id/initiative_name columns no RETURN TABLE)

### Cobertura sat 2026-05-23 09:30 BRT (primeira execução p173)

15 leaders notified-eligible (dry-run validated):

**Tribes (7):**
- Hayala Curto · Débora Moura · Fernando Maquiaveli · Jefferson Pinto · Fabricio Costa · Marcos Antunes Klemz · Ana Carla Cavalcante

**Non-tribe (8):**
- Hub Comunicação (3): Leticia · Maria Luiza · Mayanna
- Publicações & Submissões (3): Fabricio · Roberto · Sarah
- CPMAI Study Group (1): Herlon
- LATAM LIM Congress (1): Vitor

**Auto-skip (correto):** Curadoria + Newsletter (no signal — sem pending events/cards). Tribe 3 (TMO) is_active=false.

### Riscos/Trade-offs aceitos

1. **Email subject still says "Resumo da sua tribo"** (subject hardcoded em `SUBJECT_BY_TYPE` map do EF). Cosmetic — funcional via notif.title override. Carry p174: update `SUBJECT_BY_TYPE['weekly_tribe_digest_leader']` para "Resumo semanal — Núcleo IA" (initiative-agnostic).

2. **Email handler body builder still named `buildWeeklyTribeDigestLeaderHtml`**. Funciona porque payload aliases preservados. Cosmetic — renomeação futura quando notification type migrate.

3. **Member orchestrator digest (`generate_weekly_member_digest_cron`) ainda independente** — segue lógica diferente (per-member instead of per-leader). Não impactado por p172/p173.

### Cross-refs

- p172 commit `17ece3a` — multi-leader per tribe (#21 partial)
- p173 commit `7956e84` — initiative-aware extension (#21 fully resolved)
- `docs/audit/P162_GAP_OPPORTUNITY_LOG.md` item #21 ✅ RESOLVED p173
- `memory/feedback_create_or_replace_full_body_fetch.md` — sediment de p172 #21 (CREATE OR REPLACE full body fetch antes de modificar)

---

## Amendment D — Selection Funnel Notification Policy Matrix (p228 #260 W2 Leaf 1, 2026-05-23)

**Status:** Accepted (PM ratified 2026-05-23, #260 comment 4525886931)
**Driver:** p227 W2 audit (`docs/audit/SELECTION_NOTIFICATIONS_W2_AUDIT_P227.md`) surfaced 17 candidate-facing selection_* notifications mis-routed via digest path over the 90d window, plus ADR-0022 catalog had ZERO selection_* entries (helper only had `selection_termo_due` from p159). Other selection_* types fell through ELSE → digest_weekly silently.

### Policy Matrix — 8 selection funnel types

| type | delivery_mode | candidate-facing? | rationale |
|---|---|---|---|
| `selection_termo_due` | `transactional_immediate` | Yes | Post-VEP-Active term + Lorena signature; cannot wait for weekly digest (p159, kept). |
| `selection_approved` | `transactional_immediate` | Yes | Approval is a milestone event; bundling erodes candidate experience. |
| `selection_interview_scheduled` | `transactional_immediate` | Yes | Calendar link + date/time must reach candidate before interview. |
| `peer_review_requested` | `transactional_immediate` | No (evaluator) | Evaluator needs prompt action to keep cycle moving; was already hardcoded at INSERT site `dispatch_peer_review_invitations`, now catalog+helper parity-locked. |
| `selection_evaluation_complete` | `suppress` | No (admin) | Internal signal; surfaced in dashboards. No email. |
| `selection_interview_noshow` | `digest_weekly` (explicit) | No (admin) | Admin recap, not time-critical. Made explicit for catalog parity + forward-drift detection. |
| `selection_interview_overdue` (new — W2 Leaf 2) | `digest_weekly` | No (admin) | Admin reminder; daily cron scans `selection_interviews WHERE scheduled_at < NOW() AND conducted_at IS NULL`, idempotent (1 notif per interview per week). |
| `selection_cutoff_approved` (new — W2 Leaf 4) | `transactional_immediate` | Yes | Candidate invitation to book interview after "2 objective evaluations + PERT ≥ cutoff". Time-critical. |

### PM ratified decisions (D-sel-1 to D-sel-5)

| ID | Decision | Justification |
|---|---|---|
| D-sel-1 | Adopt Policy Matrix as proposed (no per-type override) | Audit doc table aligns with candidate UX rationale + admin operational rhythm. |
| D-sel-2 | **Selective** replay of the 17 historical mis-routed rows, not blind: replay `selection_approved` + `selection_interview_scheduled` when still relevant; replay `selection_termo_due` only when candidate still has a real pending term/onboarding action; otherwise manual-close/document. | Avoid useless double-send for candidates who already saw the digest summary. Resend quota (100/day) trivially covers but signal-to-noise matters more. |
| D-sel-3 | **Soft** AI gate with `no_ai_context` path for `dispatch_peer_review_invitations`: if consent + analysis exist, peer review includes AI context; if absent, peer review may proceed without AI context. Do not simulate AI without consent. Admin override allowed only if audited. | Hard gate (status quo) blocked 14/38 cycle 4 apps; soft gate unblocks while preserving Art. 11 LGPD consent posture. |
| D-sel-4 | `notify_delivery_mode_pref = suppress_all` is bypassed by **candidate-facing operational selection_*** emails only (termo_due, approved, interview_scheduled, cutoff_approved). Marketing/digest/internal noncritical messages still respect suppress_all. | Candidate is in active workflow; opt-out for promotional vs operational must be split. Legal/UX rationale: workflow-critical operational > opt-out preference. |
| D-sel-5 | Peer-review dispatcher = **automatic + idempotent** (cron-driven) with manual override path retained + 24h health signal (`selection_emails_pending_24h`). | 18/38 cycle 4 apps were eligible-never-dispatched (manual trigger gap); cron closes that gap, health signal surfaces dispatcher silence. |

### Implementation phasing — 7 W2 Leaves

- **Leaf 1 (2026-05-23):** catalog backfill + helper parity for 6 existing selection_* types + contract test extension. Migration `20260805000008`.
- **Leaf 2 (2026-05-23):** `selection_interview_overdue` new type + daily `_selection_interview_overdue_cron()` at 14:00 UTC + one notification per (interview, interviewer) pair with 7-day idempotency window. Migration `20260805000009`.
- **Leaf 3 (2026-05-23):** soft AI gate (`no_ai_context` path) in `dispatch_peer_review_invitations`. Removes hard `PEER_PRECONDITION` raise; adds `p_force_no_ai_context boolean DEFAULT false` parameter (admin override). Notification body + admin_audit_log + return jsonb all carry `no_ai_context` + `no_ai_reason ∈ {no_consent, analysis_pending, admin_override, NULL}`. Authority gate unchanged. Migration `20260805000010`.
- **Leaf 4 (2026-05-23):** `selection_cutoff_approved` new type + foundation. Helper case `transactional_immediate`; idempotency column `selection_applications.cutoff_approved_email_sent_at`; multi-lang campaign template `selection_cutoff_approved` (PT-BR/EN/ES); manual dispatch RPC `notify_selection_cutoff_approved(p_application_id)` with committee-lead-or-manage_member authority, idempotent single-fire, audit log. Cycle's `interview_booking_url` is CTA. **Auto-trigger deferred to PM follow-up** — admin invokes RPC manually until cron lands (decision needed on threshold formula + transition vs cron). Migration `20260805000011`.
- **Leaf 5 (2026-05-23):** one-shot RPC `_replay_selection_notifications_p228(p_dry_run)` with dry-run default. Identifies 17 historical mis-routed rows (window 2026-05-01..2026-05-20), applies per-type selective criteria per PM D-sel-2, returns eligible_replay + manual_close breakdown. p_dry_run=false UPDATEs eligible rows + writes admin_audit_log. Live dry-run smoke: 2 eligible (selection_approved recent+active) + 15 manual_close. Migration `20260805000012`.
- **Leaf 6 (2026-05-23):** operational suppress_all bypass for the 4 candidate-facing operational types (selection_termo_due, selection_approved, selection_interview_scheduled, selection_cutoff_approved). SQL helper `_is_operational_candidate_facing(p_type text)` is source-of-truth; EF `send-notification-email` matches the Set byte-for-byte in lock-step. PM D-sel-4 explicit: workflow-critical operational > opt-out preference (candidate-facing only — evaluator/admin-facing types still respect suppress_all). Migration `20260805000013`.
- **Leaf 7 (2026-05-23):** 24h dispatcher silence health signal `get_selection_emails_pending_24h(p_alert_threshold integer DEFAULT 10)`. STABLE SECDEF RPC returns jsonb {total_pending, by_type, oldest_pending_at, oldest_age_minutes, alert_threshold, alert_triggered}. Counts selection_* + delivery_mode=transactional_immediate + email_sent_at NULL + created_at > NOW()-24h. Healthy state ~0 (cron picks up within 5min). Authority: manage_member/manage_platform admin path; service_role for cron auto-monitoring. MCP tool registration deferred to p229 fast-follow. Migration `20260805000014`.

### Cross-refs

- p159 commit `a3a91a9d` — `selection_termo_due → transactional_immediate` (single-type predecessor)
- p228 #260 comment 4525886931 — PM Policy Matrix ratification
- p227 audit doc `docs/audit/SELECTION_NOTIFICATIONS_W2_AUDIT_P227.md` — 90d evidence pack
- #292 sprint umbrella — Selection Reliability Cycle 4 sprint
- Migration `20260805000008_p228_260_w2_leaf1_selection_notification_catalog_helper_parity.sql` — Leaf 1 shipping migration
