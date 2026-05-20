---
issue: 163
title: infra/security - Cloudflare BIC blocks MCP OAuth bootstrap
lane: Infra/Security
priority: P1
effort: S (rule + verification)
status: done
opened: 2026-05-19
github: https://github.com/VitorMRodovalho/ai-pm-research-hub/issues/163
---

# p201 Session Brief - Issue #163: Cloudflare BIC vs MCP/OAuth Bootstrap

## Why this matters

Cloudflare Browser Integrity Check (BIC) returns `403 Error 1010
browser_signature_banned` on `nucleoia.vitormr.dev/mcp`,
`/.well-known/oauth-*`, and `/oauth/*` for some programmatic client
signatures (default Python `urllib`). Blocked requests never reach the
Worker, so they do not appear in Worker Observability or
`mcp_usage_log`. Real Claude.ai connector failures are therefore
invisible to app-side telemetry, and the only diagnostic path is
Cloudflare Security Events filtered by Ray ID + path.

## Evidence (collected during p201 audit)

- `urllib`/Python signature -> `403 Error 1010` on `/mcp`,
  `/.well-known/oauth-protected-resource`,
  `/.well-known/oauth-authorization-server`, `/oauth/authorize`.
- Browser-like and synthetic `Claude-User/1.0` user-agents PASS: `/mcp`
  returns `401 + WWW-Authenticate`, `/.well-known/oauth-*` returns
  `200`, `/oauth/register` returns `201`, `/oauth/authorize` renders
  consent at `200`.
- Worker Observability only logs requests that pass the edge.
- Repeated retests during p201 (Rays `9fe60dc55ef31516`,
  `9fe60dc61b331826`, `9fe612d38c4b1514`) confirmed the block
  reproduces on every synthetic request without browser-like signature.
- Cloudflare docs: official Error 1010 cause is access denied based on
  browser signature; owner-side resolution is to disable BIC for the
  path or skip it via WAF custom rule.

## Lane and gates

- Lane: Infra/Security (Cloudflare dashboard / Terraform, no app code)
- Can touch: Cloudflare WAF custom rules, Bot Fight Mode scope, BIC
  scope, rate limits for `/mcp*`
- Can't touch: app source code, Worker behaviour, OAuth flow
  semantics
- Gates: Cloudflare Security Events before/after with Ray IDs, smoke
  on real Claude connector path, compensating rate limit so the skip
  rule does not become an abuse vector

## In scope

1. Inspect Cloudflare Security Events filtered by path
   `/mcp`, `/.well-known/oauth-*`, `/oauth/*` and action
   `browser_signature_banned` to capture the real Claude connector
   Ray ID (if available).
2. Create a Cloudflare WAF custom rule:
   - Match: hostname `nucleoia.vitormr.dev` AND path matches
     `^/(mcp|\.well-known/oauth-|oauth/)`.
   - Action: Skip > Bot Fight Mode + Browser Integrity Check + Managed
     Challenge (whichever components are blocking).
   - Order: above default Bot Fight rule.
3. Add compensating rate limit for `/mcp*` (e.g., 100 req/min per IP
   with `429` on excess).
4. Document the rule in `docs/MCP_SETUP_GUIDE.md` or a new
   `docs/infra/CLOUDFLARE_MCP_RULES.md`.
5. Record the decision in `docs/GOVERNANCE_CHANGELOG.md` (new GC
   entry).

## Out of scope

- Switching to a different origin or hostname.
- Implementing JWT-level abuse detection beyond rate limit.
- Touching the OAuth flow code in the Worker.

## Files likely to touch

- `docs/MCP_SETUP_GUIDE.md` (or new `docs/infra/CLOUDFLARE_MCP_RULES.md`)
- `docs/GOVERNANCE_CHANGELOG.md` (new GC entry)
- `docs/audit/P162_GAP_OPPORTUNITY_LOG.md` (close item #40)
- Cloudflare dashboard config (no repo file unless we maintain
  Terraform)

## Validation

- Before/after Security Events comparison: blocked Ray IDs disappear
  for the test signature.
- Synthetic smoke after rule:
  ```bash
  curl -sS -i https://nucleoia.vitormr.dev/.well-known/oauth-protected-resource
  # expect HTTP/2 200

  curl -sS -i https://nucleoia.vitormr.dev/mcp -X POST \
    -H "Content-Type: application/json" \
    -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}'
  # expect HTTP/2 401 + WWW-Authenticate: Bearer resource_metadata=...
  ```
- Real Claude connector reconnect succeeds end-to-end.
- Rate limit triggers `429` at the documented threshold.

## Rollback

- Disable the WAF custom rule (single click in Cloudflare UI) - all
  traffic goes back to BIC default.
- Rate limit can stay enabled even if skip rule is rolled back.

## Cross-references

- `docs/audit/P162_GAP_OPPORTUNITY_LOG.md` item #40 (full evidence)
- `docs/audit/P201_MCP_ARCHITECTURE_AUDIT.md` §3.3
- CLAUDE.md decision #2 (custom domain to avoid `.workers.dev` BIC)
- `.claude/rules/mcp.md` (pre-deploy + smoke after deploy)

## Handoff (fill on completion)

```md
## Handoff

Issue: #163
Branch: agent/issue-163 (worktree em /home/vitormrodovalho/projects/ai-pm-issue-163)
Cloudflare rule:
  - `mcp-oauth-skip-bic` (WAF Custom Rule) — Active. Match: `(http.host eq "nucleoia.vitormr.dev") and (starts_with /mcp or /.well-known/oauth- or /oauth/)`. Action: Skip → Browser Integrity Check + All Super Bot Fight Mode Rules.
Rate limit configured:
  - `mcp-rate-limit` (Rate Limiting Rule) — Active. Match: `(http.host eq "nucleoia.vitormr.dev") and starts_with(/mcp)`. Threshold: 50 req / 10s per IP. Action: Block. Duration: 10s. (Free plan limita Period a 10s; original spec 100/min adaptada mantendo ordem de magnitude ~300/min effective.)
Security Events before/after:
  - PRÉ-fix Ray IDs (Python-urllib/3.11 → 403): `9fe75d560886181e-RIC` (/.well-known/oauth-authorization-server), `9fe75d585a2f181e-RIC` (/oauth/authorize). Histórico em audit log #40 também lista 7 retests pré-fix com Rays adicionais.
  - PÓS-fix Ray IDs (Python-urllib/3.11 → 200/302/401): `9fe793db1e9b151a-RIC`, `9fe793dbab751514-RIC`, `9fe793dc4c057bea-RIC`, `9fe793dcdc437bea-RIC`.
  - Burst Ray IDs (429 rate limit hits): `9fe7a4903c0c151e-RIC`, `9fe7a490afc97bea-RIC`, `9fe7a4912df87bf3-RIC`.
Smoke results:
  - 4 paths × Python-urllib/3.11 UA: TODOS PASS (200 / 302 / 401 / 200 conforme expected). Pré-fix 2 paths retornavam 403; pós-fix 0 paths bloqueados.
  - Burst 120 requests: 50 × 401 + 70 × 429 (match exato ao threshold 50/10s).
  - Sanity Claude-User/1.0: continua HTTP/2 401 + WWW-Authenticate normal. Browser-like UAs preservados.
Riscos:
  - Free plan rate limit 10s window é mais agressivo que 1min original — sessões Claude.ai tool-heavy podem hit 429 em loops agênticos. Backlog: re-tunar para 100/1min se upgrade Pro plan.
  - Skip rule cobre BIC + Bot Fight Mode + Super Bot Fight Mode. NÃO cobre WAF Managed Rules (preserva proteção contra exploits conhecidos) nem custom rules (defesa em profundidade).
Rollback:
  - Disable Rule 1 (`mcp-oauth-skip-bic`) → BIC volta a bloquear programáticos. 1-click no dashboard.
  - Disable Rule 2 (`mcp-rate-limit`) → sem throttle de burst. 1-click no dashboard.
  - Rate limit pode permanecer enabled se skip rule rolada — sem dependência.
Docs:
  - `docs/infra/CLOUDFLARE_MCP_RULES.md` — spec completa com Rays pré/pós + burst evidence (NOVO arquivo)
  - `docs/GOVERNANCE_CHANGELOG.md` — GC-146 atualizada Status: Aberto → Implementado com Rays evidence
  - `docs/audit/P162_GAP_OPPORTUNITY_LOG.md` — item #40 marcado RESOLVED com follow-up p202 + Rule 2 apply + burst smoke
  - `docs/MCP_SETUP_GUIDE.md` — linha de Troubleshooting adicionada apontando para CLOUDFLARE_MCP_RULES.md
Próximo passo:
  - Pós-merge: monitorar Cloudflare Security Events últimas 24h pra confirmar 0 hits de `browser_signature_banned` em /mcp e /oauth (já são esperados 0 — Rule 1 skip elimina o block).
  - Se algum cliente legítimo reportar 429 em uso normal Claude.ai tool-heavy: aumentar threshold (75 ou 100 req/10s).
  - Pós-1 sprint QA window: PM avalia fechar issue + remover branch + remover worktree.
  - Backlog WATCH: re-tunar rate limit para 100 req/1min se upgrade Pro plan acontecer (registrado em audit log #40 + CLOUDFLARE_MCP_RULES.md).
```
