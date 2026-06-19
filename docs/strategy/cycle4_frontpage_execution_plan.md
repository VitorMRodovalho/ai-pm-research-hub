# Plano de Execução — Frontpage do Ciclo 4 (verticais-first)

- **Status:** Plano de execução / startpoint para sessão limpa
- **Data:** 2026-06-19 (autor: Vitor PM + Claude PMO)
- **Issue-mãe:** #680 ([Ciclo 4] Frontpage: value-prop CoP/pós-IA + ponto de conexão de parceiros) · relacionado #661 (discussão do modelo) · #661 entrada do Ciclo 4
- **SSOT que este plano orquestra (não substitui):**
  - `cycle4_landing_value_prop.md` — brief de execução da landing (6 blocos + checklist de aceite)
  - `verticals_x_quadrants_model.md` — modelo conceitual (a IA como linha de costura)
  - `vertical_pitch_kit.md` — kit de pitches por vertical (ordem de ativação)
  - `deck_outline.md` — outline do deck executivo (entregável **separado**, ver §Referências)
  - `docs/adr/ADR-0103-vertical-as-initiative-kind.md` — decisão de modelagem (hoje *Proposed*)

> **Para que serve este doc.** Os 4 docs de estratégia (12/jun) são SSOT maduro, mas **assumem um modelo de domínio que ainda não existe no banco**. Este plano adiciona a camada que faltava: (1) o *grounding* do que já existe vs. net-new vs. bloqueado, medido ao vivo; (2) as fatias ordenadas por dependência; (3) as decisões travadas com o PM em 2026-06-19. É o startpoint organizado para a sessão limpa — não recomeçar do zero.

---

## 1. Decisões travadas (PM, 2026-06-19)

| # | Decisão |
|---|---------|
| Sequência | **Verticais primeiro** (mais perto do kickoff do C4). Caminho crítico = 0 → A → B; C em paralelo/depois. |
| Modo de operação | Toda a onda: **branch → QA visual → só então deploy pra produção.** Sem deploy direto. |
| Vertical-piloto | **Construção** — Henrique Diniz já em pré-onboarding como líder = âncora real (não vaporware). |
| Parceiros (C) | Parceria entra **pelo Programa/Núcleo** (porta única de 1º contato) mas é **firmada VIA PMI-GO**, capítulo-sede e dono da relação. Copy precisa deixar isso explícito. |
| Deck | **Não é entregável de build** — é conhecimento/inspiração para layout e organização dos temas. `branded-deck-build` numa sessão separada. |
| Landing — regra de ferro | **Nada hardcoded** (indicadores e verticais saem de dado ao vivo) + **mudar a informação, preservar o sistema visual** (sem rebrand na virada de ciclo). |

---

## 2. Grounding ao vivo (medido 2026-06-19 — re-verificar no build)

> Números/estado são snapshot. Re-consultar a fonte (`pg_proc`, `initiatives`, grep FE) no início de cada fatia antes de agir.

### ✅ Já existe (reusar, não recriar)
- **Home (`src/pages/index.astro`) com 14 seções**: `HomepageHero`, `NucleoSection`, `ChaptersSection`, `PlatformStatsSection`, `QuadrantsSection`, `TribesSection`, `RulesSection`, `KpiSection`, `TrailSection`, `TeamSection`, `CpmaiSection`, `VisionSection`, `WeeklyScheduleSection`, `ResourcesSection`.
  - Mapeamento aos 6 blocos do brief: bloco 1 herói → `HomepageHero` ✅ · bloco 2 prova viva → `PlatformStatsSection`+`KpiSection` ✅ (em grande parte) · bloco 4 escada → `TrailSection`+`CpmaiSection` ✅ · blocos 3/5 → parciais (`QuadrantsSection`/`ChaptersSection`).
- **RPCs públicas exigidas pelo brief — todas existem**: `get_public_impact_data`, `get_public_platform_stats`, `get_public_trail_ranking`, `get_champions_ranking`, **`capture_visitor_lead`** (primitivo de inbound de parceiro pronto).
- **ADR-0103 escrito** (modelagem da vertical).

### 🔴 Net-new ou BLOQUEADO
- ~~**`community_vertical` kind NÃO existe.**~~ ✅ **RESOLVIDO 2026-06-19 (Fatia A):** kind `community_vertical` configurado + vertical Construção seedada (`forming`). Os blocos 3/6 da landing já têm dado ao vivo para ler (`kind='community_vertical'`, `metadata.status`).
- ~~**ADR-0103 = *Proposed***~~ ✅ **Accepted** (Fatia 0).
- → Blocos 3 (hub-and-spoke) e 6 (CTA por `status`) **desbloqueados** — agora dependem só do FE (Fatia B).
- **Ponto de contato de parceiros público**: net-new. Só existe admin-side (`PartnerPipelineIsland`, `/admin/partnerships`). Backend (`capture_visitor_lead`) pronto; falta a porta pública.
- **Diagrama hub-and-spoke** (bloco 3) e **mapa Brasil/LatAm** (bloco 5): visuais net-new (mapa pode reusar o componente do PMAIrevolution).

---

## 3. Fatias (ordenadas por dependência — verticais primeiro)

### Fatia 0 — Ratificar ADR-0103 (governança) — ✅ CONCLUÍDA (2026-06-19)
- ADR-0103 movido *Proposed* → **Accepted**; open questions resolvidas (curado/teto 8 ajustável; roteamento deferido; âncora própria+escada=sim; piloto=Construção).
- **Saída:** ADR-0103 aceito; `community_vertical` autorizado e configurado.

### Fatia A — Modelo de vertical no banco (caminho crítico) — ✅ CONCLUÍDA (2026-06-19)
> Migration `20260805000221` (kind `community_vertical` + engagement_kinds `vertical_lead`/`vertical_member`) + vertical Construção criada via `create_initiative` (`81fdbdfa-4a92-401f-9e50-9318be9b94fe`, status engine=active, `metadata.status='forming'`, anchor PMI-CP, parceiro Global Construction Ambassadors). Henrique = líder pretendido em `metadata.intended_lead` (engajamento adiado p/ termo assinado). `has_board=false` honrado (0 boards), invariantes 0 violações. Adiados p/ ativação: engajar Henrique, seeds de permissão do líder, elevação de operational_role, invariante AJ guard-parent (detalhe no ADR-0103 §Implementação).
- Configurar o **kind `community_vertical`** via config ADR-0009 (admin, **sem migration**), `custom_fields_schema` do ADR-0103: `anchor_credential`, `predecessor_credential`, `credential_body`, `partner_org`, `status` (`forming|open|paused` — dirige o CTA da landing), `pmi_registry_url`.
- **Aterrar Henrique** (person/engagement reais) **antes de seedar**; criar a vertical **Construção** como `community_vertical` (âncora **PMI-CP**, parceiro Global Construction Ambassadors, `status`) com Henrique como líder.
- Roteamento deliverable↔vertical (ADR-0103 §3, `verticals text[]` vs. join) pode ficar para fatia posterior — a landing só precisa das verticais existirem + `status`.
- **Council:** `data-architect` (config do kind + seed + autoridade de quem gere vertical; confirmar zero-migration).
- **Aceite:** ≥1 `community_vertical` consultável com `status`; landing consegue lê-la ao vivo.

### Fatia B — Landing value-prop (FE; branch → QA visual → prod) — 🟡 B1+B2 EM PR (#810, 2026-06-19); B3 mapa adiado
> **B1 (camada de dado, mig `20260805000222`) + B2 (FE verticais) shipados no PR #810** (PM escolheu B1+B2 agora, mapa B3 depois). `get_public_verticals()` anon-safe (zero-PII) + `visitor_leads.target_vertical` (uuid FK) + `total_verticals`; `VerticalsSection` island (hub-and-spoke + CTA protagonista por `status='forming'` → `capture_visitor_lead(target_vertical)`); contador no bloco 2; copy CoP/pós-IA nas 3 dicts. Council data-architect+security (B1), code-reviewer+ux-leader (B2). **B3 mapa Brasil/LatAm = net-new sem componente reusável → sessão dedicada.**
- **Copy CoP/pós-IA** no herói/núcleo/visão (espinha narrativa do brief §1) — i18n nas 3 dicts.
- **Bloco 3 — hub-and-spoke**: raios = lista dinâmica de `community_vertical` (não fixos). Componente visual net-new; *este visual É o pitch*.
- **Bloco 6 — "Seja protagonista"**: CTA dirigido por `status='forming'`; interesse entra como `capture_visitor_lead` (`target_vertical`).
- **Bloco 5 — mapa Brasil/LatAm** em 1º plano + presença internacional como legenda nomeada; **LGPD: agregar por capítulo/estado/país, pins individuais só com opt-in** (`set_my_gamification_visibility` como precedente). Reusar/re-projetar o mapa do PMAIrevolution.
- **Bloco 2 — prova viva**: estender contadores (verticais, champions) se faltarem; tudo derivado.
- **Identidade:** sem rebrand; no máximo **1 token** de acento para o CTA protagonista; componentes net-new aditivos e tokenizados.
- **Council:** `ux-leader` (layout/jornada) + `code-reviewer`; `security-engineer` no mapa (LGPD).
- **Aceite:** checklist §7 do brief (nada hardcoded; verticais de `community_vertical`; CTA por `status`; mapa agrega; internacional visível; paleta preservada; hub-and-spoke comunica integração de silos).

### Fatia C — Ponto de conexão de parceiros (FE + wiring; independente)
- Porta pública **"Seja parceiro / fale com o programa de parcerias"** (seção na frontpage e/ou página dedicada). Copy: **Núcleo = porta de entrada; PMI-GO = capítulo-sede e dono da relação.**
- Inbound → `capture_visitor_lead` (intenção de parceria) → pipeline existente (`get_partner_pipeline` / `PartnerPipelineIsland`).
- Linguagem ancorada em `docs/strategy/partnerships/PMI_PARTNERSHIP_FRAMEWORK_NOTES.md` + playbook `nucleo-ia-gp/frameworks` §6. (Material PMI Global já disponível localmente — abrir issue no projeto pmigo só se faltar diretriz específica.)
- **Council:** `ux-leader` + `legal-counsel` (enquadramento de parceria / brand guidelines PMI / titularidade PMI-GO) + `code-reviewer`.
- **Aceite:** inbound roteia para o processo de parceria sem furar a titularidade do PMI-GO; LGPD na captura de lead.

### Rider — domínio canonical (pmigo) — encaixar antes dos certificados do C3
- Camada A (divulgar pmigo na copy/links) = livre dentro da B.
- Camada B (flip canonical pra `nucleoia.pmigo.org.br`): **centralizar o host num ponto único primeiro** → flip mantendo `vitormr.dev` **co-hospedado** (certificados já emitidos + clients MCP) → checklist: identificador OAuth do MCP (`.well-known/*`, `mcp.ts`), allowlist do Supabase Auth, confirmar Bot Fight Mode no subdomínio pmigo, GSC.
- **Janela:** Ciclo 3 = "2026/1" fechando em semanas → priorizar o flip **antes** da leva de certificados do fim do C3 (o PDF crava a URL no momento da emissão). Não depende da migração do servidor (subdomínio já está no Cloudflare).
- Host hoje chumbado como literal em ~6 arquivos: `astro.config.mjs` (`site`), `middleware.ts` (`CANONICAL_HOST`), `mcp.ts`, `mcp/semantic.ts`, `.well-known/oauth-authorization-server.ts`, `.well-known/oauth-protected-resource.ts`, `oauth-security.ts`, `certificates/pdf.ts`.

---

## 4. Referências (inspiração/conhecimento — não build)
- **Decks** em `docs/strategy/deck/`: `Nucleo_IA_GP_PMI_LATAM_Natalia.pdf`, `Nucleo_IA_GP_Pitch_Executive_EN.pdf`, `Nucleo_IA_GP_Pitch_Executivo.pdf`, `Nucleo_IA_GP_Pitch_ALUN_Kruel.pdf`, `Nucleo_IA_GP_CEIA_UFG_PnD.pdf` — minerar para layout (hub-and-spoke visual) e ordem dos temas na Fatia B.
- **Parceria** em `docs/strategy/partnerships/`: `PMI_PARTNERSHIP_FRAMEWORK_NOTES.md`, `partnership_value_exchange_canvas.md`, `partner_dossier_TEMPLATE.md`, `partner_ceia_ufg.md` (parceiro real), `README.md` — base da copy e do fluxo da Fatia C.
- **Deck executivo** (`deck_outline.md`): renderização dos 3 docs via `branded-deck-build` em sessão limpa, com template `.pptx` PMIGO. Separado da engenharia de frontpage.

## 5. Ordem de ativação das verticais (do pitch kit, para fatias futuras pós-piloto)
1. **Construção** (líder aceito + 2 Ambassadors BR/EUA) — piloto da Fatia A · 2. PMO (PMI-PMOCP recém-lançada) · 3. ESG (CSPP, janela de mídia) · 4. Ágil (Agile Alliance + refresh PMP) · 5. Negócio/Portfólio (definir parceiro).

## 6. Perguntas abertas (herdadas dos SSOT — resolver no build)
- Prova viva mostra todos os indicadores ou subconjunto curado (não poluir o herói)? (landing §perguntas)
- Verticais = catálogo curado fixo ou abertas a proposta? (`max_concurrent_per_org`, ADR-0009)
- Escada Champion→CPMAI é a única costura de credencial, ou cada vertical tem âncora própria além dela?
- Roteamento deliverable↔vertical: `verticals text[]` vs. join table (ADR-0103 §3) — decidir quando o relatório `GROUP BY vertical` for necessário.
