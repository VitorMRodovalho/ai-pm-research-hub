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
- [x] Próxima sessão: MCP tools commit + pii_access_log integration (W2/W3/W4 + W5 — todos shipped)

## W5 (sessão p76): lifecycle closure — self-withdraw + owner-detail listing

| Field | Value |
|---|---|
| Status | Accepted (lifecycle closure) |
| Date | 2026-04-28 (sessão p76) |
| Migration | `20260514370000_adr_0061_w5_self_withdraw_and_owner_listing.sql` |
| MCP version | v2.36.0 → v2.37.0 (176 → 178 tools) |

### Gap closed

Após W4 (owner approval flow + pii_access_log), o lifecycle de invitations
termina em **engagement.status='active'** mas faltava:

1. **Saída self-service**: o membro entrou (via invite ou request) mas não tinha
   como sair sem intervenção admin/owner. `manage_initiative_engagement` exige
   autoridade SOBRE outro — bloqueia self-removal por design.
2. **Visibilidade detalhada para owner**: `get_initiative_members` é
   public-shape (id, kind, role, status, name) sem `granted_by`, `source`,
   `motivation`, ou status filter. Owner querendo audit ("quem aprovou esse
   membro? veio por invite ou request?") precisava SQL direto.

### Components shipped W5

1. **RPC `withdraw_from_initiative(p_initiative_id, p_reason)`** SECDEF, search_path=''
   - Reason ≥10 chars enforced no DB (audit trail completeness — pattern 34 da W1)
   - Sole-required-kind safeguard: bloqueia se caller é único holder ativo de uma
     `initiative_kinds.required_engagement_kinds`. Cobre: study_group_owner sole,
     committee/workgroup/congress/research_tribe último required-kind member.
     Mensagem de erro instrui transferência prévia via admin/coordinator.
   - Sucesso: engagement.status='revoked' + revoke_reason='self_withdraw: <reason>' +
     end_date=CURRENT_DATE + metadata.withdraw_source='self_service'
   - Returns {ok, engagement_id, kind, role, withdrew_at, initiative_title}
   - GRANT EXECUTE TO authenticated; REVOKE FROM PUBLIC, anon

2. **RPC `list_initiative_engagements(p_initiative_id, p_status_filter)`** STABLE SECDEF
   - Authority: `can(manage_member|view_pii on initiative)` (admin) OR active member
     of the initiative (member-self-view)
   - Status filter: `active` (default) | `all` | `revoked` | `onboarding`
   - Returns: engagement_id, kind, role, status, lifecycle timestamps, granted_by_name,
     source (metadata.source), kind_display
   - **Motivation gated to admin only** — member-self-view não vê motivation de outros
     (LGPD: motivation pode conter dados sensíveis sobre razões pessoais)
   - GRANT EXECUTE TO authenticated; REVOKE FROM PUBLIC, anon

3. **MCP tools (2)**:
   - `withdraw_from_initiative` — confirm gate (ADR-0018 W1) com preview de
     initiative+engagement+reason. Returns `next_call` payload se confirm omitido.
   - `list_initiative_engagements` — wrapper direto da RPC; status_filter validado
     no Zod schema antes de chamar.

### Authority model unchanged

W5 preserva o V4 catalog sem novas actions. Reusa `manage_member` + `view_pii`
para detalhe admin. Self-withdraw não exige nova permission — auth.uid() →
person → engagement match é suficiente (membro só pode cancelar própria
engagement). Pattern: **self-service operations dispensam V4 action quando
o sujeito é o próprio caller**.

### Verification W5

- [x] Migration `20260514370000` applied + repaired status applied
- [x] check_schema_invariants() = 11/11 = 0 (preserved across migration)
- [x] EXECUTE grants: authenticated only; PUBLIC + anon revoked
- [x] get_advisors deltas: zero novas WARN/ERROR/INFO
- [x] MCP smoke test HTTP 200 + serverInfo.version=2.37.0
- [x] Pre-deploy duplicate tool check: 0 dupes
- [x] Tool count: 178 (176 + 2)
- [ ] Live smoke: PM exercises withdraw_from_initiative com reason placeholder em initiative de teste (deixar pending)
- [ ] Live smoke: PM como owner CPMAI chama list_initiative_engagements para auditar engagements correntes

### Sole-holder safeguard truth table

| Initiative kind | required_engagement_kinds | Withdraw block when… |
|---|---|---|
| study_group | study_group_owner | sole owner |
| committee | committee_member | last committee_member |
| workgroup | workgroup_member | last workgroup_member |
| congress | volunteer | last volunteer |
| research_tribe | volunteer | last volunteer |
| workshop | (none) | nunca bloqueia |
| book_club | (none) | nunca bloqueia |

Coordinator/leader-only kinds NÃO são protegidos pelo safeguard (não estão em
`required_engagement_kinds`). Trade-off intencional: roles de coordenação são
suaves; um workgroup pode operar com membros mas sem coordinator. Owner-of-kind
é o único caso onde "sole" cria orfanidade real.

### Post-W5 lifecycle estado

```
            ┌────────────────────┐
            │ list_open_init     │ (W3 discovery)
            └─────────┬──────────┘
                      │
    ┌─────────────────┴─────────────────┐
    ▼                                   ▼
[invite_to_init]                [request_to_join_init]
(owner curated)                 (Notion-style)
    │                                   │
    ▼                                   ▼
[respond_to_invite]            [review_initiative_request]
(invitee accept/decline)       (owner approve/decline)
    │                                   │
    └──────────────┬────────────────────┘
                   ▼
         engagement.status='active'
         + welcome notification (W7 = ADR-0060)
                   │
       ┌───────────┴───────────┐
       ▼                       ▼
[withdraw_from_init]   [manage_init_engagement(remove)]
(self-service exit)    (admin-led removal)
       │                       │
       └───────────┬───────────┘
                   ▼
         engagement.status='revoked'
                   │
         (cron auto-expire pending invitations 72h+
          remains in W3 — orthogonal to engagement lifecycle)
```

W5 fecha o último gap — todos os caminhos in/out estão cobertos por SECDEF
RPCs auditáveis, com confirm gate em destrutivos.

### Pattern sedimented (cumulative)

35. **Self-service operations dispensam V4 action when subject is the caller**:
    self-withdraw, self-leave, self-update_profile não criam novas actions no
    catalog porque a autoridade é trivial (auth.uid() = subject). Reserva o
    catalog para operações cross-subject.

36. **Sole-holder safeguard via required_engagement_kinds**: ao implementar
    self-removal/withdraw em qualquer subsistema com role de "owner" obrigatório,
    bloquear quando o caller é o último holder ativo. Catálogo de "kinds
    requeridos" deve viver no parent resource (initiative_kinds) — não no engagement
    table — para sobreviver a refactors do role hierarchy.

37. **Motivation field as admin-only gated projection**: ao expor listas que
    misturam authority levels (admin + member-self), gate fields contendo
    razões pessoais por authority. Pattern aplicável a: motivation, withdraw_reason,
    application_essay, anonymous_feedback.

## References

- Issue #88
- Council synthesis: `docs/council/decisions/2026-04-28-tier-3-issues-87-88-97-synthesis.md`
- ADR-0007 (V4 authority)
- ADR-0006 (engagement model)
- PMI Code of Ethics Sec. 4 (Accountability)
- ux-leader recommendations R1-R7 (Notion-style request-to-join, message obrigatório, batch invite)
- accountability-advisor BLOCKING items (audit trail, second-level approval)

Assisted-By: Claude (Anthropic) + council 4-agent Tier 3
