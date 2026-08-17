# Handoff — a reunião geral de 13/08 fechada: ata, presença, protagonistas, ações e vídeo

> Sessão de 16/08/2026, noite (madrugada de 17/08 UTC). Anterior:
> `2026-08-16_handoff_1822_dominio_nao_declarado.md`.
> Arranque que a originou: `2026-08-17_PROMPT_ARRANQUE_REUNIAO_13AGO_1710_E_905.md` (ITEM 1).
>
> ⚠️ **Repo público.** Este documento conta população, nunca pessoa. Os nomes vivem na plataforma
> (ata, presença, champions) e no material git-ignored de `_drive-docs/`.

---

## O que entrou

O ITEM 1 do arranque fechou inteiro, pela porta do MCP em todos os writes que têm porta.

| entrega | antes | depois |
|---|---|---|
| `minutes_text` | 0 chars | **22.081** (a de 30/07, que é a forma-alvo, tem 14.473) |
| ações rastreáveis | 0 | **10** (7 com responsável, **0 com prazo**) |
| presenças | 31 presentes / 34 linhas | **45 presentes / 48 linhas** |
| champions ativos | 0 | **3**, com métrica dentro da `justification` |
| `suggested_champion_ids` | 0 | **5** (todos os que passaram no gate) |
| `recording_type` | nulo | `youtube` |
| `recording_url` / `youtube_url` | nulos | o vídeo publicado, ambos |

`roster_sealed_at` segue **nulo de propósito** nas duas gerais. Nada foi selado.

Estado de partida conferido no início: **43 invariantes, zero violações**; `main` em `a5793a35`;
zero PRs abertas. Nada de schema mudou nesta sessão.

## O buraco da presença, resolvido por prova e não por estimativa

O arranque trazia "31 presentes contra 51 em 30/07" como queda de público. **Não era.**

A medição mostrou que **as 34 linhas de 13/08 tinham `registered_by` nulo — 100% auto-check-in.**
Em 30/07, 52 das 54 também eram. Comparação justa, então: 51 auto contra 31 auto.

O cruzamento contra as fontes documentais (transcrição, log do chat e a chamada nominal do
encerramento) achou **14 membros com prova citável de participação e zero linha de presença**, entre
eles quem conduziu a reunião. Registrados os 14 com `attendance_record`, o que grava `registered_by`
e mantém a distinção entre auto-check-in e cobertura de líder. **31 + 14 = 45.**

📌 **45 é PISO, não total.** Quem assistiu calado não deixa rastro em transcrição nem em chat. E não
existe Meeting Report do Google para 13/08 contra o que reconciliar (a pasta para em 09/07 e guarda
analytics de YouTube, não lista de presença).

⚖️ **Decisão do PM (16/08):** registrar os 14 com prova documental. A governança declarada na própria
ata de 30/07 já previa: a marcação é do participante, e "o líder de tribo pode cobrir o registro
depois". Foi exatamente isso.

## Protagonistas: o teto transformou ordem de chamada em critério

`award_champion` tem **teto anti-inflação no corpo da função**: `general` 3, `tribe` 2,
`deliverable` 1, mais 3 por concedente por evento. Concedi na ordem em que pensei nos nomes, e os
dois últimos voltaram `per_event_cap_reached`.

**Medido depois, quem entrou em 3º era o 5º colocado em todos os eixos, e o 1º em volume ficou de
fora.** O acaso da chamada virou a seleção.

O PM mandou metrificar. Nasceu o skill **`champion-metrics`** (`.claude/skills/champion-metrics/`,
SKILL.md + 2 scripts), que lê a transcrição carimbada e aplica:

- **Gate eliminatório:** ocupou bloco de pauta com entrega própria. Só debater não qualifica.
- **Eixo A** palavras dentro do próprio bloco (40%) · **B** pessoas distintas que intervieram no
  bloco (35%) · **C** palavras fora do próprio bloco (25%). Normalizados pelo maior do grupo.
- **`span` NÃO é eixo, de propósito:** quem apresenta por último tem span curto por posição de
  agenda, então o eixo mediria a agenda e não a pessoa.
- **Robustez publicada junto:** o conjunto do top-3 se manteve em **12 de 12** combinações de peso.
  Conjunto que só vale num peso é artefato do peso.

Base medida: **26 falantes, 429 turnos, 13.832 palavras, 5 candidatos passaram no gate.**
Resultado aplicado: 1 revogação (com a métrica na razão), 1 concessão nova, e a métrica anexada em
bloco entre colchetes na `justification` dos três.

🔎 **`champions_awarded` não tem coluna de comentário.** Os campos são `criteria_met`,
`justification`, `points_awarded`, `status` e os de revogação. A anotação só cabe em `justification`.
`events.suggested_champion_ids` **não tem teto**, e é por isso que a forma de 5 de 30/07 existia:
30/07 sugeriu 5 e não premiou ninguém (zero linhas em `champions_awarded`). **13/08 é o primeiro
prêmio formal da série.**

## O vídeo, e o erro que ele custou

Publicado com 37 capítulos, todos ancorados em carimbo real da transcrição (71 disponíveis), título
90/100 chars, descrição 3.457/5.000, 16 tags, na playlist de reuniões gerais do ciclo resolvida pelo
SSOT `src/data/youtube-playlists.ts` por chave semântica.

🔴 **A primeira publicação saiu errada e ficou pública por ~3 minutos.** A gravação do Meet não para
no encerramento da pauta: seguiu por **69,5 s** dentro do **bloco reservado aos líderes**, com chamada
nominal de quem ficou. O PM pegou. Sequência de correção: privar imediatamente, achar o corte,
cortar, republicar, apagar o antigo, remover o `playlistItem` órfão.

**O corte não sai da transcrição** (os blocos do Gemini são grossos e a virada caía no meio de um).
Sai da **faixa `mov_text` embutida no MP4**: `ffmpeg -map 0:s:0 -c:s srt` dá timing por legenda e o
segundo exato. Corte com `-t <fim> -map 0 -c copy`, sem reencode, e **prova por grep** dos marcadores
do bloco restrito no SRT do cortado, esperando zero. Deu zero em 4 de 4 marcadores; 1438 → 1421
blocos de legenda.

⚠️ **YouTube não substitui arquivo.** Corrigir é sempre novo vídeo. E a API mente por propagação:
`videos.list` já devolve 0 enquanto `playlistItems.list` ainda mostra o item. **Reconfira.**

## A capacidade estava fora do repo, e eu disse que não existia

Declarei que não tinha credencial de publicação e ofereci passar o upload ao PM. Errado, e é
reincidência do mesmo eixo do incidente de 25/07 com o Drive.

O ferramental existe em **`~/projects/_pmo/youtube/`**: `upload.py` (Data API v3), `token.json` OAuth
vivo, venv `~/.venvs/youtube`, e a pasta do precedente de 30/07 com `meta.json` e log. O ponteiro
está **no header de um script deste repo** (`scripts/refresh-youtube-playlists.mjs`).

📌 Varrer `supabase/functions/` não basta. Varra `scripts/` pelo domínio e siga os ponteiros para
`~/projects/_pmo/`.

## Rastreado

- **#1826 aberta** (`type:feature`, `priority:low`, `mcp-server`, `meeting-notes`): tornar o critério
  de seleção um **dado** (hoje mora como texto dentro de `justification`, porque `champions_awarded`
  não tem coluna de comentário) e abrir a **rota de decisão** no MCP, já que `champion_award` cobre o
  ato (`award`/`revoke`) e não a decisão. Três fases: A guardar métrica estruturada, B porta MCP de
  ranking com o teto exposto e derivado do corpo da RPC, C ingestão da transcrição. Conversa com o
  **EPIC #1780**, com a diferença de que aqui a porta que **muda estado** existe e a que **informa a
  decisão** falta, que é a ordem mais perigosa das duas.
- **LL registrada no intake #588** (6 lições + 3 notas de método). As de maior alcance: teto de API
  transforma ordem de chamada em critério; métrica em campo de prosa não é dado; publicar gravação
  exige conferir o FIM e não a duração; ranking sem teste de robustez é opinião com número; eixo de
  métrica que muda ao embaralhar o processo mede o processo; e a reincidência de "a capacidade pode
  estar fora do repo", que agora inclui `~/projects/_pmo/`.

## Aberto, para a próxima

- **O skill `champion-metrics` está NÃO RASTREADO** (`.claude/skills/champion-metrics/`), junto com
  este handoff. Nada foi commitado nesta sessão: **zero commits, zero PRs, zero `--admin`, nenhuma
  migration.** Abrir a PR é decisão do PM. ⚠️ Nunca `git add -A` neste repo.
- **As 10 ações estão sem prazo** porque a reunião não declarou nenhum. Definir os prazos é do PM.
- **`roster_sealed_at` continua nulo.** Não selar sem decidir o que fazer com o piso de 45.
- **A varredura `data-retention-sweep-daily` estreia às 04:25 UTC de 17/08** e ainda não tinha rodado
  quando esta sessão fechou (era 01:30 UTC no arranque). Conferir: `get_lgpd_cron_health` impersonado
  sai de `never_ran:true`, e `admin_audit_log` ganha linha `action='data_retention.sweep'` com
  `affected_total = 0`. Falha só pinta o painel de vermelho depois de 2 dias.
- Os demais itens do arranque seguem intactos: **#1710 re-medir em 23/08** (prazo 24/08), portão legal
  **R1–R5 do SPEC #905** (30/09), triagem das **56** do #1822, os **238 pares** do #1805/#1809,
  **#1814** sem urgência, e o resto do **EPIC #1780**.
