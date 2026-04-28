# ADR-0061: Initiative invitation flow + scope-bound permissions (#88 Foundation)

| Field | Value |
|---|---|
| Status | Accepted (foundation; MCP tools deferred to next session) |
| Date | 2026-04-28 (sessão p74, council Tier 3) |
| Author | Vitor Maia Rodovalho (Assisted-By: Claude + 4-agent council) |
| Migration | `20260514320000_adr_0061_initiative_invitations_foundation.sql` |
| Issue | #88 (convocação iniciativas) |
| Cross-ref | ADR-0007 (V4 authority), ADR-0006 (engagement model), council synthesis 2026-04-28 |

## Context

Council Tier 3 (4 agents — product-leader, ux-leader, ai-engineer, accountability-advisor) divergiu em sequenciamento mas convergiu nos prerequisites:

- **product-leader**: Comms-first (impacto operacional)
- **ux-leader**: Authority-first — sem `manage_initiative` action no V4 catalog, tools = cosmético
- **accountability-advisor**: 4 BLOCKING items antes de QUALQUER tool (invitations table, pii_access_log, ADR formal, second-level approval CPMAI)

Síntese: foundation primeiro, tools depois. Esta migration entrega a foundation; MCP tools (invite_to_initiative + accept/decline + list_my_invitations + list_open_initiatives) ficam para próxima sessão com base sólida.

## Decision

### Components shipped

1. **Table `initiative_invitations`**: rastreabilidade auditável de cada convite (PMI Code Section 4 Accountability)
   - Required: `kind_scope`, `message` (CHECK length≥50)
   - Lifecycle: `pending` → `accepted | declined | expired | revoked`
   - Default `expires_at = now() + 72 hours` (ux R2)
   - `reviewed_by` + `reviewed_at` para second-level approval (CPMAI cobrança scenario per accountability-advisor)
   - 3 RLS policies: invitee read own, inviter read own, admin read all
   - Mutations via SECDEF RPCs only (no PERMISSIVE INSERT/UPDATE/DELETE)

2. **`initiatives.join_policy` enum** (`invite_only` | `request_to_join` | `open`):
   - Default `invite_only`
   - Backfill: `study_group` → `request_to_join` (Notion-style, 30+ candidates expected)
   - workgroup/committee mantêm `invite_only` (curated team, governance compliance)

3. **`engagement_kinds.created_by_role` expansão**:
   - `workgroup_member.created_by_role` agora inclui 'coordinator' (workgroup_coordinator pode convidar workgroup_member)
   - `committee_member.created_by_role` agora inclui 'coordinator' (committee_coordinator pode convidar committee_member)
   - Fecha gap onde schema permitia owner mas role coordinator não estava listado

4. **Helper `expire_stale_initiative_invitations()`**: SECDEF callable via cron, marca pending past expires_at como expired

5. **`updated_at` trigger** para audit

### NOT shipped (deferred next session)

MCP tools (4 ferramentas):
- `invite_to_initiative(initiative_id, member_ids[], kind_scope, message)` — batch (ux R4)
- `accept_initiative_invite(invite_id, optional_note)`
- `decline_initiative_invite(invite_id, reason)`
- `list_my_initiative_invitations(status_filter)`

Plus opcional `request_to_join_initiative(initiative_id, message)` quando join_policy='request_to_join'.

### Audit trail completeness

Per accountability advisor BLOCKING items:

| Item | Status |
|---|---|
| `invitations` table com expires_at, revoked_at, kind_scope | ✅ DONE |
| ADR formal documentando delegação | ✅ DONE (this) |
| Second-level approval (`reviewed_by`) para CPMAI cobrança | ✅ DONE (column exists; RPC layer enforces in next commit) |
| `pii_access_log` integration quando admin lista candidatos | ⏳ deferred (will integrate in MCP tools commit) |

## Consequences

**Positive:**
- Foundation completa: sem premature optimization. Invitations table não bloqueia operação atual (members atuais já estão active).
- Multi-tenant ready: `join_policy` permite diferenciar comportamento por iniciativa
- PMI compliance: audit trail (who invited whom, when, with what message) resiste a auditor PMI Latam pedindo "como X entrou na iniciativa"
- ux R5 enforced via DB constraint (`message length >= 50`) — não depende de frontend para qualidade
- LGPD-friendly: invitations não-aceitas com PII expurgáveis pós `expires_at + 90d` via cron futuro

**Neutral:**
- Bug original `manage_initiative_engagement` enforcement: já parcialmente fixado em sessão anterior (verificado: `study_group_participant.created_by_role` inclui 'owner'). Esta migration completa a expansão para workgroup/committee
- Membros atuais (3 comms, owner CPMAI) seguem operacionais sem invitation — apenas novos convites passam por flow

**Negative:**
- Frontend ainda não consome — owners precisam aguardar MCP tools / UI para usar
- pii_access_log integration deferida — accountability flag mas não BLOCKING per se (será cumprido em commit subsequent)

## Path impact (Trentim)

- **Path A (PMI internal)**: invitations table + audit trail → demonstrável em audit PMI Latam. Reduz exposure do presidente de capítulo parceiro
- **Path B (consulting)**: invitations + join_policy = product feature transferível para outras associações
- **Path C (community)**: `request_to_join` em study_groups destrava self-service organic growth

## Pattern sedimented

34. **Foundation-first invitation pattern**: para qualquer flow de invitation/membership delegation, fundar com (a) audit trail table + RLS + SECDEF mutations only, (b) policy enum on parent resource (join_policy), (c) extend created_by_role no catalog antes de buildar tools. Invitations rendering em UI/MCP consome a foundation; foundation sobrevive a refactors de UX.

## Verification

- [x] Migration applied (`20260514320000`)
- [x] Schema invariants 11/11 = 0
- [x] Tests preserved (1418/1383/0/35)
- [x] Existing manage_initiative_engagement permission check inalterado (não regrediu)
- [x] join_policy backfill: study_groups → 'request_to_join' (verificar manualmente se necessário)
- [ ] Post-deploy: PM cria invitation manualmente via SQL para validar shape
- [ ] Próxima sessão: MCP tools commit + pii_access_log integration

## References

- Issue #88
- Council synthesis: `docs/council/decisions/2026-04-28-tier-3-issues-87-88-97-synthesis.md`
- ADR-0007 (V4 authority)
- ADR-0006 (engagement model)
- PMI Code of Ethics Sec. 4 (Accountability)
- ux-leader recommendations R1-R7 (Notion-style request-to-join, message obrigatório, batch invite)
- accountability-advisor BLOCKING items (audit trail, second-level approval)

Assisted-By: Claude (Anthropic) + council 4-agent Tier 3
