-- Wave 1 (PM 2026-08-21, direcao A): ativar o degrau Vice-GP.
--
-- Antes: o CASE mapeava volunteer/co_gp -> 'manager', tornando GP e co-GP
-- indistinguiveis em toda tela movida por operational_role, e deixando o tier
-- 'deputy_manager' INALCANCAVEL (0 pessoas, sempre) apesar de ter lista propria
-- de 21 permissoes em permissions.ts, rank proprio (2.5) em useBoardPermissions
-- e rotulo proprio nos 3 dicionarios.
--
-- Depois: co_gp e deputy_manager compartilham o degrau 'deputy_manager'.
-- Medido antes de aplicar: 1 pessoa afetada, is_superadmin=true, portanto
-- hasPermission() curto-circuita e nenhuma permissao efetiva muda hoje. O efeito
-- real e estrutural (GP vira distinguivel de co-GP) e vale para co-GPs futuros
-- que nao sejam superadmin.
--
-- Medicao antes/depois (ambas ao vivo, 2026-08-21):
--   antes: operational_role manager=2, deputy_manager=0, colapsados=1
--   depois: operational_role manager=1, deputy_manager=1, colapsados=0
--
-- NAO altera engagement_kind_permissions: volunteer/co_gp mantem os 19 combos em
-- escopo organization. A matriz cliente fica mais estreita que a autoridade
-- servidor, que e a direcao fail-closed.

CREATE OR REPLACE FUNCTION public.sync_operational_role_cache()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_member_id uuid;
  v_new_role text;
BEGIN
  SELECT id INTO v_member_id FROM public.members WHERE person_id = COALESCE(NEW.person_id, OLD.person_id);
  IF v_member_id IS NULL THEN RETURN COALESCE(NEW, OLD); END IF;

  SELECT CASE
      WHEN bool_or(ae.kind = 'volunteer' AND ae.role = 'manager')        THEN 'manager'
      -- Wave 1 (2026-08-21): co_gp deixa de colapsar em 'manager'. GP e co-GP
      -- passam a ser distinguiveis, e o tier 2.5 ja desenhado passa a existir.
      WHEN bool_or(ae.kind = 'volunteer' AND ae.role IN ('co_gp','deputy_manager')) THEN 'deputy_manager'
      WHEN bool_or(ae.kind = 'volunteer' AND ae.role IN ('leader','comms_leader')) THEN 'tribe_leader'
      -- Wave 1 fix: sponsor outranks researcher (committee/workgroup) so a sponsor who also sits on a
      -- committee (e.g. the governance committee) shows as a sponsor, not a researcher.
      WHEN bool_or(ae.kind = 'sponsor') THEN 'sponsor'
      -- Wave 2 WS-1 (PM 2026-06-28 'governança vence'): chapter_board (chapter director) outranks
      -- researcher/observer so a chapter director who also sits on a committee or observes a
      -- tribe still shows as 'Ponto Focal do Capítulo' (chapter_liaison). Stays BELOW sponsor
      -- and operational leaders (manager/deputy/tribe_leader) — those who lead operationally keep that role.
      WHEN bool_or(ae.kind = 'chapter_board') THEN 'chapter_liaison'
      WHEN bool_or(
        (ae.kind = 'volunteer' AND ae.role IN ('researcher','facilitator','communicator','curator'))
        OR (ae.kind IN ('committee_member','workgroup_member','study_group_owner')
            AND ae.role IN ('leader','co_leader','owner','coordinator','researcher','contributor','member','participant'))
        OR (ae.kind IN ('committee_coordinator','workgroup_coordinator')
            AND ae.role IN ('leader','co_leader','owner','coordinator'))
      ) THEN 'researcher'
      WHEN bool_or(ae.kind = 'external_signer') THEN 'external_signer'
      WHEN bool_or(ae.kind = 'institutional_auditor') THEN 'institutional_auditor'
      WHEN bool_or(ae.kind = 'observer') THEN 'observer'
      WHEN bool_or(ae.kind = 'alumni') THEN 'alumni'
      WHEN bool_or(ae.kind = 'candidate') THEN 'candidate'
      ELSE 'guest'
    END INTO v_new_role
  FROM public.auth_engagements ae
  WHERE ae.person_id = COALESCE(NEW.person_id, OLD.person_id) AND ae.is_authoritative = true;

  UPDATE public.members SET operational_role = COALESCE(v_new_role, 'guest'), updated_at = now()
    WHERE id = v_member_id AND operational_role IS DISTINCT FROM COALESCE(v_new_role, 'guest');

  RETURN COALESCE(NEW, OLD);
END;
$function$;

-- Backfill ALVEJADO: so quem esta cacheado como 'manager' por causa do colapso
-- do co_gp. Nao recalcula a base inteira de proposito -- um recalculo geral
-- mudaria papeis por motivos alheios a esta migration e esconderia o efeito.
UPDATE public.members m
   SET operational_role = 'deputy_manager', updated_at = now()
 WHERE m.operational_role = 'manager'
   AND EXISTS (SELECT 1 FROM public.auth_engagements ae
                WHERE ae.person_id = m.person_id AND ae.is_authoritative
                  AND ae.kind = 'volunteer' AND ae.role = 'co_gp')
   AND NOT EXISTS (SELECT 1 FROM public.auth_engagements ae
                    WHERE ae.person_id = m.person_id AND ae.is_authoritative
                      AND ae.kind = 'volunteer' AND ae.role = 'manager');
