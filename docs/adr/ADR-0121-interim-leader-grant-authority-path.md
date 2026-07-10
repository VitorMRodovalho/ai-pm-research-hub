# ADR-0121 — Interim leader grant: autoridade de líder antes da assinatura do termo

**Status:** Accepted (2026-07-05); follow-ups 1-2 reconciliados e fechados em 2026-07-10 (ver "Reconciliação"). Exceção de governança autorizada pelo owner.
**Relacionado:** ADR-0007 (`can()`/`can_by_member()` = source of truth de autoridade) · ADR-0006 (persons + engagements modelam identidade) · ADR-0005 (initiatives primitivo, tribes bridge) · #1103 (onboarding role-scoped: `get_my_onboarding` semeia por `operational_role`) · #1116 (roster de tribos no frontend — follow-up de descoberta).
**Migration:** `20260805000341_interim_leader_grant_auth_engagements.sql`.

## Contexto

A autoridade V4 deriva de `auth_engagements.is_authoritative`, que — para engagements de `kind` com `requires_agreement=true` (ex.: `volunteer`) — exige `agreement_certificate_id IS NOT NULL`, i.e., **o termo de voluntário assinado**. O trigger `sync_operational_role_cache` lê essa view; sem cert, um líder designado (`volunteer`/`role=leader`) fica com `operational_role='researcher'` (derivado da engagement `workgroup_member` autoritativa que não exige acordo). Como `get_my_onboarding` (#1103) filtra os passos por `operational_role`, os passos de líder (`applies_to_role={tribe_leader}`) **não aparecem** — o líder vê onboarding de pesquisador.

No Ciclo 4, 5 líderes designados (Henrique/T9, Honorio/T10, João H/T11, Messias/T6, Jhonathan/T12) já aceitaram a oferta pelo site oficial do PMI, mas o **template do termo está em revisão jurídica** (bloqueio externo). O owner precisa **iniciar o onboarding de líder deles esta semana**, antes do kickoff (09/07), assumindo o risco de operarem antes do termo com cláusula de PI/LGPD assinado.

Alternativas rejeitadas: (a) forjar um `volunteer_agreement` `issued` sem assinatura — corromperia a cadeia de certificados/auditoria (verify/counter-sign) e a exposição jurídica seria pior que o risco assumido; (b) sobrescrever `members.operational_role` à mão — briga com o cache derivado (invariante A3) e o trigger reverte; (c) `requires_agreement=false` global em `volunteer` — afeta todos os voluntários.

## Decisão

**Trilho honesto e reversível de concessão interina na view `auth_engagements`.** `is_authoritative` passa a aceitar também `COALESCE((e.metadata->>'interim_grant')::boolean, false)`:

```
... AND (e.agreement_certificate_id IS NOT NULL
         OR NOT COALESCE(ek.requires_agreement, false)
         OR COALESCE((e.metadata->>'interim_grant')::boolean, false))
```

A concessão é gravada **no `metadata` da própria engagement** (não em `legal_basis`, que fica `'contract'` intacto — não-destrutivo): `interim_grant=true` + `interim_grant_by` (person_id do owner) + `interim_grant_at` + `interim_grant_reason` (texto explícito: "assinatura formal pendente"). O registro **diz a verdade** — é uma concessão administrativa interina, não uma assinatura.

Efeito: trigger recomputa → `operational_role='tribe_leader'` → onboarding de líder + autoridade (`can()`) ativos. Blast radius = exatamente as engagements com o flag (as 5).

## Reversão / ciclo de vida

- **Ao assinar o termo de verdade:** setar `agreement_certificate_id` (fluxo normal) e **remover** o flag `interim_grant` do metadata. A autoritatividade passa a vir do cert; o trilho interino deixa de ser usado por aquela engagement.
- **Para revogar a concessão:** remover o flag → engagement volta a não-autoritativa → trigger demove.

## Escopo / fora de escopo

- **No escopo:** o trilho na view + 5 concessões interinas + transição T6 (Fabricio→Messias, `leader_member_id` + engagement do Messias apontada à iniciativa T6) + criação da tribo 12 (Produtividade Aumentada, Q1) e sua iniciativa-ponte.
- **Fora (follow-up):**
  1. **Finalizar os 5 grants** quando o termo for assinado (setar cert + limpar flag). Sem isso, ficam interinos indefinidamente.
  2. **Encerrar a engagement `volunteer/leader` do Fabricio na T6** (`7e9eb067`) via offboard limpo — hoje ele mantém a engagement ativa (líder duplo de registro é o Messias via `leader_member_id`); NÃO encerrada nesta sessão para evitar cascata de revogação (Drive/board). Fabricio permanece co-GP + curador.
  3. **Roster de descoberta no frontend (#1116)** — `src/data/tribes.ts` + i18n das tribos 9/10/11/12 + troca de líder da T6; sem isso as tribos novas não listam na landing (não bloqueia onboarding/autoridade).

## Consequências

- Desacopla **início do onboarding de líder** do gargalo do termo, sem forjar assinatura e sem quebrar invariantes (baseline 0 antes e depois; A3/AG/AH/P verdes).
- Introduz uma superfície de autoridade nova (o flag) que **precisa de disciplina de ciclo de vida** — daí os follow-ups 1–2. Risco jurídico residual (líder operando pré-termo) é **exceção autorizada pelo owner**, com Angeline (legal) no loop; a revisão de segurança/legal do trilho é pós-hoc dado o bloqueio externo.
- A view é `CREATE OR REPLACE` sem mudança de colunas ⇒ RLS/consumidores inalterados exceto pela semântica de `is_authoritative`.

## Reconciliação (2026-07-10, #1117)

Auditoria ao vivo do estado dos follow-ups (queries de leitura sobre `engagements`/`selection_applications`, nenhuma escrita nesta reconciliação). Os follow-ups 1 e 2 já haviam sido resolvidos por ondas anteriores; esta seção só os formaliza e fecha.

- **Follow-up 1 (finalizar os 5 grants): RESOLVIDO.** A onda de ativação do termo + campanha de assinatura (07-08/07) percorreu o fluxo normal em todos os 5 líderes: cada engagement de líder passou a carregar `agreement_certificate_id` (cert real) e o flag `interim_grant` foi removido do metadata. Estado ao vivo em 2026-07-10: os 5 (Henrique/T9, Honorio/T10, João H/T11, Messias/T6, Jhonathan/T12) são `volunteer/leader/active` com cert presente e `metadata->>'interim_grant'` nulo. **Zero engagements no sistema retêm o flag `interim_grant`** (blast radius do trilho voltou a 0). A autoritatividade voltou a derivar do cert; o trilho interino deixou de ser exercido.
- **Follow-up 2 (encerrar a engagement `volunteer/leader` do Fabricio na T6, `7e9eb067`): RESOLVIDO.** A engagement está `expired` (revoked_at 2026-07-05, end_date 2026-07-05) e o cache `members.tribe_id`/`initiative_id` do Fabricio foi limpo no data-fix do #1217 (08/07). Não há líder duplo: Messias é o único `volunteer/leader/active` da "ROI & Portfólio" (leader de registro via `leader_member_id`). Fabricio permanece co-GP + curador (engagements `co_gp` e `committee_member` ativos, intactos).
- **Follow-up 3 (roster de descoberta no frontend, #1116): fora do escopo do #1117.** Segue como issue própria (família #1215/#1217; a página de tribo derivar o roster do primitivo em vez do cache single-slot é o fix estrutural rastreado em #1217).

**Nota de ciclo de vida (candidato a guard, não implementado aqui):** o trilho interino segue disponível para coortes futuras (ex.: líderes C5 pré-termo). A disciplina de ciclo de vida pedida acima ("Consequências", 2º bullet) hoje é manual. Um detector periódico (invariante em `check_schema_invariants`, ex.: "`interim_grant=true` junto de `agreement_certificate_id` não-nulo é contradição da regra de reversão") institucionalizaria a honestidade do flag. Deferido como follow-up de baixo custo (não bloqueia o fechamento do #1117), candidato a acoplar à fatia de invariante do #1221.
