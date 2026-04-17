# ADR-0011: V4 Auth Pattern — RPCs + MCP (single source of truth via `can()`)

- Status: Accepted
- Data: 2026-04-17
- Aprovado por: Vitor (PM) em 2026-04-17
- Autor: Vitor (PM) + Claude (comitê arquitetural)
- Escopo: Autenticação e autorização de RPCs, MCP tools e front paths — pós Domain Model V4

## Contexto

O cutover Domain Model V4 (13/Abr/2026 — ver ADR-0007 e `DOMAIN_MODEL_V4_MASTER.md`) entregou as primitivas:
- `public.can(p_person_id, p_action, p_resource_type, p_resource_id)` — retorna boolean consultando `auth_engagements` × `engagement_kind_permissions`
- `public.can_by_member(p_member_id, p_action, ...)` — wrapper que aceita `members.id` em vez de `persons.id`
- `public.rls_can(p_action)` — helper para RLS policies consultando `auth.uid()`
- TypeScript `canV4(sb, member_id, action)` — wrapper para MCP tools (EF `nucleo-mcp`)

Auditoria 17/Abr (Eixo A da sessão de hoje) revelou drift estrutural: de **576 RPCs SECURITY DEFINER**, apenas **5 usam `can()`/`can_by_member()`**. As outras **83 RPCs com auth gate** ainda verificam `operational_role IN ('manager','deputy_manager',...)` hardcoded. Efeitos:

1. **Divergência silenciosa**: se um novo kind/role é adicionado a `engagement_kind_permissions` com permission `manage_event`, o MCP aceita (via `canV4`) mas a RPC rejeita (não reconhece o role).
2. **Dupla fonte de verdade**: MCP-level e RPC-level decidem independentemente. Mudança de política exige dois patches.
3. **`engagement_kind_permissions` subutilizado** como fonte operacional única.

Nenhum incidente reportado em `mcp_usage_log` nos últimos 30 dias (0 unauthorized em 200+ calls), mas o drift é dívida técnica que cresce com o tempo.

## Decisão

**`public.can()` / `public.can_by_member()` é a ÚNICA fonte de verdade de autoridade no banco. Todas as RPCs com auth gate DEVEM invocá-la em vez de verificar `operational_role` hardcoded.**

### Padrão canônico por camada

| Camada | Implementação obrigatória |
|---|---|
| **RLS policies** | `rls_can('<action>')` — helper que lê `auth.uid()` e delega a `can()` |
| **RPC SECURITY DEFINER (write)** | `IF NOT public.can_by_member(v_caller_id, '<action>') THEN RAISE EXCEPTION ...` |
| **RPC SECURITY DEFINER (PII read)** | `IF NOT public.can_by_member(v_caller_id, 'view_pii') THEN RAISE EXCEPTION ...` |
| **RPC SECURITY DEFINER (read s/ PII)** | Auth gate opcional — depender de RLS/MCP gate já é suficiente |
| **MCP tools (write)** | `if (!(await canV4(sb, member.id, '<action>'))) return err("Unauthorized")` |
| **MCP tools (read PII)** | `canV4(sb, member.id, 'view_pii')` ou delegação à RPC (que já gate) |
| **Front paths `/admin/*`** | Middleware verifica via RPC helper e redireciona |

### Actions canônicas

Definidas em `engagement_kind_permissions.action`:
- `write` — operações de escrita de domínio (criar evento, marcar presença, criar ata, notificar tribo)
- `write_board` — criar/mover cards em board (granularidade menor que `write`)
- `manage_event` — editar/cancelar evento, inclusive em série recorrente
- `manage_member` — offboard/reactivate/update member, mudar role/designations
- `manage_partner` — CRUD de parceiros e interactions
- `promote` — triagem/promoção de aplicações do ciclo seletivo
- `view_pii` — ler email/phone/pmi_id/auth_id/cpf de membros/pessoas

Novas actions são introduzidas via seed em `engagement_kind_permissions`, **nunca** via código de RPC.

### Scope refinement quando `can()` não é suficiente

Para casos em que `can()` não modela finura de recurso (ex: "tribe_leader só gerencia eventos da própria tribo"), a RPC aplica **segundo check refinado** APÓS `can_by_member`:

```sql
IF NOT public.can_by_member(v_caller_id, 'manage_event') THEN
  RAISE EXCEPTION 'Unauthorized: requires manage_event permission';
END IF;

-- Scope refinement: tribe_leader constrained to own tribe
IF v_caller_role = 'tribe_leader' AND v_caller_tribe IS DISTINCT FROM v_event_tribe THEN
  RAISE EXCEPTION 'Unauthorized: tribe_leader can only manage events of own tribe';
END IF;
```

Este padrão é **temporário**. A evolução desejada é que `can()` aceite `resource_type='event'` e resolva scope internamente (tracked como tech-debt).

### Proibido (anti-patterns)

- `IF v_caller.operational_role IN ('manager','deputy_manager',...)` como ÚNICO gate
- `IF v_caller.is_superadmin = true` como ÚNICO gate
- Duplicar lógica de role list em RPC quando `can()` já expressa a política
- Introduzir nova RPC com auth gate hardcoded — sempre use `can_by_member`

## Consequências

### Positivas
- **Single source of truth**: política vive em `engagement_kind_permissions`, propaga automaticamente
- **Menor custo de mudança**: adicionar kind/role com permission é seed, não migration de RPCs
- **Audit trail**: `engagement_kind_permissions` documenta a matriz completa
- **Defense in depth real**: MCP gate + RPC gate consultam a mesma fonte; contradições impossíveis

### Negativas / Tech debt conhecida
- **83 RPCs legacy** (pós-auditoria 17/Abr) ainda usam role hardcoded. Fixar uma RPC por sessão quando tocá-la, ou em esforço dedicado.
- `can()` não resolve scope por event/tribe ainda — exige refinement adicional na RPC.
- `operational_role` (cache) ainda é usado em vários places para outras finalidades (filtros, display, sync). Manter como cache, não como fonte de autoridade.

### Bloqueio
- Teste de contract (`tests/contracts/rpc-v4-auth.test.mjs`) falhará se uma RPC SECURITY DEFINER nova for criada com auth gate sem chamar `can*`. Ver A4.5.

## RPCs refatoradas como parte deste ADR (17/Abr)

Migrations `20260424040000`, `20260424050000`, `20260424060000`:

### Event domain (3)
- `drop_event_instance(uuid, boolean)` → `manage_event` + tribe-scope
- `update_event_instance(uuid, ...)` → `manage_event` + tribe-scope
- `update_future_events_in_group(uuid, ...)` → `manage_event` + tribe-scope

### Member admin (6)
- `admin_offboard_member(uuid, text, text, text, uuid)` → `manage_member`
- `admin_reactivate_member(uuid, int, text)` → `manage_member`
- `admin_update_member(uuid, ...)` → `manage_member`
- `admin_update_member_audited(uuid, jsonb)` → `manage_member`
- `promote_to_leader_track(uuid, boolean)` → `promote`
- `manage_selection_committee(uuid, text, uuid, text)` → `promote`
- DROP `admin_reactivate_member(uuid)` overload legacy (sem auth gate)

### PII reads (3)
- `admin_get_member_details(uuid)` → `view_pii`
- `admin_list_members_with_pii(int)` → `view_pii`
- `export_audit_log_csv(text, text, text)` → `view_pii`

## Próximos passos

1. **Refatoração contínua**: cada sessão que tocar uma RPC com drift deve migrá-la (one-at-a-time)
2. **Enriquecer `can()` com scope por event**: quando escalar, resolver event-level scope dentro de `can()` em vez de scope refinement na RPC
3. **ADR-0012 (futuro)**: formalizar o padrão `can()` + `view_X_context` helpers para views sensíveis

## Referências

- ADR-0007 — V4 Authority source of truth (cutover 13/Abr)
- `DOMAIN_MODEL_V4_MASTER.md` — histórico completo do refactor
- `engagement_kind_permissions` — matriz seeded de `kind × role × action × scope`
- Migrations `20260424040000` → `20260424060000` — refactor das 12 RPCs
