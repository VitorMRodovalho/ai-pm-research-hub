# Release Log

## 2026-03-07 — Stabilization Hotfix Train

### Scope
Production stabilization covering route compatibility, SSR safety, and documentation discipline.

### Included changes

#### `6f1593d`
**Message:** `fix: add Cloudflare Pages SPA fallback redirects`

**Why**
Reduce direct navigation failures and improve resilience for non standard entry paths on Cloudflare Pages.

#### `f33afce`
**Message:** `fix: add legacy route aliases for team and rank pages`

**Why**
Restore compatibility for old or live links still pointing to:
- `/teams`
- `/rank`
- `/ranks`

#### `87cde9a`
**Message:** `fix: guard tribes deliverables mapping against missing data`

**Why**
Prevent SSR failure in `TribesSection.astro` when static data is incomplete or optional.

### Validation captured
- local `npm run build` passed
- local `npm run dev -- --host 0.0.0.0 --port 4321` started successfully
- local access confirmed through `http://localhost:4321/`

### Known follow up
- production propagation of aliases should still be smoke tested
- SSR safety audit should continue in other sections
- docs were behind the code and are now being corrected

---

## 2026-03-07 — Credly Tier Scoring Expansion

### Scope
Backend scoring logic for Credly verification was expanded beyond the older coarse behavior.

### Delivered
- tier based certification scoring in the verification flow
- richer scoring breakdown in backend response
- improved zero match handling

### Important caveat
This release is **not complete from a product standpoint** because rank and gamification UI surfaces still need alignment with the new scoring logic.

### Operational note
When backend truth and frontend experience diverge, the release log must say so plainly instead of pretending the feature is done. Reality is stubborn like that.

---

## Release policy from now on

Every production affecting hotfix, stabilization batch, or materially visible backend change should create or update an entry in this file.

Automated semantic versioning can come later. Team memory cannot.
