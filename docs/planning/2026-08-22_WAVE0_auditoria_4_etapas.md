# Wave 0: auditoria de 4 etapas (V4_AUTHORITY_MODEL) para a camada tática

> Medido ao vivo em **2026-08-21**. Procedimento obrigatório de `docs/reference/V4_AUTHORITY_MODEL.md`
> antes de qualquer proposta de seed. **Nenhum seed é proposto aqui**: esta wave só produz a base de
> evidência. Repositório PÚBLICO: sem nome de pessoa.

Actions auditadas (as 8 que existem em escopo `initiative`, que é o escopo da camada tática):
`write_board`, `manage_event`, `manage_initiative`, `manage_member`, `manage_board_admin`, `view_pii`,
`award_champion`, `write`.

---

## Etapa 1 - combos seedados

| action | `initiative` | `organization` |
|---|---|---|
| `write_board` | **16** | 6 |
| `view_pii` | 7 | 4 |
| `write` | 6 | 5 |
| `award_champion` | 5 | 4 |
| `manage_board_admin` | 5 | 3 |
| `manage_event` | 5 | 4 |
| `manage_initiative` | 5 | 3 |
| `manage_member` | **4** | 3 |

Três leituras:

1. **O bloco de "líder de estrutura" é uniforme.** `award_champion`, `manage_board_admin`,
   `manage_event` e `manage_initiative` têm exatamente os mesmos 5 combos em escopo `initiative`:
   `committee_member/leader`, `study_group_owner/leader`, `study_group_owner/owner`, `volunteer/leader`,
   `workgroup_member/leader`. Liderar uma estrutura já é um pacote coerente.
2. **`manage_member` escopado exclui o líder de tribo de propósito.** São os mesmos 5 combos **menos**
   `volunteer/leader`. Ou seja, líder de tribo administra evento, board e iniciativa da própria tribo,
   e **não** administra quem entra e sai dela. Isso é carve-out deliberado, não lacuna.
3. **`write_board` já é largo**: 16 combos em escopo `initiative`, incluindo `volunteer/researcher`,
   `workgroup_member/participant`, `study_group_participant/participant` e os quatro papéis de
   `speaker`. Escrever em board não é privilégio de liderança hoje.

## Etapa 2 - RPCs que consomem cada action, e se o portão é puro ou composto

| action | RPCs | portão composto (há OR com outra capacidade) | com scoping inline | com gate de designation |
|---|---|---|---|---|
| `manage_member` | 174 | 52 | 22 | 2 |
| `manage_event` | 58 | 16 | 4 | 0 |
| `view_pii` | 25 | 8 | 3 | 0 |
| `write_board` | 24 | 15 | 0 | 6 |
| `write` | 7 | 3 | 0 | 0 |
| `manage_board_admin` | 3 | 3 | 0 | 0 |
| `award_champion` | 3 | **0** | 0 | 0 |
| `manage_initiative` | 2 | 1 | 2 | 0 |

⚠️ **Armadilha de método, registrada porque quase passou.** A primeira rodada desta etapa devolveu
"0 portões compostos" para **todas as 8 actions**. Resposta uniforme não é medição. A causa era a
regex: em Postgres a fronteira de palavra é `\y`, e **`\b` significa backspace**, então `\yOR\y` casa e
`\bOR\b` nunca casa. Controle usado para pegar o erro:

```sql
select ('... OR ...' ~ '\bOR\b') as com_b,   -- false, sempre
       ('... OR ...' ~ '\yOR\y') as com_y;   -- true
```

Também vale: o limite de repetição de regex do Postgres é 255, então `[^;]{0,300}` é erro de sintaxe.

Leitura: `award_champion` é a única action **sem nenhum caminho alternativo** (3 RPCs, todos com portão
puro). As demais têm alternativa em pelo menos parte da superfície, que é exatamente o falso positivo
contra o qual o procedimento existe.

## Etapa 3 - gates baseados em designation

| designation | RPCs | funções |
|---|---|---|
| `co_gp` | **7** | `assign_curation_reviewer`, `board_write_authority`, `complete_checklist_item`, `create_board_item`, `get_tribe_event_roster`, `move_board_item`, `update_board_item` |
| `comms_leader` | 5 | `board_write_authority`, `create_board_item`, `create_card_comment`, `move_board_item`, `update_board_item` |
| `curator` | 5 | leitura de board, documento de governança, org chart |
| `voluntariado_director` | 5 | ciclo do termo de voluntariado |
| `sponsor` | 4 | funil, impacto, roteamento de seleção |
| `chapter_board` | 3 | `_can_sign_gate`, termo de voluntariado |
| `chapter_liaison` | 1 | `_can_sign_gate` |
| **`deputy_manager`** | **1** | `get_tribe_event_roster` |
| `legal_signer` | 1 | `_can_sign_gate` |

Achado que muda o Bloco B: **escrita em board já tem caminho por designation**, e `co_gp` é o mais
usado dos nove. Confirma o anexo §6 do desenho: `deputy_manager` quase não existe no backend (1 RPC),
enquanto `co_gp` sustenta 7.

## Etapa 4 - RPCs SECURITY DEFINER com scoping inline

De **1.120** funções SECDEF em `public`:

| mecanismo | funções |
|---|---|
| `rls_can_see_initiative` (gate #785) | 50 |
| `v_caller_person_id` | 35 |
| `v_caller_chapter` | 10 |
| `v_caller_tribe_id` | 4 |

O gate de confidencialidade (#785) é o mecanismo de escopo mais adotado, com folga. O scoping por tribo
é o menos usado (4), o que é coerente com a migração para o primitivo `initiative`.

---

## Conclusão da Wave 0

**Nenhum gap novo justifica seed hoje.** O que a auditoria mostra é o contrário do que uma leitura
mecânica sugeriria:

- o mecanismo de escopo por iniciativa existe, é uniforme para "líder de estrutura", e já tem carve-out
  pensado em `manage_member`;
- `write_board` já alcança o pesquisador, então o **"braço direito" do Bloco B não precisa de action
  nova** - precisa de decisão sobre *qual papel* e sobre o que ele **não** pode (exclusão e alteração),
  que é restrição, não concessão;
- `board_write_authority` já implementa uma cadeia de 7 ramos alternativos, incluindo um ramo por
  engajamento com `role IN ('leader','coordinator','manager','co_gp')` na iniciativa do board. **O papel
  `coordinator` escopado à iniciativa já é, hoje, o "braço direito" que o PM descreveu**, sem seed novo.

Fica um achado de autorização levantado nesta wave que **não entra em repositório público**. Ele foi
arquivado como **security advisory privado do repositório** (draft), com mecanismo, prova, raio
medido e correção candidata. Precisa ser decidido **antes da Wave 3**, porque toca o mesmo mecanismo de
escopo que a camada tática vai usar.

---

## Decisão do PM registrada nesta sessão

**Bloco C (aba Membros da tribo):** mesclar as seleções, **mas em bloco separado e rotulado**. Roster de
vínculo em cima, "interessados nesta rodada" à parte. Exige limitar a janela, senão a lista cresce para
sempre. Entra como Wave 2.
