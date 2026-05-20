# p203 Curadoria Journey Audit

**Data:** 2026-05-19  
**Status:** Em andamento — evidência inicial consolidada  
**Escopo:** requisitos vs entrega, frontend, SQL/RPC/RLS, notificações/email, MCP, workspace do Comitê de Curadoria e semantic layer.

---

## 1. Contexto Operacional

O fluxo de curadoria foi reativado entre p196-p201 após o primeiro teste real com o artigo `Artigo — Agentes Autônomos em GP`.

Linha do tempo reconstruída:

- p196 (`08b65a88`) — safety net: atribuir `curation_reviewer` a card `done` auto-transiciona para `curation_pending`.
- p197 (`7766325d`) — botão canônico `Submeter para Curadoria` + campos estruturados de peer/leader review.
- p198 (`710929a2`) — ADR-0086 formaliza FSM e requisitos do Manual §4.2.
- p198 (`5dcead1e`) — workspace MVP do Comitê de Curadoria com board + 3 cards bootstrap.
- p200 (`4ac95bed`) — ADR-0087 migra 14 gates V3 `curator` para action V4 `curate_content`.
- p201 (`a6f10cdb`, `2d91e07c`) — UI `/admin/curatorship` passa a aceitar `canFor('curate_content')` e corrige simulação superadmin.

Há três trilhas parcialmente sobrepostas:

| Trilha | Primitivo | Status |
|---|---|---|
| Board FSM | `board_items.curation_status`, `curation_review_log` | Canônica para artigos/boards de tribo |
| Legacy curation board | `list_curation_board`, `curate_item`, `hub_resources` | Ainda renderizada no Super-Kanban, mas separada da FSM |
| Publication/governance | `publication_submissions`, `publication_ideas`, governance docs/CRs | Paralela; não entra automaticamente na fila `/admin/curatorship` |

---

## 2. Requisitos Prometidos

Do ADR-0086 e comunicação operacional:

1. Tribe leader não deve precisar nomear curadores específicos para submeter.
2. Botão único `Submeter para Curadoria` deve mover o card para fila do Comitê.
3. Curadores devem ver fila em `/admin/curatorship`.
4. Curadores devem receber notificação quando houver submissão.
5. SLA deve ser 7 dias.
6. Avaliação usa rúbrica de 5 critérios: `clarity`, `originality`, `adherence`, `relevance`, `ethics`.
7. Devolução deve retornar ao autor com feedback.
8. Workspace do Comitê deve ser "one place" operacional, mas a fila real continuou em `/admin/curatorship` no MVP.
9. Fonte de autoridade de curadoria deve ser V4 `curate_content`, não `members.designations`.

---

## 3. Evidência Live — 2026-05-19

Consulta read-only em produção:

| Métrica | Resultado |
|---|---:|
| `board_items` com `curation_status` | 506 |
| `draft` | 505 |
| `curation_pending` ativo | 1 |
| `curation_pending` overdue | 0 |
| `curation_pending` sem SLA | 0 |
| `curation_review_log` total | 0 |
| reviews últimos 30 dias | 0 |
| `board_item_assignments.role='curation_reviewer'` | 3 |
| workspace Comitê de Curadoria | 1 board, 3 cards bootstrap, todos `backlog` |

Item live:

- `642fe90f-20ad-4ba4-a9e7-05470ed7c5de`
- Título: `Artigo — Agentes Autônomos em GP`
- Board: `T2: Agentes Autônomos - Quadro Geral`
- Estado: `status='done'`, `curation_status='curation_pending'`
- SLA: `2026-05-26T01:23:11Z`
- Reviews: `0`

Capacidades dos 3 curadores V4:

| Curador | `curate_content` | `participate_in_governance_review` | `write_board` |
|---|---:|---:|---:|
| Fabricio | true | true | true |
| Roberto | true | true | false |
| Sarah | true | true | false |

---

## 4. Achados Confirmados

### C-001 — Backend da fila ainda exige `write_board`, não `curate_content`

**Severidade:** HIGH  
**Camada:** SQL/RPC + frontend access
**GitHub:** #185

`CuratorshipBoardIsland` agora aceita `canFor('curate_content')`, mas as RPCs que a ilha chama primeiro/fallback ainda exigem `can_by_member(v_member_id, 'write_board')`:

- `get_curation_dashboard()`
- `list_curation_pending_board_items()`

Impacto live:

- Roberto e Sarah têm `curate_content=true`, mas `write_board=false`.
- A UI pode deixar entrar, mas a RPC nega a fila.
- Isso explica o relato de Roberto: "Sem acesso / status em conflito".

Próxima ação:

- Trocar gate das reader RPCs de fila para `curate_content OR participate_in_governance_review OR manage_member`, preservando `write_board` apenas se ainda for necessário para outros operadores.

### C-002 — Caminho canônico de submissão não notifica o Comitê

**Severidade:** HIGH  
**Camada:** SQL/RPC + notification/email
**GitHub:** #186

`submit_for_curation(p_item_id)` só atualiza `board_items.curation_status` e insere `board_lifecycle_events`. Ele não cria notificação para curadores.

O trigger `notify_on_curation_status_change()` notifica apenas membros já existentes em `board_item_assignments` do card:

- Se o tribe leader usa o caminho antigo/workaround e atribui curadores, eles recebem notificação.
- Se o tribe leader usa o botão canônico "sem precisar nomear curadores", não há destinatários do Comitê.

Evidência do item live:

- 11 notificações associadas ao item.
- 3 curadores `curate_content` receberam 3 notificações cada.
- Tipos: `assignment_new`, `card_assigned`, `card_moved`.
- Todas com `delivery_mode='digest_weekly'`.
- `email_sent_at = NULL` em todas.

Interpretação:

- Os curadores foram notificados in-app/digest porque estavam atribuídos como `curation_reviewer`.
- Não há evidência de email transacional imediato para o caso.
- A promessa operacional "curadores foram notificados" é parcialmente verdadeira para in-app/digest, mas não para email imediato e não para o fluxo canônico sem nomear curadores.

Próxima ação:

- Criar broadcast idempotente para todos com `can_by_member('curate_content')` quando card entra em `curation_pending`.
- Definir se o delivery deve ser `transactional_immediate` ou digest, porque SLA de 7 dias e primeiro teste real sugerem imediato.

### C-003 — Picker de `curation_reviewer` ainda filtra por V3 `designations`

**Severidade:** MEDIUM/HIGH  
**Camada:** frontend
**GitHub:** #187

`MemberPickerMulti.tsx` filtra candidatos a `curation_reviewer` com:

```ts
m.designations?.includes('curator')
```

Isso contradiz ADR-0087 para novos curadores que tenham `curate_content` via engagement V4 mas não tenham `members.designations` atualizado.

Próxima ação:

- Expor capacidade V4 no payload de membros do board ou criar RPC específica de eligible curation reviewers.
- Evitar depender de `designations` para seleção de revisor de curadoria.

### C-004 — MCP `get_curation_dashboard` é admin-only e não curator-native

**Severidade:** MEDIUM/HIGH  
**Camada:** MCP/semantic layer
**GitHub:** #188

MCP tool `get_curation_dashboard`:

- Descrição: "Admin only".
- Gate JS: `canV4(..., 'manage_member')`.
- RPC chamada: `get_curation_dashboard()`, que por sua vez exige `write_board`.

Impacto:

- Curadores V4 sem `manage_member` não conseguem usar MCP para ver fila.
- MCP não tem tools canônicas para `submit_for_curation`, `complete_peer_review`, `complete_leader_review` ou `submit_curation_review`.

Próxima ação:

- Após corrigir os RPC gates, adicionar MCP tools curadoria-native com gate `curate_content` / `participate_in_governance_review`.

### C-005 — Pipeline visual usa estados aspiracionais que não batem com DB

**Severidade:** MEDIUM  
**Camada:** frontend UX
**GitHub:** #189

`CardDetail.tsx` renderiza pipeline visual com:

```ts
['ideation', 'research', 'drafting', 'author_review', 'peer_review', 'leader_review', 'curation', 'published']
```

Mas o tipo/DB real é:

```ts
'draft' | 'peer_review' | 'leader_review' | 'curation_pending' | 'published'
```

Impacto:

- Card em `curation_pending` não mapeia para `curation`, então o indicador visual pode não marcar a etapa atual corretamente.
- O ADR-0086 já reconhece dead branches herdados, mas este ponto ainda aparece na UI.

Próxima ação:

- Alinhar o pipeline visual ao enum real ou mapear `curation_pending -> curation`.

### C-006 — Review RPCs não têm contract tests focados

**Severidade:** MEDIUM  
**Camada:** QA

Já registrado no `P162_GAP_OPPORTUNITY_LOG.md` item #32:

- `complete_peer_review`
- `complete_leader_review`

Continuam sem testes de contrato focados para autorização, transições, reset de peer state, devolução e submit para fila.

### C-007 — API legada `advance_card_curation` não representa o fluxo p197

**Severidade:** MEDIUM/HIGH  
**Camada:** MCP/backend compatibility
**GitHub:** #191

O MCP expõe `advance_card_curation`, mas a tool chama `advance_board_item_curation`, que pertence ao fluxo legado (`request_review`, `approve_peer`, `approve_leader`) e não aos RPCs p197:

- `complete_peer_review`
- `complete_leader_review`
- `submit_for_curation`
- `submit_curation_review`

Além disso, a descrição MCP cita ações como `assign|approve|reject|request_changes`, que não batem com o vocabulário real do RPC legado.

Próxima ação:

- Deprecar ou reescrever `advance_card_curation` para chamar os contratos p197.
- Atualizar descrição da tool para impedir agentes de chamarem ações inválidas.

### C-008 — `get_curation_dashboard` filtra `revision_requested`, estado inexistente no CHECK

**Severidade:** MEDIUM  
**Camada:** SQL/RPC drift
**GitHub:** #193

O corpo live de `get_curation_dashboard()` filtra:

```sql
bi.curation_status IN ('curation_pending', 'revision_requested')
```

Mas o CHECK real de `board_items.curation_status` é:

```text
draft | peer_review | leader_review | curation_pending | published
```

Devoluções do comitê voltam para `draft` + `status='review'`, não para `revision_requested`.

Próxima ação:

- Remover ou mapear `revision_requested` explicitamente.
- Definir se a tela deve mostrar devoluções em uma seção própria usando `status='review'`.

### C-009 — `TribeKanbanIsland` está implementado, mas não montado na jornada atual

**Severidade:** MEDIUM/HIGH  
**Camada:** frontend UX / dead code risk
**GitHub:** #191

O código possui `TribeKanbanIsland` com lanes e transições de curadoria, mas as rotas atuais de tribo/iniciativa montam `BoardEngine`/`CardDetail`. Isso deixa duas experiências divergentes:

- fluxo ativo: drawer `CardDetail` com RPCs p197;
- fluxo órfão: `TribeKanbanIsland` com `advance_board_item_curation`.

Próxima ação:

- Remover/arquivar o island órfão ou reativá-lo usando os RPCs p197.
- Evitar manter dois motores de curadoria com vocabulários diferentes.

### C-010 — `curation_review_log` permite múltiplas reviews do mesmo curador no mesmo item

**Severidade:** MEDIUM  
**Camada:** dados/consenso
**GitHub:** #192

A tabela registra `board_item_id`, `curator_id`, decisão e scores, mas não há evidência de UNIQUE em `(board_item_id, curator_id)` ou `(board_item_id, curator_id, review_round)`.

Impacto:

- Um mesmo curador pode inflar `reviews_approved` e atingir `reviewers_required` sozinho se a RPC não bloquear duplicidade.

Próxima ação:

- Definir modelo: uma review por curador por rodada.
- Adicionar constraint/guard RPC e teste de contrato.

### C-011 — `auto_publish_approved_article` é dead code documentado

**Severidade:** LOW/MEDIUM  
**Camada:** backend drift
**GitHub:** #193

ADR-0086 já registra que `auto_publish_approved_article` espera estado `approved`, mas `approved` não existe no CHECK atual de `curation_status`.

Próxima ação:

- Remover trigger morto ou alinhar com `published`/`curation_pending`.

---

## 5. Gaps de Semantic Layer

O domínio curadoria está repartido entre:

- `board_items.curation_status`
- `curation_review_log`
- `board_lifecycle_events`
- `board_item_assignments`
- `notifications`
- `project_boards`
- `engagements` / `engagement_kind_permissions`
- MCP `get_curation_dashboard`
- workspace initiative `6a93cc94-c4a0-4280-8ea7-452ec6ec48a5`

Oportunidade:

Criar uma view/RPC `curation_queue_state` que normalize:

- item;
- origem (`tribe_board`, `governance_document`, `manual`, `webinar`, `article`, `hub_resource`);
- estado;
- SLA;
- review_count;
- required_review_count;
- curators_notified;
- email_sent;
- next_action;
- actor eligible actions for caller.

Isso vira fonte para:

- `/admin/curatorship`;
- workspace do Comitê;
- MCP tools;
- smoke tests;
- digest/email.

**GitHub:** #190

---

## 6. Próximas Ações Recomendadas

1. Corrigir gates das reader RPCs da fila (`get_curation_dashboard`, `list_curation_pending_board_items`) para `curate_content`.
2. Criar notificação/broadcast transacional ou digest explícito para o Comitê quando item entra em `curation_pending`.
3. Trocar picker `curation_reviewer` para fonte V4 de elegibilidade.
4. Corrigir pipeline visual de `CardDetail`.
5. Criar tests contract para `complete_peer_review`, `complete_leader_review`, `submit_for_curation`, `submit_curation_review`.
6. Adicionar MCP tools curadoria-native depois dos RPC gates.
7. Evoluir workspace do Comitê para consumir `curation_queue_state` em vez de depender de link manual para `/admin/curatorship`.
8. Deprecar/reconciliar `advance_card_curation` e `TribeKanbanIsland` com o fluxo p197.
9. Adicionar guard/constraint contra review duplicada do mesmo curador por rodada.
10. Resolver `revision_requested` e `auto_publish_approved_article` como drift de vocabulário.

