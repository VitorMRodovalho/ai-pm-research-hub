# Guia Editorial — Frontiers in AI & Project Mgmt
## v1.x — pivot to `content_products` (ADR-0099) · trilingual · biweekly · CC BY-SA 4.0 · C2/C3/C4 ratificadas (p268)

> **Status (this draft):** authored 2026-05-25 (p267), patched 2026-05-26 (p268). Target storage: `governance_documents.id = 18ec4690-4f5a-4cab-904d-451e2c7245bf` (`doc_type=editorial_guide`, `status=draft`, `current_version_id=NULL`). Once locked via `lock_document_version`, the editorial_guide gate template fires 3 internal gates (`curator` + `leader_awareness` + `submitter_acceptance`); no PMI Boards/witnesses required for this `doc_type`.
>
> **Resolves (D-decisions ratified pre-v1):** F1 (Frontiers as a platform-governed series, not parallel pipeline) · F2 (trilingual EN/PT/ES native parity) · F3 (CC BY-SA 4.0 as default license) · F7 (formal trademark search de-escalated; passive monitoring + defensive disclaimer) · cadence biweekly · pivot to `content_products` canonical surface (ADR-0099 §2.1) — `publication_ideas` NOT used; the SQL Block 2 of `SPEC_FRONTIERS_NEWSLETTER_LAUNCH.md` is **OBSOLETE / SUPERSEDED**.
>
> **Resolves (C-decisions ratified in v1.x, p268):**
> - **C2** — `review_mode` default por `target_instrument` ratificado conforme tabela em §5 (`sequential` para long-form / `collaborative` para short-form / `independent_blind` para externos magazine/journal).
> - **C3** — shape jsonb das 3 declarações obrigatórias = **flat keys top-level** em `content_products.publication_metadata`. Exemplo concreto em §6.
> - **C4** — originalidade = **mecanismo híbrido ratificado**: curadoria manual sempre + `check_idea_originality` (#95) quando shipped (flag `originality_warning=true`, não bloqueia).
>
> **Still pending external (Gate 0 jurídico):** CR-050 v2.2 (Política de PI) ratification + R3-C4/aditivo for volunteer term covering Case Studies + CC licensing + AI disclosure + employer consent. The Guide cannot publish issue #1 before Gate 0 closes.
>
> **Still pending decision (C5, deferred to v2):** C5 pilot author for issue #1 — decisão diferida até Gate 0 jurídico cair (CR-050 + R3-C4 ratificadas). Sem sentido nomear autor pre-Gate-0; quando ratificarem, abrir issue dedicada `frontiers-issue-1-pilot`.
>
> **Author of this draft:** Vitor Maia Rodovalho (PM); proposer-of-record on `governance_documents.proposer_member_id` is Fabricio Costa (`92d26057-…`).

---

# 1. Propósito + escopo · Purpose + scope · Propósito + alcance

<section lang="pt-BR">

## 1. Propósito + escopo (PT-BR — canonical)

Este Guia define **como o Núcleo IA & GP produz, revisa, publica e arquiva conteúdo editorial sob a marca _Frontiers in AI & Project Mgmt_** — uma newsletter quinzenal trilíngue (EN/PT/ES) e os produtos editoriais derivados (artigos, posts LinkedIn, recaps de webinar, frameworks, estudos de caso, entrevistas, papers de tribo).

O escopo do Guia inclui:

- Padrão editorial (voz, tom, audiência, formatos aceitos).
- Cadência e calendário.
- Política trilíngue (paridade nativa, não tradução automática).
- Tipos de conteúdo aceitos e mapeamento para o primitivo `content_products` da plataforma (ADR-0099).
- Princípios autorais e declarações obrigatórias (uso de IA, consentimento do empregador, conflitos de interesse).
- Licenciamento default e regime de exceção.
- Fluxo de revisão por modo (`review_mode`) e estados (`status`).
- Governança editorial (curadoria, lideranças cientes, aceite do GP) e relação com a governança jurídica do Núcleo (Política de PI, Termo de Adesão Voluntário, Manual de Governança).
- Marca e disclaimers defensivos.
- Manutenção e cadência de revisão deste próprio Guia.

O escopo **não inclui**: marketing pago, programas de afiliado, conteúdo patrocinado, qualquer modalidade comercial. Frontiers é uma newsletter aberta, sem fins lucrativos, governada como parte da operação do Núcleo IA & GP.

</section>

<section lang="en">

## 1. Purpose + scope (EN — native parity)

This Guide defines **how Núcleo IA & GP produces, reviews, publishes and archives editorial content under the _Frontiers in AI & Project Mgmt_ brand** — a biweekly trilingual newsletter (EN/PT/ES) and its derived editorial products (articles, LinkedIn posts, webinar recaps, frameworks, case studies, interviews, tribe research papers).

The scope of this Guide includes:

- Editorial standard (voice, tone, audience, accepted formats).
- Cadence and calendar.
- Trilingual policy (native parity, not machine translation).
- Accepted content types and their mapping to the platform `content_products` primitive (ADR-0099).
- Authorship principles and mandatory declarations (AI usage, employer consent, conflicts of interest).
- Default license and exception regime.
- Review flow by mode (`review_mode`) and state (`status`).
- Editorial governance (curator, leader awareness, GP submitter acceptance) and how it relates to the Núcleo's legal governance (IP Policy, Volunteer Agreement, Governance Manual).
- Brand and defensive disclaimers.
- Maintenance and review cadence of this Guide itself.

The scope **does not include**: paid marketing, affiliate programs, sponsored content, or any commercial modality. Frontiers is an open, non-commercial newsletter, governed as part of Núcleo IA & GP operations.

</section>

<section lang="es-LA">

## 1. Propósito + alcance (ES — paridad nativa)

Esta Guía define **cómo el Núcleo IA & GP produce, revisa, publica y archiva contenido editorial bajo la marca _Frontiers in AI & Project Mgmt_** — un boletín quincenal trilingüe (EN/PT/ES) y los productos editoriales derivados (artículos, posts de LinkedIn, recaps de webinars, frameworks, estudios de caso, entrevistas, papers de tribus de investigación).

El alcance de esta Guía incluye:

- Estándar editorial (voz, tono, audiencia, formatos aceptados).
- Cadencia y calendario.
- Política trilingüe (paridad nativa, no traducción automática).
- Tipos de contenido aceptados y su mapeo al primitivo `content_products` de la plataforma (ADR-0099).
- Principios autorales y declaraciones obligatorias (uso de IA, consentimiento del empleador, conflictos de interés).
- Licencia predeterminada y régimen de excepción.
- Flujo de revisión por modo (`review_mode`) y estado (`status`).
- Gobernanza editorial (curador, lideranças informadas, aceptación del GP) y su relación con la gobernanza jurídica del Núcleo (Política de PI, Acuerdo de Voluntariado, Manual de Gobernanza).
- Marca y disclaimers defensivos.
- Mantenimiento y cadencia de revisión de esta propia Guía.

El alcance **no incluye**: marketing pagado, programas de afiliados, contenido patrocinado, ni ninguna modalidad comercial. Frontiers es un boletín abierto, no comercial, gobernado como parte de la operación del Núcleo IA & GP.

</section>

---

# 2. Posicionamento editorial · Editorial positioning · Posicionamiento editorial

<section lang="pt-BR">

## 2. Posicionamento editorial (PT-BR)

**Audiência primária:** PMs profissionais no Brasil, América Latina e mercados internacionais que usam IA no dia a dia da gestão de projetos. Inclui pesquisadores, líderes de tribo, executivos PMI, membros voluntários do Núcleo e o público externo interessado em PM aumentado por IA.

**Audiência secundária:** academia (programas de PM + IA), times de comms PMI capítulos, redes de inovação corporativa.

**Voz:** profissional, neutra, institucional. Trilíngue nativa (não traduzida).

**Tom:** rigoroso sem ser hermético; concreto sem ser superficial; opiniões fortes apresentadas com fundamentação. Evitar marketing-speak e hype gratuito.

**Promessa editorial:** cada issue traz pelo menos um artefato útil — um framework reutilizável, um estudo de caso replicável, uma análise comparativa de ferramentas, uma síntese de pesquisa, uma entrevista com profissional sênior, ou um recap de evento com extração de insights práticos.

**Anti-promessa (o que Frontiers NÃO é):** não é peer-reviewed journal científico; não é canal de divulgação corporativa; não é coluna de opinião pessoal sem fundamentação; não é catálogo de cursos ou certificações.

</section>

<section lang="en">

## 2. Editorial positioning (EN)

**Primary audience:** professional PMs in Brazil, Latin America and international markets who use AI day-to-day in project management. Includes researchers, tribe leaders, PMI executives, Núcleo volunteer members, and external audiences interested in AI-augmented PM.

**Secondary audience:** academia (PM + AI programs), PMI chapter comms teams, corporate innovation networks.

**Voice:** professional, neutral, institutional. Trilingual native (not translated).

**Tone:** rigorous without being arcane; concrete without being superficial; strong opinions defended with substance. Avoid marketing-speak and gratuitous hype.

**Editorial promise:** each issue ships at least one usable artifact — a reusable framework, a replicable case study, a comparative tool analysis, a research synthesis, a senior-practitioner interview, or an event recap with extracted practical insights.

**Anti-promise (what Frontiers is NOT):** not a peer-reviewed scientific journal; not a corporate PR channel; not personal opinion columns without grounding; not a catalog of courses or certifications.

</section>

<section lang="es-LA">

## 2. Posicionamiento editorial (ES)

**Audiencia primaria:** PMs profesionales en Brasil, América Latina y mercados internacionales que usan IA en la gestión de proyectos del día a día. Incluye investigadores, líderes de tribu, ejecutivos PMI, miembros voluntarios del Núcleo y audiencias externas interesadas en PM aumentado por IA.

**Audiencia secundaria:** academia (programas de PM + IA), equipos de comunicación de capítulos PMI, redes de innovación corporativa.

**Voz:** profesional, neutra, institucional. Trilingüe nativa (no traducida).

**Tono:** riguroso sin ser hermético; concreto sin ser superficial; opiniones fuertes defendidas con sustancia. Evitar marketing-speak y hype gratuito.

**Promesa editorial:** cada issue entrega al menos un artefacto útil — un framework reutilizable, un estudio de caso replicable, un análisis comparativo de herramientas, una síntesis de investigación, una entrevista con un profesional sénior, o un recap de evento con extracción de insights prácticos.

**Anti-promesa (lo que Frontiers NO es):** no es un journal científico peer-reviewed; no es un canal de PR corporativo; no es una columna de opinión personal sin fundamentación; no es un catálogo de cursos o certificaciones.

</section>

---

# 3. Cadência e calendário · Cadence + calendar · Cadencia y calendario

<section lang="pt-BR">

## 3. Cadência (PT-BR)

**Cadência ratificada:** **biweekly** (uma issue a cada 2 semanas), 26 issues/ano. Ratificada pelo GP em 2026-04-21 como upgrade vs. mensal originalmente proposto.

**Calendário operacional:**

- **Semana A** (dia 1): publica issue N.
- **Semana A** (dias 2–5): kickoff editorial da issue N+1 (curador + autor designado).
- **Semana A** (dias 6–7) + **Semana B** (dias 8–10): autoria + revisão por pares.
- **Semana B** (dias 11–12): revisão de lideranças cientes + aceite do GP.
- **Semana B** (dia 14): publicação de issue N+1 (= dia 1 do próximo ciclo).

Issues atrasadas re-entram no ciclo seguinte (não duplica). Issues canceladas viram `archived` no `content_products`; nova issue ocupa o slot do ciclo.

</section>

<section lang="en">

## 3. Cadence (EN)

**Ratified cadence:** **biweekly** (one issue every 2 weeks), 26 issues/year. Ratified by GP on 2026-04-21 as an upgrade vs. the originally-proposed monthly cadence.

**Operational calendar:**

- **Week A** (day 1): publishes issue N.
- **Week A** (days 2–5): editorial kickoff of issue N+1 (curator + assigned author).
- **Week A** (days 6–7) + **Week B** (days 8–10): authorship + peer review.
- **Week B** (days 11–12): leader-awareness review + GP submitter acceptance.
- **Week B** (day 14): issue N+1 publishes (= day 1 of next cycle).

Late issues re-enter the next cycle (no duplication). Cancelled issues become `archived` in `content_products`; a new issue takes the cycle slot.

</section>

<section lang="es-LA">

## 3. Cadencia (ES)

**Cadencia ratificada:** **biweekly** (un issue cada 2 semanas), 26 issues/año. Ratificada por el GP el 2026-04-21 como upgrade vs. la cadencia mensual originalmente propuesta.

**Calendario operacional:**

- **Semana A** (día 1): publica issue N.
- **Semana A** (días 2–5): kickoff editorial del issue N+1 (curador + autor asignado).
- **Semana A** (días 6–7) + **Semana B** (días 8–10): autoría + revisión por pares.
- **Semana B** (días 11–12): revisión de lideranças informadas + aceptación del GP.
- **Semana B** (día 14): publicación del issue N+1 (= día 1 del próximo ciclo).

Los issues atrasados re-entran al ciclo siguiente (no se duplican). Los issues cancelados se vuelven `archived` en `content_products`; un nuevo issue toma el slot del ciclo.

</section>

---

# 4. Política trilíngue · Trilingual policy · Política trilingüe

<section lang="pt-BR">

## 4. Política trilíngue (PT-BR)

**Princípio:** paridade nativa EN/PT/ES — não tradução automática.

**Operacionalização:** cada issue gera 3 produtos publicados simultaneamente. Cada produto é uma `content_products` row distinta, agrupada via `derived_group_id` self-FK (ADR-0099 §2.3) com o produto-semente apontando para si mesmo. As outras 2 línguas apontam para a semente.

**Fonte canônica:** EN é a fonte canônica editorial — quando há divergência interpretativa, o texto EN prevalece. PT e ES são versões nativas paralelas, não traduções subordinadas.

**Tempo de revisão:** 60–90 min por issue para tradução + revisão humana (~20–30 min por idioma). Não publicar uma issue até que as 3 línguas estejam prontas — atrasar a issue inteira é preferível a publicar parcialmente.

**Tradução assistida por LLM é permitida**, mas SEMPRE com revisão humana fluente no idioma de destino. Marcar `metadata.translation_assistance` com modelo + escopo quando usada.

**Glossário trilíngue** (mantido em `wiki_pages` ou anexado ao Guia em versões futuras): termos PM + IA com tradução validada (ex: "stakeholder" → "parte interessada" PT / "parte interesada" ES; "backlog" mantém termo em EN nas 3 línguas, etc.). v1 não inclui glossário — fica para v2.

</section>

<section lang="en">

## 4. Trilingual policy (EN)

**Principle:** native EN/PT/ES parity — not machine translation.

**Operationalization:** each issue produces 3 simultaneously-published products. Each product is a distinct `content_products` row, grouped via `derived_group_id` self-FK (ADR-0099 §2.3) with the seed product pointing at itself. The other 2 languages point at the seed.

**Canonical source:** EN is the editorial canonical source — when interpretive divergence arises, the EN text prevails. PT and ES are parallel native versions, not subordinate translations.

**Review time:** 60–90 min per issue for translation + human review (~20–30 min per language). Do not publish an issue until all 3 languages are ready — delay the whole issue rather than publish partial.

**LLM-assisted translation is allowed**, but ALWAYS with human review by a fluent speaker of the target language. Mark `metadata.translation_assistance` with model + scope when used.

**Trilingual glossary** (maintained in `wiki_pages` or attached to the Guide in future versions): PM + AI terms with validated translation (e.g., "stakeholder" → "parte interessada" PT / "parte interesada" ES; "backlog" stays in EN across all 3 languages). v1 does not include the glossary — deferred to v2.

</section>

<section lang="es-LA">

## 4. Política trilingüe (ES)

**Principio:** paridad nativa EN/PT/ES — no traducción automática.

**Operacionalización:** cada issue genera 3 productos publicados simultáneamente. Cada producto es una `content_products` row distinta, agrupada vía `derived_group_id` self-FK (ADR-0099 §2.3) con el producto-semilla apuntando a sí mismo. Las otras 2 lenguas apuntan a la semilla.

**Fuente canónica:** EN es la fuente canónica editorial — cuando hay divergencia interpretativa, el texto EN prevalece. PT y ES son versiones nativas paralelas, no traducciones subordinadas.

**Tiempo de revisión:** 60–90 min por issue para traducción + revisión humana (~20–30 min por idioma). No publicar un issue hasta que las 3 lenguas estén listas — atrasar el issue completo es preferible a publicar parcialmente.

**Traducción asistida por LLM está permitida**, pero SIEMPRE con revisión humana por hablante fluente del idioma destino. Marcar `metadata.translation_assistance` con modelo + alcance cuando se use.

**Glosario trilingüe** (mantenido en `wiki_pages` o adjunto a la Guía en versiones futuras): términos PM + IA con traducción validada (ej.: "stakeholder" → "parte interessada" PT / "parte interesada" ES; "backlog" se mantiene en EN en las 3 lenguas). v1 no incluye el glosario — diferido a v2.

</section>

---

# 5. Tipos de conteúdo · Content types · Tipos de contenido

<section lang="pt-BR">

## 5. Tipos de conteúdo aceitos (PT-BR)

Cada tipo mapeia 1:1 para um `target_instrument` do `content_products` (ADR-0099 §2.4). A primeira issue de cada tipo passa por revisão editorial dupla (curador + GP) antes de estabilizar o padrão.

| Tipo do Guia | `target_instrument` | Tamanho típico | `review_mode` default sugerido* |
|---|---|---|---|
| Lead Article | `linkedin_newsletter` ou `hub_article` | 1.500–3.500 palavras | `sequential` |
| Supporting Insight | `linkedin_post` ou `hub_article` | 400–900 palavras | `collaborative` |
| Framework / Model | `hub_article` | 1.200–2.500 palavras | `sequential` |
| Case Study / Use Case | `hub_article` ou `magazine_article` | 1.500–3.000 palavras | `sequential` (ou `independent_blind` se enviada a magazine externa) |
| Webinar & Event Recap | `hub_article` ou `linkedin_post` | 800–1.500 palavras | `collaborative` |
| Expert Interview | `hub_article` ou `podcast_episode` | 1.200–2.500 palavras | `collaborative` |
| Research Stream Insight | `linkedin_newsletter` | 600–1.200 palavras | `sequential` |

\* `review_mode` default **ratificado (p268, C2)**. A tabela acima é a fonte canônica de defaults; cada `content_products` row pode override em casos pontuais com justificativa em `publication_metadata.review_mode_override_reason`.

`source_kind` (ADR-0099 §2.2) por origem:
- Conteúdo derivado deste Guia ratificado → `source_kind='governance_document_version'` apontando para a v ratificada do Guia.
- Conteúdo derivado de paper/relatório de tribo → `source_kind='board_item'`.
- Entrevista, recap, conteúdo de parceiro → `source_kind='external'` com `source_external_uri` populado.
- One-off (raro) → `source_kind='none'`.

</section>

<section lang="en">

## 5. Accepted content types (EN)

Each type maps 1:1 to a `target_instrument` of `content_products` (ADR-0099 §2.4). The first issue of each type passes through dual editorial review (curator + GP) before the pattern stabilizes.

| Guide type | `target_instrument` | Typical length | Suggested default `review_mode`* |
|---|---|---|---|
| Lead Article | `linkedin_newsletter` or `hub_article` | 1,500–3,500 words | `sequential` |
| Supporting Insight | `linkedin_post` or `hub_article` | 400–900 words | `collaborative` |
| Framework / Model | `hub_article` | 1,200–2,500 words | `sequential` |
| Case Study / Use Case | `hub_article` or `magazine_article` | 1,500–3,000 words | `sequential` (or `independent_blind` if submitted to external magazine) |
| Webinar & Event Recap | `hub_article` or `linkedin_post` | 800–1,500 words | `collaborative` |
| Expert Interview | `hub_article` or `podcast_episode` | 1,200–2,500 words | `collaborative` |
| Research Stream Insight | `linkedin_newsletter` | 600–1,200 words | `sequential` |

\* Default `review_mode` is **ratified (p268, C2)**. The table above is the canonical source of defaults; each `content_products` row may override in pointed cases with justification in `publication_metadata.review_mode_override_reason`.

`source_kind` (ADR-0099 §2.2) by origin:
- Content derived from this ratified Guide → `source_kind='governance_document_version'` pointing at the ratified version of the Guide.
- Content derived from tribe research paper/report → `source_kind='board_item'`.
- Interview, recap, partner content → `source_kind='external'` with `source_external_uri` populated.
- One-off (rare) → `source_kind='none'`.

</section>

<section lang="es-LA">

## 5. Tipos de contenido aceptados (ES)

Cada tipo mapea 1:1 a un `target_instrument` de `content_products` (ADR-0099 §2.4). El primer issue de cada tipo pasa por revisión editorial doble (curador + GP) antes de estabilizar el patrón.

| Tipo de la Guía | `target_instrument` | Tamaño típico | `review_mode` predeterminado sugerido* |
|---|---|---|---|
| Lead Article | `linkedin_newsletter` o `hub_article` | 1.500–3.500 palabras | `sequential` |
| Supporting Insight | `linkedin_post` o `hub_article` | 400–900 palabras | `collaborative` |
| Framework / Model | `hub_article` | 1.200–2.500 palabras | `sequential` |
| Case Study / Use Case | `hub_article` o `magazine_article` | 1.500–3.000 palabras | `sequential` (o `independent_blind` si se envía a magazine externa) |
| Webinar & Event Recap | `hub_article` o `linkedin_post` | 800–1.500 palabras | `collaborative` |
| Expert Interview | `hub_article` o `podcast_episode` | 1.200–2.500 palabras | `collaborative` |
| Research Stream Insight | `linkedin_newsletter` | 600–1.200 palabras | `sequential` |

\* El `review_mode` predeterminado está **ratificado (p268, C2)**. La tabla anterior es la fuente canónica de predeterminados; cada `content_products` row puede sobrescribirse en casos puntuales con justificación en `publication_metadata.review_mode_override_reason`.

`source_kind` (ADR-0099 §2.2) por origen:
- Contenido derivado de esta Guía ratificada → `source_kind='governance_document_version'` apuntando a la versión ratificada de la Guía.
- Contenido derivado de paper/reporte de tribu → `source_kind='board_item'`.
- Entrevista, recap, contenido de socio → `source_kind='external'` con `source_external_uri` poblado.
- One-off (raro) → `source_kind='none'`.

</section>

---

# 6. Princípios autorais · Authorship principles · Principios autorales

<section lang="pt-BR">

## 6. Princípios autorais + 3 declarações obrigatórias (PT-BR)

Todo autor que submete material para o Frontiers concorda com 3 princípios:

1. **Honestidade intelectual** — fontes citadas com rigor; opiniões claramente marcadas como tal; dados verificáveis ou marcados como anedóticos.
2. **Atribuição** — coautores reconhecidos; ferramentas de IA usadas declaradas; material de terceiros licenciado ou de domínio público.
3. **Não-prejuízo** — material não expõe pessoas, parceiros ou empregadores sem consentimento documentado; não viola NDA; não infringe propriedade intelectual de terceiros.

**3 declarações obrigatórias** a serem capturadas em `content_products.publication_metadata jsonb` (**shape ratificado p268, C3 — flat keys no top-level**). Sem as 3 declarações o produto não avança além de `drafted`. Exemplo concreto:

```json
{
  "ai_usage_declaration": "Claude Opus 4.7 usado para sugestão de outline + revisão de prosa em ~30% do produto final; redação substantiva humana.",
  "employer_consent_confirmed": true,
  "conflicts_of_interest": "PMP ativo + sem sponsors/vendor relationships relevantes neste tema.",
  "cc_license": "CC BY-SA 4.0"
}
```

As 3 chaves (`ai_usage_declaration` / `employer_consent_confirmed` / `conflicts_of_interest`) ficam no top-level de `publication_metadata`, junto com `cc_license` (§7) e quaisquer outras chaves técnicas (`review_mode_override_reason`, `translation_assistance`, `originality_warning`, `originality_review_notes`). Pattern alinhado com p213 ADR-0095 (sediment-aligned) e consulta jsonb-friendly via operador `?`.

- **`ai_usage_declaration`** — descrição textual: qual(is) ferramenta(s) de IA generativa foi(ram) usada(s); escopo (ex: ideação, redação, edição, tradução, ilustração); aproximação do percentual do produto final atribuível a IA. Política mãe: CR-050 v2.2 §4 (sob ratificação).
- **`employer_consent_confirmed`** — boolean atestando que material proprietário do empregador (se houver) tem autorização documentada para uso público no Frontiers. Protege autor e Núcleo contra ação de NDA. Quando `true`, autor deve manter prova (e-mail, política interna pública, autorização escrita) acessível em caso de auditoria.
- **`conflicts_of_interest`** — string listando afiliações relevantes do autor: certificações PMI ativas, sponsors, empregador atual, relacionamentos de vendor, posições em conselhos, holdings financeiras em ferramentas mencionadas. Padrão emprestado de arXiv/IEEE.

Quando `source_kind='governance_document_version'` apontando para este Guia, esses 3 campos são obrigatórios no produto. Quando `source_kind='external'` (entrevista, parceiro), os 3 campos são fortemente recomendados mas a obrigatoriedade é decidida caso a caso pelo curador.

</section>

<section lang="en">

## 6. Authorship principles + 3 mandatory declarations (EN)

Every author who submits material for Frontiers agrees to 3 principles:

1. **Intellectual honesty** — sources cited rigorously; opinions clearly flagged as such; data either verifiable or labeled as anecdotal.
2. **Attribution** — co-authors credited; AI tools used declared; third-party material licensed or public-domain.
3. **No-harm** — material does not expose people, partners or employers without documented consent; does not violate NDA; does not infringe third-party IP.

**3 mandatory declarations** captured in `content_products.publication_metadata jsonb` (**shape ratified p268, C3 — flat keys at top level**). Without all 3 declarations the product cannot advance beyond `drafted`. Concrete example:

```json
{
  "ai_usage_declaration": "Claude Opus 4.7 used for outline suggestion + prose revision on ~30% of the final product; substantive writing human.",
  "employer_consent_confirmed": true,
  "conflicts_of_interest": "Active PMP + no relevant sponsors/vendor relationships on this topic.",
  "cc_license": "CC BY-SA 4.0"
}
```

The 3 keys (`ai_usage_declaration` / `employer_consent_confirmed` / `conflicts_of_interest`) sit at the top level of `publication_metadata`, alongside `cc_license` (§7) and other technical keys (`review_mode_override_reason`, `translation_assistance`, `originality_warning`, `originality_review_notes`). Pattern aligned with p213 ADR-0095 (sediment-aligned) and jsonb-friendly via the `?` operator.

- **`ai_usage_declaration`** — text description: which generative AI tool(s) were used; scope (e.g., ideation, drafting, editing, translation, illustration); approximate percentage of final product attributable to AI. Parent policy: CR-050 v2.2 §4 (under ratification).
- **`employer_consent_confirmed`** — boolean attesting that any proprietary employer material has documented authorization for public use on Frontiers. Protects author and Núcleo from NDA action. When `true`, author must keep proof (email, public internal policy, written authorization) accessible for audit.
- **`conflicts_of_interest`** — string listing relevant author affiliations: active PMI certifications, sponsors, current employer, vendor relationships, board positions, financial holdings in tools mentioned. Pattern borrowed from arXiv/IEEE.

When `source_kind='governance_document_version'` pointing at this Guide, these 3 fields are mandatory on the product. When `source_kind='external'` (interview, partner), the 3 fields are strongly recommended but mandatoriness is decided case-by-case by the curator.

</section>

<section lang="es-LA">

## 6. Principios autorales + 3 declaraciones obligatorias (ES)

Todo autor que somete material para Frontiers acuerda con 3 principios:

1. **Honestidad intelectual** — fuentes citadas con rigor; opiniones claramente marcadas como tales; datos verificables o etiquetados como anecdóticos.
2. **Atribución** — coautores reconocidos; herramientas de IA usadas declaradas; material de terceros licenciado o de dominio público.
3. **No daño** — el material no expone personas, socios ni empleadores sin consentimiento documentado; no viola NDA; no infringe la propiedad intelectual de terceros.

**3 declaraciones obligatorias** capturadas en `content_products.publication_metadata jsonb` (**shape ratificado p268, C3 — flat keys en el top-level**). Sin las 3 declaraciones el producto no avanza más allá de `drafted`. Ejemplo concreto:

```json
{
  "ai_usage_declaration": "Claude Opus 4.7 usado para sugerir outline + revisar prosa en ~30% del producto final; redacción sustantiva humana.",
  "employer_consent_confirmed": true,
  "conflicts_of_interest": "PMP activo + sin sponsors/relaciones de vendor relevantes en este tema.",
  "cc_license": "CC BY-SA 4.0"
}
```

Las 3 claves (`ai_usage_declaration` / `employer_consent_confirmed` / `conflicts_of_interest`) están en el top-level de `publication_metadata`, junto con `cc_license` (§7) y otras claves técnicas (`review_mode_override_reason`, `translation_assistance`, `originality_warning`, `originality_review_notes`). Patrón alineado con p213 ADR-0095 (sediment-aligned) y jsonb-friendly vía el operador `?`.

- **`ai_usage_declaration`** — descripción textual: cuáles herramientas de IA generativa fueron usadas; alcance (p.ej. ideación, redacción, edición, traducción, ilustración); aproximación del porcentaje del producto final atribuible a IA. Política madre: CR-050 v2.2 §4 (bajo ratificación).
- **`employer_consent_confirmed`** — boolean atestiguando que material propietario del empleador (si lo hubiera) tiene autorización documentada para uso público en Frontiers. Protege al autor y al Núcleo contra acción de NDA. Cuando es `true`, el autor debe mantener prueba (e-mail, política interna pública, autorización escrita) accesible en caso de auditoría.
- **`conflicts_of_interest`** — string listando afiliaciones relevantes del autor: certificaciones PMI activas, sponsors, empleador actual, relaciones de vendor, posiciones en consejos, holdings financieras en herramientas mencionadas. Patrón tomado de arXiv/IEEE.

Cuando `source_kind='governance_document_version'` apunta a esta Guía, estos 3 campos son obligatorios en el producto. Cuando `source_kind='external'` (entrevista, socio), los 3 campos son fuertemente recomendados pero la obligatoriedad se decide caso por caso por el curador.

</section>

---

# 7. Licenciamento · Licensing · Licenciamiento

<section lang="pt-BR">

## 7. Licenciamento (PT-BR)

**Default ratificado (GP 2026-05-25, p267):** `CC BY-SA 4.0` (Creative Commons Attribution-ShareAlike 4.0 International) para o conteúdo deste Guia e para todos os produtos editoriais derivados publicados sob a marca Frontiers, salvo exceção formal aprovada.

**Racional:** atribuição obrigatória + obras derivadas devem manter mesma licença; permite uso comercial por terceiros (alinhado com posicionamento aberto da newsletter); evita ambiguidades operacionais de licenças non-commercial; alinha com a governança de conhecimento aberto do Núcleo.

**Operacionalização técnica:** cada `content_products` row deve registrar a licença efetiva em `publication_metadata` jsonb (chave sugerida `cc_license`). Valor default `cc_license = "CC BY-SA 4.0"`; alterações requerem registro em `admin_audit_log` com justificativa (pattern alinhado com SEDIMENT-239b.A — source de toda coluna gravada deve ser auditável).

**Exceção formal:** alteração de licença para uma issue específica (ex.: `CC BY-NC 4.0` para conteúdo derivado de obra de terceiros que exige non-commercial; ou licença proprietária para material patrocinado em contexto excepcional) requer:

1. Justificativa textual em `publication_metadata.cc_license_exception_reason`.
2. Aprovação documentada do curador editorial + GP.
3. Audit row em `admin_audit_log` com `action='content_product.cc_license_overridden'`.
4. Disclaimer visível na publicação informando a licença efetiva da issue.

**Compatibilidade com Gate 0 jurídico:** a licença CC BY-SA 4.0 só será operacionalizável após CR-050 v2.2 (Política de PI) e R3-C4 (aditivo do Termo de Adesão Voluntário) entrarem em status `active`. Até lá, este Guia documenta a intenção; nenhuma issue pode ser publicada legalmente.

</section>

<section lang="en">

## 7. Licensing (EN)

**Ratified default (GP 2026-05-25, p267):** `CC BY-SA 4.0` (Creative Commons Attribution-ShareAlike 4.0 International) for the content of this Guide and for all editorial products derived under the Frontiers brand, save for formally-approved exceptions.

**Rationale:** mandatory attribution + derivative works must keep same license; allows third-party commercial use (aligned with the open positioning of the newsletter); avoids operational ambiguities of non-commercial licenses; aligns with Núcleo's open-knowledge governance.

**Technical operationalization:** every `content_products` row must record the effective license in `publication_metadata` jsonb (suggested key `cc_license`). Default value `cc_license = "CC BY-SA 4.0"`; changes require an `admin_audit_log` row with justification (pattern aligned with SEDIMENT-239b.A — source of every written column must be auditable).

**Formal exception:** changing the license for a specific issue (e.g., `CC BY-NC 4.0` for content derived from a third-party work that requires non-commercial; or proprietary license for exceptional sponsored material) requires:

1. Text justification in `publication_metadata.cc_license_exception_reason`.
2. Documented approval from editorial curator + GP.
3. Audit row in `admin_audit_log` with `action='content_product.cc_license_overridden'`.
4. Visible disclaimer on the publication declaring the effective license of the issue.

**Compatibility with legal Gate 0:** the CC BY-SA 4.0 license is operationalizable only after CR-050 v2.2 (IP Policy) and R3-C4 (Volunteer Agreement addendum) reach `active` status. Until then, this Guide documents the intent; no issue can be legally published.

</section>

<section lang="es-LA">

## 7. Licenciamiento (ES)

**Default ratificado (GP 2026-05-25, p267):** `CC BY-SA 4.0` (Creative Commons Attribution-ShareAlike 4.0 International) para el contenido de esta Guía y para todos los productos editoriales derivados publicados bajo la marca Frontiers, salvo excepción formalmente aprobada.

**Racional:** atribución obligatoria + obras derivadas deben mantener la misma licencia; permite uso comercial por terceros (alineado con el posicionamiento abierto del boletín); evita ambigüedades operacionales de las licencias non-commercial; alinea con la gobernanza de conocimiento abierto del Núcleo.

**Operacionalización técnica:** cada `content_products` row debe registrar la licencia efectiva en `publication_metadata` jsonb (clave sugerida `cc_license`). Valor predeterminado `cc_license = "CC BY-SA 4.0"`; los cambios requieren una row en `admin_audit_log` con justificación (patrón alineado con SEDIMENT-239b.A — la fuente de toda columna escrita debe ser auditable).

**Excepción formal:** cambiar la licencia para un issue específico (p.ej., `CC BY-NC 4.0` para contenido derivado de obra de terceros que exige non-commercial; o licencia propietaria para material patrocinado en contexto excepcional) requiere:

1. Justificación textual en `publication_metadata.cc_license_exception_reason`.
2. Aprobación documentada del curador editorial + GP.
3. Audit row en `admin_audit_log` con `action='content_product.cc_license_overridden'`.
4. Disclaimer visible en la publicación declarando la licencia efectiva del issue.

**Compatibilidad con Gate 0 jurídico:** la licencia CC BY-SA 4.0 es operacionalizable solo después de que CR-050 v2.2 (Política de PI) y R3-C4 (aditivo del Acuerdo de Voluntariado) alcancen el estado `active`. Hasta entonces, esta Guía documenta la intención; ningún issue puede ser publicado legalmente.

</section>

---

# 8. Fluxo end-to-end · End-to-end flow · Flujo de extremo a extremo

<section lang="pt-BR">

## 8. Fluxo end-to-end (PT-BR)

Cada issue percorre 6 estados (ADR-0099 §2.6 — `content_products.status`):

```
idea → drafted → under_review → approved → published
                      ↓             ↓
                                 archived (terminal)
```

**Transição `under_review → drafted` é permitida** (revisão retorna para reedição). **`published → archived` NÃO é permitida** (correções emitem nova row em `archived` + nova row apontando para a mesma `source_*` + `target_instrument` como sibling).

Por modo de revisão (`review_mode`):

- **`collaborative`** (default sugerido para Supporting Insight, Webinar Recap, Expert Interview, LinkedIn post): todos os revisores veem comentários uns dos outros + o produto. Comentários encadeados ajudam a polir.
- **`sequential`** (default sugerido para Lead Article, Framework, Case Study, LinkedIn Newsletter, Research Stream): comentários visíveis para o time, mas avanço de estado é stage-by-stage (curador → líder → GP).
- **`independent_blind`** (default sugerido para Case Study enviado a magazine externa, journal acadêmico): revisor A não vê parecer de revisor B até depois de submeter o próprio. Cada revisor vê o produto + seu próprio rascunho de parecer; pareceres dos siblings revelados apenas após submissão. Implementado via primitivos blind_review_* (PR #398, p266 — ADR-0099 §2.7 + §7).

**Default `review_mode` por `target_instrument`** ainda pendente C2; tabela §5 reflete recomendação atual.

**Sem chain `approval_chains`:** cada `content_products` row NÃO carrega autoridade governamental — é output editorial, não documento ratificado. Não tem `approval_chain` formal. A "ratificação editorial" é o conjunto signatures `peer_review` + `leader_review` + `submitter_acceptance` capturadas via primitivos da plataforma (ADR-0086 para curation + ADR-0099 §2.7 para blind-review).

</section>

<section lang="en">

## 8. End-to-end flow (EN)

Each issue passes through 6 states (ADR-0099 §2.6 — `content_products.status`):

```
idea → drafted → under_review → approved → published
                      ↓             ↓
                                 archived (terminal)
```

**Transition `under_review → drafted` is allowed** (review returns for re-edit). **`published → archived` is NOT allowed** (corrections issue a new row in `archived` + a new row pointing at the same `source_*` + `target_instrument` as sibling).

By review mode (`review_mode`):

- **`collaborative`** (suggested default for Supporting Insight, Webinar Recap, Expert Interview, LinkedIn post): all reviewers see each other's comments + the product. Threaded comments help polish.
- **`sequential`** (suggested default for Lead Article, Framework, Case Study, LinkedIn Newsletter, Research Stream): comments visible to the team, but state advances stage-by-stage (curator → leader → GP).
- **`independent_blind`** (suggested default for Case Study submitted to external magazine, academic journal): reviewer A does not see reviewer B's parecer until after submitting their own. Each reviewer sees the product + their own draft parecer; siblings' pareceres revealed only after submission. Implemented via blind_review_* primitives (PR #398, p266 — ADR-0099 §2.7 + §7).

**Default `review_mode` per `target_instrument`** still pending C2; §5 table reflects current recommendation.

**No `approval_chains`:** each `content_products` row does NOT carry governmental authority — it is editorial output, not a ratified document. It does not have a formal `approval_chain`. "Editorial ratification" is the set of signatures `peer_review` + `leader_review` + `submitter_acceptance` captured via platform primitives (ADR-0086 for curation + ADR-0099 §2.7 for blind-review).

</section>

<section lang="es-LA">

## 8. Flujo de extremo a extremo (ES)

Cada issue atraviesa 6 estados (ADR-0099 §2.6 — `content_products.status`):

```
idea → drafted → under_review → approved → published
                      ↓             ↓
                                 archived (terminal)
```

**La transición `under_review → drafted` está permitida** (la revisión vuelve para re-edición). **`published → archived` NO está permitida** (las correcciones emiten una nueva row en `archived` + una nueva row apuntando a la misma `source_*` + `target_instrument` como sibling).

Por modo de revisión (`review_mode`):

- **`collaborative`** (predeterminado sugerido para Supporting Insight, Webinar Recap, Expert Interview, LinkedIn post): todos los revisores ven los comentarios de los demás + el producto. Comentarios encadenados ayudan a pulir.
- **`sequential`** (predeterminado sugerido para Lead Article, Framework, Case Study, LinkedIn Newsletter, Research Stream): comentarios visibles para el equipo, pero el avance de estado es stage-by-stage (curador → líder → GP).
- **`independent_blind`** (predeterminado sugerido para Case Study enviado a magazine externa, journal académico): el revisor A no ve el parecer del revisor B hasta después de someter el propio. Cada revisor ve el producto + su propio borrador de parecer; los pareceres de los siblings se revelan solo después de la sumisión. Implementado vía primitivos blind_review_* (PR #398, p266 — ADR-0099 §2.7 + §7).

**El `review_mode` predeterminado por `target_instrument`** está aún pendiente C2; la tabla §5 refleja la recomendación actual.

**Sin `approval_chains`:** cada `content_products` row NO carga autoridad gubernamental — es output editorial, no un documento ratificado. No tiene `approval_chain` formal. La "ratificación editorial" es el conjunto de firmas `peer_review` + `leader_review` + `submitter_acceptance` capturadas vía primitivos de la plataforma (ADR-0086 para curation + ADR-0099 §2.7 para blind-review).

</section>

---

# 9. Originalidade e curadoria · Originality + curation · Originalidad y curaduría

<section lang="pt-BR">

## 9. Originalidade + curadoria (PT-BR)

**Princípio:** Frontiers não publica derivativos triviais de conteúdo já amplamente disponível em outros canais (LinkedIn de PMs com audiência grande, posts virais de IA, traduções diretas de Substacks famosos). O diferencial editorial é síntese, análise comparativa, dados originais, opinião defendida com substância.

**Mecanismo (ratificado p268, C4 — híbrido):**

- **Opção a — automatizada:** chamar `check_idea_originality(title, summary)` (issue #95, ainda não shipped) na transição `idea → drafted`. Se a função detectar cluster denso de 3+ fontes externas convergentes, marca `originality_warning=true` no `publication_metadata`. Curador pode aprovar mesmo assim, mas decisão fica registrada no audit log.
- **Opção b — manual:** curador editorial faz busca livre (Google + LinkedIn + arXiv recentes) sobre o tema antes de aprovar `idea → drafted`. Registra confirmação textual em `publication_metadata.originality_review_notes`.

v1.x ratifica o mecanismo híbrido: opção (b) manual é **sempre obrigatória** independente do estado de #95; opção (a) automatizada é **complementar** quando #95 estiver shipped (flag `originality_warning=true` em `publication_metadata`, decisão final permanece com o curador, audit trail registrado). Sem #95 shipped, opção (b) é o único trilho — sem bloqueio do launch.

**Independente da opção escolhida:** o critério é "agregar valor além do que já existe", não "ser literalmente o primeiro a escrever sobre o tema". Síntese rigorosa de múltiplas fontes é tão valiosa quanto análise primária; o que não vale é repetir o que outro PM já disse melhor sem agregar nada.

</section>

<section lang="en">

## 9. Originality + curation (EN)

**Principle:** Frontiers does not publish trivial derivatives of content already widely available in other channels (large-audience PM LinkedIn posts, viral AI posts, direct translations of famous Substacks). The editorial differential is synthesis, comparative analysis, original data, opinion defended with substance.

**Mechanism (ratified p268, C4 — hybrid):**

- **Option a — automated:** call `check_idea_originality(title, summary)` (issue #95, not yet shipped) at the `idea → drafted` transition. If the function detects a dense cluster of 3+ convergent external sources, mark `originality_warning=true` in `publication_metadata`. Curator can still approve, but the decision is recorded in the audit log.
- **Option b — manual:** editorial curator performs free search (Google + LinkedIn + recent arXiv) on the topic before approving `idea → drafted`. Records text confirmation in `publication_metadata.originality_review_notes`.

v1.x ratifies the hybrid mechanism: option (b) manual is **always mandatory** regardless of #95 state; option (a) automated is **complementary** when #95 ships (flag `originality_warning=true` in `publication_metadata`, final decision stays with the curator, audit trail captured). Without #95 shipped, option (b) is the only rail — no launch blocker.

**Regardless of option:** the criterion is "add value beyond what exists", not "be literally first to write on the topic". Rigorous synthesis of multiple sources is as valuable as primary analysis; what doesn't count is repeating what another PM already said better without adding anything.

</section>

<section lang="es-LA">

## 9. Originalidad + curaduría (ES)

**Principio:** Frontiers no publica derivativos triviales de contenido ya ampliamente disponible en otros canales (posts de LinkedIn de PMs con gran audiencia, posts virales de IA, traducciones directas de Substacks famosos). El diferencial editorial es síntesis, análisis comparativo, datos originales, opinión defendida con sustancia.

**Mecanismo (ratificado p268, C4 — híbrido):**

- **Opción a — automatizada:** llamar `check_idea_originality(title, summary)` (issue #95, aún no shipped) en la transición `idea → drafted`. Si la función detecta un cluster denso de 3+ fuentes externas convergentes, marca `originality_warning=true` en `publication_metadata`. El curador puede aprobar igualmente, pero la decisión queda registrada en el audit log.
- **Opción b — manual:** el curador editorial hace búsqueda libre (Google + LinkedIn + arXiv reciente) sobre el tema antes de aprobar `idea → drafted`. Registra confirmación textual en `publication_metadata.originality_review_notes`.

v1.x ratifica el mecanismo híbrido: la opción (b) manual es **siempre obligatoria** independientemente del estado de #95; la opción (a) automatizada es **complementaria** cuando #95 esté shipped (flag `originality_warning=true` en `publication_metadata`, la decisión final queda con el curador, audit trail registrado). Sin #95 shipped, la opción (b) es el único riel — sin bloqueo del launch.

**Independiente de la opción:** el criterio es "agregar valor más allá de lo existente", no "ser literalmente el primero en escribir sobre el tema". La síntesis rigurosa de múltiples fuentes es tan valiosa como el análisis primario; lo que no vale es repetir lo que otro PM ya dijo mejor sin agregar nada.

</section>

---

# 10. Governança e dependências externas · Governance + external dependencies · Gobernanza y dependencias externas

<section lang="pt-BR">

## 10. Governança e dependências externas (PT-BR)

**Gate 0 jurídico — bloqueador formal para publicar issue #1:**

| Dependência | Status (2026-05-25) | Bloqueia? |
|---|---|---|
| CR-050 v2.2 (Política de PI sucessora) | `under_review` em `governance_documents` | 🔴 SIM |
| R3-C4 (aditivo do Termo de Adesão Voluntário) ou Termo R3-C4 v1.0 | Em redação pelo time Claude (estimado 2026-04-23) | 🔴 SIM |
| Manual de Governança R3 | `draft` (sem versões ainda) | 🟡 NÃO direto, mas referenciado |
| Conformidade LGPD (Art. 18 cycle) | ✅ shipped (consent + export + delete + anonymize) | 🟢 |

Sem CR-050 + R3-C4 ratificados, **nenhuma issue Frontiers pode publicar legalmente**. Este Guia v1 documenta o pivô para `content_products` (ADR-0099) e ratifica decisões editoriais; a operacionalização de produtos espera Gate 0.

**Governança editorial interna (3 gates `editorial_guide`):**

- `curator` (threshold=all) — curadores designados aprovam a versão deste Guia.
- `leader_awareness` (threshold=0, informativo) — lideranças de tribo recebem ciência da nova versão.
- `submitter_acceptance` (threshold=1) — GP do Núcleo aceita formalmente.

Esses gates aplicam-se **a este Guia editorial**, NÃO aos `content_products` derivados. Produtos derivados usam `peer_review` + `leader_review` + `submitter_acceptance` via primitivos de curation (ADR-0086 + ADR-0099).

**Cadência de revisão deste Guia:** anual (na virada de ciclo) OU ad-hoc quando: (a) Gate 0 jurídico cair; (b) C2–C5 forem decididos; (c) novo `target_instrument` for adotado; (d) incidente editorial relevante.

</section>

<section lang="en">

## 10. Governance + external dependencies (EN)

**Legal Gate 0 — formal blocker for publishing issue #1:**

| Dependency | Status (2026-05-25) | Blocks? |
|---|---|---|
| CR-050 v2.2 (successor IP Policy) | `under_review` in `governance_documents` | 🔴 YES |
| R3-C4 (Volunteer Agreement addendum) or Term R3-C4 v1.0 | Being drafted by the Claude team (ETA 2026-04-23) | 🔴 YES |
| Governance Manual R3 | `draft` (no versions yet) | 🟡 NOT direct, but referenced |
| LGPD compliance (Art. 18 cycle) | ✅ shipped (consent + export + delete + anonymize) | 🟢 |

Without ratified CR-050 + R3-C4, **no Frontiers issue can publish legally**. This v1 Guide documents the pivot to `content_products` (ADR-0099) and ratifies editorial decisions; operationalization of products waits for Gate 0.

**Internal editorial governance (3 `editorial_guide` gates):**

- `curator` (threshold=all) — designated curators approve the version of this Guide.
- `leader_awareness` (threshold=0, informational) — tribe leaders receive awareness of the new version.
- `submitter_acceptance` (threshold=1) — Núcleo GP formally accepts.

These gates apply **to this editorial Guide**, NOT to derived `content_products`. Derived products use `peer_review` + `leader_review` + `submitter_acceptance` via curation primitives (ADR-0086 + ADR-0099).

**Review cadence of this Guide:** annual (at cycle turn) OR ad-hoc when: (a) legal Gate 0 falls; (b) C2–C5 are decided; (c) a new `target_instrument` is adopted; (d) a relevant editorial incident occurs.

</section>

<section lang="es-LA">

## 10. Gobernanza y dependencias externas (ES)

**Gate 0 jurídico — bloqueador formal para publicar el issue #1:**

| Dependencia | Estado (2026-05-25) | ¿Bloquea? |
|---|---|---|
| CR-050 v2.2 (Política de PI sucesora) | `under_review` en `governance_documents` | 🔴 SÍ |
| R3-C4 (aditivo del Acuerdo de Voluntariado) o Acuerdo R3-C4 v1.0 | En redacción por el equipo Claude (ETA 2026-04-23) | 🔴 SÍ |
| Manual de Gobernanza R3 | `draft` (sin versiones aún) | 🟡 NO directo, pero referenciado |
| Conformidad LGPD (Art. 18 cycle) | ✅ shipped (consent + export + delete + anonymize) | 🟢 |

Sin CR-050 + R3-C4 ratificados, **ningún issue Frontiers puede publicarse legalmente**. Esta Guía v1 documenta el pivote a `content_products` (ADR-0099) y ratifica decisiones editoriales; la operacionalización de productos espera Gate 0.

**Gobernanza editorial interna (3 gates de `editorial_guide`):**

- `curator` (threshold=all) — los curadores designados aprueban la versión de esta Guía.
- `leader_awareness` (threshold=0, informativo) — los líderes de tribu reciben aviso de la nueva versión.
- `submitter_acceptance` (threshold=1) — el GP del Núcleo acepta formalmente.

Estos gates aplican **a esta Guía editorial**, NO a los `content_products` derivados. Los productos derivados usan `peer_review` + `leader_review` + `submitter_acceptance` vía primitivos de curation (ADR-0086 + ADR-0099).

**Cadencia de revisión de esta Guía:** anual (en el cierre de ciclo) O ad-hoc cuando: (a) caiga el Gate 0 jurídico; (b) se decidan C2–C5; (c) se adopte un nuevo `target_instrument`; (d) ocurra un incidente editorial relevante.

</section>

---

# 11. Marca, disclaimers e responsabilidade · Brand, disclaimers + responsibility · Marca, disclaimers y responsabilidad

<section lang="pt-BR">

## 11. Marca, disclaimers e responsabilidade (PT-BR)

**Marca:** "Frontiers in AI & Project Mgmt" (slug `frontiers-newsletter`). Busca formal USPTO/INPI desescalada por decisão GP (2026-04-21, F7) — monitoramento passivo (Google Alerts + busca livre INPI/USPTO 30min + disclaimer) é suficiente pre-launch.

**Gatilhos que destravam busca formal (revisitar F7):** 10+ issues publicadas OU 1000+ subscribers OU primeiro contato comercial/sponsorship OU qualquer cease-and-desist OU expansão para mercado EUA/Europa OU publicação em journals formais com peer review.

**Disclaimer obrigatório no masthead de toda issue:**

> *Frontiers in AI & Project Mgmt — published by Núcleo IA & GP, an independent community hub affiliated with PMI Brasil. Not affiliated with Frontiers Media SA or its journals. Editorial content reflects the views of authors, not of PMI or any sponsor.*

**Responsabilidade autoral:** o autor é responsável pelo conteúdo de sua issue. O Núcleo IA & GP atua como curador editorial e plataforma de publicação, não como editor responsável no sentido jurídico estrito. Erros factuais devem ser corrigidos via nova issue marcada como `archived` (correção) + nova publicação (ADR-0099 §2.6).

**Conteúdo de terceiros:** material licenciado de terceiros (imagens, citações longas, dados proprietários) deve ter licença/permissão documentada. Em caso de dúvida, perguntar ao curador antes de submeter.

</section>

<section lang="en">

## 11. Brand, disclaimers + responsibility (EN)

**Brand:** "Frontiers in AI & Project Mgmt" (slug `frontiers-newsletter`). Formal USPTO/INPI search de-escalated by GP decision (2026-04-21, F7) — passive monitoring (Google Alerts + free INPI/USPTO 30min search + disclaimer) is sufficient pre-launch.

**Triggers that unlock formal search (revisit F7):** 10+ issues published OR 1000+ subscribers OR first commercial/sponsorship contact OR any cease-and-desist OR expansion to US/Europe markets OR publication in formal peer-reviewed journals.

**Mandatory disclaimer in every issue masthead:**

> *Frontiers in AI & Project Mgmt — published by Núcleo IA & GP, an independent community hub affiliated with PMI Brasil. Not affiliated with Frontiers Media SA or its journals. Editorial content reflects the views of authors, not of PMI or any sponsor.*

**Authorship responsibility:** the author is responsible for the content of their issue. Núcleo IA & GP acts as editorial curator and publication platform, not as legally-strict responsible publisher. Factual errors must be corrected via a new issue marked `archived` (correction) + new publication (ADR-0099 §2.6).

**Third-party content:** licensed third-party material (images, long citations, proprietary data) must have documented license/permission. When in doubt, ask the curator before submitting.

</section>

<section lang="es-LA">

## 11. Marca, disclaimers y responsabilidad (ES)

**Marca:** "Frontiers in AI & Project Mgmt" (slug `frontiers-newsletter`). Búsqueda formal USPTO/INPI desescalada por decisión del GP (2026-04-21, F7) — monitoreo pasivo (Google Alerts + búsqueda libre INPI/USPTO 30min + disclaimer) es suficiente pre-launch.

**Gatillos que desbloquean búsqueda formal (revisitar F7):** 10+ issues publicados O 1000+ subscribers O primer contacto comercial/sponsorship O cualquier cease-and-desist O expansión a mercados EE.UU./Europa O publicación en journals formales con peer review.

**Disclaimer obligatorio en el masthead de todo issue:**

> *Frontiers in AI & Project Mgmt — published by Núcleo IA & GP, an independent community hub affiliated with PMI Brasil. Not affiliated with Frontiers Media SA or its journals. Editorial content reflects the views of authors, not of PMI or any sponsor.*

**Responsabilidad autoral:** el autor es responsable por el contenido de su issue. Núcleo IA & GP actúa como curador editorial y plataforma de publicación, no como editor responsable en sentido jurídico estricto. Los errores factuales deben corregirse vía nuevo issue marcado como `archived` (corrección) + nueva publicación (ADR-0099 §2.6).

**Contenido de terceros:** material licenciado de terceros (imágenes, citas largas, datos propietarios) debe tener licencia/permiso documentado. En caso de duda, preguntar al curador antes de someter.

</section>

---

# 12. Manutenção do Guia · Maintenance of the Guide · Mantenimiento de la Guía

<section lang="pt-BR">

## 12. Manutenção do Guia (PT-BR)

**Versão atual:** v1.x (este draft — patch p268 com C2/C3/C4 ratificadas; aguarda Gate 0 jurídico + C5 + #95 para v2).

**Cadência:** revisão anual no final do ciclo + ad-hoc se Gate 0 cair, C2-C5 forem decididos, ou se incidente editorial demandar mudança.

**Próximas versões esperadas:**

- **v1.x patch (este — p268):** absorvidas C2 (default `review_mode` ratificado) + C3 (shape jsonb flat-keys ratificado) + C4 (originalidade híbrida ratificada). C5 (autor-piloto issue #1) **deferido** até Gate 0.
- **v2 (médio prazo, pós-Gate-0):** absorver CR-050 v2.2 ratificada + R3-C4 ratificado; adicionar glossário trilíngue; expandir Section 5 com `target_instrument` adicionais conforme experimentação.
- **v3+ (longo prazo):** reflexão sobre 1 ano de operação; ajustar cadência se biweekly for inviável; revisitar F7 (marca) se gatilhos disparados.

**Mantenedores designados:**

- **Editor-chefe:** Fabricio Costa (proposer-of-record do Guia; co-autor original do docx 2026-04-21).
- **Co-mantenedor:** GP Vitor Maia Rodovalho (orquestração da v1 reconciliada + decisões pendentes C2-C5).
- **Curadores assistentes:** a serem nomeados quando Frontiers entrar em operação ativa (Gate 2 da #96).

**Como propor mudança neste Guia:** abrir issue com label `editorial-guide-frontiers`; descrever mudança proposta + racional + impacto em produtos já publicados (se houver). Mantenedores avaliam e, se aceito, criam novo `document_versions` draft via `upsert_document_version`, depois `lock_document_version` para iniciar chain interno (3 gates `editorial_guide`).

</section>

<section lang="en">

## 12. Maintenance of the Guide (EN)

**Current version:** v1.x (this draft — p268 patch with C2/C3/C4 ratified; awaits legal Gate 0 + C5 + #95 for v2).

**Cadence:** annual review at cycle end + ad-hoc if Gate 0 falls, C2-C5 are decided, or an editorial incident requires change.

**Expected next versions:**

- **v1.x patch (this — p268):** absorbed C2 (default `review_mode` ratified) + C3 (jsonb flat-keys shape ratified) + C4 (hybrid originality ratified). C5 (pilot author for issue #1) **deferred** until Gate 0.
- **v2 (medium term, post-Gate-0):** absorb ratified CR-050 v2.2 + ratified R3-C4; add trilingual glossary; expand Section 5 with additional `target_instrument` as experimentation matures.
- **v3+ (long term):** reflection on 1 year of operation; adjust cadence if biweekly is infeasible; revisit F7 (brand) if triggers fired.

**Designated maintainers:**

- **Editor-in-chief:** Fabricio Costa (proposer-of-record of the Guide; co-author of original 2026-04-21 docx).
- **Co-maintainer:** GP Vitor Maia Rodovalho (orchestration of reconciled v1 + pending decisions C2-C5).
- **Assistant curators:** to be named when Frontiers enters active operation (Gate 2 of #96).

**How to propose changes to this Guide:** open an issue with label `editorial-guide-frontiers`; describe proposed change + rationale + impact on already-published products (if any). Maintainers evaluate and, if accepted, create new `document_versions` draft via `upsert_document_version`, then `lock_document_version` to start the internal chain (3 `editorial_guide` gates).

</section>

<section lang="es-LA">

## 12. Mantenimiento de la Guía (ES)

**Versión actual:** v1.x (este draft — patch p268 con C2/C3/C4 ratificadas; espera el Gate 0 jurídico + C5 + #95 para v2).

**Cadencia:** revisión anual al final del ciclo + ad-hoc si cae el Gate 0, se deciden C2-C5, o un incidente editorial demande cambio.

**Próximas versiones esperadas:**

- **v1.x patch (este — p268):** absorbidas C2 (`review_mode` predeterminado ratificado) + C3 (shape jsonb flat-keys ratificado) + C4 (originalidad híbrida ratificada). C5 (autor-piloto del issue #1) **diferido** hasta el Gate 0.
- **v2 (mediano plazo, post-Gate-0):** absorber CR-050 v2.2 ratificada + R3-C4 ratificado; agregar glosario trilingüe; expandir la Sección 5 con `target_instrument` adicionales conforme la experimentación madure.
- **v3+ (largo plazo):** reflexión sobre 1 año de operación; ajustar cadencia si biweekly es inviable; revisitar F7 (marca) si los gatillos se dispararon.

**Mantenedores designados:**

- **Editor-en-jefe:** Fabricio Costa (proposer-of-record de la Guía; coautor original del docx 2026-04-21).
- **Co-mantenedor:** GP Vitor Maia Rodovalho (orquestación de la v1 reconciliada + decisiones pendientes C2-C5).
- **Curadores asistentes:** a ser nombrados cuando Frontiers entre en operación activa (Gate 2 de #96).

**Cómo proponer cambios a esta Guía:** abrir issue con label `editorial-guide-frontiers`; describir el cambio propuesto + racional + impacto en productos ya publicados (si los hay). Los mantenedores evalúan y, si se acepta, crean nuevo `document_versions` draft vía `upsert_document_version`, luego `lock_document_version` para iniciar el chain interno (3 gates de `editorial_guide`).

</section>

---

## Apêndice A — Mapeamento decisão ratificada × seção do Guia

| Decisão | Onde ratificada | Seção do Guia v1 |
|---|---|---|
| F1 — Frontiers como série da plataforma | ADR-0021 (2026-04-21) | §1, §10 |
| F2 — trilíngue nativo EN/PT/ES | ADR-0021 (2026-04-21) | §1, §4 |
| F3 — CC BY-SA 4.0 | ADR-0021 (2026-05-25, p267) | §7 |
| F4 — 3 declarações obrigatórias + C3 shape | ADR-0021 (Proposed, Gate 0 unblock) + p268 C3 ratificada (flat keys) | §6 |
| F5 — 7 stages mapeados | ADR-0021 (Proposed; obsoleto post-pivot — agora 6 status ADR-0099 §2.6) | §8 |
| F6 + C4 — originality check híbrido | ADR-0021 (Proposed) + p268 C4 ratificada (manual + #95 quando shipped) | §9 |
| C2 — `review_mode` default por instrumento | p268 (2026-05-26) | §5 |
| F7 — busca formal desescalada | ADR-0021 (2026-04-21) | §11 |
| Cadência biweekly | ADR-0021 (2026-04-21) | §3 |
| Pivot para `content_products` | ADR-0099 (2026-05-26, p264.W4g #383) | §1, §5, §7, §8 |
| ADR-0099 §6 implementation | PR #396 (2026-05-26, p265.W4f Foundation) | §5, §8 |
| ADR-0099 §7 blind-review primitives | PR #398 (2026-05-26, p266.W4f Primitives) | §8 |

## Apêndice B — Pendências explícitas v1.x → v2

| Pendência | Origem | Resolução esperada em |
|---|---|---|
| ~~C2 — `review_mode` default por `target_instrument`~~ | ✅ ratificada p268 (tabela §5) | — |
| ~~C3 — shape jsonb das 3 declarações em `publication_metadata`~~ | ✅ ratificada p268 (flat keys §6) | — |
| ~~C4 — originality check #95 vs manual~~ | ✅ ratificada p268 (híbrido §9) | — |
| C5 — autor piloto da issue #1 | PM decision (Gate 2 da #96) — diferida até Gate 0 cair | v2 |
| Gate 0 — CR-050 v2.2 ratificada | Externo (jurídico) | v2 |
| Gate 0 — R3-C4 (aditivo Termo Voluntário) | Externo (time Claude → jurídico) | v2 |
| Glossário trilíngue PM+IA | Editorial work | v2 |
| #95 `check_idea_originality` shipped | Issue #95 W1-W4 backlog | depende de roadmap (complementar a C4) |

---

*Fim da v1. Este draft é authored 2026-05-25 (p267 + p268) e tem como destino `governance_documents.id = 18ec4690-4f5a-4cab-904d-451e2c7245bf`. Não é uma versão lacrada (`locked_at = NULL`); permanece editável até `lock_document_version` ser invocada.*
