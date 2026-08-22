# Arranque: lane de vídeo - reunião de liderança + shorts do ciclo

> Tudo abaixo foi medido ao vivo em **21/08/2026** (horários em UTC). **Re-medir antes de agir**:
> número recitado de handoff não vale como medição.
> Repositório PÚBLICO: sem nome de pessoa, sem identificador de candidato, em issue, PR ou commit.

---

## 0. REGRA DA LANE, acima de tudo o resto

**Toda escrita passa pelo MCP do Núcleo, não por SQL.**

Isto não é preferência de estilo, é o método de trabalho desta lane. Escrever por `execute_sql`
funciona e não ensina nada. Escrever pela porta semântica faz três coisas de uma vez:

1. **Exercita a rota** e revela rota quebrada, ausente ou com envelope mentiroso. Já aconteceu:
   `update_checklist_item` (9 de 9 falhas), `delete_checklist_item` (4 de 4) e
   `get_selection_health` (3 de 3 com erro de SQL vivo) só apareceram porque alguém tentou usar.
2. **Preserva as garantias** que a RPC canônica aplica e o SQL direto pula: auditoria, vínculo,
   janela de autoridade, cache de papel. O caminho em lote já contornou as quatro (#1834), e um
   `UPDATE` direto contornou de novo em 17/08, com pavio de 27 horas (#1850).
3. **Não suja a base.** Um `UPDATE` sem gate escreve onde a tabela barraria.

**Se a rota do MCP não existir ou falhar:** PARE, registre o achado (ferramenta, argumentos,
envelope recebido) e traga para o PM. **Não caia para SQL como contorno** sem decisão explícita.
A falta da rota é o produto desta lane tanto quanto o vídeo publicado.

⚠️ **Envelope de sucesso não prova gravação.** Já medimos RPC que devolve `application_status` que
não gravou, e outra que devolve `{"error": ...}` com HTTP 200. Depois de cada escrita, **confirme o
estado por leitura**, não pela resposta.

---

## 1. Bloco A: Reunião de Liderança #10 (20/08)

Estado medido em 21/08:

| campo | valor |
|---|---|
| `id` | `f77a91d2-5211-4ed8-b197-5616d8e7d692` |
| título | Reunião de Liderança #10 |
| data / hora | 2026-08-20, 19:00 |
| `status` | **`scheduled`** (não foi marcada como realizada) |
| `is_recorded` | `true` |
| `youtube_url` | **nulo** |
| `recording_url` | **nulo** |
| `minutes_text` | **nulo** |
| `minutes_posted_at` | **nulo** |

### O que fazer

1. **Localizar a gravação.** Ela vem do Meet, via Drive. Dois detalhes que já custaram tempo:
   a gravação do Meet chega **sem extensão** no nome (filtre por MIME, não por `.mp4`), e pastas do
   Drive podem ter **barra fullwidth `／`** no nome. Doc nativo do Google lê **0 bytes** pelo mount:
   use `rclone cat` ou `drive-docs-pull.sh`.
2. **Tratar e subir o vídeo**, seguindo o padrão do que já está publicado (ver Bloco C para os
   exemplos completos).
3. **Registrar no evento** o `youtube_url` e o `recording_url` **pela porta MCP**.
4. **Ata (`meeting_minutes`)**: redigir e publicar.
5. **Ações capturadas (`meeting_actions`)**: cada ação vira item rastreável, **com responsável e
   com prazo**. 📌 Na geral de 13/08 ficaram **10 ações sem prazo**, e não repita: ação sem prazo não
   é acompanhável, e some do radar.
6. **Fechar o evento**: o `status` ainda é `scheduled`. Enquanto não refletir a realidade, todo
   relatório que conta reunião realizada erra.

⚠️ **Evento futuro não prova reunião, e evento passado não prova realização.** Meça **presença**
antes de afirmar que aconteceu.

---

## 2. Bloco B: sequência de shorts

Motivo: o Núcleo está **sem shorts agendados** nas redes.

Material do Ciclo 4 (início 2026-07-09), medido:

| data | tipo | título | YouTube | gravação | ata | duração real |
|---|---|---|---|---|---|---|
| 09/07 | geral | Kick-off Ciclo 4 (2026/2) | ✅ | ✅ | ✅ | 60 min |
| 16/07 | geral | Reunião Geral | (n/a) | (n/a) | (n/a) | **CANCELADA** |
| 16/07 | geral | Aftershow (AI Community Day) | ✅ | ❌ | ❌ | 60 min |
| 30/07 | geral | Reunião Geral | ✅ | ✅ | ✅ | 93 min |
| 04/08 | **webinar** | ROI & Portfólio · 1º Webinar | ✅ | ✅ | ✅ | 73 min |
| 13/08 | geral | Reunião Geral | ✅ | ✅ | ✅ | 60 min |

**As "duas primeiras gerais" do ciclo são 09/07 e 30/07**, porque a de 16/07 foi cancelada e o Aftershow
é evento à parte, além de não ter `recording_url` (só YouTube), o que muda o caminho de extração.

**Webinar do ciclo: um só**, o de 04/08. Se a expectativa era "webinares" no plural, isso precisa
ser confirmado com o PM antes de planejar volume.

### O que fazer

1. Confirmar com o PM o **recorte** (quais peças entram) e a **quantidade** de shorts.
2. Extrair os cortes. Há capacidade instalada no ambiente para isso, e **procure antes de dizer que
   não dá**: `hyperframes` e as skills de vídeo (`talking-head-recut`, `embedded-captions`,
   `branded-video`), transcrição **local** por `lecture-transcribe` (WhisperX/whisper.cpp, nada sai
   da máquina).
3. **Agendar a publicação pela porta MCP** (`comms_post` e a família de comunicação), não por SQL.
   O cron `publish-scheduled-social` roda `*/15` e é ele que despacha.
4. Registrar o que foi agendado onde o acompanhamento vive, para não virar trabalho invisível.

---

## 3. Bloco C: padrões a copiar, não reinventar

A geral de **13/08** (`ed3a4c5a-553d-41c7-b01b-40e4145e85e9`) está **completa**: YouTube, gravação,
ata publicada. É o modelo de "pronto" para o Bloco A.

O handoff dela está em `docs/planning/2026-08-17_handoff_reuniao_geral_13ago_publicada.md`, com o
que deu certo e o que ficou aberto (`roster_sealed_at` nulo, os **45 presentes são PISO**, e as 10
ações sem prazo).

---

## 4. Armadilhas medidas, que custam tempo real

- **CI**: escalone os pushes. Duas branches atualizadas no mesmo segundo derrubam as duas na faixa
  do banco (#1509). E `cancel-in-progress: false` faz push durante run criar um segundo run
  `pending` que não despacha, então cancele o obsoleto.
- **Árvore de trabalho é COMPARTILHADA entre sessões.** Em 20/08 um `checkout` de outra sessão
  passou por cima de edição em andamento; salvou-se por auto-stash. **Trabalhe no worktree desta
  lane** e não troque a branch da árvore principal.
- **DDL no banco compartilhado serializa TODAS as PRs.** Se esta lane precisar de migration, o
  `.sql` local tem que subir junto, senão os guards `Track Q-C`, `Phase C` e `ADR-0097` ficam
  vermelhos para todo mundo. Aconteceu 5 vezes em 20-21/08.
- **`npm test` local**: o reporter do Node 24 é `spec` (`✔`/`✖`/`ℹ`), não TAP. Filtro que procura
  `not ok` volta VAZIO mesmo com falha. Use:
  `npm test 2>&1 | grep -E '^[[:space:]]*(not ok|✖)|^(#|ℹ) (fail|pass|tests|skipped)'`
  e **carregue o `.env`** (`set -a; . ./.env; set +a`), senão os testes DB-aware pulam em silêncio:
  medimos **744 skipped** contra 1 na CI.

---

## 5. Estado da fila (contexto, não tarefa)

`main` em `fe268cf2`. A fila está **travada** por uma linha de `gate_attempts` de 21/08 14:18:47 que
reprova 2 testes da família #1636 em qualquer branch. **Não é desta lane** e não bloqueia o trabalho
de vídeo, mas bloqueia o merge. Planeje entregar em PR e não conte com merge imediato.
