# Handoff - lane Biblioteca de Recursos (13/08/2026)

> Números medidos em 12 e 13/08/2026. **Re-medir antes de usar em decisão, commit ou issue.**
> Esta lane **não é a main lane**: os PRs saem verdes e param.

---

## 1. Entregue

| artefato | estado |
|---|---|
| **PR #1747** correção do arranque obsoleto do #1673 + a #1681 no painel de sessão | **11/11 verde**, `MERGEABLE` |
| **PR #1750** tile da tribo passa a apontar para o catálogo público | **11/11 verde**, `MERGEABLE` |
| **#1748** Biblioteca de Recursos: plano por fases | aberta, 5 comentários |
| **#1749** regra: capacidade de escrita da UI declara se tem rota semântica | aberta |
| **#1751** pipeline de ingestão reporta sucesso sem entregar | aberta |
| **#1046** absorveu a Fase 0 | comentada com os 3 lugares hardcoded |
| **#207**, **#1185**, **#632** | sequenciamento registrado |

Nenhum bypass. Nenhum merge feito por esta lane.

---

## 2. O caso

Um líder de tribo tentou cadastrar uma referência em `Admin > Conteúdo > Biblioteca de
Recursos` (12/08) e recebeu na tela o texto cru da política:

```
Erro: new row violates row-level security policy for table "hub_resources"
```

A RLS agiu certo pela regra dela. O defeito é que a plataforma **o levou até o botão**.

### Propósito da feature

`hub_resources` é `Public-by-design` pelo comentário da própria tabela: alimenta o card da
home e o catálogo público `/library`. **330 linhas, 231 ativas e visíveis a visitante.**

### Quem escreve

`INSERT` e `UPDATE` exigem `can_manage_knowledge()`, que resolve para
`can_by_member(id, 'manage_platform')`: **2 de 79** membros com login. `DELETE` exige
`is_superadmin`.

### ⚠️ Correção de um número que esta lane publicou errado

A issue foi aberta dizendo "**17** veem o menu, 2 conseguem salvar". Isso contava só o
`AdminSidebar` (`permission: 'admin.access'`). Havia um **segundo caminho, sem gate nenhum**:
um tile no painel geral da página de tribo. A cadeia inteira depois dele também não tem gate
(página e ilha), então o alcance real era **qualquer membro logado (79)**, dos quais **77**
são recusados pela RLS.

**A regra que faltou:** antes de afirmar quem alcança uma tela, enumerar **todos** os links
de entrada, não só a navegação.

### O achado que fecha o caso

| `source` | n |
|---|---|
| `bulk-drive-import` | 272 |
| `miro_import` | 51 |
| `whatsapp_extraction` | 7 |

Soma **330**, exata. **Nenhuma linha jamais veio do formulário**, e o último registro é de
**14/03/2026**. O papel `curator` existe no mapa do front com `admin.curation` e tem
**0 pessoas** em `operational_role` e em `designations`, embora `curation_status` já exista.

Uso zero aqui não é imunidade nem desuso: é **capacidade ausente**.

---

## 3. Decisão do PM (12/08), não re-litigar

**Líder de tribo cria pendente, curador publica.** O recurso entra como pendente e só vai ao
catálogo público depois de aprovação.

**E o fluxo tem de ficar explícito no frontend:** texto antes de enviar, confirmação de
"enviado para revisão", estado por item, e a lista do que a pessoa enviou.

---

## 4. As duas armadilhas que invertem a decisão

**a) Os defaults publicam direto.**

| coluna | default |
|---|---|
| `curation_status` | `'published'` |
| `is_active` | `true` |

Ampliar o `INSERT` sem mexer nisso não entrega "cria pendente", entrega **publica na vitrine
pública sem revisão**. A curadoria hoje é rótulo, não porteiro.

**b) O pendente sumiria da tela de quem o enviou.**

A leitura é `(is_active = true) OR can_manage_knowledge()`. Um pendente com
`is_active = false` fica invisível para todo mundo sem `manage_platform`, **inclusive para o
autor**. Pior que o erro atual, que ao menos avisa que falhou.

E `author_id` é anulável, sem default, **nulo em 324 de 330**: não há chave para "meus
envios" nem para notificar quem enviou.

---

## 5. Ordem de implementação

| fase | o quê |
|---|---|
| **0** (→ **#1046**) | menu e servidor falando o mesmo vocabulário de autoridade |
| **1** | carimbar autoria na escrita, ainda com os 2 escritores atuais |
| **2** | trocar `insert` direto por **RPC única, consumida pela UI e pelo MCP** |
| **3** | a **leitura** aceita o pendente **antes** de existir pendente |
| **4** | separar publicar de criar |
| **5** | popular o papel de curador (hoje 0 pessoas) |
| **6+7** | abrir a porta **no mesmo deploy** que entrega a UX |

### O que quebra se a ordem for trocada

| se fizer | antes de | resultado |
|---|---|---|
| 6 (abrir a porta) | 4 (estado) | líder publica direto na vitrine pública |
| 4 (pendente) | 3 (leitura) | o envio some da tela do autor |
| 6 | 5 (curadores) | fila sem atendente |
| 6 | 1 (autoria) | não há "meus envios" nem a quem notificar |
| 6 | 2 (RPC) | o estado pendente fica por conta do cliente |

---

## 6. MCP: leitura nas duas superfícies, escrita em nenhuma

| superfície | tool | modo |
|---|---|---|
| legada | `search_hub_resources` | leitura |
| semântica | `search_nucleo_knowledge` | leitura, agrega `hub` + `wiki` + `knowledge_assets` |

**Zero escrita**, em nenhuma das duas. No mapa de anotações: **24 `SEM_RO`**,
**20 `SEM_WRITE`**, **8 `SEM_DESTRUCTIVE`**. A escrita semântica existe e é madura; o que
falta é cobertura medida.

⚠️ **A RPC da Fase 2 é o substrato compartilhado.** Se nascer só para a UI, a rota MCP depois
reimplementa o portão, que é como se produz duas RPCs para o mesmo ato (#1601).

⚠️ Se a tool nova incluir `withdraw` ou `review(reject)`, ela **inteira** vira
`SEM_DESTRUCTIVE` e puxa o confirm-gate do ADR-0018 (precedente do #1548).

Isso virou a **#1749**: *toda capacidade de escrita da UI declara se tem rota semântica, ou
por que não tem*. O objetivo não é ter tool para tudo; é que "não tem rota" seja **decisão
registrada e não descoberta**.

---

## 7. Gap assessment: seis superfícies de conhecimento

| superfície | linhas | último registro |
|---|---|---|
| `hub_resources` | 330 | 2026-03-14 |
| `wiki_pages` | 151 | 2026-07-17 |
| `knowledge_ingestion_runs` | 53 | **2026-08-10** |
| `knowledge_insights` | 2 | 2026-03-08 |
| `knowledge_assets` | **1** | 2026-03-08 |
| `knowledge_chunks` | **1** | 2026-03-08 |

### #1751: `success` não prova ingestão

| fonte | runs | status | recebidas | gravadas | chunkadas | **receberam ZERO** |
|---|---|---|---|---|---|---|
| `insights` | 51 | 100% `success` | 17 | 2 | 28 | **34** |
| `youtube` | 2 | `success` | 2 | 1 | 1 | 0 |

Os três destinos estão congelados em **08/03/2026** enquanto o pipeline segue rodando e
declarando sucesso. As rodadas somam **29** linhas chunkadas e `knowledge_chunks` tem **1**.
**A causa não foi medida** e não está sendo afirmada aqui.

`search_nucleo_knowledge` consulta `knowledge_assets` (1 linha) a cada busca.

---

## 8. Recomendações aprovadas pelo PM (12/08)

1. **Fundir a Fase 0 com a #1046.** O destino administrativo está hardcoded em **três**
   lugares e `navigation.config.ts`, que é o SSOT, **não tem entrada para ele**. A entrada que
   está no SSOT (`/library`, `minTier: visitor`) é justamente a que se comporta bem.
2. **Corrigir o tile da tribo.** Feito no PR #1750.
3. **Não alimentar antes de consertar.** #207, #1185 e #632 despejam conteúdo numa biblioteca
   sem curadoria viva e com default que publica direto. Foi assim que nasceram as 324 órfãs.
4. **Issue própria para o pipeline.** Feito: #1751.
5. **Decidir se `knowledge_assets` continua no agregador.** Incorporado à #1751.

---

## 9. Higiene de processo desta lane

- 🔴 **A árvore principal esteve o tempo todo no branch de outra sessão**
  (`docs/1590-handoff-ondas-a-b`). Todo trabalho de código saiu de **worktree isolada**, e as
  worktrees foram removidas ao fim. Uma sessão trocou o branch da árvore **no meio de um
  `gh pr create`**, que foi contornado apontando `--head` explícito.
- ⚠️ **`validate` e `check-invariants` demorados no #1750 eram FILA, não defeito.** Os runs
  estavam atrás dos da própria `main` contra o mesmo banco. Assentou 11/11 sozinho, sem
  intervenção. Antes de culpar a mudança, medir.
- ⚠️ **O comentário de código do #1750 não cita o caminho literal que o fix remove.** Um guard
  sobre o fonte cru casaria o próprio comentário e ficaria verde com o defeito de volta.
- 🔒 **Issues e repositório são públicos.** O relator não foi nomeado em lugar nenhum, só o
  papel, que é o que torna o caso reproduzível.

---

## 10. Próximos passos, e de quem são

| item | dono |
|---|---|
| Mergear **#1747** e **#1750** (ambos verdes) | main lane |
| Executar as Fases 1 a 7 da #1748 | a definir |
| Fundir a Fase 0 na **#1046** | a definir |
| Investigar a **#1751** antes de ligar novas fontes | a definir |
| Popular o papel de curador | PM |
| Decidir se `curator` é `operational_role` ou `designation` | PM |
