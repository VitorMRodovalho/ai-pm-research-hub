# BACKLOG — AI & PM Research Hub
## Updated: 27 March 2026

---

## P0 — Immediate (this week)

| ID | Item | Status | Owner | Notes |
|----|------|--------|-------|-------|
| — | Andressa Martins 1-on-1 | ⏳ Prazo sexta 28/Mar | Vitor | 3 meses ausente, comms team |
| — | Lídia Do Vale 1-on-1 | ⏳ Prazo sexta 28/Mar | Vitor | 3 meses ausente, T1 |

---

## P1 — This sprint (next 2 weeks)

| ID | Item | Status | Est. effort | Notes |
|----|------|--------|-------------|-------|
| — | Relatório Evolução C2→C3 | ✅ Done | — | Integrated into /admin/cycle-report with evolution section + PDF export |
| — | Resend DNS pmigo.org.br | ✅ Done (27/Mar) | — | DNS verified, email sent from nucleoia@pmigo.org.br, new API key deployed to EF secrets |
| — | Sentry TDZ monitoring | Monitoring | — | 14 workspace.astro issues. Watch post-deploy 97287b5. |
| W-ASTRO6 | Astro 5→6 migration | ✅ Done (GC-133, 2026-03-28) | — | Completed: Astro 6, @astrojs/cloudflare v13, Vite 7, Workers SSR. |

---

## P2 — April (second half)

| ID | Item | Status | Est. effort | Notes |
|----|------|--------|-------------|-------|
| W-MCP-1 | Custom MCP server for tribe leaders | Investigation complete | 2 sessions | Phase 1: 10 read-only tools (mcp-lite + Edge Function). Phase 2: write tools + Fabrício pilot. See W_MCP_1_INVESTIGATION.md. Target: week 14-18/Apr. |
| — | GitHub Copilot opt-out | Not started | 15 min | Deadline 24 April |

---

## P3 — Backlog (unscheduled)

| ID | Item | Status | Notes |
|----|------|--------|-------|
| — | Admin panel Phase 2-4 modularization | Deferred | Internal refactoring, invisible to users |
| — | Ana Carla T8 Notion import → BoardEngine | Deferred | Wait for BoardEngine maturity |
| — | 7 remote-only migrations | Tech debt | Low priority, doesn't block anything |
| — | Manual R3 (ethics, audit, PMBOK 8th ed) | Not started | Content from governance team |
| — | National expansion (3+ chapters) | Planning | Dependent on Relatório + sponsor approval |
| — | 4 ghost researchers | ✅ Resolved | Zero remaining (verified 27/Mar) |
| W-MCP-1-P3 | REST API for ChatGPT/Gemini users | Not started | Phase 3 of MCP initiative. Deferred until MCP pilot validates. |

---

## Completed (27 March 2026 session)

| Item | Commit/Status |
|------|---------------|
| Migration repair (6 RPCs + 1 policy) | ✅ f631c8f |
| pg_cron detractor + attendance reminders | ✅ 93a874c |
| Stakeholder attendance verification | ✅ Validated (5 chapters, numbers coherent) |
| Blog posts 3-5 curadoria + publishing | ✅ Corrected (T1-T8 accurate) |
| Cristiano Oliveira → alumni | ✅ DB updated |
| Ghost researchers audit | ✅ Zero remaining |
| Sentry triagem (37 issues, 5 fixes) | ✅ 97287b5 |
| Documentation (README, ARCHITECTURE, CONTRIBUTING, RUNBOOK, INDEX) | ✅ c25aeb9 |
| W-MCP-1 investigation | ✅ Complete (docs produced) |
