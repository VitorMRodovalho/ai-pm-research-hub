# SPEC: Platform Quality Audit — Congress-Ready Review

**Status:** In Progress — WS1/WS2/WS3/WS4/WS6 complete, WS5/WS7 partial
**Priority:** Critical (CBGPL Congress presentation)
**Created:** 2026-04-08
**Author:** Claude (PM/Architect) + Vitor (GP)

---

## 1. Context

The Nucleo IA & GP platform will be demonstrated at the CBGPL Congress. Every visible defect becomes an attention point that overshadows the platform's capabilities. This spec defines a systematic quality audit across all dimensions.

## 2. Workstreams

### WS1: URL Hierarchy & Route Audit
**Owner:** Tech Backend + Frontend
**Goal:** Every page has a defined access level, is reachable via navigation, and works in all 3 languages.

#### Known issues found today:

| # | Issue | Severity | Status |
|---|-------|----------|--------|
| 1 | `/blog` (public, visitor) — missing `/en/blog/` and `/es/blog/` redirect pages | High | **Fixed** (meta-refresh) |
| 2 | `/governance` — configured as `minTier: 'member', requiresAuth: true` but should have a public version for the manual (read-only, no CRs) | Medium | **Fixed** (visitor, manual-only) |
| 3 | `/governance` — `navSlot: 'none'` means it only shows in admin drawer, not in main nav for members | Medium | **Fixed** (navSlot: primary) |
| 4 | `/publications/submissions/[id]` — missing EN/ES redirect pages | Low | **Fixed** |

#### Audit checklist:
- [x] List all routes from `navigation.config.ts` and `src/pages/`
- [x] Cross-reference: every `src/pages/*.astro` must have `en/` and `es/` redirects — **100% coverage** (all ~70 routes)
- [x] Every route with `navSlot: 'primary'` must be visible in the top nav
- [ ] Every route with `drawerSection` must be visible in the profile drawer
- [ ] Check for orphan pages (exist in `src/pages/` but not in `navigation.config.ts`)
- [ ] Check for phantom routes (in `navigation.config.ts` but page doesn't exist)
- [x] Verify `minTier` and `requiresAuth` for governance route — now visitor-accessible

### WS2: Persona Journey Simulation
**Owner:** QA + UX
**Goal:** Walk through the platform as each persona and verify the experience is complete and error-free.

#### Personas to test:

| Persona | Tier | Designations | Key journey |
|---------|------|-------------|-------------|
| **Visitor (not logged in)** | visitor | — | Homepage → About → Blog → Impact → Governance (manual) → Webinars |
| **Candidate (selection)** | candidate | — | Homepage → Login → Onboarding → Profile |
| **New Researcher** | researcher | — | Login → Onboarding → Profile → Tribe → Boards → Gamification → Certificates → Volunteer Agreement |
| **Active Researcher** | researcher | — | Dashboard → Tribe → Boards → Attendance → Library → Blog → Webinars → Publications |
| **Tribe Leader** | tribe_leader | — | Dashboard → Tribe mgmt → Board → Attendance → Deliverables → Events |
| **Sponsor (Chapter Board)** | sponsor | chapter_board | Admin Dashboard → Certificates → Chapter Report → Analytics → Stakeholder |
| **Chapter Board (Lorena)** | observer | chapter_board | Admin Dashboard → Certificates (counter-sign) → Chapter view |
| **GP (Manager)** | manager | superadmin | Full admin → All reports → All dashboards → Selection → Governance |
| **Congress Demo** | — | — | Public tour: Homepage → Impact → Blog → About → Governance → Webinars → Login → Dashboard overview |

#### For each persona, check:
- [ ] All expected nav items are visible
- [ ] No unexpected nav items are visible (LGPD)
- [ ] Every link works (no 404, no broken pages)
- [ ] i18n: switching language preserves the page context
- [ ] Data loads correctly (no "Não informado" where data exists)
- [ ] No console errors
- [ ] Mobile responsive

### WS3: i18n Completeness
**Owner:** Tech Frontend
**Goal:** Every page works in PT-BR, EN-US, ES-LATAM without English fallback text in PT-BR context.

#### Known issues:
- ~~Diversity dashboard showed English chart titles in PT-BR session~~ (fixed)
- Some components use hardcoded PT-BR strings instead of i18n keys

#### Audit checklist:
- [x] Remove duplicate i18n keys: 12 in pt-BR, 12 in en-US, 11 in es-LATAM — **all cleaned**
- [x] Build produces 0 duplicate key warnings
- [ ] Grep for hardcoded English strings in `.tsx` components
- [ ] Verify all `t()` calls have keys in all 3 dictionaries
- [x] Check all redirect pages in `/en/` and `/es/` directories exist for every PT-BR page — **100%**
- [x] Special: `/blog/` and `/blog/[slug]` i18n redirects — **done** (meta-refresh)

### WS4: Data Consistency
**Owner:** Tech Backend
**Goal:** Every number shown on the platform is traceable to a single source of truth.

#### Completed this session:
- [x] Member count standardized: 52 active (all RPCs aligned)
- [x] Diversity data enriched: 70/70 gender, sector, seniority
- [x] Daniel Bittencourt status fixed

#### Remaining checks:
- [x] KPI dashboard: 4 duplicate rows removed, all 18 KPIs now have `current_value` (zero "NO DATA")
- [x] Active members: 52 — consistent across `members`, `get_public_platform_stats()`
- [x] Attendance: 209 events, 1005 records, avg 20.2% (gerais), 7.4 avg per event
- [x] Gamification: 1299 entries, 16,270 points, 60 members with points
- [x] Certificates: 5 issued
- [ ] Certificate counts match between admin panel, member view, and verification page (manual verify needed)

### WS5: Governance Journey
**Owner:** PM + Legal
**Goal:** Volunteer agreement workflow is complete and legally compliant.

#### Completed this session:
- [x] Contracting chapter governance (PMI-GO for all cycle 3)
- [x] Counter-signature scoped by contracting chapter
- [x] Template preview in admin
- [x] Tenure info in member table
- [x] Self-notification to signer (link: /certificates)
- [x] Admin notification (link: /admin/certificates)

#### Remaining:
- [ ] Verify the template content matches the signed PDF exactly
- [ ] Test counter-sign flow as Lorena (chapter_board)
- [ ] Test flow as non-PMI-GO member (ensure contracting_chapter = PMI-GO)
- [ ] Verify /verify/[code] page shows correct counter-signer info

### WS6: Congress Demo Script
**Owner:** PM + Comms
**Goal:** Scripted demo flow that showcases platform strengths and avoids known gaps.

#### Recommended demo flow:
1. **Public** (no login): Homepage → Impact metrics → Blog → About → Webinars calendar
2. **Governance**: Manual viewer → Change requests → Approval workflow
3. **Member login**: Profile → Gamification → Tribe dashboard → Boards (kanban)
4. **Admin**: Dashboard (KPIs + widgets) → Selection pipeline → Diversity charts → Certificates → Sustainability
5. **MCP**: Show Claude.ai connected with 56 tools → run a query live

#### Avoid during demo:
- Pages with known UX gaps (if any remain)
- Features still in development
- Admin pages that require specific data to look good

### WS7: Documentation
**Owner:** Tech + PM
**Goal:** Platform architecture, features, and governance model are documented for stakeholder review.

- [ ] Update ADMIN_ARCHITECTURE.md with new certificate workflow
- [ ] Update CHANGELOG.md with this session's changes
- [ ] Ensure the governance manual in the platform reflects current policies
- [ ] Prepare one-pager for congress handout

---

## 3. Immediate Fixes (this session)

| # | Fix | Complexity |
|---|-----|-----------|
| 1 | ~~Create `/en/blog/index.astro`, `/es/blog/index.astro` redirect pages~~ | **Done** |
| 2 | ~~Create `/en/blog/[slug].astro`, `/es/blog/[slug].astro` redirect pages~~ | **Done** |
| 3 | ~~Decision on `/governance` public access → implement~~ | **Done** (manual public, auth tabs hidden) |
| 4 | ~~Create `/en/es` redirects for `publications/submissions/[id]`~~ | **Done** |
| 5 | ~~Remove 4 duplicate KPI rows + fill all current_values~~ | **Done** |
| 6 | ~~Clean 34 duplicate i18n keys across 3 dictionaries~~ | **Done** |

---

## 4. Recommendation from specialists

### PMI Global perspective:
Transparency and open governance are core PMI values. The governance manual (policies, change request process, volunteer term template) should be **publicly accessible** to demonstrate organizational maturity. The simulation feature (role-based access) correctly requires authentication.

**Recommendation:** Make `/governance?view=document` (manual only) accessible to visitors. Keep `view=approvals`, `view=changes`, `view=documents` behind auth.

### Tech perspective:
The `/governance` page uses a single React island that calls 3 RPCs. For public access:
- `get_manual_sections` can be made anon-safe (SECURITY DEFINER, no PII)
- `get_change_requests` and `get_governance_documents` should remain auth-gated
- The component already handles `member = null` gracefully (retries then gives up)
- Fix: show manual tab without auth, hide other tabs for visitors

### UX perspective:
For a congress demo, the governance page is a **showcase feature** — it demonstrates that the research group operates with formal governance, change management, and version control. Making it public sends a strong signal of maturity.
