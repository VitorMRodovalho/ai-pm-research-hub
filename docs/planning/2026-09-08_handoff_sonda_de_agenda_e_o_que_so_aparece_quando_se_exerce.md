# Handoff de 08/09/2026: a sonda de agenda, e o que só aparece quando se exerce o caminho

> **Nada aqui é medição.** Foi carimbado no fim de 08/09 e envelhece sozinho. Antes de decidir,
> re-meça: `git fetch && git log --oneline -1 origin/main`, `gh pr list --state open`,
> `gh issue list --state open --limit 30`.

Estado ao encerrar, para você **comparar** e não para acreditar: `main 28727486` · fila **0 PRs** ·
4 PRs mergeadas no dia, **todas por squash com CI verde, nenhuma com `--admin`** · nenhum push
direto. A janela de bypass não avançou.

## A sessão retomou de 04/09, com quatro dias de vão

A sessão anterior fechou em 04/09 e o arranque de 05/09 nunca foi executado. Duas coisas dele
foram medidas hoje, e as duas responderam:

- **A previsão da `#2185` sobreviveu.** `pii_access_log.actor_kind = 'unknown'` continua em **0**
  depois de 584 linhas novas de `automation` (7.592 → 8.176). Nenhum escritor ficou de fora.
- **As agendas do 04/09 mudaram**, e é onde o dia inteiro acabou indo.

## O que foi entregue

Quatro PRs, e cada uma existe porque a anterior foi **exercida de verdade** e falhou:

| PR | o que fechou |
| --- | --- |
| `#2194` | fase 1 da `#2188`: o despacho registra o estado da agenda |
| `#2195` | o segredo vem do Vault, e a sonda lê a grade que existe no DOM |
| `#2196` | a sonda não devolve texto de exceção na resposta HTTP |
| `#2198` | base do CodeQL desce de 101 → 96 alertas, altos 55 → 50 |

### A `#2188` fase 1, e o que ela deliberadamente NÃO fecha

`interview_agenda_probes` (RLS deny-all, RPC-only), duas colunas em `selection_dispatch_url_log`
(`agenda_days_open`, `agenda_probed_at`), o endpoint `/api/internal/agenda-availability-probe` que
renderiza cada agenda com o binding `BROWSER` (o mesmo do PDF de certificado), o leitor
`get_interview_agenda_health` e um cron 4x ao dia.

**Fora do escopo, e o contract test não finge o contrário:** o rodízio ainda NÃO pula agenda vazia
(item 1 da issue), o despacho ainda NÃO falha de forma visível (item 2), não há alerta quando um
avaliador ativo zera (item 4). Os três leem o dado que esta fase começa a produzir.

⚠️ **`despachos_com_estado_de_agenda` = 0 ao fechar o dia.** Isso é correto, não defeito: nenhum
despacho novo aconteceu desde a migration. O primeiro despacho de researcher será a primeira linha
com número.

## O que quebrou, e por que só apareceu ao exercer

Três premissas minhas caíram, e **nenhuma delas teria caído sem rodar o caminho de verdade**.

**1. O GUC não podia ser setado nesta plataforma.**
```
ALTER DATABASE postgres SET app.agenda_probe_internal_secret = '...'
ERROR: 42501: permission denied to set parameter
```
Eu havia copiado o desenho do **comentário** da migration do `cert-pdf-render`. Medido:
`pg_db_role_setting` não tem NENHUM `app.*secret*`, e o próprio `cert_pdf_internal_secret` mora no
**Vault** desde 2026-05-23. O comentário descrevia um caminho que nunca funcionou aqui. O cron
ficaria para sempre no ramo "sem segredo, não chama nada": verde, silencioso e inútil.

**2. A sonda estava cega nas quatro agendas.** Primeiro disparo real: `probed=4 fechadas=0
cegas=4`. Casei `[role="gridcell"]`, que **não existe no DOM**. A grade é uma
`<table role="grid">` com `<td>` sem role, e o papel gridcell é *implícito*, existe na árvore de
acessibilidade e não no HTML. Escrevi o seletor a partir do snapshot do Playwright, que é uma
**projeção** do DOM. Quem carrega o `aria-label` é `<button data-grid-cell>`.

> **A coluna `ok` pagou o próprio custo na primeira execução real.** Sem a distinção entre "sonda
> cega" e "agenda fechada", essa rodada teria gravado `days_open = 0` para as quatro e concluído
> que TODAS estão fechadas, e a fase 2 esvaziaria o rodízio por causa de um seletor errado.

**3. Vazamento de stack trace**, cobrado pelo ratchet do CodeQL. Eram **quatro** pontos, não o um
apontado: `browser_failed`, `render_failed`, `write_error` (mensagem do Postgres, que nomeia
tabela, coluna e constraint) e `query_failed`. O diagnóstico continua no log do Worker e na coluna
`error` da tabela; a resposta HTTP passa a levar só `error_class`.

## Os dois segredos, configurados

| onde | o quê |
| --- | --- |
| Cloudflare Worker | `AGENDA_PROBE_INTERNAL_SECRET`, via stdin |
| Supabase | **Vault**, `agenda_probe_internal_secret` |

Pareados, conferidos por **sha256 idêntico dos dois lados**, sem o valor transitar por log ou
arquivo versionado. Rotação: `wrangler secret put` + `vault.update_secret`.

⚠️ **`/tmp/.ag_probe_secret` ficou na máquina** com o valor em claro (modo 600). A remoção foi
negada por permissão. Apagar com `shred -u /tmp/.ag_probe_secret`. O valor já vive nos dois
lugares certos.

## Estado final, medido

```
sondagens gravadas: 12 (8 ok; as 4 primeiras foram a rodada cega)
bloqueios de roteamento ativos: 0
candidaturas com URL de currículo e sem arquivo: 6
despachos com estado de agenda: 0
```

Última sondagem: `probed=4 fechadas=0 cegas=0`, janela 30/08 a 10/10.

| agenda | dias abertos |
| --- | ---: |
| GP | 23 |
| institucional | 19 |
| Fabricio | 13 |
| Fernando | 13 |

## O rodízio: bloqueio posto e retirado no mesmo dia

De manhã, a agenda do Fabricio tinha **0 horários** de 30/08 a 10/10, e ele era a **posição 1 do
LRD**, e o próximo despacho de researcher iria para porta fechada. Registrado um blackout pela RPC
canônica `set_interviewer_routing_block`, com auditoria, e provado por contrafactual que o rodízio
passou a eleger o Fernando.

À tarde o Fabricio ajustou ("Feito" no grupo) e a sonda mediu **13 dias**. O blackout foi removido
por `clear_interviewer_routing_block`: a premissa caiu, e mantê-lo puniria quem já corrigiu.

## ⚠️ Uma decisão do dia cuja PREMISSA MUDOU

De manhã você decidiu **deixar os tokens dos 3 presos vencerem** e tratar só no conserto
estrutural. Naquele momento a agenda do Fabricio estava fechada e o cenário era ruim.

Ao fechar o dia: **3 candidaturas em `interview_pending`, 0 reservas, token vencendo 09/09 às
11:00 BRT**, e agora **as quatro agendas estão abertas**. A decisão continua sendo sua, mas o
cenário que a motivou não é mais o mesmo. Se nada for feito, os três perdem o caminho de
agendamento amanhã de manhã.

## O import do VEP, e um achado maior que o relatado

O import consolidado reportou "1 resume falho": `311824`, `storage_upload_520`. O `520` foi no
upload para o **nosso** Storage, não na leitura do Azure. A origem respondia `200` com 205 KB.
**Reimport resolveu**: `resume_storage_path = cycle-cycle4-2026/12902948.pdf`, e o total de
resumes subiu 76 → 77 com 0 falhos.

Medindo o acervo, porém: **7 candidaturas sem arquivo**, não 1. As outras **6 são de 14/03**, todas
`leader`, **sem `cv_extracted_text`**, com assinaturas do Azure **expiradas em jan/abr**. O
currículo dessas pessoas não existe mais nem aqui nem na origem. As 6 já estão decididas (3
`approved`, 2 `converted`, 1 `rejected`), então **nenhuma avaliação está travada**: o dano é de
acervo. Registrado na `#2199`.

## O webinar da Tribo 11, e o que a plataforma não cobrou

O webinar de hoje (20h, painel "Sua área entrega bem. Isso garante que ela continue existindo?")
chegou às 14h **sem nenhuma peça publicada nem agendada**.

⚠️ **A primeira medição que fiz deu "zero" e estava ERRADA.** Olhei `comms_scheduled_posts`, que só
registra o que sai **pela API**. Esta campanha é manual por decisão documentada no kit (a automação
não faz marcação na imagem nem convite de colaborador), então **uma campanha inteira executada
corretamente aparece como ausência total naquela tabela**. A superfície certa é
`comms_media_items`.

O que de fato saiu: o anúncio D-10 em 29/08 (Instagram + LinkedIn, este impulsionado). **Não saiu**
o lembrete D-1 de 07/09 nem a peça do dia. Publiquei as duas de última chamada, com a copy do kit;
a do LinkedIn **reprovava no lint do próprio projeto** (4 hashtags, que a régua corta) e foi
corrigida.

**Pendente e fora da plataforma:** as 5 menções no post do LinkedIn (à mão, e **antes de
impulsionar**, porque o kit mediu em 01/09 que post impulsionado aceita a edição na tela, responde
"Changes saved" e continua com o texto antigo), o story das 19h45 e o WhatsApp das 19h50.

## Issues abertas hoje

- **`#2193`**: a divulgação de webinar depende de alguém lembrar: a plataforma tem `scheduled_at`,
  `promo_kit_url` e o canal, e nada cobra a fila.
- **`#2197`**: o ratchet do CodeQL corre contra a análise que ele lê. Medido: ratchet
  `completed/failure` às 20:33 com o `CodeQL Analysis` ainda `in_progress`, e o alerta que ele
  reprovou visto no commit ANTERIOR ao conserto. Todo merge que conserta um achado vai reprovar uma
  vez. A **A3** já resolveu essa classe para o deploy com `workflow_run`; a issue propõe herdar.
- **`#2199`**: falha de sync de currículo não tem leitor nem retry, e a assinatura da origem
  expira em dias.

As três são a mesma forma da `#2130` e da `#2188`: **a plataforma registra o defeito e não tem quem
o consulte.**

## Não consertado, e vale issue própria

**Os dois gatilhos de PDF de certificado divergem.** `_trg_certificate_pdf_autogen` lê do Vault
(funciona); `_trg_event_guest_cert_pdf_autogen` lê de `current_setting('app.cert_pdf_internal_secret')`,
que **não existe e não pode ser criado** nesta plataforma. O PDF de certificado de convidado de
evento externo (`#1098`) pula em silêncio. Registrado no cabeçalho da migration `20260908193328`.

## Prazos vivos

- **09/09 11:00 BRT**: vencem os tokens dos 3 candidatos em `interview_pending` (ver a seção da
  premissa que mudou)
- **09/09 17:18 BRT**: expira a assinatura do último currículo recuperável, caso outro falhe
- **10/09**: Reunião Geral
- **11/09**: aprovação do TAP do Grupo de Estudos CPMAI (lane `.wt-cpmai`, parada desde 31/08)

## Do lado do PM, e atravessou o dia

Os **cinco pontos da pauta** da Reunião Geral seguem parados desde 04/09. O Fernando também deu
janelas específicas para entrevistas (quinta 14:30 às 18h, sexta 14:30 às 18:30, e amanhã não
pode). Isso é **mais fino do que o rodízio LRD enxerga**, que distribui por último-despacho e não por
preferência de dia. E ele pediu opinião sobre um formulário de onboarding.

## A regra da sessão, que vale para a próxima

> **Copiar o comentário não é verificar o caminho. Ler a projeção não é ler a fonte.**

Os três defeitos do dia têm a mesma forma: eu li uma **representação** de algo em vez do algo.

- O comentário da migration do cert descrevia um GUC que nunca funcionou → medir
  `pg_db_role_setting`, não ler o comentário.
- O snapshot de acessibilidade mostrava `gridcell` que não existe no HTML → medir o DOM, não a
  árvore derivada.
- `comms_scheduled_posts` representava a campanha que saiu pela API, não a campanha → medir a
  superfície onde o fato acontece.

E o corolário que salvou o dia: **guarde a diferença entre "não sei" e "é zero"**. A coluna `ok`
custou uma coluna e evitou que um seletor errado esvaziasse o rodízio de entrevistas.
