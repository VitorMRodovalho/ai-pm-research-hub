# Arranque: governança da liderança - rastreio das ações, board de gestão, permissão por papel

> Tudo abaixo foi medido ao vivo em **21-22/08/2026** (horários em UTC). **Re-medir antes de agir**:
> número recitado de handoff não vale como medição.
> Repositório PÚBLICO: sem nome de pessoa, sem identificador de candidato, em issue, PR ou commit.

---

## 0. De onde isto vem

A lane de vídeo fechou a Reunião de Liderança #10: ata de 10.637 chars, 26 ações rastreáveis com
responsável e prazo, presença de 11 para 15, vídeo publicado. **Mas as 26 ações pararam em
`meeting_action_items` e nenhuma virou card em board.** E o PM levantou, em cima disso, quatro perguntas
que não são de execução, são de desenho. Este arranque existe para respondê-las com medição, não com
opinião.

---

## 1. Bloco A: as ações da liderança não têm casa

### Estado medido

| medida | valor |
|---|---|
| ações criadas no evento `f77a91d2-5211-4ed8-b197-5616d8e7d692` | **26** |
| com responsável | 26 |
| com prazo | 26 |
| **convertidas em card de board** | **0** |

`meeting_actions` tem a rota `action='convert_to_card'`, que exige `board_id` e a capacidade
`write_board`. Ela existe e não foi usada, porque não estava claro **para qual board** essas ações vão.

### O board já existe, e é confidencial

A pergunta do PM era "fico até pensando se eu não tinha que ter um board de gestão oculto aos demais,
ou se já até existe". **Já existe.** Medido em `project_boards` com `initiative_id` sem tribo:

| board | visibilidade | itens | ativo |
|---|---|---|---|
| **GP × Presidência - Governança do Núcleo** | **`confidential`** | 25 | sim |
| Hub de Comunicação | standard | 69 | sim |
| CPMAI Prep Course - Design | standard | 36 | sim |
| Publicações & Submissões PMI | standard | 32 | sim |
| Kickoff Ciclo 4 + Onboarding dos Líderes | standard | 30 | sim |

O mecanismo de ocultação é o do **ADR-0105 / #785**: `initiatives.visibility='confidential'` exclui
board, eventos, artefatos e documentos do read-all de Tier 1+, deixando visível só para quem tem
engajamento na iniciativa mais GP (`manage_platform`). O gate é `rls_can_see_initiative()`.

### O que decidir, e é decisão do PM

1. As ações da liderança vão para o board confidencial existente, para um board novo de rito de
   liderança, ou ficam só em `meeting_action_items`?
2. **Nem toda ação é confidencial.** Das 26, a maioria é operação de tribo ("apresentar o artefato na
   próxima reunião") e caberia no board da própria tribo, visível ao time. Uma minoria é sensível
   (conversa individual sobre desempenho, afastamento). Se tudo for para o board confidencial, o líder
   de tribo perde o acompanhamento do que é dele.
3. Se houver split, ele precisa de **critério declarado**, senão vira julgamento caso a caso.

### Itens da reunião que o PM citou e que NÃO viraram ação

Levantados por ele depois, e ausentes das 26:

- melhorar a jornada da própria reunião de liderança
- agrupar um one-pager de métricas das tribos (existe uma ação de one-pager, mas de presença e cartões,
  não de métricas por tribo)
- desligamentos pendentes em algumas tribos
- reuniões duplicadas ou inexistentes constando no calendário de tribos

📌 Os dois últimos conversam direto com o Bloco C.

---

## 2. Bloco B: o modelo de permissão por papel

### A pergunta do PM, literal

> "estas rotas de subir vídeo, agenda, ata, link de ata, link de reunião, MCP subir tarefas,
> responsáveis, data, atualizar informações no board, presenças... todos estes o líder de tribo tem que
> ter permissão também. Fico pensando quais destas o pesquisador da tribo deveria ter, porque sempre tem
> um braço direito do líder que ajuda a manter a ordem na tribo. Desde que tenha rastreabilidade, e
> talvez limitando só algumas especificidades como exclusão ou alteração para as tiers corretas."

### O que já se sabe, medido

- `event_write` gateia por `manage_event` **escopado à iniciativa do evento** (migração 455 fechou o
  gate resourceless). Ou seja, líder de tribo já edita evento da própria tribo e não da alheia.
- `meeting_minutes` write/close: mesmo gate, escopado.
- `meeting_actions` create/resolve/decision: mesmo gate. `convert_to_card` **soma** `write_board`.
- `attendance_record`: `manage_event` escopado + #785, e grava `registered_by`, que é o que distingue
  auto-check-in de cobertura de líder (#1322). **A rastreabilidade que o PM pede já existe nessa rota.**
- **Não existe rota** para `youtube_url`, `recording_url`, `recording_type`, `duration_actual` nem
  `status` (issues #912, #1601, #1916). Então "líder sobe vídeo" hoje é impossível para qualquer papel,
  inclusive GP.
- Medição de 2026-08-21 já registrada: **145 RPCs de leitura pedem capacidade de GP**, o que sugere que
  o modelo foi exercido quase só por GP e os portões intermediários estão pouco testados.

### O que decidir

1. Matriz **papel × rota × operação** (criar / editar / apagar), cobrindo pelo menos: líder de tribo,
   braço direito (papel que **ainda não existe** como `engagement kind`), pesquisador, GP.
2. Se "braço direito" vira papel novo, ele nasce como `engagement kind` com combos em
   `engagement_kind_permissions`, **e o procedimento de 4 etapas do `docs/reference/V4_AUTHORITY_MODEL.md`
   é obrigatório antes de propor qualquer seed.** Auditoria mecânica dessa tabela produz falso positivo
   recorrente (sedimento p122e).
3. ⚠️ **Anti-padrão documentado:** "seed expansion como atalho" em ações destrutivas (`manage_member`,
   `manage_platform`) cria escalada de privilégio e viola a invariante de que ciclo de vida de membro é
   só-GP (LGPD Art. 18). A intuição do PM de "limitar exclusão e alteração às tiers corretas" está
   alinhada com isso e deve virar regra escrita, não convenção.

---

## 3. Bloco C: a página de membros da tribo mostra quem já saiu

### O relato

O PM notou, durante a reunião, que a página de membros da tribo do líder da **tribo 5** ainda lista
pessoas que saíram. Hipótese dele: *"o SQL daquela página não está com o filtro de se a pessoa continua
na tribo, e simplesmente capturando a coluna seca da tabela se a pessoa já esteve na tribo."*

### O que a medição diz, e ela INVERTE a hipótese

Primeiro erro foi meu: medi vínculo ativo por `end_date IS NULL` e achei 66 contra 10, o que parecia
catástrofe. **Errado.** `engagements.kind='volunteer'` tem 151 linhas e só 12 com `end_date` nulo,
porque `end_date` guarda o **fim do ciclo**, que é futuro. O teste correto é
`end_date IS NULL OR end_date >= CURRENT_DATE`.

Refeito, por tribo:

| tribo | coluna seca `members.tribe_id` | vínculo vigente | **já saiu** |
|---|---|---|---|
| 1 | 8 | 8 | 5 |
| 2 | 0 | 0 | 7 |
| 4 | 6 | 6 | 2 |
| **5** | **2** | **2** | **4** |
| 6 | 8 | 8 | 2 |
| 7 | 5 | 6 | 5 |
| 8 | 7 | 8 | 1 |
| 9 | 7 | 7 | 1 |
| 13 | 2 | 2 | 2 |

**A coluna seca bate com o vínculo vigente em quase toda tribo.** Ela não é a fonte do defeito. O que
existe é gente com vínculo **encerrado**: a tribo 5 tem 4.

Conclusão provisória: se a página mostra quem saiu, ela provavelmente lê `engagements` **sem filtrar por
data**, e não a coluna seca. As tribos 7 e 8 mostram `vigente > seca`, o que sugere que as duas fontes
divergem nos dois sentidos.

### O experimento decisivo, que ficou por fazer

**Identificar qual query a página realmente executa.** Enquanto isso não for feito, tudo acima é
hipótese. Passos:

1. Achar a rota da página de membros da tribo no frontend e a RPC que ela chama.
2. Ler o corpo da RPC e ver qual fonte usa e qual predicado aplica.
3. Só então decidir se o conserto é filtro de data, troca de fonte, ou as duas coisas.

📌 Ver `reference-numero-que-bate-com-o-esperado-pode-bater-pela-fonte-errada`: número que bate pode
bater pela fonte errada. Aqui há **três** representações possíveis de "quem é da tribo" (coluna seca,
engajamento, e o que a tela mostra) e elas não coincidem.

---

## 4. Armadilhas medidas nesta lane, que valem para a próxima

- **`end_date` de engajamento é fim de CICLO, não saída da pessoa.** Testar por `IS NULL` mede a coisa
  errada e produz alarme falso de 66 contra 10.
- **Driver da NVIDIA desencontrado:** módulo `595.71.05` contra bibliotecas `595.84`. `nvidia-smi` não
  sobe e o CUDA falha de forma intermitente com `out of memory`. Contorno: um processo por arquivo, ou
  `CUDA_VISIBLE_DEVICES=""` para cair na CPU. **Correção real é reboot** e é decisão do dono.
- **Janela de origem curta impede conferir a cauda.** Foi o erro que o PM pegou: corte parando onde o
  arquivo acabava, não onde o raciocínio fechava. Mínimo de 5 min, e desde o início do bloco quando o
  trecho ABRE um tema.
- **QA visual quadro a quadro pega o que checagem programática não pega.** Seis defeitos passaram por
  validação verde e só apareceram ao olhar o quadro renderizado.
- **CI:** escalone os pushes. Duas branches atualizadas no mesmo segundo derrubam as duas (#1509).

---

## 5. Estado da fila (contexto, não tarefa)

Lane de vídeo entregue e agendada: 8 shorts no YouTube (24/08 a 02/09, 18h BRT) e 8 REELS no Instagram
(mesmos dias, 19h). Ata, ações e presença da Liderança #10 gravadas e conferidas por leitura.

Issues abertas por esta lane: **#1915** (leitura de ata sem tribo), **#1916** (`duration_actual` sem
fonte confiável), **#1917** (vídeo publicado com descrição vazia). Comentários em **#912** (rota de
gravação ausente, com o SQL como especificação) e no **#588** (7 lições aprendidas).

Nada de schema mudou. O worktree `lane-video-shorts` tem só o arranque anterior e este documento.
