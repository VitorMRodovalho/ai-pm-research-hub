# Handoff: o ITEM 1 verificado inteiro, a #1586 fechada, a retenção estreando e o vídeo aparado

> Sessão de 17/08/2026, madrugada UTC (03:31 a 05:30). Anterior:
> `2026-08-17_handoff_reuniao_geral_13ago_publicada.md`.
> Arranque que a originou: `2026-08-17_PROMPT_ARRANQUE_POS_DESPACHOS_1710_E_RETENCAO.md`.
>
> ⚠️ **Repo público.** Este documento conta população, nunca pessoa, e não publica identificador
> de membro nem de candidatura. Os nomes vivem na plataforma.

---

## O que entrou

| entrega | antes | depois |
|---|---|---|
| #1586 | aberta, esperando chamada real | **fechada**, 3 critérios provados |
| varredura de retenção | 0 corridas, `never_ran: true` | **1 corrida**, `succeeded`, painel verde |
| ponto cego do painel | não sabido | **#1829 aberta** |
| triagem das 56 (#1822) | base medida, sem classes | **5 classes** + achado de geografia suja |
| vídeo da geral de 13/08 | 1:36:05, abre na chegada | **1:33:13**, abre no conteúdo |

Estado de partida e de chegada, conferido nas duas pontas: `main` em **`508ce10d`**, **zero PRs
abertas**, **43 invariantes com zero violações**, **zero eventos de bypass** em 7 dias, EF
`nucleo-mcp` em `ef_version` **2.102.0**. **Nenhuma migration, nenhuma mudança de schema.**

---

## ITEM 1 (a): os 6 resgates de 02:45, conferidos

Os 6 despachos de 17/08 02:45:10 a 02:46:02 UTC estão íntegros: distribuição **4 para um
entrevistador e 2 para o outro**, todos com `booking_token_md5`, e
`selection_interviewer_blackouts` **vazia**, ou seja, zero bloqueios ativos ao fim.

📌 **Nenhum abriu e nenhum reservou** nos primeiros 50 minutos: `first_opened_at` e `booked_at`
nulos nos 6. O funil segue **103 linhas, 9 instrumentadas, 1 abertura, 0 reservas**, e a única
abertura é linha antiga, anterior ao lote.

## ITEM 1 (c): #1586 fechada, os 3 critérios um a um

Fechada às **03:35:06 UTC**. Citação em PR não prova entrega, então cada caixa foi provada:

1. **Superfície existe.** `rescue_unbooked` está no `z.enum` do EF vivo, mapeando para
   `selection_rescue_unbooked_invite`. ⚠️ O conector entregou o schema **em cache, com 4 ações**,
   e as 7 do EF publicado só aparecem lendo `nucleo-mcp/index.ts`.
2. **Autoria preservada.** As 6 linhas de audit têm `actor_id` não nulo, contra `NULL` em 100%
   das 19 anteriores, com `dispatch_source: 'manual'`, `rescue_path: 'manual'`,
   `rpc_version: 'p1586'` e contador próprio `interview_manual_rescue_count`, cap 3, separado
   do cap 1 do cron.
3. **Os 3 registros retroativos: anotados, não reescritos.** Estão em 2026-08-04, 00:13:26 /
   00:13:31 / 00:13:36 UTC. ⚖️ **Decisão: não corrigir.** Reescrever linha de trilha de auditoria
   para consertar atribuição anula a propriedade que faz a trilha valer, e a correção seria ela
   própria uma mutação sem registro.

## ITEM 1 (b): a pré-condição do cron, verificada pelo corpo da função

O predicado saiu de `_selection_unbooked_rescue_cron()`, não de suposição. Das 10 candidaturas
em `interview_pending` no ciclo aberto:

- **3** saíram da carência às 04:01 UTC e ficam elegíveis às **15:30 UTC de 17/08**;
- **1** só sai em **25/08**;
- as **6** manuais têm `auto_count = 1` e tiveram `cutoff_approved_email_sent_at` **re-carimbado**
  para 02:45, então voltam à carência apenas em **27/08**.

✅ **Zero sobreposição: convite duplicado é impossível.** A corrida em si ainda precisa ser
conferida, e é o ITEM 1 do próximo arranque.

## ITEM 1 (d): a varredura estreou e passou

Rodou às **04:25:00.090725 UTC**, `status='succeeded'` em **170 ms**, com **1 linha** em
`admin_audit_log` (`action='data_retention.sweep'`, `affected_total = 0`). As 3 políticas de
`delete` executaram com zero linhas afetadas, como esperado: nenhuma morde antes de 09/09.

Painel impersonado (`set_config` **antes** do `SET LOCAL ROLE`, em transação abortada) saiu de
`never_ran: true` para `never_ran: false`, `days_since_last_run: 0.013`, `health_signal: green`.

📌 **A divergência `2` contra `3` é benigna, não é drift.** A varredura conta como descoberta só
quem **não tem executor nenhum** (as 2 de `archive` do #1814); o ratchet
`_audit_retention_policy_coverage()` conta também `selection_applications/anonymize`, que tem
executor declarado porém **inativo** (o portão legal do #905). **Base declarada = 3, intacta.**

## O achado que virou #1829: o painel fica verde com a varredura FALHANDO

Lendo o corpo da RPC antes de confiar no sinal, apareceu um modo de falha não coberto. O único
gatilho de vermelho da varredura é `v_sweep_days_since > 2`, e `v_sweep_days_since` sai de
`max(start_time)` em `cron.job_run_details` **sem filtro de status**. O `pg_cron` grava a linha
mesmo quando o comando levanta, e `_data_retention_sweep_cron()` **não tem handler**, então nesse
caso o `INSERT` no audit nunca acontece.

Resultado: uma varredura que dispara e quebra todo dia mantém `days_since ≈ 0`, nunca cruza o
limiar e **o painel fica verde com zero evidência de trabalho**. `last_status`,
`failed_runs_last_90d` e `last_sweep` estão no payload e **nenhum é driver**; `get_operational_status`
encaminha só `health_signal`.

Hoje é **latente, não ativo**, porque a estreia foi bem sucedida. A correção mais forte proposta
na issue não é ler `last_status`, é **vermelho quando o job rodou e o audit não ganhou linha**,
que pega também a falha silenciosa: função que retorna sem levantar e sem gravar.

Classe conhecida nesta base: #1751 (`success` do transporte não prova o efeito) e #1710 (métrica
sobre linha gravada não vê a ausência de linha).

## ITEM 8: as 56 do #1822 triadas, e elas não são o que o nome sugere

Base reconfirmada: **270 examinadas, 208 com domínio, 6 por FK, 56 sem guarda** em 44 tabelas.
Os valores foram **amostrados**, não julgados pelo nome, e as 56 se separam em cinco classes:

1. **Geografia disfarçada de estado (11 colunas).** `members.state`, `persons.state`,
   `chapter_registry.state`, `selection_applications.state`, `volunteer_applications.state` e as
   `chapter*` guardam **UF**, não ciclo de vida. `CHECK` de estado seria errado.
2. **Vocabulário que cresce de propósito.** `admin_audit_log.action` (201 valores),
   `notifications.type` (56), `ai_processing_log.triggered_by` (11, com resíduo de smoke).
3. **Autoridade V4.** `engagement_kind_permissions.action` (22) e `.role` (20),
   `engagements.role` (20). Domínio fechado de verdade, mas conversa com a ADR-0009.
4. **Enumeração técnica fechada**, a melhor razão custo/benefício: `comms_*.channel`,
   `recurring_meeting_rules.visibility`, `event_agenda_block_audit.action`,
   `tribe_deliverables.status`, `partner_entities.status` e afins.
5. **Falso positivo pelo nome:** `pilots.scope` guarda um parágrafo de texto corrido.

⚠️ **Achado novo: a geografia já está suja**, o que muda a natureza do conserto. `persons.state`
tem `Goiás` convivendo com `GO` (**13 linhas** nas duas grafias) e **três grafias do mesmo lugar**
(`VA`, `Virginia`, `Virgínia`, **4 linhas**); `members.state` tem `Goiás` (4) e `Setúbal` (1);
`volunteer_applications.state` tem `11` em **2 linhas**; `selection_applications.state` tem
**string vazia** em 1. Isso não é `CHECK`, é normalização com FK para `chapter_registry`, e é
item próprio.

📌 **A decisão do PM continua sendo quais das 56 merecem `CHECK`.** A triagem acima existe para
tornar a decisão possível, não para substituí-la.

## O vídeo da geral de 13/08, aparado sem trocar a URL

O PM assistiu e apontou que os primeiros **2min52s** eram chegada e organização. O capítulo 2
ancorava em **02:54**, então a observação batia com o carimbo.

🔴 **O defeito atravessou a revisão porque eu dei a ele um TÍTULO DE CAPÍTULO**
(`00:00 Abertura, convidados e remoção dos notetakers`). Capítulo nomeado parece decisão
editorial, não sobra de gravação. A sessão anterior tinha acabado de aprender a conferir o
**fim**; o começo continuou cego. Regra curta: **corte as duas pontas.**

| | antes | depois |
|---|---|---|
| duração | 1:36:05 | **1:33:13** |
| capítulos | 37 | **36**, o primeiro em `00:00` |
| último capítulo | 1:34:06 | 1:31:14 |
| URL, views, playlist, banco | | **inalterados** |

⚠️ **A Data API v3 não corta vídeo.** Aparar a cabeça mantendo a URL é o **editor do YouTube
Studio**, caminho de navegador, e por isso não apareceu na sessão passada quando se concluiu
"YouTube não substitui arquivo". Isso continua verdade para **substituir**, e não impede
**aparar**. Procedimento medido: corte confirmado em `0:02:51:17`, processou em **~29 min**, e
o diálogo final avisa que a mudança é **permanente e sem desfazer** (original só por Takeout).

📌 **Zero escrita no banco.** O evento de 2026-08-13 segue com `recording_type='youtube'` e os
dois campos apontando para o mesmo vídeo. Era esse o ganho sobre re-upload: nenhum `playlistItem`
órfão, nenhum campo para atualizar, nenhuma dança de correção.

## Rastreado

- **#1829 aberta** (`type:bug`, `priority:medium`, `governance`, `mcp-server`): o painel verde
  com a varredura falhando. Sucessora direta da #1819.
- **2 memórias** escritas ou estendidas: o capítulo que legitima o tempo morto (com o
  procedimento completo do editor do Studio) e o índice atualizado.

## Aberto, para a próxima

- 🔴 **A corrida do cron das 15:30 UTC de 17/08** é o item mais perecível. As 3 estão elegíveis e
  a sobreposição é zero, mas o desfecho não foi observado.
- ⏰ **ITEM 2 bloqueado no PM**: os 2 aprovados já ativos precisam de **data e hora**. O
  entrevistador já está decidido, e com eles a rodada fecha 4 a 4.
- ⏰ **#1710, prazo 24/08**, re-medir em **23/08** pelos dois caminhos. Config conferida hoje e
  intacta (`floor_date: 2026-08-24`, `grace_days: 14`, cron ativo).
- **Funil, prazo 28/08:** nenhum número de conversão é publicável enquanto `booked_at` for 0.
- As 10 ações da reunião seguem **sem prazo**, e `roster_sealed_at` segue **nulo**, com 45 de piso.
- Os demais itens do arranque anterior seguem intactos: #1826, a triagem das 56, os 238 pares do
  #1805/#1809, #1814, o resto do EPIC #1780, #1664 e #1614, e o portão legal do #905 em 30/09.
