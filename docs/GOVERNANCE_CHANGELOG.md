# Governance Changelog

## 2026-03-10 — CPO Production Audit: Information Architecture restructure

### Decisions

1. **Help page made public**: `/admin/help` migrated to `/help` with `minTier: member`. LGPD-sensitive topics (privacy, data protection) are hidden client-side for non-admin users. The old `/admin/help` route returns a 301 redirect to `/help`.

2. **Onboarding removed from main navbar**: Moved to the profile drawer (`section: 'drawer'`, `group: 'profile'`). Requires authentication (`minTier: member`). This reduces main nav clutter without removing the feature.

3. **Universal tribe visibility**: The tribe dropdown now queries ALL tribes (active + inactive). Inactive or legacy tribes render with reduced opacity, a lock icon, and tooltip "Tribo Fechada". Members can discover tribes they cannot currently access.

4. **Webinars placeholder**: `admin/webinars.astro` now renders a "Coming Soon / Módulo em Construção" UI with feature preview cards instead of a blank page. Admin-gated.

### Why

CPO audit revealed that the information architecture had UX friction: help was admin-locked despite being useful to all members, onboarding polluted the main nav, tribe discovery was limited to active tribes only, and the webinars page was blank in production.

### Affected governance documents

- `docs/PERMISSIONS_MATRIX.md` updated (help, onboarding, webinars rows + code mapping)
- `backlog-wave-planning-updated.md` updated (S-HF10 through S-IA3)
- `src/lib/navigation.config.ts` is the code source of truth for these changes

---

## 2026-03-07 — Documentation and release governance reset

### Decision
The repository will maintain a disciplined documentation set with clear boundaries:

- `README.md` = institutional context, platform scope, current status, stack, and documentation map
- `backlog-wave-planning-updated.md` = execution plan and debt visibility
- `docs/GOVERNANCE_CHANGELOG.md` = governance, access, and product engineering decisions
- `docs/MIGRATION.md` = transitional technical notes and compatibility state
- `docs/RELEASE_LOG.md` = operational release and hotfix history

### Why
Recent hotfixes exposed that code can move faster than shared team understanding. Documentation is now part of the delivery obligation.

---

## 2026-03-07 — Manual release log becomes mandatory

### Decision
Manual release logging is required immediately, even before automated semantic versioning exists.

### Rule
Every production affecting hotfix should document:

- what changed
- why it changed
- how it was validated
- what remains pending

### Note
Automated version tags can come later. Invisible releases are not acceptable now.

---

## 2026-03-07 — Route compatibility policy

### Decision
Legacy routes may be retained when there is evidence of active navigation patterns, bookmarks, old links, or prior product behavior.

### Current examples
- `/teams`
- `/rank`
- `/ranks`

### Implication
Backward compatibility is a product decision, not a random convenience.

---

## 2026-03-07 — SSR fail safe rule

### Decision
Server rendered sections must degrade safely when optional arrays or metadata are absent.

### Current reminder
`TribesSection.astro` already required a guard around missing `deliverables`.

### Rule
No server rendered page should assume optional data exists without a default or guard.

---

## 2026-03-07 — Role model v3 becomes the governing model

### Decision
The platform formally adopts the v3 separation between operational role and designations.

### Target fields
- `operational_role`
- `designations`

### Transitional note
Legacy `role` and `roles` may exist during migration but must not define the long term architecture.

---

## 2026-03-07 — Deputy PM hierarchy recognition

### Decision
The hierarchy must distinguish between the main Project Manager and the supporting Deputy PM role.

### Operational meaning
- `manager` remains the principal GP layer
- `deputy_manager` becomes the explicit Co GP / Deputy PM layer

### Product implication
Frontend ordering, badges, and admin views must reflect the distinction consistently.

---

## 2026-03-07 — Members snapshot vs cycle history

### Decision
`members` is the current snapshot table. Historical role, tribe, and cycle participation belongs to `member_cycle_history`.

### Why
Trying to force both current state and historical truth into one table creates ambiguity, broken reporting, and governance confusion.

### Rule
Future timeline and historical reporting features must read from cycle aware history tables.

---

## 2026-03-07 — Product analytics governance

### Decision
The Hub may adopt PostHog and Looker Studio style dashboards, but under strict governance.

### Rules
- no unnecessary PII in analytics identity
- input masking required
- access tier restrictions required
- right to be forgotten must include analytics systems when applicable
- iframe first strategy preferred over custom frontend charting for internal admin dashboards

---

## 2026-03-07 — Source of truth doctrine

### Decision
The Hub is the only source of truth for gamification and project operational metrics.

### Implication
External tools may feed or visualize data, but they do not own business truth.

This rule exists to stop the project from dissolving into a swamp of disconnected tools pretending to be architecture.
