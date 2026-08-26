# Handoff 26/08 (noite) — #2012 fechada, e o relógio da sexta re-medido

**Estado:** branch `fix/2012-quem-conduz-registra`, **PR #2015**, migration `20260826212137`
aplicada com a fila vazia, zero bypass. Quatro commits: o conserto, a regeneração do manifesto do
MCP (drift real que a CI pegou), o scrub de nomes nos comentários e a correção da SPEC.

---

## 1. O relógio da sexta: defusado, mas não pelo desenho

O arranque mandava checar primeiro se a entrevista do incidente tinha sido pontuada antes das 11h
de 29/08. **Foi.** Medido em 26/08 21h14 UTC: a candidatura está `final_eval`, com
`interview_score = 84`, e a entrevista tem `conducted_at` de 26/08 20:35 UTC.

O cron `process_pending_reschedule_nudges` filtra por
`a.status IN ('interview_pending','interview_scheduled')` — li o corpo vivo, não o comportamento
esperado. `final_eval` está fora, então **o disparo de 29/08 não a alcança**.

⚠️ Ela continua com `interview_status = 'needs_reschedule'`. Escapa **pelo status**, não porque o
campo tenha sido limpo. É exatamente o acidente que a #2013 nomeia no item 4.

## 2. #2012 — o que entrou

`schedule_interview` ganha um **terceiro caminho de autoridade**: quem é do comitê **do ciclo**,
com `can_interview` e papel que decide, pode criar o registro da entrevista **que conduziu**,
informando **apenas a si próprio** como entrevistador. Desenho da #1972, do outro lado do fluxo:
a designação é criada, o portão não é contornado.

E a **recusa por autoridade passa a existir no log**: virou envelope `{success:false}` com código
próprio **P0005 / `UNAUTHORIZED_NOT_INTERVIEW_AUTHORITY`**, em vez de `RAISE EXCEPTION` antes do
primeiro `_log_gate_attempt`.

### O achado que mudou o desenho

O aceite da issue pedia "membro do comitê do ciclo com `can_interview`". Medido em 26/08:

| | |
|---|---:|
| linhas de `selection_committee` | 13 |
| ... com `can_interview = true` | **13** (4 evaluator, 4 lead, 5 observer) |
| ... com `can_interview = false` | **0** |

**A coluna é rótulo, não autoridade.** Alargar só por ela entregaria a criação do registro aos 5
observadores — e observador, nesta plataforma, é leitura (`isObserver` bloqueia a pontuação; o eixo
`operate_selection` do #1838 exclui exatamente esse papel). Por isso o predicado pede as **duas**
coisas: `can_interview` **e** papel diferente de `observer`, com o domínio vindo do catálogo
(`selection_committee_role_check`).

Efeito no `cycle4-2026`: **2 pessoas → 3**. Os 4 observadores seguem fora.

### O que o alargamento não faz

- Não agenda entrevista de terceiro: exige lista de **um**, e esse um é o chamador.
- Não alcança status fora da fase de entrevista: o caminho novo **nunca** recebe o bypass, então
  P0002/P0003 e a allow-list P0004 do #472 corr.3 continuam valendo integralmente para ele.
- Não afrouxa quem já passava: precedência `lead > manage_platform > self`.

### Provado no corpo vivo

`BEGIN/ROLLBACK` num único `execute_sql`, impersonando, contra candidatura **sintética**:

| caso | resultado |
|---|---|
| avaliador do comitê, lista de si próprio | `success:true`, `authority_path: self_interviewer`, `gate_bypassed:false` **mesmo pedindo bypass** |
| o mesmo avaliador nomeando terceiro | `success:false`, **P0005** |
| observadora com `can_interview=true`, lista de si própria | `success:false`, **P0005** |
| `gate_attempts` dentro da transação | as **três** tentativas registradas |

`ROLLBACK` conferido com consulta **nova**: zero sobreviventes; `gate_attempts` segue em 37.

**Antes:** 37 tentativas de `schedule_interview` na tabela, **todas** `gate_passed=true`, **zero
recusas** em toda a vida dela. Não por falta de código: `RAISE` e `INSERT` na mesma transação, e a
linha morria com a exceção que deveria explicar (mesma causa da #1594).

## 3. Duas coisas que a CI ensinou nesta PR

- **`src/lib/mcp-manifest.json` é derivado do `index.ts`.** Mudei duas descrições de ferramenta e o
  job `structural` reprovou por drift de ferramenta. `node scripts/generate-mcp-manifest.mjs`
  resolve. **Toda mudança em descrição de tool do MCP pede a regeneração no mesmo commit.**
- **`?head_sha=` exige o SHA de 40 caracteres.** `gh api ".../actions/runs?head_sha=2901708e"`
  devolveu `total_count: 0` e eu li como "o GitHub nunca despachou workflow para este commit" — a
  assinatura da queda do Actions. **Os 7 runs existiam**, criados 40s depois do push; a listagem
  **sem filtro** os mostrou na hora. Filtro que não casa devolve zero, não erro. Use
  `gh pr checks <N>`, que resolve o head sozinho.
- **Reabrir a PR re-despacha TODOS os workflows no mesmo SHA.** Com `cancel-in-progress: false`
  (#1505) isso **dobra o relógio** em vez de encurtá-lo: ficam dois conjuntos de runs, serializados
  pelo grupo de concorrência. E não dá para acelerar cancelando o antigo — `validate` **escreve em
  produção**, e matá-lo no meio deixa fixture do #1636 pela metade no banco, que é exatamente por
  que o `cancel-in-progress` é `false`. O remédio "fechar e reabrir" vale para workflow que
  **nunca foi criado**, não para workflow lento.
- **`check-invariants` reprovou por contenção, não por código.** A violação de
  `M_application_score_consistency` apontava para `b9aaa0e8-…`, que é uma **fixture sintética do
  #1636** (`__1636_synthetic__ rescue-p0002`), com `updated_at` dentro da janela do job `validate`
  **irmão, do mesmo run**. O `wait-for-db-lane` serializa runs, e não jobs do mesmo run. Vermelho
  de invariante cujo `sample_id` é fixture sintética viva **não é veredito sobre o código** — leia
  o nome da linha antes de caçar causa.
- **E não "resolva" isso cancelando o run.** Cancelei aquele `validate` para liberar a faixa e a
  fixture ficou **órfã em produção** — o `cleanup()` do helper roda no fim do teste e nunca chegou
  a rodar. 34 min depois ela passava do `GRACE_MINUTES` de 30 e teria reprovado o guard do #1636 no
  run seguinte, por motivo alheio à PR. Limpa na ordem do helper (`onboarding_tokens` →
  `selection_dispatch_url_log` → `onboarding_progress` → `admin_audit_log` → candidatura, o CASCADE
  leva o resto) e conferido em consulta nova: **0 fixtures vivas, 0 invariantes violadas**.

## 3b. A SPEC afirmava metade da verdade desde 05/08

`docs/specs/SPEC_INTERVIEW_BOOKING_INTEGRITY.md` §4.0 diz, desde a correção da #1594, que a recusa
em `schedule_interview` virou retorno estruturado. Era verdade para os gates de **fluxo**
(P0002/P0003/P0004) e **falso** para o de **autoridade**, que seguia levantando exceção antes do
primeiro log. Corrigido no mesmo PR, com bloco de correção datado — e o guard da #2012 agora
afirma **a spec** também, não só o código (a classe do #1987: guard de código verde deixa o doc
normativo apodrecer).

## 4. PII: nomes em repo público

⚠️ Escrevi o caso com nome e sobrenome do entrevistador e da candidata nos comentários da migration
e do guard, e no corpo da PR. **O repo é público**, e há decisão do PM de 08/08 para scrub de nomes
de membros e candidatos, preservando o PM e cargos institucionais. Corrigido no commit `dfdb142f`:
trocados por papel. Os nomes estavam **só fora do bloco `$function$`** — md5 do corpo segue
`2157e4da…`, idêntico ao vivo, sem DDL a reaplicar.

**Fica pendente e é decisão do PM:** as **mensagens dos dois primeiros commits** da branch ainda
carregam os nomes. Limpar isso exige `git push --force` na branch (não na main), que precisa de
autorização explícita. Alternativa sem force-push: mergear com **squash** passando um `--body`
explícito, que é o que mantém os nomes fora da main — a branch some no delete, mas os objetos
seguem alcançáveis pelas refs da PR.

E o padrão é maior que esta PR: a migration da #1997, mergeada ontem, também narra o caso com
nomes. A memória `project-incidente-pii-repo-publico-2026-08-08` mede 1.566 ocorrências em 336
arquivos e classifica o scrub como decisão tomada, não executada.

## 5. #2013 — o item 4 sozinho não esvazia o balde (medido, comentado na issue)

| grupo | quantas | entra no filtro do cron |
|---|---:|---|
| entrevista **concluída e pontuada** | **3** | não (2 `approved`, 1 `final_eval`) |
| sem entrevista concluída (4 sem entrevista, 1 `cancelled`) | **5** | **sim** |
| `rejected` de junho | 1 | não |

- Limpar `interview_status` na pontuação toca **3 linhas**, e **nenhuma delas recebe e-mail hoje**.
  O ganho é higiene e tirar a proteção do acidente do filtro. Não é ganho de cobrança.
- As **5** que estão sendo cobradas não têm entrevista concluída: para elas `needs_reschedule` é o
  valor **certo**, e o item 4 não as alcança nem deveria.
- **O que interrompe a cobrança são os itens 1 e 3** (teto com escalonamento, e roteamento por
  `open_count`) — os que pedem decisão do PM.
- Próximo disparo às 5: **29/08 14:00 UTC (11h BRT)**.

## 6. Fila daqui

`#2013` (itens 1 e 3 pedem decisão; o 4 é barato e mexe em `schedule_interview` de novo — a
próxima migration que recriar a função herda o guard da #2012, que afirma o corpo **vigente**, não
um arquivo fixo) · `#1995` · `#1996` · `#1999` · `#2001` · `#2004` · `#2009` · `#2010` · `#2011`.

Continua valendo: **#2011** (37 links de e-mail no domínio pessoal) contraria a diretiva de 03/07
de usar `nucleoia.pmigo.org.br` nas comunicações.
