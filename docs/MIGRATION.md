# Migration Notes

## Current migration state
## March 2026

This document tracks active technical transition points so the team can distinguish between:

- what is already in production
- what exists in schema but is not yet fully consumed
- what is legacy and scheduled for removal

---

## 1. Navigation and production stabilization

### Applied
- Cloudflare Pages SPA fallback redirects introduced.
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

## 7. Analytics architecture

### Internal analytics
Current production route is native Chart.js dashboards backed by Supabase RPCs in protected admin routes.

### External media analytics
Current production route is Supabase-backed admin communications dashboards. External connectors may still feed source data, but Looker/PostHog iframes are no longer the primary product pattern.

### Migration constraint
Do not build brittle direct social API integrations into core Astro or Supabase flows unless absolutely necessary.

---

## 8. Architecture sustainability note

The project remains viable on a zero cost or free tier oriented stack so long as heavy binary storage and unnecessary frontend complexity are avoided.

This is not a hack. It is a deliberate operating principle.
