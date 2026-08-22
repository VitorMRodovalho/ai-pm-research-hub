# Arranque de 21/08: fila destravada, e um relógio que já desarmou

> Tudo aqui foi medido ao vivo em **20/08/2026** (horários em UTC). **Re-medir antes de agir**:
> número recitado de handoff não vale como medição.
> Sem nome e sem identificador de candidato: este repositório é público.

---

## 1. Estado

### ✅ RESOLVIDO: a fila esteve congelada por quebra externa do npm, e foi destravada

O check **`deno` é required** (os três são `validate`, `browser_guards`, `deno`). Ele passou a
falhar em 20/08 com `Could not find npm package '@bruits/satteri-darwin-arm64' matching '0.10.4'`,
sem nenhuma mudança no repositório, e **nenhuma PR mergeava**.

**Causa raiz, medida (#1896, PR #1897 mergeada):** `deno check --node-modules-dir=auto` sobre
`supabase/functions/**` fazia o Deno descobrir o `package.json` da **raiz** e resolver **toda** a
árvore npm do frontend. Em clone limpo, o `node_modules` criado por esse job ganhava **39 entradas
de topo** (astro 7.2.4, playwright, eslint, @radix-ui), e **nenhuma Edge Function importa qualquer
uma delas**: elas usam `npm:`/`jsr:` inline. O portão das EFs estava refém da árvore do site.

O gatilho externo: `satteri@0.10.4` (publicado 19/08 10:57 UTC) declara `optionalDependencies` em
`@bruits/satteri-darwin-arm64@0.10.4`, versão que **nunca foi publicada** (a lista pula de `0.10.3`
para `0.10.5`). O npm tolera, porque a dep é opcional e o `os` não casa com Linux. O Deno não.

**Correção:** `DENO_NO_PACKAGE_JSON=1` no job. Medido com Deno 2.9.5, clone limpo, cache frio:
`node_modules` cai de 39 para **4**, seguem **56 de 56** arquivos checados, e um `TS2322` injetado
de propósito **continua reprovando**. O portão não virou vácuo.

⚠️ **A armadilha que quase inverteu o diagnóstico:** reproduzir local **passou**. O workflow pede
`deno-version: v2.x`, que **flutua**; o runner instala **2.9.5** e eu tinha 2.5.6. Antes de dizer
"não reproduz", leia no log do job qual versão o runner instalou. `v2.x` não é uma versão.

📌 **Fica aberto, sem dono:** o `deno-version` segue em faixa flutuante (a exposição caiu muito com
o acoplamento removido, mas segue móvel num check required), e o `deno.lock` segue velho de fato
(registra `astro@^6.4.8` enquanto o `package.json` pede `^7.2.2`).

---

**Fila de PRs:** livre. `main` em **`72319b04`** (a #1897, o conserto do `deno`). **Zero bypass** consumido em toda a sessão de 19-20/08, inclusive no destravamento.

Mergeadas na sessão: **#1879** (auditoria da jornada), **#1883** (trigger de XP), **#1890** (o #1887),
**#1893** (isenção do #1636), **#1892** (docs da lane), **#1897** (o conserto do `deno`).

`check_schema_invariants()` devolveu **0 violações** às 13:51, depois do import do VEP.

---

## 2. O que tem data (por urgência)

### ✅ Sábado 22/08, 15:00 UTC: o relógio DESARMOU sozinho

O cron `selection-stuck-scheduled-rescue-daily` (15:00 UTC diário, ativo) alcançaria a entrevista de
**19/08 21:30 UTC** que estava sem desfecho, e dispararia um convite de agendamento NOVO para quem já
tinha sido entrevistada.

**Desarmou como previsto, sem intervenção manual.** O entrevistador submeteu as notas em **20/08
18:49:03 UTC**: `submit_interview_scores` carimbou `conducted_at`, a linha virou `completed` e a
candidatura avançou para `final_eval`. Rodei o predicado do próprio cron às **19:09:19 UTC**:
**0 alvos** (grace medido = 48h). Ele lê a linha canônica e o status da candidatura, e os dois
deixaram de casar.

⚠️ **O que isso custou, e é o item que fica:** o entrevistador achou que a submissão tinha
**falhado**, porque o painel de histórico ao lado pintou `Unauthorized: requires manage_member action`
em vermelho. O painel tem `try/catch` próprio e não bloqueia o formulário, mas quem opera não tem como
saber disso. É o espelho do defeito 1 do #1838 (a tela confirma gravação que não aconteceu): aqui a
tela **sugere falha onde houve gravação**. Registrado no **#1895**.

📌 **Ainda em aberto na mesma candidatura:** o LinkedIn não gravou. Os dois portões aceitam o
avaliador (a RPC `update_application_contact` já foi corrigida pelo #1838, e o gate de tela
`operate_selection` espelha), então a causa **não** é autoridade e não foi determinada. Pedir nova
tentativa e capturar o texto exato do toast.

### 🔴 24/08 — #1710, o único irreversível

Config conferida ao vivo em 20/08 12:20: `platform_settings.attendance.seal_window` =
`{floor_date: 2026-08-24, grace_days: 14}`. Cron `attendance-seal-window-daily` ativo.

**Re-medir em 23/08.** Os números de 15/08 (43 selam, 80 faltas, 40 pessoas) são **teto**, não
medição atual. `preview_seal_attendance` recusa `service_role` — use a porta MCP ou o predicado
replicado, com `America/Sao_Paulo`.

### ⏳ Sem relógio, mas envelhecendo

Duas candidaturas do ciclo aberto estão com **zero avaliações de qualquer tipo** desde 17/08: uma
em `interview_pending` (travada, não pode ser convidada) e uma em `submitted`. Todo o resto do
funil ativo tem 2 ou mais.

---

## 3. Decisões do PM nesta sessão — não re-litigar

1. **Convidar para entrevista sem o peer review completo está DESCONTINUADO.** Foi feito em julho
   sob pressão de kickoff e pedido de patrocinador; o PM classificou a repetição de 19/08 como
   **erro**. Quando o gate barrar, o desfecho é conseguir as avaliações, não contornar.
2. **Quatro certificados `alumni_recognition` de membros inativos foram REVOGADOS** (decisão de
   mérito do PM, não de cadastro), com `revoked_by` explícito e auditoria. Fila de contra-assinatura
   zerada.

---

## 4. Aberto, sem dono

- **#1888** — a fila de contra-assinatura só tem desfecho positivo (falta a porta de **recusar**,
  com motivo e autoria) **e** esconde certificado de outro capítulo de quem não tem `manage_member`.
- **5 linhas fantasma** no ciclo 3 (fechado): candidaturas de líder carregando o
  `vep_application_id` da candidatura de pesquisador da mesma pessoa. **Observado**, não inferido:
  um import completo do VEP passou por cima em 20/08 e não as viu (`vep_last_seen_at` segue nulo
  nas 5, enquanto as gêmeas foram tocadas às 13:49). Inflam a contagem de líderes daquele ciclo.
  Sem issue.
- **Gargalo do comitê:** quatro pessoas cadastradas como `evaluator`/`lead`, e **duas** fizeram
  298 das 299 avaliações objetivas. Uma fez 1 (em abril), outra **nunca** avaliou. Não é falta de
  cadastro, é falta de exercício. Sem issue.
- Itens da lane #1877 (documento de entrega): 4 ferramentas MCP que falham desde maio/julho
  (`update_checklist_item` 9/9, `delete_checklist_item` 4/4, `get_selection_health` 3/3 com erro de
  SQL vivo), **169 MB** de log sem política de retenção (`admin_audit_log` 137 MB, `pii_access_log`
  12 MB ⚠️), e 273 FKs sem índice.
- **#1895 (nova, e é a que o comitê sente a cada jornada):** a tela de seleção deriva **todas** as
  afordâncias de UM eixo pessoal (`is_locked` = "eu já submeti a avaliação DESTE tipo"). Os dois botões
  são complementares por construção (`canScore` vs `isLocked || isObserver`), então **quem fez a
  entrevista e não a objetiva nunca vê o resultado consolidado**. O mesmo eixo faz a tela convidar à
  avaliação redundante dos dois lados, e o formulário de entrevista aparece para quem **não** é o
  entrevistador designado, com `submit_interview_scores` **aceitando** a submissão de quem tem
  `manage_platform`.
  📐 **O número que dimensiona:** dos 3 `evaluator` do ciclo aberto, **2 são GP**. Só 1 é comitê puro,
  então o modelo de autoridade nunca tinha sido exercido sem GP, e essa pessoa descobre um portão por
  jornada. Superfície medida: **145 RPCs SECDEF de leitura** exigem `manage_member`, `manage_platform`
  ou `view_internal_analytics` (mais 248 de escrita/outro).
  ⚖️ **O que trava não é análise, é decisão do PM:** o que um avaliador de comitê **pode ler**. O #1838
  pediu isso em 17/08 e segue sem resposta. Sem ela, varrer os 145 só produz outra tabela esperando a
  mesma decisão.
  🐛 **Defeito latente achado no caminho:** `selection_committee_role_for()` **nunca devolve `'lead'`**
  (o `CASE` colapsa em `evaluator`/`observer`), então um lead puro perderia escrita e agendamento. Não
  acende hoje porque o ciclo aberto tem 3 `evaluator` e 4 `observer`, e nenhum `lead`.
- **#1664**, **#1728**, **#1729**, **#1742**, **#1744**, **#1592**, **#1205**, **#1842**, **#1844**,
  **#1850** (violação aberta de propósito, vence 30/09), **#1876**, **#1877** (épica), **#1880**,
  **#1881**, **#1882**, **#1884**, **#1885**, **#1886**, **#1895**.

---

## 5. Armadilhas MEDIDAS nesta sessão (custaram tempo real)

**A CI tem duas armadilhas que se combinam.** (a) `wait-for-db-lane` (#1509) falha *fail-closed*
quando não consegue ler a fila na API do GitHub — atualizar duas branches no mesmo segundo faz as
duas disputarem a faixa e caírem juntas. **Escalone.** (b) `cancel-in-progress: false` faz um push
durante um run criar um segundo run `pending` que **não despacha** até o primeiro terminar —
cancele o obsoleto, senão a espera é indefinida.

**`CREATE OR REPLACE` recusa se você omitir o DEFAULT do parâmetro** (42P13). E
`pg_get_function_identity_arguments()` **não mostra defaults** — leia `pg_get_function_arguments()`.

**Mensagem de falha de guard nomeia a HIPÓTESE do autor, não o diagnóstico.** O guard do #1636
acusa "algum teste escolheu alvo por predicado"; a causa real eram chamadas manuais. O experimento
decisivo e barato é **re-rodar a suíte inteira e ver se o contador anda**.

**Uma CTE que escreve não enxerga a própria escrita no mesmo statement.** Contar "quantos restam"
na mesma query do `UPDATE` devolve o snapshot anterior e parece que o conserto falhou.

**O `apply_migration` cria a linha de rastreio com timestamp PRÓPRIO.** Renomeie o arquivo local
para o timestamp da fantasma — foi assim que o #1883 e o #1890 fecharam.

---

## 6. Import do VEP — o padrão que funcionou

Rodado pela interface em 20/08 13:48-13:49. **167 candidaturas tocadas, nenhuma linha nova criada**
(preencheu o `vep_application_id` de uma linha existente em vez de duplicar), **0 violações** de
invariante depois. Total permaneceu em 173.

Rodar `check_schema_invariants()` **depois de todo import** continua sendo a regra (#1834), e desta
vez ela passou limpa.
