# Arranque 04/09/2026: o que ler, o que re-medir, o que decidir

> **Nada aqui é medição.** Foi carimbado no fim de 03/09 e envelhece sozinho.
> Antes de qualquer decisão, rode os quatro comandos da seção seguinte.

## Primeiro: re-meça (4 comandos, cerca de 15s)

```bash
git fetch --all && git log --oneline -1 origin/main
gh pr list --state open
gh run list --limit 10 --json headSha,conclusion,status,name
gh issue list --state open --limit 30
```

Estado ao encerrar 03/09, para você comparar e **não** para acreditar:
`main 60c13855` · fila 0 PRs · 4 migrations de 03/09 aplicadas e na main · EFs `nucleo-mcp` v268 e
`sync-comms-metrics` v47 · janela de bypass em 2 de 2, sem push direto na sessão.

## A primeira coisa da manhã, e ela tem prazo natural

**A pós-condição da #2153 não foi medida ontem, e o motivo foi cota, não código.** O cron das
06:00 UTC de hoje é o exercício natural, com o teto do LinkedIn renovado. Meça DEPOIS que ele
rodar:

```sql
SELECT count(*) AS linhas,
       count(cached_image_url) AS com_imagem,
       count(*) FILTER (WHERE payload->>'image_urn' IS NOT NULL) AS com_urn,
       max(synced_at) AS ultimo_sync
FROM comms_media_items WHERE channel = 'linkedin';
```

Alvo medido na sondagem: **30 de 50** (16 `media.id`, 9 `multiImage`, 5 `article.thumbnail`; os
três confirmados resolvendo com 200 / AVAILABLE / `downloadUrl`). Era 0 ao encerrar 03/09.

**Se continuar 0, leia o log ANTES de mexer no código.** A ambiguidade a desfazer é entre "429 de
cota outra vez" e "o cache falhou de verdade":

```sql
SELECT context, status, created_at FROM comms_metrics_ingestion_log
WHERE source = 'api_linkedin' ORDER BY created_at DESC LIMIT 3;
```

`context->>'media_items'` igual a 0 significa que o fetcher voltou vazio, e aí a causa está no log
da função (`stats 429` nomeia a cota). Diferente de `media_items` maior que zero com
`cached_image_url` ainda em 0, que aí sim seria falha do cache: download recusado por
`media.licdn.com`, ou upload recusado pelo bucket.

E não gaste cota antes disso: cada sondagem manual consome do mesmo teto que o cron precisa.

## Antes de mergear ou pushar qualquer coisa

**A janela de bypass segue em 2 de 2** (#2157). Ontem não avancei nela: a PR #2161 foi squash sem
`--admin`, e não houve push direto. Mantenha: **tudo por PR, inclusive handoff e planning.**

## O que espera decisão sua (nenhuma tem relógio)

1. **#2159, achado 2:** os dois logs existem e estão vivos, mas não se cruzam. `pii_access_log`
   sabe QUEM leu e o CONTEXTO, `mcp_usage_log` sabe o CANAL e a tool, e nenhum dos dois responde
   "qual credencial, por qual canal, leu PII de quem". Falta propagar uma marca de origem do
   handler do MCP para o `pii_access_log`. O achado 1 foi resolvido ontem.
2. **#2159, achado 3:** 6.830 leituras de PII em `reconcile_initiative_drive_access` com accessor
   nulo. É fluxo automático, então não há pessoa, mas gravar NULL faz o volume sumir de qualquer
   relatório por responsável. Ator sintético nomeado, ou fica nulo?
3. **#2152, decisão 1:** o SELO da tela deve ler o VEP quando ele for mais recente que a
   verificação? Ontem respondi só a decisão 2 (o cron avisa, não grava).
4. **#2152, nota que virou pendência:** as faixas D-30, D-7 e vencida continuam avisando o MEMBRO
   com base na verificação. Se ela estiver atrasada, o membro leva cobrança de renovação estando
   regular. Hoje não acontece (divergência 0), e suprimir mudaria QUEM é notificado, que não foi o
   que se decidiu.
5. **#2153, achado de desenho:** um 429 na API de métricas descarta caption e `image_urn`, que
   vieram da listagem e não dependem dela. Não há perda de dado (linha existente fica intacta), há
   perda de avanço: post novo não ganha linha e o backfill não começa. Vale gravar a linha com o
   que a listagem deu e deixar as métricas nulas?

## Registrado e sem issue própria

- **`fetchWithRetry` sem redação em `verify-credly` e `send-global-onboarding`.** Mesmo
  `throw new Error(\`...: ${url}\`)` que vazava no `sync-comms-metrics`. Hoje não vazam porque as
  URLs delas não levam segredo na query, mas o padrão está armado para o próximo parâmetro.
- **56 handoffs nunca commitados** em `docs/planning/` (contra 123 rastreados). Não é regra de
  ignore, é acúmulo.
- **Candidato a memória, com custo:** a lição de escopo de guard (abaixo) ainda não está no
  `MEMORY.md`. O índice tem teto de 200 linhas e quem acrescenta arquiva outra, então é decisão,
  não automatismo.

## Prazos vivos

- **08/09** publicação do webinar (lane `.wt-campanha`)
- **10/09** Reunião Geral. É a pauta do pedido que gerou a #2158, e ela está reservável: posição 1
  da janela, 20 minutos ocupados, 70 livres.
- **11/09** aprovação do TAP do Grupo de Estudos CPMAI (lane `.wt-cpmai`)

**Atenção para o dia 10:** a ação `reserve` existe no servidor, mas o catálogo de tools é cacheado
no CLIENTE na conexão. Quem já estava conectado ao MCP **precisa reconectar** para enxergar o verbo
novo. Tool deployada não é tool alcançável.

## A regra da sessão, que vale para a próxima

> **Presença em algum lugar não é presença no lugar certo.**

Três guards escritos ontem passaram por acidente, e nos três a injeção de defeito foi quem revelou:
um casou a palavra `manage_event` no próprio comentário que explicava por que ela não é usada;
outro achou `startsWith('urn:li:image:')` no resolver enquanto a checagem da captura tinha sumido;
o terceiro exigia o começo de uma expressão sem proibir nada depois dela.

É o corolário de escopo da regra de 02/09 ("presença não é efeito"). O prático:

- ancore a busca no SÍTIO sob teste, não no arquivo inteiro;
- **conte** as ocorrências em vez de conferir presença;
- ancore o FIM da expressão, não só o começo;
- e, ao terminar um guard, injete o defeito que ele deveria pegar e exija que ele reprove.
