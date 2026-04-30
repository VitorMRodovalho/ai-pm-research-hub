# ADR-0067 — AI-Augmented Selection: LGPD Art. 20 Safeguards & Human-in-the-Loop Invariant

- **Status:** Proposed
- **Date:** 2026-04-30
- **Author:** Claude (council Tier 2 review by legal-counsel) — pending PM ratification
- **Supersedes:** none. **Complements:** ADR-0066 (PMI Journey v4 Phase 1).
- **Trigger:** Wave 5b spec (`docs/specs/p84-wave5-ai-augmented-self-improvement.md`) introduces multi-version AI analysis with metadata visible to the committee. legal-counsel review (2026-04-30) flagged that this surface increases risk of LGPD Art. 20 violation through anchoring bias unless explicit safeguards are documented and enforced.

## Contexto

A plataforma Núcleo IA & GP utiliza Google Gemini 2.5 Flash para análise automatizada de aplicações de candidatura voluntária. A partir de Wave 5b, o sistema permitirá que candidatos enriqueçam suas aplicações pós-consent, com cap de 2 re-análises por candidato. Cada versão é preservada em `ai_analysis_versions` para auditoria, e o comitê avaliador (`manage_selection`) tem acesso ao histórico completo, incluindo:

- Versão original da análise (score, red flags, áreas de probe)
- Versões enriquecidas (versão 1 e versão 2)
- Diffs visuais entre versões
- Audit log de visualizações de tópicos prováveis da entrevista (`selection_topic_views`)
- Metadados quantitativos: `enrichment_count`, timestamps de consent re-analysis, IPs de acesso

Esses metadados são **informativos** — destinados a apoiar a tomada de decisão humana com contexto adicional. **Nenhum desses metadados pode ser utilizado como critério negativo de seleção** sem violar a LGPD Art. 20 e a política institucional do Núcleo.

## Forças em tensão

1. **Transparência ao comitê vs. risco de anchoring bias.** Mostrar a evolução do score (ex: "1 → 3" pós-enriquecimento) pode levar a julgamento humano enviesado pela versão inicial mais fraca, ainda que a versão final seja superior. Estudos de cognição (Kahneman 2011) mostram que números iniciais ancoram decisões mesmo após informações contraditórias.

2. **Auditoria robusta vs. punição implícita.** Registrar quantas re-análises o candidato fez e se ele visualizou os tópicos prováveis da entrevista é necessário para auditoria pós-decisão e para detecção de abuso. Mas torna esses metadados visíveis cria a possibilidade de o comitê interpretá-los como sinal qualitativo (ex: "candidato menos genuíno por ter usado todas as 2 re-análises").

3. **Direito do candidato à revisão humana (Art. 20 LGPD) vs. eficiência operacional.** O Art. 20 garante revisão de decisões automatizadas. Se a IA influenciar excessivamente a decisão humana através de anchoring, a "revisão humana" torna-se procedimentalmente formal mas materialmente automatizada — violando o espírito do Art. 20.

## Decisão

### D1 — Invariante operacional não-negociável

**Toda decisão de admissão, recusa ou avanço de candidato no processo seletivo voluntário do Núcleo IA & GP é tomada exclusivamente pelo comitê humano avaliador, com base na versão final da aplicação enriquecida pelo candidato.**

Análises por IA (versão original ou versões enriquecidas) e metadados de processo (contagem de re-análises, timestamps, audit logs) constituem **insumos contextuais informativos** ao comitê — sem caráter vinculativo, sem peso decisório quantificável.

### D2 — Salvaguardas técnicas contra anchoring bias

A interface administrativa (`/admin/selection/[id]`) será desenhada para mitigar anchoring:

- **Versão final em destaque visual:** a versão mais recente da análise IA é renderizada por padrão; versões anteriores ficam em seção colapsável "Histórico de versões".
- **Sem renderização inline da evolução de score:** o painel admin NÃO mostra "Score: 1 → 3" como header; apenas o score atual. A evolução fica disponível clicando-se no histórico.
- **Sem flags ranqueadores baseados em metadados de processo:** o painel admin NÃO ordena, filtra ou destaca candidatos com base em `enrichment_count` ou flags de visualização de tópicos.
- **Audit log read-only:** comitê pode consultar quem viu tópicos e quando, mas a UI deixa claro que essa informação é "para contextualização da entrevista", não "para julgamento da candidatura".

### D3 — Salvaguardas processuais

O onboarding/treinamento dos membros do comitê avaliador deve incluir:

- Reconhecimento explícito do invariante D1 (decisão humana baseada em versão final);
- Explicação do que são metadados informativos e por que não podem ser critério;
- Compromisso de documentar, em sede de auditoria do processo seletivo, qual versão da análise foi consultada e por quê.

A inclusão deste ADR e do treinamento associado é pré-requisito para concessão da `designation = curator` ou `co_gp` para fins de seleção.

### D4 — Direito de revisão humana garantido (Art. 20 LGPD)

Qualquer candidato recusado pode solicitar revisão da decisão dentro de 30 dias após o encerramento do ciclo. A revisão será conduzida por:
- Membro do comitê **distinto** dos que tomaram a decisão original
- Acesso à mesma versão final da aplicação que o comitê viu
- Acesso à análise IA contextual (sem influência de versões intermediárias)
- Resposta documentada em prazo de 15 dias

Esta garantia será explicitada na cláusula 9-A do Termo de Voluntariado R3-C3 (draft em `docs/drafts/r3c3-clause-enriched-data-draft.md`).

### D5 — Audit trail imutável

`selection_topic_views` é INSERT-only (RLS: `manage_selection` pode read; `service_role` insere; nenhum role pode UPDATE/DELETE — apenas CASCADE via right-to-erasure no parent application).

`ai_analysis_versions` segue mesmo padrão — INSERT-only, append-only, CASCADE em right-to-erasure.

Tentativas de manipulação destas tabelas geram alerta em `ai_analysis_runs.error_detail` + cron `detect_audit_drift_15min` (a ser implementado em Wave 5b-5).

## Consequências

### Positivas

- Compliance LGPD Art. 20 reforçado materialmente, não apenas formalmente
- Anchoring bias mitigada por design da UI admin (não confia apenas em treinamento humano)
- Audit trail robusto suporta contestação processual de candidato eventualmente recusado
- Coerência com framework "AI augments human, doesn't replace" do Núcleo
- Diferencial publishable em PMI Global Summit / blog framework — não é "mais um AI screening tool"

### Negativas / trade-offs

- Comitê tem visibilidade restrita (não vê evolução inline de score) — pode reduzir nuance da avaliação. Mitigação: histórico colapsável fica acessível para quem quiser explorar.
- Treinamento adicional do comitê adiciona overhead operacional. Mitigação: documentação clara + checklist de onboarding.
- D5 (audit imutável) requer disciplina técnica nas migrations e RLS — risco de drift se RLS forem alteradas em wave futura sem revisão deste ADR. Mitigação: contract test pgPolicy guard estendido para cobrir esses padrões.

## Implementação

- **Wave 5b-1**: schema migration + EF deploy — incluir `selection_topic_views` e `ai_analysis_versions` com RLS imutável conforme D5.
- **Wave 5b-4**: admin diff panel — implementar conforme D2 (versão final em destaque, histórico colapsável).
- **Pré-deploy**: treinamento do comitê (D3) — documento separado em `docs/training/committee-art20-safeguards.md`.
- **R3-C3 ratificação**: cláusula 9-A draft em `docs/drafts/r3c3-clause-enriched-data-draft.md` consolidada com este ADR.

## Referências

- LGPD Lei nº 13.709/2018, Art. 7,V; Art. 9,I; Art. 20
- ADR-0066 (PMI Journey v4 Phase 1)
- Spec p84-wave5-ai-augmented-self-improvement
- legal-counsel review 2026-04-30
- Kahneman, D. (2011). Thinking, Fast and Slow — anchoring effect

## Status histórico

- 2026-04-30: ADR proposto após council Tier 2 review (legal-counsel + ai-engineer + ux-leader)
- Pendente: PM ratification + comitê CR-050 incorporação no Termo R3-C3
