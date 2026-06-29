# ADR-0109 — Recusal por conflito de interesse: candidato ativo é impedido das visões de seleção

**Status:** Accepted (2026-06-28, Onda 2 WS-4)
**Relacionado:** ADR-0007 (V4 `can()` autoridade), ADR-0068 (CoI declaration de curadoria), ADR-0105/#785 (visibilidade ortogonal), ADR-0023 (ladder de derivação), Onda 2 (handoff pt6), `docs/reference/V4_AUTHORITY_MODEL.md`.

## Contexto

A V4 responde "o caller PODE ler esta superfície de seleção?" via `can_by_member(caller, 'view_internal_analytics')` (gate de leitura das RPCs de seleção: `get_selection_dashboard`, `get_selection_rankings`, `get_selection_pipeline_metrics`, `get_selection_health`). A designação `sponsor` e a engagement `chapter_board` concedem `view_internal_analytics` — então um **presidente/patrocinador de capítulo** lê os dashboards de seleção, **incl. scores dos candidatos**.

Surge um conflito de interesse estrutural quando essa mesma pessoa **se candidata** ao programa no ciclo vigente (o mix-case "presidente do PMI-Amazonas se candidata como pesquisador"). Ela seria simultaneamente **autoridade institucional que vê o processo** e **candidata avaliada** — podendo ver os scores dos concorrentes e da própria candidatura.

Parecer do conselho (2026-06-28):
- **legal-counsel (BLOCKER):** viola finalidade (Art. 6, I) e não-discriminação (Art. 6, VII) da LGPD — um avaliado vendo os dados do processo que o avalia não tem base legal válida; afeta direitos de terceiros (os outros candidatos, também titulares). Exige **impedimento técnico, não honra-sistema**.
- **accountability-advisor:** PMI Code of Ethics §4 (Fairness) exige disclosure + gestão de COI; a *aparência* de imparcialidade é tão exigida quanto o bloqueio. Impedimento automático **independentemente do cargo institucional**.

Grounding 2026-06-28: **0 instâncias atuais** (nenhum dos 13 detentores de acesso a seleção é candidato ativo no ciclo `cycle4-2026`). Logo, isto é **forward-defense** — sem janela de exposição ao introduzir.

## Decisão

**Um caller que é candidato ATIVO (linha `selection_applications` em status não-terminal) no ciclo é RECUSADO das visões de seleção daquele ciclo — mesmo que detenha `view_internal_analytics`.**

1. **Primitivo** — helper `selection_coi_recused(p_caller_id uuid, p_cycle_id uuid) → boolean` (`STABLE SECURITY DEFINER`):
   - `true` quando o caller tem uma `selection_applications` não-terminal (`status NOT IN ('rejected','withdrawn','cancelled')`) no ciclo, casada por email (`members.email` OU `member_emails`), **E** o caller NÃO é GP (`NOT can_by_member(caller, 'manage_platform')`).
   - **GP/superadmin nunca é recusado** — ele administra a seleção (member-lifecycle/selection-admin = GP-only by design). O persona recusado é o detentor de acesso **não-GP** (sponsor/chapter_board) que também se candidatou. "Independentemente do cargo" significa que o cargo institucional **não isenta** o candidato — não que o administrador da seleção seja bloqueado.
   - **Internal-only:** `REVOKE` de `anon`/`authenticated`/`PUBLIC` (senão expor-se-ia via PostgREST e vazaria o status de candidatura de um membro arbitrário); `GRANT` só a `service_role`. As RPCs SECDEF de seleção o chamam como definer.
2. **Aplicação (este PR):** gate em `get_selection_rankings` (a superfície de **scores** — o cerne do COI). Após resolver o ciclo, se `selection_coi_recused(v_caller_id, v_cycle_id)` → retorna `{error: 'recused_conflict_of_interest', detail: …}`.
3. **Restauração automática:** o impedimento é derivado, não um flag — quando a candidatura vira terminal (rejected/withdrawn/approved→não mais "candidato no ciclo") ou o ciclo fecha, o caller volta a ver as superfícies sem nenhuma ação manual.

## Escopo / fast-follow (PR-2, rastreado)

Este PR gateia **`get_selection_rankings`** (scores). As demais superfícies que expõem dado de candidato e são alcançáveis por um detentor de `view_internal_analytics` — **`get_selection_dashboard`** (18.9KB), **`get_selection_pipeline_metrics`**, **`get_selection_health`** — recebem o **mesmo gate** (uma chamada ao helper após a resolução do ciclo) no fast-follow rastreado. As RPCs gateadas por `manage_member` (`get_application_score_breakdown`, `get_application_detail`) são GP-only — um GP candidato é caso extraordinário e está fora do persona; ainda assim entram no fast-follow por completude. **0 instâncias atuais** → sem janela de exposição para o intervalo.

## Consequências

- **Segregação de deveres real (técnica)**, não apenas declaração: o avaliado não lê os scores do processo. Defensável perante LGPD (finalidade/não-discriminação) e PMI Code §4.
- **Função-anchored:** o gate é por condição (candidato-no-ciclo), nunca por indivíduo nomeado; sobrevive à rotação de cargos.
- **Read ≠ write:** o helper é `STABLE`; nada de write/lifecycle é concedido ou negado — apenas leitura de scores é impedida.
- **Sem seed-expansion:** não toca `engagement_kind_permissions`; é um eixo ortogonal (como #785), aplicado dentro das RPCs SECDEF.
- **Auditabilidade:** o estado de recusa é determinístico e consultável (quem é candidato × quem tem acesso). Um log de evento de recusa não foi embutido nas RPCs (são `STABLE`, não podem escrever); se exigido, virá por mecanismo de auditoria separado.
- **Trade-off:** enquanto o fast-follow não fecha as superfícies irmãs, um candidato-com-acesso poderia chamá-las direto via PostgREST. Aceito porque há **0 instâncias** e o gate de scores (o dado mais sensível ao COI) já está ativo.
