# Brief de arranque — Onda 2 do arco `operational_role`-como-proxy (#1476/#1477)

> **Contexto:** a Onda 1 (tribe-scoped) FECHOU e MERGEOU 2026-07-23 (PR #1481 `f971e753`, mig 484).
> Esta sessão abre a Onda 2: superfícies **org-wide / write-path** que também usam `operational_role` como
> proxy de pertencimento, MAS que exigem um canonical **mais amplo** que a view de tribo — e uma **decisão
> de owner** por causa do entanglement com a métrica ratificada #1437/ADR-0126. Modelo Opus 4.8; `/effort`
> normal, `xhigh` na decisão dura. **Auditar ao vivo ANTES de recomendar; números só de tool result desta sessão.**

---

## ESTADO AO FECHAR A ONDA 1 (2026-07-23) — NÃO recitar, re-aterrar

- **Onda 1 MERGEADA + DEPLOYADA.** main na Onda 1 `f971e753`; migration head `20260805000484`.
  View canonical **`v_tribe_active_members`** viva (engagement SSOT, `security_invoker=on` + REVOKE).
  Detalhe/classificação completa (classes A-E) → `docs/planning/2026-07-24_arc_operational_role_membership.md`
  e memória [[project-operational-role-membership-arc-1476]].
- **Consults do data-architect (2×, arco #1476)** já classificaram TODAS as superfícies. Não re-classificar do
  zero; partir da tabela abaixo e re-aterrar os corpos vivos (`pg_get_functiondef`) antes de mexer.

---

## A DECISÃO QUE TRAVA A ONDA 2 (trazer ao owner PRIMEIRO, antes de código)

Várias superfícies da Onda 2 são **org-wide** (não tribo-scoped): pertencimento operacional = "tem engagement
volunteer/operacional ativo", não "está na tribo X". Isso pede um canonical **irmão** da view de tribo — algo
como `v_active_operational_members` (org-wide, por engagement). MAS esse conjunto **compete semanticamente**
com a view **`v_operational_members`** (#1437 / ADR-0126), cujo "governança vence" foi decisão **deliberada**.

**Before/after aterrado (2026-07-23, re-aterrar na sessão):**
- `v_operational_members` headline atual (label-based) = **69**.
- Membros ativos do ciclo com engagement de tribo ativo MAS excluídos do headline pelo rótulo = **2** (ambos
  `chapter_liaison` — os mesmos dual-hat da Onda 1).
- Portanto um rebase engagement-based moveria o headline **69 → 71**.

**Pergunta ao owner (AskUserQuestion, com o número acima re-aterrado):** o headline "Pesquisadores ativos"
(#1437) deve passar a contar os pesquisadores dual-hat que hoje exibem `chapter_liaison` (69→71), OU o
"governança vence" continua deliberado para essa métrica e a Onda 2 só cria o canonical amplo para as
superfícies OPERACIONAIS (dropout/cohort/seal), deixando o KPI #1437 intocado?
- Se **rebasear #1437**: exige **emenda de ADR-0126** + before/after aterrado + sign-off (é KPI publicado).
- Se **NÃO rebasear**: `v_operational_members` fica como está; a Onda 2 introduz `v_active_operational_members`
  APENAS para as funções operacionais, e documenta a divergência intencional (headline governança-vence ≠
  intervenção operacional engagement-based).
> **Recomendação a formar ao vivo:** provável "não rebasear o KPI #1437 + canonical amplo só p/ operacional" —
> o headline é métrica de composição (governança conta como stakeholder), enquanto dropout/seal são intervenção
> operacional onde apagar um pesquisador ativo é dano real. Mas CONFIRMAR com o owner, não assumir.

---

## SUPERFÍCIES DA ONDA 2 (classificação data-architect #1476 — re-aterrar corpos)

Todas são forma de **inclusão** `operational_role IN ('...researcher...')` usada como derivação de pertencimento.

| função | por que é bug | materialidade |
|---|---|---|
| **`seal_event_attendance`** | WRITE-PATH: não materializa linha de ausência p/ o multi-papel no `INSERT ... SELECT` do seal → registro de presença **permanentemente ausente** | ALTA (dado, não display) |
| `get_attendance_engagement_summary` / `get_attendance_reliability_summary` | cohort CTE exclui multi-papel; usadas DENTRO do `exec_cycle_report` per-tribo (%/at_risk) | ALTA |
| `get_dropout_risk_members` | at-risk dual-hat some da lista de intervenção — a superfície cujo propósito É pegar essa pessoa | ALTA (org-wide) |
| `get_gp_cohort_health` | base cohort ainda label-gated (já tem `is_committee` por engagement — inconsistente) | MÉDIA (org-wide) |
| `get_cycle_attendance_overview` | dual-hat some do `members[]` do overview | MÉDIA |
| `_credly_health_rows` | não flagga link Credly faltante do dual-hat | BAIXA |
| `admin_get_anomaly_report` (Rule 7 SÓ) | o meta-detector não pega essa classe de drift; só morde com `tribe_id` NULL | BAIXA |

**LEAVE (NÃO tocar):** `analytics_role_bucket` (bucketing por parâmetro, não pertencimento); `v_operational_members`
(a decisão acima). Class B da Onda 1 (get_org_chart / get_portfolio_planned_vs_actual / review_change_request /
get_admin_dashboard) já confirmada legítima.

## #1477 — `check_my_tcv_readiness` (elegibilidade ao TCV)
`operational_role IN (...)` → `role_exempt` isenta pesquisador voluntário ativo pelo rótulo. Elegibilidade ao
termo deve derivar do **engagement**, não do cache. Pode ir junto na Onda 2 (é a mesma classe) ou em onda 3
curta. Ver #1477 (labels type:bug/governance/certificates/requires-review).

---

## SEQUÊNCIA SUGERIDA
1. Re-aterrar: headline #1437 (69?), delta (2?), corpos vivos das 7 funções + confirmar person↔member 1:1 e
   0 personless nos cohorts org-wide (como na Onda 1). `SELECT version ... ORDER BY version DESC LIMIT 1` p/ head.
2. **Decisão do owner** (bloco acima) — NÃO codar antes.
3. Definir o canonical amplo (view `v_active_operational_members` ou parametrizar) — postura de segurança IGUAL à
   de tribo (`security_invoker=on` + REVOKE anon/authenticated; #1422). Consult data-architect 1× no design se
   houver dúvida de escopo (org-wide inclui engagements não-tribo?).
4. Aplicar por onda serial (write-path `seal_event_attendance` primeiro — maior materialidade). QA impersonado.
5. Se o owner aprovar rebasear #1437 → emenda ADR-0126 + atualizar `1437-operational-members-canonical-metric.test.mjs`.
6. Fechar #1476 quando A+B+E resolvidas; #1477 quando o TCV cair.

## REGRAS DA CASA (herdadas — ver Onda 1)
- DDL só via `apply_migration` byte-fiel; `Write` arquivo local; `migration repair`; **deletar phantom row**
  (timestamp REAL < sequência sintética — Gotcha 1, [[feedback-apply-migration-creates-tracking-row]]); `NOTIFY pgrst`.
- `CREATE OR REPLACE` de função compartilhada: basear no corpo VIVO (`pg_get_functiondef`), não em grep.
- Teste novo nas 2 whitelists do `package.json`. `npx astro build` + `npm test` (com secrets). **Regenerar
  `database.gen.ts`** se criar view/tabela nova (`supabase gen types typescript --project-id ldrfrvwhxsmgaabwmaik`,
  CLI pin 2.109.0) — a Onda 1 esqueceu e o gate `gen-types-drift` pegou.
- Merge à main = sessão main. Sem em-dash. Trailer `Assisted-By: Claude (Anthropic)`, nunca `Co-Authored-By`.
- `Refs #1476` (umbrella, não `Closes` — fechar à mão quando a Onda 2 completar).
