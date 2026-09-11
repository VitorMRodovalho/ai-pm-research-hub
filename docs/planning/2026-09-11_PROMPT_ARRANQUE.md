# Arranque: o que ficou de pé quando a sessão de 09 a 11/09 foi encerrada

> **Nada aqui é medição.** Carimbado em 11/09 às 11h BRT, ao limpar contexto.
> **Re-meça antes de decidir:**

```bash
git fetch --all && git log --oneline -1 origin/main
gh pr list --state open
gh issue list --state open --limit 40
```

**Estado ao encerrar, para COMPARAR:** `main e98b7ee1`, sem mover desde 09/09 às 22:59 ·
**4 PRs abertas, TODAS `BLOCKED`** · **0 alertas** no Dependabot · **0 bypass**.

---

## 1. A fila está congelada, e esse é o item zero

O `validate` é obrigatório pelo ruleset da main e reprova em asserção de **dado vivo**. Nada mergeia
até isso fechar. A **#2233** é a issue-mãe.

| PR | o que é | de quem |
| --- | --- | --- |
| **#2235** | conserta o `#1536` e o `#676` | esta sessão |
| #2232 | rastreamento da sessão | esta sessão |
| #2230 | handoff da Reunião Geral de 10/09 | lane `-ff` |
| #2223 | skill de publicação no YouTube | lane `-ff` |

**O que já caiu:** o `#1536` (contava falta como presença) e o `#676` (dois defeitos distintos, ver
abaixo). Ambos na **#2235**, testados contra o banco vivo.

**O que sobra:** **`#1945 C`**, "nenhum pesquisador passou em ALGUM board e falhou em outro: ou os
seeds mudaram, ou o helper virou constante". A lane `-ff` ficou com ela. A hipótese dela é
vencimento de engajamento por data, **ainda não testada contra nada**.

---

## 2. Dois defeitos com o mesmo número, e não confundir

O `#676` falhou **duas vezes por causas diferentes**, e a segunda foi criada pelo conserto da
primeira.

**Primeira:** `materializadas (7) > esperadas (6)`. Causado por eu ter tornado a série de
comunicação semanal **nos eventos** e deixado a **regra** dizendo `biweekly`. Consertado no banco em
11/09: regra da quinta virou `weekly` às 18:30, regra da terça foi para `paused`.

**Segunda:** `7 tribe rules + 2 comms rules backfilled with correct cadence`, que exigia
"exactly one biweekly among the comms rules". Ficou falso **por causa do conserto acima**.
Corrigido na #2235, trocando o que o assert afirma e somando um segundo assert para o zero não
poder ser satisfeito por ausência.

---

## 3. A suspeita que pode valer mais que tudo nesta lista

**#2231**, `browser_guards` nunca falhou em **87 runs** até 09/09, e falhou **3 vezes nos 13**
seguintes. O corte é o merge do `astro 7.2.2 -> 7.2.10` (#2215).

Não dá para reverter: a 7.2.2 tem o **RCE critical** por AVIF.

**A #2219 é pré-requisito da #2231.** O retry do `browser_guards` não limpa o daemon, então qualquer
bateria de repetição reporta o dobro da taxa real. Consertar o retry primeiro.

**E a #2217 (ondas de dependência) está bloqueada de fato pela #2231:** subir mais dependência antes
de entender a regressão é repetir o ciclo que o dono levantou.

⚠️ Há um sintoma local não explicado: `astro build` pendurou **3 vezes** nesta máquina, com carga
alta e com carga baixa, sempre no mesmo ponto. O CI compila a mesma árvore normalmente. **Eu disse
que era contenção local e estava errado.** Não há explicação confirmada, e não somei isso à #2231
para não repetir alarme falso.

---

## 4. Defeitos achados por exercer o caminho, não por procurar

Todos nasceram de alguma ação real desta sessão.

| # | o que | como apareceu |
| --- | --- | --- |
| **#2225** | `event_write` autoriza pelo `initiative_id` e não o grava | criar o evento da reunião pelo MCP |
| **#2234** | `member_lifecycle` perde parâmetros da RPC, incluindo a **data de saída** | formalizar um desligamento |
| **#2236** | taxa de presença conta falta de reunião anterior à entrada | dois líderes reportaram no grupo |
| **#2226** | home e MCP mostram nomes diferentes para a mesma pessoa (9 de 135) | conferir o time nas três rotas |
| **#2227** | curadoria não existe no modelo | montar audiência de e-mail |
| **#2228** | 1 líder de tribo e 2 pesquisadores sem tribo nenhuma | a mesma audiência |

A **#2225** e a **#2234** são a mesma classe: a camada semântica do MCP perde parâmetro que a RPC
canônica tem. O conserto que pega as duas é **um teste de contrato que compare assinatura da RPC
com schema da tool**.

---

## 5. A #2236 tem uma pista nova que a issue ainda não incorporou

A issue aponta o cron de selagem como candidato. **Medição posterior mostrou que ele não explica o
caso principal:**

O Nestor entrou em **15/08**. Em **27/08**, doze dias depois, **oito faltas retroativas nasceram no
mesmo instante**, cobrindo eventos de 09/07 a 12/08. O cron diário sela a janela do dia; ele não
cria oito eventos de semanas diferentes de uma vez.

Isso é assinatura de **backfill no momento do ingresso**. A Anastasia entrou no mesmo dia e tem o
mesmo padrão. **Convivem três escritores na tabela `attendance`, e só um está errado.**

Atualizar a #2236 antes de consertar, senão o conserto erra o alvo.

---

## 6. Feito e NÃO refazer

- **Três desligamentos formalizados**: João Paulo Castro (02/09, prioridade externa), Letícia
  Rodrigues Vieira (15/07, sobrecarga profissional) e Cristiano Nunes (11/09, lapso de filiação).
  Todos com motivo, data correta e certificado. Nenhum tinha item atribuído.
- **Pesquisa da Tribo 4 enviada a 78 pessoas** (74 por campanha + 4 individuais), todas entregues.
- **Reunião do time de comunicação de 10/09** registrada: ata, 6 presenças, 4 decisões, 8 ações
  rastreáveis. Cadência corrigida para semanal às quintas, 18:30.
- **Currículo da Patrícia Sebastião recuperado** a 23h da assinatura expirar. Ela é uma das 3
  candidatas com entrevista pendente.
- **RCE critical do astro fechado**, 17 alertas do Dependabot zerados.
- **Pesquisa das docs dos 45 dias** nos 8 provedores, mergeada (#2212).

---

## 7. Do lado do dono

1. **Os cinco pontos do PMOGA**, só na thread do WhatsApp do grupo "Núcleo Tribos PMO / PMO GA
   LATAM". Varri banco, Gmail, Drive e 9 exports: não estão em lugar alcançável.
2. **A resposta do Jefferson** sobre se a reunião de 18/08 aconteceu. Decide se há presença legítima
   a recuperar, porque as linhas foram apagadas em 03/09.
3. **A Tribo 10 tem 1 pessoa ativa: o próprio líder.** Zero pesquisadores, zero reuniões futuras, 10
   cards (4 concluídos, incluindo um inventário de domínio que é ativo transferível). O Honório
   propôs encerrar e seguir noutra tribo. Três cards vivos precisam de destino antes.
4. **Regularizar o VEP de Sarah e Roberto**, curadores sem VEP ativo.
5. **Os 3 candidatos** seguem sem reserva de entrevista, com e-mail entregue.

---

## 8. As lições que a sessão pagou caro

**Premissa de handoff vale como hipótese.** Uma frase sobre o `extract-zip` sobreviveu a três PRs
sendo repetida e só caiu quando foi preciso assinar uma dispensa com ela.

**`^` não segura o que você decidiu segurar.** Quando a intenção é prender numa linha, o operador
é `~`.

**Re-run REESCREVE a conclusão do job.** Falha histórica de CI se mede por `run_attempt > 1` e
`/attempts/1/jobs`, nunca por `conclusion`.

**Contagem igual não prova conjunto igual.** VEP e plataforma deram 72 dos dois lados, e a diferença
simétrica achou 12 de um lado e 2 do outro.

**Zero só vale com controle positivo.** Usado o tempo todo aqui, e foi o que separou "não há" de
"chave errada" em pelo menos quatro medições.
