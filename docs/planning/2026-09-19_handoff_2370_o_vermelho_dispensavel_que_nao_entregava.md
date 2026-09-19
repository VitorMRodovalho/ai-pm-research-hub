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
