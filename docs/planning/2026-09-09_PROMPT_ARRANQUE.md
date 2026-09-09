# Arranque 09/09/2026: reemitir os convites, e fechar o webinar de ontem

> **Nada aqui é medição.** Carimbado em 09/09 às 10:55 BRT, no fim de uma sessão que estourou
> contexto. Re-meça antes de decidir.

```bash
git fetch --all && git log --oneline -1 origin/main
gh pr list --state open
gh issue list --state open --limit 30
```

Estado ao encerrar 08/09, para **comparar**: `main 09b148ae` · fila 0 PRs · 5 PRs no dia, todas por
squash com CI verde, **nenhuma com `--admin`**.

## Primeiro: os 3 convites de entrevista, que venceram às 11:00 de hoje

Três candidaturas em `interview_pending`, todas `researcher`, **0 reservas**:

```
e998f6ec-1b76-4143-894a-9069a3e09d33   abriu o link 3x
15ebca9c-a0fa-4a0f-9d06-8bccfaf2cbba   nunca abriu
36b3cc78-2ff1-4fad-8c60-35a863adc45f   nunca abriu
```

**A decisão do dono (09/09) foi REEMITIR.** Não foi feito na sessão anterior, e o motivo importa:

⚠️ **`issue_interview_booking_token` NÃO envia e-mail.** Medido: ela chama
`_issue_interview_booking_token_core`, que emite o token e grava o log, e o core **não tem** nenhum
`net.http_post` nem caminho de notificação. Reemitir por ela renova o token em SILÊNCIO, e dois dos
três nunca abriram convite nenhum: um token que ninguém sabe que existe não muda nada.

Quem envia é **`_dispatch_interview_booking_link`** (`_`-prefixed, ACL só `postgres` +
`service_role`). Antes de chamá-la, resolva duas coisas:

1. **O gate.** O core pode recusar com `GATE_NO_PEER_REVIEW` (`P0002`). É exatamente o que a
   `#2171` investigou em 03/09: quatro tentativas barradas por esse gate. Meça se os três passam
   ANTES de disparar, ou o despacho falha e a recusa vira linha de auditoria sem convite.
2. **Qual caminho é o legítimo.** Ver se a UI de admin tem botão de reenvio que já orquestra
   token + e-mail; se tiver, use-o em vez de chamar a função interna à mão.

**O cenário melhorou desde ontem:** as quatro agendas estão abertas (GP 23 dias, institucional 19,
Fabricio 13, Fernando 13) e não há bloqueio de roteamento ativo. O rodízio LRD elegerá o Fabricio
(posição 1), e a linha nova já gravará `agenda_days_open`, que será a **primeira** linha com esse
dado (`despachos_com_estado_de_agenda` estava em 0).

## Segundo: o webinar de ontem não foi fechado

O painel da Tribo 11 ocorreu em 08/09 às 20h. Medido em 09/09:

```
status: planned          (não mudou)
youtube_url: null        (sem gravação)
event_id: null           (sem evento vinculado)
registros de presença: 0
```

O dono pediu: **levantar o que o fechamento exige neste projeto e mostrar a lista, sem alterar
nada.** Comece por `webinar_manage` no MCP e pelas RPCs de ciclo de vida
(`webinar_lifecycle_events`), e veja como os webinares anteriores foram fechados, em vez de supor.

## O que já está entregue e NÃO precisa refazer

- **`#2188` fase 1 mergeada e em produção.** A sonda roda (`probed=4 cegas=0`), o cron lê o segredo
  do Vault 4x ao dia, e o despacho grava `agenda_days_open`/`agenda_probed_at`.
- **Os dois segredos configurados e pareados** (Worker `AGENDA_PROBE_INTERNAL_SECRET` + Vault
  `agenda_probe_internal_secret`), conferidos por sha256 idêntico.
- **O import do VEP de ontem foi reprocessado**, resume `311824` recuperado, 0 falhos.

⚠️ **`/tmp/.ag_probe_secret` ficou na máquina** com o valor em claro. Apagar:
`shred -u /tmp/.ag_probe_secret`.

## Fases 2 e seguintes da #2188, quando houver espaço

O rodízio pular agenda comprovadamente vazia (item 1), o despacho falhar de forma visível quando
nenhuma agenda tem horário (item 2) e o alerta quando um avaliador ativo zera (item 4). Os três
leem o dado que a fase 1 começou a produzir, e **não devem ser escritos contra tabela vazia**:
agora ela tem linhas.

## Issues abertas ontem, todas da mesma família

`#2193` (a divulgação de webinar depende de alguém lembrar) · `#2197` (o ratchet do CodeQL corre
contra a análise que ele lê; a **A3** já resolveu essa classe para o deploy com `workflow_run`) ·
`#2199` (falha de sync de currículo sem leitor nem retry; 6 CVs de março perdidos sem recuperação).

Não consertado e sem issue: **`_trg_event_guest_cert_pdf_autogen` lê um GUC que não existe e não
pode ser criado** nesta plataforma, então o PDF de certificado de convidado de evento externo
(`#1098`) pula em silêncio. Registrado no cabeçalho da migration `20260908193328`.

## Prazos

- **10/09** Reunião Geral. Os **cinco pontos da pauta** seguem parados do lado do PM desde 04/09.
- **11/09** aprovação do TAP do Grupo de Estudos CPMAI (lane `.wt-cpmai`, parada desde 31/08).

## A regra que a sessão de ontem deixou

> **Ler a projeção não é ler a fonte.** Comentário de migration descreve; snapshot de
> acessibilidade deriva; tabela de fila registra um caminho entre vários. Exerça contra o catálogo,
> o DOM, a superfície onde o fato acontece.

E o corolário: **guarde a diferença entre "não sei" e "é zero"**. Uma coluna booleana impediu que
um seletor errado registrasse "quatro agendas fechadas" e esvaziasse o rodízio.
