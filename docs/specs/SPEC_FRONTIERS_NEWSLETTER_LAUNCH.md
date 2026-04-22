# SPEC — Newsletter Frontiers Launch (Gate 1 prep)

> **Status:** Pre-aprovação — todos os SQL blocks abaixo são **DRAFT**, NÃO devem ser aplicados em prod até Gate 0 da [issue #96](https://github.com/VitorMRodovalho/ai-pm-research-hub/issues/96) estar 100% verde (CR-050 v2.2 ratificada + Termo R3-C4/aditivo + busca marca + decisões 1-6 do GP+Fabrício).
>
> **Propósito:** ter Gate 1 (integração plataforma) executável em <30min uma vez que Gate 0 cair. Esta spec é o playbook técnico — copia-cola direto após decisões.
>
> **Sessão de origem:** debug 9908f3, 2026-04-21.
>
> **Related:** [ADR-0020](../adr/ADR-0020-publication-pipeline.md), [ADR-0021](../adr/ADR-0021-newsletter-frontiers-governance.md) (Proposed), [#94](https://github.com/VitorMRodovalho/ai-pm-research-hub/issues/94), [#95](https://github.com/VitorMRodovalho/ai-pm-research-hub/issues/95), [#96](https://github.com/VitorMRodovalho/ai-pm-research-hub/issues/96).

## Pré-requisitos (Gate 0 — issue #96)

Não executar nada deste documento sem confirmar:

- [ ] **CR-050 v2.2** ratificada no portal `https://nucleoia.vitormr.dev/admin/governance/documents` (sair de `under_review`)
- [ ] **Termo R3-C4** (novo) ou aditivo R3-C3.1 publicado e aceito por autores piloto
- [ ] **Busca USPTO + INPI** concluída para o nome final (default = "Frontiers in AI & Project Mgmt", alternativa = preencher após decisão 1)
- [ ] **Consulta Mario Trentim** sobre uso da palavra "Frontiers" + marcas PMI documentada
- [ ] **Decisão 1 (GP+Fabrício):** nome final → preencher `__FRONTIERS_NAME__` abaixo
- [ ] **Decisão 2 (GP+Fabrício):** idioma → preencher `__LANGUAGE_POLICY__`
- [ ] **Decisão 3 (GP+Fabrício):** licensing default → preencher `__CC_LICENSE__`
- [ ] **Decisão 4 (GP+Fabrício):** nome do termo aditivo → preencher `__TERM_REF__`
- [ ] **Decisão 6 (GP+Fabrício):** Frontiers como série da plataforma? Se NÃO, pular SQL Block 3 deste spec
- [ ] (Decisão 5 = autor piloto issue #1 não bloqueia Gate 1, é Gate 2)

## Variáveis a substituir antes de executar

| Placeholder | Default sugerido | Decisão # | Status |
|---|---|---|---|
| `__FRONTIERS_NAME_EN__` | `Frontiers in AI & Project Mgmt` | 1 | TBD |
| `__FRONTIERS_NAME_PT__` | `Frontiers em IA & Gestão de Projetos` | 1 | TBD |
| `__FRONTIERS_NAME_ES__` | `Frontiers en IA y Gestión de Proyectos` | 1 | TBD |
| `__SLUG__` | `frontiers-newsletter` | 1 | TBD (renomear se nome mudar) |
| `__LANGUAGE_POLICY__` | `bilíngue nativo EN+PT (recomendado pelo Claude B)` | 2 | TBD |
| `__CC_LICENSE__` | `CC BY-SA 4.0` (recomendado para newsletter profissional) | 3 | TBD |
| `__TERM_REF__` | `Termo R3-C4 v1.0` | 4 | TBD |

---

## SQL Block 1 — Adiciona 3 categorias novas em `blog_posts.category`

**Arquivo target:** `supabase/migrations/AAAAMMDDhhmmss_blog_categories_frontiers_alignment.sql`
**Tempo estimado de aplicação:** ~30s
**Risco:** 🟢 Aditivo, rollback trivial (recriar constraint sem os 3 novos).
**Depende de Decisões:** nenhuma. Pode ser aplicado isolado de Frontiers (#94 Oportunidade #12 vale mesmo sem Newsletter).

```sql
-- ============================================================================
-- Issue #94 Oportunidade #12 + Issue #96 Gate 1 — alinha blog_posts.category
-- com 7 tipos do Guia Editorial Frontiers (§5)
--
-- Adiciona: framework-model, webinar-recap, expert-interview
-- Mantém os 10 valores anteriores (commit 57a1ce9).
--
-- Mapeamento Guia §5 → category:
--   Lead Article            → deep-dive | research-findings
--   Supporting Insight      → opinion
--   Framework / Model       → framework-model            (NOVO)
--   Case Study / Use Case   → case-study
--   Webinar & Event Recap   → webinar-recap              (NOVO)
--   Expert Interview        → expert-interview           (NOVO)
--   Research Stream Insight → weekly-radar
-- ============================================================================

ALTER TABLE public.blog_posts DROP CONSTRAINT IF EXISTS blog_posts_category_check;

ALTER TABLE public.blog_posts ADD CONSTRAINT blog_posts_category_check CHECK (
  category = ANY (ARRAY[
    'case-study',
    'tutorial',
    'announcement',
    'opinion',
    'deep-dive',
    'weekly-radar',
    'community-spotlight',
    'behind-the-scenes',
    'rant',
    'research-findings',
    'framework-model',     -- NOVO
    'webinar-recap',       -- NOVO
    'expert-interview'     -- NOVO
  ])
);

COMMENT ON COLUMN public.blog_posts.category IS 'Categoria editorial. 13 valores expandidos para alinhar com Guia Editorial Frontiers (§5). Ver SPEC_FRONTIERS_NEWSLETTER_LAUNCH.md.';
```

**Validação pós-apply:**

```sql
-- esperar 13 valores
SELECT pg_get_constraintdef(oid)
FROM pg_constraint
WHERE conrelid = 'public.blog_posts'::regclass AND conname = 'blog_posts_category_check';
```

---

## SQL Block 2 — `publication_ideas` primitivo (#94 W2) com stages extended

**Arquivo target:** `supabase/migrations/AAAAMMDDhhmmss_publication_ideas_w2_with_extended_stages.sql`
**Tempo estimado de aplicação:** ~2min
**Risco:** 🟡 Médio — nova table + 4 FKs em tabelas existentes (todas opcionais).
**Depende de Decisões:** nenhuma direta, mas Decisão 6 muda como Frontiers se conecta. Stages incluem `proposed/tribe_review/leader_review` discutidos em #94 Oportunidade #13.

```sql
-- ============================================================================
-- Issue #94 W2 + Issue #96 Gate 1 — primitivo publication_ideas
--
-- Stages alinhados com Guia Editorial Frontiers §9 (7 etapas):
--   draft         → proposta de pauta
--   proposed      → validação preliminar (NOVO vs ADR-020 D2)
--   researching   → produção (research)
--   writing       → produção (escrita)
--   tribe_review  → revisão tribo (NOVO vs ADR-020 D2)
--   leader_review → revisão líder (NOVO vs ADR-020 D2)
--   curation      → curadoria final
--   approved      → pronto para publicação
--   published     → publicado
--   archived      → arquivado/rejeitado
--
-- metadata jsonb suporta 3 declarações obrigatórias (issue #96 PI Crítico #2/#3/#4):
--   ai_usage_declaration         (CR-050 v2.2 §4)
--   employer_consent_confirmed   (proteção contra NDA)
--   conflicts_of_interest        (afiliação, PMI, empregador)
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.publication_ideas (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  source_type text CHECK (source_type IN (
    'meeting_action','hub_resource','wiki_page','external_research',
    'experiment','partnership','webinar','ata_decision','submission_external'
  )),
  source_id uuid,                                  -- FK polimórfica intencional
  title text NOT NULL,
  summary text,
  tribe_id integer REFERENCES public.tribes(id),
  initiative_id uuid REFERENCES public.initiatives(id),
  author_ids uuid[] NOT NULL DEFAULT '{}'::uuid[],
  proposed_channels text[] DEFAULT '{}'::text[],   -- ex: ['blog','newsletter','pmcom']
  stage text NOT NULL DEFAULT 'draft' CHECK (stage IN (
    'draft','proposed','researching','writing',
    'tribe_review','leader_review','curation',
    'approved','published','archived'
  )),
  series_id uuid REFERENCES public.publication_series(id),
  target_languages text[] NOT NULL DEFAULT ARRAY['pt-BR'],
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,     -- declarações + checks (#96 PI)
  created_by uuid REFERENCES public.members(id),
  organization_id uuid NOT NULL DEFAULT '2b4f58ab-7c45-4170-8718-b77ee69ff906',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  published_at timestamptz
);

CREATE INDEX idx_publication_ideas_stage ON public.publication_ideas(stage);
CREATE INDEX idx_publication_ideas_series ON public.publication_ideas(series_id) WHERE series_id IS NOT NULL;
CREATE INDEX idx_publication_ideas_tribe ON public.publication_ideas(tribe_id) WHERE tribe_id IS NOT NULL;
CREATE INDEX idx_publication_ideas_authors ON public.publication_ideas USING GIN (author_ids);
CREATE INDEX idx_publication_ideas_metadata ON public.publication_ideas USING GIN (metadata);

-- Constraint: metadata DEVE ter 3 declarações antes de avançar para 'tribe_review' ou além
-- (enforced via trigger; opção mais leve que CHECK por causa de jsonb shape)
CREATE OR REPLACE FUNCTION public.publication_ideas_check_declarations() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.stage IN ('tribe_review','leader_review','curation','approved','published') THEN
    IF NOT (
      NEW.metadata ? 'ai_usage_declaration' AND
      NEW.metadata ? 'employer_consent_confirmed' AND
      NEW.metadata ? 'conflicts_of_interest'
    ) THEN
      RAISE EXCEPTION 'publication_ideas: cannot advance to stage % without 3 mandatory declarations in metadata (ai_usage_declaration, employer_consent_confirmed, conflicts_of_interest). See CR-050 v2.2 §4.', NEW.stage;
    END IF;
  END IF;
  NEW.updated_at = now();
  RETURN NEW;
END $$;

CREATE TRIGGER trg_publication_ideas_check_declarations
  BEFORE INSERT OR UPDATE ON public.publication_ideas
  FOR EACH ROW EXECUTE FUNCTION public.publication_ideas_check_declarations();

-- RLS
ALTER TABLE public.publication_ideas ENABLE ROW LEVEL SECURITY;

CREATE POLICY publication_ideas_read_members ON public.publication_ideas
  FOR SELECT USING (rls_is_member());

CREATE POLICY publication_ideas_authors_write ON public.publication_ideas
  FOR ALL USING (
    auth.uid() IN (
      SELECT m.auth_id FROM public.members m WHERE m.id = ANY(author_ids)
    )
    OR EXISTS (
      SELECT 1 FROM public.members m
      WHERE m.auth_id = auth.uid() AND (m.is_superadmin = true OR m.role IN ('comms_leader','tribe_leader'))
    )
  );

CREATE POLICY publication_ideas_v4_org_scope ON public.publication_ideas
  FOR ALL USING ((organization_id = auth_org()) OR (organization_id IS NULL));

-- FKs opcionais nas 4 tabelas downstream (ADR-0020 D2 specs)
ALTER TABLE public.blog_posts ADD COLUMN IF NOT EXISTS source_idea_id uuid REFERENCES public.publication_ideas(id);
ALTER TABLE public.publication_submissions ADD COLUMN IF NOT EXISTS source_idea_id uuid REFERENCES public.publication_ideas(id);
ALTER TABLE public.campaign_sends ADD COLUMN IF NOT EXISTS source_idea_id uuid REFERENCES public.publication_ideas(id);
ALTER TABLE public.public_publications ADD COLUMN IF NOT EXISTS source_idea_id uuid REFERENCES public.publication_ideas(id);

CREATE INDEX IF NOT EXISTS idx_blog_posts_source_idea ON public.blog_posts(source_idea_id) WHERE source_idea_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_publication_submissions_source_idea ON public.publication_submissions(source_idea_id) WHERE source_idea_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_campaign_sends_source_idea ON public.campaign_sends(source_idea_id) WHERE source_idea_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_public_publications_source_idea ON public.public_publications(source_idea_id) WHERE source_idea_id IS NOT NULL;

COMMENT ON TABLE public.publication_ideas IS 'Primitivo de pipeline editorial (ADR-0020 D2 + #94 W2). Stages alinhados com Guia Frontiers §9. metadata exige 3 declarações antes de tribe_review.';
```

**Validação pós-apply:**

```sql
-- 10 stages esperados
SELECT pg_get_constraintdef(oid)
FROM pg_constraint
WHERE conrelid = 'public.publication_ideas'::regclass AND contype = 'c';

-- Trigger declaração obrigatória ativo
SELECT tgname FROM pg_trigger WHERE tgrelid = 'public.publication_ideas'::regclass;

-- Smoke test: insert sem declarações e tentar mover para 'tribe_review' deve FALHAR
BEGIN;
  INSERT INTO publication_ideas (title) VALUES ('test') RETURNING id;
  -- esperar EXCEPTION:
  -- UPDATE publication_ideas SET stage='tribe_review' WHERE title='test';
ROLLBACK;
```

---

## SQL Block 3 — Seed `frontiers-newsletter` em `publication_series`

**Arquivo target:** `supabase/migrations/AAAAMMDDhhmmss_frontiers_newsletter_seed.sql`
**Tempo estimado de aplicação:** ~10s
**Risco:** 🟢 Aditivo (single INSERT com ON CONFLICT).
**Depende de Decisões:** 1 (nome final), 2 (idioma), 6 (Frontiers como série da plataforma — se NÃO, pular este block).

```sql
-- ============================================================================
-- Issue #96 Gate 1 — Seed Newsletter Frontiers como 6ª publication_series
--
-- Pré-requisitos:
-- - Gate 0 da #96 fechado (CR-050 ratificada + Termo R3-C4 + decisão de marca)
-- - Decisões 1, 2, 6 do GP+Fabrício preenchidas
-- ============================================================================

INSERT INTO public.publication_series (
  slug,
  title_i18n,
  description_i18n,
  cadence_hint,
  format_default,
  editorial_voice,
  target_audience,
  hero_tribe_id,
  hero_initiative_id,
  is_active
) VALUES (
  '__SLUG__',  -- ex: 'frontiers-newsletter' (ajustar após decisão 1 de nome)
  jsonb_build_object(
    'en', '__FRONTIERS_NAME_EN__',
    'pt', '__FRONTIERS_NAME_PT__',
    'es', '__FRONTIERS_NAME_ES__'
  ),
  jsonb_build_object(
    'en', 'Monthly newsletter on the frontiers of AI applied to project management. Editorial voice: professional, neutral, institutional. Language policy: __LANGUAGE_POLICY__. Default license: __CC_LICENSE__. Governed by __TERM_REF__.',
    'pt', 'Newsletter mensal sobre as fronteiras da IA aplicada à gestão de projetos. Voz editorial: profissional, neutra, institucional. Política de idioma: __LANGUAGE_POLICY__. Licença default: __CC_LICENSE__. Regida por __TERM_REF__.',
    'es', 'Newsletter mensual sobre las fronteras de la IA aplicada a la gestión de proyectos.'
  ),
  'monthly',
  'newsletter',
  'Profissional, neutro, institucional',
  'PM profissional internacional + academia PM+IA',
  NULL,  -- transversal a todas as tribos
  NULL   -- sem initiative específica
)
ON CONFLICT (slug) DO NOTHING;

COMMENT ON TABLE public.publication_series IS 'Séries temáticas. 6 ativas (5 originais + frontiers-newsletter). Ver SPEC_FRONTIERS_NEWSLETTER_LAUNCH.md.';
```

**Validação pós-apply:**

```sql
SELECT slug, title_i18n->>'en' AS name_en, cadence_hint, editorial_voice
FROM publication_series
WHERE slug = '__SLUG__';
```

---

## SQL Block 4 — Renomear `weekly-radar-tribe-1` → `research-stream-tribe-1` (opcional)

**Arquivo target:** `supabase/migrations/AAAAMMDDhhmmss_unify_research_stream_naming.sql`
**Tempo estimado de aplicação:** ~5s
**Risco:** 🟡 Renomeia slug — pode quebrar URLs futuras (mas hoje 0 posts apontam para essa série).
**Depende de Decisões:** confirmação que GP quer unificar nome com Guia §5 "Research Stream Insight" (Oportunidade #14 da #94).

```sql
-- Issue #94 Oportunidade #14 — unifica naming Research Stream Insight (Guia §5)
-- com weekly-radar-tribe-* da plataforma. Captura tanto curadoria interna quanto
-- externa numa série só.

UPDATE public.publication_series
SET slug = 'research-stream-tribe-1',
    title_i18n = jsonb_build_object(
      'pt', 'Research Stream — T1 Tecnologia',
      'en', 'Research Stream — T1 Tech',
      'es', 'Research Stream — T1 Tecnología'
    ),
    description_i18n = jsonb_build_object(
      'pt', 'Stream curatorial da Tribo 1 cobrindo (a) avanços de pesquisa interna da tribo e (b) radar de insights externos. Cadência semanal. Alinhado com Guia Editorial Frontiers §5 "Research Stream Insight".'
    ),
    editorial_voice = 'Curatorial + research'
WHERE slug = 'weekly-radar-tribe-1';
```

---

## Pós-Gate-1 — checklist operacional

Após executar todos os SQL blocks aprovados:

- [ ] Rodar `check_schema_invariants()` — todas as 8 invariantes 🟢
- [ ] Rodar `mcp_smoke()` — sem regressão
- [ ] Atualizar Content Pipeline Playbook (`docs/editorial/CONTENT_PIPELINE_PLAYBOOK.md`) com seção dedicada Frontiers (já preparada com TBD)
- [ ] Comunicar superadmins via meeting agendado: "publication_ideas existe — pipeline editorial agora tem source-of-truth"
- [ ] Adicionar `frontiers-newsletter` ao backlog editorial do Fabrício como 1ª série a popular
- [ ] Marcar #94 W2 como completo + atualizar status de #96 Gate 1
- [ ] Ativar `check_idea_originality` (#95 W2) **antes** da issue #1 do Frontiers ser criada — ver Comment 5 da #94

## Estimativa total de execução pós-Gate-0

| Bloco | Tempo |
|---|---|
| SQL Block 1 (categorias) | ~5min (incluindo PR review) |
| SQL Block 2 (publication_ideas) | ~15min (PR review + smoke test) |
| SQL Block 3 (seed Frontiers) | ~5min |
| SQL Block 4 (rename, opcional) | ~3min |
| Pós-Gate-1 checklist | ~30min |
| **TOTAL** | **~1h** |

## Trace

- Origem: análise Guia Editorial Frontiers + cross-check operacional Claude B (sessão 9908f3)
- Anchor docs: ADR-0020 (publication pipeline base), ADR-0021 (Frontiers governance addendum, Proposed)
- Issues: #94 (Pipeline), #95 (echo-chamber), #96 (Frontiers launch)
- Trigger: GP Vitor pediu pre-arrange Gate 1 enquanto Gate 0 ainda em deliberação (2026-04-21 ~24h)

Assisted-By: Claude (Anthropic)
