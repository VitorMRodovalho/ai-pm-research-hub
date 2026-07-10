# SPEC — Tribe Switch (researcher self-service) + Leader-Review Hardening

> **Status:** PLAN (não implementado). Sessão de planejamento 2026-07-10.
> Executar em **waves**; **merge só na sessão dev** ([[feedback-merge-to-main-is-main-session-only]]).
> Complementa `SPEC_TRIBE_SELECTION_HYBRID.md` (fluxo de entrada). Este SPEC cobre **corrigir tribo errada** + **endurecer a ponta do líder**.
> **Grounding:** todos os números abaixo foram medidos ao vivo em **2026-07-10** — re-grounde a cada PR (não recite estes valores como antes/depois).

---

## 1. Problema

1. Um voluntário **selecionou a tribo errada** e não consegue trocar — não há self-service de saída/cancelamento + re-escolha.
2. Suspeita de gap na jornada do **líder** aceitar/rejeitar o pedido de entrada.

## 2. Grounding ao vivo (2026-07-10)

| Métrica | Valor |
|---|---|
| Membros ativos com `tribe_id` | 47 |
| `tribe_id` sem engagement de tribo correspondente | 1 (liaison Roberto, conhecido) |
| Pedidos de entrada **pendentes** agora | 12 (todos dos últimos 3 dias — onda do kickoff C4) |
| Pedidos expirando em <48h **sem ação do líder** | 2 |
| Tribo com backlog mais antigo | Tribo 11 "PMO Inteligente" — 4 pendentes desde 2026-07-07 |
| `research_tribe.required_engagement_kinds` | `{volunteer}` |
| Invariantes AG / AH | 0 / 0 |
| TTL do convite | `initiative_invitations.expires_at DEFAULT now()+72h` (default de tabela) |
| Cron de expiração | `expire-stale-invitations-hourly` (`0 * * * *`) |
| Status enum em uso | `pending, accepted, declined, expired` (sem `cancelled`) |
| `tribe_capacity_limit()` | **7** (platform_settings SSOT, mig `...335`) |
| Contagem por tribo (lógica `count_tribe_slots`) | 1/4/6/8 = **7 (1 líder + 6 pesq)** → aparecem "7/7 lotada" com só 6 pesquisadores |

## 3. Achados da auditoria

### F1 — [1a] Pedido pendente na tribo errada não pode ser cancelado (GAP, alto)
- `request_tribe_assignment` bloqueia um **segundo** pedido: `"Você já tem um pedido de tribo pendente"` (mig `20260805000216`/`...347`).
- Não existe RPC/UI de cancelamento. O `respond_to_initiative_invitation(id,'decline')` **funciona** para o próprio self-request (guard só checa `invitee_member_id = caller`; para self-request `invitee==inviter==caller`) — mas é **MCP-only, sem UI**.
- O card "Pedido enviado" em `TribeRequestBlock.tsx` (estado `ctx.pending`, linhas ~224-249) **não tem ação nenhuma**.
- **Consequência:** pesquisador que pediu a tribo errada fica preso até 72h (expiração) ou o líder recusar. Provável causa-raiz do sintoma reportado.

### F2 — [1b] Membro aprovado na tribo errada não tem saída self-service (GAP, alto)
- `withdraw_from_initiative(initiative_id, motivo≥10)` (mig `20260514370000`) revoga o engagement (`status='revoked'`), o que **dispara** `trg_sync_tribe_id_from_engagement` (branch de demotion, mig `20260805000216`) → **limpa `members.tribe_id`** quando não resta outro engagement ativo de tribo → o picker reaparece (`get_my_tribe_request_context` volta `eligible=true`).
- O primitivo **existe** mas é **MCP-only** (está no `mcp-manifest.json`, sem botão na web). O empty-state `has_tribe` (`TribeRequestBlock.tsx` ~271-279) é beco: só diz "fale com a coordenação".
- **Safeguard do withdraw:** bloqueia se o caller for o **único** ativo do `required_engagement_kind` (`volunteer`). Como o **líder é sempre** um `volunteer`, um membro comum **nunca** é o único → withdraw liberado. O **líder** não consegue auto-sair (é o único voluntário nas tribos de 1 vol) — comportamento aceitável; mostrar mensagem que roteia ao GP.

### F3 — [Gap #2] Ponta do líder já está CONSTRUÍDA (contra a hipótese)
- Fila em `/tribe/[id]?tab=members`: `list_tribe_pending_requests` (mig `...218`) + UI aceitar/recusar com nota + badge + foco/aria (`tribe/[id].astro` ~1136-1261).
- Notificação ao líder no pedido, deep-linked pro tab certo (`?tab=members`, #1139 Item 2).
- Autoridade correta (Caminho-3 inline: GP `manage_member` **ou** engagement `volunteer/leader` da tribo).
- **Gaps soft (reais):**
  - **Sem nudge/escalonamento** antes da expiração de 72h → pedido expira em silêncio (2 casos expirando em 48h agora; Tribo 11 com 4 parados há 3 dias). Líder voluntário não loga todo dia.
  - **TTL de 72h curto** para revisão feita por voluntário.
  - Descoberta: só notificação + visitar a página (sem hub global). Menor.

### F4 — [correção obrigatória] Auto-aprovação via `respond_to_initiative_invitation` (design hole, médio)
- `respond_to_initiative_invitation('accept')` sobre o **próprio** pedido self-service (invitee==inviter) **cria o engagement sem passar pelo líder** — fura o modelo híbrido "líder confirma".
- MCP-only hoje (sem UI), risco real baixo, mas é buraco estrutural. **Fechar** (não é escolha de produto).

### F5 — [capacidade] O líder consome uma vaga de pesquisador (BUG, alto · URGENTE) — *reportado por Vitor 2026-07-10*
- Modelo pretendido: **líder + 7 pesquisadores = 8 assentos**. O limite `tribe_capacity_limit()=7` deveria valer para **pesquisadores**, não incluir o líder.
- `count_tribe_slots()` (mig `20260691000000`) e o gate de capacidade em `review_tribe_request` (mig `...335`, ~L249-257) contam `members` por `tribe_id` com `operational_role NOT IN ('sponsor','chapter_liaison','guest','none')` — **`tribe_leader` NÃO está na exclusão**, então o líder **entra na contagem**.
- **Ao vivo:** tribos 1/4/6/8 contam **7 = 1 líder + 6 pesquisadores** → exibem "7/7 lotada" tendo só **6 pesquisadores** (o "6+1" reportado). Bloqueia aprovações reais: tribo 6 (2 pendentes), 8 (1), 4 (1) estão "lotadas" sem estarem.
- **Nota:** `comms_leader` também deriva `operational_role='tribe_leader'` (ladder A3) — a exclusão do líder cobre os dois.

## 4. Decisões (ratificadas PM 2026-07-10)

- **D1 (troca 1b):** **Sair → repedir** (self-service). Reusa `withdraw_from_initiative` + picker existente. Aceita a janela curta "sem tribo" (re-pedido é imediato).
- **D2 (líder):** **Nudge + TTL maior** — TTL 72h→7d (só para pedidos de tribo), nudge D-2 antes de expirar, fallback de visibilidade ao GP na expiração.
- **D3 (escopo):** **Incluir paridade MCP (#1138)** — expor o fluxo híbrido + as novas ações como tools MCP.
- **D0 (obrigatória):** fechar a auto-aprovação (F4).
- **D4 (capacidade, F5) — RATIFICADA PM 2026-07-10:** **subir o limite para 8** (`platform_settings.max_researchers_per_tribe` 7→8), mantendo o líder na contagem. Assim `limite=8` = líder + 7 pesquisadores. Tradeoff conhecido e aceito: com o líder contado, um futuro co-líder consumiria um assento de pesquisador (hoje toda tribo tem 1 líder). Sem edição de corpo de função — as 3 superfícies leem `tribe_capacity_limit()`.

## 5. Plano de waves

> Cada wave = 1 PR independente, verde, revisado pelo agente de domínio + Tier 1. **Merge só na sessão dev.** Re-grounde números no PR.

### Wave 0 — Fechar auto-aprovação (F4) · *correctness, isolada, primeiro*
- **DDL** (`apply_migration` + arquivo local + repair + NOTIFY): em `respond_to_initiative_invitation`, **rejeitar `'accept'` quando `invitee_member_id = inviter_member_id`** com mensagem clara ("pedido self-service é aprovado pelo revisor; para cancelar use decline"). `'decline'` continua permitido (é o cancelamento do próprio pedido).
  - Basear no corpo **VIVO** via `pg_get_functiondef` ([[reference-create-or-replace-base-on-live-body]]); é RPC genérica ADR-0061 (blast radius: todo self-request de convite — hoje só tribo usa esse padrão, confirmar).
- **Teste contrato:** `respond_to_initiative_invitation('accept')` sobre self-request → erro; leader-invite (invitee≠inviter) → aceita normal.
- **Rollback:** re-aplicar corpo de `20260514330000`.

### Wave A — Subir capacidade para 8 (F5 / D4) · *config + fallback FE · URGENTE, pode shippar primeiro*
> Independente das demais; destrava aprovações do kickoff **hoje** (tribos 1/4/6/8 saem de "7/7" para "7/8"). Pode ir antes até da Wave 0.
> **Sem edição de corpo de função** — `count_tribe_slots`, o gate de `review_tribe_request` e `select_tribe` já leem `tribe_capacity_limit()` (SSOT `platform_settings.max_researchers_per_tribe`, mig `...335`). Basta subir a setting. Mas ela vem amarrada ao fallback do frontend por contract test.
>
> **DUAS mudanças coordenadas no MESMO PR** (senão `tests/contracts/1214-tribe-capacity-ssot.test.mjs` P2 falha no CI com DB):
> 1. **Config (DML, `execute_sql`):** `UPDATE public.platform_settings SET value = '8'::jsonb WHERE key = 'max_researchers_per_tribe';` (valor vivo hoje = jsonb `7`). A migration `...335` documenta: capacidade é config, **sem migration**. Reproducibilidade: a setting já derivou por edição de config (10→7), não é migration-tracked — anotar no PR. Opcional: mini-migration `UPDATE ...` só para trilha de auditoria.
> 2. **Fallback FE:** `src/data/tribes.ts` → `export const MAX_SLOTS = 7;` para `8` (o teste P2 exige `MAX_SLOTS == SSOT vivo`). Manter o comentário `#1214` de que é fallback.
>
> **Verdade global:** `tribe_capacity_limit()` = 8, `get_homepage_stats.max_researchers_per_tribe` = 8 (auto), gate de approve libera até 8.
- **Efeito ao vivo (medir antes/depois no PR):** 1/4/6/8 passam de 7/7 → **7/8** (líder + 6 pesquisadores) → abre 1 assento de pesquisador em cada; nenhuma tribo perde membro. Destrava pendentes reais (tribo 6:2, 8:1, 4:1).
- **Testes:** `npm test` com DB — `1214-tribe-capacity-ssot.test.mjs` deve passar (as 3 fontes = 8). `npx astro build` verde.
- **Rollback:** setting → `7`; `MAX_SLOTS` → `7`.

### Wave 1 — Cancelar pedido pendente (F1 / caso 1a) · *DB + UI researcher*
- **DDL:** nova RPC `cancel_tribe_request(p_invitation_id uuid)` — só o próprio invitee de um self-request `pending` de `research_tribe`; seta `status='declined'` + `reviewed_note='self_cancelled'` (**reusa `declined`**, evita mexer no CHECK do enum; marcador distingue de recusa-do-líder em analytics). Alternativa avaliada: adicionar `status='cancelled'` (requer alterar CHECK + toda leitura que filtra status) — **rejeitada** por custo/benefício.
  - Grant authenticated; REVOKE anon.
- **UI:** botão **"Escolher outra tribo"** no card `ctx.pending` do `TribeRequestBlock.tsx` → `cancel_tribe_request` → re-`load()` → picker reaparece (eligible volta true; pending vira null).
- **i18n:** chaves nas 3 dicts (`cancelRequest`, confirm, toast).
- **Teste:** cancelar → pending some, picker reaparece; re-request na tribo certa passa (guard "pendente" já livre).
- **Rollback:** `DROP FUNCTION cancel_tribe_request`; reverter TSX/i18n.

### Wave 2 — Sair da tribo → repedir (F2 / caso 1b) · *DB read + UI researcher*
- **DDL (aditivo):** estender `get_my_tribe_request_context` para retornar, no caso `has_tribe`, `current_tribe_id` (int) **e** `current_tribe_initiative_id` (uuid) — a UI precisa do `initiative_id` para chamar `withdraw_from_initiative`. Puramente aditivo (chaves existentes intactas). Basear no corpo vivo.
- **UI:** trocar o empty-state `has_tribe` (beco) por card com ação **"Sair da tribo"** (confirm + `motivo ≥10`) → `withdraw_from_initiative(current_tribe_initiative_id, motivo)` → re-`load()` → picker reaparece.
  - Tratar o retorno de erro do safeguard (único voluntário / líder): mensagem explicativa roteando ao GP (não é erro genérico).
- **i18n:** 3 dicts (`leaveTribe`, confirm, reasonLabel, blockedSoleVolunteer, toast).
- **Invariantes:** AG/AH permanecem 0 (o trigger de demotion garante). Adicionar asserção no teste.
- **Teste:** membro comum sai → `tribe_id` NULL, picker reaparece, AG/AH=0; único-voluntário → bloqueado com mensagem GP.
- **Rollback:** reverter TSX/i18n + corpo de `get_my_tribe_request_context` (`...347`).

### Wave 3 — Hardening da ponta do líder (F3 / D2) · *DB + cron* — ✅ PR #1265 (verde, aguardando merge dev)
> Migration `20260805000395`. Inclui o fix #1263 (troca atômica na admissão). FE inalterado (a UI já lê `expires_at` real). Nudge/fallback via `process_tribe_request_nudges()` + coluna `metadata` em `initiative_invitations` + cron `tribe-request-nudge-hourly`. Grant do nudge = REVOKE PUBLIC+anon+authenticated (default privileges do Supabase; #965).
- **TTL 7d (só tribo):** setar `expires_at := now() + interval '7 days'` **explicitamente** no INSERT de `request_tribe_assignment` (NÃO alterar o default da tabela — afeta convites de líder→pesquisador legítimos de 72h). Ajustar o texto de expiração devolvido pela RPC + o `pendingExpiryNote` na UI.
- **Nudge D-2:** cron novo (ou estender `expire-stale-invitations-hourly`) que, para pedido `pending` de `research_tribe` a ~2 dias da expiração sem review, notifica o(s) líder(es) (dedup 1x por pedido — flag em metadata).
- **Fallback GP:** ao expirar sem ação, notificar o GP (`manage_member`) para triagem manual (não re-cria o pedido; só visibilidade).
- **Teste:** pedido a D-2 → nudge disparado 1x; expiração → notificação GP; TTL de tribo = 7d, convite não-tribo permanece 72h.
- **Rollback:** reverter corpo de `request_tribe_assignment`; `cron.unschedule` do nudge.

### Wave 4 — Paridade MCP do fluxo híbrido (#1138 / D3) · *EF nucleo-mcp + manifest*
- Expor como tools MCP (server `supabase/functions/nucleo-mcp/`): `request_tribe_assignment`, `review_tribe_request`, `list_tribe_pending_requests`, `get_my_tribe_request_context` (read), `cancel_tribe_request`, e um wrapper `leave_tribe` (resolve tribe→initiative e chama `withdraw_from_initiative`).
- Atualizar `mcp-manifest.json`, regenerar a **MCP tool matrix**, bump do manifest count.
- **Deploy EF** pelo Bash do Claude (tem Docker; o `!` do usuário falha — [[reference-ef-deploy-shell-separation-docker]]); verdade global = `functions list` version + smoke HTTP.
- **Teste:** matriz MCP regenerada; smoke de cada tool via MCP autenticado.

## 6. Invariantes & riscos

- **AG/AH (0 hoje):** todas as waves preservam. Wave 2 depende do branch de demotion do trigger; asserção obrigatória.
- **`declined` reusado (Wave 1):** analytics que contam "recusas do líder" devem filtrar `reviewed_note <> 'self_cancelled'` (ou o marcador escolhido). Documentar.
- **TTL explícito (Wave 3):** garantir que só o caminho de tribo seta 7d; convite genérico continua 72h.
- **Ordem de merge:** Wave 0 antes de expor MCP (Wave 4) — não expor o fluxo antes de fechar a auto-aprovação. **Wave A é independente e pode ir primeiro** (destrava o kickoff).
- **Wave A / SSOT amarrado:** subir a setting SEM atualizar `MAX_SLOTS` em `src/data/tribes.ts` quebra o contract test `1214` no CI com DB. As duas mudanças andam juntas no mesmo PR.
- **Wave A / co-liderança (tradeoff aceito):** com o líder contado (limite 8), um futuro co-líder (`comms_leader`, mesmo `operational_role`) consumiria 1 assento de pesquisador (efetivo = 6). Hoje toda tribo tem 1 líder, então não morde. Se co-liderança virar padrão, revisitar (voltaria a fazer sentido excluir o líder da contagem).
- **Janela "sem tribo" (D1):** aceita; re-request é imediato. Cards/pontos da tribo antiga permanecem do executor ([[feedback-merit-immutable-on-completed-work]]) — troca por engano não gera contribuição, então sem perda material.

## 7. Mapeamento de issues (criadas 2026-07-10)

- **EPIC #1258** — guarda-chuva do arco (checklist das waves).
- **Wave A → #1253** (capacidade → 8, líder + 7 pesq · URGENTE · detalhada p/ execução)
- **Wave 0 → #1254** (auto-aprovação)
- **Wave 1 → #1255** (cancelar pendente)
- **Wave 2 → #1256** (sair→repedir)
- **Wave 3 → #1257** (nudge + TTL 7d líder)
- **Wave 4 → #1138** (paridade MCP do fluxo híbrido — issue existente, open)
- **#1139** (UX pré-kickoff / empty-states) → já entregue/fechada; Waves 1/2 estendem a mesma superfície.

## 8. Fora de escopo

- Troca **atômica** sem janela (Opção B descartada) — reconsiderar só se a janela "sem tribo" gerar atrito medido.
- Hub global de aprovações do líder (Opção C do hardening) — adiado; badge por-tribo cobre o kickoff.
- Movimentação de **líder** entre tribos (governança GP) — fora; é ato mediado.
- Aposentadoria formal (DROP) das RPCs legadas `select_tribe`/`deselect_tribe` — separado (ADR-0123 já removeu as tools; RPCs ficam inertes).
