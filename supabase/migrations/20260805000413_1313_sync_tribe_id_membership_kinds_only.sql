-- #1313 fix(bridge): _sync_tribe_id_from_engagement — SET assimétrico vs CLEAR
--
-- Assimetria: o ramo de ATIVAÇÃO setava members.tribe_id para QUALQUER kind de
-- engagement ativa numa research_tribe (inclusive observer/speaker), mas o guard
-- de DEMOÇÃO só reconhece kind='volunteer' para reter o tribe_id. Resultado: um
-- observer/curador populava members.tribe_id ("membro da tribo") enquanto o roster
-- (corretamente) não o lista — drift dual-write semântico.
--
-- Em research_tribe TODA membresia é kind='volunteer' (líder é role='leader' dentro
-- de volunteer; ver auditoria ao vivo). Fix: o ramo de ativação só popula tribe_id
-- quando NEW.kind='volunteer', espelhando exatamente o predicado do guard de demoção.
--
-- Base: corpo VIVO (pg_get_functiondef), não a migration original (evita drift).
CREATE OR REPLACE FUNCTION public._sync_tribe_id_from_engagement()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_legacy_tribe_id integer;
  v_member_id uuid;
BEGIN
  SELECT i.legacy_tribe_id INTO v_legacy_tribe_id
  FROM public.initiatives i
  WHERE i.id = NEW.initiative_id AND i.kind = 'research_tribe';

  IF v_legacy_tribe_id IS NULL THEN
    RETURN NULL;
  END IF;

  SELECT m.id INTO v_member_id
  FROM public.members m
  WHERE m.person_id = NEW.person_id;

  IF v_member_id IS NULL THEN
    RETURN NULL;
  END IF;

  -- SET simétrico ao CLEAR: só membresia de tribo (kind='volunteer') popula tribe_id.
  -- observer/speaker/etc. NÃO são membros de tribo e não devem setar o cache.
  IF NEW.status = 'active' AND NEW.kind = 'volunteer' THEN
    UPDATE public.members
       SET tribe_id = v_legacy_tribe_id
     WHERE id = v_member_id
       AND tribe_id IS DISTINCT FROM v_legacy_tribe_id;
    RETURN NULL;
  END IF;

  IF TG_OP = 'UPDATE' AND OLD.status = 'active' AND NEW.status <> 'active' THEN
    IF NOT EXISTS (
      SELECT 1
      FROM public.engagements e2
      JOIN public.initiatives i2 ON i2.id = e2.initiative_id AND i2.kind = 'research_tribe'
      WHERE e2.person_id = NEW.person_id
        AND e2.kind = 'volunteer'
        AND e2.status = 'active'
        AND e2.id <> NEW.id
    ) THEN
      UPDATE public.members m
         SET tribe_id = NULL,
             initiative_id = CASE
               WHEN m.initiative_id IN (SELECT id FROM public.initiatives WHERE kind = 'research_tribe')
                 THEN NULL
               ELSE m.initiative_id
             END
       WHERE m.id = v_member_id
         AND (
           m.tribe_id IS NOT NULL
           OR m.initiative_id IN (SELECT id FROM public.initiatives WHERE kind = 'research_tribe')
         );
    END IF;
  END IF;

  RETURN NULL;
END; $function$
;
