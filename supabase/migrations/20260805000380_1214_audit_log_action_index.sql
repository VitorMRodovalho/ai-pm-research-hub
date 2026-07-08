-- #1214 (drive-by de CI): admin_audit_log não tinha índice em `action` — probes de contract
-- test (p240 #251) e auditorias (bypass semanal) filtram por action e seq-scaneavam 38k rows
-- (~66MB); sob carga de I/O o probe estourou o statement_timeout do PostgREST 3x (1 local,
-- 2 CI em 08/07). Índice torna o probe index-scan e imune à carga.
CREATE INDEX IF NOT EXISTS idx_audit_log_action ON public.admin_audit_log (action);
