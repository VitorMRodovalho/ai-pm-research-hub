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

## 6. Wave 2 — Email, Digest e Pipelines Paralelos

### 6.1 Evidência Email/Digest — 2026-05-19

Consulta live em `notifications`, `_delivery_mode_for()` e `cron.job`:

| Evidência | Resultado |
|---|---:|
| `_delivery_mode_for('assignment_new')` | `digest_weekly` |
| `_delivery_mode_for('card_assigned')` | `digest_weekly` |
| `_delivery_mode_for('card_moved')` | `digest_weekly` |
| `_delivery_mode_for('curation_submitted')` | `digest_weekly` |
| `assignment_new` total | 412 |
| `assignment_new` com email enviado | 0 |
| `card_assigned` total | 33 |
| `card_assigned` com email enviado | 0 |
| `card_moved` total | 4 |
| `card_moved` com email enviado | 0 |
| `send-notification-emails` cron | ativo a cada 5 min |
| `send-weekly-member-digest` cron | ativo sábado 12:00 UTC |
| `send-weekly-leader-digest` cron | ativo sábado 12:30 UTC |

Interpretação:

- A infraestrutura de email transacional existe e roda.
- Os tipos usados pelo caso de curadoria (`assignment_new`, `card_assigned`, `card_moved`) são classificados como `digest_weekly`, então não passam pelo email transacional imediato.
- Não existe tipo dedicado para "novo item submetido ao Comitê de Curadoria".
- O digest semanal inclui `assignment_new`, mas isso é fraco para SLA de 7 dias quando a curadoria depende de ação do comitê.

### 6.2 Evidência Cross-Pipeline — 2026-05-19

Consulta live:

| Pipeline | Estado | Contagem |
|---|---|---:|
| `board_items` | `curation_pending` + `done` | 1 |
| `publication_submissions` | `under_review` | 21 |
| `publication_submissions` | `submitted` | 8 |
| `publication_submissions` | `published` | 6 |
| `publication_ideas` | `approved` | 1 |
| `governance_documents` | `under_review` | 6 |
| `change_requests` | `submitted` | 14 |
| `change_requests` | `pending_review` | 1 |

Interpretação:

- `/admin/curatorship` representa a fila de `board_items`, não uma fila institucional completa de curadoria.
- Existem itens de publicação, docs e change requests em estados de revisão que não convergem para o Comitê.
- O workspace do Comitê continua com 3 cards bootstrap e não consome essas filas.

### 6.3 Achados Wave 2

#### C-012 — Política de email de curadoria não existe como tipo próprio

**Severidade:** HIGH
**Camada:** notification catalog / Resend

Os tipos atuais usados por curadoria são genéricos (`assignment_new`, `card_assigned`, `card_moved`) e caem em `digest_weekly`. Isso explica `email_sent_at=NULL` no caso live.

Próxima ação:

- Criar tipo explícito, por exemplo `curation_item_submitted`, com política decidida no catálogo.
- Se o objetivo é SLA rápido, mapear para `transactional_immediate`.
- Se o objetivo é reduzir ruído, manter digest mas criar seção específica de curadoria no weekly digest.

#### C-013 — Curadoria cross-pipeline ainda é promessa, não entrega

**Severidade:** HIGH
**Camada:** produto/semantic layer

Há filas paralelas relevantes:

- board items em curadoria;
- publication submissions em `submitted`/`under_review`;
- publication ideas aprovadas;
- governance docs em `under_review`;
- change requests pendentes.

Nenhuma delas compõe uma fila única do Comitê.

Próxima ação:

- Tratar `curation_queue_state` como cross-pipeline, não apenas wrapper de `board_items`.
- Definir `origin_type` e `origin_id` para `board_item`, `publication_submission`, `publication_idea`, `governance_document`, `change_request`, `webinar_proposal`.

#### C-014 — Digest semanal moderno e Edge Function legada divergem

**Severidade:** MEDIUM
**Camada:** email/digest implementation
**GitHub:** #195

Há duas superfícies:

- `get_weekly_member_digest()` rico, com `consumed_notification_ids`, seções e `weekly_member_digest`;
- Edge Function `send-notification-digest`, que consulta notificações diretamente e monta HTML próprio.

Risco:

- Um caminho pode consumir/mostrar notificações de curadoria e o outro não.
- A correção de curadoria deve escolher o caminho canônico de digest para não duplicar lógica.

Próxima ação:

- Confirmar qual job é canônico para membros.
- Se usar `get_weekly_member_digest()`, adicionar seção `curation_pending`.
- Se usar EF direta, adicionar agrupamento explícito de tipos de curadoria.

### 6.4 Docs e Testes

#### C-015 — `PERMISSIONS_MATRIX.md` / `SITE_MAP.md` estão defasados para curadoria V4

**Severidade:** MEDIUM/HIGH
**Camada:** docs/governance
**GitHub:** #196

Achados:

- `PERMISSIONS_MATRIX.md` tem última atualização 2026-03-15 e ainda descreve curadoria como tier/designation (`curator`) em vez de V4 `curate_content`.
- `SITE_MAP.md` lista `/admin/curatorship` como `observer` sem designations, e a arquitetura ainda cita MCP `64 tools`, Edge Functions `21`, pg_cron `4`.
- Isso conflita com ADR-0087 e com os números/runtime p201 já corrigidos em outros documentos.

Próxima ação:

- Atualizar `PERMISSIONS_MATRIX.md` e `SITE_MAP.md` para refletir `curate_content`, `participate_in_governance_review`, contagens runtime atuais e a diferença entre discoverability e gate real.

#### C-016 — Testes estáticos ainda validam V3/`write_board` em curadoria

**Severidade:** HIGH
**Camada:** QA

Achados:

- `tests/contracts/rpc-acl.test.mjs` ainda espera "curator designation or admin role" para RPCs de curadoria.
- `tests/contracts/rls-v4-phase4-1.test.mjs` valida `curation_review_log_write` com `write_board`, enquanto a direção de #185 é separar leitura/curadoria V4 de board-write amplo.
- `tests/ui-stabilization.test.mjs` cobre wiring básico de `CuratorshipBoardIsland`, mas não garante persona Roberto/Sarah nem bloqueia regressão de gates V4.

Próxima ação:

- Incluir esses ajustes em #194.
- Atualizar testes para `curate_content` / `participate_in_governance_review` onde for o contrato aceito.
- Adicionar teste estático que falha se reader queue voltar a `write_board`-only.

---

## 7. Wave 3 — QA/QC Operacional

### 7.1 Route Smoke — Produção

`curl -L` anônimo retornou `200` para:

| Rota | HTTP |
|---|---:|
| `/admin/curatorship` | 200 |
| `/initiative/6a93cc94-c4a0-4280-8ea7-452ec6ec48a5` | 200 |
| `/publications` | 200 |
| `/notifications` | 200 |

Interpretação:

- Não há falha de roteamento/SSR básica nas superfícies principais.
- Esse smoke não valida acesso autenticado nem RPCs da ilha; os gaps de autorização permanecem em #185/#186.

### 7.2 Logs Supabase — Últimas 24h

Evidência:

- API logs recentes mostram RPCs de board/card/notifications retornando `200`.
- Edge Function `send-notification-email` executa com `200` em cron a cada 5 min.
- `nucleo-mcp` aparece com `200/202` e um `406` isolado, sem correlação direta com curadoria.
- Postgres logs mostram alguns `permission denied for function get_pending_ratifications` / `401` em API, fora do fluxo de curadoria.

Interpretação:

- Infra de email transacional está viva; o problema de curadoria é catálogo/tipo/destinatário, não outage da Edge Function.
- Nenhum blocker novo de rota/log foi identificado para a auditoria p203.

### 7.3 Supabase Advisors

Rodado advisor de segurança como smoke geral. O output inclui achados existentes como `security_definer_view` e `rls_enabled_no_policy` em superfícies não relacionadas diretamente à curadoria. Como esta wave não alterou DDL/RLS, eles não foram abertos como novos blockers p203.

Próxima ação se for aprofundar segurança:

- Rodar uma auditoria dedicada de advisors/security drift e reconciliar com o baseline aceito do projeto.

---

## 8. Próximas Ações Recomendadas

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
11. Criar tipo de notificação/email específico para curadoria ou seção dedicada no digest.
12. Expandir `curation_queue_state` para pipelines paralelos, não só `board_items`.
13. Atualizar permissões/docs públicas para curadoria V4 e contagens runtime atuais.
14. Ajustar testes que ainda cristalizam V3/designation/`write_board` como contrato de curadoria.

