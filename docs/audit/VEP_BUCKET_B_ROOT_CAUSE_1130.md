# #1130 — Causa-raiz do "bucket B" (62) e reconciliação VEP↔plataforma

> Grounding: todas as contagens abaixo vieram de queries ao vivo em 2026-07-07 (projeto
> `ldrfrvwhxsmgaabwmaik`) + CSV oficial PMI `pmi_volunteer_service_history_2026-07-05.csv`.
> Re-consultar antes de citar em qualquer decisão futura.

## TL;DR

O "62 divergentes" do `get_vep_divergence_report` (bucket B / `onboarding_divergent`) **não era um
backlog de recruiter** — era o **roster ativo saudável contado como divergência**. O bucket marcava
`status IN (approved,converted) AND vep_status_raw IN ('Submitted','Active')`, mas no ciclo de vida do
VEP **`Active` é o estado de quem JÁ ACEITOU a oferta e está na jornada** (só vira `Complete` quando o
termo encerra). Logo o bucket "crescia sem parar" porque crescia junto com o número de voluntários
ativos. Corrigido: divergência de pré-onboarding = aprovado/convertido **mas ainda pré-aceite** no VEP
(`Submitted` = sem oferta, ou `OfferExtended` = oferta emitida aguardando aceite). Resultado ao vivo:
**62 → 6** (os 6 = C4 com oferta emitida que falta aceitar).

## Ciclo de vida do status VEP (confirmado com o owner 2026-07-07)

```
Submitted  →  OfferExtended  →  Active  →  Complete
(sem oferta)  (oferta emitida,  (aceitou,   (termo
              aguardando        na jornada)  encerrado)
              aceite)
```

- **Pré-onboarding acionável** = `Submitted` + `OfferExtended`. Aceitar a oferta é parte do
  pré-onboarding; sem listar esses, o owner perde a visibilidade de "quem falta aceitar e já deveria
  estar na jornada".
- **`Active` = saudável** (não é divergência).
- Terminais negativos: `Withdrawn` / `Declined` / `OfferNotExtended` / `OfferExpired` / `Expired`.

## Fatos aterrados (2026-07-07)

| Métrica | Valor |
|---|---|
| Plataforma — contratos de voluntário ativos (distinct person) | **71** (12 líder + 57 pesq + 1 co_gp + 1 manager) |
| Plataforma por coorte | 46 C4 · 20 C3 · 1 C3-b2 · 4 sem ciclo |
| VEP-mirror (`vep_status_raw='Active'`) | **62** |
| Bucket B **antigo** (approved/converted + Submitted/Active) | 62 (falso-positivo) |
| Bucket B **novo** (approved/converted + Submitted/OfferExtended) | **6** (todos C4) |
| `Submitted` no banco | **0** |
| Distribuição `vep_status_raw` | Active 62 · OfferNotExtended 47 · Complete 10 · OfferExtended 7 · null 6 · Expired 3 · Withdrawn 2 · OfferExpired 1 |
| vep_status das 71 pessoas ativas | 58 Active · 6 OfferExtended · 1 OfferNotExtended · 6 sem match de app |

## As três "verdades VEP" divergem entre si

| Fonte | Líderes | Pesquisadores | Total |
|---|---|---|---|
| Dashboard PMI ao vivo (owner) | 12 | 65 | 77 |
| CSV oficial 05/07 (endDate ≥ hoje) | 9 | 46 | 55 |
| Mirror DB (`vep_status_raw='Active'`) | — | — | 62 |

Os próprios exports do PMI divergem (55 no CSV × 77 no dashboard). Conclusão: **reconciliação pontual
manual não escala** — precisa de view viva com join estável. A nova RPC usa o **mirror como piso
reconciliável**, não como verdade externa (campo `mirror_note` deixa isso explícito na resposta).

## Causa-raiz por trás do "62 crescendo"

1. **Bug de definição (principal).** `Active` foi tratado como divergência. É o estado normal do
   voluntário onboarded. Não há sync quebrado nem recruiter negligente por trás dos 62 — o número
   era o roster. **Corrigido no `get_vep_divergence_report` (migration `20260805000354`).**
2. **Mirror defasa do dashboard externo (secundário).** O worker `pmi-vep-sync` só espelha quem passou
   pelo funil da plataforma; adds diretos no VEP e drift de export não entram. Por isso mirror(62) ≠
   dashboard(77). Não é regressão — é limite estrutural do espelho. A view expõe isso em vez de
   esconder (delta nominal + `mirror_note`).

## O que fica visível agora (visibilidade de pré-onboarding)

Os **6 `OfferExtended`** (todos C4, aprovados/convertidos) são exatamente os que têm oferta emitida e
**falta aceitar** — aparecem no bucket B corrigido (`onboarding_divergent`) e também no
`platform_only` da matriz quando já têm contrato ativo. Nominalmente: Adailson Santos, Francisco Jose
Nascimento de Oliveira, Hector Rigon, Jhonathan Brandao, Joao Leite de Oliveira Neto, Marcela Foligno.

Caso Ricardo França (`active_members_divergent` + `vep_only`): offboarded na plataforma mas `Active` no
VEP — divergência legítima, com ação sugerida "reativar contrato ou encerrar no VEP".

## Recomendação de automação/alerta

O fix estrutural (semântica do bucket) elimina o ruído. Para o que sobra:

- **Alerta de acúmulo de pré-onboarding**: `OfferExtended` aprovado envelhecendo > N dias (candidato
  não aceitou a oferta) — é o único acúmulo real e acionável (nudge ao voluntário / recruiter).
- **Breakdown por coorte** já é emitido em `summary.onboarding_by_cohort` (hoje `{cycle4-2026: 6}`).
- Não automatizar nada sobre `Active` — não é divergência.

## Superfícies

- RPC: `get_vep_divergence_report` (bucket B corrigido) + nova `get_vep_role_cohort_reconciliation`
  (matriz papel×coorte + listas nominais, join estável por `pmi_id` → e-mail). Migration
  `supabase/migrations/20260805000354_1130_vep_role_cohort_reconciliation.sql`.
- Frontend: `src/components/admin/VepReconciliationIsland.tsx` (aba Matriz + F3 estado de erro + F4
  navegação cruzada para `/admin/selection?cycle=` e `/admin/filiacao`).
- Contract test: `tests/contracts/1130-vep-role-cohort-reconciliation.test.mjs`.
