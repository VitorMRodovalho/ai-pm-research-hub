# `sync_operational_role_cache` trigger — investigation findings (2026-04-29)

## Context
Governance audit (p81) tried to set `operational_role='alumni'` for 4 offboarded members (Daniel Bittencourt, Leandro Mota, Pedro Henrique R Mendes, Wellinghton Pereira Barboza). Direct UPDATE on `members.operational_role` did NOT stick — final state showed Daniel/Leandro=`guest`, Pedro/Wellinghton=`observer`. Investigation was needed.

## Root cause
`members.operational_role` is a **CACHE** maintained by trigger `sync_operational_role_cache` (per CLAUDE.md). The trigger derives the role from `auth_engagements.kind` rows where `is_authoritative=true`, **NOT** from a direct UPDATE on the `members` row.

Trigger logic (extracted via `pg_get_functiondef`):

```sql
SELECT CASE
  WHEN bool_or(ae.kind='volunteer' AND ae.role='manager')        THEN 'manager'
  WHEN bool_or(ae.kind='volunteer' AND ae.role='deputy_manager') THEN 'deputy_manager'
  WHEN bool_or(ae.kind='volunteer' AND ae.role='leader')         THEN 'tribe_leader'
  WHEN bool_or(ae.kind='volunteer' AND ae.role='co_gp')          THEN 'manager'
  WHEN bool_or(ae.kind='volunteer' AND ae.role='comms_leader')   THEN 'tribe_leader'
  WHEN bool_or(ae.kind='volunteer' AND ae.role IN
    ('researcher','facilitator','communicator','curator')) THEN 'researcher'
  WHEN bool_or(ae.kind='external_signer') THEN 'external_signer'
  WHEN bool_or(ae.kind='observer')        THEN 'observer'
  WHEN bool_or(ae.kind='alumni')          THEN 'alumni'
  WHEN bool_or(ae.kind='sponsor')         THEN 'sponsor'
  WHEN bool_or(ae.kind='chapter_board')   THEN 'chapter_liaison'
  WHEN bool_or(ae.kind='candidate')       THEN 'candidate'
  ELSE 'guest'
END INTO v_new_role
FROM public.auth_engagements ae
WHERE ae.person_id = COALESCE(NEW.person_id, OLD.person_id)
  AND ae.is_authoritative = true;
```

## Why all 6 members are inconsistent
SQL audit showed all 6 (Daniel, Leandro, Marcel, Lídia, Pedro, Wellinghton) have **NO `auth_engagements` rows** (LEFT JOIN returned NULL for all kind/role/is_authoritative).

For empty set:
- `bool_or(...)` returns NULL on every branch
- All `WHEN bool_or(...) THEN ...` clauses evaluate to false
- Falls through to `ELSE 'guest'`

But:
- Daniel/Leandro currently `guest` ← matches `ELSE` rule (probably trigger fired recently with empty set)
- Pedro/Wellinghton currently `observer` ← STALE cache from past auth_engagements row that was deleted; trigger never re-fired
- Marcel/Lídia currently `alumni` ← STALE cache from past `kind='alumni'` row

The trigger fires only when `auth_engagements` is INSERT/UPDATE/DELETE'd. Direct UPDATE on `members.operational_role` doesn't fire it. Direct UPDATE that I attempted appears to have been silently overwritten OR the trigger is also attached to `members` updates and re-runs the cache logic before commit.

(Note: query result for my `UPDATE members SET operational_role='alumni'` showed unchanged values — strongly suggests there's also a `BEFORE UPDATE ON members` trigger that re-runs the cache logic. Confirming this requires reading `pg_trigger` for members table.)

## Proper fix path (V4-correct)

Don't UPDATE `members.operational_role` directly. Instead, INSERT proper `auth_engagements` row of `kind='alumni'` `is_authoritative=true`. Trigger fires, cache reflects truth.

```sql
-- Pseudo (need actual auth_engagements schema columns):
INSERT INTO auth_engagements (person_id, kind, is_authoritative, start_date, end_date, source_id, ...)
VALUES (
  (SELECT person_id FROM members WHERE id='13d19079-...'),
  'alumni',
  true,
  '2026-03-26'::date,  -- offboarded_at
  NULL,
  ...
);
```

The `kind` enum allowed (per trigger): `volunteer`, `external_signer`, `observer`, `alumni`, `sponsor`, `chapter_board`, `candidate`.

## Open questions for data architect

1. **Schema audit**: what are the required NOT NULL columns of `auth_engagements`? (need full DDL inspection)
2. **`is_authoritative=true` semantic**: does inserting a NEW row of kind='alumni' COEXIST with the old volunteer row, or should the volunteer row be flipped to is_authoritative=false?
3. **Multiple `is_authoritative=true` rows**: if a member has BOTH a `volunteer` (old) AND `alumni` (new) row authoritative, the bool_or matches volunteer first → role='researcher' or similar — NOT alumni. Probably need to set `is_authoritative=false` on the old volunteer row simultaneously.
4. **Pedro and Wellinghton stale cache**: current `observer`/`guest` is stale from past auth_engagements rows. Will any future engagement trigger a cache refresh (now that they have NO auth_engagements rows, the trigger sets to ELSE='guest' on next fire). Marcel/Lídia stay `alumni` only because trigger hasn't fired since their alumni-kind rows were deleted.

## Recommendation

**Defer fix to a dedicated session with data-architect agent**. Create explicit `auth_engagements` rows (with proper schema). Mark old engagements `is_authoritative=false`. Verify cache reflection. Add invariant test if not present.

**Non-blocking for current operations**: `operational_role` is a cache. Source of truth (auth_engagements) may already be NULL/empty for these 6 — meaning the V4 model considers them not-engaged, which is correct for offboarded members. The cache showing `observer`/`guest` instead of `alumni` is purely a display inconsistency.

## Status
- Documented for handoff p82.
- 6 affected members identified.
- Recommended path: V4-proper auth_engagements INSERT (not direct UPDATE).
