# Webinars Module Discovery

Status: discovery complete, with the first admin orchestration surface now implemented on top of this direction.

## Decision Summary

- The first webinars MVP should use `events` as the operational source of truth, with `type='webinar'`.
- The MVP should reuse the current stack around `attendance`, `certificates`, `hub_resources`, meeting artifacts / presentations, communications, and admin analytics.
- The existing `webinars` table should not become a second operational source of truth until the product explicitly needs entities that `events` does not cover well.
- The first implementation should stay focused on internal or member-first webinars. Public registration, external attendee operations, and speaker CRM stay out of scope.

## What Already Exists

- `src/pages/attendance.astro` already treats `webinar` as an event type and uses the event creation, recurring scheduling, roster, and self check-in flows.
- `src/lib/database.gen.ts` already exposes the generic operational tables needed for a first pass: `events`, `attendance`, `certificates`, `hub_resources`, `comms_metrics_daily`, and `member_chapter_affiliations`.
- `src/pages/presentations.astro` already renders meeting artifacts and recording links.
- `src/pages/workspace.astro` already supports `asset_type='webinar'` for replay or knowledge-library surfacing.
- `src/pages/admin/comms.astro` and `src/pages/admin/analytics.astro` already cover the first reporting and communications needs without a webinar-specific BI stack.
- `src/pages/admin/webinars.astro` already exists as the admin-only placeholder surface.

## Recommended MVP Scope

- Agenda and scheduling: create webinar sessions through the existing event flow, with title, date, duration, meeting link, audience, recorded flag, and optional tribe or chapter context.
- Speakers: store speaker names and context as copy or notes for now; do not create first-class speaker entities yet.
- Attendance: use member-authenticated check-in plus leader or admin roster correction exactly as the current attendance flow already supports.
- Recordings and materials: publish replay links through `youtube_url`, meeting artifacts, and `hub_resources`.
- Certificates: allow only manual or exception-based issuance through the generic `certificates` model for the first pass.
- Analytics: reuse attendance, participation, and communications aggregates before introducing webinar-specific dashboards.
- Communications: use announcements and the existing communications stack for invite, reminder, and follow-up operations.

## Explicitly Out Of Scope

- New `webinar_*` schema for registrations, speakers, or series.
- Public or anonymous registration inside the Hub.
- Native Zoom, Meet, or YouTube API integrations, provider webhooks, or external attendance sync.
- Automatic certificate generation or bulk certificate orchestration.
- Advanced webinar BI such as attribution, no-show funneling, transcript analysis, or chat and poll analytics.

## Operational Flow

1. Plan the session as `events.type='webinar'` with the required operational metadata.
2. Publish the webinar through the existing comms surfaces and, when useful, add a replay or library card to `hub_resources`.
3. Capture live attendance through the current authenticated attendance path, with leader or admin correction when necessary.
4. After the session, add recording and supporting artifacts, then run follow-up communications and any manual certificate handling.

## ACL And LGPD Guidance

- `/admin/webinars` remains an `admin` route and should stay discovery or orchestration focused unless a future ACL review expands it.
- The webinar MVP should remain member-first because the current attendance model is tied to authenticated `member_id`.
- Analytics should stay aggregated and admin-scoped; do not introduce email or full-name based webinar analytics.
- If external registration or public attendee tracking is ever approved, it must come with a dedicated ACL, RLS, and consent review before schema expansion.

## Data Model Decision

- `events` is the operational truth for scheduling, attendance, and replay state in V1.
- The standalone `webinars` table currently creates a dual-source-of-truth risk because it overlaps with `events` while not being connected to attendance or the existing reporting path.
- A later schema expansion is justified only if the product approves at least one of these needs:
  - reusable external speaker profiles
  - public or external registration and waitlist management
  - webinar-specific certificate automation
  - a chapter or sponsor programming model that cannot be represented safely on top of `events`

## Next Implementation Slice

- If the team still wants less operator effort, evolve the new contextual aids into lightweight reusable helpers for message drafting or event QA without cloning the underlying workflows locally.
- Review `docs/WEBINARS_CONVERGENCE_PROPOSAL.md` and approve whether the existing `webinars` table should be converged into `events` or retired before any broader webinar schema work begins.
- Keep avoiding webinar-local CRUD until there is an approved need that the current event, content, and comms stack cannot cover safely.

## Follow-Through Already Applied

- `/admin/webinars` no longer stays as a placeholder: it now reads webinar sessions from `get_events_with_attendance`.
- The admin panel now checks replay publication across both reuse surfaces:
  - `Presentations` via `list_meeting_artifacts` and `meeting_artifacts.event_id`
  - `Workspace` via active `hub_resources` with `asset_type='webinar'`
- This keeps the replay follow-up path visible to operators without introducing a dedicated webinar publishing schema.
- The admin panel now also derives a recommended next action per webinar, so operators can move directly to the right existing module (`Attendance`, `Admin Comms`, `Presentations`, or `Workspace`) instead of inferring the handoff manually.
- `Presentations` and `Workspace` now accept URL-driven filters (`q`, `tribe`, `type`) so `/admin/webinars` can hand operators off into a pre-filtered follow-through view instead of a generic destination page.
- `Attendance` now accepts webinar handoff state (`tab`, `type`, `q`, `eventId`, `action`, `edit`) so operators can land on the right event, with the intended context and optional edit modal already open.
- `Admin Comms` now accepts webinar handoff state (`focus`, `context`, `stage`, `q`, `title`, `date`) so the broadcast history view can open already scoped to the current webinar follow-through.
- `Attendance` now also exposes a small edit-time assistant for webinar-specific tasks such as filling the meeting link or replay URL, while `Admin Comms` exposes a contextual playbook with reusable subject/body suggestions and copy actions.
