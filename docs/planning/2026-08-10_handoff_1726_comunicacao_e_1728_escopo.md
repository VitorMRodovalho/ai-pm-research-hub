# Handoff - #1726 decidida e escrita, #1728 corrigida (10/08/2026, noite)

> Continuação de `docs/planning/2026-08-10_handoff_1710_passo2_elegibilidade.md`.
> Cobre a **PR #1730**.

## Regra zero

Todo numero aqui foi medido em **10/08/2026 entre 20h e 21h30 (Brasilia)**. ⚠️ Nesse intervalo o
banco **virou o dia em UTC**, e isso mexe nos numeros: re-medir com tool call na mesma volta em que
o numero entrar numa decisao, num commit, numa issue ou numa pergunta ao PM.

---

## O que foi entregue

### 1. #1726 decidida e escrita (o bloqueio do #1710)

Decisoes do PM, todas registradas na issue:

| item | decisao |
|---|---|
| publico | **todos os membros ativos, de uma vez** (86 pessoas) |
| janela | **14 dias** entre o aviso e o primeiro selo |
| correcao | **lider da tribo corrige, GP como recurso** |
| canal | anuncio na plataforma (`announcements`, ja tem os 3 idiomas) mais e-mail |

Texto pronto nos 3 idiomas em
`docs/_deliverables/2026-08-10_1726_comunicacao_mudanca_leitura_presenca.md`.

**O que falta e ato do PM: enviar.** Depois disso, 14 dias, e so entao o #1710 pode ligar o selo.

### 2. #1728 - as duas RPCs de escrita de presenca gateavam sem escopo (corrigido em prod)

Achado ao verificar se o caminho de correcao que a comunicacao promete **funciona**.
`mark_member_present` e `clear_member_attendance` chamavam `can_by_member(caller,'manage_event')`
sem passar o evento; `public.can()` casa qualquer grant nessa forma. Provado em transacao abortada:
o lider da tribo 9 marcou presenca na tribo 8 e apagou linha da tribo 11.

Corrigido com `_can_manage_event(p_event_id)`, o mesmo predicado do irmao
`admin_bulk_mark_attendance`. Regressao: 63 pares evento-ator no historico, 57 passavam, os
**mesmos** 57 passam.

### 3. #1719 (auditoria de bypass da W33) revisada e fechada

Veredito honesto: os 6 sao pushes diretos de `docs(planning)` e **nao** satisfazem os criterios do
protocolo (nao houve CI vermelho externo, nem issue de rastreio, nem trailer). Atenuante: nenhum
toca codigo. A remediacao ja estava em vigor desde **09/08** - os 8 commits de planejamento
seguintes entraram por PR (#1706, #1711, #1712, #1715, #1717, #1718, #1721, #1723).

---

## Tres achados novos, cada um com issue

### #1727 - a janela do selo fecha em `CURRENT_DATE`, que e UTC

Das 21h a meia-noite no Brasil, o banco ja virou o dia e as reunioes **daquela noite** entram na
janela antes de acontecer. Medido as 21h12: **4 reunioes** com inicio entre 18h30 e 20h de 11/08 ja
elegiveis, com zero linhas.

A guarda que existe (`IF v_date > CURRENT_DATE THEN 'Evento futuro'`) usa a **mesma** comparacao e
nao pega. O corte tem de ser por instante local do fim da reuniao; `time_start` e `timezone` ja
existem nos eventos.

Sem dano: **nao existe cron de selo** (`cron.job` so tem `sync-attendance-points`, e 0 eventos com
`roster_sealed_at`). E restricao de desenho, a respeitar antes de o cron nascer.

### #1729 - iniciativa ARQUIVADA segue emitindo reuniao semanal

**Agentes Autonomos** (`legacy_tribe_id = 2`), `status = 'archived'`, **0 engajamentos ativos**, e
mesmo assim gerou 5 reunioes no ciclo (13/07 a 10/08, todas com 0 presencas) e tem **mais 8
agendadas ate 05/10**. Selar coorte vazia grava zero linhas e ainda assim carimba
`roster_sealed_at`: marca "lista fechada" em algo que nunca teve lista.

✅ **Decidido e aplicado pelo PM em 10/08:** as **8 futuras foram canceladas**. `cancelled_by = NULL`
(nenhuma pessoa executou o ato) e o motivo carimba a issue, replicando o que `cancel_event_occurrence`
grava. Antes/depois: 8 futuras ativas → **0**; 20 passadas → **20**, nenhuma cancelada; **50** linhas
de presenca preservadas.

⚠️ **Isso NAO limpou as 5 de coorte zero**, que sao passadas (13/07 a 10/08) e continuam na janela.
Depois do cancelamento, a janela do ciclo tem **57** reunioes, **52** com coorte e **5** sem. O
cancelamento estanca a entrada de novas; a frente do selo (pular coorte vazia) segue valendo e e
escopo do #1710.

⚠️ **A causa raiz continua aberta:** por que arquivar a iniciativa nao parou a recorrencia. Hoje e
caso unico (nenhuma outra arquivada gerou evento em 60 dias), mas arquivar a proxima repete o efeito.

### As outras 20 RPCs da mesma classe do #1728

A varredura achou **22** RPCs de escrita que recebem um recurso concreto e gateiam sem ele. Duas
foram corrigidas; **20 seguem abertas**, rastreadas no corpo da #1728 sem detalhe (repo publico).

⚠️ **Nao atacar por varredura mecanica.** A busca crua devolve **43** funcoes e a maioria e falso
positivo: leitura, ou org-wide por natureza, onde a pergunta sem recurso e a certa. O recorte que
importa e **escrita sobre recurso concreto**. Seguir o procedimento de 4 etapas em
`docs/reference/V4_AUTHORITY_MODEL.md`.

---

## Os numeros do #1726, re-medidos

Ciclo 4 (2026/2), inicio 09/07. **Medidos as 21h15 de 10/08**, ja excluindo as 4 reunioes que ainda
nao tinham ocorrido:

| medida | na abertura da issue | agora |
|---|---:|---:|
| pessoas com linha / em 100% | 70 / 70 | **68 / 68** |
| media publicada | 100,0% | **100,0%** |
| media pos-selo | 74,8% | **75,4%** |
| pessoas que recebem falta | 52 | **48** |
| linhas de falta | 120 | **112** |
| maior queda individual | -87,5 pp | **-87,5 pp** |
| reunioes que o selo alcanca | 53 | **48** |
| reunioes passadas do tipo | 301 | **306** |

As duas correcoes de fato: **-5 reunioes** sao as da tribo 2 arquivada (#1729), e a exclusao das
**4** futuras vem do #1727. Pela janela crua seriam 52 reunioes, 56 pessoas e 134 linhas.

---

## Armadilhas pagas nesta sessao

⚠️ **1. Medicao que se move sem escrita = borda temporal.** A mesma simulacao deu 120 linhas as 20h
e 134 as 21h15 sem nada ter sido gravado. O candidato numero um nao e o dado, e o `CURRENT_DATE`.

⚠️ **2. O guard do #1660 ficou vermelho por trabalho correto, em 3 assercoes.** Duas ancoradas na
forma antiga do gate. A terceira e a mais sutil: afirmava `REVOKE`/`GRANT` sobre a **captura mais
recente**, e o teste ate documentava que nao usava caminho hardcoded. Mas grant e propriedade do
**banco**, estabelecida uma vez; ancorar em "o arquivo que por acaso substituiu o corpo por ultimo"
cobra pedagio de toda reescrita futura. Passou a varrer a historia inteira, com controle positivo e
a inversa.

⚠️ **3. Batizar migration e teste pelo numero da issue ANTES de criar a issue.** O 1727 foi para
outra issue e o fix virou #1728: rename de 2 arquivos, referencias em 3, `UPDATE` no
`schema_migrations.name` e **uma migration a mais** so para reescrever os `COMMENT ON` (que ficam
gravados em `pg_proc`, ao contrario dos comentarios `--`).

⚠️ **4. Duas suites contra o mesmo banco nao convivem.** A primeira rodada ficou invalida pelo
rename no `package.json`; matar e reiniciar foi mais barato que interpretar. `npm test` leva
**~12 minutos**: rodar em segundo plano, nunca numa chamada com teto.

---

## Estado

- **PR #1730 MERGEADA** (`48463fb2`), CI verde nas 11 checagens. DDL ja estava em producao
  (`20260811000816` + `20260811001755`).
- `npm test`: **6662 testes, 0 fail, 1 skip**. `npx astro build`: ok.
- `check_schema_invariants()`: **43 invariantes, 0 violadas**.
- md5 do corpo vivo == arquivo local nas duas funcoes.
- Guard novo: 7 testes, 3 camadas, com inversa e **mutacao verificada** (reintroduzir o gate antigo
  derruba exatamente 2 dos 7).
- **#1719 fechada.** Zero bypass nesta sessao: tudo por PR.

## Proxima sessao

1. **#1726**: o PM envia a comunicacao. Enquanto nao sair, o #1710 continua bloqueado.
2. **#1710**, ja com duas restricoes novas no escopo (corte local do #1727, coorte vazia do #1729) e
   um item a mais: **o dry-run tem de reportar coorte por evento**, senao os dois casos passam
   despercebidos - os dois produzem "sucesso" com zero linhas, indistinguivel de "todo mundo ja
   estava registrado".
3. Depois: **#1654** (coluna de nome fixa nas 6 tabelas com scroll horizontal), **#1218** (presenca
   orfa de 08/07).
4. Seguem abertas: **#1655** (unificacao dos 4 componentes + `src/pages/profile.astro` 1015/1385),
   **#1656** (3 dos 5 itens), **#1724** e **#1725** (higiene de CI), e as **20** RPCs restantes da
   classe do #1728.
