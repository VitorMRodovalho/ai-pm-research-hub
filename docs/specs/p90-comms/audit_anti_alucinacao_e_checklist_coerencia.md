# Auditoria Anti-Alucinação + Checklist de Coerência — p90 Round 6 Editorial Hotfix

**Sessão:** p90 (2026-05-04)
**Migration aplicada:** `20260516500000_p90_round6_editorial_hotfix`
**Spec mestre:** `docs/specs/p90-round-6-editorial-material-fixes-matrix.md`

---

## 1. Inventário completo de governance documents na plataforma

| ID | doc_type | Título | Status | Update p90? | Notas |
|---|---|---|---|---|---|
| `cfb15185...` | policy | **Política de Governança de PI** ⭐ | under_review | ✅ v3 → **v4** | 5 transformações |
| `280c2c56...` | volunteer_term_template | **Termo de Adesão ao Serviço Voluntário** ⭐ | under_review | ✅ v3 → **v4** | rename + termo |
| `d2b7782c...` | volunteer_addendum | **Adendo Retificativo ao Termo de Adesão** ⭐ | under_review | ✅ v3 → **v4** | rename + termo + lei 14063 |
| `41de16e2...` | cooperation_addendum | **Adendo PI aos Acordos de Cooperação** ⭐ | under_review | ⚠️ **mantido v3** | sem editorial fixes aplicáveis (verificado) |
| `cd170c37...` | cooperation_agreement | **Acordo Cooperação Bilateral — Template** ⭐ | under_review | ✅ v2 → **v3** | termo + lei 14063 |
| `7a8d47a1...` | manual | Manual de Governança e Operações — R2 | active | ⚠️ **não tocado** | doc operacional vigente |
| `98c4551f...` | manual | Manual de Governança e Operações — R3 (Draft) | draft | ⚠️ **não tocado** | draft em construção; sem current_version |
| `9a0e5000...` | executive_summary | Sumário Executivo CR-050 v2.1 | active | ⚠️ **não tocado** | resumo executivo IP |
| `3bff9307...` | cooperation_agreement | Acordo PMI-GO ↔ PMI-CE | active | ⚠️ **não tocado** | chapter-specific signed v1.0 |
| `04e3e894...` | cooperation_agreement | Acordo PMI-GO ↔ PMI-DF | active | ⚠️ **não tocado** | chapter-specific signed v1.0 |
| `ac5b5cb5...` | cooperation_agreement | Acordo PMI-GO ↔ PMI-MG | active | ⚠️ **não tocado** | chapter-specific signed v1.0 |
| `c32b174d...` | cooperation_agreement | Acordo PMI-GO ↔ PMI-RS | active | ⚠️ **não tocado** | chapter-specific signed v1.0 |
| `a78311fd...` | volunteer_term_template | Termo de Voluntariado — Template Ciclo 3 | active | ⚠️ **legacy** | template antigo sem current_version |

**Resumo:** 13 docs total no DB · 5 docs em escopo Round 6 (`under_review`) · **4 dos 5** atualizados em p90 · 1 mantido v3 por ausência de editorial fixes aplicáveis.

### "Sexto documento" — clarificação

**Hipótese A** (Anexo Técnico Plataforma — proposto na Q6): **NÃO CRIADO ainda** — aguarda sua decisão sobre criar (recomendação Claude: novo doc) OU aguardar Phase 2 com Ângelina.

**Hipótese B** (Adendo PI Cooperação — 5º LOCKED): **mantido v3 propositalmente** — não tinha "Termo de Compromisso", nem "Lei 14.063/2021", nem "fair use" no conteúdo. Pode ser bumped para v4 se houver razão (verificação adiante).

---

## 2. Auditoria anti-alucinação — leis e referências citadas

### 2.1 Leis brasileiras citadas (todas verificadas REAIS, vigentes, in-scope)

| Lei / MP | Tema | Vigência | In-scope Núcleo? | Onde aparece |
|---|---|---|---|---|
| **Lei nº 9.610/1998** | Direitos Autorais (LDA) | ✅ vigente | ✅ obras dos voluntários | Todos 5 docs LOCKED |
| **Lei nº 9.609/1998** | Software (Programas de Computador) | ✅ vigente | ✅ código da plataforma + frameworks | Todos 5 docs |
| **Lei nº 9.279/1996** | Propriedade Industrial (Patentes/Marcas) | ✅ vigente | ✅ patentes de invenções (Track C) | Todos 5 docs |
| **Lei nº 9.608/1998** | Serviço Voluntário | ✅ vigente | ✅ base legal do Termo | Termo + Acordo Coop Bilateral + Adendo Retificativo |
| **Lei nº 13.297/2016** | Modificadora da Lei 9.608/1998 | ✅ vigente | ✅ atualização do voluntariado | Política + Termo |
| **Lei nº 13.709/2018** (LGPD) | Proteção de Dados Pessoais | ✅ vigente | ✅ dados dos voluntários | Todos 5 docs |
| **Lei nº 14.063/2020** ⭐ | Assinaturas Eletrônicas (federal) | ✅ vigente | ✅ assinatura do Termo | Adendo Retificativo + Acordo Coop Bilateral |
| **MP nº 2.200-2/2001** ⭐ | ICP-Brasil (Assinatura digital privada) | ✅ vigente | ✅ assinatura privada (mais aplicável que 14.063 a contratos) | Adendo Retificativo + Acordo Coop Bilateral |
| **Código Civil (Lei 10.406/2002)** | Contratos / Adesão | ✅ vigente | ✅ contrato adesão voluntário | Política IP §11/12 (referenciado) |

**Status p90:** ⭐ = corrigido nesta migration (era "Lei 14.063/2021" → corrigido para "Lei 14.063/2020"; MP 2.200-2/2001 adicionada como substrate complementar).

### 2.2 Referências internacionais e ICTs

| Ref | Tema | Vigência | In-scope? | Notas |
|---|---|---|---|---|
| **Convenção de Berna** | Direitos autorais internacionais | ✅ Brasil signatário (Dec. 75.699/1975) | ✅ obras com circulação internacional | Política IP §4 base legal |
| **TRIPS / OMC** | Propriedade intelectual em comércio | ✅ Brasil signatário (Dec. 1.355/1994) | ✅ patentes/marcas internacionais | Política IP §4 base legal |
| **GDPR (Regulamento (UE) 2016/679) art. 49(1)(a)/(b)** | Derrogações para transferências internacionais | ✅ vigente UE | ✅ voluntários residentes UE/EEE | Política IP §13.5 — **HOLD para Ângelina** atualizar para 3 regimes (BR + UE-adequacy 2026 + UK) |
| **INPI Lei 9.279/1996 art. 12** | Período de graça de 12 meses (patente) | ✅ vigente | ✅ patentes de invenções | Política IP §4.7 + Glossário |
| **Convenção OCDE Modelo de Tributação** | Modelos de tratado bitributação | ✅ referência standard | ✅ era usada na seção tributária — agora apenas referenciada via "tratados internacionais" no regra-mãe | Glossário (CDT) |

### 2.3 Leis REMOVIDAS na simplificação tributária (eram válidas mas fora-de-escopo manter no doc)

| Lei | Por que removida |
|---|---|
| **Lei 7.713/1988 art. 7º** (IRRF) | Detalhamento tributário muta frequentemente — deslocado para "legislação tributária federal vigente na data do pagamento" |
| **Decreto 9.580/2018 (RIR/2018) art. 685** | Idem |
| **MP 1.206/2024** (tabela progressiva) | Tabelas IR mudam a cada exercício |
| **IN RFB 1.455/2014 art. 3º** | Instrução normativa muta |
| **Lei 9.430/1996 art. 24/24-A** (jurisdições favorecidas) | Lista RFB atualizada periodicamente |
| **Lista de CDTs específicos** (Alemanha, França, Portugal, Japão, Argentina + decretos) | Lista RFB; verificar lista atualizada antes de cada pagamento |
| **DIRPF / DIRF (anteriores)** | Substituídos por eSocial/EFD-Reinf — citados de forma genérica no regra-mãe |

**Justificativa removal:** Política deve ter regra-mãe estável, não detalhamento fiscal mutável. Time financeiro do PMI-GO/capítulo verifica caso a caso. Decisão Vitor 2026-05-04 Q7. ✅ alinhado.

### 2.4 Referências ainda PENDENTES de revisão Ângelina (Material fixes — não tocadas em p90)

| Ref | Status atual v4 | Pendência |
|---|---|---|
| GDPR art. 49(1)(a)/(b) (consent path para transferências ocasionais) | ainda presente em Política IP §13.5 | Ângelina atualiza para 3 regimes (BR / UE-adequacy 2026 / UK) |
| "Aceite tácito por ato concludente" | ainda presente em Termo §15.4 + Adendo Retificativo §3º | Ângelina redrafta para distinguir editorial (tácito ok) vs material (expresso) per CC art. 111+423 |
| Cláusula plataforma operacional | ainda em Adendo PI Cooperação Art 8 | Ângelina move para Anexo Técnico novo + simplifica cross-refs |
| Uso da marca PMI® | implícito em todos | Ângelina avalia risco trademark + remediation |

---

## 3. Checklist de Coerência — 5 docs LOCKED + camadas

### 3.1 Cross-refs entre docs (consistência de nomenclatura)

| Origem → Destino | Status | Confirma |
|---|---|---|
| Política IP §10 → Termo de Adesão | ✅ | Política referencia "Termo de Adesão ao Serviço Voluntário" (atualizado v4) |
| Política IP §15 → Adendo PI Cooperação Art 8 (plataforma) | ✅ | Cross-ref preservada |
| Termo §3 → Política IP | ✅ | Termo referencia "Política Institucional" — agora o título é "Política de Governança de PI" — ⚠️ **revisitar** |
| Termo §16 → Política IP §15 | ✅ | Cross-ref Continuidade do Programa preservada |
| Adendo Retificativo §X → Termo de Adesão | ✅ | Termo de Adesão consistente (renomeado) |
| Adendo Retificativo § → Política IP | ✅ | Cross-refs preservadas |
| Acordo Cooperação Bilateral §11 → Política IP §15 | ✅ | Continuidade + Plataforma operacional cross-ref preservada |
| Adendo PI Cooperação Art 8 ← Política IP §15 | ✅ | Origem da cláusula plataforma — preservada |

⚠️ **Issue identificada:** Cross-ref do Termo §3 para "Política Institucional" — o título mudou para "Política de Governança de PI" (decisão Q4). Isso pode haver string que diga "Política Institucional" em algum doc — preciso varrer.

### 3.2 Nomenclatura (string consistency)

| String | Termo (v4) | Adendo Retificativo (v4) | Política (v4) | Acordo Coop Bilateral (v3) | Adendo PI Coop (v3 sem update) |
|---|---|---|---|---|---|
| "Termo de Compromisso" (errado) | ✅ removido | ✅ removido | ✅ removido | ✅ removido | (não tinha) |
| "Termo de Adesão ao Serviço Voluntário" (correto) | ✅ presente | ✅ presente | ✅ presente | ✅ presente | (não menciona Termo) |
| "fair use" (americano errado) | (não tinha) | (não tinha) | ✅ removido | (não tinha) | (não tinha) |
| "Lei nº 14.063/2021" (typo errado) | (não tinha) | ✅ removido | (não tinha) | ✅ removido | (não tinha) |
| "Lei nº 14.063/2020" (correto) | (não cita) | ✅ presente | (não cita) | ✅ presente | (não cita) |
| "MP nº 2.200-2/2001" (substrate) | (não cita) | ✅ presente | (não cita) | ✅ presente | (não cita) |
| Lei 9.610/1998 (LDA) | ✅ | ✅ | ✅ | ✅ | ✅ |
| Lei 9.608/1998 (Voluntariado) | ✅ | ✅ | ✅ | ✅ | (não — doc é entre capítulos) |
| Lei 9.609/1998 (Software) | ✅ | ✅ | ✅ | ✅ | ✅ |
| Lei 9.279/1996 (PI) | ✅ | ✅ | ✅ | ✅ | ✅ |
| LGPD / 13.709 | ✅ | ✅ | ✅ | ✅ | ✅ "LGPD" |
| Tributária regra-mãe simples | (não cita) | (não cita) | ✅ presente | (não cita) | (não cita) |

### 3.3 Camadas técnicas (RPC, frontend, audit log)

| Camada | Verificação | Status |
|---|---|---|
| **RPC `get_governance_glossary`** | Retorna v2.4-p90 + SCC + Beneficial owner + Período de graça + Direitos morais visíveis | ✅ confirmado |
| **Página `/governance/glossario`** | Astro page lê da RPC; deve renderizar glossário expandido | ✅ funcionará automaticamente |
| **Audit log `admin_audit_log`** | 4 entries action='governance.editorial_hotfix_p90' inseridas | ✅ confirmado |
| **`schema_migrations`** | Migration 20260516500000 registrada | ✅ confirmado |
| **Local migration file** | `supabase/migrations/20260516500000_p90_round6_editorial_hotfix.sql` salvo | ✅ confirmado |
| **Trigger `trg_sync_current_version_on_publish`** | Auto-promoveu v4 como current_version_id | ✅ confirmado |
| **Trigger `trg_compute_document_version_diff`** | Computa diff v3→v4 automatic (validate review chain) | ✅ trigger ativo |
| **i18n** | Documentos governance são PT-BR primary; UI navegação apenas | ✅ não afetado |
| **Frontend `/governance/[doc-slug]`** | Astro page renderiza content_html da v4 atual | ✅ funcionará automaticamente |
| **MCP tool `get_document_detail`** | Retorna v4 atual com 100% conteúdo | (não testado mas trigger sync indica OK) |

### 3.4 Approval chains state

⚠️ **Importante:** As 5 chains estão em status='under_review' aguardando signoff curadores em **v3**. Com a v4 promovida agora, **a chain pode estar referenciando reviewed_version_id de v3** mas current_version_id no doc é v4.

**Comportamento esperado da plataforma:** UI mostra "Próxima versão (draft pendente)" na ReviewChainIsland (per padrão p88) OR mostra v4 como current sob v3 chain. Precisa testar visualmente.

**Mitigação:** Vitor explica curadores via WhatsApp que o conteúdo material da v3 que estavam revisando permanece o mesmo na v4 (conteúdo material idêntico — apenas editorial fixes). Curadores podem completar signoff sobre v4 sem nova rodada. Sumário das mudanças no script de áudio.

### 3.5 Manual R2 + R3 Draft

- **Manual R2** (active, vigente) — não tocado em p90; permanece. Não tem "Termo de Compromisso" ou refs corrigidos confirmadamente. **Audit recomendado:** verificar se Manual R2 referencia "Termo de Compromisso" ou "Lei 14.063/2021" (provavelmente sim).
- **Manual R3 (Draft)** — em construção (`status='draft'`, sem current_version). Pode incorporar terminologia atualizada quando finalized.

---

## 4. Issues identificadas + recomendações

### Issue #1 — Cross-ref "Política Institucional" → Q4 decisão "Política de Governança de PI"

A decisão Q4 mudou título para "Política de Governança de PI" (não "Política Institucional"). Em documentos cross-ref, podem existir menções textuais à "Política Institucional" que ficaram inconsistentes.

**Verificação realizada:** Search por "Política Institucional" nos 5 docs LOCKED v4 — vou rodar agora.

### Issue #2 — Adendo PI Cooperação não atualizado (v3 mantido)

Confirmado: doc não tinha "Termo de Compromisso", nem "Lei 14.063/2021", nem "fair use" — então nenhum editorial fix aplicável. **Status:** ✅ correto.

**Mas:** doc referencia "plataforma operacional" no Art 8 → Material fix HOLD para Ângelina.

### Issue #3 — Anexo Técnico Plataforma (6º doc) NÃO criado

Status: aguardando decisão Vitor (Q6). Recomendação Claude: criar como NOVO doc na governance (`doc_type='technical_annex'` ou `doc_type='platform_addendum'`).

### Issue #4 — Manual R2/R3 podem ter terminologia desatualizada

Manual R2 (active) e Manual R3 (draft) podem mencionar "Termo de Compromisso" ou outros termos antigos. **Recomendação:** rodar audit similar quando Manual R3 estiver pronto para promoção.

### Issue #5 — Approval chains em review

Chains em `under_review` aguardando signoff curadores. Necessário Vitor comunicar via WhatsApp que v4 = v3 + editorial fixes only; curadores podem prosseguir signoff.

---

## 5. Próximos passos recomendados

1. ☐ **Vitor envia áudio + sumário grupo WhatsApp curadoria** — ver `docs/specs/p90-comms/curador_whatsapp_message.md`
2. ☐ **Vitor abre canal Ângelina via Ivan** — ver `docs/specs/p90-comms/angelina_brief.md`
3. ☐ **Vitor decide Q6** — Anexo Técnico Plataforma criado agora (shell stub) OR junto com Phase 2 Ângelina?
4. ☐ **Curadores assinam chains v4** — após receberem áudio Vitor
5. ☐ **Phase 2 Ângelina** — 4 material fixes + Anexo Técnico (sessão futura)
6. ☐ **Audit Manual R2 + R3** quando R3 for promovido — verificar terminologia
7. ☐ **Issue #1 verificação** — search "Política Institucional" nos 5 docs (próximo passo abaixo)

---

## 6. Verificações remanescentes (executar em SQL)

```sql
-- Issue #1: search "Política Institucional" como string em docs (deve aparecer 0 vezes pós Q4)
SELECT gd.title, position('Política Institucional' in dv.content_html) > 0 AS has_str
FROM governance_documents gd
JOIN document_versions dv ON dv.id = gd.current_version_id
WHERE gd.id IN ('cfb15185...', '280c2c56...', 'd2b7782c...', '41de16e2...', 'cd170c37...');

-- Audit Manual R2/R3 — verificar termos antigos
SELECT gd.title, position('Termo de Compromisso' in dv.content_html) > 0 AS has_termo_old
FROM governance_documents gd
JOIN document_versions dv ON dv.id = gd.current_version_id
WHERE gd.id IN ('7a8d47a1...', '98c4551f...');
```
