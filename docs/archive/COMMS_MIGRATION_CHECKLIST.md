# Comms Team — Trello → Hub Migration Checklist

Status: **Ready for pilot testing**

## Current State

| Aspect | Status |
|--------|--------|
| Board exists in DB | Yes — "Hub de Comunicação" (`domain_key: communication`) |
| Board scope | `global` (all members can view) |
| Columns | `backlog → todo → in_progress → review → done` |
| Items imported | 54 total (28 backlog, 2 todo, 3 in progress, 1 review, 20 done) |
| Frontend page | `/admin/comms-ops` with BoardEngine + CommsDashboard |
| Access control | superadmin, manager, deputy_manager, comms_leader, comms_member (verified: Mayanna=comms_leader, Leticia Clemente=comms_member, Andressa=comms_member) |
| Drag-and-drop | Yes (desktop + mobile + keyboard) |
| Card detail | Title, description, assignee, reviewer, tags, due date, checklist, attachments |
| MemberPicker | Yes (searchable autocomplete for 66+ members) |
| Real-time sync | Yes (Supabase Realtime — changes appear in ~500ms) |

## What Works Today

- [x] Kanban board renders with 5 columns
- [x] Cards can be dragged between columns
- [x] Card detail panel opens on click
- [x] Assignee/reviewer can be set via MemberPicker
- [x] Tags, due dates, checklist supported
- [x] File attachments upload (5MB limit, pdf/png/jpg/docx/xlsx/pptx)
- [x] CommsDashboard shows metrics (backlog_count, overdue_count, by_status)
- [x] Real-time updates across tabs/users
- [x] Permission-gated: only comms team + managers can access

## Gaps / Action Items Before Go-Live

### Must Have
- [ ] **Verify imported items quality** — 54 items from Trello may need cleanup
  - Some may be duplicates or stale (check the 28 backlog items)
  - Action: Comms team reviews and archives stale items
- [ ] **Assign team members** — Current items likely have no assignee_id set
  - Action: Comms team assigns cards to Mayanna, Leticia, Andressa
- [x] **Storage bucket** — `board-attachments` bucket created (2026-03-12)
  - 5MB limit, pdf/png/jpg/docx/xlsx/pptx allowed
  - RLS policies: authenticated can upload/read, owner can delete

### Nice to Have
- [ ] **Labels/categories** — Board supports `labels` (jsonb) but no UI for managing label taxonomy
- [ ] **Filtered views** — BoardEngine has useBoardFilters (search + tag filter) but comms may want status-based filters
- [ ] **Email/Slack notifications** — No notification system when cards are assigned or moved
- [ ] **Due date reminders** — Cards have due_date but no automated reminders
- [ ] **Recurring tasks** — Some comms tasks (weekly newsletter, monthly report) need recurrence

## How to Test

1. Login as a comms team member or manager
2. Navigate to `/admin/comms-ops`
3. Verify the board loads with 5 columns
4. Try creating a new card, assigning someone, adding tags
5. Try dragging cards between columns
6. Open a card and verify all fields work
7. Test on mobile (should stack columns vertically)

## Rollback Plan

If issues arise, the Trello board remains the source of truth until the team formally migrates. No data is deleted from Trello.
