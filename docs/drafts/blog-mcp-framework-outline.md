# Blog post outline — "Núcleo IA + MCP: framework AI-native para gestão de projetos"

**Status:** Draft (Apr 30, 2026) — PM review + publish via /admin/blog quando CR-050 IP policy ratificada.
**Target slug:** `mcp-framework-pmi-chapter` (replaces `mcp-server-launch` from Mar 2026)
**Existing post to retire/redirect:** `/blog/mcp-server-launch` (title says "74 ferramentas" — stale 3.2× vs reality 236).

**Audience:** Primary persona per product-leader council = **PMI Chapter Operator/President**. Secondary: PMs corporativos curiosos sobre AI-native ops.
**Tone:** practitioner case study, not whitepaper. Honest about what's specific to Núcleo vs generic.
**Length:** ~1200 palavras (5 seções).
**Languages:** PT-BR canonical → EN+ES via `title_i18n`/`body_html` jsonb (paridade trilingue padrão Núcleo).

---

## Estrutura — 5 seções

### Seção 1 — O que é MCP (para quem nunca viu)
~150 palavras. Audience: PM/PMI não-tech.

**Pontos:**
- MCP = Model Context Protocol (open spec da Anthropic, Nov 2024). Padrão para conectar assistentes de IA a sistemas reais.
- Analogia: como dar ao Claude/ChatGPT acesso *controlado* (com auth + permissões + log) ao banco de dados da sua organização — via linguagem natural.
- Diferença vs API tradicional: conversacional, com permissões por papel, com auditoria por chamada.
- Mês de vida: Anthropic SDK ~97M downloads/mês (Mar 2026); 30% dos vendors enterprise vão expor MCP em 2026 (Forrester).
- "Não é mais 'preciso aprender a UI' — é 'pergunto à minha IA preferida'."

### Seção 2 — O framework: por que o Núcleo construiu isso
~350 palavras. **Coração do post.** Articula a hipótese do PM em linguagem de gestor.

**Citação do PM (parafraseada):**
> "Gestores de projeto passam 30-40% do tempo localizando informação dispersa — ata no Drive, decisão no WhatsApp, KPI na planilha. O MCP do Núcleo conecta tudo em um único ponto via chat. A IA não substitui o gestor; amplifica o tempo dele para decisão, não para localização."

**Componentes do framework (tabela ou lista visual):**
- **Plataforma** (banco + RPCs) — Supabase Postgres com 236 ferramentas operacionais expostas
- **MCP** (camada conectora) — 1 EF expõe tudo via OAuth 2.1 + permissões `can_by_member()`
- **Drive** (documentos) — atas, arquivos, deliverables das tribos auto-discovered (ADR-0064/0065)
- **Chat** (interface) — Claude.ai / Claude Code / Cursor / outros clientes MCP

**Resultado prático:**
- Membro consulta carga horária / próxima reunião / status do board sem abrir 5 telas
- Líder de tribo escreve ata via comando + estrutura automática
- Diretoria monitora KPIs por pergunta natural ("como estamos vs meta?")
- Curador busca recursos da biblioteca por tópico
- Tudo com auth + audit log + LGPD-compliant

**Diferencial Núcleo:** processo seletivo assistido por IA (Gemini 2.5 + comissão híbrida), gamificação automática, governança documentada via 67+ ADRs públicos.

### Seção 3 — Números ao vivo + link para o catálogo
~100 palavras.

**Texto:**
> "Hoje o servidor MCP do Núcleo expõe **236 ferramentas, 4 prompts e 3 recursos**, organizados em 12 domínios. Read tools (148): consulta de membros, eventos, KPIs, atas, biblioteca. Write tools (79): criar cards, registrar presença, atualizar boards, propor versões. Admin tools (9): operações de gestão por membros autorizados.
>
> [**Ver catálogo completo →** /docs/mcp](/docs/mcp)"

Não listar as 236 inline. O link para /docs/mcp resolve.

### Seção 4 — Jornada de exemplo (case study mini)
~300 palavras. Story de 5 passos com 1 voluntário concreto (anonimizado ou com permissão).

**Cenário:** pesquisador da Tribo "Radar Tecnológico" preparando apresentação para diretoria do CBGPL 2026.

```
Pesquisador (no Claude.ai chat):
1. "Quais foram nossas entregas este trimestre?"
   → MCP: get_tribe_deliverables (lista publications + deliverables)
   → 8min de pesquisa em Drive evitados

2. "Tem algum card em atraso?"
   → MCP: get_my_board_status
   → 2 cards "in_progress" há >30 dias surfaced

3. "Quantas presenças registrei este ciclo?"
   → MCP: get_my_attendance_hours
   → 87% rate, 18h impact

4. "Busca recursos sobre ROI de IA pra incluir nas referências"
   → MCP: search_hub_resources
   → 5 hits relevantes da biblioteca curada

5. "Qual a versão atual da plataforma pra citar?"
   → MCP: get_current_release
   → v3.2.1 (Structural Quality)
```

**Resultado:** 45 minutos de prep manual viraram 8 minutos de conversa.

**Não é mágica:** os dados estavam todos lá. Mudou o *como acessar* — chat ao invés de 5 telas + 3 planilhas.

### Seção 5 — Reproducibilidade: outros chapters podem fazer isso?
~300 palavras. Honesto sobre framework genérico vs Núcleo-specific.

**Framework genérico (replicável em ~2-4 semanas dev work):**
- Padrão: Supabase EF + SDK MCP + Zod schemas + OAuth 2.1
- Auto-refresh JWT server-side via KV
- Permissões via tabela `engagement_kind_permissions` (kind × role × action)
- Pattern de catálogo: JSON manifest gerado de source + Astro SSG
- 31 Edge Functions deployable

**Núcleo-specific (não replicável só lendo README):**
- 67+ ADRs documentando *por quê* de cada decisão (Domain Model V4, IP ratification, drift prevention)
- 30 migrations consolidadas + RLS policies + LGPD compliance
- Modelo de membro/engagement/initiative refinado em 7 fases de refactor
- Volunteer flywheel + brand PMI

**Onde começar:**
- Repo público [`nucleo-ia-gp/frameworks`](https://github.com/nucleo-ia-gp/frameworks) (CC-BY-SA / MIT) com:
  - `docs/MCP_HELLO_WORLD.md` — passo a passo "EF + 3 tools + Claude.ai connection" (objetivo: outro chapter consegue MCP funcional em 2h)
  - `docs/PERMISSION_MODEL.md` — como montar permissões para org menor (sem 7 fases)
  - ADR templates — `.md` boilerplates pra próprias decisões
  - Migration patterns — schemas exemplares (chapter_registry, initiatives, engagements)

**Próximos passos pra capítulos PMI Brasil:**
- 15 capítulos anunciados CBGPL 2026 — onboarding rolling via PMI Volunteer Portal já LIVE
- Conversation 1:1 com chapter presidents via WhatsApp do GP (mailto: nucleoia@pmigo.org.br)
- LIM Lima 2026 (regional LATAM) + PMI Global Summit Detroit (Out 2026 — abstract submission quando inscrições abrirem)

---

## CTAs sugeridos no final

- "Ver catálogo MCP completo →" `/docs/mcp`
- "Conversar com o GP →" `mailto:nucleoia@pmigo.org.br`
- "Repo público" → `https://github.com/nucleo-ia-gp/frameworks`
- "ADRs do Núcleo" → repo principal `docs/adr/`

---

## Risk flags antes de publish (PM check)

1. **CR-050 IP policy ratificação** — não publicar antes (voluntary research authorship em zona cinza)
2. **PMI trademark uso** — "PMI chapter" como descritor factual; evitar "PMI-endorsed" sem autorização institucional
3. **Catálogo public visibility (Path B curado)** — `/docs/mcp` já live em 30/Abr. Sensitive tools (10) têm descrição genérica. Verificar se descrições admin não revelam surface attack
4. **Frase "case de sucesso" vs "framework"** — product-leader recomenda **"case study"** (não "framework genérico software"). Preserva path optionality.

---

## Referências internas (para o post)

- ADR-0007: V4 Authority via `can_by_member()` (gating canonical)
- ADR-0011 V4 Auth (substituiu role lists hardcoded por engagement-derived authority)
- ADR-0012: Schema Consolidation Principles
- ADR-0064/0065: Drive auto-discovery (atas via cron + filename heuristic)
- ADR-0066: PMI Journey v4 (rolling onboarding pós-CBGPL)
- 30 migrations Domain Model V4 (Apr 2026)

---

## Quem revisa antes de publish

- PM (Vitor) — voice + accuracy + final-call
- legal-counsel agent — PMI trademark + IP risk review (per product-leader Wave 4 plan W3)
- ux-leader (opcional) — readability check para chapter operator persona

## Checklist pré-publish (após CR-050 ratificada)

- [ ] Substituir slug antigo `mcp-server-launch` por redirect 301 → novo
- [ ] OG image atualizada (236 tools / framework visual)
- [ ] Schema.org Article + ScholarlyArticle JSON-LD verificado
- [ ] PT-BR canonical + EN + ES paridade no `title_i18n`/`body_html`
- [ ] Cross-post em ProjectManagement.com (PMI community platform)
- [ ] Anunciar via blast email pros 48 researchers (`send-weekly-member-digest` próximo sábado já pega)
- [ ] LinkedIn post com link
- [ ] WhatsApp do GP — share com 15 chapter presidents

---

**Notas finais:**
- Tom matura: "construímos isso, funciona, here's how, you can replicate" — não promotional/salesy
- Métricas concretas: 48 researchers, 7 tribos, 15 chapters anunciados, 236 tools, 510h impact, 73.8% retention. Esses números **estão na home dinâmica** — link de "ver ao vivo" reforça honestidade.
- Path optionality preservada: case study NÃO é "instale nosso software" — é "veja como pensamos, replique a ideia". A/B/C Trentim continuam abertas.
