# Handoff 11/09/2026 — a Reunião Geral de 10/09 fechada, e o portão de XP que ninguém vê

> Carimbado em 11/09 ~04:30 UTC. Números medidos nesta sessão; **re-meça antes de decidir**.

## O que foi feito (tudo verificado por leitura, não por retorno de escrita)

### Reunião Geral de 10/09 (evento `8c3fa194-0ed6-45c3-a109-d3ffcca3b18a`)

- **4 blocos de protagonismo confirmados**, com XP creditado aos quatro:
  Ramom 21 · Hanae 27 · Messias 23 · Fernando 12.
- **Presença**: +2 linhas (Hanae e Fernando, que apresentaram e não estavam registrados).
  Total agora 32. **Ainda muito abaixo** da lista de convidados (~76).
- **10 ações registradas** em `meeting_action_items` (antes: zero), com responsável e prazo.
  Prazos vivos: **13/09** divulgar vagas · **16/09** pesquisa de cultura · **30/09** entrevistas do Fernando.

### O ACHADO da sessão: o portão de XP depende da presença

`confirm_event_blocks` confirma o bloco **sempre**, mas só credita XP se o dono tiver linha em
`attendance` com `present = true`:

```sql
v_present := EXISTS (SELECT 1 FROM attendance
  WHERE event_id = ... AND member_id = owner_member_id AND present = true);
...
IF v_present THEN PERFORM _grant_agenda_block_xp(v_block.id); END IF;
```

Resultado medido: `confirmed: 4, credited: 2`. Hanae e Fernando apresentaram, foram confirmados e
**não receberam nada**, porque não tinham linha de presença. O único sinal disso é a diferença entre
dois números no envelope, que ninguém lê.

**Pior: não há caminho de volta pelo produto.** O laço do `confirm` percorre só `status='reserved'`,
então re-rodar não alcança bloco já confirmado. O conserto exigiu registrar a presença e chamar
`_grant_agenda_block_xp(block_id)` direto (ela é idempotente e **não** checa presença; o portão está
só no chamador).

**A ordem certa é: registrar presença ANTES de confirmar blocos.** Eu inverti e por isso precisei
consertar. **Registrado na #2229**, com a reprodução medida e quatro propostas, inclusive a pergunta
de fundo: se presença deve mesmo ser pré-requisito de reconhecimento, já que quem apresentou esteve
na reunião por definição.

### Onde a gravação mora, e o que ela já traz de graça

`~/gdrive/pessoal/Google Meet/Reunião Geral - Núcleo IA (quinzenal) (recurring)/`
com três arquivos de 10/09: **Recording** (841 MB, 1h54m24s, 1280x720), **Chat**, e
**Notes by Gemini** (resumo + 10 próximas etapas + detalhes com carimbo de tempo).

⚠️ O Notes by Gemini **lê 0 bytes pelo mount** (doc nativo do Google). Use
`rclone cat "gdrive:<caminho>"`. O `.mp4` lê normalmente pelo mount.

✅ **A gravação traz faixa de legenda embutida** (`mov_text`, 1555 cues em pt), que é a transcrição
do próprio Meet. Extrair com `ffmpeg -map 0:s:0` dispensa retranscrever. Tem artefato `()` por cue
(marcador de falante vazio) a limpar. A faixa termina em **01:44:24** e o arquivo vai até 01:54:24.

## A régua real da reunião (por que a pauta institucional não aconteceu)

| trecho | reservado | real |
|---|---|---|
| governança de dados em pequenas empresas (**não reservado**) | — | **~34 min** |
| Hanae · pesquisa Tribo 4 | 10 | ~8 min |
| Messias · TEDx, crise do testemunho ocular | 15 | ~11 min |
| Ramom · LGPD e ANPD | 30 | **~41 min** |
| Fernando · onboarding | 20 | **~2 a 5 min** |

Os 34 minutos iniciais não reservados comeram o espaço institucional. **Nada foi anunciado**:
webinar da Tribo 11, acervo trilíngue, cooperação LATAM, o RCE crítico. O prazo de 13/09 sobreviveu
só porque virou ação.

XP é calculado pela duração **reservada**, não pela real. Decisão do dono: confirmar os quatro como
estavam.

## Dois sinais de governança que só aparecem lendo o chat

- **Dois gravadores de terceiros na sala**: Tactiq (Marcela) e Fireflies (em nome do Honório), numa
  reunião cujo tema central foi proteção de dados. Merece decisão do Núcleo.
- **Ana Carla relatou áudio falhando às 01:33** e já havia dito no grupo que está sempre no trânsito
  no horário da call. Duas barreiras somadas na líder de Inclusão.

## Pendente

- **Publicar a gravação**: separado de propósito para uma **sessão limpa**, porque desdobra em corte,
  normalização, legenda em três idiomas, tradução, upload, miniatura, vínculo e fechamento.
  **Tudo já medido e persistido** em `~/projects/_pmo/youtube/geral-2026-09-10/`, com `LEIA-ME.md`
  que dá os números prontos: corte em ~6270 s (9min57s de silêncio no fim, offset ZERO no início),
  áudio `-18,78 LUFS / +0,59 dBFS` (quarto perfil diferente em quatro gravações), a faixa de legenda
  do Meet com 1555 cues, e a régua da reunião para os capítulos.
- **Vincular a gravação ao evento** e fechar a reunião (`meeting_minutes action='close'`).
- **A lacuna de presença**: 32 de ~76. A lista de convidados está no Notes by Gemini.
- **Desambiguar a enquete de MCP**: uma pessoa relatou não conseguir acessar. Não existe tabela de
  enquete no schema (medido), então é externa — **a menos que** o que ela não acessou fosse o MCP,
  que aí é a #2181.

## Estado das outras frentes

- **#2208 fase 1 CONCLUÍDA**: 9 vídeos trilíngues, 27 faixas, conferidas em 10/09 às 03:30 pelo cron.
  Fases 2-4 abertas. Artefatos em `~/projects/_pmo/youtube/fase1-2208/`.
- **#2207** aberta (modelagem de audiência de evento, + plataforma e idioma).
- **PR #2223** aberta: skill `youtube-publicacao`.
- **11/09 (hoje): aprovação do TAP do CPMAI.** Lane `.wt-cpmai` parada desde 31/08, sem PR.

## A regra da sessão

> **Confirmar não é creditar, e o envelope só conta a diferença uma vez.**

Quando uma operação faz duas coisas e só uma delas tem portão, o sucesso parcial sai com cara de
sucesso. `confirmed: 4, credited: 2` é a única evidência de que duas pessoas ficaram sem
reconhecimento. Leia os dois números, não o `ok: true`.
