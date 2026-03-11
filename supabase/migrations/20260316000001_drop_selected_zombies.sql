-- Operação Detox: DROP de tabelas zumbis aprovadas pelo CPO
-- Tabelas sem referência em código de produção (zero consumers).
-- change_requests MANTIDA por decisão executiva (rito processual PMI).
-- Date: 2026-03-16
-- ============================================================================

-- 1. _bak_gp_credly_sanitize_v1 — backup temporário de sanitização Credly
DROP TABLE IF EXISTS public._bak_gp_credly_sanitize_v1 CASCADE;

-- 2. comms_metrics_publish_log — tabela de auditoria sem consumidor
DROP TABLE IF EXISTS public.comms_metrics_publish_log CASCADE;

-- 3. global_links — substituída por admin_links
DROP TABLE IF EXISTS public.global_links CASCADE;

-- 4. webinars — nunca consumida; webinars geridos via events.type='webinar'
DROP TABLE IF EXISTS public.webinars CASCADE;
