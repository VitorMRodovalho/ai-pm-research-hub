-- #2732: members mantém a ponte com persons (o nome do perfil e o vínculo de volta).
--
-- members e persons guardam a mesma identidade (ADR-0006), ligadas por members.person_id e
-- persons.legacy_member_id. Nada mantinha essa ponte:
--   - persons.name nasce do nome da candidatura no VEP (approve_selection_application) e não acompanha
--     o perfil: a edição pela gestão (admin_update_member) grava só em members. 9 membros divergiam.
--   - 7 membros ativos tinham persons.legacy_member_id vazio, e toda função que descobre a pessoa do
--     chamador por legacy_member_id não os achava.
--
-- Decisão do GP (18/10/2026): o nome do PERFIL (members.name, o nome completo que a pessoa preenche
-- antes de assinar o Termo, e que vai para o Termo assinado) é a fonte; persons segue members.
--
-- Efeito colateral bom para a #2729: anonimizar o nome em members passa a anonimizar o nome em persons.
--
-- ROLLBACK: DROP TRIGGER trg_sync_person_bridge_from_member ON public.members;
--           DROP FUNCTION public._trg_sync_person_bridge_from_member();
--           (o acerto de dados não se desfaz sozinho: os valores anteriores de persons.name eram o nome da
--           candidatura no VEP, que continua em selection_applications.applicant_name.)

CREATE OR REPLACE FUNCTION public._trg_sync_person_bridge_from_member()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
BEGIN
  IF NEW.person_id IS NULL THEN
    RETURN NULL;
  END IF;

  -- O nome do perfil é a fonte (decisão do GP, 18/10/2026): persons segue members.
  IF NEW.name IS NOT NULL THEN
    UPDATE public.persons p
       SET name = NEW.name,
           updated_at = now()
     WHERE p.id = NEW.person_id
       AND p.name IS DISTINCT FROM NEW.name;
  END IF;

  -- O vínculo de volta, só quando está vazio, e nunca roubando um vínculo que já aponta para este
  -- membro a partir de outra pessoa (persons.legacy_member_id é único).
  UPDATE public.persons p
     SET legacy_member_id = NEW.id,
         updated_at = now()
   WHERE p.id = NEW.person_id
     AND p.legacy_member_id IS NULL
     AND NOT EXISTS (SELECT 1 FROM public.persons p2 WHERE p2.legacy_member_id = NEW.id);

  RETURN NULL;
END;
$function$;

REVOKE ALL ON FUNCTION public._trg_sync_person_bridge_from_member() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_sync_person_bridge_from_member ON public.members;
CREATE TRIGGER trg_sync_person_bridge_from_member
  AFTER INSERT OR UPDATE OF name, person_id ON public.members
  FOR EACH ROW EXECUTE FUNCTION public._trg_sync_person_bridge_from_member();

-- Acerto dos dados (medido antes do apply: 9 nomes divergentes, 7 vínculos de volta vazios).
UPDATE public.persons p
   SET name = m.name,
       updated_at = now()
  FROM public.members m
 WHERE m.person_id = p.id
   AND m.name IS NOT NULL
   AND p.name IS DISTINCT FROM m.name;

UPDATE public.persons p
   SET legacy_member_id = m.id,
       updated_at = now()
  FROM public.members m
 WHERE m.person_id = p.id
   AND p.legacy_member_id IS NULL
   AND NOT EXISTS (SELECT 1 FROM public.persons p2 WHERE p2.legacy_member_id = m.id);

-- Pós-condição: a migration inteira volta atrás se sobrar divergência.
DO $$
DECLARE
  v_nomes int;
  v_vinculos int;
BEGIN
  SELECT count(*) INTO v_nomes
    FROM public.members m JOIN public.persons p ON p.id = m.person_id
   WHERE m.name IS DISTINCT FROM p.name;
  SELECT count(*) INTO v_vinculos
    FROM public.members m JOIN public.persons p ON p.id = m.person_id
   WHERE p.legacy_member_id IS DISTINCT FROM m.id;
  IF v_nomes > 0 OR v_vinculos > 0 THEN
    RAISE EXCEPTION '#2732 pós-condição: % nome(s) divergente(s), % vínculo(s) de volta inconsistente(s)', v_nomes, v_vinculos;
  END IF;
END $$;
