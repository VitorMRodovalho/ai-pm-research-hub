# Prompt de arranque - Onda 1, o contrato de presença (#1656)

> Colar depois do `/clear`. **Effort: `xhigh`.**
> Handoff anterior: `docs/planning/2026-08-09_handoff_onda1_1653_1660_presenca.md` (com adendo).
> O plano por ondas vive em `~/.claude/plans/breezy-questing-wren.md`, fora do repo.

---

## Regra zero

**Nada deste documento pode ser recitado.** Todo número aqui foi medido em 09/08/2026 e alguns já
se moviam dentro da própria sessão: os divergentes por arredondamento passaram de 26 para 27 em
poucas horas, e as células sem registro de 92 para 114, porque o conjunto de eventos passados
cresce todo dia. Re-medir com tool call na mesma volta em que o número entrar numa decisão, num
commit, numa issue ou numa pergunta ao PM.

Os padrões que já custaram caro, agora dez:

- **verde sem significado** (o gate passou, o efeito não aconteceu)
- **número certo, significado errado** (a query certa sobre a população errada)
- **vermelho sem defeito** (o gate falhou por infraestrutura, e o dedo aponta para a mudança nova)
- **verde por vacuidade** (`skip` e ramo vazio leem como verde)
- **medido no lugar errado** (a varredura certa sobre o recorte errado)
- **citada em PR mergeado não prova entrega** (conferir critério a critério)
- **o denominador se move** (87 ativos hoje; era 89 quando o plano foi escrito)
- **a lógica de três valores morde a query que MEDE** (`NOT NULL` é NULL e o `FILTER` não conta:
  devolve zero exatamente nas linhas do defeito). `COALESCE(pred, false)` antes de negar
- **ler o corpo da função não diz o que o ATO faz** (o trigger da tabela faz; ver o incidente do
  cancelamento no adendo do handoff)
- **tirar a acusação de um lugar pode inflar a métrica no outro** (é o que quase aconteceu no
  #1657: 65 de 66 iriam a 100%)

⚠️ **Nunca escreva `close #N` / `fixes #N` / `resolves #N` num corpo de PR sem intenção de fechar,
nem para CITAR o padrão.** Aspas e negação não protegem: em 09/08 um PR só de documentação fechou
uma issue por citar a frase. Para citar, quebre o verbo (`clos&#101; #N`). E o espelho:
**`Fecha #N` em português não fecha nada.**

---

## Estado

`main` em **`3675cc69`**. Nada em voo. Backlog: **190 abertas**.

Fecharam em 09/08: **#1653**, **#1660**, **#1657**, **#1705**, mais **#1637** (Dependabot, como
superseded) e as decisões de governança. Sete PRs mergeados no dia.

### O que a Onda 1 já entregou

| | antes | depois |
|---|---:|---:|
| divergência de **contagem** painel × grade | 42 de 66 | **0** |
| falta simples **gravável** | não (só por contorno) | sim |
| células acusando falta **sem registro** | 92 | **0** |
| `detractor` só por inferência | 2 | **0** |
| `at_risk` só por inferência | 5 | **0** |

### O que sobra, medido em 09/08

| medida | valor |
|---|---:|
| membros ativos | **87** |
| comparáveis (aparecem na grade da própria tribo) | **66** |
| **divergentes na tela** (só arredondamento) | **27** |
| divergentes **depois de igualar a escala** | **0** |
| delta máximo | **0,5 pp** |
| células `unrecorded` | **114** |
| eventos **selados** | **0 de 301** |
| linhas em `attendance` | 2.020 |
| faltas simples na base | 3 |
| eventos nos próximos 30 dias | 75 |

---

## O denominador: DECIDIDO, opção (a) - não re-litigar

**Decisão do PM em 09/08/2026:** o denominador continua sendo **todo evento elegível passado**,
`unrecorded` incluído. É o que já está vivo desde o #1657, então **não há código a escrever** por
causa disso. Consequência aceita: um evento que ninguém registrou continua **contando** no
denominador; ele deixou de **acusar** na célula, e é só isso que o #1657 mudou.

**Restrição verificada na mesma volta, por medição e não por leitura do código:** a matemática é
só de fato ocorrido. Nenhuma célula `present`, `unrecorded` ou `excused` vem de evento futuro
(0 de 489); as 1.361 células `scheduled` são todas de evento futuro e **não entram** no
denominador, porque `member_stats` conta apenas `present`/`absent`/`excused`/`unrecorded`.

O que **não** foi decidido e continua com o #1656: a **escala** (0-100 × 0-1) e **nomear a métrica
na tela**. É isso que fecha os 27 divergentes.

---

## O #1656, a parte mecânica

Independe da decisão acima e fecha os 27 divergentes:

- `get_tribe_stats` e `get_initiative_stats` devolvem **0-100**; `exec_tribe_dashboard`,
  `get_tribe_gamification`, `get_cycle_attendance_overview` e `exec_cross_initiative_comparison`
  devolvem **0-1**, com cada consumidor multiplicando no cliente
- o tell está em `src/components/tribes/TribeAttendanceTab.tsx`: `rate <= 1 ? rate * 100 : rate`.
  Um coalesce assim é confissão de contrato instável
- a grade arredonda a **2 casas em 0-1** (1 pp de granularidade) e o painel a **1 casa em 0-100**
  (0,1 pp). É só isso que sobra dos 27

**Aceite:** uma escala no contrato das RPCs, **zero** ocorrências do coalesce no front, e a
divergência medida antes e depois com os dois números publicados.

---

## Duas issues novas saíram da decisão (09/08)

**#1713 - saneamento das séries que pararam.** Os eventos passados sem nenhuma linha não estão
espalhados: concentram-se em **duas séries semanais de tribo** que pararam de registrar presença na
primeira semana de julho (última com presença em 06/07 e 07/07), e **cada uma tem 8 ocorrências
futuras agendadas até 28/09**. Três destinos possíveis - não aconteceu (cancelar), aconteceu e
ninguém registrou (selar/registrar), série morreu (encerrar) - e o banco não distingue: precisa da
resposta dos dois líderes. ⚠️ Com a opção (a), enquanto as ocorrências existirem elas **contam**.

**#1714 - XP mistura ciclo e acumulado.** Mesma causa do #1656 em outra superfície. Dentro da tribo
o recorte já é por ciclo e está certo; o `get_public_leaderboard` filtra a **população** por
`current_cycle_active` e soma o XP de **todos os ciclos**, com o nível derivado do acumulado.
Medido: **71,5%** do XP exibido veio de fora do ciclo, e **57 de 82** pessoas mudariam de nível se o
recorte fosse o ciclo. Recomendação registrada: manter as duas métricas e **nomeá-las** (XP do
ciclo = o que compete; acumulado e nível = trajetória).

## Depois do #1656

1. **#1710** - superfície para selar. Já tem o cuidado registrado: automatizar o selo transforma
   omissão em falta sem ninguém decidir, que é o defeito que o #1657 acabou de tirar. Se for
   automático, precisa de janela e de aviso a quem será marcado.
2. **#1655 → #1654** - três grades membro × evento vivas mais uma órfã
   (`src/components/attendance/AttendanceGrid.tsx`, exportada e nunca importada); unificar e
   depois fixar a coluna de nome nas 6 tabelas com scroll.
3. **#1218** - presença órfã na reunião de 08/07, resíduo da Onda 0.
4. **#1652** fecha quando as filhas fecharem, com o aceite **corrigido**: "0 divergentes" é do
   #1656, não do #1653.

---

## Ferramentas e armadilhas já pagas

- **Corpo vivo de função:** `public._audit_function_source(p_proname text)` devolve o texto
  (grant: `service_role`). ⚠️ `_audit_list_public_function_bodies` devolve **só md5**, não o corpo.
- **Recaptura de função grande:** gerar o arquivo **por script** a partir da captura anterior, com
  substituições ancoradas que abortam se não casarem exatamente uma vez, e provar por md5 que a
  **reversão** reproduz o corpo vivo. Aplicar por `DO` block com `RAISE` por âncora; conferir
  depois que o corpo vivo bate com o arquivo.
- **Provar comportamento em prod sem deixar rastro:** `DO` que impersona por
  `request.jwt.claim.sub`, exerce e termina em `RAISE EXCEPTION`. **Conferir os triggers da tabela
  antes** - rollback desfaz linha, não e-mail nem webhook.
- **Guard de RPC gateada em `auth.uid()`:** duas camadas. Estática sobre a captura mais recente
  (ponteiro **derivado** de `loadLatestCaptures`, nunca caminho escrito à mão) mais comparação do
  `body_md5` vivo com essa mesma captura.
- `tests/helpers/selection-fixtures.mjs` (fixture sintética), `rpc-call-scanner.mjs` (chamar ≠
  citar), `rpc-body-drift-parser.mjs` (`loadLatestCaptures`, `normalizeBody`, `md5`).
- ⚠️ **Teste novo tem de entrar nas DUAS whitelists** do `package.json` (`test` e
  `test:contracts`), por script - a linha é grande demais para editar à mão.

---

## Verificação, antes de declarar qualquer coisa fechada

1. `npx astro build` passa
2. `npm test` com `.env` **exportado**: 0 fail e **1 skip** (não ~548 - o número de skips é o que
   dá sentido ao verde)
3. `SELECT * FROM public.check_schema_invariants()` com 43 invariantes e 0 violadas
4. as queries de aceite rodadas **na volta** em que o número é afirmado
5. **CI: monitorar por RUN** (`gh run list --json headSha,name,status,conclusion`), nunca por
   `gh pr checks`
6. ⚠️ **Vermelho de `Schema Invariants` pode ser FILA, não schema.** O gate espera 900s pela faixa
   serializada do banco e falha se ela não abrir. Aconteceu em 09/08 num PR só de documentação, com
   o banco vivo em 43/0. Medir antes de culpar a mudança, e re-rodar o job com a faixa livre.

---

## Regras da casa

- Merge à `main` é da sessão main; lane leva o PR até verde e para.
- **Force-push bloqueado pelo harness.** Atualizar branch por `git merge origin/main`.
- Commit: `Assisted-By:`, nunca `Co-Authored-By`.
- Repo **PÚBLICO**: nenhum candidato ou membro nomeado, só contagens.
- DDL por migration, com o arquivo local espelhando o corpo vivo, `migration repair` e
  `NOTIFY pgrst, 'reload schema'`. Conferir e **apagar a linha fantasma** de tracking por chamada.
- Não rodar `npm test` com CI em voo.

---

## Pendências antigas que não mudaram

- **Reescrita de histórico** (PII): force-push é ação do mantenedor, e avisar o audit de bypass
  antes (a reescrita de 04/07 gerou 69 falsos positivos).
- **#334** (notificação LGPD Art. 48) segue `status:blocked` com bloqueador vivo.
- **Onda 0.5** (superfície pública / README) ficou para trás quando a Onda 1 começou.
- Dependabot: **security updates desligados** em 09/08 (`automated-security-fixes` `enabled=false`),
  feed de alertas ativo. Restam 5 alertas: 3 do astro (patch só em 7.x, é o **#1617**) e 2 do
  `image-size` (sem patch, entram por `@turbodocx/html-to-docx`, pedem decisão de alcance).
