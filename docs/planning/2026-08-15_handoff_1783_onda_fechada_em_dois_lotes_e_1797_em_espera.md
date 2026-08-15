# Handoff — 15/08/2026 (noite): a onda do #1783 caiu de 8 para 3, e o terceiro lote está pronto e parado

> Sessão anterior: `docs/planning/2026-08-15_handoff_1791_escrita_gateada_e_1779_nome_proprio.md`
> Arranque da próxima: `docs/planning/2026-08-16_PROMPT_ARRANQUE_1797_EM_ESPERA_1710_E_1780.md`

---

## Estado ao fechar

`main` em **`43247280`**. **1 PR aberta: a #1797**, verde e `MERGEABLE`, **parada de propósito**
aguardando decisão de data. **2 merges na sessão, zero bypass.**

Alertas Dependabot: **8 → 3**, com os **5 high zerados**. Os 3 restantes são todos do `astro` e são
exatamente o conteúdo da #1797.

| lote | o que era | desfecho |
|---|---|---|
| 2 | `nanoid`, `js-yaml` — transitivos **com** patch | **mergeado** (#1796, 11/11 verde) |
| 3 | `extract-zip`, `image-size` — **sem** patch publicado | **veredito + 3 alertas dispensados** |
| 1 | `astro` — major, 3 alertas | **#1797 aberta, 11/11 verde, aguardando 24/08** |

---

## Lote 2 — o barato, e ele foi barato mesmo

`nanoid` 3.3.17 → 3.3.18 e `js-yaml` 4.3.0 → 4.3.1, um em cada lockfile do repo (o segundo,
`cloudflare-workers/pmi-vep-sync/`, é o que se esquece). Ambos os pais já declaravam faixa compatível,
então o patch coube **sem tocar em nenhum `package.json`**: 3 linhas por lockfile.

---

## Lote 3 — o veredito, e por que ele não foi "aceitar e seguir"

`extract-zip` (CVE-2026-56876, traversal por symlink) e `image-size` (CVE-2025-71330 e 71329, laço que
não avança quando o campo de tamanho vem zerado) **não têm patch**: a `image-size@2.0.2` **é** a última
publicada.

As outras duas saídas do manual foram medidas e descartadas, não presumidas:

- **Subir o pai não resolve nenhum dos dois.** O `@puppeteer/browsers@3.2.0` abandonou o `extract-zip`
  de vez (usa `modern-tar`), mas o `@cloudflare/puppeteer`, na versão mais nova, declara
  `"@puppeteer/browsers": "2.2.4"` — **exato, sem caret**. E o `@turbodocx/html-to-docx@1.22.0` ainda
  aponta `image-size: ^2.0.2`, que é o topo.
- **`overrides` seria pior que a doença:** forçar o `@puppeteer/browsers` 3.x rompe um pin
  **deliberado** da Cloudflare no caminho que gera o PDF de certificado — rota que já teve incidente
  (#1047).

Veredito **não alcançável**, verificado **contra o bundle construído**, não contra a árvore de
dependências. Alertas dispensados como `not_used`, com as **premissas de reabertura** registradas na
issue (senão o veredito apodrece e ninguém sabe o que reconferir).

### O achado que a árvore de dependências não mostrava

Ao grepar o `dist/` apareceram **duas** cópias do `image-size`, com histórias opostas:

| cópia | Dependabot vê? | chega ao servidor? | é chamada? |
|---|---|---|---|
| pacote (via `html-to-docx`) | **sim** (#94, #93) | não, só ao bundle do cliente | na aba do próprio usuário |
| **vendorizada dentro do `astro`** | **não** (não é pacote) | **sim**, no chunk `image-transform-endpoint` | **não** |

A vendorizada tem o **mesmo laço sem guarda em 6.4.8, 7.1.0 e 7.2.2** — conferido nas três. É código
morto ali porque o `/_image` entrega os bytes ao binding nativo `env.IMAGES` em vez de ao parser JS, e
porque `domains`/`remotePatterns` vazios devolvem 403 a qualquer `href` remoto.

⚠️ **Consequência prática: a #1797 NÃO fecha essa classe.** Não vender o bump do astro como correção
disso.

---

## Lote 1 — a #1797, e o que o major revelou

Não é um bump. O `@astrojs/cloudflare` 13.x pinza `astro: ^6.3.0` **até a 13.7.0**, então não existe
astro 7 sem o major do adapter; e o 14.2.1 pede `astro ^7.2.0`. O react integration vai junto porque o
vite sobe para 8.

```
astro 6.4.8 → 7.2.2 · @astrojs/cloudflare 13.5.1 → 14.2.1 · @astrojs/react 5 → 6
@astrojs/sitemap 3.7.2 → 3.7.3 · astro-eslint-parser + eslint-plugin-astro → 3.1.0
vite 7.3.6 → 8.2.1 (transitivo; rolldown no lugar do rollup)
```

**Dois defeitos latentes vieram junto, ambos já existiam:**

1. **Um `<script>` que nunca era fechado.** `src/pages/tribe/[id].astro` abria `<script>` na linha 370
   e o arquivo terminava em `boot();`. O compilador do astro 6 auto-fechava no EOF; o do 7 é o
   `@astrojs/compiler-rs` (reescrita em Rust) e recusa. Varredura dos **400** arquivos `.astro` com o
   compilador novo: **399 OK, 1 falha**. Depois da correção, **400/400**.
2. **O gate do #1205 dependia do compilador removido.** `astro-eslint-parser@1.4.0` carrega
   `astrojs-compiler-sync`, que importa `@astrojs/compiler` — o pacote que o astro 7 tirou da árvore.
   O `lint:client-scripts` quebrou, e como o gate executa esse lint por dentro, falhou junto. Pior:
   **travou 39,9 min num único teste**. O parser 3.x já usa `compiler-rs` mas deixou de expor default
   export, daí o `import * as` no `eslint.config.mjs`.

**Gates, todos re-rodados depois das correções:** CI **11/11** · suíte local **6846 · 6845 pass · 0
falhas · 1 skip · 634,6 s** contra baseline da `main` de 629,5 s com a mesma contagem ·
`wrangler deploy --dry-run` passa com 470 módulos e bindings `SESSION`/`BROWSER`/`IMAGES`/`ASSETS`
resolvidos.

O dry-run foi rodado de propósito: o adapter 14 passou a emitir um `dist/server/wrangler.json` que o
13.5.1 **não** emitia, com `main: entry.mjs` divergindo do `wrangler.toml` da raiz. Em vez de supor
que o contrato de deploy se manteve, validou-se.

---

## ⚖️ A decisão que ficou com o PM

**Segurar a #1797 até depois de 24/08** (recomendação registrada na PR, ainda não decidida).

O argumento não é "pode quebrar no CI" — não quebrou. É que a PR troca astro, adapter, react
integration e o **bundler** de uma vez, e o que só aparece em produção apareceria dentro da janela do
selo. Um build vermelho bloqueia depurar **e** deployar correção urgente ao mesmo tempo.

E o outro lado da balança esvaziou quando foi medido. Os 3 alertas do astro são **XSS**, cada um
exigindo um padrão de código específico:

| alerta | padrão exigido | ocorrências no repo |
|---|---|---|
| #62 medium | `{...spread}` em `.astro` | **0** |
| #60 low | `transition:persist` / `transition:scope` | **0** |
| #52 medium | `transition:animate` / `ViewTransitions` / `ClientRouter` | **0** |

Pelo mesmo critério do Lote 3, os três também são não alcançáveis. Sobra higiene, que é boa razão mas
**sem prazo** — enquanto o `floor_date` 2026-08-24 tem.

📌 **Erro de processo a não repetir:** a primeira recomendação de adiar saiu por **severidade nominal**
("2 medium + 1 low"). Ler o *summary* do advisory e grepar o padrão custou uma volta de tool call e
teria dado o argumento certo desde o início.

---

## Sedimentado fora daqui

- **3 memórias novas**, indexadas no `MEMORY.md`: cópia vendorizada invisível ao scanner · pin exato
  que anula "subir o pai" · major que troca o compilador e leva o toolchain de lint junto.
- **Lições de processo na `[LL]` #588** para o loop do PMO, incluindo as três armadilhas de
  instrumentação (o `| tail -N` que cega a suíte em background, o `pgrep -P` para distinguir lenta de
  travada, e o contract test com shell-out que trava em vez de falhar).

---

## Aberto ao fechar

**#1710** (re-medir em 23/08 pelos dois caminhos; lista nominal ao GP **fora** de issue e PR) ·
**#1797** (decisão de data) · resto do **EPIC #1780** · **#1586** e o **funil de 28/08**, que só fecham
com uso real · **#1783** fecha quando a #1797 mergear.
