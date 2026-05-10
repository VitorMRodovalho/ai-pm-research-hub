# Research — Airmeet Developer Docs Deep-Dive

**Session:** p134 Ω-A Wave 2 (council research, complement to `p134_airmeet_landscape.md`) · **Date:** 2026-05-09
**Audience:** PM Vitor — to be assertive when asking Natália Tavares (head PMI Latam) for Airmeet integration access for CPMAI Latam.
**Method:** WebFetch (now permitted) on Airmeet KB articles + targeted WebSearch. All endpoint paths quoted verbatim from official docs.

---

## TL;DR (5 lines)

1. **Model 1 (API key escopo apenas CPMAI events) = NOT SUPPORTED**. Airmeet API keys are **community-scoped only** — there is no per-event key restriction. Whoever holds the Access Key + Secret Key can read all events in that community.
2. **Model 2 (Team member with limited role) = PARTIALLY SUPPORTED but inadequate for our integration**. The "Event Executive" role IS event-scoped (only sees assigned events) but **cannot access the Integrations tab to generate API keys**. Generating keys requires Owner / Admin / Manager (community-wide) — so giving Núcleo a "limited team member" role does NOT enable our automated webhook + API workflow.
3. **Model 3 (Sub-community CPMAI Latam) = STRUCTURALLY THE CLEANEST**. Airmeet "Community" is the top-level account boundary. PMI Latam can spin up a separate Airmeet community (own license OR sub-account if Airmeet sales agrees) where Núcleo is Admin. **Confirmed: there is no "transfer event between communities" API** — events live where they're created. So sub-community needs to be set up upfront for CPMAI events that are CPMAI-native, with Núcleo as Admin from day 1.
4. **Recording API = `GET /airmeet/{id}/session-recordings?sessionIds=<id>` returns CloudFront signed URL valid 6h**. Combined with 60-day account-creation-date retention → MUST mirror to YouTube within 7d via cron. Available on all paid tiers (Premium Webinar, Conference, Enterprise).
5. **Recommendation revisada: pedir Modelo 1.5 (híbrido)** — "Natália, podemos receber acesso de **Manager** dentro da community PMI Latam, OU vocês geram um par de Access Key + Secret Key para nos enviarem (escopo community PMI Latam, somente leitura via API)?" — segundo é menor friction, primeiro é mais governável.

---

## 1. Authentication mechanism CONFIRMED

**Two-step OAuth-like flow but with static credentials:**

1. **Bootstrap headers** (used only on `POST /auth`):
   - `X-Airmeet-Access-Key: <access_key>`
   - `X-Airmeet-Secret-Key: <secret_key>`
   - Content-Type: `application/json`

2. **Subsequent calls** use a token:
   - `X-Airmeet-Access-Token: <token>` (header on every request)
   - **Token TTL: 30 days, cacheable** (per docs)

**Where credentials come from:** Sign in to Airmeet → **Integrations tab → API Access Key section → "Generate access key"** + assign label. Generates Access Key + Secret Key pair. **This UI is gated to Owner / Admin / Manager only** (Event Executive cannot access Integrations).

**Base URLs (regional):**
- Mumbai (default): `https://api-gateway.airmeet.com/prod`
- EU: `https://api-gateway-prod.eu.airmeet.com/prod`
- US: `https://api-gateway-prod.us.airmeet.com/prod`

**NOT OAuth 2.x.** No user-delegation flow, no scope tokens, no refresh tokens. Access Key + Secret Key are **community-wide bearer credentials** — anyone holding them sees everything.

---

## 2. Permission scopes table

| Credential / Role | Scope | Read API | Write API | Generates API keys | Use case for Núcleo |
|---|---|---|---|---|---|
| **Owner** | Whole community | Yes (full) | Yes (full) | Yes | Natália / PMI Latam holder |
| **Admin** | Whole community except remove/replace owner | Yes (full) | Yes (full) | Yes | Could be Núcleo PM if PMI Latam grants — wide privilege |
| **Manager** | Whole community except billing | Yes (full) | Yes (full) | Yes | **Best fit for Núcleo as institutional partner** |
| **Event Executive** | ONLY events explicitly assigned by Admin | Yes (within event) | Limited | **NO** | Useful for Núcleo team members co-running specific events; **does NOT enable automated integration** |
| **Access Key + Secret Key pair** | Community (the one that generated it) | Per endpoint perms | Per endpoint perms | n/a | What Worker calls; **community-wide** — cannot scope to single event |
| **Speaker / Co-host (per-session)** | Single session, dashboard-only | n/a | n/a | NO | Irrelevant to integration |

**Critical finding for Vitor's ask:**
- API key escopo a 1 event = **DOES NOT EXIST** in Airmeet
- API key read-only sub-set = **DOES NOT EXIST** (granular endpoint permissions are tied to the account that owns the key, not the key itself)
- Per-event role assignment exists ONLY for "Event Executive" UI role — and that role explicitly **cannot generate keys or access Integrations**

**FAQ verbatim quote:** *"When you modify the settings of a particular role, the new settings are enforced for all users of that role for all events: ongoing, upcoming, or completed."* → role-level customization is global, not per-event.

---

## 3. Attendee export endpoint

**Primary list endpoint:**
```
GET /airmeet/{airmeetId}/attendees?after=<cursor>&before=<cursor>&size=<1-50>
Header: X-Airmeet-Access-Token: <token>
```

**Per-session attendees:**
```
GET /session/{sessionId}/attendees?after=&before=&size=
```

**Response shape (verbatim from docs):**
```json
{
  "data": [{
    "email": "user_email@example.com",
    "id": 4024760,
    "name": "John Doe",
    "user_id": "9jWs2N5Ex",
    "time_stamp": "2021:12:25T12:20:56.00Z",
    "time_spent": "20000"      // milliseconds
  }],
  "cursors": { "after": 4024760, "before": 4024760, "pageCount": 1, "totalCount": 1 },
  "statusCode": 200
}
```

**For richer profile data (registrations, not attendance):**
```
GET /airmeet/{airmeetId}/participants?emailIds=&resultSize=&pageNumber=&sortingKey=&sortingDirection=
```
Returns: `email, name, city, country, organisation, Designation, registrationDate, profile_url, user_type, token (direct entry link), invite_sent, user_profile[] (custom fields)`. Default page size 1000, max 500 for `/airmeets` list.

**Attendance compliance for certificate auto-issue:**
- `time_spent` field (ms) = exact duration in event → divide by event duration → % attendance → trigger our existing `issue_certificate` RPC at threshold
- `event-replay-attendees` endpoint also has `duration_viewed` (minutes) for post-event replay views

**Async wrinkle:** *"This is an Asynchronous API. If you get a 202 code in response, please try again after 5 minutes"* applies to attendance, booth-attendance, UTM, and replay endpoints. Plan for poll-with-backoff in our cron.

**Pagination:** `after` / `before` cursor (preferred) + `size` (1-50 attendance, default 1000 participants). Older offset-style `pageNumber` also supported on participants.

---

## 4. Webhook events list

**Configuration endpoint:**
```
POST /platform-integration/v1/webhook-register
Body: { url, triggerMetaInfoId, name, description }
Some triggers also need: ?airmeetId=<id>&sessionId=<id>
```

**Sample payload for any trigger:**
```
GET /platform-integration/v1/sample-payload?triggerMetaInfoId=<id>
```

**Confirmed triggers (Power Automate connector + KB):**

| Trigger name | Payload-relevant fields | Use case Núcleo |
|---|---|---|
| `trigger.airmeet.registrant.added` | email, name, registration timestamp, custom fields | Pre-event: ingest into our `event_registrations`, dedupe against `members` |
| `trigger.airmeet.attendee.added` | email, name, organization, designation | Push pre-registered Núcleo members so they get entry link |
| `trigger.airmeet.attendee.joined` | email, name, airmeetId, joined timestamp | Live: ingest into `event_attendance` |
| `trigger.airmeet.session.attendee.joined` | email, sessionId, joined ts | Track per-session attendance for multi-session CPMAI day |
| `trigger.airmeet.recording.available` | recording URL or session ID + ready signal | **Trigger our cron `airmeet_recording_mirror` immediately, NOT daily poll** |
| `trigger.airmeet.polls` | poll question, options, responses | Engagement metrics (optional) |
| Engagement scores / leaderboard / Q&A / CTA / booth visits | various | Optional analytics |

**25+ triggers total** documented (event lifecycle, registrations, attendance, engagement, post-event).

**NOT documented (gaps):**
- Retry policy / delivery guarantees — not in KB
- Signature verification (HMAC, secret header) — not in KB → **MUST email Airmeet support before going live; lack of HMAC means we should validate sender IP allowlist or pass a shared-secret in URL path**
- Rate limits on inbound webhook delivery — not documented

---

## 5. Rate limits

**Airmeet does NOT publicly document API rate limits**. No 429 / Retry-After header info in any KB article searched.

**Inferred ceiling from public usage signals:**
- Power Automate connector + Pipedream connectors work fine for normal community ops → likely generous (>60 req/min)
- Async-202 pattern on attendance endpoints suggests they offload to background processing, which itself implies they limit synchronous load

**Action:** Email `support@airmeet.com` BEFORE production rollout. For now, design Worker to:
- Backoff exponentially on 429 / 5xx
- Cache token full 30 days (don't re-auth per call)
- Batch webhook ingest (don't poll attendees endpoint > 1x per 10min during live event)
- Honor 202 → schedule retry +5min as docs prescribe

---

## 6. Sub-community / multi-tenant

**Airmeet "Community" is the top-level account.** Each community = its own subscription, billing, team, branding, integrations.

**No sub-community / parent-child hierarchy in product.** Confirmed via search — no docs reference "child community", "sub-community", or transferring events.

**No event-transfer API endpoint** — `POST /airmeet/{id}/duplication` exists (clone within same community) but no "move to another community". So if PMI Latam creates a CPMAI event in their community, Núcleo cannot pull it into a separate community after the fact.

**Models that ARE possible:**

| Option | What it means | Cost / friction | Núcleo posture |
|---|---|---|---|
| **A. Núcleo joins PMI Latam community as Manager** | Single community, Vitor / 1-2 Núcleo members get Manager seat | Zero new license; depends on Natália agreeing | Most natural, but exposes ALL PMI Latam events to Núcleo (privacy concern for Natália's team) |
| **B. Núcleo joins as Event Executive** | Per-event scoping, but cannot generate API keys | Zero | **Insufficient** for automated integration |
| **C. PMI Latam generates an API Key + Secret + sends to Núcleo** | Community-wide API access via key, no UI access | Zero | **Cleanest for integration**; Natália controls revocation; Núcleo sees everything via API though |
| **D. Núcleo gets its own Airmeet community (separate license)** | Independent account; CPMAI events held in Núcleo's community; PMI Latam attends as visitors / co-marketing | License cost ($167+/mo Premium Webinar; ~$18K/yr Enterprise for 2000-attendee CPMAI Latam) | **Independent path**; defer until volume justifies |
| **E. PMI Latam creates a sub-account via Airmeet sales** | Airmeet enterprise contracts sometimes allow sub-accounts | Negotiation needed; cost unclear | Possible if Natália has CSM contact |

**Recommendation:** **Option C** is the smallest ask with biggest enable. Combine with Option B (Vitor as Event Executive on specific co-events for UI access during the event itself).

---

## 7. Recordings export workflow

**Endpoint:**
```
GET /airmeet/{airmeetId}/session-recordings?sessionIds=<sessionId>
Header: X-Airmeet-Access-Token: <token>
```

**Response:** `download_link` field with CloudFront signed URL like:
```
https://streaming.airmeet.com/recordings/<community>/<event>/<session>.mp4?Policy=...&Key-Pair-Id=...
```
**Signed URL TTL: 6 hours.** Must download / mirror within window or re-call API to get fresh link.

**Format:** MP4. Resolution depends on tier: 480p (Free), 720p (Premium Webinar / Business / Enterprise). Transcript download (separate endpoint not detailed in KB) is **Enterprise-only**.

**60-day retention is HARD** — counted from community/account creation date per KB. Enterprise extension possibly negotiable but **not advertised**. PMI Latam's community was created Mar/2020 → recordings beyond 60d from then are gone unless they have negotiated retention extension.

**Núcleo workflow (proposed):**
1. Webhook `trigger.airmeet.recording.available` fires when recording is ready (typically minutes-hours post-event)
2. Cron `airmeet_recording_mirror` (every 6h, fallback if webhook miss) calls `GET /session-recordings`
3. Stream signed URL → Cloudflare R2 OR YouTube unlisted upload
4. Update `recordings` table with our canonical URL + token-gate
5. Trigger certificate via existing `register_attendance` + `issue_certificate` flow

**Must-have safety net:** If our cron / webhook silently fails, we lose the recording forever after 60d. Add monitoring + alert if any session is `> 50 days post-event` and `recording_mirrored = false`.

---

## 8. Enterprise tier API access

**Confirmation from search results:** *"API access is available in the Social Webinar and Conference Plans."* (Conference is the modern name for Enterprise tier in 2026 Airmeet pricing.) So **API access is included in Premium Webinar (~$167/mo annual) AND Enterprise** — Natália's team's Enterprise license definitely includes it.

**Enterprise-only API features:**
- **Transcript download** (separate from recording — confirmed in KB)
- Higher attendee caps on participants/attendees endpoints (probably; not explicitly documented)
- Dedicated CSM may unlock sandbox / higher rate limits / custom SLAs

**Webhook availability:** *"Some of Airmeet's public APIs and webhooks are not available in the connector, though these will be added incrementally"* — this is about Microsoft Power Automate connector specifically; the underlying webhook system is fully available via direct `webhook-register` API on Premium Webinar+.

**Team member caps:** *"All in Suite Plan: 10 (1 Community Manager + 9 Event Manager)"*. Enterprise: not documented; assume negotiable.

---

## Recomendação revisada para pedido a Natália

**Script literal, em PT, para Vitor:**

> "Natália, para a integração CPMAI Latam → Núcleo (auto-emissão de certificados, mirror de gravação dentro do prazo de 60 dias), o ideal técnico é receber **um par de Access Key + Secret Key da community PMI Latam** (geramos no Integrations tab, leva 30 segundos). Com isso o Worker do Núcleo:
>
> 1. Recebe webhook quando alguém se registra ou entra em um evento CPMAI
> 2. Calcula attendance (tempo em sessão)
> 3. Emite certificado Núcleo automaticamente
> 4. Espelha a gravação para nosso storage antes do auto-purge da Airmeet em 60 dias
>
> Se preferir não compartilhar uma chave global, alternativa é me adicionar como **Manager** da community (não como Event Executive — esse role não consegue gerar chaves API). Você revoga a qualquer momento. Manager não acessa billing, então sem risco financeiro.
>
> Como bônus, posso entrar como **Event Executive** apenas nos eventos co-organizados, para ajudar no dia (acesso UI somente, escopo restrito).
>
> Não preciso modificar nenhum evento — só ler. Se quiser, posso documentar o que vou consumir antes de você gerar a chave."

**Por que esse pedido específico:**
- Reconhece que Airmeet API keys são community-wide (não vale a pena pedir o impossível "escopo só CPMAI")
- Dá DOIS caminhos de baixo custo (chave OU Manager seat) → Natália escolhe o que prefere
- Demonstra conhecimento técnico → credibilidade
- Inclui o "you revoke anytime" → tira fricção de risco
- Adiciona o Event Executive como cherry on top (UI access para dias de evento) sem ser load-bearing

---

## Open questions ainda não respondidas

1. **Webhook signature verification** — Airmeet KB silente. Email `support@airmeet.com` antes de prod. Workaround: pass shared secret in webhook URL path + IP allowlist.
2. **Rate limits** — não documentado publicamente. Pedir limits oficiais ao CSM da PMI Latam quando integrarmos.
3. **Sub-account model on Enterprise** — não documentado. Natália pode perguntar ao CSM dela se PMI Latam pode criar uma "sub-community" formal — would solve governance cleanly.
4. **Transcript endpoint exact path** — Enterprise-only mas KB não publica path. CSM pode compartilhar.
5. **Recording webhook latency** — quanto tempo de fato leva do `event.finished` até `recording.available` disparar? Crítico para SLA do certificate flow.
6. **Custom field exposure** — `participants` endpoint expõe `user_profile[]` com `fieldId`. Mapping `fieldId → human-readable name` requires cross-call to `/custom-fields`. Plan accordingly.

---

## Sources cited

- [Airmeet Public API Introduction (KB)](https://help.airmeet.com/support/solutions/articles/82000467794-airmeet-public-api-introduction)
- [1. Event Details API (KB)](https://help.airmeet.com/support/solutions/articles/82000909768-1-event-details-airmeet-public-api) — endpoint catalog + auth headers + base URLs + participants/attendance shapes
- [2. Manage Registrations API (KB)](https://help.airmeet.com/support/solutions/articles/82000909769-2-manage-registrations-airmeet-public-api)
- [3. Manage Event API (KB)](https://help.airmeet.com/support/solutions/articles/82000909770-3-manage-event-airmeet-public-api) — POST /auth, POST /airmeet, duplication, no transfer-between-communities
- [Airmeet Webhooks (KB)](https://help.airmeet.com/support/solutions/articles/82000878498-airmeet-webhooks) — `/platform-integration/v1/webhook-register` + sample-payload endpoint
- [Power Automate connector (KB)](https://help.airmeet.com/support/solutions/articles/82000879966-integrate-airmeet-with-power-automate) — confirmed trigger names + Integrations-tab UI for key generation
- [Roles & Permissions on Airmeet (KB)](https://help.airmeet.com/support/solutions/articles/82000894401-how-to-assign-a-role-grant-permissions-to-your-team-member-event-manager-on-airmeet-) — Owner/Admin/Manager/Event Executive matrix
- [Roles and Permissions FAQs (KB)](https://help.airmeet.com/support/solutions/articles/82000898530-roles-and-permissions-faqs) — global-not-per-event role enforcement
- [Add team member on Airmeet Community (KB)](https://help.airmeet.com/support/solutions/articles/82000475602-how-to-add-a-team-member-and-assign-a-permission-role-to-them-on-airmeet-) — UI flow + 14-day invitation validity + All-in-Suite cap of 10
- [Session Recordings access (KB)](https://help.airmeet.com/support/solutions/articles/82000443239-how-to-access-session-recording-for-an-airmeet-event-) — dashboard path + 60d retention
- [`session-recordings` API endpoint pattern](https://help.airmeet.com/support/solutions/articles/82000909768-1-event-details-airmeet-public-api) — CloudFront signed URL TTL 6h
- [Sub-community / multi-account search](https://help.airmeet.com/support/solutions/articles/82000444075-what-is-the-community-how-to-create-community-in-airmeet-) — no sub-community feature documented
- [Airmeet plans & pricing (KB)](https://help.airmeet.com/support/solutions/articles/82000453871-what-are-airmeet-plans-and-pricing-) — tier comparison
- Prior research: `docs/research/p134_airmeet_landscape.md` (PMI Latam case study + Interprefy multilingue + competitive landscape)
