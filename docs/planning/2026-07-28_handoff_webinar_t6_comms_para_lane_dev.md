# Handoff 2026-07-28 - Webinar T6 encerrado no lado comms, voltando para a lane dev

Encerra a linha de trabalho de comunicação do webinar da tribo ROI & Portfólio (04/08).
Continua o handoff de 27/07 (`2026-07-26_handoff_webinar_t6_airmeet_comms.md`).

**Evento:** `webinars.id` `4ff3a888-8959-4262-82e6-a6f54ffc3964` · card `f5a77542-...`
**Kit:** https://drive.google.com/drive/folders/1aZYlu4iRASdoZ82Kq86Yhdna_P74ns88
**Página do kit:** https://claude.ai/code/artifact/9cc6f3fc-8f55-4d26-96de-cbe1901350cf

## Estado final

**No ar** (publicados 27/07, 11h12 BRT):
- LinkedIn https://www.linkedin.com/feed/update/urn:li:share:7487510200724152320/
- Instagram https://www.instagram.com/p/DbTJ-JrE-rA/

**Página do evento**: 4 palestrantes (Denis, Messias, Fernando, Clendson) com foto, cargo, empresa e
LinkedIn, os 4 com convite de backstage enviado. Título, Overview, capa, waiting screen e lounge banner
corrigidos e auditados.

**Programação confirmada pelo Denis**: 19h00 abertura, 19h05 tribo (Messias), 19h10 Fernando,
19h45 Clendson, 20h25 fechamento. Fabrício dá suporte não declarado pela conta `contato@pmigo.org.br`.

## ⚠️ NADA está agendado

A fila `comms_scheduled_posts` tem só os 2 publicados e 2 cancelados. **Não vão sair sozinhos:**

| peça | por quê |
| --- | --- |
| Story do Instagram | pela API sai sem link tocável, e o link é o CTA. Manual, com sticker |
| 3 mensagens de WhatsApp (anúncio, D-1, 18h50) | não há publisher para o canal |
| Lembrete D-1 do LinkedIn | pronto e no padrão do time, mas não agendado |

**Marcação de pessoas e colab de post nunca foram feitas** nos 2 posts no ar. Não é automatizável
(#1374): precisa alguém abrir o app e marcar Fernando, Clendson, Messias, Denis e as páginas dos
capítulos.

## Lição que virou código: o time de comms edita, e o padrão é por canal

Comparei o payload publicado com o texto que ficou no ar. **No LinkedIn cortaram 25%**
(1913 -> 1431 bytes): as 7 hashtags, o parágrafo institucional do Núcleo, a linha de formato, o
"(horário de Brasília)", o chamariz da gravação, e o emoji do rótulo do CTA. **No Instagram não mexeram
em nada estrutural.** E o descritor da pessoa muda por canal: IG curto e capitalizado, LinkedIn completo
em minúscula correndo na frase, com a titulação.

Codificado em `scripts/lint-social-copy.mjs` (reprova o meu LinkedIn com 3 erros, aprova o do time) e na
memória `reference-social-post-conventions`.

## Métricas: linha de base, não conclusão

O cron `sync-comms-metrics` roda 06h UTC e grava **por canal e por dia**, não por post. O snapshot de
28/07 cobre só ~16h depois da publicação.

| LinkedIn | 27/07 | 28/07 | delta |
| --- | --- | --- | --- |
| impressões únicas | 19.735 | 19.976 | +241 |
| reações | 1.837 | 1.861 | +24 |
| cliques | 4.583 | 4.602 | +19 |
| seguidores | 802 | 807 | +5 |

Instagram, alcance diário: 292 (26/07), 140 (27/07), **354 (28/07)**.

**Não dá para atribuir isso ao post com confiança**: é métrica de canal, a janela é curta, e o dia 27
teve outras publicações. Para virar conclusão, precisa de métrica **por post**, que a Graph API e a
LinkedIn API expõem mas o `sync-comms-metrics` hoje não persiste por `permalink`.

### Horário de publicação: há um dado bom e um caveat

O payload do IG traz `online_followers`, distribuição horária de seguidores online. Pico nas horas
**15, 17, 14, 16, 13, 11** (índice 253-278); vale mais baixo às 23h (17) e 22h (22).

⚠️ **O fuso desse índice não está verificado.** O `sync-comms-metrics` repassa o valor cru da Graph API
sem normalizar, e a Meta já mudou esse comportamento (ora UTC, ora fuso da conta). O post saiu
**11h12 BRT = 14h12 UTC**, que cai no platô alto nas duas leituras, mas "quanto antes do pico" depende
de resolver o fuso. Resolver comparando um post de horário conhecido com o pico observado, ou checando o
fuso configurado na conta.

## Backlog que esta linha gerou (candidatos para a lane dev)

1. **Métrica por post.** Persistir insights por `permalink` em `comms_scheduled_posts`, para conseguir
   dizer se um post específico funcionou. Hoje só existe agregado de canal.
2. **Normalizar o fuso de `online_followers`** no `sync-comms-metrics`, ou ao menos gravar de qual fuso
   veio. Sem isso, "melhor horário para postar" é chute.
3. **Wire do lint no fluxo**: rodar `lint-social-copy.mjs` antes de `comms_post action='schedule'`, ou
   como gate de CI sobre `docs/_deliverables/**`.
4. **`drive-upload-to-folder` ganhou `overwrite`** (PR #1492, verde e pronto para merge). Falta mergear.
5. Sujeira no Drive que a automação não apaga: `_probe_upsert.txt`, `Clendson_Gonçalves.png` (órfã),
   `Fabricio_Costa.png`, e dois pares redundantes de LEIAME/CSV. Não há endpoint de delete, por decisão.

## PR aberto

**#1492** `feat/drive-upload-upsert-airmeet-skill`, 11 checks verdes, `MERGEABLE / CLEAN`.
Contém: upsert do Drive, skill `airmeet-event-ops` com 4 scripts, o lint de copy, a copy do webinar e os
handoffs. Merge é decisão da sessão de dev.
