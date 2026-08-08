# Handoff - 08/08 (noite): #1636, a suite para de escrever em candidatura real

> Sessao a partir de `docs/planning/2026-08-09_PROMPT_ARRANQUE_POS_1643.md`.
> **#1636 FECHADA** pelo PR **#1690**, mergeado em **`9044dccf`** (squash, 6/6 verde).
> Desdobramento aberto: **#1691** (35 arquivos que ainda escrevem em prod).
>
> Suite completa no CI, com credenciais: **6593 testes, 6592 pass, 0 fail, 1 skip**. Os +7 sobre a
> linha de base sao exatamente os do guard novo (4 na camada A, 3 na camada B) - nao e o modo de
> falha dos 548 skips silenciosos.

---

## Decisao do PM tomada nesta sessao

O arranque propunha semear personas sinteticas **na base restaurada** e apontar a suite DB-aware
para ela. Medi antes de executar e levei a divergencia: **isso nao fecharia o dano**, porque
`.github/workflows/ci.yml:95` injeta `SUPABASE_URL` + `SERVICE_ROLE_KEY` de **producao** no
`npm test`. O laboratorio local e onde a PII incomoda; o dano em curso e do CI.

PM escolheu **fixture efemera em producao, na convencao do #1437**, com escopo **so na familia do
gate de entrevista**. As outras duas opcoes (tirar a suite DB-aware de prod; seed permanente
marcado com exclusao em toda leitura) ficam registradas como nao escolhidas.

---

## O que estava acontecendo, medido

| medida (08/08/2026, contra producao) | valor |
|---|---|
| `gate_attempts` | **663** linhas, **627 sem ator** (94,6%) |
| candidaturas reais contaminadas | **13**, com 3 concentrando **489** linhas |
| tokens de agendamento vivos da suite | **4**, `access_count` 0, validos ate 21/08 |
| custo por rodada de CI | **5** linhas novas em **3** candidaturas reais |

As 4 rajadas de exatamente 5 linhas de hoje (16:49, 17:13, 17:26, 17:39) batem **uma a uma** com
runs de `CI Validate`. Nao era hipotese sobre a torneira: era a torneira, com vazao medida.

⚠️ Verifiquei que nao eram minhas: `cron.job` nao tem nenhum job de ~13min tocando o gate (os tres
crons de selecao rodam diario as 14:00/15:00/15:30), e as linhas caem todas em `cycle3-2026`.

---

## O que foi entregue

- `tests/helpers/selection-fixtures.mjs` - constroi cada forma que o gate exige e apaga no fim
- `tests/helpers/rpc-call-scanner.mjs` - distingue **chamar** uma RPC de **mencionar** num literal
- `tests/contracts/1636-suite-nao-toca-candidatura-real.test.mjs` - o guard, em duas camadas
- repontados: `1594-1595`, `1598-1599`, `1613`, `1640`

### Tres coisas que o helper aprendeu contra o banco, e nenhuma era obvia

1. **`notify_selection_cutoff_approved` levanta P0003 (#1450) ANTES de chegar ao core.** A fixture
   de RECUSA precisa de nota; sem ela o teste afirmaria sobre outro caminho (excecao, nao recusa
   de gate). O predicado antigo nao filtrava por nota - passava por sorte.
2. **O ciclo fechado mais recente (`cycle2-2025`) nao resolve URL de agendamento**, e sem URL o
   caminho e P0020, nao recusa. "Pegar o ultimo fechado" teria quebrado calado. O helper **pergunta
   ao SSOT** (`resolve_interview_booking_url`) e move a fixture de ciclo ate resolver, em vez de
   reimplementar a regra do comite (duas copias divergem).
3. **`trg_recompute_app_pert` recalcula `objective_score_avg` a cada avaliacao inserida** e devolve
   a coluna a NULL (as avaliacoes sinteticas nao tem `submitted_at` nem `weighted_subtotal`). A
   nota tem de ser gravada **por ultimo**, depois dos filhos. Custou um vermelho para descobrir.

### O guard, e por que duas camadas

**Camada A** e guard de CLASSE sobre o codigo da suite. Carrega os dois controles que a tornam
nao-decorativa:

- **positivo** - o scanner acha as chamadas reais. Sem ele, um scanner quebrado (que nao achasse
  nada) passaria por vacuidade. **Ele pegou exatamente isso durante a escrita**: minha primeira
  versao nao tratava literal de regex, e regex com aspas soltas (`/…'P0001'…/`) a jogava em modo
  string, fazendo-a perder o resto do arquivo.
- **negativo** - sete arquivos MENCIONAM a RPC dentro de um literal porque inspecionam o codigo do
  admin/MCP. Um grep os acusaria, e guard que fica vermelho em trabalho correto e desligado.

**Mutacao: detectada**, nomeando o arquivo.

**Camada B** mede o EFEITO no banco, porque A fica verde se alguem importar o helper e mesmo assim
varrer producao. Ela separa a suite do **cron** pelo carimbo de execucao no audit log no mesmo
instante - os dois rodam como `service_role` e tem a MESMA digital de ator nulo. Medido sobre 30
dias: **632** linhas sem ator, **4** explicadas pelo cron, **628** sem explicacao.

A correlacao e feita em JS e **nao numa RPC nova de proposito**: DDL em prod antes do merge
serializa todos os PRs abertos (#1633), e um guard nao vale esse preco.

---

## O guard achou um quinto arquivo

`p693-dual-track-autolink-fkfix` escreve em `selection_applications` e o mapeamento manual nao o
tinha visto. Ele **ja era conforme**, com fixture propria em `@example.invalid`.

A regra foi corrigida para cobrar a **invariante** (o alvo nao alcanca pessoa nenhuma), nao o
modulo. O `p693` precisa de duas candidaturas com o **mesmo** e-mail (e assim que o gatilho de
auto-link dispara) e o helper compartilhado gera e-mail unico justamente para manter aquele gatilho
inerte - forca-lo a usar o helper quebraria o teste.

---

## Ganho alem da higiene

- Somem **cinco ramos "assercao nao exercida"** que liam como verde. Um deles registrava, em
  07/08, que **nenhuma** candidatura do ciclo aberto recusava mais: o teste vinha passando sem
  exercer nada.
- O `prior_evidence` do #1595 vira **deterministico**. Antes a assercao aceitava os tres tiers
  porque o alvo era dado vivo e uma corrida anterior podia ter subido o tier - e uma assercao que
  aceita tudo o que existe nao tem dentes.

---

## Duas correcoes no proprio guard, depois de aberto o PR

O teste de token tinha os dois erros de sinal ao mesmo tempo:

1. **Falso positivo.** O caminho de PASSAGEM (#1640) emite um token e so o apaga no `after` do
   bloco: por alguns segundos existe, legitimamente, token vivo sobre fixture viva. Sem janela de
   graca, este guard ficaria vermelho porque OUTRA corrida estava fazendo o trabalho dela.
2. **Falso negativo, o mais grave.** A versao anterior so olhava tokens cuja candidatura ainda
   EXISTE - ou seja, o caso que o #1636 descreve (candidatura apagada, token sobrevivendo) era
   exatamente o que escapava. `onboarding_tokens` nao tem FK para a candidatura: o vinculo e
   polimorfico por `source_id`, e o CASCADE nao alcanca. Linha de base medida antes de assertar:
   17 tokens, **0 orfaos**.

---

## Verificacao

### A torneira fechou, e esta MEDIDO (nao inferido do verde)

A confirmacao veio na propria rodada de CI do PR (run `31271160818`, `Run Unit Tests` de
**18:07:58 → 18:18:16 UTC**), que ja rodava o codigo novo contra producao:

| medida | antes | depois |
|---|---|---|
| linhas em `gate_attempts` por rodada de CI | **5**, em 3 candidaturas reais | **0** |
| candidaturas sinteticas sobreviventes | - | **0** |
| membros sinteticos sobreviventes | - | **0** |
| tokens de agendamento emitidos e nao limpos | 4 vivos por 14 dias | **0** |
| tokens orfaos (candidatura inexistente) | - | **0** |

A ultima linha de `gate_attempts` e de **17:39:55**, da rodada anterior ao merge. A janela inteira
do run novo nao deixou nenhuma. Total estacionou em **668** (632 sem ator).

⚠️ Que a suite DB-aware **de fato rodou** esta provado pelo numero de skips: **6593 testes, 6592
pass, 0 fail, 1 skip**. Sem credenciais seriam ~548 skips silenciosos, e o zero acima nao
significaria nada - "0 linhas novas" e "o teste nao rodou" produzem exatamente a mesma leitura.

### Antes disso, localmente

- `1594-1595`: 18/18 · `1598-1599` + `1640`: 25/25 · `1613` + `1636`: 27/27
- `npx astro build`: passa
- `package.json`: 564 → 565 e 548 → 549 arquivos (por script nas duas listas, +1 exato)

⚠️ **Faixa de banco**: o push do segundo commit deixou os runs do SHA anterior segurando a faixa
enquanto os novos esperavam. Cancelei os superados a mao. Vale como habito: depois de empurrar
correcao, **cancelar os runs do SHA velho** em vez de deixar os dois competindo (#1509).

---

## Fora de escopo, deliberado

- Os **4 tokens vivos** seguem a decisao do PM de 08/08 (*registrar, nao revogar*); expiram
  sozinhos em **21/08**. Se a decisao mudar, e antes disso.
- As **627 linhas historicas** ficam: apaga-las seria falsificar auditoria de tentativas que de
  fato aconteceram. O guard afirma a **direcao**, a partir do cutoff `2026-08-09T00:00:00Z`.
- Inventariei **40** arquivos de teste que escrevem direto em producao. Esta volta fecha a familia
  do gate de entrevista, onde esta o dano medido. **O resto merece issue propria** - e o inventario
  ja esta levantado.

---

## Proximo

1. ✅ **#1690 mergeado** em `9044dccf`; **#1636 fechada** (a mao - "Fecha #N" nao e palavra-chave
   do GitHub, so `close/closes/fix/fixes/resolve/resolves` fecham sozinhas).
2. ✅ **#1691 aberta** com o inventario das outras **35** superficies de escrita em producao.
3. **Re-medir o efeito** na rodada de CI da `main` pos-merge: ela tem de deixar **zero** linha nova
   em candidatura real (antes eram 5 por rodada). E o unico jeito de saber que a torneira fechou.
4. Residuos escolhidos, ainda intocados: observador por URL direta em
   `get_my_pending_evaluations`; `route-acl.test.mjs` reimplementando o `canAccess`; exigir
   evidencia no consentimento de IA sob `RAISE`.

## Em aberto, sem decisao (herdado)

- Os quatro defeitos recortaveis do **#1679** viram issues?
- R2 sem lifecycle (~5 GB/ano). Se ganhar poda, a retencao de 30 do artefato precisa subir.
