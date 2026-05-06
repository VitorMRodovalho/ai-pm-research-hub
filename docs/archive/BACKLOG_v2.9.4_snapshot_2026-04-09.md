# BACKLOG — AI & PM Research Hub
## Updated: 09 April 2026 (v2.9.4 — 64 MCP tools, 21 EFs, 779 tests)

---

## P0 — Bugs / Active Issues

| # | Item | Status | Notes |
|---|------|--------|-------|
| 1 | Claude Code MCP OAuth on Linux | Open | OAuth flow doesn't open browser. Headers workaround ignored. |
| 2 | 3 events with 0 attendance | Investigate | Cultura & Change 24/Mar + 07/Abr, Inclusao 02/Abr — did meetings happen? |
| 3 | Wellinghton 10% attendance | Operational | Detractor in Tribo 5. Leader (Jefferson) aware. |

---

## P1 — Ready to Execute

| # | Item | Est. | Notes |
|---|------|------|-------|
| 4 | Congresso CBGPL (D-19) | 2h | Deck Canva, one-pager, FAQ. Semana 2 do plano. |
| 5 | ~~Recurrence edit "this + future"~~ | ✅ | Done 10/Abr. Dialog "somente este" vs "este e futuros". |
| 6 | Excused bulk UI | 1h | RPC `bulk_mark_excused` + MCP tool 60 ready. Frontend button needed. |
| 7 | Git history cleanup | Low | 29MB PPTX blob in history |

---

## P2 — Needs External Input

| # | Item | Blocker | Notes |
|---|------|---------|-------|
| 8 | Mario Trentim demo | No response | Nudge needed |
| 9 | Marcio PMI-RS login | Never logged in | auth_id=null, last_seen_at=null. Follow up. |
| 10 | Emanoela Kerkhoff login | Never logged in | PMI-RS observer, no auth |
| 11 | Lorena Souza login | Never logged in | PMI-GO chapter_board, no auth |
| 12 | nucleoia.pmigo.org.br CNAME | Waiting Ivan | HostGator DNS |
| 13 | R3 Manual batch approve | Waiting Ivan | 11 CRs pending |
| 14 | Jefferson board cards | 0 cards by researchers | Need nudge |

---

## P3 — Future Features

| # | Item | Notes |
|---|------|-------|
| 15 | Nature filter in attendance grid | get_attendance_grid too complex for quick add. get_events_with_attendance already returns nature. |
| 16 | ~~Gamification dashboard Sprint 2~~ | ✅ Done 10/Abr. Leaderboard + admin onboarding % column. |
| 17 | Executive sponsor view | 5 sponsors no auth |
| 18 | Conforto approach via Alexandre | Jefferson aligned. Roteiro needed. |

---

## Recently Completed (09/Apr — v2.9.3)

### Session 09/Apr — 20 deliverables, 6 commits, 60 MCP tools
- Event management: drop/update_event_instance RPCs + frontend delete button
- Excused absences: 3-state toggle (absent→present→excused), tooltip with reason, bulk RPC
- Multi-tag: 7 tribe tags + cycle backfill + auto-tag trigger + compound filters
- Mobile: date headers, eligible events filter, no duplicate dates
- Atas: 10 meeting minutes inserted, expandable inline on click
- 10 YouTube links for Tribo 2/6 (Debora recordings)
- Attendance backfill: 10 meetings with corrected attendance
- i18n: 15 broken /en/ /es/ routes fixed (page-as-component → redirect)
- Artia: responsible fixed (PMI Goias → GP Projeto Nucleo IA) for all 10 activities
- Impact hours: excused excluded from calculation (408→397.5h)
- Dashboard: chapters 5/? → 5/8, SyncHealthWidget fixed (response_summary column)
- Attendance pills: classList with CSS vars → inline styles
- Search filter: OR→AND logic fix
- Tribe dropdown: sb null → moved to onMemberReady
- Today = scheduled (not absent) in attendance grid
- Pagination: 200→500 events
- Crons: timeout 5s→30s for all EF-calling jobs
- Recurrence group backfill: 22 groups, ~200 events
- Blog: v2.9.2 post published, MCP post updated 53→59→60
- Paulo Alves excused April (Harvard + Microsoft)

### Session 08/Apr — v2.9.0→v2.9.1
- Artia full integration (GraphQL API, 34 activities, 9 KPIs, status sync)
- sync-artia EF #21 + SyncHealthWidget
- Tag backfill (203 tags) + auto-tag trigger
- Governance public, i18n cleanup (34 dupes removed), 18 KPIs
- Route audit, demo script, SITE_MAP, README updated
- Volunteer Agreement panel, contracting_chapter, diversity enrichment
- 3 deploys, 24 docs archived

### Session 07/Apr — canWriteBoard, 10 atas
- canWriteBoard: researchers create/move cards via MCP
- 10 meeting artifacts, legacy card Ciclo 2
- 5 framework cards assigned, Emanoela created
