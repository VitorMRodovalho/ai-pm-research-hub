# SPEC-280.A — Connector Store Readiness Matrix

**Date:** 2026-05-22  
**Status:** Draft accepted with PM decisions — ready for implementation-spec handoff  
**Parent:** GitHub #280 — Semantic MCP Gateway + internal capability registry  
**Child issue:** GitHub #283 — Connector store readiness matrix for Semantic MCP Gateway

## Decision

The Semantic MCP Gateway must be designed from day zero against the most restrictive requirements of the major AI connector and app ecosystems, even if official publication is a later phase.

This is a design-quality gate, not a marketing or packaging task. The gateway should not be optimized only to unblock Perplexity. It should be suitable for future review by OpenAI, Anthropic, and other MCP-capable hosts.

## Product Principle

Do not frame the work as a reduced catalog. Frame it as:

> Public semantic contract over a full internal capability registry.

The current 299-tool catalog remains valuable as an internal capability inventory and audit surface. It should not remain the default public discovery surface for every external connector.

## Source Map

| Ecosystem | Official sources used | Publication posture |
|---|---|---|
| OpenAI / ChatGPT | Apps SDK submission docs, Apps SDK security/privacy, MCP for ChatGPT Apps/API, Developer mode docs | Public app directory submission exists for verified developers |
| Anthropic / Claude | Connectors Directory, submission guide, pre-submission checklist, connector testing docs | Public connector directory submission exists |
| Perplexity | Custom Remote Connectors help center | Custom/org connector path documented; public third-party store submission not documented |
| xAI / Grok | Connectors, Connector Catalog, Remote MCP Tools docs | Catalog exists; BYO remote MCP/API path documented; public catalog submission not documented |
| Manus | Integrations overview, Custom MCP Servers docs | Prebuilt connectors and custom MCP supported; public third-party store submission not documented |
| MCP spec | 2025-06-18 tools and authorization specs | Canonical protocol baseline |

## Readiness Matrix

| Requirement area | OpenAI / ChatGPT | Anthropic / Claude | Perplexity | xAI / Grok | Manus | Gateway rule |
|---|---|---|---|---|---|---|
| Store/directory | ChatGPT Apps Directory submission via OpenAI Platform Dashboard; requires app metadata, MCP/tool info, screenshots, privacy URL, test prompts/responses, localization info. | Connectors Directory accepts remote MCP servers, desktop extensions, and MCP Apps; review standards apply. | Custom Remote Connectors only in public docs; no public store submission path found. | Connector Catalog exists for preconfigured connectors; remote MCP tools documented for API; no public catalog submission path found. | Prebuilt MCP connectors plus Custom MCP Servers; no public third-party store submission path found. | Build as if store-reviewed, but document which ecosystems are custom-only today. |
| Transport | ChatGPT developer mode supports SSE and streaming/Streamable HTTP for MCP apps. | Remote MCP connectors use the same runtime for custom and directory connectors; test custom before submission. | User must explicitly choose `Streamable HTTP` or `SSE`; HTTPS required. | Remote MCP tools support remote servers via API; connector catalog is separate. | HTTPS endpoint required for custom MCP server. | `/mcp` public default must be Streamable HTTP and HTTPS; SSE compatibility should be documented or explicitly unsupported. |
| Auth | OAuth, no auth, and mixed auth supported in developer mode; DCR/CIMD options exist. App submission requires OAuth details if selected. | Submission asks for auth type and connection details. Test account required. OAuth 2.0 expected if auth is required. | OAuth, API key, or none. | Built-in/catalog connectors use OAuth; remote MCP API can use connector/auth config. | API key, bearer token, OAuth or other secure credentials; do not expose credentials in URLs/logs. | OAuth 2.1 remains primary. Refresh must be stable. Test account must not require MFA/email/SMS steps during review. |
| Tool design | Developer mode docs recommend action-oriented tool names/descriptions, parameter descriptions, enums, and disambiguation. Write actions require confirmation; `readOnlyHint` is respected. | Review criteria require separate read/write tools, tool annotations, short names, narrow accurate descriptions, no prompt-injection patterns. | Short connector description; no detailed public review criteria. | API supports limiting allowed tools; catalog docs emphasize OAuth-ready connectors. | Tools should be focused, clear, and return graceful errors. | Semantic tools must be narrow enough for safe selection but broad enough to orchestrate internal capabilities. Separate read/write/destructive behavior. |
| Functional quality | Review can reject apps when MCP URL/test credentials fail; test prompts/responses required. | Reviewers run functional tests of every tool and policy scan. Generic errors fail review. | Connector must retrieve tools and complete auth. | Remote MCP should be callable from API/client. | Manus verifies it can communicate with server and retrieve available tools. | Every public semantic tool must have deterministic smoke tests, valid sample params, bounded responses, and actionable errors. |
| Privacy/compliance | Submission requires company and privacy policy URLs. Apps SDK has Security & Privacy guidance. | Submission requires data/compliance details, privacy policy, docs/support, allowed links, and security/functionality maintenance. | Custom connector includes risk acknowledgement. | Data/privacy docs exist; catalog path not public. | Manus says integrations use secure auth and only access explicitly authorized data to complete requested tasks. | Publish a connector-specific data handling section before store submission. No unnecessary PII in semantic responses. |
| Test account | OpenAI review needs demo/test credentials that work without extra configuration; common rejection if reviewers cannot connect. | Submission requires test account and setup instructions for a reviewer unfamiliar with the service. | User self-tests connector after adding. | No public store review test-account requirement found. | User tests connection after adding. | Create a reviewer account/org with seeded non-sensitive data and a step-by-step review script. |
| Docs/support | OpenAI submission requires description, privacy URL, screenshots, test prompts/responses, localization. | Submission needs public docs, support channel, logo/favicon/assets, allowed link URIs if opening links. | Connector name, URL, auth, transport, icon. | Catalog docs are user-facing; no submission checklist found. | Server name, URL, auth details; monitoring and maintenance expected. | `/docs/mcp`, support email, privacy/data handling, and revised blog must ship before official submission. |
| Unsupported / policy risks | Apps must meet safety/privacy/functionality guidelines; updates require resubmission. | Unsupported cases include money/crypto transfer and some AI media generation; hidden/encoded/system-overriding instructions are rejected. | Custom connector risk acknowledged by user. | No public third-party review criteria found. | Security, authz, rate limiting, monitoring, performance. | Avoid hidden instructions, generic errors, unbounded exports, destructive actions without confirmation, and raw internal implementation leakage. |

## Most Restrictive Wins Checklist

The Semantic MCP Gateway is not ready for implementation until these rules are accepted.

### Tool Surface

- Public `/mcp` exposes semantic tools, not the 299 internal implementation catalog.
- Tool names are short, action-oriented, stable, and domain-scoped where useful.
- Descriptions describe what the tool does and when to use it. They must not instruct the model to override behavior, promote the product, or contain hidden/encoded instructions.
- Similar operations are disambiguated by name and description.
- Read and write semantics are separated. Destructive actions are explicit and gated.
- Public tools include annotations where supported, especially read-only hints.
- The internal 299-tool matrix remains available as an audit artifact, not as the default public discovery contract.

### Schema

- Input schemas are strict, shallow where possible, and avoid open-ended `additionalProperties: {}` on public semantic tools unless justified.
- Required fields are explicit.
- Enums are used for bounded option sets.
- Parameter descriptions are present and short.
- Output envelopes are stable by domain: `{ ok, data, warnings, next_actions, audit }` or an equivalent accepted pattern.
- Responses are bounded. No tool should return a full database dump when the user asked for a summary.

### Auth And Sessions

- HTTPS only.
- OAuth 2.1 remains the primary auth path.
- Dynamic client registration and discovery metadata must remain valid where used.
- Token refresh must be stable for normal connector usage.
- Reviewer/test accounts must not require MFA, SMS, email verification, corporate network access, or manual admin action during review.
- Public semantic tools must enforce RLS/RPC/capability gates server-side; client-side tool visibility is not authorization.

### Safety And Privacy

- No unnecessary PII in public semantic responses.
- Write/destructive operations require confirmation or two-step preview/execute semantics.
- All public semantic tools return actionable errors. Generic `Internal Server Error` or silent empty failures are not acceptable.
- Logs must support audit without storing secrets, raw credentials, or unnecessary conversation data.
- Connector privacy/data handling docs must explicitly state what data is read, written, logged, retained, and who can access it.

### Reviewability

- Each public semantic tool has:
  - sample successful call;
  - sample invalid input call;
  - expected error shape;
  - required permission;
  - PII classification;
  - read/write/destructive classification;
  - owner domain.
- A review account with seeded data exists.
- `/docs/mcp` explains the semantic gateway model.
- The `mcp-server-launch` blog no longer implies external clients should ingest the 299-tool implementation catalog.
- `docs/MCP_SETUP_GUIDE.md` distinguishes public semantic mode from internal/dev full-catalog mode.

## Platform-Specific Readiness Notes

### OpenAI / ChatGPT

OpenAI now frames connectors as Apps. Apps SDK submission requires an MCP server/app package plus review through the OpenAI Platform Dashboard. The submission form expects app name, logo, description, company and privacy policy URLs, MCP/tool information, screenshots, test prompts and responses, and localization information.

Design implications:

- Treat ChatGPT as an app review surface, not just a raw MCP client.
- Prepare screenshots/test prompts even if the first Núcleo version is data-only.
- Use `readOnlyHint` and confirmation behavior correctly for write tools.
- Keep descriptions action-oriented and disambiguating.
- Provide a no-friction reviewer account.

### Anthropic / Claude

Claude has the clearest public MCP directory process. Directory connectors are reviewed for security, reliability, and compatibility. Anthropic reviewers test each tool and scan for policy compliance. Their checklist explicitly calls out short tool names, narrow descriptions, annotations, separation of read/write tools, avoiding prompt-injection patterns, actionable errors, and exercising every tool before submission.

Design implications:

- Anthropic review criteria should heavily influence the baseline gateway quality bar.
- Claude custom connector testing is the staging path because custom and directory connectors use the same runtime.
- Every public semantic tool must be testable with valid params.

### Perplexity

Perplexity public docs focus on Custom Remote Connectors. They require HTTPS MCP URL, auth choice, and explicit transport selection between Streamable HTTP and SSE. No public third-party store submission process was found.

Design implications:

- Perplexity remains the immediate compatibility smoke target.
- Because the current 299-tool `tools/list` payload fails in Perplexity, the semantic gateway should be validated here early.
- The docs must clearly say `Transport = Streamable HTTP` for `/mcp`.

### xAI / Grok

Grok has built-in connectors and a Connector Catalog. xAI also documents Remote MCP Tools for API use. Public docs do not show a third-party catalog submission process.

Design implications:

- Design for an `allowed_tools` style model: the public semantic surface should be easy to allowlist.
- OAuth and low-configuration connector behavior matter for future catalog readiness.
- Treat xAI as custom/API validation first, catalog later.

### Manus

Manus supports prebuilt MCP Connectors and Custom MCP Servers. Custom servers must be HTTPS endpoints with secure auth, tool definitions, request handlers, and connection testing. Manus docs emphasize focused tools, clear descriptions, meaningful errors, performance, timeouts, logging, and monitoring.

Design implications:

- Manus validates the same core direction: fewer focused semantic tools with reliable orchestration.
- Long-running operations should return task IDs/status tools instead of blocking.
- Monitoring and graceful errors are store-readiness requirements, not optional polish.

## Required Public Docs Before Submission

| Document / page | Purpose | Owner lane |
|---|---|---|
| `/docs/mcp` | Public semantic gateway docs, connector setup, capability overview, link to internal matrix | Governance + Frontend |
| `/blog/mcp-server-launch` | Product narrative: semantic gateway over internal capability registry | Governance |
| `docs/MCP_SETUP_GUIDE.md` | Operational setup by client, public vs internal/dev modes | Governance / MCP |
| Privacy/data handling page or section | Connector-specific data access, logging, retention, PII posture | Governance / Security |
| Reviewer runbook | Test account, sample prompts, expected outputs, known limitations | Governance / QA |
| Internal matrix docs | Keep 299-tool registry auditable without exposing it as public discovery | MCP / QA |

## Gate For #280

#280 should not move into implementation design until this spec is reviewed and accepted. The implementation spec must explicitly map every proposed semantic tool to:

- user intent;
- internal capability/RPC/tool dependencies;
- required permission;
- read/write/destructive classification;
- PII classification;
- expected response envelope;
- sample valid and invalid calls;
- platform compatibility risks.

## PM Decisions — 2026-05-22

### Endpoint Migration

Adopt a bridge-first migration:

- keep `/mcp` as the current full-catalog endpoint during the transition;
- introduce `/mcp/semantic` as the public semantic gateway for Perplexity and new connector validation;
- migrate `/mcp` to semantic-first only after metrics, client smoke tests, public docs, and user communication are complete;
- move the full technical catalog behind an explicit internal/dev mode such as `/mcp/full` or `?profile=full` when the migration is ready.

Rationale: existing Claude/ChatGPT/Cursor/dev consumers may rely on `/mcp` today. A bridge gives compatibility proof and rollback without breaking active users.

### First-Wave Semantic Domains

First-wave semantic tools should be selected by combining:

- `mcp_usage_log` usage data: most-used tools, success/failure rate, latency, user count;
- Pareto semantic consolidation: intents that collapse the largest number of technical tools;
- operational priority: selection, profile, knowledge, governance, boards/operations, reporting;
- review/store readiness: simple schemas, bounded responses, low PII exposure, read-only/contextual operations first.

Initial candidate semantic tools:

- `get_my_context`
- `search_nucleo_knowledge`
- `get_selection_workspace`
- `get_candidate_context`
- `get_governance_context`
- `get_operational_status`
- `get_board_or_initiative_context`
- `run_nucleo_report`

These are candidates, not final names. The #280 implementation spec must validate them against usage data and review constraints.

### App Surface

Start as data/tool-only. Do not add MCP App UI widgets in the first wave.

Rationale: data/tool-only has lower review, security, CSP, UX, and maintenance surface. UI components can be a later phase after semantic tool adoption and compatibility are proven.

### Reviewer Account And Dataset

Prepare a reviewer/demo account with seeded non-sensitive data and limited permissions.

Preferred shape:

- demo or masked organization/scope;
- fictitious members;
- sample events;
- sample boards/cards;
- sample selection candidates;
- public/low-risk knowledge items;
- public/low-risk governance docs;
- no real PII.

If production cannot safely provide this isolation, use a staging/demo environment. The reviewer flow must still match production behavior closely enough to avoid false confidence.

### Support Contacts

Use:

- public/institutional support: `nucleoia@pmigo.org.br`;
- technical/developer owner: `vitor@vitormr.dev`.

Store/directory submissions and public docs should prefer the institutional address for continuity. Technical owner details can be used where platforms ask for developer contact.

## Remaining Open Questions

1. What exact tool names and response envelopes should first-wave semantic tools use?
2. Which internal capabilities/RPCs map to each semantic tool?
3. What query should define the usage/Pareto baseline from `mcp_usage_log`?
4. Should `/mcp/semantic` live in the Worker proxy, the Supabase MCP server, or both?
5. What is the exact migration/communication threshold for making `/mcp` semantic-first?

## References

- OpenAI Apps SDK submission: https://developers.openai.com/apps-sdk/deploy/submission
- OpenAI MCP for ChatGPT Apps/API: https://developers.openai.com/api/docs/mcp
- OpenAI ChatGPT Developer mode: https://developers.openai.com/api/docs/guides/developer-mode
- OpenAI Apps SDK Security & Privacy: https://developers.openai.com/apps-sdk/guides/security-privacy
- Anthropic Connectors Directory submission: https://claude.com/docs/connectors/building/submission
- Anthropic pre-submission checklist: https://claude.com/docs/connectors/building/review-criteria
- Anthropic connector testing: https://claude.com/docs/connectors/building/testing
- Perplexity Custom Remote Connectors: https://www.perplexity.ai/help-center/en/articles/13915507-adding-custom-remote-connectors
- xAI Grok Connectors: https://docs.x.ai/grok/connectors
- xAI Connector Catalog: https://docs.x.ai/grok/connectors/catalog
- xAI Remote MCP Tools: https://docs.x.ai/developers/tools/remote-mcp
- Manus Integrations: https://manus.im/docs/integrations/integrations
- Manus Custom MCP Servers: https://manus.im/docs/integrations/custom-mcp
- MCP Tools spec 2025-06-18: https://modelcontextprotocol.io/specification/2025-06-18/server/tools
- MCP Authorization spec 2025-06-18: https://modelcontextprotocol.io/specification/2025-06-18/basic/authorization
