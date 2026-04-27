# ADR-0044: `generate_manual_version` V3→V4 + 2-of-N approval pattern

- Status: **Accepted** (2026-04-27 — PM Vitor pre-ratified per p70 decision log §B.2)
- Data: 2026-04-27 (p72)
- Autor: PM (Vitor) + Claude (proposal autônomo)
- Escopo:
  - Section A — New table `pending_manual_version_approvals` (proposal state + 24h expiry)
  - Section B — `propose_manual_version(p_version_label, p_notes)` RPC
    (V4 `manage_platform`; creates pending row + notifies signers)
  - Section C — `confirm_manual_version(p_proposal_id)` RPC
    (V4 `manage_platform` + must be different actor than proposer; executes
    actual generation logic)
  - Section D — `cancel_manual_version_proposal(p_proposal_id, p_reason)` RPC
    (V4 `manage_platform`; cancels pending proposal)
  - Section E — DROP legacy `generate_manual_version` (replaced by 2-fn flow)
  - Section F — New notification type `governance_manual_proposed`
- Implementation:
  - Migration `20260514060000_adr_0044_manual_version_2_of_n_approval.sql`
- Cross-references: ADR-0007 (V4 authority), ADR-0011 (cutover),
  ADR-0016 (IP ratification 2-of-N pattern, the design predecessor),
  ADR-0022 (notification catalog), ADR-0043 (engagement-aware notifications)

---

## Contexto

PM decision log §B.2 ratified converting `generate_manual_version` from V3
(`is_superadmin = true`) to V4 (`can_by_member('manage_platform')`) with
a **2-of-N approval safeguard**.

**The concern**: `generate_manual_version` is a high-impact, mostly-irreversible
operation:
1. Marks the current Manual as `superseded`
2. Creates a new Manual document version
3. Marks all `change_requests.status = 'approved'` as `implemented`
4. Locks `manual_version_from`/`manual_version_to` on the CRs

A single actor with `manage_platform` could unilaterally publish a new
manual version. PM ratify §B.2 considered this excessive concentration of
authority for a governance-document mutation.

**Solution**: split into two phases — `propose` + `confirm` — with the
constraint that proposer ≠ confirmer (different actors required), and a
24h expiry window to keep the pending state bounded.

This mirrors the IP ratification 2-of-N pattern from ADR-0016 (chapter
president signoff chain), but applied at the platform level for
manage_platform-tier governance changes.

---

## Decisão

### Section A — `pending_manual_version_approvals` table

```sql
CREATE TABLE public.pending_manual_version_approvals (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  version_label text NOT NULL,
  notes text,
  proposed_by uuid NOT NULL REFERENCES members(id),
  proposed_at timestamptz NOT NULL DEFAULT now(),
  signoff_member_id uuid REFERENCES members(id),  -- set on confirm
  signoff_at timestamptz,                          -- set on confirm
  status text NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending','confirmed','expired','cancelled')),
  expires_at timestamptz NOT NULL DEFAULT (now() + interval '24 hours'),
  governance_document_id uuid REFERENCES governance_documents(id),  -- set on confirm
  cancelled_at timestamptz,
  cancelled_by uuid REFERENCES members(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
```

Indexes:
- `(status, expires_at) WHERE status = 'pending'` — hot path for finding
  active proposals
- `(proposed_by)` — lookup by proposer

RLS: only `manage_platform` holders can SELECT (RLS policy enforced).
INSERT/UPDATE only via SECDEF RPCs (table not direct-writable).

### Section B — `propose_manual_version(p_version_label, p_notes)`

Pre-conditions:
1. Auth check: `can_by_member('manage_platform')`
2. `p_version_label` non-empty
3. Approved CRs exist (preserves V3 invariant)
4. No pending proposal already exists (avoid concurrent proposals)
5. Version label not already in `governance_documents`

On success:
- INSERT pending row
- Audit log: `manual_version_proposed`
- Notify all OTHER `manage_platform` holders (excluding proposer)
- Returns `{ success, proposal_id, version_label, crs_count, expires_at }`

### Section C — `confirm_manual_version(p_proposal_id)`

Pre-conditions:
1. Auth check: `can_by_member('manage_platform')`
2. Proposal exists, status = 'pending'
3. Within 24h window (auto-expires if past)
4. Caller ≠ proposed_by (2-of-N constraint)
5. Re-validate approved CRs still exist
6. Re-validate version label still unused

On success — executes the actual generation logic:
- Marks current `manual` as `superseded`
- INSERT new `governance_documents` row with `description` referencing
  both proposer and signer for full audit trail
- UPDATE `change_requests`: status='implemented', `implemented_by` =
  signer, version_to = label
- UPDATE proposal: status='confirmed', signoff_member_id, signoff_at,
  governance_document_id
- Audit log: `manual_version_confirmed` with both actors
- Notify chapter board + sponsors (via `governance_manual_proposed` type
  reused for "manual published" announcement)
- INSERT announcement draft

Returns full result with both actors' IDs + timestamps.

### Section D — `cancel_manual_version_proposal(p_proposal_id, p_reason)`

Allows proposer (or any `manage_platform` holder) to cancel a pending
proposal before confirmation. Use case: typo in version_label, pending
CR became contentious, etc. Audit log captures the cancellation reason.

### Section E — DROP `generate_manual_version`

Legacy fn dropped (no frontend callsites verified pre-apply — `grep -rn
generate_manual_version src/` returned 0). Replaced entirely by
propose+confirm flow. MCP tool layer should be updated separately to
expose the new RPCs.

### Section F — Notification catalog extension

New type `governance_manual_proposed` (delivery_mode: `transactional_immediate`):
- Used both for: (a) proposal-fanout (asks for 2nd signoff) and (b)
  final-publish-fanout (informs chapter board + sponsors of new version)
- Time-critical due to 24h proposal window
- ADR-0022 catalog bumped W1.2 → W1.3

---

## 2-of-N enforcement details

The 2-of-N rule is enforced in `confirm_manual_version`:
```sql
IF v_signer_id = v_proposal.proposed_by THEN
  RETURN jsonb_build_object('error', 'self_signoff_forbidden', ...);
END IF;
```

Additional implicit safeguards:
- **24h window**: `expires_at = proposed_at + 24h`. After expiry, status
  auto-transitions to 'expired' on next confirm attempt; re-proposal needed.
- **Single pending**: pre-check at propose time prevents concurrent
  pending proposals; clean serial workflow.
- **Re-validation at confirm**: approved CRs and version label availability
  are re-checked at confirm time (state could have changed during 24h window).

---

## Privilege expansion

V3 → V4:
- V3: `is_superadmin = true` (Vitor + Fabricio)
- V4: `manage_platform` audience = `volunteer × {manager, deputy_manager,
  co_gp}` (Vitor + Fabricio + any future deputy_manager/co_gp)

Net change in *who can act on Manual*: zero (Vitor + Fabricio are the
current set). Net change in *requirement*: 2-of-N enforcement means a
single actor can no longer unilaterally publish a manual version. Both
Vitor AND Fabricio (or future additional manage_platform holders) must
participate.

---

## Trade-offs aceitos

1. **Proposer cannot confirm own proposal**: this is the central feature
   of the safeguard. If only one manage_platform holder is active in a
   given window, the manual cannot be published until a second holder is
   available. Acceptable: Manual versions are infrequent; we prioritize
   governance over speed.
2. **24h window**: balances urgency with availability of 2nd signer. Could
   be parameterized later if operational data shows 24h is too short.
3. **Single pending at a time**: prevents concurrent proposals from
   confusing the workflow. Cancel + re-propose is the explicit path for
   correction.
4. **DROP `generate_manual_version`**: irreversible from this migration's
   POV. Frontend has no callsites; MCP tool layer needs separate update.
   ROLLBACK plan: re-create the legacy fn via reverse migration if needed.

---

## Cross-cutting precedent

### Platform-tier 2-of-N approval pattern

ADR-0044 establishes the platform-tier 2-of-N approval pattern:
- `pending_*_approvals` table (proposal + signoff state + 24h expiry)
- `propose_*` + `confirm_*` + `cancel_*_proposal` RPC trio
- `manage_platform` holders required at both ends; proposer ≠ confirmer

This pattern can be reused for other high-impact platform-level mutations:
- ADR ratifications (if/when codified beyond markdown)
- Catalog seed deletions (vs. additions which are reversible)
- Any operation that destroys/locks data with downstream cascading effects

Forward template:
1. Create `pending_<operation>_approvals` table with proposer/signer/expiry
2. Split the operation into `propose_*` (creates pending) + `confirm_*`
   (executes; requires different signer)
3. Add `cancel_*_proposal` for explicit retraction
4. Notification type for proposal-fanout + publish-fanout

### Notification reuse for proposal + publish

`governance_manual_proposed` is reused for both:
- "2nd signoff needed" (fanout to manage_platform)
- "Manual published" (fanout to chapter board + sponsors)

This is intentional — both events relate to the same governance
transition. Recipient sees:
1. Proposal notification with link to approve
2. Publish notification confirming the transition completed

If audit clarity requires distinct types in future, can split into
`governance_manual_proposed` (proposal-only) + `governance_manual_published`
(post-confirm only).

---

## Phase B'' tally update

Pre-ADR-0044: 98/246 (~39.8%)
Post-ADR-0044: 99/246 (~40.2%)

(1 fn V3→V4: `generate_manual_version` was V3-gated. Replaced by 2 new V4
fns + 1 cancel fn — all V4. Net Phase B'' fn-count delta: +1 since the
legacy fn is dropped and 3 new V4 fns added; counted as 1 V3→V4
conversion to reflect the conceptual replacement.)

---

## Status / Next Action

- [x] PM ratifica ADR (§B.2 ratify) — 2026-04-27 p70 decision log
- [x] Migration `20260514060000_adr_0044_manual_version_2_of_n_approval.sql`
- [x] JSON catalog update (ADR-0022 W1.2 → W1.3)
- [x] Audit doc update — Phase B'' tally (98 → 99 / 246, ~40.2%)
- [x] Tests preserved: 1415 / 1383 / 0 / 32
- [ ] Future: MCP tool layer update to expose `propose_manual_version` +
  `confirm_manual_version` + `cancel_manual_version_proposal`
- [ ] Future: admin UI for proposal review/approval (single-page workflow)

---

## Forward backlog

- **Sprint Session 3 done** (B.1 + B.2 + #82 closure all shipped in p72)
- **PM action items** (~15 min manual):
  - Toggle `auth_leaked_password_protection` no Supabase Auth dashboard
  - Schedule #91 G5 Whisper design session
  - Schedule #88 Convocação iniciativas design session
- **MCP tool layer**: expose 3 new fns to `nucleo-mcp` EF for admin/PM use
- **Cron auto-expiry**: optionally add `pg_cron` job to mark expired
  proposals (currently inline-checked at confirm time)
