# Handoff - a comunicacao saiu e os tres bloqueios do #1710 cairam (10-11/08/2026)

> Continuação de `docs/planning/2026-08-10_handoff_1710_passo2_elegibilidade.md`.
> Cobre as PRs **#1730, #1731, #1732 e #1734**. `main` em **`c2b4137a`**.
>
> 📖 **Se for ler so uma parte, leia "SEGUNDA PARTE DA SESSAO" e "Estado final", mais abaixo.** A
> primeira metade descreve o caminho ate a PR #1730 e continua valendo como historico, mas o desfecho
> (comunicacao enviada, #1727 e #1733 fechadas, tribo 2 cancelada) esta na segunda.

## Regra zero

Todo numero aqui foi medido em **10/08/2026 entre 20h e 21h30 (Brasilia)**, salvo os da segunda
parte, medidos na madrugada de 11/08. ⚠️ Nesse intervalo o banco **virou o dia em UTC**, e isso mexe
nos numeros: re-medir com tool call na mesma volta em que o numero entrar numa decisao, num commit,
numa issue ou numa pergunta ao PM.

⚠️ **A tabela "Os numeros do #1726" mais abaixo esta CONGELADA em 21h15 de 10/08** e serve para
mostrar a distancia entre a abertura da issue e a medicao correta. Ela **nao** e o numero de hoje: a
base recebe presenca continuamente, e o corte da janela mudou desde entao (#1727). Re-medir sempre.

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

⚠️ **5. Checar a faixa e IMPRIMIR o resultado nao e checar.** Uma das rodadas de `npm test` saiu com
CI da `main` em voo porque o comando so imprimia `runs em voo: 1` e seguia adiante — a verificacao
era informativa, nao porteiro. Nao houve dano (os dois fecharam verdes), mas foi sorte. A regra do
`deploy.md` e prosa; **nao existe helper que a torne executavel**, e por isso e violavel sem
perceber. Um `pretest` automatico NAO serve: o proprio CI roda `npm test` e se veria em voo,
travando sozinho. O helper tem de ser de uso local, explicito.

---

# SEGUNDA PARTE DA SESSAO (madrugada de 11/08)

O handoff acima foi escrito antes desta parte. O que segue e o desfecho.

## O que mudou desde entao

### A comunicacao SAIU (decisao do PM, 10/08)

Enviada pelo **grupo de WhatsApp do Nucleo**, nao por e-mail, para nao duplicar envio nem consumir
cota do Resend. O texto dos 3 idiomas fica como registro do que foi decidido comunicar.

**Isto destrava o #1710.** Contando os 14 dias a partir de 10/08, o primeiro selo pode rodar a partir
de **24/08/2026**.

⚠️ O texto redigido dizia "a partir de 25/08" porque pressupunha envio em 11/08. **Vale a data que
foi dita as pessoas no grupo**, nao a do documento: conferir antes de configurar o cron.

⚠️ **Alcance.** O grupo alcanca quem esta no grupo, que nao e necessariamente o mesmo conjunto dos 86
membros ativos. O selo grava falta para 48 pessoas. Mitigacao de custo zero, se o PM quiser: o
**anuncio in-app** (tabela `announcements`) e banner na plataforma, nao passa pelo Resend e ja tem os
3 idiomas.

### Os tres bloqueios tecnicos do #1710 CAIRAM (PR #1732)

| | antes | depois |
|---|---|---|
| **#1727** corte da janela | `e.date <= CURRENT_DATE` (data, em UTC) | instante LOCAL de termino |
| **#1729** coorte vazia | carimbava "lista fechada" com 0 linhas | `skipped_empty_cohort`, sem carimbar |
| **dry-run** | nao existia | `preview_seal_attendance`, 223 eventos em 480 ms |

⚠️ **O #1727 estava subdimensionado no corpo da issue**, e foi corrigido la. Nao sao 3 horas, sao ate
**23**: `e.date <= CURRENT_DATE` compara DATA, entao o evento de hoje as 20h e elegivel desde o
instante em que o dia UTC comecou. A virada de fuso responde por 3 dessas horas; as outras 20 vem de
comparar data em vez de instante. **Corrigir so o fuso nao resolveria.**

O instante de termino virou **uma** funcao, `_event_end_instant`, usada pela elegibilidade E pela
guarda do selo. Usa `duration_minutes` porque o corte certo e o FIM: selar durante a reuniao marcaria
falta de quem ainda esta nela.

Alcance medido antes de aplicar: `_attendance_eligible_events` e a primitiva canonica (SPEC §3b) com
**9 consumidores**. 524 pares (pessoa, evento) → **502**; os 22 removidos sao 4 eventos por terminar,
e **0** deles tinha presenca registrada.

### Tribo 2: as 8 futuras foram canceladas

Decisao do PM. Antes/depois: 8 futuras ativas → **0**; 20 passadas → **20**, nenhuma cancelada; **50**
linhas de presenca preservadas.

⚠️ **As 5 de coorte zero seguem na janela** (sao passadas, 13/07 a 10/08). Agora sao inofensivas
— aparecem no ensaio como `skipped_empty_cohort` — mas a **causa raiz continua aberta**: por que
arquivar a iniciativa nao parou a recorrencia.

### #1733: `db:types` destruia o proprio arquivo

`supabase gen types ... > src/lib/database.gen.ts`. O `>` trunca ANTES de rodar, entao a falha
(`LegacyProjectNotLinkedError`) gravou o JSON de erro por cima: **34.288 linhas viraram 1**. Corrigido
para gerar em `mktemp`, validar o cabecalho e mover com `&&`; e `--project-id` no lugar de `--linked`,
alinhando com o gate.

⚠️ **A versao da CLI NAO era o problema.** Medi com `npx supabase --version` (2.113.0) e quase
reportei divergencia contra o pin 2.109.0 do workflow. O `npx` **baixa a mais recente** e nao e o
binario que o script resolve — o global era 2.109.0, identico ao pin. **Meca o binario resolvido,
nunca o `npx`**; mexer no pin com base nesse numero produziria drift falso.

---

## Estado final

- **`main` em `c2b4137a`**. Quatro PRs mergeadas, **zero bypass**, CI verde em todas.

| PR | entrega | commit |
|---|---|---|
| #1730 | escopo de recurso nas RPCs de presenca (#1728) + entregavel da #1726 | `48463fb2` |
| #1731 | handoff (primeira parte) | `633d4170` |
| #1732 | corte local, coorte vazia e dry-run (#1727, #1729) | `94a8f1aa` |
| #1734 | `db:types` para de destruir o arquivo (#1733) | `c2b4137a` |

- `npm test`: **6677 testes, 0 fail, 1 skip**. `npx astro build`: ok.
- `check_schema_invariants()`: **43 invariantes, 0 violadas**.
- md5 do corpo vivo == arquivo local em todas as funcoes tocadas.
- **Fechadas:** #1719, #1727, #1733.
- Guards novos: `1728-presenca-escopo-de-recurso` (7), `1727-corte-local-e-coorte-vazia` (10),
  `1733-db-types-nao-destroi-o-arquivo` (5). Todos com a inversa e **mutacao verificada**.

## Proxima sessao

1. **#1710**, agora com caminho livre. Falta so superficie e operacao, e cabe folgado ate 24/08:
   - [ ] caminho de reversao por evento (nao existe `unseal`; o carimbo `notes = '[roster_seal] ...'`
         e o que permite identificar e desfazer)
   - [ ] superficie para selar, com confirmacao dizendo quantas faltas serao gravadas
   - [ ] a grade mostra se o evento esta selado, e desde quando
   - [ ] tool MCP para selar, na familia do #1588
   - [ ] contagem de eventos selados publicada depois de uma semana

   ⚠️ Ao montar a superficie, lembrar que **o ensaio depende de QUEM pergunta**: `preview_seal_attendance`
   tem o gate do #785, entao a contagem que um lider ve pode ser menor que a do GP. A decisao de selar
   e do GP.

2. **#1729** — a causa raiz da recorrencia da iniciativa arquivada.
3. Depois: **#1654** (coluna de nome fixa nas 6 tabelas com scroll horizontal), **#1218** (presenca
   orfa de 08/07).
4. Seguem abertas: **#1655** (unificacao dos 4 componentes + `src/pages/profile.astro` 1015/1385),
   **#1656** (3 dos 5 itens), **#1724** (ampliada com a inanicao da faixa) e **#1725**, e as **20**
   RPCs restantes da classe do #1728.

## Duas ofertas em aberto, decisao do PM

- **Anuncio in-app** da mudanca de presenca, para cobrir quem nao esta no grupo de WhatsApp. Custo
  zero de e-mail.
- **Helper de faixa livre** para uso local, tornando executavel a regra do `deploy.md` que hoje e so
  prosa (ver armadilha 5).
