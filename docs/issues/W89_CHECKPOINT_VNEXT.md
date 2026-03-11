# W89: Checkpoint de Roadmap vNext — Issue template

Use o conteúdo abaixo para criar uma issue no GitHub via `gh issue create` ou manualmente.

---

## Título
`[W89] Checkpoint v2: Estabilidade e prontidão para Growth`

## Corpo

### Contexto
Encerramento da onda W85–W89 (Operações, Legado, Qualidade). Passagem da faixa declarando que a **V2 está pronta para escala** e recebimento de novos usuários (Growth).

### Entregas consolidadas (W85–W89)
- **W85:** Dashboard Comms (Cockpit Tribo 8) — RPC `get_comms_dashboard_metrics`, Recharts, macro cards + gráficos
- **W86:** Data Sanity do Legado — migration `legacy_data_sanity`, `legacy_board_url`, padronização `cycle_code`
- **W87:** E2E User Lifecycle — spec Playwright para fluxo líder de tribo
- **W88:** Docs atualizados — MIGRATION, RELEASE_LOG, PERMISSIONS_MATRIX

### Estado de estabilidade
- [ ] `npm test` passando
- [ ] `npm run build` passando
- [ ] `supabase db push` aplicado
- [ ] `npm run test:e2e:lifecycle` passando
- [ ] `npm run test:visual:dark` passando
- [ ] Smoke routes OK

### Próximos passos (vNext / Growth)
- [ ] Escala de usuários (onboarding em lote)
- [ ] Novos chapters/parceiros
- [ ] Webinars MVP (conforme discovery)
- [ ] Analytics avançados

### Labels sugeridas
`checkpoint`, `governance`, `wave-89`

---

**Comando para criar via gh cli:**
```bash
gh issue create \
  --title "[W89] Checkpoint v2: Estabilidade e prontidão para Growth" \
  --body-file docs/issues/W89_CHECKPOINT_VNEXT.md \
  --label "checkpoint,governance"
```
