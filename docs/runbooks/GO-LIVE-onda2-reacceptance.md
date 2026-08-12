# Runbook — Go-live Onda 2 (re-aceite do Termo v9 pelos voluntários ativos)

**Audiência:** GP / Gerente de Projeto (`manage_platform`).
**Status:** DRAFT / planejamento (2026-07-07). Onda 2 é DESACOPLADA da Onda 1.
**Spec:** `docs/specs/SPEC_ONDA2_LEDGER_BACKFILL_AND_REACCEPTANCE.md`.
**Máquina:** #976 PR-4 de #571 (`open_reacceptance_obligations` e cia), migration `20260805000304`.
**Base legal:** Termo 15.3 (cascata material) · 15.4.3 (objeção) · 15.4.5 (licenças preservadas).

> **Objetivo de negócio.** Levar os voluntários **ativos que assinaram versões antigas** do Termo
> a **re-aceitar a v9** (mudança material — rodada jurídica Aaron/Angeline). A Onda 1 destravou a
> assinatura para os C4 novos; a Onda 2 fecha o círculo com quem já estava dentro.

> **O que Claude NÃO faz.** Claude não dispara o fan-out real (`p_dry_run=false`) nem envia e-mail
> aos voluntários sem go explícito do GP **e** o gate OUTWARD #334 (DPO/ANPD). Claude prepara,
> aterra ao vivo e verifica; a decisão de disparar a cascata (que pode desligar não-respondentes) é humana.

---

## 0. O bloqueador que a Onda 2 resolve primeiro (LER)

A máquina de re-aceite faz fan-out sobre `member_document_signatures` (ledger). **Esse ledger está
VAZIO** — as 48 assinaturas reais estão em `certificates`. Sem popular o ledger, o fan-out é vazio.
Por isso a Onda 2 tem uma **etapa de backfill** (§2) que a Onda 1 não tinha. Detalhe e SQL na spec.

---

## 1. Estado aterrado (re-conferir SEMPRE antes de executar — Onda 1 está viva)

```sql
-- Template ativo + change_class (esperado: v9, material)
SELECT gd.id, gd.current_version_id, dv.version_label, dv.change_class
FROM governance_documents gd JOIN document_versions dv ON dv.id=gd.current_version_id
WHERE gd.doc_type='volunteer_term_template' AND gd.status='active';

-- Ledger (fonte do fan-out) — 0 ANTES do backfill; 48 DEPOIS
SELECT count(*) AS ledger_rows FROM member_document_signatures;

-- Distribuição e alvo (ver §4 da spec para a CTE completa)
-- Esperado 2026-07-07: 40 históricos (30 active = ALVO), 8+ na v9 (excluídos)
```

Valores de referência (2026-07-07, re-aterrar):
| Fato | Valor |
|---|---|
| template ativo | v9 `246ff8be`, `change_class=material` |
| ledger | 0 linhas (bloqueio) |
| alvo Onda 2 (active + histórico) | **30** (todos com `organization_id`) |
| já na v9 (Onda 1) | 8 e subindo (excluídos) |

---

## 2. Backfill do ledger (pré-requisito — ato do GP via migration)

**Antes:** confirmar D1 (versão âncora, legal) e D2 (escopo 48 vs 30) da spec §1.

- [ ] Aplicar `supabase/migrations/<ts>_onda2_backfill_member_doc_signatures.sql` (SQL na spec §2)
      via `apply_migration`. É DML idempotente.
- [ ] Sync local + `supabase migration repair --status applied <ts>` (`feedback-apply-migration-creates-tracking-row`).
- [ ] Verificar: ledger espelha os certs, 1 corrente por membro, v9-signers apontam v9, históricos a âncora (spec §2).

---

## 3. Pré-flight da cascata

- [ ] **Onda 1 assentada.** E-mail C4 entregue, adesões v9 em curso estáveis. Não disparar Onda 2 no
      mesmo dia do go-live C4.
- [ ] **Gate OUTWARD #334 (DPO/ANPD).** SPEC_571 §208: o fan-out real (aviso-30d aos voluntários) só
      dispara com PM-OK **e** #334. Sem isto, PARAR.
- [ ] **change_class = material.** Confirmado na §1. Se fosse editorial, o caminho seria
      `notify_editorial_change_awareness` (ciência tácita, sem obrigação) — NÃO é o caso.
- [ ] **D3 (liderança).** Confirmar que GP/co-GP entram no re-aceite (assinaram versão antiga como voluntários).

---

## 4. Dry-run do fan-out (read-only — ato do GP autenticado)

`open_reacceptance_obligations` exige `auth.uid()` + `manage_platform` (não roda por service role).
O GP autenticado chama com `p_dry_run=>true`:

```sql
SELECT public.open_reacceptance_obligations(
  '280c2c56-e0e3-4b10-be68-6c731d1b4520'::uuid,   -- doc
  '246ff8be-9ed8-4a81-9211-bf097750c4c7'::uuid,   -- v9
  true);                                          -- DRY-RUN
```
- [ ] `target_count` = **30** (ou o número re-aterrado). Se vier 0 → o backfill não foi aplicado. Se
      vier 40 → D2 ficou em (a) sem filtro active; decidir antes do run real.
- [ ] Conferir os nomes em `targets` contra o preview.

---

## 5. Fan-out real (ato do GP — dispara a cascata)

**Só após #334 + dry-run conferido.** Idempotente (índice parcial impede dupla obrigação).

```sql
SELECT public.open_reacceptance_obligations(
  '280c2c56-e0e3-4b10-be68-6c731d1b4520'::uuid,
  '246ff8be-9ed8-4a81-9211-bf097750c4c7'::uuid,
  false);   -- REAL: cria obrigações + aviso-30d in-app; e-mail via jobid 9
```
- [ ] `created` = alvo esperado. `admin_audit_log` action `reacceptance.obligations_opened`.
- [ ] Prazos no retorno: `effective_from` (+30d), `window_closes_at` (+15 úteis GO), `suspended_until` (+30d).

---

## 6. Ciclo e monitoramento (cron dirige; humanos respondem)

- **Membro** vê o banner/countdown via `get_my_reacceptance_obligations`; re-aceita via
  `express_reacceptance(obligation)` (permitido `in_window`, `suspended` tardio, `accommodation`).
- **Objeção fundamentada (15.4.3):** `register_reacceptance_objection` congela a cascata; Comitê
  responde em 10 úteis via `respond_reacceptance_objection` (accepted→recircula / rejected→retoma /
  accommodation→5 úteis). Acolhida ⇒ recircular o instrumento e `link_reacceptance_recirculation`.
- **Recusa expressa (15.3(e)):** `refuse_reacceptance` → desligamento imediato, licenças preservadas.
- **Lapso:** cron diário move `notified→in_window→suspended→lapsed_disengaged`; `_reacceptance_disengage`
  desliga (status `inactive`, engagements fechados) **preservando** `member_document_signatures` (15.4.5).
- [ ] Monitorar `member_reacceptance_obligations` por estado. Bounces do e-mail via `email_webhook_events`.

---

## 7. Rollback / abortar

- **Antes do fan-out real:** nada a desfazer além do backfill (que é verdade do ledger — manter).
- **Após o fan-out, antes de qualquer desligamento:** as obrigações `notified`/`in_window` podem ser
  neutralizadas marcando `state='superseded'` (ato administrativo com `manage_platform` + nota no
  audit log). NÃO deletar linhas (audit-trail).
- Desligamentos por recusa/lapso **preservam licenças** — não são reversíveis por este runbook (o
  membro retorna via re-engajamento normal, `member_status` é reversível).

---

## 8. Cross-ref
- Spec: `docs/specs/SPEC_ONDA2_LEDGER_BACKFILL_AND_REACCEPTANCE.md`
- Máquina: `docs/specs/SPEC_571_CAMADA5_MATERIAL_CHANGE.md` (§5 PR-4, §9.5, §208 gate OUTWARD)
- Onda 1: `docs/runbooks/GO-LIVE-onda1-volunteer-term.md`
- Drift das 2 representações: memory `reference-volunteer-term-signing-representation-drift`
