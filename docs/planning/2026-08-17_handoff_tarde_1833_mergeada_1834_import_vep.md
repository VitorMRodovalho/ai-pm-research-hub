# Handoff: a tarde de 17/08, duas reservas invisíveis, o import do VEP e a #1833 mergeada

> Sessão de 17/08/2026, tarde UTC (14:30 a 17:00). Anterior:
> `2026-08-17_handoff_item1_verificado_1586_fechada_1829_aberta.md`.
>
> ⚠️ **Repo público.** Este documento conta população, nunca pessoa, e não publica e-mail nem
> identificador. Os nomes vivem na plataforma e no export do VEP, que é git-ignored e cuja própria
> nota de minimização manda apagar as cópias locais depois do import.

---

## O que entrou

| entrega | antes | depois |
|---|---|---|
| entrevistador no histórico de `/admin/selection` | não aparecia | **nome, ou "não registrado"** |
| `get_application_interviews` | só `interviewer_ids` | **+ `interviewers` com nome** |
| entrevistas registradas no ciclo | 2 | **3** |
| reservas medidas no funil | 0 | **1** |
| invariantes | **43, com 1 violação** | 43, **zero** |

`main` em **`c30f481d`** (PR #1833, **12/12 verde, sem `--admin`**), migration `20260817145902`,
zero PRs abertas, zero eventos de bypass em 7 dias. EF `nucleo-mcp` em `ef_version` **2.102.0**.

## Duas reservas de entrevista chegaram, e nenhuma pela plataforma

O PM mandou print de duas reservas feitas no calendário de agendamento de um entrevistador. As
duas eram invisíveis para a plataforma: zero linha em `selection_interviews`, `booked_at` nulo.

A primeira tinha risco de relógio: a candidatura estava em `interview_pending` e **o cron das 15:30
mandaria convite para quem já tinha marcado**, porque o predicado dele exclui quem tem entrevista
futura agendada e não havia linha. Registrada à mão pela porta MCP às 14:36, ela saiu do predicado
por dois caminhos independentes (status e linha futura).

✅ **O cron rodou às 15:30 e resgatou exatamente 2**, com `refused_count: 0` e `error_count: 0`.
Eram 3 elegíveis pela manhã; a intervenção tirou uma. Convite duplicado não aconteceu.

📌 A segunda reserva é **a primeira conversão da rodada de resgates manuais de 02:45**: a pessoa
recebeu o convite, abriu e agendou. `schedule` carimbou `booked_at` sozinho e ligou
`booked_interview_id`, porque a linha de despacho dela é instrumentada.

⚠️ **Duas ressalvas que precisam viajar com esse número:** `booked_at` guarda a hora do REGISTRO
manual, não a da reserva; e `first_opened_at` segue nulo, embora ela obviamente tenha aberto. A
outra reserva não entra na conta porque o convite dela é anterior à instrumentação. **Há 2 reservas
reais e 1 medida.** Não carimbar a outra à mão foi decisão consciente: inventar `booked_at`
transformaria estimativa em medição.

## #1614: a causa está na CLASSIFICAÇÃO, não no casamento

Proposta medida publicada na issue. O matcher casa por `guest_email` e teria funcionado: o endereço
usado na reserva era o mesmo da candidatura. O que falhou foi antes.

O Apps Script decide quem é o candidato com **uma lista fixa de três e-mails**, e quem não está
nela vira candidato. Medido em `selection_booking_attempts`:

| lido como candidato | tentativas | desfecho |
|---|---|---|
| endereço pessoal do operador (o institucional está na lista, o pessoal não) | **11** | `no_application` |
| um entrevistador do comitê | 2 | `cycle_closed` |
| outro integrante do comitê | 1 | `cycle_closed` |
| três endereços institucionais do capítulo | 1 cada | `no_application` |

📌 **Os 11 registros "do endereço do próprio operador" da #1664 são este defeito.**

Proposta em três camadas: completar a lista para destravar, **tirar a classificação do script** e
devolvê-la ao servidor que tem o catálogo, e filtrar por **organizador do comitê** em vez de
título de calendário. Filtrar por título foi considerado e descartado: é texto livre, editável pelo
dono, e a captura pararia sem erro nenhum.

## #1832, fechada pela #1833: a tela passa a dizer com QUEM

O dado já existia; a RPC devolvia `interviewer_ids` e a UI nunca lia. Agora a RPC devolve também os
nomes, resolvidos **no servidor**: um mapa montado no cliente a partir do comitê atual quebraria
calado quando alguém saísse. `LEFT JOIN` de propósito, para que id sem membro mantenha a posição.

E quando não há entrevistador a tela **diz isso**, em vez de omitir a linha:

| origem da entrevista | total | sem entrevistador |
|---|---|---|
| webhook de calendário | 55 | **24 (44%)** |
| plataforma (com nota) | 10 | 2 |
| plataforma (sem nota) | 64 | **0** |

Omitir tornaria "não temos o dado" indistinguível de "não mostramos o dado".

## #1834: o import do VEP, e a correção que a origem impôs

O CI da #1833 ficou vermelho em dois gates, e **nenhum dos dois era do PR**. Investigar rendeu o
achado do dia.

`import_vep_applications` gravou o estado de **83 candidaturas** às 13:03-13:05 UTC e **não chama
`approve_selection_application()`**. Com isso pulou três garantias que moram lá dentro:

1. **auditoria** (zero linhas em `admin_audit_log`);
2. **vínculo do membro** (`R_approved_application_has_member`);
3. **sincronia da janela de autoridade ao contrato** (a da #1362).

🔴 **A terceira é a pior e a mais invisível.** O import escreveu contrato novo terminando em
30/06/2027 e deixou o vínculo terminando em 11/02/2027: a pessoa **perderia acesso quatro meses e
meio antes do fim do contrato**, sem alarme e sem e-mail.

⚖️ **Correção publicada na própria issue.** Eu havia escrito que as decisões não tinham registro de
"quem, quando e por qual caminho". O **quando** é conhecível: o export do VEP traz carimbo por
decisão (**69 Active e 18 Complete com `acceptanceDateUTC`; 50 de 51 recusas com
`declinedDateUTC`**), cobrindo de 02/09/2025 a 16/07/2026. As decisões foram tomadas ao longo de
dez meses no sistema do PMI; o import apenas as sincronizou. **Aquele minuto é o carimbo do
transporte, não o do fato.** O defeito real, mais preciso, é que a plataforma não guarda vestígio
da sincronização nem carrega o carimbo de origem.

## Dois reparos em dado de produção, ambos com antes e depois medidos

1. **Vínculo de e-mail alternativo.** A candidatura trazia o endereço institucional e o cadastro o
   pessoal. Identidade corroborada por **chave estrutural** (identificador do PMI idêntico nos dois
   lados, mesmo capítulo), não por nome. Pela porta MCP, que preserva o autor. Invariante fechou.
2. **Backfill da janela de autoridade**, com a sentença idempotente que a própria migration da
   #1362 declara. Alcance medido **antes** (81 ativos, 1 violando) e **depois** (81, zero).

📌 **Consequência operacional até a #1834 ser resolvida: rodar o import exige conferir os
invariantes logo depois.** Sem isso, os defeitos ficam latentes até o CI de terceiros reclamar, que
foi exatamente o que aconteceu.

## O ITEM 2 se dissolveu

O arranque anterior trazia "2 aprovados já ativos que nunca foram entrevistados", com decisão de
agendar direto e pendência de data e hora. Hoje são **3** (o import acrescentou um), e o export do
VEP mostra por que a pergunta não se aplica: os três estão **Active na mesma vaga**, com
`submittedDateUtc` **nulo** e oferta estendida e aceita em julho.

**Eles nunca se candidataram.** Entraram por oferta direta, então não havia etapa de entrevista a
cumprir. "Nunca foram entrevistados" não era lacuna, era a forma correta de quem entra por outra
porta. 📌 Falta o PM ratificar, e a pendência deixa de ser "marcar horário".

## Rastreado

- **#1834 aberta** (`type:bug`, `priority:high`, `audit-trail`, `selection`), com o segundo achado
  e a correção anexados.
- **#1829** e **#1614** com material medido.
- **LL no #588**: 8 lições e 4 notas de método, incluindo os erros próprios (normalização com
  `trim` que fabricou falso drift; espaçamento de carimbo lido como "humano clicando" quando era
  laço de import).
- **Memória:** 3 lições duráveis novas, índice compactado de 19,7KB para 17,2KB sem perda.

## Aberto, para a próxima

- 🔴 **Entrevistas em 18/08 e 19/08**, as duas registradas à mão. Enquanto a #1614 não for
  resolvida, **toda reserva nova pelo calendário do entrevistador precisa de registro manual**, e
  só se descobre por print.
- ⏰ **#1710, prazo 24/08**, re-medir em 23/08 pelos dois caminhos.
- **Funil, prazo 28/08:** 105 linhas, 11 instrumentadas, 3 aberturas, **1 reserva medida contra 2
  reais**. Publicar sem o denominador explícito diria conversão falsa.
- **Decisões do PM:** o que fazer com a #1834, se reabre a #1614, a triagem das 56 do #1822, e a
  ratificação dos três de oferta direta.
