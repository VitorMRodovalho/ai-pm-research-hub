# Brief de arranque — Re-triagem do backlog (próxima frente pós-arco de auditoria)

> **Contexto:** o arco de auditoria pontuação/mérito (Ondas 1-5, umbrella #1465) fechou e deployou em 2026-07-23.
> Não há mais frente aberta com prioridade urgente conhecida. Esta sessão NÃO executa uma feature específica: ela
> **re-prioriza o backlog ao vivo** e apresenta ao owner a próxima frente. Modelo Opus 4.8; `/effort` normal para a
> triagem, `xhigh` só se cair numa decisão dura. **Trazer opções + recomendação + porquê; auditar ao vivo antes de recomendar.**

---

## ESTADO AO FECHAR O ARCO (2026-07-23) — NÃO recitar, re-aterrar

- **Arco 1-5 COMPLETO + MERGEADO + DEPLOYADO.** Detalhe vivo → memória `project-scoring-merit-audit-2026-07-21`.
  main na 5b `2046820a`; migration head `20260805000483`; worker `f8745f1b`; EF nucleo-mcp v2.80.0.
- **NÃO há item `high`/`P1` "pegando fogo"** conhecido: os 2 highs históricos já resolvidos (#1004 fechado; #1008
  postura conservadora ratificada). Abertas ~137 (re-contar ao vivo). **Por isso a 1ª ação é triagem, não código.**

### Resíduo do arco (3 follow-ups, BAIXA materialidade — NÃO justificam sessão própria)
- **#1478** (o único "real"): `get_member_cycle_xp.cycle_points` sem upper-bound/org vs total do ledger auditável.
  Risco: um membro ver `cycle_points` no ranking ≠ total do ledger. **Recomendação: dobrar numa futura sessão de
  gamificação** (mesma superfície da Onda 3/5a), ~30min de checagem ao vivo antes. Não standalone.
- **#1470** (baixa): digests de janela-móvel (`xp_delta`) ainda por `created_at` — decisão de produto, não bug.
- **#1468** (baixa): `recompute_application_status` corte próprio cross-role — não-cron, `in_cutoff=0` hoje.
> Deixar #1470/#1468 como backlog frio; reabrir só se a métrica mudar.

---

## MANDATO DA SESSÃO

1. **Re-aterrar ao vivo (ANTES de recomendar qualquer coisa):**
   - `gh issue list --state open --limit 300 --json number,title,labels,createdAt` — contagem real + varrer títulos.
   - Checar labels de prioridade REAIS (nesta sessão `--label high` veio vazio; confirmar se o label existe:
     `gh label list | grep -iE 'high|prio|urgent|p1'`). Não assumir esquema de labels.
   - Confirmar os 3 follow-ups ainda abertos (#1478/#1470/#1468).
   - **Se existir** `docs/planning/2026-07-20_backlog_triage_waves.md` (a memória o cita, mas ele NÃO estava presente
     em 07-23 — provável scratch de outra sessão), usar como ponto de partida; **senão, re-triar do zero**.
2. **Agrupar as abertas em ondas/temas** (ex.: gamificação, seleção/VEP, MCP/infra, comms, LGPD, higiene). Marcar
   materialidade (alta/média/baixa) e dependências. Output = tabela curta de candidatos a próxima frente.
3. **Convocação de conselho só se a próxima frente for decisão estratégica** (1 agente do domínio; NUNCA o conselho
   inteiro por default — routing discipline do CLAUDE.md). Triagem em si não precisa de agente.
4. **Apresentar ao owner** (`AskUserQuestion`) 2-4 frentes candidatas com recomendação + porquê. Números nas opções
   DEVEM vir de query desta sessão (grounding MANDATÓRIO do CLAUDE.md). NÃO iniciar código antes da escolha.
5. **Só depois da escolha:** abrir a frente escolhida (pode virar seu próprio brief/ondas, apply→merge serial).

---

## REGRAS DA CASA (herdadas)
- Números em prompt/PR/commit/memória = de tool result DESTA sessão; nunca recitar de memória/handoff.
- Merge à main = sessão main. Sem em-dash em entregáveis. Trailer `Assisted-By: Claude (Anthropic)`, nunca `Co-Authored-By`.
- DDL só via `apply_migration` (byte-fiel; phantom por nome/statement; `migration repair`; `NOTIFY pgrst`).
- Teste novo nas 2 whitelists do `package.json`. `npx astro build` + `npm test` (com `SUPABASE_URL`+`SERVICE_ROLE_KEY`).
- Flake conhecido: `p599-600-initiative-roster-parity` fica vermelho na suíte cheia com `roster=null` universal
  (transitório da prod compartilhada) mas **verde isolado** — re-rodar isolado antes de tratar como regressão. Idem
  classe de rounding Postgres-vs-JS em taxas (%). NÃO bypassar por causa deles.
