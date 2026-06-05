# p202 Volunteer Lifecycle Remediation Spec

**Data:** 2026-05-19  
**Status:** Spec de execução / pronto para fatiar por issue  
**Origem:** Auditoria p201/p202 do fluxo seleção -> onboarding -> termo -> autoridade -> offboarding

---

## 1. Objetivo

Eliminar estados parciais no ciclo do voluntário. O sistema deve ter um caminho canônico para converter candidato aprovado em membro V4 autoritativo, com identidade, engagement, termo, comunicação, audit log e MCP alinhados.

Escopo operacional imediato:

- GitHub #179 — aprovação canônica do ciclo do voluntário.
- GitHub #180 — garantir entrada no grafo V4 autoritativo.
- GitHub #181 — prova de contra-assinatura e evidências do termo.
- GitHub #182 — matriz de notificações/renovações/pending-authority.
- GitHub #183 — MCP lifecycle tools após estabilizar contratos.
- GitHub #177 — emissão do termo vigente para special engagement kinds.

---

## 2. Evidência Base

Auditoria SQL read-only em produção mostrou:

| Métrica | Resultado |
|---|---:|
| Applications `approved`/`converted` | 38 |
| Approved/converted sem `members` por email | 1 |
| Approved/converted com member mas sem `person_id` | 0 |
| Active `auth_engagements.requires_agreement=true` | 52 |
| Active requires agreement sem certificado | 16 |
| Pending agreement sem notificação detectável | 2 |
| Certificados totais | 42 |
| Certificados com `counter_signed_at` | 33 |
| Coluna `counter_signature_hash` | ausente |
| Certificados com `signed_ip` ausente | 42 |
| Certificados com `signed_user_agent` ausente | 42 |

Interpretação:

- O risco de aprovação incompleta é real, mas pequeno no estado atual: 1 caso sem `member`.
- O vínculo `members.person_id` está íntegro para os membros já pareados.
- O maior backlog operacional é `agreement_certificate_id` ausente em 16 engagements ativos que exigem acordo.
- O fluxo de certificado funciona operacionalmente, mas ainda não sustenta claim forte de não-repúdio criptográfico.

---

## 3. Sequência de Rollout

### Fase 0 — Guardrails e Queries

Antes de mexer em RPCs:

1. Adicionar o pack SQL read-only `docs/audit/P202_VOLUNTEER_LIFECYCLE_SQL_AUDIT.md` ao runbook.
2. Rodar baseline antes/depois de qualquer migration.
3. Definir que `is_authoritative` não será ajustado manualmente como shortcut.
4. Definir como tratar o 1 caso `approved/converted` sem `member`: correção pontual via caminho canônico ou backfill controlado.

Gate:

- Baseline de contagens registrado no PR.
- Rollback documentado.

### Fase 1 — Certificados e Evidência (#181)

Primeiro corrigir o substrato de assinatura, porque #177 e #180 dependem dele.

Mudanças prováveis:

- Migration: adicionar `certificates.counter_signature_hash text`.
- RPC: atualizar `counter_sign_certificate(p_certificate_id uuid)` para persistir o hash.
- RPC/teste: decidir se `signed_ip` e `signed_user_agent` serão populados server-side ou explicitamente documentados como não utilizados.
- Backfill/auditoria: verificar 1 certificado com `signature_hash IS NULL` e 1 certificado histórico com `period_end='2026-06-30'`.
- `get_my_signatures()`: incluir pacote coerente de termo/certificado quando necessário para LGPD Art. 18.

Gates:

- `counter_sign_certificate()` persiste hash.
- `admin_audit_log` e notification continuam sendo gerados.
- `check_schema_invariants()` segue 16/16.
- Teste DB-aware ou static contract cobre counter-sign.

### Fase 2 — Pending Agreement Queue (#177/#180)

Criar a fila operacional que lista engagements ativos que exigem acordo e não têm certificado.

Contrato sugerido:

- View/RPC: `pending_agreement_engagements` ou `get_pending_agreement_engagements()`.
- Campos mínimos:
  - `engagement_id`
  - `person_id`
  - `member_id`
  - `kind`
  - `role`
  - `initiative_id`
  - `start_date`
  - `requires_agreement`
  - `agreement_certificate_id`
  - `notification_status`
  - `next_action`

Gates:

- Retorna os 16 casos atuais sem PII desnecessária.
- Herlon aparece como pending agreement, não como authority bug.
- Não concede capability antes de assinatura/countersign.

### Fase 3 — Approval Orchestration (#179/#180)

Unificar o contrato de aprovação.

Opção preferencial:

- Criar `approve_selection_application(p_application_id uuid, p_decision jsonb)` ou equivalente.
- Fazer `admin_update_application` e `finalize_decisions` delegarem para esse contrato, ou deprecar um deles explicitamente.

Efeitos colaterais obrigatórios:

1. Validar autoridade com `can_by_member()`.
2. Criar ou reativar `members`.
3. Garantir `persons` e `members.person_id`.
4. Criar `engagements` com `selection_application_id`.
5. Criar onboarding progress.
6. Enfileirar termo quando `requires_agreement=true`.
7. Criar notification.
8. Registrar `admin_audit_log`.

Gates:

- Aprovar candidato novo gera `member`, `person`, `engagement`, onboarding e notification.
- Aprovar candidato existente/reactivated não duplica pessoa ou engagement.
- `admin_update_application` e `finalize_decisions` têm paridade ou um deles vira wrapper/deprecated.

### Fase 4 — Lifecycle Notifications (#182)

Criar matriz de transições e comunicação.

Estados mínimos:

- `candidate`
- `approved_pending_member`
- `approved_pending_person`
- `agreement_pending`
- `countersign_pending`
- `authoritative`
- `renewal_due`
- `offboarded`
- `reengagement_pending`

Para cada estado/transição:

- tabela fonte;
- evento que dispara;
- template/campaign;
- idempotency key;
- audit log esperado;
- responsible actor;
- retry/cron owner.

Gates:

- Os 2 pending agreement sem notificação detectável entram em fila.
- Renovações e reengajamentos têm estado visível.
- Admin consegue distinguir "sem permissão" de "autoridade pendente de termo".

### Fase 5 — Semantic Layer e MCP (#166/#183)

Só depois de estabilizar RPCs:

- Criar view/RPC `volunteer_lifecycle_state` ou `get_volunteer_lifecycle_state()`.
- Adicionar MCP tools canônicas:
  - `list_pending_agreement_engagements`
  - `explain_volunteer_lifecycle_state`
  - `approve_selection_application`
  - `issue_current_agreement`
  - `counter_sign_certificate`

Gates:

- Cada tool tem `canV4()` ou gate RPC explícito.
- `tools/list` e `/health` permanecem consistentes.
- Smoke MCP não gera `mcp_usage_log.success=false`.
- Tools não expõem PII além do necessário para o papel do caller.

---

## 4. Ordem Recomendada de Issues

1. #181 — corrigir substrato de certificado/prova.
2. #177 + #180 — fila e emissão para pending agreements.
3. #179 — aprovação canônica.
4. #182 — matriz de comunicação/renovação.
5. #166 — semantic layer `volunteer_lifecycle_state`.
6. #183 — MCP tools sobre contratos estabilizados.

---

## 5. Critérios de Done do Programa

- Nenhuma aplicação `approved`/`converted` sem caminho explícito para `member`.
- Nenhum `member` aprovado com `person_id` ausente.
- Todo engagement ativo que exige acordo tem:
  - certificado vinculado; ou
  - estado pendente visível; ou
  - waiver documentado.
- Contra-assinatura persiste prova criptográfica.
- Assinatura/termo tem decisão clara sobre IP/user-agent.
- Admin UI mostra pending-authority com próxima ação.
- MCP usa contratos canônicos e não cria estado parcial.
- Release log e governance changelog atualizados antes de deploy.

