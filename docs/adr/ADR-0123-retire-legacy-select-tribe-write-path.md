# ADR-0123 - Aposentadoria do write-path legado select_tribe / deselect_tribe

**Status:** Accepted (2026-07-09)
**Relacionado:** #1247 (auditoria da jornada de entrada em tribo) · #1248 (fix do picker da landing) · #1138 (MCP do fluxo híbrido, gap) · #1249 (testes de roster frágeis) · memória `reference-tribe-selection-hybrid-journey` · PRs #793/#794/#795 (fluxo híbrido vivo)

## Contexto

A plataforma tem duas superfícies de entrada em tribo, e a legada é um write-path perigoso:

1. **Legado (`select_tribe` / `deselect_tribe`):** grava `members.tribe_id` via `tribe_selections` + trigger `sync_tribe_id_from_selection`, **sem criar engagement e sem aprovação do líder**. Nasceu do modelo de seleção em lote (deadline `home_schedule.selection_deadline_at`), anterior ao Domain Model V4.
2. **Vivo (híbrido, contínuo):** `request_tribe_assignment` (pedido) -> `review_tribe_request` do líder (aprovação) -> cria `engagements` -> trigger `_sync_tribe_id_from_engagement` grava `members.tribe_id`. Fonte de autoridade correta no V4 (engagement e o primitivo).

No kickoff do Ciclo 4 (2026-07-09), vários pesquisadores relataram "Erro ao selecionar" ao usar o picker da landing (`TribesSection.astro`), que chamava `select_tribe`. A auditoria #1247 (grounding ao vivo) apurou que o erro era um composto, não só o deadline:

- O frontend engolia a mensagem descritiva da RPC e pintava o toast genérico `tribes.errorSelect` = "Erro ao selecionar" para QUALQUER falha.
- Falhas reais no kickoff: tribo lotada (tribos 1, 4, 6, 8 estavam em 7/7, limite = 7), termo de voluntário não assinado, e possivelmente deadline (que no momento da auditoria já estava estendido para 2026-07-18, aberto).

Consequência arquitetural mais grave: o write-path legado produziu **12 memberships fantasma** (pesquisadores C4 com `members.tribe_id` setado mas SEM engagement V4), reconciliados na mesma sessão (engagement retroativo, drift 13 -> 1, restando apenas 1 chapter_liaison esperado).

O PR #1248 já cortou o write-path do botão da landing (passou a redirecionar para `/workspace`). Faltava cortar as demais superfícies de escrita.

## Decisão

Aposentar o write-path legado de seleção de tribo, mantendo a RPC no banco.

1. **Tools MCP `select_tribe` e `deselect_tribe` RETIRADAS** (`supabase/functions/nucleo-mcp/index.ts`). Eram os últimos consumidores de escrita do legado alcançáveis por um agente. O fluxo vivo (`request_tribe_assignment`) ainda NÃO tem tool MCP (gap #1138); a assimetria e assumida conscientemente ate #1138.
2. **Entradas removidas do `src/lib/mcp-manifest.json`** (`select_tribe`, `deselect_tribe`).
3. **Strings i18n órfãs removidas** nas 3 línguas (`tribes.errorSelect`, `tribes.selectedSuccess`) e no `TRIBES_MSG` do `TribesSection.astro` (inalcançáveis após o corte do write).
4. **RPCs `select_tribe` / `deselect_tribe` / `sync_tribe_id_from_selection` NÃO são dropadas.** A migration `20260805000216` marca `select_tribe` como "LEGACY (frozen) - do NOT drop without a deprecation ADR": este e o ADR. Dropar exigiria remover o trigger `trg_sync_tribe_id` e migrar/limpar `tribe_selections` (43 linhas, 7 divergentes de `members.tribe_id`), fora do escopo do estanca-sangramento. Ficam inertes: sem superfície de escrita, ninguem mais as invoca.
5. **`count_tribe_slots` MANTIDA.** E read-only (telemetria de ocupação por `members.tribe_id`), consumida pela vitrine da landing para pintar vagas. Não é write-path nem gera fantasma; remover degradaria a vitrine sem ganho de segurança.

## Alternativas rejeitadas

- **Drop total das RPCs legadas agora.** Rejeitada: exige desmontar o trigger de sync e uma migração de dados de `tribe_selections`, com risco em plena virada C4. O ganho (higiene) não justifica o risco no momento; as RPCs inertes não são footgun sem superfície de escrita.
- **Reabrir o deadline de `select_tribe` como caminho oficial.** Rejeitada: mantém o defeito de raiz (membership sem engagement nem aprovação do líder), que é justamente o que produziu os 12 fantasma.
- **Carve-out no `TribesSection` mantendo o botão escrever direto.** Rejeitada pelo #1248: a landing deve rotear para o fluxo vivo, não ser uma segunda fonte de escrita.

## Consequências

- Nenhuma superfície de escrita de tribo passa por fora do modelo V4. Novo membership de tribo só nasce de `request_tribe_assignment` -> `review_tribe_request` -> engagement (ou dos caminhos admin `admin_*_tribe`, que são governados).
- **Gap remanescente (#1138):** o fluxo híbrido vivo não tem tool MCP. Um agente que precise "entrar em tribo" via MCP não tem mais o atalho legado (bom: era quebrado) nem um substituto vivo (pendente). Priorizar a tool `request_tribe_assignment` no #1138.
- **Bug legado conhecido (não corrigido de propósito):** `deselect_tribe` fazia `DELETE FROM tribe_selections`, mas o trigger de sync só dispara em INSERT/UPDATE, então `members.tribe_id` ficava preso. Com a tool retirada e a RPC inerte, o bug não tem mais superfície de disparo; sera resolvido junto do drop futuro das RPCs, se e quando ocorrer.
- **Pré-deploy MCP:** a retirada de 2 tools muda a contagem do `tools/list`; rodar `node scripts/audit-mcp-tool-matrix.mjs --runtime` após o deploy da EF `nucleo-mcp` para confirmar `runtime ≡ static` (sem drift).
- **Follow-up:** limpeza de `tribe_selections` + drop das RPCs legadas + correção/remoção do trigger de sync legado, quando houver janela fora de virada de ciclo.
