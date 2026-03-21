# Changelog

## 2026-03-21

### GC-116: Governance Change Management Infrastructure
- `manual_sections` table: 33 R2 sections with hierarchy, bilingual titles (PT/EN), page refs
- `change_requests` upgraded: 12 new columns — `cr_type`, `impact_level`, `manual_section_ids` linkage, approval workflow (`approved_by_members`, `approved_at`), implementation tracking (`implemented_by`, `implemented_at`), version tracking (`manual_version_from/to`)
- 5 SECURITY DEFINER RPCs: `get_manual_sections`, `get_change_requests` (with tier filtering), `submit_change_request`, `review_change_request`, `get_section_change_history`
- 13 candidate CRs seeded as draft (CR-001 to CR-013), linked to manual sections
- RLS: `manual_sections` read-only for authenticated, write via RPC only
- João Santos (PMI-RS) designated as `chapter_liaison`

### GC-114/114b: /attendance Events List Redesign
- Collapsible sections by event type (7 public + 3 GP-only)
- Past events first, future capped at 3 with "Ver todos" expander
- Type dropdown + tribe dropdown + search filters (dynamically generated)
- GP-only sections (1on1, parceria, entrevista) visible only to GP/superadmin
- Participant visibility: members see events where they have attendance records

### GC-113b: Future Events Denominator Fix (4 RPCs)
- `exec_cross_tribe_comparison`: 6 event queries bounded with `AND e.date <= CURRENT_DATE`
- `exec_tribe_dashboard`: 5 event queries bounded
- `get_annual_kpis`: `v_cycle_end` replaced with `LEAST(v_cycle_end, CURRENT_DATE)`
- `get_portfolio_dashboard`: added `overdue` status for past-due items

### GC-112: TipTap Meeting Minutes Editor
- `EventMinutesEditor` modal with TipTap rich text (reuses `RichTextEditor`)
- `EventMinutesIsland` React island for Astro ↔ React communication
- Past events show "Adicionar/Editar ata" buttons (permission-gated)
- Minutes rendered with prose class for TipTap HTML output

### GC-111: Tribe Grid Visual Parity
- Week grouping headers, dd/MMM date format, event type letter badges
- CI fix: `ui-stabilization` test updated for `get_selection_dashboard`

### GC-109/110: Attendance Rate Fix + Minutes/Agenda READ
- `scheduled` cell status for future events (📅, not clickable)
- Rate normalization (0-1 → 0-100%)
- `EventContentBadges` + `ExpandableContent` reusable components
- `get_tribe_events_timeline` RPC: `agenda_text` added to upcoming events

### GC-107: Attendance Interaction Layer
- `useAttendance` hook: fetchGrid, toggleMember (optimistic), selfCheckIn, batchToggle
- `AttendanceCell`: 5 visual states with permission-gated click handlers
- `AttendanceGrid`: full wrapper with sticky cols, filters, summary cards
- `SelfCheckInButton`: standalone for workspace/hero card
- Toggle with toast + undo (5s auto-dismiss)

### GC-106: Tribe Dashboard Events Timeline
- "Proximos Eventos" + "Reunioes Anteriores" blocks in Geral tab
- Meeting link for today/tomorrow, attendance fractions, recording links
- "Criar Evento" button (permission-gated)

### GC-105/105b: Tribe Navigation + Access Matrix
- Workspace hero card: "Acesso a todas as tribos" for admins without tribe_id
- `getTribePermissions()` helper (18 permission flags)
- Cross-tribe viewing banner (blue for members, purple for curators)

### GC-104: Enable Gamification + Attendance Tabs
- `switchTab()` and `validTabs` arrays updated to include gamification/attendance

### GC-103: Microsoft OAuth + LGPD Hardening
- "Entrar com Microsoft" button (Azure provider, scopes: email profile openid)
- Stakeholder login via institutional @pmi*.org emails

### GC-102: Org Chart + Workspace Audit
- `get_org_chart()` RPC: 3-dimension interactive structure
- `get_my_onboarding()` RPC: replaces direct query on RLS deny-all table
- Workspace audit: zero violations found

### GC-101: Pilots Schema Alignment
- Resolved metrics via `get_pilot_metrics` (auto_query values)
- Date inputs in edit modal (`p_started_at`/`p_completed_at`)
- Team member names resolved in detail view

### GC-100: Project Skill + Chart Fix
- `skills/nucleo-ia/SKILL.md`: 10 critical rules from past bugs
- Cycle report chart infinite loop fix (container height + destroy + rAF)
- Pilots page boot race condition fix (wait for both sb AND member)

## 2026-03-20

### Earlier GC entries
- GC-095 through GC-099: Selection pipeline, cycle report, homepage fixes
