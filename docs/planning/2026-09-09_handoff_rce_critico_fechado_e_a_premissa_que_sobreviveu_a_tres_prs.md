# Handoff 09/09/2026: o RCE crítico fechado, e a premissa que sobreviveu a três PRs

> **Nada aqui é medição.** Carimbado em 09/09 às 19:06 BRT. Tudo abaixo é relógio.
> **Re-meça antes de decidir:**

```bash
git fetch --all && git log --oneline -1 origin/main
gh pr list --state open
gh issue list --state open --limit 30
gh api repos/VitorMRodovalho/ai-pm-research-hub/dependabot/alerts --jq '[.[]|select(.state=="open")]|length'
```

**Estado ao encerrar, para COMPARAR e não para acreditar:** `main aae0c61e` · fila **vazia** ·
**8 PRs mergeadas no dia**, todas por squash com CI verde · **0 bypass** (os 8 commits da main
carregam `(#N)`) · **0 alertas abertos** no Dependabot.

---

## O que fechou, e por quê importa

### O vermelho da #2204 tinha uma causa que ninguém tinha achado em três dias

A PR estava travada desde 07/09 com **duas hipóteses erradas em sequência**. A do `@tiptap` já
tinha caído na sessão anterior. **A do `react` caiu agora, por medição direta:** comparei os dois
lockfiles pacote a pacote e `react`, `react-dom`, `vite`, `rolldown`, `esbuild` e
`@vitejs/plugin-react` estavam **idênticos nos dois lados**. O bump `19.2.6 -> 19.2.8` anotado no
comentário da PR **não existia**.

A causa real: **`astro 7.2.2 -> 7.3.2`**, que o `npm audit fix` arrastou sem nenhum alerta exigir.
O scanner de dependências do Vite falha ao parsear o **frontmatter dos `.astro`**:

```
[PARSE_ERROR] Expected `(` but found `const`
  virtual-module:src/pages/admin/blog.astro?id=0:3:1
```

Substituída pela **#2210**, que sobe só os **5 pacotes** que os 8 alertas exigiam. O lock diff caiu
de 741/988 linhas para 243/245, e o `browser_guards` ficou verde.

### No meio do caminho apareceu um RCE `critical`

A revarredura que seguiu o merge da #2210 abriu **9 alertas novos**, um deles **`critical`: RCE no
astro por otimização de imagem AVIF**. A decisão de segurar a linha 7.2 virou sorte, porque **o
piso do advisory era 7.2.8, não 7.3**. Fechado pela **#2215** com `~7.2.10`.

**Balanço do dia: 17 alertas tratados, 0 abertos.** 16 corrigidos por código, 1 dispensado.

---

## O que NÃO refazer

- **Os 3 convites de entrevista JÁ FORAM REEMITIDOS**, hoje às 11:56 BRT, e **o e-mail saiu**:
  `email.sent` e `email.delivered` para os três, um deles com `opened` e `clicked`. O arranque
  dizia que faltava o "caminho que ENVIA e-mail". Não falta. **O que falta é reserva:** os três
  seguem com `booked_at` nulo e `interview_state = needs_reschedule`.
- **O webinar de 08/09 está fechado e verificado.** Já estava dito no delta, continua valendo.
- **A hipótese do `react` na #2204 está morta.** Medida e enterrada. Não reabrir.
- **As duas deprecações da Supabase não alcançam este repo.** `logs.all` (removido em 23/09) e
  pinagem de versão de extensão: **0 ocorrências** cada, medidas hoje. O prazo de 23/09 **não é
  nosso**.
- **As três alavancas de latência da spec MCP nova não existem hoje.** O SDK 1.30.0, que a
  `nucleo-mcp` pina, declara `LATEST_PROTOCOL_VERSION = '2025-11-25'`. Não planejar contra elas.

---

## A lição do dia, que não é técnica

**Uma premissa de handoff sobreviveu a três PRs sendo repetida, e só caiu quando alguém precisou
dela para assinar algo.**

A frase era: *"o `extract-zip` só roda no download do Chrome em ambiente local/CI, nunca no runtime
do Worker"*. Vinha da #2204 e foi repetida em **#2210, #2215 e #2217** sem re-medição, por mim.

Ao ir escrever a justificativa da dispensa no Dependabot, ela caiu em dois pontos:

1. `@cloudflare/puppeteer` está em **`dependencies`**, não em devDependencies, e é importado em
   duas rotas do Worker (`cert-pdf-render`, `agenda-availability-probe`). A biblioteca **está** no
   runtime, então a afirmação exigia olhar o artefato.
2. "Só em local/CI" estava **errado**, e a verdade é mais forte: **nada o invoca, em lugar nenhum**.
   Nem `@cloudflare/puppeteer` nem `@puppeteer/browsers` têm `postinstall`, e o repo não chama o
   CLI que o usaria.

O que assina a dispensa é o artefato: `grep -rl 'extract-zip\|yauzl' dist/` dá **0**, com dois
controles (positivo no mesmo diretório, e de padrão contra `node_modules/extract-zip/`).
Correção completa registrada na **#611**.

**O gatilho de verificação chegou tarde.** Precisar da premissa para uma ação irreversível é o
último momento possível para conferi-la, não o primeiro.

---

## Armadilhas de ferramenta que custaram caro, e vão custar de novo

**1. `astro dev` DAEMONIZA.** Volta ao shell imprimindo um pid; a saída real vai para
`astro dev logs`. Um harness que faz `spawn` e lê o stdout vê **silêncio**, e silêncio foi lido
como "sem erro". Foi isso que deixou o diagnóstico errado sobreviver duas sessões.

**2. Mensagem de erro que começa com uma LISTA nomeia o primeiro item, não o culpado.** O log
dizia `Failed to scan for dependencies from entries:` seguido de `ErrorBoundary.tsx`. Duas sessões
leram isso como o arquivo defeituoso. Era o primeiro **entry**; o `[PARSE_ERROR]` real vinha
**depois da lista inteira**, em dois `.astro`.

**3. `^` não segura o que você decidiu segurar.** `^7.2.10` admite `7.3.x` e reintroduz o defeito
**em silêncio**, sem diff e sem decisão. Quando a intenção é prender numa linha, o operador é `~`.

**4. Repo com DOIS lockfiles: `grep` na raiz responde pela raiz.** Quase classifiquei 4 alertas de
`vitest` como falso positivo porque ele está **ausente** do lock da raiz. Estava em
`cloudflare-workers/pmi-vep-sync/package-lock.json`. **O alerta traz `manifest_path`; leia esse
campo antes de concluir.**

**5. `gh pr checks` não lista quem não reportou.** Meu laço de espera usava "nenhum pendente" e viu
`total=7 pendentes=1` quando faltavam cinco checks. Troquei por **piso de contagem** (`total >= 12`),
que é o mesmo critério do portão de merge. Nenhum merge saiu pela condição frouxa.

Tudo isso está na **#588** para a colheita do PMO, e as lições 1, 2 e 3 já entraram nas memórias
(estendi arquivos existentes; o índice segue nas 200 linhas do teto).

---

## A pesquisa dos 45 dias saiu (#2212)

`docs/research/2026-09-09_docs_45d_oito_provedores_e_latencia_mcp.md`. Dois achados que mudam
trabalho:

**A spec do MCP virou `2026-07-28`**, e ela remove o handshake `initialize`, remove as sessões e o
`Mcp-Session-Id`, torna `server/discover` obrigatório e exige `ttlMs`/`cacheScope`. **Mas o SDK não
acompanhou** (#2214).

**A rota MCP está saudável, ao contrário do que o número feio sugeria.** Últimos 14 dias:
**p50 1003 ms, p95 2048 ms, p99 2970 ms, máximo 5575 ms**. O p99 de 101,7 s dos 45 dias vem de **um
episódio de três dias** (17 a 19/08), e durante ele o p50 seguiu em 1023 ms. **Não abrir isto como
"o MCP está lento".** O defeito real é outro: **35 chamadas gastaram 93,7 s de média para entregar
uma FALHA**, enquanto as recusas legítimas levam 752 ms (#2213).

---

## ADENDO, depois deste handoff já estar mergeado: a armadilha 1 tem uma consequência (#2219)

Ao mergear este próprio documento, o `browser_guards` reprovou numa PR que **só adiciona um `.md`**.
O re-run passou, mas o log tinha a informação: **duas falhas de classes diferentes na mesma
execução.** Na tentativa 1 o servidor subiu e o `workerd` falhou ao resolver o módulo virtual de um
`<script>` inline do `BaseLayout.astro`; na tentativa 2 o servidor **nem subiu**.

A causa é a armadilha 1 desta mesma página, vista do outro lado. O harness faz
`devServer?.kill('SIGTERM')` (`tests/browser-guards.test.mjs:677`), mas `devServer` é o wrapper
`npm run dev`, **não o daemon**. O `run_browser_guards_with_retry.sh` só faz `sleep 5` entre as
tentativas. Resultado: **a tentativa 2 nasce com o dev server da tentativa 1 ainda vivo, e falha
por causa dele. O retry não é um retry.**

Duas consequências que valem mais que o flake:

1. **Um retry que não limpa transforma falha transitória em falha aparentemente determinística.**
   Esconde o flake e inventa um defeito.
2. O argumento *"o script tenta duas vezes e falhou nas duas, então não é flake"*, usado na #2204
   para sustentar três dias de investigação, **era mais frágil do que parecia**. Naquele caso a
   conclusão continua certa por outro motivo (a tentativa 1 falhava com um `PARSE_ERROR`
   determinístico, reproduzido local, que sumiu ao segurar o astro na linha 7.2). Da próxima vez
   pode sustentar uma conclusão errada.

Isto também **explica o travamento local** mencionado ao longo do dia: eram daemons vazados dos
próprios runs anteriores, e matei dois `workerd` órfãos. Não era confundidor inexplicado da máquina.

Registrado na **#2219**, com proposta: parar o daemon entre tentativas, **verificar** a parada em
vez de confiar nela, e distinguir no relatório "servidor não subiu" de "servidor subiu e o locator
estourou".

---

## Aberto, e o que cada coisa espera

| # | o que é | espera |
| --- | --- | --- |
| **#2211** | astro 7.3.2 quebra o dev server | correção upstream; 7.3.2 é a última publicada |
| **#2213** | MCP mede só de dentro do handler, e falha devagar | timer ponta a ponta **primeiro** |
| **#2214** | spec MCP 2026-07-28 contra SDK 2025-11-25 | vigia: SDK publicar versão que declare a nova |
| **#2217** | plano de dependências, 30 atrasados re-medidos | ondas 1 a 4, na ordem escrita lá |
| **#2219** | o retry do `browser_guards` não limpa o daemon entre tentativas | limpar e **verificar** a parada |
| #2205 #2207 #2208 | camada semântica de webinar, audiência de evento, legendas | abertas pela lane, não toquei |

**Nenhuma PR aberta.** A fila está vazia, o que é a melhor hora para abrir lane.

---

## Prazos

- **10/09, amanhã: Reunião Geral.** Os **cinco pontos da pauta** seguem parados do lado do PM
  desde 04/09. Não toquei.
- **11/09: aprovação do TAP** do Grupo de Estudos CPMAI (lane `.wt-cpmai`, parada desde 31/08).

---

## Ordem sugerida para a próxima sessão

1. **Os cinco pontos da pauta**, porque a reunião é amanhã e é o único item com data no dia
   seguinte.
2. **#2213 item 1**, o timer de ponta a ponta do MCP. É pequeno, e **vem antes** de qualquer
   otimização, porque sem ele nenhuma melhoria fica visível.
3. **Onda 1 da #2217**, os minor/patch por família. A fila vazia favorece.
4. **Os 3 convites**, se ninguém reservar. O e-mail chegou; se a reserva não vier, o gargalo é
   outro e precisa ser medido, não reemitido de novo.

---

## Uma observação que não virou issue

A cadeia de supersede do `selection_dispatch_url_log` **tem buracos**: filtrando por
`superseded_at IS NULL` para os três candidatos voltam **7 linhas**, não 3. As linhas de 31/07,
04/08 e 07/08 (todas da era `instrumented = false`) nunca foram marcadas como superadas.

Não investiguei e não abri issue. Fica o aviso: **uma consulta que assume "não superada = vigente"
vai contar convite velho como ativo.** Para pegar o vigente, ordene por `dispatched_at DESC` e
tome o primeiro, ou cruze com `instrumented`.
