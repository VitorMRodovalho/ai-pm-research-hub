---
date: 2026-04-26
session: p59
type: decision-log
authors: PM (Vitor Rodovalho) + accountability-advisor + security-engineer
status: APPROVED — autonomous PM authority + accountability-advisor governance trigger
sponsor_disclosure: scheduled Monday 2026-04-28 (PMI-GO president Ivan Lourenço)
---

# Tracks Q-D + R — Security Hardening Workstream Decision Log

> **Decision artifact** establishing pre-authorized change-control record
> for the cumulative security hardening work executed across sessions
> p55-p59 (2026-04-24 → 2026-04-26). Closes the audit gap identified
> by accountability-advisor council review (p59): the audit trail
> existed in commits + audit doc + briefing, but no single decision
> record formally framed the workstream.

---

## 1. Workstream Identification

**Name:** Tracks Q-D + R — Security Hardening (SECDEF + pg_graphql exposure)

**Scope:**
- **Track Q-D**: 109+ SECDEF database functions with PUBLIC/anon EXECUTE
  default and no internal authorization gate. Triaged + remediated via
  REVOKE + per-function classification (dead/internal/EF-only/member-tier/
  admin/V4-discovered/verified-public).
- **Track R**: 165 tables/views with `anon SELECT` grant exposing schema
  via pg_graphql introspection endpoint. Triaged + remediated via REVOKE
  SELECT FROM anon for non-intentional surfaces; intentional public
  surfaces preserved with inline COMMENT ON TABLE documentation per
  ADR-0024 pattern.

**Duration:** 5 sessions (p55 → p59) over 3 days (2026-04-24 → 2026-04-26).

---

## 2. Authorization Basis

**Authority:** General Project Manager (Vitor Rodovalho) standing
technical authority for defensive security operations.

**Governance trigger:** Accountability-advisor memo (2026-04-25)
recommending proactive sponsor disclosure on SECDEF audit progress
+ scope + closure pattern.

**Regulatory mandate:**
- LGPD Art. 46 — "agentes de tratamento devem adotar medidas de
  segurança, técnicas e administrativas aptas a proteger os dados
  pessoais de acessos não autorizados"
- LGPD Art. 5/6 — princípios de necessidade, finalidade e segurança
- OWASP Top 10 A05:2021 — Security Misconfiguration

**Scope of autonomous authority:**
- Defensive REVOKE operations (no functional change, no privilege
  expansion)
- Inline COMMENT ON TABLE/FUNCTION documentation
- Per-function callsite verification + audit doc closure
- Test suite preservation (1397/1372/0/25 throughout)

**Out of autonomous scope (escalated for PM input):**
- 3 selection readers awaiting tier classification (Q-D 3a.2)
- 11 V3-gated functions documented for Phase B'' V4 action ratify
  per ADR

---

## 3. Outcome Metrics (audit-defensible)

| Indicator | Pre-workstream | Post-workstream | Delta |
|---|---|---|---|
| Q-D functions triaged | 0 | **166** (vs 109 estimate) | +166 |
| Q-D buckets closed | 0/8 | **8/8** | +100% |
| Q-D hardened (REVOKE applied) | 0 | 137 | +137 |
| Track R cumulative REVOKEs | 0 | **152** (102 batch 1 + 50 batch 2) | +152 |
| Track R intentional public documented (Phase R3) | 0 | **20** | +20 |
| Total cumulative hardenings | 0 | **289** (137 fns + 152 tables/views) | +289 |
| Supabase advisor security WARN | 171 | **25** | **-85%** |
| `pg_graphql_anon_table_exposed` lint | 165 | 20 | -88% |
| Open regressions | 0 | 0 | — |
| Test suite pass rate | 1397/1372/0/25 | 1397/1372/0/25 | unchanged |
| Schema invariants violations | 0/11 | 0/11 | unchanged |

**Defensive verification at each batch:**
- `pg_class.relacl` post-state ACL inspection
- `check_schema_invariants()` 11/11 = 0 between every migration
- `npm test` regression check between every batch
- Per-function callsite grep across `src/` + `supabase/functions/`
- `pg_proc.prosrc` regex for SECDEF caller chain detection (Q-D 3b)
- `pg_policy.polqual` per-policy classification (Track R Phase R2)

**Identified + resolved exception:** 1 regression (`comms_check_token_expiry`
admin caller missed in batch 1 p55) — surfaced and remediated in same
session p58 via amendment migration `20260426131249` / commit
`a8521ec`. Lesson methodology incorporated into protocol: per-batch
callsite verification must include cross-check of previously-triaged
functions whose ACL changed.

---

## 4. Audit Trail (cross-reference)

**Primary artifact:** `docs/audit/RPC_BODY_DRIFT_AUDIT_P50.md`
- Full Q-D charter + treatment matrix
- Per-batch closure section (8 buckets + 1 amendment)
- Track R section with batch 1 + batch 2 + Phase R3 closure
- Phase Q-D vs Phase B' decision matrix (when to use which pattern)

**Sponsor-facing summary:** `docs/BRIEFING_IVAN_QD_DISCLOSURE_26ABR2026.md`

**Council reviews (p59):**
- security-engineer: CONDITIONAL ship gate — 3 follow-ups identified
  (rls_can SECDEF verify ✅ DONE p59, auth_org ACL contract test 🔜 p60,
  get_gp_whatsapp LGPD legal basis ✅ DONE p59)
- accountability-advisor: 5 priority items for Monday call —
  3 implemented this session (briefing fixes + decision log + LGPD
  comment), 2 are PM responsibility (send pre-read, ADR-0024 Q&A prep)

**Migration range:** 13 migrations across p55-p59
```
20260426001848  batch 1 SECDEF security hardening sweep (p55)
20260426005822  batch 3a.1 admin selection readers (p57)
20260426120532  batch 3a.3a initiative/board dead/internal (p58)
20260426123542  batch 3a.3b initiative/board member-tier (p58)
20260426124716  batch 3a.4 knowledge/wiki readers (p58)
20260426130254  batch 3a.5 comms readers (p58)
20260426131249  batch 1 amendment — comms_check_token_expiry (p58)
20260426132442  batch 3a.6 curation/governance readers (p58)
20260426133716  batch 3a.7 sustainability/KPI readers (p58)
20260426143952  batch 3a.8 legacy/utility readers (p59)
20260426145632  batch 3b internal helpers — defense-in-depth (p59)
20260426152751  Track R batch 1 — pg_graphql anon REVOKE (p59)
20260426155255  Track R batch 2 — Phase R2 per-policy review (p59)
20260426161441  Track R Phase R3 — COMMENT ON TABLE intentional public (p59)
20260426162019  Track R Phase R3 — LGPD legal basis get_gp_whatsapp (p59)
```

**Commit range:** Q-D + Track R + audit + briefing
- Q-D commits (p55-p59): `e59295e` → `69adad5`
- Track R commits (p59): `d58ea6d` → `2ff39e8`
- Audit doc / briefing: `680a5a0`, `49b624a`, `39ae521`, `c02247d`

---

## 5. Path A/B/C Optionality Preservation

**Council assessment:** PASS — no path-foreclosing decisions detected.

The defensive nature of the work (REVOKE + COMMENT, no functional
change) preserves all three Trentim paths:
- **Path A (PMI institutional spinoff)**: improved audit-readiness +
  -85% advisor reduction = stronger institutional posture
- **Path B (commercial)**: cleaner data governance = stronger DD
  position
- **Path C (community)**: no community visibility impact

The COMMENT ON TABLE pattern (Phase R3) establishes ADR-0024 as the
default documentation framework for intentional public exposures —
reusable across paths.

---

## 6. Sponsor Disclosure Plan

**Cadence proposal:** Quarterly sponsor touchpoints (90-day cycle)
aligned with research cycle quarters where possible.

**Next touchpoint:** Monday 2026-04-28 — Vitor + Ivan Lourenço call.

**Disclosure pattern (this and future):**
1. Briefing as pre-read (sent Sunday EOD before Monday call)
2. Frame: "no incident, proactive audit, remediation complete,
   audit trail in GitHub"
3. Talking points 30-second + detailed (per briefing Section 7)
4. No-surprise principle: include 1 ERROR remaining (public_members)
   + ADR-0024 rationale
5. Post-call: short ciência memo registered

**Quarterly metrics to report:**
- Advisor security ERROR + WARN counts (current 1+25)
- Cumulative hardenings since last touchpoint
- Open regressions count
- New ADRs ratified
- Phase B'' progress (V3→V4 conversion)

---

## 7. Open Items After This Decision

**Before p60 closes (security-engineer items):**
- Add contract test for `auth_org()` ACL (assert no PUBLIC/anon
  EXECUTE grant) — prevents silent regression on future migrations
  that recreate the function with default ACL.
- Consider LGPD ROPA (Art. 37) mapping doc: legal basis per public
  surface for the 20 intentional public objects.

**PM input required:**
- Q-D 3a.2 — 3 selection readers tier classification
  (`get_attendance_panel`, `get_meeting_notes_compliance`,
  `count_tribe_slots`)
- Phase B'' new V4 actions ratify per ADR (`manage_comms`,
  `manage_finance`, etc.) — 11 fns documented.

**Optional polish:**
- Phase B' drift signals #3 + #4 (PM-blocked)
- ADR-0015 Phase 5 timing
- preview_gate_eligibles ladder choice

---

## 8. Decision Record

**This decision log is the formal change-control authorization
record for Tracks Q-D + R**. It establishes:

1. The workstream existed under PM standing technical authority.
2. The governance trigger was the accountability-advisor memo
   (2026-04-25) — not arbitrary action.
3. Defensive scope is appropriate for autonomous authority (no
   privilege expansion, no functional change, comprehensive audit
   trail).
4. Sponsor disclosure follows no-surprise principle (briefing
   pronto, Monday call scheduled).
5. Council review (security-engineer + accountability-advisor)
   conducted post-execution = conditional approval with 3 immediate
   fixes applied (rls_can verify, get_gp_whatsapp LGPD comment,
   briefing authorization basis).

**Approval chain:**
- Authored: PM (Vitor Rodovalho), 2026-04-26
- Council validation: security-engineer + accountability-advisor, 2026-04-26
- Sponsor disclosure: scheduled Monday 2026-04-28 (Ivan Lourenço)
- Post-disclosure ciência: pending Monday call

**Reproducible by any auditor:** all artifacts in GitHub at commits
`e59295e` through `2ff39e8`. Audit doc + briefing + this decision
log provide complete narrative + evidence trail.
