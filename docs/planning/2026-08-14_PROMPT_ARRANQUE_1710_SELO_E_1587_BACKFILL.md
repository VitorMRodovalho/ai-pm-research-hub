# Prompt de arranque — #1710 (prazo 24/08), backfill do #1587, e o cap do #1586

> Colar depois do `/clear`. **Effort: `xhigh`.**
> Handoff anterior: `docs/planning/2026-08-14_handoff_1587_o_estado_da_entrevista_ganhou_fonte.md`

---

## Regra zero

**Nada deste documento pode ser recitado.** Todo número abaixo foi medido em **14/08/2026** e
vários se movem sozinhos. Re-meça com tool call na mesma volta em que o número entrar numa decisão,
num commit, numa issue ou numa pergunta ao PM.

E duas regras de varredura que custaram caro nas últimas sessões:

- **Uma listagem não sustenta afirmação de ausência.** Vale para `gh run list --limit`, `LIMIT` em
  SQL, `gh pr checks` (a lista ENCOLHE durante um rebase, e `all()` sobre lista vazia é vacuamente
  verdadeiro — foi assim que um monitor anunciou "CI concluído" com dois gates ainda rodando).
- **Varra pela CHAVE publicada, não pelo nome da função**, e varra `pg_proc`, não o repositório.

---

## Estado (14/08, fim da madrugada)

`main` em **`082fe71d`**. **Zero PRs abertas.** A sessão anterior fechou 4 merges com **zero
bypass** (#1752, #1770, #1769, #1772; a #1771 foi fechada e consolidada na #1770).

Em produção desde então: `v_application_interview_state` (SSOT do estado da entrevista,
`security_invoker`, `anon` recebe 401), `get_selection_dashboard` derivando dela, o contrato
`1587-estado-canonico-da-entrevista.test.mjs` e o allowlist do guard #1636.

---

## ⛔ O erro da sessão anterior, que esta sessão NÃO pode repetir

**DDL foi aplicada ao banco ANTES de a PR mergear.** Duas consequências, ambas medidas:

1. **Toda branch aberta ficou vermelha.** A #1769 era só documentação, não tocou em SQL nenhum, e
   quebrou em `Phase C: no NEW body-hash drift` + `ADR-0097: no NEW missing-file drift`.
2. **O trabalho ficou INSEPARÁVEL em PRs.** A #1771 (guard) e a #1770 (migrations + tipos) se
   bloqueavam mutuamente — cada uma descrevia metade do banco vivo, e o CI compara contra o banco
   inteiro. A #1771 teve de ser fechada e consolidada.

**A regra:** depois que a DDL está no banco, migrations + `database.gen.ts` + qualquer guard que o
novo estado afete viram **uma única unidade mergeável**. Decida o recorte de PR ANTES de aplicar, e
prefira aplicar quando não houver outra PR esperando merge.

---

## ⏰ ITEM 1 — #1710, e ele tem DATA: 24/08

O cron `attendance-seal-window-daily` está **ATIVO e no-op até 24/08**. Faltam **10 dias**. Se
ninguém conferir, ele executa sozinho e grava sem que ninguém tenha visto o que ia gravar.

**A tarefa:** re-medir o que a **primeira execução** vai gravar. Na medição de 13/08 eram 51 faltas
em 12 eventos, e o selo **anda nos dois sentidos** (marca presença e marca falta).

⚠️ **Como ensaiar sem gravar:** um dry-run antes do piso devolve `skipped: before_floor`. Para
exercitar de verdade, recuar o `floor_date` **DENTRO de transação abortada** (`BEGIN; ... ROLLBACK;`).

⚖️ **DECISÕES do PM sobre #1710/#1726, NÃO re-litigar:** selo **automático com janela e aviso** ·
86 ativos, janela de 14 dias, correção pelo líder da tribo · exige dry-run e reversão por evento
(**não existe `unseal`**). A comunicação **já foi enviada** e os 3 bloqueios caíram; as duas issues
seguem abertas.

---

## ITEM 2 — backfill do cache do #1587, e depois FECHAR a issue

⚖️ **DECISÃO do PM (14/08):** **backfill único, sem trigger.** Não criar trigger para manter o
cache: a view já é a fonte, e `cache_is_stale` serve de alarme se voltar a divergir.

**Medido em 14/08:** `SELECT count(*) FILTER (WHERE cache_is_stale) FROM
v_application_interview_state` = **106**, de **170** candidaturas. Re-medir antes de aplicar, e
capturar o **antes** e o **depois** por consulta viva (nunca derivar o "antes" do "depois").

A fonte do backfill é a própria view:

```sql
UPDATE public.selection_applications a
SET interview_status = v.interview_state
FROM public.v_application_interview_state v
WHERE v.application_id = a.id AND v.cache_is_stale;
```

⚠️ **Três cuidados antes de rodar:**

1. **`needs_reschedule` não pode ser destruído.** A view já o preserva (ela o lê do próprio cache),
   então o `UPDATE` acima é seguro por construção — mas **confirme** contando quantas linhas têm
   `needs_reschedule` antes e depois. Hoje é **1**.
2. **`stuck` é um valor NOVO** que a view emite e que o domínio antigo do cache não tinha. Decidir
   se ele entra na coluna ou se o backfill o mapeia para `scheduled`. Hoje são **2** candidaturas.
   O frontend não renderiza `interview_status` cru (só filtra por `none`/`needs_reschedule` e
   mostra um chip para `needs_reschedule`), então o risco de tela é baixo — **confirme com grep**.
3. É **DML**, então vai por `execute_sql`, não por `apply_migration`. Mas registre o backfill em
   migration se quiser rastreabilidade — e aí lembre do erro de sequenciamento acima.

⚖️ **DECISÃO do PM:** **feito o backfill, FECHAR a #1587.** Os 3 critérios da issue já estão
atendidos (varredura das 29 funções · view canônica · diagnóstico do dashboard); o backfill era o
que faltava para não sobrar trabalho.

---

## ITEM 3 — #1586, com o cap resolvido NO DESENHO

**Medido em 14/08:** **9** candidaturas em `interview_pending` no ciclo aberto, das quais **6** já
têm `interview_auto_rescue_count >= 1`. A RPC `selection_rescue_unbooked_invite` levanta exceção
nesse caso, então **uma tela entregue hoje recusaria 6 dos 9 casos que ela mostra**.

⚖️ **DECISÃO do PM (14/08):** **contador SEPARADO para o resgate manual.**

O racional, que precisa sobreviver à implementação: o invariante
`AI_unbooked_rescue_cap_respected` trata `interview_auto_rescue_count > 1` como **violação de
schema** (hoje em 0 violações). A coluna se chama `auto_rescue_count` — o cap de 1 existe para o
**cron** não spammar. Um resgate feito por **uma pessoa**, com autor autenticado e auditado, é
outra coisa, e por isso conta em coluna própria. Assim o invariante fica **intacto** e os 6 casos
se resolvem.

⚠️ **Não** afrouxar o invariante, **não** zerar o contador dos 9 (apagaria o histórico), e **não**
entregar a tela sem o cap resolvido.

**Contexto que torna isso dívida ativa, não melhoria:** hoje a única porta para despachar é o
`service_role`, e por ela toda operação manual (a) cai no allowlist do guard #1636, (b) gasta o
resgate **sem registrar autor**. A sessão anterior pagou exatamente esse preço e deixou uma entrada
de dívida no código.

---

## Depois desses três

- **#1664 fase 2** — a fila de VÍNCULO. As 31 `no_application` já estão classificadas na issue: 11
  linhas são a sonda do operador, **7 linhas / 6 pessoas** são candidatos REAIS que reservaram com
  outro e-mail. Encosta na **#1614** (mesma causa raiz: o endereço com que a pessoa AGENDA nunca é
  capturado).
- **#1762** — o rodízio concentra despachos quando o lote sai na mesma transação (`now()` é da
  transação, o LRD empata, o desempate por `member_id` decide). **Corrigir muda quem recebe
  candidato → precisa do PM.**
- **Onda E** (avaliação e decisão): #1572 (P0, aprovação sem avaliação não deixa trilha), #1575,
  #1574, #1573, #1576, #1634, #1581, #1579.

---

## 🔔 Pendência de OBSERVAÇÃO, com prazo em 28/08

O funil da onda D saiu do vácuo, mas **só até o despacho**. Medido em 14/08: **95** linhas, **1**
instrumentada, **0** aberturas, **0** reservas.

⚠️ **Nenhum número de conversão do funil pode ser publicado** até uma linha real carimbar
`first_opened_at` e `booked_at`. Isso depende do candidato abrir o link; o **token vence 28/08**.
Se vencer sem abrir, o mecanismo continua sem prova ponta a ponta e é preciso decidir com o PM se
provoca outro despacho.

Ao conferir, exija na linha nova: `instrumented = true` **e** `booking_token_md5` preenchido.

---

## Armadilhas da vizinhança, com o preço que já custaram

1. **Chamar RPC de escrita via `service_role` dispara o guard #1636.** O caminho deixa `caller_id`
   nulo, que é a MESMA digital de uma escrita de teste em candidatura real. Se for inevitável,
   saiba que vai precisar de entrada no allowlist — e que **apagar a linha, forjar carimbo de
   `cron_run` ou aceitar `dispatch_source='cron'` do metadata como prova são saídas REJEITADAS**
   (a última afrouxaria o guard para tolerar qualquer service_role; o cron real se distingue por
   carimbar a EXECUÇÃO, `selection.%cron_run%`, 197 linhas medidas).

2. **`apply_migration` recebe o SQL como STRING, não como arquivo** — DDL grande passa por
   transcrição. Feche o risco comparando `md5(regexp_replace(prosrc,'\s+',' ','g'))` do corpo vivo
   com o do arquivo local (mesma normalização do Phase C). E antes de transcrever, **tente não
   transcrever**: com o allowlist de drift vazio, o corpo vivo é byte-equivalente à última captura
   em migration, então dá para extrair o bloco do próprio repositório com `sed`.

3. **`apply_migration` cria a linha de tracking com timestamp PRÓPRIO.** Renomeie o arquivo local
   para casar com ele, ou o gate ADR-0097 fica vermelho.

4. **Mudança que afete o schema exige `npm run db:types` na MESMA PR** (gate `gen-types-drift`).
   ⚠️ O script falha em **silêncio** na cadeia com `&&`: rode `mktemp` + `supabase gen types`
   **separados**, confira tamanho e sentinela (`export type Json`), e **grepe o símbolo novo dentro
   do arquivo**. Uma view nova conta.

5. **`CREATE FUNCTION` concede EXECUTE a `PUBLIC` por padrão.** O `REVOKE ... FROM PUBLIC, anon` vai
   na MESMA migration. Views não herdam isso, mas conceda explicitamente mesmo assim, e prove com
   **sonda direta na porta** (chamar com a chave anon e exigir `status != 200`) — é mais forte que
   inspecionar o grant, e 150× mais rápido que os endpoints de auditoria de catálogo, que estouram
   timeout (#1742).

6. **A suíte de contratos offline (~75 s) é o gate barato antes da PR:**
   `env -u SUPABASE_URL -u SUPABASE_SERVICE_ROLE_KEY -u PUBLIC_SUPABASE_URL npm run test:contracts`.
   ⚠️ **Mas skip ≡ pass:** rode o arquivo novo **com** `.env` exportado antes de acreditar no guard,
   e confira `gh run list` antes (o `validate` com DB não tolera execução concorrente — #1505).

7. **Teste novo entra nas DUAS whitelists do `package.json`** (`test` e `test:contracts`,
   SEDIMENT-186.C). Esquecer uma desliga o teste em silêncio.

8. **Um guard antigo ficar vermelho pode ser o vermelho CORRETO.** Desça a afirmação um nível em
   vez de apagá-la — foi o que salvou o tratamento do #1636.

9. ⚠️ **Nunca escrever `close #N` / `fixes #N` / `resolves #N` num corpo de PR sem intenção de
   fechar, nem para CITAR o padrão.** E o espelho: **`Fecha #N` em português não fecha nada.**

10. ⚠️ **Branch nova nasce do HEAD, não da main.** `git checkout -b <nome> origin/main` explícito, e
    confira com `git merge-base --is-ancestor origin/main HEAD`. `--show-current` confirma o nome,
    não a BASE.

11. ⚠️ **O conector cacheia `tools/list`.** Tools novas só aparecem depois de recarregar o catálogo.
