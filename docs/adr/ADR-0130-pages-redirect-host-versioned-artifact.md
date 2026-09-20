# ADR-0130 - O redirect de `nucleoia.pmigo.org.br` passa a ser artefato versionado

**Status:** Accepted (2026-09-19)
**Ratificado por:** decisão do dono, resposta literal - *"Declarar o redirect em controle de versão"*
**Contexto de origem:** #2370 (reconciliação de veículos de deploy), sessão de 19/09/2026

## Contexto

`nucleoia.pmigo.org.br` é o `CERT_VERIFY_HOST` declarado em `src/lib/canonical.ts` e impresso nos
links de verificação de **certificados PDF já emitidos**. Ele responde `301` para
`https://nucleoia.vitormr.dev/`, preservando caminho e query.

Medido em 19/09/2026, a origem desse 301 **não era** nenhuma das duas hipóteses que a investigação
carregava (Bulk Redirect de conta, ou configuração do projeto Pages):

- o `canonical_deployment` do projeto Pages `ai-pm-research-hub` é `474cbb90`, de **2026-06-11**,
  com `trigger=ad_hoc`, `commit_hash` **vazio**, `commit_dirty=true` e estágios
  `clone_repo:idle  build:idle  deploy:success` - ou seja, **artefato subido à mão**, que pulou
  clone e build e nunca veio do repositório;
- a config do projeto não tem nenhuma chave `redirect` (busca em todos os caminhos do JSON);
- não existe `_redirects` na árvore do repositório, nem existia na árvore de 11/06.

A investigação anterior havia concluído o contrário, porque seu discriminador estava quebrado: ela
sondou o deployment `1b8ea19a`, que devolve `404` com **16149 bytes** e título *"Deployment Not
Found"* - **byte-idêntico ao que dois hashes inventados devolvem**. Aquele 404 significava "este
deployment não existe", não "existe e não redireciona".

## Decisão

1. O redirect passa a viver em **`infra/pages-redirect/_redirects`**, versionado, com a regra
   `/*  https://nucleoia.vitormr.dev/:splat  301`.
2. A publicação é feita por **`scripts/deploy-pages-redirect.sh`**, que exige `--prod` explícito
   para tocar produção e **verifica** o resultado (três caminhos + o destino final em 200) antes de
   declarar sucesso.
3. O projeto Pages **permanece desconectado do git** (`deployments_enabled=false`,
   `preview_deployment_setting=none`, desde 19/09/2026). Publicar é ato deliberado, não efeito de
   push. Isso é intencional: o projeto acumulou **5824** deployments, e os de produção ficavam em
   `deploy:idle` sem nunca rodar.
4. O diretório de deploy contém **apenas** `_redirects`. Um `index.html` ali seria servido em `/`
   com precedência sobre a regra e mataria o redirect na rota mais importante. O script tem guard
   para isso, exercitado por mutação: com um `index.html` injetado, ele reprova e não publica.

## Equivalência provada antes de publicar

Deploy de preview exercido contra o comportamento vivo, mesma medição nos dois:

| caminho | vivo (artefato manual) | preview (artefato versionado) |
|---|---|---|
| `/` | 301 → `…/` · 44 bytes · `text/plain` | **idêntico** |
| `/verify/TESTE-123` | 301 → `…/verify/TESTE-123` · 60 bytes | **idêntico** |
| `/a/b/c?x=1&y=2` | 301 → `…/a/b/c?x=1&y=2` · 57 bytes | **idêntico** |

Controle negativo na mesma medição: um alias de preview inexistente devolve 404 com 16149 bytes,
logo a sonda discrimina. Controle positivo: seguindo o redirect, o destino responde **200**.

## Consequências

- **Positiva:** o comportamento de um host impresso em documento externo deixa de depender de um
  artefato que só existia na conta Cloudflare, sem histórico, sem revisão e sem autor registrado.
- **Positiva:** mudar o redirect passa a ser uma PR, com diff legível.
- **Custo aceito:** a publicação é manual. Não há gatilho automático, e um `_redirects` alterado em
  `main` **não** chega sozinho ao ar. Quem mudar o arquivo tem de rodar o script.
- **Não resolvido por este ADR:** dois hostnames de `pmigo.org.br` (`nucleoia.` e `sgpl.`) vivem em
  projetos Pages de **conta pessoal**, com a zona hospedada na HostGator. Isso é decisão de
  governança de portfólio e foi **escalada ao nó PMO**, conforme a regra de
  `AI-PMO-Framework/docs/operating-model.md` (*account/org-scoped blockers escalate to the PMO*).

## Rollback

O deployment `474cbb90` (o artefato manual de 11/06) **não é apagado** por esta mudança. Reverter é
repromovê-lo como produção no painel do Pages, ou publicar de novo a partir de um commit anterior
deste diretório. Verificação de rollback é a mesma do script: os três caminhos + o 200 final.

## Gatilho de reabertura

Este ADR é reaberto se qualquer uma ocorrer:

| gatilho | ação |
|---|---|
| a zona `pmigo.org.br` migrar para a Cloudflare | reavaliar: com zona própria, uma Redirect Rule substitui o projeto Pages inteiro |
| o nó PMO decidir mover os hostnames para conta institucional | o redirect muda de dono, e este ADR é substituído |
| `CERT_VERIFY_HOST` deixar de ser `nucleoia.pmigo.org.br` | o redirect vira legado e pode ser aposentado depois do último certificado emitido com o host antigo |
