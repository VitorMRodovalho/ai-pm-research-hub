# Contraprova do plano da vitrine (#2553, #811)

**Data:** 04/10/2026. **Revisor:** sessão limpa `d4a3d38d`, que não leu o pacote da PR 1 antes desta revisão.
**Objeto:** `docs/specs/2553-vitrine-producao-e-conhecimento.md` no commit `908faf0a`. Nada foi implementado e
nada foi escrito no banco: as consultas rodaram nesta sessão, em transação somente leitura. Número aqui também é
relógio: re-meça antes de executar.

## Veredito

- **F0 e F1: aprovado com ajustes** (A1 a A5). Podem seguir sem esperar o resto do plano.
- **F2 a F5: reprovado na forma atual.** Três motivos, em ordem de peso:
  1. A tabela 4.1 põe palestra, congresso e seminário de capítulo no card do board, com tipo estruturado, link e
     marca "público". É a alternativa A da **ADR-0099** (Accepted), rejeitada em §4.1 dela: `board_items` é
     rastreio operacional, e o produto derivado tem dono próprio, `content_products`. O plano não cita nem a ADR
     nem a tabela.
  2. O plano propõe `get_public_outputs` e uma página nova sem citar a superfície pública que já existe para isso:
     `/publications`, com filtro por tipo, busca, rotas `/en` e `/es` e feed RSS (`src/pages/publications/feed.xml.ts`),
     lendo `get_public_publications`, que o `anon` já executa. Ela sai vazia por falta de dado, não de permissão.
  3. Parte do diagnóstico está errada de um jeito que muda o desenho: há conteúdo trilíngue em muito mais tabelas
     do que o plano diz, em duas convenções de chave incompatíveis, e a tradução das tribos 9 a 15 já existe, só que
     escrita à mão em `src/`.

Reescrever 4.1, 4.2 e a tabela de fases sobre os donos existentes (A6 a A18) antes de executar F2.

## 1. Re-medição

| item | plano | agora | |
|---|---|---|---|
| webinars | 12; 6 concluídos, os 6 com YouTube | 12: `completed` 6, `confirmed` 3, `planned` 3; 6 concluídos com YouTube | igual |
| webinars sem status final | 3 `confirmed` e 3 `planned` com data passada | os mesmos 6 (3 em abril, 3 em maio) | igual |
| `list_webinars_v2` para `anon` | sem EXECUTE | sem EXECUTE; `/webinars` chama com a chave anon no SSR | igual |
| vídeos do YouTube sincronizados | 98 | **99** (sync de hoje, 06:00 UTC); `payload` nulo nos 99 | mudou |
| Instagram / LinkedIn | 89 / 56 | 89 / 56 | igual |
| blog | 13 publicados, último em 18/07 | 13 publicados (13 de 13 com título em en e es), 1 rascunho, último em 18/07 | igual |
| `publication_submissions` | 37 (21, 8, 6, 2) | 37: `under_review` 21, `submitted` 8, `published` 6, `draft` 2; **0 de 37 com `doi_or_url`** | igual |
| `public_publications` | 7, 0 publicadas | 7, 0 publicadas: são os 7 artigos do ProjectManagement.com, cada um com par em `publication_submissions` no estado `submitted`; nenhum com URL nem data | igual |
| iniciativas `congress` | 6 | 6 | igual |
| wiki | 19 páginas, leitura só `authenticated` | 19; CC-BY-4.0 em 17, sem licença em 2; origem `nucleo-ia-gp/wiki` e `plataforma`; **o repo é privado** | igual |
| biblioteca | 229 ativos | 229 de 330; 11 deles do tipo `certificate` | igual |
| `event_showcases` | não medido | 41 | novo |
| `/about` contra home | pesquisadores 100/76, horas 3427/2319, tribos 15/13, capítulos 5, eventos 620/650 | mesmos números. Mas o 100 é rotulado **"Colaboradores Ativos"**, e `get_public_impact_data` já devolve `chapters_engaged` = 15 | rótulo errado no plano |
| campos trilíngues no banco | "só `events.title_i18n` e `tribes.name_i18n`" | também `tribe_deliverables.title_i18n`/`description_i18n` (71 de 71 preenchidos), `publication_series`, `blog_posts.title`/`excerpt`/`body_html`, `help_journeys.title`, `tribes.quadrant_name_i18n` e outros | **errado** |
| tribos 9 a 15 sem en/es | sim | sim no banco; **existem** nos 3 dicionários (`data.tribe15.name` etc.), via `src/data/tribes.ts` | incompleto |
| listas de `get_public_impact_data` | partners 11, timeline 4, recognitions 1, tribes_summary 15, chapters_summary 5, recent_publications 0 | iguais. `timeline` e `recognitions` são literais no corpo da função | igual |
| amostra do `[inventário]` | | `list_webinars_v2` devolve id e nome de co-gestores; `get_cpmai_course_dashboard` devolve "Not authenticated"; tribo 15 criada em 02/10 | confirmados |

Não re-medidos: 101 vídeos no canal, 13 legendas trilíngues, 7 episódios no Spotify, 26 cards por palavra-chave,
plano de comunicação no Drive, 34 seções do manual, idioma das descrições das tools do MCP.

## 2. O que o plano ignorou

1. **`content_products` e a ADR-0099.** 37 produtos (31 `under_review`, 6 `published`), um para cada submissão, com
   enum de instrumento que já cobre `pmi_global_conference`, `academic_conference`, `pmi_chapter_event`,
   `podcast_episode`, `youtube_video`, `magazine_article`, `linkedin_newsletter` e outros; status com `published`;
   `published_at`; `initiative_id`; `target_language_policy`; ponte `board_items.content_product_id` (8 cards
   ligados); leitores `list_content_products` e `get_content_product_reader` (só membro, com portão de
   confidencialidade). A ADR também prevê a biblioteca de produtos para membro (§2.8), ainda não construída.
2. **`/publications`, `get_public_publications`, `public_publications` e o feed RSS**: a vitrine de artigos,
   frameworks e gravações de webinar (tipos da página) que já existe.
3. **`tribe_deliverables`**: 71 entregáveis por iniciativa, trilíngues, com `list_initiative_deliverables`.
4. **Pipeline editorial**: `publication_ideas` (3), `propose_publication_idea` (com `p_target_languages` e
   `p_proposed_channels`), `fork_idea_to_channel`, `publication_series` (6 séries ativas, entre elas
   `frontiers-newsletter` e `cpmai-journey`) e a newsletter da ADR-0021.
5. **`get_webinars_count(..., 'realized')`**: o número canônico de webinars da ADR-0100, que o `anon` já executa
   (hoje 6).
6. **Fluxo de publicação do wiki**: `wiki_decide` (publicar ou devolver), `wiki_audit` (manter ou despublicar),
   papéis de autor e de liderança, e detector de PII (`_wiki_pii_detail`, `get_wiki_health`).
7. **Contadores internos de produção**: o bloco "output" de `get_chapter_dashboard`, "knowledge produced" de
   `exec_cycle_report` e as publicações de `get_comms_dashboard`. A vitrine pública vai contar a mesma coisa.
8. **Infra pronta**: PostHog no `BaseLayout`, sitemap (`@astrojs/sitemap`), feeds RSS de `/publications` e `/blog`,
   `get_weekly_member_digest` com seção de publicações, `tests/browser-guards.test.mjs`, o gateway `/semantic` do
   MCP e o gatilho `trg_auto_comms_on_publish` (card publicado cria card de comunicação).
9. **O que já sai com nome para o `anon`**: `get_public_impact_data` devolve nome de líder de tribo
   (`tribes_summary.leader_name`), de patrocinador (`chapters_summary.sponsor`) e autores
   (`recent_publications.authors`); `get_public_publications` devolve `authors`.

## 3. Arquitetura contra o CLAUDE.md e as ADRs

| referência | o plano | ajuste |
|---|---|---|
| ADR-0005 | `p_initiative_id` nas RPCs novas | `get_public_publications` ainda usa `p_tribe_id`: trocar ao reusá-la |
| ADR-0007 | D5 pergunta qual papel registra | autoridade é ação do `can()`; `curate_content` (ADR-0087) já existe |
| ADR-0010 | wiki aberto "pela licença" | wiki é narrativo; páginas de tribo carregavam roster: PII antes de abrir |
| ADR-0099 | card do board como dono de palestra e congresso | dono é `content_products` (A6) |
| ADR-0100 | D7 aberta; F1 "repontar" | fórmula de horas já decidida; datas literais proibidas (A4, A5) |
| ADR-0105 | portão nas RPCs novas | `get_public_publications` não aplica o portão hoje |
| ADR-0106 | SSR anon com dado público | conforme |
| ADR-0126 | home e `/about` no mesmo número | o `/about` mostra o Tema A; a ADR reserva o A para admin e analytics |
| ADR-0127/0128 | não citadas | `chapters_summary` conta membro por `members.chapter` (texto livre) e lista 5 capítulos ao lado de um contador de 15 |
| CLAUDE.md, decisão 4 | `webinars` como dono | conforme |
| CLAUDE.md, decisão 6 | zero PII no `anon` | o substrato que o plano manda reusar já devolve nomes (A17) |

## 4. Pedidos do GP: fase, entregável e guard

| pedido | fase | entregável | guard | situação |
|---|---|---|---|---|
| webinars | F0 | `list_public_webinars` + `/webinars` | chaves do payload | coberto, com A2 e A3 |
| YouTube | F2 a F4 | flag de privacidade, leitor, página | nenhum para não listado | lacuna (A15) |
| Instagram e LinkedIn | nenhuma | 4.1 diz "nada falta" e nenhuma fase os mostra | nenhum | **lacuna**: entram como feed ou ficam como link de canal? |
| Spotify | F2 (D4) | canal no sync | nenhum | parcial; com A6, episódio pode ser produto `podcast_episode` |
| plano de comunicação | contínuo (4.4) | site como canal | nenhum | **lacuna**: operação sem dono nem data; ou ganha dono, ou sai do escopo |
| tribo nova | F5 | destaque de lançamento | nenhum | **lacuna**: sem regra de dado; derivar de `initiatives.created_at`, nunca texto fixo |
| congressos, artigos, seminários | F2 a F4 | tipo no card | fonte única | **reprovado**: dono errado (A6); artigo não tem fase |
| trilíngue | F2, F4 | `_i18n` em webinars e iniciativas | paridade de chaves de **interface** | **lacuna**: nenhum guard de dado (A11); hreflang: 0 arquivos em `src/` hoje |
| fácil e interativo | F4 | ilha com filtro, busca e player | checklist manual | parcial: automatizar no browser guard e medir uso no PostHog |
| conhecimento aberto | 4.3, sem fase | página de conhecimento | nenhum | **lacuna**: nenhuma fase entrega a página; CPMAI público não tem entregável |

## 5. Ordem das fases

- **F0 depende de D6 sem dizer** (o menu do visitante). Separar (A1).
- **F1 depende de D7** (está em 4.2 e falta na linha de F1) e do aviso ao pmigo-plataforma (#2365). Com A4, D7 se
  reduz a janela e rótulo.
- **F3 depende da decisão "uma fonte pública, não duas"** (4.2), que não está na lista D nem na linha de F3 (A10).
- **F2 é um pacote de cinco coisas independentes** (Spotify, tipo no card, visibilidade do wiki, `_i18n` de
  webinars e de iniciativas), e F3 espera o pacote inteiro. Com A6 e A14, F3 começa com os donos que não precisam de
  nada novo (webinars concluídos, blog, produtos publicados com URL) e cada enriquecimento vira PR própria. A home
  (F5) deixa de esperar o podcast.
- **F2 e F3 têm Edge Function**, um terceiro veículo, publicado à mão. A tabela só diz "banco antes do frontend".
  A ordem é migration → EF e backfill → RPC → frontend (A15).
- A seção 10 manda "escrita curada por tema" e "botão de copiar do MCP" para F6, que é animação (PR 3 da #2553).

## 6. Superdimensionado, e o que falta para ser plataforma

**Pode sair:** busca e paginação no servidor para algumas centenas de itens (A9); marca "público" em todo dono
(A14); tipo estruturado no card (A6); tool MCP nova (A18); boletim por pipeline e retrato da semana (seção 7 abaixo).

**Falta:** dono por tipo amarrado às ADRs (A6, A10); "realizações publicadas" no dicionário da ADR-0100 (A16);
helper único de idioma com guard de dado (A11); um detector de qualidade, porque realização publicada sem URL não
pode aparecer e hoje são 0 com URL de 6 publicadas (A8); medição de uso no PostHog; hreflang e dados estruturados
(o sitemap já existe); autoridade pelo `can()` (A14).

## 7. Seção 10 (referência externa)

- **Entra, com fase:** molde único de página e "próximos passos" no fim (F4); número ao lado do que prova (sai de
  graça com A9); player só no clique (F4); hreflang nas 3 versões (F0 ou F4, como entregável com guard, não
  "contínuo"); botão de copiar em `/docs/mcp` (PR pequena, a qualquer momento).
- **Entra como conteúdo**, com dono na comunicação e fora das PRs de plataforma: transparência explícita,
  expectativa antes do contato, o papel de cada canal, diagrama do ciclo, faixa final com missão.
- **Não cabe agora:** retrato real da semana (a agenda tem nome de gente e repete os contadores da home); boletim
  por pipeline (já existem os feeds RSS, `get_weekly_member_digest` e a newsletter da ADR-0021; vira issue própria
  depois de F3). "Escrita curada por tema" já tem dado em `publication_series` e nos domínios do wiki.

## 8. Ajustes

**F0**
- **A1.** Separar a correção de `/webinars` (não depende de nada) do menu do visitante (depende de D6). Recomendação
  para D6: esconder `/library` do visitante (entre os 229 ativos há 11 certificados, dado pessoal, e a maior parte é
  documento interno) e mostrar em `/cpmai` uma seção explicativa com convite para entrar, nunca o painel.
- **A2.** O guard do payload anônimo vira **lista de chaves permitidas**. `webinars` tem `meeting_link`, `notes`,
  `briefing_doc_url` e `promo_kit_url`, que não são "nome, e-mail, telefone ou id" e também não podem sair. Chave
  nova reprova até alguém revisar.
- **A3.** O número de webinars sai de `get_webinars_count(..., 'realized')`. Se a lista mostra só os que têm
  replay, o rótulo diz isso: número e lista nunca usam predicados diferentes em silêncio.

**F1**
- **A4.** A ADR-0100 já decide a **fórmula** das horas. As 3427 do `/about` somam `duration_minutes` de toda
  presença desde sempre, sem `duration_actual` e sem excluir justificada: é reimplementação inline. As 2319 da home
  são `get_impact_hours_canonical()`, cuja janela padrão é o ano corrente. O GP decide só a **janela** e o rótulo,
  e o `/about` chama o mesmo primitivo com ela.
- **A5.** O 100 do `/about` é o Tema A da ADR-0126 (`is_active AND current_cycle_active`); recomendo o Tema B, com o
  rótulo da home. Os 620 (`'2026-03-01'`) e os 650 da home (`'2026-01-01'`) são dois literais de data, os dois
  vedados pela ADR-0100 §2.1: corrigir os dois. `tribes` conta as 15 linhas de `tribes`, inclusive as 2 inativas.
  Para capítulos, basta o `/about` ler `chapters_engaged`, que já existe, sem mudar o contrato do pmigo-plataforma.
  Os rótulos do `ImpactPageIsland` estão escritos no componente, fora dos 3 dicionários: F1 os move.

**F2 em diante**
- **A6. Dono das realizações é `content_products`.** "Publicado" é `status = 'published'` com URL em
  `publication_metadata` (ADR-0099 §2.6); o card liga ao produto por `board_items.content_product_id`. Sair de 4.1 o
  tipo e a marca no card. Se o GP quiser outro dono, o caminho é emendar a ADR-0099, não contorná-la.
- **A7. Evoluir `/publications`, não criar `/x`.** `get_public_publications` passa a ler os produtos publicados, com
  o portão de confidencialidade e `p_initiative_id`; a página e o feed viram a vitrine, e D3 vira "renomear ou não".
  `public_publications` se aposenta depois de migrar o que for verdade.
- **A8. Verdade antes da vitrine.** Os 7 artigos do ProjectManagement.com estão em três tabelas com três estados, e a
  timeline escrita no corpo de `get_public_impact_data` diz "7 artigos submetidos". Nenhum tem URL nem data. Os 6
  produtos `published` têm 0 URL e a mesma data de backfill (10/03/2026). Alguém precisa dizer o que foi publicado e
  onde: é tarefa de dado com dono, não de arquitetura.
- **A9. Uma consulta, dois invólucros.** Uma função interna, não exposta, projeta os itens públicos dos donos; a lista
  (com facets calculados das mesmas linhas) e o resumo da home são invólucros finos dela. "Facets igual a summary"
  vira verdade por construção, e o guard afirma que os dois invólucros chamam a mesma função. Filtro, busca e
  paginação no cliente, com estado na URL.
- **A10. `get_public_impact_data` vira fachada**: cada campo chama o primitivo canônico ou o leitor público do dono,
  sem consulta própria (ADR-0100 B). Isso fecha "uma fonte pública, não duas". `timeline` e `recognitions` são
  literais na função (a timeline está velha, #2365); reconhecimento é realização, pedido da #811, e falta na tabela
  4.1: precisa de dono, ou sai do contrato com aviso ao pmigo-plataforma.
- **A11. Convenção de idioma antes de F2.** `tribes`, `events`, `tribe_deliverables`, `publication_series` e
  `help_journeys` usam `pt`/`en`/`es`; `blog_posts` usa `pt-BR`/`en-US`/`es-LATAM`; `normalize_platform_language()`
  devolve a forma longa. Um leitor ingênuo devolve fallback para tudo que usa chave curta. Um helper único de escolha
  de idioma com marca de fallback, e um guard com controle positivo: item com chave `en` volta em inglês para
  `p_lang = 'en-US'`. Corrigir a seção 2 do plano.
- **A12. Tribos 9 a 15: migrar, não traduzir.** Nome, descrição e entregáveis em en e es estão nos dicionários
  (`data.tribeN.*`), via `src/data/tribes.ts`, lista escrita à mão em `src/` (contra o princípio 1 do plano) que
  também guarda nome de líder. Levar para `tribes.name_i18n` e `tribe_deliverables` e aposentar o arquivo, em vez de
  criar uma terceira cópia.
- **A13. Wiki pelo fluxo que existe.** O repo é privado; CC-BY-4.0 é declaração por página, e declarar licença não é
  decidir publicar. D2 vira: quem marca público dentro de `wiki_decide`/`wiki_audit`, com a passada de PII como
  pré-condição.
- **A14. Marca "público" só onde falta estado público.** Produto tem `published`; webinar tem `completed` com
  replay; mídia de canal já é pública no canal e só precisa excluir não listado. Só o wiki precisa de decisão nova.
  D5 deixa de ser lista de papéis: é ação do `can()`, e `curate_content` já existe.
- **A15. Filtro de não listado falha fechado.** Hoje não há coluna de privacidade e o `payload` é nulo nos 99
  vídeos. Se a coluna nascer nula e o filtro for `IS DISTINCT FROM 'unlisted'`, tudo passa até o backfill. Exigir
  `= 'public'`, e fazer o backfill antes de a vitrine ler.
- **A16. Uma fonte por número também para dentro.** Registrar "realizações publicadas" no dicionário da ADR-0100 e
  fazer a vitrine, `get_chapter_dashboard`, `exec_cycle_report` e `get_comms_dashboard` lerem o mesmo primitivo.
- **A17. D1 cobre o que já sai.** O guard "sem nome" do plano, aplicado à fachada, reprova no primeiro dia (seção 2,
  item 9). D1 vale para essas chaves (base registrada ou retirada), e uma exceção aprovada entra como dado no guard,
  não como comentário.
- **A18. MCP:** um modo numa ferramenta do gateway `/semantic` (catálogo em `docs/reference/SEMANTIC_TOOL_CATALOG.md`),
  não uma tool crua nova. O MCP é só para membro, então ali "público" quer dizer "o que a vitrine mostra".

## 9. Decisões para o GP, revisadas

- **D1** autoria: vale também para o que já sai (A17).
- **D2** wiki: dentro do fluxo existente, com PII antes (A13).
- **D3** nome e rota: evoluir `/publications` ou renomear (A7).
- **D4** podcast: produto `podcast_episode` ou canal `spotify` no sync.
- **D5** quem registra: resolvida pela ADR-0099 com `curate_content`; resta decidir se o correspondente de
  comunicação recebe a ação.
- **D6** páginas vazias: recomendo esconder `/library` e dar a `/cpmai` uma seção explicativa (A1).
- **D7** horas: só janela e rótulo (A4).
- **D8 (nova)** seguir a ADR-0099 (recomendado) ou emendá-la.
- **D9 (nova)** o que é verdade sobre os 7 artigos do ProjectManagement.com e os 6 "publicados" (A8), e quem
  completa URL e data.
- **D10 (nova)** convenção de chave de idioma no banco (A11).
- **D11 (nova)** Instagram e LinkedIn entram na vitrine ou ficam como link de canal.
