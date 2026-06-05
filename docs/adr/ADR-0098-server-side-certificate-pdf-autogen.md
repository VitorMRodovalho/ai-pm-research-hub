# ADR-0098 — Server-side certificate PDF auto-generation via DB trigger + CF Browser Rendering

**Status:** Accepted (2026-05-23 p225 #281 close); Amended same-day for vault refactor (migration 20260805000006) — see "Amendment 2026-05-23" below.
**Supersedes:** none
**Amends:** none (extends p221 #267 alpha — backfill scope completion)
**Related:** [[ADR-0006]] (V4 person + engagement model), p221 PR #282 (backfill alpha — bucket + script), [[ADR-0095]] (member alternate emails — PII surface reference)

## Contexto

p221 PR #282 shipped Issue #267 **alpha**: one-shot backfill of 42 existing certificates (41 `volunteer_agreement` + 1 `contribution`) into a private `certificates` Supabase Storage bucket via a Node 24 native TS script with playwright headless Chromium. Same `buildCertificateHTML` + `hydrateCertData` pipeline as the browser-print path in `src/pages/certificates.astro`, ensuring zero visual drift between the stored PDF and the member-print PDF.

The forward gap deferred to this ADR:

1. **No auto-gen on new cert issuance.** RPCs that insert into `public.certificates` (`bulk_issue_certificates`, `admin_offboard_member`, `sign_ip_ratification`, `issue_certificate` called via `sign_volunteer_agreement`) leave `pdf_url IS NULL`. The backfill script would need to be re-run manually after every new cert.
2. **`/verify/{code}` page is metadata-only.** Stored PDF link is not surfaced. Intentional per LGPD soft-private design (cert content carries PII: birth_date, address, pmi_id, govbr_signer).
3. **`/certificates` member-facing page** does not consume `pdf_url` yet — still uses `downloadCertificatePDF` via `window.print()` (browser-print pipeline, p218 PR #262).
4. **Storage RLS on `storage.objects`** for the `certificates` bucket = zero policies (alpha bucket has service_role bypass only). MCP `apply_migration` is blocked by storage.objects ownership chain (sediment p210); requires Studio UI.

WATCH-258.B (Issue #281) captures the forward gap as a single trackable item.

## Decisão

Adotar **Path β** do trade-off matrix em #281: **Cloudflare Browser Rendering binding + DB trigger pipeline**.

### Pipeline (single-point capture, async, exception-safe)

```
public.certificates INSERT (any RPC path or direct execute_sql)
  ↓
AFTER INSERT trigger trg_certificate_pdf_autogen fires WHEN (NEW.pdf_url IS NULL)
  ↓
PERFORM net.http_post(/api/internal/cert-pdf-render/<id>) — fire-and-forget
  ↓
Astro endpoint validates Bearer shared secret (CERT_PDF_INTERNAL_SECRET)
  ↓
Hydrate cert via service_role + reuse hydrateCertData() from pdf.ts
  ↓
buildCertificateHTML(certData) + buildPrintDocument(title, html, lang)
  ↓
puppeteer.launch(env.BROWSER) → page.setContent(html) → page.pdf({A4, margins})
  ↓
Upload to certificates/<member_id>/<verification_code>.pdf (upsert=true)
  ↓
UPDATE certificates SET pdf_url = path WHERE id = X AND pdf_url IS NULL
```

### Por que trigger (vs wrap per-RPC)

Quatro RPCs hoje inserem em `public.certificates` (`bulk_issue_certificates`, `admin_offboard_member`, `sign_ip_ratification`, plus `issue_certificate` chamada por `sign_volunteer_agreement`). Wrap per-RPC = 4 mudanças + maintenance burden + risk de novo RPC ser adicionado sem wrap. **AFTER INSERT trigger captura todos os caminhos sem code-touch — incluindo execute_sql direto pelo admin e futuras RPCs.**

### Por que fire-and-forget (não sync)

Cert issuance UX (sign termo, bulk issue, offboarding) não pode esperar 2-5s do render PDF. `net.http_post` enfileira em background worker; UPDATE de `pdf_url` chega assincronamente (single-digit segundos típico). Member que abre `/certificates` immediately após sign vê o cert listado, com fallback browser-print disponível enquanto stored PDF é gerado.

### Por que shared secret (não JWT/HMAC)

Caminho interno DB-trigger → Worker endpoint, mesma org, sem expectativa de rotation crítica. Shared secret armazenado em **Supabase Vault** (`vault.decrypted_secrets` name=`cert_pdf_internal_secret`) no lado DB + `CERT_PDF_INTERNAL_SECRET` wrangler secret (Worker). Rotation requer 2-step (Worker secret → vault row UPDATE) mas é raro. JWT/HMAC adicionaria complexidade `pgcrypto.digest()` em plpgsql sem benefício prático em threat model atual.

> **Historical note**: original migration 20260805000005 attempted to use `app.cert_pdf_internal_secret` GUC via `ALTER DATABASE postgres SET`. Supabase managed PG returned `ERROR: 42501: permission denied to set parameter "app.cert_pdf_internal_secret"` — the `app.*` namespace requires allowlist enrollment. Migration 20260805000006 refactored the trigger fn body to read from `vault.decrypted_secrets` instead. See SEDIMENT-225.B below.

### Storage path convention

`certificates/<member_id>/<verification_code>.pdf` — herdado do backfill alpha. Permite **future Option C member-owned RLS** (`(storage.foldername(name))[1]::uuid IN (SELECT id FROM members WHERE auth_id = auth.uid())`) sem mudança de path. Não bloqueante para esta entrega — atual path uses signed URL via service_role (member SELECT path Option A da decisão #281).

### Member SELECT path: Option A (member-only, LGPD-conservative)

- `/verify/{code}` STAYS metadata-only (matches current design intent + LGPD soft-private)
- **THIS PR scope**: `/certificates` continues using browser-print pipeline (`downloadCertificatePDF` via `window.print()`, PR #262 p218) — already satisfies LGPD Art. 18 data subject access. No change.
- **Future work**: wire `pdf_url` consumption into `/certificates` page via signed URL TTL 5min server-side (new RPC `get_my_certificate_pdf_path` + new Astro endpoint `/api/cert-pdf-url/[id]` generating signed URL via service-role bypass storage RLS). Fallback to browser-print when `pdf_url IS NULL` (cert just issued, async render still pending). Tracked as follow-up to this PR (see "Future work" below).

### LGPD Art. 16 — Record-keeping

Stored PDFs ficam no bucket pelo mesmo período retention da `certificates` table (indefinido enquanto member ativo, anonymize 5y após offboarding via existing anonymize cron). Bucket retention herda o mesmo lifecycle — não há GC separado em storage.

## Trade-off matrix (4 paths considered em #281)

| Path | Cost | Time | Visual Fidelity | Risk |
|---|---|---|---|---|
| α — Per-RPC wrap (status quo extended) | None | 1-2h | n/a (no PDF gen, still manual backfill) | Drift between RPCs; new RPC = forgotten wrap |
| **β — CF Browser Rendering + trigger ✅** | CF Workers Paid quota (negligible at <50 certs/mo) | 2-3h | Identical to backfill alpha + member-print (same HTML template) | New paid CF dep |
| γ — @react-pdf rewrite | None | 4-6h | Risk of visual regression on legal document (termo) | Workers bundling spike for pdfkit |
| δ — EF Deno + puppeteer-deno | None | 4-5h | Same (same template, different runtime) | Cold-start adds 1-2s; Deno-specific puppeteer fork maintenance |

Path β wins on time + zero rendering drift. CF cost negligible (~$5/M req; nucleo issues <50 certs/month).

## Consequências

### Positivas
- Forward gap from #281 closed: any new cert (regardless of issuing RPC) auto-gets stored PDF
- Zero visual divergence vs backfill alpha (same `buildCertificateHTML` + same wrapper)
- Idempotent: `WHEN(NEW.pdf_url IS NULL)` + endpoint `UPDATE ... WHERE pdf_url IS NULL` (race-safe)
- Exception-safe: trigger catches errors → WARNING → insert succeeds; failed certs recoverable via backfill script
- `/certificates` page (post-Phase 4): signed URL bypasses storage RLS → no Studio UI gate
- **No `/mcp` surface change** (no new MCP tool) — keeps Perplexity-stable 3-tool `/semantic` invariant from #277 close (P162 #188)

### Negativas
- New paid dep: CF Browser Rendering (Workers Paid plan required). Cost negligible at our volume; visible in CF dashboard observability.
- Two secrets to rotate together (DB GUC + wrangler secret) — documented in migration header
- Shared-secret model less defensible than HMAC for high-threat surfaces; acceptable here (internal-only path, no external client touches it)
- `@cloudflare/puppeteer` dep added to package.json
- Worker bundle size grows by puppeteer footprint (~few hundred KB)

### Future work (NOT in this ship; tracked via soft watches)
- **`/certificates` signed URL wiring**: new RPC `get_my_certificate_pdf_path(p_cert_id)` + new Astro endpoint `/api/cert-pdf-url/[id]` returning signed URL TTL 5min via service-role. Frontend checks `pdf_url` from extended `get_my_certificates` return; if non-null, fetches endpoint → opens signed URL; if null, falls back to browser-print. Estimated S (~1h). Acceptable to defer because browser-print already satisfies LGPD Art. 18.
- **Storage.objects RLS Option C** (member-owned SELECT via folder-prefix matching): pending Studio UI work + sediment p210 resolution. Path A (signed URL) suffices today.
- **Public verify route stored PDF**: Path B from #281 not chosen — `/verify/{code}` stays metadata-only per LGPD soft-private design. Re-evaluate if auditor demand surfaces.
- **HMAC instead of shared secret**: if cert issuance volume scales 100x or threat model changes (e.g. multi-tenant external client touching this path), revisit.
- **/admin/certificates bulk-regen UI**: backfill script (`scripts/backfill-cert-pdfs.ts`) still works; future enhancement could expose a "regenerate PDF" admin action wired to the same endpoint via service-role.

## Amendment 2026-05-23 (vault refactor + SEDIMENTs surfaced during ship)

Three sediments surfaced during the same-day ship:

- **SEDIMENT-225.A** (already merged in 20260805000005 commit body): Postgres strips inline `--` comments from `prosrc` when storing function source. The body-drift parser (`tests/helpers/rpc-body-drift-parser.mjs`) parses the raw migration file body verbatim, so any `--` inside the function body causes md5(prosrc) ≠ md5(file body) drift on first Phase C check. Fix = move design notes outside the `AS $$ ... $$` block.

- **SEDIMENT-225.B**: Supabase managed PG blocks `ALTER DATABASE postgres SET app.*` for non-allowlisted params. The original GUC-based approach in 20260805000005 was deployment-blocked. Path forward = `supabase_vault` extension (v0.3.1, installed by default). Migration 20260805000006 refactored the trigger fn body to read via `SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'cert_pdf_internal_secret'` (search_path includes `vault`).

- **SEDIMENT-225.C**: Body-drift parser regex `/\bCREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION\s+.../i` matches `CREATE OR REPLACE FUNCTION` literal **inside SQL comments**. The rollback example in the migration header initially included a `CREATE OR REPLACE FUNCTION` template inside a comment, causing the parser to emit two blocks for the same function (a 5-byte stub from the comment + the real 1097-byte body), which broke Phase C "latest capture" logic. Fix = rephrase rollback examples to avoid the exact `CREATE ... FUNCTION` token sequence inside comments.

### Updated deploy ops (post-vault refactor)

1. `npx wrangler deploy` (one-time, already done in initial deploy)
2. `openssl rand -base64 32` (capture output)
3. `npx wrangler secret put CERT_PDF_INTERNAL_SECRET` (paste output from step 2)
4. **Vault** (Studio SQL editor — was `ALTER DATABASE SET` before refactor):
   ```sql
   SELECT vault.create_secret(
     '<same value from step 2>',
     'cert_pdf_internal_secret',
     'p225 #281 ADR-0098: shared secret for AFTER INSERT trigger → /api/internal/cert-pdf-render'
   );
   ```
5. Smoke: INSERT test cert via `execute_sql` → verify pdf_url populated within 5s

### Rotation (future, post-vault refactor)

1. Worker side: `npx wrangler secret put CERT_PDF_INTERNAL_SECRET` (new value)
2. DB side (Studio SQL): `UPDATE vault.secrets SET secret = vault.encrypt('<new value>', key_id) WHERE name = 'cert_pdf_internal_secret';`
   (or `DELETE` + `vault.create_secret` in same transaction for atomicity)

## Cross-ref

- Migration: `supabase/migrations/20260805000005_p225_281_certificate_pdf_autogen_trigger.sql`
- Migration (vault refactor): `supabase/migrations/20260805000006_p225_281_certificate_pdf_autogen_use_vault.sql`
- Endpoint: `src/pages/api/internal/cert-pdf-render/[id].ts`
- Browser binding: `wrangler.toml` `[browser] binding = "BROWSER"`
- CSRF allowlist: `src/middleware.ts` `CSRF_BYPASS_PREFIXES` includes `/api/internal/`
- HTML template (canonical): `src/lib/certificates/pdf.ts` (`buildCertificateHTML`, `hydrateCertData`)
- Backfill script (reference + recovery path): `scripts/backfill-cert-pdfs.ts`
- Bucket: `supabase/migrations/20260805000000_p221_267_create_certificates_bucket.sql`
- P162 log: #189 RESOLVED-281 (this ship)
- Issue: #281 (now closed)
- LGPD: Art. 16 (retention) + Art. 18 (data subject access via /certificates)
