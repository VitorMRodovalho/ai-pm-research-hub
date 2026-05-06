# ADR-0074: ARM Onda 3 — Dual-Model AI Architecture (Sonnet 4.6 triage + Haiku 4.5 briefing + Gemini qualitative legacy)

**Status**: Accepted
**Date**: 2026-05-06
**Decider**: PM Vitor Maia Rodovalho (GP Núcleo IA & GP)
**Trigger**: ARM Onda 3 AI Build (plano ABCD bloco C, decisão `analyze_application` confirmada)

---

## Context

A plataforma já tem pipeline IA ativo via `pmi-ai-analyze` EF (Gemini 2.5 Flash) que produz análise qualitativa estruturada (`raises_the_bar`, `summary`, `key_strengths`, `areas_to_probe`, `fit_for_role.score 1-5`). Pipeline tem:

- Consent gate dedicado (`consent_ai_analysis_at` + revoke trigger LGPD 72h)
- Observability via `ai_analysis_runs` (per-run audit + retry + diff UI)
- Cron retry hourly + admin retry manual
- Retenção LGPD 90/180d pós-decisão via `cycle_decision_date`
- RLS comitê do ciclo

`ARM_PILLARS_AUDIT_P107.md` Onda 3 propôs 3 capabilities AI:

1. **`analyze_application` LLM scoring** — pre-screen para reduzir pool de avaliação (ARM-3 Triage). PM gate: go/no-go LGPD + budget + escolha modelo.
2. **`get_evaluator_calibration_stats`** — métricas estatísticas (já entregue p107 P1).
3. **`generate_interview_briefing`** — gera 3 perguntas personalizadas + áreas de atenção (ARM-5 Interview, MCP tool).

Decisão PM (2026-05-06):

- **Decisão 1 (go/no-go)**: GO. Pre-screen scoring é alto valor para reduzir burden em comitê (em ciclos com 80+ apps, triagem manual gera fadiga e calibração inconsistente).
- **Decisão 2 (modelo)**: B = Claude Sonnet 4.6 + prompt cache rubrica (custo ~$0.10/ciclo, mais consistente para qualitativo) — confirmado em handoff p108.
- **Decisão 3 (LGPD)**: Art. 20 §1 honored — score é non-binding, decisão humana é a fonte autoritária. Retenção via mecanismo existente (consent gate + cycle_decision_date purge cron).
- **Decisão 4 (briefing model)**: Haiku 4.5 — query baixa freq (1 por candidato no estágio entrevista), latência baixa preferível, sem necessidade de cache.

Resultado: arquitetura **dual-model** (3 propósitos, 3 modelos):

| Purpose | Model | Why |
|---------|-------|-----|
| Qualitative narrative (legacy) | Gemini 2.5 Flash | Free tier, já em produção, schema estruturado complexo. Mantém-se. |
| Triage scoring (NEW) | Claude Sonnet 4.6 + prompt cache | Mais consistente em scoring qualitativo numérico, cache rubric (~5K tokens) reduz custo amortizado. |
| Interview briefing (NEW) | Claude Haiku 4.5 | Latência baixa, custo trivial, usado uma vez no estágio entrevista. |

## Decision

### Schema (Foundation)

Migration `20260516930000_arm3_arm5_onda3_ai_processing_log_and_triage_columns.sql`:

1. **Tabela `ai_processing_log`** (LGPD Art. 37 audit): registra cada AI call com model/purpose/prompt_hash/tokens/duration. **NUNCA conteúdo** — só hashes SHA-256 e metadata. RLS rpc-only via `list_ai_processing_log` admin RPC.
2. **`selection_applications` ALTER**:
   - `ai_triage_score numeric` (CHECK 0-10)
   - `ai_triage_reasoning text` (curto, ≤500 chars)
   - `ai_triage_confidence text` (CHECK high|medium|low)
   - `ai_triage_at timestamptz`
   - `ai_triage_model text`
3. **RPC `list_ai_processing_log`** com filtros (application_id, purpose, status, limit) e auth `view_internal_analytics`.

Score range 0-10 (não 1-5 como Gemini's `fit_for_role.score`) para granularidade — cinco buckets (0-2, 2-4, ..., 8-10) cobrem sinais negativos a positivos com precisão suficiente.

### EF `pmi-ai-triage` (Sonnet 4.6 + prompt cache)

Novo Edge Function. Workflow:

1. Recebe `{ application_id, triggered_by? }` (POST, service-role auth)
2. Valida consent (`consent_ai_analysis_at` NOT NULL + `consent_ai_analysis_revoked_at` IS NULL)
3. Insere row em `ai_processing_log` (status=running)
4. Constrói prompt: **system** (rubric, ~5K tokens, **cached via cache_control**) + **user** (candidate data, varia por candidato)
5. Chama Anthropic Sonnet 4.6 com `cache_control: {type: "ephemeral"}` na system prompt
6. Parseia JSON estruturado: `{score: 0-10, reasoning: text, confidence: high|medium|low}`
7. Atualiza `selection_applications.ai_triage_*`
8. Atualiza `ai_processing_log` (status=completed + token usage incluindo cache_read_tokens)

Modelo: `claude-sonnet-4-6`. `output_config: {format: {type: "json_schema", schema: TRIAGE_SCHEMA}}` para garantir output válido. Sem `thinking` (triage é categorização, não reasoning multi-step).

**Prompt caching strategy**: rubric inteira no system prompt → cache hit ratio ~95% após primeiro candidato do ciclo. Custo amortizado por ciclo: cache write 1x ($0.0875 input × 1.25) + N reads (~$0.00875 cada). Para ciclo de 80 candidatos: ~$0.79 total (vs $7.05 sem cache).

### MCP tool `generate_interview_briefing` (Haiku 4.5)

Nova tool em `nucleo-mcp/index.ts`. Workflow:

1. Recebe `application_id` (Zod schema)
2. canV4 gate: `view_pii` action (briefing pode incluir áreas sensíveis sobre o candidato)
3. Busca application data + `ai_analysis_snapshot` (do Gemini run)
4. Insere row `ai_processing_log` (purpose='briefing')
5. Chama Anthropic Haiku 4.5 inline com payload curto (sem cache)
6. Parseia 3 perguntas + áreas de atenção
7. Atualiza `ai_processing_log` (completed + tokens)
8. Retorna estrutura formatada para o entrevistador

Modelo: `claude-haiku-4-5`. `output_config.format` JSON schema. Sem `thinking`. Latência alvo: <3s.

Não persiste em `selection_applications` — é gerado on-demand quando o entrevistador clica "Briefing" no painel.

### LGPD Art. 20 §1 compliance (decisão automatizada)

Art. 20 §1 LGPD: **decisões tomadas unicamente com base em tratamento automatizado de dados pessoais que afetem interesses do titular podem ser revistas.** Garantias arquiteturais:

1. **`ai_triage_score` é NON-BINDING**: nenhuma RPC de decisão (`update_application_decision`, `compute_application_scores`) consome `ai_triage_score`. Score serve só como signal para priorização visual.
2. **Human-in-loop forçado por design**: workflow de seleção exige ≥2 evaluations objetivas + interview score (calculados por humanos via `selection_evaluations`). `final_score` é computed de evaluations humanas, não de `ai_triage_score`.
3. **Audit trail completo**: `ai_processing_log` registra cada call (mesmo que conteúdo não seja persistido) — comprova ao titular que processamento ocorreu, com qual modelo, quando, por quem (caller_member_id).
4. **Briefing é assistivo, não autoritativo**: as 3 perguntas geradas são sugestões para o entrevistador adaptar; não substituem a entrevista nem entram em scoring.

### Não-conflitos com pipeline existente

- `pmi-ai-analyze` (Gemini, qualitative narrative) **continua intocado**. Existing consent gate `consent_ai_analysis_at` cobre TODOS os AI processings (incluindo triage e briefing) — novo consent não é necessário pois é o mesmo escopo de "uso de IA para análise da aplicação".
- `ai_analysis_runs` (Gemini operational tracker) coexiste com `ai_processing_log` (cross-purpose LGPD audit). Triage e briefing escrevem só em `ai_processing_log`. Gemini qualitative escreve em ambos no futuro (additive change, defer até necessário).
- `revoke_consent_via_token` purga `linkedin_relevant_posts/cv_extracted_text/ai_pm_focus_tags/ai_analysis` em 72h — **deve ser estendido para purgar `ai_triage_*` também**. Será atualizado em migration follow-up.

### Anthropic SDK em Deno

Usar `npm:@anthropic-ai/sdk@^0.43` (latest stable que suporta Sonnet 4.6 + prompt cache). Import:

```typescript
import Anthropic from "npm:@anthropic-ai/sdk@0.43.0";
```

Pin versão exata (não `^`) para reproducibilidade — pattern já adotado para Zod no MCP server (ver `.claude/rules/mcp.md`).

`ANTHROPIC_API_KEY` Supabase secret (PM action — não está set ainda).

## Implementation

| Component | File | Status |
|-----------|------|--------|
| Schema migration | `supabase/migrations/20260516930000_arm3_arm5_onda3_ai_processing_log_and_triage_columns.sql` | Applied |
| EF pmi-ai-triage | `supabase/functions/pmi-ai-triage/index.ts` | Building |
| MCP tool generate_interview_briefing | `supabase/functions/nucleo-mcp/index.ts` | Building |
| ADR | `docs/adr/ADR-0074-onda3-arm-dual-model-ai-architecture.md` | This doc |

## Consequences

### Positive

- ARM-3 Triage maturidade 2 → 3 (pre-screen scoring funcional + LGPD compliant + observable)
- ARM-5 Interview maturidade 1 → 2 parcial (briefing assistivo, agendamento via #92/#116 ainda pending)
- ARM-11 AI Layer maturidade 2 → 3 (dual-model + cross-purpose audit + LGPD-grade observability)
- Comitê reduz burden em ~30-40% (priorização por triage_score concentra esforço em apps high-confidence)
- LGPD Art. 37 audit trail genérico (ai_processing_log) substrato para futuros AI integrations
- Prompt cache reduz custo Sonnet 4.6 em ~88% por ciclo (rubric reuse)

### Negative

- Custo operacional: ~$1-2/ciclo (vs $0 do Gemini free tier — Gemini permanece para qualitative)
- Dependência adicional Anthropic API (single point of failure adicional, mitigado por fallback strategy: pmi-ai-analyze Gemini permanece se Anthropic indisponível)
- Complexidade arquitetural: 3 modelos × 3 purposes (vs 1 modelo × 1 purpose antes). Pattern documentado em ADR-0074 facilita future additions, mas onboarding é mais demorado.
- ANTHROPIC_API_KEY se torna secret crítico (pre-existing risk de leak parcialmente mitigado por scope: triage + briefing only, sem write capabilities além de log)

### Pendentes (follow-up sessions)

1. **PM action**: set `ANTHROPIC_API_KEY` Supabase secret (`supabase secrets set ANTHROPIC_API_KEY=...`)
2. **Cron `auto-triage-on-consent`**: trigger automático quando `consent_ai_analysis_at` é populado (defer até PM ratificar UX inline AI Onda 4)
3. **`revoke_consent_via_token` extension**: purgar `ai_triage_*` columns junto com `ai_analysis` no revoke trigger
4. **Frontend admin/selection inline AI panel**: tab "Análises IA" deprecated em favor de inline panel mostrando triage_score + reasoning + confidence + Gemini qualitative + briefing button (Onda 4 browser session)
5. **Calibration delta**: cron weekly comparando `ai_triage_score` vs `final_score` humano para detectar drift e flag manual recalibration (Onda 5)

## References

- ADR-0011: V4 authority gate (`can_by_member`)
- ADR-0012: schema invariants (não impactado)
- ADR-0059 W1: existing Gemini AI analysis pipeline
- ADR-0071: member lifecycle state machine (paralelo, mesma sessão)
- ADR-0072: ARM-1 lead capture funnel (paralelo, mesma sessão)
- ADR-0073: issue #116 calendar booking sync (paralelo, mesma sessão)
- LGPD Art. 20 §1 (revisão de decisão automatizada)
- LGPD Art. 37 (registros de tratamento)
- `docs/strategy/ARM_PILLARS_AUDIT_P107.md` — Onda 3 spec
- Anthropic SDK docs (prompt caching): https://platform.claude.com/docs/en/build-with-claude/prompt-caching.md
