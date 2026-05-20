# Cloudflare WAF Rules — MCP / OAuth Bootstrap

**Owner:** Vitor (GP / superadmin)  
**Domain:** `nucleoia.vitormr.dev` (zone `vitormr.dev`)  
**Adopted:** 2026-05-19 (issue #163 close, p202)  
**Audit reference:** `docs/audit/P162_GAP_OPPORTUNITY_LOG.md` item #40

## Problema

Cloudflare Browser Integrity Check (BIC) retorna `HTTP 403 / Error 1010 browser_signature_banned` em rotas MCP/OAuth para certas assinaturas programáticas (`Python-urllib/3.11`, alguns crawlers/bots HTTP). Browser-like e `Claude-User/1.0` passam. Requests bloqueados nunca atingem o Worker, então não aparecem em `mcp_usage_log` — único caminho de diagnóstico é Cloudflare Security Events filtrado por Ray ID + path.

Impacto: clientes MCP programáticos legítimos (Python bootstrap, agentes futuros, scripts de smoke) falham na descoberta OAuth sem qualquer telemetria app-side.

## Rule 1 — WAF Custom Rule: Skip BIC para MCP / OAuth bootstrap

### Onde aplicar (dashboard)

1. Login em https://dash.cloudflare.com com conta dona da zona `vitormr.dev`
2. Selecionar zone `vitormr.dev`
3. Menu lateral: **Security** → **WAF** → aba **Custom rules**
4. Clicar **Create rule**

### Configuração

| Campo | Valor |
|---|---|
| Rule name | `mcp-oauth-skip-bic` |
| Description | `Skip Browser Integrity Check + Bot Fight for MCP/OAuth bootstrap (issue #163)` |
| Field | usar o **Expression editor** (modo "Edit expression") |

**Expression (copy-paste):**

```
(http.host eq "nucleoia.vitormr.dev") and (
  starts_with(http.request.uri.path, "/mcp")
  or starts_with(http.request.uri.path, "/.well-known/oauth-")
  or starts_with(http.request.uri.path, "/oauth/")
)
```

| Campo | Valor |
|---|---|
| Action | **Skip** |
| Skip — Browser Integrity Check | ☑ marcado |
| Skip — Bot Fight Mode | ☑ marcado (se ativo na zona) |
| Skip — Super Bot Fight Mode | ☑ marcado (se ativo) |
| Skip — Managed Challenge actions | ☑ marcado |
| Skip — Rate Limiting | ☐ desmarcado (queremos que rate limit continue valendo — ver Rule 2 abaixo) |
| Skip — WAF Managed Rules | ☐ desmarcado (mantém proteção contra exploit conhecido) |
| Skip — Zone Lockdown | ☐ desmarcado |
| Order/Priority | Acima de qualquer rule de Bot Fight Mode default |

Salvar e **Deploy**.

### Notas

- Cloudflare docs: Error 1010 é "access denied based on browser signature". Owner-side resolution é desabilitar BIC para o path ou skipar via WAF custom rule. Estamos fazendo o segundo (mais cirúrgico, mantém BIC para resto da zona).
- A rule é ordem-sensitive: tem que ser avaliada ANTES das regras de Bot Fight Mode. Cloudflare avalia rules em ordem; arraste para topo da lista se necessário.

## Rule 2 — Rate Limiting: /mcp* (compensating control)

### Por que

Sem rate limit, a skip rule acima vira um vetor de abuso (atacante pode disparar requests programáticos contra `/mcp` sem fricção). Rate limit por IP compensa.

### Plan limitation (Free plan)

Cloudflare Free plan limita Period de Rate Limiting rule a **10 segundos** (Pro+ desbloqueia 1min, 5min, 10min, etc.). A spec original era `100 req / 1 minute`; adaptamos para Free plan mantendo a ordem de magnitude da proteção: **50 req / 10s ≈ 300 req/min effective**.

Trade-off: 50 req/10s é mais permissivo que 100/min original (~3x) mas evita false-positive em sessões Claude.ai tool-heavy (agentes podem facilmente burst 20-30 requests em segundos durante loops agênticos). Mantém detecção de abuso sustentado (>5 req/s).

Se houver upgrade Pro futuro: alterar para 100 req/1 minute = spec original.

### Onde aplicar

1. Mesma zona `vitormr.dev`
2. **Security** → **WAF** → aba **Rate limiting rules**
3. Clicar **Create rate limiting rule**

### Configuração (Free plan adapted)

| Campo | Valor |
|---|---|
| Rule name | `mcp-rate-limit` |
| Description | `50 req/10s per IP on /mcp* (Free plan adapted; ≈300 req/min effective; compensates skip-BIC, issue #163)` |

**Expression (copy-paste):**

```
(http.host eq "nucleoia.vitormr.dev") and starts_with(http.request.uri.path, "/mcp")
```

| Campo | Valor |
|---|---|
| When rate exceeds | **50 requests** per **10 seconds** |
| With the same characteristics | **IP address** |
| Then | **Block** (action) |
| Duration | **10 seconds** (mínimo Free plan) ou **1 minute** se disponível |
| Response type | Default Cloudflare block page (HTTP 429) |

Salvar e **Deploy**.

### Tuning futuro

- 50 req/10s = ~300 req/min. Claude.ai connector em uso normal (1 user, agente médio) fica longe disso. Pegue casos extremos de loops agênticos burst.
- Se um cliente legítimo for bloqueado: aumentar para 75 ou 100 req/10s.
- Não aplicar rate limit a `/.well-known/oauth-*` ou `/oauth/*` — fluxo OAuth tem natural burstiness durante handshake.
- Upgrade Pro plan desbloqueia 1min+ windows; aí voltar para spec original `100 req / 1 minute`.

## Verification (smoke)

### Pré-aplicação (baseline esperado: bloqueado)

```bash
# Path 1: oauth-authorization-server com Python-urllib UA
curl -sS -o /dev/null -w "HTTP %{http_code} | Ray: %header{cf-ray}\n" \
  -A "Python-urllib/3.11" --max-time 8 \
  "https://nucleoia.vitormr.dev/.well-known/oauth-authorization-server"
# Esperado pré-fix: HTTP 403 (BIC block)

# Path 2: /oauth/authorize com Python-urllib UA
curl -sS -o /dev/null -w "HTTP %{http_code} | Ray: %header{cf-ray}\n" \
  -A "Python-urllib/3.11" --max-time 8 \
  "https://nucleoia.vitormr.dev/oauth/authorize?response_type=code&client_id=test&redirect_uri=https%3A%2F%2Fexample.com&state=x&code_challenge=y&code_challenge_method=S256"
# Esperado pré-fix: HTTP 403 (BIC block)
```

### Pós-aplicação (esperado: passa pela edge)

```bash
# Path 1 deve passar
curl -sS -o /dev/null -w "HTTP %{http_code} | Ray: %header{cf-ray}\n" \
  -A "Python-urllib/3.11" --max-time 8 \
  "https://nucleoia.vitormr.dev/.well-known/oauth-authorization-server"
# Esperado pós-fix: HTTP 200

# Path 2 deve passar (mas /oauth/authorize com client_id desconhecido retorna 400, é esperado — o ponto é não ser 403)
curl -sS -o /dev/null -w "HTTP %{http_code} | Ray: %header{cf-ray}\n" \
  -A "Python-urllib/3.11" --max-time 8 \
  "https://nucleoia.vitormr.dev/oauth/authorize?response_type=code&client_id=test&redirect_uri=https%3A%2F%2Fexample.com&state=x&code_challenge=y&code_challenge_method=S256"
# Esperado pós-fix: HTTP 400 (client_id inválido), NÃO 403

# Path 3: /mcp POST initialize com Python-urllib
curl -sS -i -A "Python-urllib/3.11" --max-time 8 -X POST \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"smoke","version":"1"}}}' \
  "https://nucleoia.vitormr.dev/mcp" | head -8
# Esperado pós-fix: HTTP 401 + header `WWW-Authenticate: Bearer resource_metadata=...`
```

### Rate limit (sanidade)

```bash
# Burst 110 requests sem auth — pelo menos a partir da 101 deve retornar 429
for i in $(seq 1 110); do
  curl -sS -o /dev/null -w "%{http_code}\n" --max-time 4 -X POST \
    -H "Content-Type: application/json" -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' \
    "https://nucleoia.vitormr.dev/mcp"
done | sort | uniq -c
# Esperado: maioria 401 (sem auth) e pelo menos algumas 429 a partir do 101º request
```

### Cloudflare Security Events (UI)

1. Security → Events
2. Filtros: **Path** contém `/mcp` ou `/oauth` · **Action** = `browser_signature_banned`
3. Time range: últimos 30 minutos
4. **Pré-fix**: lista mostra entries com Ray IDs (ex: `9fe75d560886181e`)
5. **Pós-fix**: lista vazia (ou só registros pré-aplicação)

## Rollback

### Cenário: skip rule causou problema (improvável)

1. WAF → Custom rules → editar `mcp-oauth-skip-bic` → **Disable** (toggle)
2. Resultado imediato: BIC volta a aplicar em `/mcp` + `/.well-known/oauth-*` + `/oauth/*`
3. Clientes browser-like e `Claude-User/1.0` continuam passando; programáticos voltam a ser bloqueados

### Cenário: rate limit muito agressivo

1. WAF → Rate limiting rules → editar `mcp-rate-limit` → ajustar threshold (200, 300, etc.) ou Disable
2. Effective em ~30s

### Cenário: ambos voltar ao estado pré-fix

1. Disable ambas as rules
2. Verificar via Security Events que tráfego normal continua aceito
3. Rate limit pode permanecer enabled mesmo se skip rule for rollada — não há dependência

## Auditoria

**Pré-fix (p202, 2026-05-19 ~21:53Z) — `Python-urllib/3.11` UA blocked:**
- `/.well-known/oauth-authorization-server` → HTTP 403 (Ray `9fe75d560886181e-RIC`)
- `/oauth/authorize` → HTTP 403 (Ray `9fe75d585a2f181e-RIC`)

**Pós-fix (p202, 2026-05-19 ~21:55Z) — `Python-urllib/3.11` UA, mesmo signature que era blocked:**
- `/.well-known/oauth-authorization-server` → HTTP 200 (Ray `9fe793db1e9b151a-RIC`)
- `/oauth/authorize?...` → HTTP 302 (redirect to login, comportamento OAuth correto) (Ray `9fe793dbab751514-RIC`)
- `POST /mcp` initialize → HTTP/2 401 + `WWW-Authenticate: Bearer resource_metadata=...` (Ray `9fe793dc4c057bea-RIC`)
- `/.well-known/oauth-protected-resource` → HTTP 200 (Ray `9fe793dcdc437bea-RIC`)

**Rate Limit (Rule 2 applied, Free plan adapted):** `mcp-rate-limit` ativada com 50 req / 10s per IP, Action Block, Duration 10s. Burst smoke test (~21:58Z): 120 requests rapid loop sem auth retornou exatamente 50 × HTTP 401 (primeiros, dentro do window) + 70 × HTTP 429 (rate-limited). 429 Ray IDs sample: `9fe7a4903c0c151e-RIC`, `9fe7a490afc97bea-RIC`, `9fe7a4912df87bf3-RIC`. Sanity: `Claude-User/1.0` UA continua passando normalmente (HTTP/2 401 + WWW-Authenticate, Ray `9fe7a4dd7fed6ac4-RIC`).

**Evidência completa:** `docs/audit/P162_GAP_OPPORTUNITY_LOG.md` item #40

## Cross-references

- `docs/audit/P162_GAP_OPPORTUNITY_LOG.md` item #40 (evidência completa, 7 retests)
- `docs/audit/P201_MCP_ARCHITECTURE_AUDIT.md` §3.3 (audit p201)
- `docs/MCP_SETUP_GUIDE.md` (client-facing guide, link de volta para aqui)
- `docs/GOVERNANCE_CHANGELOG.md` GC entry (decisão registrada)
- CLAUDE.md decision #2 (custom domain vs `.workers.dev` BIC) — esta rule cobre o BIC residual da custom domain
- `.claude/rules/mcp.md` — pre-deploy + smoke após deploy
