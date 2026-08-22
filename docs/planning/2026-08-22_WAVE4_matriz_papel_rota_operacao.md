# Wave 4: a matriz papel × rota × operação (Bloco B)

> Medido ao vivo em **2026-08-22**. Nenhum seed proposto: o procedimento de 4 etapas rodou na Wave 0 e
> a conclusão dela se mantém, mas **duas afirmações herdadas caíram na medição** e estão marcadas com
> ⚠️. Repositório PÚBLICO: sem nome de pessoa.
>
> **Re-medido em 2026-08-22 (segunda passada).** Uma terceira afirmação caiu, e era da própria matriz:
> a coluna do pesquisador estava errada para ata e presença. Ver §4-bis. O §7 foi reescrito com a
> medição, e a decisão 1 dele está **fechada**.

A pergunta do PM, literal: *"estas rotas de subir vídeo, agenda, ata, link de ata, link de reunião, MCP
subir tarefas, responsáveis, data, atualizar informações no board, presenças... todos estes o líder de
tribo tem que ter permissão também. Fico pensando quais destas o pesquisador da tribo deveria ter,
porque sempre tem um braço direito do líder que ajuda a manter a ordem na tribo. Desde que tenha
rastreabilidade, e talvez limitando só algumas especificidades como exclusão ou alteração para as tiers
corretas."*

---

## 1. As rotas citadas se reduzem a DUAS capacidades

| rota (nome da ferramenta MCP) | RPC por baixo | capacidade |
|---|---|---|
| evento, agenda, link de reunião (`event_write`) | `update_event`, criar, apagar | **`manage_event`** escopada + #785 |
| ata: escrever e fechar (`meeting_minutes`) | `upsert_event_minutes`, `meeting_close` | **`manage_event`** escopada + #785 |
| ações da reunião (`meeting_actions`) | criar/resolver/decisão | **`manage_event`** escopada |
| ↳ converter ação em card | `convert_to_card` | `manage_event` **+ `write_board`** |
| presença (`attendance_record`) | grava `registered_by`/`marked_by` | **`manage_event`** escopada + #785 |
| bloco de agenda (`agenda_blocks`) | escrita só com `confirm=true` | **`manage_event`** |
| board: criar, editar, mover, arquivar (`card_write`) | ver §5 | **`write_board`** |

**A rastreabilidade que o PM condiciona já existe** e é anterior a qualquer mudança: `attendance_record`
grava `registered_by`/`marked_by`, que é o que distingue auto-check-in de cobertura do líder (#1322).
Board tem `board_lifecycle_events` com `actor_member_id`. Não é pré-requisito a construir; é fato.

## 2. Quem tem cada capacidade hoje

`manage_event` em escopo `initiative`:

| kind / role | vigentes |
|---|---|
| `volunteer` / `leader` | **14** |
| `committee_member` / `leader` | 4 |
| `workgroup_member` / `leader` | 1 |
| `study_group_owner` / `leader` e `owner` | — |

`write_board`, por escopo:

| kind / role | escopo | vigentes |
|---|---|---|
| `volunteer` / `researcher` | initiative | **97** |
| `workgroup_member` / `participant` | initiative | 11 |
| `workgroup_coordinator` / `coordinator` | initiative | 6 |
| `volunteer` / `facilitator` | initiative | 1 |
| `volunteer` / `leader` | **organization** | 14 |
| `manager`, `co_gp`, `deputy_manager`, `comms_leader`, `curator` | organization | — |

Duas leituras que saem daí:

1. **O líder de tribo já tem tudo o que o PM listou.** `manage_event` escopado cobre evento, ata, ações,
   presença e agenda. Não falta permissão para ele.
2. **O `write_board` do líder de tribo é de escopo `organization`, não `initiative`.** Ele escreve em
   board de qualquer tribo por desenho do seed. Isso é anterior a esta wave e não é defeito do gate; é
   escolha de seed que vale revisar quando a Wave 3 desenhar níveis.

## 3. ⚠️ Correção: a rota de vídeo EXISTE

O arranque afirmava, e a Wave 0 repetiu, que **não existe rota** para `youtube_url`, `recording_url`,
`recording_type`, `duration_actual` nem `status`, e que "subir vídeo é impossível para qualquer papel,
inclusive GP". **Falso para vídeo e gravação.**

```
update_event(p_event_id uuid, p_title text, ..., p_meeting_link text,
             p_youtube_url text, p_is_recorded boolean, p_recording_url text, ...)
```

Gateada em **`manage_event`** e com `EXECUTE` para `authenticated`. Ou seja: **o líder de tribo já pode
subir o vídeo do próprio evento hoje**, pelo banco.

O que falta é **superfície**, não autoridade. A ferramenta MCP `event_write` chama `update_event` mas
**não expõe** `youtube_url`, `recording_url`, `recording_type`, `duration_actual` nem `status` — expõe
`meeting_link`. Há 43 eventos com `youtube_url` preenchido, então alguém escreve por outro caminho.

Isso reclassifica o item: de "criar rota e decidir quem pode" para "expor parâmetros que a RPC já
aceita". A decisão de autoridade **já está tomada** e é `manage_event`.

## 4. ⚠️ Correção: `coordinator` não é o "braço direito" completo

A Wave 0 concluiu que *"o papel `coordinator` escopado à iniciativa já é o braço direito que o PM
descreveu"*. **Meia verdade, e a metade que falta é a que importa.**

`board_write_authority` tem um ramo por engajamento com `role IN ('leader','coordinator','manager','co_gp')`
na iniciativa do board. Mas isso é **um ramo hardcoded dentro de uma função**, não uma capacidade
seedada. Medido:

| kind / role | escopo | actions | vigentes |
|---|---|---|---|
| `volunteer` / `coordinator` | organization | **só `reserve_agenda_block`** | 1 |
| `workgroup_coordinator` / `coordinator` | initiative | `view_pii`, `write`, `write_board` | 6 |

Então um `volunteer/coordinator` numa tribo escreve no board **daquela** iniciativa (pelo ramo do
`board_write_authority`) e **não tem `manage_event`** — logo, nada de ata, presença, evento ou ação de
reunião. Ele é meio braço direito: cobre a metade de board e nenhuma da metade de reunião.

## 4-bis. ⚠️ Correção: o portão das rotas de reunião não é a capacidade, e o pesquisador JÁ passa

As linhas de reunião desta matriz foram derivadas da capacidade `manage_event`. Medido no corpo vivo,
a maioria das RPCs de reunião **não pergunta pela capacidade**: pergunta por `_can_manage_event(p_event_id)`,
que tem um caminho preservado da V3:

```
IF v_caller.operational_role = 'tribe_leader' AND v_event_tribe_id = v_caller.tribe_id THEN RETURN true;
IF v_caller.operational_role = 'researcher'   AND v_event_tribe_id = v_caller.tribe_id THEN RETURN true;
IF v_event.created_by = v_caller.id THEN RETURN true;
```

Chame-o de **Path Y**. Ele concede por `operational_role` e por tribo, **fora do catálogo de capacidades**.
As RPCs de reunião se dividem em dois grupos, e a divisão é o corte real:

| portão | RPCs | pesquisador da própria tribo |
|---|---|---|
| `_can_manage_event` (**tem Path Y**) | `mark_member_present`, `clear_member_attendance`, `admin_bulk_mark_attendance`, `seal_event_attendance`, `unseal_event_attendance`, `preview_seal_attendance`, `upsert_event_minutes`, `upsert_event_agenda`, `manage_action_items` | **passa** |
| `_manage_event_scope_ok` (só capacidade, escopada) | `meeting_close`, `register_attendance_batch`, `create_action_item`, `resolve_action_item`, `update_event_instance`, `drop_event_instance`, `mark_member_excused`, `register_decision` | não passa |

Logo **o pesquisador já lança presença e já escreve ata** na própria tribo. `upsert_event_minutes` tem
inclusive uma janela explícita para ele: pode editar dentro de 72h do evento, e quem tem `manage_event`
não tem essa trava.

### A afordância existe e ninguém usa

| superfície | GP | co-GP | líderes de tribo | pesquisadores |
|---|---|---|---|---|
| presença lançada por outrem (`marked_by`) | 101 linhas / 6 eventos | 132 / 9 | 50 / 10 eventos (5 pessoas de 13) | **0** |
| ata (`minutes_posted_by`) | 23 eventos | 19 | 22 (5 pessoas) | **0** |

São **55 pesquisadores ativos** com a permissão e **zero** uso nas duas superfícies. E a cobertura mostra
onde a dor está: das **137 reuniões de tribo dos últimos 120 dias, 122 têm presença (89%) e 36 têm ata
(26%)**; 15 não têm nenhuma das duas.

📌 Isto instancia `reference-a-regra-ja-existe-na-rpc-e-a-ui-nao-a-chama` na direção inversa: a
autoridade já existe no banco, e o que falta é superfície e prática. Também instancia
`reference-zero-linhas-hoje-nao-e-ausencia-de-risco`: `clear_member_attendance` e
`seal_event_attendance` estão no grupo do Path Y, então 55 pessoas podem limpar e selar presença da
própria tribo, e isso toca o selo do #1710.

---

## 5. O achado central: não existe UM modelo de autoridade para board

A pergunta do PM pressupõe que dá para "limitar exclusão e alteração às tiers corretas". Medido, cada
RPC de board tem **portão próprio, escrito à mão, e eles não concordam entre si**:

| RPC | portão |
|---|---|
| `create_board_item` | composto próprio: `is_gp` OU `is_leader` OU `is_tribe_member` |
| `update_board_item` | `write_board` (+ `manage_platform`), checa superadmin |
| `move_board_item` | `write_board`, checa superadmin |
| `delete_board_item` | `write_board` **OU** ser o responsável do card **OU** `board_members` com papel `admin`/`editor`, mais `rls_can_see_item` |
| `admin_archive_board_item` | superadmin **OU** `manage_member` **OU** designation `co_gp` **OU** líder da própria tribo |
| `move_item_to_board` | `board_write_authority`, que tem **7 ramos** |

⚠️ **Correção de leitura minha, feita ao ler o corpo em vez do nome:** `delete_board_item` **não apaga**.
Ele faz `UPDATE board_items SET status='archived'` e grava em `board_lifecycle_events`. É arquivamento
suave, reversível e auditado. Portanto **não existe operação destrutiva de card** para restringir - a
premissa de "exclusão" da pergunta não se aplica como se imagina.

O que existe de assimétrico é isto: **`delete_board_item` (arquivar via a ação chamada "delete") pede
menos que `admin_archive_board_item` (arquivar via admin)**. Duas rotas para o mesmo efeito, com
autoridades diferentes. Isso é dívida de consistência, não brecha.

📌 Há resíduo desta classe em outras RPCs de board, rastreado no security advisory privado do
repositório. Entra no inventário da wave de consistência.

## 6. A matriz, como ela ESTÁ hoje

`✔` = pode · `✖` = não pode · `~` = pode por caminho lateral

| rota / operação | GP e co-GP | líder de tribo | `workgroup_coordinator` | pesquisador |
|---|---|---|---|---|
| evento: criar, editar, apagar | ✔ | ✔ (própria) | ✖ | ✖ |
| vídeo e gravação (`update_event`) | ✔ | ✔ (própria) | ✖ | ✖ |
| ata: **escrever** | ✔ | ✔ (própria) | ✖ | **✔ (própria, 72h)** |
| ata: **fechar** (`meeting_close`) | ✔ | ✔ (própria) | ✖ | ✖ |
| ações da reunião | ✔ | ✔ (própria) | ✖ | ~ (`manage_action_items` sim; criar/resolver não) |
| converter ação em card | ✔ | ✔ | ✖ | ✖ |
| presença: marcar e limpar | ✔ | ✔ (própria) | ✖ | **✔ (própria)** |
| presença: selar e dessellar | ✔ | ✔ (própria) | ✖ | **✔ (própria)** |
| presença: lote e abonar | ✔ | ✔ (própria) | ✖ | ✖ |
| bloco de agenda | ✔ | ✔ | ~ (`reserve_agenda_block`) | ~ (`reserve_agenda_block`) |
| board: criar card | ✔ | ✔ | ✔ (própria) | ✔ (própria) |
| board: editar card | ✔ | ✔ | ✔ | ✔ |
| board: arquivar card ("delete") | ✔ | ✔ | ✔ | ✔ |
| board: arquivar via admin | ✔ | ✔ (própria) | ✖ | ✖ |

A linha que responde a pergunta do PM: **o pesquisador já cria, edita e arquiva card, e já escreve ata
e lança presença na própria tribo**. O corte hoje não é entre `write_board` e `manage_event`: é entre as
RPCs que passam por `_can_manage_event` (Path Y, e o pesquisador passa) e as que passam por
`_manage_event_scope_ok` (só capacidade, e ele não passa). Ver §4-bis.

⚠️ A versão anterior desta matriz dizia `✖` para o pesquisador em ata, ações e presença. Estava errada:
foi derivada da capacidade seedada, e não do portão que as RPCs realmente chamam.

## 7. O que decidir

1. ✅ **FECHADA em 2026-08-22: o "braço direito" não vira papel novo.** A pergunta pressupunha que o
   pesquisador estivesse bloqueado. Ele não está: pelo Path Y (§4-bis) ele já lança presença e já
   escreve ata na própria tribo, e **55 pesquisadores ativos nunca exerceram nem uma nem outra**. Criar
   `volunteer/deputy_leader` com `manage_event` escopado concederia o que já existe, e o efeito
   previsto é zero. A lacuna medida é de **cobertura de ata (26% das 137 reuniões)**, que é problema de
   superfície e de prática, não de autoridade. **Nenhum seed proposto**, portanto o procedimento de 4
   etapas do `V4_AUTHORITY_MODEL.md` não é acionado.
2. ~~Se for papel novo, ele nasce como `role` sob `kind='volunteer'`.~~ Prejudicada pela decisão 1. Fica
   registrado, para quem retomar: **não reaproveitar `coordinator`**, que já existe com outro
   significado e outro conjunto (§4).
3. **Restrição, e agora ela tem alvo.** Não há operação destrutiva de card a restringir (§5), mas há em
   presença: `clear_member_attendance`, `seal_event_attendance` e `unseal_event_attendance` estão no
   grupo do Path Y, logo os 55 pesquisadores podem limpar, selar e dessellar presença da própria tribo.
   Isso alimenta o selo do #1710. **Decisão em aberto:** manter Path Y como está, ou tirar dele as três
   RPCs de limpar/selar, deixando ata, agenda e marcar presença. É restrição, não concessão, e não
   depende de seed nenhum.
4. **Fechar ata (`meeting_close`) continua fora do Path Y** e exige a capacidade escopada. Nenhuma
   mudança proposta; fica registrado que o corte já está onde a pergunta do PM sugeria colocá-lo.
5. **Consistência dos portões de board** (§5): seis RPCs, seis portões diferentes. Vale unificar em
   `board_write_authority`, mas é refactor, não permissão, e deve entrar como wave própria.
6. **Expor os parâmetros de vídeo no `event_write`** (§3). Não é decisão de autoridade, é de escopo de
   ferramenta.
