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

### ⚠️ Menção inline: o limite é da AUTOMAÇÃO, não do editor

Medido em 29/08/2026, publicando o anúncio de um webinar **por automação de teclado**. A receita que
faz uma menção nascer certa: digitar o parcial, **esperar a lista carregar**, e então `Down` mais
`Return`. Sai o `<a class="ql-mention">` correto.

Da segunda menção em diante a automação devolve lixo. Três saídas observadas: o nome colado ao texto
vizinho, um sufixo herdado de outro item da lista, e num dos casos **a menção anterior foi apagada**.
Pausas maiores não mudaram nada.

**Não conclua daí que o editor não aceita várias menções.** No mesmo dia, o dono da página fez as
**cinco menções de uma vez, à mão, editando o post já publicado**, e todas saíram corretas. O que
falha é o caminho sintético, não o produto.

O que fazer, então:

1. **Pela automação, publique o corpo em texto limpo**, nomeando as pessoas por extenso, sem nenhuma
   arroba. Um post sem menção tem conserto; um post público com o texto quebrado dá muito mais
   trabalho.
2. **Peça a uma pessoa que adicione as menções.** ✅ **Editar o post já publicado funciona** e é o
   caminho preferido, porque a menção fica no corpo, onde ela pesa mais. Comentar marcando todo mundo
   também notifica, e serve quando ninguém tem acesso de edição.

### ⚠️ Digitar em blocos come as linhas em branco entre parágrafos

Também medido em 29/08/2026. O arquivo de origem em `publicar/` tinha os parágrafos separados por
linha vazia, e **o post saiu como um bloco corrido**: o campo é `contenteditable`, e digitar por
partes colapsou as linhas em branco. Ninguém avisa, e o texto continua legível o bastante para passar
despercebido.

**Confira contando linha VAZIA, não linha de texto.** A armadilha aqui foi da própria conferência:
`innerText.split('\n').filter(Boolean)` **descarta as linhas vazias**, então a checagem que deveria
pegar o defeito o apagava antes de olhar. Meça `(txt.match(/\n\s*\n/g) || []).length` e compare com
o número de parágrafos do arquivo de origem.

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

**A prévia do link de um post do Instagram é um CORTE agressivo, não um redimensionamento.** Medido:
`640x640`, razão 1,000, contra 0,800 da peça, e a própria URL do `og:image` traz a diretiva de corte
`stp=c216.0.648.648a_..._s640x640`. O resultado não é "perder as bordas": **sumiram os dois
palestrantes e a data**, e a manchete perdeu os dois lados. O que resta é um pedaço de texto ampliado.

Não há ajuste do nosso lado para um post já publicado. **Em conversa, mande o link do EVENTO**, cuja
miniatura é a peça inteira; deixe o link do post para quem for curtir e comentar.

Existe uma hipótese de mitigação **ainda não testada**: publicar a peça de feed em 1:1, para que não
sobre nada a extrair. Vale testar num post seguinte e medir, em vez de assumir.

**A grade do perfil no Instagram** corta reels em cima e embaixo e usa o primeiro frame como capa.
O tile é 242x322 (razão 0,75) e o reel é 9:16 (0,563), então sobra `0,563 / 0,75 = 75%` da altura:
**12,5% saem em cima e 12,5% embaixo**. O post de feed 4:5 não sofre, perde ~3% de cada lado.

Antes de publicar um reel, rode a checagem e **olhe o contato**:

    python3 scripts/design-kit/checar_reel.py <video.mp4>

Ela recorta os quadros como a grade recorta e responde as duas perguntas da #2068: se há conteúdo
na faixa que será decepada, e se o primeiro quadro presta como capa (ou em que segundo está o
melhor). Sai `grade.png`, que é o que o perfil mostra, e sai diferente de zero quando reprova.

Ela mede **detalhe**, não texto: acusa "tem coisa que vai ser cortada", não "tem texto ali". O
`grade.png` continua sendo o juiz.
