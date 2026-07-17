# SPEC — Onda 2 (re-aceite dos ativos): backfill do ledger + fan-out da máquina #976

**Status:** DRAFT / planejamento (2026-07-07). Nada aplicado ao banco.
**Escopo:** habilitar a Onda 2 (re-aceite do Termo v9 pelos voluntários ativos que assinaram
versões antigas), resolvendo o bloqueador do ledger vazio antes de qualquer fan-out.
**Deps:** Onda 1 ATIVADA (v9 `246ff8be` = `status='active'`, `change_class='material'`).
Máquina de estados #976 (PR-4 de #571, migration `20260805000304`) já vive DORMENTE.
**Runbook operacional:** `docs/runbooks/GO-LIVE-onda2-reacceptance.md`.
**Feridas legais:** Termo 15.3 (cascata de re-aceite) · 15.4.5 (licenças preservadas) · SPEC_571 §208 (OUTWARD-gate #334).

---

## 0. O bloqueador (aterrado ao vivo, projeto `ldrfrvwhxsmgaabwmaik`, 2026-07-07)

A máquina `open_reacceptance_obligations(doc, to_version)` faz fan-out sobre
`member_document_signatures` (`is_current=true`). **Essa tabela tem 0 linhas.** As assinaturas
reais do Termo vivem em `certificates` (`type='volunteer_agreement'`), porque
`sign_volunteer_agreement` escreve lá, nunca no ledger (drift das 2 representações —
`reference-volunteer-term-signing-representation-drift`).

**Consequência:** rodar `open_reacceptance_obligations('280c2c56…', '246ff8be…')` hoje →
fan-out **VAZIO**. A Onda 2 depende de **popular o ledger primeiro**.

Números aterrados (re-aterrar antes de executar — Onda 1 está viva, os `has_v9` sobem):

| Fato | Valor | Query |
|---|---|---|
| `member_document_signatures` | **0 linhas** | `SELECT count(*) FROM member_document_signatures` |
| certs `volunteer_agreement` | 48 membros distintos (0 fora de `members`) | ver §4 |
| históricos (pré-v9, sem `body_version_id`) | **40** (30 active, 10 inativos) | ver §4 |
| já na v9 (Onda 1) | **8 e subindo** → excluídos | ver §4 |
| conjuntos | disjuntos (40+8=48; nenhum membro tem antigo E v9) | ver §4 |
| **alvo do re-aceite (active + histórico + org≠null)** | **30** | ver §4 |
| versão âncora candidata (última pré-v9) | v2.7 `29a2d175` (lacrada 2026-05-12) | `document_versions` |

Constraints do ledger (confirmados ao vivo):
- `uq_member_doc_sigs_current` UNIQUE `(member_id, document_id) WHERE is_current` → 1 corrente por (membro,doc)
- `member_document_signatures_member_id_signed_version_id_key` UNIQUE `(member_id, signed_version_id)`
- trigger `trg_member_doc_sig_supersede_previous` AFTER INSERT WHEN `is_current=true` → auto-supersede
- `signed_version_id` é **NOT NULL** → históricos EXIGEM uma versão âncora (não podem ser NULL)

---

## 1. Decisões ABERTAS (confirmar antes de aplicar — impacto legal)

### D1 — Versão âncora dos 40 históricos
Os históricos assinaram **18/02→14/04**, mas a versão nº1 sob 280c2c56 só foi lacrada em
**18/04**. Eles assinaram o **clauseN JSON pré-versionamento** (sem pin; `content_snapshot`
só tem a chave `clauses`). Não existe `document_version` que corresponda ao que assinaram.
Como `signed_version_id` é NOT NULL, é preciso ESCOLHER uma âncora. A escolha só afeta o
`from_version_id` do audit-trail (todos os não-v9 disparam obrigação igual).

- **Recomendado:** v2.7 `29a2d175` (última pré-v9) → delta de auditoria "v2.7 → v9" = o delta
  jurídico real que a rodada Aaron/Angeline produziu.
- Alternativa: v1 `0f61a8db` (mais antiga) — "assinou a linhagem mais antiga".
- Verdade documentada: assinaram texto pré-versionamento; a âncora é uma convenção de auditoria.
- **Confirmar com legal_counsel.**

### D2 — Escopo do backfill: 48 (verdade) vs 30 (active)
`open_reacceptance_obligations` **NÃO filtra `members.is_active`** (SPEC_571 §302, por design —
para não perder ninguém). Se o backfill incluir os 40 históricos, o fan-out atinge **40** (inclui
10 inativos), não 30. Opções:
- **(a) backfill 48 (ledger = verdade) + fan-out Onda 2 restrito a active** (wrapper que filtra, ou
  aceitar que os 10 inativos recebem obrigação no-op — já estão offboarded; `_reacceptance_disengage`
  é idempotente em inativo). **Recomendado (a) com filtro explícito** para não mandar e-mail
  "re-aceite ou desligamento" a alumni.
- (b) backfill só os 30 active (ledger incompleto; se um alumnus voltar, sua assinatura não está registrada).
- **Recomendado:** (a) — backfill dos 48 para verdade do ledger; a Onda 2 obriga só os 30 active.

### D3 — Liderança na população
Os 30 incluem **GP (Vitor)** e **co-GP/curador (Fabricio Costa)** — assinaram versão antiga como
voluntários; ratificaram a v9 como curadores. Papéis distintos ⇒ re-aceitam como voluntários.
Confirmar que não há exclusão de liderança desejada.

### D4 — Wiring forward do `sign_volunteer_agreement` (§3) é PR separado
Tocar a RPC do fluxo de assinatura VIVO (Onda 1 em curso) é delicado (#648 imutabilidade). NÃO
empacotar com o backfill. PR dedicado, testado, depois que a Onda 1 assentar.

---

## 2. Backfill (DML idempotente) — NÃO aplicar até D1/D2 confirmados

> Migration file: `supabase/migrations/<timestamp>_onda2_backfill_member_doc_signatures.sql`
> (timestamp > head atual). DML puro (INSERT) — mesmo assim vai como migration + `migration repair`
> per `feedback-apply-migration-creates-tracking-row`. Aplicar via `apply_migration`.

```sql
-- Onda 2 backfill: popular member_document_signatures a partir de certificates
-- (volunteer_agreement) para a máquina de re-aceite #976 enxergar os signatários reais.
-- Idempotente (guard NOT EXISTS). 1 linha corrente por membro (conjuntos disjuntos, ledger vazio).
DO $$
DECLARE
  v_doc    uuid := '280c2c56-e0e3-4b10-be68-6c731d1b4520';  -- volunteer_term_template
  v_v9     uuid := '246ff8be-9ed8-4a81-9211-bf097750c4c7';  -- versão material vigente
  v_anchor uuid := '29a2d175-a9d7-4993-8147-3b476e4d896e';  -- D1: v2.7 (última pré-v9) — CONFIRMAR
BEGIN
  INSERT INTO public.member_document_signatures
    (member_id, document_id, signed_version_id, certificate_id, signed_at, is_current)
  SELECT DISTINCT ON (c.member_id)
    c.member_id,
    v_doc,
    CASE WHEN (c.content_snapshot->>'body_version_id') = v_v9::text THEN v_v9 ELSE v_anchor END,
    c.id,
    COALESCE((c.content_snapshot->>'signed_at')::timestamptz, c.created_at, now()),
    true
  FROM public.certificates c
  WHERE c.type = 'volunteer_agreement'
    -- D2 (a): backfill dos 48 = comentar o filtro; para (b) só-active, descomentar:
    -- AND EXISTS (SELECT 1 FROM public.members m WHERE m.id=c.member_id AND m.member_status='active')
    AND NOT EXISTS (
      SELECT 1 FROM public.member_document_signatures x
      WHERE x.member_id = c.member_id AND x.document_id = v_doc AND x.is_current)
  ORDER BY c.member_id, (c.content_snapshot->>'signed_at') DESC NULLS LAST;
END $$;
```

Pós-backfill (verificação):
```sql
-- ledger espelha os certs; v9-signers apontam v9, históricos apontam a âncora
SELECT signed_version_id::text, count(*)
FROM public.member_document_signatures WHERE document_id='280c2c56-e0e3-4b10-be68-6c731d1b4520'
GROUP BY 1;
-- 1 corrente por membro:
SELECT count(*) FILTER (WHERE is_current) AS current_rows,
       count(DISTINCT member_id) AS members FROM public.member_document_signatures;
```

---

## 3. Wiring forward (D4 — PR separado, NÃO neste ciclo)

Sem isto, todo re-aceite/adesão nova continua indo só p/ `certificates` e o ledger volta a
divergir. Em `sign_volunteer_agreement` (após gravar o certificate), adicionar INSERT no ledger:

```sql
-- dentro de sign_volunteer_agreement, após o INSERT em certificates (v_cert_id):
INSERT INTO public.member_document_signatures
  (member_id, document_id, signed_version_id, certificate_id, signed_at, is_current)
VALUES (v_member_id, v_doc_id, v_active_version_id, v_cert_id, now(), true)
ON CONFLICT DO NOTHING;  -- trigger auto-supersede cuida da versão anterior
```
Exige aterrar `v_doc_id`/`v_active_version_id` dentro da RPC (hoje ela seleciona o template
`active`). Cobrir com contract test: toda adesão nova cria 1 linha corrente no ledger.

---

## 4. Queries de aterramento (read-only — re-rodar antes de executar)

```sql
-- Distribuição + alvo (corrige a lógica ternária: body_version_id NULL ≠ false)
WITH sig AS (
  SELECT c.member_id,
         COALESCE(bool_or((c.content_snapshot->>'body_version_id')
                          = '246ff8be-9ed8-4a81-9211-bf097750c4c7'), false) AS has_v9
  FROM public.certificates c WHERE c.type='volunteer_agreement' GROUP BY c.member_id)
SELECT
  count(*) AS distinct_cert_members,
  count(*) FILTER (WHERE NOT s.has_v9) AS historical,
  count(*) FILTER (WHERE NOT s.has_v9 AND m.member_status='active') AS hist_active_target,
  count(*) FILTER (WHERE s.has_v9) AS v9_signers
FROM sig s LEFT JOIN public.members m ON m.id=s.member_id;
```

Lista nominal (PII → não commitar; rodar ao vivo): ver o `WHERE NOT has_v9 AND active` do §4 com
`m.name`. Preview de 2026-07-07 (30 membros) ficou no scratchpad da sessão, fora do repo.

---

## 5. Sequência da Onda 2 (resumo — detalhe no runbook)

1. Confirmar D1–D4 (legal_counsel em D1/D3; PM em D2).
2. Aplicar backfill (§2) via `apply_migration` + sync local + `migration repair`.
3. **Gate OUTWARD #334 (DPO/ANPD)** — SPEC_571 §208. Sem isto, não disparar fan-out real.
4. `open_reacceptance_obligations('280c2c56…','246ff8be…', p_dry_run=>true)` → conferir target = 30.
5. Idem `p_dry_run=>false` (ato do GP, `manage_platform`, autenticado) → aviso-30d in-app + e-mail (jobid 9).
6. Monitorar a cascata (30d vigência → 15 úteis janela → 30d suspensão → desligamento). UI:
   `get_my_reacceptance_obligations`. Objeção/recusa: `register_reacceptance_objection`/`refuse_reacceptance`.
7. **Timing:** só depois da Onda 1 / e-mail C4 assentarem. Não no mesmo dia do go-live.

---

## 6. Invariantes / o que NÃO fazer

- NÃO rodar `open_reacceptance_obligations(p_dry_run=false)` antes do backfill (fan-out vazio) NEM
  antes do gate #334.
- NÃO deletar/mutar linhas de `certificates` (imutáveis #648) — o backfill só LÊ delas.
- NÃO empacotar o wiring forward (§3, toca RPC viva) com o backfill.
- Desligamento por lapso/recusa **preserva** `member_document_signatures` (15.4.5) — nunca deletar.
