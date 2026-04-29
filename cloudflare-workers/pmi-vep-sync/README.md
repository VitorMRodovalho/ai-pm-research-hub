# pmi-vep-sync — Cloudflare Worker

Worker que sincroniza candidaturas do PMI Volunteer Engagement Platform (VEP) com `selection_applications` do Núcleo IA & GP.

**Migration backing**: `supabase/migrations/20260516200000_phase_b_pmi_journey_v4.sql` (apply este antes de deploy do worker).
**Review doc**: `docs/specs/PMI_JOURNEY_V4_REVIEW.md` (verdict + ajustes B1+B2+B3 + R2/R5/R6/R7/R8).

## Função

- Cron: diário às 04:00 UTC (01:00 BRT). Self-healing: roda só se `now() - last_success >= 72h`.
- Para cada `vep_opportunities.is_active = true` com `essay_mapping` populado:
  - Lista applications nos 3 buckets PMI (submitted, qualified, rejected)
  - Para cada nova: detail call → mapeia → upsert → emite onboarding_token (TTL 7d) → envia welcome
  - Para existente: update apenas dos campos vindos do PMI (preserva consent, scores, ai_analysis)
- Log completo em `cron_run_log`. Alerta GP após 3 falhas consecutivas (via `campaign_send_one_off` slug `cron_failure_alert`).

## Adapt notes vs spec source (specs/p81-pmi-vep-journey/)

Diferenças desta versão (em produção) vs spec original:

| Mudança | Por quê |
|---|---|
| `db.ts` upsert usa COMPOUND KEY `(vep_application_id, vep_opportunity_id)` | B2 — preserva dual-track triaged_to_leader; spec original usava só `vep_application_id` que daria conflict em 5 candidatos triaged |
| `welcome.ts` chama `campaign_send_one_off(p_template_slug, p_to_email, p_variables, p_metadata)` | B3 — RPC original `campaign_send_one_off` não existia; wrapper criado em migration que delega para `admin_send_campaign` por slug |
| `welcome.ts` armazena `onboarding_token_hash` (sha256 hex), nunca plaintext | R2 — token é credencial; metadata é queryable, leak risk |
| `index.ts` issueOnboardingToken usa `ttl_days` da var env `ONBOARDING_TOKEN_TTL_DAYS` (default 7) | R2 — reduzido de 30→7 dias para PMI applications |
| `mapper.ts` aceita `role_default = 'manager'` sem mapeamento extra | B1 — `selection_applications.role_applied` CHECK estendida para incluir 'manager' |

## Estrutura

```
cloudflare-workers/pmi-vep-sync/
├── wrangler.toml          # Cloudflare config + crons + vars
├── package.json
├── tsconfig.json
├── README.md              # ← você está aqui
└── src/
    ├── index.ts           # entry point: scheduled handler
    ├── types.ts           # shared types (Env, VEP, Núcleo)
    ├── db.ts              # Supabase client + helpers (upsert compound key B2)
    ├── scheduler.ts       # self-healing logic + alert via campaign_send_one_off
    ├── pmi-vep-client.ts  # PMI VEP API wrapper (OAuth — TODO grant_type)
    ├── mapper.ts          # PMI detail → selection_applications
    ├── onboarding-token.ts# token issuer (Web Crypto API) + sha256Hex helper R2
    └── welcome.ts         # welcome message dispatcher (B3 + R2)
```

## PMI OAuth KV Setup — access-only mode (Plano B-revised)

**Descoberta crítica via análise HAR (2026-04-28)**: PMI vep_ui app NÃO emite
`refresh_token`. App é public SPA com PKCE, scope=`openid profile` (sem
`offline_access`). Token tem TTL de **24h** mas não pode ser auto-renovado.

**Workflow operacional**: PM re-seeda KV diariamente (15-30 segundos por dia).
Worker alerta proativamente quando access_token expira em < 6h.

**Long-term fix (assíncrono — não bloqueia)**: PM solicita ao PMI IT que adicione
`offline_access` ao scope do `vep_ui_a58c68be946f4cf8841ff4bbf7b3c43b` OU
registre app dedicado `nucleo_pmi_sync` com offline_access. Quando isso for feito,
o worker suporta refresh_token automaticamente (código já preparado, só passar
`refresh_token` no seed JSON).

### Passo 1 — Criar KV namespace
```bash
cd cloudflare-workers/pmi-vep-sync
npx wrangler kv namespace create pmi_oauth_kv
# Output: { "binding": "PMI_OAUTH_KV", "id": "abc123def456..." }
```
Editar `wrangler.toml`: substituir `REPLACE_WITH_KV_NAMESPACE_ID_AFTER_CREATE` pelo `id` retornado.

### Passo 2 — Capturar access_token via login PMI VEP

Opção A (HAR — recomendada): exportar HAR do login (DevTools → Network → "..." → Save all as HAR), passar o caminho para Claude Code. Claude extrai automaticamente.

Opção B (manual): DevTools → Network → procurar POST `https://idp.pmi.org/connect/token` → response JSON → copiar `access_token`. Calcular `expires_at = Date.now() + (expires_in * 1000)`.

### Passo 3 — Seed o KV

```bash
# Se Claude já extraiu (arquivo /tmp/pmi_oauth_seed.json):
npx wrangler kv key put --binding=PMI_OAUTH_KV pmi_oauth:tokens "$(cat /tmp/pmi_oauth_seed.json)"

# OU manual:
TOKENS_JSON='{
  "access_token": "<COLE_JWT_ACCESS_TOKEN_AQUI>",
  "expires_at": 1777521033000,
  "refreshed_at": 1777434633000,
  "initialized_by": "manual_seed_YYYY_MM_DD_vitor"
}'
npx wrangler kv key put --binding=PMI_OAUTH_KV pmi_oauth:tokens "$TOKENS_JSON"
```

### Passo 4 — Confirmar
```bash
npx wrangler kv key get --binding=PMI_OAUTH_KV pmi_oauth:tokens
```

### Re-seed diário (operacional)

Quando worker detectar token expirando em < 6h, alerta via:
- `cron_run_log.metrics.pmi_token_expiring_soon = true`
- console.warn em logs (`wrangler tail`)

Após 3 falhas consecutivas (token totalmente expirado), o worker dispara
`campaign_send_one_off` slug=`cron_failure_alert` para PM.

PM re-seeda repetindo Passos 2-3 (HAR export + extract OU manual copy do
DevTools).

**Auditoria**: campo `initialized_by` no JSON permite rastrear quem/quando fez
o seed. Atualizar a cada re-seed (ex: `manual_seed_2026_04_30_vitor`).

---

## Pré-deploy checklist (PM browser tasks)

- [ ] **Setup PMI OAuth KV** (passos 1-4 acima)
- [ ] **Seedar `campaign_templates`** com 2 rows:
  - `slug = 'pmi_welcome_with_token'` — template do welcome ao candidato (placeholders: `{{first_name}}`, `{{role_label}}`, `{{chapter}}`, `{{onboarding_url}}`, `{{expires_in_days}}`)
  - `slug = 'cron_failure_alert'` — template do alerta GP (placeholders: `{{worker}}`, `{{failure_count}}`)
- [ ] **Verificar `vep_opportunities.essay_mapping`** populado nas 3 ativas (manager/researcher/leader)
  ```sql
  SELECT opportunity_id, title, role_default,
         essay_mapping IS NULL OR essay_mapping = '{}'::jsonb AS missing_mapping
  FROM vep_opportunities WHERE is_active = true;
  ```
- [ ] **Confirmar `chapter_failure_alert` mapping** dos 5 chapters parceiros (TODO em `mapper.ts:parseChapterFromMembership`)
- [ ] `cd cloudflare-workers/pmi-vep-sync && npm install`
- [ ] `npm run typecheck` — deve passar limpo
- [ ] **Setar todos os secrets via `wrangler secret put`:**
  - `SUPABASE_URL`
  - `SUPABASE_SERVICE_ROLE_KEY`
  - `PMI_VEP_BASE_URL`
  - `PMI_VEP_OAUTH_TOKEN_URL`
  - `PMI_VEP_OAUTH_CLIENT_ID`
  - `PMI_VEP_OAUTH_CLIENT_SECRET`
  - `GP_NOTIFICATION_EMAIL`
  - `ONBOARDING_BASE_URL` (ex: `https://nucleoia.vitormr.dev/pmi-onboarding`)
- [ ] Deploy em staging primeiro: `wrangler deploy --env staging`
- [ ] Smoke test manual: trigger via dashboard + `wrangler tail`

## Smoke test em produção (primeiro run)

Como o cron diário só executa às 04 UTC, para testar imediatamente:

```bash
wrangler triggers cron pmi-vep-sync --env production
wrangler tail pmi-vep-sync --env production
```

Conferir resultado:

```sql
-- Última execução
SELECT * FROM cron_run_log
WHERE worker_name = 'pmi-vep-sync'
ORDER BY started_at DESC
LIMIT 1;

-- Applications novas
SELECT vep_application_id, vep_opportunity_id, applicant_name, email, role_applied, status, imported_at
FROM selection_applications
WHERE imported_at > now() - interval '1 hour'
ORDER BY imported_at DESC;

-- Tokens emitidos
SELECT token, source_id, scopes, expires_at, issued_at
FROM onboarding_tokens
WHERE issued_by_worker = 'pmi-vep-sync'
  AND issued_at > now() - interval '1 hour';
```

## Self-healing detalhado

A lógica `decideRun()` em `scheduler.ts`:

| Condição | Decisão |
|---|---|
| Sem run anterior bem-sucedido | run, reason=`first_run` |
| `hoursSince >= cadence + tolerance` (84h) | run, reason=`overdue` |
| `hoursSince >= cadence` (72h) | run, reason=`normal_window` |
| `hoursSince < cadence` | skip, reason=`last_success_Xh_ago_next_in_Yh` |
| Erro ao consultar `v_cron_last_success` | run (fail-safe), reason=`fallback_on_query_error` |

Se `log_cron_run_start` detecta zumbi (status=running > 30min), mata via UPDATE para `zombie` antes de criar novo run.

## Alerting

Após 3 runs consecutivos com `status = 'failed'`, `alertConsecutiveFailures()` envia email para `GP_NOTIFICATION_EMAIL` via `campaign_send_one_off(p_template_slug='cron_failure_alert', ...)`.

## Variáveis de ambiente

| Var | Função | Default |
|---|---|---|
| `CRON_CADENCE_HOURS` | janela normal entre runs | 72 |
| `CRON_TOLERANCE_HOURS` | atraso aceitável antes de "overdue" | 12 |
| `CONSECUTIVE_FAILURE_ALERT_THRESHOLD` | falhas seguidas antes de alertar | 3 |
| `ONBOARDING_TOKEN_TTL_DAYS` | TTL de tokens emitidos (R2) | 7 |
| `ORG_ID` | uuid da organization (multi-tenant ready) | `2b4f58ab-...` |

## Troubleshooting

### "PMI OAuth token failed"
- Verificar `PMI_VEP_OAUTH_*` secrets
- Confirmar grant_type (pode não ser `client_credentials` — ver TODO no client)

### "essay_mapping vazio — popular antes de ativar"
Vaga existe em `vep_opportunities.is_active = true` mas sem mapping configurado. Popular via SQL editor.

### Welcome message não chegou
- Verificar `email_webhook_events` por bounces
- Verificar `campaign_sends.metadata->>onboarding_token_hash` para o `application_id` (token plaintext NÃO é armazenado — busca por hash)
- Conferir spam do destinatário

### Run "zombie"
Significa que o worker travou ou foi morto antes de chamar `log_cron_run_complete`. `log_cron_run_start` mata zumbis automaticamente no próximo trigger.

## Próximos workers (não estão neste pacote)

- `gemini-transcribe`: ouve uploads de vídeo, chama Gemini 2.0 Flash, escreve transcrição em `pmi_video_screenings.transcription`
- `ai-objective-drafter`: gera draft objective (Sonnet 4.6), insere em `selection_evaluation_ai_suggestions` (consent-gated por trigger)
- `ai-interview-drafter`: idem para interview, após 4 transcrições prontas
