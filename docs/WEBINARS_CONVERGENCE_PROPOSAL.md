# Webinars Convergence Proposal

Status: proposal ready for approval before any broader webinar schema expansion.

## Recommendation

Adopt `events` as the only operational source of truth for webinars now, deprecate `webinars` / `list_webinars` for new product work immediately, and decide physical retirement only after a short live-data audit.

This is a **converge operationally now, retire physically after audit** recommendation.

## Why This Is Recommended

- `events` is already connected to the working flow:
  - scheduling and edits via `create_event`, `create_recurring_weekly_events`, and `update_event`
  - attendance and roster via `attendance`, `get_events_with_attendance`, `register_own_presence`, and `mark_member_present`
  - replay follow-through via `meeting_artifacts.event_id`, `hub_resources`, `Presentations`, `Workspace`, and `/admin/webinars`
- `webinars` is currently isolated:
  - one table
  - one read RPC: `list_webinars`
  - no attendance relation
  - no replay-artifact relation
  - no current runtime consumer in the webinar operator flow
- Keeping both models alive increases drift risk exactly where the product is getting deeper: scheduling, replay publication, follow-up communications, and reporting.

## Additional Product Constraint To Preserve

The Núcleo is not only scheduling internal webinars. The project also needs to coordinate joint programming with other PMI chapter initiatives and partner efforts, where the Núcleo project manager, deputy manager, communications team, and external initiative managers may need to align:

- event pipeline and timing
- date and channel
- topic and positioning
- who leads which part of the operation
- what is published before and after the event

This can include webinars, events, congresses, awards, and other invited initiative formats. Delivery channels may vary (`Airmeet`, `Zoom`, `YouTube Live`, and others), while the post-event artifact path should still converge into the Núcleo publication journey, especially the YouTube playlist and Hub access surfaces.

## Why This Constraint Strengthens The Recommendation

- This future is broader than "webinars as a special object".
- A generic operational backbone centered on `events` is a better fit for cross-initiative programming than promoting a webinar-specific table.
- If the platform later needs richer partnership coordination, the likely next model is not `webinars` as truth, but a generic extension around:
  - partner initiative context
  - external coordinators or guest operators
  - event channel/provider metadata
  - publication funnel status
- In other words, the current decision should avoid hardening the product around a webinar-only schema branch that will likely be too narrow for the real operating model.

## Evidence In Repo

### `events`

- `public.events` already contains the webinar-operational fields the current product uses:
  - `type`
  - `date`
  - `duration_minutes`
  - `meeting_link`
  - `youtube_url`
  - `is_recorded`
  - `audience_level`
  - `tribe_id`
  - `created_by`
- Current webinar UI and operator flow already depend on `events`:
  - `src/pages/attendance.astro`
  - `src/pages/admin/webinars.astro`
  - `src/pages/presentations.astro`
  - `src/pages/workspace.astro`
  - `src/pages/admin/comms.astro`

### `webinars`

- `public.webinars` was introduced in `supabase/migrations/20260309140000_webinars_and_rpc_security.sql`.
- The table carries:
  - `title`
  - `description`
  - `scheduled_at`
  - `duration_min`
  - `status`
  - `chapter_code`
  - `tribe_id`
  - `organizer_id`
  - `meeting_link`
  - `youtube_url`
  - `notes`
- The same migration adds `list_webinars(p_status text default null)`.
- In `src/lib/database.gen.ts`, `list_webinars` returns rows directly from `webinars`, but the current operator flow does not use it.

## Options Considered

### 1. Keep `webinars` as long-term non-authoritative metadata

Not recommended.

- Pros:
  - no immediate migration work
  - preserves `chapter_code`, `notes`, and `status`
- Cons:
  - keeps dual-source ambiguity alive
  - encourages future drift
  - makes every webinar feature ask which table is real

### 2. Promote `webinars` to authoritative operational truth

Not recommended.

- Pros:
  - preserves webinar-specific fields already present there
- Cons:
  - would require reconnecting attendance, replay, analytics, and current admin flow
  - reverses the direction already validated in Waves 26-33
  - increases implementation risk with little immediate product gain

### 3. Converge on `events` now and retire `webinars` after audit

Recommended.

- Pros:
  - aligns schema policy with real runtime behavior
  - reduces future drift and mental overhead
  - preserves momentum on the already working operator flow
- Cons:
  - needs a short audit of live `webinars` rows
  - may need a minimal follow-through if some webinar-only fields are still genuinely needed

## Proposed Decision

1. Effective immediately:
   - `events` is the only operational webinar source of truth.
   - No new UI, RPC, or workflow should be built on top of `webinars` or `list_webinars`.
2. Treat `webinars` as deprecated compatibility state, not as active product state.
3. Run a short live-data audit before any destructive schema change.
4. After the audit:
   - if `webinars` is empty, stale, or disposable: remove it
   - if `webinars` has meaningful live rows: migrate them into `events` using an approved mapping
5. If broader cross-chapter orchestration is approved later, design it as a generic event-programming extension on top of `events`, not as a re-promotion of `webinars` to primary truth.

## Short Audit Questions

Before a migration or drop:

1. Does production still contain meaningful rows in `webinars`?
2. Are `chapter_code`, `description`, `notes`, `organizer_id`, or `status` still required operationally?
3. If yes, should those fields:
   - move into `events` via a minimal approved extension, or
   - be intentionally discarded as no longer relevant to the current product scope?

## Recommended Execution Path

### Phase 1. Freeze

- Keep `list_webinars` out of new frontend work.
- Mark `webinars` as deprecated in docs and architectural notes.

### Phase 2. Audit

- Inspect live rows in `webinars`.
- Classify them as:
  - disposable legacy/test data
  - operationally relevant
  - partially relevant because of fields not present on `events`

### Phase 3. Converge

- If rows are disposable:
  - drop `list_webinars`
  - drop `webinars`
- If rows matter:
  - define the exact mapping into `events`
  - migrate data once
  - remove `list_webinars`
  - retire `webinars` after verification

### Phase 4. Extend Only If Product Requires It

Only consider new webinar-specific schema after explicit approval for needs such as:

- external registration or waitlists
- reusable speaker entities
- webinar-specific certificate automation
- chapter programming metadata that cannot be represented safely on top of `events`

If the approved need is actually broader partner programming across chapters and invited initiatives, prefer a generic event-orchestration model over a webinar-only branch.

## Recommendation Summary

The recommended decision is:

`events` becomes the sole webinar truth now; `webinars` is deprecated now; physical removal happens right after a short live-data audit confirms whether any rows or fields still matter.
