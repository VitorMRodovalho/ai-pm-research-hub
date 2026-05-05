# Brief Ângelina — Validação Final Round 6 (docs PRONTOS para validação)

**Status mudança 2026-05-05:** Vitor decidiu não esperar Ângelina para aplicar texto — todas as mudanças críticas + material fixes foram aplicadas com trailback documentado, entregando docs **prontos para validação** (não remendos).

**Spec mestre com trailback completo:** `docs/specs/p90-comms/round6_material_fixes_proposed_text_with_trailback.md`

---

## Mensagem inicial atualizada para Vitor enviar à Ângelina

> Olá Ângelina, tudo bem?
>
> Falou com você o Ivan sobre o Núcleo IA & GP, certo? Sou Vitor Maia, GP do programa. O Ivan comentou que você é advogada voluntária do PMI-GO há uns dois anos e topa nos ajudar com uma revisão jurídica dos nossos documentos de governança.
>
> Primeiro: muito obrigado por topar! Sua ajuda nesse momento faz muita diferença. Eu sei que o timing pode ser apertado pra você, então vamos no seu ritmo — o que importa é qualidade da revisão.
>
> Recebi do Ricardo Santos (pesquisador do Núcleo, com patentes próprias) uma análise crítica de 8 pontos. Trabalhamos para que você receba os documentos **prontos para validar** — não remendar de novo. Já apliquei todas as correções sugeridas com trailback documentado de cada decisão.
>
> Você vai validar **6 documentos governance**:
>
> 1. **Política de Governança de Propriedade Intelectual** (v6) — antes "Política de Publicação e PI"
> 2. **Termo de Adesão ao Serviço Voluntário** (v6) — antes "Termo de Compromisso"
> 3. **Adendo Retificativo ao Termo de Adesão ao Serviço Voluntário** (v6)
> 4. **Adendo de Propriedade Intelectual aos Acordos de Cooperação** (v5)
> 5. **Acordo de Cooperação Bilateral — Template Unificado** (v5)
> 6. **Anexo Técnico — Plataforma Operacional do Núcleo IA & GP** (v1) ⭐ NOVO
>
> Plus o spec doc detalhado com **trailback completo** mostrando, para cada mudança:
> - Fonte da crítica/sugestão
> - Verificação de fato/dado (com URLs primárias)
> - Texto antes vs texto depois
> - Rationale + cross-refs
> - Pendências que precisam da sua verificação primária (4 itens)
>
> Posso te enviar:
> - Os 6 documentos v atual em PDF/HTML/Word (escolha sua preferência)
> - Spec doc com trailback (markdown)
> - A análise crítica original do Ricardo Santos (3 páginas)
>
> **4 pendências específicas** que precisam de verificação primária por você:
>
> 1. **Status atualizado da decisão de adequacy Brasil ↔ UE/EEE** — A Comissão Europeia e a ANPD podem ter adotado decisão recíproca de adequação em janeiro/2026 conforme apontado pelo Ricardo. Aplicamos texto **future-proof** que cobre os dois cenários (com ou sem adequacy), mas precisamos da sua verificação primária via:
>    - ANPD: https://www.gov.br/anpd
>    - Comissão Europeia: https://commission.europa.eu/law/law-topic/data-protection/international-dimension-data-protection_en
>
> 2. **UK Addendum / IDTA versão atual** — Aplicamos referência ao IDTA + UK Addendum em vigor desde 21/março/2022. Confirmar versão atual via Information Commissioner's Office:
>    - ICO: https://ico.org.uk
>
> 3. **Chapter Operating Guidelines do PMI Global** — Cláusula 16 da Política referencia conformidade com Chapter Operating Guidelines. Verificar se há cláusula específica sobre uso de marca PMI® por iniciativas inter-capítulos como o Núcleo. Se PMI Global requer autorização formal além do endorsement do PMI-GO como Chapter Sponsor, ajustamos.
>
> 4. **PMOGA — instrumento institucional** — Cláusula 12 do Acordo de Cooperação Bilateral abre possibilidade de cooperação com PMO Global Alliance (PMOGA, hoje subsidiária PMI Global em pmoga.pmi.org). Verificar se PMOGA tem framework próprio para parcerias com iniciativas de capítulos PMI ou se relaciona via Chapter Sponsor.
>
> Que canal você prefere para revisar? PDF anotável, Google Docs com comentários, ou outra opção?
>
> Avisa qualquer coisa e fico no aguardo.
>
> Abraço!

---

## Estado final dos 6 docs em production (todos LOCKED current)

| # | Doc | Versão | doc_type | Status | Length |
|---|---|---|---|---|---|
| 1 | Política de Governança de PI | **v2.6-p90c-material-fixes** | policy | under_review | 38.7K chars |
| 2 | Termo de Adesão ao Serviço Voluntário | **R3-C3-IP v2.6-p90c-material-fixes** | volunteer_term_template | under_review | 17.9K chars |
| 3 | Adendo Retificativo | **v2.6-p90c-material-fixes** | volunteer_addendum | under_review | 17.8K chars |
| 4 | Adendo PI aos Acordos de Cooperação | **v2.5-p90c-material-fixes** | cooperation_addendum | under_review | 14.8K chars |
| 5 | Acordo de Cooperação Bilateral | **v1.4-p90c-material-fixes** | cooperation_agreement | under_review | 31.0K chars |
| 6 | **Anexo Técnico — Plataforma Operacional** ⭐ NOVO | **v1.0-p90c-anexo-tecnico-creation** | framework_reference | under_review | 9.6K chars |

## Resumo das mudanças aplicadas (M1-M5)

### M1 — Aceite tácito framework (CC art. 111 + 423)
**Aplicado em:** Termo §15.4 + Adendo Retificativo §3º
**Mudança:** Aceite tácito reservado a Editorial change; Material change exige aceite expresso; ambiguidade → favor aderente.
**Trailback:** Ricardo Santos #2 + CC art. 111 + 423 + ADR-0068 framework

### M2 — Transferência internacional 3 regimes
**Aplicado em:** Política IP §2.5.5
**Mudança:** Brasil + UE/EEE + UK + demais jurisdições + voluntários estrangeiros + atualização normativa. Future-proof. Art. 49 GDPR não como solução padrão (EDPB Guidelines 2/2018).
**Trailback:** Ricardo Santos #3 + GDPR arts. 45-46-49 + Decisão (UE) 2021/914 + UK GDPR/ICO IDTA + LGPD arts. 33-36 + EDPB Guidelines 2/2018

### M3 — Cláusula plataforma → Anexo Técnico
**Aplicado em:** Adendo PI Cooperação Art 8 (simplificado para thin cross-ref) + Anexo Técnico v1 NOVO
**Mudança:** Tema centralizado em novo doc Anexo Técnico (8 seções) + cláusula original no Adendo PI Cooperação reduzida a thin cross-ref.
**Trailback:** Ricardo Santos #8 + clarification Vitor 2026-05-04 (opensource self-licensed + futura exploração comercial conjunta) + Lei 9.610/1998 art. 15 (coautoria)

### M4 — Disclaimer Marca PMI® + Identidade Institucional
**Aplicado em:** Política IP nova Cláusula 16
**Mudança:** Reconhecimento explícito PMI® como propriedade PMI Global; status Núcleo como iniciativa de capítulo (não direta PMI Global); compliance Chapter Operating Guidelines; branding rules; distinguir marcas PMI vs marcas/frameworks Núcleo.
**Trailback:** Ricardo Santos RED FLAG #2c + sediment incident CBGPL Vargas + memory feedback_pmi_brand_canonical

### M5 — Cooperação com Entidades Externas e Subsidiárias PMI Global
**Aplicado em:** Acordo de Cooperação Bilateral nova Cláusula 12
**Mudança:** Permite cooperation expandida com (a) entidades-PMI Global (PMOGA), (b) ICTs Lei 10.973/2004, (c) outras associações/comunidades técnicas (AIPM, AI.Brasil, etc) sem precisar amend Acordo Bilateral.
**Trailback:** Vitor 2026-05-05 pergunta sobre PMO-GA + memory project_nucleo_strategic_direction (PMOGA acquired by PMI) + 5 prospect partnerships (FioCruz, AI.Brasil, CEIA-UFG, IFG, PMO-GA)

## Migrations chain p90 → p90.c

```
20260516500000  p90    Round 6 editorial hotfix (5 fixes)
20260516500001  p90.b  Cross-refs patch (Política Publicação→Governança + de Voluntário typo)
20260516500002  p90.c  Anexo Técnico Plataforma creation (NEW 6th doc)
20260516500003  p90.c  Material fixes v6 (M1+M2+M3+M4+M5)
```

## Audit log entries
- 4 entries `governance.editorial_hotfix_p90` (initial editorial)
- 5 entries `governance.editorial_patch_p90b_cross_refs` (cross-ref patch)
- 1 entry `governance.anexo_tecnico_created_p90c` (new doc creation)
- 5 entries `governance.material_fixes_p90c` (material fixes batch)

## Verificação final (smoke check)

✅ Todos os 5 docs governance + 1 Anexo Técnico em status `under_review` com current_version_id atualizado
✅ Zero residuals de termos antigos (Termo de Compromisso, fair use, Lei 14.063/2021, Política de Publicação old, "de Voluntário" typo)
✅ Zero residuals de cláusulas substituídas (aceite tácito old, art 49 old phrasing, Art 8 4-§s old)
✅ Todas as 5 fixes M1-M5 verificadas presentes nos docs corretos
✅ Anexo Técnico v1 LOCKED com 9.5K chars de conteúdo em 8 seções
✅ Migrations registered em `schema_migrations`
✅ Local migration files salvos em `supabase/migrations/`
✅ Audit log tracking integral

## Materiais que Vitor deve enviar

1. ☐ **Spec doc trailback** (`docs/specs/p90-comms/round6_material_fixes_proposed_text_with_trailback.md`)
2. ☐ **Audit anti-alucinação + checklist** (`docs/specs/p90-comms/audit_anti_alucinacao_e_checklist_coerencia.md`)
3. ☐ **6 docs governance** em formato escolhido por Ângelina (PDF/HTML/Word)
4. ☐ **Análise crítica Ricardo Santos** original (`/home/vitormrodovalho/Downloads/A/Análise crítica dos documentos enviados.docx`)
5. ☐ **Drafts simplificados Ricardo** (referência opcional para Ângelina)

## Pós-validação Ângelina

1. Se Ângelina aprovar tudo → solicitar curadores assinarem v6 (Sarah/Roberto/Fabricio) + circular para 15 capítulos via pontos focais
2. Se Ângelina propor ajustes em algum dos 4 pontos pendentes → aplicar via v7 + audit
3. Se Ângelina propor mudanças adicionais → discutir + decidir Material vs Editorial change framework
