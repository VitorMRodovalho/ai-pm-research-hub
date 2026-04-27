# ADR-0032: Board Admin fns V4 conversion — `manage_board_admin` new action + `view_internal_analytics` reuse

- Status: **Accepted** (2026-04-26 p66 — PM ratify Q1=SIM / Q2=SIM / Q3=Opção A / Q4=p66)
- Data: 2026-04-26 (p66)
- Autor: PM (Vitor) + Claude (proposal autônomo)
- Escopo: Phase B'' V3→V4 conversion track — fecha 4 fns V3 board admin
- Implementation:
  - Migration `20260427122648_adr_0032_board_admin_v4_action_grants.sql` (8 grants)
  - Migration `20260427122725_adr_0032_board_admin_v4_writers_convert.sql` (3 writers)
  - Migration `20260427122732_adr_0032_board_admin_v4_reader_convert.sql` (1 reader Opção A)
  - Migration `20260427122737_adr_0032_board_admin_revoke_anon.sql` (defense-in-depth)
- Privilege expansion outcomes:
  - Group W (writers): legacy 8 → V4 10. would_gain = [Herlon, Mayanna] (initiative leaders, scope-restricted via `can_by_member(_, _, 'initiative', _)`). would_lose = []
  - Group R (reader): legacy 5 → V4 10. would_gain = 7 admin/governance roles. would_lose = [Sarah curator, Mayanna comms_leader] — Path A drift correction
- pg_policy precondition (Q-D charter, p65): zero RLS refs verified pre-apply.
- Cross-references: ADR-0007, ADR-0011, ADR-0027 (Opção B reuse precedent),
  ADR-0030 (view_internal_analytics — action being reused for reader),
  ADR-0031 (admin_list_members — recent Opção B reuse precedent)

---

## Contexto

Sequência ADR-0029/0030/0031. Fecha 4 fns V3 board admin documentadas em
handoff p67 next-tier discovery. Análise revelou **2 audiências distintas**
nas 4 fns — não é monolítico "1 nova action".

### As 4 funções afetadas

#### Group W (Writers — 3 fns) — destructive board ops

V3 ladder idêntica para os 3:
```sql
v_caller.is_superadmin = true
OR v_caller.operational_role IN ('manager', 'deputy_manager')
OR ('co_gp' = ANY(v_caller.designations))
OR (v_caller.operational_role = 'tribe_leader' AND v_caller.tribe_id = v_board_tribe_id)
```

(`admin_update_board_columns` excluí co_gp; trataremos como variante)

| Fn | Caller | Op |
|---|---|---|
| `admin_archive_project_board(uuid, text, boolean)` | admin UI (não em src/) | DESTRUCTIVE — set is_active=false + archive items |
| `admin_restore_project_board(uuid, text)` | admin UI | DESTRUCTIVE inverse |
| `admin_update_board_columns(uuid, jsonb)` | /admin/board/[id] (per RPC inventory) | UPDATE columns config |

**Legacy V3 set: 8 active members** (6 tribe_leaders + Fabricio + Vitor SA)

#### Group R (Reader — 1 fn) — list archived items

V3 ladder MAIS BROAD que writers — inclui curator + comms_leader:
```sql
is_superadmin
OR operational_role IN ('manager', 'deputy_manager')
OR designations IN ('co_gp', 'curator', 'comms_leader')
```

| Fn | Caller |
|---|---|
| `admin_list_archived_board_items(uuid, integer)` | `/admin/governance-v2.astro` (curator-visible page from Bug A) |

**Legacy V3 set: 5 active members** (Fabricio, Mayanna, Roberto, Sarah, Vitor SA)

### Por que 2 estratégias diferentes

**Group W (writers)** tem privilege expansion problemática reusando V4 actions:

| Reuse candidate | V4 set | Issue |
|---|---|---|
| `write_board` | 35 active | TOO broad — granted to researcher/participant/communicator. Initiative-scoped via `can_by_member(_, 'write_board', 'initiative', id)` ainda expande de 8 → ~30 (todos os leaders de iniciativas). Destructive op em V3 era restrita. |
| `manage_platform` | 2 active | TOO narrow — perde co_gp, perde tribe_leader own-tribe scope. |
| `view_internal_analytics` | 10 active | Read-oriented; ladder não inclui tribe_leader. |
| `manage_member` | 2 active | Wrong domain. |

→ **Group W needs new V4 action `manage_board_admin`**.

**Group R (reader)** pode reusar:

| Reuse candidate | V4 set vs legacy | Drift |
|---|---|---|
| `view_internal_analytics` | 10 (incl Roberto, sem Sarah/Mayanna) | Drift correction: Sarah curator + Mayanna comms_leader perdem (mesmo padrão ADR-0030) |
| `write_board` | 35 | Too broad — read-only grant a participant é cesto demais |

→ **Group R reuses `view_internal_analytics`** (Opção B precedent) com drift correction documented.

---

## Decisão (proposta)

### Group W — Nova action `manage_board_admin`

#### 1. Adicionar action ao engagement_kind_permissions

```sql
INSERT INTO public.engagement_kind_permissions (kind, role, action, scope)
VALUES
  -- Org-admin tier (matches V3 manager/deputy_manager/co_gp)
  ('volunteer', 'co_gp',          'manage_board_admin', 'organization'),
  ('volunteer', 'manager',        'manage_board_admin', 'organization'),
  ('volunteer', 'deputy_manager', 'manage_board_admin', 'organization'),
  -- Initiative-leader tier (matches V3 tribe_leader own-tribe scope)
  ('volunteer', 'leader',         'manage_board_admin', 'initiative'),
  ('study_group_owner', 'owner',   'manage_board_admin', 'initiative'),
  ('study_group_owner', 'leader',  'manage_board_admin', 'initiative'),
  ('committee_member', 'leader',   'manage_board_admin', 'initiative'),
  ('workgroup_member', 'leader',   'manage_board_admin', 'initiative')
  ON CONFLICT (kind, role, action) DO NOTHING;
```

#### 2. Convert 3 writers — usar resource-scoped `can_by_member()` para enforce own-initiative scope

```sql
-- Pattern aplicado em todos os 3:
DECLARE
  v_caller_id uuid;
  v_board record;
BEGIN
  SELECT m.id INTO v_caller_id FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Auth required'; END IF;

  SELECT * INTO v_board FROM public.project_boards WHERE id = p_board_id;
  IF v_board IS NULL THEN RAISE EXCEPTION 'Board not found'; END IF;

  -- V4 gate: org-wide manage_board_admin OR initiative-scoped manage_board_admin
  IF NOT public.can_by_member(v_caller_id, 'manage_board_admin', 'initiative', v_board.initiative_id) THEN
    RAISE EXCEPTION 'Insufficient permissions';
  END IF;

  -- (rest of body)
END;
```

`can_by_member` resolve scope automaticamente:
- Organization-scope grant → passes para qualquer initiative
- Initiative-scope grant → passes apenas para a initiative específica

Path Y (preserve own-initiative scope) é built-in via resource args.

#### 3. Privilege expansion check — Group W

```sql
WITH legacy_writers AS (
  SELECT m.id, m.name FROM members m
  WHERE m.is_active = true
    AND (
      m.is_superadmin
      OR m.operational_role IN ('manager', 'deputy_manager')
      OR m.designations && ARRAY['co_gp']
      OR m.operational_role = 'tribe_leader'  -- own-tribe enforced runtime per board
    )
),
v4_writers AS (
  SELECT DISTINCT m.id, m.name FROM members m
  JOIN engagements e ON e.person_id = m.person_id AND e.status = 'active'
  WHERE m.is_active = true
    AND (
      m.is_superadmin
      OR (e.kind = 'volunteer' AND e.role IN ('co_gp', 'manager', 'deputy_manager'))
      OR (e.kind IN ('volunteer', 'study_group_owner', 'committee_member', 'workgroup_member')
          AND e.role IN ('leader', 'owner'))
    )
)
SELECT
  (SELECT count(*) FROM legacy_writers) AS legacy,
  (SELECT count(*) FROM v4_writers) AS v4,
  ARRAY(SELECT name FROM v4_writers WHERE id NOT IN (SELECT id FROM legacy_writers) ORDER BY name) AS would_gain,
  ARRAY(SELECT name FROM legacy_writers WHERE id NOT IN (SELECT id FROM v4_writers) ORDER BY name) AS would_lose;
```

(executar pre-apply para confirmar zero-net change ou drift documentado)

### Group R — Reuse `view_internal_analytics`

#### 4. Convert `admin_list_archived_board_items`

```sql
CREATE OR REPLACE FUNCTION public.admin_list_archived_board_items(...)
...
DECLARE
  v_caller_id uuid;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid() AND is_active = true;
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Auth required'; END IF;

  -- V4 gate (Opção B reuse view_internal_analytics — same precedent as ADR-0031)
  IF NOT public.can_by_member(v_caller_id, 'view_internal_analytics') THEN
    RAISE EXCEPTION 'Board governance access required';
  END IF;

  RETURN QUERY (...);
END;
```

#### 5. Privilege expansion check — Group R

```
legacy reader = 5: Fabricio, Mayanna, Roberto, Sarah, Vitor SA
v4 view_internal_analytics = 10
would_gain = [Ana, Felipe, Francisca, Ivan, Márcio, Matheus, Rogério] (7 admin/governance roles)
would_lose = [Mayanna (comms_leader designation sem V4 engagement),
              Sarah (curator designation sem V4 engagement)]
```

**Implications**:
- 7 admin/governance roles ganham acesso a archived board items listing — adequado per role institucional
- Sarah/Mayanna drift loss — mesmo padrão de ADR-0030 (Path A drift correction)
- **MAS**: `/admin/governance-v2.astro` é Bug A's curator-visible page. Sarah loses listing capability there. UX consideration.

### Alternative para Group R: keep V3 OR new action

Dois caminhos alternativos para R, dependendo do PM weight:

- **R-Opção A** (proposed): reuse `view_internal_analytics` + drift correction Sarah/Mayanna
- **R-Opção B**: new action `view_archived_boards` com ladder incluindo curator + comms_leader designations (hybrid V3+V4)
- **R-Opção C**: keep V3 (defer)

R-Opção A é mais consistente com p66 padrão; R-Opção B preserva curator UX em /admin/governance-v2.

---

## Implications

### Para a plataforma
- **4 fns V3 a menos** no backlog Phase B''.
- **+1 V4 action** (`manage_board_admin`).
- **+1 Opção B reuse** (view_internal_analytics ext to listing reader).
- Resource-scoped `can_by_member` usage — first time in p66 (precedente para ADR futuras com per-resource gates).

### Para members
- **Group W writers**: privilege expansion neutra/intencional (TBD pre-apply check).
- **Group R reader Opção A**: 7 admin/governance gain access; Sarah + Mayanna lose.
- **Group R reader Opção B**: zero loss + 7 gain; mas hybrid V3+V4.

### Para path A/B/C optionality
- **Path A (PMI internal)**: positivo — board governance auditable.
- **Path B (consultoria)**: positivo — multi-tenant board admin role explicit.
- **Path C (community-only)**: neutro.

---

## Open Questions (para PM input)

### Q1 — Aceito separar Group W (new action) e Group R (reuse)?

**Recomendação**: SIM. Audiences são genuinamente distintos.

### Q2 — Group W: resource-scoped `manage_board_admin` ladder OK?

Proposed ladder = manage_platform (org-wide) + initiative-leader (initiative-scope).
Privilege expansion check pendente — pre-apply verifica.

**Recomendação**: SIM, com check pre-apply.

### Q3 — Group R: Opção A (reuse view_internal_analytics, accept Sarah/Mayanna drift) OU Opção B (new action `view_archived_boards`)?

**Trade-off**:
- Opção A: simpler, follows ADR-0030 drift precedent. Sarah loses curator board listing access em /admin/governance-v2.
- Opção B: preserves Sarah/Mayanna access. New action sprawl.

**Recomendação**: **Opção A com PM accept Sarah curator drift** — Sarah já lost view_internal_analytics em ADR-0030, drift consistent.

OU se UX em /admin/governance-v2 é importante para Sarah → Opção B.

### Q4 — Implementation timing

Estimativa: ~1.5h (mais complexa que ADR-0031 — 4 fns + new action + scope work + privilege expansion validation).

**Recomendação**: PM decide p66 ou p67.

---

## Status / Next Action

- [x] PM ratifica ADR (Q1=SIM / Q2=SIM / Q3=Opção A / Q4=p66) — 2026-04-26 p66
- [x] Migration `engagement_kind_permissions` rows (8 grants) — `20260427122648`
- [x] Migration conversão Group W (3 fns com resource-scoped gate) — `20260427122725`
- [x] Migration conversão Group R (1 fn — Opção A) — `20260427122732`
- [x] Migration REVOKE FROM anon — `20260427122737`
- [x] Privilege expansion validation (real numbers verified pre-apply)
- [x] Audit doc update — Phase B'' tally bumps (62 → 66 / 246, ~26.8%)
- [x] Status ADR → `Accepted`

**Bloqueador**: nenhum.

### Outcome (post-apply)

- 4 fns V3 convertidas: 3 writers via novo `manage_board_admin` (resource-scoped) + 1 reader via Opção B reuse `view_internal_analytics`.
- 1 nova V4 action (`manage_board_admin`) com 8 grants.
- Group W gain Herlon + Mayanna (initiative leaders, scope-restricted to own initiative).
- Group R gain 7 admin/governance roles + lose Sarah/Mayanna (Path A drift correction).
- Phase B'' tally: 62 → 66 / 246 (~26.8%).
- First use of resource-scoped `can_by_member(_, action, 'initiative', id)` in p66 — precedent para ADRs futuras.
