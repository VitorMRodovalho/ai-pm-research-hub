-- ADR-0012: documentar dívida das 4 cache columns sem sync trigger em members.
-- Data-architect tier 3 audit p28 flaggou como violação estrutural — Wellington pattern
-- drift risk (manual UPDATE via service_role sem trigger diverge da source).
-- Esta migration NÃO cria triggers (domain decision dedicada necessária por column);
-- documenta origem + status "DEBT" explicitamente via COMMENT ON COLUMN.

COMMENT ON COLUMN public.members.current_cycle_active IS
  '[CACHE — UNSYNCED DEBT ADR-0012] Indica se membro está ativo no ciclo corrente. Source: selection_cycles.status=''active'' + member_cycle_enrollments OR selection_applications. Drift risk: manual UPDATE sem trigger diverge de realidade. Fix pendente: AFTER trigger em selection_cycles + member_cycle_enrollments. Registrado no issue log p35.';

COMMENT ON COLUMN public.members.cpmai_certified IS
  '[CACHE — UNSYNCED DEBT ADR-0012] Indica se membro tem certificado CPMAI ativo. Source: certificates WHERE type IN (''cpmai_practitioner'',''cpmai_certified'') AND status=''issued'' AND member_id=members.id. Drift risk: cert emitido mas flag não atualizada. Fix pendente: AFTER INSERT/UPDATE trigger em certificates. Registrado no issue log p35.';

COMMENT ON COLUMN public.members.credly_badges IS
  '[CACHE — EXTERNAL SYNC ADR-0012] Array de badges Credly do membro. Source: Credly API (external). Sync manual via admin UI ou futuro cron. Drift risk: badge adicionado no Credly mas não refletido na plataforma até sync. Fix pendente: cron diário + webhook Credly. Não-trigger-able (source externo). Registrado no issue log p35.';

COMMENT ON COLUMN public.members.cycles IS
  '[CACHE — UNSYNCED DEBT ADR-0012] Array histórico de ciclos que membro participou. Source: selection_applications + member_cycle_enrollments. Drift risk: cycle add mas flag antigo. Fix pendente: AFTER INSERT trigger em enrollment tables. Registrado no issue log p35.';

NOTIFY pgrst, 'reload schema';
