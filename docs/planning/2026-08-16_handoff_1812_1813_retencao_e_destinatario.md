# Handoff — a retenção que ninguém executava, o alerta sem destinatário, e o painel que não via nenhum dos dois

> Sessão de 16/08/2026 (tarde). Arranque anterior: `2026-08-17_PROMPT_ARRANQUE_1710_VESPERA_RETENCAO_E_1780.md`
> (ITENS 2 e 3 daquele documento). Handoff anterior: `2026-08-16_handoff_1809_metade_compartilhada_fechada.md`.
> **Tudo abaixo foi medido em 16/08/2026. Nada pode ser recitado — re-meça.**

---

## O que fechou

| issue | PR | o que era |
|---|---|---|
| **#1812** | #1815 (12/12, sem `--admin`) | `data_retention_policy` declarava 6 políticas ativas e não tinha executor nenhum |
| **#1813** | #1816 (12/12) | o alerta diário de consistência da seleção só alcançava `role='lead'`, e o ciclo aberto tem zero |
| **#1819** | #1820 (12/12) | `get_lgpd_cron_health` não via nem a varredura de retenção nem a cobertura das políticas |

`main` saiu de `524a311d` e fechou em **`28f8232d`**. Migrations **`20260816184810`** (#1812),
**`20260816191212`** (#1813) e **`20260816201138`** (#1819) — **cada uma aplicada com zero PRs abertas**
e mergeada antes da seguinte. Drift `0/0/0` depois das três.

**Edge Function `nucleo-mcp` deployada**: `ef_version` **2.101.0 → 2.102.0** (só o #1819 mexeu na EF).

## O que ficou aberto de propósito

**#1814** — `cleanup_type='archive'` não tem destino. Não existe tabela `*_archiv*` em `public`, e as
únicas colunas com esse nome (`content_products.archived_at`, `publication_ideas.archived_reason`) são de
outro domínio. As duas linhas seguem **ativas e descobertas**, nomeadas na base do ratchet.
**Primeira mordida em 2028-03-13** (board) e **2029-03-05** (presença) — sem urgência.

⚠️ **Risco de produto declarado na issue:** pontos de gamificação leem histórico de presença
(`sync-attendance-points`). Tirar linhas da tabela quente pode mudar cálculo retroativo. Confira antes
de escolher entre armazenamento frio genérico, tabela-espelho por origem, ou não arquivar.

---

## O achado que mudou o desenho no meio do caminho

A linha de `selection_applications` na tabela de retenção era uma **declaração duplicada e desalinhada**:
1095 dias (3 anos), enquanto o caminho revisado (`anonymize_premember_applications`, SPEC #905) roda a
**5 anos** e a recomendação legal é **2 anos rejeitado / 1 ano desistente**.

O cron `lgpd-anonymize-premember-monthly` está **inativo de propósito** — não é esquecimento. O SPEC #905
o registrou dormante atrás de um checklist de parecer legal (R1–R5), com **prazo máximo de ativação
sugerido em 30/09/2026**.

Um executor genérico que rodasse aquela linha passaria por cima de um portão jurídico. Ela passou a
**apontar** para o job dedicado, e seu `retention_days` foi para **1825** — o número que o job realmente
carrega (`p_years := 5`). O ratchet agora exige que o horizonte declarado seja igual ao argumento do job:
quando o parecer ratificar, os dois se movem juntos ou o CI fica vermelho.

📌 **Para o PM:** o prazo de 30/09 do SPEC #905 está a **45 dias**. R1–R5 são decisões de fora da
engenharia (ratificar janela, RoPA, base legal Art. 11 I para voz/vídeo, purga dos binários externos).

---

## O prazo real da retenção não é "zero linhas hoje"

As seis políticas alcançavam **0 linhas** — mas só porque a plataforma tem 155 dias. A data em que cada
uma passa a morder (linha elegível mais antiga + horizonte):

| tabela | tipo | horizonte | 1ª mordida | linhas hoje |
|---|---|---|---|---|
| `notifications` (lidas) | delete | 180d | **2026-09-09** | 6.671 (2.667 lidas) |
| `visitor_leads` (não convertidos) | delete | 90d | 2026-10-03 | 3 |
| `data_anomaly_log` | delete | 365d | 2027-05-13 | 165 |
| `board_lifecycle_events` | archive | 730d | 2028-03-13 | 3.341 |
| `attendance` | archive | 1095d | 2029-03-05 | 2.121 |
| `selection_applications` | anonymize | 1825d | 0 candidatos pelo anchor | 170 |

**A varredura entra em produção antes da primeira mordida.** `data-retention-sweep-daily`, `25 4 * * *`.

⚠️ **Re-meça a lacuna de pré-membro pelo ANCHOR da função, nunca por `created_at`.** `created_at` mínimo
de `selection_applications` é 2026-03-14 (a data da migração da plataforma, não do fato). Pelo critério
próprio: **0 candidatos a 5 anos e 0 a 3 anos**.

---

## Como cada peça foi provada

**#1812** — os três ramos de `DELETE` nunca tinham apagado nada. Em transação abortada, envelhecendo
linhas reais para dentro do corte: `n=2 v=3 a=4` envelhecidas → `notifications 2`, `visitor_leads 3`,
`data_anomaly_log 4` apagadas. Contagens conferidas depois: **6671 / 3 / 165 intactas**.
O guard fica **vermelho** com uma quarta política plantada (4 descobertas em vez de 3).

**#1813** — ponta a ponta, com uma anomalia plantada em transação abortada:
`alert_delivery = {"via":"manage_platform","notified_count":2}` e **2 notificações efetivamente
gravadas**, onde antes seriam zero. Com um lead promovido: `via_lead=1`, `via_gp=0` — o fallback não
dispara em paralelo. Nada persistiu (`scores_plantados=0`, `audit_do_ensaio=0`).

**#1819** — impersonando quem tem `view_internal_analytics` (a função resolve o chamador por
`auth.uid()` e devolveria `Not authenticated` para `service_role`), em transação abortada. O limiar foi
exercido **nos dois sentidos**, plantando uma linha em `cron.job_run_details`:

```
nunca-rodou         -> green   (a guarda IS NOT NULL funciona)
silêncio de 5 dias  -> red
silêncio de 1 dia   -> green
```

A linha plantada não sobreviveu (`0`).

---

## O painel de LGPD passou a ver a retenção (#1819)

`get_lgpd_cron_health` reportava quatro jobs e **nada** do que o #1812 tinha entregue. Agora reporta os
cinco (quatro mensais + a varredura diária) e ganha um bloco `data_retention` com a cobertura das
políticas e o motivo de cada lacuna.

**Quatro decisões de desenho, todas guardadas por teste:**

1. **A varredura é diária e tem driver de saúde próprio (2 dias).** O limiar de 35 dias dos mensais
   esconderia semanas de silêncio de um job que apaga linha todo dia.
2. **Nunca-rodou não é vermelho.** Sem a guarda `v_sweep_days_since IS NOT NULL` o painel ficaria
   vermelho no minuto em que subisse — a varredura nasceu com zero execuções.
3. **A cobertura é INFORMACIONAL, nunca driver de saúde.** A base declarada tem descobertas por desenho
   (#1814 e o portão do #905); painel sempre amarelo treina todo mundo a ignorar o painel. Quem cobra
   regressão é o ratchet no CI.
4. **`max_days_since_any_job_ran` não mudou de significado** — segue sendo sobre os mensais.

De quebra, a descrição da tool MCP dizia **"3 monthly crons"**, desatualizada desde o #905, que já tinha
levado o SQL a quatro. Corrigida, manifesto regenerado, EF deployada.

📌 **O `ef_version` estava igual no vivo e no fonte (`2.101.0`)** — o comentário do #1598 no bloco de
`/health` diz que o bump existe justamente para que UMA chamada a `/health` sirva de testemunha do
deploy. Bumpado para **2.102.0** junto com o guard de versão. Smoke pós-deploy: `initialize` HTTP 200 e
`tools/list` com **342 tools, zero erro** (o `tools/list` é o que pega a classe de falha de Zod que o
`initialize` não pega).

⚠️ **O conector cacheia `tools/list`:** o servidor já responde com a descrição nova (conferido no vivo),
mas um cliente MCP conectado só a vê depois que o cache dele expira.

---

## Os dois ratchets novos

`_audit_retention_policy_coverage()` — devolve **todas** as políticas ativas com `coberta` e o motivo,
para que lista vazia seja distinguível de guard cego. Cobertura exige job registrado, **ativo**, com ramo
implementado (derivado do **corpo vivo** da varredura, não de lista de nomes) e horizonte igual ao
argumento do job. **Base declarada: 3 descobertas.** Uma quarta derruba o CI.

`_selection_consistency_recipients()` — a resolução do destinatário virou função própria justamente para
que o teste **exerça a audiência sem provocar notificação**. Hoje devolve **2 via `manage_platform`**.

---

## Estado dos itens que não foram tocados

- ⏰ **#1710, prazo 24/08.** Config conferida no banco: `{"floor_date":"2026-08-24","grace_days":14}`,
  alterada em 13/08; cron `attendance-seal-window-daily` (`40 11 * * *`) **ativo**.
  **Re-medir em 23/08 pelos dois caminhos.** Última medição (15/08): 43 selam, 80 faltas, 40 pessoas —
  **é teto e encolhe**. A lista nominal das células fora do alcance de líder vai ao GP **na conversa**.
- **#1586** fecha na primeira chamada real de `rescue_unbooked`. ⚠️ **Não despachar para testar.**
- **Funil, prazo 28/08.** Falta `booked_at`. Nenhum número de conversão publicável.
- **EPIC #1780** — segue aberto: agregada de comentário e anexo (não existe nem em SQL), 4 definições de
  autoridade para a mesma ação, 8 verbos de curadoria sem porta MCP.
- **ITEM 4 do arranque anterior** (resolução por STATEMENT) — não atacado. Segue sendo o resto da classe
  #1805/#1809: função com duas ou mais relações da mesma coluna sai da cobertura dos dois ratchets.

---

## Lições desta sessão

1. 🔴 **"Zero linhas hoje" não é ausência de risco.** As seis políticas alcançavam 0 porque a plataforma
   é mais nova que o horizonte mais curto. O número que decide é a **data da primeira mordida**
   (linha elegível mais antiga + horizonte), não a contagem de hoje.
2. 🔴 **Antes de implementar uma política declarada, procure quem já a executa — e se há portão.**
   Quase entreguei um executor genérico que anonimizaria candidatura a 3 anos, passando por cima do
   portão de parecer legal do SPEC #905.
3. ⚠️ **Ramo que reporta `affected = 0` sem ter ramo é indistinguível de política cumprida.** Era assim
   que `archive` aparecia. Política não executada tem de sair com `handled=false` **e o motivo**.
4. ⚠️ **O qualificador do predicado sai da DESCRIÇÃO da linha, não da intuição.** A função aposentada
   inventou `status = 'resolved'` sobre uma tabela que não tem `status`.
5. 📌 **Um cron inativo pode ser governança, não esquecimento.** Antes de propor ativar, leia o SPEC.
6. 🆕 ⚠️ **Job diário não cabe no limiar de job mensal.** Enfiar a varredura no `max_days_since` dos
   mensais teria escondido semanas de silêncio e ainda dado um segundo significado ao mesmo campo.
   Cadência diferente pede driver próprio, e campo existente não muda de sentido.
7. 🆕 ⚠️ **Guard novo cujo estado normal é "lacuna" não pode dirigir sinal de saúde.** A cobertura das
   políticas tem 3 descobertas por desenho; ligá-la ao sinal deixaria o painel amarelo para sempre, e
   painel sempre amarelo é painel ignorado. Informação no corpo, cobrança no ratchet do CI.
8. 🆕 📌 **`ef_version` igual no vivo e no fonte apaga a testemunha do deploy.** Confira ANTES de subir:
   `curl .../nucleo-mcp/health` contra o literal em `index.ts`. Se forem iguais, bumpe (o guard de versão
   em `mcp-lgpd-retroactive-operator-tools` acompanha) — senão a prova do deploy vira grep no bundle.
