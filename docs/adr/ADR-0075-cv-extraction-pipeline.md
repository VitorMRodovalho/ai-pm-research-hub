# ADR-0075: CV Extraction Pipeline — Deno + unpdf + cron-driven backfill

**Status**: Proposed
**Date**: 2026-05-07
**Decider**: PM Vitor Maia Rodovalho (GP Núcleo IA & GP)
**Trigger**: p116 backfill manual revelou que `cv_extracted_text` esteve vazio para todos candidatos por ~23 dias após ADR-0059 W1 ter shipado a coluna. Auditoria pós-p116 mostrou 55 selection_applications dos últimos 90 dias com `resume_url IS NOT NULL AND cv_extracted_text IS NULL` — gap operacional sem pipeline de captação.

---

## Context

ADR-0059 W1 (migration `20260514300000`, 2026-04-14) shipou a coluna `cv_extracted_text` em `selection_applications`, com infra LGPD completa:
- Trigger `_trg_purge_ai_analysis_on_consent_revocation` (purge 72h SLA on consent revoke)
- Estendido em `20260516940000` para purgar também `ai_triage_*`
- Comentário documental define retenção: 90d pós `cycle_decision_date` para não-selecionados, 180d para selecionados

ADR-0074 (p108 Onda 3) shipou `pmi-ai-triage` que, após p116 (commit `b1da718`), lê `cv_extracted_text` no prompt enviado ao Sonnet 4.6.

Mas o **pipeline que preenche essa coluna nunca foi implementado**. Em p116, fizemos backfill manual de 16 candidatos do cycle3-2026-b2 via script Python local (`/tmp/extract_cv.py`, não-commitado, one-shot) usando pypdf + URLs frescas de SAS extraídas de um JSON do worker `pmi-vep-sync`.

### Evidência da urgência (p116 audit)

```sql
SELECT 
  COUNT(*) AS total_apps,
  COUNT(*) FILTER (WHERE cv_extracted_text IS NOT NULL) AS with_extracted,
  COUNT(*) FILTER (WHERE resume_url IS NOT NULL AND cv_extracted_text IS NULL) AS need_extraction,
  COUNT(*) FILTER (WHERE resume_url IS NULL) AS no_resume
FROM selection_applications
WHERE created_at > now() - interval '90 days';
-- total=103, with_extracted=16, need_extraction=55, no_resume=32
```

55 apps órfãos (3.4× o volume de cycle3-2026-b2 sozinho). Backfill manual não escala — cada novo ciclo gera novos órfãos enquanto o pipeline está ausente.

### Drift bilateral revelado em p116

A/B re-triage pós-backfill mostrou que CVs ricos podem mover scores significativamente (João Coelho 4→7, Thayanne 1→3). Sem CV, AI triage opera com input incompleto e gera scores enviesados (tendência a subestimar). O pipeline é load-bearing para a calibração de ARM-11 evoluir além de 4.5.

### Restrições upstream (worker pmi-vep-sync)

- `resume_url` é uma URL SAS Azure com validade ~24h
- Worker `pmi-vep-sync` (Cloudflare Worker, repo separado) faz refresh dessas URLs
- Worker tem histórico de bot-detection do Azure (0 runs consecutivos no email alert recente — handoff p116)
- Sem worker funcionando, URLs eventualmente expiram e janela de extração fecha

Pipeline de extração precisa rodar **dentro da janela de validade do SAS** ou requerer fresh URLs do worker.

### Não-escopo

- Re-extração ou parsing semântico estruturado (e.g. extrair tags PM/AI separadamente — ai_pm_focus_tags fica para outra ADR/sprint)
- LinkedIn enrichment (out-of-scope, requer ToS/API decisão separada)
- OCR de PDFs scaneados (95%+ dos PDFs do VEP são text-based; OCR fica para edge case futuro)

## Decision

Implementar **`extract-cv-text` Edge Function (Deno + unpdf)** acionada por **cron a cada 15 minutos** com **fallback inline lazy em `pmi-ai-triage`** quando `cv_extracted_text IS NULL` no momento da triagem.

### Implementation choice (extraction): unpdf em Deno EF

| Option | Cost | Deno-native? | LGPD | Risco | Veredicto |
|--------|------|--------------|------|-------|-----------|
| **A — unpdf em Deno EF** | ~zero (compute only) | Sim (oficialmente suportado, ZDR irrelevante — texto fica em DB) | Self-hosted; texto cai em coluna já protegida por purge trigger | Baixo — Mozilla PDF.js sob o capô | **Escolhido** |
| B — Anthropic native PDF input em pmi-ai-triage | ~$0.025-0.05/triage (5pg CV; 1500-3000 tokens/page input) | N/A (substitui extração) | Texto+imagem vai para Anthropic (já vai parcial via prompt; ZDR-eligible) | Médio — duplica per-triage cost; perde searchability | Defer (avaliar como Option C V2 se Option A se mostrar limitante) |
| C — External service (Cloud Vision, Mathpix, Adobe) | ~$1/1K páginas + DPA setup | N/A (HTTP service) | Envio PII para terceiros (DPA + base legal extra) | Alto LGPD overhead | Rejeitado |
| D — Worker-side em pmi-vep-sync | Compute Cloudflare Workers (low) | Sim (V8 isolate) | Mesma posição que Option A | Médio — cross-repo deploy + bot-detection issue independente | Rejeitado nesta fase (revisitar quando worker estabilizar) |
| E — Python EF separada | ~zero | Não — Supabase EFs são Deno-only; precisaria Cloudflare Worker Python ou Container | LGPD ok | Alto — adiciona runtime separado só para esse pipeline | Rejeitado |

**unpdf foi escolhido porque:**
1. Suporte Deno oficial e estável (extração de texto não requer canvas)
2. Mesma família de PDF.js usada por pdfjs-dist (Mozilla, validado)
3. Compute zero — roda dentro do EF Supabase grátis até quota
4. Mantém `cv_extracted_text` self-hosted em DB (compatível com purge trigger LGPD existente)
5. Compatível com PDFs e .txt (este último como passthrough — ver p116, Marcio = .txt link LinkedIn)

### Trigger choice: cron 15min + lazy fallback inline

| Option | Latency | Idempotente? | Cobre backlog? | Coupling | Veredicto |
|--------|---------|--------------|----------------|----------|-----------|
| T1 — AFTER UPDATE trigger via pg_net | <30s | Sim (com guard `cv_extracted_text IS NULL`) | Não (só apps novos) | Alto — falha silenciosa se EF down | Defer |
| **T2 — Cron a cada 15min** | ≤15min | Sim | Sim (varre todos null) | Baixo | **Escolhido (primary)** |
| **T3 — Inline lazy em pmi-ai-triage** | 0 (in-line) | Sim | Não (só quando triage roda) | Médio (acopla triage à extração) | **Escolhido (fallback)** |
| T4 — Worker-side em pmi-vep-sync | imediato | Sim | Não (só apps novos) | Cross-repo | Rejeitado nesta fase |

**Padrão composto:**

- **Cron (T2)** primário — `extract-cv-cron-every-15min`:
  ```sql
  SELECT cron.schedule(
    'extract-cv-text-15min',
    '*/15 * * * *',
    $$SELECT public.extract_cv_text_batch(p_limit := 10);$$
  );
  ```
  RPC `extract_cv_text_batch` faz SELECT FOR UPDATE SKIP LOCKED de até 10 candidatos elegíveis (consent ativo + resume_url presente + cv_extracted_text NULL), invoca EF via `pg_net.http_post` por candidato com `pg_sleep(0.3)` entre chamadas (mesmo padrão de Resend rate-limit estabelecido em p92).

- **Lazy fallback (T3)** — em `pmi-ai-triage`, antes de buildUserPrompt:
  ```typescript
  if (app.resume_url && (!app.cv_extracted_text || app.cv_extracted_text.trim().length === 0)) {
    const extracted = await fetch(`${SUPABASE_URL}/functions/v1/extract-cv-text`, {
      method: "POST",
      headers: { Authorization: `Bearer ${SUPABASE_SERVICE_ROLE_KEY}`, "Content-Type": "application/json" },
      body: JSON.stringify({ application_id: app.id })
    });
    // re-fetch app row (triage continua mesmo se extração falhar — operação não bloqueia)
  }
  ```
  Cobre edge case onde cron não rodou ainda (e.g. nova application, admin clica "Rodar Triage" antes do próximo tick).

- **Trigger AFTER UPDATE (T1)** explicitamente DEFERIDO até cron + lazy provarem confiabilidade. Adicionar trigger sem cron significa silent failure mode (se EF down, perde extração). Adicionar trigger DEPOIS do cron é puro speedup, sem mudar semântica.

### Edge Function spec: `extract-cv-text`

**Endpoint**: `POST /functions/v1/extract-cv-text`

**Auth**: service-role only (chamado por cron RPC + por pmi-ai-triage internamente). Não exposto a JWT user.

**Request**:
```json
{ "application_id": "uuid" }
```

**Response (success)**:
```json
{
  "application_id": "uuid",
  "extracted_chars": 5918,
  "truncated": false,
  "source_format": "pdf",
  "duration_ms": 1230
}
```

**Response (no-op cases)** — return 200 com `noop_reason`:
- `consent_missing` (consent_ai_analysis_at NULL ou revoked)
- `no_resume_url`
- `already_extracted` (cv_extracted_text já populado e nonempty — idempotência)

**Response (errors)**:
- 400 `missing_application_id`
- 404 `application_not_found`
- 502 `fetch_failed` (resume_url retornou non-200; reportar status)
- 422 `parse_failed` (PDF inválido/corrupto/encrypted)
- 503 `unpdf_unavailable` (improvável, fallback se import falhar)

**Workflow**:
1. Service-role guard
2. SELECT application (consent + resume_url + cv_extracted_text)
3. Early returns (noop cases)
4. fetch(resume_url) com User-Agent realista (espelha o script p116) + timeout 30s
5. Detect content-type:
   - `application/pdf` → unpdf.extractText
   - `text/plain` → response.text() direto
   - outros → 422 com `unsupported_content_type`
6. Normalize: trim, collapse whitespace, NFC
7. Truncate em 50K chars (defesa-em-profundidade contra PDFs gigantes; pmi-ai-triage já trunca em 12K para o prompt)
8. UPDATE selection_applications.cv_extracted_text
9. INSERT em `ai_processing_log` (purpose='cv_extraction', status='completed', tokens_in=NULL, tokens_out=length(extracted), prompt_hash=sha256(resume_url), response_hash=sha256(extracted))
10. Return 200

**LGPD audit**: cada extração registrada em `ai_processing_log` (Art. 37 record-keeping). prompt_hash captura URL (não conteúdo); response_hash captura output (não conteúdo). Texto extraído fica em coluna purgável existente.

### RPC spec: `extract_cv_text_batch`

```sql
CREATE OR REPLACE FUNCTION public.extract_cv_text_batch(p_limit int DEFAULT 10)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_app RECORD;
  v_invoked int := 0;
  v_failed int := 0;
  v_url text;
  v_key text;
  v_response_id bigint;
BEGIN
  -- Service-role only (cron + admin emergencies)
  IF auth.role() <> 'service_role' THEN
    RAISE EXCEPTION 'extract_cv_text_batch requires service_role (called by cron)';
  END IF;

  v_url := 'https://ldrfrvwhxsmgaabwmaik.supabase.co/functions/v1/extract-cv-text';
  SELECT decrypted_secret INTO v_key
  FROM vault.decrypted_secrets
  WHERE name = 'service_role_key' LIMIT 1;
  IF v_key IS NULL THEN
    RAISE EXCEPTION 'service_role_key not in vault (extract_cv_text_batch)';
  END IF;

  FOR v_app IN
    SELECT id
    FROM selection_applications
    WHERE consent_ai_analysis_at IS NOT NULL
      AND consent_ai_analysis_revoked_at IS NULL
      AND resume_url IS NOT NULL
      AND (cv_extracted_text IS NULL OR length(cv_extracted_text) = 0)
    ORDER BY created_at DESC
    LIMIT p_limit
    FOR UPDATE SKIP LOCKED
  LOOP
    BEGIN
      SELECT net.http_post(
        url := v_url,
        body := jsonb_build_object('application_id', v_app.id),
        headers := jsonb_build_object('Authorization', 'Bearer ' || v_key, 'Content-Type', 'application/json')
      ) INTO v_response_id;
      v_invoked := v_invoked + 1;
      PERFORM pg_sleep(0.3); -- rate-limit guard (Resend pattern)
    EXCEPTION WHEN OTHERS THEN
      v_failed := v_failed + 1;
    END;
  END LOOP;

  RETURN jsonb_build_object('invoked', v_invoked, 'failed', v_failed, 'limit', p_limit);
END;
$function$;
```

**Por que SELECT FOR UPDATE SKIP LOCKED?** Garante que cron consecutivo (paranóia: cron interruption) não duplica trabalho. SKIP LOCKED evita bloqueio em apps que outro cron-tick está processando.

**Por que p_limit=10?** ~150ms/PDF (estimativa p116) × 10 = 1.5s loop, mais 0.3s × 10 = 3s sleep = ~4.5s total. Bem dentro da janela de 15min entre ticks. Permite ramp up para 20-30 se backlog grande.

### Schema follow-up

Adicionar `cv_extraction_attempts smallint DEFAULT 0` em selection_applications? **Não nesta ADR.** Se uma extração falha, o cron retentará automaticamente no próximo tick (idempotente). Adicionar contador prematuramente é YAGNI — só vale se observarmos um padrão de PDFs irrecuperáveis acumulando. Watch via `ai_processing_log WHERE purpose='cv_extraction' AND status='failed' GROUP BY application_id`.

## Implementation

| Component | File | Status |
|-----------|------|--------|
| ADR | `docs/adr/ADR-0075-cv-extraction-pipeline.md` | This doc |
| EF extract-cv-text | `supabase/functions/extract-cv-text/index.ts` | Pending implementation |
| RPC extract_cv_text_batch | migration `<next_ts>_arm11_cv_extraction_batch_rpc.sql` | Pending implementation |
| Cron job extract-cv-text-15min | migration (mesma) | Pending implementation |
| pmi-ai-triage lazy fallback | `supabase/functions/pmi-ai-triage/index.ts` | Pending edit (additive) |
| ai_processing_log purpose='cv_extraction' | usa schema existente (sem migration) | N/A |

**Estimativa de esforço de implementação** (sessão p118 ou seguinte): ~2-3h
- 30min EF (boilerplate + unpdf + auth + ai_processing_log insert)
- 30min RPC + cron migration
- 30min lazy fallback edit + smoke test
- 30min build + deploy + verificar primeiro cron tick + invoke manual teste
- Buffer 30-60min para edge cases (encrypted PDFs, content-type variants, oversized files)

## Consequences

### Positive

- ARM-11 AI Layer maturidade 4.5 → 5.0 (gathering + extraction operacionais, calibração feedback loop completa)
- Elimina 55 órfãos atuais (e todos futuros) sem mais scripts ad-hoc
- Pipeline LGPD-compliant by-design (purge trigger existente cobre + Art. 37 audit via ai_processing_log)
- Cost ~zero (unpdf compute only; cron 96 ticks/dia × 10 apps = ~144 invocações/dia steady-state após backlog)
- Lazy fallback em pmi-ai-triage cobre race conditions sem agravar coupling sistêmico
- Pattern reusável: extração de outros campos (LinkedIn enriched data) pode seguir o mesmo molde EF + cron + ai_processing_log

### Negative

- Custo manutenção: nova EF para monitorar (ai_processing_log filter purpose='cv_extraction' status='failed' precisa entrar em `get_lgpd_cron_health` ou novo health check)
- unpdf é dependência nova (npm); update path precisa ser revisitado periodicamente (mesma disciplina que zod no MCP, ver `.claude/rules/mcp.md`)
- Pipeline depende de `resume_url` válido. Se worker pmi-vep-sync continuar broken, URLs expiram em 24h e cron passa a fail (502 fetch_failed). Mitigation: monitor + worker fix é dependência paralela, não bloqueante para shipar essa ADR
- Lazy fallback em pmi-ai-triage adiciona latência (extra ~1-2s por triage quando CV faltando)
- Zero OCR support — PDFs scaneados retornam string vazia (raros no VEP atual; documentar como follow-up se observado)

### Pendentes (follow-up sessions)

1. **Implementação completa (sessão dedicada)**: shipar EF + RPC + cron + lazy fallback + smoke test em pelo menos 5 apps reais
2. **Health check**: estender `get_lgpd_cron_health` ou criar `get_extraction_health` para alertar se backlog cresce (e.g. >20 apps elegíveis aguardando extração)
3. **Worker pmi-vep-sync investigation**: dependência paralela (handoff p117 trigger #2). Sem worker, SAS expira e pipeline falha por 502. Investigar bot-detection Azure separadamente
4. **OCR follow-up**: se observarmos PDFs scaneados (parse_failed por content vazio mesmo com PDF válido), avaliar Tesseract.js ou serviço externo
5. **Trigger AFTER UPDATE (T1)**: revisitar após 30 dias de cron estável — se latência de 15min se mostrar problema operacional, adicionar trigger como acelerador
6. **Anthropic native PDF (Option B) reavaliação**: se Sonnet melhorar interpretação multimodal a ponto de justificar 2-5× custo, A/B com candidato amostra

## References

- ADR-0011: V4 authority gate (`can_by_member`) — não impactado, EF service-role only
- ADR-0012: schema invariants — não impactado
- ADR-0028: service_role bypass adapter pattern — RPC `extract_cv_text_batch` segue o padrão (auth.role() check)
- ADR-0059 W1: cv_extracted_text column substrate + LGPD purge trigger
- ADR-0067: AI-Augmented Selection Art. 20 safeguards
- ADR-0074: ARM Onda 3 dual-model AI architecture (pmi-ai-triage consumer)
- LGPD Art. 37 (registros de tratamento — ai_processing_log)
- LGPD Art. 16 (retenção — purge via cycle_decision_date documentado em ADR-0059)
- p116 handoff: `memory/handoff_p116_post_cv_extraction.md` (manual backfill evidence + 55 orphans + drift bilateral)
- p117 boot prompt: `memory/next_session_prompt.md`
- unpdf: https://github.com/unjs/unpdf (Deno-supported per repo README)
- Anthropic PDF support: https://platform.claude.com/docs/en/build-with-claude/pdf-support (Option B reference for future)
