# Mapa de Comunicações — Jornada de Pré-Onboarding (J1)

> **Status:** vivo · **Origem:** discovery #740 (gap J1) · **Aterrado:** 2026-06-16 (Wave 2)
> · **Reconciliado:** 2026-06-18 (Épico J pós-D) com o estado live — ver nota abaixo.
> **Escopo:** primeira pernada (aprovação na seleção → aceite VEP → pré-onboarding →
> termo → promoção). Seleção de tribo é jornada separada (ver discovery #740).

> **🔄 Reconciliação 2026-06-18:** entre 06-16 e 06-18 shiparam peças que este doc dava como
> FUTURO. Corrigido contra queries vivas: **J4 (SLA configurável)** = ✅ feito (`sla_policies`
> + UI admin, #776/#777); **D7 (auto-e-mail de aceite VEP)** = ✅ feito (#782) — supersede a nota
> "painel basta"; **D5/D3 (push ao GP de funil travado)** = ✅ feito (#781), camada PUSH além do
> pull do painel D1; catálogo `_delivery_mode_for` agora conhece os tipos novos (lacuna de higiene
> fechada). Detalhes nas linhas marcadas **[2026-06-18]** e na seção "Lacunas".

J1 do discovery pedia "definir quais e-mails/lembretes automáticos em cada estágio".
Este doc **documenta o que JÁ existe** (não propõe) — o re-grounding da Wave 2 mostrou
que a maior parte da malha de comunicação do funil já está implementada (crons p282 +
notificações transacionais p157/p159 + painéis D1/E1 da Wave 2). É um mapa de referência;
não substitui as fontes de verdade abaixo.

## Fontes de verdade (SSOT)
- **Tipos + roteamento de e-mail:** `public._delivery_mode_for(p_type)` — decide
  `transactional_immediate` (e-mail na hora) · `digest_weekly` (junta no digest de sábado) ·
  `suppress` (só sino in-app, sem e-mail).
- **Tabela:** `public.notifications` (`recipient_id`, `type`, `title`, `body`, `link`,
  `delivery_mode`, `email_sent_at`, …).
- **Crons:** `cron.job` (todos UTC). **Painéis in-app:** D1 (`/admin` — "Ação hoje") e
  E1 (`/admin/certificates` — fila priorizada).

## Mapa por etapa

| Etapa | Quem é avisado | Canal / tipo | Mecanismo | Cadência |
|---|---|---|---|---|
| **Aprovado na seleção** | Candidato | sino + e-mail · `selection_approved` | trigger | imediato (sino); e-mail canônico vem no termo |
| **Oferta VEP pendente** (aprovado, sem ACEITE no VEP) | Candidato | e-mail oficial do **PMI** (remetente `donotreply at pmi.org`) | externo (PMI) | no envio da oferta |
| ⤷ **[2026-06-18] lembrete próprio (D7)** | Candidato | e-mail · template `vep_offer_accept_reminder` | cron `nudge-vep-offer-accept-daily` → `process_pending_vep_offer_reminders` (single-fire, SLA `offer_accept_grace` 7d a partir de `vep_offer_extended_at`) | diário 17:00 |
| ⤷ visibilidade p/ liderança | GP/curadoria | painel **D1** (balde "Oferta VEP não aceita") | pull (in-app) | ao abrir `/admin` |
| **Convite de entrevista** (cutoff aprovado) | Candidato | e-mail · `cutoff_approved_email_sent_at` | cron `selection-cutoff-pending-daily` (strict-above-target) | diário 14:00 |
| ⤷ in-band/below-target (sem auto-convite) | GP | painel **D1** (balde "sem convite") — **decisão manual** (PM 2026-06-16) | pull (in-app) | ao abrir `/admin` |
| **Entrevista agendada** | Candidato + entrevistadores | sino · `selection_interview_scheduled` | trigger | imediato |
| **Lembrete 1h antes** | Entrevistadores | `interview-reminder-1h-q15min` | cron | a cada 15min |
| **Entrevista vencida / nunca conduzida** | Entrevistadores | `selection_interview_overdue` (digest) | cron `selection-interview-overdue-daily` | diário 14:00 |
| ⤷ agendamento travado >48h | — | rescue `selection-stuck-scheduled-rescue-daily` | cron | diário 15:00 |
| ⤷ convite enviado, nunca agendado | GP | painel **D1** (balde correspondente) | pull (in-app) | ao abrir `/admin` |
| ⤷ **[2026-06-18] push ao GP (D5)** | GP/managers | sino · `selection_candidate_unbooked` | cron `detect-stuck-selection-funnel-daily` → `detect_stuck_selection_funnel` (bucket `invited_never_booked`, SLA `interview_booking_grace` 10d a partir do convite) | diário 16:00 |
| **No-show** | GP | painel **D1** (balde "no-show") | pull (in-app) | ao abrir `/admin` |
| ⤷ **[2026-06-18] push ao GP (D3)** | GP/managers | sino · `selection_noshow_unrecovered` | cron `detect-stuck-selection-funnel-daily` → `detect_stuck_selection_funnel` (bucket `noshow_not_recovered`, SLA `noshow_recovery_grace` 3d) | diário 16:00 |
| **Pré-onboarding — termo disponível** | Candidato | e-mail · `selection_termo_due` (e-mail principal pós-VEP-Active, com termo + próximos passos) | trigger p157/p159 | imediato |
| ⤷ **apto a assinar (lado-liderança)** | GP + Dir. Voluntariado (`manage_member`) | sino · `selection_apto_to_sign_digest` (agregado) → link p/ fila **E1** | cron `selection-apto-to-sign-digest-daily` (Wave 2 E2) | diário 13:45 |
| **Onboarding parado / overdue** | Candidato | `selection_onboarding_overdue` | cron `detect-onboarding-overdue-daily` | diário 13:00 |
| **Termo assinado (voluntário)** | GP/liderança | sino + e-mail · `volunteer_agreement_signed` | trigger | imediato |
| **Promoção (contra-assinatura do GP)** | Candidato | (promoção ocorre no counter-sign; ver fila **E1**) | — | — |
| **Integridade do funil** (drift app↔entrevista) | GP | `selection_consistency_anomaly` | cron `selection-consistency-check-daily` | diário 13:30 |

## Cópia operacional canônica (insumos)
- **Aceite da oferta VEP:** o PMI envia e-mail (remetente `donotreply at pmi.org` — checar spam)
  com link p/ aceitar; manualmente em `volunteer.pmi.org` → **My Info & Activity** → **Accept Position**.
- **Filiação privada (capítulo oculto):** `community.pmi.org/profile` → Edit Overview →
  **Chapter Membership** → desmarcar "Hide my chapter(s)"; depois avisar a gestão (WhatsApp) p/ re-sync.
- **Grupo de WhatsApp de pré-onboarding** (dúvidas; candidatos + Núcleo + diretorias):
  `chat.whatsapp.com/Gl6eUqK45DJGQxZ8VFE2bs`.

> **J2 (decisão de canal) + J5 (marcos "jeito Disney")** agora têm doc próprio:
> [`PRE_ONBOARDING_CHANNEL_AND_CELEBRATION_MATRIX_2026-06-16.md`](./PRE_ONBOARDING_CHANNEL_AND_CELEBRATION_MATRIX_2026-06-16.md)
> (Wave 4) — o **princípio** por trás da coluna "Canal / tipo" acima + a matriz de celebração de marcos.

## Cadência / SLA configurável (J4) — ✅ implementada [2026-06-18]

As janelas dos crons **não são mais fixas no código**: ficam na tabela `sla_policies` (SSOT),
editáveis por GP em `/admin/settings` → "Janelas de SLA" (gate `manage_platform`, #776/#777).
Valores vivos (queried 2026-06-18):

| policy_key | Janela | Usado por |
|---|---|---|
| `interview_booking_grace` | 10 dias | `detect_stuck_selection_funnel` (bucket invited_never_booked) |
| `noshow_recovery_grace` | 3 dias | `detect_stuck_selection_funnel` (bucket noshow_not_recovered) |
| `offer_accept_grace` | 7 dias | `process_pending_vep_offer_reminders` (D7, single-fire) |
| `interview_overdue_grace` | 24h | `_selection_interview_overdue_cron` |
| `stuck_scheduled_grace` | 48h | `_selection_stuck_scheduled_rescue_cron` |
| `reschedule_nudge_initial` | 3 dias | `process_pending_reschedule_nudges` (1º nudge) |
| `reschedule_nudge_repeat` | 3 dias | `process_pending_reschedule_nudges` (subsequentes) |

## Lacunas conhecidas (não cobertas aqui)
- **J5 marcos server-side** (termo assinado member-side, promoção, 1ª presença, 1ª entrega):
  ainda parciais/futuros — ver a matriz de marcos no doc companheiro.
- **J3 WhatsApp** segue **manual** (link de grupo coletivo, sem gatilho automatizado): decisão de
  canal documentada no doc companheiro (Parte A); automação = projeto à parte (Business API).

## Cross-ref
- Discovery: `docs/project-governance/PRE_ONBOARDING_JOURNEY_DISCOVERY_2026-06-16.md`
- Modelo guest/pré-onboarding: `PRE_ONBOARDING_GUEST_MODEL.md`
- PRs Wave 2: #745 (D1), #746 (E1), #747 (E2) · umbrella #740
- PRs reconciliação 2026-06-18: #776/#777 (J4 SLA config + UI), #781 (D5/D3 push funil), #782 (D7 auto-e-mail VEP)
