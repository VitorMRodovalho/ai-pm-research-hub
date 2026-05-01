# Spec p87 — External Speaker Engagement Lifecycle (Partnership → Initiative)

**Status:** Spec design (0-deploy planning)
**Origem:** GitHub issue #97 (consolidação executable)
**Caso real:** 2026 LATAM LIM (Lima, 13-16/Ago) — Roberto Macêdo lead + Ivan co-speaker
**W1 já shipped:** 22/Abr 2026, sessão `d211ff` — initiative `a68fcc06-...` + 7 milestones + 5 engagements + WhatsApp group via MCP, zero schema change
**Próximas waves:** W2 (schema hardening), W3 (MCP + automation), W4 (UX wizard)

---

## 1. Problema

A jornada `partner_entity` → `initiative congress` foi possível em W1 sem schema change, mas evidência relacional ficou ad-hoc. 7 gaps estruturais (G1-G7) identificados durante audit runtime impedem:

- Replay automatizado para próximas submissões (LIM 2027, ProjectManagement.com articles, etc.)
- Dashboard "external engagements" sem inferência via metadata jsonb
- Welcome email a engajados (G7 — gap LGPD + UX crítico)
- Distinção lead/co speaker formal (G2)
- Tag de proveniência externa em deadlines (G3)

## 2. Inventário G1-G7 com proposta executável

### G1 — `initiatives` ↔ `partner_entities` sem FK
**Hoje:** linked apenas via `metadata.partner_entity_id` ad-hoc
**Proposta W2:** coluna nullable + FK + index parcial

```sql
ALTER TABLE public.initiatives
  ADD COLUMN IF NOT EXISTS origin_partner_entity_id uuid
    REFERENCES public.partner_entities(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS ix_initiatives_origin_partner
  ON public.initiatives (origin_partner_entity_id)
  WHERE origin_partner_entity_id IS NOT NULL;

-- Backfill LATAM LIM W1 case
UPDATE public.initiatives
SET origin_partner_entity_id = '8bb97295-4e8e-4e19-98a4-37b72d3305b8'::uuid
WHERE id = 'a68fcc06-7de8-400b-b5b3-60e368fb46ac'::uuid
  AND origin_partner_entity_id IS NULL;
```

**Cross-cut:** #85 menciona "partner ↔ card FK"; G1 expande para partner ↔ initiative.

### G2 — Distinção lead/co speaker ausente
**Hoje:** `engagement_kinds.speaker` único; W1 usou `engagements.metadata.presenter_role IN ('lead','co')` ad-hoc
**Proposta W2 (escolher 1):**

**Opção A:** novo kind `co_speaker` em `engagement_kinds`
```sql
INSERT INTO public.engagement_kinds (kind, label, initiative_kinds_allowed, requires_agreement)
VALUES ('co_speaker', 'Co-palestrante', ARRAY['congress','workshop'], false)
ON CONFLICT (kind) DO NOTHING;
```

**Opção B (PREFERIDA):** CHECK em `engagements.metadata` formalizando convenção
```sql
ALTER TABLE public.engagements
  ADD CONSTRAINT engagements_speaker_role_check
  CHECK (
    kind <> 'speaker'
    OR (metadata ->> 'presenter_role') IN ('lead', 'co', 'panelist', 'moderator')
  );
```

**Recomendação:** Opção B — preserva cardinality única do kind, evita explosão de kinds. Ratificar com council.

### G3 — Proveniência externa de deadlines sem tag formal
**Hoje:** `board_items.tags=['pmi_lim_2026','external_milestone']` workaround
**Proposta W2:** colunas tipadas

```sql
ALTER TABLE public.board_items
  ADD COLUMN IF NOT EXISTS source_type text DEFAULT 'internal',
  ADD COLUMN IF NOT EXISTS source_partner_id uuid REFERENCES public.partner_entities(id) ON DELETE SET NULL;

ALTER TABLE public.board_items
  ADD CONSTRAINT board_items_source_type_check
  CHECK (source_type IN ('internal','external_partner','external_event'));

CREATE INDEX IF NOT EXISTS ix_board_items_source_partner
  ON public.board_items (source_partner_id, source_type)
  WHERE source_partner_id IS NOT NULL;

-- Backfill LATAM LIM 7 milestones
UPDATE public.board_items
SET source_type = 'external_partner',
    source_partner_id = '8bb97295-4e8e-4e19-98a4-37b72d3305b8'::uuid
WHERE board_id = '632787ee-9e27-43c9-b6a0-566b52815adc'::uuid;
```

**Cross-cut:** #92 (calendar integration) — escopos diferentes (G3 = origem partner; #92 = sync GCal/Outlook).

### G4 — Sem MCP tool `create_external_speaker_engagement`
**Hoje:** SQL direto via MCP execute_sql
**Proposta W3:** novo MCP tool em nucleo-mcp + RPC backing

```typescript
// supabase/functions/nucleo-mcp/index.ts
mcp.tool("create_external_speaker_engagement", "...", {
  partner_entity_id: z.string().uuid(),
  lead_person_id: z.string().uuid(),
  co_person_id: z.string().uuid().optional(),
  initiative_title: z.string(),
  initiative_kind: z.enum(['congress','workshop']),
  deadlines: z.array(z.object({
    title: z.string(),
    due_date: z.string(),
    is_portfolio: z.boolean().default(false),
  })),
  whatsapp_url: z.string().url().optional(),
}, async (params) => {
  const { data, error } = await sb.rpc("create_external_speaker_engagement_v1", { p_payload: params });
  // ... gating canV4 manage_partner OR manage_event
});
```

Backing RPC `create_external_speaker_engagement_v1(p_payload jsonb)` faz tudo numa transação:
- INSERT initiative (kind, origin_partner_entity_id from G1)
- INSERT project_board (taxonomy gating)
- INSERT engagements (lead = speaker/presenter_role=lead, co = speaker/presenter_role=co, GP volunteer/coordinator, T6 leader observer/reviewer, committee_coord observer/reviewer)
- INSERT board_items (each deadline, source_type=external_partner from G3, is_portfolio_item if marked)
- UPDATE partner_entity (status='active', next_action, follow_up_date)
- INSERT partner_interactions audit log

**Cross-cut:** #88 (convocação MCP-first) — pattern alinhado.

### G5 — Subject Matter Expert feedback sem estrutura formal
**Hoje:** W1 usou `board_items.checklist jsonb` + `attachments jsonb`
**Proposta W3 (avaliar reuso):**

Avaliar se `document_comments` (#85 — Phase IP-1) cobre o caso:
- `document_comments.clause_anchor` permite ancorar comments a sections de proposta
- Document_versions pode versionar draft → final
- Reuso evita criar nova table

**Decisão:** spike de 30min testando com proposta LATAM LIM M3 (draft) + M5 (final). Se cobre 80%+ dos casos SME, reusar. Senão, propor `submission_reviews` table dedicada.

### G6 — Portfolio artifact convention não documentada
**Hoje:** time diverge sobre "qual artefato vai pra onde"
**Proposta W2:** ADR-0068 ou doc convention

Criar `docs/adr/ADR-0068-external-speaker-artifact-conventions.md` documentando:

| Stage | Artefato | Schema target | Visibility |
|---|---|---|---|
| Pre-submission | Draft video preview | `meeting_artifacts` | Comitê (privado) |
| Stage 1 review | Draft slides PPT | `meeting_artifacts` | Reviewers (Fabricio, Sarah) |
| Stage 2 final | Final slides PPT | `meeting_artifacts` | Comitê + curador |
| Post-event | Gravação oficial PMI | `public_publications` (kind='video') | Público |
| Post-event | Slides finais públicos | `public_publications` (kind='deck') | Público (CC-BY-SA opcional) |

**Cross-cut:** #94 W1 (publication_ideas pipeline 10-stage) — pode integrar G6 na 6ª seed "Palestras & Keynotes".

### G7 — Welcome email em engagement INSERT ⚠️ CRITICAL
**Audit confirmado:** ZERO trigger/RPC envia welcome ao adicionar engagement. UX gap + LGPD risk para kinds com `requires_agreement=true`.

**Proposta W3:** 3-piece migration + EF + templates

#### Piece 1 — RPC helper `_enqueue_engagement_welcome(engagement_id)`
```sql
CREATE OR REPLACE FUNCTION public._enqueue_engagement_welcome(p_engagement_id uuid)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_eng record;
  v_template_slug text;
  v_first_name text;
  v_member record;
  v_metadata jsonb;
BEGIN
  SELECT e.*, p.name AS person_name, m.email AS member_email, m.id AS member_id,
         i.title AS initiative_title, i.metadata AS initiative_metadata
  INTO v_eng
  FROM engagements e
  JOIN persons p ON p.id = e.person_id
  LEFT JOIN members m ON m.person_id = p.id AND m.is_active = true
  JOIN initiatives i ON i.id = e.initiative_id
  WHERE e.id = p_engagement_id;

  IF NOT FOUND OR v_eng.member_email IS NULL THEN RETURN; END IF;

  v_template_slug := 'engagement_welcome_' || v_eng.kind;  -- e.g., engagement_welcome_speaker

  v_first_name := split_part(v_eng.person_name, ' ', 1);

  -- Use campaign_send_one_off (pattern adopted Wave 5d/5b-2)
  PERFORM public.campaign_send_one_off(
    v_template_slug,
    v_eng.member_email,
    jsonb_build_object(
      'first_name', v_first_name,
      'initiative_title', v_eng.initiative_title,
      'engagement_kind_label', v_eng.kind,
      'whatsapp_url', v_eng.initiative_metadata ->> 'whatsapp_url'
    ),
    jsonb_build_object(
      'language', 'pt',
      'recipient_name', v_eng.person_name,
      'source', 'engagement_welcome'
    )
  );
END $$;
```

#### Piece 2 — Trigger AFTER INSERT
```sql
CREATE OR REPLACE FUNCTION public._trg_engagement_welcome_notify()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'pg_temp'
AS $$
BEGIN
  -- Only on initial INSERT, not status transitions
  IF TG_OP = 'INSERT' AND NEW.status = 'active' THEN
    -- Async via pg_net (don't block INSERT on Resend latency)
    PERFORM public._enqueue_engagement_welcome(NEW.id);
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_engagement_welcome_notify ON public.engagements;
CREATE TRIGGER trg_engagement_welcome_notify
  AFTER INSERT ON public.engagements
  FOR EACH ROW EXECUTE FUNCTION public._trg_engagement_welcome_notify();
```

#### Piece 3 — campaign_templates seeds (pt/en/es) per kind
Initial set: `engagement_welcome_speaker`, `engagement_welcome_volunteer`, `engagement_welcome_observer`. Templates re-usam plumbing campaign_send_one_off.

**Risco:** envia email a TODAS novas engagements ativas — incluindo backfill futuro. Mitigation: feature flag `metadata.skip_welcome_email=true` para casos de backfill bulk.

**Cross-cut:** #88 (convocação) — pair natural "owner convida → member aceita → welcome contextualizado".

## 3. Risk + sequencing por wave

### W2 — Schema hardening aditivo (~2h, 1 commit + 1 ADR)
**Risk:** baixo. Tudo additive, FKs nullable, backfill 1 row LATAM LIM.
**Auth-affecting:** não.
**Launch week safe:** sim.
**Migration:** `20260516370000_p87_external_engagement_w2_schema.sql`
**ADR:** `docs/adr/ADR-0068-external-speaker-artifact-conventions.md`

### W3 — MCP + automation (~3-4h, 2-3 commits)
**Risk:** moderado. Inclui novo MCP tool (nucleo-mcp redeploy) + new EF `send-engagement-welcome` + trigger AFTER INSERT em engagements (high-traffic path).
**Auth-affecting:** parcial — novo MCP tool tem canV4 gate; trigger SECDEF + search_path pinned.
**Launch week safe:** **AGUARDAR quiet window** D+5 OR após 1ª semana CBGPL.
**EF redeploys:** nucleo-mcp + send-engagement-welcome (nova).

### W4 — UX wizard (~2-3h, 1-2 commits)
**Risk:** baixo. Frontend only.
**Auth-affecting:** não.
**Launch week safe:** sim.
**Files:** `src/pages/admin/partnerships/[id].astro` ou `src/components/admin/partnerships/CongressWizard.tsx` + dashboard "external engagements" em `src/pages/admin/initiatives/external.astro`.

## 4. Estimativa total

| Wave | Effort | Risk | Dependencies | Sessions |
|---|---|---|---|---|
| W2 schema | ~2h | low | none | 1 |
| W3 MCP+auto | ~3-4h | moderate | W2 (G1+G3 cols) | 1-2 |
| W4 UX | ~2-3h | low | W2 | 1 |
| **Total** | **~7-9h** | | | **3-4 sessions** |

W2 pode shippar mesmo durante launch week. W3 espera quiet window. W4 fica para depois (ou pode shippar parallel a W3 sem dependency dura).

## 5. Validations needed before W2

- **legal-counsel** review G7 welcome email LGPD (consent contínua sob umbrella ou cada engagement requires confirm-link?)
- **ux-leader** decisão UI Card Wizard vs templated form (W4 scope)
- **security-engineer** review trigger AFTER INSERT polarity (deadlock risk em high-volume engagement INSERTs?)
- **PM** ratifica G2 Opção A (kind co_speaker) vs Opção B (CHECK metadata)

## 6. Não está em escopo desta spec

- Calendar integration (#92) — escopo separado
- publication_ideas pipeline (#94) — cross-ref G6
- WhatsApp MCP integration (#93) — escopo separado
- pii_access_log (#85 Phase IP-2) — cross-ref G7 LGPD audit

## 7. Open questions

1. **Backfill batching** — quando G7 W3 trigger landar, todos os engagements existentes ativos receberão welcome se reativarmos? Solução: feature flag `metadata.skip_welcome_email=true` no trigger condition.
2. **Welcome dedup** — usuário com 5 engagements simultâneos recebe 5 emails? Solução: rate limit 1 welcome per (member_id × kind) per 24h via `notifications.delivery_mode='digest_daily'`.
3. **Templates per kind variation** — quantos kinds precisam de template dedicado? Initial: speaker (lead+co), volunteer, observer. Outros (external_signer, etc) seguem template default fallback.

## 8. Cross-ref

- Issue origem: #97
- Cross-cut: #85 #88 #92 #94
- Wave 5b/5d shipped p86 (campaign_send_one_off pattern reused em G7 Piece 1)
- ADR-0066 (PMI Journey v4) — engagement subsystem reference

## 9. Trace W1

- Debug session: Cursor `d211ff` (2026-04-22)
- Initiative: `a68fcc06-7de8-400b-b5b3-60e368fb46ac`
- Board: `632787ee-9e27-43c9-b6a0-566b52815adc`
- Partner entity: `8bb97295-4e8e-4e19-98a4-37b72d3305b8`
- Engagements: 5 IDs (Roberto, Ivan, Vitor, Fabricio, Sarah)
- WhatsApp: `https://chat.whatsapp.com/FWOxzlb80gJ1HUFGUMAgfa`

## 10. Sediment para futuras submissões

Se W2-W4 shippadas, replay para próxima submissão (LIM 2027, PMI Global, ProjectManagement.com articles) reduz de **~3h SQL manual** para **~5 min via MCP wizard**. ROI mede-se quando 2ª submissão landar.
