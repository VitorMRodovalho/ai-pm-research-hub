# Prompt de arranque: a fila travada, a filiação segmentada e o vencimento de 31/08

> Colar depois do `/clear`.
> **Modelo: Opus 5 (auto, não pinar). Effort: `xhigh`.**
> **Supersede** `docs/planning/2026-08-19_PROMPT_ARRANQUE_FILIACAO_E_ENTREVISTAS.md` (que foi
> escrito para 19/08 e executado ainda em 18/08, ver Regra zero).

---

## Regra zero

**Nada deste documento pode ser recitado.** Todo número foi medido em **19/08/2026 até 01:34 UTC**.
Re-meça com tool call na mesma volta em que o número entrar numa decisão, commit, issue ou pergunta.

🆕 🔴 **Confira o RELÓGIO antes de executar a ordem sugerida.** O arranque anterior foi escrito à
noite datado do dia seguinte, e ao ser executado o passo 1 estava vazio: mandava marcar desfecho de
entrevistas que ainda não tinham acontecido (uma começava em 26 minutos). `date -u` **e** `now()` do
banco, e leia os passos pela **pré-condição**, não pela data.

Regras de varredura que já custaram caro. As **quatro últimas foram ganhas em 18-19/08**:

- **Uma listagem não sustenta afirmação de ausência.**
- **Varra `pg_proc`, não o repositório**, e leia o corpo antes de confiar na varredura.
- **`replace_all` casa a string, não a intenção.** Conte e diffe.
- **O carimbo do TRANSPORTE não é o do FATO.**
- 🆕 🔴 **Ausência de dado só vale COM o controle do campo.** Nulo é "não existe" OU "a coleta não
  funciona", e os dois são idênticos. Meça a **taxa de preenchimento na população** antes de
  afirmar ausência. (Foi assim que `pmi_memberships` vazio virou afirmação: 120 de 172 preenchidos.)
- 🆕 🔴 **Junção por chave FRACA esconde vínculo que a chave FORTE acha.** Publiquei a contagem
  errada **duas vezes na mesma noite**, uma por `pmi_id` e outra por `lower(email)`. Identificador
  emitido por terceiro é mais forte que e-mail. **Meça pelas duas; divergência é achado.**
- 🆕 🔴 **Defeito consertado na ESCRITA sobrevive na EXIBIÇÃO.** O #999 foi corrigido na trilha de
  escrita pelo #1175, e a mesma fonte errada continuou no rótulo da tela e no pré-preenchimento.
- 🆕 ⚠️ **Fallback cujo último termo só dispara na ausência de evidência é gerador de dado falso.**
  Campo vazio pede preenchimento; campo com valor errado pede só confirmação.
- 🆕 ⚠️ **`check_schema_invariants()` já devolve `sample_ids`.** NÃO reconstrua o predicado: a minha
  reconstrução devolveu zero linhas porque `members.chapter` usa `PMI-DF`/`Outro` e
  `chapter_registry` usa `GO`/`DF`.

---

## Estado (19/08, 01:34 UTC)

`main` em **`418b9d8d`** · **218 issues abertas** · **4 PRs abertas** · bypass: **re-medir**.

🔴 **43 invariantes, 1 violação. E ela trava TUDO.** Ver ITEM 1.

---

## 🔴 ITEM 1: a fila de merge está congelada, e essa é a decisão que destrava a sessão

`U_active_person_has_primary_chapter_affiliation` = **1 violação**, aberta **por decisão do PM**
(#1850). O vermelho está certo, e reparar o dado para calar o check continua proibido.

🆕 **O que se descobriu em 18/08 e muda o custo da decisão:** o vermelho **não fica no
`check-invariants`**. Ele derruba **16 testes dentro do `validate`**, todos ancorados em
`0 total violations`. Consequência: **nenhuma PR fica verde**. Confirmado na prática: a #1861
passou em todos os outros portões e caiu nos dois.

**Quatro PRs esperando, duas delas prontas:**

| PR | o que é | estado |
|---|---|---|
| **#1864** | #1862: rótulo de serviço e fim do pré-preenchimento chutado | conteúdo verde, travada pelo #1850 |
| **#1861** | #1856: regex do WhatsApp e correção de contato | conteúdo verde, travada pelo #1850 |
| #1860 | arranque de 19/08 (superado por este) | pode fechar |
| #1859 | handoff da noite de 18/08 | travada pelo #1850 |

📌 **Caçar evidência de filiação para o ofensor JÁ FOI FEITO e deu negativo, com controle.** Não
refaça: `pmi_memberships` e `membership_status` nulos, busca ao PMI rodada em 17/08 e vazia, e o
campo está preenchido em 120 de 172 candidaturas (então o vazio é real). O que existe é histórico
de **voluntariado**, que não é filiação. **Não grave linha.**

⚖️ **A decisão que falta:** a fila espera a Diretoria verificar (ato humano, prazo indefinido), ou
sai um bypass pontual documentado para o que já está pronto? **Re-meça a contagem de bypass da
janela antes de propor.** Há entrega com prazo em 31/08 que precisa de merge.

## ⏰ ITEM 2: #1855, migration PRONTA e retida de propósito. 12 dias.

**As duas decisões do PM já estão tomadas** (registradas na issue): "vencida" implica **só lembrete,
mesmo tom**, sem consequência; e o freio sai **junto com a faixa de vencidos, numa PR só**.

A migration está construída, com bases conferidas por md5 normalizado contra as **19** capturas do
repo, **drift zero**. Ela faz quatro coisas: faixa nova de vencidas (dedupe de **30** dias, não 7,
porque a faixa é ilimitada no tempo), fecha o **buraco do dia 0** (`BETWEEN 1 AND 7` → `0 AND 7`),
cataloga o tipo novo em `_delivery_mode_for` em vez de deixar no `ELSE`, e tira o `dry_run` por
`cron.alter_job` **pelo nome**, sem hardcode de `jobid`.

📌 **Não apliquei porque `apply_migration` antes do merge deixa toda branch aberta vermelha por
drift, e a fila já está travada.** Aplicar somaria um segundo motivo de vermelho. **Resolva o ITEM 1
primeiro**, depois é uma chamada só. A receita de reconstrução está no comentário da issue.

Medido em 18/08 22:37: dry-run devolve `candidates_d30: 6`, `d7: 0`, `stale: 0`. **Re-meça.**

## ITEM 3: filiação, a fila da Diretoria já está segmentada

**26 membros ativos sem verificação** (mais 5 pré-onboarding, somando o "31" do painel). O número
**anda enquanto a Diretoria trabalha**: medi 32 às 22:37 e 26 às 23:45 do mesmo dia.

| classe | pessoas | com `pmi_id` | com candidatura por e-mail |
|---|---|---|---|
| externo: `chapter_liaison` | 10 | 2 | 0 |
| **interno: `researcher`** | **7** | 7 | 5 |
| externo: `sponsor` | 5 | 0 | 0 |
| externo: revisor externo | 3 | 1 | 0 |
| **interno: `manager`** | **1** | 1 | 0 |

⚖️ **Decidido pelo PM:** os **18 externos não recebem** comunicação de filiação (não estão sob o
Termo). Os **8 internos recebem**, e todos têm `pmi_id`, então todos levam o link do VEP.

📌 **Ninguém nunca foi comunicado:** `notifications` com tipo `affiliation%` tem **zero** linhas.
E o radar do #1855, mesmo ligado, **não alcança esses 8**, porque ele itera sobre a tabela de
verificações e eles não têm linha lá. Não é atraso na fila, é estar **fora** dela (issue **#1863**).

⚖️ **Pendente:** aprovar o texto (rascunho no comentário da #1863, com `nucleoia@pmigo.org.br` como
endereço único, decisão do PM: o Núcleo é a ponte, a pessoa não procura diretoria) e escolher o
canal (e-mail direto ou notificação da plataforma).

## ITEM 4: os dois consertos de filiação que sobraram na #1863

Nenhum foi feito, os dois são pequenos e os dois são **DDL ou RPC**, logo dependem do ITEM 1:

1. **O painel sub-mostra o link do VEP.** `pmi_profile.pmi_id` vem da **candidatura**, mas
   `members.pmi_id` está preenchido em **11 dos 26**. O link do #1368 poderia aparecer para 11 e
   aparece para 5. Falta projetar `m.pmi_id` como fallback na RPC.
2. **A fila da Diretoria está inflada:** 18 dos 31 não são público dela. Falta filtro de coorte.

## 🆕 ITEM 4b: o módulo de filiação auditado, e a inversão que ele pede

Auditado em 19/08 02:00, com o contexto quente. **A medição dá nome à intuição do PM:** o módulo
pede que humanos façam o trabalho da máquina, e enterra o trabalho que só humano faz.

| fato | número |
|---|---|
| verificações mais recentes por membro | 69 |
| com evidência **reprocessável por máquina** | **69 (100%)** |
| idade da evidência (`pmi_data_fetched_at`) | **2 dias** (mín = máx = média) |
| crons que **verificam** filiação | **0** |
| ativos sem verificação, com evidência reprocessável | 26, dos quais **0** |

📌 **Efeito de manada chegando:** as 69 verificações têm idade entre 1 e 37 dias, média 33. Foram
feitas na mesma campanha, então **vencem juntas**.

- **#1866**: auto-verificar quem TEM evidência (a regra já existe no #1175 F1, é agendar), e a tela
  vira console de exceção. 🔴 **Cinco guardas na issue**, e a principal: a recusa tem que ser por
  **idade da evidência**, não por o job terminar sem erro, senão o sync quebrar deixa o painel verde
  mentindo. ⚠️ **Refresh automático NÃO é atestação:** use valor de `method` próprio, e **não**
  `verified_by_member_id` nulo (a coluna é nullable, e ator nulo é o anti-padrão conhecido).
- **#1867**: seção de filiação no digest semanal de líderes. A infra existe
  (`send-weekly-leader-digest`, segundas 12:00 UTC, 3.560 chars, **não cita filiação**). 🔴
  **Requisito que faz ou quebra: publicar o DENOMINADOR.** "2 vencidas, 7 vencendo" seria correto e
  mentiroso, porque os **26 sem linha** não aparecem em contagem nenhuma.

⚖️ Os dois são **propostas**, não decisões tomadas. O #1867 tem três pendências declaradas: público,
nominal ou agregado, e se a seção deve sumir quando não há exceção.

## ⏰ ITEM 5: #1710, prazo 24/08

Config conferida em 17/08 e intacta (`floor_date` 2026-08-24, `grace_days` 14; cron
`attendance-seal-window-daily`, `40 11 * * *`).

📌 **Re-medir em 23/08, a véspera, pelos DOIS caminhos independentes.** É TETO e encolhe a cada
presença registrada. ⚠️ **A entrevista de 24/08 23:30 UTC cai no MESMO dia.** Não deixe os dois
para a mesma sessão.

## ITEM 6: entrevistas

| quando (UTC) | quando (BRT) | status em 19/08 01:34 |
|---|---|---|
| 19/08 21:30 | 18:30 | `scheduled` |
| 24/08 23:30 | 20:30 | `scheduled` |

A de 18/08 23:00 aconteceu durante a sessão anterior e **não teve desfecho marcado**. Confira
`passadas_sem_desfecho` antes de qualquer coisa.

⚠️ **`mark` carimba `conducted_at` com a hora do REGISTRO**, não da entrevista (16 de 99 divergem,
máximo 64 dias), e **o envelope relata `application_status` que não gravou**. Sem issue.

## ITEM 7: funil, prazo 28/08

Medido em 18/08: **105 linhas, 1 reserva medida**. **Nenhum número de conversão é publicável sem o
denominador explícito.** **Não provocar despacho:** o cron gera linhas sozinho.

## ITEM 8: o resto, com dono

- **#1863** (alcance dos não verificados) · **#1862** (fechada pela #1864, confirme no merge).
- **#1852**: filiação do VEP parada há 4 meses. ⚠️ São **dois exports** do PMI, e só o enriquecido
  de membership traz capítulo.
- **#1854** · **#1858** (⚠️ reproduzir antes de consertar) · **#1848** · **#1844** (causa da
  saturação de pool **ainda não identificada**; a suíte roda contra produção).
- **#1842** · **#1829** · **#1822** (as 56) · **#1592** · **#1205** · **#905** (30/09).
- **#588 alimentada em 19/08** com 6 lições. O laço do PMO voltou a andar.
- **#92** (118+ dias), raiz estrutural da **#1614**.

---

## Ordem sugerida

1. **ITEM 1: decidir como destravar a fila.** Sem isso nada merge, e há prazo em 31/08.
2. **Marcar desfecho das entrevistas que JÁ ocorreram** (pré-condição, não data).
3. **#1855: aplicar a migration** assim que a fila andar. Uma chamada.
4. **#1863: aprovar o texto e escolher o canal**, e disparar para os 8 internos.
5. **23/08: re-medir o #1710** pelos dois caminhos.
6. **ITEM 4:** os dois consertos de RPC da filiação.

---

## Armadilhas da vizinhança

1. ⚠️ **`CREATE OR REPLACE` exige o corpo INTEIRO.** md5 normalizado antes, bloco extraído **do
   arquivo**, substituição **contada**, diffe. 📌 **Aplique em LOTES** e confira md5 de cada um.
2. ⚠️ **Captura antiga usa `CREATE FUNCTION` sem `OR REPLACE`**: troque, que `OR REPLACE` preserva
   as ACLs.
3. **`apply_migration` cria o timestamp**: renomeie o arquivo local para ele. **A CLI não está
   linkada.**
4. **DDL antes do merge deixa toda branch aberta vermelha.** Aplique com zero PRs.
5. **Schema novo exige `npm run db:types` na MESMA PR**, e **confira por `grep`**, porque o script
   faz **no-op com exit 0** quando o PostgREST serve schema em cache.
6. **Teste novo entra nas DUAS whitelists do `package.json`.**
7. **Suíte offline (~66 s):** `env -u SUPABASE_URL -u SUPABASE_SERVICE_ROLE_KEY -u PUBLIC_SUPABASE_URL npm run test:contracts`. ⚠️ **Skip ≡ pass.** Com DB: `set -a; . ./.env; set +a`.
8. ⚠️ **`Fecha #N` NÃO fecha.** Use `Closes #N`, e nunca escreva o padrão sem intenção.
9. ⚠️ **Branch nova nasce do HEAD.** `git checkout -b <nome> origin/main`. **Nunca `git add -A`**
   (há ~60 arquivos não rastreados na árvore).
10. ⚠️ **Repo PÚBLICO.** Nome, e-mail e identificador não entram em issue, PR nem doc. **Conte a
    população.**
11. ⚠️ **RPC com `auth.uid()` devolve "Not authenticated" para `service_role`.** Impersone em
    transação abortada, `set_config` **antes** do `SET LOCAL ROLE`.
12. 📌 **Prove o guard VERMELHO**, e faça-o devolver **todos** os examinados com um booleano.
13. ⚠️ **Guard que PROÍBE um padrão acusa a própria DOCUMENTAÇÃO.** Rode sobre o SQL **sem
    comentários**.
14. ⚠️ **O build leva 4m15s a 4m22s: background + confira o `Complete!`.**
15. 🔴 **SQL direto por `service_role` registra ato humano como 'cron' com actor nulo.** Use a porta
    MCP. ⚠️ **`upsert_chapter_affiliation` NÃO audita** e é a única porta de escrita da tabela que
    ancora o capítulo.
16. 🔴 **Despacho em LOTE quebra o rodízio** (`now()` é da transação).
17. ⚠️ **i18n: chave nova nos TRÊS dicionários**, e o fallback inline do componente tem que casar
    com o valor do dicionário.
18. ⚠️ **Drive:** barra fullwidth (`／`), gravação do Meet **sem extensão**, doc nativo **0 bytes**
    pelo mount. `~/.local/bin/rclone` (1.74), nunca o do apt.
19. ⚠️ **YouTube:** ferramental em `~/projects/_pmo/youtube/`; a API **mente por propagação nos dois
    sentidos**; `videos.update` com `part='snippet'` substitui o snippet INTEIRO.
