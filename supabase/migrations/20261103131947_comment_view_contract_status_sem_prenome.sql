-- Comentario da view v_nucleo_contract_status: referencia nominal substituida por rotulo opaco.
-- Sem versao nem schema_migrations manual: aplicar com apply_migration.

COMMENT ON VIEW public.v_nucleo_contract_status IS $c$#1316 Per-app Nucleo contract status, person-scoped by pmi_id. Feeds #1284 baixa detection (desligado = person whose latest app is ended). superseded protects promotions (member A researcher->leader) from being read as dismissals.$c$;