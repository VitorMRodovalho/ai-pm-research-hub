---
issue: 160
title: permissions - resolve Herlon study_group_owner authority state
lane: Foundation + Governance
priority: P1
effort: M (decision + migration or UX)
status: ready
opened: 2026-05-19
github: https://github.com/VitorMRodovalho/ai-pm-research-hub/issues/160
---

# p201 Session Brief - Issue #160: Herlon Authority State

## Why this matters

Herlon shows as `operational_role='observer'` with empty V4 capabilities,
even though he has an active `study_group_owner / leader` engagement for
CPMAI. The V4 model has the seed in `engagement_kind_permissions`, but
the engagement row is not authoritative because `requires_agreement=true`
and `agreement_certificate_id=NULL`. The system is technically correct;
the UX is misleading and the institutional decision is unresolved.

## Runtime evidence (collected during p201 audit)

- `members` row: `operational_role='observer'`, designations include `ambassador`.
- `engagements`: one active row `kind='study_group_owner'`, `role='leader'`,
  initiative = `Preparatorio CPMAI - Ciclo 3 (2026)`.
- `engagement_kind_permissions` for `(study_group_owner, leader)` grants:
  `manage_event`, `manage_member`, `write`, `write_board`,
  `participate_in_governance_review`, etc.
- `auth_engagements` shows the row as `requires_agreement=true`,
  `agreement_certificate_id=NULL`, `is_authoritative=false`.
- `get_caller_capabilities()` returns empty `org_actions`, `tribe_actions`,
  `initiative_actions`.
- Related carve-out already in production: migration `20260710000000`
  (p195) allows `participate_in_governance_review` bypass for
  non-authoritative engagements, but only for that single action.

## Lane and gates

- Lane: Foundation (SQL/migrations) + Governance (decision)
- Can touch: `supabase/migrations/`, `docs/adr/`, UI message only if
  picking path (C); no broad UI refactor here
- Can't touch: scope expansion to other engagement kinds; member_status_transitions;
  other people's `is_authoritative` flag without separate review
- Gates: `check_schema_invariants()` 16/16; smoke that Herlon's
  capability shape matches the chosen path; no privilege escalation for
  any other member; ADR if the decision changes an invariant

## Decision options (PM must pick before SQL)

| Path | What changes | Effort | Risk |
|---|---|---|---|
| A | Issue + counter-sign agreement/certificate for Herlon's study_group_owner engagement | XS (use admin certificate flow) | Low - one person scope |
| B | Amend `requires_agreement` for `study_group_owner` engagement kind | M | High - changes all current+future study group owners |
| C | Keep as pending; add UI "leadership pending agreement" badge | S | Low - cosmetic only |

Recommended path is A unless PM has policy objection. Path B should be
gated by an ADR because it changes a global invariant.

## In scope

1. Decision recorded in `docs/audit/P162_GAP_OPPORTUNITY_LOG.md` item #44
   (status = Resolved + path picked).
2. If path A: use existing certificate counter-sign flow (`/admin/certificates`)
   or admin RPC; verify `auth_engagements.is_authoritative` flips to true
   for Herlon's row only.
3. If path B: new migration with seed update + ADR justifying the policy
   change + smoke that no other person silently gains authority.
4. If path C: add UI badge in profile and admin views (engagement card
   should show "Agreement pending - capabilities limited").

## Out of scope

- Touching `participate_in_governance_review` carve-out from p195.
- Refactoring `auth_engagements` aggregation logic.
- Resolving any other pending-authority case.

## Files likely to touch

- Path A: none in code; admin action only + log entry.
- Path B: `supabase/migrations/<ts>_p201_amend_study_group_owner_agreement.sql`,
  `docs/adr/ADR-008X_study_group_owner_authority.md`.
- Path C: `src/components/profile/*Engagement*.tsx`, `src/i18n/*.ts`
  (3 dicts), engagement card surface in `/admin/members/[id]`.

## Validation

- After path A: `SELECT is_authoritative FROM auth_engagements WHERE
  member_id='<herlon>' AND kind='study_group_owner'` returns true.
- After any path: `SELECT * FROM check_schema_invariants() WHERE
  violation_count > 0` returns empty.
- `get_caller_capabilities()` for Herlon returns the expected actions
  (or, for path C, still empty - and the UI now explains why).
- Smoke: 3 other test members do not unintentionally gain new actions.

## Rollback

- Path A: revoke certificate via admin; `auth_engagements` returns to
  prior state automatically.
- Path B: revert migration; downgrade ADR to Superseded.
- Path C: revert UI commit; no DB impact.

## Cross-references

- `docs/audit/P162_GAP_OPPORTUNITY_LOG.md` items #4 (Track E root), #44
- `docs/audit/P201_MCP_ARCHITECTURE_AUDIT.md` §5
- ADR-0007 (can() authority), ADR-0080 (pending cutover)
- Migration `20260710000000` (governance review carve-out, p195)

## Handoff (fill on completion)

```md
## Handoff
Issue: #160
Branch:
Path picked:
Arquivos:
Validacao:
Riscos:
Rollback:
Docs:
Proximo passo:
```
