# Prompt de arranque - #1590 onda D: a tentativa que falha não deixa linha

> Colar depois do `/clear`. **Effort: `xhigh`.**
> Handoff anterior: `docs/planning/2026-08-13_handoff_1590_onda_c_o_comite_ganhou_tela.md`
> (onda C entregue: o comitê ganhou superfície de roteamento).
> O plano das ondas vive em `~/.claude/plans/ler-e-comecarmos-docs-planning-2026-08-1-jolly-curry.md`,
> fora do repositório.

---

## Regra zero

**Nada deste documento pode ser recitado.** Todo número abaixo foi medido em **13/08/2026** e vários
já se moveram enquanto a onda C era escrita: `selection_booking_attempts` saiu de 40 para 41 linhas
**no meio da sessão**, sem ninguém tocar em código.

Re-medir com tool call na mesma volta em que o número entrar numa decisão, num commit, numa issue ou
numa pergunta ao PM. E esta onda é sobre **medição**: um diagnóstico feito com número velho aqui
propõe instrumentar o lugar errado.

---

## Estado (13/08, fim do dia)

`main` em **`8b8d7089`**. Onda C fechada em duas PRs, **#1761** (RPCs + MCP) e **#1763** (handoff),
ambas verdes, **zero bypass**.

⏰ **Compromisso com data, de outra lane:** antes de **24/08** alguém precisa re-medir o que a
primeira execução do cron de selo do #1710 (`attendance-seal-window-daily`) vai gravar. Não é
trabalho desta onda, mas se a sessão atravessar aquela data, é dela.

⚠️ **PRs abertas de outras lanes, não mexer sem decisão de quem as abriu:** **#1750** (tile da tribo)
e o que restar da lane Biblioteca.

---

## O item

**#1590, onda D.** O briefing de 12/08 levantou, e nenhuma onda tocou:

> **A tentativa de agendamento que falha não deixa linha.** O candidato que abre a agenda e não
> encontra horário é indistinguível de quem nunca clicou. Enquanto isso não mudar, qualquer métrica
> de sucesso de agendamento diz **100% por construção**.

### O mapa do despacho, medido no corpo vivo (13/08)

**Cinco funções** chamam `_dispatch_interview_booking_link`, e é ele quem grava a linha em
`selection_dispatch_url_log`:

| caminho | quando dispara |
|---|---|
| `notify_selection_cutoff_approved` | o e-mail de aprovação no corte |
| `request_interview_reschedule` | o candidato pede remarcação |
| `process_pending_reschedule_nudges` | o cutucão automático de remarcação |
| `mark_interview_status` | mudança de status da entrevista |
| `request_interview_booking_link_via_token` | **o portal do candidato** (`pmi_onboarding_portal`) |

O que ele grava é **o despacho** (a plataforma mandou o link) — nunca o desfecho. O destino é uma
agenda do Google renderizada **numa aba nova**, fora da plataforma.

### ⚠️ Correção medida a um item que os handoffs vinham repetindo

Os handoffs anteriores dizem "o caminho do portal cunha token novo a cada clique **sem incrementar
`access_count`**". Isso mistura **dois caminhos diferentes**, e só metade é verdade:

- `validate_interview_booking_token` (a página `/interview-booking/[token]`) **INCREMENTA**
  `access_count` e grava `last_accessed_at`. Conferido no corpo vivo em 13/08.
- `request_interview_booking_link_via_token` (o portal PMI, escopo `profile_completion`) chama o
  despacho, que **cunha um token novo** por clique, e não toca no `access_count` do token do portal.

Medido em 13/08 sobre `onboarding_tokens` com escopo `interview_booking`: **17 tokens para 13
candidaturas** (confirma a cunhagem repetida), **9 nunca abertos**, 8 abertos, **16 aberturas** no
total, máximo de **7** aberturas num mesmo token.

Ou seja: **já existe sinal de abertura da página**, e ele nunca foi usado como denominador. A onda D
começa perguntando o que falta MESMO, não reconstruindo o que já está lá.

### ⚠️ `selection_booking_attempts` NÃO é o denominador

É tentador (o nome engana). Ela é escrita pelo **webhook do Google Calendar**
(`src/pages/api/calendar-webhook.ts`), uma linha por **evento + convidado**, e portanto só existe
quando a reserva **aconteceu** e o webhook disparou. Ela conta *reservas que a plataforma não
conseguiu casar com candidatura*, não *candidatos que abriram a agenda e não acharam horário*.

Medido em 13/08: **41 linhas** — `no_application` 31, `matched` 5, `cycle_closed` 4,
`status_not_allowed` 1. (Em 12/08 eram 40, com `matched` 4. Anda sozinho.)

---

## Números de 13/08 - VELHOS quando você ler, servem para dizer ONDE olhar

| medida (13/08) | valor |
|---|---|
| entrevistas | 127: **97** completed · 21 cancelled · 5 noshow · 4 scheduled |
| candidaturas aguardando entrevista (ciclo aberto) | 9 |
| **candidaturas com MAIS DE UMA linha em `selection_interviews`** | **14** |
| tokens `interview_booking` | 17 para 13 candidaturas · 9 nunca abertos |
| `selection_booking_attempts` | 41 (31 `no_application`) |
| despachos (`selection_dispatch_url_log`) | 94 |
| bloqueios de roteamento (onda C) | **0** — a superfície existe e nunca foi exercida |

As **14 candidaturas com múltiplas linhas** são a #1587 quantificada pela primeira vez. Até aqui a
issue dizia só que "ler a mais recente devolve estado errado", sem tamanho.

---

## As issues da onda

- **#1664** - fila de reservas sem candidatura: 31 linhas `no_application`, e o rótulo é falso para
  parte delas. Começa por classificar as 31 antes de propor conserto.
- **#1587** - múltiplas linhas em `selection_interviews`; ler a mais recente devolve estado errado.
  **14 candidaturas** hoje. Encosta em `mark_interview_status` e no INSERT do webhook.
- **#1586** - rescue sem superfície MCP. `selection_rescue_stuck_interview` já está em
  `interview_manage action='rescue'` desde a Wave 4 — **confirmar se ainda é verdade antes de manter
  a issue aberta**, é candidata a fechar por já-entregue.
- **#1614** - endereço do agendamento, adiada pelo PM em 05/08.
- **#1762** (vizinha, aberta na onda C) - o rodízio concentra despachos quando o lote sai na mesma
  transação. Não é da onda D, mas mexe no mesmo picker.

## Decisões que esta onda vai EXIGIR do PM (não decidir sozinho)

1. **O que passa a ser gravado quando o candidato abre a agenda e desiste.** A plataforma não vê a
   aba do Google: o máximo alcançável é "abriu a porta" + "não reservou em N dias". Isso é
   inferência, não medição — e o PM precisa saber que é.
2. **Se o portal PMI passa a registrar abertura** (hoje cunha token e não conta), e se o token
   cunhado a cada clique vira reuso do vigente.
3. **O que fazer com as 31 `no_application`** — são pessoas que reservaram horário e a plataforma
   não reconheceu.

---

## Armadilhas da vizinhança, com o preço que já custaram

1. **`CREATE FUNCTION` concede EXECUTE a `PUBLIC` por padrão.** Toda RPC nova nasce alcançável por
   `anon`; o `REVOKE ... FROM PUBLIC, anon` vai na MESMA migration (#1710, #1592). Na onda C isso
   pegou uma RPC de escrita que já estava exposta.
2. **Gate por RECURSO, não por papel.** Uma RPC que recebe um alvo concreto e não olha para ele
   alcança o recurso de qualquer um: #1728, e 622 pares indevidos medidos no #1710.
3. **Mudança de assinatura de RPC exige `npm run db:types` na MESMA PR** (gate `gen-types-drift`).
   ⚠️ **Dentro do sandbox o script falha em SILÊNCIO**: o `mktemp` dele escreve em `/tmp`, que é
   bloqueado, e o `&&` da cadeia esconde o erro — o arquivo simplesmente não muda. Rodar com
   `TMPDIR=<scratchpad> npm run db:types` e conferir o `git status`.
4. **A suíte de contratos offline (~60s) é o gate barato antes da PR:**
   `env -u SUPABASE_URL -u SUPABASE_SERVICE_ROLE_KEY -u PUBLIC_SUPABASE_URL npm run test:contracts`.
   Varrer por palpite não substitui: na onda C ela achou **dois contadores pinados** que a varredura
   não achou (a versão da superfície `/semantic` é pinada em dois arquivos que não se conhecem, um
   deles lendo o TÍTULO do teste vizinho, mais o manifesto de `/docs/mcp`).
5. **Um guard antigo ficar vermelho pode ser o vermelho CORRETO.** Na onda C o guard da onda A
   afirmava que a aba de comitê declara `manage_member`; o significado da aba mudou. Desça a
   afirmação um nível em vez de apagá-la.
6. **`browser_guards` ESTÁ no CI** (o job existe, mesmo sem casar com `grep browser-guards` nos
   workflows) e **não roda neste sandbox** (sai em 144 sem saída). Para exercer a tela: subir
   `astro dev` e dirigir por Playwright com `page.addInitScript`, travando `navGetSb`/`navGetMember`
   com `Object.defineProperty` (`writable: false`) — senão o `Nav.astro` sobrescreve o stub depois.
7. **Dois `CI Validate` sobre o banco de produção se contaminam** (#1505): eles falham em subtestes
   DIFERENTES e o mesmo commit passa sozinho no re-run. Aconteceu em 13/08 mesmo com o
   `wait-for-db-lane` do #1509 no lugar — **por que ele não segurou não foi medido**, e a hipótese
   (a consulta paginada em `per_page=50` não enxergar o run da frente quando muitos workflows
   disparam juntos) é hipótese, não medição. Antes de chamar qualquer vermelho de flake: conferir
   sobreposição de runs e re-rodar SOZINHO.
8. ⚠️ **Nunca escrever `close #N` / `fixes #N` / `resolves #N` num corpo de PR sem intenção de
   fechar, nem para CITAR o padrão.** E o espelho: **`Fecha #N` em português não fecha nada.**

---

## Primeiros passos sugeridos (não decididos)

1. **Re-medir tudo da tabela acima.** Especialmente entrevistas por status, as 14 candidaturas com
   múltiplas linhas e as 31 `no_application`.
2. **Classificar as 31 `no_application`** antes de propor conserto (#1664): quantas são e-mail que
   não casa, quantas são reserva de quem nunca se candidatou, quantas são ciclo antigo.
3. **Decidir com o PM o que é "tentativa"** — sem isso, qualquer instrumentação mede a coisa errada
   com muita precisão.
4. **Confirmar se a #1586 já está entregue** (`interview_manage action='rescue'`) antes de gastar
   sessão nela.
5. Só então desenhar a escrita.

## Depois da onda D

**Onda E** (avaliação e decisão), já triada no backlog: #1572 (P0, aprovação sem avaliação não deixa
trilha), #1575, #1574, #1573, #1576, #1634, #1581, #1579.
