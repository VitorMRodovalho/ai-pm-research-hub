# ADR-0043: `create_cost_entry` + `create_revenue_entry` V3→V4 + sponsor finance notification safeguard

- Status: **Accepted** (2026-04-27 — PM Vitor pre-ratified per p70 decision log §B.1)
- Data: 2026-04-27 (p72)
- Autor: PM (Vitor) + Claude (proposal autônomo)
- Escopo:
  - Section A — Phase B'' V3→V4 conversion (2 fns) — finance entry creators
    via `manage_finance` catalog action (mirrors ADR-0038 pattern)
  - Section B — New notification type `sponsor_finance_entry_logged` +
    `_delivery_mode_for` catalog extension (transactional_immediate)
  - Section C — Trigger fn `notify_sponsor_finance_entry()` AFTER INSERT on
    `cost_entries` + `revenue_entries` for governance safeguard
  - Section D — Enhanced `admin_audit_log` entry with engagement context
- Implementation:
  - Migration `20260514050000_adr_0043_finance_v4_and_sponsor_notification.sql`
- Cross-references: ADR-0007 (V4 authority), ADR-0011 (cutover),
  ADR-0022 (notification types catalog + delivery_mode), ADR-0025
  (manage_finance V4 action seed), ADR-0038 (pattern for V3→V4 finance fns)

---

## Contexto

PM decision log §B.1 ratified converting `create_cost_entry` and
`create_revenue_entry` from V3 (`operational_role IN ('manager',
'deputy_manager') OR is_superadmin = true`) to V4 (`can_by_member(
'manage_finance')`). The V4 catalog `manage_finance` audience is broader
than V3:
- V3: ~3 active members (Vitor, Fabricio + any superadmin)
- V4: `volunteer × {manager, deputy_manager, co_gp}` + `sponsor × sponsor`

**PM concern**: `sponsor × sponsor` in `manage_finance` lets non-volunteer
sponsors log cost/revenue entries directly. This is intentional (chapter
sponsors fund the chapter), but lacks governance visibility — manage_platform
holders should know when a sponsor logs a financial transaction outside
the volunteer chain.

**PM requirement (§B.1 safeguard)**:
1. Notification trigger to `manage_platform` holders when a non-volunteer
   sponsor creates a finance entry
2. Audit log entry with engagement context + chapter_board affiliation

---

## Decisão

### Section A — V3→V4 conversion

`create_cost_entry` + `create_revenue_entry` replace V3 gate with
`can_by_member('manage_finance')`. Same pattern as ADR-0038
(`update_event_duration` fix). REVOKE FROM anon for defense-in-depth.

V4 catalog audience for `manage_finance`:
```
volunteer × manager
volunteer × deputy_manager
volunteer × co_gp
sponsor × sponsor   ← THE concern triggering this safeguard
```

### Section B — Notification catalog extension

New type `sponsor_finance_entry_logged`:
- delivery_mode: `transactional_immediate` (governance visibility critical
  — manage_platform holders should not wait for weekly digest to know
  about non-volunteer sponsor finance entries)
- Source: trigger fn fires from cost_entries / revenue_entries AFTER INSERT
- Recipients: all active `manage_platform` holders (excluding the actor)

Catalog updates:
- `docs/adr/ADR-0022-notification-types-catalog.json` (W1.1 → W1.2 bump,
  +1 type entry)
- `_delivery_mode_for(text)` SQL helper (+1 WHEN branch)

Contract test `tests/contracts/adr-0022-delivery-mode.test.mjs` enforces
SQL ↔ JSON parity automatically.

### Section C — Trigger fn `notify_sponsor_finance_entry()`

```sql
-- Fires AFTER INSERT on cost_entries + revenue_entries
-- Path Y check: actor has sponsor × sponsor authoritative engagement
-- AND no volunteer × * authoritative engagement (i.e., non-volunteer)
-- If yes: write enhanced admin_audit_log + send notification to manage_platform holders
```

Detection logic:
- `v_is_sponsor` — actor has `sponsor × sponsor` authoritative engagement
- `v_is_volunteer` — actor has any `volunteer × *` authoritative engagement
- Trigger fires only when `v_is_sponsor AND NOT v_is_volunteer`

This excludes Vitor (manager) and Fabricio (co_gp), who are already in the
volunteer chain. It targets sponsor-only members (Ivan, Felipe, Francisca,
Márcio, Matheus per current population) when they log finance entries.

### Section D — Enhanced audit log

`admin_audit_log` entry payload:
```jsonb
{
  "entry_kind": "cost" | "revenue",
  "entry_id": uuid,
  "amount_brl": numeric,
  "description": text,
  "created_by_member_id": uuid,
  "created_by_name": text,
  "created_by_chapter": text,
  "engagement_context": {
    "is_sponsor": true,
    "is_volunteer": false,
    "chapter_board_roles": ["board_member" | "liaison"]
  },
  "governance_concern": "non_volunteer_sponsor_logged_finance_entry"
}
```

Provides full context for governance audit: who, what amount, what kind,
their chapter, their engagement profile, the specific governance flag.

---

## Privilege expansion (verified pre-apply)

### `manage_finance` audience (existing per ADR-0025)

| Member | Engagement | V3 access | V4 access |
|---|---|---|---|
| Vitor Maia Rodovalho | volunteer/manager | ✓ | ✓ |
| Fabricio Costa | volunteer/co_gp | ✓ (super) | ✓ |
| Ivan Lourenço | sponsor/sponsor | ✗ | **✓ (new)** |
| Felipe Moraes Borges | (chapter_board.board_member only) | ✗ | ✗ |
| Francisca Jessica de Sousa | (chapter_board.board_member only) | ✗ | ✗ |
| Márcio Silva dos Santos | (chapter_board.board_member only) | ✗ | ✗ |
| Matheus Frederico Rosa Rocha | (chapter_board.board_member only) | ✗ | ✗ |

**Net change**: Ivan gains finance entry creation (V4 catalog allowed,
intentional per ADR-0025). The other "sponsor-flagged" members
(Felipe/Francisca/Márcio/Matheus) have **only** chapter_board × board_member
engagement, NOT sponsor × sponsor — they do NOT gain manage_finance.

### Trigger fire scope

Trigger fires for finance entries created by Ivan (or any future
sponsor × sponsor member without parallel volunteer engagement). Volunteer
chain entries (Vitor, Fabricio) do NOT trigger — those are normal flow.

---

## Trade-offs aceitos

1. **Sponsor × sponsor gains write access**: V4 catalog explicitly grants
   `manage_finance` to sponsors. PM ratify §B.1 accepted this pattern with
   the notification safeguard. Without the safeguard, V3→V4 conversion
   would be silent privilege expansion.
2. **`transactional_immediate` delivery**: governance concerns about
   non-volunteer finance entries warrant immediate visibility. Cannot wait
   for weekly digest.
3. **Excluded recipient: actor**: trigger excludes the actor from
   notification list (you don't notify yourself about your own action).
4. **Trigger fires on AFTER INSERT only**: UPDATE/DELETE paths not covered.
   Updates to existing entries by sponsors would not trigger. Defer to
   future iteration if/when delete/update flow adopted.

---

## Cross-cutting precedent

### Engagement-aware trigger pattern

ADR-0043 establishes a new pattern: triggers that inspect the actor's V4
engagement profile (via `auth_engagements`) to decide whether to fire side
effects. Future safeguards can follow:
- "Notify manage_platform when chapter_board × board_member writes to X"
- "Audit log when external_signer engagement performs Y"
- etc.

Pattern signature:
1. Lookup actor's `legacy_member_id → person_id`
2. Check `auth_engagements` for relevant kinds × roles + `is_authoritative`
3. Branch logic on engagement profile
4. Fire notifications + audit log accordingly

### Notification type for governance safeguards

`sponsor_finance_entry_logged` is the first notification type explicitly
named for *governance safeguard purposes* (vs. operational events). Future
similar types can follow naming pattern:
- `<actor_engagement>_<event>_logged`
- `transactional_immediate` delivery_mode default for governance visibility
- Body should include engagement context for the recipient

---

## Phase B'' tally update

Pre-ADR-0043: 96/246 (~39.0%)
Post-ADR-0043: 98/246 (~39.8%)

(2 fns converted in this ADR. Trigger fn does not count toward Phase B''
since it's net-new code, not a V3→V4 conversion.)

---

## Status / Next Action

- [x] PM ratifica ADR (§B.1 ratify) — 2026-04-27 p70 decision log
- [x] Migration `20260514050000_adr_0043_finance_v4_and_sponsor_notification.sql`
- [x] JSON catalog update (ADR-0022 W1.2)
- [x] Audit doc update — Phase B'' tally bumps (96 → 98 / 246, ~39.8%)
- [x] Tests preserved: 1415 / 1383 / 0 / 32 + ADR-0022 contract test
  (catalog parity)
- [ ] Future: smoke test trigger fire with Ivan as actor (manual; could be
  scheduled when sponsor finance flow is exercised in production)

---

## Forward backlog

- **B.2** `generate_manual_version` 2-of-N approval (PM ratify §B.2 — next
  session candidate)
- **PM action item**: toggle `auth_leaked_password_protection` no Supabase
  Auth dashboard
- Future: extend trigger to `cost_entries` UPDATE/DELETE paths if/when those
  operations become user-facing
