# Feature Spec: Weekly Member Digest (Saturday) — issue #98 + ADR-0022

## Status: Proposed (parallel track com SPEC_ENGAGEMENT_WELCOME_EMAIL.md)

> ⚠️ **Escopo ampliado 2026-04-22 p35** — per [ADR-0022](../adr/ADR-0022-communication-batching-weekly-digest-default.md), este digest deixa de ser apenas "card digest" e passa a ser o **single weekly email** consolidando toda comunicação de rotina (cards, eventos, broadcasts, publicações, governance pendente, achievements). RPC renomeia: `get_weekly_card_digest` → `get_weekly_member_digest` com 7 seções. Seção 1 "cards" abaixo segue sendo o primeiro corte MVP; seções 2-7 entram em W2 conforme ADR-0022. Arquivo renomeado: antes era `SPEC_WEEKLY_CARD_DIGEST.md`.

## Problema
Plataforma tem 472 board_items, 89 com `due_date`, 32 abertos com due pendente, **18 overdue** (snapshot 22/Abr). Não há sinal automatizado para (a) lembrar member de atualizar cards pending, (b) mostrar o que vem na próxima semana, (c) dar ao leader visibilidade agregada do health da tribo/iniciativa. Hoje leaders cobram via WhatsApp individual — não escala.

## Objetivo
Todo sábado 09:00 BRT (12:00 UTC), member ativo com cards ou tasks recebe digest individual; leader de initiative recebe stats agregado (sem conteúdo individual de outros members — privacy-preserving).

## Superfície tocada
- `public.members`: nova coluna `notify_weekly_digest boolean DEFAULT true`
- `pg_proc`: RPCs `get_weekly_card_digest(p_member_id uuid)`, `get_weekly_tribe_digest(p_initiative_id uuid)` (V2), `generate_weekly_card_digest_cron()`
- `public.notifications`: novo `type='weekly_card_digest_member'` (V1) + `type='weekly_card_digest_leader'` (V2)
- `cron.job`: nova entry `weekly-card-digest-saturday` (12:00 UTC Sábado)
- Edge function `send-notification-email`: novo template renderer para os types acima

**Zero conflict com SPEC_ENGAGEMENT_WELCOME_EMAIL.md** — surface disjunta (column em members, cron, RPCs novas). Os únicos pontos comuns são `notifications.type` (text, aceita novos valores) e `send-notification-email` EF (multi-template por type).

## MVP (V1) — Member digest only

### Migration

```sql
-- 1. Opt-out
ALTER TABLE public.members
  ADD COLUMN IF NOT EXISTS notify_weekly_digest boolean NOT NULL DEFAULT true;
COMMENT ON COLUMN public.members.notify_weekly_digest IS
  'Opt-in/out do weekly card digest (sábado 09:00 BRT). Default true.';

-- 2. RPC — digest individual
CREATE OR REPLACE FUNCTION public.get_weekly_card_digest(p_member_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = 'public', 'pg_temp'
AS $$
DECLARE
  v_result jsonb;
BEGIN
  SELECT jsonb_build_object(
    'member_id', p_member_id,
    'generated_at', now(),
    'this_week_pending', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', bi.id, 'title', bi.title, 'status', bi.status,
        'due_date', bi.due_date, 'board_name', pb.board_name,
        'initiative_title', i.title,
        'days_overdue', CURRENT_DATE - bi.due_date
      ) ORDER BY bi.due_date ASC)
      FROM public.board_items bi
      LEFT JOIN public.project_boards pb ON pb.id = bi.board_id
      LEFT JOIN public.initiatives i ON i.id = pb.initiative_id
      WHERE bi.assignee_id = p_member_id
        AND bi.status NOT IN ('done','archived')
        AND bi.due_date BETWEEN CURRENT_DATE - INTERVAL '7 days' AND CURRENT_DATE
    ), '[]'::jsonb),
    'next_week_due', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', bi.id, 'title', bi.title, 'status', bi.status,
        'due_date', bi.due_date, 'board_name', pb.board_name,
        'initiative_title', i.title
      ) ORDER BY bi.due_date ASC)
      FROM public.board_items bi
      LEFT JOIN public.project_boards pb ON pb.id = bi.board_id
      LEFT JOIN public.initiatives i ON i.id = pb.initiative_id
      WHERE bi.assignee_id = p_member_id
        AND bi.status NOT IN ('done','archived')
        AND bi.due_date > CURRENT_DATE
        AND bi.due_date <= CURRENT_DATE + INTERVAL '7 days'
    ), '[]'::jsonb),
    'overdue_7plus', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', bi.id, 'title', bi.title, 'status', bi.status,
        'due_date', bi.due_date, 'board_name', pb.board_name,
        'initiative_title', i.title,
        'days_overdue', CURRENT_DATE - bi.due_date
      ) ORDER BY bi.due_date ASC)
      FROM public.board_items bi
      LEFT JOIN public.project_boards pb ON pb.id = bi.board_id
      LEFT JOIN public.initiatives i ON i.id = pb.initiative_id
      WHERE bi.assignee_id = p_member_id
        AND bi.status NOT IN ('done','archived')
        AND bi.due_date < CURRENT_DATE - INTERVAL '7 days'
    ), '[]'::jsonb)
  ) INTO v_result;

  RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_weekly_card_digest(uuid) TO authenticated, service_role;

-- 3. Orchestrator do cron
CREATE OR REPLACE FUNCTION public.generate_weekly_card_digest_cron()
RETURNS TABLE(member_id uuid, notified boolean, reason text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public', 'pg_temp'
AS $$
DECLARE
  v_m record;
  v_digest jsonb;
  v_has_content boolean;
BEGIN
  FOR v_m IN
    SELECT id FROM public.members
    WHERE is_active = true AND notify_weekly_digest = true
  LOOP
    v_digest := public.get_weekly_card_digest(v_m.id);
    v_has_content :=
      jsonb_array_length(v_digest->'this_week_pending') > 0
      OR jsonb_array_length(v_digest->'next_week_due') > 0
      OR jsonb_array_length(v_digest->'overdue_7plus') > 0;

    IF v_has_content THEN
      INSERT INTO public.notifications (recipient_id, type, title, body, metadata, is_read)
      VALUES (
        v_m.id,
        'weekly_card_digest_member',
        'Seu resumo semanal de tarefas',
        NULL,
        v_digest || jsonb_build_object('template_key', 'weekly_card_digest_member'),
        false
      );
      member_id := v_m.id; notified := true; reason := 'sent';
    ELSE
      member_id := v_m.id; notified := false; reason := 'no_pending_cards_skip';
    END IF;
    RETURN NEXT;
  END LOOP;
END;
$$;

GRANT EXECUTE ON FUNCTION public.generate_weekly_card_digest_cron() TO service_role;

-- 4. Cron entry
SELECT cron.schedule(
  'weekly-card-digest-saturday',
  '0 12 * * 6',  -- Sábado 12:00 UTC = 09:00 BRT = 06:00 PST = 08:00 ET
  $$SELECT public.generate_weekly_card_digest_cron()$$
);
```

### Edge Function — template

Em `send-notification-email/index.ts`, novo handler para `type='weekly_card_digest_member'`:

```ts
if (notification.type === 'weekly_card_digest_member') {
  const d = notification.metadata; // get_weekly_card_digest result
  const html = renderWeeklyDigest({
    member_name,
    thisWeekPending: d.this_week_pending,  // amarelo
    nextWeekDue: d.next_week_due,           // neutro
    overdue7plus: d.overdue_7plus,          // laranja, CTA renegociar
    boardsBaseUrl: 'https://nucleoia.vitormr.dev/boards',
    optOutUrl: 'https://nucleoia.vitormr.dev/settings/notifications',
  });
  return {
    subject: `[Núcleo IA] Resumo semanal — ${thisWeek.length} pending, ${nextWeek.length} próxima`,
    html
  };
}
```

### UI opt-out

Em `/settings/notifications` (criar se não existir ainda):
- Toggle "Receber digest semanal de cards (sábado 09h)" → `UPDATE members SET notify_weekly_digest = $1 WHERE id = auth_member()`
- Pre-visualização do que o digest inclui

### Testes (contract)

- `tests/contracts/weekly-card-digest.test.mjs`:
  1. Member com 0 cards → `generate_weekly_card_digest_cron()` retorna `reason='no_pending_cards_skip'`, 0 rows em notifications
  2. Member com 2 pending + 1 próxima → 1 row em notifications com `type='weekly_card_digest_member'`; metadata tem as 3 arrays preenchidas
  3. Member `notify_weekly_digest=false` → skip, reason não retorna row (WHERE filtra antes)
  4. Member `is_active=false` → skip
  5. Privacy: `get_weekly_card_digest(other_member_id)` chamado por non-service_role → deve rejeitar (se adicionarmos check de ownership no V2)

## V2 — Leader digest (sprint seguinte)

RPC `get_weekly_tribe_digest(p_initiative_id uuid)`:
- Aggregate only: `members_with_overdue`, `cards_due_next_week`, `cards_without_assignee`, `cards_without_due_date`, `tribe_health_pct = 100 * (cards with baseline_date / total)`
- **NÃO retorna cards individuais** (privacy-preserving)

Orchestrator estendido: para cada initiative ativa com leader assignment (via `engagements.role ∈ ['leader','coordinator','owner']`), gerar digest e notificar leader.

## V3 — Smart + configurável (futuro)

- Cadência configurável por member (weekly / biweekly / monthly) — nova coluna `notify_digest_cadence text`
- Channel preference: email / in-app / WhatsApp integration (depende de #88 ecosystem decision)
- Respect timezone do member se `members.timezone` for populado

## Rollout

1. Migration aditiva (column + 2 RPCs + cron entry) — DOWN migration trivial (DROP FUNCTION, DROP COLUMN, cron.unschedule)
2. EF deploy com novo template
3. Primeira execução sábado seguinte ao deploy em horário fixo; monitorar:
   - `notifications` rows created count
   - EF success rate (`admin_audit_log` / logs)
   - Bounce rate (via Resend/Postmark dashboards, se houver)
4. Se volume > 200 members/sábado, medir latência RPC (deve ficar < 2s total)

## Riscos

- **Email fatigue** — mitigação: skip se 0 content; opt-out coluna; V3 cadência ajustável
- **Leader overreach** — mitigação V2: aggregate only, nunca lista cards individuais
- **Timezone wrong para alguns members** — aceite: 09h BRT é razoável para LATAM concentrado; V3 respeitará timezone

## Cross-ref
- Issue #98 (este spec materializa a oportunidade)
- Issue #82 advisor — `idx_notif_recipient_unread` (198k scans) é hot path; digest vai usar massivamente; monitorar após rollout
- Issue #89 — `baseline_date` + `forecast_date` já existem em board_items; input natural para health score V2
- Issue #91 — notification cascade pós-offboarding pode usar mesma infra
- SPEC_ENGAGEMENT_WELCOME_EMAIL.md (paralelo) — mesmo pipeline `notifications → EF`, surface disjunta

## Estimativa

- Migration (column + 2 RPCs + cron): 2h
- EF template MVP: 1.5h
- UI opt-out (toggle simples): 1h
- Testes contract + smoke: 1.5h
- **Total MVP: 4-6h** · V2 leader digest: +3-4h · V3: backlog
