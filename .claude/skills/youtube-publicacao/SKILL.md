---
name: youtube-publicacao
description: Padrão de publicação no canal do YouTube do Núcleo — corte, normalização de áudio, transcrição local e legenda TRILÍNGUE (pt-BR, es-LATAM, en-US), metadados, capítulos e miniatura. Use ao publicar qualquer gravação (webinar, reunião geral, mesa redonda, vídeo de tribo) e ao fazer backfill do acervo. Cobre também a cota da API, que é o gargalo real.
user_invocable: true
---

Padrão de publicação do canal `UCIEiHte8f_AVwCXP2wZ7DjQ` (Núcleo de Estudos e Pesquisa em IA e GP).

Ferramentas em `~/projects/_pmo/youtube/`: `upload.py`, `set_thumbnail.py`, `list_uploads.py`,
`clean_vtt.py`. Tokens: `token.json` (upload) e `token_captions.json` (legendas, escopo
`youtube.force-ssl`). Transcrição local: `~/.venvs/video/bin/whisperx`.

## Por que trilíngue é padrão, e não extra

Acordo de cooperação em conversa com PMO GA LATAM e capítulos da Argentina e do Caribe (registrado
em 09/09/2026). A audiência hispanofalante é compromisso, não hipótese. E o replay é onde o
multilíngue custa quase nada: a transcrição local já é produzida, e as faixas es/en saem dela.

Ver `#2207` para a modelagem de audiência e a pesquisa de plataforma.

## Ordem obrigatória

A ordem não é preferência. Cada passo consome a saída do anterior.

### 1. Cortar ANTES de qualquer carimbo

Cortar depois invalida todo carimbo já publicado (capítulos, ata, action items).

```bash
# tempo morto: silencedetect. Rodar TAMBÉM num limiar mais permissivo como controle,
# senão ruído de sala mascara pausa e você conclui "não há o que cortar" sem base.
ffmpeg -v info -nostats -i audio.wav -af silencedetect=noise=-40dB:d=2 -f null - 2>&1 | grep silence_
ffmpeg -v info -nostats -i audio.wav -af silencedetect=noise=-30dB:d=2 -f null - 2>&1 | grep silence_
# cortar em KEYFRAME permite -c:v copy (sem perda de geração, minutos em vez de horas)
ffprobe -v error -select_streams v:0 -skip_frame nokey -show_entries frame=pts_time \
        -of csv=p=0 -read_intervals 160%200 origem.mp4
```

**Guardar o offset** (`tempo_no_corte = tempo_original - <corte>`) num `CORTE.md` ao lado do master.
Sem ele, ninguém reancora nada depois.

### 2. Áudio: MEDIR, nunca recitar

O defeito muda por gravação. Três casos medidos no mesmo canal: Airmeet T6 (04/08) a −24 LUFS sem
problema de pico; Liderança 06/08 a −15,5 LUFS **com** pico em +0,9 dBFS; webinar 08/09 a −21,68
LUFS **e** pico em +0,04. Recitar a cadeia do caso anterior produz o conserto errado.

```bash
ffmpeg -v info -nostats -i audio.wav -af ebur128=peak=true -f null -   # Integrated, LRA, True peak
ffmpeg -v info -nostats -i audio.wav -af loudnorm=I=-14:TP=-1.5:LRA=11:print_format=json -f null -
```

Duas passadas com os valores medidos. Alvo: **I −14 LUFS, TP ≤ −1 dBTP**. O `loudnorm` enxerga pico
intersample que o `ebur128` perde: decidir pelo número dele. Aplicar `afftdn` **só** se medir ruído.

**Re-medir o arquivo final.** Confirmação de comando não prova pós-condição. E a codificação AAC
reintroduz pico: se o alvo é estrito, usar `TP=-2`.

### 3. Transcrever LOCAL, em português

Nunca usar a transcrição da plataforma de evento sem olhar. A do Airmeet de 08/09 rodou ASR em
inglês sobre áudio em português e saiu inutilizável ("Wow. Rodrigo to the bone.").

```bash
~/.venvs/video/bin/whisperx audio.wav --language pt --model large-v3 \
  --device cuda --compute_type float16 --batch_size 8 --output_format all --output_dir tx
```

### 4. Traduzir LOCAL para es-LATAM e en-US

Sem chave de API e sem mandar gravação a terceiro: `~/.venvs/video` tem `ctranslate2` e
`transformers`. Revisar termo técnico de gerenciamento de projetos: é onde tradução automática
erra e o erro é institucionalmente caro diante de capítulo parceiro.

### 5. DESLOCAR as legendas antes de subir

**A armadilha que mais custa.** O VTT nasce no tempo do ORIGINAL; o vídeo publicado está cortado.
Subir cru deixa a legenda inteira fora de sincronia, e o defeito só aparece para quem assiste.

Subtrair o offset de cada cue, descartar o que termina antes de zero, aparar o que atravessa.
**Verificação cruzada de graça:** conferir 3 a 5 capítulos da descrição contra o texto da legenda
naquele instante. Se baterem, e os dois vierem de caminhos independentes, o offset está certo.

### 6. Subir vídeo, depois metadados, depois legendas, depois miniatura

```bash
~/.venvs/youtube/bin/python upload.py --video X.mp4 --meta meta.json
~/.venvs/youtube/bin/python set_thumbnail.py --video-id <ID> --image thumb.jpg
```

Legenda via `captions().insert` com `token_captions.json`, uma faixa por idioma,
`name:""` e `isDraft:false`.

## Regras de metadado

- **Título:** prefixo `YYYY-MM-DD - `, data do EVENTO e não do upload. Teto de 100 caracteres.
- **Enquadramento institucional, sempre:** "Núcleo IA & GP, iniciativa dos capítulos do PMI no
  Brasil, sediada no PMI-GO". **Nunca** "o Núcleo e os capítulos do PMI", que os põe como
  co-realizadores separados. Não reivindicar evento oficial do PMI nem PDU.
- **`defaultAudioLanguage`:** declarar corretamente. Auditoria de 09/09/2026 encontrou 53 vídeos
  marcados `pt-PT` e 30 `en-US` num canal brasileiro. O idioma declarado orienta ASR, busca e
  tradução automática do YouTube: errado ali, tudo a jusante degrada.
- **Capítulos** na descrição, nos tempos do vídeo CORTADO. 55 dos 67 vídeos longos não têm.
- **Playlist** resolvida pelo SSOT `src/data/youtube-playlists.ts`, nunca id chumbado.
- **Miniatura:** não reaproveitar o banner do evento. O texto dele é convite no futuro ("dia 4,
  19h"), errado para replay. Gerar variante com o design-kit.

## Subir como não listado e virar público depois

Subir `unlisted` quando o TEXTO (título, descrição, capítulos) ainda não foi aprovado. Liberação
para subir não é aprovação do texto.

Ao virar público: **`videos.update` SUBSTITUI a parte enviada**. Ler o objeto `status` inteiro,
mudar só `privacyStatus`, devolver o resto igual, e conferir campo a campo depois. Mandar só
`privacyStatus` reseta `license`, `embeddable`, `publicStatsViewable` e os de conteúdo infantil,
em silêncio. Mesma família do `upsert_webinar` sem `COALESCE` (#1604).

Para provar que ficou público, **não** usar oembed: ele responde para não listado também. Usar o
feed RSS do canal (`videos.xml?channel_id=...`), que só lista público.

## Cota da API é o gargalo, planeje por ela

| operação | unidades |
|---|---|
| `captions.insert` | **400** |
| `videos.update` | 50 |
| `videos.list` / `playlistItems.list` | 1 |

Teto padrão: **10.000 unidades/dia**, ou seja **25 legendas por dia**. Trilíngue num vídeo custa
1.200 unidades. Backfill do acervo é batch de vários dias, não de uma sessão: dividir por leva,
começar pelos públicos e longos, e registrar o que já foi para não repetir e queimar cota.

## Ao terminar

Atualizar a linha do vídeo no acervo e, se for gravação de evento da plataforma, seguir o
fechamento do evento (ver `#2205` e `#2207`). Escrita em banco é da sessão main.
