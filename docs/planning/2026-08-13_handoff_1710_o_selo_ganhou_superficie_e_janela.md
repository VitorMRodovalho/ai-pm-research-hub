# Handoff — #1710: o selo saiu do papel, e agora tem data (13/08/2026)

> Sessão aberta pelo `2026-08-13_PROMPT_ARRANQUE_1710_SELO.md`. Quatro ondas, três mergeadas, a
> quarta em CI ao fechar este documento.

## Regra zero

Todo número aqui foi medido em **13/08/2026, 16h22 UTC**. Três deles se movem sozinhos e o mais
importante — o que a primeira execução do cron vai gravar — **muda todo dia até 24/08**. Re-medir na
mesma volta em que entrar numa decisão, num commit, numa issue ou numa pergunta ao PM.

## Estado

`main` em `cba13b43` mais a #1756 (onda D), **zero bypass** nas quatro PRs.

| medida | valor |
|---|---:|
| eventos passados / com `roster_sealed_at` | **510 / 0** |
| membros ativos no ciclo | **86** |
| faltas que o selo materializaria hoje | **111**, sobre **44** pessoas |
| dessas, já vencida a carência de 14 dias | **51**, em **12** eventos |
| linhas gravadas pelo selo até agora | **0** |
| cron | `attendance-seal-window-daily`, 11:40 UTC, **ativo**, no-op até **24/08** |

## O que foi entregue

### #1754 — escopo, reversão e superfície

- **`seal_event_attendance` gateava sem recurso.** Medido impersonando os 14 portadores de
  `manage_event`: **622 pares (líder, evento)** passavam pelo gate amplo e não pelo escopado. Cada um
  dos 12 líderes de tribo alcançava de 49 a 55 eventos de **outras tribos**. Enquanto ninguém podia
  clicar, não doía; dar tela ao ato sem trocar o gate seria publicar a porta. Mesma classe do #1728.
- **`unseal_event_attendance`** — a reversão por evento que o PM exigiu e que não existia. Apaga só
  as linhas do selo ainda intocadas e devolve `kept_touched_count`, porque quem foi marcado presente
  ou justificado depois **permanece**.
- **As três grades** (havia uma terceira, `get_initiative_attendance_grid`) passam a publicar
  `roster_sealed_at`. As três já **liam** o campo para decidir entre `unrecorded` e `absent`.
- Painel de selagem em `/attendance`, botão no quadro do evento que leva à **mesma** confirmação, e
  o cadeado na grade.

### #1755 — a tool MCP

`attendance_seal` (`list` / `seal` / `unseal`), tool **própria** e destrutiva. Sem `confirm=true`,
`seal`/`unseal` devolvem o ensaio daquele evento. `/semantic` em produção: **v0.13.0, 54 tools**.

### #1756 — o cron da janela (em CI)

Núcleo compartilhado (`_seal_event_attendance_apply`), ator **nulo** para o caminho automático com
carimbo `source=window_cron` no audit log, janela em `platform_settings['attendance.seal_window']`.

## Decisões do PM tomadas nesta sessão — NÃO re-litigar

1. **Onde a superfície mora:** painel de lote **mais** botão por evento (as duas consomem o mesmo
   `preview_seal_attendance`).
2. **A janela de 14 dias é carência POR EVENTO, com piso em 24/08.** Um evento é selado 14 dias
   depois de terminar, e nada sela antes de 24/08.

## Decisões de implementação que valem como precedente

- **O ator do selo automático é NULO.** Atribuí-lo a um GP registraria uma falsidade. Cron e suíte de
  teste compartilham a digital do `service_role`, então o que separa os dois é o carimbo `source`.
- **O job entra ativo; quem segura o gatilho é o `floor_date`**, que é dado. Uma flag `enabled`
  exigiria que alguém lembrasse de virá-la, sem tela — o defeito que a issue existe para consertar.
- **O ensaio não fala a língua do ato**: `events_would_seal` / `absences_would_write` no dry-run,
  `events_sealed` / `absences_written` só no ato.

## Armadilhas pagas, com o preço

1. **`CREATE FUNCTION` concede EXECUTE a PUBLIC por padrão.** `unseal_event_attendance` — SECURITY
   DEFINER, que **apaga** linhas — nasceu alcançável por `anon`. O portão interno recusava, então não
   houve exposição de dado; o que se corrigiu foi a superfície. Classe do #1592.
2. **Varrer por palpite não substitui rodar a suíte.** O `/semantic` tem **quatro** contadores
   pinados em arquivos que não se conhecem, e um deles pina também a versão. Procurei por `53` em
   dois arquivos, achei dois, e conclui que eram todos: o terceiro custou um CI vermelho (#1755) e o
   quarto só apareceu na suíte completa.
   **O antídoto é barato:** `env -u SUPABASE_URL -u SUPABASE_SERVICE_ROLE_KEY npm run test:contracts`
   roda em ~52s, pula os 665 testes DB-gated, não disputa o banco compartilhado (#1505) e mostra
   todo gate estático.
3. **Um vermelho pode ser da contagem, não do código.** O guard do #1377 acusou
   `list_webinar_proposals` caindo do teto de 256 tools do `/mcp`; era artefato de a tool nova faltar
   em `SEMANTIC_ONLY`. A remediação que a mensagem do teste sugere teria tratado o sintoma.
4. **Regenerar artefato congelado absorve dívida alheia.** `MCP_TOOL_MATRIX.md` estava em 29/07 e não
   tinha o `agenda_blocks` do #1548: 394 → 396 são **duas** tools, não uma.

## O que continua aberto

- **O último item do escopo da #1710:** "contagem de eventos selados publicada depois de uma semana".
  Só faz sentido depois de o cron rodar uma vez, ou seja **a partir de 31/08**.
- **A #1726 segue aberta** e só fecha quando o selo tiver rodado — o envio foi feito, a janela é que
  ainda corre.
- ⚠️ **Antes de 24/08, re-medir o que a primeira execução vai gravar.** Hoje são 51 faltas em 12
  eventos; o número cresce conforme reuniões vencem a carência e encolhe conforme líderes registram
  presença, que é exatamente o que a janela existe para permitir. Rodar
  `SELECT public.seal_attendance_window_cron(true);` como `service_role` dá o ensaio pela mesma
  função que executa — mas note que **antes do piso ele devolve `skipped: before_floor`** e não
  varre nada. Para ensaiar de verdade antes da data, recuar o `floor_date` **dentro de uma transação
  abortada**, como foi feito na prova desta sessão.
- **A #1656 e a #1655** seguem abertas e cruzam com este item: se o `rate` passar a contar só evento
  selado, a #1710 vira pré-requisito delas.

## Para a próxima sessão

Se a #1756 estiver mergeada: o tema natural é a **onda C do #1590** (superfície de roteamento), que
era a ordem decidida pelo PM em 13/08 para depois do #1710. Dentro dela, a **superfície do comitê vem
antes do painel de roteamento**, porque o comitê é a regra de segurança de acesso da tela de seleção.

Se não estiver: ler o CI da #1756 antes de qualquer coisa.
