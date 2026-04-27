# ADR-0039: Volunteer-agreement countersign subsystem 100% V4 — Path Y precedent extension + register_attendance_batch security drift fix

- Status: **Accepted** (2026-04-27 — PM Vitor ratified Q1=SIM / Q2=SIM / Q3=p69)
- Data: 2026-04-27 (p69)
- Autor: PM (Vitor) + Claude (proposal autônomo)
- Escopo:
  - Section A — Phase B'' V3→V4 conversion (3 fns) — countersign subsystem
    100% V4 via `manage_member` + Path Y (chapter_board engagement)
  - Section B — Security drift correction (1 fn) — `register_attendance_batch`
    parameter-based gate → `auth.uid()` + `manage_event` (same pattern as
    ADR-0038 `update_event_duration` fix)
- Implementation:
  - Migration `20260427220000_adr_0039_countersign_and_attendance_batch.sql`
  - Migration `20260427220005_adr_0039_revoke_anon.sql`
- Cross-references: ADR-0007, ADR-0011, ADR-0030 (chapter_board × liaison
  inclusion), ADR-0037 (Path Y chapter_board engagement preservation pattern),
  ADR-0038 (parameter-gate drift detection sediment from p68)

---

## Contexto

p68 strict V3 re-discovery surfaced 3-fn cluster (volunteer-agreement
countersign subsystem) with identical V3 gate pattern: `(manager OR
chapter_board designation)`. ADR-0037 already established the Path Y
pattern for chapter_board sub-role preservation; this ADR applies the
precedent to close the countersign subsystem 100% V4.

Section B closes a parallel security drift identified by the p68
"parameter-based gate" detection pattern (see audit doc § "Strict V3
re-discovery DELTA"). `register_attendance_batch` exhibits the exact
same vulnerability as ADR-0038's `update_event_duration` fix.

### Section A — Countersign subsystem (3 fns)

#### `counter_sign_certificate(p_certificate_id uuid)` — countersign volunteer agreement certificate

V3 ladder atual:
```sql
SELECT m.id, m.chapter,
  (m.operational_role IN ('manager') OR m.is_superadmin = true),
  ('chapter_board' = ANY(m.designations))
INTO v_member_id, v_member_chapter, v_is_manager, v_is_chapter_board
FROM members m WHERE m.auth_id = auth.uid();
IF NOT COALESCE(v_is_manager, false) AND NOT COALESCE(v_is_chapter_board, false) THEN
  RETURN jsonb_build_object('error', 'not_authorized');
END IF;
```

Plus chapter-scope cross-check downstream:
```sql
IF v_is_chapter_board AND NOT v_is_manager THEN
  IF v_contracting_chapter IS DISTINCT FROM v_member_chapter THEN
    RETURN jsonb_build_object('error', 'not_authorized_different_chapter');
  END IF;
END IF;
```

Caller: `src/pages/admin/certificates.astro:57`.

#### `get_pending_countersign()` — list certificates pending countersign

Same V3 ladder + chapter filter:
```sql
WHERE c.counter_signed_by IS NULL
  AND COALESCE(c.status, 'issued') = 'issued'
  AND c.type != 'volunteer_agreement'
  AND (COALESCE(v_is_manager, false) OR m.chapter = v_member_chapter);
```

Caller: `src/pages/admin/certificates.astro:86`.

#### `get_volunteer_agreement_status()` — chapter dashboard for volunteer agreement signing

Same V3 ladder:
```sql
IF NOT COALESCE(v_is_manager, false) AND NOT COALESCE(v_is_chapter_board, false) THEN
  RETURN jsonb_build_object('error', 'Unauthorized');
END IF;
```

Plus chapter-scope filtering on output (manager sees all, chapter_board sees own).

Callers: `src/components/admin/VolunteerComplianceWidget.tsx:33`,
`src/components/admin/VolunteerAgreementPanel.tsx:200`.

### Por que Path Y (chapter_board engagement) ao invés de catalog-only

V4 catalog `manage_member` audience: `volunteer × manager + deputy_manager +
co_gp` only — **does NOT include chapter_board** (any role).

Without Path Y, V3→V4 conversion would lose all 7 chapter_board × board_member
members (Emanoela, Emanuele, Lorena + 4 sponsor × sponsor + chapter_board ×
board_member), which is operationally wrong: chapter_board members are who
countersign their chapter's volunteer agreements (chapter governance).

Path Y precedent ADR-0037 (chapter_needs subsystem): preserves chapter_board
engagement via direct `auth_engagements` query for chapter-scoped access.
Same pattern applied here.

### Privilege expansion (verified pre-apply)

```
V3 set       = 10 members
V4+Path Y    = 13 members
gains        = [Ana Cristina Fernandes Lima, Roberto Macêdo, Rogério Peixoto]
losses       = (none)
```

**Gain rationale (3)**:
- **Ana Cristina Fernandes Lima** — `chapter_board` engagement registered in V4
  but NO `chapter_board` designation in `members.designations`. Inverse drift
  pattern (engagement-without-designation). V4 conversion correctly grants
  access — V4 engagement is source of truth.
- **Roberto Macêdo** — `chapter_board × liaison` engagement (already gained in
  ADR-0030 view_internal_analytics catalog). Consistent extension.
- **Rogério Peixoto** — same as Ana Cristina (engagement-without-designation).

**Loss rationale**: zero. Vitor (manager+SA) covered by `manage_member`;
all 7 chapter_board designations have matching chapter_board engagements.

### Section B — register_attendance_batch security drift

**SECURITY HOLE** (same pattern as ADR-0038 `update_event_duration`):
parameter-based gate without `auth.uid()` cross-check. Authenticated caller
could pass any tribe_leader UUID and bypass the gate.

V3 broken pattern atual:
```sql
PERFORM 1 FROM members
WHERE id = p_registered_by  -- ⚠️ comes from request, NOT from auth.uid()
  AND (is_superadmin = true OR operational_role IN ('manager','deputy_manager','tribe_leader'));
IF NOT FOUND THEN
  RAISE EXCEPTION 'Unauthorized: only managers and tribe leaders can register attendance';
END IF;
```

Callers:
- `src/components/workspace/AttendanceForm.tsx:144` — passes `member.id` (own
  auth-derived id, no production bug)
- `supabase/functions/nucleo-mcp/index.ts:627` — passes `member.id` (same)

Both callers pass the auth-derived id. Production bug never triggered.
Architectural drift remains exposed via PostgREST.

V4 fix (mirror ADR-0038 update_event_duration):
- Derive `v_caller_id` from `auth.uid()` + `can_by_member(v_caller_id, 'manage_event')`
- `p_registered_by` retained for signature compat, ignored
- Insert uses `v_caller_id` (authoritative)

Privilege expansion: zero (V3 set = V4 set = 8 members: admin + 6 tribe_leaders).
Same audience as `update_event_duration` (both gated by event-management tier).

### pg_policy precondition (Q-D charter mandatory)

Word-boundary regex `\m` scan on `pg_policy.polqual` + `polwithcheck` for all
4 fns: **zero references** for each. Safe to proceed without RLS hotpath risk.

---

## Decisão (proposta)

### 1. `counter_sign_certificate` — V4 manage_member + Path Y (chapter scope preserved)

```sql
CREATE OR REPLACE FUNCTION public.counter_sign_certificate(p_certificate_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_caller_id uuid;
  v_caller_chapter text;
  v_caller_person_id uuid;
  v_is_manage_member boolean;
  v_is_chapter_board boolean;
  v_cert record;
  v_contracting_chapter text;
  v_hash text;
BEGIN
  SELECT m.id, m.chapter, m.person_id
    INTO v_caller_id, v_caller_chapter, v_caller_person_id
  FROM public.members m WHERE m.auth_id = auth.uid();

  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('error', 'not_authenticated');
  END IF;

  v_is_manage_member := public.can_by_member(v_caller_id, 'manage_member');
  v_is_chapter_board := EXISTS (
    SELECT 1 FROM public.auth_engagements ae
    WHERE ae.person_id = v_caller_person_id
      AND ae.kind = 'chapter_board'
      AND ae.status = 'active'
  );

  IF NOT v_is_manage_member AND NOT v_is_chapter_board THEN
    RETURN jsonb_build_object('error', 'not_authorized');
  END IF;

  SELECT * INTO v_cert FROM public.certificates WHERE id = p_certificate_id;
  IF v_cert IS NULL THEN RETURN jsonb_build_object('error', 'not_found'); END IF;
  IF v_cert.counter_signed_by IS NOT NULL THEN
    RETURN jsonb_build_object('error', 'already_counter_signed');
  END IF;

  v_contracting_chapter := COALESCE(
    v_cert.content_snapshot->>'contracting_chapter',
    (SELECT m.chapter FROM public.members m WHERE m.id = v_cert.member_id)
  );

  -- Chapter-scope enforcement: chapter_board (without manage_member) restricted to own chapter
  IF v_is_chapter_board AND NOT v_is_manage_member THEN
    IF v_contracting_chapter IS DISTINCT FROM v_caller_chapter THEN
      RETURN jsonb_build_object('error', 'not_authorized_different_chapter');
    END IF;
  END IF;

  v_hash := encode(sha256(convert_to(
    COALESCE(v_cert.signature_hash,'') || v_caller_id::text || now()::text || 'nucleo-ia-countersign-salt', 'UTF8'
  )), 'hex');

  UPDATE public.certificates SET counter_signed_by = v_caller_id, counter_signed_at = now() WHERE id = p_certificate_id;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes)
  VALUES (v_caller_id, 'certificate_counter_signed', 'certificate', p_certificate_id,
    jsonb_build_object('verification_code', v_cert.verification_code, 'type', v_cert.type, 'contracting_chapter', v_contracting_chapter));

  INSERT INTO public.notifications (recipient_id, type, title, body, link, source_type, source_id, delivery_mode)
  VALUES (v_cert.member_id, 'certificate_ready',
    'Seu ' || v_cert.title || ' esta pronto!',
    'O documento foi contra-assinado e esta disponivel. Codigo: ' || v_cert.verification_code,
    '/certificates', 'certificate', p_certificate_id,
    public._delivery_mode_for('certificate_ready'));

  RETURN jsonb_build_object('success', true, 'counter_signature_hash', v_hash, 'counter_signed_at', now());
END;
$$;
```

### 2. `get_pending_countersign` — V4 manage_member + Path Y reader

```sql
CREATE OR REPLACE FUNCTION public.get_pending_countersign()
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_caller_id uuid;
  v_caller_chapter text;
  v_caller_person_id uuid;
  v_is_manage_member boolean;
  v_is_chapter_board boolean;
  v_result jsonb;
BEGIN
  SELECT m.id, m.chapter, m.person_id
    INTO v_caller_id, v_caller_chapter, v_caller_person_id
  FROM public.members m WHERE m.auth_id = auth.uid();

  IF v_caller_id IS NULL THEN RETURN '[]'::jsonb; END IF;

  v_is_manage_member := public.can_by_member(v_caller_id, 'manage_member');
  v_is_chapter_board := EXISTS (
    SELECT 1 FROM public.auth_engagements ae
    WHERE ae.person_id = v_caller_person_id
      AND ae.kind = 'chapter_board'
      AND ae.status = 'active'
  );

  IF NOT v_is_manage_member AND NOT v_is_chapter_board THEN
    RETURN '[]'::jsonb;
  END IF;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', c.id, 'type', c.type, 'title', c.title, 'member_name', m.name, 'member_email', m.email,
    'member_role', m.operational_role, 'member_chapter', m.chapter, 'tribe_name', t.name, 'cycle', c.cycle,
    'verification_code', c.verification_code, 'issued_at', c.issued_at,
    'signature_hash', c.signature_hash
  ) ORDER BY c.issued_at DESC), '[]'::jsonb) INTO v_result
  FROM public.certificates c
  JOIN public.members m ON m.id = c.member_id
  LEFT JOIN public.tribes t ON t.id = m.tribe_id
  WHERE c.counter_signed_by IS NULL
    AND COALESCE(c.status, 'issued') = 'issued'
    AND c.type != 'volunteer_agreement'
    AND (v_is_manage_member OR m.chapter = v_caller_chapter);

  RETURN v_result;
END;
$$;
```

### 3. `get_volunteer_agreement_status` — V4 manage_member + Path Y reader

(Body preserved verbatim except gate replacement; full body in migration file.)

```sql
-- Gate excerpt:
SELECT m.id, m.chapter, m.person_id
  INTO v_caller_id, v_caller_chapter, v_caller_person_id
FROM public.members m WHERE m.auth_id = auth.uid();

IF v_caller_id IS NULL THEN
  RETURN jsonb_build_object('error', 'Unauthorized');
END IF;

v_is_manage_member := public.can_by_member(v_caller_id, 'manage_member');
v_is_chapter_board := EXISTS (
  SELECT 1 FROM public.auth_engagements ae
  WHERE ae.person_id = v_caller_person_id
    AND ae.kind = 'chapter_board'
    AND ae.status = 'active'
);

IF NOT v_is_manage_member AND NOT v_is_chapter_board THEN
  RETURN jsonb_build_object('error', 'Unauthorized');
END IF;
-- (output filtering uses v_is_manage_member instead of v_is_manager throughout)
```

### 4. `register_attendance_batch` — auth.uid()-derived + manage_event (Section B security fix)

```sql
CREATE OR REPLACE FUNCTION public.register_attendance_batch(
  p_event_id uuid,
  p_member_ids uuid[],
  p_registered_by uuid DEFAULT NULL  -- DEPRECATED: kept for signature compat, ignored
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_caller_id uuid;
  inserted integer;
BEGIN
  SELECT m.id INTO v_caller_id
  FROM public.members m WHERE m.auth_id = auth.uid();

  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  IF NOT public.can_by_member(v_caller_id, 'manage_event') THEN
    RAISE EXCEPTION 'Unauthorized: requires manage_event';
  END IF;

  INSERT INTO public.attendance (event_id, member_id, present, registered_by)
  SELECT p_event_id, unnest(p_member_ids), true, v_caller_id
  ON CONFLICT (event_id, member_id)
  DO UPDATE SET present = true, registered_by = v_caller_id, updated_at = now();
  GET DIAGNOSTICS inserted = ROW_COUNT;
  RETURN inserted;
END;
$$;

COMMENT ON FUNCTION public.register_attendance_batch(uuid, uuid[], uuid) IS
'p_registered_by is DEPRECATED and ignored — caller derived from auth.uid() (ADR-0039 p69 security drift fix mirroring ADR-0038 update_event_duration). V4 manage_event gate.';
```

### 5. Defense-in-depth REVOKE FROM PUBLIC, anon

```sql
REVOKE EXECUTE ON FUNCTION public.counter_sign_certificate(uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.get_pending_countersign() FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.get_volunteer_agreement_status() FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.register_attendance_batch(uuid, uuid[], uuid) FROM PUBLIC, anon;
```

---

## Implications

### Para a plataforma
- 3 fns adicionais Phase B'' V3→V4 (countersign subsystem 100% V4).
- 1 fn security drift fix (register_attendance_batch).
- Phase B'' tally: 83 → 86/246 (~35.0%).
- Drift signals: 9/8 → **10/8** (parameter-gate pattern closures sediment).
- Zero novo V4 action — full Opção B reuse `manage_member` + `manage_event`.
- Path Y precedent (ADR-0037) extended to second subsystem (countersign).
- 4 SECDEF advisor surface entries closed (REVOKE FROM anon).
- `volunteer_agreement_countersign` subsystem 100% V4.

### Para members (drift consolidado)
- **3 gains** (Ana Cristina, Roberto, Rogério) — all legitimate chapter_board
  V4 engagements. V3 designation drift correction (members had engagement
  but lacked designation in `members.designations`). Inverse drift correction
  (engagement-without-designation), legitimate gain.
- **0 losses** — Vitor (manage_member) + 7 chapter_board × board_member members
  + 7 chapter_board × sponsor (Felipe, Francisca, Ivan, Márcio, Matheus +
  Lorena/Emanuele/Emanoela) all preserved.
- Section B (register_attendance_batch): zero member-set change, security
  vector closed.

### Para path A/B/C optionality
- Path A (PMI internal): positivo — countersign subsystem governance hardened
  + parameter-gate vector closed.
- Path B (consultoria): positivo — multi-tenant security baseline strengthened.
- Path C (community-only): neutro.

---

## Open Questions (para PM input)

### Q1 — Aceito Section A countersign cluster Path Y reuse?

3 fns × identical V3 gate (manager OR chapter_board designation) → V4
manage_member + Path Y chapter_board engagement. ADR-0037 precedent.
3 legitimate gains (engagement-without-designation drift correction), zero losses.

Recomendação: **SIM** — ADR-0037 Path Y pattern extension to volunteer-agreement
countersign subsystem.

### Q2 — Aceito Section B register_attendance_batch security fix?

Same pattern as ADR-0038 update_event_duration fix. Switch from parameter-based
gate (privilege escalation vector) to `auth.uid()`-derived caller +
`manage_event`. Zero member-set change. Closes architectural drift.

Recomendação: **SIM** — sediment ADR-0038 detection pattern by acting on second
case found.

### Q3 — Implementation timing

ADR está em `Proposed`. Implementação requer:
- 1 migration conversão (4 fns single batch)
- 1 migration REVOKE FROM anon (4 fns)
- 1 audit doc update

Estimativa: ~25 min.

Recomendação: **p69 mesmo**.

---

## Status / Next Action

- [ ] PM ratifica ADR (Q1 / Q2 / Q3)
- [x] Migration conversão + drift fix — `20260427220000`
- [x] Migration REVOKE FROM anon — `20260427220005`
- [x] Audit doc update — Phase B'' tally bumps (83 → 86 / 246, ~35.0%)
- [x] Status ADR → `Proposed` (PM rubber-stamp pending)

**Bloqueador**: nenhum (PM rubber-stamp expected).

### Outcome (post-apply esperado)

- 3 fns Phase B'' V3→V4 (volunteer-agreement countersign subsystem 100% V4).
- 1 fn security drift fix (register_attendance_batch parameter-gate).
- Privilege expansion countersign: legacy 10 → V4+Path Y 13 (gains 3,
  losses 0; all 3 gains are V4-engagement-correct).
- Privilege expansion register_attendance_batch: zero member set change.
- Zero novo V4 action — full reuse `manage_member` + `manage_event`.
- Defense-in-depth REVOKE FROM anon aplicado em 4 fns.
- pg_policy precondition (Q-D charter): zero RLS refs verificados.
- Path Y pattern extension: ADR-0037 precedent applied to second subsystem.
- Parameter-gate vector pattern: 2nd closure (sediment of p68 detection).
- Phase B'' tally: 83 → 86/246 (~35.0%).
- 4 SECDEF advisor entries closed: 778 → 774.
