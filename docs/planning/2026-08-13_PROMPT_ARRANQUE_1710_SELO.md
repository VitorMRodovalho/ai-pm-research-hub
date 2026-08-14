# Prompt de arranque - #1710: o selo de presenca nao tem superficie

> Colar depois do `/clear`. **Effort: `xhigh`.**
> Handoff anterior: `docs/planning/2026-08-13_handoff_1590_ondas_A_e_B_mergeadas_e_a_onda_C.md`
> (tem o desfecho das ondas A e B do #1590 **e** as duas decisoes do PM que fecharam aquela sessao).
> O plano por ondas de `/admin`+Selecao vive em
> `~/.claude/plans/ler-e-comecarmos-docs-planning-2026-08-1-jolly-curry.md`, fora do repo.

---

## Regra zero

**Nada deste documento pode ser recitado.** Todo numero aqui foi medido em **13/08/2026** e varios
se movem sozinhos. Dois ja se moveram enquanto esta sessao acontecia:

- eventos passados: a issue dizia **302** (09/08), hoje sao **510**
- publico do selo: os handoffs dizem **86 ativos**, hoje sao **87**

Re-medir com tool call na mesma volta em que o numero entrar numa decisao, num commit, numa issue
ou numa pergunta ao PM.

Padroes que ja custaram caro neste repositorio, e que este item toca de perto:

- **verde por vacuidade** - populacao zero le como verde; o invariante da onda B do #1590 e vacuo
  hoje por ausencia de uso, e esta dito no proprio teste
- **o denominador se move** - ver os dois numeros acima
- **ausencia de linha renderizada como fato negativo** (#1657) - e exatamente o que o selo
  materializa; e por isso que ele e irreversivel
- **guard ancorado num ARQUIVO nao observa o mundo** - aqui o guard tem de olhar `roster_sealed_at`
  vivo, nao o texto da migration
- **branch nova nasce do HEAD, nao da main** (custou nesta sessao, #1746/#1747): criar com
  `git checkout -b <nova> origin/main` e conferir `git log origin/main..HEAD` antes do push

⚠️ **Nunca escreva `close #N` / `fixes #N` / `resolves #N` num corpo de PR sem intencao de fechar,
nem para CITAR o padrao.** E o espelho: **`Fecha #N` em portugues nao fecha nada.**

---

## Estado (medido 13/08)

`main` em **`5012ec95`**. **Zero bypass** na sessao anterior (3 PRs, todas com CI verde).

| medida | valor |
|---|---:|
| eventos passados | **510** |
| eventos com `roster_sealed_at` | **0** |
| membros ativos (publico do selo) | **87** |
| `seal_event_attendance` existe | sim |
| `preview_seal_attendance` (dry-run) existe | sim |
| chamadas das duas no front ou na MCP | **0** |

A unica mencao no codigo e um **comentario** em `src/components/attendance/types.ts:3`. Ou seja: o
mecanismo esta pronto e **inerte**.

⚠️ **PRs abertas de outras lanes:** **#1747** (redundante - o conteudo dela entrou na main por engano
meu na #1746; ver o comentario que deixei la) e **#1750** (`fix/1748-tile-da-tribo...`, intacta).
Nao mexer em nenhuma das duas sem decisao de quem as abriu.

---

## O item

**#1710** - `priority:high`, `onda:1`. Follow-up do #1657.

O #1657 tirou o defeito de "sem linha = falta". Agora sem linha num evento **nao selado** e
`unrecorded` e nao acusa ninguem. Isso transferiu **todo o peso para o ato de selar**, que e o que
materializa a linha de no-show. Com **0 de 510** selados, a plataforma nao consegue afirmar que
alguem faltou.

`seal_event_attendance(p_event_id)` esta viva, gateada em `manage_event`, idempotente
(`ON CONFLICT DO NOTHING`), **e nao e chamada por nada**.

### Escopo da issue

- superficie para selar, com confirmacao que **diga quantas faltas serao materializadas** antes de
  executar (e escrita em massa no historico de gente real)
- a grade mostra se o evento esta selado, e desde quando
- tool MCP para selar, na familia do #1588
- contagem de eventos selados publicada depois de uma semana, para o zero-uso ser respondido com
  medicao

### Decisoes do PM ja tomadas - NAO re-litigar

- selo **AUTOMATICO com janela e aviso** (nao manual)
- janela de **14 dias**
- publico: os ativos (**87**, re-medir)
- sponsor/chapter_liaison fora do tier **nao sao cobrados**
- gestor sem tribo **nao e elegivel** a reuniao de tribo
- correcao pelo **lider da tribo** (GP como recurso)
- exige **dry-run** e **reversao por evento** - **nao existe `unseal`**

### O que ja foi resolvido e nao precisa refazer

- **#1726**: a comunicacao foi enviada; os 3 bloqueios cairam.
- **#1722**: as coortes convergiram - as celulas que selar transformaria em falta **sem nenhum
  registro** foram de 133 (16 pessoas) para **zero**.
- **#1727**: o corte da janela ja usa o instante LOCAL (`_event_end_instant`), nao `CURRENT_DATE`.
- **#1729**: coorte vazia nao carimba `roster_sealed_at` (`skipped_empty_cohort`).
- `preview_seal_attendance` (o dry-run) **ja existe**.

### Cuidados que a propria issue registra

- `seal_event_attendance` escreve `present=false` para todo elegivel sem linha, com `marked_by` do
  executor, e e **irreversivel pela RPC**. A confirmacao na UI nao e cosmetica.
- A coorte elegivel vem de `v_member_operational_tiers` + `_attendance_eligible_events`, que **nao
  era** a mesma da grade de tribo. A #1722 fez convergir - **conferir de novo antes de expor o
  botao**, porque a divergencia volta com dado novo.

---

## Primeiros passos sugeridos (nao decididos)

1. **Re-medir** eventos selados vs passados e o publico ativo. Os dois numeros desta pagina ja
   estao velhos quando voce ler.
2. Exercer `preview_seal_attendance` num evento real em **transacao abortada** e ver o que o dry-run
   devolve hoje - a superficie de confirmacao vai renderizar exatamente isso.
   ⚠️ Conferir ANTES que as triggers envolvidas nao chamam servico externo.
3. Decidir onde a superficie mora: quadro de presenca do evento, grade da tribo, ou os dois.
4. So entao o cron da janela de 14 dias, que e a parte irreversivel.

## Depois do #1710

**Onda C** do #1590 (superficie de roteamento). Ordem decidida pelo PM em 13/08, com o criterio que
a inverte registrado no handoff. Dentro da onda C, a **superficie do comite vem antes do painel de
roteamento**, porque o PM definiu que **o comite E a regra de seguranca de acesso** da tela de
selecao.
