# Documentacao oficial dos ultimos 45 dias, e a rota MCP medida

**Janela:** 2026-07-26 a 2026-09-09. **Carimbado:** 09/09/2026.
**Metodo:** changelog oficial de cada provedor quando existe, mais medicao no banco desta
plataforma para a parte de latencia. Onde so consegui fonte secundaria, esta dito na secao.

Este documento responde a dois pedidos que estavam adiados: (1) o que ha de relevante em
seguranca, oportunidade e pivotada na documentacao dos oito provedores; (2) onde estao as
oportunidades de latencia e confiabilidade na rota MCP, que com voz vira diferencial competitivo.

---

## Sumario: o que exige acao, por urgencia

| Quando | O que | Onde |
| --- | --- | --- |
| ja vigente | A revisao vigente da spec MCP passou a ser `2026-07-28`, e o SDK 1.30.0 ainda declara `2025-11-25` | Parte A.9 e B.3 |
| ja vigente | GitHub passou a poder **bloquear merge de PR com segredo exposto** | Parte A.6 |
| ja vigente | `@modelcontextprotocol/sdk` sem versao nova desde a 1.30.0, e ela nao implementa a spec vigente | Parte B.3 |
| medido | A rota MCP esta **saudavel hoje**: p50 1003 ms, p95 2048 ms nos ultimos 14 dias | Parte B.1 |
| medido | O `execution_ms` **nao mede** o que o usuario de voz espera | Parte B.2 |
| sem exposicao | As duas deprecacoes da Supabase **nao alcancam** este repo (medido) | Parte A.7 |

---

# Parte A: os oito provedores

## A.1 Anthropic

Fonte: release notes oficiais da API.

**Seguranca e governanca**

- **08/07** Expiracao de chave de API configuravel na criacao, com aviso por e-mail 7 dias antes
  e campo `expires_at` na Admin API. As chaves ja existentes nao foram afetadas.
- **05/08** **Inference Hooks** (beta, Claude Enterprise): cada prompt governado fica retido
  aguardando veredito allow/deny de um servidor de seguranca da organizacao, com requisicao
  assinada e negativa registrada no Activity Feed. Vale para claude.ai, Cowork e Claude Code.
- **11/08** e **03/08** Compliance API passou a devolver transcricao de sessoes Cowork e Claude
  Code, remotas e locais, sob escopo `read:compliance_user_data`.
- **26/08** Chaves pessoais e de conta de servico no Console, que param de funcionar quando a
  conta vinculada sai da organizacao.

**Retiradas e migracoes**

- **05/08** `claude-opus-4-1-20250805` **retirado**.
- **17/08** Workbench legado e as tres APIs experimentais de prompt (`generate_prompt`,
  `improve_prompt`, `templatize_prompt`) retiradas.
- **20/08** **SDK Python v1.0**, com quebras: sai a Text Completions API, saem `temperature`,
  `top_p` e `top_k` dos metodos de Messages, e `AnthropicBedrock` passa a exigir regiao AWS
  explicita.
- **19/08** Saem de beta: Files API, Agent Skills API, Admin API user management, e a ferramenta
  de computer use vira `computer_toolset_20260801`. Cada uma com guia de migracao.

**Modelos**

- **24/07** **Claude Opus 5**, 1M de contexto, thinking ligado por padrao, mesmo preco do 4.8.
  Quebra: desligar thinking so e permitido em effort `high` ou abaixo.
- **01/09** **Fable 5.1 e Mythos 5.1**. O numero que importa aqui e **leitura de cache a
  US$ 0,25 por MTok**, que e 0,025x o preco de entrada, contra 0,1x nos demais modelos.
  Restricao nova: `tool_choice` do tipo `any` e `tool` devolvem 400.

**O que isso muda aqui**

O `CLAUDE.md` deste projeto ainda diz `Claude Opus 4.8 (claude-opus-4-8), released 2026-05-28`
como o modelo da plataforma. Ha duas geracoes desde entao. Nao e urgente, mas e drift de
documento normativo, exatamente a classe que a licao "guard de codigo verde deixa o doc normativo
apodrecer" nomeia.

## A.2 OpenAI

Fonte: changelog oficial da plataforma.

- **29/08** **mTLS e federacao de identidade de carga de trabalho X.509 em GA**, configuraveis
  no console com controle de acesso por papel. E o item de seguranca mais relevante do periodo
  entre os provedores de modelo.
- **26/08** **Assistants API desligada por completo**, com migracao para Responses e
  Conversations.
- **26/08** Quatro modelos de transcricao marcados para desligar em **26/02/2027**: `whisper-1`,
  `gpt-4o-transcribe`, `gpt-4o-mini-transcribe` e `gpt-4o-transcribe-diarize`.
- **02/09** Diferenciacao de erro: `429` com `slow_down` para pico de trafego, e `503` com
  `server_is_overloaded` para sobrecarga de modelo. Dois sintomas que antes se confundiam.
- **03/09** **GPT-6 Astra**, mais chamada assincrona de ferramenta, direcionamento no meio do
  turno e ajuste dinamico de esforco de raciocinio na Responses API.
- **08/09** **Prompt Cache Diagnostics** na Responses API.
- **21/08** Escolha de processamento regional por requisicao, via dominio prefixado.
- **01/09** IPv6 em `api.openai.com`.

**O que isso muda aqui**

O contexto que o dono deu para a pesquisa foi o ChatGPT interagindo por voz com o MCP. Os itens
de 03/09 (chamada assincrona de ferramenta e direcionamento no meio do turno) sao exatamente o
mecanismo que torna tolerável uma ferramenta lenta: o cliente deixa de ficar bloqueado. Isso
**nao dispensa** o trabalho de latencia do lado do servidor, mas muda quais chamadas doem.

## A.3 Google

Fonte: changelog oficial da Gemini API. As release notes de Vertex AI que consultei nao cobriam
a janela, entao esta secao vale para a Gemini API.

- **26/08** GA de `gemini-3.5-transcribe` e `gemini-3.5-transcribe-live`, este por WebSocket com
  eventos interinos e finalizados, 85+ idiomas e diarizacao.
- **27/08** GA do `gemini-omni-1.1-flash`. O endpoint `gemini-omni-flash-preview`
  **sera depreciado em 30/09/2026**.
- **01/09** Compreensao agentica de video: o modelo navega a linha do tempo pedindo transcricao,
  quadros ou trilha sob demanda, com reducao declarada de ate 88% de tokens em conteudo longo.
- **02/09** GA do `gemini-3.8-flash`.
- **03/09** `lyria-3.5` em preview publico.

Nenhuma mudanca de MCP, cache, deprecacao de auth ou seguranca documentada na janela.

**O que isso muda aqui**

A plataforma tem uma issue aberta de legendas (`#2208`: 113 de 122 videos sem legenda, com cota
da API do YouTube limitando o backfill a 25 por dia). O `gemini-3.5-transcribe` com diarizacao e
uma rota alternativa que **nao passa pela cota do YouTube**, porque transcreve o arquivo em vez
de pedir a legenda ao YouTube. Vale avaliar, nao vale adotar sem medir custo.

## A.4 xAI

Fonte: changelog do Grok Build mais agregadores. **Confianca media**: nao consegui abrir um
changelog de API oficial navegavel, o `docs.x.ai/docs/changelog` devolveu 404.

- **12/08** **Grok 4.6**, id `grok-4.6`, contexto de 500 mil tokens.
- Na janela, o Grok Build registra **partida de MCP mais rapida** e **retry de conexao MCP que
  falha transitoriamente**, em vez de deixar o servidor indisponivel.

**O que isso muda aqui**

O segundo item e a confirmacao, vinda de outro fornecedor, de que **a partida do MCP e um
gargalo reconhecido no mercado**, e de que retry de falha transitoria e comportamento esperado do
cliente. Reforca a Parte B.

## A.5 Meta

**Confianca baixa, e digo isso explicitamente.** O blog oficial da Meta AI nao trouxe, na janela,
nenhum anuncio de modelo Llama, licenca, ferramenta de agente ou seguranca. O que aparece sobre
Llama 4 e licenciamento em agosto vem de **fontes secundarias e mutuamente inconsistentes**, e
por isso nao registro numero nem data como fato aqui.

Se este provedor importar para alguma decisao, e preciso ir a fonte primaria antes.

## A.6 GitHub

Fonte: changelog oficial.

- **09/09** **Bloqueio de merge de PR com segredo exposto.** Esta e a mais relevante para este
  repo, que teve incidente de PII em repo publico em 08/08 e cujo hook de pre-commit e uma
  varredura de segredo, nao um portao de build.
- **09/09** Autofix agentico para achados de qualidade de codigo.
- **08/09** Acesso automatico do Dependabot a registries hospedados no GitHub.
- **03/09** **CodeQL 2.26.4**, com deteccao melhorada de seguranca em workflows de Actions.
- **03/09** Multiplas configuracoes de trusted publishing para npm.
- **03/09** A chave de assinatura dos pacotes Linux do GitHub CLI **expirou em 05/09**.

**O que isso muda aqui**

Tres convergencias diretas:

1. O bloqueio de merge por segredo exposto e a rede que o hook local nao pode ser. O hook roda na
   maquina de quem commita; este portao roda no lado do servidor.
2. CodeQL 2.26.4 melhora deteccao em workflows de Actions, e a **`#2197`** e sobre o ratchet do
   CodeQL correr contra a analise que ele le. Subir a versao muda o denominador do ratchet, entao
   as duas coisas precisam ser pensadas juntas, ou o ratchet reprova por motivo novo.
3. A chave do GitHub CLI expirou em 05/09. Se alguma imagem de CI instala o `gh` por apt, isso
   quebra silenciosamente.

## A.7 Supabase

Fonte: changelog oficial.

- **23/07** O endpoint `logs.all` da Management API **sera removido em 23/09/2026**, com migracao
  para o endpoint `logs`, que so aceita SQL do ClickHouse.
- **22/07** Pinagem explicita de versao em `CREATE`/`ALTER EXTENSION` **depreciada, e ignorada
  com aviso desde 05/08/2026**.
- **17/07** Em self-hosted, o Envoy substitui o Kong como gateway padrao, com rollout na semana
  de 09/08.
- **30/07** Corrigido: credenciais velhas sobrevivendo a um restore fisico.
- **29/07** Corrigido: panico na coleta de metricas que podia derrubar metricas.
- **12/08** Corrigido: backup diario ocasionalmente pulado por timeout de agendamento, agora com
  retry.
- **21/08** Read replicas mudaram de lugar no painel, sem mudanca de API.
- **14/07** O schema `realtime` passou a bloquear qualquer modificacao de objeto.

**Medido contra este repo, e o resultado e tranquilizador**

```
grep -rn "logs\.all" (ts, mjs, js, sh, yml, yaml, json, fora de node_modules)  ->  0 ocorrencias
grep -rniE "(CREATE|ALTER) EXTENSION[^;]*VERSION" supabase/migrations/         ->  0 ocorrencias
```

Nenhuma das duas deprecacoes alcanca esta plataforma. O prazo de 23/09 **nao e um prazo nosso**.
Registro o controle porque "nao encontrado" calmo e um formato ruim de resultado: as duas buscas
foram feitas com o padrao amplo, e a segunda cobre o diretorio inteiro de migrations.

O item que **sim** merece atencao e o backup pulado por timeout (12/08). Foi corrigido do lado
deles, mas nomeia uma classe: falha silenciosa de agendamento em rotina que ninguem olha quando
da certo.

## A.8 Cloudflare

Fonte: changelog oficial do Workers.

- **28/08** V8 atualizado para 15.3.
- **20/08** Limite de concorrencia de Durable Object Dynamic Worker subiu **de 4 para 10**.
- **18/08** V8 atualizado para 15.2.

Sem quebra, sem aviso de seguranca e sem mudanca de wrangler na janela.

**O que isso muda aqui**

Nada exige acao. O Worker principal roda Astro SSR e nao usa Durable Objects para isso, entao o
aumento de concorrencia nao muda o caminho quente.

## A.9 MCP, a spec (nao e provedor, mas e o que mais muda aqui)

**A revisao vigente da spec passou a ser `2026-07-28`**, dentro da janela, e ela e a mudanca mais
consequente do periodo inteiro para esta plataforma. As mudancas maiores:

1. **O handshake `initialize`/`notifications/initialized` deixou de existir.** O protocolo virou
   sem estado: cada requisicao carrega a versao e as capacidades do cliente em `_meta`.
2. **Sessoes de protocolo e o cabecalho `Mcp-Session-Id` foram removidos** do transporte
   Streamable HTTP. Quem precisa de estado entre chamadas usa handle explicito, emitido pelo
   servidor e passado como argumento comum de ferramenta.
3. **`server/discover` passa a ser obrigatorio**, devolvendo versoes suportadas, capacidades e
   identidade **numa unica requisicao**.
4. **`CacheableResult`**: `tools/list`, `prompts/list`, `resources/list`, `resources/read` e
   `resources/templates/list` passam a exigir `ttlMs` e `cacheScope`, para o cliente cachear em
   vez de repesquisar.
5. **Ordem deterministica em `tools/list`** e recomendada, para melhorar a taxa de acerto do
   cache de prompt do cliente.
6. O GET de SSE e `resources/subscribe` viram `subscriptions/listen`, um unico stream POST longo.
7. **Resumabilidade de stream SSE foi removida** (`Last-Event-ID` e ids de evento): stream que
   quebra perde a requisicao em voo, e o cliente **precisa** reemiti-la com id novo.
8. Todo resultado passa a carregar `resultType`, e o padrao Multi Round-Trip Requests substitui as
   requisicoes iniciadas pelo servidor.
9. Propagacao de contexto de trace do OpenTelemetry documentada em `_meta`.

**Seguranca, na mesma revisao**

- Servidores de autorizacao **devem** incluir `iss` na resposta (RFC 9207), e o cliente **deve**
  valida-lo contra o emissor registrado antes de resgatar o code.
- Credenciais de cliente sao **vinculadas ao emissor**: nao podem ser reusadas com outro
  servidor de autorizacao, e exigem novo registro quando ele muda.
- Cliente precisa declarar `application_type` no Dynamic Client Registration, para evitar
  conflito de redirect URI do OpenID Connect.
- **O Dynamic Client Registration (RFC 7591) foi depreciado** em favor de Client ID Metadata
  Documents.

**Depreciados:** Roots, Sampling e Logging; o transporte HTTP+SSE; e os valores `thisServer` e
`allServers` de `includeContext`.

---

# Parte B: a rota MCP desta plataforma, medida

Tudo nesta parte vem de consulta ao banco em 09/09, sobre `mcp_usage_log`.

## B.1 O estado atual e saudavel, e o numero assustador e de um episodio

Janela de 45 dias inteira, 1403 chamadas, nenhuma sem medicao:

| metrica | 45 dias | **ultimos 14 dias** | 45d sem o episodio | o episodio 17-20/08 |
| --- | --- | --- | --- | --- |
| chamadas | 1403 | **404** | 1071 | 332 |
| media | 4117 ms | **1082 ms** | 1109 ms | 13821 ms |
| p50 | 1006 ms | **1003 ms** | 999 ms | 1023 ms |
| p95 | 2970 ms | **2048 ms** | 1998 ms | 94513 ms |
| p99 | 101694 ms | **2970 ms** | 3190 ms | 162549 ms |
| maximo | 175786 ms | **5575 ms** | 21111 ms | 175786 ms |
| falhas | 102 | 27 | 50 | 52 |

O p99 de **101,7 segundos** na janela de 45 dias e real, e seria a manchete errada. Das 50
chamadas acima de 10 s, **48 caem em 17, 18 e 19/08**, mais uma em 20/08 e uma em 25/08. Nao ha
nenhuma desde **25/08**, ou seja, 15 dias limpos.

O detalhe que fecha o diagnostico: **durante o episodio o p50 continuou em 1023 ms**. O evento
nao degradou tudo, criou cauda numa minoria de chamadas. Essa e a assinatura de dependencia
externa expirando por timeout, nao de banco lento nem de plataforma sobrecarregada.

**Concentracao por ferramenta**, dentro dos 45 dias:

| ferramenta | n | media | p50 | acima de 10 s | falhas |
| --- | --- | --- | --- | --- | --- |
| `event_write` | 66 | 43733 ms | 2147 ms | **31** | **30** |
| `event_search` | 55 | 14589 ms | 1062 ms | 9 | 4 |
| `attendance_report` | 13 | 26085 ms | 1396 ms | 4 | 3 |
| `member_search` | 18 | 16143 ms | 1148 ms | 3 | 4 |
| `interview_manage` | 21 | 4414 ms | 668 ms | 2 | 5 |
| `card_write` | 281 | 1340 ms | 1100 ms | 1 | 2 |

`event_write` sozinho responde por 31 das 50 lentas e por 30 falhas em 66 chamadas, quase
metade. E `card_write`, que e a ferramenta mais usada com 281 chamadas, esta saudavel: media
1340 ms contra p50 1100 ms.

**A forma mais cara do defeito**, cruzando sucesso com lentidao:

| | rapida | lenta |
| --- | --- | --- |
| **sucesso** | 1286 chamadas, media 1115 ms | 15 chamadas, media 67640 ms |
| **falha** | 67 chamadas, media 752 ms | **35 chamadas, media 93663 ms** |

As recusas legitimas de dominio sao **rapidas** (67 chamadas, 752 ms de media), que e o
comportamento certo. O problema sao as **35 chamadas que gastam 93,7 segundos para entregar uma
falha**. Numa interacao por voz, isso e um minuto e meio de silencio terminando em "nao deu".

## B.2 O `execution_ms` nao mede o que o usuario de voz espera

O timer comeca **dentro do handler da ferramenta** (`const start = Date.now()` no topo de cada
tool) e fecha em `supabase/functions/nucleo-mcp/index.ts:311`
(`const execMs = startTime ? Date.now() - startTime : null`).

Logo, ele **exclui**: partida fria do isolate do Edge Function, TLS, verificacao do OAuth,
roteamento pelo dominio proprio e o salto de rede ate o cliente.

O p50 de 1003 ms e portanto um **piso**, nao a espera do usuario. Nao existe hoje, nesta
plataforma, nenhum numero que meca de ponta a ponta o que o cliente de voz aguarda. Essa e a
lacuna que precisa ser fechada **antes** de qualquer otimizacao, porque sem ela nao ha como saber
se uma mudanca melhorou o que importa.

Isto e o mesmo padrao que a coluna `instrumented` ja resolveu para o despacho de convite:
separar "nao mediu" de "nao aconteceu".

## B.3 O SDK esta uma revisao de spec atras, e isso e um teto

Medido baixando o pacote:

```
@modelcontextprotocol/sdk@1.30.0 (ultima publicada no npm)
  LATEST_PROTOCOL_VERSION            = '2025-11-25'
  DEFAULT_NEGOTIATED_PROTOCOL_VERSION = '2025-03-26'
  SUPPORTED_PROTOCOL_VERSIONS         = 2025-11-25, 2025-06-18, 2025-03-26, 2024-11-05, 2024-10-07
  server/discover  -> ausente
  cacheScope       -> ausente
```

A `nucleo-mcp` importa exatamente essa versao, pinada
(`supabase/functions/nucleo-mcp/index.ts:194-195`).

**Consequencia honesta: as tres maiores alavancas de latencia da spec vigente nao estao
disponiveis hoje.** Fim do handshake, `server/discover` e `CacheableResult` dependem do SDK
implementar `2026-07-28`, e a 1.30.0 nao implementa. Nao adianta planejar contra elas ainda.

Isso e informacao que **evita trabalho perdido**, e por isso vale mais do que uma lista de
otimizacoes que nao dariam para fazer.

## B.4 O que da para fazer sem esperar o SDK

Em ordem de razao entre valor e risco:

1. **Fechar o buraco de medicao da B.2.** Um timer de ponta a ponta, do inicio da requisicao HTTP
   ate a resposta, gravado ao lado do `execution_ms`. Sem isso, nenhuma das outras muda um numero
   que alguem consiga ver.
2. **Fazer a falha falhar rapido.** As 35 chamadas de 93,7 s eram falhas. Um timeout explicito por
   dependencia externa, bem abaixo do que quer que esteja segurando por 90 s, converte um minuto e
   meio de espera em uma recusa util. `event_write` e o lugar para comecar, com 30 falhas em 66.
3. **Ordenar `tools/list` de forma deterministica.** E recomendacao da spec nova, mas **nao
   depende dela**: e so ordenar. Melhora a taxa de acerto do cache de prompt do cliente, que e
   token e latencia do lado dele.
4. **Olhar o tamanho da superficie.** O fonte registra **341 nomes unicos** de ferramenta em
   12.792 linhas, e apenas **105 ferramentas distintas foram chamadas** nos 45 dias. O cliente ve
   uma fachada menor que isso. Vale medir quanto do payload de `tools/list` e superficie que
   ninguem exerce, porque isso e custo em toda conversa. Nao proponho remover nada antes de medir:
   ferramenta pouco usada nao e ferramenta inutil.
5. **Instrumentar com OpenTelemetry pelo `_meta`**, na convencao que a spec nova documenta. Da
   para adotar a convencao de chave sem adotar a revisao inteira.

## B.5 O que vigiar, e nao mexer agora

- **`@modelcontextprotocol/sdk`** publicar uma versao que declare `2026-07-28`. Quando isso
  acontecer, as tres alavancas da B.3 abrem de uma vez, e a migracao **nao e pequena**: sai o
  handshake, saem as sessoes, sai a resumabilidade de stream, e `resultType` passa a ser
  obrigatorio em todo resultado.
- **A depreciacao do Dynamic Client Registration.** A `#2181` e sobre registro de cliente OAuth
  pendurando para um membro. A spec nova aponta para Client ID Metadata Documents no lugar do
  RFC 7591. Vale olhar as duas juntas quando a `#2181` for trabalhada, em vez de consertar o
  caminho que esta sendo aposentado.
- **Validacao de `iss` (RFC 9207)** no fluxo de autorizacao, que a spec nova passa a exigir do
  cliente e recomendar do servidor.

---

## Onde este documento e fraco, dito de frente

- **Meta**: nao consegui fonte primaria na janela. A secao A.5 nao afirma nada por isso.
- **Google**: as release notes de Vertex AI que abri nao cobriam a janela. A secao A.3 vale para
  a Gemini API.
- **xAI**: o changelog de API oficial devolveu 404; usei o changelog do Grok Build e agregadores.
- **A causa do episodio de 17 a 19/08 nao foi investigada** aqui. Eu mostrei a forma dele
  (bimodal, p50 intacto, concentrado em `event_write`) e nomeei a hipotese mais provavel
  (dependencia externa expirando), mas nao abri log de Edge Function para confirmar. Isso e
  trabalho proprio, e a hipotese **nao deve ser recitada como fato** ate alguem exercer o log.
