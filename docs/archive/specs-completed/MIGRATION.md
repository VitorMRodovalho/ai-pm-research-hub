# Migration Notes

## Current migration state
## March 2026

This document tracks active technical transition points so the team can distinguish between:

- what is already in production
- what exists in schema but is not yet fully consumed
- what is legacy and scheduled for removal

---

## W85-W89 (Operações, Legado, Qualidade) — Mar 2026

### W85: Dashboard Comms (Cockpit Tribo 8)
- **RPC:** `get_comms_dashboard_metrics()` — agrega project_boards com `domain_key = 'communication'`, board_items, tags.
- **Frontend:** `CommsDashboard.tsx` (React Island + Recharts) — macro cards (Backlog, Atrasados, Total), bar chart por status, pie chart por formato.
- **Rota:** `/admin/comms-ops` — mantém acesso `comms_leader`, `comms_member`, admin.

### W86: Data Sanity do Legado
- **Migration:** `20260315000000_legacy_data_sanity.sql` — orfãos em `member_cycle_history`, padronização de `cycle_code`, coluna `legacy_board_url` em `tribes`.

### W87: E2E User Lifecycle
- **Spec:** `tests/e2e/user-lifecycle.spec.ts` — Playwright valida fluxo líder de tribo: /tribe/1, board tab, card, drag, logout.

---

## 1. Navigation and production stabilization

### Applied
- Cloudflare Workers SPA fallback redirects introduced.
- Legacy aliases restored for `/teams`, `/rank`, and `/ranks`.
- `TribesSection.astro` guarded against missing `deliverables` during SSR.
- Repeatable smoke tests added with `npm run smoke:routes`.
- Sprint audit now includes an explicit site hierarchy checklist.

### Still needed
- validation that production propagation matches local behavior after deploy

---

## 2. Role model migration

### Legacy fields removed
- `role`
- `roles`

### Target fields
- `operational_role`
- `designations`

### Transition rule
The current platform may still use fallback behavior in some places, but new work must prefer the target fields.

### Required next steps
1. Frontend reads have been migrated in core and admin pages to consume `operational_role` and `designations`.
2. Remaining compatibility is concentrated in transitional RPC contracts and historical documentation cleanup.
3. New work must not reintroduce `role` / `roles` assumptions anywhere in frontend or docs.

### Final cleanup target
Achieved in Wave 8 (`20260312020000`):

```sql
ALTER TABLE public.members DROP COLUMN role;
ALTER TABLE public.members DROP COLUMN roles;
```

---

## 3. Hierarchy refinement

### New role introduced
`deputy_manager`

### Why
The platform must visually and logically distinguish the primary GP layer from the Deputy PM layer.

### Frontend implications
- badge rendering
- sorting logic
- team section hierarchy
- profile displays
- admin editing flows

---

## 4. Current snapshot vs historical truth

### Governing rule
`members` is the current snapshot table only.

### Historical truth
Historical cycle state belongs in `member_cycle_history`.

### Product implications
Features such as:

- timeline in profile
- “who was leader in cycle X”
- chapter and tribe participation history
- cycle aware reporting

must read from historical fact tables instead of overloading `members`.

---

## 5. Credly scoring migration

### Applied
Tier based scoring logic has already advanced in backend verification behavior.

### Current issue
Core leaderboard and gamification flows now reflect the tier-based model, but historical recalculation and long-tail UI consistency should still be validated over time.

### Migration note
Treat this as a partial migration, not a completed feature.

### Required next steps
- align leaderboard calculations and display
- expose tier aware outcomes in user visible flows where appropriate
- validate historical recalculation logic for already imported badges

---

## 6. Mobile profile input hardening

### Applied
Paste normalization, debounce fallback, and validation hardening were shipped in `Profile.astro`.

### Required next steps
- keep validating on real iOS Safari and Chrome when regressions are reported
- preserve normalization for valid public profile variants without tightening regex again

---

## 7. Tribe catalog runtime migration

### Applied
`supabase/migrations/20260312050000_dynamic_tribe_catalog_and_status.sql` adds `public.tribes.is_active`, introduces runtime tribe catalog RPCs, removes the strongest frontend assumptions that tribe ids stop at `8`, and is already applied on the linked Supabase project.

### Current transition state
- admin, nav, tribe routes, workspace, artifacts, gamification, and hero counts now read runtime tribe metadata
- `src/lib/database.gen.ts` was regenerated from the linked project after the migration

### Required next steps
1. Validate the new admin create/toggle tribe flows against the real linked environment.
2. Decide whether the public/editorial tribe layer should remain partially curated in static i18n or move further into runtime metadata.
3. Extend regression coverage once the public tribe layer starts consuming more runtime metadata.

---

## 8. Analytics architecture

### Internal analytics
Current production route is native Chart.js dashboards backed by Supabase RPCs in protected admin routes.

### Applied in Wave 36-40
- `supabase/migrations/20260312110000_analytics_v2_internal_readonly_and_metrics.sql` adds `can_read_internal_analytics()` so `/admin/analytics` can open to `sponsor`, `chapter_liaison`, and `curator` as read-only consumers without widening write/admin actions.
- The same migration introduces cycle-aware contracts for `exec_funnel_v2`, `exec_impact_hours_v2`, `exec_certification_delta`, `exec_chapter_roi`, and `exec_role_transitions`, plus a shared `analytics_member_scope(...)` helper.
- `src/lib/database.gen.ts` was regenerated from the linked project after the migration.

### Current transition state
- `/admin/analytics` now runs on Analytics V2 contracts and global filters (`cycle_code`, `tribe_id`, `chapter_code`).
- `/admin/selection` remains the LGPD-sensitive analytics path and is still admin-only.
- Attribution and leadership analytics are now backed by explicit SQL contracts rather than frontend-only aggregation guesses.

### External media analytics
Current production route is Supabase-backed admin communications dashboards. External connectors may still feed source data, but Looker/PostHog iframes are no longer the primary product pattern.

### Migration constraint
Do not build brittle direct social API integrations into core Astro or Supabase flows unless absolutely necessary.

### Required next steps
1. Validate the new V2 metrics against live linked-project data and tune the chapter-attribution window only through governance docs plus SQL contracts, not ad-hoc frontend logic.
2. Keep future analytics asks inside the staged contract pattern (new RPC/view first, chart second) so `admin/analytics` does not regress into client-side business logic.

---

## 9. Architecture sustainability note

The project remains viable on a zero cost or free tier oriented stack so long as heavy binary storage and unnecessary frontend complexity are avoided.

This is not a hack. It is a deliberate operating principle.

---

## 10. Webinar operational model

### Current state
The repo currently exposes two overlapping webinar paths:

- `events` already supports `type='webinar'` and is connected to attendance and current event operations
- `webinars` / `list_webinars` exist in schema, but are not yet the primary operational flow

### Current issue
Without an explicit rule, the platform risks splitting webinar scheduling, attendance, replay publishing, and reporting across two different sources of truth.

### Governing rule
For the first webinar MVP, webinar operations should remain **events-first** and reuse the existing attendance, content, communications, and analytics stack.

### Required next steps
- Keep the next implementation slice on top of `events` + `attendance`, not a new webinar-specific schema.
- Treat the standalone `webinars` table as non-authoritative until a convergence or retirement decision is approved.
- If the product later approves external registration, reusable speaker entities, or webinar-specific certificate automation, define the new data model and migration path before adding more schema.

### Supporting reference
See `docs/archive/WEBINARS_MODULE_DISCOVERY.md` for the approved discovery scope and rollout boundaries, and `docs/archive/WEBINARS_CONVERGENCE_PROPOSAL.md` for the recommended path on deprecating or converging the standalone `webinars` table.
