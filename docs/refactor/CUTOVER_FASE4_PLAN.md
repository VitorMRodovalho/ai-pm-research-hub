# Fase 4 Cutover Plan — canWrite → can() (ADR-0007)

- **Data alvo:** 2026-04-15
- **Pré-requisito:** 48h quiet window completa (shadow desde 2026-04-13)
- **Shadow validation:** 70/71 mirrors_ok=true. 1 divergência aprovada (Marcel Fleming — melhoria de segurança)

## Sumário das mudanças

### A. MCP `nucleo-mcp/index.ts`

**Substituir** as funções locais `canWrite`/`canWriteBoard` por chamadas RPC a `can_by_member()`.

#### Funções a remover (linhas 39-49)

```typescript
// REMOVER:
const WRITE_ROLES = ["manager", "deputy_manager", "tribe_leader"];
function canWrite(member) { ... }
const BOARD_ROLES = [...WRITE_ROLES, "researcher", "facilitator", "communicator"];
function canWriteBoard(member, boardTribeId) { ... }
```

#### Função substituta a adicionar

```typescript
// V4: Authority gate via engagement-derived can() (ADR-0007)
async function canV4(sb: ReturnType<typeof createClient>, memberId: string, action: string, resourceType?: string, resourceId?: string): Promise<boolean> {
  const { data, error } = await sb.rpc("can_by_member", {
    p_member_id: memberId,
    p_action: action,
    p_resource_type: resourceType || null,
    p_resource_id: resourceId || null,
  });
  if (error) return false; // fail-closed
  return data === true;
}
```

#### 14 call sites a migrar

| # | Tool | Linha | Antes | Depois |
|---|------|-------|-------|--------|
| 1 | create_board_card | 516 | `canWriteBoard(member, boardData?.tribe_id)` | `await canV4(sb, member.id, 'write_board')` |
| 2 | update_card_status | 533 | `canWriteBoard(member, cardTribeId)` | `await canV4(sb, member.id, 'write_board')` |
| 3 | create_meeting_notes | 545 | `canWrite(member)` | `await canV4(sb, member.id, 'write')` |
| 4 | register_attendance | 562 | `canWrite(member)` | `await canV4(sb, member.id, 'write')` |
| 5 | register_showcase | 575 | `canWrite(member)` | `await canV4(sb, member.id, 'write')` |
| 6 | send_notification_to_tribe | 588 | `canWrite(member)` | `await canV4(sb, member.id, 'write')` |
| 7 | create_tribe_event | 635 | `canWrite(member)` | `await canV4(sb, member.id, 'write')` |
| 8 | manage_partner | 1075 | `canWrite(member) \|\| designations...` | `await canV4(sb, member.id, 'manage_partner')` |
| 9 | drop_event_instance | 1141 | `canWrite(member)` | `await canV4(sb, member.id, 'write')` |
| 10 | update_event_instance | 1153 | `canWrite(member)` | `await canV4(sb, member.id, 'write')` |
| 11 | mark_member_excused | 1165 | `canWrite(member)` | `await canV4(sb, member.id, 'write')` |
| 12 | bulk_mark_excused | 1177 | `canWrite(member)` | `await canV4(sb, member.id, 'write')` |
| 13 | promote_to_leader_track | 1279 | `canWrite(member)` | `await canV4(sb, member.id, 'promote')` |
| 14 | nucleo-guide prompt | 83 | `WRITE_ROLES.includes(role)` | `(informational only — see notes)` |

**Notas:**
- `manage_partner` (tool 8): legado checava `canWrite || sponsor || chapter_liaison`. V4 já tem permissions para sponsor e chapter_board kinds com action `manage_partner`.
- `promote_to_leader_track` (tool 13): action `promote` já está seeded nas permissions.
- `nucleo-guide` prompt (item 14): usa `WRITE_ROLES` apenas para construir texto informativo, não para gate. Migrar para verificação via `canV4(sb, member.id, 'write')` para consistência. Alternativa: manter como informativo e migrar na Fase 7.
- Board tools: `write_board` no V4 é initiative-scoped para researchers/facilitators/communicators — `can()` já faz o match via `ae.initiative_id`. Não precisa mais passar `boardTribeId` explicitamente.

### B. Migration RLS (NÃO incluída no cutover inicial)

A migração de RLS policies para subquery em `auth_engagements` é **postergada** para depois do cutover MCP estar estável (48h+). Razão: RLS toca todas as queries, superfície de impacto muito maior. O cutover MCP pode ser testado isoladamente.

## Sequência de execução

```
1. PRE-FLIGHT (15 min)
   ├── npm test → 1077 pass / 0 fail
   ├── npx astro build → 0 erros
   ├── curl MCP smoke → HTTP 200 + serverInfo v2.9.5
   └── SQL shadow re-validation → 70/71 mirrors_ok (Marcel = divergência aprovada)

2. EDITAR index.ts (15 min)
   ├── Adicionar canV4() async function
   ├── Migrar 14 call sites (tabela acima)
   ├── Remover canWrite, canWriteBoard, WRITE_ROLES, BOARD_ROLES
   └── Ajustar nucleo-guide prompt isLeader

3. VALIDAR LOCALMENTE (10 min)
   ├── npx astro build
   ├── npm test
   └── Grep: zero referências restantes a canWrite/canWriteBoard (exceto comentários)

4. DEPLOY (5 min)
   └── supabase functions deploy nucleo-mcp --no-verify-jwt

5. SMOKE PÓS-DEPLOY (15 min)
   ├── curl MCP initialize → HTTP 200
   ├── Via Claude.ai: create_meeting_notes (write gate)
   ├── Via Claude.ai: create_board_card (write_board gate)
   ├── Via Claude.ai: get_my_profile (read — sem gate)
   └── Verificar que Marcel Fleming NÃO consegue write

6. COMMIT (5 min)
   └── Commit atômico: "feat(refactor/v4-f4): Cutover canWrite→can() no MCP (ADR-0007)"
```

## Rollback Plan

### Se o MCP quebrar pós-deploy (HTTP 500 ou tools retornando erro)

**Ação imediata (< 5 min):**

1. Reverter `index.ts` ao estado pré-cutover:
   ```bash
   git checkout HEAD~1 -- supabase/functions/nucleo-mcp/index.ts
   ```

2. Re-deploy:
   ```bash
   supabase functions deploy nucleo-mcp --no-verify-jwt
   ```

3. Smoke test:
   ```bash
   curl -sS -X POST "https://ldrfrvwhxsmgaabwmaik.supabase.co/functions/v1/nucleo-mcp/mcp" \
     -H "Content-Type: application/json" -H "Authorization: Bearer test" \
     -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"test","version":"1"}}}' \
     -w "\nHTTP:%{http_code}\n"
   ```

**O rollback NÃO requer migration SQL** — can(), can_by_member(), auth_engagements, engagement_kind_permissions continuam existindo no banco mas simplesmente não são chamados. O schema é aditivo.

### Se can_by_member() retornar false para alguém que deveria ter acesso

1. Diagnosticar com `why_denied()`:
   ```sql
   SELECT why_denied(
     (SELECT person_id FROM members WHERE name = 'NOME'),
     'ACTION'
   );
   ```

2. Se o problema for engagement com status errado:
   ```sql
   UPDATE engagements SET status = 'active'
   WHERE person_id = (SELECT person_id FROM members WHERE name = 'NOME')
     AND kind = 'volunteer';
   ```

3. Se o problema for permission faltando:
   ```sql
   INSERT INTO engagement_kind_permissions (kind, role, action, scope, description)
   VALUES ('KIND', 'ROLE', 'ACTION', 'SCOPE', 'Hotfix: missing permission');
   ```

### Se o impacto for generalizado (múltiplos membros sem acesso)

Rollback completo conforme "ação imediata" acima. Investigar offline. Não tentar fix no MCP em produção com múltiplos membros afetados.

## Divergência conhecida e aprovada

| Membro | Legado | V4 | Decisão PM |
|--------|--------|----|------------|
| Marcel Fleming | canWrite=true (tribe_leader) | can()=false (engagement expired) | **Aprovada** — Marcel solicitou desligamento, current_cycle_active=false. V4 está correto; legado era permissivo demais. |

## Impacto nos MCP hosts externos

- **Claude.ai:** Connector verificado em 2026-04-12. Se MCP responde HTTP 200 com serverInfo, tools funcionam.
- **ChatGPT:** Conector OIDC. Mesma condição.
- **Cursor/Perplexity:** Mesma condição.
- **Nenhuma ação necessária nos hosts** — mudança é server-side only.
