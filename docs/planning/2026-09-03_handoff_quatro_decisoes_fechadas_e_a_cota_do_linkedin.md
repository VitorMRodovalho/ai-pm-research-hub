# Handoff 03/09/2026: as quatro decisões fechadas, e o que a cota do LinkedIn impediu de provar

> Números aqui foram medidos em 03/09. Envelhecem sozinhos. O arranque de 04/09 manda re-medir
> antes de decidir, e isso vale para tudo neste arquivo.

## Estado ao encerrar

`main 00e98393` (PR #2161, squash, CI 13/13, sem `--admin`) · fila com 0 PRs · 0 pushes diretos
hoje, então a janela de bypass segue em 2 de 2 (#2157) e eu não avancei nela.

Na main, tudo verde, incluindo `Deploy to Cloudflare Workers`, `CI Validate`, `Schema Invariants` e
o `Ratchet da linha de base do CodeQL (#1966)`.

Edge Functions deployadas e conferidas no CORPO, não pelo exit code:

| EF | versão | marcas do fix | controles negativos |
|---|---|---|---|
| `nucleo-mcp` | v268 ACTIVE | 6 de 6 | 3 em zero |
| `sync-comms-metrics` | v47 ACTIVE | 7 de 7 | 3 em zero |

Quatro migrations aplicadas e alinhadas em nome com as tracking rows: `20260903015614`,
`20260903015844`, `20260903022128`, `20260903022949`.

## As quatro decisões, e as três que mudaram de forma ao serem medidas

**#2158 (FECHADA).** As duas perguntas que travavam a implementação já estavam respondidas no
banco, e medi-las foi o trabalho. A RPC `reserve_agenda_block` não pede `manage_event`: pede
capacidade própria, exercida por 80 de 100 membros ativos contra 14 de `manage_event` (controle
negativo com capacidade inexistente deu 0). E reserva é sempre self-scoped, com terceiro se
expressando por `guest_name`, caminho já usado em 8 dos 22 blocos confirmados.

**#2159 (achado 1 resolvido).** A coluna `auth_user_id` não estava vazia por acidente de esquema:
a EF passa `p_auth_user_id: null` LITERAL em 1791 pontos de chamada, e o handler não tem o `sub`
em escopo. Preenchida DENTRO da RPC com `COALESCE(p_auth_user_id, auth.uid())`, o que cobre os
1791 sem tocar em nenhum.

**#2152 (decisão 2 respondida).** O `vep_sync` NÃO passa a gravar sozinho, porque as RPCs de
escrita exigem `filiacao_director`/`manage_member` e vedam auto-verificação: um cron gravaria
verificação sem verificador. O radar das 09:00 UTC ganhou a faixa (C), que compara e AVISA. Ela
dispara em 0 hoje de propósito (69 pares, 0 divergentes, 0 em rota de divergir em 90 dias). É
tripwire para a próxima leva de renovações, não remendo.

**#2153 (ABERTA, e o motivo importa).** A sondagem que a issue pedia foi feita e deu resultado: a
listagem `/rest/posts?q=author` devolve a referência de mídia em três formas, e `/rest/images`
resolve as três para uma URL que EXPIRA (`downloadUrlExpiresAt`), o que confirma que o caminho
certo é cachear e não guardar a URL.

| forma | posts | resolve? |
|---|---:|---|
| `content.media.id` = imagem | 16 | sim, 200 / AVAILABLE |
| `content.multiImage.images[0].id` | 9 | sim, 200 / AVAILABLE |
| `content.article.thumbnail` | 5 | sim, 200 / AVAILABLE |
| vídeo, documento, link externo, sem content | 20 | não |

Alvo: 30 de 50. O teste NÃO exige 50 de propósito, porque exigir cobertura total transformaria um
limite da fonte em falha do código.

## O que impediu a pós-condição, e a culpa é minha

O sync manual das 12:06 registrou `success` com `media_items: 0`. O log nomeia:

```
LinkedIn media: 0 of 50 post(s) had statistics (discovery=author_listing)
stats 429 ... "DAY limit for calls to this resource is reached"
```

A listagem FUNCIONOU e trouxe os 50 posts, então a captura do URN rodou. Morreu a chamada de
estatística por post, por cota diária. Como o laço faz `if (!statResp.ok) continue`, nenhum item
entra em `items`, não há upsert, e o URN capturado é descartado antes de virar linha.

A cota foi consumida pelos próprios runs de verificação de hoje: 01:38 (pós-condição da legenda do
#2142), 06:00 (cron) e 12:06 (este), somando cerca de 150 chamadas ao mesmo recurso, mais 5
sondagens diretas. **Medir gastou o orçamento de que a medição seguinte precisava.**

Não re-disparei: gastaria cota sem chance. O exercício natural é o cron das 06:00 UTC de 04/09.

**O que NÃO acontece num dia de cota estourada, e eu escrevi errado antes de corrigir:** as linhas
existentes ficam intactas. Conferido: depois do run de 12:06 com zero itens, as 50 linhas seguiam
com 50 legendas e `synced_at` inalterado em 06:00:45. Não há perda de dado, há perda de avanço.

## Três correções de rota DENTRO da própria sessão

**1. Um `REVOKE` meu calaria a auditoria que a issue queria criar.** Revoguei `anon` em
`log_mcp_usage`; o ratchet do #965 reprovou, e a entrada acusada carregava uma nota de #1551 que eu
não tinha lido. `createAuthenticatedClient(token?)` usa a anon-key e só acrescenta `Authorization`
se houver token, então o caminho que registra "Not authenticated" (388 chamadas de
`logUsage(sb, null, ...)`) roda como `anon`, e `logUsage` engole a exceção. O revoke não daria
erro: apagaria em silêncio a classe de evento mais interessante para auditoria de acesso.

Desfeito na `20260903022949`. O `COALESCE` ficou, e é justamente a "body derivation, not an ACL
change" que a própria nota de #1551 pedia. Efeito colateral bom: a varredura do #965 exclui função
cujo corpo consulte `auth.uid()`, então `log_mcp_usage` saiu dela POR DERIVAÇÃO, e a allowlist
catracou para baixo com `anon` mantendo EXECUTE.

**2. `to_date` cru dentro do cron.** `to_date('No Memberships','DD Mon YYYY')` estoura (22007) e
derrubaria a função INTEIRA, D-7 urgente incluído, que nada tem a ver com VEP. Guardado por formato
na `20260903022128`, e o que não parseia virou número (`expiry_unparseable`) em vez de silêncio.
Acervo limpo hoje: 0 de 121 fora do formato, então isso remove um modo de falha, não conserta
defeito ativo.

**3. CodeQL, dois alertas de naturezas opostas.** Um era pré-existente (#142, aberto 02/09, na
baseline do #1966) reatribuído à PR por deslocamento de linha; consertei mesmo assim, com redação
por ESTRUTURA (origem + path, descarta a query inteira) em vez de filtro por nome de parâmetro, o
que fecha os quatro `clear-text-logging`. O outro era MEU: `new RegExp` montada de variável com
escape parcial, no teste novo. O ratchet do #1966 passou na main depois.

## A lição de método desta sessão

Três guards que eu mesmo escrevi passaram por ACIDENTE, e nos três casos quem revelou foi a
injeção de defeito, não a leitura:

| onde | o que o guard media | o que deveria medir |
|---|---|---|
| #2158 | a palavra `manage_event` no ramo | o portão (`canV4`, `permission:`) |
| #2153 | `startsWith('urn:li:image:')` no arquivo inteiro | a checagem NA CAPTURA, contada |
| #2161 | o prefixo da expressão de redação | a expressão inteira, ancorada no fim |

> **Presença em algum lugar não é presença no lugar certo.**

É o corolário direto da regra de 02/09 ("presença não é efeito"), aplicado ao ESCOPO da busca: um
guard que varre o arquivo todo fica verde quando o marcador existe em qualquer outro sítio que não
o que está sob teste. Ancore no sítio, e conte em vez de conferir presença.

Todo guard novo desta sessão foi provado por injeção de defeito, com o arquivo restaurado
byte-idêntico depois.

## Um fato operacional que não estava previsto

**Tool deployada não é tool alcançável para cliente já conectado.** O `reserve` está no servidor
(v268 verificado no corpo), mas o catálogo de tools é cacheado no CLIENTE no momento da conexão. A
sessão MCP desta própria conversa seguiu com `enum: ["list","confirm","no_show"]` depois do deploy.
Para o pedido que originou a #2158 (um líder de tribo reservando 10 minutos na Geral de 10/09), o
agente dele precisa RECONECTAR o MCP.

A Geral de 10/09 está reservável: posição 1 da janela das duas próximas, `time_start` configurado,
20 minutos ocupados e 70 livres. Conferido por SQL e depois pela própria tool, com os dois lados
batendo.
