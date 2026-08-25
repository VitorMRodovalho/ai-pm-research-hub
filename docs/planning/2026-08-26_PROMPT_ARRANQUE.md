# Prompt de arranque - main, depois de 25/08 (tarde)

Copie o bloco abaixo como primeira mensagem da nova sessao.

---

Leia `MEMORY.md` e depois `docs/planning/2026-08-25_handoff_duas_ddl_serializadas_1978_e_1925.md`.

**Estado medido no fim de 25/08:** main `97e35eef`, **fila VAZIA**, **zero bypass**.
Merges do dia: **#1980**, **#1981**, **#1983**, **#1979**, **#1986** (#1978) e **#1988** (#1925).

## O arranque anterior ficou VAZIO

As duas entregas de DDL que a fila liberou sairam as duas, e **#1978** e **#1925** estao FECHADAS.
Nao ha divida de CI aberta, nao ha PR na fila, e nao ha DDL aplicada sem captura commitada
(conferido: `schema_migrations` tem exatamente as 2 versoes do dia, ambas na main).

## O que sobrou, e e barato

**#1987 - decisao de DOCUMENTACAO, nao de codigo.** A escada de `operational_role` tem hoje UMA
copia inline, dentro da A3 (`check_schema_invariants`), e o SSOT `_derive_operational_role()`.
Converter a A3 para chamar o SSOT **elimina a copia e custa caro**: o invariante deixa de ser
independente da implementacao, **e** o guard `role-ladder-parity` (ADR-0023) vira tautologia. Como
esse guard ja existe e ja esta exercido, a saida provavel e **registrar no ADR-0023 que a duplicacao
e deliberada** - para a proxima pessoa nao "consertar" apagando o guard junto. **Sem DDL**, entao
nao entra em fila de serializacao.

## O que tem relogio

- ⏰ **27/08 08h40 BRT: o selo de presenca grava** (#1948). Decisao mantida do PM: **gravar as 77 e
  corrigir depois**. A correcao tem **3 passos, ou os tres ou nenhum** - apagar a linha NAO desfaz a
  falta (evento selado + sem linha le como `absent`). Efeito 77 → **66**. O cron dispara sozinho.
- 🆕 **00:04 UTC todo dia: `operational-role-reconcile-daily`** (novo, do #1925). Na primeira semana
  vale conferir `admin_audit_log` por `members.operational_role_reconciled` - ele **so grava quando
  houve mudanca ou erro**, entao **ausencia de linha e o esperado**. Linha aparecendo significa que a
  virada de `CURRENT_DATE` de fato mexeu em alguem, que e a hipotese da #1925 se confirmando.
- ⏳ Radar Tecnologico 13/07 segue o unico item de presenca aberto.
- ⏰ **28/08** funil · **09/09** retencao · **30/09** anonimizacao.

## O que mudou na sua rotina

- **A escada de papel tem DONO:** `_derive_operational_role(person_id)`. Se precisar mexer em
  prioridade de papel, mexa **la**, e saiba que o `role-ladder-parity` compara clausula a clausula
  com a A3 - mudar um lado sem o outro reprova.
- **`sync_operational_role_cache` DELEGA.** Ha guard proprio que reprova se a escada voltar para
  dentro dele.
- **Notificacao de comite resolve destinatario por `_selection_cycle_recipients(cycle_id)`:**
  lead → comite do ciclo → `manage_platform`. **Nunca devolve vazio**, nem para ciclo NULL.

## Armadilhas medidas em 25/08 (tarde) - nao re-aprender

**De fila:**
- **Antes de aplicar a 2a DDL, confirme que o `check-invariants` da main fechou com a 1a.** Foi o que
  impediu de recriar o impasse cruzado de 24/08 (duas PRs com DDL, cada uma vermelha pela do outra,
  nenhuma fecha sozinha). Custa poucos minutos de espera.
- **Renomear o arquivo local para o timestamp que o `apply_migration` registrou** dispensa `repair` e
  nao deixa fantasma. Funcionou nas duas entregas. Confirmado: `schema_migrations` sem linha extra.

**De guard:**
- **Recriar uma funcao VENCE todo guard fixado no `.sql` dela.** Dois cairam (`1972-designacao`, que
  ficou vermelho de verdade, e o md5 do `1978-paridade`). Conserto: `latestFunctionCapture(ROOT, fn)`.
- **Guard que afirma PRESENCA fica vermelho quando a forma muda; guard que afirma AUSENCIA fica
  verde e vazio.** O `role-ladder-parity` usa `assert.ok(caseInner)` e por isso avisou. **Rode a suite
  INTEIRA depois de mover logica compartilhada** - os testes-alvo nao pegariam.

**De sonda:**
- Postgres limita repeticao de regex a **255**: `.{0,300}` levanta `invalid repetition count(s)`.
- `ELSE 'guest' END` **nao casa** em `prosrc` cru (ha quebra de linha). Normalize
  (`regexp_replace(prosrc,'\s+',' ','g')`) **antes**, e leve controle positivo: vazio nao e evidencia.
- **`| tail -N` engole o codigo de saida da suite.** Rode sem pipe, redirecionando para arquivo, e
  carimbe `TEST_EXIT=$?`. Foi assim que descobri as 4 falhas reais do `role-ladder-parity`.

**De escopo:**
- **Antes de escrever reconciliador, conte as divergencias FORA do escopo pretendido.** Eram **32**
  entre nao-ativos contra **0** entre ativos: um `WHERE true` teria feito mutacao em massa e passado
  como "reconciliacao" no relatorio.

## Higiene

`MEMORY.md` em **24.120** de 24.985 (folga **865**, contra 535 no inicio de 25/08). Cinco linhas do
READ-FIRST comprimidas e a licao do impasse de DDL movida para o arquivo-topico. **A folga voltou a
ser confortavel, mas o mecanismo e o mesmo:** encurtar para gancho e mandar o integral para
`MEMORY_ARCHIVE_INDEX.md` ou para o arquivo-topico da licao.
