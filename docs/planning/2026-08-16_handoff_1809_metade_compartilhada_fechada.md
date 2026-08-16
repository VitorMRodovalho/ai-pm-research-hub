# Handoff — 16/08/2026: a metade compartilhada fechou, e achou um domínio que nunca mudou

> Sessão anterior: `docs/planning/2026-08-16_handoff_1805_classe_fechada_com_ratchet_de_dominio.md`
> Arranque desta: `docs/planning/2026-08-17_PROMPT_ARRANQUE_1710_VESPERA_1780_E_DIVIDA.md`
> Arranque da próxima: `docs/planning/2026-08-17_PROMPT_ARRANQUE_1710_VESPERA_RETENCAO_E_1780.md`
> Mapa da Fase 1 do EPIC: `docs/audit/EPIC_1780_FASE1_MAPA_BOARD_CARD.md`

---

⚠️ **Todo número abaixo foi medido em 16/08 e vários se movem sozinhos. Re-meça, não recite.**

## Estado ao fechar

`main` em **`5ccab55f`** (PR **#1810**, squash, **12/12 checks verdes, sem `--admin`**).
Duas migrations aplicadas e verificadas: **`20260816143638`** e **`20260816143735`**.
**Zero PRs abertas no início. Zero alertas Dependabot. Zero bypass na janela de 7 dias**
(69 commits, todos com `(#N)`).

| issue | desfecho |
|---|---|
| **#1809** | **FECHADA** — a metade `status` do #1805, ampliada para todas as colunas de nome compartilhado |

---

## O ITEM 3 do arranque pedia resolver alias por CONSULTA. Foi o que resolveu.

Para cada função, **quais relações que possuem aquela coluna o corpo referencia**. Exatamente uma =
o literal só pode ser daquela tabela. Medido: **409** funções comparam `status` a literal, **159**
com alias resolvível, 231 ambíguas, 19 sem tabela.

Ampliada para **todas** as colunas de nome compartilhado (decisão do PM), a varredura deu **20 pares
em 11 funções**. A **leitura do corpo** separou 6 falsos positivos, em dois padrões que o ratchet do
#1805 não conhecia:

- **gatilho** — `NEW.`/`OLD.` não citam a tabela no texto, então três gatilhos resolviam para a
  tabela **vizinha**;
- **alias de schema não-`public`** — `cron.job_run_details` fazia `get_ots_pipeline_health` parecer
  resolvida quando era ambígua.

Ambos estão fechados **por construção** no ratchet novo, não por lista de exceção.

---

## O achado maior não é literal morto, é um domínio que nunca mudou

`visitor_leads` nasceu (`20260319100033`) com CHECK **inline**, que o Postgres nomeia
`visitor_leads_status_check` automaticamente. A ARM-1 (`20260516890000`) tentou trocar o domínio com
`ADD CONSTRAINT` usando **esse mesmo nome**: bateu `duplicate_object`, e o próprio handler
`WHEN duplicate_object THEN NULL` — escrito para dar idempotência — **engoliu a mudança**.

Migration verde. Domínio parado em `new/contacted/converted/archived` enquanto o código de maio
escrevia `promoted`/`dismissed`. Provado em transação abortada:

- `promote_lead_to_application` e `dismiss_visitor_lead` **levantavam exceção em toda chamada**;
- `auto_promote_eligible_leads_for_cycle` falhava por lead **dentro** do `EXCEPTION WHEN OTHERS`,
  **desfazendo junto a candidatura recém-inserida**, e contabilizava como `errors`;
- `admin_audit_log` tem **zero** eventos `visitor_lead.*`. Nunca funcionou, e ninguém percebeu.

📌 **A forma correta é `DROP CONSTRAINT IF EXISTS` + `ADD`.** `ADD` isolado com nome que já existe
não é idempotência, é silenciamento.

---

## Antes → depois, medido pelo caminho real (impersonando, em transação abortada)

| o que | antes | depois |
|---|---:|---:|
| `visitor_leads` CHECK | `new/contacted/converted/archived` | `new/contacted/promoted/dismissed` |
| `get_tribe_credly_status(6)` — trilha | **0** | **4** |
| idem — PMI senior | **0** | **2** |
| `get_tribe_members_with_credly(6)` — membros com badge | **0** | **6** |
| filtros `revoked` / `onboarding` | sempre vazios | `offboarded` / `pending` |
| gate de comitê em 2 RPCs de leitura | `('lead','member')`, efetivo `lead` | `('lead','evaluator')` |

---

## 🔴 O conserto que eu quase entreguei INERTE

A troca `certificates.status = 'active'` → `'issued'` **não teria consertado nada**: o mesmo
predicado comparava `certificates.type` com `'trail'`/`'cpmai'`/`'cert_pmi_senior'`, e esses também
estão fora do domínio (`participation/completion/contribution/excellence/volunteer_agreement/
institutional_declaration/ip_ratification/alumni_recognition`). Nenhuma linha jamais os teve.

O literal errado era **sintoma de fonte errada**: os badges vivem em `members.credly_badges` (jsonb),
com **70 de 128 membros, 440 badges**. As categorias saem da EF `verify-credly`, que é quem escreve
(`trail`, `cert_cpmai`, `cert_pmi_senior`) — mapeamento derivado do **escritor**, não escolhido.

📌 Só apareceu porque a rede foi ampliada para todas as colunas. Escopar em `status` teria shipado
um conserto que não conserta.

---

## O gate de comitê conversa com o alerta sem destinatário

`selection_committee.role` é `evaluator/lead/observer`. Com `'member'` morto, o predicado
`role IN ('lead','member')` valia **`role='lead'` sozinho** — e há **3 leads, ZERO em ciclo em
andamento**, contra **5 evaluators (3 no ciclo aberto)** e 5 observers.

Ou seja: os avaliadores que estão de fato trabalhando o `cycle4-2026` não alcançavam
`get_application_ai_analysis_runs` nem `get_application_communications`. **É o mesmo fato-dado do
ITEM 2 do arranque anterior aparecendo por outra porta.**

O padrão `('evaluator','lead')` para leitura sobre candidatura foi **derivado do catálogo**
(`_get_peer_review_eligibility`, `get_selection_routing_overview`, `resolve_interview_booking_url`,
`submit_evaluation` já usam), não escolhido por mim.

---

## O que também entrou

- **`get_invitation_health`**: contador `canceled` morto, removido (o domínio tem `revoked`, já
  contado à parte). Decisão do PM.
- **Analytics**: `curation_status='approved'` → `'published'` (3×), `type='general'` → `'geral'`,
  `action='submission'` → `'submitted_for_curation'`.
- **`enforce_interview_audience_private`**: `'interview'` era morto, mas **NÃO era fail-open** —
  `'entrevista'` (143 linhas), `'1on1'` e `'parceria'` já cobriam o caso. Limpeza.
- **`recalculate_cycle_rankings`**: `'merged'` num `NOT IN`, efeito zero. Foi para **migration
  separada** — é a única função do caminho crítico de ranking.
- **`admin_run_retention_cleanup` aposentada** (decisão do PM): citava **três** colunas inexistentes
  (`notifications.read` → é `is_read`; `data_anomaly_log.status` → a tabela não tem; 
  `selection_applications.applied_at` → é `application_date`) e falhava na primeira.

---

## O ratchet, e o que ele NÃO alcança

`_audit_shared_state_literal_domain()` — irmão do `_audit_state_literal_domain()` do #1805.
**Linha de base ZERO**, cobertura **562 pares, 20 colunas, 268 funções, 48 tabelas**.

Provado **não-cego**: violação plantada em transação abortada levou **0 → 1**, acusada como
`_tmp_1809_prova_fn.curation_status = inexistente`, e nada persistiu.

⚠️ **Ponto cego declarado:** a resolução é conservadora de propósito — função que referencia **duas
ou mais** relações com a mesma coluna sai da cobertura, em vez de ser resolvida errado. Foi o que
salvou `get_ots_pipeline_health`, e o mesmo mecanismo tirou `get_invitation_health` (o `canceled`
dela foi achado por **leitura**, não pelo guard). Fechar esse resto exige resolução **por
STATEMENT** (qual tabela cada `UPDATE`/`DELETE` alcança), não por corpo inteiro.

---

## Os tropeços da sessão

1. 🔴 **Quase entreguei um conserto inerte** (seção acima). A lição não é sobre Credly: é que
   corrigir UM literal de um predicado com DOIS literais mortos não muda nada.
2. ⚠️ **Quase afirmei que a LGPD estava quebrada.** `admin_run_retention_cleanup` falha em toda
   chamada — mas **não está em cron nenhum**, e a anonimização roda por crons próprios e
   independentes. Antes de escalar a gravidade, conferir **quem chama**.
3. ⚠️ **`pgrep -f "<padrão>"` casa o PRÓPRIO watcher.** Um `until ! pgrep -f "astro build"; do sleep;
   done` rodando via `bash -c` tem a string `astro build` na **própria linha de comando** — o pgrep
   se enxerga, o laço nunca sai, e o build parecia travado quando já havia terminado. Ancore num
   padrão que não apareça no watcher (ex.: `node .*/\.bin/astro`).
4. ⚠️ **Meu primeiro contract test da aposentadoria ficou vermelho por ancorar no PRIMEIRO `DROP`.**
   A migration `20260426173951` já fazia `DROP` + `CREATE` para recriar a função, então o primeiro
   DROP tem um CREATE legítimo logo abaixo. O certo é ancorar no **último**.
5. 📌 **Não transcrevi corpo de função nenhum.** 12 corpos vivos provados idênticos às capturas do
   repositório por md5 normalizado (**12/12**), editados como arquivo com substituição **contada**,
   migration montada por concatenação, e o diff de cada função conferido linha a linha.
6. 📌 **Uma captura usava `CREATE FUNCTION` sem `OR REPLACE`** — erraria em função existente. Trocado
   por `CREATE OR REPLACE`, que ainda **preserva as ACLs** em vez de reconceder `EXECUTE` a `PUBLIC`.

---

## Conferência

- **Drift após as duas migrations: `drifted_definite=0`, `drifted_suspect=0`, `orphans_true=0`.**
- `check_schema_invariants()`: **44 invariantes, todas com `violation_count=0`**.
- Teste novo: **15/15, zero skips**, com `.env`. Registrado nas **duas** whitelists.
- Suíte offline: **6442 testes, 0 falhas**, 717 skip (portão de DB), 52,7 s.
- Build verde (**4m32s**, 0 erros). `lint:client-scripts` verde. `npm run db:types` regenerado.
  Manifesto MCP regenerado (`scripts/generate-mcp-manifest.mjs`).
- Arquivos locais renomeados para os timestamps de tracking; **sem fantasma, sem `migration repair`**.

---

## Aberto ao fechar

**#1710** (véspera 23/08, prazo 24/08 — re-medir pelos DOIS caminhos) · resto do **EPIC #1780** ·
**#1586** e o **funil de 28/08**, que só fecham com uso real · **#1592** · o alerta de consistência
sem destinatário · e **dois itens novos, registrados em #1809**:

- **`data_retention_policy` tem 6 políticas ativas e ZERO executor.** Isso já era verdade **antes**
  da aposentadoria, porque a função nunca chegou a executar: dois ramos `delete` citando coluna
  inexistente, o ramo `anonymize` com `applied_at` inexistente, `visitor_leads` **sem ramo nenhum**,
  e `archive` era `v_affected := 0`.
- **`lgpd-anonymize-premember-monthly` está INATIVO.** Lacuna **latente, não viva**: 170
  candidaturas, a mais antiga de **2025-08-11**, **zero** acima de 3 anos.
