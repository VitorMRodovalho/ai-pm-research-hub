-- ADR-0022 W1 — harden _delivery_mode_for with explicit search_path.
--
-- Closes Supabase advisor lint 0011_function_search_path_mutable WARN
-- introduced when 20260513070000_adr0022_w1_producer_updates added the
-- helper without SET search_path. The function body is a pure SQL CASE
-- on a text parameter and resolves no schema identifiers, so the
-- most-restrictive empty search_path is safe and matches the linter
-- recommendation.
--
-- Surrounding SECDEF functions in the same p48 batch already pin
-- search_path to 'public' or 'public,pg_temp'; this is the one straggler.

ALTER FUNCTION public._delivery_mode_for(text) SET search_path = '';
