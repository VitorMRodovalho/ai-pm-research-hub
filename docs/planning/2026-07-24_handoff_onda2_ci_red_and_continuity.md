# Handoff — Onda 2 do arco `operational_role` (#1476): resolver CI vermelho, depois continuar

> **Instrução do owner (2026-07-23):** a **próxima sessão resolve o CI vermelho ANTES de continuar** qualquer
> outra frente. Este handoff organiza (1) o vermelho a resolver primeiro e (2) a continuidade do arco.
> **Regra da casa:** aterrar números ao vivo ANTES de recomendar; nada de recitar de memória. Merge à main é da
> sessão main. Sem em-dash em entregáveis. Trailer `Assisted-By: Claude (Anthropic)`.

---

## ESTADO (2026-07-23) — não recitar, re-aterrar

- **Onda 1 MERGEADA** (PR #1481 `f971e753`, mig 484). **Onda 2 = PR #1483 ABERTO, verde exceto o vermelho abaixo**
  (`4a8fa7d1`, mig **485**, branch `1476-wave2-operational-membership-canonical`). Migration head = `20260805000485`.
- Onda 2 entregou: junction `v_member_operational_tiers` (per-tier, engagement, multi-hat) + 8 consumidores
  org-wide/write-path via semi-join `EXISTS`. Owner decidiu **NÃO rebasear** o KPI #1437/ADR-0126 (fica 69).
  Detalhe completo em [[project-operational-role-membership-arc-1476]] e no addendum de `docs/adr/ADR-0126-*.md`.

---

## PRIORIDADE 1 — RESOLVER O CI VERMELHO (antes de qualquer outra coisa)

Rodar a suíte completa com secrets primeiro para re-confirmar o estado ao vivo:
```bash
set -a; . ./.env; set +a; export SUPABASE_URL="${SUPABASE_URL:-$PUBLIC_SUPABASE_URL}"; npm test
```

### 1a. `#630 live: confirmed tribes have seven linked weekly tribe events` — VERMELHO PERSISTENTE (dado, não código)
- **Assertion** (`tests/contracts/630-tribe-agenda-reconciliation.test.mjs:116`): cada tribo listada precisa de
  **>= 7 semanas distintas (âncora segunda-feira)** com evento `type='tribo'` na janela `2026-06-13 .. 2026-07-31`.
  Tribo 1 tem **6**, falha.
- **Fato aterrado (2026-07-23):** tribo 1 tem tribo-eventos nas semanas de 06-15, 06-22, 06-29, 07-06, 07-13, 07-20.
  **Falta a semana de 2026-07-27** (nenhum evento `tribo` da tribo 1 entre 27 e 31/07). O `expected.count` da tribo 1
  é 7; o tempo avançou e a janela agora exige a 7a semana que nunca foi agendada.
- **NÃO é regressão da Onda 2** (mig 485 não cria/altera `events` nem `tribe_meeting_slots`; é vermelho de DADO,
  idêntico em main e no branch pois ambos leem a mesma prod). **Provável também vermelho em main.**
- **Decisão para a próxima sessão (é escolha de PMO/owner, aterrar antes):**
  - (A) **Agendar** o encontro semanal faltante da tribo 1 na semana de 27/07 (se a tribo realmente se reúne essa
    semana) — cria a linha `events type='tribo'` linkada à iniciativa da tribo 1. É a correção de dado "real".
  - (B) Se a tribo 1 legitimamente NÃO se reúne essa semana (recesso), **ajustar o `expected` da tribo 1** no teste
    (ou a janela) com justificativa — como o próprio teste já faz para remarcações intra-semana (#1065/#803).
  - Confirmar com o owner qual caso é verdade antes de escrever qualquer fix. Ver também tribos irmãs na mesma
    assertion (o `expected` cobre várias tribos; re-rodar a query por-semana para cada uma).

### 1b. `detect_inactive_members dry_run=false with tx=rollback` — FLAKE TRANSITÓRIO (HTTP 522)
- Falhou 1x na suíte cheia sob carga (Cloudflare 522, origin timeout), **passou isolado** (`tests/contracts/detect-inactive-members-non-dry-run.test.mjs`, 4/4). Não é código. Re-rodar isolado para confirmar verde; se reincidir, é infra (não debugar lógica).

### Confirmar que o resto está verde (já verificado 2026-07-23, re-confirmar)
Guards que a Onda 2 tocou/depende, todos verdes após a recaptura byte-fiel: **#1437** (KPI intocado, 69), **#785**
(`_audit_secdef_initiative_reader_gates`), **Phase C** body-drift (`rpc-migration-coverage`), **#1422**, subconjunto
de 90 testes de attendance, `1476-wave2` (novo). ⚠️ **Trap se re-mexer na mig 485:** `apply_migration` DEVE ser
byte-fiel ao arquivo (comentário stripped tira a palavra "events" do corpo de `get_dropout_risk_members` e faz #785
ficar vermelho) — ver [[reference-apply-migration-comment-word-flips-text-audit]].

---

## PRIORIDADE 2 — CONTINUIDADE DO ARCO (só depois do CI verde)

1. **Mergear o PR #1483** (sessão main; este lane só preparou). Ao mergear: **fechar #1476 à mão** (usei `Refs`, não
   `Closes` — é umbrella). Confirmar deploy: worker + (nenhuma EF nova; só DB/mig já aplicada em prod).
2. **#1477 `check_my_tcv_readiness` (DEFERIDO, onda curta própria) — precisa DECISÃO DE OWNER:** é gate INVERSO de
   isenção do TCV. Fix engagement-based (isento sse NÃO tiver engagement operacional) corrige os 2 dual-hat MAS
   **muda a isenção de +45 membros** (aterrado 2026-07-23: 25 alumni + 15 guest + 5 null-role que hoje NÃO são
   isentos passariam a ser). Duas rotas para levar ao owner:
   - (A) **Carve-out cirúrgico:** manter a lista-rótulo como base e só REMOVER a isenção de quem tem engagement
     operacional (corrige só os 2 dual-hat, 0 ripple). Menos "canonical", mais seguro.
   - (B) **Isenção pura por engagement:** isento sse não-operacional (corrige os 2 + isenta os 45 alumni/guest/null,
     que é arguivelmente mais correto — alumni não deveria assinar TCV do ciclo — mas é mudança de comportamento).
   - Re-aterrar os 45 (`v_member_operational_tiers` já existe) e trazer o before/after ao owner ANTES de codar.
3. **Follow-ups vivos herdados** (não bloqueiam): #1478 (get_member_cycle_xp janela/org vs ledger), #1470 (digests
   janela-móvel), #1468 (recompute_application_status corte próprio), #1440 (rate-limit /oauth/register), #1004 (LGPD
   23 auth-sem-engagement), #1424 Fases C/D date-gated (sáb 25/07), #1403 (watch spec MCP 07-28).

## Classes do #1476 — o que fecha o umbrella
- Onda 1 (tribe-scoped) ✅ + Onda 2 (org-wide/write-path) ✅ cobrem as classes A/B/E do brief de arranque
  (`docs/planning/2026-07-24_arc_operational_role_membership.md`). **#1477 é sibling** (não bloqueia fechar #1476).
  Fechar #1476 quando o PR #1483 mergear; abrir/continuar #1477 como onda curta.

## REGRAS DA CASA (herdadas)
- DDL só via `apply_migration` **byte-fiel ao arquivo** (inclusive comentários); `Write` local; `migration repair`;
  **deletar phantom row** por versão exata; `NOTIFY pgrst`. Regenerar `database.gen.ts` se criar view/tabela.
- Teste novo nas 2 whitelists do `package.json`. `npx astro build` + `npm test` com secrets.
- Merge à main = sessão main. `Refs #1476` (umbrella). Sem em-dash. `Assisted-By: Claude (Anthropic)`.
