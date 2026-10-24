# Runbook: trocar o major do Node na CI

> Criado em 2026-10-24 (#2774). Cobre a troca de major (a próxima: 24 para 26) e o que medir
> antes, durante e depois. Sem em-dash por regra de entregáveis.

## Onde o major mora

- **`.nvmrc`**, com um major puro e par (`24`). Todo passo `actions/setup-node` dos workflows lê
  esse arquivo com `node-version-file: '.nvmrc'` e `check-latest: true`, então a CI sempre pega o
  patch mais novo daquele major. Nenhum workflow carrega versão literal.
- **Guard:** `tests/contracts/2774-setup-node-le-o-nvmrc.test.mjs`. Reprova versão literal, passo
  sem `check-latest`, job que chama `node`/`npm`/`npx` sem `setup-node` antes, e `.nvmrc` que não
  seja major puro e par. É ele que mantém a troca em uma linha.
- **Canário:** `.github/workflows/node-next-canary.yml` mede o major do `.nvmrc` + 2 (hoje, 26)
  contra `npm ci`, build, `smoke:routes` e as três suítes offline, toda quarta às 07:41 UTC e sob
  demanda (Actions, "Node next canary", Run workflow). Só reporta: não roda em push nem em PR, não
  recebe secret e não entra na faixa do banco.
- **Fora do `.nvmrc`, de propósito:** o runtime de produção é o workerd da Cloudflare, não Node; as
  Edge Functions rodam em Deno (`deno-ef-check.yml` fixa a versão do Deno); o worker
  `cloudflare-workers/pmi-vep-sync` não tem workflow nem `engines`.

## Antes do dia: prontidão

Tudo abaixo é leitura; nada muda o repositório.

1. **O major de destino é LTS.** Ler `https://raw.githubusercontent.com/nodejs/Release/main/schedule.json`
   e conferir a data `lts` do major. O 26 vira LTS em 2026-10-28.
2. **O canário está verde nas duas últimas rodadas**, lendo o resumo da rodada e não só a cor:
   - `EBADENGINE`: 0 pacotes (o resumo lista o nome de cada um quando não for 0);
   - `structural`, `contracts` e `behavioural` com sumário lido (não "sem sumario" nem "nao medido"),
     0 falhas, e 0 `DeprecationWarning`;
   - `npm ci`, build e `smoke:routes` com `success`.
3. **Engines das ferramentas que importam**, lidos do registro na hora (não de memória):

   ```bash
   for p in astro @astrojs/cloudflare vite wrangler @playwright/test eslint-plugin-astro astro-eslint-parser; do
     printf '%-24s %s\n' "$p" "$(npm view "$p" engines.node)"
   done
   ```

   Medido em 2026-10-24: `eslint-plugin-astro` e `astro-eslint-parser` pedem
   `^22.22.3 || ^24.16.0 || >=26.3.0`, então o piso real da linha 26 é **26.3.0**. O `check-latest`
   resolve o patch mais novo, que hoje é 26.12.1.
4. **O patch mais novo está no manifesto que o `setup-node` usa** (`actions/node-versions`, não o
   nodejs.org):

   ```bash
   curl -fsSL https://raw.githubusercontent.com/actions/node-versions/main/versions-manifest.json \
     | jq -r '[.[] | select(.version | startswith("26."))][0].version'
   ```

## No dia

1. Branch nova a partir da `main` atualizada.
2. **Uma linha:** `.nvmrc` de `24` para `26`. O guard garante que nenhum workflow precisa mudar; se
   ele reprovar, leia a mensagem, porque ela nomeia arquivo, job e passo.
3. **Ensaie no Node exato que a CI vai pegar**, não no padrão da máquina. Verde local num Node
   diferente do da CI já enganou uma vez (#2773: local em 24, CI em 22.23.3).

   ```bash
   nvm install 26 && nvm use 26         # o 26.x mais novo, o mesmo que o check-latest pega; vale só neste shell
   node -v                              # anote a versão: ela vai para o corpo da PR
   npm ci
   npm run build > /tmp/build.log 2>&1; echo "exit=$?"; head -40 /tmp/build.log
   for b in structural contracts behavioural; do
     env -u SUPABASE_URL -u SUPABASE_SERVICE_ROLE_KEY node scripts/run-suite.mjs "$b"
   done
   node tests/browser-guards.test.mjs
   ./node_modules/.bin/astro dev stop   # o browser-guards deixa o dev server de pé
   ```

   O código de saída do build é o do comando sem pipe; leia o começo do log, que é onde a
   ferramenta nomeia o erro.
4. **O padrão do nvm da máquina** (`nvm alias default 26`) é configuração de máquina e vai pelo
   runbook de máquina, fora da PR.
5. A PR roda a CI inteira no 26, porque todo job lê o `.nvmrc`. A exceção é o `deploy.yml`, que só
   roda na `main`.

## Depois do merge: o primeiro deploy

O `deploy.yml` dispara por `workflow_run` do CI na `main`, então a PR nunca o exercita.

1. Abrir a rodada do deploy disparada pelo merge e ler, no passo do `setup-node`, a versão
   resolvida (`Attempting to download 26.x.y...` ou `Found in cache @ .../node/26.x.y/x64`). O
   número tem de ser do major novo; se não for, o deploy rodou outro Node e nada abaixo vale.
2. O job terminou com `success`.
3. `npm run smoke:prod` passa contra a produção.
4. O carimbo de proveniência de produção aponta o commit do merge (#2255).

**Reverter:** PR de revert da troca do `.nvmrc`, nunca force-push. O guard aceita o 24 de volta
sem mais nada.

Depois da troca, o canário passa sozinho a medir o 28. Enquanto o 28 não tiver release no
nodejs.org, a rodada diz "nao medido" e sai verde.

## Armadilhas conhecidas (medidas em 2026-10-24)

- **Formato do `node --test`.** Do 23 em diante o reporter é `spec` mesmo em pipe (`✖`, `ℹ tests N`);
  o 22 emite TAP em pipe (`not ok`, `# tests N`). Quem lê log de teste aceita os dois
  (`invariants-check.yml`, `tests/contracts/1910-*`); `scripts/test-verdict.mjs` lê `ℹ`.
- **`module.register()`** é depreciação de runtime no 26 (DEP0205, "será removido"). O hook de
  `scripts/lib/register-ts-resolve.mjs` já usa `module.registerHooks()`. Antes dessa troca, as
  suítes no 26 emitiam 5 `DeprecationWarning`; depois, 0.
- **`--experimental-strip-types`** continua aceito no 26 e é redundante desde o 24.12 (type
  stripping estável). `--experimental-transform-types` foi removido no 26; o repositório não usa.
- **npm 11 e `allowScripts`.** O `npm ci` avisa que `esbuild`, `workerd` e `@turbodocx/html-to-docx`
  têm script de instalação não coberto por `allowScripts`. No npm 11.19.1 (Node 24.22.1) e no
  11.20.0 (Node 26.12.1) os scripts **rodam** com o aviso: depois do `npm ci` os binários de
  `esbuild` e `workerd` são ELF; com `--ignore-scripts` ficam como shim JS. Mesmo bloqueados,
  `esbuild`, `workerd` e `wrangler` respondem `--version` pelo shim. Se uma versão do npm passar a
  bloquear por padrão, o build não depende desses scripts.
- **APIs que o 24 e o 26 depreciaram ou removeram** (`url.parse`, `SlowBuffer`,
  `tls.createSecurePair`, `http.Server.prototype.writeHeader`, `_stream_*`): 0 usos no nosso código
  em 2026-10-24.

## Ensaio de 2026-10-24 no Node 26.12.1

Local (GS66), numa cópia da árvore com índice git, sem `.env` e sem credencial de banco, com
`NODE_OPTIONS=--trace-deprecation`. É um ensaio local, não uma rodada da CI.

| passo | resultado |
|---|---|
| `npm ci` (npm 11.20.0) | ok, 0 pacotes `EBADENGINE` |
| build | exit 0 |
| `smoke:routes` | ok |
| structural | 4472 testes, 0 falhas, 0 pulos |
| contracts | 8218 testes, 0 falhas, 975 pulos (pedem banco) |
| behavioural | 4118 testes, 0 falhas, 980 pulos (pedem banco) |
| `DeprecationWarning` | 0 (eram 5, todos DEP0205, antes da troca do hook) |

Sem índice git, os 5 arquivos de guard que leem `git ls-files` reprovaram no 26; com o índice, os
mesmos 5 passam no 26 e no 24 (30 testes, 0 falhas). Era o ambiente da cópia, não o 26: ensaie
sempre num checkout.
