# Content Pipeline Playbook — Núcleo IA & GP

> **Status:** Draft local (21/Abr/2026) — target: `nucleo-ia-gp/wiki` repo, path `editorial/content-pipeline-playbook.md`.
> **Propósito:** guia operacional para líderes de tribo, comms team, pesquisadores e curadores sobre como o pipeline de conteúdo funciona, quando escrever, como escolher série, cadência e voice.
> **Complementa:** ADR-0020 (primitivo arquitetural) e ADR-0010 (wiki scope).

## Visão rápida

O Núcleo gera conteúdo em 5 canais:

1. **Publicações formais** (ProjectManagement.com, PMI.org, JAIPM) — compliance + credibilidade acadêmica
2. **Blog interno** — cadência flexível, voice autoral, owned traffic
3. **Newsletter** — digest para members + subscribers
4. **Social** (LinkedIn, Instagram) — awareness + recruitment
5. **Webinars** — live engagement + gravações YouTube

Desde 21/Abr/2026 (ADR-0020), organizamos tudo em **séries temáticas nomeadas** — inspiração do [akitaonrails.com/en](https://akitaonrails.com/en/) que mantém 500+ posts em 21 anos agrupados por tema (M.Akita Chronicles, Frank*, Omarchy, Vibe Code, RANT).

## As 5 séries iniciais (seed ADR-0020)

| Série | Cadência | Voice | Formato | Dono | Audiência |
|---|---|---|---|---|---|
| **CPMAI Journey** | Quinzenal | Crônica educativa | Multi (blog+webinar+newsletter) | Herlon (GP subiniciativa) | PMs considerando CPMAI + voluntários |
| **Trilha do Pesquisador** | Mensal | Case study com voz pessoal | Blog post | GP / Comms | Candidatos processo seletivo + Community Managers PMI |
| **Behind Núcleo IA** | Mensal | Crônica técnica com storytelling | Blog post | GP Vitor | Dev BR + PMs que querem tech governance em comunidade |
| **Radar Semanal — T1 Tecnologia** | Semanal | Weekly radar | Newsletter | Líder T1 | Members + subscribers externos |
| **Agentes Autônomos: Deep Dive** | Mensal | Deep dive técnico | Multi | Líder T2 | PMs experienced + devs em multi-agent |

## Como escolher em qual canal publicar

Árvore de decisão:

```
IDEIA CHEGOU
│
├─ É research findings formal (com dados, metodologia, citações)?
│    ├─ SIM → publication_submissions → PM.com ou PMI.org
│    │          ↓
│    │        + também virar deep-dive no blog interno (série pertinente)
│    │          ↓
│    │        + tease no Weekly Radar T* do tema
│    │
│    └─ NÃO
│         │
│         ├─ É journey/crônica (construindo X, aprendendo Y, errando Z)?
│         │    └─ Blog interno → série 'behind-nucleo-ia' ou 'trilha-pesquisador'
│         │
│         ├─ É digest/curadoria (insights externos + opinião)?
│         │    └─ Newsletter → série 'weekly-radar-*'
│         │
│         ├─ É tutorial técnico (how-to reproducible)?
│         │    └─ Blog interno categoria 'tutorial' + github_repo_url
│         │         ↓
│         │       + considerar cross-post no Dev.to
│         │
│         ├─ É rant/opinião provocativa (estilo Akita "RANT:")?
│         │    └─ Blog interno categoria 'rant' — série opcional
│         │
│         └─ É case study tribo (projeto 6 meses com resultado)?
│              └─ publication_submissions (se tiver métrica formal)
│                  + blog categoria 'case-study' + série da tribo
```

## Voice & Tone por série

### CPMAI Journey — "Crônica educativa"
- Primeira pessoa do plural ("nós estudamos", "nosso grupo avançou")
- Transparência sobre dificuldades + referência ao material oficial PMI
- Tom: honesto, vulnerável, didático
- Evitar: marketing-speak, hype

### Trilha do Pesquisador — "Case study com voz pessoal"
- Primeira pessoa do singular (o volunteer conta sua journey)
- Estrutura narrativa (porque entrei → o que fiz → o que aprendi → porque fiquei/saí)
- Tom: autêntico, reflexivo, pode ser emocional
- Permite "exit stories" (ex.: Lorena/Lídia/Alexandre de 21/Abr — post póstumo com consent)

### Behind Núcleo IA — "Crônica técnica com storytelling"
- Inspirado nos "Behind the M.Akita Chronicles"
- Mostra ADRs, decisões, debug sessions como narrativa
- Permite código + diagramas + trechos de commit
- Tom: técnico mas legível, com humor quando cabível
- Exemplos de títulos:
  - "Fixing 9 stale refs in 1 session — a debug post-mortem"
  - "From 0 to 17 ADRs in 6 months — governance evolution"
  - "Why we didn't adopt APM (and built our own council instead)"
  - "The 4-minute outage that ADR-018 prevented forever"

### Radar Semanal T1 — "Weekly radar"
- Terceira pessoa (reportagem)
- 5-7 items curados: 2 papers arXiv + 2 LinkedIn posts relevantes + 1 GitHub trending + 1 link surpresa
- Tom: direto, scannable, com takeaway claro por item
- Feeder natural: [AI Briefing Skill](../../.claude/skills/tribe-weekly-brief/SKILL.md) (issue #93 Op #2)

### Agentes Autônomos Deep Dive — "Deep dive técnico"
- Mistura terceira pessoa (análise) + primeira pessoa plural (experimento)
- Sempre com comparação ou benchmark (A vs B vs C)
- Sempre com repo GitHub se aplicável
- Tom: rigoroso, específico, não-superficial
- Longo OK (4000-8000 palavras)

## Cadência — expectativas realistas

- **Weekly**: Radar T1 — ~500-800 palavras. 1h de curadoria + 30min de escrita.
- **Biweekly**: CPMAI Journey — 1500 palavras. 2h (incl. screenshots do grupo).
- **Monthly**: Trilha Pesquisador / Behind Núcleo / Deep Dive — 2000-5000 palavras. 4-8h.
- **Sporadic**: rants, announcements, community spotlights — on demand.

**Princípio Akita:** consistência > perfeição. Melhor publicar 1000 palavras decentes do que 3000 polidos atrasados 2 semanas. Posts podem ser atualizados depois.

## Multi-idioma

- **PT-BR**: sempre obrigatório (audiência primária)
- **EN-US**: recomendado para series `behind-nucleo-ia` e `tribe-2-agents-deep-dive` (reach AIPM + internacional)
- **ES-LATAM**: opcional, priorizar quando tiver volunteer hispanofalante revisor

Schema `blog_posts.title/excerpt/body_html` é `jsonb i18n` pronto. Tradução via LLM com review humano: ~30min por post.

## GitHub repo link — quando aplicável

Série `tribe-2-agents-deep-dive` e posts categoria `tutorial` + `deep-dive`:

- Criar repo `nucleo-ia-gp/<slug-do-post>` com código reproducível
- Popular `blog_posts.github_repo_url` com URL
- README.md do repo linka de volta para o post (loop)
- License: Apache 2.0 ou MIT (não copyleft para facilitar uso externo)

Série `behind-nucleo-ia`: linkar para commits/PRs do próprio `ai-pm-research-hub` ao invés de repo novo.

## Como os 5 canais se alimentam

```
[hub_resources 330 items] ──┬──► curated weekly digest ──► Radar Semanal T*
                             │
[meeting_action_items] ──────┼──► decisões → posts → Behind Núcleo IA
                             │                    └─► case studies → Trilha Pesquisador
                             │
[public_publications 7] ─────┼──► tease no blog + deep dive
                             │
[wiki_pages 40] ─────────────┴──► knowledge anchors + referências cruzadas
```

## Editorial board / ownership

Cada série tem 1 dono declarado. Série sem dono por >60 dias → `is_active=false`. Reativação exige novo dono.

Matriz sugerida inicial:
- CPMAI Journey → Herlon (GP subiniciativa) + co_gp Fabrício
- Trilha Pesquisador → Comms lead (rotativo por ciclo)
- Behind Núcleo IA → GP Vitor (voice único neste)
- Radar Semanal T1 → Líder T1 (hoje: rotativo, idealmente fixo por ciclo)
- Tribe 2 Deep Dive → Líder T2

## Métricas de sucesso (6 meses — out/2026)

- ≥ 5 séries ativas com ≥ 3 posts cada
- blog_posts volume: 12 → 50+
- ≥ 1 série cross-format completa (blog + webinar + newsletter)
- `github_repo_url` populado em ≥ 50% dos posts `tutorial`/`deep-dive`
- ≥ 30% dos posts com versão EN

## Anti-patterns

- **Post sem dono** — sempre atribuir `author_member_id` antes de draft
- **Série fantasma** — declarar cadência weekly e publicar 1 vez em 3 meses. Melhor re-classificar para `sporadic`
- **Content marketing** — posts otimizados para SEO sem substância. Preferir menos + profundo
- **Tradução automática sem revisão** — LLM pode ajudar mas humano revisa antes de publicar EN/ES
- **Cross-post sem atribuição** — quando syndicar para Dev.to/Medium/LinkedIn, sempre incluir canonical URL para o post original no Núcleo

## Inspirações externas

- [akitaonrails.com/en](https://akitaonrails.com/en/) — modelo primário (séries + 21 anos + multi-idioma)
- [One Useful Thing](https://www.oneusefulthing.org/) — Ethan Mollick, research-backed essays IA+Education
- [Stratechery](https://stratechery.com/) — Ben Thompson, single-author thoughtleadership
- [GitHub Blog](https://github.blog/) — cada post com repo demo
- Engineering blogs (Uber/Netflix/Stripe/LinkedIn) — dev-written + author profile
- [Dev.to](https://dev.to/) — syndication model

## Histórico

- 2026-04-21 — Playbook criado (draft local) após sessão debug 9908f3 — análise comparativa com Akita e 10 cases de mercado. ADR-0020 em aprovação. 5 séries seed criadas.

## Para publicar no wiki

1. Aprovação deste playbook pelo PM
2. Copiar este arquivo para `nucleo-ia-gp/wiki` repo, path `editorial/content-pipeline-playbook.md`
3. Commit + push → webhook aciona `sync-wiki` EF → popula `wiki_pages` tabela
4. Aparece em `/wiki/editorial/content-pipeline-playbook`
