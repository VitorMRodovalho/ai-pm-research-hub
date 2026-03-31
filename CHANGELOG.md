# Changelog

## 2026-03-31 — v2.8.0 MCP Expansion: 42 Tools Covering All Personas

### MCP — 13 New Tools (29 → 42)
- **P1 — 7 tools:** `get_event_detail`, `get_comms_dashboard`, `get_campaign_analytics`, `get_partner_pipeline`, `get_public_impact_data`, `get_curation_dashboard`, `get_tribe_deliverables`
- **P2 — 4 tools:** `get_pilots_summary`, `get_comms_metrics_by_channel`, `get_anomaly_report`, `get_portfolio_health`
- **P3 — 2 tools:** `get_volunteer_funnel`, `get_near_events`
- Full persona coverage: Sponsors, Comms team, GP/Management, Chapter liaisons, Members
- Fixed SQL bug in `get_public_impact_data` (nested aggregate in chapters_summary)

### Migration
- `20260331010000_fix_public_impact_nested_aggregate.sql`

## 2026-03-31 — v2.7.1 MCP Auto-Refresh: Transparent Token Renewal

### MCP
- **Server-side auto-refresh:** Worker proxy now detects expired JWTs before forwarding to upstream, refreshes transparently using stored `refresh_token` from KV (30-day TTL). Users stay connected for up to 30 days without re-authentication.
- Token endpoint (`/oauth/token`) now stores `mcp_refresh:{user_id}` in KV on both `authorization_code` and `refresh_token` grants.
- MCP proxy decodes JWT payload, checks `exp` with 5-minute buffer, and auto-refreshes via Supabase Auth API when expired.
- Eliminates dependency on MCP host implementing `grant_type=refresh_token` (most hosts don't yet).

### Blog
- Updated MCP Server Launch post (3 languages) with new "Continuous sessions: transparent auto-refresh" section explaining the best practice.

### Documentation
- CLAUDE.md version bump to v2.7.1
- MCP rules updated with auto-refresh architecture details

## 2026-03-31 — v2.7.0 Sprint 10: OAuth Refresh, WCAG AA, MCP Health, Campaign Tracking

### MCP
- OAuth refresh_token support: consent sends refresh_token, exchange stores it, token endpoint supports `grant_type=refresh_token`
- Per-route health monitoring with auto-discovery via `mcp_usage_log` (no hardcode)
- Fixed member_id logging in `get_upcoming_events` and `get_hub_announcements` (was null → broken top_tools.users metric)
- Verified on 4 hosts: Claude.ai (9/10), ChatGPT (8/10), Perplexity (8/10), Claude Code — 30/30 route calls successful
- OAuth discovery announces `refresh_token` as supported grant type

### CSS & Accessibility
- WCAG AA global contrast fix: --text-secondary, --text-muted, --text-on-dark-muted bumped for ≥4.5:1 ratio on dark bg
- Semantic status card CSS vars (--status-info/success/warning/accent/danger) for light+dark modes
- Global prose content styles: tables, code, blockquote in theme.css
- Migrated funnel cards + category badges from Tailwind inline to CSS vars

### Campaign & Email
- Resend open/click tracking: `tracking: { open: true, click: true }` in send-campaign payload
- Click Tracking + Open Tracking enabled on pmigo.org.br domain in Resend dashboard

### Blog
- Fixed langKey pt vs pt-BR mismatch in blog/[slug] and blog/index rendering
- Normalized all 9 posts: pt→pt-BR, en→en-US, es→es-LATAM keys
- Rewrote MCP Server Launch post: 29 routes, correct URL, Perplexity added
- Fixed TypeScript `as any` leak in define:vars script
- Fixed legacy URLs (pages.dev, workers.dev) across all posts

### Infrastructure
- 11 irrelevant MCP servers disabled in project .claude/settings.json (~375K tokens freed)
- Migration: `20260330010000_mcp_adoption_stats_v2_route_health.sql`

### Commits (8)
- `e563ae1` feat: Sprint 10 — campaign tracking, CSS contrast, MCP health, OAuth refresh
- `30e69d4` fix: remove TypeScript `as any` from define:vars in blog/[slug]
- `874807a` fix: blog langKey fallback for pt-BR keys + MCP post rewrite
- `4263423` fix: global prose table/code CSS + blog data normalization
- `e23f30e` fix: global dark mode contrast — WCAG AA compliance
- `caca787` docs: add Perplexity to MCP compatible hosts, fix tool count
- `d3ae5b7` fix: log member_id in get_upcoming_events and get_hub_announcements

## 2026-03-29 — Sprint 4: PostHog Events, Designation Filter, Smoke Test, MCP v2.3.0

### Sprint 4 Deliverables
- **S3.3 PostHog Events:** 7 custom events (board_card_moved, webinar_viewed, blog_post_read, profile_updated, certificate_issued, governance_cr_submitted) + posthog.identify() with person properties
- **S3.2 Designation Filter:** Shared RoleDesignationFilter component + integration on /admin/members
- **GC-097 P2 Smoke Test:** 11 automated endpoint checks (`npm run smoke`) — site, OAuth, MCP, EF, public RPCs
- **MCP v2.3.0:** SDK 1.27.1 (protocolVersion 2025-11-25), SSE response wrapping, InMemoryTransport, notification 202 handling
- **Custom domain:** nucleoia.vitormr.dev consolidated (301 redirects from legacy hosts)
- **Claude Code structure:** .claude/rules/, agents/, skills/, hooks/ with PostCompact context re-injection

### Infrastructure
- MCP transport: StreamableHTTPServerTransport → InMemoryTransport (Deno compatible) + SSE wrapping
- OAuth debug logging via KV (temporary, for connector troubleshooting)
- SDK 1.28.0 Zod migration attempted but blocked by BOOT_ERROR (Node.js deps on Deno) — deferred to Sprint 5

## 2026-03-28/29 — v2.2.1: Webinar Governance, LGPD, MCP 23 Tools, Analytics, Custom Domain

### GC-160: Webinar Governance
- `webinars` + `webinar_lifecycle_events` tables with co-management (co_manager_ids, event_id, board_item_id)
- 5 RPCs: list_webinars_v2, upsert_webinar, link_webinar_event, get_webinar_lifecycle, webinars_pending_comms
- /admin/webinars rewritten: CRUD modal, filters, lifecycle timeline
- /admin/comms: "Webinars pendentes de campanha" section
- /webinars: public view (confirmed + replays)
- 6 pipeline webinars migrated from board_items
- Notification triggers for 4 stakeholder groups

### GC-161: MCP P1 (19 tools)
- 4 new tools: get_my_attendance_history, list_tribe_webinars, create_tribe_event, get_comms_pending_webinars
- mcp_usage_log table + log_mcp_usage RPC + get_mcp_adoption_stats
- Usage logging on all 19 tools

### GC-162: LGPD RLS Hardening (P0 Security)
- ~20 tables locked: members PII, attendance, gamification, boards, events, CRs, publications
- Anon/Ghost blocked from PII; public RPCs: get_public_leaderboard, get_public_platform_stats
- /gamification public fallback via RPC

### GC-163: Adoption Dashboard v2
- get_auth_provider_stats RPC (auth providers, ghost visitors, secondary auth)
- get_adoption_dashboard enhanced: mcp_usage, auth_providers, designation_counts
- MCP card + Auth providers card + designation filter + MCP column
- PostHog native charts: DAU/WAU line, top pages bar, traffic doughnut, rage clicks, retention heatmap
- posthog-proxy v2 EF with Query API (5 whitelisted queries)

### GC-164: MCP P2 (23 tools)
- Transport fix: mcp-lite@0.10.0 → @modelcontextprotocol/sdk@1.12.1
- 4 new tools: get_my_certificates, search_hub_resources, get_adoption_metrics, get_chapter_kpis
- Version: v2.2.0 → v2.2.1

### Infrastructure
- Custom domain: nucleoia.vitormr.dev (bypasses .workers.dev Bot Fight Mode)
- Middleware: 301 redirects from legacy hosts + manual CSRF (checkOrigin bypass for OAuth/MCP)
- OAuth fixes: CORS on .well-known, client_secret placeholder, issuer dedup
- 4 EFs redeployed with nucleoia.vitormr.dev URLs
- i18n: 19 duplicate publication keys removed

### Bug Fixes
- Attendance toggle: memberReady state + useMemo deps
- TribeAttendanceTab: 6 event type icons added
- AttendanceGridTab: SSR window guard
- CI: public /webinars test assertions updated
- Certificates i18n redirects (en/es)

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
