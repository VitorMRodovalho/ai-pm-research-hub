# BACKLOG — AI & PM Research Hub
## Updated: 02 April 2026 (Sprint 12 — 4 Ondas: 11 CRs addressed, volunteer term, diversity dashboard, board members UI)

---

## P0 — Bugs / Active Tech Debt

| # | Item | Est. | Status | Notes |
|---|------|------|--------|-------|
| 1 | Attendance cross-tribe | 1-2h | Monitoring | Retry pattern deployed (30×300ms). Intermittent — cannot reproduce reliably. Monitor. |
| 33 | TMO ghost events | — | ✅ Done (02/Abr) | 10 recurrence events for inactive TMO tribe deleted. Notifications sent to 7 leaders for 59 pending. |
| 2 | 2 attendance corrections | — | ✅ Done | Guilherme + Gustavo confirmed present in DB |
| 3 | Migration repair 26/Mar | 5 min | ✅ Done (29/Mar) | All migrations synced |
| 4 | i18n server-side locale | — | ✅ Verified (29/Mar) | EN/ES resolve correctly server-side. Not a bug. |
| 5 | MCP connector Claude.ai | — | ✅ Done (31/Mar) | SDK 1.28.0 + Zod + native transport. 52 tools visible on Claude.ai. |
| 28 | Campaign tracking test | 1h | ✅ Done (02/Abr) | Bug: process_email_webhook didn't sync aggregate counters to campaign_sends. Fixed + backfilled (50/50 delivered). |
| 29 | Claude Code MCP OAuth on Linux | — | Open | OAuth flow doesn't open browser. Headers workaround ignored by Claude Code. Tested via curl successfully. |

---

## P1 — Ready to Execute (no blockers)

| # | Item | Est. | Status | Notes |
|---|------|------|--------|-------|
| 6 | S3.3 Custom PostHog events | — | ✅ Done (29/Mar) | 7 events deployed. posthog.identify() in Nav. |
| 7 | S3.2 Designation filter | — | ✅ Done (29/Mar) | /admin/members + /attendance ranking. |
| 8 | GC-097 P2 smoke test | — | ✅ Done (29/Mar) | 11 checks, all pass. `npm run smoke` available. |
| 9 | pg_cron verification | — | ✅ Done (29/Mar) | 7 jobs active |
| 10 | URL migration notice | Note | FYI | Débora + Marcos using legacy .pages.dev (redirect works) |
| 30 | P1.3 Write Tools tested | — | ✅ Done (31/Mar) | 4/4 pass via curl: create_tribe_event, create_meeting_notes, register_attendance, send_notification_to_tribe |
| 31 | P2 tool count update | — | ✅ Done (31/Mar) | 42/47/50 → 52 across rules, SKILL.md, EF, adoption.astro |
| 32 | MCP error_rate post auto-refresh | — | ✅ Done (31/Mar) | Anomaly report: 0 pending, 0 errors |

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
| 18 | Pre-onboarding gamification | Sprint 1 Done | 3 RPCs deployed, João QA baseline (3/5 auto-completed). Sprint 2 (frontend dashboard) pending. |
| 19 | Playwright e2e expansion | — | ✅ Done (29/Mar) — 15→40 tests, 9 new spec files |
| 20 | Sustainability frontend | ✅ Done (audit 31/Mar) | 819-line page with dashboard, tabs, permissions. en/es redirects exist. |
| 21 | W107 Pilot #1 handler | ✅ Done (audit 31/Mar) | 14/14 audit checks pass. Table, 3 RPCs, /admin/pilots.astro, pilot #1 seeded. |
| 22 | BoardEngine polish | ✅ Done (audit 31/Mar) | Exceeds spec: 14 components + 4 hooks, 6 views (kanban/table/list/calendar/timeline/activities), DnD, curation mode, keyboard shortcuts. |
| 23 | Admin modularization Phases 2-4 | ✅ Done (audit 31/Mar) | 33 admin pages, page-per-domain architecture. ADMIN_ARCHITECTURE.md documents full structure. |
| 24 | Advisor: Security audit | — | ✅ Done (29/Mar) — 35 search_path fixed, 2 RLS tightened, 11 SD views intentional |
| 25 | legacy_tribes table cleanup | — | ✅ Done (29/Mar) — table dropped, code ref replaced with cycle_tribe_dim |
| 26 | Git history cleanup | Low | 29MB PPTX in git history (G16) |
| 27 | Co-managers member picker | — | ✅ Done (29/Mar) — F2 spec |

---

## Frontend ↔ Backend Parity Gaps (audit 29/Mar)

RPCs with backend ready but no frontend surface. To be specced and implemented in grouped sprints.

| # | RPC | Current State | Recommended Frontend | Sprint |
|---|-----|---------------|---------------------|--------|
| F1 | `get_public_platform_stats` | ✅ Done (29/Mar) | Homepage `/` stats section — all 3 locales | S4 |
| F2 | Co-managers selector | ✅ Done (29/Mar) | Member multi-select in `/admin/webinars` CRUD modal | S4 |
| F3 | Board card webinar badge | ✅ Won't Do (31/Mar) | Premissa incorreta (FK não existe em board_items). Relação board↔webinar é artificial — YAGNI. | — |
| F4 | `search_hub_resources` | ✅ Done (29/Mar) | `/library` search upgraded to server-side RPC (300ms debounce) | S4 |
| F5 | `get_my_attendance_history` | ✅ Done (29/Mar) | Personal attendance history in `/profile` with progress bar + table | S4 |

**Note:** F3 deferred to Sprint 5 (low demo impact). F1/F2/F4/F5 implemented per SPRINT4_PARITY_SPECS.md.

---

## Recently Completed (session 31/Mar)

### Sprint 10 (31/Mar)
- P1.3: Write tools tested (4/4 pass — create_tribe_event, create_meeting_notes, register_attendance, send_notification_to_tribe)
- P2: MCP tool counts updated across 4 files (42/47/50 → 52)
- P2: MCP error_rate post auto-refresh — anomaly report clean (0 pending, 0 errors)
- i18n review: 4 commits (hardcoded lang fixes, global search EN, blog EN, webinars SSR)
- P1+P2: OAuth lang propagation, OG image fallback, release log, hub cleanup, onboarding prompt, blog revision, governance tools

### Sprint 4 Parity (29/Mar — continued session)
- F1: Homepage public stats section (3 locales, 6 metrics)
- F2: Webinar co-manager selector in CRUD modal
- F4: Library server-side RPC search (augments client-side, 300ms debounce)
- F5: Personal attendance history on /profile (progress bar + table)
- S3.2: Attendance ranking role filter
- PostHog: 4 new events (homepage_stats_viewed, library_search, attendance_history_viewed, webinars_public_viewed)
- Security: 35 functions search_path hardened, 2 RLS policies tightened
- E2e: Playwright expanded 15→40 tests (9 new spec files)
- Bug fix: webinar trigger fixed_tribe_id → tribe_id
- Bug fix: /webinars anon GRANT + 3 webinars confirmed
- Cleanup: legacy_tribes table dropped (G13), .gitignore, settings.json hook
- Demo: script + checklist in docs/DEMO_SCRIPT_MARIO.md

### Sprint 4 (28-29/Mar)
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

---

## Selection Pipeline V2 — ✅ All 11 Gaps Resolved (01-02/Apr)

All S1-S11 gaps resolved. Pipeline is production-ready for Batch 2 async evaluation.

| # | Gap | Status |
|---|-----|--------|
| S1 | Modal Info | ✅ Done — membership, certs, CV, WhatsApp, Credly, chapter_affiliation |
| S2 | Interview questions | ✅ Done — 5 pillars stored per cycle (interview_questions jsonb) |
| S3 | Per-criterion notes | ✅ Done — criterion_notes jsonb in selection_evaluations |
| S4 | Interview booking | ✅ Done — URL shown in modal |
| S5 | Consolidated results | ✅ Done — grouped by phase (Quantitativa/Qualitativa/Líder) with PERT |
| S6 | Bulk feedback | ✅ Done — field in bulk actions bar |
| S7 | Application date | ✅ Done (via S1) |
| S8 | Interview questions config | ✅ Done — per-cycle jsonb + rich essay mapping |
| S9 | RPC missing fields | ✅ Done — all essay + contact fields returned |
| S10 | Background contextual | ✅ Confirmed OK (no score, guide-only) |
| S11 | Membership flagging | ✅ Done — !M and R badges in pipeline table |

### Additional Selection Deliverables (01-02/Apr)
- Evaluation rubrics (advisory panel): cert 0-2, others 0-10 with anchored descriptors
- Observer role enforcement (see but can't score)
- VEP opportunities config UI (create/edit + rich essay mapping)
- Evaluator UX: phone/WhatsApp, inline contact edit, Credly link, context panel
- Ciclo 3 kickoff normalized: 62 candidates, 146 evaluations, rankings, 34 interviews
- 7 leader-only retrospective researcher evaluations (PM validated)
- 5 dual applicants linked via converted_from/converted_to

### KPI Audit (01-02/Apr)
- Trail: 3 values unified → 32% (calc_trail_completion_pct shared function)
- CPMAI target: 5→2 (annual_kpi_targets corrected)
- Impact/Meeting hours: date range fixed (Jan 1 not kickoff Mar 5)
- Attendance: 38.6%→53.3% (includes geral+tribo+1on1+lideranca)
- Chapters count: hardcoded "5" → dynamic
- All homepage indicators audited — no other hardcoded values found

### Other Fixes (01-02/Apr)
- Sentry DSN console.log removed
- P0: Cycle 1 tags 22/22 members
- P0: Manual Apêndice A corrected to Docusign V2 (8 founders + designações)
- P1: 5 MCP tools tribe_id fallback
- P2: Manual EN/ES full translation (34 sections)
- P3: Anomaly detection (7 proactive rules)
- P3: CR audit — 34/46 marked implemented
- P3: Quadrants table created with FK from tribes
- Tribes quadrant fix: Agentes Autônomos Q1→Q2, TMO removed (paused)
- Pre-onboarding dashboard deployed on workspace
