# Prompt de arranque — depois do arco de consentimento (08/08/2026)

> Colar depois do `/clear`. **Effort: `xhigh`.**
> Handoff completo: `docs/planning/2026-08-07_handoff_arco_consentimento_e_acesso.md`.
> `main` em **`6481534c`**.

---

## Regra zero

**Nada deste documento pode ser recitado.** Re-medir com tool call na mesma volta antes de qualquer
decisão. O padrão que custou três leituras erradas na sessão anterior: **número certo, significado
errado**. O instrumento é barato — rode o grupo de controle, ou pergunte *de quem é este valor* e
*em que ponto do processo essa população está*, em vez de *quantos são*.

Dois exemplos da sessão passada, ambos inverteram a decisão:
- "3 candidatos impedidos de consentir" era verdade — e os 3 já tinham sido avaliados E
  entrevistados, então a análise de IA não tinha finalidade restante. A recomendação virou **não**
  reemitir.
- "4 observadores nunca avaliaram" era verdade — e era por **hábito**, não por trava: nenhuma RPC
  olhava o papel. O menu novo ia transformar isso em convite.

---

## Não re-litigar (fechado e em produção)

- **#1640, #1642, #1649, #1666, #1665, #1423, #1591** fechadas. `#1641` fechada por decisão do PM
  (não reemitir), com a medição registrada na issue.
- O consentimento de IA agora tem **ledger auditável** (`consent_records` + `evidence`), o comitê
  **alcança** `/admin/selection` e `/minhas-avaliacoes`, e **observador não avalia**.
- Migrations `20260807000400`–`001000` aplicadas, registradas e com arquivo no checkout.

---

## ⚠️ ANTES DE TUDO, SE FOR MEXER NO PR #1673

Lane separada (worktree), com prompt próprio:
**`docs/planning/2026-08-07_PROMPT_ARRANQUE_MAIN_LANE_1673.md`** — ler antes de qualquer coisa ali.
Objetivo: QA e merge do #1673.

O branch **local** tem um commit órfão por cima do head real do PR:

```
origin/fix/youtube-playlists-ciclo4-gerais-e-lideranca → 55bb9265   ← head REAL
local /fix/youtube-playlists-ciclo4-gerais-e-lideranca → 08a17f2f   ← órfão
                                                          55bb9265
```

`08a17f2f` é o commit do #1666 da sessão de 07/08: caiu ali porque a árvore de trabalho estava com
aquele branch em check-out. **O conteúdo já está na `main`** (squash `49a8586f`), então é resíduo,
não trabalho pendente.

1. Trabalhe **sempre a partir de `origin/`**, nunca do branch local.
2. Atualize o PR por **MERGE, nunca rebase** — force-push está bloqueado nesta máquina.
3. **NÃO empurre o `08a17f2f`**: apareceria como diff duplicado.

Estado medido em 07/08 à noite: head `55bb9265`, `mergeable`, **`validate` fail**, outros 8 gates
verdes. ⚠️ **Classificar o vermelho, não presumir** — na sessão anterior houve três classes de
vermelho alheias ao PR (#1649, esm.sh fora do ar no `deno`, e timeout do passo `Smoke Test Routes`).
Comparar com um commit vizinho que passou é o instrumento mais barato.

---

## Ordem sugerida (lane LGPD/seleção)

### 1. Confirmar com gente (não dá para medir por SQL)
As RPCs resolvem por `auth.uid()` e o conector MCP passa como o Vitor. Pedir a um **avaliador** que
abra a plataforma logado: deve ver *Minhas Avaliações* (20 pendentes) e *Processo Seletivo*. Um
**observador** deve ver só o segundo. Se vier diferente, é bug medido — e aí sim investigar.

### 2. #1679 — curadoria (investigação, não precisa de decisão)
37 submissões, 7 publicações, **zero** revisões registradas, **zero** portadores de `curator`.
⚠️ **NÃO confundir com o comitê de SELEÇÃO.** São corpos e domínios distintos. A confusão já
aconteceu; o aviso está no topo da issue.
Declarar qual das leituras é: curadoria fora da plataforma, ou algo impedindo o uso.

### 3. #1643 — outros consentimentos "opcionais" com gate escondido
Método na issue, com uma **terceira classe** acrescentada: além de "gate de tratamento" (ok) e
"gate de avanço" (defeito), procurar **"afirmação incondicional sobre tratamento condicional"** —
foi o caso do `peer_review_request`, que dizia "Pré-análise IA concluída" para candidatura sem
análise.

### 4. Resíduos, se o PM quiser fechá-los
- exigir evidência no consentimento de IA (`RAISE`), depois de confirmado o front no ar
- observador por URL direta ainda vê a fila com botão que recusa
- escapador parcial em 3 arquivos de teste pré-existentes

---

## Armadilhas medidas (07/08)

- **Serialização não é sobre DDL, é sobre REGISTRAR VERSÃO.** Qualquer `migration repair` deixa
  vermelho todo branch sem aquele `.sql`, mesmo que o conteúdo tenha sido `UPDATE` de dado.
  **Antes de aplicar, olhe os PRs abertos.**
- **`gh pr checks` mente por omissão.** Um gate na fila do grupo de concorrência ainda não registrou
  check-run, então "todos os reportados passaram" é vacuamente verdadeiro. **Monitorar por RUN.**
- **Função de 19 KB: NÃO transcrever.** Aplicar por `replace` ancorado sobre `pg_get_functiondef`
  com `RAISE` se a âncora não casar, e extrair o corpo vivo para o arquivo **por script** (o script
  precisa rodar de dentro do projeto para achar `node_modules`).
- **`apply_migration` cria phantom row** — deletar (1 por chamada) e `migration repair` no
  timestamp sintético.
- **`Closes #a, #b`** fecha só a primeira; cada número precisa da palavra-chave.
- **Não rodar `npm test` com CI em voo** — **gatear**, não só imprimir o número.
- **Guard ancorado num ARQUIVO não observa o mundo**: fica verde com o mecanismo inerte e depois de
  removido. Camada B no corpo vivo.
- **Mutação é obrigatória**, e ela pega asserção frouxa própria: `INSERT INTO public.consent_records`
  casava `consent_records_XX` como substring.

## Regras da casa

- Merge à `main` é da sessão main; lane leva o PR até verde e para.
- Commit: `Assisted-By:`, nunca `Co-Authored-By`.
- Repo **PÚBLICO**: nenhum candidato ou membro nomeado, só contagens.
