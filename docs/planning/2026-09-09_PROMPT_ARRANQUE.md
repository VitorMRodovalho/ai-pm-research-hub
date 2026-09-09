# Arranque 09/09/2026: reemitir os convites, e fechar o webinar de ontem

> **Nada aqui é medição.** Carimbado em 09/09 às 10:55 BRT, no fim de uma sessão que estourou
> contexto. Re-meça antes de decidir.

```bash
git fetch --all && git log --oneline -1 origin/main
gh pr list --state open
gh issue list --state open --limit 30
```

Estado ao encerrar 08/09, para **comparar**: `main 09b148ae` · fila 0 PRs · 5 PRs no dia, todas por
squash com CI verde, **nenhuma com `--admin`**.

## Primeiro: os 3 convites de entrevista, que venceram às 11:00 de hoje

Três candidaturas em `interview_pending`, todas `researcher`, **0 reservas**:

```
e998f6ec-1b76-4143-894a-9069a3e09d33   abriu o link 3x
15ebca9c-a0fa-4a0f-9d06-8bccfaf2cbba   nunca abriu
36b3cc78-2ff1-4fad-8c60-35a863adc45f   nunca abriu
```

**A decisão do dono (09/09) foi REEMITIR.** Não foi feito na sessão anterior, e o motivo importa:

⚠️ **`issue_interview_booking_token` NÃO envia e-mail.** Medido: ela chama
`_issue_interview_booking_token_core`, que emite o token e grava o log, e o core **não tem** nenhum
`net.http_post` nem caminho de notificação. Reemitir por ela renova o token em SILÊNCIO, e dois dos
três nunca abriram convite nenhum: um token que ninguém sabe que existe não muda nada.

Quem envia é **`_dispatch_interview_booking_link`** (`_`-prefixed, ACL só `postgres` +
`service_role`). Antes de chamá-la, resolva duas coisas:

1. **O gate.** O core pode recusar com `GATE_NO_PEER_REVIEW` (`P0002`). É exatamente o que a
   `#2171` investigou em 03/09: quatro tentativas barradas por esse gate. Meça se os três passam
   ANTES de disparar, ou o despacho falha e a recusa vira linha de auditoria sem convite.
2. **Qual caminho é o legítimo.** Ver se a UI de admin tem botão de reenvio que já orquestra
   token + e-mail; se tiver, use-o em vez de chamar a função interna à mão.

**O cenário melhorou desde ontem:** as quatro agendas estão abertas (GP 23 dias, institucional 19,
Fabricio 13, Fernando 13) e não há bloqueio de roteamento ativo. O rodízio LRD elegerá o Fabricio
(posição 1), e a linha nova já gravará `agenda_days_open`, que será a **primeira** linha com esse
dado (`despachos_com_estado_de_agenda` estava em 0).

## Segundo: o webinar de ontem não foi fechado

O painel da Tribo 11 ocorreu em 08/09 às 20h. Medido em 09/09:

```
status: planned          (não mudou)
youtube_url: null        (sem gravação)
event_id: null           (sem evento vinculado)
registros de presença: 0
```

O dono pediu: **levantar o que o fechamento exige neste projeto e mostrar a lista, sem alterar
nada.** Comece por `webinar_manage` no MCP e pelas RPCs de ciclo de vida
(`webinar_lifecycle_events`), e veja como os webinares anteriores foram fechados, em vez de supor.

## O que já está entregue e NÃO precisa refazer

- **`#2188` fase 1 mergeada e em produção.** A sonda roda (`probed=4 cegas=0`), o cron lê o segredo
  do Vault 4x ao dia, e o despacho grava `agenda_days_open`/`agenda_probed_at`.
- **Os dois segredos configurados e pareados** (Worker `AGENDA_PROBE_INTERNAL_SECRET` + Vault
  `agenda_probe_internal_secret`), conferidos por sha256 idêntico.
- **O import do VEP de ontem foi reprocessado**, resume `311824` recuperado, 0 falhos.

⚠️ **`/tmp/.ag_probe_secret` ficou na máquina** com o valor em claro. Apagar:
`shred -u /tmp/.ag_probe_secret`.

## Fases 2 e seguintes da #2188, quando houver espaço

O rodízio pular agenda comprovadamente vazia (item 1), o despacho falhar de forma visível quando
nenhuma agenda tem horário (item 2) e o alerta quando um avaliador ativo zera (item 4). Os três
leem o dado que a fase 1 começou a produzir, e **não devem ser escritos contra tabela vazia**:
agora ela tem linhas.

## Issues abertas ontem, todas da mesma família

`#2193` (a divulgação de webinar depende de alguém lembrar) · `#2197` (o ratchet do CodeQL corre
contra a análise que ele lê; a **A3** já resolveu essa classe para o deploy com `workflow_run`) ·
`#2199` (falha de sync de currículo sem leitor nem retry; 6 CVs de março perdidos sem recuperação).

Não consertado e sem issue: **`_trg_event_guest_cert_pdf_autogen` lê um GUC que não existe e não
pode ser criado** nesta plataforma, então o PDF de certificado de convidado de evento externo
(`#1098`) pula em silêncio. Registrado no cabeçalho da migration `20260908193328`.

## Prazos

- **10/09** Reunião Geral. Os **cinco pontos da pauta** seguem parados do lado do PM desde 04/09.
- **11/09** aprovação do TAP do Grupo de Estudos CPMAI (lane `.wt-cpmai`, parada desde 31/08).

## A regra que a sessão de ontem deixou

> **Ler a projeção não é ler a fonte.** Comentário de migration descreve; snapshot de
> acessibilidade deriva; tabela de fila registra um caminho entre vários. Exerça contra o catálogo,
> o DOM, a superfície onde o fato acontece.

E o corolário: **guarde a diferença entre "não sei" e "é zero"**. Uma coluna booleana impediu que
um seletor errado registrasse "quatro agendas fechadas" e esvaziasse o rodízio.

---

# ADENDO, carimbado 09/09 as 12h15 BRT

> O texto acima foi escrito as 10h55 e **envelheceu**. Isto e o que mudou desde entao.
> Continua valendo: re-meca antes de decidir.

## Estado agora

`main 2812f2a3` · fila com **1 PR** (a `#2204`, ver abaixo) · 3 PRs mergeadas depois do arranque
original (`#2200` handoff, `#2201` este arranque, `#2203` setup-lane).

## O item 1 do arranque MUDOU de natureza

Os 3 convites **venceram as 11:00**, como previsto. Mas o motivo de nao terem sido reemitidos nao
foi o relogio, e sim uma medicao que muda o desenho da tarefa:

⚠️ **`issue_interview_booking_token` NAO envia e-mail.** Ela chama
`_issue_interview_booking_token_core`, que emite o token e grava o log, e o core nao tem
`net.http_post` nem notificacao. Reemitir por ela renova o token EM SILENCIO, e dois dos tres
candidatos nunca abriram convite algum. Quem envia e `_dispatch_interview_booking_link`, interna
(ACL so `postgres` + `service_role`) e sujeita a `GATE_NO_PEER_REVIEW` (a mesma da `#2171`).

Antes de reemitir, meca se os tres passam no gate, e prefira o caminho da UI se existir botao de
reenvio que orquestre token mais e-mail.

## O item 2 do arranque esta MEIO FEITO

O webinar de 08/09 foi parcialmente fechado. A lane `ai-pm-research-hub-ff` cuidou do video e a
main aplicou as escritas, na ordem que a `#2205` documenta.

**Feito:**
- `webinars.youtube_url = https://youtu.be/qdHhUUxWIrg`, por UPDATE direto com `RETURNING`
  (NUNCA `upsert_webinar`, ver `#1604`). Conferido: `initiative_id` e `sympla_event_url`
  sobreviveram.
- Evento `ac40ecfc-a8fb-4eb6-bc75-b3533fd2edb5` criado por `link_webinar_event(id, NULL)`, DEPOIS
  do passo anterior, impersonando o GP para a auditoria nao nascer sem ator. Conferido: a gravacao
  foi copiada para o evento, `initiative_id` presente, `audience_level='tribe'`.

**Falta, e nesta ordem:**
1. **presenca dos 23 membros** (de 58 presentes; os outros 35 sao publico externo). A lane mediu
   por `md5(lower(email))` e ficou de mandar os `member_id`. Sem os uuid nao da para montar o
   INSERT.
2. `status = 'completed'` (hoje ainda `planned`).
3. card `be0a1980-cd62-458c-88f8-f2fcfb2646f4` (**venceu em 09/09**) e amarrar
   `webinars.board_item_id`, que segue nulo.

⚠️ **A gravacao e publica**, verificado de forma independente pelo feed RSS do canal
(`videos.xml?channel_id=UCIEiHte8f_AVwCXP2wZ7DjQ`), e nao pelo oembed, que responde para
`unlisted` tambem e portanto nao prova nada.

## O item 3 do arranque esta FEITO, mas a PR nao mergeou ainda

`#2204` fecha os 8 alertas do Dependabot pela politica `#611` (PR local de higiene). Cinco pacotes
transitivos, todos acima do piso do advisory. **Confira se ela mergeou antes de mexer em
dependencia.**

Duas coisas aprendidas ali, e a segunda quase passou:
- `npm audit fix` subiu `@tiptap/core` SOZINHO e quebrou o build
  (`[MISSING_EXPORT] cancelPositionCheck`). Pacote de monorepo nao sobe sozinho.
- O `npm outdated` revelou que `extension-image` e `extension-placeholder` ainda estavam em 3.23.1
  contra core 3.31.3. Passava no build por nao importarem o simbolo removido, e quebraria em
  RUNTIME. Os seis `@tiptap/*` estao agora em 3.31.3.

⚠️ **Fica fora, e e decisao:** `extract-zip <- @puppeteer/browsers <- @cloudflare/puppeteer`,
high no `npm audit` e AUSENTE no Dependabot (bases de advisory diferentes). O unico fix e
downgrade major do `@cloudflare/puppeteer`, que quebraria o `cert-pdf-render` e a sonda da `#2188`.
O `extract-zip` so roda no download do Chrome em ambiente local/CI, nunca no runtime do Worker.

## Auditoria de versoes, ja medida, para nao refazer

**Em dia com o ultimo estavel:** Astro `7.3.2`, wrangler `4.130.0`, `@astrojs/cloudflare` `14.3.1`,
MCP SDK `1.30.0`. Postgres `17.6.1.084`, Node `v24.19.0`.

**27 pacotes npm atras**, sendo 24 minor/patch e **3 major que sao decisao**:

| pacote | em uso | ultimo | nota |
| --- | --- | --- | --- |
| `typescript` | 6.0.3 | **7.0.2** | compilador reescrito em Go; ganho no gate de build |
| `@tanstack/react-table` | 8.21.3 | 9.2.4 | mexe em componente de UI |
| `globals` | 16.5.0 | 17.12.0 | so lint |

**Dois desalinhamentos que valem nome:**
- `@supabase/supabase-js` **11 minors atras** (2.105.4 contra 2.116.0), e e o cliente que fala com
  producao o tempo todo;
- o **CLI do Supabase e 2.117.0 e o CI pina 2.109.0** no `gen-types-drift`. Gerar tipos com a
  versao local produz diff diferente do CI, entao **use a pinada**: `npx -y supabase@2.109.0`.
- no MCP (Deno): `zod` pinado em 4.3.6 contra 4.5.4; `hono` 4.12.9.

## O QUE NAO FOI FEITO, e e o pedido de maior valor

O dono pediu, e ficou para esta sessao:

1. **Documentacao oficial dos ultimos 45 dias** de Anthropic, OpenAI, Google, xAI, Meta, GitHub,
   Supabase e Cloudflare: o que ha de relevante em seguranca, oportunidade de melhoria ou pivotada.
2. **Oportunidades de latencia e confiabilidade na rota MCP.** O contexto que o dono deu importa:
   com o ChatGPT interagindo por voz, um MCP rapido vira diferencial competitivo, nao so conforto.

Nao foi feito por falta de contexto na sessao anterior, nao por falta de escopo. Fazer com contexto
esgotado produziria leitura rasa de oito fontes.

## Regra de processo NOVA, estabelecida pelo dono em 09/09

**Qualquer escrita em banco que uma lane precise fazer vai para a main.** A lane prepara, avisa, a
main aplica. Excecao unica, e testavel: se `grep -rl "<tabela>" tests/contracts/` vier **vazio** e
a escrita for o proprio produto da lane, linha a linha, ela pode escrever direto.

Ja gravado em `feedback-merge-to-main-is-main-session-only`.

## Rotina NOVA ao abrir qualquer lane

```bash
scripts/setup-lane.sh ../.wt-<lane> [branch]
```

Ja esta no `CLAUDE.md`, primeira linha do bloco Build & Test. A `.wt-campanha` ja foi preparada por
ele e esta em `lane/webinar-t11-pos-evento`, em dia com a main.

## Issues abertas depois do arranque original

- **`#2202`** `[LL]` worktree de lane nasce sem `.env` e sem `node_modules`, e os tres sintomas sao
  silenciosos (virou o `setup-lane.sh`).
- **`#2205`** o MCP nao tem camada semantica para fechar webinar: 6 escritas cruas, ordem tacita,
  armadilha de perda silenciosa e auditoria sem ator. **Mesma familia da `#2192`.**

## Duas armadilhas que me pegaram, e vao pegar de novo

**Um vigia de merge que afirma sucesso sem verificar.** Montei um laco que esperava
`gh pr checks` ficar sem pendentes e entao mergeava. Ele disse "MERGEADO" com a PR aberta: logo
depois de um push, os checks do commit novo **ainda nao comecaram**, e `gh pr checks` nao lista
quem nao reportou. Pior, eu tinha engolido o erro do `gh pr merge` com `>/dev/null`. **Exija
contagem MINIMA de checks e confira o codigo de saida do merge.**

**O `.env` da arvore principal nao tem tudo.** `SUPABASE_ACCESS_TOKEN` vem do AMBIENTE do shell.
Sem ele o `db:types` faz no-op silencioso com exit 0.

## PEDIDO DO DONO (09/09, 12h): plano de atualizacao de dependencias

**Atualizar os 27 pacotes atrasados, incluindo os minors, e o `zod`. Manter tudo atualizado e com
a documentacao das atualizacoes em dia.** O plano de COMO fazer e para esta sessao definir.

Sugestao de fatiamento, aprendida hoje na `#2204`:

1. **Onda 1, minor/patch em lote** (24 pacotes). Baixo risco, mas rode o gate entre lotes, nao so
   no fim. Cuidado com FAMILIA: `@tiptap/*` (6), `@radix-ui/*` (4) e `playwright`/`@playwright/test`
   sobem JUNTOS ou o build quebra por export ausente.
2. **Onda 2, `zod`** 4.3.6 -> 4.5.4, que vive na EF do MCP (Deno, `npm:zod@`), nao no npm local.
   Exige deploy da EF e smoke do MCP, nao so o gate do repo.
3. **Onda 3, os 3 majors, um por PR**: `typescript` 6->7 (compilador em Go; o mais valioso e o mais
   arriscado), `@tanstack/react-table` 8->9 (UI), `globals` 16->17 (so lint, comece por ele).
4. **`@supabase/supabase-js`** 2.105.4 -> 2.116.0: 11 minors, cliente que fala com producao.
   Merece PR propria com smoke das rotas.

**A licao que justifica o fatiamento:** `npm audit fix` subiu `@tiptap/core` sozinho e o build
morreu com `[MISSING_EXPORT] cancelPositionCheck`. Depois, o `npm outdated` mostrou que duas
extensions do mesmo monorepo ainda estavam sete minors atras, passando no build por nao importarem
o simbolo removido. **Pacote de monorepo nao sobe sozinho, e "o build passou" nao prova que a
familia esta consistente.** Meca a familia inteira com `npm outdated` depois de cada onda.

**Documentacao das atualizacoes:** o dono quer isso em dia. Cada onda deve dizer, na PR, o que
subiu, de onde para onde, e o que foi exercido para provar. As PRs `#2204` e as da `#2188` de
08/09 servem de modelo.

---

# DELTA FINAL, carimbado 09/09 as 13h30 BRT (fim da sessao, antes do clear)

`main f73b7005` · fila com **1 PR: a #2204**, e ela esta VERMELHA.

## O unico item que trava: `browser_guards` na #2204

Os 8 alertas do Dependabot estao corretamente resolvidos. O que trava e um check, e o
**diagnostico completo esta no comentario da propria PR** (`gh pr view 2204 --comments`).

Resumo, para nao reabrir caminho ja andado:

- erro: `[PARSE_ERROR]` do **rolldown** ao escanear `src/components/ErrorBoundary.tsx` no scan de
  dependencias do Vite, seguido de `TypeError: Cannot read properties of null (reading 'useState')`;
- ⚠️ **a hipotese do tiptap CAIU.** Nao e o editor. A cadeia suspeita e **Vite / rolldown / React**,
  e o candidato e `react`/`react-dom` **19.2.6 -> 19.2.8**, que entrou no bolo do `npm audit fix`;
- **nao e flake:** o script ja tenta 2x e falhou nas duas, e o check passou nas #2203 e #2206, que
  nao tocam `package.json`;
- **por que o gate local nao pegou:** `astro build` e `npm test` passam. Quem quebra e o DEV SERVER,
  que o `browser-guards.test.mjs` sobe antes do chromium. Build e dev usam caminhos diferentes;
- reproduzir: `npx playwright install chromium && npm run test:browser:guards`;
- **saida pragmatica:** fatiar. Deixar entrar o que nao mexe em React (`browserslist`, `svgo`,
  `fflate`, `postcss-selector-parser`) fecha **6 dos 8 alertas** de imediato, e isola
  `react`/`react-dom`/`@tiptap/*` numa PR propria.

## O webinar de 08/09 esta FECHADO. Nao refazer.

`status=completed`, gravacao `youtu.be/qdHhUUxWIrg`, evento `ac40ecfc`, **23 presencas todas com
`registered_by`**, card `be0a1980` em `done`, `board_item_id` amarrado, `initiative_id` preservado.

A nota de alcance em `events.notes` foi marcada como **"Registro PROVISORIO ate a #2207"**, porque
a lane abriu a #2207 (modelagem de audiencia) e texto livre sem data de validade vira modelo por
acidente.

**Aprendizado para a proxima marcacao de presenca:** use `register_attendance_batch`, NAO
`admin_bulk_mark_attendance`. Medi as duas: so a primeira grava ator. A segunda cai direto na #2176.

## Issues abertas pela lane, que eu nao toquei

- **#2207** modelagem de audiencia de evento (inscritos e participantes, interno e externo). Medicao
  util que ela ja fez: `events.external_attendees` preenchida em **1 de 740** eventos (coluna morta),
  e `persons` tem 134 linhas contra 135 membros, entao modelar externo nominalmente joga ~35
  titulares LGPD novos por evento la dentro.
- **#2208** backfill de legendas do acervo: **113 de 122 videos sem legenda**.

## Ordem sugerida para a proxima sessao

1. **#2204**, decidir entre investigar o React ou fatiar. E o unico item que segura a fila.
2. **Os 27 npm + `zod`**, com o plano de 4 ondas ja escrito acima nesta mesma pagina.
3. **A pesquisa das docs dos ultimos 45 dias** nos oito provedores, e as oportunidades de latencia
   do MCP. **E o pedido de maior valor e continua intocado**, adiado duas vezes por falta de
   contexto, nao por falta de escopo.
4. Os 3 convites de entrevista, que venceram e precisam do caminho que ENVIA e-mail.
