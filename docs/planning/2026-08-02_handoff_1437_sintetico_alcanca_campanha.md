# Handoff 02/08/2026 (tarde) — o dado de teste que virou destinatário de campanha

> ⚠️ **Nenhum número aqui vale como medição.** Todos foram medidos em 02/08 entre 12h e 22h UTC e
> derivam a partir daí. Re-consulte a fonte antes de usar qualquer um em decisão, commit, PR ou memória.

Continuação de `2026-08-02_handoff_trilha_a_adesao_webinar_04ago.md`. O item que aquele handoff
deixava para o Vitor ("disparar a campanha") **foi feito por ele**; esta sessão mediu o resultado e
foi atrás da única falha de envio, que revelou um defeito estrutural.

## 1. Trilha A: entregue e no ar

Campanha `webinar-t6-04ago-membros` (`send_id` `a48fff86-e955-4c1e-a01e-a00a37bfae21`), disparada
02/08 **13:34 UTC**. Medido ~2h depois:

| | |
|---|---|
| destinatários | 89 |
| entregues | 88 |
| aberturas | 27 |
| cliques | 6 |
| descadastros / bounces / reclamações | 0 / 0 / 0 |
| falhas | 1 (ver seção 2) |

**Posts pendentes, conferidos e válidos** (saem sozinhos pelo cron `publish-scheduled-social`, a
cada 15 min):

| peça | quando (UTC) | arte |
|---|---|---|
| LinkedIn IMAGE lembrete D-1 | 03/08 14:00 | `t6-linkedin-1200x627.png` |
| IG STORIES lembrete D-1 | 03/08 23:00 | `t6-story-1080x1920.png` |
| IG STORIES "começa agora" | 04/08 21:50 | `t6-story-comeca-agora-1080x1920.png` |

As 3 artes respondem HTTP 200. Conferi visualmente a do LinkedIn e a de "começa agora": data
(4 de agosto), horário (19h às 20h30 Brasília), nomes (Fernando Carvalho / Clendson Gonçalves,
mediação Denis Vasconcelos) e framing institucional corretos. O texto do LinkedIn D-1 tem o rótulo
`Link do evento:` com a URL do Airmeet, sem hashtag e sem travessão.

✅ **Dependência manual, já resolvida:** a arte de "começa agora" diz **"Link na bio"**. O Vitor
colocou o link na bio do Instagram à mão em 02/08. Sem isso a peça apontaria para o vazio no dia do
evento — a bio não é gerenciada por nenhum cron da plataforma.

## 2. O defeito: um membro de teste entrou na audiência real

A única falha de envio foi para `test-sync-updated-…@example.com`. Investigando:

Existem **10 linhas sintéticas** `Test Sync Member __205_synthetic__` na produção, criadas por
`tests/contracts/member_emails.test.mjs` entre 04/07 e 31/07. A **#1437** já havia mapeado 9 delas
e as soft-retirou em 20/07 — **a 10ª nasceu em 31/07, depois daquela limpeza.** Ela ficou
`is_active = true` + `current_cycle_active = true`, que é exatamente o predicado de audiência de
`admin_send_campaign`, e por isso foi selecionada como qualquer membro.

**Só o domínio `example.com`, que a Resend recusa, impediu o dado de teste de chegar a uma pessoa.**

### Não ficaram parados: consumiram superfícies reais

| superfície | linhas apontando para as 10 |
|---|---|
| `pii_access_log` | **621** (`affiliation_verification_queue`, `affiliation_verification_bulk`, `audit_drive_offboarding_access`, `get_drive_teardown_overview`) |
| `member_offboarding_records` | 9 |
| `drive_teardown_scans` | 9 |
| `campaign_recipients` | 1 (hoje) |
| `notifications` | 1 |

Filas de verificação de afiliação, varreduras de teardown do Drive e registros de offboarding
trataram entidades fictícias como membros.

### Causa raiz

O cleanup do teste dependia do processo **chegar ao fim** — e não chega sempre (run de CI cancelado,
timeout, Ctrl-C). Pior: o step 9 zerava `testMemberId` **antes** de confirmar o delete, o que
desarmava a rede do `finally` justamente quando ela era necessária. E PostgREST responde **204 a um
DELETE que não removeu nada**, então o teste dava o cleanup por feito.

### Por que a purga trava

`pii_access_log.target_member_id` é `REFERENCES members(id)` **sem `ON DELETE`** (NO ACTION), assim
como `campaign_recipients.member_id` e `notifications.recipient_id`. Com log gravado, a linha prende
a si mesma. Purgar de fato exigiria apagar **621 linhas de log de acesso a PII** — decisão do Vitor,
deliberadamente **fora** deste PR.

## 3. O que foi feito

1. **10ª soft-retirada** (mesmo tratamento ratificado em 20/07, reversível, sem tocar no log).
   Antes → depois: audiência `all` **89 → 88**; domínio reservado alcançável **1 → 0**;
   `check_schema_invariants()` **0 violações**.
2. **Cleanup do teste refeito**: varredura por marcador que roda **antes e depois**, purga o que dá
   e soft-retira o que não dá; `testMemberId` só é zerado com o delete confirmado; o `finally` não
   asserta (um `finally` que lança substitui a falha real que levou até ele).
3. **Defesa na fonte do envio** (migration `20260805000502`): `admin_send_campaign` exclui domínios
   reservados por RFC 2606/6761 dos **dois** laços (membros e contatos externos) e não os conta em
   `recipient_count`. Verificado contra os 131 e-mails reais: exclui **exatamente as 10 sintéticas e
   nenhum membro legítimo**.
4. **Guard novo** `tests/contracts/1437-synthetic-member-never-reachable.test.mjs`, ligado ao `test`
   e ao `test:contracts` (2 ocorrências no `package.json`).

### Duas decisões de autoria do guard que vale preservar

- O invariante é **"não PERSISTE alcançável"**, não "não existe". Enquanto `member_emails.test.mjs`
  roda legitimamente, existe um sintético ativo por alguns segundos; como runs de CI compartilham o
  banco de produção (#1505/#1261), uma checagem de existência pura ficaria vermelha porque um run
  **concorrente** estava fazendo seu trabalho. A janela de graça de 30 min desenha essa linha
  explicitamente em vez de deixá-la à sorte.
- A checagem **itera** as linhas ofensoras e as reporta. Um `assert.match` existencial passaria
  assim que uma linha parecesse boa enquanto outras derivam.

**Mutation-testado:** com uma sintética reativada o guard fica vermelho; revertido em seguida.

Descoberta lateral: `is_active` é **derivado por trigger** — um `UPDATE ... SET is_active = true`
isolado volta `false` enquanto `member_status = 'inactive'` / `offboarded_at` persistirem. Para
mutar de verdade é preciso mexer na fonte (`member_status` + `offboarded_at`), não na coluna.

## 4. Aberto, e o que depende do Vitor

- **#1562 (nova)** — `include_inactive` **anula a segmentação inteira** da campanha. A cláusula
  `v_all OR v_include_inactive OR (roles…)` torna tudo verdadeiro, então marcar "incluir inativos"
  com um filtro de papel escolhido não manda para "aquele papel, ativos e inativos": manda para a
  **base inteira** (131 contra 88). O aviso "não marcar o checkbox" já circulou como instrução de
  operação; instrução de operação não é defesa, o próximo operador não a tem. **Não corrigido neste
  PR de propósito** — muda comportamento de segmentação e merece teste das 4 combinações.
- **#1437 continua aberta** com os dois pendentes originais: a purga de fato (bloqueada pela decisão
  sobre as 621 linhas de log de PII) e a redefinição de "membros ativos" para operacional-only (→72).
- ~~Link na bio do Instagram antes de 04/08~~ — feito à mão pelo Vitor em 02/08.
- Sem trabalho nesta sessão: **#1561**, #1556, #1205, #1557, #1558, #1560; trilha B (base legal dos
  941 externos, desbloqueada); 66470 com `essay_mapping` vazio; divergência de título entre
  plataforma e Airmeet; os 2 webinares de 2025 ausentes de `webinars`.

Assisted-By: Claude (Anthropic) <noreply@anthropic.com>
