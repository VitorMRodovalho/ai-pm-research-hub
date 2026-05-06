# ADR-0020: Publication Pipeline — primitivo unificado `publication_ideas` + `publication_series`

- Status: Accepted (p95 2026-05-05 — PM Vitor ratified after W1 stable 22 days in prod)
- Data: 2026-04-21 (Proposed) → 2026-05-05 (Accepted)
- Autor: Claude (debug session 9908f3, issue #94, sessão de encerramento 23h50)
- Última revisão: p95 — Amendment 1 (PM decisions 2B+2C+2D)
- Escopo: Formaliza arquitetura de pipeline de publicação do Núcleo unificando 5 flows hoje paralelos (hub_resources → wiki → submission → publication → blog → newsletter). Inspirado em padrões observados em akitaonrails.com/en (21 anos de blog, 500+ posts agrupados em séries temáticas) e 10 cases de mercado (Stratechery, One Useful Thing, Engineering blogs, Dev.to, GitHub Blog, arXiv, Substack, MDPI, Building in Public, PM.com/PMI.org).

## Contexto

Runtime evidence (21/Abr/2026):

| Stage | Table | Rows | Status |
|---|---|---:|---|
| Ideia bruta (external) | `hub_resources` | 330 | ✅ library curated |
| Wiki narrativo | `wiki_pages` | 40 | 🟡 sourced from `nucleo-ia-gp/wiki` via webhook |
| Knowledge embed (pgvector) | `knowledge_assets` | 1 | 🔴 dormido |
| Submission formal | `publication_submissions` | 37 | ✅ 7 ProjectManagement.com confirmed |
| Submission events audit | `publication_submission_events` | 0 | 🔴 órfã |
| Submission multi-author | `publication_submission_authors` | 0 | 🔴 órfã |
| Publicação formal | `public_publications` | 7 | ✅ |
| Blog interno | `blog_posts` | 12 | 🟡 baixo volume |
| Comms media/arts | `comms_media_items` | 44 | ✅ |
| Campaign templates | `campaign_templates` | 16 | ✅ |
| Campaign sends | `campaign_sends` | 13 | ✅ modesto |
| Campaign recipients | `campaign_recipients` | 143 | ✅ |

**Gap estrutural:** pipeline é 5 flows paralelos sem amarração. `blog_posts` não linka para `publication_submissions` nem `hub_resources`. Uma ideia sobe por canais separados sem trilha única.

**Benchmark Akita (21 anos de blog):**

- Séries temáticas com brand distintiva ("M.Akita Chronicles", "Frank*", "Omarchy", "Vibe Code", "RANT")
- Volume + consistência: ~24 posts/ano de média
- Multi-idioma EN/PT via URL (`/en/`, `/pt/`)
- Agrupamento timeline por ano (bucket view)
- Link direto do blog para GitHub repo do projeto discutido
- Brand voice autoral (Rant, Deep Dive, Behind the Scenes)
- Conteúdo ancorado em PROJETO REAL, não teoria

**Benchmark cases de mercado** (priorizados por aderência ao Núcleo):

1. One Useful Thing (Ethan Mollick) — research-backed essays IA+Education, formato cabe research aplicado IA+PM
2. Stratechery (Ben Thompson) — single-author + paid newsletter + free digest
3. Engineering blogs (Uber/Netflix/Stripe) — dev-written não marketing, author profile
4. arXiv + OpenReview — preprint + peer review público antes formal
5. GitHub Blog — cada post com repo demo linkado
6. Dev.to/Hashnode — syndication cross-platform
7. Substack/Ghost Pro — creator economy
8. MDPI — peer review formal tracking
9. Building in Public (Kahl/Levels/Marc Lou) — journey narrativa + métricas abertas
10. PMI.org / ProjectManagement.com — canal formal já usado (7 submissões 2025)

### Forças em tensão

1. **Consolidação vs flexibilidade** — Núcleo tem 5 flows separados funcionando. Adicionar primitivo único (`publication_ideas`) pode ser overhead se cada canal continua sendo operado isoladamente. Mitigação: FK opcional, não-bloqueante.

2. **`webinar_series` (#89) vs `publication_series` (aqui)** — mesmo conceito, instâncias diferentes. Decisão: consolidar em `publication_series` com `format_default='multi'` quando série gera tanto blog quanto webinar quanto newsletter. `webinar_series` específico fica para casos onde só webinar (ex.: série de lives).

3. **Blog como produto principal vs blog como side output** — hoje blog é side output (submission vai primeiro ao PM.com). Akita mostra que blog próprio pode ser canal primário, submissão externa é consequence. Equilíbrio: Núcleo pode priorizar PM.com/PMI.org para compliance e blog próprio para série de community-spotlight + behind-the-scenes + weekly-radar + deep-dive + tutorial + rant.

4. **Single-language vs multi-language** — schema `blog_posts.title/excerpt/body_html` já é jsonb i18n pronto (feedback #86 feature_i18n_lang_keys). Hoje populado só em PT. Akita mostra valor de /en/ para reach internacional (alinha AIPM Ambassadors path). Expand é aditivo.

## Decisão

### D1 — Primitivo canônico `publication_series`

Aplicado em commit (migration `20260505060000`):

```sql
CREATE TABLE publication_series (
  id uuid PRIMARY KEY,
  slug text UNIQUE,                 -- 'cpmai-journey', 'behind-nucleo-ia', etc.
  title_i18n jsonb,
  description_i18n jsonb,
  cover_image_url text,
  hero_tribe_id integer REFERENCES tribes(id),
  hero_initiative_id uuid REFERENCES initiatives(id),
  cadence_hint text CHECK (cadence_hint IN ('weekly','biweekly','monthly','quarterly','sporadic','one_shot')),
  format_default text CHECK (format_default IN ('blog_post','webinar','newsletter','podcast','deep_dive','multi')),
  editorial_voice text,              -- "Rant","Crônica","Tutorial técnico"
  target_audience text,
  is_active boolean DEFAULT true
);
```

5 séries seed aplicadas:
- `cpmai-journey` (biweekly, multi) — grupo de estudos CPMAI + preparatório
- `trilha-pesquisador` (monthly, blog_post) — journey do volunteer
- `behind-nucleo-ia` (monthly, blog_post) — crônicas de construção da plataforma
- `weekly-radar-tribe-1` (weekly, newsletter) — digest T1 Radar
- `tribe-2-agents-deep-dive` (monthly, multi) — Agentes Autônomos análises

### D2 — `publication_ideas` primitive (Wave 2)

**NÃO aplicado ainda.** Aguarda validação do modelo D1 por 1 ciclo de operação.

```sql
-- Proposta para próximo sprint
CREATE TABLE publication_ideas (
  id uuid PRIMARY KEY,
  source_type text CHECK (source_type IN ('meeting_action','hub_resource','wiki_page','external_research','experiment','partnership','webinar','ata_decision')),
  source_id uuid,                    -- FK polimórfica
  title text,
  summary text,
  tribe_id integer,
  initiative_id uuid,
  author_ids uuid[],
  proposed_channels text[],
  stage text CHECK (stage IN ('draft','researching','writing','curation','review','approved','published','archived')),
  series_id uuid REFERENCES publication_series(id),
  target_languages text[] DEFAULT ARRAY['pt-BR'],
  created_at timestamptz,
  published_at timestamptz
);

-- FK opcionais em tabelas existentes
ALTER TABLE blog_posts ADD COLUMN source_idea_id uuid REFERENCES publication_ideas(id);
ALTER TABLE publication_submissions ADD COLUMN source_idea_id uuid REFERENCES publication_ideas(id);
ALTER TABLE campaign_sends ADD COLUMN source_idea_id uuid REFERENCES publication_ideas(id);
ALTER TABLE public_publications ADD COLUMN source_idea_id uuid REFERENCES publication_ideas(id);
```

### D3 — Expanded `blog_posts.category` enum

Aplicado em commit:
- Antigo (4): case-study, tutorial, announcement, opinion
- Novo (10): + deep-dive, weekly-radar, community-spotlight, behind-the-scenes, rant, research-findings

### D4 — `blog_posts.series_id` + `series_position` + `github_repo_url`

Aplicado em commit:
- `series_id uuid REFERENCES publication_series(id)` — FK opcional, posts órfãos são OK
- `series_position smallint` — ordem narrativa na série (Akita pattern)
- `github_repo_url text` — repo reproducível (padrão Akita/GitHub Blog)

### D5 — Multi-language expansion (Wave 4)

**NÃO aplicado ainda.** Schema já suporta via jsonb i18n. Aguarda decisão operacional de investir em translations. Recomendação: começar com últimos 12 posts em EN (alinha AIPM outreach).

### D6 — Consolidação `webinar_series` × `publication_series`

Proposta: **NÃO criar `webinar_series` table separada** (#89 Frente 2). Ao invés, usar `publication_series` com `format_default='webinar'` para séries exclusivamente webinar. Para séries cross-format (ex.: CPMAI Journey gera blog+webinar+newsletter), usar `format_default='multi'`.

Dividendo: 1 primitivo, N formats. Consistente com princípio ADR-0015 (consolidação de domínios).

### D7 — Diretrizes de cadência e voice (editorial guideline)

Cada série declara `cadence_hint` e `editorial_voice`. Não é contratual — é convenção editorial para manter consistência. Quando tribe líder abandona cadência, `is_active=false` e `cadence_hint` preserva registro histórico.

Playbook operacional (quando escrever, como titular, quando switchar idioma) fica em `docs/editorial/CONTENT_PIPELINE_PLAYBOOK.md` (draft local, target: wiki `nucleo-ia-gp/wiki`).

## Consequências

### Positivas

- **Primitivo canônico** para agrupar content do Núcleo — reduz chaos de 12 tabelas para 1 conceito operacional
- **Consistência com Akita pattern** proven (21 anos, 500+ posts) — reduz risk de reinventar
- **Diferencia conteúdo** por voice/audience — Trilha Pesquisador ≠ Behind Núcleo ≠ Weekly Radar
- **Prepara AIPM outreach internacional** — jsonb i18n pronto, só faltam translations
- **GitHub repo link** para posts técnicos — aumenta credibilidade + reach dev
- **Consolida `webinar_series` × `publication_series`** — 1 primitivo, menos débito técnico futuro

### Negativas

- **Overhead editorial** — alguém precisa curar séries, garantir cadência, manter voice consistente. Recomendação: atribuir cada série a um líder específico (GP, comms_leader, ou tribo).
- **Decisão pendente sobre `publication_ideas`** — Wave 2 aguarda validação D1. Risco: D1 fica órfão se Wave 2 nunca vier.
- **Multi-language requer investimento** — LLM translation + review humano para EN. Custo: ~30min por post.

### Não-consequências

- Não substitui fluxo atual de submission formal (PM.com/PMI.org) — segue como está
- Não muda `publication_submissions` workflow — séries referenciam submission, não substituem
- Não quebra blog_posts existentes — `series_id` é opcional

## Alternativas consideradas

1. **`webinar_series` + `publication_series` separados** (original #89) — rejeitada. Over-modeling, 1 conceito só.
2. **`publication_ideas` aplicado junto** — rejeitada. Conservador: validar D1 em produção por 1 ciclo, então adicionar orquestração.
3. **Sem primitivo de séries** (continuar flat) — rejeitada. Akita demonstra valor de séries para SEO, retenção de leitor, storytelling.
4. **Séries como campo string em blog_posts** (sem table) — rejeitada. Perde-se metadata (cadence, voice, hero_tribe, cover_image).

## Waves futuras

| Wave | Conteúdo | Esforço | Risco |
|---|---|---|---|
| **W1** (APLICADA) | Schema `publication_series` + 5 seeds + category expand + series_id FK | 2h | 🟢 Baixo |
| **W2** | `publication_ideas` primitivo + FKs | 4-6h | 🟡 Médio |
| **W3** | MCP tools pipeline (`propose_idea`, `advance_stage`, `fork_to_channel`) | 4-6h | 🟡 Médio |
| **W4** | Multi-language expansion (12 posts para EN) | 1 sprint | 🟢 Baixo (aditivo) |
| **W5** | Série "Behind Núcleo IA" (começar com post sobre esta sessão 9908f3) | Contínuo | 🟢 Zero |

## Métricas de sucesso

Após 6 meses (out/2026):
- ≥ 5 séries ativas com ≥ 3 posts cada
- blog_posts volume: 12 → 50+ (4x growth)
- Pelo menos 1 série cross-format (blog + webinar + newsletter) completa
- `github_repo_url` populado em ≥ 50% dos posts `tutorial` e `deep-dive`
- `series_id` populado em ≥ 80% dos novos posts

Se métricas falham: revisar se séries estão com dono claro (atribuição), cadência realista, audiência alinhada.

## Cross-ref

- **Issue #94** — contexto completo + benchmark 10 cases
- **Issue #89** Frente 3 — `webinar_series` proposta. Este ADR **substitui** com `publication_series` + `format_default='webinar'`.
- **Issue #84** — Meeting↔Board traceability. `meeting_action_items` podem virar source_type='meeting_action' de `publication_ideas` (W2).
- **Issue #86** — Knowledge infra dormida. Conectar `knowledge_assets` como source de ideias.
- **Issue #93** Op #1 — APM como conteúdo T2. Post candidato para série `tribe-2-agents-deep-dive`.
- **Issue #93** Op #2 — AI Briefing Skill. Feed direto para `source_type='external_research'`.
- **ADR-0010** — wiki scope (narrative vs SQL operational). Playbook editorial fica em wiki repo.
- **ADR-0015** — consolidação de domínios. D6 (consolidação webinar/publication series) aplica mesmo princípio.

## Referências

- [akitaonrails.com/en](https://akitaonrails.com/en/) — 21 anos de blog, exemplo canônico de séries
- Migration `20260505060000` — aplicação W1
- Sessão debug 9908f3 (21/Abr/2026) — contexto completo

## Aprovação

W1 aplicado p35 como conservative bet (aditivo, rollback fácil). 22 dias em prod sem regressão.

**Status: Accepted p95 (2026-05-05)** — PM Vitor ratified.

---

## Amendment 1 (p95 2026-05-05) — 4 PM decisions for W2

PM Vitor ratified 4 decisions enabling W2 (`publication_ideas` table) shipping:

### D1 (PM 2A) — Status promotion
Proposed → **Accepted**. W1 substrate stable, spec sólida, no objections raised in 22d window.

### D2 (PM 2B) — Editorial language policy
**PT-BR primary + EN obrigatório para Frontiers Newsletter (audience PMI Latam) — bilingual content via jsonb expansion.**

Rationale:
- Resolve #96 EN-only vs PT-first conflict
- Aligns with ADR-0010 (narrative knowledge) + atende ambos públicos (BR voluntários ~40% não-EN-fluentes vs PMI Latam audience EN-required)
- Cost: tradução effort scales linearly per post; mitigation = AI-assisted translation (Anthropic via existing infra) + human review for tier-1 content (Frontiers Newsletter)
- jsonb fields (`title_i18n`, `description_i18n`, `body_html_i18n` etc.) já usado em `blog_posts` + `publication_series`. Pattern consistent.
- `target_languages text[] DEFAULT ARRAY['pt-BR']` for `publication_ideas` (each idea declara seus idiomas explicitamente)

### D3 (PM 2C) — Channel taxonomy
**Liberate all proposed channels** (`proposed_channels text[]` aceita PMI.org, PM.com, blog interno, newsletter, LinkedIn, Medium, Dev.to, YouTube, podcast).

Rationale:
- Maximum optionality: each `publication_ideas` row pode declarar 1-N channels candidates
- Não compromete a publicar em todos — só lista possíveis
- PMI brand guidelines aplicam case-by-case na `stage='approved'` review
- Substack/Ghost out of scope (Resend + React Email já cobre)
- Cross-platform syndication respeita CC-BY-SA quando aplicável (ADR-0010)

### D4 (PM 2D) — Polymorphic source FK pattern
**Endorse polymorphic** — `source_type text + source_id uuid` (no FK constraint, but indexed).

Rationale:
- An idea pode vir de hub_resource OR wiki_page OR meeting_action OR external_research OR experiment OR partnership OR webinar OR ata_decision (8 source types per spec)
- Strict FK per source type would explode schema with N nullable FK columns OR N intermediate tables
- Postgres handles polymorphic well via filtered indexes (`CREATE INDEX ... WHERE source_type = 'X'`)
- Trade-off accepted: integrity validation moves to application layer (RPC on insert) instead of FK constraint
- Pattern precedent: `notifications.source_type/source_id` (existing, working)

### Implementation gate

Amendment 1 unblocks W2 (`publication_ideas` table) implementation. Schema migration TBD next session.

W2 dependencies (validated):
- ✅ ADR-0020 Accepted
- ✅ EN/PT decision (jsonb i18n pattern)
- ✅ Channel taxonomy (text[] enum)
- ✅ Polymorphic FK (text + uuid + filtered indexes)

W3-W5 (multi-channel pipeline, RSS/author pages, dark mode, etc.) follow W2.
