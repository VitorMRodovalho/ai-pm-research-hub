# Prompt de arranque - #1590 onda C: o comite decide o acesso, e nao tem tela

> Colar depois do `/clear`. **Effort: `xhigh`.**
> Handoffs anteriores: `docs/planning/2026-08-13_handoff_1590_ondas_A_e_B_mergeadas_e_a_onda_C.md`
> (o desfecho das ondas A e B, e as duas decisoes do PM que fecharam aquela sessao) e
> `docs/planning/2026-08-13_handoff_1710_o_selo_ganhou_superficie_e_janela.md` (a sessao seguinte,
> que fechou o #1710 e cujas armadilhas se aplicam aqui).
> O plano aprovado vive em `~/.claude/plans/ler-e-comecarmos-docs-planning-2026-08-1-jolly-curry.md`,
> fora do repositorio.

---

## Regra zero

**Nada deste documento pode ser recitado.** E vale em dobro aqui: a onda C decide **superficie** a
partir de "quem esta cadastrado para roteamento", e todo numero de roteamento abaixo foi medido em
**12/08/2026**, duas sessoes atras. Eles descrevem um comite que pode ter mudado desde entao.

Re-medir com tool call na mesma volta em que o numero entrar numa decisao, num commit, numa issue ou
numa pergunta ao PM. Um painel que descreve a coorte errada e pior que painel nenhum: ele parece
autoridade.

---

## Estado (13/08, fim do dia)

`main` em **`cbd15358`**. **Zero bypass** nas quatro PRs do #1710.

⚠️ **PRs abertas de outras lanes, nao mexer sem decisao de quem as abriu:** **#1750** (tile da tribo)
e **#1752** (handoff da lane Biblioteca). Se a **#1758** (handoff do #1710) ainda estiver aberta, ela
e so documento e fecha verde sozinha.

O #1710 foi fechado em quatro ondas nesta data: escopo + reversao + tela (#1754), tool MCP (#1755),
cron da janela (#1756). ⏰ **Ha um compromisso com data:** antes de **24/08** alguem precisa re-medir
o que a primeira execucao do cron de selo vai gravar. Isso **nao e trabalho desta onda**, mas se a
sessao atravessar aquela data, e dela.

---

## O item

**#1590**, `onda:admin-ui`. As ondas A e B estao na main. Falta a **C**, que e a maior — e o PM
decidiu, em 13/08, que dentro dela **a superficie do comite vem antes do painel de roteamento**.

### Por que o comite vem primeiro

Nas palavras do PM: entram na tela de selecao **presidentes, admin da plataforma, gestao (GPs) e
quem estiver listado no comite** — e **e no comite que se define quem e observador e quem avalia**.

Isso torna o comite **o mecanismo de controle de acesso**. E hoje `selection_committee` so se edita
por **SQL direto**: nao tem tela, e `manage_selection_committee` nao aceita o campo que decide o
roteamento. Um mecanismo de seguranca que so o dono do banco consegue operar e a mesma classe de
defeito que o #1710 acabou de fechar.

### Escopo previsto (do plano aprovado)

1. RPC de leitura `get_selection_routing_overview(p_cycle_id)`: por pessoa, papel, `can_interview`,
   se tem URL e de qual precedencia, janelas de bloqueio, contagem e data do ultimo despacho.
2. `set_interviewer_routing_block` / `clear_interviewer_routing_block`: **autosservico** quando o
   alvo e o proprio chamador, `manage_member` para qualquer um. Auditado.
3. `manage_selection_committee` aceita `p_interview_booking_url`.
4. Painel "Comite e roteamento" em `/admin/selection`, com o controle de pausa.
5. Espelhar as acoes novas em `interview_manage` / `selection_decide`
   (`supabase/functions/nucleo-mcp/index.ts`), senao a MCP volta a exigir SQL direto (#1588).
6. i18n nos 3 dicionarios.

**Hedge, se o escopo apertar:** so as duas RPCs de escrita (bloquear/desbloquear), sem painel e sem
MCP — cerca de um quarto do esforco.

### Decisoes do PM ja tomadas - NAO re-litigar

- bloqueio de roteamento e **autosservico + GP**
- sem ninguem elegivel, o candidato **cai na agenda do Nucleo**, com o desvio **registrado** (ja
  entregue na onda B)
- ondas organizadas por **jornada do candidato**
- quem entra na tela de selecao: **presidentes + admin + GPs + listado no comite**. Os **6
  `chapter_liaison`** ficam de fora; estende-los e decisao nova do PM, nao consequencia tecnica.

---

## O que a onda A ja entregou, e que NAO se re-litiga

A pagina passou a espelhar o **publico do drawer**, de proposito mais estreita que a RPC. A primeira
versao espelhava o predicado do servidor (`view_internal_analytics` OU comite) e isso **criava 6 no
sentido inverso**: 6 `chapter_liaison` entrariam numa rota `lgpdSensitive` por uma porta que o menu
nunca ofereceu. O contrato fica vermelho se alguem reintroduzir aquele eixo.

⚠️ **Licao que se aplica direto ao painel desta onda:** ao espelhar um predicado de servidor numa
superficie, **medir as duas direcoes**. "Quantos passam a ver" e so metade; a outra e "quantos
passam a poder o que nao podiam".

---

## Numeros de 12/08 - VELHOS, servem so para dizer onde olhar

| medida (12/08) | valor |
|---|---|
| comite de `cycle4-2026` | 3 avaliadores roteaveis + 4 observadores fora do rodizio |
| despachos | 94: researcher 57 `member_global` + 30 `committee_override`; leader 7 `cycle_fallback` |
| rodizio desde 31/07 | Vitor 8, Fabricio 5, Fernando 4 |
| `selection_booking_attempts` | 31 `no_application`, 4 `matched`, 4 `cycle_closed`, 1 `status_not_allowed` |
| `selection_interviewer_blackouts` | 0 linhas (a escrita e esta onda) |

⚠️ **`interview_booking_url` decidia 30 dos 30 ultimos despachos de researcher** e foi preenchido por
SQL direto. E o campo mais importante da onda, e o que menos tem superficie.

⚠️ **O rodizio LRD nao equaliza como o nome promete** (8/5/4), e isso **ainda nao tem explicacao
medida**. Nao e escopo da onda C, mas se o painel publicar "proximo da fila" sem entender isso, ele
publica uma promessa que o codigo nao cumpre.

---

## Armadilhas da vizinhanca, com o preco que ja custaram

1. **Mudanca de assinatura de RPC exige `npm run db:types` na MESMA PR** (gate `gen-types-drift`).
   O item 3 do escopo muda uma assinatura.
2. **`CREATE FUNCTION` concede `EXECUTE` a `PUBLIC` por padrao.** Toda RPC nova nasce alcancavel por
   `anon`; o `REVOKE ... FROM PUBLIC, anon` vai na MESMA migration, nao numa depois (#1710, #1592).
3. **A suite de contratos roda offline em ~52s** e e o gate barato antes de abrir PR:
   `env -u SUPABASE_URL -u SUPABASE_SERVICE_ROLE_KEY -u PUBLIC_SUPABASE_URL npm run test:contracts`.
   Sem credenciais os ~665 testes DB-gated pulam, nao ha contencao com o banco compartilhado (#1505)
   e todo gate estatico aparece. **Varrer por palpite nao substitui roda-la** — no #1755 isso custou
   um CI vermelho por dois contadores pinados que a varredura nao achou.
4. **Um guard varre `prosrc`, que inclui COMENTARIOS.** Um comentario que nomeia uma tabela faz a
   funcao parecer que a le (#1710). E o espelho do ja conhecido: um guard de ausencia que casa a
   propria explicacao.
5. **Gate por recurso, nao por papel.** Uma RPC de escrita que recebe um recurso concreto e gateia
   sem ele alcanca o recurso de qualquer um: foi assim no #1728, e no #1710 mediu-se **622 pares
   (lider, evento)** indevidos. As RPCs de bloqueio desta onda recebem um `member_id` — o gate tem
   de olhar para ele.
6. **Branch nova nasce do HEAD, nao da main:** `git checkout -b <nova> origin/main`, e conferir
   `git log origin/main..HEAD` antes do push.
7. ⚠️ **Nunca escrever `close #N` / `fixes #N` / `resolves #N` num corpo de PR sem intencao de
   fechar, nem para CITAR o padrao.** E o espelho: **`Fecha #N` em portugues nao fecha nada.**

---

## Primeiros passos sugeridos (nao decididos)

1. **Re-medir o comite de `cycle4-2026`**: quem esta listado, com que papel, quem tem
   `interview_booking_url`, e quantos despachos cada um recebeu. Os numeros da tabela acima estao
   velhos quando voce ler.
2. Ler `supabase/functions/nucleo-mcp/index.ts` na parte de `interview_manage` / `selection_decide`
   antes de desenhar as RPCs — o espelho na MCP e item de escopo, e a forma das tools condiciona a
   forma das assinaturas.
3. Decidir se a superficie do comite e uma aba nova em `/admin/selection` ou um bloco na existente.
4. So entao as duas RPCs de escrita e o painel de roteamento.

## Depois da onda C

**Onda D** do #1590, que o briefing levantou e nenhuma onda tocou: **a tentativa de agendamento que
falha nao deixa linha**, entao qualquer metrica de sucesso de agendamento diz 100% por construcao.
Tambem nela: #1664, o caminho do portal que cunha token novo a cada clique sem incrementar
`access_count`, #1587, #1586, #1614.
