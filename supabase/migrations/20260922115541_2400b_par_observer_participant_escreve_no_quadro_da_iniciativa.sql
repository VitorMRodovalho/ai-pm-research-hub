-- Participante EXTERNO passa a poder contribuir no quadro da iniciativa em que entrou.
--
-- O CASO DE USO CONCRETO (exigido pelo procedimento de audit, item 1).
--   A diretoria do Student Club Brasilia (que e uma INICIATIVA do capitulo PMI-DF, nao o capitulo)
--   entra no workgroup "Hackathon de Impacto Social" para contribuir. Eles NAO sao voluntarios do
--   Nucleo: nao assinaram o termo de voluntario, que e o instrumento que cobre LGPD e propriedade
--   intelectual. Medido em 21/09/2026: o termo e EXCLUSIVO do `kind='volunteer'` (117 de 124
--   vinculos com termo); os outros 13 kinds tem ZERO. Logo o vinculo deles nao pode ser
--   `kind='volunteer'`, e `kind='observer'` e o que a plataforma ja usa para "vinculo externo,
--   nao-voluntario" (ADR-0131: externo e atributo do VINCULO, nao da pessoa).
--
--   Hoje esse vinculo nao concede nada: o par `observer x participant` nao existe no seed, e a
--   pessoa entra sem conseguir escrever no quadro daquilo que veio contribuir.
--
-- POR QUE OS PATHS 2 E 3 NAO COBREM (item 2 do procedimento), com os nomes das funcoes.
--   Checklist de 4 etapas de `docs/reference/V4_AUTHORITY_MODEL.md:158`, action `write_board`,
--   rodado em 22/09/2026:
--     Etapa 1: 22 combos seedados, e NENHUM com `kind='observer'`.
--     Etapa 2: 5 RPCs usam a action. As cinco operacoes de escrita (`create_board_item`,
--              `update_board_item`, `move_board_item`, `complete_checklist_item`,
--              `create_card_comment`) passam pelo gate canonico (`_can_write_board` /
--              `board_write_authority`). O unico gate composto e `set_initiative_roadmap`, e o
--              outro ramo dele e `manage_platform`, que um externo nao tem nem deve ter.
--     Etapa 3: nenhum gate por designation cobre escrita em quadro para externo.
--     Etapa 4: nenhuma RPC com escopo inline concede escrita por fora do gate.
--   O UNICO path alternativo existente e a checagem direta `e.role IN ('leader','coordinator',
--   'manager','co_gp')`, presente em 3 das 5 operacoes de escrita. **`participant` nao esta nela.**
--   ⇒ As 4 etapas terminam sem path alternativo e o caso de uso esta bloqueado: e gap, pelo
--   criterio do proprio procedimento, e nao por analogia com o par `workgroup_member x participant`.
--
-- JUSTIFICATIVA DE PRINCIPIO POR COMBO (item 3 do procedimento).
--   O escopo e **`initiative`** e isso e a decisao de seguranca desta migration, nao um detalhe.
--   `organization` daria a um externo escrita em QUALQUER quadro da plataforma, inclusive os de
--   iniciativas confidenciais (ADR-0105). Com `initiative`, ele escreve no quadro DAQUELA
--   iniciativa e em nenhum outro, que e exatamente o alcance do convite que recebeu.
--   Comparacao ancorada: o par analogo `workgroup_member x participant` tambem e `initiative`. A
--   diferenca entre os dois pares e o kind, que carrega "externo, sem termo", e e isso que o
--   registro precisa preservar.
--
-- O QUE ESTA MIGRATION NAO FAZ.
--   Nao reclassifica nenhum vinculo existente, nao cria pessoa e nao mexe no papel `observer`.
--   Ela so abre o par. Quem hoje e `observer x observer` continua sem conceder nada, que e o
--   desenho, e os 10 vinculos com `role='observer'` seguem como estao ate a onda da ADR.
--
-- Cross-ref: #2400, ADR-0131, ADR-0105 (iniciativa confidencial), V4_AUTHORITY_MODEL.md:158.

DO $$
DECLARE
  v_org uuid;
  v_inseridas int;
BEGIN
  -- A organizacao vem do par ANALOGO, nunca de literal: se a ancora sumir, esta migration falha
  -- alto em vez de inventar um dono para a permissao.
  SELECT organization_id INTO v_org
  FROM public.engagement_kind_permissions
  WHERE kind = 'workgroup_member' AND role = 'participant' AND action = 'write_board';

  IF v_org IS NULL THEN
    RAISE EXCEPTION 'ancora ausente: o par workgroup_member x participant x write_board nao existe, '
                    'entao nao da para derivar organization_id. Investigue antes de seedar.';
  END IF;

  INSERT INTO public.engagement_kind_permissions (kind, role, action, scope, description, organization_id)
  VALUES (
    'observer', 'participant', 'write_board', 'initiative',
    'Participante EXTERNO (sem termo de voluntario) contribuindo na iniciativa em que foi convidado. '
    'Escopo initiative de proposito: organization daria escrita em qualquer quadro, inclusive de '
    'iniciativa confidencial (ADR-0105). Gap confirmado pelo checklist de 4 etapas do V4 em 22/09/2026.',
    v_org
  )
  ON CONFLICT (kind, role, action) DO NOTHING;

  GET DIAGNOSTICS v_inseridas = ROW_COUNT;
  RAISE NOTICE 'observer x participant x write_board: % linha(s) inserida(s)', v_inseridas;
END $$;
