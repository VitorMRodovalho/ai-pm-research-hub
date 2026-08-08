# Prompt de arranque - depois do #1636 e do plano por ondas

> Colar depois do `/clear`. **Effort: `xhigh`.**
> Handoff: `docs/planning/2026-08-08_handoff_1636_fechado_plano_por_ondas_e_pii.md`.
> **O plano por ondas vive em `~/.claude/plans/` (fora do repo). Ler antes de escolher trabalho.**
>
> ⚠️ Existem dois arranques homonimos de 09/08 ja **consumidos**. Este e o que vale.

---

## Regra zero

**Nada deste documento pode ser recitado.** Re-medir com tool call na mesma volta. Os padroes que
custaram caro, agora cinco:

- **verde sem significado** (o gate passou, o efeito nao aconteceu)
- **numero certo, significado errado** (a query estava certa, a populacao nao era a da pergunta)
- **vermelho sem defeito** (o gate falhou por infraestrutura, e o dedo aponta para a mudanca nova)
- **verde por vacuidade** (o teste nao exerceu nada; `skip` e ramo vazio leem como verde)
- **medido no lugar errado** (a varredura certa sobre o recorte errado: `docs/` em vez de tudo o
  que o `git ls-files` devolve. Custou um numero 3x menor do que a realidade, nesta sessao)

---

## Estado

| item | estado |
|---|---|
| `main` | **`6b33bd01`** |
| **#1636** | fechada (PR #1690). A torneira fechou: **5 linhas por rodada de CI → 0**, medido |
| **#1692** | PR de remocao de PII - mergear quando verde |
| **#1691** | 35 superficies de teste que ainda escrevem em prod |
| **#1693** | politica de dado pessoal + guard + divida do historico |
| **#1694** | scrub de nomes (1.566 ocorrencias, 336 arquivos) |

⚠️ **`Fecha #N` NAO fecha issue.** So `close/closes`, `fix/fixes`, `resolve/resolves`. O #1636
ficou aberto depois do merge e teve de ser fechado a mao.

⚠️ **Nao commitar docs na `main` com um PR seu aberto** - move a `main`, o PR fica atras, e
`gh pr update-branch` recomeca todos os gates.

---

## ⚠️ Pendente e depende do PM, nao de codigo

1. **Reescrita de historico.** O #1692 limpa o HEAD; tudo segue nos commits antigos. Force-push e
   bloqueado pelo harness. A reescrita de 04/07 orfanou associacao commit-PR e gerou 69 falsos
   positivos no audit de bypass (#1142) - avisar o audit antes.
2. **Notificacao LGPD Art. 48** - nao avaliada. A **#334** ja existe e esta `status:blocked`.

Detalhe do incidente **nao esta no repo** (ele e publico). Esta na memoria da sessao.

---

## Ordem sugerida

### 1. Mergear o #1692 e commitar os docs
Nao mergear com CI de outro PR em voo (satura o `wait-for-db-lane`, #1509). Depois de empurrar
correcao num PR, **cancelar os runs do SHA velho**.

### 2. Retomar a Onda 0 - trilhas (a) e (b)
A trilha (c), da PII, esta entregue.

**(a) Estado.** **30 das 195** abertas sao citadas em **PR ja mergeado** - parte e a classe do
"`Fecha #N` nao fecha". Conferir uma a uma. Depois, as 11 `status:blocked`.

**(b) Agrupamento.** Sete clusters candidatos, no plano. Regra: uma epica so existe se tiver
**causa comum**, nao tema comum. O teste e "consertar a causa fecha as filhas?".

### 3. Onda 0.5 - superficie publica
README parado em 17/07: 52 vs **86** membros, 7 vs **12** tribos, 209 vs **493** eventos, 5.306 vs
**6.592** testes, 342 vs **395** registros de tool, 9 vs **13** posts de blog.

⚠️ **O "$0 monthly cost" esta CORRETO** - o mantenedor absorve o custo e o PMI/capitulos pagam
zero. O ajuste e **explicitar de quem e o zero**, nao corrigir o numero.

Tambem parados: blog (ultimo post 18/07), repo publico `nucleo-ia-gp/frameworks` (14/06),
`SITE_MAP.md` (04/06). O `wiki` (03/08) e o `wiki_pages` (151 paginas) estao saudaveis.

### 4. Onda 1 - presenca
Epica **#1652**, mas **#1660 e a raiz e esta fora dela**: `mark_member_present(false)` **APAGA a
linha** desde 19/05. Medido: `attendance` tem 2.028 linhas, 1.934 presencas e **3 faltas simples**
na base inteira, 1.723 (85%) sem `marked_by`. Ordem de dependencia: **#1653** (alivio curto) →
**#1660** + **#1657** (modelo de dados) → **#1656** (contrato) → **#1655** + **#1654** (superficie).

---

## Ferramentas desta safra

- `tests/helpers/selection-fixtures.mjs` - candidatura sintetica na forma que o gate exige. **Use
  isto** em vez de escolher alvo por predicado sobre producao.
- `tests/helpers/rpc-call-scanner.mjs` - distingue **chamar** uma RPC de **menciona-la** num literal.
- `tests/contracts/pii-nenhum-dado-pessoal-versionado.test.mjs` - guard de PII, allow-list.

Armadilhas ja pagas, que voltam em qualquer trabalho parecido:

1. coluna **derivada** tem de ser gravada **por ultimo** (criar os filhos dispara o recompute)
2. vinculo **polimorfico** (`source_id` sem FK) **escapa do CASCADE**
3. o registro "mais recente" pode nao ter a **capacidade** que o teste precisa
4. **`.gitignore` nao desrastreia** o que ja esta rastreado
5. **`grep -I` ignora binario** - PDF e docx carregam texto que a varredura nao ve

---

## Regras da casa

- Merge a `main` e da sessao main; lane leva o PR ate verde e para.
- **Force-push bloqueado pelo harness.** Atualizar branch por `git merge origin/main`.
- Conflito na linha do `test` no `package.json`: resolver **por script**.
- Commit: `Assisted-By:`, nunca `Co-Authored-By`.
- Repo **PUBLICO**: nenhum candidato ou membro nomeado, so contagens. **E nao descrever onde dado
  pessoal esta no historico** enquanto a reescrita nao acontecer.
- Nao rodar `npm test` com CI em voo. **Monitorar por RUN**, nao por `gh pr checks`.
