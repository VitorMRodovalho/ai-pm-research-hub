# #883 — Auditoria `/admin/comms` + Spec

**Data:** 2026-07-03 · **Autor:** PM (assistido) · **Status:** aguardando aprovação do PM (ciclo auditoria → spec → aprovação → implementação; nada implementado sem OK).

> Todos os números abaixo vêm de query ao vivo (`ldrfrvwhxsmgaabwmaik`) em 2026-07-03.

---

## 0. Manchete — o Achado #1 do issue está DESATUALIZADO

O issue (2026-06-24) afirma que "o time de comms está efetivamente FORA da camada". **Grounding 2026-07-03 mostra que o acesso de LEITURA já foi resolvido** — provavelmente por #963/#964/#966/#997 (hardening dos read-gates de comms), que aterrissou depois do achado.

Estado real hoje:

| Pessoa | operational_role | designations | resolve `manage_comms`? | vê os readers de comms? |
|---|---|---|---|---|
| Fabricio Costa | manager | founder, co_gp, … | ✅ (via manager) | ✅ |
| Vitor Maia Rodovalho | manager | founder, … | ✅ (via manager) | ✅ |
| **Mayanna Duarte** | researcher | **comms_leader** | ❌ | ✅ (via designação) |
| **João Coelho Júnior** | researcher | **comms_member** | ❌ | ✅ (via designação) |
| **Leticia Clemente** | researcher | **comms_member** | ❌ | ✅ (via designação) |

Por quê os 3 do time de comms JÁ leem os indicadores:
- **Readers** (`comms_channel_status`, `comms_top_media`, `comms_metrics_latest_by_channel`) gateiam em `can_view_comms_analytics()`, cujo corpo é:
  `can_by_member(view_internal_analytics) OR can_by_member(manage_comms) OR (designations && {comms_leader, comms_member})`.
- **Nav** (`AdminNav.astro`) expõe o link `/admin/comms` com `allowedDesignations: ['comms_leader','comms_member']`.
- **Sem SSR gate** na página (ADR-0106) → a fronteira é o RPC no DB, e o RPC honra a designação.

**Conclusão:** não há crise de acesso de leitura. O issue pediu "criar engagement `volunteer × comms_leader`" — isso **não é mais necessário** para leitura. Resta decidir se migramos o gate de leitura do array V3 legado (drift-prone) para engagements V4, e o que fazer com escrita/config (abaixo).

---

## 1. Dimensão Acesso/Permissões — o que REALMENTE resta

**1.a — Dependência do array V3 `designations` no gate de leitura.** `can_view_comms_analytics()` depende do array legado `designations` (cache V3), exatamente o vetor de drift que o V4 (`can()` derivado de engagements) busca eliminar (ADR-0026/Mayanna). Funciona hoje (carve-out deliberado de #963), mas é frágil: se a designação for limpa sem um engagement equivalente, o acesso some silenciosamente.
- **Opção A (mínima, recomendada p/ agora):** manter o carve-out por designação; documentar como dívida conhecida. Zero migração.
- **Opção B (higiene V4):** provisionar `volunteer × comms_leader` para os 3 (procedimento V4 de 4 etapas, NÃO seed em `engagement_kind_permissions`) e, num passo futuro, remover o `OR designations` do gate. Alinha com V4, mas é trabalho maior e toca o gate.

**1.b — Escrita/config = manager-only.** `comms_channel_status` mascara token/config exceto para `manage_comms` (`v_is_manager`), e ações de escrita (`admin_manage_comms_channel`) exigem `manage_comms`. O time de comms **não** tem. Decisão de produto: **o time de comms precisa VER a saúde do token (expiry/refresh) e/ou EDITAR config?**
- Se só VER token-health → expor um sub-conjunto read-only de status de token via `can_view_comms_analytics` (não `manage_comms`).
- Se EDITAR config → aí sim provisionar `manage_comms` (Opção B acima), com cautela (manage_comms pode carregar outras ações — auditar o leque antes).

---

## 2. Dimensão Gates dos RPCs — segurança

- **`get_comms_to_adoption_funnel` tem `GRANT anon:EXECUTE`** ⚠️ — porém o corpo **fail-closes para anon** (`v_caller_id IS NULL → {error: Unauthorized}`). **Não é vazamento**, mas o grant a `anon` é ruído de higiene (o ratchet de #965 revoga SECDEF anon-reachable; este passou por fail-close). **Ação: REVOKE anon** (higiene, baixo risco).
- **Inconsistência de gate no funnel:** `get_comms_to_adoption_funnel` gateia em `view_internal_analytics OR manage_platform OR view_aggregate_analytics` — **não inclui** `manage_comms` nem a designação de comms. Resultado: o time de comms vê status/mídia/métricas mas **não vê o próprio funil comms→adoção** (que é justamente uma métrica de comms). **Decisão:** unificar o gate do funnel com `can_view_comms_analytics()` (dar ao time de comms a visão do funil) ou manter separado (o funil cruza dados de seleção/adoção — pode ser intencionalmente mais restrito). Recomendo **incluir `can_view_comms_analytics()`** no OR, já que o funil é conteúdo do dashboard de comms.
- Readers (`comms_channel_status`/`comms_top_media`/`comms_metrics_latest_by_channel`): gate OK (`can_view_comms_analytics`), token mascarado a `manage_comms`. Sem over/under-exposure detectada.

---

## 3. Dimensão Indicadores unificados × por-canal

- **Canais com dados (comms_metrics_daily):** instagram 81 linhas · linkedin 12 · youtube 81 · **newsletter 1 (stale — última 2026-03-08)**. LinkedIn **está presente** nos dados e é devolvido per-canal por `comms_metrics_latest_by_channel`.
- **Semântica de `reach` mistura janelas:** LinkedIn = impressões lifetime (12m); Instagram = reach/dia. Somar num KPI agregado único mistura janelas temporais. **Decisão:** normalizar (ex.: separar "reach/dia" de "impressões lifetime") ou rotular explicitamente cada card. Recomendo **rotular** (barato) agora; normalização é maior.

---

## 4. Dimensão Cobertura de dados / camadas futuras (enhancements)

- **Newsletter:** 1 linha obsoleta (mar/2026). **Ação:** definir fonte de sync ou **remover o canal** do dashboard (não deixar card morto).
- **LinkedIn per-post / Top Content:** hoje só agregado. Scope `r_organization_social` no token permite `fetchLinkedInMedia()` → popular `comms_media_items`. ⚠️ thumbnails → depende de #855 (CSP `*.licdn.com`).
- **Demografia de followers** (país/indústria/função/senioridade): disponível via followerStatistics, não capturado.
- **Métricas member-level** (`r_member_postAnalytics`/`r_member_profileAnalytics`): avaliar uso.
- *(Estes são enhancements, não defeitos — candidatos a PRs próprios pós-aprovação.)*

---

## 5. Dimensão Saúde do token na UI

`comms_check_token_expiry()` foi gateado atrás da tier de analytics de comms em #963-#3 (#997). Verificar se o painel "Channel Admin config" reflete o estado de auto-refresh (#882) e mostra expiry ao time de comms (hoje o token/config é `manage_comms`-only no `comms_channel_status`; ver decisão 1.b).

---

## 6. Spec proposto (para aprovação — em ondas)

**Onda A — higiene de segurança (baixo risco, sem decisão de produto):**
- A1. `REVOKE EXECUTE ON get_comms_to_adoption_funnel FROM anon` (fail-close já existe; higiene + tira do radar do ratchet #965).
- A2. Incluir `can_view_comms_analytics()` no gate do funnel (dar ao time de comms a visão do funil comms→adoção — coerência com os outros readers do mesmo dashboard).

**Onda B — decisões de produto (precisam do PM):**
- B1. Token-health para o time de comms: read-only via `can_view_comms_analytics` (recomendado) vs `manage_comms` completo vs manter manager-only.
- B2. Newsletter: definir fonte de sync **ou** remover o canal.
- B3. Semântica de reach: rotular janelas (recomendado) vs normalizar.
- B4. Gate de leitura: manter carve-out por designação V3 (recomendado agora) vs migrar p/ engagement V4 (higiene, maior).

**Onda C — enhancements (PRs próprios, pós-aprovação):** LinkedIn per-post · demografia de followers · métricas member-level.

---

## Refs
- Issue #883 · #963/#964/#966/#997 (comms read-gate hardening) · #965 (anon SECDEF ratchet) · #882 (auto-refresh token) · #859 (LinkedIn Fase 1) · ADR-0026 (manage_comms V4) · ADR-0106 (no SSR gate) · ADR-0111 (comms aggregate) · `docs/reference/V4_AUTHORITY_MODEL.md`.
