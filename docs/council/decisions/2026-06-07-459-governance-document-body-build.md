# Decision — #459: expose governance_documents normative body via MCP (build, Option A)

- **Date:** 2026-06-07
- **Issue:** #459 (Expor corpo normativo de governance_documents via MCP — leitura)
- **Decider:** PM (Vitor) — decision loop per [[working-agreement-decision-process-2026-06-07]]
- **Role split:** council/grounding brought options; legal-counsel cleared the gate; I (PL/CTO) recommended; PM decided.
- **Supersedes the placeholder name** `get_governance_context` from `2026-06-07-mcp-wave2-get-operational-status.md` (that doc deferred #459 "to legal/RLS review before spec"). The precise tool is a document **body** read, so it ships as `get_governance_document_body` (a broad "governance context composite" was never the ask).

## Context (grounded live before options — never assumed)

Live queries this turn (prod `ldrfrvwhxsmgaabwmaik`):

| Signal | Value | Source |
|---|---|---|
| **Canonical body-reader RPC already exists** | `get_governance_document_reader(p_document_id uuid)` SECDEF — returns `current_version.content_html` + enforces the full visibility model inline (visibility_class matrix + `locked_at` hard-gate + status exclusion + #381 curator bypass). **Powers `/governance/document/[id]` today.** NOT MCP-wrapped. | `pg_proc.prosrc` (5336 chars) |
| Wrap proven end-to-end | Under a real member JWT (impersonation): Acordo **30993**, Termo **22517**, Adendo **14720** chars of real clause HTML returned | `get_governance_document_reader()` via `set_config('request.jwt.claims',…)` |
| Reader payload contract | returns `content_html`; **no** markdown, **no** `pdf_url`/`docusign`/`partner_entity_id` | `prosrc` LIKE checks |
| Body storage | `document_versions.content_html` (text NOT NULL; 42/42 populated); `content_markdown` null on **40/42** | `information_schema` + counts |
| Scale | 16 docs / 42 versions · max body **79557** chars (~20–26k tok) · avg 20053 | live counts |
| Visibility distribution | **16/16 = active_members** (status: 3 draft · 7 active · 6 under_review) | `governance_documents` |
| Precedent | `get_manual_section` + `get_wiki_page` already return full narrative bodies via MCP (authenticated + SECDEF) | index.ts |

## Legal gate (the council-imposed "legal/RLS review before spec")

**RLS half** — cleared by grounding: the new tool only replicates the visibility authority the member-facing web route already grants (same RPC).

**Legal half** — cleared by **legal-counsel: GO-com-condições** (parecer 2026-06-07). No PII in bodies; no rule forbids MCP exposure; the 3 CR-050 docs are legal instruments *under_review* but already readable by active members on the web. **5 mandatory guard-rails** (all in the build):
1. `ratification_status` + mandatory `caveat` when status ≠ `active`.
2. **MCP-channel visibility ceiling** `visibility_class IN ('public','active_members')` — tighter than the RPC's web authority; `admin_only`/`audit_restricted`/`legal_scoped` are never served via MCP even if the caller would pass the RPC gate.
3. Exclude `document_comments` (curation notes) — the reader never returns them; asserted in test.
4. Reinforced logging: `document_id` + `version_id` + `ratification_status` into `mcp_usage_log.response_summary`.
5. No-legal-advice + under_review disclaimer in the tool description.

## Options presented (PL/CTO)

Scope ladder (B ⊂ A ⊂ C), all wrapping the canonical reader + the 5 guard-rails:
- **A (Recommended)** — current body as sanitized **HTML + server-rendered Markdown + section anchors**. Full AC; serves the PMOGA "cite Cláusula 12.2 → draft MoU" use case.
- **B (Lean)** — HTML-only (defer MD/anchors). Smallest; the MCP consumer is an LLM that reads HTML fine.
- **C (Max)** — A + version-addressable history. Adds a NEW per-version gated read path (must NOT reuse `get_version_diff`'s weaker active-member-only gate). YAGNI for the current-text use case.

## Recommendation → A · Decision → **A**

PM chose **A**. Rationale (accepted, not re-litigated): anchors let the assistant jump to/quote the exact clause and clean Markdown pastes into a draft far better than TipTap HTML; version-history is unneeded for "read the current text" and forces the riskier per-version gate.

## Architecture (key call)

**All enrichment lives in the EF/MCP layer; the canonical RPC is untouched → no migration.** Because (a) legal placed the visibility *ceiling* at the MCP layer explicitly, (b) Markdown/anchors/caveat are LLM-consumer concerns, (c) not touching the legally-reviewed `get_governance_document_reader` = zero authority-regression risk + no PostgREST reload. EF-only build.

- New shared **pure module** `supabase/functions/nucleo-mcp/governance-html.mjs` (Deno-importable + Node-unit-testable, no DOMParser/turndown dep): `htmlToMarkdown` (targeted TipTap converter, entity-decode-last), `extractSectionAnchors` (mirrors `ClauseCommentDrawer` CLAUSE_REGEX, regex-based + h4), `sanitizeGovernanceHtml`, `ratificationCaveat`, `MCP_GOVERNANCE_VISIBLE_CLASSES`.
- New tool `get_governance_document_body(document_id)` wraps `get_governance_document_reader`; returns `{available, document:{…, ratification_status, caveat}, content_html, content_markdown, content_html_length, section_anchors}`; `available:false` (no body) for not-found/not-visible / channel-restricted / no-published-version (no existence oracle).
- `logUsage` extended with optional `responseSummary` → `log_mcp_usage.p_response_summary` (additive; the RPC already accepted it).
- Tool ↔ RPC name divergence recorded in `.claude/rules/mcp.md` alias map.

## Execution

- EF: `supabase/functions/nucleo-mcp/index.ts` (+import, +tool, logUsage extension, /health 307→308) + `governance-html.mjs` (new). **Deployed** (script 2.892MB; bundled the sibling .mjs). Smoke: /health 308, initialize 200, tools/list has the tool, runtime total 308 (no drift).
- Tests: `tests/contracts/459-governance-document-body.test.mjs` (35 — unit converter/anchors + static contract for all 5 guard-rails + council M1/M3/L1 + code-block/br/nested-list), registered in BOTH whitelists; 4 count-assertion tests bumped 307→308; matrix/manifest regenerated (312 flat). Full suite **3615/0/0** (DB-aware). `astro build` clean.
- No migration. No Worker deploy needed for the tool (the /docs/mcp catalog page refreshes on the next Worker build — manifest committed).
- PR: (filled at merge). 0 `--admin`.

## Council review (code-reviewer + security-engineer + converter adversarial verify)

- **Converter adversarial verify (me, on the 3 real bodies):** headings preserved (11→11, 3→3, 16→16), **0 residual HTML tags** in markdown, no script leak, anchors correct (Art. 1–9, Cláusula 1/2/15/16, 2.1/2.2.1, Preâmbulo). Re-verified after the council fixes — no regression.
- **code-reviewer:** 0 BLOCKER / 0 HIGH. logUsage extension confirmed safe (`log_mcp_usage` has `p_response_summary DEFAULT NULL`; ~300 callers send `null`). Surfaced the code-block path had no unit test — which exposed (during folding) that the stash token must survive `trim()`. **Folded in-PR:** NUL-escape (`\u0000`) sentinel + `replaceAll` for code-block restore; `<pre><code>` + `<br>` + nested-list unit tests; version fields `?? null`; `<br>`→soft-newline (the hard-break double-space is stripped by cleanup anyway).
- **security-engineer: GO-with-fixes.** **Folded in-PR:** **M1** restricted-class branch now returns `document: null` (no metadata fingerprint of a restricted doc via MCP); **M3** independent EF forward-defense `draft_not_locked` gate (the channel serves only LOCKED current versions, regardless of how the ceiling list evolves); **L1** `content_markdown`/`section_anchors` derive from `cleanHtml` (explicit sanitize-first contract); **L2 (partial)** `vbscript:` added to the URL-scheme strip. Confirmed: no body content in `mcp_usage_log`; anon ACL on the reader is fail-closed via active-member gate + the tool's `getMember` envelope.

## Follow-ups (filed)

- Live authenticated end-to-end call (real member OAuth token) not exercised this session — covered by: RPC body-return proof (impersonation) + 35 unit/static tests + converter run on the 3 real bodies. Verify opportunistically from an authenticated MCP-Claude session.
- code-reviewer/security follow-ups (non-blocking): nested-list proper indentation; `data:` URI handling for downstream HTML renderers; prompt-injection note (admin-authored bodies = accepted risk); optional `REVOKE EXECUTE … FROM anon` on `get_governance_document_reader` in a maintenance migration; `toolBlock()` end-sentinel robustness in the test.
- `/docs/mcp` public catalog reflects 308 only after the next Worker deploy (manifest committed; cosmetic lag).
- If #459 is ever extended to serve `legal_scoped`/version-history, that needs a fresh legal parecer + the per-version gate (do NOT reuse `get_version_diff`).
