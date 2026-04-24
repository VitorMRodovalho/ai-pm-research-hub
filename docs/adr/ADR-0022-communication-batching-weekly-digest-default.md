# ADR-0022: Communication Batching — Weekly Digest como Default, Transactional como Exceção

- Status: Proposed (2026-04-22 p35, sessão `d211ff`)
- Data: 2026-04-22
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

### W1 (schema aditivo + EF split, ~1 sprint)

- Migration: `notifications.delivery_mode` + `digest_delivered_at` + `digest_batch_id` + index
- Backfill: mapear `type` → `delivery_mode` conforme catálogo acima (pode ficar em migration separada para evitar lock longo)
- Split EF: `send-notification-emails` (a cada 5min, filtrar `WHERE delivery_mode='transactional_immediate' AND sent_at IS NULL`) + nova `send-weekly-member-digest` (sábado 12:00 UTC via cron)
- Contract test: toda migration futura que adicionar novo type em notifications deve declarar `delivery_mode`

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

- [ ] Validar com PM os opt-outs: weekly-only é o default correto? Ou 4 modos (immediate_all / weekly_digest / suppress_all / custom_per_type)?
- [ ] Dev team decide: 1 EF polivalente ou 2 EFs split (send-transactional vs send-digest)
- [ ] Dev team confirma nomes de colunas (`delivery_mode` ok?)
- [ ] Validar com Roberto+Ivan+Fabricio+Sarah+curadoria se algum kind de notification deles é sensível a latência (ex: review gate pending)
- [ ] Revisão pré-CBGPL: se ADR vai a CR-051 (formal) ou fica Proposed até implementação
