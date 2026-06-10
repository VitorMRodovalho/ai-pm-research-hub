# ADR-0101 — PI-Exclusion Asset Registry + OpenTimestamps proofs (digest-only)

- **Status:** Proposed (draft for council review — 2026-06-09)
- **Issue:** #569 (legal-ops, type:feature, priority:high, governance, audit-trail)
- **Origin:** Parecer Técnico-Jurídico nº 01/2026 (Aaron Chaves), recomendação **(k)**; instrumento **Declaração Explícita de Exclusão de PI e Autoria Independente** (doc7), **Cláusula Quarta 4.1 + Anexo I**.
- **Refs:** doc9 §B (procedimento OpenTimestamps); ADR-0004 (`organization_id`), ADR-0007 (`can()`), GC-162 (RLS/LGPD).

## Context

The Declaração de Exclusão de PI (doc7) requires, as its **piso obrigatório de eficácia probatória**, a time-stamp via **OpenTimestamps** over the **SHA-256 digest** of each work listed in Anexo I (decisão B3: free baseline anchored to the Bitcoin blockchain; reinforcements — ata notarial / ICP-Brasil / INPI — are optional, manual, out of scope here). Today the procedure is manual; rec (k) asks the platform to automate it.

Grounded constraints (2026-06-09, prod `ldrfrvwhxsmgaabwmaik`):
- Extensions present: `pg_cron 1.6.4`, `pg_net 0.20.0`, `pgcrypto 1.3`.
- No existing asset/obra/declaration registry table.
- OpenTimestamps requires the binary OTS protocol with calendar servers + Bitcoin attestation aggregation — **not expressible in SQL alone**; it needs a client (the `opentimestamps` JS lib) running in an Edge Function (Deno).
- doc7 is **not yet uploaded** to `governance_documents` — the registry must build standalone with a nullable seam to the doc7 instance.

## Decision

**Digest-only registry** (PM decision 2026-06-09): the work **never leaves the Núcleo** — only its SHA-256 digest + metadata are registered and timestamped. No file storage; the `.ots` proof (a few hundred bytes) lives in `bytea`.

Architecture:
1. **DB** (this ADR / migration `20260805000135`): `pi_exclusion_declarations` (one row per declarant instance of doc7) + `pi_exclusion_assets` (the Anexo I rows: digest + `.ots` proof + status `unstamped → pending → confirmed`). RLS deny-all + access exclusively via SECURITY DEFINER RPCs (declarant self-service; `view_pii`-gated admin read for fiscalization, with org fence + `pii_access_log`). `organization_id` on both (ADR-0004).
2. **Edge Function** (Deno, `npm:opentimestamps` — Slice 2): `stamp` (submit digest to calendar servers → store `.ots` → mark `pending`), `verify`. Uses `service_role` to call the internal `_ots_*` RPCs.
3. **Cron** (`pg_cron` → `pg_net` → EF `upgrade`, Slice 3): promote `pending → confirmed`, recording Bitcoin block + attested UTC. Health tool in the `get_lgpd_cron_health` mould.
4. **Export + MCP** (Slice 4): `export_anexo_i` RPC + MCP tool feeding doc7; wired to the doc7 governance_document when it is uploaded (workstream 2).

**Eficácia = `confirmed`, não `pending`** (closes the QA gap on doc7 Cl.4.1): a freshly-created `.ots` is `pending` (not yet Bitcoin-anchored) and does not yet attest a date. `export_anexo_i` surfaces per-asset status + an `all_confirmed` flag so the Declaração's efficacy is reported honestly.

## Slices (1 PR each)
- **0. Spike — DONE** (2026-06-09): the `opentimestamps@0.4.9` lib is `likely_breaks` under Deno EF; decision = **HAND_ROLL** a zero-dep fetch+`.ots` engine (`_shared/ots.ts`), verified **byte-exact** vs 5 canonical vectors + a live stamp. See `docs/specs/SPEC_569_S0_OTS_DENO_SPIKE.md`.
- **1. DB** — tables + RLS + member-facing RPCs + internal `_ots_*` pipeline RPCs (**this ADR**).
- **2. EF stamp — DONE** (2026-06-09): `ots-stamp` EF wires `ots.ts` to `_ots_claim_unstamped_assets`/`_ots_mark_stamped`; deployed + smoked in prod (full data path incl. the bytea-over-PostgREST seam verified byte-exact).
- **3. pg_cron upgrade pass + health tool — DONE** (2026-06-10, migration `20260805000136`): 3 cron jobs (stamp 02:10 / upgrade 02:40 UTC non-overlapping + retention monthly), claim turned into an UPDATE-based **lease** (`claimed_at`, 10-min window, FOR UPDATE SKIP LOCKED — see note under Open items), registry retention pass (revoked + window, 1y safety floor, default 5y), `get_ots_pipeline_health` RPC + MCP tool. Cron auth via dedicated `vault.ots_cron_secret` ⇄ EF env `OTS_CRON_SECRET` (fail-closed gate widening on both EFs — the vault `service_role_key` copy was proven stale vs the EF-injected key, 403 live; see #618).
- **4. `export_anexo_i` + MCP tools; wire to doc7.**
- **5. (opt.)** git pre-commit hook (repo script, out-of-platform).

## Consequences
- New domain primitive (asset registry with cryptographic proofs). Lowest-surface design: no file storage, no R2, no new PII beyond research-metadata + digest.
- Trade-off (accepted, per doc9 (vi) [PM]): the platform cannot verify that the registered digest is the "final byte" of the work — that remains a human (declarant/PM) responsibility. The registry attests *a digest existed at a time*, not *which file it was*.
- The `.ots` proof in `bytea` keeps the evidence co-located with the row; verification is self-contained once `confirmed`.

## Alternatives considered
- **Platform stores the file (R2) + computes the hash** — rejected: stores unpublished research (tese/artigo inédito), larger privacy/security surface, contradicts "a obra nunca sai do Núcleo".
- **Hybrid (hash mandatory, file optional)** — rejected for Slice 1: doubles the code/RLS/retention paths for little near-term value; can be revisited if a "high-value asset" workflow needs it.
- **SQL-only OTS** — impossible (binary calendar protocol + Bitcoin attestation).
- **Third-party notarization API as baseline** — rejected: rec (k)/decisão B3 set OpenTimestamps as the free baseline; notarial/ICP/INPI are optional reinforcements (manual).

## Council review (2026-06-09, `wf_e64398e5-c2c`) — folded
4 reviewers (data-architect, security-engineer, legal-counsel, senior-eng), all **GO_W_FIXES**, 0 NO_GO; 2 BLOCKERs. All must-fix folded into migration `20260805000135`:
- **BLOCKER** `get_exclusion_declaration`/`export_anexo_i` were `STABLE` while INSERTing into `pii_access_log` → planner could drop the LGPD-Art.37 write → made **VOLATILE**.
- **BLOCKER** `organization_id` had no FK → added `REFERENCES public.organizations(id) ON DELETE RESTRICT` on both tables.
- `export_anexo_i` admin path now logs to `pii_access_log` (accessor_id = members.id); `register_exclusion_asset` derives org **from the declaration** (not the caller) + rejects `revoked`; `_ots_mark_error` guards `NOT IN ('confirmed')`; `_ots_mark_confirmed` requires block+attested and only promotes `pending`; export envelope splits `pending`/`unstamped`/`error` + adds asset `id` + `digest_only_notice`; `list_my_…` uses LATERAL counts.
- **Invariants PI1/PI2 enforced via CHECK constraints** (`confirmed ⇒ block+attested`, `pending ⇒ proof`) instead of `check_schema_invariants()` entries — structural enforcement is stronger than drift detection (the bad state cannot be written) and avoids re-creating a large function. `UNIQUE(declaration_id, seq)` makes seq collisions fail-loud. Least-privilege `GRANT` (no `ALL`/TRUNCATE). `updated_at` via a self-contained trigger (`moddatetime` is not installed).

## Deferred to the #569 wire-up slice (Slice 4) — tracked, zero live data today
- `export_my_data()` integration (LGPD Art. 18 II portability of a declarant's own PI registry) — security reviewer must-fix, but no member data exists yet; do it with the wire-up to avoid re-creating the large export body from a possibly-stale source.
- `admin_audit_log` entry on declaration create/revoke (lifecycle audit).
- Retention/elimination of `error`/`revoked` rows + `.ots` bytea (doc1 2.5.6) — with the Slice 3 cron.

## Open items (gate the later slices, not this migration)
- ~~OTS-lib-in-Deno feasibility (Slice 0 spike)~~ **RESOLVED** → HAND_ROLL engine, verified (Slice 0/2 done).
- ~~`_ots_claim_unstamped_assets` row-locking (FOR UPDATE SKIP LOCKED) — Slice 3~~ **RESOLVED** (2026-06-10, mig `20260805000136`) — implemented as an UPDATE-based **lease** (`claimed_at` + 10-min window + SKIP LOCKED), not the bare row lock this item described: over PostgREST each RPC call is its own transaction, so a SELECT-only lock would release before the EF processed anything and two invocations seconds apart would still double-claim. The lease survives across transactions; cron non-overlap is now defense-in-depth instead of a correctness requirement.
- ~~Cron auth: the EFs gate on exact `SUPABASE_SERVICE_ROLE_KEY` string-match (repo convention); the pg_net cron call must use the EF's current injected key.~~ **RESOLVED** (2026-06-10) — the vault `service_role_key` copy does NOT match the EF-injected key (403 proven live; #618). Instead of chasing the injected key, the cron authenticates with a dedicated low-scope secret (`vault.ots_cron_secret` ⇄ EF env `OTS_CRON_SECRET`; both EF gates widened fail-closed: `service-role OR cron-secret`). Survives future service-key rotations; precedent: `x-sync-secret` (job 21).
- doc7 upload (workstream 2) before the Anexo I export is wired to a real governance_document.
