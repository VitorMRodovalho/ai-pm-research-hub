# Prompt de arranque - depois do #1643 e da faixa de banco

> Colar depois do `/clear`. **Effort: `xhigh`.**
> Handoff completo: `docs/planning/2026-08-08_handoff_1643_fechado_e_a_faixa_de_banco.md`.
> `main` em **`dea130d7`**.
>
> ⚠️ Existe um arranque anterior homônimo (`2026-08-09_PROMPT_ARRANQUE.md`), já **consumido**.
> Este é o que vale.

---

## Regra zero

**Nada deste documento pode ser recitado.** Re-medir com tool call na mesma volta. Os padrões que
custaram caro nas últimas sessões, agora três:

- **verde sem significado** (o gate passou, o efeito não aconteceu)
- **número certo, significado errado** (a query estava certa, a população não era a da pergunta)
- **vermelho sem defeito** (o gate falhou por infraestrutura, e o dedo aponta para a mudança nova)

Depois de consertar, verifique o **efeito**. Antes de citar um contador, pergunte **de quem é este
valor**. E diante de um gate vermelho, pergunte **se ele chegou a rodar** antes de procurar defeito.

---

## 🔴 A armadilha nova, que eu mesmo criei na sessão passada

O CI serializa o acesso ao Postgres de produção (`wait-for-db-lane`, do #1509): **um job por vez**,
espera 900s e então **falha em vez de rodar concorrente**.

**Não mergear com a CI de outro PR em voo.** A regra da casa já dizia para não rodar `npm test`
local com CI em voo; o irmão dela é este, e o sintoma é pior: o `check-invariants` fica vermelho
**em PR inocente e na `main`**, parecendo regressão de schema.

Diagnóstico em um comando, sem esperar CI:

```sql
SELECT * FROM public.check_schema_invariants();  -- 43 invariantes, baseline 0 em todas
```

Se o log do job disser `faixa ocupada por ... - aguardando 15s` até `esperei 900s`, é fila, não
defeito. Conserto: esperar a faixa esvaziar e `gh run rerun <id> --failed`, **um de cada vez**.

⚠️ **`gh run list --limit N` mente por omissão** - mostrou "faixa livre" com um run meu em voo.
Filtrar por status explicitamente:

```bash
gh run list --limit 30 --json databaseId,status,workflowName,headBranch \
  --jq '.[] | select(.status=="in_progress" or .status=="queued" or .status=="pending")'
```

---

## Não re-litigar (fechado e em produção)

- **#1643 fechada.** Três classes varridas, a inversa medida (0 de 170), `sign_proposer_consent`
  classificado fora da família. Sweep completo na issue.
- **#1647 mergeado** (`dea130d7`). Estava vermelho por estar atrás do `main`, não por defeito.
- **#1682** fechada pelo #1688; **#618** fechada pelo #1684.
- **Decisões do PM de 08/08** seguem valendo: `auth` fora do dump; PITR não, dump diário; 4 tokens
  do #1636 registrados e **não** revogados.

---

## Ordem sugerida

### 1. PR #1689 - só falta a decisão de merge
Aberto, `CLEAN`, **11/11 verde**. Guarda da terceira classe do #1643 (teste + `package.json`, sem
DDL, não serializa PR nenhum). Re-conferir a cor antes de mergear, não recitar daqui.

### 2. 🔴 Personas sintéticas (#1636) - o único com dano EM CURSO
Medido em 08/08: a suíte emitiu **4 tokens de agendamento reais** (run `31144140275`), vivos até
**21/08**, `access_count` 0. Cada rodada de CI que exercer aquele caminho cria token real sobre
candidatura real.

Semear personas sintéticas na base restaurada (`scripts/pull-backup-local.sh --restore`, ~15s) e
apontar a suíte DB-aware para ela. Ganha três coisas: para de tocar gente real, o teste deixa de
depender de **quem** ocupa o papel, e some a PII do laboratório.

⚠️ A suíte também escreve `members` - foi assim que nasceram os 10 "membros sumidos" que se
revelaram fixtures. O mesmo trabalho cobre as duas superfícies.

### 3. Resíduos escolhidos, ainda intocados
- observador por URL direta ainda recebe a fila em `get_my_pending_evaluations`
- `route-acl.test.mjs` **reimplementa** o `canAccess` em vez de importar `getItemAccessibility`
- exigir evidência no consentimento de IA (`RAISE`), depois de confirmado o front no ar

---

## Ainda em aberto, sem decisão

- Os quatro defeitos recortáveis do **#1679** viram issues?
- R2 sem lifecycle (~5 GB/ano). Se ganhar poda, a retenção de 30 do artefato precisa subir.
- Os 4 tokens do #1636 expiram sozinhos em **21/08**. Se a decisão mudar, é antes disso.

---

## Regras da casa

- Merge à `main` é da sessão main; lane leva o PR até verde e para.
- **Force-push está bloqueado pelo harness.** Atualizar branch de PR por `git merge origin/main`
  (o merge final é squash, a história do branch não sobrevive).
- Conflito na linha do `test` no `package.json`: resolver **por script**, tomando a lista do `main`
  e reinserindo o arquivo do branch. Transcrever à mão é como se perde um teste calado.
- Commit: `Assisted-By:`, nunca `Co-Authored-By`.
- Repo **PÚBLICO**: nenhum candidato ou membro nomeado, só contagens.
- **Postura de backup não vai para issue pública.**
- Não rodar `npm test` com CI em voo. **Monitorar por RUN**, não por `gh pr checks`.
