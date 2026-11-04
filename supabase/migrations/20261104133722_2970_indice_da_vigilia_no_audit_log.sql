-- #2970: a vigília da varredura de alertas (_alert_sweep_cron, Fonte C) lê as últimas N linhas de uma action em
-- admin_audit_log. Com índices só em (action) e em (created_at) separados, o banco traz todas as linhas da action e
-- ordena para pegar N. O índice composto entrega as N primeiras direto.
SET LOCAL lock_timeout = '3s';

CREATE INDEX IF NOT EXISTS idx_audit_log_action_created
  ON public.admin_audit_log (action, created_at DESC);

ANALYZE public.admin_audit_log;
