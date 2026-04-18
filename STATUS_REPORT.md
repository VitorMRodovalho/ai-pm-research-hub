# STATUS REPORT — ai-pm-research-hub

**Data:** 2026-04-20
**Executor:** Claude Code (instância do projeto ai-pm-research-hub)
**Origem:** `/home/vitormrodovalho/Desktop/ai-pm-research-hub`
**Destino:** `/home/vitormrodovalho/projects/ai-pm-research-hub`

## 1. Estado pré-migração

- Branch: `main`
- Commit HEAD: `eef876b` (`feat(seed): Phase IP-1 v2.1 — 5 documents + 4 approval chains em review`)
- Dirty: 1 arquivo untracked (`supabase/.temp/linked-project.json` — esperado, não é git-tracked)
- Unpushed: 0 (push feito pré-migração; `0 0` em `git rev-list --left-right --count origin/main...HEAD`)
- Tamanho: 1.3 GB
- Sub-repos: apenas `./.git` (não-umbrella, clone único)

## 2. Git — ações executadas

- **Commits criados nesta sessão (pré-migração)**: 3 commits atômicos
  - `6646d3d` — `docs(council): CR-050 v2.1 legal-counsel audit + source MDs`
  - `e14d30c` — `feat(db): Phase IP-1 foundation — 5 tables + RPCs + RLS + 2 invariants`
  - `eef876b` — `feat(seed): Phase IP-1 v2.1 — 5 documents + 4 approval chains em review`
- **Push**: sucesso. `git push origin main` → `0c04a3a..eef876b main -> main`
- **Branches empurradas**: `main`

## 3. Dados externos (map-deps)

Referências encontradas a caminhos fora do projeto:

| Arquivo do projeto | Referência externa | Status |
|---|---|---|
| `.claude/settings.local.json` | `/home/vitormrodovalho/Desktop/ai-pm-research-hub/...` + `~/Desktop/ai-pm-research-hub/...` (permission patterns) | **Resolvido** — 25 paths `Desktop/...` + 24 paths `~/Desktop/...` substituídos por `projects/...` via sed. Agora 0 refs a `Desktop/ai-pm-research-hub` e 149 refs a `projects/ai-pm-research-hub`. |
| `scripts/bulk_knowledge_ingestion/upload_manifest.json` | `/home/vitormrodovalho/Desktop/ai-pm-hub-v2/data/raw-drive-exports/...` | **Consumido** — referências a projeto diferente (ai-pm-hub-v2). Dados já ingeridos; manifest é log histórico. Fora de escopo deste projeto. |
| `scripts/bulk_knowledge_ingestion/upload_manifest_curated.json` | idem | **Consumido** — mesma classificação. |
| `scripts/docusign-signers-extracted.json` | `/home/vitormrodovalho/Downloads/A/Termos de Compromisso ao Voluntariado 2026-.../` | **Consumido** — dados já extraídos e persistidos no DB (certificates) + commits anteriores. |
| `scripts/data_science/1.2_kpi_and_enrichment.ts` | `/home/vitormrodovalho/Downloads/data/raw-drive-exports/.../Selecao candidatos 2025-2.xlsx` e `...2026-1.xlsx` | **Consumido** — script one-shot de pesquisa; dados processados em ciclo de seleção passado. Se precisar re-executar, usuário precisa restaurar Downloads (fora do git). Sinalizar para consolidação (fase 3). |
| `data/ingestion-logs/file_detective_report.json` | `/home/vitormrodovalho/Desktop/ai-pm-research-hub/data/staging-knowledge/...` | **Consumido** — log histórico da ingestão knowledge (processing report). Paths in-repo, mas prefixo Desktop em logs não impacta funcionalmente (staging dir já não existe). |
| `docs/council/2026-04-18-platform-audit.md` | `/home/vitormrodovalho/Downloads/A/` (.docx path) | **Consumido** — menção em relatório de auditoria, texto histórico. |
| `docs/council/2026-04-19-legal-counsel-ip-review.md` | `/home/vitormrodovalho/Desktop/ai-pm-research-hub/tmp/ip-v2-md/*.md` | **Consumido** — parecer jurídico referencia working dir de conversão pandoc. `tmp/` é gitignored (nesta sessão adicionado). `docs/council/cr-050-v2.1-source/` tem os .md v2.1 preservados. |
| `docs/council/2026-04-18-ip-ratification-planning.md` | `/home/vitormrodovalho/Downloads/A/` | **Consumido** — texto histórico. |
| `docs/audit/SPEC_VS_DEPLOYED_W140.md` | `/home/vitormrodovalho/Downloads/CODE_PROMPT_W140_UPDATED.md` | **Consumido** — audit report referencia spec de W140 histórico. |
| `.claude/skills/session-log/SKILL.md` | ref docs-like | **Consumido** — comentário, não-funcional. |
| `GOVERNANCE.md` | ref docs-like | **Consumido** — sem path funcional. |
| `docs/archive/RELEASE_LOG_HISTORICAL.md` | N/A | **Consumido** — arquivo histórico. |

**Claude Code memory** (externo ao repo mas crítico para continuidade):
- `/home/vitormrodovalho/.claude/projects/-home-vitormrodovalho-Desktop-ai-pm-research-hub/` (sessões + memory/) copiado para `-home-vitormrodovalho-projects-ai-pm-research-hub/` via `cp -a`. diff -qr: 0 linhas (integridade 100%).

## 4. Mineração de dados (se aplicável)

- **Status:** N/A para esta migração. Mineração histórica (Ciclo 1-3 docusign, drive exports, file detective) já concluída em sessões anteriores; todos os dados persistidos em DB + commits.
- **Fontes consumidas:**
  - `~/Downloads/A/Termos de Compromisso ao Voluntariado 2026-.../` (docusign certificates) — persistido em `certificates` table.
  - `~/Downloads/data/raw-drive-exports/.../Selecao candidatos *.xlsx` — persistido em `selection_applications` via scripts/data_science.
  - `~/Desktop/ai-pm-hub-v2/data/raw-drive-exports/Núcleo IA & GP/Apresentações/...` — persistido em `hub_resources` via bulk_knowledge_ingestion.
- **Pendências:** nenhuma mineração ativa na sessão p30.

## 5. Migração — integridade

- `cp -a` executado: **sim** (preserva timestamps, permissões, atributos, hardlinks, symlinks)
- `diff -qr` exit code: **0** (`/tmp/migration-diff-ai-pm-research-hub.txt`, 0 linhas — cópia byte-perfect)
- Verificação git pós-cópia:
  - `git status`: idêntico à origem (branch main up to date, untracked: supabase/.temp/linked-project.json)
  - `git log --oneline -5`: HEAD `eef876b` idêntico
  - `git rev-list --left-right --count origin/main...HEAD`: `0 0`
- `.claude/settings.local.json` paths atualizados: 25 refs `Desktop/...` + 24 refs `~/Desktop/...` → 149 refs `projects/ai-pm-research-hub` (0 refs remanescentes a Desktop)
- Claude Code memory copiado: `-home-vitormrodovalho-Desktop-...` → `-home-vitormrodovalho-projects-...` (diff -qr 0 linhas)
- **Origem deletada: sim** (`rm -rf /home/vitormrodovalho/Desktop/ai-pm-research-hub`)

## 6. Sinalizações para consolidação (fase 3)

Arquivos externos que **PODEM** ser deletados com segurança após esta migração (referências internas ao projeto já são consumidas):

- `~/Downloads/A/Termos de Compromisso ao Voluntariado 2026-20260410T173216Z-3-001/` — certificates já no DB, scripts/docusign-signers-extracted.json é log histórico.
- `~/Downloads/data/raw-drive-exports/` (subset tocado por `scripts/data_science/1.2_kpi_and_enrichment.ts`) — `selection_applications` no DB.
- `~/Downloads/A/*.docx` (v2) — convertidos para `docs/council/cr-050-v2.1-source/*.md` + HTML seed em DB.
- `/home/vitormrodovalho/Desktop/ai-pm-research-hub/data/staging-knowledge/` — referenciado em `data/ingestion-logs/file_detective_report.json` mas staging-knowledge já foi processado e seu próprio conteúdo agora está em `hub_resources`.

Arquivos externos que **NÃO PODEM** ser deletados ainda (ou decisão pertence a outro projeto):

- `/home/vitormrodovalho/Desktop/ai-pm-hub-v2/` — **fora de escopo**: parece ser outro projeto (legacy/predecessor). Upload_manifests referenciam mas dados já foram ingeridos. Aguarda decisão do projeto dono (provavelmente rotulado como "ai-pm-hub-v2" separado).
- `~/Downloads/CODE_PROMPT_W140_UPDATED.md` — **fora de escopo**: menção em audit report. Provavelmente deletável mas decisão do dono.
- `~/Desktop/ai-pm-research-hub-OLD/` — **fora de escopo deste projeto**: é o clone redundante que será tratado pelo prompt `02-ai-pm-research-hub-OLD.md`. Validações confirmam histórico preservado no remote.

## 7. Problemas encontrados

- **Conflito de cwd pós-delete**: Após `rm -rf` da origem, a shell persistente do Claude Code (cwd = `/home/vitormrodovalho/Desktop/ai-pm-research-hub`) ficou em estado inválido ("getcwd: cannot access parent directories"). Efeito cosmético apenas — todas as ações subsequentes (incluindo escrever este STATUS_REPORT) usam caminhos absolutos e continuam funcionando. Usuário precisa reabrir Claude Code em `/home/vitormrodovalho/projects/ai-pm-research-hub/` para continuar a próxima sessão.
- **Tilde expansion em `.claude/settings.local.json`**: primeiro sed pegou apenas paths `/home/vitormrodovalho/Desktop/...`. Segundo sed pegou `~/Desktop/...`. Ambos resolvidos.
- Nenhum problema de integridade detectado (diff -qr = 0).

## 8. Confirmação final

- [x] Projeto funcional em `~/projects/ai-pm-research-hub/` (git state idêntico, 1.3G copiado byte-perfect, 0 diffs)
- [x] Git remoto em dia (3 commits pushed, `0 0` ahead/behind)
- [x] Origem removida (`rm -rf /home/vitormrodovalho/Desktop/ai-pm-research-hub` executado)
- [x] `.claude/settings.local.json` paths atualizados (Desktop → projects, 0 Desktop refs restantes)
- [x] Claude Code memory dir copiado (`-home-vitormrodovalho-Desktop-...` → `-home-vitormrodovalho-projects-...`)
- [x] Report pronto para envio à conversa mestra

**Nota de continuidade**: Próxima sessão Claude Code deve ser iniciada em `/home/vitormrodovalho/projects/ai-pm-research-hub/` para usar memory + settings migrados. O old Claude memory dir (`-home-vitormrodovalho-Desktop-ai-pm-research-hub`) foi preservado como backup e pode ser removido em fase 3 após confirmação de que nova sessão funciona.
