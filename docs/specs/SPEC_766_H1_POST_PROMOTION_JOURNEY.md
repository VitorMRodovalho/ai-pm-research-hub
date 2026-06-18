# SPEC — H1: Jornada Pós-Promoção (primeiros dias do papel real)

**Issue/épico:** #766 fechada; H1 é a próxima onda do ÉPICO H (discovery `PRE_ONBOARDING_JOURNEY_DISCOVERY_2026-06-16.md`, gap H1, sev 🟡).
**Escopo decidido (PM 2026-06-17):** **MVP FE-only** — zero DB, 1 PR pequeno. H4 (nudge anti-dropout) e H6 (1ª missão) ficam para ondas próprias.
**Council:** product-leader (GO-with-changes) + ux-leader (GO-with-changes na "nova island persistente sibling").

---

## 1. Problema

O onboarding termina na assinatura do termo. O roteiro dos "primeiros dias" (1ª reunião → 1ª entrega → 1º XP) hoje existe só como **copy estática** (`HBLOCK`) DENTRO de `OnboardingChecklist.tsx`, que **desaparece** quando o onboarding conclui (`if (allComplete) …`). Resultado: no exato momento "assinei o termo, e agora?", o `/workspace` fica sem orientação — o dead-end A4/A5. Além disso a copy é fixa: as batidas não refletem se a pessoa de fato já fez a 1ª presença / 1ª entrega.

## 2. Solução (uma frase)

Uma **island persistente e stateful** no `/workspace` (`PostPromotionJourney`) que aparece DEPOIS do onboarding concluir, lê os marcos server-side reais (`first_attendance`, `first_deliverable`) para marcar cada batida como feita/pendente, e encerra-se sozinha quando ambas as batidas com marco estão alcançadas. Sem rota nova, sem DDL.

## 3. Fonte de dados (tudo já existe)

- `get_my_onboarding()` → `all_complete` (já consumido pelo OnboardingChecklist).
- `get_my_milestones()` → `{ pending:[{milestone_key,occurred_at}], history:[{milestone_key,occurred_at,acknowledged_at}] }`.
  - **"Alcançado"** de um marco = chave presente na **união** `pending ∪ history` (independe de acknowledge).
  - Chaves usadas: `onboarding_complete` (gate), `first_attendance` (batida 1), `first_deliverable` (batida 2).
- `window.navGetMember()` → `{ id, operational_role, tribe_id, … }`. `window.navGetSb()` → cliente supabase.
- **Não existe** marco `first_xp` (decisão PM) → batida 3 (trilha/XP) é **CTA aberto**, sem auto-check.

## 4. Regra de visibilidade (gating) — exata

A island **renderiza** quando TODAS forem verdadeiras:

1. `member.operational_role` **≠ `'guest'`** (membro promovido; estado de entrada = `researcher`).
2. `member.tribe_id` **≠ null** (tem tribo — exclui o GP, que não tem tribo; os CTAs de tribo não fazem sentido sem ela).
3. `get_my_onboarding().all_complete === true` (onboarding concluído — o momento que H1 resolve).
4. `onboarding_complete` está **em `history`** (acknowledged), **não** em `pending` — evita sobreposição com o card de celebração do OnboardingChecklist (que mostra enquanto a celebração está pendente; ux R1).
5. **NÃO** estão ambos `first_attendance` E `first_deliverable` alcançados (critério de saída — ver §6).

Caso contrário → `return null` (silenciosa). Nunca há dois cards de "primeiros dias" simultâneos: enquanto `all_complete === false`, quem orienta é o OnboardingChecklist; quando conclui, ele some e a `PostPromotionJourney` assume.

## 5. Estados das batidas (stepper linear vertical)

`role="list"`, 3 itens. Estado por batida:

| Batida | Rótulo | Sinal de "feito" | CTA |
|--------|--------|------------------|-----|
| 1 | Participe da 1ª reunião e registre presença | `first_attendance` alcançado | `→ /attendance` |
| 2 | Faça sua 1ª entrega | `first_deliverable` alcançado | `→ /workspace` (suas atividades) / tribo |
| 3 | Comece a trilha PMI AI e ganhe seu 1º XP | **(aberto — sem auto-check)** | `→ /gamification` |

Modelo visual:
- **done** (marco alcançado): círculo verde sólido com ✓, texto normal, sem CTA. Comunicar "feito" por texto/`aria-label`, não só cor.
- **current** (primeira batida 1–2 ainda não feita): destaque, label em bold, CTA visível.
- **upcoming** (batidas 1–2 após a current): muted, sem CTA.
- **Batida 3 = "aberta"** o tempo todo: estilo distinto (não numerada como "3 de 3" em progresso), CTA sempre presente, com linha auxiliar muted: *"Conquista registrada automaticamente ao completar a trilha"*. Ela **nunca** entra em "done" e **não** bloqueia a conclusão da jornada (a saída depende só das batidas 1 e 2). Isso evita que pareça "quebrada" ao lado de duas que checam.

CTAs: `min-height: 44px` (touch target). Mobile 375px nativo (stepper vertical, sem reflow).

## 6. Ciclo de vida / saída

- **Saída automática (sem dismiss manual):** a island desaparece quando `first_attendance` **E** `first_deliverable` estiverem ambos alcançados (`pending ∪ history`). Critério objetivo e server-backed → cross-device sem localStorage e sem novo marco. Dismiss manual foi rejeitado (ux): cria decisão cognitiva desnecessária e ressuscita ansiedade.
- **Sem janela temporal de visibilidade no MVP** (product): persiste até as duas batidas estarem feitas, não some após 7 dias. "Primeiros 7 dias" é o alvo de UX (onde o H4 nudge entraria), não um gate.
- **Membros antigos (backfill):** os marcos `first_attendance`/`first_deliverable` foram backfillados (mig 203) para quem já tinha presença/entrega; esses já satisfazem o critério de saída → não veem a island. Só vê quem genuinamente ainda não fez uma das duas — a audiência certa.
- **Deferido (v2, NÃO MVP):** teto de N dias desde `onboarding_complete.occurred_at` como guarda anti-stale. Omitido agora porque o `occurred_at` do backfill é ≈ data da migração (não confiável como "data de promoção"); o critério de saída já cobre a audiência.

## 7. Composição com BuddyBlock

**Blocos separados, `PostPromotionJourney` ACIMA do `BuddyBlock`.** Não envolver/abraçar (ux): "o que eu faço" (jornada) e "quem me ampara" (buddy) são perguntas cognitivamente distintas, com ciclos de vida próprios. O `BuddyBlock` permanece como island sibling já montada — H1 **não recria** lógica de buddy (satisfaz "importa o canônico, não recria" por coexistência, não por aninhamento).

Ordem no `workspace.astro`:
```
PreOnboardingChecklist
OnboardingChecklist          ← HBLOCK estático REMOVIDO daqui
PostPromotionJourney         ← NOVA island (aparece após onboarding concluir)
BuddyBlock                   ← inalterada
```

## 8. Mudança no OnboardingChecklist

- Remover `HBLOCK`/`hblock()` (def. linhas ~43-86) e o bloco de render (linhas ~218-227).
- **Cuidado:** `h.attendanceCta` é reusado no passo `first_meeting` (linha ~301). Mover esse rótulo para o dicionário `L` (`attendanceCta`) antes de remover o HBLOCK, mantendo o botão do passo intacto.

## 9. i18n

Copy **trilíngue inline** no componente (idioma do OnboardingChecklist — `L`/`HBLOCK`/`CELEBRATE` são inline). Não usa `t()` → não toca os 3 dicts globais nem o grep de chaves. pt-BR / en-US / es-LATAM obrigatórios no dict inline.

**Tom "jeito Disney" (regra de grounding: SEM números/pontos inventados):**
- Título pt-BR: *"Seus primeiros passos no Núcleo"* (evita repetir "bem-vindo" — a celebração de onboarding já recepcionou; e evita assumir "agora" para quem vê via backfill).
- Sem estado explícito de "tudo feito": a island simplesmente some quando concluída.

## 10. Métrica de sucesso (hipótese, NÃO medida)

> % de researchers com `all_complete = true` e `tribe_id` não-nulo que registram `first_attendance` em até 30 dias da promoção. Meta hipotética ≥ 50% (baseline real a medir antes do launch via marco `first_attendance` existente — não citar como fato).
> Secundária: tempo mediano entre marcos `promotion` → `first_attendance` (espera-se redução). Ambas deriváveis dos marcos já no servidor; nenhum evento novo.

## 11. Fora de escopo (proteger a fatia pequena)

- Nudge/badge "você está parado há X dias" (= H4 — exige cron/DB-write).
- Marco `first_xp` / check automático da trilha (= H6 — exige evento novo; PM decidiu CTA).
- Personalização por tribo (agenda específica) — acoplamento que infla 1 PR em 3; H1 v2.
- Ramo "GP sem tribo" — < 10 usuários, CTAs de tribo não se aplicam.

## 12. Entrega

- **1 PR FE-only** (product): island stateful + composição são inseparáveis para resolver o dead-end; dividir cria estado intermediário pior.
- Arquivos: `src/components/onboarding/PostPromotionJourney.tsx` (novo) · `src/pages/workspace.astro` (mount) · `src/components/onboarding/OnboardingChecklist.tsx` (remover HBLOCK, mover `attendanceCta`) · `tests/contracts/766-h1-journey.test.mjs` (offline; +2 whitelists).
- Sem migração, sem rota nova, sem ACL nova, sem mudança nos 3 dicts globais.

## 13. a11y

- Stepper: `role="list"` + `role="listitem"`; estado "done" em texto/`aria-label`, não só cor.
- CTA da batida current com `aria-describedby` → label da batida.
- Contraste dos botões ≥ 4.5:1; touch target ≥ 44px.
