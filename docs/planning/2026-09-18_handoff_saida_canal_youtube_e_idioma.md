# Handoff de saída 18/09 (2): o campo vazio decidiu por nós, e o canal não cresce pelo motivo que eu achava

> **Nada aqui é medição viva.** Carimbado em 18/09 ~17h40 UTC, antes de um reboot da máquina.
> **Re-meça antes de decidir.** Repositório público: este documento não nomeia terceiros.

**Estado ao encerrar:** `main f4e7d2d5` · **1 PR aberta** (#2367) · Liderança #12 **publicada** como
não listada (`JodNJgeltgw`), com legendas e playlist confirmadas.

---

## 1. A Liderança #12 ESTÁ NO AR (não listada)

**Concluído antes do reboot.** `https://youtu.be/JodNJgeltgw`

Pós-condição relida do YouTube campo a campo, não aceita pelo retorno da chamada: título,
descrição (3.546 chars), 15 tags, `categoryId=27`, `privacyStatus=unlisted`,
`defaultAudioLanguage=pt-BR`, `defaultLanguage=pt-BR`, `madeForKids=false` — **todos batem** com o
`meta.json` aprovado. **43 capítulos** na descrição. Playlist `PLfWCBF5VAWZM` passou de 3 para
**4 itens** e contém o vídeo.

**Três faixas de legenda** (pt, es, en) inseridas e conferidas: `draft=False`, `status=serving`.

Nada pendente neste item. `duration` lia `P0D` no carimbo porque o YouTube ainda processava; não é
defeito.

**Limpeza não feita, de propósito:** `~/projects/_pmo/youtube/lideranca-17set/` tem **13 GB**
(3 wavs + 4 mp4s). Apagar é irreversível e o dono não autorizou. Para limpar, manter `origem.mp4`,
`final3.mp4`, `meta.json`, `tx/` e `legendas/`, e remover `audio_master.wav`, `audio_norm*.wav`,
`audio16k.wav`, `final.mp4`, `final2.mp4`, `final4.mp4`.

## 2. O canal: 53 vídeos com idioma errado, corrigidos

Medido em 18/09 nos **93 públicos** (118 únicos no total): idioma são **dois** campos, e o defeito
estava nos dois de formas diferentes.

| população | `defaultAudioLanguage` | `defaultLanguage` | n |
|---|---|---|---|
| Shorts | **AUSENTE** | pt-PT | 37 |
| Shorts | pt-PT | pt-PT | 1 |
| Longos | pt-BR (ok) | **pt-PT** | 15 |

**Campo vazio não é neutro: o YouTube preencheu `pt-PT` sozinho num canal brasileiro.** Todos
corrigidos para `pt-BR`, com backup, piloto de 1 antes do lote e conferência campo a campo: **0
divergências** em título e tags, **191 tags** preservadas nos longos. Nos longos também foi preciso
mover a chave de `localizations` (`pt-PT` → `pt-BR`), senão a localização órfã mantém o vídeo
anunciado como português de Portugal.

**A origem foi consertada:** `upload.py` tratava idioma como opcional e **23 de 24** `meta.json` não
declaravam. Agora cai em `pt-BR` por padrão. ⚠️ **Essa correção NÃO está versionada** — `_pmo` ignora
`youtube/*` (`.gitignore:20`). Existe só no disco, em `~/projects/_pmo/youtube/upload.py` linha 62.

**A config do canal está correta** e não precisa de ação: `country=BR`, `madeForKids=False`. O
`defaultLanguage` do canal lê `pt` e **não vira `pt-BR`** — é normalização da plataforma, não falha
de escrita, provado por controle positivo.

## 3. Por que o canal não cresce: o diagnóstico mudou duas vezes

**178 inscritos · 3.663 views · 118 vídeos únicos** (93 públicos: 48 Shorts, 45 longos).

Duas hipóteses caíram na medição, e a segunda era minha:

1. **"Os Shorts recentes morreram"** — falso. Normalizado por idade, o patamar é **estável desde
   outubro de 2025**, entre 0,11 e 0,30 views/dia. Os Shorts de agosto com 1 e 2 views têm 20 dias
   de vida e estão no patamar de sempre. Views brutas comparam vídeos de idades diferentes.
2. **"É o `pt-PT` que sufoca os Shorts"** — não sustentado. Na janela comparável havia **1** Short
   `pt-BR` contra 43 `pt-PT`, e o Short mais visto do canal inteiro (269 views) é `pt-PT`.

**O que os dados realmente dizem:**

- **Volume já foi testado e não moveu o patamar.** Julho teve **26 Shorts em 22 dias**, com cinco
  dias levando 2 ou 3. O mês seguinte é o pior da série.
- **Os longos rendem o DOBRO dos Shorts**: 0,38 contra 0,19 views/dia. No seu canal o formato curto
  é o menos eficiente, o inverso do senso comum.
- **Engajamento é o sinal mais grave: 9 comentários no canal inteiro**, 91 de 98 vídeos em zero.
- SEO estrutural: **80 de 98 sem capítulos**, 26 sem nenhuma tag.

⚠️ **O que decide está fora de alcance hoje.** Impressões, CTR e retenção separam "o YouTube não
mostra" de "mostra e ninguém clica" de "clicam e abandonam" — três causas com ações **opostas**. A
Analytics API devolve **403**: nenhum token tem `yt-analytics.readonly`.

**Próximo passo, e ele depende do dono:**

```bash
~/.venvs/youtube/bin/python ~/projects/_pmo/youtube/auth_analytics.py   # abre o navegador
```

O script já existe e escreve `token_analytics.json` separado (só leitura). **Sem essa medição,
qualquer ajuste de SEO é palpite** — inclusive os que estão nesta seção.

## 4. Áudio: quatro tentativas, e a constante da skill não valia

A gravação tinha **pico positivo** (+0,58 dBTP), que é clipping. Quatro execuções sobre o **mesmo**
arquivo:

| # | config | Integrated (alvo −14) | TP final (alvo ≤ −1) |
|---|---|---|---|
| 1 | TP=−2, `linear` | −14,3 ✓ | **+1,4** ✗ |
| 2 | TP=−5, `linear` | **−15,9** ✗ | −2,8 ✓ |
| 3 | **TP=−4, dinâmico** | −15,3 | **−2,8** ✓ ← **publicado** |
| 4 | TP=−3, dinâmico | −14,8 ✓ | **+0,5** ✗ |

**O overshoot do AAC variou de 1,1 a 3,4 dB sem padrão** (a skill registrava 0,8 dB, de outro vídeo).
Não há margem calculável de antemão: só a medição do arquivo final decide.

**O `linear=true` foi erro meu** — não estava na skill e contrariava o `normalization_type: dynamic`
que a própria análise devolveu. Criou um impasse artificial e custou duas execuções de ~10 min.

**Escolha registrada:** entre os dois alvos, protegi o **pico**. Clipping é audível; 1,3 dB de
loudness a menos não é, e o YouTube atenua quem passa de −14 mas **não amplifica quem fica abaixo**.

## 5. O que ficou pronto do pipeline

- **Transcrição** local (WhisperX/GPU), 1.165 cues, cobrindo até 2:11:28 de 2:11:29.
- **Legendas** pt-BR, es-LATAM, en-US: 1.165 cues **cada** (a igualdade de contagem é o porteiro do
  pareamento), blindagem aplicada (42 correções no inglês, 41 no espanhol). Sobrou **1** `core`, e é
  legítimo: "the core of the business".
- **43 capítulos** ancorados em frase da transcrição e conferidos **um a um**. A primeira tentativa,
  por janelas de tempo, reproduziu o defeito que a skill já documentava (a marca cai no fim do
  assunto anterior).
- **Sem corte** — medido: fala começa em 2,6 s e há 27 s de fala após o último silêncio. Isso
  dispensou o passo 5 (deslocar legendas), que é o que mais custa quando existe.
- **Sem miniatura**, por padrão medido: as três Lideranças anteriores usam frame automático.

## 6. ABERTO

| # | o que | estado |
|---|---|---|
| — | `auth_analytics.py` | **precisa do dono** (login no navegador) |
| #2367 | reforma da skill `youtube-publicacao` | **PR aberta**, CI rodando |
| — | 23 vídeos **não listados** ainda sem idioma declarado | fora do escopo autorizado hoje |
| #2362 | `REVOKE` + guard derivado de `_test_*` | issue aberta, **não aplicado** |
| #2361 | 170 tools absorvidas mas registradas | issue aberta, sem dono |
| — | alertas do Dependabot (`security/dependabot/115`) | política #611: PR local de higiene |

## 7. O que a sessão fechou

- PRs **#2363** (hook de DDL enxerga job de banco) e **#2364** (handoff) mergeadas.
- Os **dois testes da seção 5** do handoff anterior rodaram: `2351-rota-de-ata` **5/5 com 0 skips**, e
  `rpc-migration-coverage` **17/17**, com a tabela órfã confirmada extinta. Com
  `DATA_INVARIANT_GATE=1` apareceu 1 falha que era **timeout de rede**, não invariante — re-rodada
  isolada, passa em 5,3 s.
- **53 vídeos** com idioma corrigido, origem consertada, `[LL]` registrado na #588.

## 8. Máquina

⚠️ **`nvidia-smi` está quebrado e MENTE por omissão:** `Failed to initialize NVML: Driver/library
version mismatch` (NVML 595.91 contra kernel 595.84). Lido como "sem GPU", trocaria 15 min de
transcrição por horas de CPU. **A GPU funciona**: `torch.cuda.is_available()` = True, RTX 3070 Ti,
matmul 4096² em 0,35 s. Pergunte ao runtime, não ao diagnóstico. Um reboot pode resolver o mismatch.
