# Decision: Drive auto-revoke no offboard — alumni-only, auto-with-exception-review (#1039)

**Date:** 2026-07-02
**Status:** Accepted
**Context:** #1026 Fatia B (follow-up governado das Fatias A+C, PRs #1035/#1036). O ADR-0107 fixou
aprovação manual do GP como gate deliberado da revogação de Drive; era holding constraint (role do SA
pendente + caminho nunca executado), não política permanente. Ambos os motivos fecharam: elevação do
SA feita e pipeline com 10/10 revogações zero-erro no cohort de 27 desligados (grounded ao vivo
2026-07-02). Automatizar a aprovação exigia: amendment do ADR-0107, amendment do invariante AL
(revoked ⇒ approved_by), parecer LGPD e decisão de re-grant na reativação.
**Council members consulted:** legal-counsel, security-engineer, data-architect,
accountability-advisor (Tier-3, mandato do PM no #1039) — 4× APPROVE_WITH_CONDITIONS, zero blockers.
Review completo: `docs/council/2026-07-02-1039-fatia-b-auto-revoke-tier3.md`.
**Decider:** PM Vitor Maia Rodovalho, 2026-07-02, via gate na sessão (AskUserQuestion) — ratificação
registrada no ADR-0107 Amendment 1.
**Path impact (Trentim A/B/C):** neutro — higiene de dados de alumni (LGPD Art. 16); não move A/B/C.

## Recommendation

1. **Auto-approve alumni-only**: RPC service-role `auto_approve_alumni_drive_revocations` chamado
   pelo EF de detecção pós-upsert; flip set-based `pending_revoke→approved` com
   `approval_mode='auto'` (`approved_by` fica NULL — a coluna é a proveniência), filtro
   `member_status='alumni' AND offboarded_at IS NOT NULL` avaliado no UPDATE. Cron 64 (drain horário)
   executa a revogação em ≤1h sem mudanças. `inactive` permanece 100% manual (reversível by design —
   ADR-0071 Amd 3-D / ADR-0116).
2. **Kill-switch ships dark**: `site_config['drive_auto_revoke_enabled']='false'::jsonb`, NULL-safe
   fail-closed, write superadmin-only. Go-live = checklist OPS auditado no runbook (UPDATE + INSERT
   `admin_audit_log site_config_changed`), gated em: comms ao titular (Privacy Notice §6 + runbook C3
   — FEITO nesta sessão) e issue de retenção PII 5y filado.
3. **Invariante AL emendado em lockstep** (migração `20260805000319`, full rebuild Phase C):
   cláusula 1 (revoked ⇒ revoked_at AND (approved_by OR mode auto)), 1b (auto nunca tem aprovador
   humano nem fica pendente), 1c (skipped ⇒ skip_reason), cláusula 2 inalterada.
4. **Reactivation queue-clear**: `admin_reactivate_member` cancela linhas abertas →
   `skipped/member_reactivated` ANTES de limpar `offboarded_at` (fecha gap pré-existente da cláusula
   2; o drain jamais revoga membro reativado).
5. **NO auto re-grant na reativação**: fundamento = minimização (Art. 6 III) — re-conceder um
   conjunto histórico de pastas seria over-grant com escopo obsoleto; re-grant é passo manual do GP
   contextual ao NOVO engajamento (drill-down do painel mostra o que foi revogado).
6. **`skip_reason` estrutural** (`owner_permission` | `member_reactivated`, CHECK) — convergência
   legal COND-2 + data-arch MF-4; texto livre não é evidência de auditoria.

## Alternatives considered

- **Sentinel "system member" como approved_by** — manteria o AL intacto mas fabricaria uma linha em
  members e mentiria no audit trail (QUEM em vez de MODO). Rejeitado.
- **Auto-approve dentro do upsert / trigger AFTER INSERT** — N+1 e mistura de contratos; trigger
  dispararia nos refreshes do ON CONFLICT e é magia oculta em tabela de auditoria com writer único.
  Rejeitados a favor do RPC set-based explícito e testável.
- **Status novo `cancelled` para reativação** — semanticamente mais limpo, mas churn de CHECK +
  overview reader + island + 3 dicts + testes; `skipped` + `skip_reason` estrutural cobre com massa
  mínima. Rejeitado (council data-arch de acordo, com as 3 condições de disambiguação incorporadas).
- **Incluir `inactive` no auto-revoke** — strand de membros diretamente reativáveis sem janela de
  intervenção. Rejeitado (é o núcleo da política alumni-only).
- **Nascer ligado** — contra ADR-0116 (automação perigosa nasce dark) e contra as condições do
  legal. Rejeitado pelo PM no gate.

## Consequences

- Para alumni, o dever do Art. 16 fecha em ≤1h do desligamento sem depender de memória/ação do GP
  (a lacuna de dias/semanas do modelo manual era o risco real de compliance).
- Fila mista exige leitura de proveniência: painel e list RPC agora expõem `approval_mode` e
  `skip_reason`; o registro de autorização (`drive_revocation_auto_approved`) carrega os `audit_ids`.
- GP não pausa o auto-revoke (site_config é superadmin-only) — escalar ao PM; escape-hatch por linha
  é follow-up.
- Edge documentado: reativação × drain em janela de µs pode deixar `skipped` com permissão de fato
  deletada — diagnóstico via `admin_audit_log`; a correção é o re-grant manual do runbook.
- Constraint futura: expansão multi-capítulo exige SA por capítulo ou filtro de escopo ANTES de
  habilitar fora do PMI-GO (registrado no Amendment).

## Next steps

1. ~~Migração `20260805000319` + EF + painel + testes + docs~~ (este PR).
2. **Go-live flip** (PM, superadmin): checklist no runbook `DRIVE_OFFBOARDING_CASCADE.md` — após
   confirmar Privacy Notice §6 em produção. Pré-requisitos COND-1 (comms) atendidos nesta sessão;
   COND-3 (issue de retenção) filado.
3. Follow-ups filados: **#1054** retenção PII 5y + ROPA + DPO (gate de go-live); **#1055**
   notificação de cortesia ao ex-membro; **#1056** `set_site_config` governado + `unapprove`
   escape-hatch.

---

**Assisted-By:** Claude (Anthropic)
