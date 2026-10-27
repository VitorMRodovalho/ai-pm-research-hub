## Decision: as onze decisoes da vitrine (#2553, #811), ratificadas em bloco

**Date:** 2026-10-04  **Decided by:** PM/GP (Vitor)  **Status:** Accepted
**Fonte:** `docs/specs/2553-vitrine-decisoes.md`, o docket com opcoes, recomendacao, caminho de volta e gatilho por
item, sobre o plano `docs/specs/2553-vitrine-producao-e-conhecimento.md` e a contraprova
`docs/specs/2553-vitrine-contraprova.md`.
**Ratificacao, palavra por palavra:** "ratifico todas".
**Escopo no tempo:** o estado medido em 04/10/2026. O que vier depois nao esta coberto.

### Decision

As onze foram aprovadas **conforme a recomendacao apresentada**.

| # | assunto | desfecho |
|---|---|---|
| **D1** | autoria publica | mostrar autoria de obra publicada e papel institucional (lider, patrocinador), com base registrada por interesse legitimo e canal de oposicao, **condicionado ao parecer do `legal-counsel` antes de F3**; vale tambem para os nomes que ja saem hoje |
| **D2** | wiki publico | abrir pagina a pagina pelo fluxo `wiki_decide` e `wiki_audit`, com a passada de PII antes |
| **D3** | nome e rota | manter a rota `/publications`; titulo "Producao" (en "Our work", es "Nuestra produccion") |
| **D4** | podcast | cadastro manual como produto `podcast_episode`; automatizar se o cadastro ficar mais de um episodio atras por mais de 30 dias |
| **D5** | quem registra | quem ja tem `curate_content`; o correspondente de comunicacao so entra com pessoa nomeada, depois do procedimento de 5 etapas do `V4_AUTHORITY_MODEL.md` |
| **D6** | paginas vazias para o visitante | tirar `/library` do menu do visitante; `/cpmai` com secao explicativa e convite |
| **D7** | horas de impacto | formula da ADR-0100; `/about` com a janela "desde 2019", home no ano corrente; avisar o pmigo-plataforma antes de mudar o numero |
| **D8** | ADR-0099 | seguir: `content_products` e o dono das realizacoes, e o card so aponta |
| **D9** | artigos e publicados | o GP nomeia responsavel e data; artigos ficam fora da vitrine ate ter URL e data |
| **D10** | chave de idioma no banco | chave curta canonica, helper unico que aceita as duas formas na transicao, guard com controle positivo |
| **D11** | Instagram e LinkedIn | so os links dos canais; destaques curados se a medicao de uso no PostHog mostrar visita depois de F4 |

### O que fica pendente

- **D1:** pedir o parecer do `legal-counsel`. E pre-condicao de F3, nao de F0 nem de F1.
- **D9:** o GP nomear o responsavel e a data.

### O que este registro nao decide

A ordem das fases (secao 5 da contraprova) e os itens mecanicos (A2, A3, A5, A9, A12, A15, A16 e A18) seguem ADRs ja
aceitas e entram quando a fase rodar, sem nova ratificacao. Mudar qualquer uma das onze pede emenda a este registro.

### Emenda 1 (2026-10-04)

**Ratificacao, palavra por palavra:** "2. Aceito" (D1) e "3. Concordo." (D9), na mesma mensagem do GP.

- **D1:** o parecer do `legal-counsel` sustenta a opcao (a). Base: legitimo interesse para autor de obra publicada,
  lider de tribo, patrocinador de capitulo e membro palestrante; consentimento para palestrante externo. Travam nomes
  na F3 o LIA por finalidade (assinado pelo encarregado) e a `/privacy` atualizada com canal de oposicao. Ao sair do
  papel, o nome sai da superficie de papel no mesmo dia; autoria de obra publicada permanece. A D1 vale para toda
  superficie publica com nome de pessoa, inclusive a secao de equipe da home. Detalhe no docket, secao "Emenda 1".
- **D9:** a lideranca da iniciativa "Publicacoes & Submissoes" confere os itens, com o Comite de Curadoria revisando,
  ate 2026-10-31. Registro pelo papel, nao pelo nome.
- Os dois pendentes acima ficam resolvidos por esta emenda.

### Emenda 2 (2026-10-06)

**Ratificacao, palavra por palavra:** "em acordo com ambas decisoes" (sync de hora em hora e so titulos) e "em acordo
com a emenda 2, aprovado" (D4), em mensagens do GP no mesmo dia.

- **D4:** o podcast entra pelo RSS publico do Spotify for Creators, de forma automatica, no lugar do cadastro manual
  como `podcast_episode`. O dono do episodio e `comms_media_items`, canal `spotify`, gravado pela EF
  `sync-comms-metrics`; o site le pela RPC `get_public_podcast_episodes`, sem tabela nova. O gatilho da redacao
  original (automatizar se o cadastro ficasse atras) foi antecipado: o canal ja publica e o RSS ja e a fonte.
- **D8 nao muda.** O episodio de podcast e midia do canal, nao realizacao. A F3 decide se um episodio passa a ser
  apontado por `content_products`; ate la, nada liga os dois.
- **Frequencia:** o canal `spotify` sincroniza de hora em hora, so ele, alem da rodada diaria de todos os canais. Le
  so o feed publico, sem token nem cota de API. O agendamento e o job `sync-comms-podcast-hourly`, no minuto 17 de
  cada hora, pela migration `20261007004320_2553_podcast_sync_de_hora_em_hora.sql`; autentica com o header
  `x-sync-secret` (segredo `sync_comms_secret` do vault), o mesmo caminho do job diario, sem a chave de servico.
- **O que sai publico:** titulo, serie, data, duracao, capa e audio de cada episodio. A descricao do episodio e
  gravada no `payload` interno, mas fica fora da RPC publica, porque cita pessoas, inclusive convidado externo:
  entra na pagina so depois que as travas da D1 (LIA assinado e `/privacy` com canal de oposicao) estiverem cumpridas
  e houver consentimento do convidado externo. O autor do item no feed nao e lido.
- O guard `tests/contracts/2553-podcast-publico.test.mjs` afirma as chaves publicas exatas do episodio e que o autor
  do item nao e lido.

### Emenda 3 (2026-10-26)

**Ratificacao, palavra por palavra:** "no item 1 sim, pode usar o termo" (o card de cada linha), "todos os grupos
quem assinou a clausula", seguido de "em acordo" com os quatro ajustes da orquestradora (a fileira de rostos de "Quem
faz"), e "segue pelo caminho A" (o consentimento de quem assinou versao anterior), em mensagens do GP no mesmo dia.

- **D1:** o card de cada linha de pesquisa e a fileira de rostos de "Quem faz", na home, passam a se apoiar no
  consentimento da Clausula 11 do Termo de Adesao ao Servico Voluntario (art. 7o, I, da LGPD), e nao no legitimo
  interesse. O filtro e por pessoa, pela decisao explicita mais recente registrada em `consent_records`
  (`image_voice_publicity`), o mesmo registro que a liberacao de comunicacao ja le: autorizacao ativa vale sim,
  revogacao vale nao; sem decisao registrada, vale o termo assinado na versao que traz a clausula. A fonte unica e
  `_member_has_image_consent`. O nome vai com a imagem, como parte da divulgacao do trabalho voluntario. Caminho A:
  quem assinou versao anterior da o consentimento no perfil, vendo o texto da Clausula 11, pelas funcoes do registro que
  ja existem; o termo nao e reemitido. A revogacao e feita no perfil a qualquer momento; autorizar de novo depois de
  revogar grava uma linha nova, e o registro nunca e apagado. Como a base deixa de ser o legitimo interesse, o card e a
  fileira saem da trava do LIA da Emenda 1. O caminho do legitimo interesse continua valendo para nome sem imagem, onde
  se aplica (autoria de obra publicada, papel institucional sem foto), com as travas da Emenda 1.
- **D3 da home v2** (citada no codigo como de 20 e de 21/10/2026: gestao e liderancas so em contagem na virada):
  emendada. Em "Quem faz", cada grupo mostra ate oito rostos (foto e nome) de quem consentiu e um "+N" que e a
  contagem da home menos os rostos mostrados. Os pesquisadores que consentiram aparecem com rosto na fileira publica;
  os demais, so na contagem. As presidencias e os pontos focais dos capitulos nao sao voluntarios do termo: aparecem
  pelo nome do capitulo, sem rosto. A taxonomia em quatro grupos nao esta decidida; a fileira usa os sete grupos que a
  home ja conta.
- **Foto:** so o objeto de nome opaco (`avatars/<32 hex>`) do bucket publico de fotos de membro; qualquer outro
  endereco sai sem foto, seja qual for a ordem de merge com a troca para nomes opacos.
- **Saida:** na revogacao ou ao deixar o papel, o nome, a foto e o video saem no mesmo dia (leitura ao vivo, sem cache
  alem do minuto do servidor).
- Os guards `pertencimento-consentimento-clausula-11` e `2553-home-v2-virada` (teste E, emendado) afirmam a regra.
