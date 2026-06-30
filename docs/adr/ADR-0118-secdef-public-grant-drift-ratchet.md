# ADR-0118 — Systemic SECDEF PUBLIC-grant drift: targeted revoke + CI ratchet (#965)

**Status:** Accepted (2026-06-30, #965)
**Relacionado:** ADR-0106 (RLS + SECDEF RPCs são a fronteira de autoridade — não há SSR auth-gate) · #963 (origem: `campaign_send_one_off` open-relay já corrigido) · #588 ([LL]: gates ortogonais não devem ser conflatados por auditoria mecânica) · #730 (precedente de contract test DB-grounded por audit RPC) · #684 (precedente de leitura defensiva de migration em contract test).
**Migration:** `20260805000306_965_secdef_public_grant_drift_revoke.sql`.

## Contexto

`CREATE FUNCTION` no Postgres concede `EXECUTE` a **`PUBLIC`** por default. Migrations que adicionaram `GRANT … TO service_role` explícito **sem** o `REVOKE … FROM PUBLIC` correspondente deixaram funções `SECURITY DEFINER` chamáveis por `anon`/`authenticated` via PostgREST (`POST /rest/v1/rpc/<fn>`) — disparando um side-effect pago/dispatch. A pior instância (`campaign_send_one_off`, open-relay de e-mail) foi corrigida em #963. O #965 rastreia **o resto da classe**.

A varredura (issue #965) acha funções `public` SECDEF alcançáveis por `anon`/`PUBLIC`, sem marcador de gate inline (`auth.uid()`/`can_by_member`/`auth.role`/`current_setting`), que fazem `INSERT/UPDATE/DELETE` ou `http_post`. **Re-rodada ao vivo (2026-06-30): 36 funções** — heurística de 1ª passada com **falsos positivos** (não detecta token-gating). O #965 e o [LL] #588 são explícitos: **não fazer mass-revoke mecânico**; cada função exige checagem de call-graph + intenção.

## Decisão

**1. Revogar 6 funções de side-effect cujo call-graph é CRON + TRIGGER + SECDEF-only (verificado ao vivo).**

`REVOKE EXECUTE FROM PUBLIC, anon, authenticated` (mantém `service_role`/`postgres` ⇒ cron/worker/SECDEF intactos; definers retêm EXECUTE p/ chamadas internas). grep `src/` + `supabase/functions/` por `.rpc('<name>')` nas 6 = **zero** caller anon/authenticated direto.

- `process_pending_email_queue()` — cron `dispatch-pending-emails` (http_post).
- `analyze_application_video_async(uuid,text,boolean)` — wrapper SECDEF `analyze_application_video` (MCP) + trigger de upload (já DROPPED) (http_post).
- `retry_pending_ai_analyses()` — cron + readers SECDEF (http_post).
- `retry_pending_ai_triages()` — cron `retry-pending-ai-triages` (http_post).
- **`generate_weekly_leader_digest_cron()`** — cron `send-weekly-leader-digest`; insere notificações **transacionais** p/ todo líder de tribo ⇒ anon = **SPAM** de notificação/e-mail. (Escalado de "lower-severity" pela revisão adversarial — mesma classe de abuso de custo das dispatchers.)
- **`_grant_auto_xp(text,uuid,uuid,text,boolean)`** — 9 triggers `trg_*_xp` + `register_event_showcase` (todos SECDEF); aceita `p_recipient_id` arbitrário ⇒ anon/authenticated = **fraude de XP**. (Escalado pela revisão.)

**2. NÃO revogar `request_application_enrichment` nem `opt_out_all_pillars` — são token-gated por design.**

Ambas validam `onboarding_tokens` no corpo (`'profile_completion'` / `'video_screening'`, `expires_at>now()`) e RAISEam em token inválido; são chamadas por fluxos de candidato pré-onboarding (anon + token: `EnrichmentCard.tsx` / opt-out de entrevista). A varredura as sinalizou (token-validation não é `auth.uid()`), mas **revogar `anon` quebraria o fluxo**. Vão para a allowlist, não para o revoke. (Exatamente o falso-positivo que o #965 e o [LL] #588 advertem — `opt_out_all_pillars` foi reclassificada de "pending revoke" → "token-gated" pela revisão adversarial.)

**3. Defesa-adiante = ratchet de CI.**

Audit RPC `_audit_secdef_public_grant_drift()` (SECDEF SELECT-only sobre catálogo; retorna **apenas identidades** — sem corpos, sem PII; usa **`has_function_privilege('anon', p.oid, 'EXECUTE')`** por-OID ⇒ robusto a overloads, sem a ambiguidade do `routine_name`; REVOKE PUBLIC/anon). O contract test `tests/contracts/965-secdef-public-grant-drift.test.mjs` afirma que o conjunto vivo **é IGUAL** a uma allowlist categorizada (token-gated / counter-lead / person-scoped / lower-severity-pendente). Um **novo grant anon/PUBLIC não-gated falha o CI**.

## Escopo / fora de escopo

- **No escopo:** as 6 funções acima + o ratchet. Pós-revoke a varredura cai de 36 → **30 = a allowlist**.
- **Fora (follow-up, ratchet-down):** ~14 funções `_*`/cron de **lower-severity** ficam na allowlist como **pendentes** — cada uma exige sua própria checagem de call-graph antes de revogar (não mecanicamente, [LL] #588). Casos que exigem atenção: `recompute_all_active_pert_cutoffs` (há um hint de wrapper MCP no EF), `record_milestone`/`register_video_screening`/`create_notification` (podem ter callers authenticated). À medida que forem revogadas/gated, saem da allowlist (o ratchet desce). As **by-design** (token RPCs, counters, `capture_visitor_lead`, `create_initiative`) permanecem. `create_initiative`: o overload de 4-arg ainda carrega um `anon` explícito remanescente (o de 6-arg foi revogado na mig …234) — rastreado p/ revisão dedicada.

## Consequências

- Fecha as superfícies de custo/DoS (e-mail/IA), spam (digest) e fraude (XP) sem regressão.
- REVOKE-only (+ 1 RPC SELECT-only) ⇒ `rpc-migration-coverage`/body-drift inalterados p/ corpos existentes; o RPC novo é capturado nesta migration.
- O ratchet por **igualdade de conjunto** é deliberadamente estrito: qualquer migration futura que adicione/remova uma função SECDEF-anon-side-effect dispara o teste — exatamente quando se quer uma revisão consciente da allowlist.
