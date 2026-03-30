# BACKLOG — AI & PM Research Hub
## Updated: 29 March 2026

---

## P0 — Bugs / Active Tech Debt

| # | Item | Est. | Status | Notes |
|---|------|------|--------|-------|
| 1 | Attendance cross-tribe | 1-2h | Monitoring | Retry pattern deployed (30×300ms). Intermittent — cannot reproduce reliably. Monitor. |
| 2 | 2 attendance corrections | — | ✅ Done | Guilherme + Gustavo confirmed present in DB |
| 3 | Migration repair 26/Mar | 5 min | ✅ Done (29/Mar) | All migrations synced |
| 4 | i18n server-side locale | — | ✅ Verified (29/Mar) | EN/ES resolve correctly server-side. Not a bug. |
| 5 | MCP connector Claude.ai | Sprint 5 | Paused | OAuth ✅, initialize ✅, tools/list ✅ (23 tools), protocolVersion 2025-11-25 ✅. Issue: Claude.ai shows "0 tools" — InMemoryTransport workaround doesn't implement full Streamable HTTP protocol. Fix: `WebStandardStreamableHTTPServerTransport` (exists in SDK but needs testing on Deno). SDK 1.28.0 Zod migration blocked by BOOT_ERROR (Node.js deps incompatible with Deno). Sprint 5: proper transport + runtime evaluation. |

---

## P1 — Ready to Execute (no blockers)

| # | Item | Est. | Status | Notes |
|---|------|------|--------|-------|
| 6 | S3.3 Custom PostHog events | 3-4h | Ready | 8 instrumentations: board_card_created/moved, webinar_viewed, blog_post_read, profile_updated, mcp_tool_called, certificate_issued, governance_cr_submitted |
| 7 | S3.2 Designation filter everywhere | 2-3h | Ready | Expand adoption filter to /admin/members, /admin/attendance, /teams |
| 8 | Phase 2 smoke-test.sh (GC-097) | 2h | Ready | Scripted QA gate layer 2 |
| 9 | pg_cron verification | — | ✅ Done (29/Mar) | 7 jobs active: credly, attendance, detractor, reminders, backup, archive, email |
| 10 | URL migration notice | Note | FYI | Débora + Marcos using legacy .pages.dev (redirect works) |

---

## P2 — Needs External Input / Decision

| # | Item | Blocker | Notes |
|---|------|---------|-------|
| 11 | Mario Trentim demo | 2026-04-03 10:00 ET | One-pager + demo script ready. Meet: wzh-tsmg-ven |
| 12 | Brantlee Underhill outreach | Post-Mario | PMI Staff AI/Innovation. linkedin.com/in/brantleeunderhill/ |
| 13 | nucleoia.pmigo.org.br CNAME | Waiting Ivan | HostGator DNS |
| 14 | Relatório C2→C3 | Deferred | Waiting Ivan to define needs |
| 15 | R3 Manual batch approve | Waiting Ivan | 29+ CRs pending approval |
| 16 | S2.3 Executive sponsor view | 5 sponsors no auth | Spec after auth onboarding |
| 17 | PMI-GO institutional page | Waiting Ivan | WordPress content sent |

---

## P3 — Sprint 3+ / Cycle 4

| # | Item | Est. | Notes |
|---|------|------|-------|
| 18 | Pre-onboarding gamification spec | 2h Chat | Candidate journey feature |
| 19 | Playwright e2e expansion | Cycle 4 | 8→30+ tests |
| 20 | Sustainability frontend | Pending | P6 |
| 21 | W107 Pilot #1 handler | Pending | — |
| 22 | BoardEngine polish | Pending | Spec in BOARD_ENGINE_SPEC.md, @dnd-kit |
| 23 | Admin modularization Phases 2-4 | Pending | Phase 1 done |
| 24 | Advisor: 10 Security Definer Views | Pending | — |
| 25 | legacy_tribes table cleanup | Low | G13 |
| 26 | Git history cleanup | Low | 29MB PPTX in git history (G16) |
| 27 | Co-managers member picker | Low | Webinar modal G10 |

---

## Frontend ↔ Backend Parity Gaps (audit 29/Mar)

RPCs with backend ready but no frontend surface. To be specced and implemented in grouped sprints.

| # | RPC | Current State | Recommended Frontend | Sprint |
|---|-----|---------------|---------------------|--------|
| F1 | `get_public_platform_stats` | Orphan — created but unused | Homepage `/` stats section (active members, tribes, events, retention) | S4 |
| F2 | Co-managers selector | Display-only in webinar cards | Member multi-select picker in `/admin/webinars` CRUD modal | S4 |
| F3 | Board card webinar badge | `board_items.webinar_id` FK exists, no UI | Badge in CardDetail showing linked webinar status | S4 |
| F4 | `search_hub_resources` | MCP only (T21) | Upgrade `/library` search from client-side filter to server-side RPC | S4 |
| F5 | `get_my_attendance_history` | MCP only (T16) | Personal attendance tab in `/profile` or section in `/attendance` | S5 |

**Note:** These are not bugs — all backend functionality works correctly via MCP or internal RPCs. The gap is frontend surface for web users. Each should be specced by Chat Claude before implementation.

---

## Recently Completed (session 28-29/Mar)

- GC-160: Webinar Governance (full stack)
- GC-161: MCP P1 (19 tools + usage logging)
- GC-162: LGPD RLS Hardening (29 policies, ~20 tables)
- GC-163: Adoption Dashboard v2 (auth providers, MCP card, PostHog native charts)
- GC-164: MCP P2 (23 tools + transport fix @modelcontextprotocol/sdk)
- OAuth fixes: CORS, secret placeholder, issuer dedup
- Custom domain: nucleoia.vitormr.dev
- Gap fixes: G1 (checkOrigin), G2 (PPTX), G4 (public /webinars), G5 (6 webinars), G7 (certificates i18n)
- Attendance bugs: toggle fix, event type icons, SSR guard
- CI fixes: public /webinars test, AttendanceGridTab window guard
