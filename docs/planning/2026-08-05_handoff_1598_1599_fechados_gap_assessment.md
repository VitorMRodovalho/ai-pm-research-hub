# Handoff 05/08/2026 - #1598 e #1599 fechados, gap assessment da jornada entregue

> 🔒 **Candidatos aparecem como rotulos (`candidato A`, `candidata B`, ...), nunca por nome ou
> e-mail: este repositorio e PUBLICO.** A identidade de cada rotulo e recuperavel por consulta
> ao `selection_applications` com os ids/contagens citados. Mesmo criterio da
> `SPEC_INTERVIEW_BOOKING_INTEGRITY`, que nao nomeia nenhum candidato.

## 0. Arranque (colar depois do /clear)

> #1598 e #1599 estao entregues no PR **#1606** (branch `fix/1598-1599-rescue-refusal-and-cron-error-capture`).
> **Duas coisas antes de qualquer outra:** conferir se o #1606 mergeou, e **deployar o `nucleo-mcp`**
> (secao 4) - sem isso o lane RAW do MCP le recusa de gate como SUCESSO.
>
> O gap assessment esta em `docs/planning/2026-08-05_gap_assessment_jornada_candidato.md`. Ele
> reordena a fila: **o gargalo e a porta de ENTRADA do agendamento, nao a de saida.**
>
> Reancore todo numero. Effort `xhigh`.

---

## 1. O que foi entregue

### #1598 - a recusa de gate parou de destruir estado

Regressao do proprio #1594. Os 2 rescues chamavam `notify_selection_cutoff_approved` e nao checavam
o retorno; dependiam da excecao para atomicidade, que o #1594 removeu.

| | antes | depois |
|---|---|---|
| chamadores de `notify` que leem `->>'success'` | 1 de 3 | **3 de 3** |
| recusa em `unbooked_invite` | queima o cap=1, sem e-mail | devolve `{success:false}`, **nao toca a linha** |
| recusa em `stuck_interview` | cancela a entrevista, sem e-mail | devolve `{success:false}`, entrevista intacta |

A ordem inverteu: **despacho ANTES da mutacao** (o padrao que o #1595 usou em
`request_interview_reschedule`). O carimbo de idempotencia cai antes da chamada - senao o `notify`
devolve `already_sent` e nao despacha - e e **restaurado na recusa**. `updated_at` fica intocado no
caminho de recusa de proposito: o cron do stuck ordena por `updated_at ASC`, e bumpar a coluna numa
recusa jogaria a candidatura presa para o fim da fila.

**Exposicao real, e aqui o handoff anterior estava impreciso:** `stuck_interview` e quase imune por
construcao (exige linha de entrevista = modo `reuse_prior` = nao reavalia gates). O caso vivo e so
`unbooked_invite`. Alvo datado: **candidato H**, que entra no predicado do cron em **10/08**.

### #1599 - o cron parou de engolir a mensagem

| | antes | depois |
|---|---|---|
| execucoes consecutivas com erro | **6** (30/07 a 04/08), nao 4 | - |
| o que o audit guardava | so `error_count` | `errors[]` com SQLERRM + SQLSTATE + application_id |
| recusa de gate no cron | contada como RESGATE (`PERFORM` cego) | `refused_count` proprio |
| erro recorrente | invisivel | linha em `data_anomaly_log` |

**A causa historica e IRRECUPERAVEL, e o PR nao finge o contrario.** O `SQLERRM` nunca foi gravado, e
o corpo vivo do `notify` foi reescrito duas vezes desde entao (#1584 as 17:19 e #1594/#1595 as 19:50
de 04/08, **ambos depois** do ultimo run vermelho das 15:00 UTC). Sonda transacional (bloco `DO` que
captura e depois aborta - nada commitado, nenhum e-mail) confirma que a mesma chamada **sucede hoje**.
Nenhuma correcao foi atribuida a um commit por falta de prova.

### O que quase repetiu o erro do #1594

A correcao do #1598 **criaria o mesmo defeito um andar acima** se os crons continuassem com o
`PERFORM` cego: recusa viraria resgate na contagem. Por isso os dois crons entraram no mesmo PR.

E o inventario de consumidores - a metade que o #1594 esqueceu - encontrou **dois consumidores
cegos** que a minha propria mudanca criaria:

| consumidor | estado |
|---|---|
| `nucleo-mcp` lane semantico (`interview_manage`) | ja tratava (#1594) |
| `nucleo-mcp` lane **RAW** | corrigido aqui |
| `admin/selection.astro` (botao de resgate) | corrigido aqui |

A descricao da tool RAW afirmava *"One transaction - a re-dispatch failure rolls the cancel back"*.
**Falso desde o #1594**, e o modelo le essa frase. Reescrita.

---

## 2. Verificacao

- `npx astro build` ok. `npm test` **6320 / 6319 pass / 0 fail / 1 skip** (baseline 6307 + 13 novos;
  skip inalterado = os DB-aware rodaram). `npm run test:ef` 194/0. `deno lint` (flags do CI) +
  `deno check` limpos, 58 arquivos.
- **Phase C**: `drifted_definite 0`, `drifted_suspect 0`, `orphans_true 0`.
- **Tracking**: phantom `20260805004201` deletado por versao exata; `20260805000511` registrada.
- **Mutacao**: removidas as 2 checagens de consumidor -> exatamente os 2 guards falham. O guard de
  CLASSE ja tinha prova empirica: antes do fix, os 2 rescues estavam **ausentes** do conjunto que le
  `->>'success'`.
- **Residuo em producao**: 2 linhas VERDADEIRAS em `gate_attempts`; **zero** tokens, `campaign_sends`,
  `selection_dispatch_url_log` e e-mails. A candidatura usada (candidato H) ficou **byte-intacta**.
- `ef_version` **2.90.0 -> 2.91.0** de proposito: o `/health` volta a testemunhar o deploy do EF.

---

## 3. O gap assessment - o veredito muda a fila

Documento completo: `docs/planning/2026-08-05_gap_assessment_jornada_candidato.md`.

**A frase que resume:** o arco #1584/#1594/#1595/#1598 fechou a porta de **SAIDA** (quem e
convidado). A porta de **ENTRADA** (quem acaba agendado) nunca foi tocada, e e onde esta o estrago.

### O numero que reordena tudo

`calendar_booking_unmatched`, 30 dias: **12.237 linhas, de 11 eventos, 9 e-mails.** A decomposicao:

| classe | linhas | quem |
|---|---|---|
| **B - e-mail divergente** | **8.124** | 6 candidatos REAIS: candidato A (5.693, desde 17/07), candidata B (1.496 em 2 enderecos), candidata C (552), candidato D (308), candidato F (75) |
| **C - convidado errado no payload** | 3.975 | 100% `o e-mail do PM` - **o unico trafego ainda queimando agora** |
| allow-list / ciclo | 138 | candidato E (e-mail CORRETO, barrado por `final_eval`) + membro G (ciclo fechado) |

**candidato A e o caso mais grave da plataforma hoje**: `interview_pending`, tentou agendar 5.693
vezes desde 17/07, e a plataforma nunca viu nenhuma.

### Achados novos, alem da spec

- **5º escritor de status ausente da tabela da spec**: `admin_update_application(uuid, jsonb)` escreve
  `selection_applications.status` sem gate de objetiva. E gateado por `manage_platform`, entao pode
  ser o caminho de excecao do R1.4 - mas nao e declarado como tal nem exige motivo. **E o argumento
  novo a favor da Opcao 1 (trigger) da §4.1 da spec.**
- **A fila de e-mail NAO esta congestionada** (1 entregue hoje, cota 100, 0 pendentes, 0 throttled).
  Isso desbloqueia a ordem de execucao da spec, que pedia resolver a fila antes de tudo.
- **Classe D tem populacao viva ZERO** hoje (0 em `interview_noshow` no ciclo aberto). Latente, nao
  ativo - rebaixa a prioridade.

### Issues abertas por este assessment

| # | o que | fila |
|---|---|---|
| **#1609** | 12.237 linhas sem corte (R4.1) | **1** - nao depende de decisao do PM |
| **#1608** | retry nao cobre `daily_quota_exceeded`: 2 pessoas sem e-mail ha 32 dias | **2** - uma linha |
| **#1611** | balde de `unmatched` mistura "nao achei" com "ja decidido" | junto com a 1 |
| **#1610** | manifesto MCP classifica 3 escritas como `read` | avulsa |

R1, R2 e R3 **nao viraram issue de proposito**: dependem de decisao do PM que a spec ja enquadrou.

---

## 4. 🚨 PENDENCIA - o `nucleo-mcp` nao foi deployado

O shell do Claude nao tem Docker. Ate rodar, o lane RAW le `{success:false}` de
`selection_rescue_stuck_interview` **como sucesso** - dira ao modelo que o convite foi reenviado
quando o gate recusou e nada aconteceu.

```bash
supabase functions deploy nucleo-mcp   # padding
```

⚠️ **O prompt `!` come o ULTIMO caractere da linha** - terminar com `# padding`.

Depois do deploy, a verificacao ficou barata: `/health` tem de dizer **`ef_version 2.91.0`** (era
2.90.0). Foi bumpado exatamente para isso. Mais o smoke obrigatorio de `.claude/rules/mcp.md`:
`initialize` **e** `tools/list` (o segundo pega falha de Zod que o primeiro nao pega).

---

## 5. Decisoes do PM registradas nesta sessao

- **candidata I**: decidido **deixar o cron das 15:00 UTC rodar**. Ela esta presa ha 12 dias; o
  resgate voltou a funcionar e vai enviar o convite governado com token novo. Conferir depois das
  15:00 UTC que `rescued_count` foi 1 e que o e-mail saiu.
- **As 4 issues acima**: decidido abrir todas.

---

## 6. Fila daqui

| # | frente | nota |
|---|---|---|
| **0** | deploy do `nucleo-mcp` | secao 4. Barato, e a janela esta aberta |
| **1** | #1609 + #1611 (a hemorragia e o balde) | mesmo caminho, sem decisao pendente |
| **2** | #1608 (retry de e-mail) | uma linha, 2 pessoas reais |
| **3** | **decisao do PM: Opcao 1 vs 2 do gate unico** (§4.1 da spec) | recomendo a 1; o 5º escritor e o argumento novo |
| **4** | **decisao do PM: forma do e-mail alternativo de candidatura** (§4.2) | destrava a Classe B, que sao 6 candidatos reais |
| 5 | modulo admin | #1590, #1591, #1592 |
| 6 | 16 issues dos arquivos do PM | #1570-#1582, #1586-#1588 |

**Fora da fila:** o **A7 operacional** (tirar o link cru de circulacao onde foi publicado fora da
plataforma) segue com o PM. E a **cauda do A6**: reemitir token para os `approved` exige antes decidir
o que fazer com os **18 de 50 que falham P0001** - reemitir em lote hoje produziria 18 recusas
auditadas e nenhum e-mail.

---

## 7. Armadilhas novas desta sessao

- **`indexOf` devolve -1, e uma comparacao de ordem passa por acidente.** Um guard que afirma "A vem
  antes de B" tem de afirmar que **os dois foram encontrados** antes de comparar. Recortar por N bytes
  tem o mesmo defeito por outro caminho (foi o `p280-411-w1c`); fatiar entre ancoras reais resolve os dois.
- **`deno lint` sem as flags do CI reporta 345 problemas falsos.** O CI usa
  `--rules-exclude=no-explicit-any,no-import-prefix` sobre `supabase/functions/`. Rodar num arquivo so,
  sem config, nao mede nada.
- **`deno` nao esta no PATH do shell do Claude** - usar `~/.deno/bin/deno`.
- **O `cd` PERSISTE entre chamadas de Bash.** Um `cd` numa chamada anterior faz a proxima rodar no
  diretorio errado, e o erro aparece como "arquivo nao existe".
- **Mudar a descricao de uma tool do MCP quebra o gate do manifesto.** Rodar
  `node scripts/generate-mcp-manifest.mjs` no mesmo PR.
- **Alterar `ef_version` quebra um teste que fixa a versao**
  (`tests/contracts/mcp-lgpd-retroactive-operator-tools.test.mjs`). Ajustar junto.
- **Sonda segura para reproduzir falha em producao**: bloco `DO` que chama a funcao dentro de
  `BEGIN...EXCEPTION`, captura `SQLERRM`/`SQLSTATE`/`PG_EXCEPTION_CONTEXT`, e depois **levanta** para
  abortar a transacao inteira. Nada commita, nenhum e-mail sai, e a mensagem aparece no erro.

---

## 8. Armadilhas que seguem valendo

- **Placeholder nao e porta**: `https://calendar.app.google/...` nos 3 dicionarios e em
  `MemberDetailIsland.tsx` e o campo onde o avaliador cola a PROPRIA agenda. Nao remover.
- `selection_cycles.status` do ciclo vivo e `'open'`; a `phase` e `'evaluating'`.
- `members` nao tem coluna `status` - o flag e `is_active`; `state` e a UF.
- **Teste novo entra em DUAS listas do `package.json`** (`test` e `test:contracts`).
- **Testes DB-aware escrevem em producao e rodam serial.** `set -a; . ./.env; set +a` antes, conferir
  o **numero de skips**, e `gh run list` antes de rodar local.
- **Conferir a branch antes de `git commit`.**

Assisted-By: Claude (Anthropic) <noreply@anthropic.com>
