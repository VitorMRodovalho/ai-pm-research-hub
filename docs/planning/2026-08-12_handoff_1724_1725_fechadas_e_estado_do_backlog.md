# Handoff - higiene de CI fechada (#1724 + #1725) e o backlog medido (11-12/08/2026)

> Continuacao de `docs/planning/2026-08-10_handoff_1726_comunicacao_e_1728_escopo.md`.
> Cobre a PR **#1736**. `main` em **`27a9a6af`**, deploy em producao saiu, **zero bypass**.
>
> 📌 **A proxima sessao e de PLANEJAMENTO.** O plano sera dito la pelo PM. Este documento entrega
> **estado medido**, nao plano: o que fechou, o que esta aberto, e os numeros para decidir.

## Regra zero

Todo numero deste documento foi medido por tool call em **11-12/08/2026**. A contagem de issues
muda a cada sessao e a de presenca muda continuamente. **Re-medir na mesma volta** em que o numero
entrar numa decisao, num commit, numa issue ou numa pergunta ao PM.

---

## O que foi entregue

### PR #1736 - #1724 e #1725, fechadas

As duas issues eram a mesma higiene: vermelho de CI que nao carrega informacao sobre o commit.
Tres em 10-11/08, nenhum de codigo, um deles numa PR **doc-only**.

**#1724 - a faixa do banco falhava por fila LONGA, nao por fila TRAVADA.** Medido por job, 12 runs:
`validate` min 674s / mediana 735s / **MAX 1533s**; `check-invariants` min 39s / mediana 49s /
**MAX 861s**. O teto era 900s, ou seja **menor que a espera legitima por UM job na frente**, e
impossivel de cumprir com dois. Agora:

- criterio = **falta de progresso** (`stuck-seconds: 1800`), com o relogio reiniciando quando a
  cabeca da faixa muda. Enquanto a fila anda, esperar e o comportamento correto.
- teto absoluto vira backstop: 900 -> 3600s.
- `api-retries: 3` com recuo para o handshake TLS que falha uma vez. Esgotadas as tentativas
  continua **falhando fechado** (engolir o erro faria a faixa parecer vazia - o estrago do #1509).

**#1725 - um orcamento para duas coisas de variancia muito diferente.** `timeout-minutes: 2` cobria
subir o dev server E exercer 42 rotas; o passo morria **sem nenhuma assercao falhar**. Agora cada
fase tem orcamento e mensagem propria (boot 90s, assercoes 120s, requisicao 15s), **cada rota se
anuncia no log antes de ser exercida**, e o teto do passo vira backstop (2 -> 6 min).

### O efeito colateral que exigiu decisao do PM

A espera pela faixa corre **dentro** do orcamento do job. Subir o teto para 3600s sem subir o
`timeout-minutes` faria o runner matar o job antes de a espera se explicar - o mesmo vermelho
obscuro por outro caminho. **Foi o guard do #1509 que pegou**, comparando os dois numeros.

Decisao do PM (12/08): subir os orcamentos. **`validate` 32 -> 95 min**, **`check-invariants`
25 -> 70 min**. Repo e PUBLIC, entao minuto de runner e gratuito, e um job de fato travado nao
chega perto disso: morre em 1800s pela `stuck-seconds`.

### Verificacao ao vivo, na main

`check-invariants` esperou o `validate` sair: **710s medidos pelo relogio** (14:37:17 -> 14:49:07),
com **um unico** job na frente. Contra o teto antigo de 900s isso e **79% consumido, sobrando
190s**. Passaria hoje, mas por margem fina - e o estouro acontecia com dois na fila, que foi como a
#1724 nasceu. Contra o teto novo, 20%.

⚠️ **O contador `waited` do log SUBESTIMA**: disse 615s contra 710s reais (13% a menos), porque soma
15s por volta e ignora o tempo das chamadas de API. Nao afeta decisao (os prazos usam `date +%s`),
mas quem ler o log para dimensionar a fila vai ler baixo. Ajuste de uma linha, nao feito.

---

## Armadilhas pagas nesta sessao

Todas viraram licao registrada. As duas primeiras estao na memoria; as quatro estao na **#588**
(intake de licoes do PMO).

### 1. Um guard estava DECORATIVO e ficaria verde para sempre

```js
Number(fonte.match(/SMOKE_BOOT_TIMEOUT_MS \|\| (\d+)/)[1].replace(/_/g, ''))
```

sobre o literal `90_000`. O `\d+` para no separador de milhar: leu **90**. O guard comparava 6
minutos contra **210 ms** achando que eram 210 s. O `replace` do `_` mostra que o autor previu o
problema, mas roda **depois** da captura. Correcao: capturar `(\d[\d_]*)` **e** assertar piso de
sanidade sobre o valor lido. Sem o piso, a proxima forma de quebrar a captura passa de novo.
→ [[reference-guard-que-le-numero-da-fonte-perde-o-separador-de-milhar]]

### 2. O guard de ausencia casou o PROPRIO COMENTARIO (terceira ocorrencia, agora em `.mjs`)

`doesNotMatch(fonte, /dev\.kill\(/)` reprovou o codigo **correto**, porque o cabecalho do arquivo
explica que `dev.kill()` era o defeito. Delta novo: **o stripper de comentarios tambem precisa de
controle positivo**, senao um stripper agressivo apaga codigo e a negativa vira decorativa.

### 3. O `finally` sempre deixou o dev server de pe

So apareceu ao **exercer** o script, e precisou de tres medicoes, cada uma derrubando uma hipotese:

| tentativa | orfaos |
|---|---:|
| `dev.kill('SIGTERM')` | 1 (morre o `npm`, o `astro dev` fica) |
| SIGTERM no **grupo** | 1 (o sinal CHEGA, o processo ignora) |
| grupo + **SIGKILL** | **0** |

Corolario: `finally` **nao cobre morte por sinal**. Quem pode ser morto por watchdog externo precisa
de handler proprio. → [[reference-matar-o-filho-nao-mata-o-neto-e-sigterm-no-grupo-nao-basta]]

### 4. O instrumento de medicao participou da medicao, tres vezes

| medicao | o que o instrumento fez | leitura errada |
|---|---|---|
| `npm test \| tail` | o pipe devolve o exit code do `tail` | "a suite passa com 1 falha" |
| `pgrep -f 'astro dev ... 4488'` | o padrao casa o proprio shell | "3 antes, 3 depois" (era 1 e 1) |
| `timeout 400 npm run smoke \| grep` | o neto sobrevive e segura o pipe | saida vazia por 10 min, parecendo travamento - **o teste tinha passado** |

Antidotos: capturar exit code **antes** de qualquer pipe; truque do colchete (`[a]stro`) ou ancora
(`^node `) em contagem por `ps`/`pgrep`; desconfiar de "saida vazia" antes de concluir travamento.

### 5. `Fecha #N` nao fecha nada

O corpo da PR #1736 dizia `Fecha #1724 · Fecha #1725`. O GitHub so reconhece as palavras em ingles.
Do jeito que estava, o merge sairia limpo e **as duas issues ficariam abertas em silencio**.
Trocado por `Closes` antes de mergear. Ja era licao conhecida; custou de novo.

---

## Estado do backlog, medido em 12/08

**818 issues no total: 194 abertas, 624 fechadas.**

### ⚠️ A contagem por onda NAO mede progresso

O rotulo `onda:` nasceu na triagem de 09/08 e **nao foi retroaplicado**: 620 das 624 fechadas nao
tem onda. A tabela abaixo e uma **particao do backlog aberto**, nao um placar. Ler "0% feito" numa
onda seria falso.

| onda | abertas | fechadas |
|---|---:|---:|
| 0 triagem/PII | 3 | 0 |
| 0.5 superficie publica | 7 | 0 |
| **1 presenca** | **9** | **4** |
| 2 ciclo seletivo | 26 | 0 |
| 3 agenda/recorrencia | 21 | 0 |
| 4 seguranca | 13 | 0 |
| 5 autossuficiencia MCP | 32 | 0 |
| **6 suite e CI** | **11** | **2** |
| 7 dados/metricas | 14 | 0 |
| 8 admin/membro | 15 | 0 |
| 9 comms/curadoria | 12 | 0 |
| 10 certificados | 10 | 0 |
| 11 legal-ops | 19 | 0 |

As 4 fechadas de presenca sao #1653, #1657, #1660 e #1705. As 2 de suite-ci sao #1724 e #1725,
**rotuladas nesta sessao** - tinham nascido so com `type:task`.

⚠️ **O rotulo de onda nao esta sendo aplicado no nascimento**: de 10 issues criadas desde a triagem,
2 sairam sem onda. Vale um habito ou um gate.

### Cobertura de triagem das 194 abertas

- **prioridade:** 81 sem rotulo · 57 media · 43 baixa · **13 alta**
- **tipo:** 116 sem rotulo · 32 task · 24 feature · 22 bug
- **status:** 183 sem rotulo · **9 bloqueadas** · 2 prontas

### O saldo e negativo, mas a composicao e melhor que o numero

| janela | fechadas | criadas | saldo |
|---|---:|---:|---:|
| 7 dias | 46 | 79 | **-33** |
| 14 dias | 66 | 130 | **-64** |
| 30 dias | 125 | 201 | **-76** |

**As 201 criadas em 30 dias sao DESCOBERTA, nao acumulo de pedido novo.** Tres medidas independentes:

1. **Rajada, nao fluxo.** 189 humanas em 24 dias distintos, mediana 6/dia, **pico de 28 num dia**
   (07/08); os 6 dias mais cheios concentram metade.
2. **O conteudo diz de onde veio.** 76% citam outra issue ou PR · 58% usam
   "medido/observado/descoberto" · 38% trazem bloco de codigo ou log · 14% datam a sessao. So **12
   (6%)** nao tem sinal, e ao abrir sao saidas de auditoria (`[audit A1]`, `[audit B0]`) e bugs.
   **Nenhuma parece item de roadmap.**
3. **Metade se consome sozinha.** Das 189 humanas, **103 (54%) ja foram fechadas dentro da janela**.

Sinal **descartado**: "criada em dia com merge" deu 99%, mas 28 dos 30 dias tiveram merge, entao
nao discrimina nada. Nao conta como evidencia.

**Onde de fato pesa:** das 194 abertas, **108 (56%) sao anteriores a 13/07**. Essa e a parte que
envelhece, e e ela que as ondas particionam.

### Um numero falseavel para conferir daqui a um mes

**7 issues `[CI Monitor] CI Validate failing on main` em 30 dias** (#1365, #1540, #1569, #1650,
#1651, #1702, #1709), todas fechadas na mao. E o custo automatizado dos vermelhos de CI, e e
exatamente o que #1724 e #1725 atacaram. **Se a correcao pegou, essa contagem cai na proxima
janela.** Se nao cair, a causa era outra.

---

## Estado final

- `main` em **`27a9a6af`**, 6 de 6 checks verdes, **deploy para o Cloudflare saiu**.
- **#1724 e #1725 CLOSED**, branch removido, zero bypass na semana.
- Licoes registradas na **#588** (4 licoes, com propostas para o framework do PMO). Ainda **nao
  colhidas** pelo `pmo-sync.sh harvest`.
- Memoria atualizada: 2 entradas novas, 1 terceira ocorrencia anexada, indice compactado de 19,7 KB
  para 17,2 KB (READ-FIRST superado movido integro para `MEMORY_ARCHIVE_INDEX.md`; **70 entradas
  antes e depois, nenhuma perdida**).

## Para a sessao de planejamento

O plano vem do PM. O que este handoff coloca sobre a mesa, sem propor ordem:

**Ordem herdada do handoff anterior** (nao re-litigada, mas nao reconfirmada): #1710 -> #1654 ->
#1218. As tres seguem abertas, e o **#1710 esta desbloqueado** desde que a comunicacao da #1726 saiu.

**Decisoes do PM ja tomadas sobre o #1710, NAO re-litigar:** selo **AUTOMATICO com janela e aviso** ·
sponsor/chapter_liaison fora do tier nao sao cobrados de geral · gestor sem tribo nao e elegivel a
reuniao de tribo · publico = **86 ativos de uma vez**, janela **14 dias**, correcao pelo **lider da
tribo** (GP como recurso). Escopo exige **dry-run** e **reversao por evento** - nao existe `unseal`.

**Itens que continuam abertos e nao entraram em nenhuma onda de execucao ainda:**

- **#1728**: as 2 RPCs de escrita foram corrigidas, mas **20 RPCs da mesma classe seguem abertas**,
  rastreadas sem detalhe na issue (repo publico).
- **#1729**: as 8 reunioes futuras da tribo arquivada foram canceladas, mas **as 5 de coorte zero
  seguem na janela** e a causa raiz da recorrencia continua aberta.
- **#1656 e #1655**: nomear as 3 semanticas na tela, destino de `get_attendance_rate`, unificar
  "faltas consecutivas", limpar a chave velha; unificar os 4 componentes mais
  `src/pages/profile.astro` (linhas 1015 e 1385), que calcula a propria taxa sem RPC.
- **Higiene de processo** levantada por este handoff, custo baixo: rotulo de onda no nascimento da
  issue · 81 abertas sem prioridade e 116 sem tipo · o `waited` que subestima a fila.

**Perguntas que so o PM responde:**

1. As ondas viram ordem de execucao, ou a ordem herdada (#1710 primeiro) continua acima delas?
2. As 108 abertas anteriores a 13/07 recebem uma varredura de envelhecimento, ou seguem so
   particionadas por onda?
3. O rotulo `onda:` vale a pena ser retroaplicado ao historico (para o placar existir), ou fica
   assumido como particao do aberto?
