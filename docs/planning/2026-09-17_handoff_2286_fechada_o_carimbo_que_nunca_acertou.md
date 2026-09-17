# Handoff de 17/09 (noite): a #2286 fecha, e o carimbo do digest nunca tinha acertado

> **Nada aqui e medicao viva.** Carimbado em 17/09, ~15h BRT. **Re-meca antes de decidir.**
> Repositorio publico: este documento nao nomeia ninguem. Casos individuais vivem nos cards e issues.

**Estado ao encerrar, para COMPARAR:** `main d78998a6` · **0 PRs abertas** · issue **#2286 fechada** ·
invariantes **0 de 44** · EF `send-notification-email` na **v40**.

---

## 1. O que foi fechado: #2286 (PR #2337)

A issue dizia "76 de 78 notificacoes de 2 tipos". **Medido na fonte viva:** das **2.661** que o
proprio digest carimbou como entregues, **ZERO** eram de um tipo que o e-mail desenha. Nao e "97%
de erro" — o carimbo do digest **nunca acertou uma vez** em toda a vida do mecanismo.

A atribuicao importa e levou uma medicao extra. Das 4.388 linhas carimbadas em `digest_weekly`:

| origem do carimbo | linhas | das quais nao chegavam ao e-mail |
|---|---:|---:|
| o proprio digest | 2.661 | **2.661** |
| `purge_stale_digest_notifications_cron` (30 dias, por idade) | 1.727 | 1.622 |

Cruzamento feito por `digest_batch_id` contra os lotes do `admin_audit_log`. **Sem essa separacao
o numero vira acusacao errada**: o purgador carimba sem entregar por PROPOSITO declarado.

### As tres camadas, e a do meio nao estava na issue

| camada | tipos | carimbadas |
|---|---:|---:|
| sem secao nenhuma na RPC | 27 | 1.277 |
| **secao na RPC e NENHUM bloco no renderizador da EF** | 2 | **3.006** |
| carimbo como SELECT paralelo as secoes | — | a classe inteira |

`new_assignments` e `attendance_reminders_pending` nasceram em **p95 #99 (1A/1B)** exatamente para
tornar visiveis os dois maiores tipos do conjunto. O renderizador **nunca** recebeu os blocos: as
duas chaves tinham **ZERO ocorrencia no repositorio inteiro** (medido com controle positivo nas 7
secoes que existiam e controle negativo com uma chave inventada). O carimbo, esse, foi ESTENDIDO
para consumi-las, com janela de 14 dias.

Pano de fundo que fecha o diagnostico: o **ADR-0022 declara 12 tipos** como `digest_weekly`; o
e-mail entregava **2**. O documento normativo estava sendo desmentido pela implementacao, e nenhum
guard perguntava pela volta.

### O conserto ataca a classe

UMA classificacao decide ao mesmo tempo em que secao a notificacao aparece e se o id entra no
carimbo. O `ELSE` do `CASE` recolhe o que nao casou com lista branca nenhuma ⇒ **um tipo novo
aparece por DEFAULT em vez de sumir por omissao**, e suprimir volta a exigir decisao registrada no
catalogo (`delivery_mode='suppress'`). Carimbar virou **consequencia** de renderizar.

**Prova viva** (RPC exercida como o proprio membro, com impersonacao): 13 ids montados, 13
carimbados, **0 carimbados sem secao e 0 montados sem carimbo** — diferenca simetrica zero nos dois
sentidos, com 5 itens na secao de sobra como controle de que nao era vacuo.

A sobra **nao tem piso de data, de proposito**: 24 das 82 pendentes ja tinham envelhecido para fora
da janela movel e nao entrariam em digest nenhum. Quem impede repeticao e o carimbo, nao a janela.

**O passado nao foi reprocessado.** As linhas ja carimbadas seguem carimbadas — descarimbar em massa
despejaria o acervo. Impacto do lado de quem recebe, medido: **82 pendencias, 31 destinatarios,
media 2,6 itens, pior caso 13** (99 membros optados).

### Ordem de publicacao, que nao foi acidental

A PR tinha **dois veiculos**: migration (banco) e EF (deploy a mao). A EF e a metade **LEITORA** e
saiu PRIMEIRO, antes da migration — ela tolera secao ausente, a RPC nao poderia ter secao sem
leitor. Efeito colateral bom: a RPC antiga JA produzia as duas secoes orfas, entao o digest de
sabado passou a mostra-las no instante do deploy da EF, antes da migration.

---

## 2. A PROXIMA COISA: `get_digest_health`, e agora ela SIGNIFICA algo

Era a ordem do handoff anterior e a medicao confirmou o porque. A funcao le
`member_digest_pending` (pendentes de `digest_weekly`) e pinta verde com `< 100`. **Antes da #2286
essa metrica era baixa porque o carimbo mentia**: tudo era carimbado, logo quase nada ficava
pendente. O sinal dizia verde pelo motivo errado. Instrumentar o canal antes de consertar daria um
verde sem significado — e daria.

Dois defeitos medidos no corpo vigente, ambos da familia "o gate nao pode reprovar":

1. **Cega a job ausente.** Ela procura 3 jobs por nome
   (`send-weekly-member-digest`, `send-weekly-leader-digest`, `weekly-card-digest-saturday`) e o
   terceiro **nao existe mais** — foi removido de proposito em maio (`p89_cron_audit_fixes`) porque
   duplicava o digest do membro. `WHERE jobname IN (...)` simplesmente **nao retorna a linha que
   falta**, e `max(coalesce(days,999))` so enxerga os jobs ENCONTRADOS. O 999 ("nunca rodou") e
   alcancavel apenas por job que EXISTE e nunca rodou. ⇒ "job ausente" e indistinguivel de "job
   saudavel".
2. **A nota mente sobre a cadencia.** Diz "Weekly Saturday crons", e o
   `send-weekly-leader-digest` roda **segunda** (`0 12 * * 1`). Medido.

⇒ O conserto e o de sempre nesta casa: **derivar do catalogo em vez de farejar nome**, reportar
TRES estados (ausente / presente-e-silencioso / saudavel), e provar por mutacao que o gate reprova
quando um job desaparece.

---

## 3. Licoes de processo desta sessao (tres mordidas, todas minhas)

1. **Rodei a suite local durante o CI da PROPRIA PR, sobre o mesmo banco de producao.** A rede da
   maquina caiu no meio (7 timeouts), matou o `cleanup()` da fixture e deixou uma candidatura
   sintetica orfa. Ela violou `M_application_score_consistency` e derrubou **15 assercoes** no CI,
   em `validate` e `check-invariants`. **As duas camadas de serializacao nao cobrem esse eixo:**
   `with-db-lease` protege sessao local × sessao local, `wait-for-db-lane` protege job × job. Nada
   protege **local × CI**. Resíduo removido pelo id exato, invariantes de volta a 44/0, re-run verde.
2. **`pkill -f` casou o proprio shell que o executava**, porque a linha do meu comando continha o
   literal `supabase functions deploy`. O bracket `[s]upabase` nao salva quando o texto aparece
   duas vezes na linha — e mata o deploy antes de ele comecar. Conte por `comm`, e separe o kill do
   comando que menciona o alvo.
3. **O guard que escrevi passava com o bloco REMOVIDO.** `ef.includes('other_notifications')`
   casava com o **comentario que eu mesmo escrevi** para explicar a secao. Mesma classe do
   `/is_visitor/` solto na #2335. Consertado com `maskJsComments`; as 5 mutacoes reprovam e o
   controle sem mutacao passa. **Sem o teste de mutacao eu teria mergeado um guard decorativo.**

Tambem pego pela maquina, e nao pela memoria: o meta-guard **#1932** reprovou porque o guard do
**#1470** fixava a migration de agosto e passou a afirmar sobre texto morto no instante em que a
funcao foi redefinida. Migrado para `latestFunctionCapture`. Era a licao 1 do handoff da manha.

### Ambiente: o bundler local do Docker esta com a rede morta

`supabase functions deploy` ficou 7 min sem sair do "Bundling Function". Medido de DENTRO do
container: **1.223 bytes em 20 s (~61 B/s)**, com DNS resolvendo normalmente (IPv4 inclusive — a
hipotese de IPv6-only foi levantada e **desmentida** por `getent ahosts`). Do host, o mesmo destino
responde em 0,088 s. ⇒ **`--use-api` (bundle no servidor, sem Docker) publicou em segundos.** Vale
como primeira tentativa nesta maquina. Classe do #2265: medir do host nao mede a rede do container.

---

## 4. Fora do escopo, medido e registrado

`purge_stale_digest_notifications_cron` (domingo 14:00 UTC) carimba `digest_delivered_at` em tudo
que passa de 30 dias pendente: **1.993 linhas em 16 execucoes desde 06/05**. E a mesma frase do
titulo da #2286 ("carimba como entregue o que nunca renderizou"), mas com proposito declarado,
audit log e cutoff explicito — existe para o acervo pendente nao crescer para sempre para quem nao
recebe digest. **Nao foi tocado.** Depois da #2286 ele fica quase inocuo para quem esta optado,
porque qualquer pendencia agora dispara `has_content`. O que sobra e uma decisao de nomenclatura:
carimbar por idade no MESMO campo que significa "entregue" mantem a metrica dizendo entrega onde
houve descarte.

---

## 5. Operacao: o convite da reuniao de lideranca

O convite da quinzenal **nao** estava faltando para os lideres em geral — medido: **12 de 12
lideres COM tribo ja estavam convidados**. Faltavam exatamente os **2 lideres em formacao**, que
nao tem iniciativa e por isso ficaram fora de uma lista montada por quem tem tribo. Mesma lacuna
estrutural das **#2333/#2334**: o modelo trata "lider" como quem ja tem tribo.

Os dois foram adicionados **na serie** (nao so na instancia de hoje — senao a falha volta na
proxima quinzena), mais uma pesquisadora como opcional. ⚠️ Havia **duas pessoas de mesmo primeiro
nome** na base, uma delas ja no convite e a outra nao; a pedida era a que faltava. Confirmar
identidade por papel antes de adicionar, nunca pelo primeiro nome.

---

## 6. Comandos para re-medir antes de decidir

```bash
git fetch --all && git log --oneline -1 origin/main
gh pr list --state open && gh issue list --state open --limit 10
npm run test:structural     # RODE ANTES DE ABRIR PR
npm run test:verdict        # e NAO rode enquanto o CI da sua propria PR estiver no ar (licao 1)
```

```sql
-- a #2286 continua honesta? (carimbado sem secao tem de ser 0 para os lotes NOVOS)
SELECT count(*) FILTER (WHERE digest_delivered_at IS NULL) AS pendentes_que_o_digest_vai_mostrar,
       count(DISTINCT type) AS tipos_vivos
FROM public.notifications WHERE delivery_mode='digest_weekly';

-- o gate cego da proxima tarefa: qual dos 3 jobs que a funcao procura NAO existe?
WITH procurados(jobname) AS (VALUES ('send-weekly-member-digest'),
       ('send-weekly-leader-digest'),('weekly-card-digest-saturday'))
SELECT p.jobname, (j.jobid IS NOT NULL) AS existe, j.schedule
FROM procurados p LEFT JOIN cron.job j USING (jobname);

-- o estado do arco
SELECT (SELECT count(*) FILTER (WHERE violation_count>0) FROM public.check_schema_invariants()) AS invariantes,
       (SELECT count(*) FROM public.selection_applications WHERE email LIKE 'fixture-1636-%@example.com') AS fixtures_orfas;
```

---

## 7. Prompt de arranque sugerido

> Ler `docs/planning/2026-09-17_handoff_2286_fechada_o_carimbo_que_nunca_acertou.md`.
> A tarefa e `get_digest_health`: ela e **cega a job ausente** (procura 3 nomes, um foi removido em
> maio, e `WHERE jobname IN (...)` nao devolve a linha que falta) e a metrica que ela pinta de verde
> **so passou a significar algo depois da #2286**. Derivar do catalogo, reportar TRES estados, e
> provar por mutacao que o gate reprova quando um job desaparece.
> Re-medir a secao 6 antes de escrever. **Nao rodar `test:verdict` local enquanto o CI da propria PR
> estiver no ar** — foi o que custou 15 assercoes hoje.
