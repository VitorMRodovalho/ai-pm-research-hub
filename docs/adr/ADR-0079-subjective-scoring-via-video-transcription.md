# ADR-0079: Subjective Scoring via Video Transcription (4th AI Frontier)

**Status**: PROPOSED (aguarda council review + PM decisions D-MODEL..D-LATENCY-SLA)
**Date**: 2026-05-12
**Decider**: PM Vitor Maia Rodovalho (GP Núcleo IA & GP)
**Trigger**: p150 B-full — operacionalizar avaliação subjetiva por vídeo para validar modelos e habilitar calibração
**Predecessor**: p150 B-light (commit `73168c0`) — visibilidade tri-state shipped
**Spec doc**: `docs/specs/p150-b-full-subjective-scoring-spec.md`

---

## Context

A plataforma tem três frentes IA ativas/declaradas (ADR-0074):

| # | Frente | Modelo | Estado |
|---|---|---|---|
| 1 | Narrativa qualitativa (`raises_the_bar`, `summary`, `key_strengths`, `areas_to_probe`) | Gemini 2.5 Flash | ✅ Em produção |
| 2 | Triage score 0-10 (pre-screen) | Claude Sonnet 4.6 + prompt cache | ⏳ Schema shipped p107, EF pending |
| 3 | Interview briefing (3 perguntas) | Claude Haiku 4.5 | ⏳ MCP tool definido, impl pending |

**Gap concreto**: candidatos têm a opção de submeter vídeos (5 por pillar) em alternativa à entrevista síncrona (`pmi_video_screenings` table populated pelo fluxo Phase B). Transcrição automática (STT) está pipelined. Mas **não existe scoring automatizado sobre o conteúdo dos vídeos** — comitê precisaria assistir 5×~3-5min por candidato para formar opinião, inviável em ciclos com volume.

Cycle 4 atual: 1 candidato (Eduardo Luz) com 5 vídeos uploaded; 15 candidatos opted-out; 16 sem decisão. Volume baixo permite calibração inicial controlada antes de operacionalizar em ciclos maiores.

**PM direção** (p150, 2026-05-12): "vamos em seguida para o full (pq é importante ter a funcionalidade operacional, até para facilitar feedbacks, engajamento e calibracoes futuras)".

Resultado: **4ª frente IA** introduzida nesta ADR.

---

## Decision (proposed)

Adicionar **subjective scoring via transcription** como 4ª frente IA da plataforma de seleção, seguindo o padrão arquitetural de ADR-0074 (audit via `ai_processing_log`, consent gate reused, LGPD Art. 20 §1 non-binding) com adições específicas:

### Arquitetura proposta

| Camada | Componente |
|---|---|
| Schema | NEW table `video_screening_analysis` (1 row per pillar per application) + derived col `selection_applications.ai_subjective_score_avg` |
| Pipeline | EF `pmi-ai-subjective` triggered by cron polling sobre `pmi_video_screenings.status='transcribed'` |
| Model | **D-MODEL pendente** — recomendação Sonnet 4.6 + prompt cache (mesmo padrão triage ADR-0074) |
| Audit | Reusa `ai_processing_log` (purpose=`subjective_scoring`) — preserva LGPD Art. 37 |
| Consent | Reusa `consent_ai_analysis_at` — revoke trigger 72h purga `video_screening_analysis` |
| Retention | Reusa cron `cycle_decision_date` purge (90d não-selecionados, 180d selecionados) |
| Frontend | Card por pillar no modal "Vídeos" (já existe B-light) + nova calibration view |
| MCP | 3-4 tools novas (paralelas ao pattern `get_application_video_screenings` shipped p150) |

### LGPD Art. 20 §1 compliance

1. **Score é non-binding**: nenhuma RPC de decisão consome `ai_subjective_score_avg`. Score é signal visual.
2. **Human-in-loop forçado por design**: `final_score` = computed de `selection_evaluations` humanas (objective + interview + leader_extra). IA subjective fica fora da fórmula.
3. **Audit trail completo**: `ai_processing_log` + `video_screening_analysis.prompt_hash`/`transcription_hash` permitem reprodutibilidade.
4. **Consent gate dedicado**: reusa `consent_ai_analysis_at` (cobre toda análise IA do candidato).
5. **Revoke trigger 72h**: purga `video_screening_analysis` rows quando candidato revoga consent.
6. **Retenção LGPD**: piggybacks no purge cron existente (90d/180d).
7. **Export Art. 18**: `video_screening_analysis` rows incluídas no export do titular (D-EXPORT=A default).

---

## Decisões abertas (council irá pesar; PM decide)

Detalhe das opções em `docs/specs/p150-b-full-subjective-scoring-spec.md` §8. Matriz resumida:

| ID | Decisão | Default proposto | Quem pesa |
|---|---|---|---|
| D-MODEL | Modelo subjective | Sonnet 4.6 + cache | ai-engineer + PM |
| D-CTX | Inclui role/chapter no prompt? | Não (evita bias) | ai-engineer + security |
| D-TRIGGER | Pipeline trigger | Cron 5min polling | data-architect |
| D-NON-BIND | Score entra em `final_score`? | Nunca | legal-counsel + PM |
| D-EXPORT | Reasoning em LGPD export? | Sim | legal-counsel + PM |
| D-RUBRIC | Onde fica rubric? | Tabela `pillar_rubrics` versionada | data-architect + ai-engineer |
| D-RETRY-CAP | Max retries antes failed permanente | 3 | data-architect |
| D-LATENCY-SLA | SLA p95 análise | 5min | product-leader + PM |
| D-SUPERSEDE | Re-run comportamento | Insert + mark prior superseded | data-architect |

---

## Council brief (próxima sessão)

Spec doc completo deve ser distribuído para 4 council agents **em paralelo**, com prompts específicos:

### data-architect

> Audita §2 (schema), §4 (pipeline + cron), §10 R1/R3/R6/R7. Foco especial em (a) FK ON DELETE CASCADE em `source_screening_id` — propaga purge corretamente? (b) trigger AFTER INSERT em `video_screening_analysis` computando `ai_subjective_score_avg` — cascade pressure em batch (50 × 5 = 250 rows simultâneas)? (c) UNIQUE constraint sobre `(source_screening_id, model, model_version) WHERE status != 'superseded'` — funciona com partial index? (d) D-TRIGGER A vs B vs C — recomenda?

### ai-engineer

> Audita §3 (EF design + prompt structure), §8 D-MODEL/D-CTX, §10 R1. Foco em (a) Sonnet 4.6 vs Haiku 4.5 vs Gemini 2.5 Flash — qual fitness pra score 0-10 reasoning ≤500 chars? (b) prompt caching ROI nesse uso (rubric ~5K, payload por candidato ~1.5K)? (c) D-CTX — incluir role/chapter no prompt é bias risk ou information gain? (d) JSON schema canonical pra `output_config.format.schema` considerando limitação `feedback_anthropic_structured_output_schema_limits.md`?

### security-engineer

> Audita §5 (LGPD compliance), §10 R4, §8 D-NON-BIND/D-EXPORT. Foco em (a) consent reuse — `consent_ai_analysis_at` cobre subjective scoring formalmente ou precisa coluna nova `consent_subjective_scoring_at`? (b) Art. 20 §1 strict — score non-binding é suficiente ou precisa adicional (banner UI? checkbox PM)? (c) revoke trigger 72h vs 24h — qual é correto? (d) prompt/transcription hashes em audit cobrem retroatividade se titular pede explicação?

### legal-counsel

> Audita §5 (LGPD compliance), §8 D-NON-BIND/D-EXPORT, §10 R4. Foco em (a) Art. 20 §1 — score automatizado de subjective requer salvaguarda adicional além de "não consome em fórmula"? (b) Art. 7º base legal — consent reuse é suficiente ou subjective scoring constitui tratamento adicional que exige consent específico? (c) Art. 18 export — reasoning é "dado pessoal do titular" ou "output derivado"? Tem que exportar? (d) retenção 90d/180d alinhada com Art. 16? Considerando dado ser "decisão automatizada", precisa retenção diferenciada?

Output dos 4 council agents em `docs/council/2026-05-12-p151-subjective-scoring/` (4 arquivos paralelos).

Synthesis depois: `docs/council/decisions/2026-05-12-p151-subjective-scoring-synthesis.md` com PM decision points consolidados.

---

## Implementation gating

ADR-0079 ACCEPTED é **precondição** para qualquer migration `b_full_*` aplicar em prod. Status PROPOSED bloqueia código.

Sequência de promoção:

1. PM revisa spec p150-b-full-subjective-scoring-spec.md
2. PM revisa esta ADR-0079 (PROPOSED)
3. Council 4 lentes em paralelo (próxima sessão p151)
4. PM decide 9 decisões (D-MODEL..D-SUPERSEDE) em síntese
5. ADR-0079 → ACCEPTED com decisões registradas
6. Implementação inicia (sessões p152+)

---

## Consequências

### Positivas

- Comitê tem signal automatizado sobre conteúdo dos vídeos → reduz fadiga em ciclos com volume
- Calibração IA × humano por pillar → permite validar modelo + identificar viés
- Habilita engajamento de candidatos que escolhem rota vídeo (15 opted-out em cycle 4 sugere que falta clareza de valor — feedback IA pode mudar adoção em ciclos futuros)
- Pattern reusável: 4ª frente segue ADR-0074 — sem nova arquitetura, só extensão
- Audit + retention LGPD piggybacks em mecanismo existente — baixo custo de compliance

### Negativas

- Adiciona ~$3.50/ciclo de custo IA (Sonnet 4.6 + cache estimado em 50 candidatos × 5 pillars)
- Mais um modelo a monitorar/calibrar — sobrecarga operacional incremental
- Risco viés se prompt context inclui role/chapter (mitigado via D-CTX=A default)
- Re-scoring quando rubric muda exige versionamento (mitigado via `model_version` + `prompt_hash`)

### Neutras

- Consent reuse (`consent_ai_analysis_at`) preserva fluxo existente, mas pode requerer ajuste se council decidir consent dedicado (D-CTX security-engineer review)

---

## Cross-refs

- Spec doc: `docs/specs/p150-b-full-subjective-scoring-spec.md`
- ADR-0074 (Onda 3 dual-model AI) — padrão pipeline IA seleção que esta ADR estende
- ADR-0076 (PMI 3-d volunteer model + Phase B base legal) — base legal LGPD candidato
- ADR-0077 (auth_org caller-derived) — RLS scope
- Migration `20260516200000_phase_b_pmi_journey_v4.sql` — pmi_video_screenings table origem
- Commit `73168c0` (p150 B-light) — visibilidade tri-state predecessor
- `feedback_anthropic_structured_output_schema_limits.md` (p108) — JSON schema limitações
- `ARM_PILLARS_AUDIT_P107.md` ARM-11 — AI Layer cross-cutting
