# DIA 9 (09/07/2026) — Runbook preparado (aterrado ao vivo em 04/07 ~19h UTC)

> Consolida: `CYCLE4_TURN_PLAN_2026-07.md` §4 + cards [DIA 9] do board `c4d0e444` + decisões
> supersedentes do kickoff (04/07 noite: cap 7 · **T2 ARQUIVA, D3 caiu** · **Messias→T6, sem tribo nova**).
> Todos os IDs e contagens abaixo vêm de queries ao vivo de 04/07 — **re-aterrar contagens no dia 9 antes de aplicar.**
>
> **Re-validado 04/07 19:30–19:40 UTC (sessão noite 3):** draft migration dry-run bate exato (63 C3 abertas · 0 cycle_4 · coorte=30) · invariantes 0/0 · cycle_4 is_current=false ✓ · tribos 9/10/11 ativas c/ leader_member_id setado ✓ · Messias eng `821f53c9` initiative NULL ✓ · T2 = Débora + Gerson/Guilherme/Gustavo (4 ativos; Débora sai no passo 4) ✓ · assinaturas líderes = 0 (gate 1 ainda fechado) · **PR #1101 estava BEHIND (main andou c/ #1108) → `gh pr update-branch` feito 04/07 ~19:35 UTC; CI re-rodou 9/9 VERDE ~19:45 UTC — PR pronto p/ merge no dia 9 (após o flip, passo 1→2).**

## Pré-flight (antes de começar)
- [ ] `check_schema_invariants()` = 0 (baseline 42/42=0 em 04/07)
- [ ] **Termo C4 ativo**: `governance_documents` doc_type `volunteer_term_template` — em 04/07 os 2 estavam `under_review` (C4 = `280c2c56`, v2.7). **GATE: owner ativa antes da campanha/assinaturas.**
- [ ] Líderes novos assinaram? `SELECT m.name FROM certificates c JOIN members m ON m.id=c.member_id WHERE c.type='volunteer_agreement' AND c.cycle=2026 AND c.status='issued' AND m.id IN ('2bbbe245...','c465b4ac...','f0e1bc1e...','4eb923be...','c7a9fde2...')` — alocação (passo 6) é gated na assinatura.
- [ ] PR #1101: OPEN, 9/9 verde em 04/07 — se main andou, `gh pr update-branch 1101` e esperar CI antes do passo 2.

## Ordem de execução

### 1. Flip do ciclo
`admin_manage_cycle('set_current','cycle_4')` + fechar C3: `admin_manage_cycle('update','cycle_3', ..., p_end=>'2026-07-08')`.
Row `cycle_4` já existe (criada 04/07, `is_current=false`, "Ciclo 4 (2026/2)").

### 2. Merge PR #1101 (strings C3→C4)
Só APÓS o flip. Squash, sem `--admin`. Pages auto-deploya.

### 3. Roll-forward `member_cycle_history` (migration governada — draft abaixo)
**Coorte medida 04/07: 31 continuantes** (member ativo + row cycle_3 aberta + engagement volunteer
ativo com end_date NULL ou ≥ 2026-12-01) **− Débora = 30 roll-forward**. As 63 rows cycle_3 estão
TODAS abertas (`cycle_end` NULL) → fechar todas com `cycle_end='2026-07-08'`.
- Draft: `_handoff/dia9/draft_migration_c4_rollforward.sql` (BEFORE/AFTER embutidos).
- **Achado 04/07 que supersede o §4.3:** `members.cycles` usa cohort tag (`cycle4-2026`) e os
  30/30 da coorte JÁ o têm — o append do plano cai; a migration só fecha C3 + insere history C4.
- Aplicar via `apply_migration` + arquivo local + `migration repair` (Q-C; cuidado LL do phantom
  com timestamp do dia — buscar `version LIKE '20260709%'` após apply).
- Follow-up institucional: #1104 (`admin_roll_cycle_membership`).

### 4. Exit Débora (`a8c9af17-d9f8-4a0e-85bc-a0b13b0f8ad7`, líder T2)
`admin_offboard_member(p_new_status=>'alumni', p_reason_category=>'end_of_cycle')` — **sem
`p_reassign_to`** (T2 arquiva, não há sucessor). NÃO revogar Drive antes do offboard.
(Ela está na coorte dos 31 mas FORA do roll-forward — a migration exclui o id dela.)

### 5. Arquivar T2 Agentes Autônomos (card `d2b61ff9`, supersede D3)
- `tribes` id=2 → `is_active=false` (via `admin_upsert_tribe` se suportar, senão UPDATE governado).
- Initiative `6c3ffc94-207c-4c63-9e83-c6f3d48529d7` → `status='archived'`.
- Varrer board_items órfãos dela e do Ricardo França (offboarded 04/07) — listar ao vivo e
  realocar/arquivar.
- **3 pesquisadores ficam órfãos de tribo: Gerson `dc42d4c5`, Guilherme `f5dee40d`, Gustavo
  `dce513e6`** (tribe_id=2) → limpar `members.tribe_id` e orientar re-seleção via `select_tribe`
  (janela até 17/07; comunicar no kickoff).

### 6. Transição T6 ROI & Portfólio: Fabricio → Messias (card `29a8776d`)
- `tribes` id=6 `leader_member_id`: `92d26057` (Fabricio) → `c465b4ac` (Messias).
- Engagement do Messias `821f53c9` (`initiative_id` NULL) → apontar à initiative T6
  `6c7e5945-1457-4eb3-ae99-28d7b1e72db9`.
- `members.tribe_id` do Messias → 6. Verificar cache `operational_role` (trigger) → tribe_leader.
- Pendência registrada: entrevista do Messias sem registro no sistema (exceção #1004).

### 7. Alocação dos líderes novos — JÁ FEITA em 04/07, só CONFIRMAR
Henrique→T9, Honorio→T10, João H→T11 (`members.tribe_id` já setado). Gate real = assinatura do
termo (pré-flight). Jhonathan: tribo Produtividade Aumentada Q1 SÓ pós-entrevista; Paulo (AI
Literacy) SÓ pós-candidatura (card `73186b96` é [DIA 9+], não bloqueia o dia).

### 8. Entrantes
Conforme assinam → `request_tribe_assignment` (cap SSOT 7 ativo). Kickoff 19h Meet `bpx-bcze-zbt`.

### 9. Reconciliação freeze §4 (09–11/07)
`list_offboarding_records(p_since=>'2026-07-03')` — âncora atualizada: **3 offboards desde 03/07**
(tribo-7 researcher + Ricardo França + exceções #1004; conferir handoff kickoff) **+ Débora do
passo 4**. Recheck leak 2a/2c = 0; enter 2d loginable==active_eng.

### 10. Residuais #1003 (mesma janela)
Fechar batch `cycle3-2026-b2` · arquivar 196 cards C3 + 25 done-unarchived (tag de ciclo,
precedente C2) · champion `general` (gestor).

## Estado da campanha de assinatura (item 2 da fila, preparado 04/07)
- Template e-mail **staged**: `campaign_templates` slug `volunteer_term_signing_leaders_c4`
  (id `57a1eef2`, pt/en/es, vars `first_name`+`member_email`, CTA
  `https://nucleoia.pmigo.org.br/volunteer-agreement`). **NÃO enviado** — gates: (1) owner ativa
  o termo C4; (2) owner aprova copy; (3) quota Resend reseta 00:00 UTC.
- `sla_deadline` setado 04/07 (9 rows): steps `volunteer_term` (5×) + `complete_profile` (4×;
  Henrique já completo) → 2026-07-08 23:59 BRT — `detect_onboarding_overdue` passa a cobrar.
- Perfis: só Henrique completo; Honorio/Jhonathan/João H/Messias sem phone/address/city/state/
  birth_date (o fluxo pede antes de assinar). João H ainda SEM auth (cria no 1º login).
