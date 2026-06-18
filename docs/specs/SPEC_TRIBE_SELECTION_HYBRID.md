# SPEC — Seleção de Tribo Híbrida (fluxo contínuo pós-promoção)

**Status:** draft · **Autor:** PM/main-loop + council (data-architect) · **Data:** 2026-06-18
**Decisões de produto (PM, esta sessão):**
1. Modelo **híbrido**: researcher escolhe a tribo → **líder da tribo confirma/recusa** (GP override).
2. Quem confirma: **líder da tribo escolhida**, com GP (`manage_member`) sempre podendo também.

---

## 1. Problema (aterrado ao vivo 2026-06-18)

A seleção de tribo foi um **evento batch único**: 35 seleções entre 05–09/mar/2026, deadline
`home_schedule.selection_deadline_at = 2026-03-09` (**fechado há 101 dias**). O RPC legado
`select_tribe` **bloqueia toda seleção pós-deadline** exceto para `manage_platform`.

**Coorte viva hoje ≈ 0:** 25/26 researchers ativos já têm tribo; o único sem tribo é conta owner.
Os demais sem-tribo (27 guest, 5 sponsor, 4 chapter_liaison, 4 observer, 2 manager) são papéis que
**legitimamente não entram em tribo**.

**O gap real é o fluxo CONTÍNUO:** quando os 27 guests forem promovidos a researcher e assinarem o
termo de voluntário (jornada guest→ativo, #625/Épico D), **não terão caminho self-service para entrar
numa tribo** — `select_tribe` retorna "Seleção encerrada". Hoje ninguém está nesse buraco; é o próximo
a aparecer.

## 2. Descoberta de reuso (lição J/C/D/106 — aterrar antes de construir)

O fluxo pedido→aprovação **já existe** como padrão genérico de iniciativa, e **as 8 tribos SÃO
initiatives** `kind='research_tribe'`:

- `request_to_join_initiative(initiative_id, message)` → cria self-invitation pending em
  `initiative_invitations` (invitee==inviter), msg ≥50 chars, expira 72h.
- `review_initiative_request(invitation_id, decision, note)` → autoridade `manage_member` (GP) **ou**
  engagement owner/coordinator/lead da initiative; aprovação cria `engagements`.
- Telas de leitura já existentes: `list_invitations_for_my_initiatives` (líder), `list_my_initiative_invitations` (researcher).
- Cron `expire_stale_initiative_invitations` (existente) expira pending após 72h.

**Eixo escolhido (data-architect GO):** construir sobre o eixo **initiative/engagement (V4-nativo)**,
não sobre o legado `tribe_selections`. Alinhado ao ADR-0005 (initiatives é o primitivo; tribes é bridge).

## 3. Os 3 gaps a fechar + correções do grounding

| # | Gap | Fato | Resolução |
|---|-----|------|-----------|
| 1 | `request_to_join_initiative` exige `join_policy IN ('request_to_join','open')` | tribos são `invite_only` | **NÃO** mudar join_policy. Criar RPC dedicada `request_tribe_assignment` (scope research_tribe) que opera direto em `initiative_invitations`. |
| 2 | Autoridade do líder | tribe_leader é `volunteer/leader`; `role='leader'` ∉ gate de `review_initiative_request` (que lista `owner/coordinator/lead`); `volunteer/leader` **não** tem `manage_member` (proibido seedar — GP-only, LGPD Art.18) | Caminho-3 **inline-scope** (`can_by_member_for_initiative` **não existe**) numa RPC wrapper `review_tribe_request` restrita a research_tribe. **NÃO** mexer no gate compartilhado (blast-radius p/ workgroup/committee/study_group). Sem seed em `engagement_kind_permissions`. |
| 3 | Ponte engagement→`members.tribe_id` | aprovação cria `engagement`, mas `members.tribe_id` só deriva de `members.initiative_id`/`tribe_selections`, **não** de `engagements` | Novo trigger AFTER em `engagements`. |

**Correção ao veredito do data-architect (re-aterrada ao vivo):** `count_tribe_slots` **já lê de
`members.tribe_id`** (não de `tribe_selections`) — então **não há drift de slots**; o trigger-ponte
preenche `members.tribe_id` e o slot count reflete sozinho. O item "migrar count_tribe_slots para
v_initiative_roster" foi **removido** do escopo.

## 4. Desenho técnico

### 4.1 Trigger-ponte `engagements` → `members.tribe_id`
- `AFTER INSERT OR UPDATE OF status, kind ON engagements`, `WHEN (kind='volunteer')`.
- Admissão: status `active` + initiative `research_tribe` → `UPDATE members SET tribe_id = i.legacy_tribe_id`
  (via `person_id`, bridge ADR-0006), guard `IS DISTINCT FROM` (evita no-op).
- **Demoção (branch obrigatório):** `OLD.status='active' AND NEW.status<>'active'` → zera `members.tribe_id`
  **só se** não houver outro engagement research_tribe ativo (senão drift silencioso, ADR-0012 P2).
- `SECURITY DEFINER`, `search_path=''`. Não escreve em `engagements`/`tribe_selections` (sem loop).

### 4.2 RPC `request_tribe_assignment(p_tribe_id integer, p_message text)`
- Gate de termo de voluntário **idêntico ao `select_tribe`** (`member_is_pre_onboarding` fail-closed) —
  só researcher promovido c/ termo assinado pede tribo.
- Researcher ativo, não tribe_leader, sem engagement ativo nem invitation pending na tribo.
- Resolve initiative da tribo (`initiatives.legacy_tribe_id = p_tribe_id AND kind='research_tribe'`).
- INSERT `initiative_invitations` (invitee==inviter==caller, `kind_scope='volunteer'`, msg) → pending.
- Notifica o líder da tribo.

### 4.3 RPC `review_tribe_request(p_invitation_id uuid, p_decision text, p_note text)`
- Restrita a invitations de initiative `research_tribe`.
- **Autoridade (Caminho-3 inline-scope):** `can_by_member(caller,'manage_member')` (GP) **OU** engagement
  ativo `kind='volunteer' AND role='leader' AND initiative_id = invitation.initiative_id` (líder DAQUELA tribo).
- approve → cria `engagement` (dispara 4.1 → seta `members.tribe_id`); decline → status declined.
- Notifica o researcher do resultado.

### 4.4 Invariantes (baseline medida = **0/0** hoje; nomes finais na mig 20260805000216)
- `AG_tribe_engagement_has_tribe_id` (era `I_tribe_engagement_has_tribe_id`): todo engagement
  `volunteer` ativo em research_tribe ⇒ `member.tribe_id = initiative.legacy_tribe_id`.
  (31 engagements ativos, 0 violações.)
- `AH_research_tribe_single_active_engagement` (**substitui** `I_research_tribe_no_dual_pending`):
  uma pessoa tem no máximo 1 engagement `volunteer` ativo entre initiatives research_tribe.
  Razão da troca (aterrada ao vivo no PR1): a formulação pending-vs-`tribe_selections` dá
  **falso-positivo** numa troca de tribo legítima (pedido in-flight ≠ drift), e a variante de
  divergência-committed já é **não-zero hoje** (1 staleness do `tribe_selections` legado congelado,
  abaixo da ponte pois AG=0). `AH` é 0-clean e protege diretamente a premissa de tribo-única do
  trigger-ponte (escalar `members.tribe_id` + branch de demoção). (0 violações.)

### 4.5 Legado `tribe_selections` / `TribesSection.astro`
- **Não dropar.** Deadline fechado já é freeze de facto. `COMMENT ON TABLE` marcando legacy + nota de
  tech-debt; deprecação formal fica para ADR futuro (data-architect concordou).
- `TribesSection.astro` (home, realtime sobre `tribe_selections`) **não é modificada** — o fluxo contínuo
  vive em tela separada (PR2/PR3), para não misturar "batch fechado" com "pedido+aprovação".
- Drift cosmético menor: FE mostra `MAX_SLOTS=10`, backend `select_tribe` impõe 6 → alinhar (LOW, fora do core).

## 5. Decomposição em PRs

- **PR1 (DB core):** trigger-ponte 4.1 (com demoção) + `request_tribe_assignment` 4.2 + `review_tribe_request`
  4.3 + 2 invariantes 4.4 + COMMENT legacy. Council: data-architect (✅ feito) + **security-engineer**
  (autoridade Caminho-3/RLS/LGPD) + code-reviewer.
- **PR2 (FE researcher-facing):** bloco/tela pós-promoção no `/workspace` p/ pedir tribo (escolher +
  mensagem ≥50 + estado pending "aguardando líder"). Reusa `list_my_initiative_invitations`. Council: ux-leader.
- **PR3 (FE leader-facing):** fila de aprovação do líder (na `/tribe/[id]` ou bloco) [Aceitar]/[Recusar].
  Reusa `list_invitations_for_my_initiatives`. Council: ux-leader.

## 6. Riscos (data-architect) e mitigação
- **Autoridade scope:** nunca usar `can_by_member` org-scoped p/ líder sem filtro de initiative → Caminho-3 inline (4.3). ✅
- **Ponte unidirecional:** branch de demoção obrigatório (4.1) senão `tribe_id` órfão. ✅
- **Expiração 72h:** pode ser curta p/ líder; avaliar `sla_policy` de revisão (P2, follow-up).
- **Dual-write tribe_selections × engagements:** ambos escrevem `members.tribe_id`; legado congelado (deadline) → sem conflito; invariantes cobrem.

## 7. Métrica de sucesso
% de researchers promovidos pós-2026-03-09 que obtêm tribo via fluxo híbrido em ≤7 dias da promoção
(baseline atual = 0 promovidos pós-deadline; medir no 1º ciclo de promoções).
