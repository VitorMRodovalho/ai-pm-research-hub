# p126 E2 Wave 3 Synthesis — Worker Mapper + Types

**Date:** 2026-05-09 (continued from p125 close)
**Sessão:** p126 (continuation)
**Predecessor:** ADR-0076 + Migrations 1-6 (p125 E1) + Wave 1 PM drafts E2 + Wave 2 council parallel review (3 agents)
**Successor:** Wave 4 = PM accepts → commit + push → E3 next session

## Wave 2 council verdicts (3 agents)

| Agent | Verdict | Key findings |
|---|---|---|
| senior-software-engineer | YELLOW | 2 substantives + 4 DRAFTS — solid code, atomicity OK |
| ai-engineer | YELLOW | 2 BLOCKERS (E3-scoped) + 5 substantives — Decision 4 cycle freeze NOT in EF (deferred to E3) |
| code-reviewer | APPROVED WITH FIXES | 1 BLOCKER (service_history dedup) + 3 substantives + 3 DRAFTS |

**Convergence-strong items (≥2 agents)**:
- BLOCKER: insertServiceHistory dedup gap (3 agents) — fixed Wave 3
- consent_version hardcoded, no payload pass-through (3 agents) — fixed
- parseGeoFromLocation dead code (3 agents) — fixed
- certifications `?? ''` inconsistency (2 agents) — fixed

## Wave 3 fixes applied

### BLOCKER fix
1. **`insertServiceHistory` dedup** — new Migration 7 (`20260518070000_p125_e2_service_history_idempotency.sql`) adds UNIQUE INDEX on `(application_id, chapter_name, COALESCE(start_date, '1900-01-01'))`. `db.ts insertServiceHistory` changed from `.insert()` to `.upsert(rows, { onConflict: 'application_id,chapter_name,start_date', ignoreDuplicates: true })`.

### SUBSTANTIVE fixes
2. **`consent_version` payload read** — `ScriptApplication` extended with `consentVersion?: string` field; `mapScriptToNucleo` reads `app.consentVersion ?? \`termo-v2-${cycleCode}\`` for Cycle 4+ dispatch path.
3. **`parseGeoFromLocation` wired** — `mapScriptToNucleo` now uses parsed fallback when `profileLocation` present but parsed fields all null.
4. **`certifications` null-semantic** — changed `phaseBCerts ?? ''` to `phaseBCerts ?? null` for consistency.
5. **`application_date` in UPDATE** — added to `upsertSelectionApplication` UPDATE block (was missing — stale on re-import).

### DRAFT fixes
6. **`setEngagementEndDateSource` idempotency** — tightened guard to compare both source AND end_date (was only `!endDate`); SELECT now includes `end_date` column.
7. **Empty `else if` block** — replaced with `console.warn` for observability when ghost-member orphan canonical UPSERT skipped.
8. **`phase_b_processed` counter** — broadened detection beyond `pmi_data_fetched_at` to include any non-null Phase B field.
9. **`ORG_ID_DEFAULT` comment** — documented test-only fallback semantics.

## Items DEFERRED to E3 Wave 1

These are Wave 2 BLOCKERS but explicitly E3-scoped (not E2 worker code):

- **Decision 4 cycle freeze in `pmi-ai-triage` EF**: cycle-based prompt template selection. EF must SELECT `cycle_id` + branch on it. Current EF doesn't even read `cycle_id`.
- **`prompt_version` column in `ai_processing_log`**: schema change pre-Cycle 4.
- **`profile_about_me` excluded from `buildUserPrompt`**: structurally enforced today (column not in `SELECT_COLS`/`AppRow`), but fragile — needs explicit comment + invariant test.
- **`is_open_to_volunteer` invariant test**: grep CI test that asserts field never appears in EF prompt source.

These are documented as **E3 Wave 1 acceptance criteria**, not blockers for E2.

## Items DEFERRED to backlog (post-E3)

- **finalStatus partial-success logging** (code-reviewer S3): cron_run_log status='success' on partial failures masks ops issues. Needs CHECK constraint verification before adding `'partial_success'` value.
- **service_history start_date sentinel**: Migration 7 uses `COALESCE(start_date, '1900-01-01')` for unique index. If PMI returns far-past start_date (pre-1900?), edge case. Unlikely.
- **Phase B test fixtures**: unit tests para 3 new mapper helpers (mapPmiChapterMemberships, mapServiceHistory, parseGeoFromLocation) — recommended but not blocking.

## Files touched (E2 Wave 1 + Wave 3)

| File | Lines added/modified | Status |
|---|---|---|
| `cloudflare-workers/pmi-vep-sync/src/types.ts` | +52 (extended ScriptApplication + 3 new interfaces + extended SelectionApplicationUpsert + extended IngestSummary) | Wave 1 + Wave 3 fixes |
| `cloudflare-workers/pmi-vep-sync/src/script-mapper.ts` | +180 (extended mapScriptToNucleo + 3 new helpers, all wired) | Wave 1 + Wave 3 fixes |
| `cloudflare-workers/pmi-vep-sync/src/db.ts` | +120 (extended UPDATE + 4 new helpers with idempotent UPSERT) | Wave 1 + Wave 3 fixes |
| `cloudflare-workers/pmi-vep-sync/src/index.ts` | +60 (Phase B canonical wiring) | Wave 1 + Wave 3 fixes |
| `supabase/migrations/20260518070000_*.sql` | new (UNIQUE INDEX for service_history idempotency) | Wave 3 BLOCKER fix |

**TypeScript compile**: ✅ clean (`npx tsc --noEmit` zero errors).

## Approval status

- Wave 1+3 fixes complete
- TypeScript compiles clean
- All 3 Wave 2 verdicts addressed (1 BLOCKER fixed; 8 substantives/drafts applied; 4 items deferred to E3 with explicit handoff)

**E2 ready for Wave 4 (PM accept) → commit + push.**

## Next session (p127)

- E3 entregável (Pipelines de seleção):
  - Decision 4 cycle freeze logic in pmi-ai-triage EF
  - `prompt_version` column in `ai_processing_log` migration
  - Fix `is_returning_member` (Issue C — João Coelho cycle 2 cohort)
  - Align booking gate (Issue B)
  - Deploy Apps Script Calendar webhook (Issue A — 30 days zero sync)
  - Cron compliance D-60/D-30/D-7 (Decision 9 — 2-week dry-run staging)
  - Audit 10 interview-no-score rows (Issue E)

E3 Wave 2 mapping per p125 handoff: product-leader + ux-leader + stakeholder-persona (active-volunteer) + security-engineer (4 agents).
