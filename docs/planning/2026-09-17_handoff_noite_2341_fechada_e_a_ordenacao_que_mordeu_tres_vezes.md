# Handoff de 17/09 (fim da noite): a #2341 fecha, e a ordenacao de DDL mordeu TRES vezes

> **Nada aqui e medicao viva.** Carimbado em 17/09, ~21h50 UTC. **Re-meca antes de decidir.**
> Repositorio publico: este documento nao nomeia ninguem.

**Estado ao encerrar, para COMPARAR:** `main 0a6e3fdc` · **0 PRs abertas** · invariantes **0 de 44** ·
deploy da main **success** · 0 fixtures orfas · EF `send-notification-email` na **v40**.

---

## 1. Fechado nesta segunda metade

| PR | issue | o que |
|---|---|---|
| #2344 | #2341 | o gate do digest passa a enxergar job ausente |
| #2346 | — | regra MANDATORIA: assercao de guard amarra condicao ao resultado |
| #2339 | — | handoff da primeira metade |

### #2341 — o gate que nao podia reprovar

`get_digest_health` procurava 3 crons num `WHERE jobname IN (...)`, e um deles
(`weekly-card-digest-saturday`) foi removido em maio. **O `IN` nao devolve a linha que falta**, e
`max(coalesce(days,999))` so enxergava os jobs ENCONTRADOS — o 999 ("nunca rodou") era alcancavel
apenas por job que EXISTE. Job ausente era indistinguivel de job saudavel: **remover o digest do
membro passaria em verde.**

A expectativa virou DADO (`digest_cron_expectations`), com aposentadoria explicita e CHECK que
recusa aposentar sem motivo. A funcao faz `LEFT JOIN` **a partir da expectativa**, entao o job que
falta sobra como linha com `jobid NULL`.

**Exercido em producao com impersonacao, dentro de BEGIN/ROLLBACK:**

| cenario | sinal | missing_jobs |
|---|---|---|
| estado atual | `green` | `[]`, com o aposentado visivel como `aposentado` |
| expectativa vigente sem cron | **`red`** | o job, e estado `ausente` |

O segundo caso e exatamente o que a versao anterior devolvia verde. Rollback conferido por consulta
NOVA: 0 residuo.

**Por que so depois da #2286:** a funcao pinta verde com `member_digest_pending < 100`, e antes o
carimbo mentia — tudo carimbado, nada pendente. O sinal dizia verde pelo motivo errado.

### O guard #1822 reprovou minha tabela, e estava CERTO

Batizei uma coluna de texto livre como `purpose` — nome que promete enumeracao. O ratchet de "coluna
de estado sem dominio declarado" pegou. **A saida nao foi inventar um CHECK nem alargar a baseline:
foi corrigir o NOME** (`description`). Medido depois: a tabela sai do ratchet e o total volta a 56.

Mordida pequena e instrutiva: o teste que EXERCE o CHECK falhou com `PGRST204` (coluna inexistente)
em vez de violacao de CHECK — e foi o assert do **TIPO** do erro que discriminou. `assert.ok(error)`
teria afirmado que o CHECK barrou quando quem barrou foi o nome da coluna.

---

## 2. A LICAO CARA DO DIA: a ordenacao de DDL mordeu TRES vezes

Todas as tres sao a mesma regra, que eu conhecia, e que nao esta em nenhum lugar que me intercepte.

| # | o que fiz | custo medido |
|---|---|---|
| 1 | rodei `test:verdict` local durante o CI da PROPRIA PR, no mesmo banco | fixture orfa violou `M_application_score_consistency` e derrubou **15 assercoes** |
| 2 | criei branch da #2346 a partir da main DEPOIS de aplicar DDL | PR de 1 arquivo `.md` reprovou por tabela orfa |
| 3 | apliquei DDL com a `main` ainda sem o arquivo | **3 alertas do CI Monitor** (#2347/#2348/#2349) e producao ~1h desalinhada |

**O padrao:** `apply_migration` atinge o banco COMPARTILHADO na hora, e enquanto o `.sql` nao esta
no ref sob teste, aquele ref nao explica o estado do banco — **e o vermelho esta correto**. A `main`
nao e excecao disso, o que eu tratava implicitamente como se fosse.

⇒ **Recomendacao registrada, para decisao do dono:** a regra vive hoje so em memoria, recuperada por
relevancia. Duas camadas resolveriam, e **so a segunda e mecanismo**:
1. regra MANDATORIA no `CLAUDE.md` (sempre lido, diferente de memoria);
2. hook `PreToolUse` interceptando `apply_migration` para checar PR aberta antes de deixar passar.

Hoje **nada** impede aplicar DDL com a fila cheia. Ver #2340, que cobre o eixo local x CI.

---

## 3. O `browser_guards` cobrou pedagio de 2h em texto puro

Duas PRs de documentacao, **3 execucoes cada** para passar. Acumulado do dia: **4 falhas em 6
execucoes**, em diffs que nao podem afetar o `BaseLayout` (um `.md` novo e um `.md` alterado).
Sintoma sempre com a mesma raiz (`Unable to resolve BaseLayout.astro` no workerd) e pagina variando.

Isso derruba a leitura de "flake raro que o retry conserta": o re-run falhou duas vezes seguidas no
MESMO SHA. Detalhe medido: na PR que mexia em EF + migration + guards, o mesmo job passou de
primeira — **nao e o diff.**

⇒ **Recomendacao: rebaixar de `required` ate a investigacao fechar.** Reversivel num comando, e a
norma da casa e explicita: limpe o sinal, depois torne obrigatorio. Enquanto bloqueia, empurra para
o `--admin`, que e o que a governanca pos-p209 existe para evitar. Ver #2343 (com as 7 ocorrencias).

---

## 4. A PROXIMA COISA: #2345, e ela veio de um pedido do dono

Um lider avisou que nao recebeu o convite da reuniao de lideranca. Medindo, a lacuna do convite era
pequena (2 pessoas, lista mantida a mao), mas a investigacao achou algo maior:

| type de evento | futuros 90d | chega ao digest? |
|---|---:|---|
| `tribo` | 115 | sim, para a tribo |
| `comms` | 16 | sim, para a tribo |
| **`lideranca`** | **7** | **invisivel** |
| **`geral`** | **6** | **invisivel** |

**13 eventos futuros nao chegam a ninguem** — nao tem `initiative_id` (sao institucionais) e nao
estao na lista branca `('plenaria','webinar','workshop_geral')`. **Mesma classe da #2286**, na secao
vizinha da MESMA funcao: lista branca que nao cobre o que existe, e o que fica fora desaparece em
silencio.

**Nao automatizar pelo Google Calendar.** Medido: a service account tem escopo apenas `auth/drive`,
nao ha EF de Calendar, e o organizador da serie e conta **Gmail pessoal** — service account nao
impersona conta pessoal (delegacao existe so em Workspace). Exigiria refresh token pessoal de longa
duracao para resolver uma lista de convidados.

**O caminho e o canal proprio**, que ja existe inteiro: a fonte de verdade e `engagements` (atualiza
sozinha em entrada e desligamento — o problema real, com muitos dos dois), as reunioes ja estao
cadastradas ate dezembro, e o digest acabou de ser consertado. Falta o gate de audiencia:

| tipo | audiencia | medido |
|---|---|---|
| `geral` | todo membro ativo | 99 ativos, 99 optados |
| `lideranca` | quem tem papel de lideranca ATIVO | 25 pessoas |

⚠️ **Audiencia nao e autoridade, mas amplia exposicao.** Jogar `lideranca` na lista branca global
faria a reuniao de lideranca aparecer no digest de todos os 99. O gate tem de ser por papel,
derivado de `engagements`.

E o guard precisa perguntar **a volta** — todo `type` de evento vivo cai em alguma audiencia, ou
esta declarado como suprimido. Sem isso, o proximo tipo nasce invisivel do mesmo jeito.

---

## 5. Aberto, com diagnostico pronto

| # | o que | decisao pendente |
|---|---|---|
| #2345 | 13 eventos invisiveis no digest | implementar (proxima) |
| #2343 | flake do `browser_guards` | **rebaixar de required?** |
| #2340 | serializacao local x CI + cleanup de fixture | qual das duas camadas |
| #2342 | purgador carimba 1.993 como entregues | nomenclatura do campo |

Tambem sem issue, por decisao do dono: **nao existe automacao ligando "lider aprovado" ao convite da
serie** — a lista e manual. A #2345 resolve o AVISO; o convite em si continua a mao.

---

## 6. Comandos para re-medir

```bash
git fetch --all && git log --oneline -1 origin/main
gh pr list --state open && gh issue list --state open --limit 8
npm run test:structural     # ANTES de abrir PR
# NAO rode test:verdict enquanto o CI da sua propria PR estiver no ar (licao 2.1)
```

```sql
-- #2345: os tipos invisiveis continuam invisiveis?
WITH tipos_no_digest(t) AS (VALUES ('plenaria'),('webinar'),('workshop_geral'))
SELECT e.type, count(*) AS futuros_90d,
       count(*) FILTER (WHERE e.initiative_id IS NULL) AS sem_iniciativa,
       (e.type IN (SELECT t FROM tipos_no_digest)) AS na_lista_branca
FROM public.events e WHERE e.date BETWEEN CURRENT_DATE AND CURRENT_DATE + 90
GROUP BY e.type ORDER BY 2 DESC;

-- #2341: o gate continua enxergando?
WITH procurados AS (SELECT jobname, retired_at FROM public.digest_cron_expectations)
SELECT p.jobname, (p.retired_at IS NOT NULL) AS aposentado, (j.jobid IS NOT NULL) AS existe
FROM procurados p LEFT JOIN cron.job j USING (jobname) ORDER BY 1;
```

---

## 7. Prompt de arranque sugerido

> Ler `docs/planning/2026-09-17_handoff_noite_2341_fechada_e_a_ordenacao_que_mordeu_tres_vezes.md`.
> A tarefa e a **#2345**: `lideranca` e `geral` entram em `events_upcoming` com **gate de audiencia
> por papel** (derivado de `engagements`, nao lista branca global — sao 25 com papel de lideranca
> contra 99 ativos), mais o guard que pergunta a VOLTA: todo `type` vivo cai em alguma audiencia.
> **Antes de aplicar DDL: `gh pr list --state open` tem de estar VAZIO** — a ordenacao mordeu tres
> vezes em 17/09 (secao 2), inclusive contra a propria `main`.
