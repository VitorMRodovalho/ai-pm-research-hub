# Desenho do time de gestão: camadas estratégica, tática e operacional

> **Medido ao vivo em 2026-08-21.** Todos os números abaixo saíram de consulta na sessão que escreveu
> este documento, não de recitação do arranque. Onde o arranque de 22/08 divergiu da medição, a
> divergência está marcada com ⚠️ e a medição prevalece.
> Repositório PÚBLICO: sem nome de pessoa e sem identificador de candidato.

---

## 1. Re-medição do Bloco 1: as três contagens de cabeçalho confirmam

| medida | arranque | re-medido 21/08 | status |
|---|---|---|---|
| pessoas com `manage_platform` (engajamento vigente) | 2 | **2** | confirma |
| `chapter_board` / `liaison` vigentes | 7 | **7** | confirma |
| iniciativas de kind governança/gestão | 0 | **0** | confirma |

Critério de vigência usado: `status='active'` e `revoked_at is null` e
`(end_date is null or end_date >= current_date)` e `(start_date is null or start_date <= current_date)`.

### ⚠️ Correção 1: o ponto focal não tem "zero". Ele tem leitura e não tem escrita

O arranque afirma que os 7 `chapter_board/liaison` "hoje têm **zero**". Falso. A tabela de seeds dá a
eles **5 capacidades**:

`manage_partner`, `participate_in_governance_review`, `view_chapter_dashboards`,
`view_internal_analytics`, `view_partner`

O que eles não têm é qualquer capacidade de **execução no ciclo**: nada de `manage_event`,
`write_board`, `manage_initiative`. E `chapter_board/board_member` (9 vigentes) tem só
`view_chapter_dashboards` e `view_pii`.

Isso muda o desenho, e para melhor. Trazer o ponto focal "para dentro" não é criar um papel do zero
nem conceder o primeiro acesso: é **acrescentar escrita escopada a quem já lê e já participa da revisão
de governança**. O degrau é bem menor do que o arranque supunha.

### ⚠️ Correção 2: o papel do time de gestão NÃO está modelado como `ambassador`

O arranque conclui que "GP e co-GP aparecem como `ambassador`, que é papel de posicionamento externo,
não de gestão interna", e trata isso como defeito de modelagem. A medição inverte:

| kind / role | vigentes | capacidades seedadas |
|---|---|---|
| `ambassador` / `ambassador` | 5 | **(nenhuma)** |
| `ambassador` / `founder` | 4 | **(nenhuma)** |
| `volunteer` / `manager` | 1 | 19, inclusive `manage_platform` |
| `volunteer` / `co_gp` | 1 | 19, inclusive `manage_platform` |

`ambassador` é rótulo puro, sem capacidade nenhuma. **Todo o `manage_platform` vem de
`volunteer/manager` e `volunteer/co_gp`**, que são papéis de gestão e estão corretamente nomeados. A
modelagem não está errada.

O defeito real é outro, e é mais nítido: **não existe degrau intermediário.**

| rung | capacidades | escopo |
|---|---|---|
| `volunteer` / `researcher` | 2 | initiative |
| `volunteer` / `leader` | 9 | initiative |
| `volunteer` / `manager` e `co_gp` | **19** | **organization** |

Entre 9 escopadas à iniciativa e 19 globais não há nada. Crescer o time de gestão hoje significa
entregar o pacote de 19 com escopo de organização, que inclui `manage_member` (ciclo de vida de membro,
invariante só-GP por LGPD Art. 18) e `manage_platform`. **Isso é exatamente o anti-padrão de escalada
do sedimento p122e**, e o arranque estava certo ao apontá-lo, só que pela razão errada.

### O achado que resolve o desenho: o escopo por iniciativa já existe e está provado

| escopo em `engagement_kind_permissions` | combos | actions cobertas |
|---|---|---|
| `organization` | 114 | 22 actions, inclusive `manage_platform` |
| **`initiative`** | **53** | `award_champion`, `manage_board_admin`, `manage_event`, `manage_initiative`, `manage_member`, `view_pii`, `write`, `write_board` |
| `global` | 1 | `view_internal_analytics` |

Dois fatos que decorrem daí:

1. **`manage_platform` só existe em escopo `organization`**, em `volunteer/{manager, co_gp, deputy_manager}`.
   Ele é, por construção, capacidade de topo. Confirma que ele não pode ser o degrau de entrada.
2. **`manage_member` já é concedido em escopo `initiative`** a `committee_member/leader`,
   `study_group_owner/{leader,owner}` e `workgroup_member/leader`. Ou seja, "administrar quem está na
   minha estrutura" já é separado de "administrar o ciclo de vida global da pessoa". O mecanismo que a
   camada tática precisa **já existe e roda em 53 combos**.

O desenho, portanto, não pede mecanismo novo. Pede **uma iniciativa** e engajamentos escopados a ela.

### Um degrau seedado e não usado

`volunteer/deputy_manager` já tem **19 combos seedados** e **0 pessoas vigentes**. Ele é tão amplo
quanto `manager` (escopo `organization`, com `manage_member` e `manage_platform`). Não serve como
degrau intermediário, mas precisa entrar na decisão: ou vira o segundo nível da camada estratégica com
o pacote que já tem, ou é reduzido, ou é aposentado. Deixá-lo seedado e vazio é uma porta aberta sem
dono.

---

## 2. Bloco C: o experimento decisivo rodou, e a causa NÃO é a que se supunha

### O caminho real da página

`src/pages/tribe/[id].astro` monta a aba Membros com **duas fontes somadas**:

1. **Roster** - `get_initiative_roster_members(p_initiative_id)` → view `v_initiative_roster` (linha 2141)
2. **Seleções** - `sb.from('tribe_selections').select('member_id').eq('tribe_id', TRIBE_ID)` (linha 2147),
   cujos membros são depois filtrados só por `current_cycle_active = true` e `is_active = true`, e
   concatenados no roster (`const allMembers = [...allDirectMembers, ...selectionMembers]`).

A hipótese do PM era que a página lia a coluna seca `members.tribe_id`. **Ela não lê** (só no fallback
legado, quando não há iniciativa resolvida). A conclusão provisória do arranque era que a página lia
`engagements` sem filtro de data. **Também não é isso.** É a segunda fonte.

### Fonte 1 (roster): tem risco latente, mas zero caso hoje

`v_initiative_roster` filtra por `e.status = 'active'` e exclui `observer`, e **não tem nenhum predicado
de data**. Medido:

| medida | valor |
|---|---|
| engajamentos `status='active'` na view | 200 |
| destes, com `end_date < current_date` | **0** |
| destes, com `revoked_at` preenchido | **0** |
| vigentes por data mas **fora** da view (`status<>'active'`) | 20 |

Por tribo, o roster bate exatamente com o vínculo vigente em **12 de 12** tribos, inclusive a 5 (2 e 2).
A ausência do filtro de data é dívida latente que depende de `status` ser mantido à mão; não é a causa
do que o PM viu.

### Fonte 2 (`tribe_selections`): esta é a causa

`tribe_selections` tem só 4 colunas (`id`, `member_id`, `tribe_id`, `selected_at`). **Não tem ciclo, não
tem status e não tem data de saída.** É a tabela de "escolhi esta tribo" da home (`TribesSection.astro`),
43 linhas, escritas entre 2026-03-05 e 2026-07-10, e nunca limpas.

Quem entra na página **só** por essa fonte, hoje:

| tribo da página | pessoas que aparecem só por seleção | tribo real dessas pessoas |
|---|---|---|
| 2 | 3 | 7, 11 e 12 |
| 3 | 1 | 4 |
| **5** | **2** | **14** |

**Total: 6 pessoas aparecendo em tribo que não é a delas.** Na tribo 5, o roster tem 2 e a tela mostra 4,
que é precisamente o que o PM relatou.

Duas propriedades tornam o defeito invisível às checagens existentes:

- as 6 seleções são de **março de 2026**, uma rodada de seleção passada;
- o filtro `current_cycle_active = true` **não protege**, porque essas pessoas *estão* ativas no ciclo
  atual. Só que em outra tribo. O filtro mede atividade da pessoa, não pertencimento àquela tribo.

Das 6, **5 chegaram a ter engajamento naquela tribo** (saíram de fato) e **1 nunca teve** (só sinalizou
interesse e nunca entrou). Então a tela mistura três coisas sob o rótulo "membros": quem está, quem
esteve, e quem só quis.

📌 Isto instancia `reference-numero-que-bate-com-o-esperado-pode-bater-pela-fonte-errada`. O roster
sozinho bate com o esperado em todas as tribos; a tela erra porque **soma uma segunda fonte** cujo
significado é outro.

### O que decidir antes de consertar

A correção mínima não é óbvia porque `tribe_selections` está viva e serve à jornada de escolha de tribo
na home. Três opções, e a escolha é do PM:

1. **Parar de mesclar seleção no roster.** A aba Membros passa a mostrar só vínculo. Mais correto
   semanticamente; o líder perde a visibilidade de quem sinalizou interesse, que talvez ele queira.
2. **Mesclar, mas rotulado e separado.** Roster em cima, "interessados nesta rodada" em bloco à parte.
   Preserva a informação e desfaz a confusão. Exige limite de janela, senão a lista cresce para sempre.
3. **Dar ciclo a `tribe_selections`.** Acrescentar coluna de ciclo e filtrar pela rodada corrente. Mais
   estrutural, e resolve também `gamification.astro:1069`, que consome a mesma tabela sem recorte.

Há ainda a dívida latente da fonte 1 (view sem predicado de data), que vale corrigir junto por ser
barata e por remover a dependência de `status` ser mantido manualmente.

---

## 3. O desenho em camadas, espelhado em boas práticas de PMO e de gestão de equipes

Pedido do PM em 21/08: espelhar o desenho em boas práticas de gestão de equipes e do PMO Global
Alliance, em particular a lógica do PMO Value Ring, dado que o Núcleo tem equipes **estratégicas,
táticas e operacionais**, e não só as tribos.

### O que o Value Ring diz que se aplica aqui

O ponto central da metodologia é que **um PMO não se define pela autoridade que detém, e sim pelas
funções que entrega a stakeholders identificados**. Autoridade é da linha; o escritório entrega
serviços. Disso saem quatro consequências diretas para este desenho:

1. **Escolher funções por expectativa de stakeholder, não por template.** Não existe modelo único de
   PMO; existe o conjunto de funções que os clientes daquele escritório precisam. Aqui os clientes da
   camada tática são as tribos e os capítulos.
2. **O nível do PMO acompanha o nível do cliente que ele serve.** Estratégico serve a direção, tático
   serve o portfólio e os líderes, operacional serve a entrega. É exatamente a estratificação que o PM
   observou.
3. **Maturidade se mede por função, não por cargo.** Cada função entregue tem indicador próprio e
   percepção de valor própria.
4. **Valor é percebido, não declarado.** Uma função que ninguém consome não gera valor mesmo que esteja
   no organograma.

Da gestão de equipes vem o complemento: **nível de responsabilidade e nível de permissão são eixos
distintos**. Senioridade define o que a pessoa responde; permissão define o que o sistema deixa
executar. Confundir os dois é o que produz escalada de privilégio, e é o que a plataforma faz hoje ao
oferecer só um pacote de 19 capacidades globais para quem sobe de degrau.

### As três camadas, mapeadas no que já existe

| camada | cliente que serve | quem é hoje | primitivo na plataforma | estado |
|---|---|---|---|---|
| **Estratégica** | presidência do capítulo, direção do Núcleo | GP e co-GP (2 pessoas) | `volunteer/{manager,co_gp}`, escopo `organization`, 19 capacidades | **existe**, e o board "GP × Presidência" é a superfície dela |
| **Tática** | tribos, pontos focais, ciclo | ninguém formalmente | **nenhum** | ⚠️ **é o vazio** |
| **Operacional** | pesquisadores, entregas | 12 tribos ativas | `volunteer/{leader,researcher}`, escopo `initiative` | **existe** e está escopado |

O vazio é o meio, e é exatamente onde as 26 ações da Liderança #10 caíram sem board. Não é coincidência:
a camada tática é a dona natural do rito quinzenal, do one-pager de métricas, do acompanhamento de
desligamentos e da higiene do calendário de tribos. Os quatro itens que o PM listou como "não viraram
ação" são, todos, funções de camada tática sem camada tática para hospedá-las.

### Como isso vira estrutura, sem inventar mecanismo

O primitivo é iniciativa (ADR-0005), a autoridade é escopada a ela (ADR-0007), e a visibilidade
`confidential` (ADR-0105 / #785) já fecha board, eventos, artefatos e documentos. A camada tática vira
**uma iniciativa como qualquer outra**, e os níveis viram `kind` + `role` escopados a ela, do mesmo
jeito que tribo tem líder e pesquisador.

Aplicando a lógica de funções do Value Ring, um esboço de partida (a validar, ver §4):

| nível | função que entrega (linguagem de serviço) | escopo de permissão pretendido |
|---|---|---|
| coordenação | direção do Núcleo, relação com a presidência | `organization` (o que já têm) |
| gestão | opera o ciclo, consolida métricas, conduz o rito | `initiative` na iniciativa de gestão |
| apoio de gestão | executa e registra, não apaga | `initiative`, sem capacidade destrutiva |
| ponto focal | representa o capítulo, lê tudo, escreve no que é dele | `initiative` + as 5 capacidades que já tem |

Três propriedades que esse desenho preserva, e que valem declarar:

- **`manage_platform` fica onde está.** Ele é `organization`-only por construção medida, e ciclo de vida
  de membro continua só-GP (LGPD Art. 18).
- **O ponto focal mantém `chapter_board/liaison`**, que descreve a relação com o capítulo, e ganha um
  segundo engajamento na iniciativa de gestão. Dois engajamentos paralelos já é padrão vigente (GP tem
  `volunteer/manager` e `ambassador` ao mesmo tempo).
- **Líder de tribo recebe tarefa sem entrar no time**: `board_item_assignments` atribui a pessoa e o
  gate de leitura continua sendo o da iniciativa. Falta decidir se ele enxerga só o card dele ou o board
  inteiro.

### Sobre o "braço direito" do líder (Bloco B), na mesma lógica

A pergunta do PM sobre o pesquisador que ajuda a manter a ordem na tribo é a mesma pergunta em escala
operacional: falta um degrau entre `researcher` (2 capacidades) e `leader` (9). O caminho coerente com
o resto é um `role` novo em escopo `initiative`, com escrita e sem operação destrutiva, e apoiado na
rastreabilidade que já existe (`registered_by` em presença, #1322). **Não é proposta ainda**, pelo
motivo do §4.

---

## 4. O que NÃO foi feito, de propósito

**Nenhum seed foi proposto e nenhuma iniciativa foi criada.** O procedimento de 4 etapas do
`docs/reference/V4_AUTHORITY_MODEL.md` é obrigatório antes de qualquer proposta de
`INSERT INTO engagement_kind_permissions`, e ele não foi executado nesta sessão. Ele precisa rodar por
action pretendida (`write_board`, `manage_event`, `manage_initiative`, `manage_member` em escopo
`initiative`), porque a auditoria mecânica dessa tabela produz falso positivo recorrente: existem três
caminhos paralelos de autoridade, e um combo ausente pode estar coberto por gate de designation ou por
scoping inline em RPC.

O que este documento entrega é o **antes** desse procedimento: o estado medido, a correção das duas
premissas erradas, e o desenho-alvo em linguagem de função. As etapas 1 a 4 são o próximo passo.

---

## 5. Decisões que dependem do PM

1. **Bloco C:** qual das três opções de correção da aba Membros (parar de mesclar, mesclar rotulado, ou
   dar ciclo a `tribe_selections`). Afeta 6 pessoas em 3 tribos hoje.
2. **Iniciativa de gestão:** nasce `confidential`, `standard`, ou as duas (uma de gestão aberta e uma de
   assuntos sensíveis fechada, que é o que a presidência já faz na prática).
3. **Quantos níveis**, e a função de cada um em linguagem de serviço, antes de qualquer permissão.
4. **`volunteer/deputy_manager`:** 19 combos seedados e 0 pessoas. Vira o segundo nível estratégico,
   é reduzido, ou é aposentado.
5. **Roteador das ações da reunião:** o campo `kind` de `meeting_action_items` vira o critério de para
   qual board a ação vai, ou se cria taxonomia própria.
6. **Manual de governança:** confirmar que ele e esta matriz saem juntos, porque o manual descreve o que
   a matriz implementa.
