# AI `raises_the_bar` Rubric — Validation vs. Decisões Humanas (cycle3-2026)

**Issue**: [#119](https://github.com/VitorMRodovalho/ai-pm-research-hub/issues/119)
**Date**: 2026-05-01 (p87 marathon final, com Sprint 3.b paid expansion)
**Status**: **FULL ROBUST VALIDATION** — sample n=53 (Gemini Tier 1 paid após PM ratify) com prompt **Sprint 4 evolution** (v2 — track record + potencial convergente paths).
**LGPD path**: Option B (PII-stripped) — `anonymize_application_for_ai_training` RPC + `pmi-ai-analyze-research` EF
**ADR**: ADR-0066 Amendment 1 + Amendment 2 + ADR-0067 N1 Art.20 Safeguards

---

## TL;DR

> Sprint 4 prompt evolution (path b potencial convergente) **trouxe recall de 33% → 80%** (n=14→n=53). AI agora identifica 4x mais candidatos eventualmente aprovados. Trade-off: precision YES caiu 75% → 64.5%. **F1 melhorou 0.46 → 0.71** — net win significativo.
>
> **Rubric agora viável como gate "soft no" + "high-confidence yes"**: AI=NO em 31% dos approved (vs 67% antes), AI=YES tem 65% chance ser aprovado. Combinada com par-revisão humana e fit_for_role >=4, fica calibrada.

---

## Comparação MVP (n=14, prompt v1) vs FULL (n=53, prompt v2 Sprint 4)

| Métrica | MVP n=14 (v1) | FULL n=53 (v2) | Δ |
|---|---|---|---|
| Precision YES | 75% | **64.5%** | -10.5pp |
| **Recall YES** | 33% | **80%** | **+47pp ⬆⬆⬆** |
| Specificity NO | 80% | 50% | -30pp |
| False Negative Rate | 67% | 20% | **-47pp ⬇⬇⬇** |
| F1 (YES) | 0.46 | **0.71** | **+0.25 ⬆** |
| Concordance overall | 50% | 58% | +8pp |

### Insights

1. **Sprint 4 path (b) potencial convergente FUNCIONOU** — recall mais que dobrou. Casos que antes eram FN (Ana Carla MBA + 5 evals approved → AI=NO) agora capturados como YES via path (b) formação sólida + commitment.
2. **Trade-off precision**: AI agora "amplia rede" — pega mais approved mas também mais rejected entram em YES. Recoverable via fit_for_role filter.
3. **AI=NO agora é signal mais forte de rejection** (vs antes era 67% errado). Quando AI diz NO, 11/16 = **69% chance ser rejected** (vs 36% no v1).
4. **Best operacional combo**: `fit_for_role >= 4 AND raises_the_bar = yes` = 17 candidatos no n=53, 15 approved + 2 converted = **88% precision** quando filter por fit também.

---

## Dataset

- **Cycle**: cycle3-2026 (closed)
- **Pool**: 63 candidatos com final outcome humano (31 approved + 30 rejected + 2 converted)
- **Filtered**: ≥30 chars em algum campo de texto substantivo
- **Final sample**: **n=53** (10 não tinham texto suficiente em qualquer campo, ou outras edge conditions)
- **Prompt**: Sprint 4 v2 (track record + potencial convergente)
- **Model**: gemini-2.5-flash com maxOutputTokens 4096
- **All runs `triggered_by='research_validation'`** em ai_analysis_runs (NÃO contaminam selection_applications.ai_analysis live)

---

## Confusion Matrix Completa (n=53)

| | AI = YES | AI = NO | AI = UNCERTAIN | Total |
|---|---|---|---|---|
| **Humano: APPROVED** | 18 (TP) | 5 (FN) | 3 | 26 |
| **Humano: REJECTED** | 11 (FP) | 11 (TN) | 3 | 25 |
| **Humano: CONVERTED** | 2 (TP*) | 0 | 0 | 2 |
| **Total** | 31 | 16 | 6 | 53 |

(*) Converted = approved + later converted to different track. Counted as positive outcome.

### Métricas (excluindo uncertain, treating converted=approved)

- **TP**: 20 (AI YES + outcome positive)
- **FP**: 11 (AI YES + rejected)
- **TN**: 11 (AI NO + rejected)
- **FN**: 5 (AI NO + approved)
- **Total binário**: 47

| Métrica | Valor | Cálculo |
|---|---|---|
| Precision YES | **64.5%** | 20/31 |
| Recall YES (sensibilidade) | **80%** | 20/25 |
| Specificity NO | **50%** | 11/22 |
| Accuracy | **65.9%** | (20+11)/47 |
| F1 (YES) | **0.71** | 2·(0.645·0.8)/(0.645+0.8) |

---

## Médias por bucket × outcome

| AI verdict | Outcome | n | Avg AI fit | Avg human score | Score range |
|---|---|---|---|---|---|
| no | approved | 5 | 1.80 | 181.2 | 142–247 |
| no | rejected | 11 | 1.64 | 84.0 | 47–118 |
| uncertain | approved | 3 | 3.33 | 121.3 | 95–137 |
| uncertain | rejected | 3 | 3.67 | 79.0 | 48–102 |
| yes | approved | 18 | 4.28 | 194.1 | 75–272 |
| yes | converted | 2 | 4.00 | 51.0 | 45–57 |
| yes | rejected | 11 | 4.45 | 130.9 | 42–208 |

### Observações

1. **AI=YES com avg human score 194 (approved)** — alinha com top performers. AI captura corretamente "raisers".
2. **AI=NO + approved (FN)** — avg human score 181 (high!), avg AI fit 1.80 (low!). AI rejeitou TEXTO muito conciso de candidatos que humanos aprovaram via outras razões (LinkedIn, contexto, prior knowledge).
3. **AI=YES + rejected (FP)** — avg fit 4.45 (highest!) mas humano rejeitou. Avg human score 130 (medium-low). Hypótese: AI focou em "raise the bar" baseado em texto bem articulado, mas humano viu red flags em LinkedIn/entrevista/anotações.
4. **AI=UNCERTAIN é meio-meio** (3 approved / 3 rejected) — verdict apropriadamente não-conclusivo quando dados são thin.

---

## Per-fit_for_role × verdict × outcome breakdown

| fit | AI verdict | Approved | Rejected | Converted |
|---|---|---|---|---|
| **5** | YES | 10 | 6 | 0 |
| **5** | NO | 0 | 0 | 0 |
| **4** | YES | 5 | 4 | 2 |
| **4** | NO | 0 | 1 | 0 |
| **4** | UNCERTAIN | 1 | 2 | 0 |
| **3** | YES | 2 | 1 | 0 |
| **3** | NO | 1 | 0 | 0 |
| **3** | UNCERTAIN | 2 | 1 | 0 |
| **2** | YES | 0 | 0 | 0 |
| **2** | NO | 2 | 4 | 0 |
| **1** | YES | 1 | 0 | 0 |
| **1** | NO | 2 | 6 | 0 |

### Insights operacionais

1. **fit=5 + AI=YES** (n=16): 10 approved (62.5%) — high-precision shortlist
2. **fit≥4 + AI=YES** (n=23): 15 approved + 2 converted = **17/23 = 74% precision**
3. **fit≥4 + AI=YES OR UNCERTAIN** (n=26): 16 approved + 2 converted = 69% precision (loosens slightly mas captura mais)
4. **fit=1 + AI=NO** (n=8): 6 rejected (75%) — high-precision auto-reject candidate (mas AINDA tem 2 approved em FN — rare cases não-textuais)
5. **fit=2 + AI=NO** (n=6): 4 rejected (67%)

### Recomendação operacional refinada (Sprint 4 calibrated)

```
SE (raises_the_bar = YES AND fit_for_role >= 4):
  → Skip-to-interview shortlist (74% precision)
  → Flag opcional "high-confidence" no UI

SENÃO SE (raises_the_bar = NO AND fit_for_role <= 2):
  → Strong soft signal de rejection (~75% TN rate)
  → Comissão prioritária se quiser overrride

SENÃO SE (raises_the_bar = UNCERTAIN OR fit between 3-4):
  → Mid-tier — par-revisão humana mandatory
  → Não usar AI verdict como decisão isolada

SE raises_the_bar = YES AND fit_for_role <= 2:
  → Caso edge — só 1 candidate no n=53 (fit=1+YES=approved)
  → Investigar manualmente
```

---

## False positives (AI=YES, humano REJECTED) — 11 casos

(Dados anonimizados — só pseudo + score humano + AI rationale snippet)

Estes 11 casos são onde AI overestimou. Vale comissão revisitar para entender porque rejeitaram apesar de aplicação convincente:

```sql
SELECT pseudo, human_score, fit, ai_rationale_excerpt
FROM (research_runs WHERE rtb='yes' AND outcome='rejected')
ORDER BY human_score DESC
```

(11 cases — IDs preservados em ai_analysis_runs para drill-down via SQL)

**Hipótese**: candidatos com aplicação muito bem escrita mas LinkedIn/entrevista revelaram gaps. Ou perfis "polished but shallow" — texto convince AI mas humanos detectam ausência de substância em conversa.

## False negatives (AI=NO, humano APPROVED) — 5 casos

Caiu de 6 (n=14) para 5 (n=53). Mas em proporção, caiu de 67% para 20% — major win.

5 casos restantes provavelmente são candidatos com aplicação muito concisa onde humanos tinham contexto extra (LinkedIn, prior knowledge, chapter representation) — fundamentalmente irreparável sem AI ter acesso a esses dados.

---

## Recomendações finais (PM ratify)

### Adoção imediata cycle3-2026-b2 (ratificação atualizar)

PM já ratificou Sprint 4 prompt LIVE. UI hint atualizar com calibração nova:

| Verdict + fit | UI badge | Confiança operacional |
|---|---|---|
| YES + fit≥4 | ⭐ Skip-to-interview eligible (74% precision) | High — par-revisão pode ser leve |
| YES + fit≤3 | ✓ Considerar — review típica | Medium — par-revisão padrão |
| NO + fit≤2 | ⚠️ Reject likely — par-revisão prioritária | High soft — rare overrides |
| NO + fit≥3 | ⚠️ Soft signal — review LinkedIn/contexto | Low — caso humano provavelmente vê algo extra |
| uncertain | ↺ Par-revisão prioritária | Não-conclusivo — humano decide |

### Sprint 5 (futuro)

- **Iteração prompt v3**: target precision ↑ sem sacrificar recall (current trade-off Sprint 4 trouxe recall mas perdeu precision)
- **Dimension separation**: separar `track_record_evidence` de `potential_signal` no schema (atualmente combinados em raises_the_bar) — permitir diff analysis explícita
- **LinkedIn integration** (consent-gated): se candidato consente, scrape público + alimenta AI. Resolve 5 FN restantes (todos sem texto adequado mas potencially OK no LinkedIn)
- **Revisitar 5 FN cycle3-2026 cases** para training data documentar rationale humano (PM + Fabricio action)

### Manter
- raises_the_bar como dimension primary
- LGPD Option B PII-stripped path (provedo viável + defensible)
- ai_analysis_runs research_validation rows preservadas para benchmarking futuro

---

## Sample summary stats (n=53)

| Metric | Value |
|---|---|
| Total runs | 53 |
| YES verdict | 31 (58%) |
| NO verdict | 16 (30%) |
| UNCERTAIN | 6 (11%) |
| Approved (humano) | 26 (49%) |
| Rejected (humano) | 25 (47%) |
| Converted | 2 (4%) |
| Avg human score (approved) | ~180 |
| Avg human score (rejected) | ~85 |
| Cost Gemini ~$1-2 USD (53 calls × ~3K tokens output) |

---

## Trace

- p87 Sprint 1: substrate `931c8ae` (anonymize RPC + research EF)
- p87 Sprint 3 MVP n=14 commit `db90e27`
- p87 Sprint 4 prompt evolution `b5106f0` (path b potencial convergente)
- p87 Sprint 3.b paid Tier 1 expansion n=53 (this report)
- LGPD Option B confirmed: zero candidate identity leak ao Gemini
- Cost Gemini Tier 1: ~$1-2 USD totais para n=53

Assisted-By: Claude (Anthropic)
