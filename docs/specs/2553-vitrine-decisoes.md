# Decisões da vitrine (#2553, #811): D1 a D11

**Status:** **Aceito**, 04/10/2026, pela ratificação do GP registrada na última seção, palavra por palavra (era
Proposto no commit `59640901`). Uma spec escrita por sessão não autoriza nada; a ratificação nomeada é que autoriza.
**Base:** o plano (`2553-vitrine-producao-e-conhecimento.md`) e a contraprova (`2553-vitrine-contraprova.md`, ajustes
A1 a A18), nesta mesma pasta.
**Formato:** kit de registro de decisões do AI-PMO-Framework (`kits/decision-records-kit.md`): triagem por balde,
opções, recomendação com o porquê, caminho de volta e gatilho de retomada.
**Escopo no tempo:** cobre o estado medido em 04/10/2026, por consulta ao vivo nesta data. Número aqui é relógio:
re-meça antes de executar.

## Triagem

Três baldes: **mecânico** (entra quando a fase rodar, sem ratificação), **decisão** (precisa da direção do GP antes
de qualquer código) e **humano externo** (tarefa nomeada de alguém, sem opção técnica).

| # | assunto | balde | o que trava |
|---|---|---|---|
| D1 | autoria pública | decisão, com parecer do `legal-counsel` antes | F3 em diante |
| D2 | wiki público | decisão | página de conhecimento |
| D3 | nome e rota da página | decisão | F4 |
| D4 | podcast | decisão | só o podcast |
| D5 | quem registra realizações | decisão | F2 |
| D6 | páginas vazias para o visitante | decisão | F0, parte do menu |
| D7 | janela e rótulo das horas | decisão | F1 |
| D8 | seguir ou emendar a ADR-0099 | decisão | F2 a F5 |
| D9 | verdade sobre artigos e publicados | humano externo | vitrine de artigos |
| D10 | convenção de chave de idioma | decisão técnica | F2, idioma do dado |
| D11 | Instagram e LinkedIn | decisão | F4 |

**Mecânico, sem ratificação:** A2 (guard por lista de chaves permitidas), A3 (`get_webinars_count`), A5 (rótulos nos
dicionários, sem literal de data, contagem de tribos ativas, `chapters_engaged`), A9 (uma função interna, dois
invólucros), A12 (migrar as traduções de `src/data/tribes.ts`), A15 (filtro de não listado que falha fechado), A16
(registrar "realizações publicadas" no dicionário da ADR-0100) e A18 (modo no gateway `/semantic`). Eles seguem ADRs
aceitas ou corrigem defeito medido.

## D1. Autoria pública

- **Medido:** `get_public_impact_data` já devolve ao visitante o nome de 15 líderes de tribo e de 5 patrocinadores de
  capítulo. `get_public_publications` devolve autores, mas hoje não há publicação.
- **Opções:**
  - (a) mostrar autoria de obra publicada e papel institucional (líder, patrocinador), com base registrada por interesse
    legítimo e canal de oposição;
  - (b) mostrar só com consentimento individual, e o resto como "equipe da tribo";
  - (c) nenhum nome em superfície pública.
- **Recomendação: (a), condicionada ao parecer do `legal-counsel`.** O nome do líder é papel institucional que já é
  público, e na obra publicada a indicação do autor também tem lado de direito autoral (a confirmar no parecer). (b)
  cria fila de consentimento que trava a vitrine; (c) retira o que já sai hoje sem motivo medido.
- **Vale também para o que já sai** (A17): a base registrada cobre as chaves atuais, e uma exceção aprovada entra como
  dado no guard.
- **Caminho de volta:** retirar a chave do payload público é uma migration.
- **Pré-condição:** o parecer, antes de F3.

## D2. Wiki público

- **Medido:** 19 páginas, 17 com CC-BY-4.0 e 2 sem licença. O repositório do wiki é privado. O fluxo `wiki_decide` e
  `wiki_audit` existe, com detector de PII.
- **Opções:**
  - (a) abrir todas as que têm licença;
  - (b) abrir página a página pelo fluxo existente, com a passada de PII como pré-condição;
  - (c) manter fechado e expor só resumos.
- **Recomendação: (b).** Licença declarada não é decisão de publicar, e páginas de tribo já carregaram lista de
  pessoas. O fluxo e o detector existem: quem decide por página são os papéis que o `wiki_decide` já tem.
- **Caminho de volta:** `wiki_audit` despublica.
- **Gatilho:** a primeira página aprovada no fluxo libera a página de conhecimento.

## D3. Nome e rota da página

- **Medido:** `/publications` existe em pt, en e es, com feed RSS (`src/pages/publications/feed.xml.ts`), e lê
  `get_public_publications`.
- **Opções:**
  - (a) manter a rota `/publications` e trocar só o título visível;
  - (b) rota nova (por exemplo `/realizacoes`) com redirecionamento da antiga;
  - (c) página nova ao lado da atual.
- **Recomendação: (a), com o título "Produção" (en "Our work", es "Nuestra producción").** Preserva links, indexação e
  quem assina o feed; o título é um valor nos três dicionários e muda quando quiser. (c) cria duas vitrines.
- **Caminho de volta:** trocar o texto no dicionário.

## D4. Podcast

- **Medido:** o enum de instrumento de `content_products` já tem `podcast_episode`.
- **Opções:**
  - (a) cadastro manual de cada episódio como produto, pela curadoria;
  - (b) ingestão automática do RSS do Spotify num sync novo (Edge Function agendada);
  - (c) só o link do canal.
- **Recomendação: (a) agora.** Usa o dono da ADR-0099 sem infraestrutura nova; automação só se pagar.
- **Gatilho de retomada:** passar a (b) se o cadastro manual ficar mais de um episódio atrás por mais de 30 dias.
- **Caminho de volta:** trivial.

## D5. Quem registra realizações

- **Medido:** a ação `curate_content` (ADR-0087) tem 3 combinações semeadas em `engagement_kind_permissions`. A ponte
  card → produto existe (`board_items.content_product_id`), com 8 cards ligados.
- **Opções:**
  - (a) quem já tem `curate_content` publica, a partir do card do líder;
  - (b) dar `curate_content` também ao correspondente de comunicação;
  - (c) o líder publica direto, sem curadoria.
- **Recomendação: (a); (b) só quando houver uma pessoa nomeada com essa atribuição.** A autoridade é do `can()`
  (ADR-0007) e o fluxo de curadoria existe (ADR-0086, ADR-0087). Semear permissão sem pessoa nomeada é rótulo sem dono.
  Antes de qualquer seed, o procedimento de 5 etapas do `V4_AUTHORITY_MODEL.md`, inclusive a etapa 0.
- **Caminho de volta:** remover o seed.
- **Gatilho:** nomeação de um correspondente de comunicação com a atribuição.

## D6. Páginas vazias para o visitante

- **Medido:** `/library` lista `hub_resources`: 229 ativos de 330, entre eles 11 certificados, que são dado pessoal.
  `/cpmai` não tem conteúdo para quem não entrou (#2555).
- **Opções:**
  - (a) tirar `/library` do menu do visitante e dar a `/cpmai` uma seção explicativa com convite;
  - (b) abrir um subconjunto curado da biblioteca, sem certificados nem documento interno;
  - (c) manter como está.
- **Recomendação: (a) agora; (b) como evolução, quando alguém curar o subconjunto.** Hoje o visitante cai em página
  vazia, e certificado não pode ir para o público. Esconder do menu é barato e reversível.
- **Caminho de volta:** o menu é configuração de frontend.

## D7. Janela e rótulo das horas de impacto

- **Medido:** o `/about` mostra 3427 horas, de uma soma escrita na própria função, sem `duration_actual` e sem excluir
  ausência justificada: fórmula que a ADR-0100 veda. Pela fórmula canônica (`get_impact_hours_canonical`): ano
  corrente 2319 (o que a home mostra), ciclo 4, desde 09/07/2026, 1412, e desde o primeiro evento (13/09/2019) 3052.
- **A fórmula não está em decisão:** a ADR-0100 já decidiu. Decide-se a janela e o rótulo do `/about`.
- **Opções:**
  - (a) a mesma janela da home (ano corrente) e o mesmo rótulo;
  - (b) desde o início, com o rótulo "desde 2019";
  - (c) o ciclo atual.
- **Recomendação: (b) no `/about`, com a home no ano corrente.** O `/about` conta a história do Núcleo e a home mostra
  o ritmo do ano. Com a mesma fórmula e rótulos explícitos, dois números deixam de parecer contradição. Se preferir um
  número só no site, (a).
- **Antes de mudar:** avisar o pmigo-plataforma, que consome `get_public_impact_data` (#2365).
- **Caminho de volta:** a janela é um parâmetro.

## D8. Seguir ou emendar a ADR-0099

- **Medido:** `content_products` tem 37 produtos (6 publicados, 31 em revisão), com leitores para membro e 8 cards
  ligados.
- **Opções:**
  - (a) seguir a ADR-0099: `content_products` é o dono das realizações e o card só aponta;
  - (b) emendar a ADR-0099 para aceitar tipo e marca de público no card, a alternativa que ela rejeitou.
- **Recomendação: (a).** A tabela, os leitores e a ponte já existem. (b) duplica o dono e é emenda de ADR de vários
  domínios, que pelo kit pede conselho com assentos nomeados.
- **Caminho de volta:** não se aplica; (a) é o estado atual.

## D9. A verdade sobre artigos e publicados

- **Medido:** `public_publications` tem 7 registros, nenhum publicado e nenhum com URL. Dos 6 produtos marcados como
  publicados em `content_products`, nenhum tem URL, e os 6 têm a mesma data de publicação, a do backfill.
- **Não há opção técnica:** alguém precisa dizer o que foi publicado, onde e quando.
- **Recomendação:** o GP nomeia um responsável (curadoria ou comunicação) e uma data. Até lá, a vitrine começa pelo que
  tem dado (webinars concluídos com replay, blog), e artigos ficam fora.
- **Gatilho:** URL e data preenchidas nos publicados, e destino decidido para os 7 de `public_publications`.

## D10. Convenção de chave de idioma

- **Medido:** chave curta (`pt`, `en`, `es`) em `tribes.name_i18n`, `events.title_i18n` e
  `tribe_deliverables.title_i18n`; chave longa (`pt-BR`, `en-US`, `es-LATAM`) em `blog_posts.title`; e
  `normalize_platform_language('en')` devolve `en-US`.
- **Opções:**
  - (a) a curta é a canônica no banco, com um helper único que converte o idioma da plataforma e marca fallback, e
    `blog_posts` migra depois;
  - (b) a longa é a canônica, e as tabelas de chave curta migram;
  - (c) as duas para sempre, com o helper tentando ambas.
- **Recomendação: (a), com o helper aceitando as duas durante a transição.** A maioria das tabelas medidas já usa a
  curta, e o defeito real é o leitor ingênuo. O guard tem controle positivo: item com chave `en` volta em inglês para
  `en-US`.
- **Caminho de volta:** o helper isola a convenção; mudar depois é trocar o helper e uma migration.

## D11. Instagram e LinkedIn

- **Medido:** os posts dos dois canais já são sincronizados pela plataforma, e o enum de `content_products` tem
  `linkedin_post`.
- **Opções:**
  - (a) só os links dos canais na vitrine;
  - (b) destaques curados como cards;
  - (c) feed completo embutido.
- **Recomendação: (a) agora.** O conteúdo já é público no canal, e feed embutido duplica o canal e custa manutenção.
- **Gatilho de retomada:** passar a (b) se a medição de uso da vitrine no PostHog, depois de F4, mostrar visita.
- **Caminho de volta:** trivial.

## Ratificação

| campo | valor |
|---|---|
| Ratificado por | GP (Vitor), na sessão orquestradora de 04/10/2026 |
| Data | 04/10/2026 |
| Resposta do GP, palavra por palavra | "ratifico todas" |
| Ratificadas como recomendado | D1 a D11 |
| Ratificadas com ajuste (qual) | nenhuma |
| Pendentes | D1: o parecer do `legal-counsel`, pré-condição de F3, ainda não foi pedido. D9: o GP ainda não nomeou o responsável nem a data. |

O registro está em `docs/council/decisions/2026-10-04-2553-vitrine-onze-decisoes.md`. Mudar uma decisão aceita pede
emenda, não edição silenciosa.
