# Handoff - #1590 ondas A e B mergeadas, e o que a onda C precisa (13/08/2026)

> Continuacao de `2026-08-12_BRIEFING_SESSAO_PLANEJAMENTO_ADMIN_SELECAO.md`, que era o pedido.
> Este documento e o **desfecho da sessao de planejamento mais duas ondas entregues**.
>
> `main` em **`994a969f`**, **0 PRs abertas**, **zero bypass** na janela de 7 dias.

## Regra zero

Todo numero deste documento foi medido em 12-13/08/2026. **Re-medir na mesma volta** em que o numero
entrar numa decisao, num commit, numa issue ou numa pergunta ao PM. Isso vale em dobro para a onda C,
que decide SUPERFICIE a partir de "quem esta cadastrado para roteamento".

---

## O diagnostico que abriu a sessao (onda 0, feita)

O caso "o Fernando nao acessa `/admin/selection`" **nao era dele e nao era do servidor**. Provado em
transacao abortada atuando como o `auth_id` dele: `get_selection_dashboard()` devolveu payload de 3
chaves e **zero erro**. Quem recusava era o gate client-side, e o dado que resolveria ja chegava ao
navegador (`get_member_by_auth()` devolve `selection_committee_role: "evaluator"`).

Coorte medida sobre `cycle4-2026`:

| superficie | predicado | passavam |
|---|---|---:|
| drawer global | tier>=admin U `sponsor` U comite | 11 |
| `get_selection_dashboard` (a RPC) | `view_internal_analytics` U comite do ciclo | 11 |
| a pagina (`canAccessAdminRoute`) | tier>=admin | **2** |

As 9 do meio: 1 avaliador, 4 observadores do ciclo vivo, 4 sponsors.

## O que entrou na main

### Onda A - PR #1743, commit `5d7c4064`, 11 checks verdes

- `src/lib/admin/route-access.ts` (novo): autoridade de rota extraida de `constants.ts`, que
  arrastava i18n e dados de tribo e por isso so podia ser testada por regex. `constants.ts`
  reexporta; nenhum call site mudou.
- A pagina passou a conhecer o eixo de comite e a designacao `sponsor`. **11 no menu, 11 na pagina,
  divergencia zero nas duas direcoes.**
- Modo somente-leitura por CSS global sobre `data-sel-requires` (a tela reinjeta quase tudo por
  `innerHTML`; varredura JS falharia no render que esquecesse de chama-la). Ausencia de atributo
  ESCONDE, entao boot com erro deixa a tela sem escrita em vez de com tudo.
- `AdminSidebar` ganhou `routeKey`, em OR com a permissao V3.

⚠️ **Decisao que mudou depois de medir, NAO re-litigar:** a primeira versao espelhava o predicado da
RPC (`view_internal_analytics` OU comite). Isso zerava a coorte de 9 e **criava 6 no sentido
inverso** - 6 `chapter_liaison` de capitulo entrariam numa rota `lgpdSensitive` por uma porta que o
menu nunca ofereceu. A pagina passou a espelhar o **publico do drawer**, de proposito mais estreita
que a RPC. Estender aos 6 e decisao do PM. O contrato fica vermelho se alguem reintroduzir o eixo.

### Onda B - PR #1745, commit `994a969f`, 12 checks verdes

Migration `20260813023435`. Tres eixos agora separados:

| eixo | significado |
|---|---|
| `selection_committee.can_interview` | desligamento PERMANENTE |
| `interview_booking_url` | CAPACIDADE (tem calendario) |
| `selection_interviewer_blackouts` (nova) | ELEGIBILIDADE por periodo |

Antes havia uma coluna para duas perguntas, e a unica forma de sair do rodizio era APAGAR a URL.

**A borda de fuso foi medida, nao argumentada.** A prova rodou as 02h35 UTC de 13/08 = 23h35 de
12/08 em Brasilia, dentro da faixa em que as datas divergem. Mesma janela, mesmo instante:
`(now() AT TIME ZONE 'America/Sao_Paulo')::date` bloqueia **true**; `CURRENT_DATE` bloqueia
**FALSE**. O predicado ingenuo soltaria o entrevistador 3h30 antes do fim do dia local dele.

A queda para `cycle_fallback` na trilha researcher passou a gravar `admin_audit_log` com
`committee_routable` e `blocked_by_window`, que separam "ninguem configurado" de "todos bloqueados".
Sai no chamador (`_dispatch_interview_booking_link`), nao no picker, que e STABLE.

---

## O estado medido do roteamento (12/08, RE-MEDIR)

- Comite de `cycle4-2026`: **3 avaliadores roteaveis** (Fabricio, Vitor, Fernando, todos por
  `committee_override`) e **4 observadores** fora do rodizio (URL nula).
- 94 despachos: researcher 57 `member_global` + 30 `committee_override`; leader 7 `cycle_fallback`.
- Desde que o Fernando entrou no comite (31/07 22:19): Vitor 8, Fabricio 5, Fernando 4.
  ⚠️ **O rodizio LRD nao equaliza como o nome promete, e isso ainda nao tem explicacao medida.**
- `selection_booking_attempts`: 31 `no_application`, 4 `matched`, 4 `cycle_closed`, 1
  `status_not_allowed`.
- 0 linhas em `selection_interviewer_blackouts` (a onda C e que traz a escrita).

---

## Onda C - o que falta, e por que ela e a maior

**Nenhuma das duas ondas entregou superficie de escrita.** Hoje, para bloquear alguem no roteamento,
ainda e preciso `INSERT` manual. E `selection_committee.interview_booking_url`, que decide **30 dos
30 ultimos despachos de researcher**, continua **sem tela e sem MCP**: foi preenchido por SQL direto.
`manage_selection_committee` nao aceita o campo.

Escopo previsto (do plano aprovado):

1. RPC de leitura `get_selection_routing_overview(p_cycle_id)`: por pessoa, papel, `can_interview`,
   se tem URL e de qual precedencia, janelas de bloqueio, contagem e data do ultimo despacho.
2. `set_interviewer_routing_block` / `clear_interviewer_routing_block`: **autosservico** quando o
   alvo e o proprio chamador, `manage_member` para qualquer um (decisao do PM). Auditado.
3. `manage_selection_committee` aceita `p_interview_booking_url`.
   ⚠️ **Mudanca de assinatura de RPC exige `npm run db:types` na MESMA PR** (gate `gen-types-drift`).
4. Painel "Comite e roteamento" em `/admin/selection` com o controle de pausa.
5. Espelhar as acoes novas em `interview_manage` / `selection_decide`
   (`supabase/functions/nucleo-mcp/index.ts`), senao a MCP volta a exigir SQL direto (#1588).
6. i18n nos 3 dicionarios.

**Decisoes do PM ja tomadas, NAO re-litigar:** bloqueio e **autosservico + GP** · sem ninguem
elegivel o candidato **cai na agenda do Nucleo**, com o desvio **registrado** (ja entregue na onda B)
· ondas por **jornada do candidato**.

## Onda D - o que o briefing levantou e nenhuma onda tocou

**A tentativa de agendamento que falha nao deixa linha.** O candidato que abre a agenda e nao acha
horario e indistinguivel de quem nunca clicou: o unico sinal que chega a plataforma e a reserva
BEM-SUCEDIDA, e a lista de horarios e renderizada pelo Google numa aba nova. Enquanto isso nao mudar,
qualquer metrica de sucesso de agendamento diz 100% por construcao.

Tambem nesta onda: #1664 (fila de reservas sem candidatura), o caminho do portal que cunha token novo
a cada clique sem incrementar `access_count`, #1587, #1586, #1614.

---

## Issues abertas nesta sessao

- **#1742** - `check_schema_invariants` estoura `statement_timeout` na suite cheia: **310 ms
  isolado, 76 s sob contencao**, 0 violacoes reais. Mesma familia da #1649 (`service_role` herda 8s
  do `authenticator`). ⚠️ Depois de aberta, **duas corridas verdes** (CI da #1743 e da #1745): a
  reproducao e intermitente, o que NAO fecha a issue - o padrao da #1649 era falhar em 3 de 5.
- **#1744** - `browser-guards` deixa `astro dev` orfao. O `finally` usa `SIGTERM` no filho; o padrao
  corrigido do #1725 (detached + pid negativo + SIGKILL) ja esta no irmao `smoke-routes.mjs`. No CI
  nao doi (o runner morre), entao **nunca vai ficar vermelho la** - o custo e diagnostico enganoso
  na maquina de quem desenvolve.

## Armadilhas pagas nesta sessao

1. **Espelhar o servidor abriu porta que o menu nunca ofereceu** (ver onda A). Medir as duas direcoes.
2. **Duas PRs com contrato novo colidem SEMPRE no `package.json`** - as duas whitelists sao linhas de
   ~32 mil caracteres. Resolver escolhendo um lado **desliga o teste do outro em silencio**. Resolvi
   por uniao, programaticamente, afirmando os dois caminhos nas duas whitelists e validando o JSON.
3. **O instrumento participou da medicao, de novo**: editar arquivos enquanto o `browser-guards`
   rodava disparava `[vite] program reload` no meio do teste. Atribui ~10 min de "travamento" ao
   teste; a corrida limpa levou **43 segundos**.
4. **Guard por regex era sintoma de modulo pesado demais para importar** - e o regex antigo
   (`return 'visitor'`) casava mais de uma funcao, entao nunca provou qual lia.

## Para a proxima sessao

Comecar por **re-medir** o comite e o roteamento (a superficie da onda C descreve exatamente esses
numeros), depois ler `supabase/functions/nucleo-mcp/index.ts` na parte de `interview_manage` /
`selection_decide`. O plano aprovado esta em
`~/.claude/plans/ler-e-comecarmos-docs-planning-2026-08-1-jolly-curry.md`.

**Perguntas que continuam do PM:** as ondas C/D viram ordem de execucao acima da ordem herdada
(#1710 -> #1654 -> #1218)? E os 6 `chapter_liaison` do achado da onda A: entram na tela de selecao
ou nao?
