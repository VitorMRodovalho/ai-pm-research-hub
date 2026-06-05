# p237 — Orphan agent-branch equivalence + ADR-0097 amnesty disposition

**Date:** 2026-05-23 (p237 boot-to-close, single PR governance)
**Author:** Vitor (PM) + Claude (audit + drafting)
**Scope:** Document equivalence between two stale agent-branch heads and the canonical live `schema_migrations` rows so the branches can be deleted without information loss. No DDL. No code. No live DB writes.
**Cite:** ADR-0097 §Decisão path δ (Hybrid amnesty + ratchet). Carries forward p236 entry #203 line 2205 out-of-scope item ("Branch deletion `agent/issue-218-whisper-art11` + `agent/issue-221` (post-merge cleanup; both `remotes/origin/` and local refs)").

## Context

Two `agent/` branches remained on `origin` after the p236 close (`5d01dbab` + `33fd9bf6` + `c5906059`). PM directive at p237 boot (`/effort max`): resolve the orphan-migration situation before any new implementation work. Two stated options: (A) cherry-pick the missing local migration file into main, OR (B) explicitly document ADR-0097 amnesty/equivalence with live migration `20260520231254`. Then delete the branches.

PM selected **Path A — Pure amnesty** (per `AskUserQuestion` ABCD pick, single Recommended option). This doc + the P162 entry referenced below are the disposition.

## Branch state map (verified live)

### 1. `agent/issue-221` — STALE, NOT orphan

- Branch head: `a48ebc90` ("fix(p207): #221 Whisper Art. 11 RETROATIVO — DROP trigger + voice biometric consent gate")
- Files diff vs `main` (`c5906059`):
  - `supabase/migrations/20260801000000_p207_issue_221_whisper_art11_drop_trigger.sql`
  - `supabase/migrations/20260801000001_p207_issue_221_capture_voice_biometric_consent_columns.sql`
  - `supabase/migrations/20260801000002_p207_issue_221_helper_gate_voice_biometric_consent.sql`
- All 3 files **byte-identical** to `main` (verified via `git show origin/agent/issue-221:<path>` and `git show main:<path>`).
- Verdict: pure stale. Zero orphan content. Safe to delete.

### 2. `agent/issue-218-whisper-art11` — orphan file, live-equivalent

- Branch head: `58a9051b` ("fix(p206): #218 emergency block — Whisper Art. 11 LGPD voice biometric consent gate")
- Single file: `supabase/migrations/20260731000000_issue_218_whisper_art11_emergency_block.sql` (4442 bytes)
- This filename does **NOT** exist in `main`. The timestamp `20260731000000` is occupied in `main` by a different file: `20260731000000_p206_gap_204_b_invariant_breach_helper.sql` (separate concern, GAP-204.B test-only helper).
- Live state evidence (verified via `mcp__supabase__execute_sql` against `ldrfrvwhxsmgaabwmaik`, 2026-05-23):
  - `supabase_migrations.schema_migrations` row `20260520231254` name=`issue_218_whisper_art11_emergency_block` has_body=true (canonical p206 registration via `migration repair --status applied`).
  - `supabase_migrations.schema_migrations` row `20260731000000` name=`issue_218_whisper_art11_emergency_block` has_body=true (apply_migration shadow row at NOW()-time of p207).
  - Trigger `trg_pmi_video_screening_voice_consent` exists on `public.pmi_video_screenings`.
  - Function `public._trg_pmi_video_screening_voice_consent_check` exists (security definer, search_path pinned).
  - Columns `consent_voice_biometric_at` + `consent_voice_biometric_revoked_at` exist on `public.selection_applications`.
- Verdict: the DDL the branch file would apply is already live. The file body is byte-equivalent modulo PostgREST statement-array normalization (4442 source bytes vs 3929 in `20260520231254.statements` monolith vs 4407 in `20260731000000.statements` 8-stmt split — CLI artifact of how each row got registered; same DDL semantics).

## Amnesty fit (ADR-0097 path δ)

- `MIGRATION_FILE_DRIFT_BASELINE_P224.txt` line 1: `20260520231254` — already in the 694-entry amnesty allowlist.
- Per ADR-0097 §Decisão: "Funcional impact = 0 hoje: live DB tem todo DDL aplicado + features funcionam + contract tests passam. Risco surface APENAS em `supabase db reset` rebuild from files, que não acontece em prod."
- This is exactly that class: orphan branch carries a file whose DDL is already present in live and whose canonical version is already amnesty-covered. Cherry-picking would add 1 file + 1 row + would not reduce operational risk.
- ADR-0097 §Critério de revisão item 1 ("drift counts crescerem sem PM ack + baseline bump"): this disposition does NOT grow drift. The branch deletion removes a never-committed file from the orphan-branch namespace; it does not touch `main`, `schema_migrations`, or any baseline.

## Side-finding (NOT remediated this PR per Path A scope)

During audit, 4 historical `apply_migration` MCP shadow rows were observed in `supabase_migrations.schema_migrations`. All pre-date p237 (p206/p207 origin) and have been operationally inert since:

| Shadow version | Shadow name | Canonical version | Notes |
|---|---|---|---|
| `20260521015219` | `20260801000000_p207_issue_221_whisper_art11_drop_trigger` | `20260801000000` | Body included full filename as `name`; canonical row registered separately via `migration repair`. |
| `20260521015244` | `20260801000001_p207_issue_221_capture_voice_biometric_consent_columns` | `20260801000001` | Same pattern. |
| `20260521015320` | `20260801000002_p207_issue_221_helper_gate_voice_biometric_consent` | `20260801000002` | Same pattern. |
| `20260731000000` | `issue_218_whisper_art11_emergency_block` | `20260520231254` | Apply_migration used NOW() at p207 time; collides timestamp-only (not name) with `main`'s local file `20260731000000_p206_gap_204_b_invariant_breach_helper.sql`, whose own canonical row is `20260520200049`. |

These rows are the artifact described in SEDIMENT-227.A (revisited p232 as SEDIMENT-232.B): `apply_migration` MCP creates a row using NOW() instead of honoring the timestamp prefix in `name`, requiring a manual `migration repair --status applied <canonical>` + DELETE-the-shadow follow-up. Path A explicitly leaves these in place; Path C would have removed them via DML. PM may pick up a narrow follow-up if desired — it is operationally inert and the rows are correctly accounted for in the p224 missing-files baseline (the canonical versions count, not the shadow versions).

Pre-existing P162 entry #203 line 2211 cross-ref string `migrations 20260731000000_issue_218_whisper_art11_emergency_block.sql + ...` should be read as "the DDL block whose canonical row is `20260520231254`"; the filename does not exist in `main`. (Not fixed retroactively per scope discipline; flagged here.)

## Decision

1. Delete both branches (`agent/issue-221` + `agent/issue-218-whisper-art11`) local + remote AFTER this PR merges.
2. Do not cherry-pick. Do not touch live `schema_migrations`. Do not touch `MIGRATION_FILE_DRIFT_BASELINE_P224.txt` count.
3. ADR-0097 amnesty already covers the canonical row; this doc records the equivalence per PM directive "explicitly document ADR-0097 amnesty/equivalence with live migration 20260520231254."

## Verify-on-next-boot

After this PR merges + branches deleted:

- `git ls-remote origin | grep agent/issue-2` returns empty.
- `git branch -a | grep agent/issue-2` returns empty.
- `supabase_migrations.schema_migrations` row count UNCHANGED (-0).
- `MIGRATION_FILE_DRIFT_BASELINE_P224.txt` line count UNCHANGED (694).
- `check_schema_invariants()` 19/19 = 0 (no impact path).
- `npm test` baseline UNCHANGED at 1856/1800/0/56 (offline) — pure docs PR.

## Cross-references

- `docs/adr/ADR-0097-migration-history-drift-amnesty-and-ratchet.md` §Decisão path δ
- `docs/audit/MIGRATION_FILE_DRIFT_BASELINE_P224.txt` (line 1 = `20260520231254`)
- `docs/audit/P162_GAP_OPPORTUNITY_LOG.md` entry #203 (RESOLVED-#221-#218-DECOMPOSE) line 2205 out-of-scope #2
- `docs/audit/P162_GAP_OPPORTUNITY_LOG.md` entry #204 (this disposition — RESOLVED-p237-ORPHAN-BRANCHES)
- `docs/project-governance/ISSUE_REGISTRY.md` header (bump to p237)
- Migrations referenced by ID (NOT by file path; the orphan branch's filename does not exist in `main`):
  - `20260520231254:issue_218_whisper_art11_emergency_block` (p206 canonical, in amnesty baseline)
  - `20260801000000:p207_issue_221_whisper_art11_drop_trigger`
  - `20260801000001:p207_issue_221_capture_voice_biometric_consent_columns`
  - `20260801000002:p207_issue_221_helper_gate_voice_biometric_consent`
