-- ADR-0134 §1 e §10, fatia 1 (#2393): a vaga do VEP é uma entidade com dono.
--
-- `vep_opportunities` ganha organização (obrigatória, ADR-0004), iniciativa (vazia = vaga geral; aponta
-- para `initiatives`, nunca para `tribes`, ADRs 0005 e 0012) e ciclo. O recrutador NÃO é coluna: deriva
-- do vínculo de liderança na iniciativa (ADRs 0007 e 0131), e isso é a fatia 2.
--
-- Medido em 30/10/2026: 10 vagas, 1 organização, 41 iniciativas e 4 ciclos, todos com organização. A
-- mesma vaga do VEP já alimentou 3 ciclos (64967 e 64966), então `cycle_id` diz o ciclo que a vaga
-- alimenta AGORA; o histórico continua em `selection_applications.cycle_id`. A importação segue caindo
-- no ciclo aberto mais recente: esta migration não muda o roteamento.
--
-- Leitores da tabela medidos no mesmo dia: 3 funções vivas, todas SECURITY DEFINER (não sentem a RLS);
-- o worker pmi-vep-sync, por chave de serviço (não passa por RLS); a tela de admin, pelo GP.
--
-- O preenchimento de `initiative_id` e `cycle_id` NÃO está aqui: é DML separado, com o mapa decidido
-- pelo GP em 30/10/2026.

-- ── 1. Organização ──────────────────────────────────────────────────────────────────────────────────
-- Preenchida com a organização única, e a suposição "uma organização só" é conferida, não presumida:
-- com duas, a migration para em vez de escolher. Depois o default é o do chamador (ADR-0077, grupo A):
-- a tela do GP herda; um pacote por chave de serviço sem organização falha no NOT NULL em vez de gravar
-- linha órfã.

ALTER TABLE public.vep_opportunities ADD COLUMN organization_id uuid;

DO $$
BEGIN
  IF (SELECT count(*) FROM public.organizations) <> 1 THEN
    RAISE EXCEPTION 'vep_opportunities.organization_id: o preenchimento supõe UMA organização, e há %',
      (SELECT count(*) FROM public.organizations);
  END IF;
  UPDATE public.vep_opportunities SET organization_id = (SELECT o.id FROM public.organizations o);
END $$;

ALTER TABLE public.vep_opportunities
  ALTER COLUMN organization_id SET NOT NULL,
  ALTER COLUMN organization_id SET DEFAULT public.auth_org(),
  ADD CONSTRAINT vep_opportunities_organization_id_fkey
    FOREIGN KEY (organization_id) REFERENCES public.organizations (id) ON DELETE RESTRICT;

-- ── 2. Iniciativa e ciclo, sempre da MESMA organização da vaga ──────────────────────────────────────
-- FK composta: a vaga não aponta para iniciativa ou ciclo de outra organização (ADR-0134 §10). A chave
-- (id, organization_id) nas tabelas-alvo é única por construção, porque `id` já é a chave primária.
-- Coluna vazia não é conferida (MATCH SIMPLE): vaga geral e vaga sem ciclo continuam válidas.

ALTER TABLE public.initiatives
  ADD CONSTRAINT initiatives_id_organization_id_key UNIQUE (id, organization_id);
ALTER TABLE public.selection_cycles
  ADD CONSTRAINT selection_cycles_id_organization_id_key UNIQUE (id, organization_id);

ALTER TABLE public.vep_opportunities
  ADD COLUMN initiative_id uuid,
  ADD COLUMN cycle_id      uuid,
  ADD CONSTRAINT vep_opportunities_initiative_same_org_fkey
    FOREIGN KEY (initiative_id, organization_id) REFERENCES public.initiatives (id, organization_id) ON DELETE RESTRICT,
  ADD CONSTRAINT vep_opportunities_cycle_same_org_fkey
    FOREIGN KEY (cycle_id, organization_id) REFERENCES public.selection_cycles (id, organization_id) ON DELETE RESTRICT;

CREATE INDEX vep_opportunities_initiative_id_idx ON public.vep_opportunities (initiative_id) WHERE initiative_id IS NOT NULL;
CREATE INDEX vep_opportunities_cycle_id_idx      ON public.vep_opportunities (cycle_id)      WHERE cycle_id IS NOT NULL;

COMMENT ON COLUMN public.vep_opportunities.organization_id IS
  'ADR-0134 §1: organização dona da vaga (ADR-0004). Default do chamador (auth_org); pacote por chave de serviço passa explícito.';
COMMENT ON COLUMN public.vep_opportunities.initiative_id IS
  'ADR-0134 §1: iniciativa da vaga. Vazio = vaga geral. Nunca tribes (ADRs 0005 e 0012). O recrutador deriva do vínculo de liderança nesta iniciativa, não de coluna.';
COMMENT ON COLUMN public.vep_opportunities.cycle_id IS
  'ADR-0134 §1: o ciclo que a vaga alimenta agora. O histórico de cada candidatura fica em selection_applications.cycle_id.';

-- ── 3. Leitura: só a própria organização, e o portão da iniciativa confidencial ─────────────────────
-- Decisão do GP (30/10/2026): a leitura deixa de ser USING (true). Mesmo padrão das demais tabelas: as
-- policies PERMISSIVE existentes ficam, e duas RESTRICTIVE estreitam (combinam por AND, nunca alargam).
--   org_scope: ADR-0004 e ADR-0134 §10. Quem não é membro tem auth_org() nulo e lê 0 linhas.
--   confidential_visibility: ADR-0105. Vaga geral e iniciativa padrão passam; vaga de iniciativa
--   confidencial só para quem tem vínculo autoritativo nela, ou para o GP.

DROP POLICY IF EXISTS vep_opportunities_v4_org_scope ON public.vep_opportunities;
CREATE POLICY vep_opportunities_v4_org_scope ON public.vep_opportunities
  AS RESTRICTIVE FOR ALL
  USING (organization_id = public.auth_org())
  WITH CHECK (organization_id = public.auth_org());

DROP POLICY IF EXISTS vep_opportunities_confidential_visibility ON public.vep_opportunities;
CREATE POLICY vep_opportunities_confidential_visibility ON public.vep_opportunities
  AS RESTRICTIVE FOR SELECT TO public
  USING (public.rls_can_see_initiative(initiative_id));

-- ── 4. Sonda de leitura como um membro, para o guard ────────────────────────────────────────────────
-- Lê uma relação pelo motor de RLS com as claims de um membro real e devolve só a CONTAGEM. Mesmo
-- mecanismo de _audit_ghost_read_probe, com um membro no lugar do uuid sintético: é o que deixa o
-- guard exercer o portão confidencial nos dois sentidos, em vez de só ler o texto da policy.
-- Invocada pelo service_role, que já lê tudo sem RLS: não amplia poder, só mede o que o membro veria.

CREATE OR REPLACE FUNCTION public._audit_member_read_probe(p_relname text, p_member_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SET search_path = ''
AS $function$
DECLARE
  v_orig_role   text := current_user;
  v_orig_claims text := current_setting('request.jwt.claims', true);
  v_auth_id     uuid;
  v_n           bigint;
  v_err         text;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_class c
                  JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
                 WHERE n.nspname = 'public' AND c.relname = p_relname AND c.relkind IN ('r', 'p', 'v', 'm')) THEN
    RETURN jsonb_build_object('relname', p_relname, 'error', 'relation not found');
  END IF;

  SELECT m.auth_id INTO v_auth_id FROM public.members m WHERE m.id = p_member_id;
  IF v_auth_id IS NULL THEN
    RETURN jsonb_build_object('relname', p_relname, 'error', 'member without auth_id');
  END IF;

  PERFORM pg_catalog.set_config('request.jwt.claims',
    pg_catalog.json_build_object('sub', v_auth_id, 'role', 'authenticated', 'aud', 'authenticated')::text, true);
  EXECUTE 'SET LOCAL ROLE authenticated';
  BEGIN
    EXECUTE format('SELECT count(*) FROM public.%I', p_relname) INTO v_n;
  EXCEPTION WHEN OTHERS THEN
    v_err := SQLERRM;
  END;
  EXECUTE format('SET LOCAL ROLE %I', v_orig_role);
  PERFORM pg_catalog.set_config('request.jwt.claims', coalesce(v_orig_claims, ''), true);

  RETURN jsonb_build_object('relname', p_relname, 'member_rows', v_n, 'ran_as', v_orig_role, 'error', v_err);
END;
$function$;

COMMENT ON FUNCTION public._audit_member_read_probe(text, uuid) IS
  'ADR-0134 fatia 1: conta as linhas de uma relação de public que um membro real veria pela RLS (claims do auth_id dele). Só contagem; service_role apenas. Consumido por tests/contracts/2393-vaga-com-dono.';

REVOKE EXECUTE ON FUNCTION public._audit_member_read_probe(text, uuid) FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public._audit_member_read_probe(text, uuid) TO service_role;

NOTIFY pgrst, 'reload schema';
