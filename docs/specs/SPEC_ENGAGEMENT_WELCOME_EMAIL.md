# Feature Spec: Engagement Welcome Email (G7 do issue #97)

## Status: Proposed (parallel track com SPEC_WEEKLY_MEMBER_DIGEST.md)

> ⚠️ **Delivery mode definido 2026-04-22 p35** — per [ADR-0022](../adr/ADR-0022-communication-batching-weekly-digest-default.md), o welcome tem entrega **híbrida**: `transactional_immediate` para kinds com `requires_agreement=true` (volunteer, external_signer) ou `speaker` de congress com deadline externo < 14d; **`digest_weekly`** (consolidado no digest de sábado) para demais kinds (observer, committee_member, study_group_participant, guest, partner_contact). Implementação da migração abaixo deve setar `notifications.delivery_mode` conforme esta regra no INSERT do `enqueue_engagement_welcome`.

## Problema
Quando um `engagement` é criado (`INSERT INTO public.engagements`), nenhuma notificação é disparada. Audit runtime (sessão `d211ff` 22/Abr) rejeitou 4 hipóteses: único trigger `trg_sync_role_cache` só atualiza `members.operational_role`; RPC `manage_initiative_engagement` não dispara nada; 14 funções `onboard_*` são todas para fluxo de candidato pós-seleção. **Validação empírica**: Sarah confirmou não ter recebido email após ser adicionada como observer/reviewer na initiative LATAM LIM 2026.

Consequência prática: member vira speaker / volunteer / observer / committee_member sem feedback de sistema, sem contexto (link para initiative, WhatsApp, termo a assinar se aplicável, próximos passos), sem registro formal de entrega do termo (`requires_agreement=true` kinds) — gap crítico de UX e de LGPD.

## Superfície tocada
- `pg_trigger`: novo trigger `trg_engagement_welcome_notify` (AFTER INSERT)
- `pg_proc`: nova função `enqueue_engagement_welcome(p_engagement_id uuid)`
- `public.notifications`: novo `type='engagement_welcome'` (text column, sem enum, já aceita novos valores)
- Edge function `send-notification-email` (já existe, já roda a cada 5min): adicionar template renderer para `type='engagement_welcome'`, variantes por `engagement_kind`

**Zero conflict com #98** — surface totalmente distinta (member column, cron, novas RPCs).

## Migration (proposta)

```sql
-- 1. Função que enfileira o welcome
CREATE OR REPLACE FUNCTION public.enqueue_engagement_welcome(p_engagement_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public', 'pg_temp'
AS $$
DECLARE
  v_eng record;
  v_member_id uuid;
  v_kind record;
  v_initiative_title text;
  v_whatsapp_url text;
BEGIN
  SELECT e.*, ek.display_name AS kind_name, ek.requires_agreement,
         ek.agreement_template, i.title AS initiative_title,
         i.metadata->>'whatsapp_url' AS whatsapp_url
  INTO v_eng
  FROM public.engagements e
  LEFT JOIN public.engagement_kinds ek ON ek.slug = e.kind
  LEFT JOIN public.initiatives i ON i.id = e.initiative_id
  WHERE e.id = p_engagement_id AND e.status = 'active';

  IF v_eng IS NULL THEN RETURN; END IF;

  -- person → member
  SELECT id INTO v_member_id FROM public.members WHERE person_id = v_eng.person_id;
  IF v_member_id IS NULL THEN RETURN; END IF;

  -- respeitar opt-out (reusa mesma coluna do #98 se existir; senão sempre notifica)
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='members' AND column_name='notify_engagement_welcome'
  ) AND (SELECT NOT notify_engagement_welcome FROM public.members WHERE id = v_member_id) THEN
    RETURN;
  END IF;

  INSERT INTO public.notifications (recipient_id, type, title, body, metadata, is_read)
  VALUES (
    v_member_id,
    'engagement_welcome',
    'Bem-vindo(a) como ' || COALESCE(v_eng.kind_name, v_eng.kind) ||
      CASE WHEN v_eng.initiative_title IS NOT NULL THEN ' em ' || v_eng.initiative_title ELSE '' END,
    NULL, -- body renderizado na EF a partir do template+metadata
    jsonb_build_object(
      'engagement_id', v_eng.id,
      'engagement_kind', v_eng.kind,
      'engagement_role', v_eng.role,
      'initiative_id', v_eng.initiative_id,
      'initiative_title', v_eng.initiative_title,
      'whatsapp_url', v_eng.whatsapp_url,
      'requires_agreement', COALESCE(v_eng.requires_agreement, false),
      'agreement_template', v_eng.agreement_template,
      'template_key', 'engagement_welcome__' || v_eng.kind
    ),
    false
  );

  -- Consent/LGPD log quando requires_agreement
  IF COALESCE(v_eng.requires_agreement, false) THEN
    INSERT INTO public.pii_access_log (member_id, accessed_by, purpose, metadata)
    VALUES (v_member_id, v_eng.granted_by,
            'engagement_welcome_with_agreement_delivery',
            jsonb_build_object('engagement_id', v_eng.id, 'kind', v_eng.kind));
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.enqueue_engagement_welcome(uuid) TO service_role;

-- 2. Trigger AFTER INSERT
CREATE OR REPLACE FUNCTION public.trg_engagement_welcome_fn()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public', 'pg_temp'
AS $$
BEGIN
  IF NEW.status = 'active' THEN
    PERFORM public.enqueue_engagement_welcome(NEW.id);
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_engagement_welcome_notify
  AFTER INSERT ON public.engagements
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_engagement_welcome_fn();
```

## Edge Function — template renderer (pseudo)

Em `send-notification-email/index.ts`, adicionar handler para `type='engagement_welcome'`:

```ts
if (notification.type === 'engagement_welcome') {
  const md = notification.metadata;
  const templateKey = md.template_key; // ex: engagement_welcome__speaker
  const body = renderTemplate(templateKey, {
    member_name, initiative_title: md.initiative_title,
    whatsapp_url: md.whatsapp_url,
    role_display: md.engagement_role,
    agreement_url: md.requires_agreement
      ? buildSignUrl(member.id, md.agreement_template) : null,
    next_steps: nextStepsByKind(md.engagement_kind),
  });
  return { subject: notification.title, html: body };
}
```

Templates a criar (mínimo V1): `engagement_welcome__speaker`, `engagement_welcome__volunteer`, `engagement_welcome__observer`, `engagement_welcome__committee_member`, `engagement_welcome__committee_coordinator`, `engagement_welcome__study_group_participant`. Fallback genérico `engagement_welcome__default`.

Cada template inclui:
- Saudação + confirmação do role
- Link para a initiative (`/initiative/<id>`)
- WhatsApp se `metadata.whatsapp_url` presente
- Próximos passos (checklist por kind)
- Link para assinar termo se `requires_agreement=true`
- Footer com opt-out settings

## Testes (contract)
- `tests/contracts/engagement-welcome-notify.test.mjs`:
  1. INSERT active engagement → 1 row em `notifications` com `type='engagement_welcome'` em < 100ms
  2. INSERT com status='revoked' → **0 rows** gerados
  3. INSERT volunteer (requires_agreement=true) → row em `pii_access_log` com `purpose='engagement_welcome_with_agreement_delivery'`
  4. INSERT member com `notify_engagement_welcome=false` (se coluna existir) → 0 rows gerados
  5. Backfill: N engagements existentes **não** devem gerar welcome retroativo (trigger só pega INSERTs novos)

## Rollout

1. Migration aditiva (função + trigger)
2. EF deploy com templates novos + fallback genérico
3. Smoke manual: adicionar observer em qualquer initiative-teste → validar delivery em 5-10 min (cron `send-notification-emails` roda a cada 5min)
4. Watch `notifications` + `admin_audit_log` 24h; se email bounce > 1%, rollback trigger

## Riscos

- **Backfill retroativo acidental** — mitigação: trigger só AFTER INSERT, nunca AFTER UPDATE; código nunca hit em rows existentes.
- **Spam se um admin bulk-add** — considerar rate-limit por `granted_by` (10/hora)? V2 se ocorrer.
- **Templates faltando** — fallback `engagement_welcome__default` cobre kinds não mapeados; EF loga warning.

## Cross-ref
- Issue #97 G7 (este spec materializa o gap)
- Issue #88 convocação — trigger é o pair natural do "owner convida → aceita → welcome"
- Issue #85 LGPD — `pii_access_log` rows geradas fecham loop de evidência
- Issue #98 (paralelo) — surface disjunta; pode reusar coluna `members.notify_weekly_digest` pattern para opt-out (nome `notify_engagement_welcome`)

## Estimativa

- Migration: 1-2h
- EF + templates (6 kinds + default): 2-3h
- Testes contract + smoke: 1h
- **Total: 4-6h**
