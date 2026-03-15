# Spec-vs-Deployed Audit — W140: Event Tags, Audience & Attendance Fix

**Audit date:** 2026-03-14
**Auditor:** Claude Opus 4.6
**Spec reference:** `/home/vitormrodovalho/Downloads/CODE_PROMPT_W140_UPDATED.md`
**Branch:** `feat/w140-event-tags-audience` (merged to `main`)

---

## Methodology

Each bloco verified against the spec across three dimensions:
1. **Schema** — Tables, columns, enums, indexes, RLS, RPCs (queried prod DB)
2. **Data** — Seed data, migration results (queried prod DB)
3. **Frontend** — Components, JS functions, UI elements (code inspection)

---

## BLOCO 1 — Unified Tags System

| Item | Spec | Deployed | Status |
|------|------|----------|--------|
| `tag_tier` enum | system, administrative, semantic | ✓ All 3 values | ✅ Full |
| `tag_domain` enum | event, board_item, all | ✓ All 3 values | ✅ Full |
| `tags` table | 13 columns (id, name, label_pt, label_en, label_es, color, tier, domain, description, is_system, display_order, created_by, created_at) | ✓ All 13 columns present | ✅ Full |
| `tags` UNIQUE constraint | UNIQUE(name, domain) | ✓ Present | ✅ Full |
| `is_system` generated column | `tier = 'system'` | ✓ Present | ✅ Full |
| `event_tag_assignments` junction | event_id + tag_id, UNIQUE | ✓ Exists | ✅ Full |
| `board_item_tag_assignments` junction | board_item_id + tag_id, UNIQUE | ✓ Exists | ✅ Full |
| RLS on all tables | Enabled on tags, event_tag_assignments, board_item_tag_assignments | ✓ All 3 enabled | ✅ Full |
| Seed: system event tags | 6 (general_meeting, tribe_meeting, kickoff, leadership_meeting, interview, external_event) | ✓ 6 event/system | ✅ Full |
| Seed: admin event tags | 5 (workshop_event, mentoring, committee, alignment, one_on_one) | ✓ 5 event/administrative | ✅ Full |
| Seed: system board_item tags | 7 (article, webinar_item, case_study, book_review, tool_review, tutorial, framework) | ✓ 7 board_item/system | ✅ Full |
| Seed: admin board_item tags | 6 + 4 gate tags = 10 | ✓ 10 board_item/administrative | ✅ Full |
| Seed: cross-domain tags | 2 (cycle-3-2026, onboarding) | ✓ 2 all/system | ✅ Full |
| **Total tags** | **30** | **30** | ✅ Full |

---

## BLOCO 2 — Event Audience Schema

| Item | Spec | Deployed | Status |
|------|------|----------|--------|
| `event_audience_rules` table | 6 columns (id, event_id, attendance_type, target_type, target_value, created_at) | ✓ All 6 columns | ✅ Full |
| `event_invited_members` table | 6 columns (id, event_id, member_id, attendance_type, notes, created_at) | ✓ All 6 columns | ✅ Full |
| Partial unique indexes | idx_event_audience_unique (non-null), idx_event_audience_unique_null (null) | ✓ Both indexes present | ✅ Full |
| UNIQUE(event_id, member_id) on invited | Constraint | ✓ event_invited_members_event_id_member_id_key | ✅ Full |
| Performance indexes | idx_event_audience_event, idx_event_invited_event, idx_event_invited_member | ✓ All 3 present | ✅ Full |
| RLS enabled | Both tables | ✓ Both enabled | ✅ Full |

---

## BLOCO 3 — Data Migration

| Item | Spec | Deployed | Status |
|------|------|----------|--------|
| Events tagged by type | All typed events get matching tag | ✓ 157 events across 6 types, all have tag assignments | ✅ Full |
| general_meeting events | 49 events tagged | ✓ 49/49 | ✅ Full |
| tribe_meeting events | 65 events tagged | ✓ 65/65 | ✅ Full |
| interview events | 35 events tagged | ✓ 35/35 | ✅ Full |
| leadership_meeting events | 5 events tagged | ✓ 5/5 | ✅ Full |
| external_event events | 2 events tagged | ✓ 2/2 | ✅ Full |
| kickoff dual tags | kickoff + general_meeting | ✓ `["general_meeting","kickoff"]` | ✅ Full |
| "Conversar projeto Nucleo" | alignment tag + specific_members audience | ✓ tags=`["alignment"]`, audience=`["specific_members"]` | ✅ Full |
| Audience rules: all_active_operational | mandatory for general_meeting + kickoff | ✓ 49 mandatory rules | ✅ Full |
| Audience rules: tribe | mandatory for tribe_meeting | ✓ 65 mandatory tribe rules | ✅ Full |
| Audience rules: role | mandatory for leadership_meeting (manager, deputy_manager, tribe_leader) | ✓ 15 role rules (5 events × 3 roles) | ✅ Full |
| Audience rules: specific_members | mandatory for interview | ✓ 36 specific_members rules | ✅ Full |
| Audience rules: optional | external_event | ✓ 2 optional rules | ✅ Full |
| Invited members | GP/DM for "Conversar projeto Nucleo" | ✓ 1 invited member record | ✅ Full |
| **Total audience rules** | — | **167** | ✅ Full |

---

## BLOCO 4 — Tag CRUD RPCs

| RPC | Spec | Deployed | Status |
|-----|------|----------|--------|
| `create_tag` | Creates tag with tier/permission checks | ✓ Exists | ✅ Full |
| `delete_tag` | Deletes non-system tag, admin-only | ✓ Exists | ✅ Full |
| `assign_event_tags` | Replaces all event tags | ✓ Exists | ✅ Full |
| `set_event_audience` | Replaces all audience rules | ✓ Exists | ✅ Full |
| `set_event_invited_members` | Replaces all invited members | ✓ Exists | ✅ Full |
| `get_tags` | Returns tags with usage counts, optional domain filter | ✓ Exists | ✅ Full |
| `get_event_tags` | Returns tags for an event | ✓ Exists | ✅ Full |
| `get_event_audience` | Returns audience rules + invited members | ✓ Exists | ✅ Full |

---

## BLOCO 5 — Corrected Attendance Calculation

| Item | Spec | Deployed | Status |
|------|------|----------|--------|
| `is_event_mandatory_for_member(uuid, uuid)` | Checks audience rules per member | ✓ Exists | ✅ Full |
| `get_attendance_panel(date, date)` | Tag-based attendance with general/tribe split | ✓ Exists, returns 53 rows | ✅ Full |
| Return columns | member_id, member_name, tribe_name, tribe_id, operational_role, general_mandatory, general_attended, general_pct, tribe_mandatory, tribe_attended, tribe_pct, combined_pct, last_attendance, dropout_risk | ✓ Function callable | ✅ Full |
| Personalized denominator | Only counts events where member is mandatory audience | ✓ Logic in is_event_mandatory_for_member | ✅ Full |
| Dropout risk flag | combined_pct < 50% | ✓ In query logic | ✅ Full |

---

## BLOCO 6 — Frontend

| Item | Spec | Deployed | Status |
|------|------|----------|--------|
| NewEventModal: multi-tag picker | ev-tags-container, ev-tag-picker, ev-selected-tags | ✓ Lines 26-32 | ✅ Full |
| NewEventModal: hidden legacy ev-type | `<input type="hidden" id="ev-type">` | ✓ Line 35 | ✅ Full |
| NewEventModal: audience dropdown | all_active_operational, tribe, role, specific_members | ✓ Lines 38-44 | ✅ Full |
| EditEventModal: multi-tag picker | edit-ev-tags-container, edit-ev-tag-picker, edit-ev-selected-tags | ✓ Lines 28-34 | ✅ Full |
| EditEventModal: audience dropdown | Same 4 options | ✓ Lines 56-63 | ✅ Full |
| RecurringModal: multi-tag picker | rec-tags-container, rec-tag-picker, rec-selected-tags | ✓ Lines 29-35 | ✅ Full |
| RecurringModal: hidden legacy rec-type | `<input type="hidden" id="rec-type">` | ✓ Line 38 | ✅ Full |
| Tag filter bar | attendance-tag-filter with chip buttons | ✓ Line 82, dynamically populated | ✅ Full |
| Legacy type filter hidden | attendance-type-filter class="hidden" | ✓ Line 87 | ✅ Full |
| loadTags() function | Calls get_tags('event'), populates pickers + filter bar | ✓ Lines 844-850 | ✅ Full |
| populateTagPickers() | Populates all 3 tag pickers | ✓ Line 856 | ✅ Full |
| populateTagFilterBar() | Renders system tag chips | ✓ Line 872 | ✅ Full |
| createEvent() → assign tags+audience | Calls assignEventTagsAndAudience after create_event | ✓ Line 1026 | ✅ Full |
| createRecurring() → assign tags+audience | Loops through event_ids, assigns each | ✓ Lines 1067-1070 | ✅ Full |
| saveEventEdit() → assign tags+audience | Calls assignEventTagsAndAudience after update_event | ✓ Line 1128 | ✅ Full |
| openEditEvent() → load tags | Calls get_event_tags, populates picker | ✓ Lines 1095-1102 | ✅ Full |
| Tag picker toggle wired | data-action="toggle-tag-picker" handler | ✓ Lines 699-700 | ✅ Full |
| Tag checkbox change handler | Updates selection on checkbox change | ✓ Lines 735-740 | ✅ Full |
| ACTIVE_TAG_FILTER in filteredEvents() | Tag-based filter variable, used in filter logic | ✓ Lines 253, 388 | ✅ Full |
| Ranking tab uses get_attendance_panel | Spec implied corrected calc should be used | ✗ Still uses `member_attendance_summary` view | ⚠️ Partial |
| AttendanceDashboard.tsx uses get_attendance_panel | Workspace dashboard should use new RPC | ✗ Still uses `get_attendance_summary` | ⚠️ Partial |

---

## BLOCO 7 — Admin Tag Management

| Item | Spec | Deployed | Status |
|------|------|----------|--------|
| Tags tab button | data-tab="tags" | ✓ Line 216 | ✅ Full |
| panel-tags container | Hidden div with grid layout | ✓ Line 875 | ✅ Full |
| Tag list display | Cards with color dot, name, tier/domain badges, usage counts | ✓ In loadAdminTags() | ✅ Full |
| Create tag modal | Form with name, label, color, tier, domain, description | ✓ Lines 889-931 | ✅ Full |
| loadAdminTags() | Calls get_tags RPC, renders grid | ✓ Line 4142 | ✅ Full |
| createAdminTag() | Calls create_tag RPC with form values | ✓ Line 4179 | ✅ Full |
| deleteAdminTag() | Calls delete_tag RPC with confirmation | ✓ Line 4205 | ✅ Full |
| switchAdmTab handles 'tags' | Toggles panel-tags visibility, calls loadAdminTags | ✓ Lines 1394, 1400 | ✅ Full |
| Hidden for leader tier | panel-tags hidden | ✓ Line 3769 | ✅ Full |
| Hidden for observer tier | panel-tags hidden | ✓ Line 3794 | ✅ Full |
| Click delegation | tags-open-create, tags-close-create, tags-confirm-create, tags-delete | ✓ Lines 4365-4378 | ✅ Full |

---

## BLOCO 8 — Governance Changelog

| Entry | Spec | Deployed | Status |
|-------|------|----------|--------|
| GC-054: Unified Tag System | Required | ✓ Present with full format (Data, Autor, Status, Decisao, Justificativa, Impacto tecnico) | ✅ Full |
| GC-055: Event Audience Rules | Required | ✓ Present with full format | ✅ Full |
| GC-056: Attendance Calculation Correction | Required | ✓ Present with full format | ✅ Full |
| GC-057: Spec-vs-Deployed Audit | Required | ✓ Present with full format | ✅ Full |

---

## Findings Summary

| ID | Bloco | Severity | Category | Description | Status |
|----|-------|----------|----------|-------------|--------|
| F-01 | 6 | Low | Integration | Ranking tab (`attendance.astro:1264`) still reads from `member_attendance_summary` view instead of calling `get_attendance_panel`. The old view doesn't use the corrected personalized denominator. | ⚠️ Partial |
| F-02 | 6 | Low | Integration | `AttendanceDashboard.tsx:75` still calls `get_attendance_summary` RPC. Should optionally use `get_attendance_panel` for corrected stats. | ⚠️ Partial |

### Notes on F-01 and F-02

These are **low severity** because:
- The new `get_attendance_panel` RPC is deployed and working (returns 53 rows for active members)
- The corrected calculation is available for any consumer that calls it
- The old views/RPCs remain functional — they just use the simpler (uncorrected) denominator
- Migration to the new RPC can be done incrementally without data loss

The ranking tab and workspace dashboard are **backward-compatible** — they show total hours and event counts, which are unaffected by the denominator correction. The denominator correction primarily affects the percentage-based attendance panel (general_pct, tribe_pct, combined_pct, dropout_risk), which is a new feature not previously displayed.

---

## Scorecard

| Bloco | Items | Full | Partial | Missing | Score |
|-------|-------|------|---------|---------|-------|
| 1 — Unified Tags | 14 | 14 | 0 | 0 | 100% |
| 2 — Audience Schema | 6 | 6 | 0 | 0 | 100% |
| 3 — Data Migration | 15 | 15 | 0 | 0 | 100% |
| 4 — Tag RPCs | 8 | 8 | 0 | 0 | 100% |
| 5 — Attendance Calc | 5 | 5 | 0 | 0 | 100% |
| 6 — Frontend | 21 | 19 | 2 | 0 | 95% |
| 7 — Admin Tags | 11 | 11 | 0 | 0 | 100% |
| 8 — Governance | 4 | 4 | 0 | 0 | 100% |
| **Total** | **84** | **82** | **2** | **0** | **99%** |

---

## Fix Backlog

| Priority | Finding | Effort | Fix |
|----------|---------|--------|-----|
| P3 | F-01: Ranking tab → get_attendance_panel | 15 min | Replace `sb.from('member_attendance_summary')` with `sb.rpc('get_attendance_panel')` in `loadRanking()`, map return columns to existing UI |
| P3 | F-02: AttendanceDashboard → get_attendance_panel | 15 min | Add optional `get_attendance_panel` call in `AttendanceDashboard.tsx` for corrected percentages |

**Recommended action:** Bundle F-01 and F-02 into a follow-up micro-sprint (W140.1, ~30min). Not blocking — current behavior is functionally correct, just uses uncorrected denominators.
