# Prompt de arranque: #1710 com prazo em 24/08, e a fila finalmente livre

> Colar depois do `/clear`. **Modelo: Opus 5 (auto, não pinar). Effort: `xhigh`.**
> **Supersede** `2026-08-19_PROMPT_ARRANQUE_FILA_TRAVADA_E_FILIACAO.md`, cujo item 1 (fila travada)
> foi **resolvido** e cujo item 2 (#1855) foi **entregue**.

---

## Regra zero

**Nada deste documento pode ser recitado.** Todo número foi medido em 19/08/2026 até 22:10 UTC.
Re-meça com tool call na mesma volta em que o número entrar numa decisão, commit, issue ou pergunta.

🔴 **Confira o RELÓGIO antes de executar a ordem sugerida.** `date -u` **e** `now()` do banco, e leia
os passos pela **pré-condição**, não pela data.

Regras de varredura ganhas em 19/08:

- 🔴 **Contar da tabela de LINHAS em vez do CATÁLOGO produz um denominador que não é o do produto.**
  Contei 12 linhas de `onboarding_progress` e conclui "4 de 12" sobre alguém que a plataforma mostra
  como **4 de 7**. Publiquei errado na #1875 e tive que corrigir.
- 🔴 **Um caso não é uma causa.** Atribuí a lentidão do CI à contenção que eu tinha criado; o modo de
  falha já existia em duas branches alheias no dia anterior.
- 🔴 **Sondar com nome de chave errado devolve o `ELSE` e parece resposta.** Sondei `_delivery_mode_for`
  com `affiliation_renewal_30d` (inexistente), todos caíram no default e quase publiquei que nenhuma
  faixa dispara e-mail imediato. Com o nome real, `affiliation_renewal_d7_urgent` é imediato.
- ⚠️ **Ler código não é exercer o caminho.**
- ⚠️ **Envelope não é prova.** Confirme o EFEITO na fonte.

---

## Estado

`main` em **`dbf7a6fc`** + os merges de 19/08. **Fila VAZIA** (0 PRs abertas ao fim da sessão).
**Bypass na janela: 0 de 2.** Invariantes: **1 violação, a declarada** (`U`, #1850).

### O que entrou em 19/08

| PR | o que |
|---|---|
| #1868 | mecanismo de exceção declarada de invariante |
| #1871 | conserto do laço do `usePageI18n` (**verificado em uso**) |
| #1874 | orçamento de saturação do CI |
| #1872 | captura da migration do #1855 |
| #1864 #1861 #1865 #1859 | a fila que estava travada |

📌 **`check-invariants` vermelho é ESPERADO e correto.** A violação do #1850 está declarada em
`tests/helpers/invariant-exceptions.mjs`, com issue e vencimento em **30/09**. O job dedicado roda com
`INVARIANT_STRICT=1` e fica vermelho de propósito; o `validate` (required) fica verde. **Não conserte isso.**
Quando a Diretoria verificar o caso, **a entrada sai do arquivo**.

---

## 🔴 ITEM 1: #1710, prazo 24/08. É o único item com data irreversível.

**Config conferida em 19/08 22:05 UTC, e ela está intacta:**

| | |
|---|---|
| `platform_settings['attendance.seal_window']` | `{"floor_date":"2026-08-24","grace_days":14}` |
| hoje (local, America/Sao_Paulo) | 2026-08-19 |
| **dias até o piso** | **5** |
| cron | `attendance-seal-window-daily`, `40 11 * * *`, **ativo** |

🔴 **CORREÇÃO (medida em 19/08 22:14 UTC): o número NÃO é teto.** Ele tem DUAS forças opostas. As
faltas encolhem a cada presença registrada, mas o conjunto de eventos devidos **CRESCE** conforme a
janela de graça (14 dias) desliza e mais eventos cruzam o corte. Replicando o predicado do cron:

| cenário | corte (fim do evento) | devidos | selam | coorte vazia | faltas |
|---|---|---|---|---|---|
| agora (19/08) | 2026-08-05 22:14 | 42 | **38** | 4 | **76** |
| piso (24/08 11:40 UTC) | 2026-08-10 11:40 | 47 | **43** | 4 | **83** |

A linha do piso é **simulação, não medição**: a coorte é lida de hoje. Que ela caia em 43 selos, o
mesmo número de 15/08, é **coincidência de duas partes móveis**, não estabilidade. **RE-MEDIR EM 23/08.**
Distribuição das 83 faltas: **41 pessoas**, sendo 17 com uma, 13 com duas, 8 com três, e uma com sete.

📌 **Os dois caminhos medem COISAS DIFERENTES, e divergir é o desenho, não achado.**
`seal_attendance_window_cron` (o ato) **não tem gate de chamador**. `preview_seal_attendance` tem
**dois** (`_can_manage_event` + `rls_can_see_initiative`) e mede o que UM chamador alcança: a
diferença entre os dois É a grade fora do alcance do líder, que já foi decidida como sendo do GP.
O preview também exige `auth.uid()` e recusa `service_role` com "Not authenticated" (medido em 19/08).

⚙️ **A consulta do caminho (b) está congelada em `docs/audit/1710_MEDICAO_SELO_23AGO.sql`**, já
parametrizada por `grace_days` e `floor_date` da config, e conferida contra os números acima. Em
23/08 é só executar. Ela caduca se o corpo de qualquer uma das três funções mudar.

⚠️ **A entrevista de 24/08 23:30 UTC cai no MESMO dia do prazo.** Não deixe os dois para a mesma sessão.

⚖️ **Já decidido, não re-litigar:** células fora do alcance de líder ficam com o GP pela grade geral;
lista nominal ao GP **fora de issue e PR**. Ensaio antes do piso devolve `skipped: before_floor`.

## ⏰ ITEM 2: relógios de amanhã

- **09:00 UTC** — o cron do **#1855** roda **sem freio pela primeira vez**. Esperado: **9 notificações**
  (7 da faixa d30 + 2 da faixa nova de vencidas), todas `digest_weekly`. **Confirme que saiu o esperado**
  e que nenhuma virou e-mail imediato. `affiliation_renewal_d7_urgent` É imediato, mas tinha 0 pessoas.
- **14:00 UTC** — `nudge-reschedule-pending-daily` pega os **9 candidatos** em `needs_reschedule`.

## ITEM 3: comunicações aguardando aprovação do PM

Arquivo: `docs/_deliverables/2026-08-19_comunicados_tribo_talentos_e_horarios.md` (rascunho antigo, com
o Figueiredo). **Os textos A e B foram REESCRITOS para o Marcelo Pereira na conversa e ainda não estão
em arquivo.** Recupere-os do handoff ou refaça:

- **A** → Marcelo Pereira (na tribo desde 07/08, Drive desde 08/08, falta `start_trail`).
- **B** → Jefferson Pinto (líder), sobre o Pereira + manter horário publicado.
- **C** → líderes das **6 tribos sem horário publicado**. Falta levantar quem são.

⚠️ **Não use o rascunho antigo.** Ele dá boas-vindas ao Figueiredo, que **não está em tribo** (a
alocação foi revertida em 19/08 a pedido do PM: ele escolhe a tribo dele depois do onboarding).

## ITEM 4: worktree paralela em curso

**#1877** (auditoria da jornada de onboarding) roda em worktree própria, com prompt em
`docs/planning/2026-08-20_PROMPT_ARRANQUE_WORKTREE_1877_JORNADA_ONBOARDING.md`.
Ela **não mergeia**: entrega handoff + PR verde, e **esta sessão faz o QA e o merge**.

⚠️ **Não disputem CI.** O `validate` fala com produção. Combine a janela antes de as duas abrirem PR.

## ITEM 5: o resto, com dono

- **#1876** (não existe porta de reenvio do convite) · **#1875** (120 linhas órfãs de onboarding)
- **#1869** entregue em parte: o orçamento existe, **a causa da saturação era a #1870 e saiu**. A suíte
  ainda roda contra produção, que é a saída estrutural (#1844).
- **#1870 FECHÁVEL:** consertado e **verificado em uso** (1 chamada, 0 backends, site público em 0,27 s).
- **#1863 #1866 #1867 #1854 #1852** (filiação) · **#1842 #1829 #1822 #1592 #1205 #905** (30/09)
- **#588** `[LL]` do PMO · **#92** (raiz da #1614)
- 🆕 **Três candidaturas com `interview_status='scheduled'` sem entrevista agendada** (família do #1842).
  Sem issue. Some se ninguém abrir.

---

## Ordem sugerida

1. **Conferir o cron do #1855** (pré-condição: passou das 09:00 UTC de 20/08): saiu o esperado?
2. ✅ **FEITO em 19/08 22:1x UTC.** Caminho (b) congelado em `docs/audit/1710_MEDICAO_SELO_23AGO.sql`,
   e o item 1 acima corrigido: o número não é teto, e os dois caminhos divergem por desenho.
3. **Textos A, B e C** ao PM, se ele aprovar. **C ainda exige levantar as 6 tribos sem horário.**
4. **23/08: re-medir o #1710** pelos dois caminhos, sabendo que eles medem recortes diferentes.

---

## Armadilhas

1. ⚠️ **`preview_seal_attendance` recusa `service_role`.** Use a porta MCP ou replique o predicado.
2. ⚠️ **`CURRENT_DATE` é UTC.** O cron do selo já usa `America/Sao_Paulo` de propósito (#1727). Ao
   replicar o predicado, **use o mesmo fuso**, senão sua contagem diverge da do cron por algumas horas.
3. 🔴 **`check-invariants` vermelho é o desenho.** Ver acima.
4. ⚠️ **DDL exige ZERO PRs abertas.** Com a worktree ativa, isso agora precisa de combinação.
5. ⚠️ **`apply_migration` cria o timestamp**: renomeie o arquivo local para ele. A CLI não está linkada.
6. ⚠️ **Teste novo entra nas DUAS whitelists do `package.json`.**
7. ⚠️ **`Fecha #N` NÃO fecha. Use `Closes #N`** — e escrever sobre a palavra-chave dispara.
8. ⚠️ **`git checkout -b <nome> origin/main`. Nunca `git add -A`** (~60 arquivos não rastreados).
9. ⚠️ **Repo PÚBLICO.** Nome, e-mail e identificador não entram em issue, PR nem doc.
10. ⚠️ **O build leva 4 a 6 min:** background + confira o `Complete!`.
11. 🔴 **SQL direto por `service_role` grava ato humano como 'cron' com actor nulo.** Use a porta MCP,
    ou o cliente autenticado da página via `window.navGetSb()` (foi assim que os 8 convites saíram).
12. ⚠️ **Não rode a suíte inteira sem necessidade.** Ela fala com produção.
