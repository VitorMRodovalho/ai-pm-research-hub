# Handoff — arco de consentimento fechado, acesso por componente aberto (07/08/2026)

> `main` em **`6481534c`**. Tudo desta sessão está MERGEADO. Migrations `20260807000400` a
> `20260807001000` aplicadas, registradas e com arquivo no checkout (conferido).

## Regra zero

Nada aqui pode ser recitado. Toda contagem foi medida em 07/08 e a base é viva. O padrão que mais
custou nesta sessão foi **número certo, significado errado** — três vezes.

---

## Fechado hoje

| issue | o que era |
|---|---|
| **#1640** | o gate de IA negava o convite de entrevista |
| **#1642** | a comunicação NEGAVA a consequência (3 superfícies, 3 idiomas) + subprocessador errado |
| **#1649** | a varredura lia 147.794 linhas para devolver zero; o teto do #1663 era inerte |
| **#1666** | o consentimento gravava carimbo, não COM O QUE a pessoa concordou |
| **#1665** | transferência internacional listava 6 e omitia os 3 de IA |
| **#1423** | a transferência de tribo partia a ponte `initiative_id` |
| **#1591** | o comitê não alcançava a tela que opera + observador recebia a fila de avaliação |
| **#1641** | fechada por decisão: **não reemitir** (ver abaixo) |

---

## Estado final da seleção, medido

| papel no comitê | pessoas | vê a FILA de avaliação | vê o PAINEL do processo |
|---|---|---|---|
| `evaluator` | 3 | 3 | 3 |
| `observer` | 4 | **0** | 4 |

⏭️ **Falta confirmação humana:** um avaliador logado deve ver *Minhas Avaliações* (20 pendentes) e
*Processo Seletivo*; observador deve ver só o segundo. **Não dá para medir por SQL** — as RPCs
resolvem por `auth.uid()` e o conector MCP passa como o Vitor.

---

## Aberto, e o que cada um espera

### #1679 — curadoria (investigação pura, NÃO precisa de decisão)
37 submissões, 7 publicações, **zero** linhas em toda a maquinaria de blind review, **zero**
portadores da designation `curator` (que gateia 9 entradas de nav).
⚠️ **NÃO tem relação com o comitê de seleção.** São corpos e domínios distintos; a confusão já
aconteceu uma vez nesta apuração. O aviso está no topo da issue.

### #1643 — varrer outros consentimentos "opcionais" com gate escondido
Também investigação. O método ganhou uma **terceira classe** hoje: além de "gate de tratamento"
(ok) e "gate de avanço" (defeito), existe **"afirmação incondicional sobre tratamento
condicional"** — foi o caso do `peer_review_request`, corrigido.

### #1632 — épica; só fecha quando #1643 e #1679 fecharem.

### Pendências de comitê (não de código)
- a redação do consentimento, **já publicada**, incluindo a cláusula "sediados nos Estados Unidos"
- o **inciso do art. 33** (VIII para as transferências de IA)

---

## Resíduos declarados (escolhidos, não esquecidos)

1. **Observador por URL direta** ainda vê a fila em `/minhas-avaliacoes` com botão que vai recusar.
   A fronteira está fechada em `submit_evaluation`; o que falta é UX. Mexer no retorno de
   `get_my_pending_evaluations` muda contrato com a tela.
2. **A evidência de consentimento ainda não é EXIGIDA.** `give_consent_via_token` registra quando
   vem e grava `unversioned` quando não vem. O aperto (`RAISE`, como no ramo de voz) espera
   confirmação de que o front novo está no ar.
3. **Escapador parcial em 3 arquivos de teste pré-existentes**
   (`admin-selection-import-error-rendering`, `consent-voice-biometric-ui`,
   `p519-visible-excused-affordance`). O CodeQL não os acusa porque só reporta código alterado.

---

## ⚠️ Os erros desta sessão, para não repetir

1. **Apliquei DDL com PR aberto e serializei tudo.** O recorte certo **não é "isso é DDL?", é "vou
   registrar uma versão?"** — qualquer `migration repair` deixa vermelho todo branch sem aquele
   `.sql`. A memória foi corrigida.
2. **Aceitei um "todos verdes" onde o gate que importa nem estava na lista.** `validate` estava na
   fila do grupo de concorrência e ainda não tinha registrado check-run; minha condição de parada
   era vacuamente verdadeira. **Monitorar por RUN, não por `gh pr checks`.**
3. **Repeti um escapador parcial 3 linhas depois de corrigi-lo.** Duas cópias de um escapador é uma
   cópia a mais.
4. **Confundi o comitê de SELEÇÃO com o de CURADORIA.** Foi o PM quem corrigiu — e a correção
   revelou que observadores receberiam a fila de avaliação.
5. **`Closes #a, #b, #c` fecha só a primeira.** Cada número precisa da palavra-chave.

---

## ⚠️ OUTRA LANE VIVA: PR #1673 (worktree separada) — LER ANTES DE TOCAR NAQUELE BRANCH

Prompt próprio: **`docs/planning/2026-08-07_PROMPT_ARRANQUE_MAIN_LANE_1673.md`** (ler antes de
qualquer coisa naquela frente). Objetivo: **QA e merge do PR #1673**
(`fix(comms)`: o rodapé dizia "Ciclo 4" e levava à playlist do ciclo 3, porque a do 4 não existia).

### O commit órfão é MEU, e a árvore de trabalho é a causa

Medido em 07/08 à noite:

```
origin/fix/youtube-playlists-ciclo4-gerais-e-lideranca → 55bb9265   ← o head REAL do PR
local /fix/youtube-playlists-ciclo4-gerais-e-lideranca → 08a17f2f   ← órfão POR CIMA
                                                          55bb9265
```

`08a17f2f` é `fix(lgpd): o consentimento de IA gravava o carimbo…` (#1666) — **desta sessão**. Ele
caiu ali porque este diretório estava com o branch do #1673 em check-out no momento do commit, e é
literalmente a armadilha de `reference-two-sessions-one-working-tree-contaminate-the-branch`:
**`git log -1` ANTES de `checkout -b`.**

✅ **Nada se perdeu:** o conteúdo do `08a17f2f` já está na `main` pelo squash `49a8586f`. O órfão é
**resíduo local**, não trabalho pendente.

### Regras para aquela lane

1. **Trabalhe SEMPRE a partir de `origin/`**, nunca do branch local — o local tem o órfão por cima.
2. **Atualize o PR por MERGE, nunca rebase.** Force-push está bloqueado nesta máquina (o harness
   recusa; só o Vitor consegue).
3. **NÃO empurre o `08a17f2f`** para aquele branch: ele já está na `main` e reapareceria como
   diff duplicado no PR.

### Estado do PR, medido em 07/08 à noite

| | |
|---|---|
| head do PR | `55bb9265` · `mergeable = MERGEABLE` |
| `validate` | **fail** — classificar antes de qualquer coisa |
| demais gates | CodeQL, analyze, browser_guards, check-invariants, deno, gen-types-drift, issue_reference_gate, visual_dark_mode: **pass** |

⚠️ O `validate` vermelho **precisa ser classificado, não presumido**. Nesta sessão houve três
classes de vermelho que não eram do PR: a #1649 (fechada), a **esm.sh fora do ar** no `deno`, e o
**timeout do passo `Smoke Test Routes`** (teto de 2 min do passo, com o dev server levando 13 s
para subir). Comparar com um commit vizinho que passou é o instrumento mais barato.

---

## Regras da casa

- Commit: `Assisted-By:`, nunca `Co-Authored-By`.
- Repo **PÚBLICO**: nenhum candidato ou membro nomeado, só contagens.
- Não rodar `npm test` local com CI em voo — **gatear**, não só imprimir o número.
