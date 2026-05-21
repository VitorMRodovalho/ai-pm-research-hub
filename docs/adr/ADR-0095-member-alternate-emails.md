# ADR-0095: Member Alternate Emails Schema and Identity Resolution RPC

| Field | Value |
|---|---|
| Status | Accepted |
| Date | 2026-05-21 |
| Author | Antigravity (Assisted-By: Gemini) |
| Migrations | [20260802000008_member_alternate_emails.sql](file:///home/vitormrodovalho/projects/ai-pm-research-hub/supabase/migrations/20260802000008_member_alternate_emails.sql) |
| Cross-ref | [ADR-0012](./ADR-0012-schema-consolidation-principles.md) |
| Closes | Issue #205 |

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
- `verified_at` (timestamptz)
- `added_at` (timestamptz NOT NULL DEFAULT now())
- `organization_id` (uuid)

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

The Deno edge function `nucleo-mcp` exposes these three RPCs as MCP tools for agentic workflows:
- `member_resolve_email`
- `member_list_emails`
- `member_add_alternate_email`

### 6. Schema Invariant T

We redefine `check_schema_invariants()` to include `T_member_has_exactly_one_primary_email`, verifying that every member has exactly one primary email in `member_emails` to catch any database-level drift or trigger bypassing. The total number of schema invariants increases from 18 to 19.

## Consequences

- **Robust Resolution**: External integrations can resolve member identities through any registered email address (e.g. institutional or personal).
- **Security Hardening**: Data is isolated at the tenant/organization boundary (`auth_org()`) and direct API manipulations are prevented via restrictive RLS and revoked grants.
- **Invariants Enforcement**: Any drift or breach is immediately detected by the schema invariants test suite.
- **Backward Compatibility**: Existing code writing to `public.members.email` continues to work seamlessly due to the trigger sync, automatically populating primary entries in `public.member_emails`.
