# Matriz de Canais & Marcos "jeito Disney" — Jornada de Pré-Onboarding (J2 + J5)

> **Status:** vivo · **Origem:** discovery #740 (gaps J2 + J5) · **Aterrado:** 2026-06-16 (Wave 4)
> · **Reconciliado:** 2026-06-18 (Épico J pós-D) — J4 saiu de FUTURO p/ ✅ feito; H1 (jornada pós-promoção) shipou.
> **Escopo:** primeira pernada (aprovação na seleção → aceite VEP → pré-onboarding → termo → promoção → 1ºs dias).
> **Companheiro de:** [`PRE_ONBOARDING_COMMS_MAP_2026-06-16.md`](./PRE_ONBOARDING_COMMS_MAP_2026-06-16.md) (J1 — o mapa
> de **o que** é comunicado por etapa). Este doc define **por qual canal** (J2) e **como celebramos marcos** (J5).

O J1 mapeou a malha de comunicação por etapa, mas o discovery apontou que **falta o princípio de decisão de canal**
("sem matriz definida") e que o **tom de celebração de marcos é inconsistente** (existe em perfil 100%, ausente nos
demais marcos). Este doc fecha esses dois gaps de *definição*. Onde algo ainda **não está implementado**, está rotulado
explicitamente como **FUTURO** — sem doc-fake (mesma disciplina do J1/J4 na Wave 2).

---

## Parte A — Matriz de decisão de canal (J2)

Três canais, três propósitos distintos. A regra é **propósito → canal**, não "manda em todos".

| Canal | Propósito | Quando usar | Fonte de verdade |
|---|---|---|---|
| **E-mail** | Formal, externo, acionável fora da plataforma | Marcos oficiais (aprovação, termo disponível, promoção), lembretes com prazo, qualquer coisa que o usuário precise ver **mesmo sem entrar na plataforma** | `_delivery_mode_for(type)` → `transactional_immediate` (na hora) ou `digest_weekly` (junta no digest de sábado) |
| **In-app (sino + painel)** | Operacional, contextual, status | Nudges de progresso, fila de ação da liderança (D1/E1), status que só faz sentido **dentro** da plataforma | tabela `notifications`; `_delivery_mode_for(type)` → `suppress` (só sino, sem e-mail) |
| **WhatsApp (grupo coletivo)** | Comunidade, dúvidas, calor humano | Acolhimento, dúvidas abertas (candidato ↔ Núcleo ↔ diretorias), avisos coletivos informais. **Nunca** dado individual/PII (é grupo) | grupo `chat.whatsapp.com/Gl6eUqK45DJGQxZ8VFE2bs` (link único, ver `PreOnboardingChecklist.tsx`) |

### Regras de decisão (heurística)
1. **É individual e tem PII?** → nunca WhatsApp coletivo. E-mail (formal) ou in-app (operacional).
2. **Precisa de ação fora da plataforma ou é um marco formal?** → e-mail (`transactional_immediate`).
3. **É status/nudge que só importa dentro da plataforma?** → in-app `suppress` (sino), sem poluir a caixa de e-mail.
4. **Pode esperar e agregar?** → `digest_weekly` (digest de sábado), não e-mail individual.
5. **É acolhimento / dúvida aberta / comunidade?** → WhatsApp coletivo (complementa, nunca substitui o canal formal).

### Anti-padrões
- **Duplicar o mesmo aviso em e-mail + sino + WhatsApp** "por garantia" → ruído; escolha o canal pelo propósito.
- **Mandar dado individual (status, nome, capítulo) no grupo de WhatsApp** → vazamento (LGPD): o grupo é coletivo.
- **E-mail para nudge puramente operacional** (ex.: "seu onboarding está 60%") → use o sino (`suppress`).

### Roteamento já implementado (referência cruzada)
A coluna "Canal / tipo" do [comms map (J1)](./PRE_ONBOARDING_COMMS_MAP_2026-06-16.md#mapa-por-etapa) lista o canal
de cada etapa. O **roteador** é `public._delivery_mode_for(p_type)` (SSOT). Esta matriz é o **princípio** por trás
daquelas escolhas — use-a ao adicionar um tipo novo de notificação.

---

## Parte B — Matriz de marcos "jeito Disney" (J5)

Princípio: **todo marco merece um momento.** Celebrar reforça pertencimento e reduz desengajamento silencioso.
Tom: caloroso, segunda pessoa, orientado ao próximo passo — **sem números fabricados** (regra de grounding).

| Marco | Celebração | Canal | Status |
|---|---|---|---|
| **Perfil 100%** | Recompensa de XP + feedback visual | in-app (gamificação) | ✅ **EXISTE** (pré-Wave 4) |
| **Onboarding completo** (todos os passos pós-promoção) | Card celebrativo "🎉 Onboarding concluído!" no lugar do checklist (antes sumia em silêncio); mostrado 1× (localStorage-gated) + CTA explorar | in-app (`OnboardingChecklist`) | ✅ **NOVO nesta fatia (J5)** |
| **Termo de voluntariado assinado** | Hoje: notifica a **liderança** (`volunteer_agreement_signed`) + tela de sucesso do membro (A4, Wave 1). Celebração member-side dedicada ("você é oficialmente voluntário") | in-app / e-mail | 🟡 **PARCIAL** — sucesso existe; celebração de marco dedicada = FUTURO |
| **Promoção** (contra-assinatura do GP) | Momento "bem-vindo, membro ativo" no primeiro acesso pós-promoção (hoje o membro só vê o checklist de 1ºs dias — H1) | in-app | 🟡 **PARCIAL** — card de 1ºs dias existe (Block H); celebração de promoção dedicada = FUTURO |
| **1ª presença registrada** | "Sua primeira presença! 🎯" | in-app | 🔴 **FUTURO** — nudge existe (Block H beat 2); celebração ao registrar = não implementado |
| **1ª entrega / deliverable** | "Primeira entrega no quadro! 🚀" | in-app | 🔴 **FUTURO** — não implementado |

### Diretrizes de tom (para qualquer celebração futura)
- **Segunda pessoa, presente:** "Você concluiu…", não "O usuário concluiu…".
- **Nomeie o marco + aponte o próximo passo:** celebrar sem deixar o membro perdido ("e agora?").
- **Uma vez, não a cada visita:** persistir "já celebrado" (localStorage no client, ou flag no `onboarding_progress`
  para marcos server-side) — evita o nag que mata o efeito.
- **Sem inventar métrica:** "você completou todas as etapas" (fato), nunca "você é o 42º a completar" sem query viva.
- **Reusar a malha existente:** marcos server-side podem virar `notifications` roteadas por `_delivery_mode_for`;
  marcos client-side (como o onboarding-complete) ficam no componente da superfície.

---

## Lacunas / próximos passos (honestos)
- **J5 marcos server-side** (termo assinado member-side, promoção, 1ª presença, 1ª entrega): exigem gatilho no
  evento (trigger/cron) + persistência de "já celebrado" — **feature futura**, não simulada aqui. Severidade 🟢.
  Parcial: promoção agora tem jornada pós-promoção (H1, #780); celebração dedicada de marco segue futura.
- **J4 — cadência/SLA configurável:** ✅ **feito [2026-06-18]** (#776/#777) — `sla_policies` + UI admin em
  `/admin/settings`. Ver tabela de janelas no [comms map (J1)](./PRE_ONBOARDING_COMMS_MAP_2026-06-16.md#cadência--sla-configurável-j4--implementada-2026-06-18).
- **J6 — cópia operacional canônica** embutida nos e-mails/telas: ver §9 do discovery; parcialmente embutido
  (aceite VEP, sync de filiação privada já estão em telas/banners; o template `vep_offer_accept_reminder` do D7
  carrega o passo-a-passo de aceite — #782).
- **J3 WhatsApp:** segue **manual** (link de grupo coletivo, sem gatilho automatizado); automação = projeto à parte.

## Cross-ref
- [`PRE_ONBOARDING_COMMS_MAP_2026-06-16.md`](./PRE_ONBOARDING_COMMS_MAP_2026-06-16.md) (J1)
- discovery `docs/project-governance/PRE_ONBOARDING_JOURNEY_DISCOVERY_2026-06-16.md` (Épico J)
- `_delivery_mode_for` (SSOT de roteamento) · tabela `notifications` · `OnboardingChecklist.tsx` (celebração J5)
- grupo WhatsApp: `chat.whatsapp.com/Gl6eUqK45DJGQxZ8VFE2bs`
