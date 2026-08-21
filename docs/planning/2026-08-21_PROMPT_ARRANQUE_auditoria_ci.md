# Arranque: auditoria da CI e dos criterios de merge

> Medido ao vivo em **21/08/2026**. **Re-medir antes de concluir**: numero recitado de handoff nao
> vale como medicao. Repositorio PUBLICO: sem nome de pessoa, sem identificador de candidato.

---

## 0. A pergunta do PM, sem reformular

"Os CI e criterios de validacao de merge estao seguindo as boas praticas? Nao estao ficando
pesados? Precisamos de um plano de agrupamento de licoes aprendidas e organizacao das rotinas?"

E a instrucao de metodo: **verificar o que GitHub, Anthropic, Cloudflare e Supabase orientaram nos
ultimos 60 dias**, e usar isso na decisao. Nao e para responder de memoria.

⚠️ **Esta lane NAO deve sair consertando a CI.** O produto e um **diagnostico com recomendacao**,
para o PM decidir. Mudanca em portao de merge sem decisao explicita e exatamente o tipo de coisa
que trava a fila de todo mundo.

---

## 1. A superficie atual, medida

| medida | valor |
|---|---|
| workflows em `.github/workflows/` | **16** |
| checks **required** na `main` | **3**: `validate`, `browser_guards`, `deno` |
| arquivos de teste | **611** |
| destes, testes de contrato | **594** |
| duracao media do `CI Validate` | **~13 min** |
| duracao media do `Schema Invariants` | **~6 min** |
| allowlist de body-drift (P175) | 26 linhas |
| allowlist de orfas (P50) | 15 linhas |

---

## 2. O fato que motivou a auditoria: 6 travamentos em 2 dias

Entre 20 e 21/08 a fila de merge parou **seis vezes**. Só **uma** foi defeito real de codigo.

| # | causa | era defeito de codigo? |
|---|---|---|
| 1 | `deno check` resolvia a arvore npm do FRONTEND inteira (39 pacotes que nenhuma EF importa); publicacao quebrada de terceiro derrubou o check | **sim**, estrutural. Corrigido (#1896) |
| 2 | migrations aplicadas no banco compartilhado sem `.sql` na branch | nao, acoplamento |
| 3 | `database.gen.ts` velho vs schema vivo | nao, acoplamento |
| 4 | 5 migrations repartidas entre DUAS branches, bloqueio MUTUO | nao, acoplamento |
| 5 | mais uma migration sem `.sql` | nao, acoplamento |
| 6 | linha de `gate_attempts` criada em producao por acao humana | nao, dado de producao |

**Quatro dos seis** (2 a 5) sao a mesma causa: **DDL aplicada num banco compartilhado antes do
merge serializa TODAS as PRs**. Duas branches nao conseguem estar verdes ao mesmo tempo.

**Dois deles** (o 6 e o card de XP de 20/08) sao outra classe: **teste comportamental sobre dado de
producao**. Um evento real e legitimo derruba a fila inteira, inclusive PRs que so mexem em docs.

---

## 3. As perguntas estruturais que a auditoria precisa responder

1. **Teste de contrato deve rodar contra PRODUCAO?** Hoje a suite roda contra o banco real e divide
   o pool de conexoes com trafego real (#1844: `check_schema_invariants()` leva 2,53 s em SQL puro
   e 33 a 49 s pela porta do PostgREST, por fila de pool). Alternativas a avaliar: branch de banco
   efemera, seed dedicado, ou separar "invariante de schema" de "invariante de dado".
2. **Quantos dos 3 required deveriam ser required?** E o inverso: ha check nao-required que deveria
   ser? Um required cancelado e **pior que vermelho**, porque nao nomeia nada e bloqueia igual
   (#1869).
3. **Allowlist que so cresce e portao ou divida?** O do #1636 saiu de 1 para 5 entradas em UM dia,
   e as 4 ultimas sao a MESMA operacao repetida. Isso mede a ausencia de superficie autenticada
   (#1586), nao teste mal escrito. Um allowlist sem data de validade vira ratchet ao contrario.
4. **Alvo instavel em teste comportamental.** Ja encontramos `limit=1` SEM `ORDER BY` escolhendo
   alvo arbitrario (#1113): a ordem fisica muda e um required reprova sem nada ter mudado.
   **Varrer a suite atras de outros alvos instaveis** e provavelmente o achado de maior retorno.
5. **Ordem de execucao e orcamento.** O `validate` leva ~13 min. Vale medir onde o tempo vai e se
   ha ganho em paralelizar ou em mover o que e lento para nao-required.

---

## 4. A pesquisa externa (60 dias)

Buscar orientacao **publicada nos ultimos 60 dias** e trazer o que for aplicavel, com link:

- **GitHub Actions**: merge queue, required checks, `cancel-in-progress`, reuso de workflow,
  artefatos e cache, boas praticas de branch protection e de rulesets.
- **Supabase**: branching de banco para CI, `db diff`/migrations em equipe, teste contra branch
  efemera, pooler e limites de conexao.
- **Cloudflare**: Workers/Pages em CI, preview deployments, wrangler em pipeline.
- **Anthropic**: praticas de engenharia com agentes em CI e revisao de codigo.

⚠️ **Nao aceite blog post antigo como "recente".** Confira a data de publicacao e diga qual e.
Se algo relevante for mais antigo que 60 dias mas continuar sendo a orientacao vigente, diga isso
explicitamente em vez de silenciar a data.

---

## 5. Entregavel esperado

Um documento em `docs/audit/` com:

1. **Inventario** dos 16 workflows: o que cada um protege, custo em minutos, required ou nao,
   e se ha sobreposicao entre eles.
2. **Classificacao dos testes** por natureza: estrutural (le catalogo/codigo) vs comportamental
   (le dado de producao). A segunda classe e a que derruba fila por evento legitimo.
3. **Varredura de alvos instaveis** (`limit` sem `ORDER BY`, dependencia de ordem fisica, janela
   de tempo fixa).
4. **Comparacao com as praticas dos 4 fornecedores**, com data e link.
5. **Recomendacao priorizada**, separando o que e decisao do PM do que e conserto mecanico.

📌 Regra do repo que vale aqui: **ao consertar portao, injete o defeito e prove que ele ainda
REPROVA.** Verde por conserto e verde por vacuo tem a mesma cor. Foi assim que validamos o #1896.

---

## 6. Armadilhas medidas, que custam tempo real

- **`npm test` local nao emite TAP.** O reporter do Node 24 e `spec` (`✔`/`✖`/`ℹ`). Filtro que
  procura `not ok` volta VAZIO mesmo com falha. Use:
  `npm test 2>&1 | grep -E '^[[:space:]]*(not ok|✖)|^(#|ℹ) (fail|pass|tests|skipped)'`
- **Carregue o `.env`** (`set -a; . ./.env; set +a`), senao os testes DB-aware **pulam em silencio**:
  medimos **744 skipped** local contra **1** na CI. `fail 0` com 744 skipped nao e suite verde.
- **A arvore de trabalho principal e COMPARTILHADA entre sessoes.** Trabalhe NESTE worktree e nao
  troque a branch da arvore principal: em 20/08 um checkout de outra sessao passou por cima de
  edicao em andamento.
- **Escalone pushes.** Duas branches atualizadas no mesmo segundo derrubam as duas na faixa do
  banco (#1509). E `cancel-in-progress: false` faz push durante run criar um segundo run `pending`
  que nao despacha: cancele o obsoleto.

---

## 7. Contexto de fila (nao e tarefa desta lane)

`main` em `fe268cf2`. A fila esta travada por uma linha de `gate_attempts` de 21/08 14:18:47, do
escopo do #1636. Nao bloqueia a auditoria, mas bloqueia merge: entregue em PR sem contar com merge
imediato.

Issues relacionadas, ja abertas: **#1896** (o conserto do `deno`), **#1906** (cron de agenda rara
sem recuperacao; 53 dos 68 ativos), **#1844** (pool do PostgREST), **#1869** (required cancelado),
**#1509** (faixa do banco).
