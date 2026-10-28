-- #2806, correção do gatilho de expurgo das inscrições de push.
--
-- O gatilho da migration 20261028144246 era AFTER UPDATE OF anonymized_at, is_active. Gatilho com lista de
-- colunas só dispara quando uma delas está no SET do UPDATE, e a documentação do Postgres diz que as mudanças
-- feitas por gatilhos BEFORE UPDATE não contam. Em members, is_active é derivado de member_status pelo gatilho
-- BEFORE trg_sync_member_status_consistency ('observer', 'alumni' e 'inactive' levam is_active a false). Então
-- um UPDATE que mudava só member_status desativava o membro e deixava as inscrições dele: medido no banco, numa
-- transação desfeita, com 1 inscrição restando.
--
-- Sem a lista de colunas, o WHEN de um gatilho AFTER é avaliado logo depois da gravação da linha e lê o valor
-- final, inclusive o que os gatilhos BEFORE mudaram. O WHEN continua o mesmo, então a função só roda na
-- transição para anonimizado ou para inativo.
DROP TRIGGER IF EXISTS trg_push_subscriptions_purge ON public.members;
CREATE TRIGGER trg_push_subscriptions_purge
  AFTER UPDATE ON public.members
  FOR EACH ROW
  WHEN ((OLD.anonymized_at IS NULL AND NEW.anonymized_at IS NOT NULL)
     OR (OLD.is_active IS TRUE AND NEW.is_active IS NOT TRUE))
  EXECUTE FUNCTION public._push_subscriptions_purge();
