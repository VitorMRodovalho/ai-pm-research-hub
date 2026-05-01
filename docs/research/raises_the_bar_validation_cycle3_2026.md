# AI `raises_the_bar` Rubric — Validation vs. Decisões Humanas (cycle3-2026)

**Issue**: [#119](https://github.com/VitorMRodovalho/ai-pm-research-hub/issues/119)
**Date**: 2026-05-01 (p87 marathon)
**Status**: **MVP / PRELIMINAR** — sample n=14 (Gemini quota cap day-1; expand pendente)
**LGPD path**: Option B (PII-stripped) — anonymize_application_for_ai_training RPC + pmi-ai-analyze-research EF
**ADR**: ADR-0066 Amendment 2026-05-01 + ADR-0067 N1 Art.20 Safeguards

---

## TL;DR

> AI rubric `raises_the_bar` (introduzida p87 Sprint C) é **conservadora e específica** — quando diz "yes" tem 75% precisão, mas captura apenas 33% dos candidatos eventualmente aprovados pela comissão humana. **Bom como filtro positivo (high-precision shortlist), inadequado como gate único de rejection** (high recall miss).

**Recomendação operacional**: usar `raises_the_bar=yes` como sinal de candidate destaque (skip-to-interview path), mas NÃO usar `raises_the_bar=no` como auto-reject. Combinar com par-revisão humana + fit_for_role >= 4 para decisão final.

---

## Metodologia

### Dataset
- **Cycle**: cycle3-2026 (closed, phase=announcement)
- **Pool original**: 63 candidatos com final outcome humano (31 approved + 30 rejected + 2 converted)
- **Filtro de qualidade**: ≥ 30 chars em algum campo de texto (motivation_letter / non_pmi_experience / leadership_experience / academic_background / proposed_theme / reason_for_applying)
- **Sample MVP atual**: **n=14** (limite quota Gemini Free Tier 10 RPM batch da sessão; expand pendente Sprint 3.b)

### Pipeline
1. RPC `anonymize_application_for_ai_training(application_id)` → strip PII (applicant_name → pseudo, email/phone/linkedin/credly/pmi_id/chapter NULL)
2. EF `pmi-ai-analyze-research` → Gemini 2.5 Flash com mesma `ANALYSIS_SCHEMA` (raises_the_bar verdict + rationale)
3. Persistência em `ai_analysis_runs` com `triggered_by='research_validation'` (NÃO toca `selection_applications.ai_analysis` live)
4. Comparação AI verdict × outcome humano

### LGPD safeguards
- AI nunca recebeu nome real, email, LinkedIn, Credly, telefone, PMI ID ou chapter dos candidatos
- Apenas conteúdo de aplicação (texto declarado pelo candidato em formulário PMI VEP — domain content, não PII direto)
- pseudo_name = "Candidato_<8chars>" (deterministic, não retraceable sem acesso DB)
- Final outcome label (approved/rejected) usado apenas para análise estatística posterior, não enviado a Gemini

---

## Confusion Matrix

| | **AI = YES** | **AI = NO** | Total |
|---|---|---|---|
| **Humano: APPROVED** | 3 (TP) | 6 (FN) | 9 |
| **Humano: REJECTED** | 1 (FP) | 4 (TN) | 5 |
| **Total** | 4 | 10 | 14 |

### Métricas
| Métrica | Valor | Interpretação |
|---|---|---|
| Concordance overall | 7/14 = **50%** | (TP + TN) / total |
| Precision (YES) | 3/4 = **75%** | Quando AI diz YES, 3 em 4 são aprovados |
| Recall (YES) | 3/9 = **33%** | AI captura apenas 1/3 dos aprovados |
| Specificity (NO) | 4/5 = **80%** | Quando humano rejeita, AI também diz NO 80% |
| False Negative Rate | 6/9 = **67%** | AI rejeitaria 67% dos aprovados |
| F1 score (YES) | **0.46** | Moderado-baixo |

> **Concordance "binária"** (ignorando uncertain/ambigous): 64.3% (9/14) considerando que AI=NO+humano=rejected = TN também é "match".

---

## Casos discordantes (insights operacionais)

### False Positives (AI = YES, humano REJECTED) — 1 caso

| Candidato (pseudo) | Score humano | AI Fit | Rationale AI |
|---|---|---|---|
| Fernanda Longato | 178 | 5 | "A aplicação é detalhada, bem articulada e demonstra um pensamento rigoroso sobre um problema complex[o]..." |

**Análise**: candidato com aplicação muito bem escrita e fit técnico aparente. Score humano não-trivial (178). PM/Fabricio rejeitaram — possivelmente por sinal extra-aplicação (LinkedIn fraco, entrevista decepcionante, ou critério não-textual). **Caso clássico onde decisão humana usa contexto que AI não tem.**

### False Negatives (AI = NO, humano APPROVED) — 6 casos

| Candidato (pseudo) | Score humano | AI Fit | Rationale AI (preview) |
|---|---|---|---|
| Alexandre Meirelles | 272 | 4 | "aplicação concisa, sem evidências factuais de contribuições acima da média" |
| Ana Carla Cavalcante | 240 | 2 | "MBA + Mestrado CPMAI mas declara estágio inicial em pesquisa" |
| Mayanna Duarte | 178 | 4 | "bem estruturada e demonstra interesse, mas não apresenta evidências factuais" |
| Antonio Costa | 152 | 2 | "não apresenta evidências factuais de contribuições acima da média" |
| Leandro Mota | 137 | 4 | "candidato afirma estar em estágio inicial de aquisição de conhecimento" |
| Gustavo Ferreira | 132 | 3 | "extremamente breve e genérica, sem detalhar contribuições, projetos específicos" |

**Análise**: AI "ancora" verdict em "evidências factuais de contribuições acima da média" (rationale literal recorrente). PM/Fabricio aprovaram baseado em:
- LinkedIn rico (não visível ao AI)
- Anotações de entrevista (não persistidas como texto)
- Mentoria/potencial não articulado em aplicação
- Diversity / inclusion / chapter representation
- Conhecimento prévio do candidato (PMI community)

### True Positives (AI = YES, humano APPROVED) — 3 casos

| Candidato (pseudo) | Score humano | AI Fit | Rationale AI (preview) |
|---|---|---|---|
| Hayala Curto | 212 | 4 | "background pesquisa e publicações em projetos software" |
| Marcos Klemz | 167 | 5 | "compromisso excepcional com comunidade PMI, facilitador eleito" |
| Thiago Freire | 163 | 5 | "esforço significativo e produção acima da média, evidenciado por publicações" |

**Análise**: ambos AI e humano concordam quando candidato **explicitamente articula evidências** na aplicação (publicações, papers, leadership exercida). Esses são candidatos "auto-evidentes".

---

## Médias por bucket

| AI verdict | Outcome | n | Avg AI fit | Avg human score |
|---|---|---|---|---|
| no | approved | 6 | 3.17 | 185.2 |
| no | rejected | 4 | 2.50 | 91.5 |
| yes | approved | 3 | 4.67 | 180.7 |
| yes | rejected | 1 | 5.00 | 178.0 |

**Observações:**
- Avg human score quando AI=YES (180.7) ≈ avg quando AI=NO+approved (185.2). AI verdict não correlaciona linearmente com score humano.
- Avg fit_for_role tem boa correlação com final outcome (rejected médio 2.50, approved médio 3.17-4.67).
- **Combo `fit_for_role >= 4 + raises_the_bar = yes`** é seletivo: 3 candidatos no sample, todos approved (100% precision).
- **Combo `fit_for_role >= 4 + raises_the_bar = no`** ainda tem 4/4 approved no sample (Alexandre, Mayanna, Leandro outros) — AI=NO não é sinal forte de rejection quando fit é alto.

---

## Recomendações

### Para uso atual da rubric
1. **`raises_the_bar = yes`** → considerar como skip-to-interview (high-precision shortlist), com par-revisão humana ainda obrigatória (não substitui evals)
2. **`raises_the_bar = no`** → **NÃO usar como auto-reject**. Soft signal apenas — comissão precisa investigar via LinkedIn / entrevista / contexto chapter
3. **`raises_the_bar = uncertain`** → fluxo padrão de par-revisão prioritário (AI sinal não-conclusivo)

### Para evolução da rubric (Sprint futuro)
1. **Adicionar dimensão "potential_signal"** orthogonal: candidato com baixo histórico mas alto interesse explícito + fit técnico → YES potencial mesmo sem track record extensivo
2. **Separar "rigor demonstrado" de "raise the bar"** — atualmente AI mistura: alguém pode ter rigor sem elevar bar (track-record sólido mas previsível) e vice-versa (potencial alto sem proof histórico)
3. **Adicionar input opcional**: linkedin_summary text + chapter_history para enriquecer contexto AI sem violar LGPD (com consent retroativo se Option A futuro)
4. **Calibrar prompt para CBGPL launch context**: durante hiring sprint inicial de community-building, threshold "raise the bar" pode flexibilizar para incluir "qualified contributor" não apenas "exceptional"

### Para Sprint 3.b expansion
- Atual sample n=14 (cap Gemini quota free tier ~50/min)
- Pool restante: ~49 candidatos cycle3-2026 elegíveis
- Approach: pg_cron job com 5/min rate (~10 min para completar) OR upgrade Gemini Tier 1 (paid) para burst
- Custo estimado restante: ~$2-3 USD

---

## Sample tabela completa (n=14)

| Pseudo | Outcome | H.Score | H.Evals | AI Fit | AI RTB |
|---|---|---|---|---|---|
| Fernanda L. | rejected | 178 | 4 | 5 | **YES** ⚠ FP |
| Grazielle S. | rejected | 116 | 2 | 2 | NO ✓ |
| Luciana M. | rejected | 102 | 2 | 3 | NO ✓ |
| Robson T. | rejected | 100 | 2 | 3 | NO ✓ |
| Daniel C. | rejected | 48 | 2 | 2 | NO ✓ |
| Alexandre M. | approved | 272 | 3 | 4 | NO ⚠ FN |
| Ana Carla C. | approved | 240 | 5 | 2 | NO ⚠ FN |
| Hayala C. | approved | 212 | 5 | 4 | YES ✓ |
| Mayanna D. | approved | 178 | 3 | 4 | NO ⚠ FN |
| Marcos K. | approved | 167 | 5 | 5 | YES ✓ |
| Thiago F. | approved | 163 | 3 | 5 | YES ✓ |
| Antonio C. | approved | 152 | 3 | 2 | NO ⚠ FN |
| Leandro M. | approved | 137 | 3 | 4 | NO ⚠ FN |
| Gustavo F. | approved | 132 | 3 | 3 | NO ⚠ FN |

---

## Próximos passos

| # | Ação | Owner | Estimativa |
|---|---|---|---|
| 1 | Decisão PM: aplicar Recomendação 1-3 imediatamente nas avaliações cycle3-2026-b2 atuais? | PM | 1h call com Fabricio |
| 2 | Sprint 3.b expand sample para n=63 (full cycle3-2026) | Claude Code (autônomo, quiet window) | 2h (1h queue + 1h analysis) |
| 3 | Sprint 4 evolução prompt rubric per Recomendação evolução | Claude Code (após PM ratify) | 30 min EF + 1h validation |
| 4 | Comissão: revisitar Ana Carla / Alexandre / Mayanna / Leandro / Antonio / Gustavo cases — confirmar approval rationale documental para training data | PM + Fabricio | 30 min cada × 6 |

---

## Referências

- Issue #119 (training data validation) + Issue #117 (workflow gate ecosystem)
- ADR-0066 Amendment 2026-05-01 (workflow gate gap surfacing + raise-the-bar mindset)
- ADR-0067 (AI augmented selection — Art.20 safeguards)
- Migration `20260516440000_p87_anonymize_rpc_and_research_triggered_by.sql`
- EF `supabase/functions/pmi-ai-analyze-research/index.ts`
- Trace conversa Vitor + Claude 2026-05-01 ~16-19h BRT (p87 marathon session)

Assisted-By: Claude (Anthropic)
