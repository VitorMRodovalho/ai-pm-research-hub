# ADR-0038: p68 cleanup batch — 1 V3→V4 zero-drift convert + 2 security drift corrections

- Status: **Accepted** (2026-04-27 — PM Vitor ratified Q1=SIM / Q2=SIM / Q3=p68)
- Data: 2026-04-27 (p68)
- Autor: PM (Vitor) + Claude (proposal autônomo)
- Escopo: Phase B'' V3→V4 conversion (1 fn) + 2 SECDEF drift corrections
  identified during p68 strict V3 re-discovery
- Implementation:
  - Migration `20260427210000_adr_0038_p68_cleanup_batch.sql`
  - Migration `20260427210005_adr_0038_revoke_anon.sql`
- Cross-references: ADR-0007 (V4 authority), ADR-0011 (V4 auth pattern),
  ADR-0011 Amendment B (drift signals), ADR-0030/0036 precedent (Opção B
  reuse), Track Q-D charter (`docs/audit/RPC_BODY_DRIFT_AUDIT_P50.md`
  § "SECDEF security hardening sweep")

---

## Contexto

p68 strict V3 re-discovery surfaced **55 candidates** vs p67 audit's **32
catalogados** — 23 missed by p67. Tier-1 classification produced 5 autonomous-
shippable items; 2 of them (`create_cost_entry`, `create_revenue_entry`) carry
+5 sponsor expansion via V4 `manage_finance` catalog and are deferred for
explicit PM ratify (sensitive finance write tier). This ADR ships the 3
zero-drift / security-tightening items.

### As funções afetadas

#### A. `update_governance_document_status(p_doc_id uuid, p_new_status text)` — Phase B'' easy convert

V3 ladder atual:
```sql
SELECT m.id, (m.operational_role IN ('manager', 'deputy_manager') OR m.is_superadmin = true)
INTO v_caller_id, v_is_manager
FROM members m WHERE m.auth_id = auth.uid();
IF NOT COALESCE(v_is_manager, false) THEN
  RETURN jsonb_build_object('error', 'Unauthorized: requires manager permission');
END IF;
```

Caller: 0 src/ + 0 supabase/functions/ — admin-direct call only (or future
admin UI). Transition state machine for governance documents
(draft→under_review→approved→active→superseded).

V4 conversion: pure `manage_platform`. Zero drift (V3 set = V4 set =
{Vitor + Fabricio}).

#### B. `update_event_duration(p_event_id uuid, p_duration_actual integer, p_updated_by uuid)` — Security drift correction

**SECURITY HOLE**: Function uses parameter `p_updated_by` for the gate check
instead of `auth.uid()`-derived member_id. An authenticated attacker passing
any manager UUID would pass the gate while being a non-manager themselves
(privilege escalation vector).

V3 broken pattern atual:
```sql
PERFORM 1 FROM members
WHERE id = p_updated_by  -- ⚠️ comes from request, NOT from auth.uid()
  AND (is_superadmin = true OR operational_role IN ('manager','deputy_manager','tribe_leader'));
IF NOT FOUND THEN RAISE EXCEPTION 'Unauthorized'; END IF;
```

Caller: `src/components/workspace/AttendanceForm.tsx:153` — currently passes
`member.id` (the caller's own member id), so the bug never triggered in
production. But the parameter is exposed via PostgREST and can be set by any
authenticated client.

V4 fix: derive `v_caller_id` from `auth.uid()` + `can_by_member(v_caller_id,
'manage_event')`. Drop dependency on `p_updated_by` parameter (kept for
backward signature compat, ignored). Zero drift (V3 set = V4 set = 8 members:
admin + 6 tribe_leaders).

#### C. `get_dropout_risk_members(p_threshold integer)` — No-gate security drift correction

**SECURITY HOLE**: Function has **NO top-level auth gate**. Returns sensitive
PII (member names + last attendance dates + tribe info) of at-risk members.
Any authenticated caller could exfiltrate this data via direct PostgREST RPC
call.

V3 broken pattern atual:
```sql
BEGIN
  RETURN QUERY
  WITH active_members AS (
    SELECT m.id, m.name, m.tribe_id, t.name as tname, m.operational_role
    FROM members m ...
  )
  ...
END;
```

(no auth check anywhere in body)

Callers:
- `src/components/sections/HomepageHero.astro:317` — gates client-side
  via `hasPermission(member, 'admin.access')` (GP-only banner)
- `src/components/workspace/DropoutRiskBanner.tsx:52` — gates client-side
  via `isGP || isLeader` (admin.access || event.create) + tribe-filter for
  leaders

Frontend gates already restrict to leadership. Server-side gate should mirror:
`can_by_member('manage_event')` (covers GP + tribe_leader cluster, matching
current frontend audience exactly).

V4 fix: add `can_by_member(v_caller_id, 'manage_event')` gate at top. Pre-fix
audience = unbounded authenticated. Post-fix audience = 8 members (Vitor +
Fabricio + 6 tribe_leaders, equal to V3 frontend gate). Pure security
tightening.

### pg_policy precondition (Q-D charter mandatory)

Word-boundary regex `\m` scan on `pg_policy.polqual` + `polwithcheck` for all
3 fns: **zero references** for each. Safe to proceed without RLS hotpath risk.

### Privilege expansion table

| Fn | V3 set | V4 set | Δ gain | Δ loss |
|---|---|---|---|---|
| `update_governance_document_status` | 2 (Vitor + Fabricio) | 2 (same) | 0 | 0 |
| `update_event_duration` | 8 (admin + 6 tribe_leaders) | 8 (same) | 0 | 0 |
| `get_dropout_risk_members` | unbounded (NO GATE!) | 8 | n/a | TIGHTENS to leadership |

**Net policy effect**: zero member-set change for A+B; for C, closes a
LGPD-sensitive PII no-gate exposure. No drift losses to discuss with PM.

---

## Decisão (proposta)

### 1. `update_governance_document_status` — pure manage_platform reuse

```sql
CREATE OR REPLACE FUNCTION public.update_governance_document_status(
  p_doc_id uuid,
  p_new_status text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_caller_id uuid;
  v_doc record;
  v_valid_transitions jsonb := '{
    "draft": ["under_review"],
    "under_review": ["approved", "draft"],
    "approved": ["active", "under_review"],
    "active": ["superseded"],
    "superseded": []
  }'::jsonb;
  v_allowed jsonb;
BEGIN
  SELECT m.id INTO v_caller_id
  FROM public.members m WHERE m.auth_id = auth.uid();

  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('error', 'authentication_required');
  END IF;

  IF NOT public.can_by_member(v_caller_id, 'manage_platform') THEN
    RETURN jsonb_build_object('error', 'Unauthorized: requires manage_platform');
  END IF;

  SELECT * INTO v_doc FROM public.governance_documents WHERE id = p_doc_id;
  IF v_doc IS NULL THEN
    RETURN jsonb_build_object('error', 'Document not found');
  END IF;

  v_allowed := v_valid_transitions->v_doc.status;
  IF v_allowed IS NULL OR NOT (v_allowed ? p_new_status) THEN
    RETURN jsonb_build_object('error', format('Invalid transition: %s -> %s. Allowed: %s', v_doc.status, p_new_status, v_allowed));
  END IF;

  UPDATE public.governance_documents SET
    status = p_new_status,
    updated_at = now()
  WHERE id = p_doc_id;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes)
  VALUES (v_caller_id, 'governance_document_status_change', 'governance_document', p_doc_id,
    jsonb_build_object('from', v_doc.status, 'to', p_new_status, 'doc_title', v_doc.title));

  RETURN jsonb_build_object('ok', true, 'doc_id', p_doc_id, 'old_status', v_doc.status, 'new_status', p_new_status);
END;
$$;
```

### 2. `update_event_duration` — auth.uid()-derived + manage_event

```sql
CREATE OR REPLACE FUNCTION public.update_event_duration(
  p_event_id uuid,
  p_duration_actual integer,
  p_updated_by uuid DEFAULT NULL  -- DEPRECATED: kept for signature compat, ignored
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_caller_id uuid;
BEGIN
  SELECT m.id INTO v_caller_id
  FROM public.members m WHERE m.auth_id = auth.uid();

  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  IF NOT public.can_by_member(v_caller_id, 'manage_event') THEN
    RAISE EXCEPTION 'Unauthorized: requires manage_event';
  END IF;

  UPDATE public.events SET duration_actual = p_duration_actual WHERE id = p_event_id;
  RETURN true;
END;
$$;

COMMENT ON FUNCTION public.update_event_duration(uuid, integer, uuid) IS
'p_updated_by is DEPRECATED and ignored — caller derived from auth.uid() (ADR-0038 p68 security drift fix).';
```

### 3. `get_dropout_risk_members` — add manage_event gate

```sql
CREATE OR REPLACE FUNCTION public.get_dropout_risk_members(p_threshold integer DEFAULT 3)
RETURNS TABLE(
  member_id uuid,
  member_name text,
  tribe_id integer,
  tribe_name text,
  operational_role text,
  last_attendance_date date,
  days_since_last bigint,
  missed_events integer
)
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_caller_id uuid;
BEGIN
  SELECT m.id INTO v_caller_id
  FROM public.members m WHERE m.auth_id = auth.uid();

  IF v_caller_id IS NULL THEN
    RETURN;  -- silent: returns empty set for unauthenticated/non-member
  END IF;

  IF NOT public.can_by_member(v_caller_id, 'manage_event') THEN
    RETURN;  -- silent: returns empty set, mirrors frontend's "no banner if not leader"
  END IF;

  RETURN QUERY
  WITH active_members AS (
    SELECT m.id, m.name, m.tribe_id, t.name as tname, m.operational_role
    FROM public.members m
    LEFT JOIN public.tribes t ON t.id = m.tribe_id
    WHERE m.is_active AND m.operational_role IN ('researcher','tribe_leader','manager')
  ),
  member_expected_events AS (
    SELECT am.id as mid, e.id as eid, e.date,
      ROW_NUMBER() OVER (PARTITION BY am.id ORDER BY e.date DESC) as rn
    FROM active_members am
    CROSS JOIN LATERAL (
      SELECT e2.id, e2.date FROM public.events e2
      LEFT JOIN public.initiatives ini ON ini.id = e2.initiative_id
      WHERE e2.date <= current_date
        AND (
          e2.type IN ('general_meeting','kickoff')
          OR (e2.type = 'tribe_meeting' AND ini.legacy_tribe_id = am.tribe_id)
          OR (e2.type = 'leadership_meeting' AND am.operational_role IN ('manager','tribe_leader'))
        )
      ORDER BY e2.date DESC
      LIMIT p_threshold
    ) e
  ),
  member_misses AS (
    SELECT mee.mid,
      count(*) FILTER (WHERE a.id IS NULL) as missed,
      count(*) as expected
    FROM member_expected_events mee
    LEFT JOIN public.attendance a ON a.event_id = mee.eid AND a.member_id = mee.mid AND a.present
    WHERE mee.rn <= p_threshold
    GROUP BY mee.mid
  ),
  last_att AS (
    SELECT a.member_id as mid, max(e.date) as last_date
    FROM public.attendance a JOIN public.events e ON e.id = a.event_id
    WHERE a.present
    GROUP BY a.member_id
  )
  SELECT am.id, am.name, am.tribe_id, am.tname, am.operational_role,
    la.last_date,
    (current_date - COALESCE(la.last_date, '2025-01-01'))::bigint,
    mm.missed::integer
  FROM active_members am
  JOIN member_misses mm ON mm.mid = am.id
  LEFT JOIN last_att la ON la.mid = am.id
  WHERE mm.missed >= p_threshold
  ORDER BY la.last_date ASC NULLS FIRST;
END;
$$;
```

### 4. Defense-in-depth REVOKE FROM PUBLIC, anon

```sql
REVOKE EXECUTE ON FUNCTION public.update_governance_document_status(uuid, text) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.update_event_duration(uuid, integer, uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.get_dropout_risk_members(integer) FROM PUBLIC, anon;
```

Matches ADR-0030..0037 precedent.

---

## Implications

### Para a plataforma
- 1 fn V3→V4 zero-drift conversion. Phase B'' tally: 82 → 83 / 246 (~33.7%).
- 2 SECDEF security drift corrections (NOT counted in Phase B'' tally — security
  hardening track parallel to V3→V4).
- Zero novo V4 action — full reuse `manage_platform` + `manage_event`.
- pg_policy precondition verified (zero refs for all 3 fns).
- 2 SECDEF advisor surface entries closed (REVOKE FROM anon on 3 fns).

### Para members
- Zero net change for A (`update_governance_document_status`).
- Zero net change for B (`update_event_duration`) — same audience, but
  privilege escalation vector closed.
- C (`get_dropout_risk_members`) — TIGHTENS from "any authenticated can read
  PII at-risk member list" to "manage_event holders only" (mirrors frontend).
  Closes LGPD-sensitive exposure.

### Para path A/B/C optionality
- Path A (PMI internal): positivo — security hardening + drift correction.
- Path B (consultoria): positivo — multi-tenant security baseline strengthened.
- Path C (community-only): neutro.

### Deferred (out of this batch — for explicit PM ratify)
- `create_cost_entry` / `create_revenue_entry` → V4 `manage_finance` would
  expand audience by **+5 sponsors** (Felipe, Francisca, Ivan, Márcio, Matheus
  — all `sponsor × sponsor` engagements per V4 catalog). V4 catalog explicitly
  grants sponsor manage_finance, but the V3 RPC was narrower (manager/deputy/SA
  only). Sponsor-tier finance write is a meaningful policy change requiring
  PM rubber-stamp. Track for next session.

---

## Open Questions (para PM input)

### Q1 — Aceito 1 V3→V4 zero-drift convert (`update_governance_document_status`)?

Recomendação: **SIM** — zero member set change, pure rename to V4 vocabulary.

### Q2 — Aceito 2 security drift corrections?

`update_event_duration`: closes parameter-based gate vector by switching to
`auth.uid()`-derived caller. `p_updated_by` deprecated (kept for signature
compat).

`get_dropout_risk_members`: closes no-gate PII exposure by adding
`manage_event` gate matching frontend audience.

Both are pure security tightening — zero member adds, frontend behavior
preserved (existing callsites pass valid auth.uid() / are gated client-side
to leadership).

Recomendação: **SIM** — security hygiene, no operational change.

### Q3 — Implementation timing

ADR está em `Proposed`. Implementação requer:
- 1 migration conversão+drift fix (3 fns single batch)
- 1 migration REVOKE FROM anon (3 fns)
- 1 audit doc update

Estimativa: ~20 min.

Recomendação: **p68 mesmo**.

---

## Status / Next Action

- [ ] PM ratifica ADR (Q1 / Q2 / Q3)
- [x] Migration conversão + drift fix — `20260427210000`
- [x] Migration REVOKE FROM anon — `20260427210005`
- [x] Audit doc update — Phase B'' tally bumps (82 → 83 / 246, ~33.7%)
- [x] Status ADR → `Proposed` (PM rubber-stamp pending)

**Bloqueador**: nenhum (PM rubber-stamp expected).

### Outcome (post-apply esperado)

- 1 fn V3 zero-drift converted (`update_governance_document_status`).
- 2 SECDEF security drift corrected (`update_event_duration`,
  `get_dropout_risk_members`).
- Phase B'' tally: 82 → 83 / 246 (~33.7%).
- 2 NEW autonomous patterns sedimented:
  1. **p68 strict V3 re-discovery delta**: re-running discovery surfaces
     candidates missed by previous audits (23 in p68). Worth running each
     session.
  2. **Auth.uid() drift detection**: parameter-based gate (`p_<actor>_id`)
     without `auth.uid()` cross-check is a privilege escalation vector
     pattern — added to Phase Q-D candidate sweep (search for
     `WHERE id = p_<actor>_id` patterns in pg_proc).
- Defense-in-depth REVOKE FROM anon on 3 fns. Advisor surface 781 → 778 (3
  closures).
