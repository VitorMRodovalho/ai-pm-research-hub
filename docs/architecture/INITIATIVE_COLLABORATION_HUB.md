# Initiative Collaboration Hub — Architecture

**Status:** Proposed — pending PM signoff and ADR-0094 ratification
**Companion:** [`INITIATIVE_COLLABORATION_HUB_RESEARCH.md`](./INITIATIVE_COLLABORATION_HUB_RESEARCH.md) (foundation), [`../adr/ADR-0094-initiative-collaboration-hub-architecture.md`](../adr/ADR-0094-initiative-collaboration-hub-architecture.md) (decision record)
**Source issue:** [#212](https://github.com/VitorMRodovalho/ai-pm-research-hub/issues/212)
**Authoritative decisions captured in this doc:**
- G1.1 Capability tier for `partner_contact.liaison` = **view + comment on assigned cards** (PM 2026-05-20)
- G2.4 Cascade direction on Núcleo offboarding = **yes default, per-kind override via `engagement_kinds.retain_access_after_member_offboard`** (PM 2026-05-20)
- G4.1 Google service-account ownership = **org-owned dedicated identity** (PM 2026-05-20)

---

## 1. Purpose

PR #203 (p205 Vassouras initiative seed) surfaced a cluster of gaps that span identity, authority, integration, and UX layers. Patching them one at a time risks layering ad-hoc decisions that diverge from the existing V4 domain model (ADR-0005..0009).

This document defines a coherent architecture for what we are calling the **Initiative Collaboration Hub** — the set of capabilities that turn an `initiative` into a true collaboration surface for both Núcleo members and external partners, with Drive integration, metadata governance, and external-member identity all backed by the same primitives.

The hub is the missing connective tissue between three already-shipped layers:
- **V4 domain model** (ADR-0005 initiative-as-primitive, ADR-0006 person+engagement identity, ADR-0007 authority-as-engagement-grant, ADR-0008 per-kind lifecycle, ADR-0009 config-driven kinds)
- **#110 board Drive integration** (per-board folder links, file references)
- **#209 member-level Drive offboarding cascade** (LGPD Art. 16 — to be implemented; this hub treats it as the foundation it extends)

## 2. Goals & non-goals

### Goals
1. **External member onboarding** — let an initiative add a non-Núcleo collaborator (PMI-RJ chapter board director, university coordinator, student) with scoped capability and explicit LGPD consent.
2. **Engagement-level Drive permission sync** — granting/revoking initiative engagement automatically reflects in Drive folder permissions, with the same audit + approval pattern as #209.
3. **Initiative metadata self-service** — initiative owners edit metadata (WhatsApp, Drive folder, recurring meeting time, YouTube, sponsorship, external collaborators) from UI without CLI/SQL dependency.
4. **Integration governance** — Google API access is operated through an org-owned service account, audited, and rate-limited; the pattern generalizes to Drive, Calendar, Meet, and any future integration.
5. **Multi-hub readiness** — the same primitives must work when PMI-CE, PMI-MG, or any other chapter spins up their own Núcleo IA instance.

### Non-goals (v1)
- Public-link Drive folders (different security model)
- Non-Google identity providers (Microsoft, Apple) for external members — Google-only first
- Real-time collaboration UX (commenting threads beyond what board cards already do)
- Re-conceding access when a re-engaged alumni returns (carry from #209)
- Per-card Drive file permissions (board scope is per-folder)

## 3. Architecture overview

```
              ┌──────────────────────────────────┐
              │   /initiative/[id] (Astro)       │
              │   - Settings panel (G3)          │
              │   - Add external collaborator    │
              │   - Provision Drive folder       │
              └────────┬─────────────────────────┘
                       │ RPC + EF calls
                       ▼
   ┌───────────────────────────────────────────────────────────┐
   │                    Supabase Postgres                       │
   │                                                             │
   │   ┌──────────┐   ┌──────────────────┐  ┌─────────────────┐ │
   │   │ persons  │   │ auth_engagements │  │ engagement_kinds │ │
   │   │ auth_id  │◄──┤ person_id        │  │ retain_access... │ │
   │   │  NULL OK │   │ initiative_id    │  │ default_duration │ │
   │   └──────────┘   │ kind/role/status │  └─────────────────┘ │
   │                  └────┬─────────────┘                       │
   │                       │                                      │
   │   ┌────────────────────▼───────────────┐                    │
   │   │  trigger: engagement_drive_sync     │ ─→ jobs queue     │
   │   └───────────────────┬─────────────────┘                    │
   │                       ▼                                      │
   │   ┌──────────────────────────────────┐                       │
   │   │   google_api_jobs (queue)        │                       │
   │   └──────────────────┬───────────────┘                       │
   │                       │                                       │
   │   ┌─────────────────────────────────────────┐                │
   │   │  engagement_drive_permissions           │                │
   │   │  drive_offboarding_audit (extended)     │                │
   │   │  google_api_call_log                    │                │
   │   └─────────────────────────────────────────┘                │
   └──────────────────────────┬────────────────────────────────────┘
                              │ cron drain (1 min)
                              ▼
              ┌──────────────────────────────────┐
              │   process-google-api-jobs (EF)    │
              │   ├─ Drive API                    │
              │   ├─ Calendar API (#210)          │
              │   └─ Meet API (#208)              │
              └──────────────┬───────────────────┘
                             │
                             ▼
              ┌──────────────────────────────────┐
              │   Google Workspace (org-owned     │
              │   service account, Vault-stored)  │
              └──────────────────────────────────┘
```

Three principles hold the design together:

1. **Engagements drive everything.** Identity (G1) is a `persons` row + `auth_engagements` grants. Drive permissions (G2) are a 1:1 function of active engagements. Metadata edits (G3) are gated by V4 `can(manage_initiative)`. Integration (G4) only fires when engagements change. No side-channels.

2. **Queue + cron + EF for Google.** Postgres triggers never call Google directly. They write rows into `google_api_jobs` and let a cron EF drain. This gives us retry, audit, batching, and decouples Postgres transactions from Google latency. User-driven actions (e.g., "Create Drive folder now") bypass the queue and call the EF directly.

3. **Reuse the existing primitives ruthlessly.** `persons.auth_id` already supports NULL — no new identity table. `engagement_kind_permissions` already gates capability — no new authority model. `initiative_drive_links` already records folder ↔ initiative. Each gap closes with new rows + new edges in existing graph, plus three new tables (`engagement_drive_permissions`, `google_api_jobs`, `google_api_call_log`).

## 4. G1 — External member onboarding

### 4.1 Identity model

External collaborators are modeled as `persons` rows with `auth_id = NULL`:

```sql
-- Example: a PMI-RJ chapter board director invited to Vassouras initiative
INSERT INTO persons (
  organization_id, auth_id, name, email,
  consent_status, consent_accepted_at, consent_version
) VALUES (
  '<nucleo-ia-org-id>',
  NULL,                                       -- no Núcleo login
  'João Coelho Júnior',
  'joao.coelho@<chapter-domain>',
  'accepted',
  now(),
  'v1'
);
```

This requires no schema change. ADR-0006 (`person-engagement-identity-model`) already permits NULL `auth_id`; what was missing was the deliberate use of this state.

### 4.2 Engagement kinds available for externals

| Kind | Display | Use case | Action seed (G1.1 decision) |
|------|---------|----------|-------------------------------|
| `partner_contact` | Contato Parceiro | PMI-RJ chapter directors, university coordinators, partner org liaisons | **view_initiative_dashboard + write_board (assigned only)** |
| `external_reviewer` | Revisor Externo | Academic reviewers, advisor reviewers | `participate_in_governance_review` (already seeded) |
| `external_signer` | Signatário Externo | MOU/contract signers for partner organizations | `sign_external` (to be seeded — narrow scope) |
| `speaker` | Palestrante | Event speakers, webinar guests | `view_initiative_dashboard` (read-only event context) |
| `guest` | Convidado | Low-capability event visitors | `view_initiative_dashboard` (read-only) |

The decision G1.1 locks `partner_contact.liaison` as the primary external collaboration kind, with the others falling out as adjacent surfaces with narrower scope.

### 4.3 Seeded permissions (post-migration)

```sql
INSERT INTO engagement_kind_permissions (kind, role, action, scope, description) VALUES
  ('partner_contact', 'liaison', 'view_initiative_dashboard', 'initiative',
   'View initiative summary, board, members list (no PII for non-coordinators)'),
  ('partner_contact', 'liaison', 'write_board_assigned', 'initiative',
   'Write board cards assigned to this engagement (G1.1 PM decision 2026-05-20)'),
  ('guest', 'participant', 'view_initiative_dashboard', 'initiative',
   'View-only dashboard for event guests'),
  ('speaker', 'speaker', 'view_initiative_dashboard', 'initiative',
   'View-only dashboard for confirmed event speakers'),
  ('external_signer', 'signer', 'sign_external', 'initiative',
   'Counter-sign external documents (MOU, partnership agreement)');
```

A new action `write_board_assigned` is required because `write_board` is too broad. The implementation gates board write to rows where `board_items.assignee_engagement_id` references the caller's engagement; this needs:
- A new column `board_items.assignee_engagement_id uuid REFERENCES auth_engagements(engagement_id) ON DELETE SET NULL`
- An RLS policy extension on `board_items` that allows write when the new action passes
- A `can()` matcher for `write_board_assigned` that does the scoped check

(This is mechanical V4 work consistent with ADR-0007. It is captured as one of the G1 sub-issue acceptance criteria.)

### 4.4 LGPD consent capture flow (G1.2 — recommendation)

**Recommendation:** v1 = PM-attested checkbox in "Add external collaborator" flow; v2 = optional email-link verification.

The "Add external collaborator" modal in `/initiative/[id]` Settings panel shows:

> ☐ Confirmo que [Nome do colaborador] aceitou os termos de tratamento de dados pessoais do Núcleo IA (LGPD). A confirmação fica registrada no audit log com o nome de quem confirmou.

On submit, the RPC creates the `persons` row with `consent_status='accepted'`, `consent_accepted_at=now()`, `consent_version='v1'`, and writes an `admin_audit_log` entry with kind=`external_collaborator_consent_attested`, details=`{attested_by_member_id, collaborator_name, collaborator_email, initiative_id}`.

This unblocks Vassouras (T-11d). A future enhancement (v2) generates a signed link to a public consent page; the collaborator clicks, accepts, and returns. The schema doesn't change; only the entry point does.

### 4.5 Multi-email model (G1.3 — recommendation)

**Recommendation:** reuse `persons.secondary_emails text[]` for v1; generalize to `person_emails` table only if external collaborators reveal need.

Why: `persons.secondary_emails` already exists and is sufficient for the typical case (one personal email + one institutional email). Building `person_emails` mirroring `member_emails` is YAGNI for v1. If #205's `member_emails` proves the multi-email-with-verification pattern is needed, we generalize then.

### 4.6 Engagement lifecycle config for externals

```sql
UPDATE engagement_kinds SET
  default_duration_days = 90,
  auto_expire_behavior = 'offboard',
  notify_before_expiry_days = 14,
  retain_access_after_member_offboard = false  -- new column from G2.4
WHERE slug IN ('partner_contact', 'guest', 'speaker');

-- external_reviewer / external_signer per existing kind config (longer duration possible)
UPDATE engagement_kinds SET
  default_duration_days = 365,
  auto_expire_behavior = 'notify_only',
  retain_access_after_member_offboard = false
WHERE slug = 'external_reviewer';
```

Externals default to 90-day engagements with auto-offboard. Initiative owner can extend manually before expiry. After offboard, the persons row is retained (anonymized at end of retention per `engagement_kinds.retention_days_after_end`, default 1825 days = 5y).

### 4.7 New RPC: `add_external_collaborator`

```sql
CREATE OR REPLACE FUNCTION add_external_collaborator(
  p_initiative_id uuid,
  p_email text,
  p_name text,
  p_kind text DEFAULT 'partner_contact',
  p_role text DEFAULT 'liaison',
  p_partner_entity_id uuid DEFAULT NULL,
  p_consent_attested boolean DEFAULT false,
  p_engagement_end_date date DEFAULT NULL,
  p_metadata jsonb DEFAULT '{}'::jsonb
) RETURNS jsonb
```

Behavior:
1. Gate: caller has `can(p_action='manage_initiative', p_resource_id=p_initiative_id)`. If not, RAISE.
2. Validate: `p_consent_attested=true` mandatory; `p_kind` in {partner_contact, external_reviewer, external_signer, speaker, guest}; `p_email` shape valid.
3. Resolve or create `persons` row: if `email` already exists in `persons.email` OR `persons.secondary_emails`, reuse that person; else INSERT new with `auth_id=NULL`, `consent_status='accepted'`.
4. INSERT `auth_engagements` row with computed `end_date` (defaults to today + `engagement_kinds.default_duration_days`).
5. If `p_partner_entity_id` present, link via `initiatives.origin_partner_entity_id` OR via a future `engagement_partner_link` table (defer).
6. Write `admin_audit_log` row.
7. **Side effect (G2 integration):** enqueue `google_api_jobs` row for Drive permission grant (if initiative has a linked Drive folder).
8. Return `{ok: true, person_id, engagement_id, drive_job_id?}`.

### 4.8 UI surface

`/initiative/[id]` gets a new "Configurações" tab (G3 territory; details in §6):
- Section "Colaboradores externos"
- Button "Adicionar colaborador externo" → modal calling `add_external_collaborator`
- List of current externals with: name, kind, role, expires_at (formatted), action buttons (extend, revoke)

## 5. G2 — Engagement-level Drive permission sync

### 5.1 New table `engagement_drive_permissions`

```sql
CREATE TABLE engagement_drive_permissions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  engagement_id uuid NOT NULL REFERENCES auth_engagements(engagement_id) ON DELETE CASCADE,
  drive_folder_id text NOT NULL,
  drive_permission_id text,                      -- Google's permission ID (null until granted)
  permission_type text NOT NULL CHECK (permission_type IN ('user', 'anyone_with_link')),
  permission_role text NOT NULL CHECK (permission_role IN ('viewer', 'commenter', 'editor')),
  granted_at timestamptz,
  granted_by_member_id uuid REFERENCES members(id),
  revoked_at timestamptz,
  revoked_audit_id uuid REFERENCES drive_offboarding_audit(id),
  status text NOT NULL CHECK (status IN ('pending', 'granted', 'pending_revoke', 'revoked', 'failed')),
  organization_id uuid NOT NULL DEFAULT '<nucleo-ia-org-id>',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (engagement_id, drive_folder_id, status) WHERE status IN ('pending', 'granted')
);
```

One row per (engagement, folder, lifecycle-event). When an engagement is created, one or more rows are inserted with `status='pending'`. The cron EF drains the queue, calls Drive API, fills `drive_permission_id`, sets `status='granted'`. On revoke, status moves through `pending_revoke` → `revoked`.

### 5.2 Cardinality (G2.1 — recommendation)

**Recommendation:** 1 engagement → N folder permissions. One row per (engagement, initiative_drive_link).

Why: explicit, auditable, and surgical. When you revoke an engagement, you know exactly which Drive permissions to remove. Google's folder-cascade is unreliable for nested subfolders with mixed permission inheritance.

When initiative has multiple Drive folders (e.g., a `primary_workspace` + a `public_assets`), engagement gets N rows — one per folder. The `link_purpose` field on `initiative_drive_links` can vary the granted `permission_role` (e.g., `viewer` for `public_assets`, `editor` for `primary_workspace`).

### 5.3 Trigger: enqueue Drive grant on engagement INSERT

```sql
CREATE OR REPLACE FUNCTION _trg_engagement_drive_sync_grant()
RETURNS TRIGGER AS $$
DECLARE
  v_folder RECORD;
  v_role text;
BEGIN
  IF NEW.status <> 'active' THEN RETURN NEW; END IF;
  IF NEW.initiative_id IS NULL THEN RETURN NEW; END IF;

  FOR v_folder IN
    SELECT id, drive_folder_id, link_purpose
    FROM initiative_drive_links
    WHERE initiative_id = NEW.initiative_id
      AND unlinked_at IS NULL
  LOOP
    -- Map link_purpose to role
    v_role := CASE
      WHEN v_folder.link_purpose = 'public_assets' THEN 'viewer'
      WHEN v_folder.link_purpose = 'primary_workspace' THEN 'commenter'
      ELSE 'commenter'
    END;

    INSERT INTO engagement_drive_permissions (
      engagement_id, drive_folder_id, permission_type, permission_role, status, granted_by_member_id
    ) VALUES (
      NEW.engagement_id, v_folder.drive_folder_id,
      'user', v_role, 'pending', NEW.created_by_member_id  -- assume column exists or use auth.uid()
    );

    -- Enqueue the actual API call
    INSERT INTO google_api_jobs (job_type, payload, status)
    VALUES (
      'drive_permission_grant',
      jsonb_build_object(
        'engagement_drive_permission_id', currval('engagement_drive_permissions_id_seq')
      ),
      'pending'
    );
  END LOOP;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER trg_engagement_drive_grant
AFTER INSERT ON auth_engagements
FOR EACH ROW EXECUTE FUNCTION _trg_engagement_drive_sync_grant();
```

Mirror trigger for soft-delete / status='inactive' that enqueues `drive_permission_revoke`.

### 5.4 External member without Google account (G2.2 — recommendation)

**Recommendation:** share-link fallback + audit, with explicit warning to PM at "Add external collaborator" time.

When `add_external_collaborator` is called and the email is not a Google account (detected by attempting to find a Google identity via Drive API, OR by domain heuristic — `.edu.br`, `.gov.br`, certain known-non-Google domains), the flow:
1. UI warns: "Este email não está vinculado a uma conta Google. Será gerado um link compartilhado de visualização. Continuar?"
2. PM confirms.
3. Engagement is created normally.
4. `engagement_drive_permissions.permission_type='anyone_with_link'`; the Drive API call generates a share link.
5. `add_external_collaborator` returns the share link in the response; UI displays it; PM forwards via WhatsApp/email.
6. On revoke, the share link is deleted (Drive API call); the link breaks for everyone using it (acceptable trade-off — log the breakage in audit).

### 5.5 Drive folder auto-creation on initiative INSERT (G2.3 — recommendation)

**Recommendation:** auto-create by default; per-kind opt-out via `engagement_kinds.metadata_schema`.

A new column on `engagement_kinds`... wait — actually this is per **initiative_kinds**, not engagement_kinds. Let me restate:

A new column on `initiative_kinds` (table that exists per ADR-0009 config-driven kinds):
```sql
ALTER TABLE initiative_kinds ADD COLUMN auto_provision_drive_folder boolean NOT NULL DEFAULT true;
```

(If `initiative_kinds` doesn't exist as a table yet — it might be a `text` CHECK on `initiatives.kind` — then we add this metadata to a sibling table or to `initiatives.metadata` schema validation.)

When `create_initiative` is called:
1. INSERT initiative row.
2. If `initiative_kinds.auto_provision_drive_folder=true`, enqueue `google_api_jobs` row with `job_type='drive_folder_create'`, payload includes initiative_id + folder name template (`[kind] - [title]`).
3. Cron EF creates folder in a parent location (configured per organization), captures folder_id, calls `link_initiative_to_drive(initiative_id, folder_id, ...)`.

For kinds where Drive isn't natural (e.g., `alumni_event`, `pilot`), set `auto_provision_drive_folder=false` and provide the "Provisionar pasta Drive" button in G3 UI for manual on-demand.

### 5.6 Cascade direction on Núcleo offboarding (G2.4 — LOCKED PM 2026-05-20)

**Decision (G2.4):** Yes by default + per-kind override via `engagement_kinds.retain_access_after_member_offboard boolean default false`.

Implementation:
1. New column `engagement_kinds.retain_access_after_member_offboard boolean NOT NULL DEFAULT false`.
2. #209's cron `audit-drive-offboarding-access` walks `members WHERE member_status IN ('inactive','alumni')`, then for each one, finds active engagements:
   ```sql
   SELECT ae.*, ek.retain_access_after_member_offboard
   FROM auth_engagements ae
   JOIN engagement_kinds ek ON ek.slug = ae.kind
   JOIN persons p ON p.id = ae.person_id
   JOIN members m ON m.id = ae.legacy_member_id
   WHERE m.member_status IN ('inactive', 'alumni')
     AND ae.status = 'active'
     AND ek.retain_access_after_member_offboard = false;
   ```
3. For each row returned, insert `drive_offboarding_audit` entries (one per `engagement_drive_permissions` row) with `status='pending_approval'`, scoped to GP approval batch.
4. After GP approves, EF calls Drive API to revoke; updates `engagement_drive_permissions.status='revoked'`.

For the future alumni-keeps-access case:
```sql
UPDATE engagement_kinds
SET retain_access_after_member_offboard = true
WHERE slug = 'alumni';  -- once alumni kind starts being used
```

### 5.7 Extension to `drive_offboarding_audit`

`#209` will introduce `drive_offboarding_audit` with `member_id` as the primary key/scope. G2 extends:

```sql
-- Extension applied in G2's migration (depends on #209 having shipped or shipped together)
ALTER TABLE drive_offboarding_audit
  ADD COLUMN engagement_id uuid REFERENCES auth_engagements(engagement_id),
  ADD COLUMN engagement_drive_permission_id uuid REFERENCES engagement_drive_permissions(id),
  ADD CONSTRAINT chk_audit_scope CHECK (
    member_id IS NOT NULL OR engagement_id IS NOT NULL
  );
```

Single audit table. Single approval gate. Single revoke EF. Both member-level (#209) and engagement-level (G2) cascades flow through the same surface.

## 6. G3 — Initiative metadata UI

### 6.1 Scope alignment with #211

#211 is filed for: WhatsApp URL, Drive folder, recurring meeting time, YouTube channel, sponsorship details. #212 G3 adds: "Add external collaborator" flow + "Provision Drive folder" button + permission gating.

**Recommendation (M2):** Keep #211 OPEN as the implementation issue for the metadata-fields portion of G3. Open a NEW sub-issue (G3 here) for the composite-flow + permission portion. Both fold into the same `/initiative/[id]` Configurações tab.

### 6.2 UI structure

`/initiative/[id]` gets a new tab next to the existing visualization tabs:

```
┌ Visão geral  Membros  Board  Eventos  [Configurações] ──┐
│                                                            │
│  ⚙️ Configurações da iniciativa                            │
│                                                            │
│  ▸ Metadata (#211)                                         │
│    - WhatsApp URL: [____________________________] [Salvar]│
│    - Pasta Drive principal:                                │
│      ⊙ Vinculada: <link>  [Desvincular]                   │
│      ⊙ Não vinculada      [Criar pasta] [Vincular existente]│
│    - Reunião recorrente: [Seg ▾] [19:30] [60 min] [Salvar]│
│    - Canal YouTube: [____________________] [Salvar]        │
│    - Detalhes patrocínio: [...]                            │
│                                                            │
│  ▸ Colaboradores externos (G3 + G1)                        │
│    [+ Adicionar colaborador externo]                       │
│    ┌──────────────────────────────────────────────────┐   │
│    │ João Coelho Júnior                                │   │
│    │   partner_contact / liaison · Expira em 90 dias  │   │
│    │   PMI-RJ Diretoria · Drive: ✓ granted            │   │
│    │   [Estender prazo] [Revogar]                     │   │
│    └──────────────────────────────────────────────────┘   │
└────────────────────────────────────────────────────────────┘
```

### 6.3 Permission gate (G3.1 — recommendation)

**Recommendation:** V4 `can(p_action='manage_initiative', p_resource_id=initiative_id)`.

A new action `manage_initiative` is seeded for:
- `volunteer.co_gp`, `volunteer.deputy_manager`, `volunteer.manager` (org-wide org-managers)
- `volunteer.leader` (initiative-scoped owners — only for their initiatives)
- `committee_coordinator.coordinator` (committee-scoped — only for their initiatives)
- `study_group_owner.owner`, `study_group_owner.leader`
- `workgroup_coordinator.coordinator`

```sql
INSERT INTO engagement_kind_permissions (kind, role, action, scope) VALUES
  ('volunteer', 'co_gp', 'manage_initiative', 'organization'),
  ('volunteer', 'deputy_manager', 'manage_initiative', 'organization'),
  ('volunteer', 'manager', 'manage_initiative', 'organization'),
  ('volunteer', 'leader', 'manage_initiative', 'initiative'),
  ('committee_coordinator', 'coordinator', 'manage_initiative', 'initiative'),
  ('study_group_owner', 'owner', 'manage_initiative', 'initiative'),
  ('study_group_owner', 'leader', 'manage_initiative', 'initiative'),
  ('workgroup_coordinator', 'coordinator', 'manage_initiative', 'initiative');
```

This gates both metadata edits AND external collaborator adds. Non-managers see the Configurações tab as read-only.

### 6.4 Backend RPC (G3 reuses existing `update_initiative`)

`update_initiative(p_initiative_id, p_title, p_description, p_status, p_metadata)` already accepts a jsonb metadata blob and validates it via `validate_initiative_metadata`. #211 work expands the validator's schema to recognize the new fields:

```sql
-- inside validate_initiative_metadata, extend schema for the new fields
-- (illustrative — actual implementation per #211)
v_schema := v_schema || jsonb_build_object(
  'whatsapp_url', jsonb_build_object('type', 'string', 'format', 'url', 'optional', true),
  'recurring_meeting', jsonb_build_object(
    'type', 'object',
    'properties', jsonb_build_object(
      'weekday', jsonb_build_object('enum', ARRAY['mon','tue','wed','thu','fri','sat','sun']),
      'time', jsonb_build_object('format', 'time'),
      'duration_minutes', jsonb_build_object('type', 'integer'),
      'timezone', jsonb_build_object('type', 'string')
    ),
    'optional', true
  ),
  'youtube_channel_event', jsonb_build_object('type', 'string', 'optional', true),
  'logistics_external', jsonb_build_object('type', 'object', 'optional', true)
);
```

Drive folder add is NOT in `update_initiative` — that's `link_initiative_to_drive` (existing). External collaborator add is `add_external_collaborator` (new in G1). The UI Configurações tab orchestrates which RPC fires per action.

### 6.5 Audit

Every metadata edit creates one `admin_audit_log` entry with:
- `kind` = `'initiative_metadata_updated'`
- `details` = jsonb with `{initiative_id, fields_changed: [...], old_values: {...}, new_values: {...}}`
- `member_id` = caller

The existing `update_initiative` likely emits this already (audit it at implementation time).

## 7. G4 — Google API integration governance

### 7.1 Service account ownership (G4.1 — LOCKED PM 2026-05-20)

**Decision:** Org-owned dedicated identity. A Google Workspace user account (or a Workspace-managed service account) lives in a Núcleo-IA-controlled Workspace tenant. PM provisions this once.

Operational steps (M1 / setup phase, before G4 implementation):
1. Provision Google Workspace tenant (or use existing if the org has one).
2. Create a user account or service account dedicated to platform integration. The exact name is operationally chosen but must not be PM's personal Google account.
3. Generate service account key (JSON); store in Supabase Vault as `google_service_account_key` secret.
4. Grant the service account Drive API + Calendar API + Meet API scopes via Workspace admin console.
5. For each existing Drive folder used by the platform (the "Pasta-mãe Núcleo IA" `1PFLzCa8dwjFNhc_y3TPOnkN9O7jfbqnA` etc.), transfer ownership OR grant the service account editor access.

**Multi-hub future:** Each new hub (PMI-CE, PMI-MG, etc.) provisions its own service account in its own Workspace tenant. The platform stores per-organization Vault secrets keyed by `organization_id`. No code change in the architecture; only Vault entries multiply.

### 7.2 Google API call envelope (G4.2 — recommendation)

**Recommendation:** Hybrid model — queue for batch/trigger flows, direct EF call for user-driven actions.

#### Queue path (for trigger-driven flows like engagement INSERT cascade)

```sql
CREATE TABLE google_api_jobs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  job_type text NOT NULL CHECK (job_type IN (
    'drive_permission_grant', 'drive_permission_revoke',
    'drive_folder_create', 'drive_folder_archive',
    'calendar_attendee_update', 'meet_transcript_fetch'
  )),
  payload jsonb NOT NULL,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'in_progress', 'success', 'failed', 'dead_letter')),
  attempts integer NOT NULL DEFAULT 0,
  max_attempts integer NOT NULL DEFAULT 5,
  next_attempt_at timestamptz DEFAULT now(),
  last_error text,
  organization_id uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  started_at timestamptz,
  finished_at timestamptz
);

CREATE INDEX idx_google_api_jobs_pending ON google_api_jobs (next_attempt_at) WHERE status = 'pending';
```

A cron EF `process-google-api-jobs` runs every minute, claims `pending` rows (`FOR UPDATE SKIP LOCKED`), calls Google API, updates status. Exponential backoff via `next_attempt_at` on failure. Dead-lettered after `max_attempts`.

#### Direct path (for user-driven actions like "Create folder now")

UI calls EF endpoint directly (e.g., `POST /functions/v1/drive-folder-create`). EF reads service account key, calls Drive API synchronously, returns folder metadata. UI updates immediately. EF still writes to `google_api_call_log` for audit.

### 7.3 Audit table

```sql
CREATE TABLE google_api_call_log (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  api_surface text NOT NULL CHECK (api_surface IN ('drive', 'calendar', 'meet', 'admin')),
  endpoint text NOT NULL,
  caller_kind text NOT NULL CHECK (caller_kind IN ('job', 'user_direct')),
  caller_member_id uuid REFERENCES members(id),
  caller_job_id uuid REFERENCES google_api_jobs(id),
  payload_summary jsonb,
  response_status integer,
  response_body_summary jsonb,
  duration_ms integer,
  organization_id uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
```

LGPD audit Art. 37 + ops visibility. `payload_summary` and `response_body_summary` are deliberately summaries (no full PII dumps, since payloads often contain emails — pass through a redactor before logging).

### 7.4 Rate limiting + backoff

- Per-EF concurrency limit (Supabase EF runtime can be configured).
- Per-job exponential backoff: 1s, 2s, 4s, 8s, ..., capped at 1h between attempts.
- Dead-letter after `max_attempts` (default 5); GP gets a notification with the job summary.
- Drive API free tier is 1B requests/day — not the bottleneck. Calendar API is similar. Meet API has stricter quotas; #208's pipeline must respect.

### 7.5 Threat model extension (ADR-0018 update)

New surfaces to consider:
- **Service account key leakage** — store ONLY in Vault, never in env, never in code, never in git. Rotate annually.
- **Quota exhaustion** — a runaway loop creating 10k engagements could spam the queue. Hard cap on `google_api_jobs` per organization per day.
- **Audit log tampering** — `google_api_call_log` is append-only; no UPDATE/DELETE granted to any role.
- **Privilege escalation via service account** — service account scopes are minimal (Drive, Calendar, Meet); no Workspace admin, no payment, no domain settings.

## 8. Multi-hub readiness (M1)

**Recommendation:** Design for multi-hub from day one; defer implementation to when a second hub is concrete.

Every new table introduced here (`engagement_drive_permissions`, `google_api_jobs`, `google_api_call_log`) carries `organization_id` from creation. Every cron and EF scopes work by `organization_id`. The service account Vault key is per-organization (`google_service_account_key_<org_uuid>`).

The single non-trivial multi-hub work item, deferred to that moment:
- Per-organization Vault secret routing in EFs.
- Per-organization Drive parent folder mapping (each hub has its own root).
- Cross-organization initiative is NOT supported (initiative belongs to one org; partner_entity may span orgs).

A future ADR will formalize the multi-hub posture (cross-reference ADR-0004 multi-tenancy posture).

## 9. Migration plan & order of operations

### Phase A — Foundation (independent, can ship parallel)
1. **#209 ships first or in parallel** — establishes service account, `drive_offboarding_audit` table, approval gate, revoke EF. **HARD DEPENDENCY** for G2.
2. Provision org-owned Google service account, Vault key, Workspace setup (G4.1 ops task — PM does this).

### Phase B — G4 infrastructure (one migration + one EF)
3. Migration: `google_api_jobs` table + `google_api_call_log` table.
4. EF: `process-google-api-jobs` (cron every 1 min).
5. EF library: shared Google API client (handles auth, retry, logging).

### Phase C — G1 external onboarding (one migration + one RPC + UI)
6. Migration: seed `engagement_kind_permissions` for `partner_contact`/`guest`/`speaker`/`external_signer`/`external_reviewer`; new action `write_board_assigned`; new column `board_items.assignee_engagement_id`; new column `engagement_kinds.retain_access_after_member_offboard`.
7. Migration: `update_initiative` validator extension for new metadata fields (or coordinate with #211).
8. New RPC `add_external_collaborator`.
9. UI: "Configurações" tab in `/initiative/[id]` + "Add external collaborator" modal (composite with G3).

### Phase D — G2 engagement-Drive sync (one migration + 2 EFs + 2 triggers)
10. Migration: `engagement_drive_permissions` table; extend `drive_offboarding_audit` with `engagement_id` + check constraint.
11. Triggers: `_trg_engagement_drive_sync_grant` AFTER INSERT on `auth_engagements`; mirror on UPDATE-to-revoke + soft-delete.
12. EF: extend `process-google-api-jobs` to handle Drive permission grants/revokes.
13. EF: enhance #209's `revoke-drive-permission` to also process engagement-level revocations.

### Phase E — G3 polish (UI + tests)
14. Implement #211 (metadata UI fields).
15. Implement #212 G3 sub-issue (external collaborator UI surface + Drive provision button).
16. MCP tools surfacing: `add_external_collaborator`, `list_external_collaborators`, `extend_external_engagement`, `revoke_external_engagement`.

### Phase F — Vassouras tactical (independent, can run any time)
17. Run the manual workaround runbook (see RESEARCH.md §7) for the 02-Jun event. No code dependency.

## 10. Sub-issues to spawn from this architecture

Four sub-issues will be opened from #212, scoped per the boundaries below. See `INITIATIVE_COLLABORATION_HUB_RESEARCH.md` §6 for the full sketches; final acceptance criteria are tightened in this doc.

- **G1 sub-issue** — external member onboarding (RPC + permissions seed + RLS extension + UI modal). Effort M ~6-8h. Hard dep: none.
- **G2 sub-issue** — engagement-level Drive permission sync (table + triggers + EF). Effort L ~10-12h. Hard dep: **#209**.
- **G3 sub-issue** — initiative metadata UI composite flows (extends #211). Effort M ~3-4h on top of #211. Hard dep: G1 + G2.
- **G4 sub-issue** — Google API governance (queue table + cron EF + audit log + ADR ratification). Effort M-L ~6-8h. Hard dep: PM provisions service account.

## 11. Decisions ratified inline (not requiring further AskUserQuestion)

These are my recommendations from RESEARCH.md §5 that PM did not separately AskUserQuestion on; they are assumed accepted with this doc. PM can override in review.

| # | Decision | Resolution |
|---|----------|------------|
| G1.2 | LGPD consent capture flow | PM-attested checkbox v1; email-link verification v2 (deferred) |
| G1.3 | Multi-email model for `persons` | Reuse `secondary_emails text[]`; generalize to `person_emails` if needed |
| G2.1 | Engagement → Drive permission cardinality | 1 engagement → N folder permissions (one row per pair) |
| G2.2 | External member without Google account | Share-link fallback + UI warning + audit |
| G2.3 | Drive folder auto-creation on initiative INSERT | Auto by default; per-kind opt-out via `auto_provision_drive_folder` |
| G3.1 | Permission to edit initiative metadata | V4 `can(manage_initiative)` action — new seed |
| G4.2 | Google API call envelope | Hybrid: queue for triggers/batch, direct EF for user-driven |
| M1 | Multi-hub readiness timing | Design for multi-hub from day one; defer implementation until 2nd hub is real |
| M2 | #211 status post-#212 | Keep #211 OPEN as G3 metadata-fields implementation issue; new sub-issue for composite flows |
| M3 | Vassouras workaround timing | Runbook lives in RESEARCH.md §7; can execute any time without dependency on G1-G4 |

## 12. Open items for PM review (final pass)

Before this architecture is ratified into ADR-0094 and sub-issues are spawned, PM confirms:
1. The three locked decisions (G1.1, G2.4, G4.1) accurately captured.
2. The seven ratified-inline decisions (table §11) accepted or flagged for further discussion.
3. The migration order in §9 — particularly whether #209 must ship before G2 starts, or whether the two can ship together as one coordinated wave.
4. The service-account provisioning (G4.1 ops task) timeline — this is a PM blocker for Phase B-D start.
5. Approval to spawn the four G1/G2/G3/G4 sub-issues from this doc.

## 13. References

| Reference | Why it matters |
|-----------|----------------|
| Issue #212 | Source of the gap framing |
| Issue #209 | Hard dependency for G2 + foundation for service account |
| Issue #211 | Subsumed by G3 metadata UI |
| Issue #204 | Parent umbrella |
| ADR-0005 | Initiative as domain primitive — G2/G3 build on |
| ADR-0006 | Person+engagement identity — G1 builds on |
| ADR-0007 | Authority as engagement grant — G1.1 capability tier |
| ADR-0008 | Per-kind engagement lifecycle — G1.4 expiry config |
| ADR-0009 | Config-driven kinds — G2.3/G2.4 per-kind overrides |
| ADR-0011 | V4 auth pattern — RPC/MCP gating |
| ADR-0018 | MCP threat model — extended in §7.5 for Google API |
| ADR-0094 (this PR) | Decision record for this hub |
| `INITIATIVE_COLLABORATION_HUB_RESEARCH.md` | Foundation: cross-refs + schema survey + decision inventory |

---

**End of architecture.** Next: PM ratification → ADR-0094 marked Accepted → 4 sub-issues spawned → implementation begins.
