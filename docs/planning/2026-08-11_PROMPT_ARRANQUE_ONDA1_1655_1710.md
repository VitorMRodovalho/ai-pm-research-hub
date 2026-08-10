# Prompt de arranque - Onda 1: a fatia do #1655 que virou pré-requisito, e o #1710

> Colar depois do `/clear`. **Effort: `xhigh`.**
> Handoff anterior: `docs/planning/2026-08-10_handoff_1656_escala_unica_presenca.md`
> (tem o desfecho do #1656 **e** o arranque do #1710 com o passo 1 já executado).
> O plano por ondas vive em `~/.claude/plans/breezy-questing-wren.md`, fora do repo.

---

## Regra zero

**Nada deste documento pode ser recitado.** Todo número aqui foi medido em **10/08/2026** e vários
se movem sozinhos: os eventos passados elegíveis foram de **302 → 306** em 24 horas, e os
divergentes por arredondamento tinham ido de 26 para 27 em poucas horas na sessão anterior.
Re-medir com tool call na mesma volta em que o número entrar numa decisão, num commit, numa issue
ou numa pergunta ao PM.

Os padrões que já custaram caro, agora doze:

- **verde sem significado** (o gate passou, o efeito não aconteceu)
- **verde por vacuidade** (`skip`, ramo vazio e **população zero** leem como verde)
- **número certo, significado errado** (a query certa sobre a população errada)
- **vermelho sem defeito** (o gate falhou por infraestrutura, e o dedo aponta para a mudança nova)
- **medido no lugar errado** (a varredura certa sobre o recorte errado)
- **o denominador se move** (87 ativos hoje; 89 quando o plano foi escrito)
- **lógica de três valores morde a query que MEDE** (`COALESCE(pred,false)` antes de negar)
- **ler o corpo da função não diz o que o ATO faz** (o trigger da tabela faz)
- **tirar a acusação de um lugar pode inflar a métrica no outro**
- **citada em PR mergeado não prova entrega** (conferir critério a critério)
- 🆕 **varrer por NOME acha menos que varrer pela CHAVE publicada** (no #1656 a 13ª RPC não citava
  o termo, e era a da tela principal)
- 🆕 **guard vermelho ≠ defeito seu** (no #1656, **4 de 5** vermelhos eram guards ancorados na
  FORMA - a expressão literal do front, um caminho de migration fixo)

⚠️ **Nunca escreva `close #N` / `fixes #N` / `resolves #N` num corpo de PR sem intenção de fechar,
nem para CITAR o padrão.** Aspas e negação não protegem: em 09/08 um PR só de documentação fechou
uma issue por citar a frase. Para citar, quebre o verbo (`clos&#101; #N`). E o espelho:
**`Fecha #N` em português não fecha nada.**

---

## Estado (medido 10/08)

`main` em **`096f94e4`**. Nada em voo, nenhum PR aberto, **zero** eventos de bypass na sessão
anterior. Backlog: **191 abertas**.

| medida | valor |
|---|---:|
| membros ativos | **87** |
| ciclo corrente | `cycle_4` |
| linhas em `attendance` | 2.020 |
| faltas simples na base | 3 |
| eventos passados elegíveis | **306** |
| eventos **selados** | **0** |
| invariantes violadas | **0** (de 43) |

### O que a sessão de 10/08 entregou

PRs **#1716** (código) e **#1717** (documentação), ambas mergeadas e **deployadas** - front e a EF
`nucleo-mcp`.

| | antes | depois |
|---|---:|---:|
| divergência painel × grade (de 66 comparáveis) | 27 | **0** |
| delta máximo | 0,50 pp | **0,0 pp** |
| células acusando falta **sem registro** nas 3 grades | 130 | **0** |
| `detractor` / `at_risk` só por inferência | 2 / 6 | **0 / 0** |

A chave de exibição de presença agora é percentual **0-100** sob nome `*_pct` em 13 RPCs; as
primitivas seguem fração 0-1. A migração foi **aditiva**, então a chave velha (`rate`,
`overall_rate`, `avg_rate`, `attendance_rate`) **continua publicada** - a limpeza é filha do #1656
e pode sair a qualquer momento, porque o front deployado já lê `*_pct`.

---

## A tarefa desta sessão

### 1. A fatia do #1655 que virou PRÉ-REQUISITO (decisão do PM em 10/08)

O #1655 completo é "unificar as 4 grades membro × evento (3 vivas, 1 órfã)". **O que bloqueia o
#1710 é só uma fatia dele:** dar linha na grade a quem não tem tribo.

Medido em 10/08, e é o achado que mudou a ordem:

| medida (ciclo corrente) | valor |
|---|---:|
| eventos passados elegíveis no ciclo | 53 |
| células da coorte do **selo** × da **grade** | 502 × 503 |
| só no selo (marcaria quem a grade não mostra) | **13 células, 3 pessoas** |
| só na grade (o selo nunca alcança) | 14 células, 2 pessoas |
| pessoas sem tribo, no ciclo, elegíveis ao selo | **3** |
| dessas, **quantas aparecem em alguma grade** | **0 de 3** |

**A divergência é de SUPERFÍCIE, não de regra.** Em todas as quatro fatias a causa é
`tribe_id IS NULL`:

- **só no selo:** `manager` + `researcher`, no ciclo, sem tribo. São elegíveis a `geral` e
  `lideranca` por `_attendance_eligible_events`, mas a grade é indexada por tribo e não tem onde
  mostrá-los. `get_attendance_grid` também agrupa por `tribes[]`, então **nenhuma** grade os alcança.
- **só na grade:** `alumni`, fora do ciclo, sem tribo. Entram pelo ramo histórico e o selo
  corretamente não os alcança - seguem `unrecorded` para sempre, o que está **certo**. Não mexer.

**Aceite da fatia:** as 3 pessoas passam a ter linha em alguma grade, medido antes e depois com os
dois números publicados, e sem mover a taxa de ninguém que já aparecia.

⚠️ **Decidir com o PM antes de codar:** unificar as grades inteiras (o #1655 como escrito) ou só
abrir a fatia? A issue pede a unificação, mas o pré-requisito é menor - e o #1656 mostrou que mexer
numa família de RPCs custa uma migration grande e alguns guards desatualizados.

### 2. O #1710, com o passo 1 já feito

Não refazer a medição das coortes: ela está acima e no handoff. **Re-verificar**, porque os números
andam.

**Decisão do PM em 10/08, NÃO re-litigar:** o selo é **AUTOMÁTICO, com janela e aviso** a quem será
marcado.

⚠️ **Consequência técnica registrada na mesma volta:** no fluxo manual há um humano lendo "isto vai
gravar N faltas" por evento; no cron não há. Um erro de coorte que no manual é pontual, no
automático se propaga pelos **306** eventos de uma vez, e **não existe `unseal`**. Por isso o escopo
passa a exigir, além do que a issue já pedia (janela, aviso, tool MCP, contagem publicada depois de
uma semana):

- **dry-run**: uma rodada em que o cron **reporta** o que faria, sem escrever;
- **caminho de reversão** por evento.

`seal_event_attendance(p_event_id)` está viva, gateada em `manage_event`, idempotente
(`ON CONFLICT DO NOTHING`), e escreve `present=false` para todo elegível sem linha com `marked_by`
do executor.

---

## Depois

1. **#1654** - fixar a coluna de nome nas 6 tabelas de presença com scroll horizontal.
2. **#1218** - presença órfã na reunião de 08/07, resíduo da Onda 0.
3. **#1652** (épica) fecha quando as filhas fecharem, com o aceite **corrigido**: "0 divergentes" é
   do #1656, não do #1653.
4. **#1656 continua aberta** com 3 dos 5 itens: **nomear as três semânticas na tela** (é o item que
   responde à pergunta da Reunião de Liderança que originou a onda), destino de
   `get_attendance_rate`, unificar "faltas consecutivas". Mais a limpeza da chave velha.

---

## Ferramentas e armadilhas já pagas

- **Corpo vivo de função:** `public._audit_function_source(p_proname text)` devolve o texto (grant:
  `service_role`). ⚠️ `_audit_list_public_function_bodies` devolve **só md5**, não o corpo.
- **Recaptura de função grande:** gerar o arquivo **por script** a partir da captura anterior, com
  substituições ancoradas que abortam se não casarem exatamente uma vez, e provar por md5 que a
  **reversão** reproduz o corpo vivo. Para mudança de 1 linha em função de ~10 KB, aplicar por `DO`
  block com `RAISE` por âncora sobre `pg_get_functiondef` - evita transcrever o corpo inteiro.
- ⚠️ **O statement de migration termina no `$$`, não no próximo `;`.** As migrations de captura em
  massa (`20260681000000_p176_phase_b_drift_capture...`) são dump cru de `pg_get_functiondef` e
  **não terminam com `;`**: cortar "até o próximo `;`" engole metade da função seguinte. O tell é
  contar `CREATE OR REPLACE FUNCTION` no arquivo gerado.
- ⚠️ **`apply_migration` em lotes:** cada chamada cria uma linha fantasma. Não faça
  `DELETE` de todas + `INSERT` à mão - isso deixa `statements` NULL e o gate *ADR-0097
  empty-statements* reprova. **Faça `UPDATE` da versão da ÚLTIMA fantasma** para o timestamp do
  arquivo local e apague só as outras; preserva os statements de graça. Se já apagou, preencha com
  `pg_get_functiondef` das funções tocadas.
- **Impersonar em prod para ler RPC gateada em `auth.uid()`:** CTE com
  `set_config('request.jwt.claim.sub', <auth_id>, true)`. ⚠️ **Use `AS MATERIALIZED` e uma
  dependência explícita** (`WHERE (SELECT count(*) FROM imp) = 1`) - sem isso a ordem de avaliação
  não é garantida e a medição devolve **população zero**, que lê como verde.
- **Provar comportamento sem deixar rastro:** `DO` que impersona, exerce e termina em
  `RAISE EXCEPTION`. **Conferir os triggers da tabela antes** - rollback desfaz linha, não e-mail.
- **Guard de RPC:** duas camadas. Estática sobre a captura mais recente (ponteiro **derivado** de
  `loadLatestCaptures`, nunca caminho escrito à mão) mais comparação do `body_md5` vivo com essa
  mesma captura. Comentários fora antes de assertar. E **controle positivo** em todo scanner.
- `tests/helpers/rpc-body-drift-parser.mjs` (`loadLatestCaptures`, `parseMigration`,
  `normalizeBody`, `md5`), `rpc-call-scanner.mjs` (chamar ≠ citar),
  `tests/contracts/1656-escala-unica-presenca.test.mjs` (as três camadas, como modelo).
- ⚠️ **Teste novo tem de entrar nas DUAS whitelists** do `package.json` (`test` e `test:contracts`),
  por script - a linha é grande demais para editar à mão.

## Verificação, antes de declarar qualquer coisa fechada

1. `npx astro build` passa
2. `npm test` com `.env` **exportado**: **0 fail e 1 skip** (não ~548 - o número de skips é o que dá
   sentido ao verde). Referência de 10/08: **6637 testes**.
3. `SELECT * FROM public.check_schema_invariants()` com 43 invariantes e 0 violadas
4. as queries de aceite rodadas **na volta** em que o número é afirmado
5. **CI: monitorar por RUN** (`gh run list --json headSha,name,status,conclusion`), nunca por
   `gh pr checks`
6. ⚠️ **Vermelho de `Schema Invariants` pode ser FILA, não schema.** O gate espera 900s pela faixa
   serializada do banco. Medir antes de culpar a mudança.
7. **Não rodar `npm test` com CI em voo** - a suíte escreve em produção e não tolera concorrência.

## Regras da casa

- Merge à `main` é da sessão main; lane leva o PR até verde e para.
- **Force-push bloqueado pelo harness.** Atualizar branch por `git merge origin/main`.
- Commit: `Assisted-By:`, nunca `Co-Authored-By`.
- Repo **PÚBLICO**: nenhum candidato ou membro nomeado, só contagens.
- DDL por migration, com o arquivo local espelhando o corpo vivo, tracking registrado e
  `NOTIFY pgrst, 'reload schema'`.
- **DDL vai a prod ANTES do CI** (o Phase C compara o corpo vivo com a migration). Por isso: se a
  mudança altera o que o front lê, faça-a **aditiva** - a chave nova ao lado da velha - senão a
  janela entre o DDL e o deploy mostra número errado.

## Pendências antigas que não mudaram

- **Reescrita de histórico** (PII): force-push é ação do mantenedor, e avisar o audit de bypass
  antes (a reescrita de 04/07 gerou 69 falsos positivos).
- **#334** (notificação LGPD Art. 48) segue `status:blocked` com bloqueador vivo.
- **Onda 0.5** (superfície pública / README) ficou para trás quando a Onda 1 começou.
- Dependabot: **security updates desligados** em 09/08, feed de alertas ativo. Restam 5 alertas: 3
  do astro (patch só em 7.x, é o **#1617**) e 2 do `image-size` (sem patch, entram por
  `@turbodocx/html-to-docx`, pedem decisão de alcance). ⚠️ **NÃO mergear PR do Dependabot** (#611).
- **`exec_all_tribes_summary` não tem consumidor** algum (nem `src/`, nem `supabase/functions/`);
  recebeu a chave nova por consistência, mas é candidata a remoção.
- **`src/pages/profile.astro`** (linhas 1015 e 1385) calcula a própria taxa de contagens locais, sem
  passar por RPC - é uma quarta fonte da mesma métrica, material do #1655.
