# Wave 4: a matriz papel × rota × operação (Bloco B)

> Medido ao vivo em **2026-08-22**. Nenhum seed proposto: o procedimento de 4 etapas rodou na Wave 0 e
> a conclusão dela se mantém, mas **duas afirmações herdadas caíram na medição** e estão marcadas com
> ⚠️. Repositório PÚBLICO: sem nome de pessoa.

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
| ata: escrever e fechar | ✔ | ✔ (própria) | ✖ | ✖ |
| ações da reunião | ✔ | ✔ (própria) | ✖ | ✖ |
| converter ação em card | ✔ | ✔ | ✖ | ✖ |
| presença | ✔ | ✔ (própria) | ✖ | ✖ |
| bloco de agenda | ✔ | ✔ | ~ (`reserve_agenda_block`) | ~ (`reserve_agenda_block`) |
| board: criar card | ✔ | ✔ | ✔ (própria) | ✔ (própria) |
| board: editar card | ✔ | ✔ | ✔ | ✔ |
| board: arquivar card ("delete") | ✔ | ✔ | ✔ | ✔ |
| board: arquivar via admin | ✔ | ✔ (própria) | ✖ | ✖ |

A linha que responde a pergunta do PM: **o pesquisador já cria, edita e arquiva card**, e **não toca em
nada de reunião**. O corte hoje é exatamente entre `write_board` e `manage_event`.

## 7. O que decidir

1. **O "braço direito" precisa de `manage_event` escopado, ou só de board?** Se a dor é "manter a ordem
   na tribo" no sentido de cards, ele **já pode** e não há nada a fazer. Se é lançar presença e escrever
   ata quando o líder falta, então é `manage_event` escopado, e aí sim é papel novo.
2. **Se for papel novo, ele nasce como `role` sob `kind='volunteer'`** (para herdar o escopo de
   iniciativa da tribo), com `manage_event` + `write_board` em escopo `initiative`. Sugestão de nome:
   `deputy_leader`. **Não usar `coordinator`**: já existe com outro significado e outro conjunto.
3. **Restrição pedida ("exclusão e alteração para as tiers corretas"):** não há operação destrutiva de
   card a restringir (§5). A restrição faz sentido em **evento** (`update_event` altera data, link e
   gravação) e em **fechar ata** (`meeting_close`, que é o ato que congela o registro). Decidir se o
   braço direito fecha ata ou só escreve.
4. **Consistência dos portões de board** (§5): seis RPCs, seis portões diferentes. Vale unificar em
   `board_write_authority` — mas é refactor, não permissão, e deve entrar como wave própria.
5. **Expor os parâmetros de vídeo no `event_write`** (§3). Não é decisão de autoridade, é de escopo de
   ferramenta.
