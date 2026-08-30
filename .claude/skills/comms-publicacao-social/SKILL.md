---
name: comms-publicacao-social
description: Publica anúncio de webinar ou evento no Instagram e no LinkedIn do Núcleo, com marcação de pessoas e convite de colaboração. Use quando houver peça e copy prontas e for hora de publicar, ou quando alguém perguntar por que a automação do projeto não dá conta.
user_invocable: true
---

Publicação orgânica nas contas do Núcleo. **Leia a primeira seção antes de prometer automação**: o
publisher do projeto NÃO faz duas coisas que quase toda campanha de evento precisa.

## O que a automação do projeto NÃO faz (medido 29/08/2026)

Lendo as Edge Functions do próprio repo:

- `supabase/functions/publish-instagram` aceita `media_type`, `image_url`, `caption` e `children`.
  **Não tem `collaborators` nem `user_tags`.**
- `supabase/functions/publish-linkedin` aceita `text`, `image_url` e `alt_text`. **Não tem menção.**

Consequência que decide o caminho: **convite de colaboração sai no ato da publicação e não se
adiciona depois**. Publicar pela API entrega o post sem colaboração e sem marcação, ou seja, sem o
alcance somado dos perfis convidados, que costuma ser a razão de convidar. Há ainda um
pré-requisito: o Graph busca a imagem por **URL pública**, então a peça teria de subir antes para o
bucket `comms-media`; peça no Drive não serve.

**Por isso a publicação de campanha é MANUAL, no navegador.** A automação serve para post simples,
sem marcação e sem colaboração.

## Instagram, pelo navegador

O compositor web tem tudo: **marcar na foto**, **Add collaborators** e até **Schedule content**.

### O passo que quase todo mundo erra: o corte

Ao subir a imagem, o Instagram abre em **1:1 por padrão** e corta a peça em silêncio. Numa peça
1080x1350 isso comeu o selo do topo e o rodapé institucional, e nada avisa. **Abra o seletor de
enquadramento (ícone no canto inferior esquerdo do preview) e escolha "Original"**, ou 4:5. Confira
na prévia que topo e rodapé aparecem antes de seguir.

### Ordem que funciona

1. **Create → Post**, e `file_upload` no `input[type=file]`. Não clique em "Select from computer":
   isso abre o seletor nativo do sistema, que a automação não enxerga.
2. **Crop → Original.** Ver acima.
3. **Next** duas vezes (a segunda tela é a de filtros; deixe em Original).
4. **Legenda**: clique no campo e digite em blocos, conferindo entre eles. É `contenteditable`.
5. **Marcar na foto**: clique sobre o rosto, digite a arroba, escolha na lista.
6. **Add collaborators**: digite a arroba, marque o radio, repita, e **Done**.

### Armadilhas medidas

⚠️ **A busca de arroba devolve sósias.** Procurando `hbj_joao` vieram também `joao.hbj` e
`haiderbaptistajoaohbj`. Escolha pelo **nome exibido e pelo selo de verificado**, não pela ordem.
Marcar a conta errada num post público não se desfaz.

✅ **Os colaboradores sobrevivem à reescrita da legenda.** Apagar tudo com `ctrl+a` e redigitar não
derruba a seleção: o campo continuou em "4 people". Confira mesmo assim.

⚠️ **O convite precisa ser ACEITO.** O próprio Instagram avisa: "If they accept, it will be shared
with their followers and shown on their profile". Até lá o post aparece só no perfil de quem
publicou. E o **teto é de 5 colaboradores**.

⚠️ **Conta sem Instagram não vira arroba.** Se um palestrante não tem conta, cite o nome dele **na
mesma frase da arroba de quem tem**, para a ausência não ficar exposta. Nunca invente uma arroba
parecida: ela pertence a outra pessoa.

## LinkedIn, pelo navegador

Não existe colaboração como no Instagram; o equivalente é pedir republicação. Menção **não se faz
colando URL**: as URLs servem para achar o perfil certo antes.

### ⚠️ Menção inline: a automação só entrega a PRIMEIRA, e as seguintes corrompem o texto

Medido em 29/08/2026, publicando o anúncio de um webinar. A receita que faz uma menção nascer certa:
digitar o parcial, **esperar a lista carregar**, e então `Down` mais `Return`. Sai o
`<a class="ql-mention">` correto.

Da segunda menção em diante o editor devolve lixo. Três saídas observadas: o nome colado ao texto
vizinho, um sufixo herdado de outro item da lista, e num dos casos **a menção anterior foi apagada**.
Não é falta de espera: as tentativas com pausas maiores falharam igual.

O que fazer, então:

1. **Publique o corpo em texto limpo**, nomeando as pessoas por extenso, sem nenhuma arroba. Um post
   sem menção tem conserto; um post público com o texto quebrado não.
2. **Peça a uma pessoa que comente marcando todo mundo.** No comentário o editor é o mesmo, mas o
   custo de errar é um comentário apagável, e para um humano leva 30 segundos. **O comentário
   notifica exatamente como a menção no corpo**, então o alcance não se perde.

Nunca tente "consertar" um post já publicado editando menção nele: a edição passa pelo mesmo editor.

Ao abrir `linkedin.com/company/<slug>/posts/`, se a conta for admin a URL redireciona para o
dashboard de admin da página. Isso confirma o acesso de publicação como página.

## Precisão institucional que já saiu errada

Distinga **quem sedia** de **quem tem filiado falando**. Escrever "com filiados dos capítulos A, B e
C" quando o capítulo A só é a sede afirma que há um filiado dele palestrando. O formato que fecha:

> "... sediada no @capituloSede. Nesta edição, os palestrantes são filiados ao @capituloX e ao
> @capituloY."

Consulte a filiação em `member_chapter_affiliations`, não por memória: cada pessoa pode ter
capítulo primário e secundário.

## Antes de publicar, confira

- Legenda dentro do limite (Instagram 2.200) e passando em `node scripts/lint-social-copy.mjs`.
- Enquadramento **Original**, com topo e rodapé visíveis.
- Arroba de cada marcado conferida pelo nome exibido.
- Colaboradores no número esperado.
- Se a copy diz "link na bio", **confira o link da bio antes**: ele já apontou para o evento anterior.

## Depois de publicar

Confira no **perfil**, não só no post: a grade corta o reel em 12,5% em cima e embaixo, e a capa
padrão é o primeiro frame. Ver `[LL] #2068`.


## Depois de publicar: confira a superfície, não o arquivo

Três defeitos desta campanha tinham a mesma forma: **a peça estava certa no arquivo e errada onde
ela é de fato vista**. Vale rodar estas conferências no fim, não no começo.

**A miniatura do link do evento.** Leia o `og:image` da página do evento e **baixe exatamente o que
o crawler recebe**, com a query string e tudo. Compare a razão com a da peça original: se bate, o
CDN está redimensionando; se não bate, está cortando, e aí a peça precisa nascer na razão de
destino. Medido: `747x420` servido contra `1440x810` original, razão 1,779 contra 1,778, ou seja
sem corte. Parâmetros `?w=&h=` na URL **não provam corte**; só a razão do arquivo que chega prova.

**A prévia do link de um post do Instagram é sempre quadrada, 640x640**, e o WhatsApp ainda recorta
de novo. Uma peça 4:5 perde as bordas nesse caminho e **não há ajuste possível do nosso lado**. Para
compartilhar em conversa, mande o **link do evento**, cuja miniatura é a peça inteira; deixe o link
do post para quem for curtir e comentar.

**A grade do perfil no Instagram** corta reels em cima e embaixo e usa o primeiro frame como capa.
Peça de vídeo precisa de um primeiro frame que já seja a capa, e de margem vertical de sobra.
