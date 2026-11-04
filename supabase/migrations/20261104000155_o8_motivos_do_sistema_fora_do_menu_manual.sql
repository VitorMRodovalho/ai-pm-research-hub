-- O8 (Refs #2111): os motivos que so o sistema grava saem do menu manual de desligamento.
--
-- POR QUE: o menu de motivo do modal "Gerenciar Status" em /admin/members le offboard_reason_categories (#2966) e
-- oferece todo codigo ativo, inclusive reacceptance_refusal e reacceptance_lapse, que pertencem ao fluxo de re-aceite
-- do Termo (#976). Decisao do GP (03/11/2026): marcar isso no catalogo, e nao numa lista fixa na tela.
--
-- O QUE MUDA:
--   - coluna nova is_system_only boolean NOT NULL DEFAULT false;
--   - true so para reacceptance_refusal e reacceptance_lapse; o bloco abaixo confere que foram exatamente 2 linhas e,
--     se nao, desfaz o apply inteiro.
--
-- O QUE NAO MUDA: nenhum codigo e desativado e nenhuma funcao muda. A RPC admin_offboard_member continua aceitando os
-- dois codigos: a tela de conciliacao do VEP a chama com reacceptance_refusal. Os leitores do catalogo nas migrations
-- leem por codigo ou por colunas nomeadas, e o unico SELECT * grava num record. A coluna herda os grants da tabela,
-- que nao tem grant por coluna nas migrations.
--
-- ROLLBACK: ALTER TABLE public.offboard_reason_categories DROP COLUMN is_system_only; e reverter o filtro da tela. Com
-- a coluna fora e o filtro dentro, o menu nao carrega e diz isso no modal.

ALTER TABLE public.offboard_reason_categories
  ADD COLUMN is_system_only boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN public.offboard_reason_categories.is_system_only IS
  'O8 (Refs #2111): codigo gravado so por fluxo do sistema (re-aceite do Termo, #976). O menu manual de desligamento em /admin/members nao o oferece. Nao restringe a RPC.';

DO $$
DECLARE
  v_n integer;
BEGIN
  UPDATE public.offboard_reason_categories
     SET is_system_only = true
   WHERE code IN ('reacceptance_refusal', 'reacceptance_lapse');
  GET DIAGNOSTICS v_n = ROW_COUNT;
  IF v_n <> 2 THEN
    RAISE EXCEPTION 'O8: expected the 2 re-acceptance codes in offboard_reason_categories, updated %', v_n;
  END IF;
END $$;

NOTIFY pgrst, 'reload schema';
