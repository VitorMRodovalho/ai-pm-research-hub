-- #2393, ADR-0134 §6, fatia 2: leitura por vaga. Parte 1 de 2: a ação e o registro.
--
-- 1. A ação `view_opening_applications`, com escopo `initiative`, só para os pares de liderança.
--    O recrutador deriva do vínculo de liderança na iniciativa da vaga (§1). Não há semente em
--    `organization` nem em `global`: a ação não alcança vaga de outra iniciativa nem a vaga geral.
--    A etapa 0 do V4_AUTHORITY_MODEL foi lida em 01/11/2026: os 3 kinds são admissíveis nas espécies
--    de iniciativa das vagas de hoje, pelos dois lados (volunteer em research_tribe, study_group_owner
--    em study_group, committee_member em committee).
-- 2. `pii_access_log.target_application_id`: o registro passa a dizer qual candidatura foi lida.
--    Antes, o alvo era o membro achado pelo e-mail, e o candidato que ainda não é membro ficava sem
--    alvo. `ON DELETE SET NULL`: a linha do registro não prende candidatura apagada.
-- 3. `_log_application_pii_access` grava a coluna nova. Assinatura e comportamento iguais, inclusive
--    o fail-soft que os chamadores de hoje esperam; o restante do corpo é o da captura 20260516810000.
-- 4. `_log_opening_application_access`, o registro ESTRITO das leituras por vaga: sem tratador de
--    exceção, então uma falha ao gravar derruba a leitura e nada é devolvido; grava pela candidatura
--    mesmo quando ela não tem e-mail. Interna: sem EXECUTE para PUBLIC, anon e authenticated.
--
-- O que NÃO faz: não cria leitura (as RPCs vêm na parte 2) e não muda a retenção do registro.
-- A coluna nova não deve ser removida depois de acumular registros: ela é a evidência de quem leu
-- qual candidatura.

DO $$
DECLARE
  v_org uuid;
  v_inseridas int;
BEGIN
  -- A organização vem do par análogo, nunca de literal: sem a âncora, falha alto.
  SELECT organization_id INTO v_org
  FROM public.engagement_kind_permissions
  WHERE kind = 'volunteer' AND role = 'leader' AND action = 'view_pii';

  IF v_org IS NULL THEN
    RAISE EXCEPTION 'âncora ausente: volunteer x leader x view_pii não existe; não dá para derivar organization_id';
  END IF;

  INSERT INTO public.engagement_kind_permissions (kind, role, action, scope, description, organization_id)
  VALUES
    ('volunteer', 'leader', 'view_opening_applications', 'initiative',
     'Líder da tribo lê as candidaturas das vagas da própria iniciativa (ADR-0134 §6).', v_org),
    ('study_group_owner', 'owner', 'view_opening_applications', 'initiative',
     'Dono do grupo de estudos lê as candidaturas das vagas do grupo (ADR-0134 §6).', v_org),
    ('study_group_owner', 'leader', 'view_opening_applications', 'initiative',
     'Líder do grupo de estudos lê as candidaturas das vagas do grupo (ADR-0134 §6).', v_org),
    ('committee_member', 'leader', 'view_opening_applications', 'initiative',
     'Liderança do comitê lê as candidaturas das vagas do comitê (ADR-0134 §6).', v_org)
  ON CONFLICT (kind, role, action) DO NOTHING;

  GET DIAGNOSTICS v_inseridas = ROW_COUNT;
  IF v_inseridas <> 4 THEN
    RAISE EXCEPTION 'view_opening_applications: esperava 4 sementes novas, entraram %', v_inseridas;
  END IF;
END $$;

ALTER TABLE public.pii_access_log
  ADD COLUMN target_application_id uuid
    REFERENCES public.selection_applications(id) ON DELETE SET NULL;

CREATE INDEX pii_access_log_target_application_id_idx
  ON public.pii_access_log (target_application_id)
  WHERE target_application_id IS NOT NULL;

COMMENT ON COLUMN public.pii_access_log.target_application_id IS
  '#2393: a candidatura lida. Gravada por _log_application_pii_access; nula nas leituras que não são de candidatura. ON DELETE SET NULL.';

CREATE OR REPLACE FUNCTION public._log_application_pii_access(
  p_application_id uuid,
  p_accessor_id uuid,
  p_fields text[],
  p_context text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $func$
DECLARE
  v_target_member_id uuid;
  v_app_email text;
BEGIN
  SELECT email INTO v_app_email FROM public.selection_applications WHERE id = p_application_id;
  IF v_app_email IS NULL THEN RETURN; END IF;

  SELECT id INTO v_target_member_id FROM public.members
  WHERE lower(trim(email)) = lower(trim(v_app_email))
  LIMIT 1;

  -- target_member_id pode ser NULL para candidatos que ainda não viraram members
  -- (legítimo no funil pré-conversion). pii_access_log permite null.
  -- #2393: target_application_id identifica a candidatura mesmo nesse caso.
  INSERT INTO public.pii_access_log (
    accessor_id, target_member_id, target_application_id, fields_accessed, context, accessed_at
  )
  VALUES (
    p_accessor_id, v_target_member_id, p_application_id, p_fields, p_context, now()
  );
EXCEPTION WHEN OTHERS THEN
  -- Fail-soft: logging não deve bloquear leitura legítima
  RAISE NOTICE '_log_application_pii_access failed: %', SQLERRM;
END;
$func$;

CREATE OR REPLACE FUNCTION public._log_opening_application_access(
  p_application_id uuid,
  p_accessor_id uuid,
  p_fields text[],
  p_context text
)
RETURNS void
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_target_member_id uuid;
  v_app_email text;
BEGIN
  IF p_application_id IS NULL OR p_accessor_id IS NULL THEN
    RAISE EXCEPTION '_log_opening_application_access: candidatura e leitor são obrigatórios';
  END IF;

  SELECT sa.email INTO v_app_email
  FROM public.selection_applications sa
  WHERE sa.id = p_application_id;

  IF v_app_email IS NOT NULL THEN
    SELECT m.id INTO v_target_member_id
    FROM public.members m
    WHERE lower(trim(m.email)) = lower(trim(v_app_email))
    LIMIT 1;
  END IF;

  INSERT INTO public.pii_access_log (
    accessor_id, target_member_id, target_application_id, fields_accessed, context, accessed_at
  )
  VALUES (
    p_accessor_id, v_target_member_id, p_application_id, p_fields, p_context, now()
  );
END;
$function$;

REVOKE ALL ON FUNCTION public._log_opening_application_access(uuid, uuid, text[], text) FROM PUBLIC, anon, authenticated;

COMMENT ON FUNCTION public._log_opening_application_access(uuid, uuid, text[], text) IS
  '#2393: registro estrito das leituras por vaga. Sem tratador de exceção: se não gravar, a leitura não acontece. Interna, chamada pelas RPCs SECURITY DEFINER da leitura por vaga.';

NOTIFY pgrst, 'reload schema';
