# ADR-0121 — Interim leader grant: autoridade de líder antes da assinatura do termo

**Status:** Accepted (2026-07-05) — exceção de governança autorizada pelo owner
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
