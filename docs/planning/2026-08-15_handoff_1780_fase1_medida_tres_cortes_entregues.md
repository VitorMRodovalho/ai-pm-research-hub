# Handoff — a Fase 1 do #1780 virou mapa, e três cortes saíram dele

> Sessão de 15/08/2026. Arranque: `2026-08-15_PROMPT_ARRANQUE_EPIC_1780_FASE1_E_1710.md`
> Anterior: `2026-08-14_handoff_1710_medido_1587_fechado_1586_com_autor.md`

## Regra zero

Todo número aqui foi medido por consulta viva em 15/08. Um deles **mudou durante a própria sessão**
e a correção está registrada abaixo, porque a forma do erro é reaproveitável.

---

## Estado

`main` em **`ce5f0276`**. **Zero PRs abertas.** **3 merges, zero bypass** (#1785 12/12, #1787 12/12,
#1788 11/11).

Em produção fora de PR (atos, não código): 5 migrations aplicadas via `apply_migration` (todas com
arquivo local no timestamp da linha de tracking e md5 normalizado conferido contra o vivo), e a EF
`nucleo-mcp` deployada **duas vezes** — `/health` responde **`ef_version: 2.100.0`**.

---

## Fase 1 do #1780: as cinco varreduras, medidas

Mapa completo em `docs/audit/EPIC_1780_FASE1_MAPA_BOARD_CARD.md`. Em uma linha cada:

1. **Sobrecargas** — 4 em `public` fora do citext; **exatamente 1 no domínio**, a do #1779. A
   pergunta do EPIC tem resposta: não há outras.
2. **Portas** — duas formas distintas de porta quebrada: a que **existe e não é exposta** (tarefa) e
   a que **não existe nem em SQL** (agregada de comentário e de anexo).
3. **Gates sem recurso** — **3** policies de escrita, não 1. E o achado que mudou o escopo do #1778:
   a regra de autoria **já existia na RPC**; a UI é que escrevia a tabela direto.
4. **UI × MCP** — **4** definições de autoridade para "adicionar atividade", e o MCP era a mais
   **estrita**, mais que a própria RPC que ele chama.
5. **Cobertura** — **13** verbos da UI sem porta em superfície MCP nenhuma. Conferido por duas fontes
   independentes (418 nomes de tool, 323 RPCs despachadas).

---

## Os três cortes entregues

### #1784 — o gate confidencial alcança as tabelas-filhas do card (fechada)

Antes/depois exercidos por impersonação, com um membro que não enxerga o board confidencial e **tem**
`write_board`: **25 → 0** linhas de papéis e **100 → 0** de log. Controle inverso intacto (893 e 3236
fora do confidencial seguem visíveis; os totais fecham em 918 e 3336).

O guard deixou de ser lista: `_audit_confidential_gate_coverage()` **deriva as filhas por chave
estrangeira** e classifica a forma do gate (`explicito` | `transitivo` | `sem_leitura` | `ausente`).
As quatro formas foram exercidas com dado real. 10 filhas de outros domínios seguem sem gate, todas
com **zero** linhas confidenciais hoje, numa linha de base que só encolhe.

### #1778 — a autoria vira predicado único (fechada)

`can_manage_card_checklist` é a fonte única das 4 RPCs e do fail-fast do MCP. A UI saiu do `INSERT` e
do `DELETE` diretos (era a **única** tabela do domínio escrita direto).

| ato | resultado |
|---|---|
| responsável sem capacidade, `INSERT` direto | **42501** RLS |
| o mesmo, pela RPC | **passa** |
| sem vínculo com o card, pela RPC | **P0001** |
| com `write_board` e sem ver a iniciativa confidencial | **P0001** (antes: escrevia) |
| `anon` nas 5 RPCs + predicado | **HTTP 404** |

### #1780 — os papéis do card no semântico

`card_write assign_role` / `unassign_role`, **sem** o `canV4('write_board')` do resto da tool: a
autoridade é a da própria RPC. A leitura já existia em `card_get.assignments` (conferido, não
suposto).

**Critério de saída nº 1 do EPIC, medido:** 52 pessoas ativas com trabalho atribuído, **52 com
caminho, 0 sem**.

---

## Duas lições que custaram tempo nesta sessão

**1. Contar barrados por uma capacidade quando a policy tem três ramos.** A população do #1778 foi
medida por `can_by_member('write_board')` e deu **3**. A policy é
`rls_is_superadmin() OR rls_can('write') OR rls_can('write_board')`: **2 das 3 pessoas passavam por
superadmin**. Barrado de verdade: **1**. O erro só apareceu porque a sonda de impersonação foi feita
com um sujeito real — e ele passou onde deveria falhar.

**2. O CI achou um buraco que a auditoria não tinha achado.** O guard
`785-secdef-reader-confidential-gate` ficou vermelho acusando o predicado novo como leitor SECDEF sem
gate. Não era falso positivo: `SECURITY DEFINER` contorna a RLS, e quem tinha `write_board` sem
enxergar a iniciativa confidencial **escrevia** nos cards dela pela RPC. O MCP já fazia esse
fail-fast como contrato; o caminho por PostgREST não tinha ninguém.

---

## Próxima sessão

1. **#1710 (prazo 24/08):** re-medir **na véspera** — o número encolhe com registro de presença. Fica
   de pé a pendência do PM sobre as **7 células** que nenhum líder de tribo alcança.
2. **#1779** — porta agregada de tarefas + desfazer a colisão de nome. É o corte natural seguinte do
   #1780, e a Fase 1 já confirmou que é caso único no domínio.
3. **Escrita** de `board_item_assignments` e `board_item_tag_assignments` — mesma classe do #1778,
   outras tabelas, ainda por capacidade sem olhar o recurso.
4. **#1586** fecha na primeira chamada real de `rescue_unbooked` (conferir `actor_id` não nulo +
   `dispatch_source='manual'`). **Despachar é decisão do PM.**
5. **Funil, prazo 28/08** — falta `booked_at`. Nenhum número de conversão pode ser publicado antes.
6. **#1783** — 8 alertas Dependabot em 3 lotes; `astro` é major 6→7. PR local de higiene, nunca
   mergear Dependabot (#611).
