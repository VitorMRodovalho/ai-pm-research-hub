# Spec p150 B-full — Subjective Scoring via Video Transcription

**Status**: DRAFT · POST-COUNCIL (council 4-lens p151 concluído; 11 blockers + 10 decisões consolidadas; AWAITING ratification gates antes de implementação)
**Sessão**: p150 (drafted) + p151 council 4-lens + p152 (amendments registrados)
**Owner**: PM Vitor Maia Rodovalho
**Predecessor**: p150 B-light (commit `73168c0`) — visibilidade tri-state shipped
**Sucessor planejado**: ADR-0079 → ACCEPTED após gates fecharem
**Council synthesis**: `docs/council/decisions/2026-05-12-p151-subjective-scoring-synthesis.md`

> ⚠ **Esta spec NÃO está código-ready.** Implementação inicia somente após **todos** os 11 blockers em §11 da ADR-0079 fecharem (M0 = consent column dedicada + Termo v2.8 + DPA Anthropic). Sessão p152 registrou amendments documentais; código fica congelado até gate clearance.

---

## 0. Contexto e gap

Em p150 B-light (shipped 2026-05-12), a plataforma ganhou:

- `pmi_video_screenings.status` agregado em 3 estados (`uploaded` / `opted_out` / `none`) exposto em `get_selection_dashboard`
- RPC `get_application_video_screenings` retornando transcrição + storage links por pillar
- Modal "Vídeos" no admin/selection com cards por pillar

O que **não existe ainda no domínio**:

| Camada | Existe? | Comentário |
|---|---|---|
| Transcrição automática do vídeo (STT) | ✅ — colunas `transcription`, `transcription_provider`, `transcription_at`, `transcription_confidence` populadas no fluxo Phase B | Ver migration `20260516200000_phase_b_pmi_journey_v4.sql` |
| **Avaliação subjetiva (score 0-10 por pillar via IA sobre a transcrição)** | ❌ | Não há schema, EF, nem RPC |
| Visualização da avaliação subjetiva | ❌ | Modal aba "Vídeos" tem placeholder "B-full pending" |
| Calibration view (validar modelo cruzando IA × avaliador humano) | ❌ | Depende do scoring acima existir |

**Problema concreto** (cycle 4 atual): 1 candidato ([REDACTED-332-NAME]) com 5 vídeos uploaded. Comitê não tem signal automatizado sobre conteúdo dos vídeos — precisaria assistir ~5×3-5min cada para formar opinião. Nas 80+ apps típicas em ciclos futuros com volume, é inviável.

**Motivação operacional** (PM, esta sessão): "operacionalizar a funcionalidade, ate para facilitar feedbacks, engajamento e calibracoes futuras".

---

## 1. Escopo da spec

### Em escopo

1. **Schema nova tabela** `video_screening_analysis` — score por pillar por candidato + reasoning + model metadata
2. **EF nova** `pmi-ai-subjective` — consome `pmi_video_screenings.transcription`, produz score 0-10 por pillar + reasoning ≤500 chars + confidence
3. **Pipeline trigger**: cron polling sobre `pmi_video_screenings WHERE status='transcribed' AND not exists analysis` (não trigger AFTER UPDATE — evita cascade pressure)
4. **LGPD Art. 20 §1** — score é non-binding (apenas signal), decisão humana é fonte autoritária (mesmo padrão ADR-0074 triage)
5. **Frontend** — popular o card por pillar no modal "Vídeos" com score IA + reasoning + diff vs avaliação humana (quando existir)
6. **MCP tool nova** `get_application_subjective_analysis` — paralelo a `get_application_video_screenings`
7. **Calibration view** — `get_subjective_ai_vs_human_correlation` RPC (Pearson r + per-pillar agreement)
8. **Audit + retention** — usar `ai_processing_log` existente (ADR-0074 sediment) + retenção 90d/180d via mecanismo `cycle_decision_date` purge cron

### Fora de escopo

- Análise de **conteúdo audiovisual** (face/tom/sentiment) — só transcrição textual. Modelos multimodais ficam para fase posterior se houver demanda.
- Re-scoring automático se transcrição mudar — versionamento simples por `model_version + run_at`; re-run só via admin retry RPC.
- Multi-language transcription quality boost — usa o STT existente, não re-transcreve.
- Avaliação humana subjetiva por vídeo — `selection_evaluations.evaluation_type` permanece `objective` / `interview` / `leader_extra`. Subjective IA é signal paralelo, não evaluation row.

---

## 2. Schema proposto

### Tabela `video_screening_analysis` (1 row per pillar per application)

```sql
CREATE TABLE video_screening_analysis (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  application_id uuid NOT NULL REFERENCES selection_applications(id) ON DELETE CASCADE,
  pillar text NOT NULL,
  question_index integer NOT NULL,
  source_screening_id uuid NOT NULL REFERENCES pmi_video_screenings(id) ON DELETE CASCADE,

  -- Score
  score numeric CHECK (score >= 0 AND score <= 10),
  reasoning text CHECK (char_length(reasoning) <= 500),
  confidence text CHECK (confidence IN ('high','medium','low')),

  -- Model metadata
  model text NOT NULL,
  model_version text,
  prompt_hash text NOT NULL,           -- sha-256 da rubric+question payload
  transcription_hash text NOT NULL,    -- sha-256 da transcrição usada
  prompt_tokens integer,
  completion_tokens integer,
  duration_ms integer,

  -- Status + audit
  status text NOT NULL CHECK (status IN ('running','completed','failed','superseded')),
  failure_reason text,
  retry_count integer NOT NULL DEFAULT 0,
  superseded_by uuid REFERENCES video_screening_analysis(id),

  -- Timestamps
  created_at timestamptz NOT NULL DEFAULT now(),
  completed_at timestamptz,
  organization_id uuid NOT NULL,

  CONSTRAINT video_screening_analysis_uniq_active
    UNIQUE (source_screening_id, model, model_version)
);

CREATE INDEX idx_vsa_application ON video_screening_analysis(application_id);
CREATE INDEX idx_vsa_status ON video_screening_analysis(status) WHERE status IN ('running','failed');
```

**Por que tabela separada** (não colunas em `pmi_video_screenings`):

- Permite múltiplas versões do score (model A vs B vs human override) sem destruir histórico
- Permite re-scoring sem perder STT data
- RLS independente — `pmi_video_screenings` é populado pelo candidato (RPC interview-optout), análise é populada pela EF service-role
- Diff UI fica trivial (`pg_get_*` sobre `superseded_by`)

### Score 0-10 (não 1-5)

Coerente com `ai_triage_score` (ADR-0074). Cinco buckets:

| Range | Sinal |
|---|---|
| 8-10 | Forte demonstração — encaixe alto com pillar |
| 6-7.9 | Adequado — atende mas não excede |
| 4-5.9 | Marginal — gap parcial mas não bloqueante |
| 2-3.9 | Fraco — concerns concretos |
| 0-1.9 | Vazio/off-topic — vídeo não responde à pergunta |

---

## 3. EF `pmi-ai-subjective`

### Inputs

```json
{
  "screening_id": "uuid",        // single row trigger
  "triggered_by": "cron|admin_retry|api"
}
```

### Workflow

1. Lookup `pmi_video_screenings` por `screening_id`; validar:
   - `status = 'transcribed'`
   - `transcription IS NOT NULL` e ≥ 20 chars
   - `application.consent_ai_analysis_at IS NOT NULL` (reusa consent existente)
2. Inserir row `ai_processing_log` (purpose=`subjective_scoring`, status=running)
3. Inserir row `video_screening_analysis` (status=running)
4. Construir prompt:
   - **System** (cached via `cache_control: ephemeral`, ~3-5K tokens):
     - Rubric pillar-aware (definição operacional de cada pillar)
     - Score range 0-10 com buckets
     - Instruções: reasoning ≤500 chars, JSON estruturado
   - **User** (varia por screening, ~500-2K tokens):
     - Question text
     - Transcription text
     - Application context (role, chapter — opcional, ver decisão D-CTX)
5. Call Anthropic Sonnet 4.6 (ou outro — decisão D-MODEL) com `output_config.format.type='json_schema'`:
   ```json
   { "score": 7.5, "reasoning": "Candidato demonstrou X com Y, gap em Z.", "confidence": "high" }
   ```
6. Update `video_screening_analysis` (status=completed) + `ai_processing_log` (completed, tokens, duration)
7. Update `selection_applications.ai_subjective_score_avg` (computed via trigger AFTER INSERT em vsa — média dos pillars completed)

### Estimativas de custo

Assumindo Sonnet 4.6 + cache:
- System prompt 4K tokens cached: write 1× ($0.0875 × 1.25 = $0.109) + reads ($0.000875 × N)
- User prompt 1.5K tokens não cached por screening
- Output ~150 tokens
- **Por candidato (5 pillars)**: ~$0.07
- **Por ciclo (50 candidatos vídeo)**: ~$3.50

Alternativa Gemini 2.5 Flash:
- Free tier 10 RPM / 32K TPM — sustenta 1 ciclo se serializar (não burst)
- Custo $0 mas latência variável

Alternativa Haiku 4.5:
- Sem prompt cache eficaz nesse uso (rubric grande > user payload), custo similar a Sonnet mas qualidade menor em scoring fino

---

## 4. Pipeline e cron

### Trigger (escolha D-TRIGGER nas decisões)

**Opção A — Cron polling (recomendada)**:
- `pg_cron` a cada 5min
- `SELECT id FROM pmi_video_screenings WHERE status='transcribed' AND NOT EXISTS (SELECT 1 FROM video_screening_analysis WHERE source_screening_id=id AND status='completed') LIMIT 10`
- Dispara EF para cada (rate-limited a 10/run)

**Opção B — AFTER UPDATE trigger em `pmi_video_screenings`**:
- Quando `status` muda para `'transcribed'`, dispara EF via `pg_net.http_post`
- Risco: cascade pressure se STT processa em lote

**Opção C — Hybrid**:
- Cron como fallback + trigger como caminho hot

Default proposto: **A**. Trigger adiciona complexidade sem benefício de latência (vídeo já leva minutos pra STT — 5min de delay é invisível).

### Retry

- `failed` status → cron retry a cada 1h, max retry_count=3
- Admin retry RPC `admin_retry_video_screening_analysis(p_screening_id uuid)` — mesma pattern de `admin_retry_application_ai_analysis` (p87)

---

## 5. LGPD Art. 20 §1 compliance

### Princípios

1. **Score é non-binding**: nenhuma RPC de decisão consome `ai_subjective_score_avg` em fórmula automatizada. Score é signal visual.
2. **Human-in-loop forçado**: `final_score` computa de `selection_evaluations` humanas (objective + interview + leader_extra), não de IA subjective.
3. **Audit trail completo**: `ai_processing_log` registra cada call (purpose, model, prompt_hash, tokens). `video_screening_analysis` registra cada output (com `prompt_hash`/`transcription_hash` para reprodutibilidade).
4. **Consent**: reusa `consent_ai_analysis_at` existente (mesma lógica do Gemini narrative + Sonnet triage). Revoke trigger purga `video_screening_analysis` rows em 72h (analog ao `consent_ai_analysis_revoked_at` trigger atual em `selection_applications`).
5. **Retenção**: piggybacks no purge cron existente — 90d pós-decisão para não-selecionados, 180d para selecionados, via `cycle_decision_date` cron.
6. **Transparência ao titular**: candidate pode solicitar export (LGPD Art. 18 — já implementado) que incluirá `video_screening_analysis` rows. Decisão D-EXPORT — incluir reasoning na export? Default sim.

---

## 6. Frontend — alterações em `selection.astro`

### Modal "Vídeos" tab (já existe em B-light)

Para cada card de pillar (em B-light renderiza transcrição + storage links), adicionar **bloco superior**:

```
┌─────────────────────────────────────────────────┐
│ Pilar Comunicação · Q1               [status]   │
│                                                 │
│ 🤖 Score IA: 7.5/10 [high confidence]           │
│ Reasoning: Candidato demonstrou X com Y, gap... │
│ ───────                                         │
│ Transcrição (90% conf STT):                     │
│ "..."                                           │
│ [Drive ↗] [YouTube ↗]                          │
└─────────────────────────────────────────────────┘
```

Quando `video_screening_analysis` ainda não existe para o screening: badge `Aguardando análise IA — próxima fila ~5min`.

### Listagem (`pipelineBadges`)

Hoje: badge 📹 emerald se uploaded.
Após B-full: estender hint com `ai_subjective_score_avg` quando existir — `📹 Subiu 5/5 pilares · IA: 7.2/10`.

### Calibration view

Novo botão no top-bar admin/selection: **"📊 Calibration IA × humano"** → abre modal com:

| Pillar | Apps avaliadas | r (Pearson) | Diff média |
|---|---|---|---|
| Comunicação | 18 | 0.72 | -0.4 |
| Pensamento Crítico | 18 | 0.58 | +0.8 |
| ... | ... | ... | ... |

Critério "avaliada" = candidato tem score IA por pillar AND tem `selection_evaluations` humana com criterion correspondente.

---

## 7. MCP tools novas (alinhar com convenção)

1. `get_application_subjective_analysis(p_application_id uuid)` — espelha `get_application_video_screenings`, retorna scores+reasoning por pillar
2. `admin_retry_video_screening_analysis(p_screening_id uuid)` — gated `manage_member` ou similar
3. `get_subjective_calibration_stats(p_cycle_id uuid DEFAULT NULL)` — Pearson + per-pillar diff
4. (Opcional) `get_subjective_outliers(p_cycle_id uuid)` — candidatos com maior gap IA × humano (>2 σ) para curadoria

---

## 8. Decisões pendentes para PM (council irá pesar)

| ID | Decisão | Opções | Recomendação |
|---|---|---|---|
| D-MODEL | Qual modelo para subjective? | A) Sonnet 4.6 + cache · B) Haiku 4.5 · C) Gemini 2.5 Flash · D) Multi-model A/B | **A** (consistência com triage ADR-0074 + qualidade scoring fino) |
| D-CTX | Incluir role/chapter context no user prompt? | A) Não — só question+transcription · B) Sim — agrega role/chapter | **A** (evita bias por contexto não-meritocrático) |
| D-TRIGGER | Pipeline trigger? | A) Cron polling · B) Trigger AFTER UPDATE · C) Hybrid | **A** (simpler, latency-acceptable) |
| D-NON-BIND | Score entra em fórmula `final_score`? | A) Nunca (signal apenas) · B) Como tiebreaker · C) Weighted ranking | **A** (LGPD Art. 20 §1 strict) |
| D-EXPORT | Incluir reasoning em LGPD export? | A) Sim · B) Sim com flag opt-out · C) Não | **A** (full transparência) |
| D-RUBRIC | Rubric pillar é codificada onde? | A) Hardcoded no system prompt da EF · B) Tabela `pillar_rubrics` versionada · C) GovDoc com versionamento | **B** (permite tweaks sem deploy) |
| D-RETRY-CAP | Max retries antes de marcar `failed` permanente? | A) 3 · B) 5 · C) Infinito com cooldown | **A** |
| D-LATENCY-SLA | SLA p95 análise? | A) 5min · B) 15min · C) 1h | **A** (UX promete "próxima fila ~5min") |
| D-SUPERSEDE | Comportamento quando re-rodar? | A) Insert + mark prior superseded · B) UPDATE in-place · C) Append apenas | **A** (audit trail) |

---

## 9. Migrações esperadas

1. `<timestamp>_b_full_video_screening_analysis_table.sql` — tabela + indexes + RLS rpc-only + trigger LGPD purge
2. `<timestamp>_b_full_subjective_score_avg_column.sql` — `selection_applications.ai_subjective_score_avg numeric` + trigger sync
3. `<timestamp>_b_full_pillar_rubrics_table.sql` — tabela `pillar_rubrics` (se D-RUBRIC=B)
4. `<timestamp>_b_full_subjective_rpcs.sql` — `get_application_subjective_analysis`, `admin_retry_video_screening_analysis`, `get_subjective_calibration_stats`
5. `<timestamp>_b_full_cron_schedule.sql` — `pg_cron` job 5min + retry hourly

EF deploy:
- `supabase/functions/pmi-ai-subjective/index.ts` (~300L)

MCP deploy:
- 3-4 new tools em `nucleo-mcp/index.ts`

Frontend:
- `selection.astro` modal Vídeos card update
- `selection.astro` new calibration view button + modal
- i18n 3 dicts (~15 novas keys)

ADR-0079 ACCEPTED é precondição para qualquer migration aplicar em prod.

---

## 10. Riscos e mitigações

| # | Risco | Mitigação |
|---|---|---|
| R1 | Bias do modelo em PT-BR sobre experiência regional | D-CTX=A (omite chapter/role) + calibration view monitora correlação por chapter; outliers flagged |
| R2 | STT transcription poor quality polui score | EF valida `transcription_confidence >= 0.6` antes de rodar; abaixo disso, status='failed' com reason=`low_transcription_confidence` |
| R3 | Custo cresce com volume | Batching: cron processa 10/5min = 120/h; cap orçamento via env var; alerta se > $5/dia |
| R4 | LGPD Art. 20 §1 violação se score migrar pra fórmula | Invariante adicional: `final_score` computed function NÃO referencia `ai_subjective_score_avg` (auditável via `pg_get_functiondef`); contract test no CI |
| R5 | Calibration view com sample size baixo (n<20) leva PM a conclusões falsas | UI mostra n + warning se n<20; correlação não calcula se n<10 |
| R6 | Re-scoring quando rubric muda invalida histórico | Versionamento `model_version` + `prompt_hash` permite re-run isolado + diff UI |
| R7 | Race condition entre cron + admin retry | UNIQUE constraint `(source_screening_id, model, model_version) WHERE status != 'superseded'` |

---

## 11. Open questions para council

Brief pro council deve solicitar pesar especificamente:

- **data-architect**: validar schema `video_screening_analysis` (indexes? FK ON DELETE CASCADE certo? `superseded_by` self-ref OK?). Validar trigger `ai_subjective_score_avg` (cascade pressure se 50 candidatos × 5 pillars completam simultaneamente?).
- **ai-engineer**: validar D-MODEL/D-CTX/D-TRIGGER. Pesar prompt caching ROI nesse uso. Sugerir output_schema canonical pra Sonnet 4.6. Conferir Haiku 4.5 fitness pra esse score qualitativo numérico.
- **security-engineer**: validar consent reuse (`consent_ai_analysis_at` cobre subjective?). Validar LGPD Art. 20 §1 strict — score non-binding suficiente ou precisa mais? Validar export Art. 18 incluir reasoning. RLS analysis tabela ok como rpc-only?
- **legal-counsel**: validar que `transcription_hash` + `prompt_hash` em audit + retenção 90/180d cobrem Art. 37. Validar LGPD Art. 7º base legal (consent vs legitimate interest?) para subjective scoring de candidato. Validar revoke trigger 72h é o correto vs 24h.

---

## 12. Trabalho remanescente após esta spec — REVISADO p151

1. ✅ **p150**: spec drafted + ADR-0079 PROPOSED.
2. ✅ **p151**: council 4-lens (data-architect + ai-engineer + security-engineer + legal-counsel) em paralelo + synthesis em `docs/council/decisions/2026-05-12-p151-subjective-scoring-synthesis.md`. Output: 10 decisões consolidadas + 11 blockers identificados.
3. ✅ **p152 (esta sessão)**: amendments documentais — spec + ADR-0079 atualizados refletindo decisões + checklist. Status spec → DRAFT · POST-COUNCIL. Status ADR → PROPOSED · AWAITING-RATIFICATION.
4. ⏳ **p153**: Material change Termo de Adesão v2.7→v2.8 (#9 do gate) — draft + workflow ratificação curadores (Sarah + Fabricio + Roberto + Ângelina + Ivan DPO).
5. ⏳ **p154**: DPA Anthropic confirmação (#11). Após confirmação + Termo v2.8 ratificado + ADR ACCEPTED, migrations M0 (consent column dedicada) + M1 (video_screening_analysis) + M2 (trigger sync) + M3 (pillar_rubrics) + M4 (RPCs) + M5 (cron) podem ser aplicadas.
6. ⏳ **p155+**: EF `pmi-ai-subjective` + frontend (banner UI + consent gate + calibration view + notificações) + MCP tools + QA + dry-run Cycle 4 ([REDACTED-332-NAME] com re-disclosure individual).

Total revisado: 5-6 sessões a partir desta. Cronograma sensível a velocidade ratificação humana (curadores + DPO).

---

## 12.1 Amendments aplicados p151b/p152 (council-derived)

Estas mudanças refletem as 10 decisões consolidadas e 11 blockers. Onde a spec original tem texto incompatível com a decisão consolidada, este addendum prevalece até o próximo full-rewrite. Detalhe em `docs/council/decisions/2026-05-12-p151-subjective-scoring-synthesis.md`.

### §2 Schema — overrides

- §2.1 `video_screening_analysis`: substituir `UNIQUE (source_screening_id, model, model_version) WHERE status != 'superseded'` por **partial unique index nomeado** `idx_vsa_uniq_active ON video_screening_analysis (source_screening_id, model, model_version) WHERE status NOT IN ('superseded','failed')`. (Blocker #1)
- §2.1: adicionar coluna `superseded_by uuid REFERENCES video_screening_analysis(id) ON DELETE SET NULL`. (Blocker #2)
- §2.1: adicionar `reasoning_truncated boolean DEFAULT false` em vez de hard `CHECK length(reasoning) <= 500` (truncate em EF + marca coluna).
- §2.1: `failure_reason` como ENUM/CHECK em `('low_transcription_confidence','transcription_too_short','model_timeout','invalid_json_output','consent_revoked','rubric_load_error')` (texto livre = risco PII).
- §2.1: introduzir status `failed_permanent` separado de `failed` + `CHECK (retry_count <= 3)`. (D-RETRY-CAP)
- §2.1: índices adicionais `idx_vsa_source_completed ON video_screening_analysis(source_screening_id) WHERE status='completed'` + adicionar `'transcribed'` ao `idx_video_screenings_status_pending`.
- §2.2 trigger derivado: renomear para `_trg_subjective_score_avg_sync` + adicionar invariant `P_subjective_score_avg_consistency` (ADR-0012 Principle 2). (Blocker #4)
- §2.3 `pillar_rubrics`: adicionar `organization_id NOT NULL DEFAULT auth_org()` + RLS + `is_active boolean DEFAULT true` + `prompt_hash text NOT NULL` + ordenação determinística no SELECT.

### §3 EF — overrides

- §3 step 1: validar `consent_subjective_video_scoring_at IS NOT NULL AND consent_subjective_video_scoring_revoked_at IS NULL` (NÃO reutilizar `consent_ai_analysis_*`). (Blocker #6 + D-CONSENT)
- §3 JSON schema output: `score: { type: "number" }` (NÃO integer) + `additionalProperties: false`; validação min/max via código pós-parse (per `feedback_anthropic_structured_output_schema_limits.md`). (Blocker #5)
- §3 STT threshold: elevar para `>= 0.65`; faixa `0.50-0.64` força `confidence='low'`.
- §3 system prompt cacheado: incluir instrução anti-bias PT-BR explícita: "avalie conteúdo semântico, não penalize vocabulário regional/informalidade".
- §3 preprocessing: truncar transcrição a ~2000 tokens no final de frase + sanitizar timestamps STT.
- §3 rubric loading: ler `pillar_rubrics` per-invocation (não cached at EF boot) com ordenação determinística.

### §4 Pipeline — overrides

- §4.2 cron: triggered por `pmi_video_screenings.status IN ('transcribed')` (não `'completed'` antigo). Cobertura via novo índice.
- §4.3 revoke handler: `handle_consent_revocation()` AGORA deve incluir `DELETE FROM video_screening_analysis WHERE application_id = NEW.id` (atualmente faltando = LGPD gap concreto). (Blocker #3) Execução **imediata** mesma transaction + fallback cron 72h.

### §5 LGPD — overrides

- §5 D-CONSENT: substituir reuse de `consent_ai_analysis_at` por **consent dedicado** `consent_subjective_video_scoring_at` + `consent_subjective_video_scoring_revoked_at` em `selection_applications`. (Blocker #8 + D-CONSENT)
- §5: adicionar tela de consent dedicada no fluxo de upload de vídeos (frontend `interview_optout.astro` ou equivalente).
- §5 export: confirmar shape de `ai_processing_log` armazena somente hashes (não conteúdo); incluir `screening_id` FK referencing `pmi_video_screenings`.
- §5: notificação ao candidato pós-scoring via Resend: "Seus vídeos foram analisados por IA. Direito de acesso e revisão." (Art. 9 + Art. 20 transparência).
- §5: SLA comunicado ao titular: "até 5 dias úteis" (mesmo que execução técnica seja imediata).
- §5: verificar purge cron `cycle_decision_date` — DELETE em `selection_applications` (CASCADE propaga) vs UPDATE/anonymize (CASCADE não dispara — Risk 2 ADR-0076).

### §6 Frontend — overrides

- §6 modal Vídeos: banner UI obrigatório `<aside>` não-dismissable: "Score gerado por IA — sinal de apoio. Decisão final é exclusivamente do Comitê de Curadoria." (Blocker #10)
- §6 calibration view: per-pillar table com **n + α (Krippendorff) + MAE + viés sistemático**; warnings se n<20; null para n<5 por pillar.
- §6 calibration: lazy show score — revelar score IA SOMENTE depois de avaliação humana submetida para o pillar (Cycle 5+ feature; Cycle 4 mantém visível por volume baixo).

### §7 Calibration RPC — overrides

- §7 `get_subjective_calibration_stats`: retornar **Krippendorff α + MAE + viés sistemático** além de Pearson r. (Blocker #7)

### §8 Material change Termo Adesão v2.7→v2.8 (Blocker #9 — novo)

Conteúdo obrigatório da v2.8:
- (a) divulgação de análise IA sobre conteúdo de vídeo com scoring por pillar;
- (b) disclosure de processamento por terceiro (Anthropic como operador LGPD);
- (c) direitos do titular: acesso, revogação, revisão, explicação;
- (d) finalidade específica (não generaliza com `consent_ai_analysis_at`);
- (e) retenção alinhada com `cycle_decision_date` purge (90d/180d).

Workflow ratificação:
1. PM redige draft v2.8 (p153)
2. Curador-jurídico Ângelina valida texto LGPD
3. DPO Ivan ratifica
4. Workflow approval_chains via `recirculate_governance_doc` para 7 curadores
5. Quando aprovada, signature deadline para candidatos opted-in cycles ativos
6. Sem candidato signatário do v2.8 → EF subjective scoring não roda para esse candidato

### §11 DPA Anthropic verification (Blocker #11)

Antes de qualquer deploy production-grade:
- [ ] Localizar DPA Anthropic vigente
- [ ] Confirmar cobertura para "transcrição de vídeo enviado por candidato" como input ao modelo
- [ ] Se gap: solicitar adendo DPA antes de deploy
- [ ] Registrar evidência em `docs/legal/` ou equivalente

---

## 13. Cross-refs

- ADR-0074 (Onda 3 dual-model AI) — define padrão de pipeline IA seleção
- ADR-0076 (PMI 3-d volunteer model) — base legal LGPD
- ADR-0077 (auth_org caller-derived) — RLS scope
- `feedback_anthropic_structured_output_schema_limits.md` (p108) — limitações JSON schema do Anthropic SDK (sem min/max em integer)
- Migration `20260516200000_phase_b_pmi_journey_v4.sql` — pmi_video_screenings origem
- `ARM_PILLARS_AUDIT_P107.md` — ARM-11 (AI Layer cross-cutting)
