# Security Policy

## Reporting a vulnerability

If you believe you've found a security vulnerability in the AI & PM Research Hub, please **do not** open a public GitHub issue. Instead:

1. **Email:** `vitorodovalho@gmail.com` with subject line `[SECURITY] <short description>`
2. **Expected response SLA:**
   - Acknowledgement: within 48 hours
   - Initial assessment: within 5 business days
   - Fix timeline: dependent on severity (critical < 72h, high < 2 weeks, medium < 1 month)
3. **Please include:** reproduction steps, affected component (frontend / API / MCP / Edge Function / database), version/commit SHA if known, and your preferred disclosure timeline.

We credit reporters in release notes unless anonymity is requested.

## Scope

In-scope:
- `nucleoia.vitormr.dev` (production)
- Supabase project `ldrfrvwhxsmgaabwmaik` (public API surfaces)
- MCP server at `nucleoia.vitormr.dev/mcp` (OAuth 2.1, 76 tools)
- Edge Functions at `ldrfrvwhxsmgaabwmaik.supabase.co/functions/v1/*`
- GitHub repos `nucleo-ia-gp/wiki` and `nucleo-ia-gp/frameworks`

Out of scope (report to upstream):
- Supabase platform vulnerabilities → security@supabase.io
- Cloudflare Workers vulnerabilities → https://www.cloudflare.com/disclosure/
- Third-party dependencies flagged by Dependabot (handled in CI)

## What MUST NOT be committed to this repo

### Secrets
- `.env` files with live credentials (`SUPABASE_SERVICE_ROLE_KEY`, `SUPABASE_ACCESS_TOKEN`, Cloudflare API tokens, Meta/Instagram app secrets, Gmail/DocuSign API keys, etc.). The `.gitignore` excludes `.env` and `.env.*` — don't override.
- Private keys (.pem, .key, .pfx)
- PAT tokens for GitHub, Supabase, Cloudflare, Vercel
- OAuth client secrets for third-party integrations (Google, Meta, LinkedIn, DocuSign)

### PII / LGPD-sensitive data
- Member emails, phone numbers, PMI IDs, auth IDs (even in test fixtures)
- Real names of non-public members in code comments, docs, commit messages (use synthetic fixture names)
- Private content of signed agreements, certificates with personal data
- Supabase audit log dumps, MCP usage log dumps containing real member activity

### Sensitive knowledge
- Strategic documents not yet public (board decisions, partnership negotiations, financial data)
- Draft legal documents (IP Policy in review, chapter agreements) — these belong in the **private wiki** `nucleo-ia-gp/wiki`
- Unpublished research findings from tribes

### Operational hygiene
- Large binaries (>10MB) — use Git LFS or external storage
- `node_modules/`, `dist/`, `.astro/` — excluded via `.gitignore`
- Personal editor config (`.vscode/settings.json` with paths, `.idea/`) — excluded or scrubbed
- Local Claude Code settings (`.claude/settings.local.json`) — excluded

### What DOES go here
- Source code (public under the repo's license)
- Migrations (schema changes, with rollback documented)
- Documentation referencing public behavior of the platform
- ADRs (architectural decisions, Accepted/Superseded never edited silently)
- CI workflows, `.claude/agents/*`, `.claude/skills/*`, `.claude/rules/*`
- Public fixtures with synthetic data

## Where sensitive content DOES go

See `GOVERNANCE.md` for the full trifold (public repo / private wiki / platform SQL). Short version:

- **Narrative knowledge with private scope** → `github.com/nucleo-ia-gp/wiki` (private Obsidian vault, syncs to `wiki_pages` table with read scoping by domain/ip_track)
- **Operational data (members, events, boards, etc.)** → Supabase SQL with RLS
- **Public methodologies + frameworks** → `github.com/nucleo-ia-gp/frameworks` (public, CC-BY-SA 4.0)

## Pre-commit protection

Run local secret scanner before committing. See `CONTRIBUTING.md` section "Pre-commit hook" for installation of `gitleaks` or similar.

If you accidentally commit a secret:
1. **Do not** push. If already pushed: rotate the secret immediately (Supabase dashboard, Cloudflare dashboard, OAuth app panel, etc.).
2. Remove from history: `git filter-repo --invert-paths --path <file>` (or BFG). Force-push to main requires notification to the team.
3. Report to the security email above so we can audit log downstream impact.

## LGPD (Brazilian Data Protection Law) compliance

The platform implements LGPD Art. 18 cycle:
- Consent gate (`consent_records` table + middleware check)
- Data export (`export_my_data()` RPC)
- Deletion (`delete_member_self()` RPC)
- Anonymization cron (`anonymize_inactive_members`, 5-year retention)

Any change that touches PII-adjacent code (members.*, certificates, attendance, consent) requires:
- RLS enabled
- No anon access to PII tables
- Test coverage in `tests/contracts/privacy-sentry.test.mjs` and `security-lgpd.test.mjs`
- DPO review for public-facing changes (Vitor as interim DPO)

Violations discovered in production must be triaged within 72 hours per ANPD guidance.

## Audit trail

All privileged mutations log to `public.admin_audit_log` (after B8 consolidation, 2026-04-18). Retention: indefinite for operational changes; 5 years for PII-related entries per LGPD.

Audit access: `can_by_member(view_pii)` permission (V4 authority, ADR-0011).
