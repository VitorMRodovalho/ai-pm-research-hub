# Runbook — Institutional Data Export (#572 Block A)

**Purpose:** produce a complete, open-format, reimportable institutional export of the platform for a
**migration** (to a successor operator) or **shutdown** event. This is the LGPD *institutional*
portability obligation (doc4 §6.4 / Parecer 01/2026 rec g) — **distinct** from the per-titular Art.18
export (`export_my_data` / #568). See `docs/adr/ADR-0112-institutional-data-portability-block-a.md`.

> **GP-only. Rare event (≤1 per platform lifetime). Pre-conditions in §1 are MANDATORY (GC-151).**
> The export bundle is plaintext PII of the entire member base — handle as maximum-sensitivity data.
>
> **Destination requirement:** the dump restores onto a **Supabase-compatible Postgres 14+** (the `auth`
> schema and its `auth.uid()`/`auth.role()` functions must pre-exist — e.g. a fresh Supabase project),
> because the dumped RLS policies reference them. A plain vanilla Postgres needs the RLS policies
> post-processed (stub/replace `auth.*`) before `psql`, or the restore aborts on `function auth.uid() does not exist`.

## 0. When this is legitimate

ONLY: (a) platform migration to a successor operator under a formal DPA (LGPD Art. 39); (b) Programa
shutdown; (c) a competent-authority request (ANPD). **Never** as a routine/periodic export, and **never**
delivered to chapter partners, sponsors, or institutional auditors. Legal basis: LGPD Art. 7º IX (legítimo
interesse na preservação/migração) + Art. 16, IV. Recipient: the controller (PMI-GO presidency/GP) or the
successor operator under DPA.

## 1. Pre-conditions (MANDATORY — GC-151)

- [ ] Formal migration/shutdown **authorization signed by the PMI-GO presidency**, archived in
  `docs/GOVERNANCE_CHANGELOG.md` **before** the dump runs.
- [ ] If delivering to a successor operator: a signed **DPA/Acordo de Operador** (Art. 39) on file.
- [ ] **Maintenance mode / write-freeze (REQUIRED for hash integrity).** The manifest (Step 1) and the
  `pg_dump` (Step 2) are separate transactions; any write between them invalidates the per-table
  `content_sha256` hashes and shifts the `admin_audit_log` count. Disable write access for all non-superuser
  roles (and pause the LGPD Block C crons) BEFORE Step 1, and resume ONLY after Step 2's file is verified.
- [ ] **`ANALYZE;`** on the source first — the manifest uses `pg_class.reltuples` to pick the per-table
  hash strategy; a stale/never-analyzed table (`reltuples = -1`) is handled conservatively (count-only) but
  a fresh `ANALYZE` keeps the strategy accurate.
- [ ] **No secrets in `platform_settings` audit trail.** `admin_update_setting()` logs verbatim
  `previous_value`/`new_value` into `admin_audit_log` (included in the dump). Verify zero secret-key changes:
  ```sql
  SELECT count(*) FROM public.admin_audit_log
  WHERE action = 'platform.setting_changed'
    AND changes::text ~ '(_secret|_token|_key|_password|_passphrase|_credential)';
  ```
  Must return 0. If not, redact those `changes` values before the dump. (Discipline: store secrets only in
  `site_config`, which is excluded; never in `platform_settings`.)
- [ ] **Invalidate live onboarding tokens.** `onboarding_tokens.token` is plaintext and `consume_onboarding_token`
  is anon-callable; an unexpired token in the dump is replayable against the still-running source during the
  migration window. Before delivery: `UPDATE public.onboarding_tokens SET expires_at = now() WHERE consumed_at IS NULL AND expires_at > now();`
  (Skip only if the source is fully shut down before delivery.)
- [ ] DPO confirmation on two open questions for a real run:
  - **Pre-member pool (#905, rejected/withdrawn):** include with an `anonymization-eligible` flag
    (receiver inherits the LGPD window) vs anonymize before dumping. The #905 anonymization cron is
    currently **dormant** (`active=false`) — confirm the legal window first.
  - **Art. 11 media (voz/imagem):** binaries in Drive/YouTube are **not** in the DB dump (URLs only);
    their fate follows the #905 path under an explicit Art. 11 decision.
- [ ] Verify the anonymization crons ran recently (so the dump does not retain rows past their window):
  `get_lgpd_cron_health` (or query `cron.job_run_details`).

## 2. Procedure (5 steps)

All RPC calls are GP/sede only (`can_by_member('manage_platform') AND caller_chapter_scope() IS NULL`).
Run them as the authenticated GP via the app/MCP, or via the Supabase dashboard SQL editor while
impersonating the GP. The `pg_dump` step needs the **direct DB password** (dashboard → Settings →
Database → Connection string) — it is intentionally **not** reachable by any RPC.

**Step 1 — manifest (pre-dump integrity + audit phase 1):**
```sql
SELECT public.generate_institutional_export_manifest(
  p_justification := 'Migration to <successor> per presidency authorization <ref> dated <date>',
  p_trigger_event := 'migration'   -- or 'shutdown' / 'anpd_request'
);
```
Save the returned `export_id` and the full manifest JSON (per-table `row_count` + `content_hash`,
`manifest_aggregate_hash`, `redacted_keys`, `excluded_table_data`, `excluded_matviews`, `excluded_schemas`).
The RPC enforces a ≥10-char justification and a 5-per-30-day rate-limit, and writes a
`institutional_export.manifest_generated` audit row.

**Step 2 — bulk dump (open SQL) + redacted settings:**
First review all `site_config`/`platform_settings` keys: the redaction pattern
`(_secret|_token|_key|_password|_passphrase|_credential)$` covers known credential keys, but for any key
storing a credential under a non-conforming name (or an embedded-credential URL like
`webhook_url=...?auth_token=...`), rename it to match the pattern or add it to a manual redaction list here.
```bash
pg_dump "<DIRECT_CONNECTION_STRING>" \
  --schema=public --schema=z_archive --no-owner --no-acl --format=plain \
  --exclude-table-data='public.cycle_tribe_dim' \
  --exclude-table-data='public.preview_gate_eligibles_cache' \
  --exclude-table-data='public.wiki_pages' \
  --exclude-table-data='public.artia_status_reports' \
  --exclude-table-data='public.cron_run_log' \
  --exclude-table-data='public.site_config' \
  --exclude-table-data='public.platform_settings' \
  | gzip -9 > institutional_export_$(date -u +%Y%m%d).sql.gz
```
The 5 cache/derived/external-sync tables keep their DDL but drop reconstructable data. `site_config` /
`platform_settings` keep DDL but their rows are exported **only** via the redacting RPC (next), so a live
shared secret (`arm116_calendar_webhook_secret`) never leaves verbatim:
```sql
SELECT public.export_redacted_settings();   -- save as redacted_settings.json
```

**Step 3 — file integrity:**
```bash
sha256sum institutional_export_$(date -u +%Y%m%d).sql.gz   # save the digest + byte size
```

**Step 4 — data dictionary:**
```sql
SELECT public.export_institutional_data_dictionary();   -- save as data_dictionary.json
```
Pair it with the LGPD semantic overlay `docs/legal/INSTITUTIONAL_EXPORT_DATA_DICTIONARY.md` (classification,
legal basis, retention anchor per domain).

**Step 5 — register completion (audit phase 2):**
```sql
SELECT public.register_institutional_export_completion(
  p_export_id   := '<export_id from step 1>',
  p_dump_sha256 := '<sha256 from step 3>',
  p_dump_bytes  := <byte size from step 3>,
  p_notes       := 'delivered to <recipient> under DPA <ref>'
);
```
Fails with `no_manifest_for_export_id` if step 1 was skipped, or `already_registered` if this `export_id`
was already completed (one receipt per export). Writes `institutional_export.completed`.

## 3. The delivered bundle

```
institutional_export_YYYYMMDD.sql.gz   # pg_dump plain SQL (public + z_archive), gzipped
data_dictionary.json                   # export_institutional_data_dictionary() output
redacted_settings.json                 # export_redacted_settings() output (secrets masked)
manifest.json                          # generate_..._manifest() output (also persisted in admin_audit_log)
INSTITUTIONAL_EXPORT_DATA_DICTIONARY.md # LGPD semantic overlay (this repo)
```

## 4. Validate completeness (receiver side)

- Per-table `row_count` in `manifest.json` matches `SELECT count(*)` after restore — **except**:
  - **`admin_audit_log`**: the manifest count is always lower than the dump by ≥1 — the phase-1
    audit row that `generate_institutional_export_manifest` itself inserts after the count, plus the
    phase-2 completion row, plus any audit events during the (write-frozen) window. Accept
    `manifest.row_count ≤ dump.count`; treat a deficit > 5 (with write-freeze on) as suspicious.
  - **Materialized views** (`excluded_matviews`, e.g. `cycle_tribe_dim`): absent from `table_manifests` by
    design — rebuild via `REFRESH MATERIALIZED VIEW` after restore.
- `manifest_aggregate_hash` recomputable from the per-table `content_hash` values.
- **`content_sha256` is a SOURCE-SIDE tamper-detection hash, not a post-restore check.** It is computed via
  `row::text` serialization, whose output depends on the Postgres version/locale (jsonb key ordering,
  timestamptz rendering, `LC_COLLATE` sort). Use it to detect corruption *in transit* (recompute on the
  SOURCE before transfer and compare). For post-restore verification use the portable `row_count` fields.
- `sha256sum` of the received `.sql.gz` equals `dump_sha256` in the `institutional_export.completed` audit row.
- **RLS:** `--no-acl` does NOT strip RLS — the restored DDL re-creates policies. After restore, create roles
  `anon`/`authenticated`/`service_role` to match the source and verify policies are intact **before** exposing
  data to any role other than the owner/superuser.

## 5. Restore the dump (receiver side)

On the destination (a Supabase-compatible Postgres 14+ — see the header requirement):
```bash
gunzip -c institutional_export_YYYYMMDD.sql.gz | psql "<DESTINATION_CONNECTION_STRING>"
```
Plain SQL format; restore against an empty database (COPY data is not idempotent). Then proceed to §4 to validate.

## 6. Restore configuration + retention jobs

After restoring the dump, `site_config` and `platform_settings` exist but are **empty** (their data was
`--exclude-table-data`). Repopulate from `redacted_settings.json`:
- Insert all key/value rows where `value != "[REDACTED]"`.
- **Manually re-enter every `[REDACTED]` secret** (e.g. `arm116_calendar_webhook_secret`) — obtain from the
  outgoing GP **out-of-band**, never from the bundle. Verify: `SELECT count(*) FROM public.site_config WHERE value = '"[REDACTED]"'::jsonb;` returns 0.
- **Recreate the LGPD Block C retention crons** (the `cron` schema is excluded from the dump): re-apply the
  migrations containing `cron.schedule(...)` (grep `supabase/migrations` for `cron.schedule`) and verify all
  Block C jobs (`lgpd-anonymize-inactive-monthly`, `v4-anonymize-by-kind-monthly`, `log-retention-monthly`,
  `ots-retention-monthly`) are active **before** going live — otherwise the successor is in breach of LGPD
  retention obligations from day one.

## 7. Excluded by design

- **Schemas:** `auth` (password hashes, OAuth tokens — migrate via Supabase Auth Export/Import), `vault`,
  `storage` (binaries), `realtime`, `supabase_migrations`, `cron` (job definitions — recreate per §6).
- **Table data:** the 5 cache/derived/external-sync tables above (DDL kept) + the two settings tables (rows
  via the redacting RPC). Materialized views (reported as `excluded_matviews`) — rebuild via `REFRESH`.
- **Media binaries:** voz/imagem in Drive/YouTube (Art. 11; #905 path) — URLs only in the dump.

## 8. Integrity caveat

The export guarantees **snapshot completeness** (one point in time, via `pg_dump` REPEATABLE READ, with the
write-freeze in §1 covering the manifest→dump window). It does **not** prove an append-only hash-chain of the
audit log — that is #574 and not yet live. Do not claim the dump "proves the audit chain".
