# ADR-0095: Member Alternate Emails Schema and Identity Resolution RPC

| Field | Value |
|---|---|
| Status | Accepted (amended 2026-05-21 GAP-205.C + GAP-205.D — see end) |
| Date | 2026-05-21 |
| Author | Antigravity (Assisted-By: Gemini) |
| Migrations | 20260802000008_member_alternate_emails.sql, 20260802000009_p213_205_email_theft_guard_and_revoke_authenticated_select.sql, 20260802000010_p213_205_invariant_synthetic_filter.sql, 20260802000011_p214_205b_member_emails_organization_id_fk.sql, 20260802000012_p215_205c_drop_member_emails_verified_at.sql, 20260802000013_p216_205d_member_emails_write_surface.sql |
| Cross-ref | [ADR-0012](./ADR-0012-schema-consolidation-principles.md) |
| Closes | Issue #205 (GAPs A/B closed p214; C closed p215; D closed p216) |

## Context

To modernize the identity resolution layer and support members with multiple active email addresses (e.g. personal, institutional, chapter, or other), the backend must support alternate emails. Previously, members were restricted to a single `email` column in the `public.members` table, which limited our ability to match incoming communication or external platform hooks (like DocuSign or Credly) that might use different email variants for the same person.

We need a design that:
1. Allows members to have multiple alternate emails of different kinds.
2. Enforces that exactly one primary email exists per member.
3. Maintains backward compatibility with existing features and integrations that read or write `public.members.email`.
4. Restricts direct mutation or arbitrary read access to the email lists (under LGPD/GDPR requirements) while exposing secure resolver APIs.

## Decision

We implement the alternate emails subsystem using a new relation, synchronization triggers, database constraints, Security Definer RPCs, and Model Context Protocol (MCP) tools.

### 1. Database Schema

We create the table `public.member_emails` with the following attributes:
- `id` (uuid PRIMARY KEY DEFAULT gen_random_uuid())
- `member_id` (uuid NOT NULL REFERENCES public.members(id) ON DELETE CASCADE)
- `email` (citext UNIQUE NOT NULL)
- `is_primary` (boolean NOT NULL DEFAULT false)
- `kind` (text NOT NULL CHECK (kind IN ('personal', 'institutional', 'chapter', 'other')))
- ~~`verified_at` (timestamptz)~~ — **removed 2026-05-21 via Amendment / GAP-205.C, see end**
- `added_at` (timestamptz NOT NULL DEFAULT now())
- `organization_id` (uuid REFERENCES public.organizations(id) ON DELETE RESTRICT — FK added 2026-05-21 via GAP-205.B / migration 20260802000011)

To guarantee that each member has exactly one primary email, we define a partial unique index:
```sql
CREATE UNIQUE INDEX member_emails_one_primary_idx ON public.member_emails(member_id) WHERE (is_primary = true);
```

### 2. Backward Compatibility Trigger

To keep `public.member_emails` synchronized with the legacy `public.members.email` field, we implement a synchronization trigger function `sync_member_email_trigger_fn` fired `AFTER INSERT OR UPDATE OF email ON public.members`.
- On `INSERT`: Synchronizes the new email as the primary personal email for the member.
- On `UPDATE`: Demotes any existing primary email for the member and upserts the new email as the primary personal email.

### 3. Security and RLS

Access control is locked down using Row Level Security (RLS) policies and revoked grants:
- **Revoked Grants**: Direct `INSERT`, `UPDATE`, `DELETE`, `REFERENCES`, `TRIGGER`, and `TRUNCATE` grants are revoked from `anon` and `authenticated` roles. `SELECT` is also revoked from the `anon` role.
- **Policies**:
  - `rpc_only_deny_all`: Permissive policy returning `USING (false)` to deny direct client-side requests on the PostgREST API surface.
  - `member_emails_v4_org_scope`: Restrictive policy enforcing tenant isolation: `USING ((organization_id = auth_org()) OR (organization_id IS NULL))`.

### 4. Canonical RPC APIs

Three Security Definer functions are defined to manage email queries and additions securely:
- `member_resolve_email(p_email text) RETURNS uuid` (STABLE): Resolves any registered email (primary or alternate) to the corresponding member ID. Gates access to authenticated users.
- `member_list_emails(p_member_id uuid) RETURNS TABLE`: Lists all emails associated with a member. Restricted to the member themselves, or users with `manage_member` / `view_pii` permissions.
- `member_add_alternate_email(p_member_id uuid, p_email text, p_kind text) RETURNS uuid` (VOLATILE): Adds an alternate email to a member. Restricted to self or users with `manage_member` permissions.

### 5. MCP Tool Exposure

The Deno edge function `nucleo-mcp` exposes these RPCs as MCP tools for agentic workflows. The p213 batch shipped the first three (read + add); the p216 batch (GAP-205.D, see amendment) shipped the remaining write surface (remove + set_primary + update_kind), six total:
- `member_resolve_email` (read; ADR-0095 §4 + p213)
- `member_list_emails` (read; ADR-0095 §4 + p213)
- `member_add_alternate_email` (write; ADR-0095 §4 + p213)
- `member_remove_alternate_email` (write; Amendment GAP-205.D + p216)
- `member_set_primary_email` (write; Amendment GAP-205.D + p216)
- `member_update_alternate_email_kind` (write; Amendment GAP-205.D + p216)

### 6. Schema Invariant T

We redefine `check_schema_invariants()` to include `T_member_has_exactly_one_primary_email`, verifying that every member has exactly one primary email in `member_emails` to catch any database-level drift or trigger bypassing. The total number of schema invariants increases from 18 to 19.

## Consequences

- **Robust Resolution**: External integrations can resolve member identities through any registered email address (e.g. institutional or personal).
- **Security Hardening**: Data is isolated at the tenant/organization boundary (`auth_org()`) and direct API manipulations are prevented via restrictive RLS and revoked grants.
- **Invariants Enforcement**: Any drift or breach is immediately detected by the schema invariants test suite.
- **Backward Compatibility**: Existing code writing to `public.members.email` continues to work seamlessly due to the trigger sync, automatically populating primary entries in `public.member_emails`.

## Amendment 2026-05-21 (GAP-205.C / P162 #118)

The `verified_at` column was dropped via migration `20260802000012_p215_205c_drop_member_emails_verified_at.sql`. Rationale:

- **Dead schema**: at p214 close (2026-05-21) the column had zero write paths anywhere in migrations / RPCs / EFs / src / tests. All 73 backfilled rows had `verified_at IS NULL`.
- **YAGNI**: no caller exists; future devs would wonder why the column exists. System policy "don't add features for hypothetical future requirements" applies.
- **Reversibility**: re-adding is a trivial `ALTER TABLE ADD COLUMN verified_at timestamptz` + `DROP/CREATE member_list_emails` if and when a verification flow becomes a real product requirement. Migration 20260802000012 documents the rollback in its header.
- **Pre-existing alternative**: Supabase Auth already verifies primary emails through its standard flow; an alternate-email verification flow would require custom token generation + email-send + verify RPC + UI, which does not exist yet. When that work is scoped, the column can be reintroduced alongside its consumers (not before).

`member_list_emails` RPC return TABLE was simultaneously updated to remove the `verified_at` field. No other RPC, trigger, or invariant referenced the column, so the migration scope is narrow.

## Amendment 2026-05-21 (GAP-205.D / P162 #126)

The write surface of `member_emails` was completed by adding three new RPCs in migration `20260802000013_p216_205d_member_emails_write_surface.sql`:

- `member_remove_alternate_email(p_member_id uuid, p_email text) → boolean` — deletes an alternate row; rejects if the email is the member's primary.
- `member_set_primary_email(p_member_id uuid, p_email text) → boolean` — promotes a registered alternate to primary by routing the change through `UPDATE public.members SET email = ...`, which fires `sync_member_email_trigger_fn` (mig 20260802000009) to handle the demote+promote and preserve the alt kind on conflict. Idempotent on already-primary.
- `member_update_alternate_email_kind(p_member_id uuid, p_email text, p_new_kind text) → boolean` — updates the kind on an alternate; rejects primary mutations.

### Rationale

- **Surfaced organically in p215 PM smoke**: PM added an alternate (`vitor@vitormr.dev`) with kind=`personal` while the original intent was `institutional`. There was no kind-correction path without direct SQL, contradicting the agentic-workflow goal stated in §5.
- **Auth pattern reused unchanged**: the three new RPCs follow the existing `member_add_alternate_email` template — self OR `can_by_member('manage_member')`, SECURITY DEFINER, SET search_path, VOLATILE.
- **Primary-mutation policy**: all three RPCs treat the primary email as a sync-trigger-driven invariant. `remove` and `update_kind` raise on primary; `set_primary` is the only canonical path to change which email is primary, and it routes through `UPDATE members.email` so that the existing cross-member theft guard (mig 20260802000009) remains the single enforcement point.
- **Idempotency**: `set_primary` on already-primary returns true (no-op). `remove` / `update_kind` on a non-registered email return false (not raise) — the distinction is between invalid operations (raise) and absent state (return false).

### MCP surface

Three matching MCP tools were added to `supabase/functions/nucleo-mcp/index.ts`, bumping the catalog from 296 to 299 and the server version from 2.77.0 to 2.78.0.

### Schema invariants

Unchanged at 19. `T_member_has_exactly_one_primary_email` already enforces the partial-unique invariant, which the three RPCs cannot violate because (a) `remove` rejects primary, (b) `set_primary` routes via the existing trigger whose `INSERT ... ON CONFLICT DO UPDATE SET is_primary = true` is itself constrained by the partial unique index, (c) `update_kind` only touches the `kind` column.

### Rollback

```sql
DROP FUNCTION IF EXISTS public.member_remove_alternate_email(uuid, text);
DROP FUNCTION IF EXISTS public.member_set_primary_email(uuid, text);
DROP FUNCTION IF EXISTS public.member_update_alternate_email_kind(uuid, text, text);
NOTIFY pgrst, 'reload schema';
```

MCP tool registrations and the version + tool-count labels in `nucleo-mcp/index.ts` are removed in the same PR.
