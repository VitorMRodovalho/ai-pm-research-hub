# Mapa de Comunicações — Jornada de Pré-Onboarding (J1)

> **Status:** vivo · **Origem:** discovery #740 (gap J1) · **Aterrado:** 2026-06-16 (Wave 2)
> **Escopo:** primeira pernada (aprovação na seleção → aceite VEP → pré-onboarding →
> termo → promoção). Seleção de tribo é jornada separada (ver discovery #740).

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
| ⤷ visibilidade p/ liderança | GP/curadoria | painel **D1** (balde "Oferta VEP não aceita") | pull (in-app) | ao abrir `/admin` |
| **Convite de entrevista** (cutoff aprovado) | Candidato | e-mail · `cutoff_approved_email_sent_at` | cron `selection-cutoff-pending-daily` (strict-above-target) | diário 14:00 |
| ⤷ in-band/below-target (sem auto-convite) | GP | painel **D1** (balde "sem convite") — **decisão manual** (PM 2026-06-16) | pull (in-app) | ao abrir `/admin` |
| **Entrevista agendada** | Candidato + entrevistadores | sino · `selection_interview_scheduled` | trigger | imediato |
| **Lembrete 1h antes** | Entrevistadores | `interview-reminder-1h-q15min` | cron | a cada 15min |
| **Entrevista vencida / nunca conduzida** | Entrevistadores | `selection_interview_overdue` (digest) | cron `selection-interview-overdue-daily` | diário 14:00 |
| ⤷ agendamento travado >48h | — | rescue `selection-stuck-scheduled-rescue-daily` | cron | diário 15:00 |
| ⤷ convite enviado, nunca agendado | GP | painel **D1** (balde correspondente) | pull (in-app) | ao abrir `/admin` |
| **No-show** | GP | painel **D1** (balde "no-show") | pull (in-app) | ao abrir `/admin` |
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

## Lacunas conhecidas (não cobertas aqui)
- **J4 — cadência/SLA configurável** (oferta não aceita, termo não assinado, onboarding
  parado, convite sem agendamento): hoje as janelas são **fixas no código** dos crons. Um
  mecanismo de config (tabela + UI) é **feature futura** — registrado em #740, **não** simulado
  como configurável neste doc.
- **D7 auto-e-mail próprio** (segundo nudge além do PMI p/ oferta não aceita): decisão PM
  2026-06-16 = **painel basta** (nudge manual); não há auto-e-mail nosso.
- Registro do tipo `selection_apto_to_sign_digest` no catálogo ADR-0022 + `_delivery_mode_for`:
  follow-up de higiene (#740) — hoje o `delivery_mode` é setado direto no INSERT do cron.

## Cross-ref
- Discovery: `docs/project-governance/PRE_ONBOARDING_JOURNEY_DISCOVERY_2026-06-16.md`
- Modelo guest/pré-onboarding: `PRE_ONBOARDING_GUEST_MODEL.md`
- PRs Wave 2: #745 (D1), #746 (E1), #747 (E2) · umbrella #740
