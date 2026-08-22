# Handoff 21/08 (2a sessao): a fila era um impasse de DUAS metades

> Medido ao vivo em 21/08/2026 (UTC). **Re-medir antes de agir.** Repositorio PUBLICO:
> sem nome de pessoa e sem identificador de candidatura.

---

## 1. Estado da fila

`main` em **`d4c20a00`** (era `fe268cf2`). **A fila andou.**

| PR | desfecho |
|---|---|
| **#1905** | **MERGEADA** 19:41:41Z, sem bypass. Carrega as duas metades. |
| **#1907** | fechada como superseded (o commit dela foi por `cherry-pick -x`) |
| **#1904**, **#1894** | branches atualizadas a partir da main, CI re-rodando |

## 2. O achado: o handoff anterior nomeava UM bloqueador, e eram DOIS

O handoff das 14h atribuiu o vermelho das tres PRs a linha `gate_attempts` `ec7336f2`
(criada 21/08 14:18:47). Para a #1905 isso era verdade. Para a #1904 nao: o ultimo
`validate` dela rodou as **04:07**, dez horas ANTES da linha existir, e falhava com **3**
testes de outra familia.

**Bloqueador A, PROD-AHEAD (#1900).** As 3 funcoes do cron (`_tribe_journey_health_data`,
`_sync_tribe_journey_card`, `sync_tribe_journey_cards_cron`) estavam vivas em producao e
**nenhuma migration na main as capturava**: o `.sql` existia so na branch da lane. Isso
derrubava Q-C (orfas), Phase C (body-hash) e ADR-0097 (missing-file) na main e em **toda**
branch tirada dela, mais o `gen-types-drift`.

**Bloqueador B, a linha `ec7336f2`.** Derrubava o guard do #1636 em toda branch, inclusive
na da lane.

**O impasse:** cada PR tinha metade do verde.

| branch | tem | `validate` |
|---|---|---|
| #1904 (run das 04:07) | nada | `fail 3` (PROD-AHEAD) |
| #1907 (allowlist) | metade B | `fail 3` (so PROD-AHEAD) |
| #1905 (migration + tipos) | metade A | `fail 1` (so o gate) |
| #1905 + cherry-pick | **as duas** | **verde** |

A saida foi `cherry-pick -x` do commit de 1 linha para a branch que destrava (a #1905, que
e quem encerra o PROD-AHEAD), feito em **worktree destacado**: a arvore principal nao foi
tocada.

## 3. Por que isso ficou invisivel

> ⚠️ CORRIGIDO em 23:15. Este trecho dizia que `validate` nao roda em push para a main.
> **Errado**: `ci.yml` declara `on: push: branches: [ main, dev ]`. O erro veio de listar
> `gh run list --branch main --limit 8`, onde o `CI Heartbeat Monitor` (a cada ~30 min)
> ocupou as 8 posicoes e escondeu os runs de push. Ver #1910.

`validate` roda na main, mas so em **push**. Aplicar DDL num banco compartilhado nao e um
push, entao a verdade que o guard afere muda **fora do repositorio** e nada dispara a
reafericao:

| horario | fato |
|---|---|
| 03:23:39Z | ultimo `CI Validate` da main (`fe268cf2`): success, e legitimamente |
| 03:54:35Z | a DDL entra no banco, 31 min depois |
| 03:54 -> 19:41 | nenhum push na main, logo nenhum run novo |

Por **15h47m** a main exibiu um verde pre-DDL. Ele nao estava errado quando foi calculado;
ele nunca foi recalculado.

📌 **Um required verde e um carimbo de tempo, nao um estado.** Quando parte da verdade mora
num banco compartilhado, a validade do carimbo expira sem aviso e sem mudar de cor. Foi
assim tambem que o verde da #1904 virou retrato velho.

## 4. O sinal de governanca, que nao e de fila

A `ec7336f2` e a **QUINTA** tentativa de emitir convite de agendamento sobre a MESMA
candidatura, e a **primeira posterior a decisao do PM** de 20/08 de descontinuar a dispensa
do gate. As quatro anteriores sao todas do dia 20; esta e do dia 21.

Medido ao vivo: a candidatura segue com **zero avaliacoes** de qualquer tipo, **0 tokens**
vivos e status `interview_pending`. Nenhum token emitido, nenhum e-mail enviado. O gate
recusou pela quinta vez, exatamente como projetado.

O allowlist saiu de 1 para **6** entradas, e as cinco ultimas sao a mesma operacao repetida.
Isso mede a ausencia de superficie autenticada (**#1586**), nao chatice do guard: enquanto a
RPC nao tiver tela, toda decisao manual entra por `service_role` e vira divida de teste.

## 5. Como a hipotese do guard foi descartada

A mensagem de falha nomeia "algum teste voltou a escolher alvo por predicado sobre
producao". Isso e hipotese, nao diagnostico. Descartada por medicao:

- arco do gate re-executado (71 testes, 5 arquivos): `gate_attempts` em **697 antes e 697
  depois**, com as **mesmas 9** sem ator pos-cutoff dos dois lados;
- Camada A passou inteira;
- `admin_audit_log` sem **nenhuma** linha na janela de +/-10min;
- e o guard nao esta cego: as outras 3 linhas sem ator fora da lista (14/08 15:00, 17/08
  15:30 x2) **tem** carimbo de cron e por isso nunca foram acusadas.

Prova de que o verde e por conserto: trocar **um caractere** do UUID deixa os DOIS testes
vermelhos (a correlacao e o ratchet de sincronia).

## 6. Pendencias

- **#1881** segue aberto e e a raiz do card de XP (o gatilho vigia as 3 colunas, o corpo
  ainda exige transicao de status). Vai repetir.
- **#1906**: escrita condicional da reconciliacao + agenda diaria (follow-up da lane).
- **5 commits so nesta maquina**, em 3 branches sem remoto:
  `feat/1153-volunteer-term-signing-sync` (2), `feat/1209-credly-keyword-tuning` (2),
  `feat/1148-curation-xp-backfill` (1).
- **`stash@{0}`** nao descartar: o conserto do `CardDetail.tsx` do #1903 ainda esta la.
- **Tres candidaturas com ZERO avaliacao**, uma travada em `interview_pending`.
- Duas branches liberadas para apagar (registro de recuperacao):
  `backup/pre-rebase-1899` = `80035339395aa358e18608329374177e730e2ebb` (so local),
  `claude/portfolio-cards-flags-tags-e7x1ar` = `d236e843150be13884cb653f1fd47efb59a5f462`.
  Nenhuma guarda trabalho nao-landado: a segunda tem arvore identica a main (assinatura de
  squash-merge) e a primeira so tem, de exclusivo, as 4 linhas do teste do #1113 que
  escolhiam alvo por predicado, justamente o anti-padrao que a #1902 consertou.

## 7. Armadilhas medidas nesta sessao

- **Run de CI ANTERIOR ao incidente nao e explicado por ele.** Compare os timestamps, e
  **conte as falhas**: o guard do #1636 derruba 1 teste, e o run mostrava 3.
- **`--log` da API vem truncado na cauda** e some com o nome da falha. Use
  `gh run view --job N --log-failed | grep 'not ok'`.
- **A saida local e colorida**, entao `grep -E '^ℹ'` nao casa (o ANSI vem antes do `ℹ`) e o
  filtro volta VAZIO mesmo com falha. Passe `sed -r 's/\x1B\[[0-9;]*[mK]//g'` antes.
- **`cmd | tail` reporta o exit do `tail`.** Um `npm test` que falhou saiu com "code 0".
- **Nem todo check vermelho e required.** Aqui os required sao `validate`, `browser_guards`
  e `deno`; o `gen-types-drift` nao e. Confira antes de declarar impasse.
- **`node_modules/` no `.gitignore` e padrao de DIRETORIO**, entao um *symlink* com esse
  nome aparece como nao rastreado e um `git add -A` o comitaria.
