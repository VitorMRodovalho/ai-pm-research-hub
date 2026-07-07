# SPEC #1153 — Sincronizar o texto jurídico aprovado com o instrumento de Termo assinado

**Status:** ARQUITETURA IMPLEMENTADA (dev lane, 2026-07-06) · **Direção RATIFICADA: Direção 1 (fonte única)** — decisão do PM Vitor, 2026-07-06 · **Issues:** #1153 (arquitetura), #1152 (função→gate) · **Execução:** dev lane (branch `feat/1153-volunteer-term-signing-sync`)

## Execução (dev lane) — CONCLUÍDA nesta rodada
Entregue a **tubulação Direção 1** (sem tocar no texto jurídico; a lavra v9 é da governança):
- **Migração `20260805000352`** (aplicada em PROD + registrada + `NOTIFY`): índice único parcial `uq_one_active_volunteer_term` (INV-1); `activate_volunteer_term_version(uuid)` (gate `manage_platform` via `can_by_member`, flip atômico superseded→active, só ativa versão `locked`); `sign_volunteer_agreement` snapshota `content_html` da versão aprovada em `content_snapshot.html_body`, resolve `{chapterName}` do SSOT `chapter_registry`, mantém `clauses` (imutabilidade #648 + rollback).
- **`src/lib/certificates/pdf.ts`**: `CertificateData.template_html_body`; `hydrateCertData` resolve `snap.html_body` (só do snapshot imutável, nunca template vivo — respeita o guard #648); `buildVolunteerAgreementHTML` bifurca — corpo aprovado (chrome sem h1 duplicado + `{chapterName}` defensivamente resolvido) × slots legado intacto (41 certos já assinados renderizam verbatim).
- **`tests/contracts/1153-volunteer-term-signing-sync.test.mjs`** (ligado a `test` + `test:contracts`): estático (mig + pdf.ts) + INV-1/INV-2 DB-aware. `astro build` ✓ · `npm test` = 0 fail (5047, 4598 pass, 449 skip).

**Estado ao vivo:** 0 linhas `volunteer_term_template` active → assinatura segue bloqueada (correto; nada ligado prematuramente).

### Resta à governança (Onda 1, main/governança — NÃO é dev lane)
1. Propor v9 do `.docx` V2 (descartar v8 stale) → lock cadeia `curator → president_go` (Ivan) → `activate_volunteer_term_version(<doc_id 280c2c56>)`.
2. **QA visual do PDF assinado** (smoke com 1 adesão de teste + rollback) comparando com o `.docx` V2 SSOT — gate ANTES de liberar os 45.
3. #1152 (limpeza de gate: Lorena = contraparte, não `president_go`) idealmente antes do lock.
4. Onda 2 (re-aceite dos ativos via `recirculate`) desacoplada.

---

**Objetivo de negócio:** liberar os ~45 novos C4 a assinar o Termo **com o texto jurídico corrigido** (rodada Aaron/Angeline 06/07), fechando a drift entre a representação do leitor/aprovação e a representação assinada.

> Grounding: todos os fatos abaixo vêm de queries ao schema live (project `ldrfrvwhxsmgaabwmaik`) e leitura de `src/lib/certificates/pdf.ts` em 06/07. Re-aterrar antes de executar.

## 1. Estado atual (mapa preciso)

### Duas representações do Termo
1. **Leitor/aprovação — `document_versions.content_html`** (por versão, FK `document_id`). HTML completo da prosa jurídica. Gerida por `propose_new_version` / `lock_document_version` (cadeia de gates em `approval_chains`). É onde vive a lavra jurídica: `governance_documents` `280c2c56-e0e3-4b10-be68-6c731d1b4520`, versões v1→v8 (v7 `29a2d175` = R3-C3-IP v2.7-p150 locked 12/05; v8 `07f96592` = draft-rev-juridica 11/06, stale).
2. **Assinatura — `governance_documents.content`** (JSONB `clauseN`). Slots fixos. Consumida por:
   - `sign_volunteer_agreement(p_language, p_signed_ip, p_signed_user_agent)` — seleciona `WHERE doc_type='volunteer_term_template' AND status='active' ORDER BY created_at DESC LIMIT 1` e grava `content_snapshot.clauses = v_template.content` no `certificates` (imutável, #648).
   - `buildVolunteerAgreementHTML` (`src/lib/certificates/pdf.ts:326-391`) — renderiza `MAIN = clause1..clause12` + `SUB_KEYS = { clause1:[a,b,c], clause2:[2_1..2_5], clause7:[7a], clause9:[9a..9f,9note] }`. Cabeçalho PMI-GO hardcoded; qualificação do voluntário hidratada (`memberDataBlock`) + i18n `volunteer.headerIntro` (`{chapterName}`,`{chapterLegalName}`,`{chapterCnpj}`) + `chapter_registry` (contracting = PMI-GO, C3 R1).

### Defeitos
- **D1 — sem sync:** nenhuma função escreve `governance_documents.content` (varredura `pg_proc`). Aprovar/travar versão no leitor não altera o `.content` assinado.
- **D2 — nenhuma linha `active`:** ambas as linhas de `volunteer_term_template` (`280c2c56` v2.7 e `a78311fd` "R3-C3 Ciclo 3") estão `under_review`. `sign_volunteer_agreement` retorna `template_not_found` → assinatura bloqueada (última adesão 2026-04-14).
- **D3 — drift de linha:** adesões históricas fizeram snapshot de `a78311fd.content` (literal "PMI Goiás"), não de `280c2c56.content` (`{chapterName}`).
- **D4 — slots incompletos:** o `.content` JSON (clause1-12 + 2_1..2_5) não tem slot para as adições jurídicas (preâmbulo/CNPJ, 2.8 cessão INPI, 13.4 foro, Cláusula 14 GDPR/SCC, Cláusula 15 lifecycle). Trazê-las ao instrumento assinado exige estender o renderer.
- **D5 — placeholder:** `280c2c56.content` usa `{chapterName}`, que `buildVolunteerAgreementHTML` NÃO substitui → renderiza literal. Inconsistente com PMI-GO hardcode (#1048).

## 2. Target design

### Direção 1 (recomendada) — fonte única de verdade
O instrumento assinado renderiza a partir da **versão aprovada da cadeia** (`document_versions.content_html` apontada por `governance_documents.current_version_id`, com `change_class` e status de cadeia = approved/active), + hidratação de membro. Aposenta o `clauseN` JSON.
- `sign_volunteer_agreement` snapshota o `content_html` aprovado (não `content`).
- `buildVolunteerAgreementHTML` passa a receber o corpo HTML aprovado + campos de membro para hidratar (nome/PMI ID/endereço/etc. no header; corpo = HTML sanitizado com marcador de assinatura + carimbo).
- Ganho: SoT único, imutabilidade e cadeia de gates governam o que é assinado. Custo: refactor do renderer (de slots para corpo HTML) + verificação de fidelidade visual.

### Direção 2 (interina) — sync na ativação
Manter o renderer de slots; adicionar ativação que transforma `content_html` → `clauseN` JSON.
- Novo passo (RPC/trigger) na conclusão da cadeia (após `president_go`): monta `content` a partir da versão aprovada, seta `status='active'` na linha certa, desativa a antiga.
- Estender `MAIN`/`SUB_KEYS` do `buildVolunteerAgreementHTML` para as cláusulas jurídicas novas.
- Ganho: desbloqueia mais rápido. Custo: mantém duas representações + transform manual/automático a manter (a mesma dívida que gerou este bug).

**Recomendação:** Direção 1 como alvo. Se o prazo de assinatura pressionar, Direção 2 como ponte explicitamente temporária, com issue de convergência para a Direção 1.

> **DECISÃO (PM Vitor, 2026-07-06): Direção 1 ratificada — fonte única.** O instrumento assinado renderiza a partir da versão aprovada da cadeia; o `clauseN` JSON é aposentado. Não seguir a Direção 2 (sem ponte interina). O passo 3 do plano de execução usa o caminho da Direção 1.

## 3. Invariantes / transversais
- **INV-1:** exatamente uma linha `volunteer_term_template` com `status='active'` (contract test + índice parcial único).
- **INV-2:** texto assinado (`certificates.content_snapshot`) ≡ texto da versão aprovada na cadeia (contract test).
- **PMI-GO (#1048):** contracting party sempre PMI-GO; resolver `{chapterName}` (substituir no dado ou no render). members.chapter é informativo.
- **Qualificação hidratada:** não introduzir `[NOME COMPLETO]`/preâmbulo como texto de cláusula — vem de member fields + i18n header + `chapter_registry`.
- **#648:** manter snapshot imutável no cert; o render usa o snapshot pinado, nunca o template live.

## 4. Ativação e a jornada de 2 ondas (contexto de #1152 / rodada jurídica)
- **Onda 1 (destravar assinatura dos 45 novos):** após aprovar a versão jurídica (cadeia `curator → president_go`/Ivan), a ativação (Direção 1 ou 2) coloca a linha correta `active` → novos assinam 1ª adesão.
- **Onda 2 (desacoplada):** re-aceite dos voluntários ativos (`volunteers_in_role_active`) via `recirculate` + retificação de capítulos na Política (`partner_consultation`). Guardrail Cláusula 15.3 (material change exige janela de re-aceite dos ativos); 15.4.1 cobre o intervalo.
- **Gate cleanup (#1152):** remover carve-out `voluntariado_director` de `president_go` (Lorena = contraparte do instrumento, não gate de versão); mapear função→gate.

## 5. Plano de execução (dev lane, ordem sugerida)
1. Ratificar Direção 1 vs 2 (PM).
2. Migração de ativação + invariante linha-única-active (`apply_migration` + arquivo local + `repair` + `NOTIFY pgrst`).
3. Direção 1: refactor `buildVolunteerAgreementHTML` para corpo HTML aprovado + hidratação; `sign_volunteer_agreement` snapshota `content_html`. / Direção 2: transform `content_html`→`clauseN` + estender slots + `.content` update.
4. Resolver `{chapterName}` (#1048).
5. Contract tests INV-1, INV-2 + fidelidade de render (fixture de cert).
6. QA visual do PDF assinado (comparar com `.docx` V2 SSOT em `~/Downloads/nucleo-juridico-v0-drafts/doc02-...-V2.docx`).
7. Ativar em PROD → smoke: uma adesão de teste (rollback) confirma que o texto assinado == texto jurídico.

## 6. Fontes de verdade
- Texto jurídico final (SSOT): `.docx` V2 (docs 1/2/3/5) + `-V1-redline` (docs 6/7) em `~/Downloads/nucleo-juridico-v0-drafts/`. Validação de diff: `RELATORIO-VALIDACAO-2026-07-06.md`.
- Correção 2.6.4 (Angeline): manter âncora art. 49 IV; remover a frase "Prazos superiores...". Confirmada ausente nos `.docx` V2.
- CNPJ preâmbulo aterrado no cartão oficial Receita (06/07): 06.065.645/0001-99, Seção Goiânia GO, Av. Perimetral Norte 4129.
