# Handoff + Prompt de arranque - Onda 5 (CAPSTONE UX: transparência de pontuação auditável)

> **Diferença das ondas 1-4:** estas eram fixes de backend com mandato claro/LOCKED. **Onda 5 é uma FEATURE UX/UI
> nova, membro + candidato, materialidade MÉDIA, outward-facing** (candidato = aplicante externo). Portanto o prompt
> NÃO é LOCKED: a sessão ABRE com uma rodada de decisões do owner (escopo/UX) via `AskUserQuestion`, e só então
> desenha + constrói. Modelo: Opus 4.8 (não pinar). Effort: `/effort xhigh`.

---

## HANDOFF - estado ao fechar a Onda 4 (2026-07-22)

**Arco de auditoria pontuação/mérito: Ondas 1-4 FECHADAS + MERGEADAS.** Detalhe vivo → memória
`project-scoring-merit-audit-2026-07-21`. main = `d2fb21ec`.

- **Onda 1** (`387f20d3`, #1466): seleção A2 min_evaluators + A1 rank read-time + invariante M (mig 475/476/478).
- **Onda 2** (`5758eaa3`, #1467, #1463): corte objetivo C4 130.9→142.69 active-only retroativo + cross-role (mig 479). Follow-up #1468.
- **Onda 3** (`b5c7eaa2`, #1469, #1464): gamificação por `occurred_at` (data do fato); C4 7510→2250 pts; 10 leitores rejanelados (mig 480). Follow-up #1470.
- **Onda 4** (`d2fb21ec`, #1472, #1471, mig **481**): backend de transparência. Predicado SSOT `selection_peer_review_complete(uuid)` unifica o cegamento nas 2 RPCs do comitê (fase→min_evaluators); `get_evaluation_results` ganhou `criterion_notes` + render no consolidado admin (`selection.astro`, bloco "Justificativas por critério"); descrições MCP realinhadas; deploy frontend (`baa5cee7`) + EF `nucleo-mcp` v2.80.0. Política de cegamento IMPLEMENTADA → `reference-selection-transparency-blind-review-policy`.

**Dependências da Onda 5 (todas SATISFEITAS):** B0 `occurred_at` (Onda 3, permite ledger por data-do-fato) · A1 rank read-time + A3 corte (Ondas 1-2, número certo por trás) · `criterion_notes` no backend + render do comitê (Onda 4).

**Migration head:** `20260805000481` → próxima livre re-consultar ao vivo (provável `20260805000482`).

---

## O QUE A ONDA 5 ENTREGA (proposto no relatório `docs/audit/2026-07-21_scoring_merit_audit.md`, seção "Onda 5")

Princípio: **corrigir primeiro (feito), expor depois**. A superfície de transparência só sobe agora que os números
por trás estão corrigidos e estáveis. Duas partes (audiências e superfícies DISTINTAS):

### Parte A - Gamificação "Minha Pontuação, auditável" (membro; admin vendo qualquer membro)
- Painel com **CICLO vs VITALÍCIO** claramente separados e rotulados (o header de chips hoje mistura escopos sem rótulo).
- Breakdown por pilar **expansível até a linha de CADA fato** (evento/atividade) com **data real** (`occurred_at`), o
  **ciclo** a que pertence e os **pontos**. Responde direto ao "de onde vêm estes pontos e em qual ciclo" (o caso Jefferson).
- Rótulo explícito "certificações contam vitalício" (pilar certificações sempre conta no perfil, #1448).
- Export.
- **Fato de infra:** não existe RPC de ledger fato-a-fato hoje. Existem `get_member_xp_pillars(member, cycle_code, scope)`
  (agregado por pilar, scope ciclo/vitalício), `get_member_cycle_xp(member)`, `get_member_gamification_stats(ids[])`.
  A parte A provavelmente precisa de **1 RPC novo** que devolva as linhas de `gamification_points` (com `occurred_at`,
  evento resolvido, ciclo, pontos) - o `occurred_at` da Onda 3 torna isso possível e correto.

### Parte B - Seleção decomposta (candidato; o comitê já foi entregue na Onda 4)
- O **comitê** já tem a matriz critério×avaliador COM `criterion_notes` (Onda 4). Falta a **visão do próprio candidato**:
  seu breakdown por critério **pós-decisão**.
- **RESTRIÇÃO LOCKED (Onda 4, não re-litigar):** candidato NUNCA vê `criterion_notes`, notas ou nomes de avaliadores.
  Logo a visão do candidato = **seus próprios scores agregados por critério** (PERT objetivo/entrevista/líder) + posição
  vs banda de corte + rank - NUNCA a identidade/racional de quem avaliou.
- RPCs candidato que já existem: `get_my_selection_result()`, `get_my_application_status()`, `get_my_evaluation_feedback()`.
  Página candidato: `src/pages/minha-candidatura.astro`. Verificar o que `get_my_selection_result` já devolve antes de criar RPC nova.

---

## DECISÕES DO OWNER - RATIFICADAS 2026-07-22 (não re-litigar)

1. **Split: SIM.** Duas ondas independentes: **5a** = gamificação (interna, membro+admin), **5b** = candidato (outward-facing).
   Cada uma tem seu PR + merge serial. Sub-issues criadas sob o umbrella #1465 (ver comentário em #1465).
2. **Candidato pós-decisão (5b):** **REJEITADO vê SÓ "não selecionado"** (sem breakdown numérico). **APROVADO vê seu breakdown
   por critério** (scores agregados próprios + posição vs banda de corte). Candidato NUNCA vê criterion_notes/notas/nomes de
   avaliadores (LOCKED Onda 4). Nota: `get_my_evaluation_feedback()` já existe - VERIFICAR o que ele já mostra ao candidato
   hoje e não regredir; a decisão "só não selecionado" é sobre o breakdown NUMÉRICO novo, não sobre feedback qualitativo pré-existente.
3. **Timing (5b): RECOMENDAÇÃO = buildar AGORA, gated por fase** (só renderiza pós-decisão), com **QA contra apps DECIDIDAS do
   Ciclo 3 (fechado)** via impersonação. Racional: desacopla eng do calendário operacional; feature pronta+testada antes do
   momento de decisão do C4 (quando há pressão real); o gate de fase impede exposição prematura. *Confirmar no início da 5b
   antes de construir; se o owner preferir aguardar o C4 fechar, adiar só a 5b (a 5a segue independente).*
4. **Gamificação (5a): PÁGINA DEDICADA** (não estender `profile.astro` como container principal). PORÉM `profile.astro` já tem
   breakdown de pontos (#1449) e **DEVE ser revisado/impactado** por estas mudanças (Ondas 1-4 já mexeram no ciclo/pilares; o
   header de chips mistura escopos sem rótulo) - alinhar o profile à nova página (ou linkar) e não deixar duas fontes divergentes.
   Export: definir formato no design (CSV default). Admin vê qualquer membro (relatório confirma).
5. **i18n real:** superfícies membro/candidato são i18n pt/en/es de verdade - toda chave nova nas 3 dicts (pt-BR/en-US/es-LATAM)
   + páginas /en/ e /es/ se criar rota nova (≠ do admin `selection.astro`, que é PT-hardcoded no client-side).

---

## MANDATO DA SESSÃO (após as decisões acima)

1. **Re-aterrar ANTES:** ciclo 4 (fase/status), o que `get_my_selection_result`/`get_member_xp_pillars` já devolvem
   (`pg_get_functiondef` vivo), migration head, e as páginas/RPCs de gamificação existentes. Nenhum número recitado de memória.
2. **Design primeiro:** convocar **`ux-leader`** (1 agente - materialidade média UX; NÃO o conselho inteiro) para journey
   do painel auditável + a visão do candidato. Se a decisão 2 envolver o que um rejeitado vê, convocar **`legal-counsel`** (1 agente).
3. **Construir conforme a decisão.** Se RPC nova (ledger de gamificação): DDL via `apply_migration` byte-fiel + md5-verify;
   REVOKE/GRANT corretos; **checar phantom tracking-row por NOME/statement, não por range** (ver gotcha abaixo); `migration
   repair`; `NOTIFY pgrst`; `npm run db:types` + commit `database.gen.ts` se assinatura nova.
4. **Grounding adversarial (workflow multi-lente)** antes de shippar superfície candidato: (a) candidato NUNCA vê
   criterion_notes/nomes/notas de terceiros; (b) membro só vê o próprio (admin gate correto p/ ver outros); (c) export não
   vaza PII fora de escopo; (d) números do painel batem com os RPCs corrigidos (Ondas 1-4).
5. **`npx astro build` + `npm test`** (com SUPABASE_URL + SERVICE_ROLE_KEY → DB-aware). 0 fail. Teste novo nas **2 whitelists**
   (`test` + `test:contracts` no package.json).
6. **Aplicar + merge à main** (sessão main pode mergear). Fecha a sub-issue da vez (**5a = #1473**, **5b = #1474**);
   o umbrella **#1465 fica ABERTO (Refs)** e é fechado À MÃO quando #1473 + #1474 mergearem.
   **Ordem sugerida:** rodar **5a (#1473) primeiro** (interna, sem dependência de timing) e **5b (#1474) depois**
   (confirmar o timing "buildar agora gated por fase vs aguardar C4" no início da 5b). Uma sub-onda por sessão limpa.
7. **Deploy do frontend** (`npx astro build && npx wrangler deploy`) - superfícies são server-rendered/client; só aparecem pós-deploy.
8. Atualizar `project-scoring-merit-audit-2026-07-21` + `MEMORY.md` (Onda 5 fechada; ARCO de auditoria COMPLETO 1-5).

---

## REGRAS DA CASA (não esquecer)
- Números em prompt/PR/commit/memória = de tool result DESTA sessão; nunca recitar de memória.
- Sem em-dash em entregáveis. Trailer `Assisted-By: Claude (Anthropic)`, nunca `Co-Authored-By`.
- DDL só via `apply_migration`; db-push BLOQUEADO (tracking divergente) → aplicar por função inline + md5-verify.
- **GOTCHA da Onda 4 (novo):** `apply_migration` MCP cria phantom tracking-row com **timestamp REAL** (ex.
  `20260722184340`), NÃO da série sintética `20260805…`. Um check de limpeza filtrando `version >= <head>` é CEGO a ele.
  Procurar phantom por **nome/statement** do migration (ou `version NOT LIKE '20260805%'`), não por range; o gate CI
  **ADR-0097 missing-file drift** é a rede. Deletar por versão EXATA.
- Adicionar coluna/assinatura quebra `gen-types-drift` → `npm run db:types` + commit `database.gen.ts` (CLI pin 2.109.0).
- Superfícies membro/candidato: i18n pt/en/es real (3 dicts) + páginas /en/ e /es/ se criar rota nova.
- Testes que fixam corpo de função por md5 → re-apontar p/ migration nova se reescrever a função.
