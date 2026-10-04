# Spec #2553 (PR 2 em diante): vitrine pública do que o Núcleo produz e sabe

**Status:** PROPOSTA. Não executar antes da contraprova em sessão limpa (seção 9) e das decisões do GP (seção 6).
**Data:** 04/10/2026. **Issue:** #2553. **Depende de:** PR 1 da #2553 (contadores de fonte única), branch
`feat/2553-contadores-fonte-unica`, aplicada e mergeada.
**Origem dos números:** `[re-medido]` = consulta só leitura desta sessão em 04/10/2026; `[inventário]` = sondagem
externa do inventário de 04/10 (página pública, YouTube, Spotify, Drive), não re-medida aqui. Re-meça tudo antes
de executar: número em spec é relógio, não fato.

## 1. O pedido do GP (03 e 04/10/2026)

1. Webinars e conteúdos no YouTube, Instagram, LinkedIn e Spotify: organizar e mostrar.
2. O plano do time de comunicação, a tribo nova sendo lançada, tribos que foram a congressos, publicaram artigos ou
   apresentam em seminários de capítulos PMI. "Muitas realizações e artefatos que talvez não estejam visíveis nem
   sendo contados no local correto para a comunidade externa."
3. Tem de ser **trilíngue** e **fácil/interativo**.
4. Inclui **conhecimento aberto**: explicações de MCP, de CPMAI e de outros temas das tribos, pelo wiki ou outro meio.
5. Forma de trabalho: **plano primeiro, contraprova em sessão limpa, abordagem de plataforma (full-stack)**.

## 2. Diagnóstico medido

| tipo | fonte de verdade hoje | número | o visitante vê? | lacuna |
|---|---|---|---|---|
| Webinars | `webinars` | 12 no total, 6 concluídos, os 6 com YouTube `[re-medido]` | **Não.** `/webinars` chama `list_webinars_v2`, sem EXECUTE para `anon` `[re-medido]`: a página sai vazia | defeito em produção |
| YouTube | `comms_media_items` (EF `sync-comms-metrics`) | 98 vídeos sincronizados `[re-medido]`; canal com 101 `[inventário]` | só links soltos nos cards de tribo | sem vitrine, sem player |
| Instagram / LinkedIn | `comms_media_items` | 89 e 56 posts `[re-medido]` | só ícones no rodapé | contado só no admin |
| Podcast | só no Spotify | 7 episódios `[inventário]` | só ícone no rodapé | fora da plataforma |
| Blog | `blog_posts` | 13 publicados, último em 18/07/2026 `[re-medido]` | sim, trilíngue | o único fluxo trilíngue, parado |
| Artigos | `publication_submissions`, `public_publications` | 37 submissões (21 em revisão, 8 submetidas, 6 "published" legadas, 2 rascunhos) e 7 em `public_publications` `[re-medido]` | **Não.** `/publications` vazia; a home e o `/about` dizem 0 artigos | realizado e contado como zero |
| Congressos, palestras, seminários de capítulo | `initiatives` do tipo `congress` (6 `[re-medido]`) e cards dos boards | sem campo estruturado: 26 cards achados por palavra-chave `[inventário]` | não (iniciativas e boards são de membro) | sem fonte estruturada |
| Showcases em reunião geral | `event_showcases` | não medido | não | só membro |
| Tribo 15 | `tribes`, `initiatives`, `src/data/tribes.ts` | criada em 02/10 `[inventário]` | card na zona de membro, no fim da home | sem destaque de lançamento |
| Wiki (MCP, CPMAI, tribos) | `wiki_pages`, 19 páginas `[re-medido]`, repo `nucleo-ia-gp/wiki` (CC-BY-4.0) | leitura só para `authenticated` `[re-medido]` | **Não**, apesar da licença aberta | conhecimento fechado |
| Biblioteca | `hub_resources`, 229 ativos `[re-medido]` | leitura só para `authenticated` `[re-medido]` | no menu, mas chega vazia | link para página vazia |
| CPMAI | `/cpmai` + `get_cpmai_course_dashboard` | a RPC responde "Not authenticated" ao visitante `[inventário]` | só o cabeçalho | rota pública sem conteúdo |
| MCP | `/docs/mcp`, `/docs/mcp/conectar` | | sim, título trilíngue | descrições das ferramentas num idioma só `[inventário]` |
| Plano de comunicação | **Drive**, pasta "Hub de Comunicacao/Ciclo 4" `[inventário]`; não está no wiki | | | o site não aparece como canal no plano `[inventário]` |

**Números públicos que se contradizem** (fora da home, que a PR 1 já unifica) `[re-medido]`: o `/about` lê
`get_public_impact_data`, que dá pesquisadores 100 (home 76), horas de impacto 3427 (home 2319), tribos 15 (home 13),
capítulos 5 (home 15 depois da PR 1) e eventos 620 (home 650).

**Legenda trilíngue:** 13 de 101 vídeos do canal `[inventário]`. Campos de conteúdo trilíngues no banco: só
`events.title_i18n` e `tribes.name_i18n` `[re-medido]`.

## 3. Princípios (critérios de aceite de todas as fases)

1. **Plataforma, não página.** Cada realização tem dono no banco; o público lê por uma RPC `SECURITY DEFINER`
   anon-safe; a interface só apresenta. Nada de lista escrita à mão em `.astro` ou `.ts`.
2. **Derivar, não duplicar** (preferência registrada do GP). A vitrine **não** copia título nem URL: lê do dono pelo
   vínculo. Só se cria fonte onde não existe nenhuma (podcast, palestra/congresso/seminário).
3. **Uma fonte por número.** O contador da home, o facet da página e o `/about` saem da mesma RPC (continua a PR 1).
4. **Trilíngue no dado, não só na interface.** Título e resumo em pt, en e es no dono; a RPC devolve no idioma
   pedido e marca o fallback ("disponível em português") em vez de esconder.
5. **Fácil e interativo.** Filtro por tipo, tribo, ano e idioma; busca; player leve que carrega só no clique; estado
   do filtro na URL; funciona em celular.
6. **Conhecimento aberto onde a licença já é aberta**, e só pelo caminho de RPC pública (decisão de arquitetura 6:
   RLS das tabelas não muda).
7. **LGPD.** Zero dado pessoal na superfície anon sem base legal decidida. Iniciativa confidencial (ADR-0105) fica fora
   de toda leitura nova. Vídeo não listado no YouTube fica fora.

## 4. Arquitetura full-stack

### 4.1 Dados: o dono de cada tipo

| tipo | dono | o que falta no dono |
|---|---|---|
| Webinar | `webinars` (CLAUDE.md, decisão 4) | título/resumo `_i18n`; fechar os 6 sem status final (3 `confirmed` e 3 `planned` com data passada) |
| Vídeo, Short | `comms_media_items` (canal youtube) | flag de não listado; vínculo opcional com iniciativa (tribo) |
| Episódio de podcast | **novo canal** `spotify` em `comms_media_items`, ingerido do RSS público pela EF `sync-comms-metrics` | fonte inteira |
| Post Instagram/LinkedIn | `comms_media_items` | nada para listar; os seguidores já existem em `comms_metrics_daily` |
| Artigo | `publication_submissions` (pipeline) | regra única de "publicado" e URL/DOI; decidir o papel de `public_publications` (7 linhas, 0 publicadas) |
| Palestra, congresso, seminário de capítulo | **o card do board** (`board_items`) da tribo, que já é o entregável (ADR-0005) | tipo estruturado (não palavra-chave), local/capítulo, data, link e marca "público" |
| Participação em congresso como iniciativa | `initiatives` do tipo `congress` | marca "público" e resumo `_i18n` |
| Conhecimento do wiki | `wiki_pages` | `visibility` (`members` ou `public`) por página, decidida pelo curador |
| Tribo | `tribes` / `initiatives` | `name_i18n` vazio nas tribos 9 a 15 `[inventário]` |

### 4.2 API (RPCs novas, todas `SECURITY DEFINER`, EXECUTE para `anon`, zero PII)

- `get_public_outputs(p_lang, p_kinds text[], p_initiative_id, p_year, p_search, p_limit, p_offset)`: a lista unificada,
  lida dos donos acima, com título no idioma pedido, `lang_fallback`, URL, provedor do player, data, tribo. Devolve
  também os facets (contagem por tipo, tribo, ano) **da mesma consulta**, para o número e a lista não divergirem.
- `get_public_outputs_summary(p_lang)`: contagem por tipo e um destaque por tipo, para a home.
- `list_public_webinars(p_lang)`: variante pública de `list_webinars_v2`, **sem** organizador e co-gestores
  (`list_webinars_v2` devolve nomes `[inventário]`; não reconceder `anon` a ela).
- `get_public_wiki_pages(p_lang)` e `get_public_wiki_page(p_slug, p_lang)`: só páginas `visibility = 'public'`.
- `/about`: repontar `get_public_impact_data` para os mesmos helpers da home (`v_operational_members`,
  `get_impact_hours_canonical`, `get_chapter_metrics().engaged`). Decidir antes se 3427 h é outra métrica legítima
  (rotular) ou drift (corrigir).

Todas aplicam o portão de confidencialidade (`visibility <> 'confidential'` / `rls_can_see_initiative`) e excluem
vídeo não listado. A nova tool MCP correspondente (ex.: `public_outputs`) lê as mesmas RPCs.

### 4.3 Interface

- **Página da produção** (nome na decisão D3) em `/x`, `/en/x`, `/es/x`: uma ilha com filtros, busca, cards por tipo,
  player leve (miniatura + `youtube-nocookie` só no clique; embed do Spotify só no clique), estado na URL, selo de
  idioma por item, paginação.
- **Home, seção "O que produzimos"** (PR 2 da #2553): um contador por tipo e um destaque por tipo, tudo de
  `get_public_outputs_summary`; destaque de lançamento para a tribo nova; links para a página e para o conhecimento.
- **Conhecimento aberto**: aba ou página com MCP (`/docs/mcp`), CPMAI, governança (34 seções no manual
  `[inventário]`), subconjunto público do wiki e o repo `frameworks`.
- **Menu do visitante**: nenhum item que leve a página vazia (`/library`, `/publications`, `/cpmai` hoje), por
  esconder do visitante ou por abrir um subconjunto (decisão D6).
- i18n: toda chave nova nos 3 dicionários; rotas `/en` e `/es`; LCP sem piora; `prefers-reduced-motion`.

### 4.4 Operação de conteúdo

- **O site entra no plano de comunicação como canal**, com dono (os correspondentes) e um ritual: o que vai para
  LinkedIn, Instagram, YouTube ou Spotify também é marcado como público na plataforma, na mesma semana.
- **Tradução**: título e resumo em en/es por tradução assistida com revisão humana, no dono. Legendas trilíngues pela
  skill `youtube-publicacao` (13 de 101 vídeos hoje `[inventário]`).
- **Marcação de realização**: convenção de tipo para palestra, congresso, seminário de capítulo e artigo publicado,
  registrada pelo líder da tribo no card, com link e data.

### 4.5 Guards (cada um provado por mutação)

- Superfície anon sem PII: as chaves devolvidas por cada RPC nova não incluem nome, e-mail, telefone nem id de membro.
- Confidencial fora: a RPC nova exclui iniciativa `confidential` (ADR-0105).
- Fonte única: a soma dos facets de `get_public_outputs` é igual à contagem de `get_public_outputs_summary`; o
  `/about` e a home dão o mesmo número para pesquisadores, horas, tribos e capítulos.
- Nenhuma lista de realização escrita à mão em `src/` (padrão do #1087).
- Paridade i18n das chaves e das rotas.
- Menu do visitante: nenhum item aponta para página que chega vazia ao `anon`.

## 5. Fases (cada uma é uma PR; banco antes do frontend que o lê)

| fase | entrega | veículos | depende de |
|---|---|---|---|
| F0 | `/webinars` volta a mostrar os replays (`list_public_webinars`) e o menu do visitante para de levar a página vazia | migration + frontend | nada; é defeito, pode ir já |
| F1 | `/about` com os mesmos números da home | migration (`get_public_impact_data`) + guard | PR 1 da #2553 |
| F2 | donos completos: canal `spotify` no sync, tipo estruturado e marca "público" nos cards, `visibility` no wiki, `_i18n` em webinars e iniciativas | migrations + EF | D1, D2, D4, D5 |
| F3 | `get_public_outputs`, `get_public_outputs_summary`, wiki público, tool MCP | migration + EF `nucleo-mcp` | F2 |
| F4 | página da produção, interativa e trilíngue | frontend | F3, D3 |
| F5 | home: reordenação aprovada na maquete + "O que produzimos" (= PR 2 da #2553) | frontend | F3, maquete aprovada |
| F6 | animações leves (= PR 3 da #2553) | frontend | F5 |
| contínuo | tradução de títulos/resumos e legendas; ritual do site no plano de comunicação | operação | F2 |

## 6. Decisões abertas para o GP (antes de executar F2 em diante)

- **D1 Autoria pública.** Mostrar nome de autor de artigo e de palestrante? Autoria publicada é pública por natureza,
  mas a plataforma precisa de base registrada (consentimento ou interesse legítimo). Consultar `legal-counsel`.
- **D2 Wiki público.** Quais páginas viram públicas (a licença CC-BY-4.0 já permite)? Quem decide por página?
- **D3 Nome e rota da página.** "Produção", "Realizações" ou "O que produzimos"?
- **D4 Podcast.** Ingestão automática do RSS ou cadastro manual?
- **D5 Quem registra realizações.** Líder da tribo no card, correspondente de comunicação, ou os dois com revisão?
- **D6 Páginas que chegam vazias ao visitante** (`/library`, `/publications`, `/cpmai`): esconder do visitante ou abrir
  um subconjunto?
- **D7 Horas de impacto.** 3427 (`/about`) contra 2319 (home): uma é outra métrica legítima, ou é drift?

## 7. Riscos

- Uma RPC que une cinco donos fica complexa: um guard de fonte única e testes por tipo evitam que um tipo some calado.
- Tradução sem revisão humana pode publicar erro em en/es: o fallback marcado é melhor que tradução ruim.
- Abrir o wiki expõe conteúdo escrito para membros: a decisão é por página, nunca em massa.
- "Público" marcado por muitas mãos tende a divergir: a marca vive no dono, com trilha de quem marcou.

## 8. Checklist de verificação (formato `/spec`)

- [ ] F0: visitante anônimo vê os webinars concluídos em `/webinars`, `/en/webinars` e `/es/webinars`; nenhum nome de
      organizador no payload anon; nenhum item do menu do visitante chega vazio.
- [ ] F1: `/about` e home iguais em pesquisadores, horas, tribos e capítulos (consulta e guard).
- [ ] F2: cada tipo da tabela 4.1 tem dono e marca "público"; `spotify` aparece em `comms_media_items`.
- [ ] F3: RPCs novas anon-safe (guard de chaves), confidencial fora, facets == summary.
- [ ] F4: filtro, busca, player no clique e estado na URL funcionando nos 3 idiomas; LCP sem piora.
- [ ] F5: a home mostra a contagem e o destaque por tipo a partir de `get_public_outputs_summary`.
- [ ] Toda fase: `./node_modules/.bin/astro build` com exit 0 sem pipe; `npm test` sem falha; mutação em cada guard novo.

## 9. Contraprova em sessão limpa

Abra uma sessão nova neste repositório, sem histórico, e cole:

> Você é o revisor deste plano: `docs/specs/2553-vitrine-producao-e-conhecimento.md` (branch
> `docs/2553-plano-vitrine`). Não implemente nada e não escreva no banco. Faça a contraprova e devolva
> **aprovado**, **aprovado com ajustes** ou **reprovado**, com a lista de ajustes:
> 1. Re-meça, só com leitura, cada número marcado `[re-medido]` e uma amostra dos `[inventário]`. Aponte o que mudou.
> 2. Procure fonte ou capacidade que o plano ignorou: `pg_proc`, tabelas, `supabase/functions`, `scripts/`, tools do
>    MCP. "Não achei na interface" não é "não existe".
> 3. Confira a arquitetura contra o CLAUDE.md e as ADRs 0005, 0007, 0100, 0105, 0106, 0126, 0127 e 0128: dado público
>    só por RPC `SECURITY DEFINER`, sem gate de rota no SSR, confidencial fora, uma fonte por número, sem cópia de dado.
> 4. Para cada pedido do GP da seção 1 (canais, realizações, trilíngue, interativo, conhecimento aberto), aponte a
>    fase, o entregável e o guard que o cobrem. Pedido sem os três é lacuna.
> 5. Verifique a ordem das fases: o banco sai antes do frontend que o lê, e nenhuma fase depende de decisão ainda
>    aberta sem dizer.
> 6. Diga o que está superdimensionado e pode sair, e o que falta para ser plataforma e não página.
