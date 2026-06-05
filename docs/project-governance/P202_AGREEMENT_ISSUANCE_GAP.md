# p202 Agreement Issuance Gap — Special Engagement Kinds

**Data:** 2026-05-19  
**Status:** Diagnóstico / decisão pendente  
**Origem:** Investigação #160 Herlon authority state
**Spec correlata:** `docs/project-governance/P202_VOLUNTEER_LIFECYCLE_REMEDIATION_SPEC.md`
**SQL audit pack:** `docs/audit/P202_VOLUNTEER_LIFECYCLE_SQL_AUDIT.md`

---

## 1. Problema

Herlon Alves tem engagement ativo `study_group_owner / leader` em CPMAI, mas não recebe capacidades V4 porque o engagement exige acordo e ainda não possui `agreement_certificate_id`.

Investigação p202 mostrou que o problema não é apenas individual: o batch anterior de emissão/admin attestation cobriu principalmente `engagement_kind='volunteer'`, deixando special engagement kinds sem termo/certificado.

---

## 2. Evidência

### Herlon

- `engagements`: `study_group_owner / leader`, status `active`, initiative `Preparatório CPMAI — Ciclo 3 (2026)`.
- `auth_engagements`: `requires_agreement=true`, `agreement_certificate_id=NULL`, `is_authoritative=false`.
- `get_caller_capabilities()`: `org_actions=[]`, `tribe_actions={}`, `initiative_actions={}`.
- `certificates`: 0 rows para Herlon.
- `notifications`: nenhuma notificação de termo/acordo para ele.
- `admin_audit_log`: nenhuma ação relacionada a cert/agreement para ele.

### Escopo sistêmico

Special kinds com backlog aproximado de engagements ativos sem certificado/termo:

- `chapter_board / board_member`
- `ambassador`
- `workgroup_member / researcher`
- `observer / observer`
- `sponsor / sponsor`
- `chapter_board / liaison`
- `committee_*`
- `study_group_owner / leader`

`volunteer / researcher`, `volunteer / leader` e `volunteer / co_gp` já estavam cobertos pelo fluxo anterior.

### Refinamento SQL — 2026-05-19

Consulta read-only em produção refinou o backlog que realmente bloqueia autoridade por `auth_engagements.requires_agreement=true AND agreement_certificate_id IS NULL`:

- total active requires agreement: 52
- active requires agreement sem certificado: 16
- pendências por kind/role:
  - `ambassador / ambassador`: 6
  - `ambassador / founder`: 6
  - `study_group_owner / leader`: 1
  - `study_group_participant / participant`: 1
  - `volunteer / coordinator`: 1
  - `volunteer / manager`: 1
- cobertura de notificação detectável: 14/16 com notificação relacionada a termo/agreement/certificate; 2/16 sem notificação detectável.

O backlog anterior por special kinds continua útil como hipótese de auditoria ampla, mas o recorte acima é o queue operacional mínimo para desbloquear autoridade V4 sem shortcut manual.

---

## 3. Decisão PM

O termo vigente deve ser usado agora. Termos/documentos em revisão não bloqueiam assinatura do termo atual.

Fluxo esperado:

1. Emitir/viabilizar assinatura do termo vigente.
2. Membro assina.
3. GP/diretor countersigna quando aplicável.
4. `agreement_certificate_id` passa a existir.
5. `auth_engagements.is_authoritative=true`.

Quando novo termo for aprovado:

- quem assinou o atual assina adendo ou nova versão, conforme regra;
- quem ainda não assinou assina diretamente a versão vigente nova.

---

## 4. Opções de Correção

### Opção A — Corrigir emissão para special kinds

Criar fluxo que detecta active engagements `requires_agreement=true` sem `agreement_certificate_id` e emite termo vigente para cada membro.

**Prós:** preserva governança atual.  
**Contras:** exige cuidado com duplicação, notificações e tipos de termo.

### Opção B — Ajustar `requires_agreement`

Revisar se todos os special kinds realmente exigem termo formal.

**Prós:** reduz fricção.  
**Contras:** decisão jurídica/governança; pode enfraquecer compliance.

### Opção C — Estado pendente explícito

Manter `is_authoritative=false`, mas exibir UX "autoridade pendente de assinatura" para GP/membro.

**Prós:** transparente e seguro.  
**Contras:** não resolve authority até assinatura.

---

## 5. Recomendação

Combinar A + C:

1. Criar backlog e tela/listagem de `pending_agreement_engagements`.
2. Emitir termos vigentes para special kinds elegíveis.
3. Mostrar status "pendente de termo" em perfil/admin quando há engagement ativo sem autoridade.
4. Não dar shortcut manual em `is_authoritative`.

---

## 6. Critérios de Done

- Query/relatório lista todos engagements ativos que exigem acordo e não têm certificado.
- Fluxo emite termo vigente para special kinds sem duplicar certificados existentes.
- Notificação é criada.
- Membro consegue assinar.
- GP consegue countersign.
- `auth_engagements.is_authoritative` muda via fluxo normal.
- Herlon recebe autoridade esperada só após assinatura/countersign.
- Release log e governance changelog documentados.

---

## 7. Dependências de Auditabilidade

A expansão da emissão para special engagement kinds deve considerar os achados da auditoria de certificados:

- `counter_signature_hash` precisa ser persistido no certificado, não apenas retornado pela RPC de contra-assinatura.
- `signed_ip` e `signed_user_agent` existem no schema, mas devem ser populados por um caminho server-side seguro ou documentados como não utilizados.
- `period_end` já é derivado pela função live a partir de VEP/ciclo/histórico; há 1 certificado histórico com `period_end='2026-06-30'` que deve ser auditado/backfilled se necessário.
- `get_my_signatures()` deve expor um pacote coerente para consulta do membro e export LGPD Art. 18.

Esses pontos não bloqueiam a emissão operacional do termo vigente para Herlon, mas são ship gates antes de qualquer claim formal de não-repúdio criptográfico completo.

---

## 8. Issues

- GitHub #160 — Herlon authority state.
- GitHub #177 — emissão do termo vigente para special engagement kinds.
- GitHub #181 / P162 #50 — `counter_signature_hash` computado mas não persistido.
- GitHub #181 / P162 #51 — evidências do Termo incompletas (`signed_ip`, `signed_user_agent`, `period_end`).
