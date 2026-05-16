# Engagement Seed Templates

> **Status**: ACTIVE — p172 #5 (2026-05-16)
> **Source-of-truth**: tabela `public.engagement_seed_templates`
> **RPC consumer**: `public.seed_member_engagement_by_role(p_person_id, p_template_slug, p_initiative_id)`

Catalog canônico de templates de engagement para onboarding de members.
Reduces drift quando Núcleo expande (PMI-CE pilot, PMI-GO replicas).

## Princípios

1. **Templates são globais** por default (`organization_id IS NULL`).
   Per-org overrides podem ser criados depois.
2. **Templates pré-validam** kind+role combinations existentes em
   `engagement_kind_permissions` (V4 ADR-0007).
3. **Seed RPC é idempotente**: skip se engagement (person × initiative ×
   kind × role) já existe com status=active.
4. **Scope**: cada engagement no template é `'initiative'` (needs
   p_initiative_id) ou `'organization'` (org-wide, initiative_id NULL).

## Templates canônicos

### 1. `researcher` — Default volunteer onboarding
Member novo aprovado no VEP/selection cycle, sem cargo específico.

```jsonb
[{"kind": "volunteer", "role": "researcher", "scope": "initiative"}]
```

**Uso**: 27 active members hoje. Default pra aprovação selection_application.

### 2. `tribe_leader` — Single-tribe leader
Líder responsável por 1 initiative (tribo). Pode ter co_leader.

```jsonb
[{"kind": "volunteer", "role": "leader", "scope": "initiative"}]
```

**Permissions herdadas** (engagement_kind_permissions): award_champion,
manage_board_admin, manage_event, sign_chain_leader, view_pii, write,
write_board.

**Uso**: 7 active tribe leaders.

### 3. `co_leader` — Deputy tribe leader (p172 #21 multi-leader)
Co-líder em initiative, paralelo ao leader principal.

```jsonb
[{"kind": "volunteer", "role": "co_leader", "scope": "initiative"}]
```

**Recebe digest semanal** (p172 #21 _v4_initiative_leader_member_ids).

### 4. `manager` — Chapter manager (GP)
Gerente do programa/capítulo. Org-wide authority.

```jsonb
[{"kind": "volunteer", "role": "manager", "scope": "organization"}]
```

**Permissions** (15 actions): award_champion, manage_*, view_*, write_*, etc.
Equivalent a operational_role='manager' V3.

### 5. `deputy_manager` — Chapter co-GP
Vice-gerente. Mesmas 15 actions que manager.

```jsonb
[{"kind": "volunteer", "role": "deputy_manager", "scope": "organization"}]
```

### 6. `co_gp` — Founder co-manager
Founder/co-fundador com gestão. Mesmas 15 actions.

```jsonb
[{"kind": "volunteer", "role": "co_gp", "scope": "organization"}]
```

### 7. `comms_leader` — Communications lead
Líder de comunicações (designation V3 espelhado em V4).

```jsonb
[{"kind": "volunteer", "role": "comms_leader", "scope": "organization"}]
```

**Permissions**: award_champion, manage_comms, manage_event,
sign_chain_leader, write, write_board (6 actions).

### 8. `sponsor` — Chapter sponsor
Patrocinador. Org-scope.

```jsonb
[{"kind": "sponsor", "role": "sponsor", "scope": "organization"}]
```

**Permissions**: manage_finance, manage_partner, view_chapter_dashboards,
view_internal_analytics (4 actions).

### 9. `ambassador` — Chapter ambassador
Embaixador / founder. Permissions reduzidas.

```jsonb
[{"kind": "ambassador", "role": "ambassador", "scope": "organization"}]
```

**Note**: founder role usado em algumas places (Vitor, Fabricio) —
template separado se necessário.

### 10. `chapter_liaison` — PMI chapter liaison
Liaison PMI Latam/Brasil/etc.

```jsonb
[{"kind": "chapter_board", "role": "liaison", "scope": "organization"}]
```

**Permissions**: manage_partner, participate_in_governance_review,
view_chapter_dashboards, view_internal_analytics (4 actions).

### 11. `chapter_board_member` — PMI board observer
Observer non-voting do PMI chapter board.

```jsonb
[{"kind": "chapter_board", "role": "board_member", "scope": "organization"}]
```

**Permissions**: view_chapter_dashboards, view_pii (2 actions).

### 12. `observer` — Read-only researcher / curator pré-engagement
Para pessoas em discovery sem volunteer agreement assinado.

```jsonb
[{"kind": "observer", "role": "observer", "scope": "organization"}]
```

## RPC Usage

```sql
-- Seed researcher pra novo member num initiative:
SELECT public.seed_member_engagement_by_role(
  p_person_id := '<uuid>',
  p_template_slug := 'researcher',
  p_initiative_id := '<initiative_uuid>'
);

-- Seed manager (org-scope, initiative_id NULL):
SELECT public.seed_member_engagement_by_role(
  p_person_id := '<uuid>',
  p_template_slug := 'manager'
);
```

Returns JSONB:
```json
{
  "success": true,
  "template_slug": "researcher",
  "engagements_created": 1,
  "engagements_skipped": 0,
  "engagement_ids": ["..."]
}
```

## Authority

- Auth: caller precisa `manage_member` permission (V4 can_by_member).
- Skip duplicates: se engagement (person × initiative × kind × role)
  active já existe, skip + return em `engagements_skipped`.
- Org enforcement: target person.organization_id == caller.organization_id.

## Expansion (PMI-CE pilot, PMI-GO replicas)

Templates são globais (organization_id NULL = applies to all orgs).
Nova replica usa MESMOS templates; só o target initiative/org muda.

Per-org override: criar row com `organization_id = <new_org_uuid>` +
mesmo slug = overrides global pra essa org.

## Migrations

- **20260676100000** (p172 #5): create table + 12 seed templates + RPC.

## Related

- ADR-0007: V4 Authority via can()
- ADR-0009: Config-not-code (templates = config, não hardcoded)
- ADR-0080: V4 Engagement canonical (FK engagements.selection_application_id)
- p171 #8 champion_criteria_catalog (mesmo pattern: catalog DB-driven)
