# Arranque: o time de gestão do Núcleo - estrutura, board, permissão por papel

> **Escopo, em uma linha:** o time de gestão hoje são 2 pessoas com uma capacidade global, sem
> iniciativa, sem board e sem papel. Vai crescer em níveis, absorver os pontos focais e sair junto
> com a reforma do manual de governança. Este arranque mede o que existe e nomeia o que decidir.

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

### O board do rito de liderança NÃO existe

⚠️ **Correção do PM, 22/08.** Uma primeira leitura minha concluiu que o board de gestão já existia, e
estava errada. O board **"GP × Presidência - Governança do Núcleo"** (`confidential`, 25 itens) é
**específico da reunião com a presidência do capítulo**, não do rito quinzenal de liderança. Os itens
confirmam: numerados `[G1]` a `[G6]` e `[8]` a `[21]`, tratam de PM Day pedido pela presidência, backlog
do SGPL, PI da presidência virar tribo, registro no INPI, posicionamento estratégico. É a pauta daquela
relação.

Varredura por board ativo com "lideran", "gest" ou "governan" no nome ou no `domain_key`:

| board | escopo | visibilidade | itens |
|---|---|---|---|
| GP × Presidência - Governança do Núcleo | relação com a presidência | `confidential` | 25 |
| T7: Governança & Trustworthy AI | tribo 7, é o TEMA de pesquisa dela | standard | 19 |
| T10: Governança Assistida | tribo 10, idem | standard | 9 |
| PMI Global Summit - Governance and Community | submissão | standard | 7 |

**Nenhum é do rito de liderança.** A reunião quinzenal que reúne a coordenação e os líderes de tribo,
com 14 edições já realizadas, **não tem board**. As 26 ações da #10 existem só em
`meeting_action_items`, sem superfície de acompanhamento.

O mecanismo de ocultação que o PM imaginou **existe** e está em uso no board da presidência: é o do
**ADR-0105 / #785**, `initiatives.visibility='confidential'`, que tira board, eventos, artefatos e
documentos do read-all de Tier 1+ e deixa visível só para quem tem engajamento mais GP
(`manage_platform`). O gate é `rls_can_see_initiative()`. Ou seja: o padrão está provado, falta aplicá-lo
a uma iniciativa nova para a liderança.

### O que decidir, e é decisão do PM

1. Criar o board do rito de liderança? Se sim, sob iniciativa `confidential` como a da presidência, ou
   `standard` visível aos líderes?
2. **Nem toda ação da liderança é sensível.** Das 26, a maioria é operação de tribo ("apresentar o
   artefato na próxima reunião", "confirmar a data do webinar") e caberia no board da própria tribo,
   à vista do time que vai executar. Uma minoria é sensível (conversa individual sobre desempenho,
   afastamento por questão familiar). Se tudo for para um board fechado, o líder perde acompanhamento
   do que é dele; se tudo for aberto, expõe o que não deve.
3. Se houver split, ele precisa de **critério declarado**, senão vira julgamento caso a caso. Uma opção
   é o campo `kind` de `meeting_action_items` (`action` / `decision` / `followup` / `general`) virar o
   roteador, em vez de inventar taxonomia nova.

### O pedido real: um board do TIME DE GESTÃO, e ele vai crescer em níveis

⚠️ **Segunda correção do PM, 22/08.** O que ele quer não é o board do rito quinzenal, é o board do
**time de gestão do Núcleo**, que hoje tem 2 pessoas (GP e co-GP), está subindo uma terceira, vai
absorver **pontos focais dos capítulos** como membros de gestão, vai ter **níveis diferentes**, e vai
junto com a reforma do manual de governança. Líder de tribo também pode receber tarefa desse board.

### O estado medido, e ele é o argumento central

| medida | valor |
|---|---|
| pessoas com `manage_platform` hoje | **2** |
| iniciativas de kind governança/gestão | **0** |
| `engagement kind` para ponto focal | **0** |

E o recorte por papel vigente:

| kind / role | vigentes | com `manage_platform` | com `manage_event` |
|---|---|---|---|
| `chapter_board` / **`liaison`** | **7** | **0** | **0** |
| `chapter_board` / `board_member` | 9 | 0 | 0 |
| `ambassador` / `ambassador` | 5 | 2 | 2 |
| `ambassador` / `founder` | 4 | 2 | 2 |

Três leituras que saem daí:

1. **O time de gestão não existe como estrutura.** Existe como **duas pessoas carregando uma capacidade
   global** (`manage_platform`). Não há iniciativa, não há board, não há papel. Crescer de 2 para um time
   multinível não é adicionar gente: é **trocar flag de capacidade por estrutura governada**.
2. **Os pontos focais já existem** e são os 7 `chapter_board/liaison`. Trazê-los "para dentro" não é
   criá-los, é dar a eles engajamento numa iniciativa de gestão e a capacidade correspondente. Hoje eles
   têm **zero**.
3. **O papel atual do time de gestão está modelado errado.** GP e co-GP aparecem como `ambassador`, que
   é papel de **posicionamento externo** (junto com `founder`), não de gestão interna. Isso funciona
   enquanto são dois; não sobrevive a níveis.

### O desenho a decidir, e a boa prática aplicável

A plataforma já tem o primitivo certo: **iniciativa** é o primitivo de domínio (ADR-0005), autoridade é
escopada a ela (ADR-0007), e `visibility='confidential'` (ADR-0105/#785) fecha board, eventos, artefatos
e documentos para quem não está engajado. **O time de gestão deveria ser uma iniciativa como qualquer
outra**, e não um conjunto de exceções.

Isso resolve de uma vez o que o PM listou:

- **board próprio**, herdando o gate da iniciativa, sem inventar mecanismo de ocultação novo
- **níveis** viram `engagement kind` + `role` dentro da iniciativa, do mesmo jeito que tribo tem líder e
  pesquisador
- **ponto focal entra** ganhando engajamento nessa iniciativa, mantendo o `chapter_board/liaison` que
  já descreve a relação com o capítulo
- **líder de tribo recebe tarefa** sem precisar ser membro do time: `board_item_assignments` atribui a
  pessoa, e o gate de leitura é da iniciativa. Decidir se ele vê só o card dele ou o board todo.

Perguntas abertas, todas do PM:

1. A iniciativa de gestão nasce `confidential` ou `standard`? Confidencial protege conversa de pessoas
   e de contrato; padrão dá exemplo de transparência para quem cobra transparência das tribos. **Pode
   ser as duas: uma iniciativa de gestão `standard` e uma de assuntos sensíveis `confidential`**, que é
   o que a presidência já faz na prática.
2. Quantos níveis, e o que cada um pode? Sugestão de partida, a validar contra
   `docs/reference/V4_AUTHORITY_MODEL.md`: coordenação (hoje `manage_platform`), gestão (opera o ciclo,
   sem ciclo de vida de membro), apoio de gestão (executa e registra, sem apagar), ponto focal
   (representa o capítulo, lê tudo, escreve no que é dele).
3. ⚠️ **`manage_platform` não deve ser o degrau de entrada.** Ele carrega ciclo de vida de membro, que é
   invariante só-GP por LGPD Art. 18. Um time de gestão crescendo com `manage_platform` para todo mundo
   é exatamente o anti-padrão de escalada registrado no sedimento p122e.
4. A reforma do **manual de governança** e este desenho são o mesmo trabalho, e devem sair juntos: o
   manual descreve o que a matriz de permissão implementa. Se saírem separados, divergem na primeira
   mudança.

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
