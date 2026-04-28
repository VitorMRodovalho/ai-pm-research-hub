# ADR-0060: Welcome email automatizado em engagements INSERT (#97 G7)

| Field | Value |
|---|---|
| Status | Accepted |
| Date | 2026-04-28 (sessão p74, council Tier 3) |
| Author | Vitor Maia Rodovalho (Assisted-By: Claude + 4-agent council) |
| Migration | `20260514310000_adr_0060_g7_engagement_welcome_email_trigger.sql` |
| Issue | #97 G7 (LATAM LIM 2026 → escalável para todos congressos/iniciativas) |
| Cross-ref | ADR-0022 (delivery_mode), ADR-0007 (V4 authority), council synthesis 2026-04-28 |

## Context

Council Tier 3 review (4 agents): 3 de 4 convergiram em "ship G7 esta semana, isolado".
- **product-leader**: G7 isolado = quick win imediato, padrão escalável
- **c-level-advisor**: G7 hygiene + costs nada (substrate ready)
- **startup-advisor**: G7 sim, mas W2/G4 só com sinal de 2º congresso

Audit runtime confirmado em sessão p74: nenhum trigger de welcome existia. Roberto, Ivan, Vitor, Fabricio, Sarah todos foram adicionados ao LATAM LIM como engagements sem nenhuma notificação automática.

Substrate técnico já pronto:
- `pg_net` extension instalada
- `send-notification-email` Edge Function ativa (cron 5min)
- `notifications` table com `delivery_mode`, `digest_delivered_at`, `digest_batch_id` (ADR-0022 W1)
- Pattern idêntico a `v4_notify_expiring_engagements` (inverter polaridade: expire → welcome)

## Decision

Implementar trigger AFTER INSERT em `engagements` que enfileira welcome notification por `engagement_kind`.

### Helper SECDEF

`_enqueue_engagement_welcome(p_engagement_id uuid) RETURNS void`:
- Resolve member_id via persons (guard: skip se ghost/sem member)
- Resolve initiative title + kind
- CASE por engagement_kind: subject + body customizados
- INSERT em `notifications` com `delivery_mode='transactional_immediate'` (welcome time-sensitive)
- Default branch: skip silenciosamente para kinds não-mapeados (anti-noise guard)

### Templates por kind (8 mapeados)

| Kind | Subject | Body highlights |
|---|---|---|
| `speaker` | "Bem-vindo(a) como speaker em <iniciativa>" | Termo de Speaker chega em etapa dedicada — NÃO bundled |
| `volunteer` | "Bem-vindo(a) ao <iniciativa>" | Termo de Voluntariado em breve |
| `study_group_owner` | "Você é owner de <study group>" | Pode convocar participantes, agendar, emitir certificado |
| `study_group_participant` | "Bem-vindo(a) ao grupo <de estudo>" | Cronograma + materiais na página |
| `observer` | "Você está listado como observer" | Acesso de leitura |
| `committee_coordinator/member` | "Bem-vindo(a) ao comitê" | Responsabilidades + agenda |
| `workgroup_coordinator/member` | "Bem-vindo(a) ao workgroup" | Tarefas + próximos passos |

Outros kinds: skip silencioso.

### Trigger

`AFTER INSERT ON engagements WHERE NEW.status = 'active'` → `_enqueue_engagement_welcome(NEW.id)`.

Guard `status='active'` evita disparar em pre-engagements ou drafts.

## Critical legal constraint (legal-counsel)

**Welcome email NUNCA bundled com cessão de direitos autorais**. Razão:
- LDA Art. 50: cessão por escrito presume-se onerosa, mas click-to-accept arguível
- LGPD Art. 8º: bundling de cessão + consent LGPD invalida (vício de consentimento)

Padrão aplicado em todos templates speaker/volunteer:
> "Antes da [próxima etapa], você receberá o Termo de [Speaker/Voluntariado] em etapa dedicada para leitura e assinatura."

Cessão real continua via fluxo separado (`requires_agreement=true` em engagement_kinds + workflow de assinatura distinto).

## Consequences

**Positive:**
- Cada engagement INSERT futuro herda welcome automaticamente
- Padrão escalável: novo congresso/study_group/workgroup → zero código adicional
- ADR-0022 substrate finalmente exercitado em produção real
- Compliance UX: member sabe imediatamente o que aceitou

**Neutral:**
- Templates inline na função (não em table) — refactor possível futuro se templates crescerem
- Skip silencioso para kinds não-mapeados pode esconder bugs (mitigação: log_pii_access ou MCP tool de auditoria depois)

**Negative:**
- Performance: cada engagement INSERT agora dispara helper SECDEF + INSERT em notifications. Latência estimada <50ms (não-blocking real-time path).

## Smoke test plan

PM owner valida no próximo engagement criado (CPMAI participant ou similar):
1. INSERT em engagements com kind='study_group_participant', status='active'
2. Verificar row em notifications com type='engagement_welcome'
3. Aguardar cron `send-notification-email` (5min)
4. Confirmar delivery via Resend logs

## Verification

- [x] Migration applied (`20260514310000`)
- [x] Helper SECDEF + trigger criados
- [x] Schema invariants 11/11 = 0
- [x] Tests preserved (1418/1383/0/35)
- [ ] Post-deploy smoke (PM owner): primeiro engagement INSERT pós-deploy

## Pattern sedimented

33. **Welcome notification trigger pattern**: AFTER INSERT trigger ON engagement-shaped tables → enqueue notification with per-kind template. Default branch skips silenciously (guard contra noise para kinds não-mapeados). Status='active' guard previne pre/draft INSERTs. Templates inline aceitáveis até crescerem (>10 kinds → migrar para table).

## References

- Issue #97 G7
- Council synthesis: `docs/council/decisions/2026-04-28-tier-3-issues-87-88-97-synthesis.md`
- ADR-0022 (delivery_mode substrate)
- LGPD Art. 7º (bases legais), Art. 8º (consent específico)
- LDA Art. 50 (cessão por escrito)
- legal-counsel parecer 002/2026 (LATAM LIM IP)

Assisted-By: Claude (Anthropic) + council 4-agent Tier 3
