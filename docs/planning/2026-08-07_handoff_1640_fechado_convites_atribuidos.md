# Handoff — #1640 fechado, 4 convites despachados com atribuição humana (07/08/2026, madrugada)

> Supersede `2026-08-06_handoff_wave1_consentimento_medido_1586b_e_impasse_prs.md` no que toca ao
> ciclo seletivo. `main` em **`54fe0eb9`**. Arranque da próxima sessão:
> `2026-08-07_PROMPT_ARRANQUE_1642.md`.

---

## 1. O que fechou

**#1640** (PR #1648, mergeado 03:59 UTC). O gate `GATE_NO_AI` saiu da pré-condição do convite de
entrevista **e** do agendamento. Migration `20260807000200`.

### A decisão de escopo que não estava na issue

A issue escrevia só `_issue_interview_booking_token_core`. Medindo antes de codar, `schedule_interview`
tinha a **condição idêntica**, sobre a mesma população. E o argumento de "deixa para o #1643" caiu com
uma medição:

| medição pré-fix | valor |
|---|---|
| recusas `GATE_NO_AI` em `schedule_interview` desde 06/05 | **0** |
| agendamentos com `bypass_granted` sobre candidatura sem consentimento | **14** |
| desses 14, que já tinham 2 avaliações **e** nota | **13** |

Zero recusas não era imunidade: era **contorno**. O comitê passava por um bypass de admin que desliga
JUNTO o peer-review e a nota. Corrigir só o emissor deixaria o mesmo defeito um passo adiante, ainda
exigindo a via que enfraquece os outros gates. PM aprovou as duas RPCs.

### A população, re-medida na sessão

- **6** candidaturas em `interview_pending` sem consentimento no `cycle4-2026`
- **todas as 6** com 2 avaliações e nota objetiva calculada, isto é, o gate de IA era o **único** obstáculo
- **4** nunca tinham recebido convite algum
- os outros 28 dos 34 sem consentimento já haviam passado do ponto onde o gate morde

---

## 2. Os convites: 4 despachados, 2 que não precisavam

Despachados pela **tela** (`/admin/selection`, bulk invite), com o Chrome dirigido na sessão logada
do PM. Verificação pelo EFEITO, não pelo retorno:

| verificação | resultado |
|---|---|
| `cutoff_approved_email_sent_at` carimbado | 4 |
| tokens de agendamento emitidos | 4 |
| linhas em `selection_dispatch_url_log` | 4 |
| passagens no gate com `has_consent: false` no payload | 4 |
| `admin_audit_log` do despacho | 4, `dispatch_source: manual`, ator nominal |

**Nenhuma linha saiu como `cron` com `actor_id NULL`** — que era o risco inteiro de fazer isso por SQL.

**As outras 2 não estavam presas.** Têm convite vivo (31/07 e 04/08; 6,6 e 3,2 dias) e a carência de
agendamento é de **10 dias**. O rescue de não-agendados as alcança em ~10/08 e ~14/08 se não agendarem
— e agora consegue, porque era ele que acumulava as recusas do gate.

### Achado que corrige a ordem do arranque anterior

O arranque dizia "reprocessar só depois do #1586(a)". Isso vale para SQL e MCP, **não para a tela**:
`notify_selection_cutoff_approved` resolve por `auth.uid()` e só entra no ramo `v_is_cron` quando não
acha membro (service_role). Pela tela, carimba `manual` com o ator real. Mapa das três superfícies
comentado no #1586.

⚠️ Detalhe para automação: os dois caminhos de convite da tela passam por `confirm()` do navegador
(`selection.astro:4179` no bulk, `:4647` na linha), que **trava a extensão do Chrome**. Foi preciso
neutralizar o `confirm` durante o clique.

---

## 3. Verificação pendente do #1586(b): resolvida, e não era defeito

O handoff anterior pedia conferir se o cron das 16:00 UTC de 06/08 inseriu as notificações. **Zero
foi o esperado**: o PR #1638 mergeou em `2026-08-07T01:14:17Z`, ~9h DEPOIS daquela corrida. O corpo
com o bucket C não existia quando o cron rodou.

Entrega conferida sem escrever nada, replicando as CTEs: **2 apps detectadas × 2 managers = 4 pares
alvo, 4 sobrevivendo ao dedup de 7 dias**. A classe destinatária não está vazia.

E depois dos convites o bucket foi de **2 → 0**: a corrida das 16:00 de hoje vai achar nada **pelo
motivo certo** (a causa foi removida), não por alerta quebrado.

---

## 4. Os testes: três precisaram mudar de âncora, e o motivo é reutilizável

`1594-1595` e `1598-1599` escolhiam alvo **por predicado sobre produção** ancorado em "sem
consentimento → P0001". Removido o gate, o predicado continua casando e a chamada **deixa de observar
uma recusa e passa a executar o ato**: emissão de token real para candidato real (30 de ciclo fechado
e as 6 do ciclo aberto casavam), e no #1598 a "prova de recusa" destravaria a chamada do rescue, que
despacha e-mail.

`p472-corr3` assertava `'P0001'` sobre migration **congelada**: passaria verde para sempre afirmando
um gate inexistente no corpo vivo.

Os três reancoraram em peer-review incompleto (P0002). Memória gravada:
`reference-test-predicate-anchored-on-the-gate-you-remove-becomes-an-actor`.

⚠️ **Resíduo declarado:** a sonda do #1598 ficou **não exercida** — nenhuma candidatura
`interview_pending` do ciclo aberto recusa mais (as 11 têm 2 avaliações e nota). A população que
tornava a asserção exercível era, em boa parte, a que o gate barrava indevidamente. O teste imprime
isso alto em vez de passar calado.

Novo contrato: `tests/contracts/1640-ia-fora-da-precondicao-do-convite.test.mjs`, nas **duas**
whitelists do `package.json`.

---

## 5. #1649 — o vermelho de CI que não é de ninguém, e trava todo mundo

`1621 behavioural: estado saudável é SILENCIOSO` estoura o `statement_timeout` de **8s** que o
`service_role` herda do `authenticator`. Derrubou **3 das últimas 5 corridas** do `validate` na `main`
— inclusive um commit **só de docs** — e passou local com **6460 testes, 0 falhas, 1 skip**.

Causa medida: `_alert_sweep_cron` varre `cron.job_run_details` por Seq Scan — **150 MB, 146.203
linhas, só o pkey**, crescendo ~2.400 linhas/dia, e o filtro descarta 146.201 de 146.201 para
devolver zero. `reltuples` estava em **29** (estatísticas nunca coletadas); rodei `ANALYZE` na sessão
e foi para 146.203. A quente a RPC mede ~300 ms: o estouro é com cache frio sob a carga da suíte.

### Fechada no mesmo dia (PR #1663), depois de virar parede

O quadro piorou antes de fechar: o vermelho derrubou também o PR **#1659**, que tem **dois arquivos
markdown e nada mais**, e o rerun **deixou de resolver**. Placar do dia: 5 falhas contra 2 sucessos.
Um PR sem uma linha de código executável não causa timeout de statement — isso encerrou a discussão
sobre atribuição.

Duas direções foram descartadas **por medição, não por gosto**:

- **índice parcial** em `cron.job_run_details`: `ERROR 42501: must be owner of table` — a tabela é do
  pg_cron (dono `supabase_admin`) e o `postgres` não é membro dele;
- **limitar por `runid`** (o único índice existente): **3.294 ms contra 152 ms** do seq scan, porque
  troca leitura sequencial por 20 mil buscas no heap. Eu havia proposto essa saída antes de medir.

O que entrou: **teto próprio de 60s, local à transação**, porque 8s é orçamento de chamada
interativa do PostgREST e o chamador natural da varredura é o `pg_cron` (roda como `postgres`, sem
teto). E para o teto não ser máscara, a função passou a gravar **`duration_ms`** na mesma linha de
auditoria que já escrevia: a degradação vira número na superfície que o próprio #1621 lê, em vez de
vermelho intermitente. O teste afirma as duas metades juntas, e trava o `set_config` em `local` (um
`false` vazaria o teto para a conexão do pool).

---

## 6. Estado

| item | estado |
|---|---|
| `main` | `54fe0eb9` |
| #1640 | ✅ fechado (PR #1648) |
| #1642 | 🔓 **destravado** (era bloqueado pelo #1640 em prod) |
| #1641, #1643 | abertos, independentes |
| #1586 | aberto, enriquecido com o mapa das 3 superfícies |
| #1649 | novo, aberto |
| #1556 | aberto (irmã da Wave 0) |
| #1637 Dependabot astro 6→7 | **não mergear** (política #611) |
| bypass, janela 7d | **1 de 2** (nenhum usado nesta sessão) |
| migration head | `20260807000200` (phantom do `apply_migration` deletado) |

---

## 7. Armadilhas medidas nesta sessão

- **DDL em prod antes do merge serializa os PRs abertos.** Mergeei o #1646 primeiro e esperei o CI da
  `main` terminar antes de aplicar — porque a suíte ANTIGA rodando contra o banco NOVO cunharia token real.
- **`apply_migration` cria a phantom row** com timestamp real, que ordena acima da sequência sintética.
  Deletar (1 por chamada) e `supabase migration repair --status applied <sintético>`.
- **`confirm()` da página trava a extensão do Chrome.** Neutralizar antes de clicar.
- **`service_role` não define `statement_timeout`**: herda 8s do `authenticator`. É esse o teto de
  qualquer RPC chamada pela suíte.
- **Estatística de tabela de sistema pode nunca ter sido coletada.** `reltuples=29` numa tabela de
  146 mil linhas muda o plano inteiro.
- **`npm test` com `.env` exportado**: 6460 testes, **1 skip**. Se aparecerem ~548, o `.env` não subiu.
