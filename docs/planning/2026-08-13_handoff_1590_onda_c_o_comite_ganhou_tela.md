# Handoff - #1590 onda C: o comitê ganhou tela, e o rodízio ganhou uma causa (13/08/2026)

> Continuação de `2026-08-13_handoff_1590_ondas_A_e_B_mergeadas_e_a_onda_C.md` e do prompt de
> arranque `2026-08-13_PROMPT_ARRANQUE_1590_ONDA_C.md`.
>
> `main` em **`e67c3577`**, PR **#1761** mergeada com **12/12 verdes**, **zero bypass**.

## Regra zero

Todo número deste documento foi medido em 13/08/2026. **Re-medir na mesma volta** em que o número
entrar numa decisão, num commit, numa issue ou numa pergunta ao PM. Vale em dobro para o roteamento:
a onda C entregou a superfície que DESCREVE exatamente esses números, e eles andam sozinhos a cada
candidato que clica.

---

## Decisões do PM nesta sessão - NÃO re-litigar

1. **URL de agenda: autosserviço + GP.** Cada membro do comitê edita a URL da própria linha;
   `manage_member` edita a de qualquer um. Simetria com a decisão de 13/08 sobre bloqueio.
2. **Painel visível às 11 pessoas que já entram na tela.** A URL crua sai só na própria linha e para
   GP; o resto do público vê "tem agenda / não tem".

## O que estava errado no briefing, e foi medido antes de codar

1. **A aba "Comitê" JÁ existia** em `/admin/selection` (adicionar e remover, via
   `manage_selection_committee`). O que não tinha superfície era o resto: `interview_booking_url`,
   `can_interview`, os bloqueios e qualquer visão do rodízio. A onda C **estendeu** a aba.
2. **A aba era escondida por `manage_member`, e a RPC é gateada por `promote`** — dois vocabulários.
   Hoje as populações coincidem (as mesmas 2 pessoas de 87 ativas), então a divergência é latente.
3. **O avaliador não conseguia cadastrar a própria agenda em lugar nenhum.** A única tela de URL é
   `/admin/members/[id]` (tier superadmin) e edita `members.interview_booking_url`, o caminho de
   **menor** precedência. Foi o caso que nomeou a onda.

---

## O que entrou na main (PR #1761)

### Migration `20260813181215`

| função | o que faz | gate |
|---|---|---|
| `get_selection_routing_overview(cycle)` | por pessoa: papel, os 3 eixos, motivo explícito de não-roteável, janelas, contagem e data do último despacho | comitê ∪ `sponsor` ∪ `manage_member` ∪ superadmin |
| `set_interviewer_routing_block(...)` | tira do rodízio por PERÍODO, sem apagar a agenda | própria linha ∪ `manage_member` |
| `clear_interviewer_routing_block(id)` | devolve ao rodízio; janela inteira vai para `admin_audit_log` | própria linha ∪ `manage_member` |
| `manage_selection_committee(... +2)` | ganha `update` (URL + `can_interview`); add/remove inalterados | recurso; papel exige `promote`; RELIGAR exige `manage_member` |

⚠️ **O público da leitura é o da TELA, não o da RPC vizinha.** Espelhar `get_selection_dashboard`
(`view_internal_analytics` ∪ comitê) abriria 6 `chapter_liaison` numa rota de PII de candidato — a
lição medida da onda A. Medido sobre o predicado novo: **11 pessoas, zero a mais nas duas direções**.

⚠️ **Hardening que veio junto:** `manage_selection_committee`, uma RPC de **escrita**, estava
alcançável por `anon` (classe do #1592). As quatro nascem com `REVOKE ... FROM PUBLIC, anon` na mesma
migration.

⚠️ **`p_role` perdeu o default `'evaluator'`.** Com ele, o `update` não distinguia "não mandou papel"
de "mandou avaliador", e um autosserviço que só troca a URL rebaixaria um lead em silêncio. O branch
`add` aplica `COALESCE(p_role,'evaluator')`, então a chamada de 4 argumentos não mudou de sentido.

### MCP - ef `2.96.0`, `/semantic` `0.14.0`, **sem tool nova**

`selection_dashboard scope='routing'` · `interview_manage action='block'|'unblock'` ·
`selection_decide committee_action='update'`.

O fail-fast proativo do `selection_decide` **passa a conhecer o autosserviço**: ele existe para dar
erro melhor, não para ser um segundo gate, e recusaria justamente quem a RPC autoriza.

⚠️ **O conector do Claude cacheia `tools/list`.** A chamada `scope='routing'` funcionou ao vivo nesta
sessão, mas um cliente que não recarregou o catálogo ainda não vê os `enum` novos.

### A tela

A aba **deixa de exigir `manage_member`** — era o que deixava o avaliador sem porta. Quem escreve o
quê é decidido **por linha**, com `is_self` e `caller.can_manage` que a própria RPC devolve. Os
controles de comitê (adicionar/remover) continuam com `data-sel-requires="manage_member"`: abrir a
ABA não abre a ESCRITA de comitê.

40 chaves de i18n nos 3 dicionários. Os rótulos de motivo e de precedência são **lookup pelas chaves
que a RPC devolve** (`role_not_routable`, `committee_override`, …) — tela e auditoria não descrevem a
mesma decisão com vocabulários diferentes.

---

## O achado da sessão: o rodízio tem causa, e ela virou a #1762

O 8/5/4 que três handoffs registraram como "sem explicação medida" **tem explicação**.

`dispatched_at` cai no default `now()`, que é o instante da **transação**, não da linha. Quando um
lote de despachos sai numa transação só, todas as linhas recebem **o mesmo timestamp**; depois do
primeiro do lote, todo mundo empata no lookback do LRD, e o desempate `sc.member_id` escolhe **sempre
a mesma pessoa**.

| instante | despachos | distribuição |
|---|---|---|
| `2026-08-06 17:29:07.94225+00` (timestamp idêntico = um lote) | 5 | **3** para o menor `member_id`, 1 e 1 |
| `04:01:47` → `04:01:49` de 07/08 (transações separadas) | 4 | gira certo |

Os 3 excedentes são exatamente a diferença. **Não foi corrigido nesta onda de propósito:** mexer no
picker misturaria "dar porta ao que existe" com "mudar quem recebe candidato". Por isso o painel
publica **fatos** (contagem, último despacho) e **nunca "próximo da fila"** — a nota está na tela,
nos 3 idiomas. Caminhos possíveis estão na **#1762**; qualquer um exige decisão do PM.

---

## Estado medido do roteamento (13/08, pós-merge, pelo conector)

| medida | valor |
|---|---|
| roteáveis hoje | **3** (Fabricio, Fernando, Vitor — todos `committee_override`) |
| bloqueados hoje | **0** |
| observadores | 4, todos com `role_not_routable` + `no_booking_url` |
| despachos | Vitor 63 · Fabricio 20 · Fernando 4 (94 no total, com 7 `cycle_fallback` de leader) |
| `selection_interviewer_blackouts` | 0 linhas — a superfície existe, o mecanismo ainda **não foi exercido em produção** |

⚠️ **Zero bloqueio é ausência de uso, não imunidade.** O invariante do contrato que verifica
"ninguém foi roteado para quem está bloqueado" é **vácuo** enquanto ninguém pausar pela tela.

---

## Como isto foi verificado

- **Prova comportamental em transação abortada**, atuando como cada perfil (21 passos): avaliador lê
  o painel e vê só a própria URL · bloqueia a si mesmo e sai do rodízio · bloquear outro, trocar URL
  alheia, auto-promoção a `lead` e auto-religamento **recusados** · `javascript:` recusada ·
  observadora cadastra URL e **continua não-roteável** · forasteiro não lê o painel · GP bloqueia
  terceiro. No picker: bloquear o escolhido passa ao próximo, comitê inteiro cai em `cycle_fallback`,
  janela futura não bloqueia hoje. Depois do ROLLBACK: 0 bloqueios, 0 auditorias, 0 URLs de prova.
- **A tela foi exercida de verdade** (dev server + Playwright, payload no formato da RPC), atuando
  como avaliador sem `manage_member`: aba visível, 3 linhas, resumo "1 de 3 podem ser escolhidos
  hoje", própria linha com editar/pausar, linha alheia sem escrita, cartão de adicionar e botão de
  remover escondidos, motivos traduzidos, nenhuma promessa de fila.
- **Bateria de mutação, 6 mutantes → 6 vermelhos** (3 no SQL, 3 na tela).
- Suíte offline de contratos **0 fail**; guard novo 14/14 com credenciais, incluindo paridade md5 do
  corpo VIVO contra a captura da migration.

## Armadilhas pagas nesta sessão

1. **Dois contadores pinados que a varredura não acha** (classe do #1755): a versão da superfície
   `/semantic` é pinada em `semantic-envelope-w6b` **e** num cross-guard do #1710 que lê o TÍTULO do
   teste vizinho; mais o manifesto de `/docs/mcp`. Só a suíte offline inteira acha os três.
2. **O guard da onda A ficou vermelho, e era o vermelho CORRETO** — ele afirmava que a aba declara
   `manage_member`, e o significado da aba mudou. Foi atualizado descendo a afirmação um nível (as
   âncoras viraram o cartão de adicionar e o botão de remover), nunca apagado.
3. **A primeira versão do guard novo passou num mutante**: renomear `not_routable_reasons` deixava os
   quatro motivos no corpo e a tela sem eles. O guard passou a afirmar o NOME do campo também.
4. **`npm run db:types` falha em silêncio dentro do sandbox** (o `mktemp` escreve em `/tmp`, que é
   bloqueado). O `&&` da cadeia esconde o erro: o arquivo simplesmente não muda. Rodar com
   `TMPDIR=<scratchpad>`.

---

## Para a próxima sessão

**Onda D do #1590** — o que o briefing levantou e nenhuma onda tocou: a tentativa de agendamento que
falha **não deixa linha**, então qualquer métrica de sucesso diz 100% por construção. Junto:
#1664 (fila de reservas sem candidatura), o caminho do portal que cunha token novo a cada clique sem
incrementar `access_count`, #1587, #1586, #1614.

**Ou a #1762**, se o PM quiser equalizar o rodízio antes — é pequena, mas muda quem recebe candidato.

⏰ **Compromisso com data que não é desta lane:** antes de **24/08** alguém precisa re-medir o que a
primeira execução do cron de selo do #1710 vai gravar.
