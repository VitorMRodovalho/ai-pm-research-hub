# Council review p151 — ai-engineer lens — ADR-0079

## TL;DR

D-MODEL deve ser Sonnet 4.6 com cache — Haiku 4.5 under-shoots para scoring qualitativo numérico fino e Gemini Free Tier serializado em 250 calls/ciclo enfrenta 429 altamente provável. D-RUBRIC deve ser opção B (tabela versionada) com estratégia de cache correta que preserva hit ratio alto. O ADR está OK com ajustes: JSON schema precisa correção imediata (score como `number` não `integer`), D-CTX recomendação padrão da spec é correta mas merece formalização mais rigorosa, e calibration precisa Krippendorff alpha além de Pearson.

---

## Recomendação D-MODEL (justificada)

**Recomendação: Sonnet 4.6 + prompt cache (opção A). Sem A/B multi-model neste ciclo.**

**Sonnet 4.6** tem o fitness mais alto. O scoring subjetivo de transcrição de vídeo exige: (a) interpretar nuances semânticas onde candidatos respondem parcialmente; (b) ancorar score em rubrica multi-dimensão; (c) produzir reasoning ≤500 chars defensável (exportado ao titular via Art. 18). Sonnet 4.6 tem capacidade de raciocínio contextual suficiente. ADR-0074 já validou para triage (mesmo output structure com input mais longo).

**Haiku 4.5 — não recomendado.** Para scoring de 0-10 com reasoning exportável, consistência inter-run e acuidade semântica de Haiku 4.5 são insuficientes. Modelos menores têm tendência a clustering no centro da escala, reasoning genérico, baixa sensibilidade entre 4.5 e 6.5.

**Gemini 2.5 Flash (Free Tier) — inviável para produção.** Sediment `feedback_gemini_free_tier_limits.md`: 10 RPM / 32K TPM. 250 calls/ciclo × ~7K tokens = 1.75M tokens. Qualquer burst (retry, admin re-run) satura. Gemini Free Tier não é SLA para produção e Pattern 43 já está saturando.

**Multi-model A/B (opção D) — over-engineering.** Cycle 4 tem 1 candidato (Eduardo Luz) com 5 vídeos. N=5 não geram dados estatísticos para comparar modelos. Sonnet 4.6 como baseline → reconsiderar A/B em cycle 5+ se custo escalar ($14/ano não é concern).

**Cache hit ratio:** ~95%, idêntico ao calculado em ADR-0074. System prompt cached via `ephemeral` TTL 5min. Cron 5min processando lote de 10 mantém cache quente. Para garantir: processar no mesmo loop EF, não disparar 10 paralelas. Custo $3.50/ciclo válido.

---

## JSON schema canonical proposto para output_config.format

Aplicando sediment `feedback_anthropic_structured_output_schema_limits.md`: sem `minimum`/`maximum`/`minLength`/`maxLength`. Campo `score` deve ser `number` (não `integer`).

```json
{
  "type": "object",
  "properties": {
    "score": {
      "type": "number",
      "description": "Score 0.0-10.0 representing pillar fit. Use one decimal place."
    },
    "reasoning": {
      "type": "string",
      "description": "Max 500 characters. Reference specific evidence from the transcript."
    },
    "confidence": {
      "type": "string",
      "enum": ["high", "medium", "low"],
      "description": "high=transcript clearly addresses rubric; medium=partial/ambiguous; low=transcript is thin or off-topic."
    }
  },
  "required": ["score", "reasoning", "confidence"],
  "additionalProperties": false
}
```

Validação pós-parse obrigatória:
```typescript
if (parsed.score < 0 || parsed.score > 10) throw new Error(`invalid score: ${parsed.score}`);
if (parsed.reasoning.length > 500) parsed.reasoning = parsed.reasoning.slice(0, 497) + '...';
if (!['high','medium','low'].includes(parsed.confidence)) throw new Error(`invalid confidence: ${parsed.confidence}`);
```

Truncate silencioso preferível a throw — score válido mesmo com reasoning excedente. Logar truncamento em `ai_processing_log.error_message` como warning não-fatal.

**Nota:** spec §2 define coluna como `score numeric CHECK (score >= 0 AND score <= 10)` — correto para decimais. Coerente com `ai_triage_score numeric` da ADR-0074.

---

## Recomendação D-CTX + D-RUBRIC (justificadas)

**D-CTX: opção A (não incluir role/chapter) — correta, mas por razão mais forte:**

A razão MAIS forte é: o pillar system já abstrai contexto. Perguntas de vídeo são por pillar (Comunicação, Pensamento Crítico, etc.). Incluir `role=leader` cria meta-rubric implícito ("leaders devem mostrar X") que pode elevar sistematicamente scores para roles de liderança sem evidência real. Em calibration posterior, viés por role muito difícil de separar do efeito legítimo.

Se ciclos futuros precisarem context, abordagem correta é rubrics pillar-específicas por role-type na tabela `pillar_rubrics` (D-RUBRIC=B), não context livre no user prompt.

**D-RUBRIC: opção B (tabela versionada), com caveat sobre cache strategy:**

Tradeoff real: A (hardcoded) maximiza cache hit porque system prompt bit-a-bit idêntico. B (tabela) introduz variabilidade: sha256 varia com whitespace/ordering → zera cache.

Solução: B é fonte da verdade, mas com cache key explícita. EF computa `sha256(rubric_content)` e usa como `model_version` em `video_screening_analysis`. System prompt deterministic (rubric ordenada por `pillar_id ASC`, sem variáveis temporais). Cache permanece quente dentro de ciclo enquanto rubric não muda.

Opção C (GovDoc) seria ideal para governance, mas overhead não compensa. Opção B com versionamento de linha suficiente.

---

## Ajustes ao prompt engineering / cache strategy

**System prompt (cacheado):**

1. Declaração propósito (2-3 linhas)
2. Rubrica por pillar (interpolada da tabela, ordenada deterministicamente)
3. Score buckets (5 buckets da spec §2 bem definidos)
4. Instruções output: JSON, reasoning ≤500 chars com evidência, **sem julgamento sobre sotaque ou fluência verbal** (R1 PT-BR)
5. Instrução confidence: definir high/medium/low em função da qualidade da TRANSCRIÇÃO, não da resposta

**User prompt (por screening, não cached):**
```
Pillar: {pillar_name}
Pergunta avaliada: {question_text}

Transcrição (confiança STT: {transcription_confidence:.0%}):
{transcription_text}
```

**Preprocessing:**
- Truncar transcrição a ~2000 tokens se exceder. Truncar no final de frase, logar truncamento.
- Sanitizar: remover timestamps STT `[00:01:23]` (ruído).
- Sem tradução: avaliar na língua que candidato respondeu.

**R1 mitigação (bias PT-BR):** Sonnet 4.6 multilingual adequado. Mitigação no system prompt: *"Avalie o conteúdo semântico. Não penalize vocabulário regional, informalidade verbal ou construções típicas do português brasileiro. A coerência argumentativa é o critério, não a formalidade."* Esta instrução vai no system cacheado (universal).

---

## Calibration metrics recomendadas (além de Pearson)

Pearson r assume escala contínua + distribuição normal. Scores 0-10 humanos tendem a distribuição assimétrica (clustering 6-8). Pearson penaliza sobre-indexação e pode reportar r=0.7 falso-positivo.

**Métricas adicionais:**

1. **Krippendorff alpha** — métrica para inter-rater agreement em escala ordinal com >2 raters (IA + múltiplos humanos). α > 0.80 confiável, 0.67-0.80 tentativo, < 0.67 não confiável.

2. **MAE (Mean Absolute Error) por pillar** — operacionalmente interpretável. "Modelo erra em média 1.2 pontos em Comunicação" é acionável.

3. **Distribuição de diferença (IA score - human score)** — histograma por pillar revela viés sistemático over/under-score. Modelo MAE=1.5 com diff média=+1.5 (sempre acima) ≠ MAE=1.5 com diff média=0 (ruído equilibrado).

4. **Score concordance rate por bucket** — % casos onde IA e humano caem no mesmo bucket (0-2, 2-4, ..., 8-10). Mais robusto para decisões binárias.

**Thresholds operacionais propostos:**

| Métrica | Confiável | Atenção | Retreino |
|---|---|---|---|
| Krippendorff α | ≥ 0.75 | 0.60-0.74 | < 0.60 |
| MAE por pillar | ≤ 1.0 | 1.0-1.8 | > 1.8 |
| Viés sistemático (mean diff) | ≤ ±0.5 | ±0.5-1.0 | > ±1.0 |

**Thresholds n:**
- n < 10 não calcula correlação (correto na spec)
- n < 20 warning (correto)
- n < 5 por pillar não calcula per-pillar — RPC retorna `null` + indicar `insufficient_data`. UI não deve mostrar r=0 como dado real.

**R2 (STT confidence):** threshold `>= 0.6` está conservador pelo lado errado. STT 0.6 pode ter 30-40% palavras incorretas — distorce scoring. Recomendo elevar para **0.65** como mínimo; faixa intermediária **0.50-0.64** → processar mas force `confidence='low'` no output. Abaixo 0.50 → falhar com `low_transcription_confidence`.

---

## ADR readiness — verdict

**OK com ajustes (não BLOCK, não READY imediato)**

Três ajustes obrigatórios antes ACCEPTED:

1. **JSON schema corrigido (load-bearing)**: `score: { type: "number" }` (não integer) + `additionalProperties: false` + validação pós-parse documentada. Sem isso, EF 400 na primeira call.

2. **D-RUBRIC=B com cache strategy explicitada**: ADR registra que EF constrói system prompt deterministicamente da tabela + `prompt_hash` = sha256 do system prompt completo (não só da rubric) — reprodutibilidade auditável Art. 37.

3. **Calibration view adiciona Krippendorff α + MAE + viés sistemático**: RPC `get_subjective_calibration_stats` retorna essas além de Pearson r. Spec §6 só menciona Pearson + diff — formalizar antes de implementar.

Dois ajustes recomendados (backlog implementação):

4. Threshold STT elevado para 0.65 (com faixa 0.50-0.64 → force confidence=low).
5. System prompt inclui instrução explícita anti-bias PT-BR.

Arquitetura geral sólida. Não há impedimento técnico após os 3 ajustes obrigatórios.

---

**Arquivos lidos:** spec, ADR-0079, ADR-0074, migration `20260516930000_arm3_arm5_onda3_ai_processing_log_and_triage_columns.sql`, `feedback_anthropic_structured_output_schema_limits.md`.
