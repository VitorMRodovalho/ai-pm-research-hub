# Synthesis — Council 4-lens review of ADR-0079 (subjective scoring via video transcription)

**Date**: 2026-05-12 (sessão p151)
**Source documents**:
- `docs/specs/p150-b-full-subjective-scoring-spec.md` (spec draft)
- `docs/adr/ADR-0079-subjective-scoring-via-video-transcription.md` (status PROPOSED)
- `docs/council/2026-05-12-p151-subjective-scoring/data-architect-review.md`
- `docs/council/2026-05-12-p151-subjective-scoring/ai-engineer-review.md`
- `docs/council/2026-05-12-p151-subjective-scoring/security-engineer-review.md`
- `docs/council/2026-05-12-p151-subjective-scoring/legal-counsel-parecer.md`

**Status agregado**: 2 BLOCK (data-architect, security-engineer) + 1 OK com ajustes (ai-engineer) + 1 APROVADO COM AJUSTES (legal-counsel)
**Path forward**: ADR-0079 NÃO ACCEPTED até 11 itens bloqueantes resolvidos. Implementação (p152+) bloqueada até ACCEPTED.

---

## 1. Convergências (4 lentes concordam)

1. **D-MODEL = Sonnet 4.6 + prompt cache** (consenso, com nuance):
   - ai-engineer: Haiku under-shoots para scoring qualitativo fino; Gemini Free Tier saturação garantida (250 calls/ciclo)
   - Custo $3.50/ciclo defensável; cache hit ratio ~95% após 1º candidato
   - Pattern alinhado com ADR-0074 triage

2. **D-CTX = Não incluir role/chapter** (consenso):
   - ai-engineer: pillar system já abstrai contexto; role criaria meta-rubric implícito que vicia calibração
   - security/legal: alinhado com princípio de mérito

3. **D-NON-BIND = Score nunca consumido em fórmula** (consenso, com salvaguarda adicional):
   - legal-counsel: human-in-the-loop com efetiva capacidade afasta Art. 20 §1
   - Adicional CONSENSUS: **banner UI obrigatório** no modal indicando "Score IA — decisão final é humana"
   - Invariante CI auditando `pg_get_functiondef` de `final_score` é bloqueante (security + data-architect)

4. **D-EXPORT = Reasoning incluído no export Art. 18** (consenso):
   - legal-counsel: reasoning é "dado pessoal derivado do titular", alinhado Art. 18 II + Art. 20 §1
   - Export completo: model + model_version + prompt_hash + transcription_hash + reasoning + confidence + score + data

5. **D-RUBRIC = Tabela `pillar_rubrics` versionada** (consenso, com nuance técnica):
   - ai-engineer: opção B com cache strategy deterministic (system prompt ordenado, `prompt_hash` em `model_version`)
   - data-architect: schema com `organization_id NOT NULL` + RLS + `is_active` + `prompt_hash`

6. **D-TRIGGER = Cron 5min polling** (consenso, com índices adicionais):
   - data-architect: simpler, latency aceitável (STT já leva minutos)
   - Requer: index `idx_vsa_source_completed` + adicionar `'transcribed'` em `idx_video_screenings_status_pending`

---

## 2. Divergências críticas resolvidas

### 2.1 D-CONSENT (nova decisão surgida no council)

A spec original propôs reuso de `consent_ai_analysis_at` (mesmo pattern ADR-0074). Council identificou que **isso não é mais defensável** sem ajuste formal:

| Lente | Posição |
|---|---|
| security-engineer | HIGH severity — escopo material diferente. Sugere validar texto do Termo ou criar `consent_subjective_scoring_at` dedicado |
| legal-counsel | Preferred path: **consent dedicado** `consent_subjective_video_scoring_at`. Alternativa: adendo ao consent existente + re-disclosure ativo (não retroativo, per ADR-0076 Princípio 4 Decision 3 Option B) |

**Resolução recomendada**: **consent dedicado** `consent_subjective_video_scoring_at` (+ timestamp revogação) com tela de consent ESPECÍFICA na jornada de upload de vídeos. Máxima robustez jurídica e separação de finalidades.

### 2.2 Prazo de revoke (72h vs imediato)

| Lente | Posição |
|---|---|
| security-engineer | **Imediato** preferível (defensável em fiscalização, elimina janela de exposição) |
| legal-counsel | 72h é defensável (sem prazo legal específico), mas comunicar ao titular como "até 5 dias úteis" |

**Resolução recomendada**: **execução imediata** (mesma transaction do UPDATE em selection_applications) **+ fallback cron para edge cases** (crash, rows órfãs). Comunicar ao titular como "até 5 dias úteis" na tela de revogação (margem defensiva para falhas técnicas).

### 2.3 Verificação revoke no path de scoring

Bug concreto identificado por security-engineer: spec §3 step 1 da EF NÃO checa `consent_ai_analysis_revoked_at IS NULL`. Candidato que revogar consent ainda terá scoring disparado pelo cron.

**Resolução**: step 1 corrigido para `consent_subjective_video_scoring_at IS NOT NULL AND consent_subjective_video_scoring_revoked_at IS NULL` (combinando com 2.1).

---

## 3. Itens BLOQUEANTES para ACCEPTED (11 totais)

### Schema/DDL (data-architect)

| # | Item | Migration |
|---|---|---|
| 1 | Partial unique index `idx_vsa_uniq_active ... WHERE status NOT IN ('superseded','failed')` em vez de constraint UNIQUE | M1 |
| 2 | `superseded_by uuid REFERENCES video_screening_analysis(id) ON DELETE SET NULL` | M1 |
| 3 | Extension de `handle_consent_revocation()` para incluir `DELETE FROM video_screening_analysis WHERE application_id = NEW.id` (LGPD gap concreto) | M1 |
| 4 | Invariant `P_subjective_score_avg_consistency` + named sync trigger `_trg_subjective_score_avg_sync` (ADR-0012 Principle 2) | M2 |

### EF/Modelo (ai-engineer)

| # | Item | Onde |
|---|---|---|
| 5 | JSON schema corrigido: `score: { type: "number" }` (não integer) + `additionalProperties: false` + validação pós-parse documentada na spec | EF + spec |
| 6 | EF step 1 valida `consent_subjective_video_scoring_at IS NOT NULL AND consent_subjective_video_scoring_revoked_at IS NULL` (combina #5+#8) | EF |
| 7 | Calibration RPC retorna Krippendorff α + MAE + viés sistemático além de Pearson r | RPC `get_subjective_calibration_stats` |

### Consent/Legal (security + legal)

| # | Item | Onde |
|---|---|---|
| 8 | Coluna `consent_subjective_video_scoring_at` + `consent_subjective_video_scoring_revoked_at` em `selection_applications` + tela de consent dedicada na jornada de upload | M0 (precede M1) + frontend `interview_optout.astro` ou equivalente |
| 9 | Material change Termo de Adesão v2.7→v2.8 incluindo: (a) análise IA de conteúdo de vídeo com scoring; (b) disclosure de processamento por terceiro (Anthropic como operador); (c) direitos titular (acesso, revogação, revisão) | Doc + workflow ratificação curadores + Ângelina |
| 10 | Banner UI obrigatório `<aside>` não-dismissable no modal Vídeos: "Score gerado por IA — sinal de apoio. Decisão final é exclusivamente do Comitê de Curadoria." | Frontend `selection.astro` modal Vídeos |
| 11 | Confirmação DPA Anthropic cobre transcrição de vídeo como input ao modelo (ou adendo DPA antes de deploy) | Verificação documental + adendo se necessário |

---

## 4. Itens NÃO-bloqueantes (vão para implementação p152+)

### Schema enhancements

- `DEFAULT auth_org()` em `organization_id` da nova tabela
- `pillar_rubrics.is_active` + `pillar_rubrics.prompt_hash` para cache invalidation detection
- `reasoning_truncated boolean DEFAULT false` em vez de hard CHECK length≤500 (truncate em EF, marca a coluna)
- `failure_reason` como ENUM/CHECK: `IN ('low_transcription_confidence','transcription_too_short','model_timeout','invalid_json_output','consent_revoked','rubric_load_error')` (não texto livre — risco PII)
- Status `failed_permanent` separado de `failed` + `CHECK (retry_count <= 3)`
- `rubric_version_id` em `ai_processing_log` para queryability
- `idx_vsa_source_completed ON video_screening_analysis(source_screening_id) WHERE status='completed'`
- Adicionar `'transcribed'` em `idx_video_screenings_status_pending`

### EF/Modelo

- STT threshold elevado para `>= 0.65` (não 0.60)
- Faixa intermediária `0.50-0.64` → force `confidence='low'` no output
- System prompt cacheado inclui instrução anti-bias PT-BR explícita ("avalie conteúdo semântico, não penalize vocabulário regional/informalidade")
- Preprocessing transcrição: truncar a ~2000 tokens no final de frase + sanitizar timestamps STT
- `pillar_rubrics` lida per-invocation (não cached at EF boot) com ordenação determinística

### LGPD operations

- Monitoring ativo revoke queue: alerta se rows não purged > 72h pós revoke
- SLA comunicado ao titular: "até 5 dias úteis" (mesmo que execução técnica seja imediata)
- Notificação ao candidato pós-scoring via Resend: "Seus vídeos foram analisados por IA. Direito de acesso e revisão." (Art. 9 + Art. 20 transparência)
- Audit de divergências deliberadas: calibration view registra casos em que comitê divergiu do score IA + motivo
- Verificar shape de `ai_processing_log` — deve armazenar somente hashes (não conteúdo); incluir `screening_id` FK referencing `pmi_video_screenings`
- Verificar purge cron `cycle_decision_date`: faz DELETE em `selection_applications` (CASCADE propaga) ou apenas UPDATE/anonymize (CASCADE não dispara — Risk 2 ADR-0076 Princípio 6)

### Frontend/UX

- Filtro/sort para video_screening_status_agg (já shipped em B-light, mas calibration view nova)
- Calibration view modal: per-pillar table com n + α + MAE + viés; warnings se n<20; null para n<5 por pillar
- Lazy show score: revelar score IA SOMENTE depois de avaliação humana submetida para o pillar (Cycle 5+ feature; Cycle 4 mantém visível por volume baixo)

---

## 5. Decisões consolidadas (10 totais — 9 originais + 1 nova D-CONSENT)

| ID | Decisão | Recomendação consolidada | Justificativa |
|---|---|---|---|
| D-MODEL | Modelo subjective | **Sonnet 4.6 + prompt cache** | ai-engineer; Haiku/Gemini não fit |
| D-CTX | Role/chapter no prompt? | **Não (A)** | ai-engineer; pillar system abstrai context, role cria meta-rubric vicioso |
| D-TRIGGER | Pipeline trigger | **Cron 5min polling (A)** + 2 índices | data-architect; latency aceitável |
| D-NON-BIND | Score em fórmula? | **Nunca (A) + banner UI + invariante CI** | consenso; salvaguardas Art. 20 §1 |
| D-EXPORT | Reasoning em export? | **Sim (A) + model_version + hashes + confidence + score + data** | legal-counsel; Art. 18 II + Art. 20 §1 |
| D-RUBRIC | Onde rubric? | **Tabela versionada (B)** + cache strategy deterministic | ai-engineer; permite tweaks sem deploy + mantém cache hit |
| D-RETRY-CAP | Max retries | **3 (A)** + status `failed_permanent` + `CHECK retry_count<=3` | data-architect |
| D-LATENCY-SLA | SLA p95 | **5min (A)** | sem objeção |
| D-SUPERSEDE | Re-run comportamento | **Insert + supersede (A)** com partial unique index (item bloqueante #1) | data-architect |
| **D-CONSENT** (NOVA) | Consent reuse ou dedicado? | **Consent dedicado** `consent_subjective_video_scoring_at` + Material change Termo v2.8 | legal-counsel preferred path |

---

## 6. Cronograma revisado (5 sessões → 6 sessões)

| Sessão | Frente | Output |
|---|---|---|
| p151 (esta) | Council 4-lens + synthesis | Este doc + 4 reviews + decisões consolidadas |
| **p151b (nova — pré-ACCEPTED)** | Amendments à spec + ADR-0079 → ACCEPTED | Spec atualizada incorporando 11 bloqueantes + ADR-0079 versão final com decisões |
| p152 | Material change Termo Adesão v2.8 (draft + curador ratification path) | Doc draft + email curadores |
| p153 | Migrations 1-6 (incluindo M0 consent column + M1 video_screening_analysis + M2 trigger sync + M3 pillar_rubrics + M4 RPCs + M5 cron) | Migrations applied + smoke |
| p154 | EF `pmi-ai-subjective` + frontend (banner UI + consent gate + calibration view + notificações) + MCP tools | Code shipped |
| p155 | QA + dry-run Cycle 4 (Eduardo Luz com re-disclosure individual) + monitoring + DPA verification | Production-ready |

---

## 7. Recomendação operacional (próxima ação)

### Para Eduardo Luz (Cycle 4 — único candidato com vídeos)

**ETHICAL PATH**: re-disclosure individual antes de rodar EF sobre vídeos dele. Não shipar production-grade scoring sobre cycle 4 sem consent gate dedicado em produção.

**Opção interim para calibração técnica**: rodar EF em modo **dry-run não-persistente** sobre Eduardo Luz para validar:
- Quality de transcrição STT está acima de threshold (0.65)
- Output JSON schema funciona corretamente
- Prompt cache hit ratio é o esperado
- Custo real bate com estimativa
- Reasoning é coerente

Resultados ficam em arquivo local (não em `video_screening_analysis`), apresentados para PM como evidência. Depois de consent gate shipa em produção, re-rodar com persistence completa se Eduardo aceitar.

### Para PM Vitor

**Passo 1 (esta sessão)**: você revisa esta síntese + 4 reviews. Confirma as 10 decisões consolidadas (ou ajusta).

**Passo 2 (próxima sessão p151b)**:
- Atualizo spec `p150-b-full-subjective-scoring-spec.md` incorporando 11 ajustes bloqueantes
- Atualizo ADR-0079 com decisões registradas (status PROPOSED → ACCEPTED)
- Sem código ainda; apenas docs

**Passo 3 (p152)**: drafting Material change Termo Adesão v2.8 (workflow ratificação curadores)

**Passo 4 (p153+)**: implementação code

### Bloqueio operacional explícito

**Nenhuma migration `b_full_*` aplica em prod até:**
- ADR-0079 status = ACCEPTED
- 11 itens bloqueantes resolvidos na spec
- Material change Termo Adesão v2.8 ratificada
- DPA Anthropic confirmada

---

## 8. Cross-refs

- ADR-0074 (Onda 3 dual-model AI) — pattern arquitetural que esta ADR estende
- ADR-0076 (PMI 3-d volunteer model + Phase B base legal) — base legal LGPD da plataforma
- ADR-0077 (auth_org caller-derived) — RLS scope
- ADR-0012 (schema consolidation principles) — Principle 2 (cache columns + sync trigger + invariant) + Principle 6 (cascade integrity)
- Spec doc origin: `docs/specs/p150-b-full-subjective-scoring-spec.md`
- ADR origin: `docs/adr/ADR-0079-subjective-scoring-via-video-transcription.md`
- Commit B-light predecessor: `73168c0`
- Predecessor commits: `010a10d` (p149 attendance), `bcab94f` (p150 peer_eval_count fix), `fd552aa` (spec + ADR PROPOSED)
- Council folder: `docs/council/2026-05-12-p151-subjective-scoring/`
