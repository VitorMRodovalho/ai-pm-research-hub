# Runbook: importar candidaturas do PMI VEP

> Atualizado 2026-07-08 (#1175 Wave 4). Cobre o fluxo completo: extracao no browser
> (script Wave 4), enrichment no PMI Community, upload via admin UI, leitura dos
> contadores e troubleshooting. Sem em-dash por regra de entregaveis.

## Visao geral

```
Phase A (volunteer.pmi.org)          Phase B (community.pmi.org)         Import (admin UI)
extract_pmi_volunteer.js       ->    mesmo script, same-origin      ->   /admin -> Import VEP JSON
lista vagas + candidaturas           enrichment (perfil, filiacoes,      dry-run preview -> Apply
baixa pmi_volunteer_full_*.json      service history)                    (proxy server-side p/ worker
                                     baixa *_enriched_*.json              pmi-vep-sync /ingest)
```

- Script canonico: `cloudflare-workers/pmi-vep-sync/scripts/extract_pmi_volunteer.js`
  (copia de trabalho do PM em `~/Downloads/AA - Scripts/`). Versao minima: Wave 4
  (#1175 F7, 2026-07-08).
- Worker: `pmi-vep-sync` (rota viva: `https://pmi-vep-sync.ai-pm-research-hub.workers.dev`).
  O endpoint `/ingest` exige `x-ingest-secret`; o upload via admin UI injeta o secret
  server-side (`PMI_VEP_SYNC_URL` no Worker principal), entao o PM NUNCA precisa colar
  o secret no browser.
- Gate de vagas: o worker so processa vagas registradas em `vep_opportunities` com
  `is_active=true` E `essay_mapping` populado. Vaga desconhecida = skip
  `opportunity_not_active` (por design; decisao D1 do #1175 para a vaga 72562).

## Passo a passo

1. **Login** em `volunteer.pmi.org` (recruiter dashboard) e TAMBEM em
   `community.pmi.org` (tocar o proprio perfil para ativar o cookie SSO).
2. **Phase A**: F12 no recruiter dashboard, colar o script inteiro no console.
   - O script valida o token OIDC (aviso se expira em < 30 min).
   - Allowlist (#1175 F7): vagas fora de 64966/64967/66470 aparecem em um modal e SO
     entram na varredura se marcadas explicitamente (minimizacao LGPD). Exclusoes ficam
     registradas em `meta.excludedOpportunityIds`.
   - Enrichment cross-origin normalmente falha por CORS (esperado); o script avisa e
     segue. Resultado: `pmi_volunteer_full_<data>.json` baixado.
3. **Phase B**: abrir `community.pmi.org/profile/<usuario>`, colar o MESMO script no
   console, escolher o JSON da Phase A no file picker. Resultado:
   `pmi_volunteer_full_enriched_<data>.json` (+ CSV de service history).
4. **Import**: `/admin` -> Import VEP JSON -> escolher o arquivo **enriched** ->
   conferir o dry-run preview (insert/update/skip) -> Apply.
5. **Pos-import**: conferir o sumario (contadores abaixo) e, se necessario, o run em
   `cron_run_log` (o sumario traz `run_id`).
6. **LGPD**: apagar as copias locais dos JSONs/CSVs apos o import confirmado (nota de
   minimizacao em `meta.lgpd` do proprio arquivo).

## Lendo o sumario do import

| Contador | Significado |
|---|---|
| `applications_received/processed` | recebidas no payload / efetivamente upsertadas |
| `applications_new/updated` | novas (disparam welcome se submitted) / atualizadas |
| `applications_skipped` + erro `opportunity_not_active` | vaga fora de `vep_opportunities` ativo (por design para vagas alheias ao Nucleo) |
| `applications_cycle_redirected` | atribuidas a ciclo semanticamente correto pela data (BUG-195.B) |
| `applications_cross_cycle_refreshed` | rows de ciclos anteriores com refresh parcial (sem welcome) |
| `chapter_affiliations_upserted` | escritas em `member_chapter_affiliations` via `upsert_chapter_affiliation` (ADR-0104) |
| `service_history_inserted` | rows em `selection_application_service_history` (contrato Wave 4: `applicationId`+`roleName`) |
| `phase_b_processed/skipped_private` | apps com enrichment / perfis privados (HTTP 400, Decision 5) |
| `resumes_synced/failed/skipped_no_url` | espelho de CVs no Storage (SAS expira ~24h, por isso pre-flight) |
| `ingest_result_warning` | eco do `ingestResult` embutido no JSON da Phase A (ver troubleshooting) |

## Troubleshooting

- **Aviso "Phase A: error unauthorized" no import.** E o eco do auto-POST da Phase A
  gravado dentro do JSON (`ingestResult`), NAO o status do seu Apply (#224). Causa
  historica: secret placeholder no script pre-Wave-4. O script Wave 4 pula o POST com
  placeholder; se o aviso voltar a aparecer, o export veio de um script antigo.
- **`service_history_inserted: 0` com serviceHistory populado no JSON.** Export
  pre-Wave-4 (rows sem `applicationId`). O worker atual tem fallback por `applicantId`
  (#1175 Wave 4), entao re-upload do MESMO arquivo passa a inserir. Se continuar 0,
  confira se o arquivo subido e o `_enriched_` (a Phase A pura tem `serviceHistory: []`).
- **`opportunity_not_active` inesperado.** Vaga nova do Nucleo? Registrar em
  `vep_opportunities` (is_active=true) E popular `essay_mapping` antes de reimportar.
  Vaga que nao e do Nucleo (ex.: diretoria do capitulo): comportamento correto, nao
  importar (D1 #1175).
- **`essay_mapping_missing`.** A vaga esta ativa mas sem mapeamento de essays; popular
  `vep_opportunities.essay_mapping` (ver 64966/64967 como referencia).
- **Import inteiro falha (fetch error no admin).** O proxy usa
  `PMI_VEP_SYNC_URL` (env do Worker principal). Atencao: o fallback hardcoded
  `https://pmi-vep-sync.vitormr.dev` NAO tem DNS (aterrado 2026-07-08); se a env sumir,
  o import quebra. Conferir `wrangler.toml`/dashboard do Worker principal.
- **429 / rate limit no PMI.** Aumentar `CONFIG.DELAY_MS`/`DELAY_DETAIL_MS` no script.
- **Welcome indevido.** So candidaturas `submitted` com `statusId=2` disparam welcome
  (bug de 2026-04-29 corrigido); buckets qualified/rejected nunca disparam.

## Referencias

- ADR-0104 (SSOT de filiacoes + amendment #1175 Waves 2-4)
- `.claude/rules/database.md` (DDL via apply_migration)
- Contract test: `tests/contracts/1175-wave4-vep-ingest-unknown-opportunity-skip.test.mjs`
- Issue #1175 (auditoria filiacao x VEP x perfil; decisoes D1-D4)
- #224 (disambiguacao do ingestResult da Phase A no admin UI)
