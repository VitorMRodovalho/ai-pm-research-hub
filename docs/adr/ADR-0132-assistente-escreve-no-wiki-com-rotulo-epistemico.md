# ADR-0132 - O assistente escreve no wiki pelas mesmas funções da tela, com rótulo epistêmico, e não aprova

**Status:** Accepted (2026-09-29)
**Ratificado por:** decisão do dono, resposta literal às três recomendações - *"Concordo com as recomendações"*.
**Relacionadas:** ADR-0129 (autoria na plataforma; emendas 2 e 3), ADR-0018 (ameaças do MCP), ADR-0011 (autoridade nas RPCs), ADR-0010 (o wiki é narrativo e não pessoal), [#2495](https://github.com/VitorMRodovalho/ai-pm-research-hub/issues/2495), [#2262](https://github.com/VitorMRodovalho/ai-pm-research-hub/issues/2262).

---

## Contexto

Medido em 29/09/2026:

- **O MCP só lê o wiki.** São 7 ferramentas de leitura (`search_wiki`, `get_wiki_page`, `search_wiki_pages`,
  `get_wiki_health`, `wiki_health_report`, `knowledge_search_text`, `knowledge_assets_latest`) mais a intenção
  `search_nucleo_knowledge` (modos `search`, `page`, `latest`). Nenhuma das funções de autoria (rascunho, envio,
  decisão, auditoria, sugestão, filas) está exposta: 0 ocorrências no `nucleo-mcp`.
- **A decisão de 26/09 (#2495, item 2) já pedia a escrita pelo assistente:** membros propõem "pela plataforma e pelo
  assistente, sem precisar de GitHub"; cada proposta leva um **rótulo epistêmico** (fonte, observação de membro,
  síntese de IA, pesquisa externa); a IA rascunha, resume, liga e aponta contradição, **mas não aprova**.
- **A #2262 pediu as duas superfícies ao mesmo tempo**, para que quem trabalha pelo assistente não fique de fora.
  A entrega saiu só na tela (piloto, fase B1, iniciativas, sugestões).
- **O rótulo epistêmico não está modelado** em nenhuma tabela, função ou tela.
- **O piloto já está em uso:** em 29/09 duas lideranças escreveram e o comitê publicou as páginas da Tribo 4 e do
  Grupo de Estudos CPMAI.

## Decisão

### 1. Uma intenção de escrita no MCP, sobre as mesmas funções da tela

A intenção semântica `wiki_write` tem quatro modos, cada um chamando a RPC que a tela já usa, com os mesmos portões:

| modo | função | o que faz |
|---|---|---|
| `context` | `wiki_authoring_context`, `wiki_review_queue`, `wiki_suggestion_queue` | onde a pessoa pode escrever, suas versões abertas e suas sugestões |
| `draft` | `wiki_save_draft` | cria ou atualiza o rascunho; uma versão aberta por pessoa e por página (#2519) |
| `submit` | `wiki_submit` | envia a versão para quem decide |
| `suggest` | `wiki_suggest` | sugere melhoria numa página |

Nenhuma autoridade nova: quem não escreve na tela não escreve pelo assistente.

### 2. Aprovar, devolver, auditar e responder sugestão continuam só na tela

`wiki_decide`, `wiki_audit` e `wiki_suggestion_decide` **não** entram no MCP. Quem confirma no assistente ainda é uma
pessoa, mas manter a decisão na tela deixa "a IA não aprova" sem ambiguidade.

### 3. Toda escrita pelo assistente é em duas chamadas

Cada modo que grava devolve primeiro uma **prévia** (o que será gravado, em qual página, quem vai decidir, com qual
rótulo) e só executa com `confirm: true` (ADR-0018 D2.1). O conteúdo do wiki é exatamente o que uma injeção vinda de
outro MCP tentaria plantar, então a regra vale para toda escrita, não só para a destrutiva. As descrições das
ferramentas são texto fixo (D2.3), e as respostas passam pela marca de dado não confiável (#1619).

### 4. O rótulo epistêmico entra agora, na versão da página

Cada versão leva um rótulo, obrigatório:

| rótulo | quando |
|---|---|
| `fonte` | o texto é derivado de uma fonte citada (documento, ata, webinar) |
| `observacao_membro` | relato ou análise de quem escreve |
| `sintese_ia` | síntese produzida por IA |
| `pesquisa_externa` | resultado de pesquisa fora do Núcleo |

Na tela, quem escreve escolhe; o padrão é `observacao_membro`. Pelo assistente, o padrão é `sintese_ia`, e a pessoa
pode declarar outro explicitamente. O rótulo aparece na página publicada e volta para o assistente na leitura, para
que quem lê, gente ou IA, saiba a natureza do conteúdo.

### 5. Ordem

Construído antes do lançamento do piloto para as lideranças, como a #2262 pedia.

## Consequências

- A versão da página e a página publicada ganham o rótulo; `wiki_save_draft` ganha o parâmetro (troca de assinatura:
  `DROP` + `CREATE`, com o `GRANT` de volta); as leituras do wiki (tela e MCP) passam a devolvê-lo.
- O editor da tela ganha o seletor do rótulo, e a página, o selo.
- O MCP ganha uma intenção de escrita com prévia e confirmação; a contagem de prévias sem execução já alimenta a
  detecção de anomalia (ADR-0018 D3.2).

## Alternativas rejeitadas

- **Expor decisão e auditoria pelo assistente, com confirmação.** Rejeitada pelo dono em 29/09: a decisão fica na tela.
- **Rótulo opcional.** O objetivo é tornar visível o que é síntese de IA; opcional vira ausente.
- **Uma ferramenta por ação.** A camada semântica agrupa por intenção, com modos; ferramentas soltas multiplicam
  descrição, portão e teste sem ganho.
