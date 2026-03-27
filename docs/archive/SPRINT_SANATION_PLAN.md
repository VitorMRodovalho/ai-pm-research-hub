# Plano de Sanação — Colocar o Projeto nos Trilhos

**Objetivo**: Estabilizar a base (P0 Foundation) antes de avançar features. Validar o que está feito, fechar gaps operacionais e habilitar o fluxo de sprints.

---

## Estado atual (Março 2026)

- **Build e testes**: ✅ Passando (`npm test`, `npm run build`)
- **Hotfixes S-HF1..S-HF8**: ✅ Implementados (exceto HF5 execução em produção)
- **Documentação**: README, AGENTS, CONTRIBUTING, CURSOR_SETUP, runbooks, board URL — ✅ Atualizados

---

## Fase 1 — Concluir P0 Foundation (esta sprint)

### 1.1 S-HF5 — Data Patch em produção ⏳

O SQL está pronto em `docs/migrations/`. **Ação manual** em produção:

1. Abrir Supabase SQL Editor (projeto de produção)
2. Executar `docs/migrations/hf5-audit-data-patch.sql` (pré-auditoria)
3. Executar `docs/migrations/hf5-apply-data-patch.sql` (patch idempotente)
4. Executar novamente `hf5-audit-data-patch.sql` (pós-auditoria)
5. Registrar em `docs/RELEASE_LOG.md`

**Runbook detalhado**: `docs/migrations/HF5_PRODUCTION_RUNBOOK.md` (criado abaixo)

### 1.2 Segurança (Technical Debt) ✅

- **Dependabot** habilitado (`.github/dependabot.yml`) — PRs semanais de dependências
- **CodeQL** habilitado (`.github/workflows/codeql-analysis.yml`) — análise de segurança em push/PR

### 1.3 Deputy PM hierarchy

- Já implementado: `TeamSection.astro` ordena manager antes de deputy_manager; labels em profile/admin
- Considerar **validado** se ordenação e badges estão corretos em produção

---

## Fase 2 — Follow-ups operacionais (próxima sprint)

| Item | Origem | Ação |
|------|--------|------|
| sync-comms-metrics | S-COM6 | Deploy Edge Function em produção; configurar `SYNC_COMMS_METRICS_SECRET` |
| COMMS_METRICS_V2 audit | RELEASE_LOG | Rodar audit SQL após primeiro sync |
| PostHog/Looker URLs | S-PA1 | Provisionar `PUBLIC_POSTHOG_PRODUCT_DASHBOARD_URL`, `PUBLIC_LOOKER_COMMS_DASHBOARD_URL` em produção |
| S-COM6 UI | ✅ Done | Rota `/admin/comms` criada com Looker iframe ou tabela nativa |
| S-AN1 | ✅ Done | Event Delegation + escapeHtml nos banners |
| S10 | ✅ Done | Workflow `credly-auto-sync.yml` semanal |

---

## Fase 3 — Avançar sprints (após P0 estável)

1. **P1 Comms**: S-COM6 UI, S-AN1 Announcements, S10 Credly Auto Sync
2. **P2 Knowledge**: S-KNW1, S-KNW2, etc.
3. **Technical Debt contínuo**: i18n long-tail, hard drop `role`/`roles` após validação final

---

## Checklist de sanção (hoje)

- [x] Dependabot habilitado
- [x] CodeQL habilitado
- [x] HF5 runbook criado
- [ ] HF5 executado em produção (ação manual)
- [ ] Registrar HF5 em RELEASE_LOG após execução
- [ ] (Opcional) Smoke test pós-deploy: `npm run smoke:routes`
