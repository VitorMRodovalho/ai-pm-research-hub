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

### Still needed
- repeatable post deploy smoke tests
- explicit route compatibility checklist
- validation that production propagation matches local behavior after deploy

---

## 2. Role model migration

### Legacy fields still alive
- `role`
- `roles`

### Target fields
- `operational_role`
- `designations`

### Transition rule
The current platform may still use fallback behavior in some places, but new work must prefer the target fields.

### Required next steps
1. Frontend reads have been migrated in core and admin pages to consume `operational_role` and `designations`.
2. Remaining compatibility is concentrated in admin RPC payload contracts (`p_role`, `p_roles`) during transition.
3. After RPC contract cleanup and validation, hard drop `role` and `roles`.

### Final cleanup target
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
Frontend rank and gamification surfaces do not yet fully reflect the new scoring model.

### Migration note
Treat this as a partial migration, not a completed feature.

### Required next steps
- align leaderboard calculations and display
- expose tier aware outcomes in user visible flows where appropriate
- validate historical recalculation logic for already imported badges

---

## 6. Mobile profile input hardening

### Current issue
Credly URL entry on iOS needs validation against real mobile paste behavior.

### Suspected causes
- regex too strict for pasted public URLs with trailing slash or benign params
- paste or focus handling on mobile
- save button enablement not responding correctly after paste

### Required next steps
- test on iOS Safari and Chrome
- trim and normalize URL before submit
- accept valid public profile variants without needless form drama

---

## 7. Analytics architecture

### Internal analytics
Recommended route is PostHog shared dashboards embedded via iframe in protected admin routes.

### External media analytics
Recommended route is Looker Studio via iframe, fed by:
- YouTube native connector
- LinkedIn and Instagram through Google Sheets plus automation

### Migration constraint
Do not build brittle direct social API integrations into core Astro or Supabase flows unless absolutely necessary.

---

## 8. Architecture sustainability note

The project remains viable on a zero cost or free tier oriented stack so long as heavy binary storage and unnecessary frontend complexity are avoided.

This is not a hack. It is a deliberate operating principle.
