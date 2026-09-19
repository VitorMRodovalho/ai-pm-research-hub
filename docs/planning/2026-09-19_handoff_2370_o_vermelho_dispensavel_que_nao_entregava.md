# Handoff 19/09 (manhã): o vermelho dispensável não era dispensável

> **Nada aqui é medição viva.** Carimbado em 19/09 entre ~06h e ~08h UTC.
> **Re-meça antes de decidir.** Repositório público: este documento não nomeia o segundo
> repositório envolvido, pelo motivo da seção 6. O identificador vive na memória privada
> `project-relogios-vivos-agosto-2026`.

**Estado ao encerrar:** `main f7c087bc` · **0 PRs abertas** · 2 PRs mergeadas (#2375, #2376) ·
#2370 com os passos 1 a 4 fechados e **exercidos**.

---

## 1. O pedido era "retomar a #237", e a #237 não existe viva

A única `#237` é um bug fechado em 21/05 com 0 comentários. O dono confirmou que era a **#2370**,
primeiro item da tabela ABERTO do handoff de ontem. Vale como padrão: número de issue truncado
resolve para uma issue real e errada, e a confirmação custou uma pergunta.

## 2. A issue estava errada exatamente no ponto que travava a execução

A #2370 ordenava 5 passos e avisava "não executar o passo 3 antes do 2", porque desativar os
workflows do outro repositório deixaria Governance e Comms **sem caminho vivo**. Re-medido, isso
não se sustenta, e três afirmações caíram:

| a issue dizia | a medição de hoje |
|---|---|
| ~75 corridas agendadas de lá escreviam em produção | o repositório tem **4 secrets**, todos de 2026-03-08, e faltam os de Comms e Credly: os dois pularam o step `Trigger` em **10 de 10** corridas |
| desativar lá deixa Governance e Comms sem caminho vivo | Comms é entregue pelo `pg_cron` jobid 21 (**88 linhas em 30 dias**, a última às 06:00 de hoje, **zero** com `triggered_by=github_actions`); Governance nunca tocou banco |
| o 504 do Credly é "o vermelho que ninguém precisa" | nas 4 corridas com `IDLE_TIMEOUT`: **0, 0, 0 e 0** membros carimbados. Não entregava nada |

E a rotação de ontem **trocou o 401 de lado**: às 22:25:54 este repo teve HTTP 200 e gravou a
linha às 22:26:04 em `knowledge_ingestion_runs`; **26 segundos depois** a corrida de lá levou 401.
Era a confirmação direta da inferência que a issue tinha deixado em aberto.

## 3. Quem ENTREGA cada sync

A tabela que faltava. `PROJECT_ON_TRACK.md` tinha a coluna "chamada de", que lista quem *pode*
chamar — e por isso não mostrava que havia três caminhos para `sync-credly-all` e que só um
entregava. A coluna "quem ENTREGA hoje" entrou nesta onda.

| sync | caminho vivo, medido |
|---|---|
| Knowledge Insights | o workflow **deste** repo, desde 18/09 22:26 (antes: 401 em **56 de 56**) |
| Credly | `pg_cron` **jobid 14**, a cada 5 dias às 03:00 UTC |
| Comms Metrics | `pg_cron` **jobid 21**, diário às 06:00 UTC |
| Project Governance | ninguém: é snapshot local, não chama Edge Function |

## 4. O conserto do Credly, e o segundo defeito que só o exercício achou

O modo de falha era `{"code":"IDLE_TIMEOUT","message":"Request idle timeout limit (150s) reached"}`.
**Idle**, não wall-clock: a EF não emite byte até terminar, então o relógio de idle é o tempo
total do lote.

Diagnóstico exercido, não inferido: token inválido devolve **401 em 1 s** (o caminho de
autenticação não é o que pendura); a chamada idêntica à do workflow, feita à mão, devolve
**200 em 40 s**; o próprio workflow, re-disparado, **200 em 53 s**. O secret estava correto.
**A falha não foi reproduzida** — o que se sabe é que o lote leva 40-53 s contra um teto de 150 s,
e que quatro vezes passou disso.

A saída veio do `pg_cron`: ele desiste de esperar em 3 s e o lote **completa assim mesmo**. A EF
sobrevive ao caller desconectar. Então o workflow passou a despachar sem segurar a conexão e a
**afirmar a entrega lendo `members.credly_verified_at`** (PR #2375).

**E aí o exercício reprovou.** O passo que existe para tratar `curl (28)` como caso normal morreu
com exit 28: `set -uo pipefail` **não desliga o errexit**, porque o `-e` não vem do script, vem da
invocação `bash -e {0}` do Actions. Consertado na #2376, com controle negativo (status 7 continua
reprovando — sem ele, `set +e` viraria "nunca falha").

Estado final, run 35430273896 na `main`, verde com os 7 passos:

```
Sem resposta em 25s — despachado. A verificacao decide.
membros carimbados desde 2026-09-19T07:47:27Z: 54
ENTREGUE: 54 membros carimbados
```

Total final do lote, por consulta nova: **69 membros**, entre 07:47:29 e 07:48:02. A verificação
leu 54 porque quebra no primeiro maior que zero, com o lote ainda correndo: ela afirma **entrega**,
não completude, e é isso que a mensagem dela diz.

## 5. ⚠️ Sobrescrevi um comentário de julho e recuperei

`gh issue comment --edit-last` **não edita o seu último comentário**. Ele sobrescreveu o
comentário `4910691970`, de 08/07, que tinha 4 lições técnicas. Só peguei porque o **id devolvido
não batia** com o que eu tinha criado 40 segundos antes; o comando sai com exit 0 e uma URL de
aparência normal.

Recuperação existe e está documentada na #588: a REST não expõe histórico, mas a GraphQL sim, via
`userContentEdits`; o nó `[1]` carrega o corpo anterior. Restaurado por
`gh api -X PATCH .../issues/comments/<id>` e conferido por leitura nova.

⇒ **Editar comentário sempre pelo id explícito.** E a regra geral: **um seletor implícito
("last", "latest", "current") é um seletor que você não mediu.**

## 6. Por que este documento não nomeia o outro repositório

Ele é privado e do mesmo dono. A combinação "repositório X guarda segredo vivo do projeto Y" é um
roteiro, e este repo é público. O identificador está na memória privada
`project-relogios-vivos-agosto-2026`, junto com o estado dos workflows dele — e vale registrar que
**antes desta sessão o nome não estava em lugar nenhum** e teve de ser re-descoberto varrendo 43
repositórios, com controle negativo e positivo na mesma execução (a varredura original da #2370
tinha respondido "TEM" para 44 de 44, porque a sonda testava presença de saída).

## 7. ABERTO

| # | o que | estado |
|---|---|---|
| #2370 passo 5 | arquivar o outro repositório | **decisão do dono**: custo medido é congelar 33 issues e 5 PRs em somente-leitura; desativar os workflows já fechou a escrita, então virou higiene |
| #2370 novo | `Comms Metrics Sync` deste repo, 29 verdes sem trabalho | **bloqueado em fato**: o dono pediu consertar, e `COMMS_METRICS_SOURCE_URL` é um feed externo que não existe em nenhum dos dois repositórios. Falta saber se esse endereço existe |
| — | chaves legadas do Supabase (prazo fim de 2026) | rastreado no tracker **privado** da lane `pmigo-plataforma`. **Não abrir issue pública** sem decisão do dono |
| #588 | 3 registros de lições desta rodada | feito |
| — | `MEMORY.md` no teto, 1 linha cortada no carregamento | continua pendente de poda |

## 8. As lições, e todas são sobre onde a prova NÃO chega

1. **Prova por mutação mede o corpo no invólucro em que ela roda.** Provei o classificador nos três
   estados e ele caiu, porque o ponto cego tem o tamanho exato da diferença entre o invólucro do
   teste e o de produção. Isso é auditável **antes** do incidente: pergunte em que os dois diferem.
2. **O status do caller não decide em nenhuma das duas direções.** Verde não prova trabalho feito
   (Comms: 29 verdes sem chamar a EF); vermelho não prova ausência de entrega (o `curl` desistiu e
   a EF entregou 69 carimbos). Quem decide é o efeito, contado por janela no destino.
3. **O que escorrega não é o número, é a frase em volta dele.** Na revisão cruzada com a lane
   `pmigo-plataforma`, quatro afirmações caíram, duas de cada lado, e **nenhuma era erro de
   medição** — todas eram erro de enunciado sobre o que a medição provava.

---

## 9. Adendo: o que só apareceu ao responder as perguntas do dono

> Carimbado 19/09 ~08h40 UTC, depois do merge das seções 1 a 8. **Re-meça antes de decidir.**

Quatro achados que não existiam quando este documento foi escrito, porque nasceram das perguntas
que vieram depois: "qual a recomendação", "vou perder estatística de comunicação" e "o cron do
Credly foi corrigido".

### 9.1 A estatística de comunicação NÃO está em risco pelo que mexemos, mas há prazo

Medido por canal, em `comms_metrics_daily`:

| canal | data mais recente | atraso |
|---|---|---|
| instagram, linkedin, youtube | 2026-09-19 | **0 dias** |
| newsletter | 2026-03-08 | 195 dias, **1 linha na vida** |

Quem entrega é o `pg_cron` **jobid 21**, diário 06:00 UTC, **30 de 30 verdes em 30 dias**. O
workflow do GitHub nunca gravou linha: **zero** registros com `triggered_by=github_actions`.

⚠️ **Mas há um prazo real, e ele não tem relação com a #2370** (ver **#2378**): o acesso a dados
do **Instagram expira em 2026-09-26** e o canal **não tem refresh token**, logo não renova
sozinho. O LinkedIn expira em 2026-10-27 e tem refresh token.

**Eu apontei o risco errado primeiro.** Disse "o token do LinkedIn em 38 dias é o risco real"
olhando só `token_expires_at`. A coluna que continha o prazo mais próximo era outra,
`data_access_expires_at`, e só apareceu quando pedi a data absoluta em vez do número de dias.
⇒ **Pedir a data absoluta não é só higiene de registro: foi o que trocou qual canal era o urgente.**

### 9.2 O detector existe e funciona; o que falta é quem o acione

Verifiquei em vez de supor, e a suposição estava errada: `_comms_token_expiry_scan` **vigia as
duas colunas**. Ele já criou dois avisos de Instagram (18/09 e 19/09), os dois com
`acknowledged = false`.

E há precedente no mesmo `comms_token_alerts`: em agosto o token do LinkedIn expirou e ficou
**4 dias** com "Métricas não estão sendo atualizadas" entre o aviso de véspera e a resolução.
⇒ O gargalo não é detecção, é que **o alerta mora numa tela que alguém precisa visitar**.

### 9.3 O `pg_cron` do Credly nunca esteve quebrado

Vale desconfundir, porque a #2370 misturava as duas coisas:

- `pg_cron` **jobid 14**: **7 de 7 sucessos em 30 dias**, última em 16/09 03:00. Sempre entregou.
- O **workflow do GitHub**: esse sim estava em HTTP 504 com entrega zero, e foi o que as PRs
  #2375 e #2376 consertaram.

### 9.4 Consequência de consertar em vez de remover

O Credly agora tem **dois caminhos vivos**: o `pg_cron` a cada 5 dias e o workflow toda segunda
às 08:00. A operação é idempotente, então não corrompe, mas é trabalho em dobro contra a API do
Credly. Se for reduzir a um, o candidato a sair é o workflow, porque o cron é o que tem histórico.

### 9.5 Recomendação revista sobre o passo 5

**Não arquivar agora.** Quando a pergunta foi feita, arquivar era a forma de fechar a escrita.
Já não é: desativar os 4 syncs fechou, e os workflows que seguem ativos lá (`CI Validate`,
`CodeQL`) **não têm `schedule:`** (medido), então não disparam sem push, e não há push há 180 dias.

O que sobra de arquivar é impedir reativação acidental, ao custo de congelar 33 issues e 5 PRs.
Mais barato e com o mesmo efeito: **apagar os 4 secrets de lá** (todos de 2026-03-08; o de
knowledge já foi rotacionado e está morto), e decidir sobre as 33 issues antes de arquivar.
Nenhuma delas foi lida.

### 9.6 Recomendação firme sobre `Comms Metrics Sync` deste repo

**Remover, ou ao menos tirar o `schedule:`.** Consertar exigiria inventar um feed externo que não
existe em nenhum dos dois repositórios, para duplicar o que o `pg_cron` jobid 21 faz há 30 dias
sem falhar. Enquanto isso, ele produz um verde por dia afirmando sucesso sem trabalho, e esse
verde entra na superfície sobre a qual o audit semanal de bypass raciocina.
