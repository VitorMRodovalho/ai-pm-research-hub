---
name: airmeet-event-ops
description: Prepara, aplica e VERIFICA a configuração pública de um evento no Airmeet (título/subtítulo, Overview, capa, pack de speakers) para webinars do Núcleo IA & GP. Use quando um webinar for criado ou revisado no Airmeet, ou quando o preview do link no WhatsApp/LinkedIn sair errado.
user_invocable: true
---

Gestão da página pública de um evento no Airmeet. **Leia a seção "Realidade do acesso" antes de
prometer qualquer coisa ao owner**: boa parte disto NÃO é automatizável, e o valor do skill está em
saber exatamente o que é e o que não é.

## Realidade do acesso (medido 2026-07-26)

**Não existe API de escrita para metadados de evento.** A "Manage Event API" pública do Airmeet expõe
`POST /auth`, `POST /airmeet` (criar) e `POST /airmeet/{id}/duplication`. Não há PUT/PATCH para
descrição, capa ou título, e as chaves de API são community-wide (aba Integrations, restrita a
Owner/Admin/Manager). Ver `docs/research/p134_airmeet_developer_docs.md`.
**Portanto: editar evento é browser, não API.** E funciona.

### O caminho certo: URL direta do dashboard do evento

```
https://www.airmeet.com/airmeets/<airmeetId>/summary
```

Essa URL entrega o dashboard completo de host. **Não tentar chegar lá pelo dashboard da community.**
Motivo medido: existem dois workspaces, e o seletor cai no errado.

- **PMI LATAM** (conta pro) = onde os webinars do Núcleo realmente vivem, e onde há permissão de edição.
  Login: **`contato@pmigo.org.br`**.
- **PMI Goiás** (limitado) = workspace vazio. `www.airmeet.com/community-manager/7f4858e0-59d1-4ada-9489-5314c4ad5265/events`
  mostra "Create your first event", e daí se conclui erradamente que não há acesso ao evento.
  Aconteceu: perdi uma rodada inteira concluindo "impossível" a partir dessa tela.

Página pública (para verificação): `https://<community>.airmeet.com/e/<airmeetId>`

## Aplicar as edições (fluxo testado de ponta a ponta)

### Título e descrição (Overview)
`.../summary` → botão **Edit** no painel "Webinar details" (abre `?drawer=eventForm`).
- **Name**: `form_input` no ref funciona. Limite **80 caracteres**, com contador ao lado.
- **Webinar description**: `form_input` NÃO serve, é rich text. ⚠️ E clicar pelo `ref` do editor
  **não dá foco**: digitei um texto inteiro que se perdeu. Clicar na **coordenada do corpo** do editor,
  digitar um pedaço curto, **conferir por screenshot que entrou**, e só então digitar o resto,
  parágrafo por parágrafo com `key: Return` entre eles. Não usar markdown: `**negrito**` sai literal.
- **Save** no rodapé do drawer. Confirmação: toast "Webinar details edited successfully".

### Capa da landing
`.../summary` → aba **Branding** → **Landing Page** → botão **Preview & Customize** (abre OUTRA ABA,
`/e/<id>/edit?preview=true`) → painel direito **Carousel Media** → **Replace** no Slide 1.
- O "Replace" abre um modal in-app ("Add image"), não o seletor nativo do sistema. Só DEPOIS de abrir o
  modal o `<input type=file>` existe no DOM: `find` por ele e usar `file_upload` com o ref.
  Antes de abrir o modal, `find` responde que não existe file input, o que parece um beco sem saída.
- Tamanho pedido: **1440x810**, jpg/png, até 5 MB. É exatamente o banner do kit.
- Salvar DUAS vezes: o **Save** do modal de ajuste (zoom/blur/opacity) e o **Save** do topo do editor.
- ⚠️ Arquivo para `file_upload` tem que estar no scratchpad da sessão; caminho em `~/Downloads` é
  rejeitado. Copiar para lá antes.

### Auditoria de branding: os 6 slots e o asset certo de cada um
Levantar os assets EM USO pelo `src` real, não pelo thumbnail:
`Array.from(document.images).filter(i=>i.alt==='imagePreview').map(i=>({src:i.currentSrc, nat:i.naturalWidth+'x'+i.naturalHeight, box:i.width+'x'+i.height}))`
e, para o backdrop do palco (que é `background-image`, não `<img>`), varrer `getComputedStyle(e).backgroundImage`.
**Comparar `nat` com o slot:** se a razão do asset não bate com a do slot, ele renderiza achatado.

| Slot | Onde | Dimensão | Peça do kit |
| --- | --- | --- | --- |
| Webinar logo | Branding > Webinar Branding | 512x512 | badge da NIA (mascote do Núcleo) |
| Welcome illustration | idem | 1440x720 | recepção |
| Lounge Banner | idem | **960x120** | gerar com `build_lounge_banner.py` |
| Stage Backdrop | Branding > Stage | 1920x1080 | palco (centro livre p/ o vídeo) |
| Waiting Screen | Branding > Stage > Waiting Screen | 16:9 | boas-vindas 1280x720 |
| Capa da landing | Branding > Landing Page | 1440x810 | banner |

Achados na T6 (26/07): logo, welcome illustration e stage backdrop **já estavam certos**. Os dois errados
eram **Lounge Banner** (peça 1440x810 num slot 8:1, achatava) e **Waiting Screen** (no "System default"
do Airmeet, com rostos de banco de imagem). Sponsors vazio é correto quando não há patrocinador.

⚠️ **O slot 960x120 não existe no kit** e nenhuma peça 16:9 serve nele. Gerar com
`build_lounge_banner.py` (no workdir do webinar): nessa razão não cabe a faixa institucional inteira
(ela sozinha teria 111px num canvas de 120), então a marca entra pelo badge da NIA. Medir a colisão
entre título e pill com `qa_measure.py` antes de subir: no primeiro render o pill passou por cima de
"de IA".

⚠️ **Upload não é o mesmo que ativar.** No Waiting Screen o arquivo sobe, aparece como "Waiting screen 1"
e o padrão **continua no System default** até marcar o radio. E o radio tem o mesmo vício do campo de
texto: clicar e navegar não persiste. Marcar, conferir na tela, e só então recarregar para confirmar.

### Importar speakers (fluxo em massa, testado)
`.../people/speakers` → **Add Speaker** → aba **Bulk upload speakers**:
1. `file_upload` do CSV no input "Upload .CSV list of your speakers" (limite: 50 linhas, 1 MB).
2. `file_upload` das fotos, todas de uma vez, no input "Drag or upload speaker images" (400x400, até 10 MB).
3. **Next** → tela "Speaker Mapping", que mostra foto ao lado do nome. **É aqui que se confere o
   auto-map**, antes de gravar. Acento e nome composto passam quando o arquivo bate com o CSV.
4. **Next** → lista com nome, e-mail e foto → **Submit**.

✅ **Adicionar speaker NÃO envia e-mail.** "Send invites to speakers" é um botão SEPARADO no topo da
página, e depois do import a coluna "Invitation status" fica em **"Not sent"**. Ou seja, dá para deixar
a landing completa sem avisar ninguém, e o convite de backstage fica como decisão de quem organiza.
Não clicar em "Send invites to speakers" sem pedido explícito: aí sim é mensagem a terceiro.

**Não existe passo de "vincular à sessão" em webinar de sessão única.** A aba Session só tem gravações,
clipes, recursos, enquete e ajustes; não há atribuição de speaker por sessão. Quem foi importado já é a
linha do palco, e o próprio import muda o "Registration Status" de Pending para **Registered** sozinho.
O que falta depois disso é só o convite.

**Disparar o convite** (mensagem a terceiro, exige pedido explícito): People > Speakers >
"Send invites to speakers" → abre gaveta com um checkbox por pessoa e o e-mail de cada uma → marcar →
"Send invites". Conferir a lista de destinatários NA GAVETA antes de confirmar. Resultado esperado:
"Invitation status" passa de "Not sent" para **"Invite sent"** na tabela.

⚠️ A ordem no site sai como o Airmeet quiser, não como a do CSV. Existe "Rearrange speakers" (arrastar),
que não vale automatizar. Conferir se a ordem bate com a da programação e ajustar à mão se importar.

### Mensagem de boas-vindas (a que o participante vê ao entrar)
Aba **Branding** → **Webinar Branding** → campo "Welcome Message" (limite 100).
- ⚠️ `form_input` aqui **não persiste**: aceita o valor na tela e volta ao antigo depois do reload.
  O caminho que persiste é clicar no **lápis**, clicar no corpo do campo, `ctrl+a`, digitar, e clicar
  no **✓**. Recarregar a página para confirmar.
- **Verificar sempre este campo em evento duplicado:** o do webinar da T6 estava com o texto do webinar
  ANTERIOR ("IA em Projetos e o Novo Standard do PMI"), herdado da duplicação. Mesma suspeita vale para
  "Welcome illustration" e "Webinar logo", que podem estar com asset de outro evento ou com placeholder
  genérico do Airmeet.

### Armadilhas de automação de browser nessa UI
- **Não confiar em coordenada entre chamadas.** O viewport muda de tamanho no meio da sessão (vi 1512 e
  1374) e a coordenada de ontem clica na linha de hoje. Em ação destrutiva isso é grave: num
  right-click por pixel eu selecionei o arquivo ERRADO no Drive. Usar `find` → `ref` para qualquer
  clique que importe, e conferir o estado de seleção por screenshot antes de confirmar.
- `computer:zoom` usa coordenadas do **viewport** (ex. 2494x1321), não do screenshot (1512). Converter
  ou não usar.

## O que ESTE skill automatiza de fato

### 1. Verificar a página pública (sem credencial, sempre funciona)

```bash
python3 .claude/skills/airmeet-event-ops/scripts/verify_public_page.py <url-do-evento>
```

Renderiza a landing em Chrome headless (o Airmeet é SPA: `curl` cru devolve casca vazia) e lê as meta
tags que os crawlers de verdade recebem, usando os user-agents do WhatsApp, do LinkedIn e do Facebook.
Reporta `og:title`, `og:description`, `og:image`, presença do botão de inscrição, e salva screenshot.

**Fuso: renderizar com `TZ=America/Sao_Paulo`.** O Airmeet mostra o horário no fuso do visitante; sem
`TZ` o headless cai no default da máquina e você reporta "horário errado" quando não está. O script já
força o TZ. Isso já gerou um falso positivo (EDT).

### 2. Montar o pack de import de speakers

```bash
python3 .claude/skills/airmeet-event-ops/scripts/build_speaker_pack.py <manifesto.json> <dir-saida>
```

Gera o CSV no template oficial de 14 colunas e as fotos 400x400, e **cruza as duas listas** para provar
que cada linha tem a foto com o nome exato que o auto-map do Airmeet aceita.

Regra do auto-map (ver memória `reference-airmeet-speaker-image-filename-mapping`): o arquivo tem que
ser a string literal `{First Name}_{Last Name}`. O `_` substitui APENAS o espaço ENTRE os dois campos;
espaço dentro de nome composto continua espaço, e **acento tem que ser idêntico ao do CSV**.
`Messias_Reis da Silva.png` mapeia; `Messias_Reis_da_Silva.png` não. Se o CSV diz "Gonçalves", o arquivo
tem que dizer "Gonçalves", não "Goncalves".

Ordem de import no Airmeet: **CSV primeiro, depois só os arquivos de imagem** (subir a pasta inteira faz
o README e previews virarem alerta "extra images present").

## Checklist da página pública de webinar do Núcleo

1. **Título x subtítulo.** O Airmeet tem limite de caracteres no título e o H1 da página é o título.
   Convenção do owner: quando o nome bonito é de uma SÉRIE ("Aplicações Práticas de IA"), o título do
   Airmeet leva o recorte específico daquela edição. Isso é deliberado, não bug. O que É bug é acento
   errado ou espaço sobrando, porque esse texto vira o `og:title` de todo link compartilhado.
2. **Overview preenchido.** Vazio deixa a seção Overview em branco na landing.
   ⚠️ **Medido e confirmado: preencher o Overview NÃO muda o `og:description`.** Ele continua
   "Checkout this event on Airmeet", que é string fixa do Airmeet. Ou seja, o preview do link no
   WhatsApp e no LinkedIn sai sempre com essa legenda genérica, e não há o que fazer pelo dashboard.
   Consequência prática para comms: **a copy do post tem que carregar o contexto**, porque o card do
   link não vai carregar. O que dá para controlar no preview é só o título e a imagem.
3. **Capa = peça de divulgação, não tela de palco.** Usar o banner 16:9 (1440x810). A tela de palco traz
   "ESTAMOS COMEÇANDO" e "Deixe seu microfone fechado", que é conteúdo de dentro do evento e fica errado
   como capa e como `og:image`.
4. **Fuso do evento** conferido com `TZ=America/Sao_Paulo` (ver acima).
5. **Organizador** aparecendo com o framing certo: "Núcleo IA & GP", iniciativa dos capítulos do PMI no
   Brasil, sediada no PMI-GO.
6. **Sem promessa de PDU** e sem "evento oficial do PMI" ou "chancelado" (regra do guia de marca, ver
   memória `reference-nucleo-event-design-kit`).

## Depois de qualquer edição

Rodar o passo 1 de novo e comparar. Editar dashboard sem re-verificar a página pública é como rodar
migration sem conferir o corpo vivo: a UI aceita e o público vê outra coisa.

Se o evento tem registro na plataforma, gravar a pasta do kit em `webinars.promo_kit_url` e a sala em
`webinars.meeting_link` (via `webinar_manage action='update_assets'` ou UPDATE direto).
