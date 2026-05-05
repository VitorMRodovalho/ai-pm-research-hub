# Round 6 — Editorial + Material Fixes Matrix

**Session:** p90 (2026-05-04)
**Source:** Ricardo Santos critique (3 docx Vitor's laptop) + verified content extraction via Supabase v3 LOCKED
**Scope:** Items 5 (editorial fixes) + 6 (cross-incorporation Ricardo's drafts) from `project_pending_items_post_natalia_queue.md`
**Status:** Foundation matrix — DECISION POINTS pending para Vitor

---

## Estado atual dos 5 docs LOCKED v3 Round 5

| Doc | Title atual | Doc ID | v3 Lock | Chain status |
|---|---|---|---|---|
| Política IP | Política de Publicação e Propriedade Intelectual do Núcleo de IA & GP | `cfb15185...` | 2026-05-02 03:43 | `under_review` (curadores aguardando signoff) |
| Termo Voluntário | Termo de Compromisso de Voluntário — Núcleo de IA & GP | `280c2c56...` | 2026-05-02 03:43 | `under_review` |
| Adendo Retificativo | Adendo Retificativo ao Termo de Compromisso de Voluntario | `d2b7782c...` | 2026-05-02 03:43 | `under_review` |
| Adendo PI Cooperação | Adendo de Propriedade Intelectual aos Acordos de Cooperação | `41de16e2...` | 2026-05-02 03:43 | `under_review` |
| Acordo Cooperação Bilateral | Acordo de Cooperação Bilateral — Template Unificado (Núcleo IA) | `cd170c37...` | 2026-04-20 18:38 (v2 atual) | `under_review` |

**Curadores aguardando signoff:** Sarah Rodovalho · Roberto Macedo · Fabricio Costa (per memory `handoff_p90`).

---

## Matriz de absorção — 8 critiques Ricardo + 1 cláusula ausente

### Legenda

- **Tipo**:
  - 🟢 EDITORIAL — typo / terminologia / rename / reformatação. Aceite expresso voluntário **NÃO requerido** (per ADR-0068)
  - 🔴 MATERIAL — altera direitos/obrigações. Aceite expresso requerido + lawyer review (Ângelina)
- **Ship Path**:
  - **NOW** — pode ir nesta sessão (low risk)
  - **AFTER-CURADOR** — esperar curadores assinarem v3 antes
  - **AFTER-ÂNGELINA** — esperar lawyer engagement

### Critique #1 — Título "Política Pública" → "Política Institucional"

| Campo | Valor |
|---|---|
| Tipo | 🟢 EDITORIAL |
| Severidade | 🟡 baixa (clarity) |
| Doc afetado | Política IP (TITLE only — texto interno NÃO usa "política pública") |
| Source | `Política de Publicação e Propriedade Intelectual do Núcleo de IA & GP` |
| Target | `Política Institucional de Publicação e Propriedade Intelectual do Núcleo de IA & GP` |
| Operação | `UPDATE governance_documents SET title = 'Política Institucional de Publicação...' WHERE id = 'cfb15185...'` |
| Ship Path | **NOW** |

### Critique #2 — Aceite tácito (CC favor aderente)

| Campo | Valor |
|---|---|
| Tipo | 🔴 MATERIAL |
| Severidade | 🔴 alta (afeta direitos voluntário) |
| Doc afetado | Termo Compromisso §15.4 + Adendo Retificativo §3º |
| Source | "constitui aceite tácito da revisão" (clausula completa em ambos docs) |
| Target | Substituir por framework distinguishing editorial (aceite tácito ok) vs material (aceite expresso requerido) |
| Reasoning Ricardo | CC art. 111 + 423 — silêncio só importa anuência quando circunstâncias autorizarem; cláusulas ambíguas em contrato adesão interpretam-se em favor aderente |
| Ship Path | **AFTER-ÂNGELINA** |
| Nota | ADR-0068 já estabelece Material vs Editorial framework, mas cláusula atual blanket-aceita tácito para "revisões". Ângelina precisa redrafting cláusula |

### Critique #3 — GDPR Art 49 + UE-UK separar (adequacy 2026)

| Campo | Valor |
|---|---|
| Tipo | 🔴 MATERIAL |
| Severidade | 🔴 alta (compliance LGPD/GDPR) |
| Doc afetado | Política IP §13.5 only (outros docs usam art. 49 da Lei 9.610 BR — diferente) |
| Source | "consentimento explícito art. 49.º(1)(a)... transferências ocasionais; (iii) necessidade contratual art. 49.º(1)(b)" |
| Target | 3 regimes separados:<br>(a) Brasil (LGPD)<br>(b) UE/EEE — **adequacy recíproca Brasil ↔ UE jan/2026** (decisão Comissão Europeia)<br>(c) UK — sem adequacy ainda; mecanismo cabível UK GDPR (não art. 49 GDPR) |
| Reasoning Ricardo | Adequacy decision Brasil-UE jan/2026 obsoleta substantialmente o art. 49(1)(a) consent path; UK ainda separado |
| Ship Path | **AFTER-ÂNGELINA** |
| Maps to | Round 6 Item F (LGPD §13.5 update) |

### Critique #4a — Title rename "Termo de Compromisso" → "Termo de Adesão ao Serviço Voluntário"

| Campo | Valor |
|---|---|
| Tipo | 🟢 EDITORIAL |
| Severidade | 🟡 média (conformidade Lei 9.608/1998) |
| Doc afetado | Termo (id `280c2c56...`) + Adendo Retificativo (id `d2b7782c...`) |
| Source | `Termo de Compromisso de Voluntário — Núcleo de IA & GP` / `Adendo Retificativo ao Termo de Compromisso de Voluntario` |
| Target | `Termo de Adesão ao Serviço Voluntário — Núcleo de IA & GP` / `Adendo Retificativo ao Termo de Adesão ao Serviço Voluntário` |
| Reasoning Ricardo | Lei 9.608/1998 art. 2 usa expressão "termo de adesão" — nomenclatura legal precisa |
| Ship Path | **NOW** (TITLE-only via UPDATE — não muda content) |

### Critique #4b — Inner text "Termo de Compromisso" → "Termo de Adesão ao Serviço Voluntário"

| Campo | Valor |
|---|---|
| Tipo | 🟢 EDITORIAL (nomenclatura) |
| Severidade | 🟡 média (consistência) |
| Doc afetado | 4 docs: Política IP (3x) + Acordo Cooperação Bilateral (3x) + Adendo Retificativo (4x) + Termo Compromisso self-ref (1x) — **~11 occurrences total** |
| Source | "Termo de Compromisso" (todas ocorrências) |
| Target | "Termo de Adesão ao Serviço Voluntário" |
| Operação | UPDATE content_html com `replace()` pattern |
| Ship Path | **NOW** (terminologia consistency com title rename) |

### Critique #5 — Lei 14.063/**2021** → /**2020** + add MP 2.200-2/2001

| Campo | Valor |
|---|---|
| Tipo | 🟢 EDITORIAL (typo factual) |
| Severidade | 🔴🔴 alta (typo legal em produção) |
| Doc afetado | Acordo Cooperação Bilateral + Adendo Retificativo (2 occurrences) |
| Source | `Lei nº 14.063/2021 (assinaturas eletrônicas); e tratados internacionais` (Acordo) <br>`Lei nº 14.063/2021 (assinaturas eletrônicas).` (Adendo Retificativo) |
| Target | `Lei nº 14.063/2020 (assinaturas eletrônicas) e Medida Provisória nº 2.200-2/2001` |
| Reasoning Ricardo | Lei correta é 14.063/**2020** (não 2021); para contratos privados convém combinar com MP 2.200-2 que reconhece documentos eletrônicos e admite outros meios |
| Ship Path | **NOW** (typo + additive substrate; low risk) |

### Critique #6 — Tributária royalties → Anexo Fiscal Atualizável

| Campo | Valor |
|---|---|
| Tipo | 🔴 MATERIAL (restructure) |
| Severidade | 🟡 média (obsolescência seção tributária) |
| Doc afetado | Política IP §4.5+ (royalties + IRRF + DIRF + CDT) |
| Source | "(e).1 Responsabilidade da fonte pagadora. O PMI-GO, como fonte pagadora, é responsável pela retenção e recolhimento do IRRF sobre royalties, nos termos do art. 7.º da Lei n.º 7.713/1988 e do art. 685 do Decreto n.º 9..." + "(e).6 DIRF... e-Reinf a partir de 2025" |
| Target | (1) Mover seções (e).1-(e).6 para novo doc "**Anexo Fiscal Atualizável da Política IP**" mantido separadamente; (2) Manter na Política regra-mãe simples: "pagamentos observarão a legislação tributária vigente na data do pagamento" |
| Reasoning Ricardo | Tabelas IR mudaram em 2026, DIRF substituída por eSocial/EFD-Reinf; conteúdo obsoleto |
| Ship Path | **AFTER-ÂNGELINA** (restructure + new Anexo precisa lawyer review) |

### Critique #7 — "Fair use" → "art. 46 LDA"

| Campo | Valor |
|---|---|
| Tipo | 🟢 EDITORIAL (terminologia) |
| Severidade | 🟡 média (terminologia EUA em doc BR) |
| Doc afetado | Política IP only (1 occurrence) |
| Source | `uso proibido (art. 46 Lei 9.610 + fair use)` |
| Target | `uso proibido (art. 46 da Lei nº 9.610/1998)` (drop "+ fair use") |
| Reasoning Ricardo | "Fair use" é categoria do direito norte-americano, não da LDA brasileira. Em doc BR gera ruído interpretativo; melhor citar limitações do art. 46 explicitamente |
| Ship Path | **NOW** |

### Critique #8 — Cláusula plataforma deslocada

| Campo | Valor |
|---|---|
| Tipo | 🔴 MATERIAL (restructure) |
| Severidade | 🟡 média (clarity GP autor + plataforma) |
| Doc afetado | Adendo PI Cooperação Art 8 (origem) + cross-refs em Política §15 + Termo §16 + Adendo Retificativo §5-C + Acordo Cooperação Bilateral §11 |
| Source | "plataforma de software como projeto independente do GP" + "GP autor da plataforma como simultaneamente Gerente de Projeto" (CoI declarado) |
| Target | (1) Mover detalhamento técnico/operational da plataforma para novo doc "**Anexo Técnico — Plataforma Operacional Núcleo IA**" OU "Termos de Uso da Plataforma";<br>(2) No Termo Voluntário, simplificar para: "plataforma é ferramenta de gestão e seu uso não altera titularidade das obras do voluntário nem do Núcleo";<br>(3) Preservar cross-ref em Política § governança |
| Reasoning Ricardo | Cláusula sobre plataforma pessoal do GP gera confusão entre PI das obras Núcleo vs PI da plataforma. **PLUS**: alinha com novo contexto Vitor 2026-05-04 (plataforma é opensource self-licensed Vitor sole author; futuro: closure comercial conjunto Núcleo+Vitor) |
| Ship Path | **AFTER-ÂNGELINA** |
| Maps to | Round 6 Item G (Cláusula plataforma → Anexo) |

### Cláusula ausente — Glossário simplificado transversal

| Campo | Valor |
|---|---|
| Tipo | 🟢 EDITORIAL (content expansion) |
| Severidade | 🟡 média (UX voluntário) |
| Doc afetado | **Política IP §17** (RPC `get_governance_glossary` lê do `content_html` da própria Política — não tem tabela separada) |
| Source | Glossário §17 atual (criado p88 ADR-0068, ~13 termos básicos) |
| Target | Expand §17 com terminologia identificada por Ricardo:<br>• Track A / Track B / Track C<br>• Material change / Editorial change<br>• SCC (Standard Contractual Clauses)<br>• Adequação (LGPD/GDPR)<br>• CDT (Convenção para Dupla Tributação)<br>• Beneficial owner<br>• Path A / Path B (PMI Journey)<br>• Standby<br>• Aceite expresso vs aceite tácito<br>• Direitos morais vs patrimoniais<br>• Coautoria<br>• Obra sensível<br>• Período de graça INPI |
| Operação | UPDATE `document_versions.content_html` da Política IP — adicionar terms no §17 |
| Ship Path | **AFTER-CURADOR** ou **AFTER-ÂNGELINA** — toca Política IP v3 LOCKED |
| Maps to | Round 6 Item H (Glossário expand) |
| Alternativa arquitetural (futuro) | Criar tabela `governance_glossary_terms` + refactor RPC para ler dela (faz glossário independente do doc Política — mas é refactor que adiciona trabalho) |

---

## Resumo executivo

### 🟢 SHIP NOW — Editorial fixes (5 itens, low risk)

| # | Doc(s) | Fix |
|---|---|---|
| 1 | Política IP (title) | Adicionar "Institucional" |
| 4a | Termo + Adendo Retificativo (titles) | "Compromisso" → "Adesão ao Serviço Voluntário" |
| 4b | 4 docs (~11 occurrences) | Inner text "Termo de Compromisso" → "Termo de Adesão ao Serviço Voluntário" |
| 5 | Acordo Cooperação Bilateral + Adendo Retificativo | "14.063/2021" → "14.063/2020 e MP 2.200-2/2001" |
| 7 | Política IP | "art. 46 Lei 9.610 + fair use" → "art. 46 da Lei nº 9.610/1998" |
| H | Glossário page (RPC) | Expandir 13 termos novos |

**Total impacto:** 5 docs LOCKED v3 (titles + content_html minor diffs) + 1 RPC page expansion.

### 🔴 HOLD — Material fixes (4 itens, Ângelina-dependent)

| # | Doc(s) | Mudança |
|---|---|---|
| 2 | Termo §15.4 + Adendo Retificativo §3º | Aceite tácito framework editorial vs material |
| 3 | Política §13.5 | LGPD/GDPR UE-UK separar + adequacy 2026 (Round 6 Item F) |
| 6 | Política §4.5+ | Mover tributária para Anexo Fiscal Atualizável |
| 8 | Adendo PI Cooperação Art 8 + cross-refs | Plataforma → Anexo Técnico/ToS (Round 6 Item G) |

**Total impacto:** ~3 docs LOCKED v3 (substantial restructuring) + 2 novos docs criados (Anexo Fiscal + Anexo Técnico/ToS).

---

## 3 Ship Paths — DECISION pendente Vitor

### Path A — Hotfix in-place v3 + notify curadores

**Como:** UPDATE direto em `governance_documents.title` + `document_versions.content_html` para os 5 fixes editorial. Adicionar `document_comments` em cada chain explicando "hotfixes editorial X/Y/Z aplicados — typos factuais corrigidos, conteúdo material inalterado, favor seguir signoff em v3 atual". Audit log com action='governance.editorial_hotfix'.

| Pros | Cons |
|---|---|
| ✅ Fast (1 sessão; ~30 min execução) | ❌ Viola immutability principle (v3 LOCKED) |
| ✅ Curadores podem continuar review v3 inalterado materialmente | ❌ Curador signoff "before vs after" — se já assinaram v3 antigo, conteúdo mudou desde |
| ✅ Glossário expansion sem ripple | ❌ Risco erosão trust curador |
| ✅ Editorial framework ADR-0068 pode justificar | |

**Risk:** medium — curador trust + process integrity.

### Path B — Wait curadores assinarem v3 atual + Round 6 batch (editorial + material via Ângelina)

**Como:** Não fazer NADA com docs LOCKED agora. Aguardar Sarah/Roberto/Fabricio assinarem v3 (chain → status 'active'). Engajar Ângelina. Quando ready, criar v4 com TODOS os fixes (editorial + material) em uma rodada batch + apply via Feature #122 `recirculate_governance_doc` workflow.

| Pros | Cons |
|---|---|
| ✅ Linear; respeita signoff workflow | ❌ Delay editorial fixes weeks (Ângelina não-ágil) |
| ✅ Clean version history | ❌ "Termo de Compromisso" + "fair use" + "14.063/2021" continuam em produção até Ângelina ready |
| ✅ Process integrity preserved | ❌ Se curadores demorarem, dual delay |
| ✅ Curadores reveem batch consolidated | |

**Risk:** low — process integrity, mas erros factuais persistem em prod.

### Path C — v4 paralelo só editorial NOW + recirculate via #122 com diff explícito

**Como:** Criar v4 das 4 docs com TODOS os 5 fixes editorial. Lock + promote via `lock_document_version`. Depois `recirculate_governance_doc(chain_id, dry_run=true)` mostra diff aos curadores. **Skip-curador-resignoff via ADR-0068 editorial change framework** (notify-only path). Glossário expand em paralelo (RPC update).

| Pros | Cons |
|---|---|
| ✅ Compatible com ADR-0068 editorial framework | ❌ Mais trabalho técnico (v4 + chains) |
| ✅ Explicit version trail | ❌ Curadores precisam re-acknowledge mesmo se editorial-only |
| ✅ Diff visível para curadores via #122 preview modal | ❌ Se Vitor depois quiser bundle Material via Ângelina, há v5 (não v4) |
| ✅ Usa Feature #122 já LIVE | ❌ Hoje v3 ainda em review — v4 emerges como "draft" sob v3 not-yet-signed |

**Risk:** medium — workflow complexity + curador overhead novo.

### ~~Path D~~ COLAPSADO em A/B/C

Inicialmente considerei "glossário só, RPC-isolated". **Mas RPC lê do content_html da Política IP** — glossário expand toca Política LOCKED. Toda mudança editorial volta a ser A/B/C.

(Alternativa futura: refactor RPC + nova tabela `governance_glossary_terms` para desacoplar — mas é refactor incremental, não fix imediato.)

---

## Recomendação

**Path B (wait + bundle batch via Ângelina)**

Justificativa:
1. **Editorial fixes são chatos mas não urgentes** — typo legal "14.063/2021" não causa damage immediato (interpreta-se conforme contexto + intent)
2. **Curador trust > velocity** — Sarah/Roberto/Fabricio já se mobilizaram em 5 rounds anteriores; bother them com editorial-only round agora pode wear thin
3. **Ângelina coming anyway** — material fixes (4) precisam dela obrigatoriamente; editorial (5) pode "ride along" no v4 batch
4. **Bundle minimiza overhead curador** — 1 round Round 6 v4 batch (editorial + material consolidated) > 2 rounds (editorial agora + material depois)
5. **Versão history fica clean** — v3 (current Round 5) → v4 (Round 6 HYBRID expanded com tudo via Ângelina) — easier audit trail
6. **Riscos delay aceitáveis** — v3 atual é defensible (Lei 9.608, Lei 9.610, LGPD citados corretamente; typos legais são clarificáveis; "fair use" + "art 46 Lei 9.610" coexisten na cláusula — ambiguous mas não wrong)

Sequência operacional Path B:
```
Etapa 1 (now—1 sem):
  Curadores Sarah + Roberto + Fabricio assinam v3 Round 5
  Chain status review → active
  Vitor abre canal Ângelina via Ivan (per memory feedback_lawyer_pathway_angelina_pmi_go.md)

Etapa 2 (1—4 sem):
  Vitor brief Ângelina escopo Round 6 HYBRID expanded:
    - Editorial fixes 5 itens (matrix above)
    - Material fixes 4 itens (matrix above)
    - Items A + E + F + G + H Round 6 substrate
    - RED FLAG marca PMI® (Item 2c separado)
  Ângelina review + draft

Etapa 3 (4—6 sem):
  Vitor aplica edits via apply_migration v4
  Lock + promote v4
  Recirculate via Feature #122 para curadores reviewing v4 (ADR-0068 fast-track per editorial+material framework)

Etapa 4 (6—8 sem):
  Curadores assinam v4
  Status active
  Eventualmente circular para 5 capítulos atuais + 10 expansion via pontos focais
```

**Path A (hotfix in-place)** continua disponível se Vitor decidir velocity > linear process.

---

## Decision points Vitor

1. ☐ **Path A / B / C escolha?** (recomendação: **B**)
2. ☐ **Glossário 13 termos novos** — todos OK ou subset? Anti-alucinação: você confirma todos termos que listei são relevantes? (Track A/B/C, Material/Editorial change, SCC, Adequação, CDT, Beneficial owner, Path A/B, Standby, Aceite expresso vs tácito, Direitos morais vs patrimoniais, Coautoria, Obra sensível, Período de graça INPI)
3. ☐ **Title rename Critique #4a** — "Termo de Adesão ao Serviço Voluntário" como exato? OU prefere variação ("Termo de Adesão ao Serviço Voluntário do Núcleo IA & GP")?
4. ☐ **Critique #1 rename** — "Política Institucional" como exato? OU prefere "Política de Governança de PI" (alt. Ricardo sugeriu)?
5. ☐ **Critique #5 MP 2.200-2/2001** — adicionar como ADDITIVE (substrate) ou só corrigir typo 14.063/2021→2020?
6. ☐ **Anexo Técnico Plataforma (Critique #8)** — criar como NOVO doc na governance ou como sub-página da plataforma `/governance/plataforma-anexo-tecnico`?
7. ☐ **Anexo Fiscal Atualizável (Critique #6)** — mesmo question (novo doc ou sub-página)?

---

## Cross-references

- `memory/project_pending_items_post_natalia_queue.md` — origem dos items 5 + 6
- `memory/feedback_lawyer_pathway_angelina_pmi_go.md` — Ângelina pathway
- `memory/feedback_pmi_brand_canonical.md` — brand framing
- `memory/reference_pmi_global_program_names_canonical.md` — nomenclatura precise
- `docs/adr/ADR-0068-governance-redraft-framework.md` — Material vs Editorial change framework (referência)
- `docs/specs/p88-governance-recirculation-workflow.md` — Feature #122 (relevante para Path C se aprovado)

## Spec author/owner
- **Author:** Claude (claude-opus-4-7) per Vitor instructions
- **Owner:** Vitor Maia Rodovalho (PM)
- **Approval pending:** Vitor (decision points 1-7 above)
- **Created:** 2026-05-04 (sessão p90)
