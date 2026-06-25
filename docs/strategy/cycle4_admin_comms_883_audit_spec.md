# Auditoria `/admin/comms` (#883) — Spec de implementação

> **Status:** AUDITORIA CONCLUÍDA + decisões estratégicas do PM travadas — **aguardando "vai" do PM para implementar**.
> **Processo:** audit → spec → aprovação do PM → implementação. Nada vai para `main` sem aprovação explícita (`main` auto-deploya em prod).
> **Data:** 2026-06-24 · **Método:** workflow multi-agente (6 dimensões → verificação adversarial dos HIGH → síntese).

---

## 1. Grounding ao vivo (verificado nesta sessão — não recitado)

### Autoridade / acesso (74 não-guests)
- Só **2** resolvem `can_by_member('manage_comms')`: **Fabricio Costa** e **Vitor** (ambos `operational_role=manager`).
- `manage_comms` é concedido em V4 por engagement `kind=volunteer × role ∈ {co_gp, comms_leader, deputy_manager, manager}`, `scope=organization`. `comms_leader` é **role** dentro de `volunteer`, não um kind.
- O gate da página `/admin/comms` (`canAccessAdminRoute`, `src/lib/admin/constants.ts:175-182`) é **client-side** (ADR-0106) e passa por: tier `admin` **OU** designação V3 `['comms_leader','comms_member']` **OU** operational_role permitido.

### Roster real do time de comms (iniciativa **"Hub de Comunicação"**, `workgroup_member`, initiative-scoped)
| Membro | Designação V3 | `manage_comms` | Vê a página hoje | Estado |
|--------|---------------|----------------|------------------|--------|
| Mayanna Duarte (líder) | `comms_leader` | ❌ | ✅ (designação) | vê página, **writes rejeitados** |
| Letícia Clemente (coord.) | `comms_member` | ❌ | ✅ (designação) | vê página, **writes rejeitados** |
| João Coelho Júnior | — | ❌ | ❌ | **travado** (`comms-denied`) |

> A premissa "time inteiro vê tela de negado" (achado D6-F1) foi **REFUTADA** na verificação: 2 de 3 veem via designação; só João é negado.

### Segurança — RPCs de comms (pg_proc, verificado)
- `comms_channel_status`, `comms_metrics_latest_by_channel`, `comms_top_media`: **`SECURITY DEFINER` + GRANT `authenticated` + SEM gate interno** → leitura aberta aos **74 autenticados, incl. 23 guests de pré-onboarding**.
- `comms_channel_status` retorna o **`config` jsonb completo**: instagram `{business_portfolio_id, facebook_page_id, ig_user_id, meta_app_id}`, linkedin `{organization_urn, refresh_token_expires_at, token_refreshed_at}`, youtube `{channel_id, channel_handle}` + saúde de token. **Não** vaza token cru (só booleans `has_api_key`/`has_oauth_token`).
- `get_comms_to_adoption_funnel`: **já gateado** (`view_internal_analytics` OR `manage_platform`) — alarme inicial **REFUTADO**, fora de escopo.
- `comms_executive_kpis`: DEFINER, **REVOKED de authenticated** (padrão de hard-gate a espelhar).

### Dados (`comms_metrics_daily`)
- instagram 72 linhas / 2026-06-24 · youtube 72 / 2026-06-24 · linkedin 3 / 2026-06-24 · **newsletter 1 / 2026-03-08 (órfã, sem `channel_config`)**.

---

## 2. A virada da auditoria (acoplamento acesso × segurança)

O problema central **não** é "ninguém vê". É que a **camada de leitura está escancarada**: qualquer autenticado (incl. guests) puxa IDs de infra + saúde de token chamando o RPC direto; o gate da página é cosmético. Mayanna/Letícia já leem; João está travado por **inconsistência** do gate.

→ Fechar o vazamento (gate nos RPCs) **trava o time** no mesmo instante, a menos que provisionemos antes. **PR-1 (provisionar) e PR-2 (gatear) são um par P0 atômico.**

---

## 3. Decisões do PM (travadas 2026-06-24)

| # | Decisão | Escolha |
|---|---------|---------|
| **Público** | Quem acessa | **Time de comms + gerência do Núcleo + diretorias/patrocinadores/pontos focais** |
| **#5 / Níveis** | read-only vs `manage_comms` | **Dois níveis:** `view_comms_analytics` (LER) amplo + `manage_comms` (ESCREVER token/config) estreito |
| **#2 / Gate** | gate vs revoke | **Split** do `comms_channel_status` (saúde de token p/ read tier; `config` jsonb só write tier) + gatear os 3 RPCs no read tier |
| **#3 / Reach** | normalizar vs rotular | **Chips por canal** c/ janela rotulada + corrigir bug do 7× |
| **#4 / Newsletter** | remover vs ligar | **Ligar fonte = digests internos** da plataforma (`get_weekly_member_digest`/`digest_health`) |

### Recomendações adicionais (não bloqueantes — proceder salvo objeção)
- **PM-6 (engagement KPI):** implementar a média **ponderada por audiência** (reaproveitar a fórmula SQL já existente, hoje morta) para casar com o rótulo "weighted avg by channel"; documentar a ressalva de que LinkedIn é razão lifetime e IG é diária.
- **PM-7 (LinkedIn Top Content):** **desabilitar** o botão com tooltip "Disponível em breve" agora (corta o dead-end); implementar `fetchLinkedInMedia()` como follow-up (PR-6).
- **PM-10 (CSP thumbnails):** **allowlist** de CSP (`media.licdn.com`, `*.ytimg.com`, `*.cdninstagram.com`, `*.fbcdn.net`) numa página admin-only — também conserta as thumbnails IG/YT já quebradas (escopo #855).

---

## 4. Plano de PRs (priorizado + sequenciado)

> **Sequência crítica:** PR-1 → PR-2 (par P0 atômico). PR-3 → PR-4. PR-5/6/7 independentes do trilho de segurança.

### PR-1 — Provisionar acesso (P0)
- **READ (`view_comms_analytics`):** time de comms (Hub de Comunicação) + gerência + diretorias/patrocinadores/pontos focais.
- **WRITE (`manage_comms`):** managers (Fabricio, Vitor) + **Mayanna** (líder, rotaciona token).
- **Mecanismo de grant = decisão de implementação aberta** (ver §5) — fechar via procedimento V4 de 4 etapas (`docs/reference/V4_AUTHORITY_MODEL.md`). **NÃO** mexer em `engagement_kind_permissions` (combo `volunteer×comms_leader×manage_comms×organization` já seedado em `20260426170038`).
- ⚠️ Sutileza de escopo: o time está engajado como `workgroup_member` *initiative-scoped*; `manage_comms` é *org-scoped* (`initiative_id=NULL`). Provisionar exige escolher o mecanismo certo (§5), não só trocar um role.
- Re-aterrar `can_by_member` ao vivo no apply (regra de grounding).

### PR-2 — Gatear os RPCs de leitura + split do `comms_channel_status` (P0, segurança DB)
- Gate interno (espelhar `can_manage_comms_metrics` + REVOKE de `comms_executive_kpis`) em: `comms_channel_status`, `comms_metrics_latest_by_channel`, `comms_top_media` → na ação `view_comms_analytics` (OU `manage_comms`).
- **Split `comms_channel_status`:** saúde de token (status, last_sync, dias p/ expirar, auto-refresh) p/ read tier; `config` jsonb (IDs de infra) **só** p/ write tier.
- **NÃO** tocar `get_comms_to_adoption_funnel` (já gateado).
- D2-05: REVOKE explícito de `comms_executive_kpis` ao fim de qualquer migration que a recrie (lockdown idempotente).
- D2-07 (fold-in): gate em `comms_acknowledge_alert`.
- DDL via `apply_migration` + Write do arquivo local + `repair` + **DELETE da linha auto** de `schema_migrations` (drift de linha-dupla) + `NOTIFY pgrst`. Provar **os dois lados** ao vivo (guest→0, time→dados). **Repo público → fix quieto, sem issue pública** (precedente #869).

### PR-3 — Alinhar gates client-side ao V4 (P1)
- Trocar `canManageChannels` (designação V3, `comms.astro:410-417`) por flag server-authoritative (RPC retorna `can_manage`).
- Migrar page-gate (`constants.ts:175-182`) + nav (`navigation.config.ts:94`) p/ consumir a capability V4 em vez da designação. Coordenar com o roster da PR-1.

### PR-4 — Split UI READ/WRITE (least-privilege) (P1)
- `#admin-sections`: tier READ (saúde de token + alertas + banner staleness) p/ quem passa o page-gate; tier WRITE (botões "Editar Config" + modal `comms.astro:806`) só `manage_comms`.
- Passar flag `canWrite` p/ `loadChannelConfig`. Depende da flag da PR-3.

### PR-5 — KPIs executivos: reach + engagement (P2)
- **Reach (`comms.astro:456`):** trocar headline único por **chips por canal** rotulados (LinkedIn impressões 12m · IG alcance/dia · YT views totais); corrigir o reduce que multiplica ~7×.
- **Engagement (`comms.astro:458-481`):** média **ponderada por audiência** `SUM(eng*aud)/SUM(aud)` (fórmula já existe em `20260422050000:159-162`); ressalva lifetime vs diária.
- **Allowlist explícita de canais** (instagram/youtube/linkedin/newsletter) onde agrega — não depender do efeito colateral da data-máxima (D3-05).
- **Não** "normalizar" o total de audiência (é o único agregado correto — D3-04).

### PR-6 — LinkedIn completo + CSP thumbnails (P2)
- Card LinkedIn (`comms.astro:~660`): taxa de engajamento + delta de followers; trocar placeholder `linkedinAwaitingApi` morto por `common.loading` + fallback no-data.
- Botão "LinkedIn" no Top Content: **desabilitar c/ tooltip** agora; `fetchLinkedInMedia()` (mirror de `fetchYouTubeMedia`, registrar em `MEDIA_FETCHERS` `sync-comms-metrics/index.ts:584-587`) como follow-up — **bloqueado por CSP**.
- CSP img-src em **ambos** `src/lib/securityHeaders.ts:41` E `public/_headers:12` (teste de paridade byte-equal). i18n: chaves novas nos 3 dicts.

### PR-7 — Ligar newsletter (digests internos) + polish UX (P3)
- **Newsletter = LIGAR FONTE:** conector que puxa stats de envio/entrega dos digests internos (`get_weekly_member_digest`/`get_digest_health`) → `comms_metrics_daily` channel='newsletter'. Investigar a superfície de dados do digest (sends, opens se rastreado). **(Mudou de "remover" para "ligar".)**
- Saúde de token: chip "Auto-renovação ativa" + deadline real ~1ano (em vez de countdown 60→0); suprimir banner vermelho salvo falha real do refresh (D5-1). Tier de expiry manual por dias (<7 vermelho, <30 âmbar).
- Calendário editorial: esconder quando `comms_calendar_embed_url` não configurado (D6-F3).
- Renomear páginas: comms="Mídia Social — Desempenho", comms-ops="Mídia Social — Operação" (D6-F4).
- Funil: trocar caixa de ressalva por tooltip; remover linguagem "Phase A/B"; localizar labels (D6-F6).

### PR-8 — Roadmap diferido (issues próprias, NÃO bundle) (P3)
- Demografia de followers (nova tabela `comms_follower_demographics` + RPC + fetcher + UI — M+, gated por pedido de produto).
- Consolidar os dois rollups divergentes (cliente vs SQL morto) num RPC DEFINER gateado (D3-06).
- De-escopar scopes member-level do LinkedIn (`r_member_*`) na próxima re-emissão de token (não usados + downside LGPD — D4-05).
- Read-audit leve em `comms_channel_status` após o gate (D2-08).

---

## 5. Decisão de implementação aberta (resolver na PR-1)

**Como conceder `view_comms_analytics` a um público heterogêneo (workgroup_member, sponsor, chapter_board, pontos focais) sem over-grant?** Permissões V4 são por `(kind, role)`, não por iniciativa — seedar `view_comms_analytics` p/ `workgroup_member` daria a TODOS os workgroups.

Opções a avaliar (procedimento V4 + possível consulta `data-architect`):
- **A — Designação-based (pragmático):** usar/expandir as designações comms (`comms_leader`/`comms_member` + talvez `comms_viewer`) e gatear os RPCs em `can_by_member(manage_comms) OR caller-tem-designação-comms-read`. Casa com o page-gate atual (já é por designação). Contras: mistura V4 `can()` com cache V3.
- **B — V4 puro:** seedar `view_comms_analytics` p/ combos específicos + provisionar engagement org-scoped p/ cada pessoa. Mais limpo, mais trabalho/risco de over-grant.

→ Recomendação preliminar: **A** (consolida o que já existe; o page-gate já é por designação), mas confirmar com o procedimento V4 + consulta de domínio na implementação.

---

## 6. Apêndice — achados (37 total; 8 HIGH verificados, 1 refutado, 16 medium)

**HIGH verificados** (severidade ajustada pós-verificação):
- D1-01 (→med) provisionamento exato Mayanna · D1-07 (→med) RPCs ungated = raiz do vazamento · D2-01 (→med) `comms_channel_status` vaza IDs de infra · D3-01 (→med) reach soma unidades incompatíveis · D3-02 (→med) engagement não-ponderado rotulado como ponderado · D5-1 (→low) UI ignora auto-refresh · D5-2 (→low) READ acoplado a WRITE · D6-F2 (→med) LinkedIn 2ª classe.

**REFUTADO:** D6-F1 (time inteiro travado — falso, 2/3 veem via designação).

**MEDIUM** (16): D1-03/05/06, D2-02/03/05/06, D3-03/05, D4-01/02, D5-3/4, D6-F3/F4/F5 — todos endereçados nos PRs acima.

---

## 7. Riscos (carry para a implementação)
- **Sequência:** PR-2 antes da PR-1 = time perde acesso no instante do gate. Par atômico.
- **Provisionamento silencioso:** engagement `volunteer×comms_leader` novo sem `agreement_certificate_id` → `is_authoritative=false` → `can()` não concede (volunteer `requires_agreement=true`). Mecanismo deve ser validado ao vivo.
- **`apply_migration` cria linha auto** em `schema_migrations` → deletar após Write+repair (senão quebra `rpc-migration-coverage`).
- **`main` auto-deploya:** verificar a árvore COMMITADA (`git show HEAD:path`) pós-merge (CI verde ≠ árvore certa — quase-incidente #852/#853).
- **CSP em 2 arquivos byte-equal** (teste de paridade); `_headers` é no-op em Workers SSR (SSOT = `securityHeaders.ts`).
- **i18n:** toda chave nova nos 3 dicts.
- **Repo público:** o gate dos RPCs é fix de segurança → quieto, sem disclosure pré-fix.
