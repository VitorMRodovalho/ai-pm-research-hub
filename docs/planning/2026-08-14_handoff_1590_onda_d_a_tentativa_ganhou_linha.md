# Handoff - #1590 onda D: a tentativa que falha ganhou linha

> Sessão de 13-14/08/2026. Arranque: `docs/planning/2026-08-13_PROMPT_ARRANQUE_1590_ONDA_D.md`.
> Handoff anterior: `docs/planning/2026-08-13_handoff_1590_onda_c_o_comite_ganhou_tela.md`.

---

## Regra zero

Todo número aqui foi medido em **13-14/08/2026** e vários se movem sozinhos. `selection_booking_attempts`
saiu de 40 para 41 linhas no meio da sessão anterior sem ninguém tocar em código. Re-medir com tool call
na mesma volta em que o número entrar numa decisão, num commit, numa issue ou numa pergunta ao PM.

---

## O que entrou

**PR #1766**, branch `feat/1590-onda-d-instrumentacao-agendamento`, commit `81f59f23`.

O item que nomeia a onda: *"o candidato que abre a agenda e não encontra horário é indistinguível de
quem nunca clicou; enquanto isso não mudar, qualquer métrica de sucesso de agendamento diz 100% por
construção."*

### A medição que motivou o desenho (13/08, janela de agosto)

Agosto é a **única** janela em que o token de agendamento existe: os 17 tokens de escopo
`interview_booking` foram **todos** emitidos em agosto. Antes disso o despacho saía sem token.

| medida | valor |
|---|---|
| candidaturas com despacho em agosto | 12 |
| com token emitido | **12 (100%)** |
| abriram a página | 6 |
| acabaram com entrevista | 5 |
| **abriram e não reservaram** | **2** |
| nunca abriram e não reservaram | 5 |

O caso literal: **uma candidatura voltou 7 vezes à página em 6 dias e não reservou.** O registro dela
é `interview_pending` / `interview_status = none` - byte por byte o mesmo das 5 que nunca clicaram.

⚠️ **Correção a um item do arranque:** ele dizia que o sinal de abertura cobre pouco ("12 de 55
despachos"). O recorte certo é por janela: o mecanismo é **novo**, não minoritário. Nos 43 despachos
de maio a julho não havia token; desde agosto a cobertura é 12 de 12.

### Decisão do PM (13/08), não re-litigar

1. **O despacho vira a linha viva.** `selection_dispatch_url_log` deixa de ser só log e carrega o
   desfecho. Recusadas com motivo: `access_count` como denominador (só enxerga despacho com token, e
   não separa "não abriu" de "não recebeu") e tabela nova de funil (duplicaria o que o log já é).
2. **As 31 `no_application`:** tirar a sonda do operador da fila e transformar os 6 candidatos reais
   numa fila de VÍNCULO. O resto vira relatório, não trabalho pendente.
3. **Escopo da onda:** instrumentação + #1664. #1587 e #1586 ficam para a PR seguinte.

### O que a PR entrega

Migration `20260813220605`:

- **8 colunas de FATO OBSERVADO** no log de despacho: `booking_token_md5`, `first_opened_at`,
  `last_opened_at`, `open_count`, `booked_at`, `booked_interview_id`, `superseded_at`, `instrumented`.
- **Nenhuma coluna de estado.** O desfecho é derivado na leitura - não há cron para mantê-lo nem
  deriva possível entre a coluna e as linhas que ela resume.
- **Três carimbos:** o despacho aposenta a oferta anterior e guarda o md5 do token; a abertura da
  página carimba a linha EXATA de onde o token saiu; a entrevista criada fecha a oferta aberta.
- `get_interview_booking_funnel(cycle)` com sete desfechos. Janela = validade do **próprio token**
  (14 dias, medido idêntico nos 17), não um N inventado nesta migration.

Superfície: scope `funnel` em `selection_dashboard` (**sem tool nova**), painel na aba de comitê,
16 chaves i18n nas 3 línguas. **ef `2.97.0` · `/semantic` `0.15.0` · 54 tools.**

### Prova

Cadeia inteira exercida em produção dentro de transação abortada (nada gravado):

```
apos 2 despachos: novas=2 supersedidas=1 com_hash=2 abertas=1
apos 2 aberturas na linha aberta: open_count=2 first_opened=t eh_a_linha_do_token=t
linha SUPERSEDIDA carimbada por engano? 0
apos a entrevista: booked=t liga_na_entrevista=t
funil totals={ "booked": 1, "superseded": 1, "pre_instrumentation": 94 }
```

---

## As três issues, respondidas com medição

### #1664 - as 31 `no_application` classificadas

**A classe que a issue supunha ser o grosso é ZERO.** Nenhuma das 31 linhas tem candidatura sob
aquele mesmo e-mail.

| classe | linhas | pessoas | tentativas |
|---|---|---|---|
| **sonda do OPERADOR** (gmail pessoal do PM, fora de toda tabela de identidade) | 11 | 1 | 7.296 |
| **candidato REAL que reservou com OUTRO e-mail** | 7 | 6 | 7.641 |
| sem pista (token único ou desconhecido) | 8 | 7 | 1.241 |
| interno/membro, evento sem entrevista | 4 | 4 | 4 |
| co-convidado de evento que **virou** entrevista (falso alarme) | 1 | 1 | 308 |

Dos 6 candidatos reais, **5 acabaram com entrevista por outro caminho e 1 segue em
`interview_pending` / `interview_status = none`, ciclo aberto, sem entrevista nenhuma.**

O e-mail pessoal do PM não existe em `members.email`, nem em `member_emails`, nem em
`selection_applications.email` - o que confirma a #1614 pelo lado inverso: o defeito não é
"candidato não é membro", é que **o endereço com que a pessoa AGENDA nunca é capturado**.

### #1587 - quantificada no eixo que importa

14 candidaturas com mais de uma linha em `selection_interviews`, e **5 dessas 14 dão resposta ERRADA
hoje** ao serem lidas como `DISTINCT ON ... ORDER BY scheduled_at DESC`: 4 dizem `cancelled` para
entrevista já realizada, 1 diz `scheduled` para entrevista já realizada.

Quem lê "a mais recente por data" nos corpos VIVOS: `selection_rescue_stuck_interview` e
`mirror_sibling_interview`.

### #1586 - confirmado NÃO entregue

O arranque listou como candidata a fechar por já-entregue. **A hipótese trocou as duas funções:**
`interview_manage action='rescue'` mapeia para `selection_rescue_stuck_interview` (convite JÁ
agendado que lapsou). A issue é sobre a complementar, `selection_rescue_unbooked_invite` (convite
emitido e nunca agendado), que aparece **só nos tipos gerados** - zero ocorrências na EF e nas telas.

População medida no ciclo aberto: 9 em `interview_pending`, **7 sem nenhuma linha de entrevista**, e
**5 já gastaram o resgate único** (`interview_auto_rescue_count >= 1`). O cap importa para o desenho.

---

## Armadilhas pagas nesta sessão

1. **`npm run db:types` falhou CALADO mesmo com `TMPDIR` no prefixo do `npm run`.** O arquivo não
   mudou e o `git status` ficou vazio. O que funcionou foi quebrar a cadeia do `&&` e rodar
   `TMPDIR=<scratchpad> mktemp` + `supabase gen types` separados, conferindo o tamanho e a sentinela
   antes do `mv`. **Conferir a FUNÇÃO NOVA dentro do arquivo, não o `git status`.**

2. **Aplicar a DDL com os comentários internos removidos acusa deriva no Phase C.** Os comentários
   dentro de `$function$...$function$` fazem parte de `prosrc` e entram no hash. As quatro funções
   divergiram do arquivo. Conserto: reaplicar os corpos **verbatim** do arquivo. Por isso a onda tem
   **duas** linhas de tracking: `20260813220605` (o arquivo) e `20260813222552` (a reaplicação).
   O achado é o guard funcionando.

3. **`_audit_secdef_public_grant_drift` e `_audit_list_public_function_bodies` estouram o
   `statement_timeout` sob contenção** (504 medido duas vezes em 14/08, com a mesma árvore que
   respondera 200 em 4,5s minutos antes). Mesma classe do #1742. O primeiro foi **substituído por
   sonda direta** - anon batendo na porta da RPC, que é mais forte que inspecionar o grant e caiu de
   61s para 0,4s. O segundo ganhou uma retentativa mirada no transiente.

4. **O conector cacheia `tools/list` e estava DUAS ondas atrasado** - nem o `routing` da onda C
   aparecia. Não dá para exercer `scope='funnel'` pelo conector sem recarregar o catálogo.

---

## Estado ao fim da sessão

- **PR #1766 MERGEADA** em `main` **`0e2016f3`**, **12/12 checks verdes**, zero bypass.
  O `validate` ficou vermelho na primeira volta pelo gate ADR-0097 (a reaplicação criou linha de
  tracking sem arquivo local) e ficou verde depois de o arquivo entrar.
- Migration aplicada em produção; EF **deployada** (`/health` ao vivo: ef 2.97.0, `/semantic` 0.15.0,
  `tools/list` devolve 54).
- Suíte de contratos offline: 6.335 testes, 0 falhas. Guard novo `1590-onda-d-*` com credencial viva:
  **13/13**.
- Comentários de medição postados nas issues **#1664**, **#1587** e **#1586**. As três seguem ABERTAS.

## ⚠️ O mecanismo está ARMADO e INERTE

Medido logo após o merge, em produção:

| medida | valor |
|---|---|
| linhas em `selection_dispatch_url_log` | 94 |
| **instrumentadas** | **0** |
| com hash de token · aberturas carimbadas · reservas carimbadas | 0 · 0 · 0 |

Isso é o esperado — as 94 são as anteriores, e nenhum despacho novo saiu desde a migration —, mas
**significa que a instrumentação nunca foi exercida por tráfego real.** É a mesma situação das 0
linhas em `selection_interviewer_blackouts` ao fim da onda C: a superfície existe, o contrato passa,
e o invariante segue **em vácuo** até o primeiro despacho de verdade.

A prova comportamental cobre a cadeia inteira, mas ela rodou dentro de transação abortada. O
primeiro despacho real é que vai dizer se o carimbo sobrevive ao caminho completo (e-mail incluído).
**Conferir `instrumented = true` + `booking_token_md5` preenchido na primeira linha nova** antes de
publicar qualquer número do funil.

## Próximo

1. **Conferir o `validate` da #1766 e mergear.**
2. **PR seguinte da onda D:** #1587 (view canônica `v_application_interview_state`) + #1586 (expor
   `selection_rescue_unbooked_invite`, endereçando o cap de resgate único).
3. **#1664 fase 2:** a fila de VÍNCULO decidida pelo PM - capturar o e-mail da reserva e oferecer
   "é a mesma pessoa?". Encosta na #1614 (adiada pelo PM em 05/08), que é a mesma causa raiz.
4. **#1762** (o rodízio concentra despachos quando o lote sai na mesma transação) segue aberta e mexe
   no mesmo picker.

## Compromissos com data, de outras lanes

⏰ **Antes de 24/08:** re-medir o que a primeira execução do cron `attendance-seal-window-daily` (#1710)
vai gravar. Em 13/08 eram 51 faltas em 12 eventos, e anda nos dois sentidos.

⚠️ **PRs abertas de outras lanes, não mexer:** #1747 e #1750 (lane Biblioteca).
