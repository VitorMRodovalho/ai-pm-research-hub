# EPIC #1780, Fase 1 — o mapa medido do domínio board / card / tarefa

> Auditoria, não correção. Medido em **15/08/2026** por consulta viva; os números se movem, e a
> regra da casa vale aqui: re-medir antes de usar qualquer um deles numa decisão.
>
> O detalhe do achado de segurança **não** está neste arquivo (repositório é público). Ele foi
> corrigido antes de ser descrito, e o relato está na issue #1784.

O EPIC nasceu de uma queixa de campo — "sou autor e contribuidor do card e não consigo inserir
atividade" — que revelou **três defeitos de causas independentes** na mesma tarde. A Fase 1 pedia
medir antes de propor. As cinco varreduras abaixo foram executadas; o corte da Fase 2 é decisão do
PM, tomada com este mapa na mão.

---

## 1 · Sobrecargas

Varridas todas as `proname` duplicadas em `public`. Fora das funções do `citext` (extensão), existem
quatro: `create_notification` (3 assinaturas), `get_board_activities` (2),
`get_offboarded_member_emails` (2) e `set_site_config` (2). Procedimentos e agregados: **zero**.

**No domínio board/card há exatamente uma sobrecarga**, e é a que o #1779 já registra. A pergunta do
EPIC ("quantas mais existem") tem resposta: nenhuma.

## 2 · Portas agregada × varejo

Para cada entidade-filha do card, a leitura existe em SQL? E está exposta no semântico?

| entidade | agregada (por board) | varejo (por card) | exposta no MCP |
|---|---|---|---|
| checklist / tarefa | existe (`get_board_activities` 4-arg) | `get_card_detail` | **só o varejo** (é o #1779) |
| comentário | **não existe** | `list_card_comments` | só o varejo |
| anexo / arquivo | **não existe** | `list_card_drive_files` | só o varejo |
| papel no card | `get_board` | `get_item_assignments` | leitura em `card_get.assignments`; escrita: ver §5 |
| tag | `get_board_tags` | dentro do card detail | agregada |
| drive do board | `get_board_drive_links` | `list_card_drive_files` | as duas |
| log de ciclo de vida | `get_board_activities` 2-arg | `get_card_timeline` | as duas |

Duas formas distintas de "porta quebrada", e elas pedem correções diferentes: a que **existe e não é
exposta** (tarefa) e a que **não existe em lugar nenhum** (agregada de comentário e de anexo).

## 3 · Gates sem recurso

**Escrita.** Três policies do domínio decidem só por capacidade e nunca olham o recurso, não uma:
`board_item_checklists`, `board_item_assignments` e `board_item_tag_assignments` (as três com
`rls_is_superadmin() OR rls_can('write') OR rls_can('write_board')`).

O achado que mudou o escopo do #1778: **a regra de autoria que a issue pedia já existia**, e no lugar
certo. `add/update/delete_checklist_item` já autorizavam `write_board` **ou** responsável do card
**ou** `board_members` admin/editor. São `SECURITY DEFINER` de dono `postgres` sobre tabela do mesmo
dono com `force_rls=false`, logo contornam a RLS. **A UI não as chamava:** `CardDetail.tsx` fazia
`INSERT` e `DELETE` diretos na tabela — o **único** acesso direto do domínio inteiro — enquanto
`complete` e `assign` já passavam pelas RPCs.

Duas consequências que a issue não registrava: o `INSERT` falhava em silêncio e o `DELETE` sumia com
a linha da tela mesmo quando o banco recusava.

**População.** 64 pessoas carregam trabalho atribuído; 15 estão sem `write_board`. Contar barrados
por essa capacidade dá 3 — mas a policy tem **três ramos**, e 2 das 3 passavam por
`rls_is_superadmin()`. **Barrado de verdade: 1 pessoa.** `board_members`, a terceira noção de
autoridade do domínio, tem **2 linhas na plataforma inteira**.

**Leitura.** A mesma varredura, no sentido inverso, encontrou tabelas-filhas do card sem o gate de
visibilidade confidencial (ADR-0105). Corrigido e descrito na #1784.

## 4 · Divergência UI × MCP

A mesma ação, "adicionar atividade ao card", tinha **quatro** definições de autoridade:

1. o gate de tela (`useBoardPermissions.ts`: tabela `ROLE_TIER` + `canFor`), que decide se o botão aparece;
2. a policy RLS, só capacidade, que decidia a escrita direta;
3. a RPC, capacidade **ou** recurso;
4. o MCP, que exigia `canV4('write_board')` **antes** de chamar a RPC — ou seja, **mais estrito que a
   RPC que ele mesmo chama**.

Vocabulário: "Atividades" é *checklist item* na UI e *log de lifecycle* no `board_overview` — três
nomes para dois conceitos, que é o #1779.

## 5 · Cobertura

**13 verbos** que a UI usa no domínio não têm porta em superfície MCP nenhuma (nem semântico, nem
raw, nem `/actions`):

- **ciclo de curadoria (8):** `submit_for_curation`, `advance_board_item_curation`,
  `complete_peer_review`, `complete_leader_review`, `curate_item`,
  `list_curation_pending_board_items`, `publish_board_item_from_curation`,
  `get_item_curation_history`
- **papéis no card (3):** `assign_member_to_item`, `unassign_member_from_item`, `get_item_assignments`
- **outros (2):** `get_board_item_drive_access`, `admin_manage_board_member`

Conferido por duas fontes independentes: os 418 nomes de tool registrados no EF e as 323 RPCs
efetivamente despachadas por ele.

Os **papéis no card** eram justamente o vocabulário da queixa que abriu o EPIC ("sou autor e
contribuidor"), e a entidade que a RLS ignorava. A leitura já existia em `card_get.assignments`; a
escrita entrou em `card_write` (`assign_role` / `unassign_role`).

---

## O que a Fase 2 fez com o mapa

| corte | resultado |
|---|---|
| #1784 — gate confidencial nas tabelas-filhas | fechado, com guard derivado por FK em vez de lista |
| #1778 — autoria vira predicado único, UI re-roteada | fechado, com o caminho exercido por impersonação |
| #1780 — papéis do card no semântico | `card_write assign_role` / `unassign_role` |

## O que segue aberto

- **#1779** — a porta agregada de tarefas e o desfazer da colisão de nome (`get_board_activities`
  significando log numa assinatura e tarefas na outra).
- **Agregada de comentário e de anexo** — não existem nem em SQL.
- **Escrita** de `board_item_assignments` e `board_item_tag_assignments`, que decide por capacidade
  organizacional sem olhar o recurso: mesma classe do #1778, outras tabelas.
- **Curadoria no semântico** — 8 verbos, decisão de escopo do PM.
- **#1777** — o fluxo que gravou o papel divergente (o dado já foi normalizado).
- **Quatro definições de autoridade** para a mesma ação: duas foram reconciliadas (RPC e MCP), o gate
  de tela e a policy seguem como estão.
