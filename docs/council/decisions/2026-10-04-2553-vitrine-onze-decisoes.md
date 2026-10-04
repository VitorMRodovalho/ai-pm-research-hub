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
