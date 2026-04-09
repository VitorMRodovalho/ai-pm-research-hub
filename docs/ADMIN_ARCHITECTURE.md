# Admin Panel Architecture

> Last updated: 08 April 2026 | v2.9.0+

---

## Overview

The admin panel is a **modular, page-per-domain** architecture. Each admin function lives in its own `.astro` page that uses `AdminLayout` for consistent sidebar navigation, breadcrumbs, and permission gating.

```
src/pages/admin/
  index.astro              ← Dashboard (33 lines, orchestrator only)
  members.astro            ← Member management (React island)
  tribes.astro             ← Tribe catalog + meeting slots
  ...29 pages total

src/components/admin/
  AdminSidebar.tsx          ← Sidebar navigation (React)
  dashboard/                ← Dashboard widgets
  members/                  ← Member list + detail islands
  audit/                    ← Audit log island
  blog/                     ← Blog editor island
  ...17 components total

src/lib/admin/
  constants.ts              ← Shared labels, colors, helpers (imported by 10+ files)
  member-format.ts          ← Member display formatting
  tribe-catalog-ui.ts       ← Tribe catalog UI helpers
  types.ts                  ← Shared TypeScript interfaces
```

---

## Page Map (29 pages)

### People
| Page | Route | Component | Purpose |
|------|-------|-----------|---------|
| Members | `/admin/members` | `MemberListIsland` | List, search, filter, edit members |
| Member Detail | `/admin/members/[id]` | `MemberDetailIsland` | Individual member profile + history |
| Certificates | `/admin/certificates` | inline script | Pending counter-signatures, issue certificates |
| Selection | `/admin/selection` | inline script | Cycle selection pipeline |

### Research & Content
| Page | Route | Component | Purpose |
|------|-------|-----------|---------|
| Tribes | `/admin/tribes` | inline script | Tribe catalog, meeting slots |
| Curatorship | `/admin/curatorship` | inline script | Cross-tribe curation board |
| Publications | `/admin/publications` | inline script | Publication submissions admin |
| Knowledge | `/admin/knowledge` | `KnowledgeIsland` | Knowledge assets management |
| Blog | `/admin/blog` | `BlogEditorIsland` | Blog post editor |
| Tags | `/admin/tags` | `TagManagementIsland` | Tag CRUD (system, admin, semantic) |
| Board | `/admin/board/[id]` | `BoardEngine` | Board management |

### Communication
| Page | Route | Component | Purpose |
|------|-------|-----------|---------|
| Comms Dashboard | `/admin/comms` | `CommsDashboard` | Communication metrics |
| Comms Operations | `/admin/comms-ops` | `BoardEngine` | Communication board |
| Campaigns | `/admin/campaigns` | inline script | Email campaigns via Resend |
| Webinars | `/admin/webinars` | inline script | Webinar events management |

### Reports & Analytics
| Page | Route | Component | Purpose |
|------|-------|-----------|---------|
| Dashboard | `/admin` (index) | `AdminDashboardIsland` + `PlatformHealthWidget` | Overview stats |
| Analytics | `/admin/analytics` | Chart.js inline | Product analytics (Chart.js) |
| Cycle Report | `/admin/cycle-report` | Chart.js inline | Cycle metrics PDF-exportable |
| Chapter Report | `/admin/chapter-report` | inline script | Per-chapter dashboard |
| Report Builder | `/admin/report` | inline script | Custom report generation |
| Portfolio | `/admin/portfolio` | inline script | GP portfolio Gantt + heatmap |
| Adoption | `/admin/adoption` | inline script | Platform adoption metrics |
| Sustainability | `/admin/sustainability` | inline script | Sustainability tier display |
| Data Health | `/admin/data-health` | `DataHealthIsland` | Data quality checks |

### Governance
| Page | Route | Component | Purpose |
|------|-------|-----------|---------|
| Governance v2 | `/admin/governance-v2` | `GovernanceAdminIsland` | CR management (admin view) |
| Partnerships | `/admin/partnerships` | inline script | Partner entity pipeline + DocuSign |
| Pilots | `/admin/pilots` | inline script | AI pilots CRUD |

### Operations
| Page | Route | Component | Purpose |
|------|-------|-----------|---------|
| Settings | `/admin/settings` | inline script | Platform configuration |
| Audit Log | `/admin/audit-log` | `AuditLogIsland` | Unified audit trail |
| Help | `/admin/help` | inline script | FAQ + troubleshooting |

---

## Component Map (21 components)

| Component | Location | Used by | Purpose |
|-----------|----------|---------|---------|
| `AdminSidebar.tsx` | `components/admin/` | `AdminLayout.astro` | Sidebar navigation with sections |
| `AdminDashboardIsland.tsx` | `components/admin/dashboard/` | `/admin` | Stats cards, recent activity |
| `PlatformHealthWidget.tsx` | `components/admin/` | `/admin` | Usage tracking, sustainability tier |
| `MemberListIsland.tsx` | `components/admin/members/` | `/admin/members` | Member table with search, filters, edit |
| `MemberDetailIsland.tsx` | `components/admin/members/` | `/admin/members/[id]` | Member profile, history, transitions |
| `AuditLogIsland.tsx` | `components/admin/audit/` | `/admin/audit-log` | Audit trail with filters |
| `BlogEditorIsland.tsx` | `components/admin/blog/` | `/admin/blog` | TipTap rich text blog editor |
| `CommsDashboard.tsx` | `components/admin/` | `/admin/comms` | Communication metrics charts |
| `DataHealthIsland.tsx` | `components/admin/` | `/admin/data-health` | Data quality checks |
| `GovernanceAdminIsland.tsx` | `components/admin/` | `/admin/governance-v2` | CR admin management |
| `GovernanceBatchModal.tsx` | `components/admin/` | governance admin | Batch CR operations |
| `GovernanceCRTable.tsx` | `components/admin/` | governance admin | CR list table |
| `GovernanceStats.tsx` | `components/admin/` | governance admin | Governance stats cards |
| `KnowledgeIsland.tsx` | `components/admin/` | `/admin/knowledge` | Knowledge assets CRUD |
| `TagManagementIsland.tsx` | `components/admin/` | `/admin/tags` | Tag CRUD with tiers |
| `TierViewerBar.tsx` | `components/admin/` | `AdminLayout` | Permission simulation bar |
| `VolunteerAgreementPanel.tsx` | `components/admin/` | `/admin/certificates` | Volunteer agreement sign/counter-sign workflow |
| `VolunteerComplianceWidget.tsx` | `components/admin/` | `AdminSidebar` | Compliance status widget |
| `SyncHealthWidget.tsx` | `components/admin/` | `/admin` | Cron job sync monitoring |
| `BoardMembersPanel.tsx` | `components/admin/` | `/admin/chapter` | Chapter board members management |

---

## Shared Library (`src/lib/admin/`)

| Module | Exports | Used by |
|--------|---------|---------|
| `constants.ts` | 14 maps (OPROLE_LABELS, TRIBE_NAMES, etc.) + 6 helpers (avatar, initials, getTier, etc.) | 10+ files |
| `member-format.ts` | Member display formatting utilities | Member components |
| `tribe-catalog-ui.ts` | Tribe catalog rendering helpers | Tribe pages |
| `types.ts` | Shared TypeScript interfaces (Member, Tribe, etc.) | All admin components |

---

## Key RPCs by Domain

### Members
- `get_member_by_auth()` — current user
- `admin_list_members()` — full member list
- `admin_update_member()` — edit member fields
- `get_member_detail()` — single member profile
- `get_audit_log()` — member activity history

### Governance
- `get_manual_sections(p_version)` — manual sections (SECURITY DEFINER, anon-safe — powers public governance page)
- `get_change_requests()` — CR list (auth-gated)
- `get_governance_documents()` — governance documents (auth-gated)
- `approve_change_request()` — sponsor approval with SHA-256
- `get_cr_approval_status()` — sponsor voting panel
- `get_governance_preview()` — manual R3 preview
- `generate_manual_version()` — create new manual version
- **Public access:** `/governance` is now visitor-accessible (manual tab only). Tabs for approvals, CRs, and documents are hidden for unauthenticated visitors.

### Certificates & Volunteer Agreements
- `get_pending_countersign()` — certificates awaiting chapter board counter-signature
- `counter_sign_certificate()` — chapter board counter-signs (scoped by `contracting_chapter`)
- `get_volunteer_agreement_stats()` — compliance metrics per chapter
- Volunteer Agreement Panel: `/admin/certificates` (VolunteerAgreementPanel.tsx)
- Compliance Widget: sidebar widget showing sign/counter-sign status (VolunteerComplianceWidget.tsx)
- Template preview: formal volunteer term template visible to admin
- Verification: `/verify/[code]` — public page shows signer + counter-signer info

### Publications
- `get_publication_submissions()` — pipeline list
- `create_publication_submission()` — new submission
- `update_publication_submission_status()` — status change

### System
- `trigger_backup()` — manual backup to R2
- `auto_archive_done_cards()` — housekeeping

---

## How to Add a New Admin Page

1. Create `src/pages/admin/my-feature.astro`:
```astro
---
import AdminLayout from '../../layouts/AdminLayout.astro';
import { getLangFromURL, t, type Lang } from '../../i18n/utils';
const lang: Lang = getLangFromURL(Astro.url.pathname + Astro.url.search);
---
<AdminLayout title="My Feature" breadcrumbs={[{label:'Section'},{label:'My Feature'}]}>
  <main class="max-w-[1100px] mx-auto px-4 pb-12">
    <!-- Content here -->
  </main>
</AdminLayout>
```

2. Add to `AdminSidebar.tsx` — find the appropriate section and add a link.

3. If interactive, create a React island in `src/components/admin/` and use `client:load`.

4. If it needs shared constants, import from `src/lib/admin/constants.ts`.

---

## Replication Guide for Other PMI Chapters

To adapt the admin for another chapter:

1. **Constants** (`src/lib/admin/constants.ts`):
   - Update `TRIBE_NAMES`, `TRIBE_LEADERS`, `TRIBE_COLORS` for your tribes
   - Update `CHAPTER_FULL` for your chapter names
   - Update `CYCLE_META` for your cycle dates

2. **Sidebar** (`AdminSidebar.tsx`):
   - Remove sections not relevant to your chapter
   - Add chapter-specific pages if needed

3. **Permissions** (`src/lib/permissions.ts`):
   - Tier model is generic — adjust `operational_role` values if different

4. **RPCs**: All admin RPCs use `SECURITY DEFINER` and check `auth.uid()`. No changes needed unless schema differs.

5. **i18n**: All labels are in `src/i18n/`. Add your locale or modify existing translations.
