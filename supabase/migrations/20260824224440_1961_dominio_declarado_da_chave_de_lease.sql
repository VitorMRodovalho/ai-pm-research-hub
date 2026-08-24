-- #1822 sobre a tabela do #1961 — dominio declarado da chave de lease.
--
-- NAO e formalidade para satisfazer ratchet. Sem dominio, um `SOURCE` com typo no
-- `scripts/with-db-lease.mjs` adquiriria um lease que ninguem disputa e o wrapper
-- reportaria "lease adquirido" enquanto serializa NADA — o modo de falha exato que
-- esta issue existe para eliminar, agora escondido dentro da propria defesa.
--
-- Dois valores de proposito: a rodada real e a sonda do contract test, que precisa de
-- chave PROPRIA para nao soltar o lease da rodada que a hospeda.
--
-- DROP + ADD com nome explicito: `ADD CONSTRAINT` com nome auto-gerado e engolido pelo
-- handler de `duplicate_object`, e a troca de dominio morre calada.

ALTER TABLE public.test_suite_leases DROP CONSTRAINT IF EXISTS test_suite_leases_source_dominio;
ALTER TABLE public.test_suite_leases
  ADD CONSTRAINT test_suite_leases_source_dominio
  CHECK (source = ANY (ARRAY['test_suite_db_aware'::text, 'probe_1961_contract'::text]));

COMMENT ON CONSTRAINT test_suite_leases_source_dominio ON public.test_suite_leases IS
  'Dominio fechado da chave de lease (#1822). Nao e formalidade: sem dominio declarado, um SOURCE com typo no wrapper adquiriria um lease que ninguem disputa e reportaria sucesso serializando NADA. Dois valores de proposito - a rodada real e a sonda do contract test, que precisa de chave propria para nao soltar o lease da rodada que a hospeda.';
