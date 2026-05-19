# ADR-0086: Curation pipeline — structured peer/leader review per Manual §4.2

| Field | Value |
|---|---|
| Status | Accepted |
| Date | 2026-05-18 (sessão p196 + p197 + council fixes + p198 ADR) |
| Author | Vitor Maia Rodovalho (Assisted-By: Claude) |
| Migrations | `20260711000000` (auto-submit trigger, p196) · `20260712000000` (forecast follows actual, p196) · `20260713000000` (8 peer/leader columns, p197) · `20260714000000` (2 RPCs, p197) · `20260715000000` (action collision fix + gate tighten, p197) · `20260716000000` (notification signature + peer reset fix, p197) · `20260717000000` (recalc guard, p197) · `20260718000000` (trigger NULL guard, p197) |
| Cross-ref | [ADR-0011](./ADR-0011-v4-auth-pattern-rpcs-mcp.md) (V4 auth) · [ADR-0012](./ADR-0012-schema-consolidation.md) (schema invariants) · [ADR-0041](./ADR-0041-governance-review-action.md) (participate_in_governance_review catalog) · Manual de Governança §3.6 / §4.2 / §4.3 / §5.1 / §5.3 |
| Closes | GAP-197.A (this ADR) · OPP-197.D (item §3.6 below) |

## Context

Por 1.5 meses (W90 entregue ~p133 até 2026-05-18) a infraestrutura de curadoria existiu mas **nunca foi usada em produção** (0 entries em `curation_review_log`, 503 cards parados em `curation_status='draft'`). Investigação iniciada por reportagem da Débora Moura (líder tribo Agentes Autônomos) revelou múltiplos gaps:

1. **Sem entrypoint UI canonical** — tribe leaders não tinham botão "Submeter para Curadoria"; a Débora intuitivamente atribuiu 3 curators via `+ Adicionar membro` (path `board_item_assignments` com `role='curation_reviewer'`), mas esse path não disparava transição na FSM `curation_status`.
2. **Manual §4.2 define 7 etapas** (geração → pesquisa → redação → revisão autores → peer review COLEGIADO → leader review NOMINAL → submissão curadoria), mas etapas 5-6 só existiam como valores de `curation_status` sem metadata estruturada (data, revisor, decisão, dispensa).
3. **Sem cascade de notificações funcionais** — triggers `trg_notify_curation_status` etc. existiam mas só disparavam em mudança de `curation_status`, que nunca acontecia porque ninguém usava a FSM.

PM clarificou design canônico durante sessão: tribe leader não deve precisar nomear curadores específicos; campos estruturados peer/leader review devem estar visíveis no card per manual de governança; dispensa permitida para artigos colaborativos.

Council Tier 1 close audit (code-reviewer + platform-guardian) identificou 12 itens (2 BLOCKERS + 5 HIGH + 3 MED + 2 LOW) — todos os BLOCKERS e HIGH foram corrigidos inline antes de fechar (p197 fix bundle).

## Decision

### §1. FSM `curation_status` consolidada

A FSM operacional do `board_items.curation_status` é:

```
draft → peer_review → leader_review → curation_pending → published
                                                          ↑ (back to draft on leader 'returned')
```

5 estados ativos (alinhados com CHECK constraint atual). Estados extras renderizados em `BoardKanban.tsx` que não existem no CHECK (`'review'`, `'curation'`, `'drafting'`, `'author_review'`, `'ideation'`, `'research'`, `'approved'`, `'rejected'`) são dead branches herdados de uma FSM "ideal" abandonada — **TypeScript type `CurationStatus` foi alinhado ao DB em p197 fix B2** (`'draft' | 'peer_review' | 'leader_review' | 'curation_pending' | 'published'`).

### §2. Peer Review = COLEGIADO

Per manual §4.2 etapa 5: *"o rascunho é compartilhado com todos os colaboradores da tribo para feedback construtivo"*.

**Modelagem**: peer review NÃO tem reviewer_id nominal. Não há "o peer reviewer". O modelo é:

- Feedbacks individuais vivem em `card_comments` (reuso de tabela existente)
- Estado de conclusão da fase no card via `board_items.peer_review_completed_at` (timestamp)
- `peer_review_summary` (text) opcional — resumo agregado para o líder ler antes de avaliar
- `peer_review_waived` (boolean) — dispensa explícita para casos colaborativos
- `peer_review_waived_reason` (text) — motivo obrigatório se waived (manual §4.2 menciona "adaptações" para webinars/podcasts/pílulas)

**Anti-pattern a evitar**: criar tabela `peer_reviews` N:N com `reviewer_id` por feedback. Isso seria "reviewer nominal repetido N vezes" — semantica diferente do que o manual define.

### §3. Leader Review = NOMINAL

Per manual §4.2 etapa 6: *"o Líder da tribo realiza a revisão final de qualidade, oferecendo feedback especializado e aprovando o artigo para a próxima etapa"*.

**Modelagem**: leader review TEM reviewer_id nominal e decisão binária (estendida a 3 opções):

- `leader_reviewer_id` (uuid FK → members.id ON DELETE SET NULL)
- `leader_review_decision` (text CHECK IN `'approved' | 'returned' | 'waived'`)
- `leader_review_notes` (text) — feedback especializado
- `leader_review_completed_at` (timestamptz)

Branches da decisão:
- `approved` → curation_status='curation_pending', SLA setado, Comitê notificado
- `returned` → curation_status='draft', peer_review_* fields completamente resetados (ver §3.5 fix H2), assignee notificado com motivo
- `waived` → curation_status='curation_pending', leader registra que dispensou avaliação formal (ex: artigo já tinha sua aprovação implícita)

#### §3.5 OPP-197.D resolução: `complete_leader_review` aceita `curation_status='draft'`

Council code-reviewer flagou que `complete_leader_review` permite chamada quando card está em `'draft'` (sem peer review concluído), criando bypass das etapas 5-6 do manual.

**Decisão PM (2026-05-18)**: ACEITO como design intencional. Justificativa:

> "Se a própria líder colocou o card como concluído, eu assumo que ela fez a revisão. Porém para próximos processos de submissão vamos deixar isto mais explícito."

Isso reconhece a realidade operacional: tribe leader que marca `card.status='done'` está implicitamente certificando que o conteúdo passou pelo crivo dela. Forçar uma chamada formal a peer_review + leader_review seria burocracia adicional sem ganho de qualidade quando a líder é a próxima na linha de aprovação de qualquer forma.

**Evolução planejada (futuro, não nesta ADR)**: adicionar UI confirmation step explícito antes do submit, exibindo claramente "Você está dispensando peer review + leader review formal porque está submetendo diretamente como líder. Confirma?". Isso preserva auditabilidade sem criar fricção.

### §4. Waiver path com motivo obrigatório

Tanto peer review (`p_waived=true` requer `p_waiver_reason`) quanto leader review (`decision='waived'`) suportam dispensa formal. Em ambos casos:

- Motivo obrigatório (RAISE EXCEPTION se NULL/empty)
- Capturado em coluna dedicada (`peer_review_waived_reason`) ou nas notes (leader)
- Audit trail via `board_lifecycle_events` preserva quem/quando/por quê
- Não há check programático de "elegibilidade" de dispensa — confiança no julgamento do leader/autor

Manual §4.2 menciona "adaptações" para formatos não-artigo (webinars/podcasts/pílulas) como precedente. Decisão é deixar a interpretação operacional sem CHECK adicional.

### §5. Distinct lifecycle actions (analytics safety)

CHECK constraint de `board_lifecycle_events.action` expandido em p197 fix B1 para incluir:

- `peer_review_completed` — etapa 5 conclusão (substituiu uso original de `'curation_review'` que colidia com analytics)
- `leader_review_completed` — etapa 6 conclusão

**Razão**: queries de analytics existentes (`w118`, `w119`, `w122`) filtram `WHERE action='curation_review' AND new_status='approved'` para contar pareceres de curadoria reais. Reusar `'curation_review'` para peer review contamina analytics em queries futuras. Distinguir explicitamente preserva semântica.

### §6. Authority hierarchy 4-tier (V4 native)

`complete_peer_review` (RPC) gate, em ordem de fall-through:

1. `v_item.assignee_id = v_caller.id` (autor do card)
2. `board_item_assignments.role IN ('author', 'contributor') AND member_id = caller.id` (co-autores formais)
3. `engagements WHERE initiative_id = card_initiative AND role = 'leader' AND status='active'` (líder da tribo do card)
4. `can_by_member(caller.id, 'participate_in_governance_review')` (curadores + governance reviewers carve-out de p195)

`complete_leader_review` (RPC) gate, mesma ordem mas SEM tier 1 e 2 (apenas leaders ou governance reviewers podem gate):

1. `engagements WHERE initiative_id = card_initiative AND role = 'leader' AND status='active'`
2. `can_by_member(caller.id, 'participate_in_governance_review')`

**Anti-pattern evitado (p197 fix H4)**: NÃO usar `board_items.created_by` como gate de autoria. Essa coluna marca "quem entrou o card no sistema" (frequentemente GP fazendo data entry), não o autor intelectual.

**Compliance ADR-0011**: ambos os RPCs novos usam V4 path canônico (`can_by_member` + `engagements`), zero hardcoded designations ou operational_role lookups.

### §7. Trigger safety-net pattern (defensive UX)

Tribe leaders que ainda não conhecem o botão canonical podem fazer o "workaround Débora" — atribuir 3 `curation_reviewer` via `+ Adicionar membro`. Para honrar essa intent intuitiva, **trigger AFTER INSERT em `board_item_assignments`** detecta o pattern (role='curation_reviewer' + card.status='done' + curation_status='draft') e auto-transiciona para `curation_pending`.

**Posicionamento**: este é safety NET, não canonical PATH. Documentado explicitamente no comentário da migration `20260711000000` e neste ADR. Quando todos os tribe leaders conhecerem o botão, o trigger raramente disparará — mas continua valioso como defensive UX.

**Audit**: ação registrada como `'submitted_for_curation'` com reason explícita ("Auto-submit (trigger): ...") para distinguir de chamadas manuais via RPC.

### §8. Canonical button — `submit_for_curation` RPC

Botão "Submeter para Curadoria" no `CardDetail.tsx` chama RPC pré-existente `submit_for_curation(p_item_id)`. Gate: `participate_in_governance_review` OR `operational_role='tribe_leader'`. Precondition: `curation_status IN ('leader_review', 'draft')`.

**Decisão UX**: tribe leader NÃO precisa nomear curadores específicos. Submissão é coletiva — qualquer curador do Comitê pega da fila. Isso reflete §3.6 do manual (Comitê é órgão de apoio, não pessoa).

### §9. Notification semantics

`create_notification` tem 3 overloads. O usado nas RPCs de curadoria é o 7-arg:

```sql
create_notification(
  p_recipient_id uuid,
  p_type text,
  p_source_type text,     -- SEMANTIC literal: 'board_item', NOT board_id::text
  p_source_id uuid,
  p_source_title text,
  p_actor_id uuid,
  p_body text
)
```

**Anti-pattern corrigido (p197 fix H1)**: passar `board_id::text` no `p_source_type` quebra deep-link rendering no frontend. Contrato: `p_source_type` é SEMPRE um literal semântico identificando o TIPO do recurso, nunca um UUID.

### §10. Recalculate card dates contract

`recalculate_card_dates` trigger (`board_item_checklists` INSERT/UPDATE/DELETE) tem 2 contratos compostos:

- **Forecast** = MAX(checklist target_date) quando algum existe; OR actual_completion_date quando todos completos sem dates (p196 Gap 2)
- **Actual_completion** = MAX(checklist.completed_at)::date quando todos completos; OR NULL apenas se card TEM checklists e não estão todos completos (p197 fix H3 guard contra clearing em cards sem checklists)

Cards sem checklists preservam `actual_completion_date` setado por outros paths (status='done' move via UI, direct RPC, etc.).

## Consequences

### Positive

- Manual §4.2 fielmente refletido na operação (não apenas no PDF)
- Tribe leaders têm caminho canonical claro + safety net para workaround antigo
- Peer review modelado corretamente (colegiado, não nominal)
- Audit trail rico via `board_lifecycle_events` com actions distinctas
- Curadores recebem notificações automáticas + veem fila em `/admin/curatorship`
- Caso Débora end-to-end LIVE (primeiro item EVER aguardando review em produção)

### Trade-offs

- 8 novas colunas em `board_items` (tabela já wide ~36 colunas pré-p197) — observação para futuros refactors mas sem ação imediata
- `complete_leader_review` aceita `'draft'` bypass (decisão §3.6 acima) — futuro deve adicionar UI confirmation
- i18n EN/ES das 41 keys novas ficaram em fallback PT-BR (backlog OPP-197.D)
- 0 contract tests para os 2 novos RPCs (backlog GAP-197.G)
- UI rerender via `window.location.reload()` perde estado do board (backlog WATCH-197.F)
- ADR-0086 NÃO governa o workspace ONE PLACE do Comitê de Curadoria (initiative `6a93cc94-...` está vazia: 0 boards/events/gov_docs). Isso é OPP-196.D, próximo escopo de p198+.

### Negative (aceitas)

- `auto_publish_approved_article` trigger continua dead code (`approved` não existe no CHECK) — GAP-196.C, próxima sessão
- 8 RPCs V3 ainda usando `'curator' = ANY(designations)` — OPP-196.E, refactor sweep separado

## Migration evidence

| Migration | What |
|---|---|
| `20260711000000` | Trigger `trg_auto_submit_curation_on_reviewer_assign` (safety net §7) |
| `20260712000000` | `recalculate_card_dates` forecast follows actual (Gap 2 / §10) |
| `20260713000000` | 8 columns peer/leader review on board_items + CHECK + FK |
| `20260714000000` | 2 RPCs `complete_peer_review` + `complete_leader_review` |
| `20260715000000` | Action CHECK expansion + RPC fix B1 (peer_review_completed) + H4 (gate tighten) |
| `20260716000000` | RPC fix H1 (notification signature) + H2 (peer state reset) |
| `20260717000000` | RPC fix H3 (recalc guard for empty-checklist cards) |
| `20260718000000` | Trigger fix H5 (NULL assigned_by COALESCE) |

TypeScript fix B2 in commit `1b3e2e9`: `CurationStatus` + `CurationReview.decision` aligned to DB enum.

## Reversibility

Cada migration tem rollback documentado no header. Em ordem reversa:

1. Drop trigger fix → restore p196 body
2. Restore p196 `recalculate_card_dates` body
3. Drop `complete_peer_review` + `complete_leader_review` RPCs
4. ALTER board_items DROP COLUMNs × 8 + DROP constraints × 2
5. Restore CHECK constraint sans `peer_review_completed` + `leader_review_completed` actions

Frontend: revert `CardDetail.tsx` + `types/board.ts` to commit `08b65a8` parent.

## Status validation

Pre-merge (p197 fix bundle, 2026-05-18 ~23:30):
- `npx astro build` PASS
- `npm test` 1449/0/46 offline preserved
- `check_schema_invariants()` 16/16=0
- Caso Débora live (642fe90f em curation_pending desde p196 backfill)

## Future work

Documented as backlog items, not committed in this ADR scope:

- ADR-0087 (futuro): Comitê de Curadoria initiative como workspace ONE PLACE (OPP-196.D — cross-pipeline RPC, meetings tab, attendance, checklists agregados, engagement→curate_content V4 action)
- UI confirmation step para tribe-leader-marking-done implicit review (evolução §3.6)
- Contract tests para `complete_peer_review` + `complete_leader_review` (GAP-197.G)
- Targeted card refetch substituindo `window.location.reload()` (WATCH-197.F)
- i18n EN/ES das 41 keys novas (OPP-197.D i18n part)
- Fix `auto_publish_approved_article` dead code (GAP-196.C — amplia CHECK ou corrige trigger)
- V4 migration dos 8 RPCs V3 designation-based para `can_by_member('curate_content')` (OPP-196.E — necessita seed em `engagement_kind_permissions` + ADR separado)
