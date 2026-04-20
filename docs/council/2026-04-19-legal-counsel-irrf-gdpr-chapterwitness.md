# Parecer Jurídico Complementar — IRRF + GDPR + Chapter Witness

**CR-050 | Núcleo IA & GP | 19/04/2026 (sessão p34)**

Legal-counsel (AI) complementar ao parecer p30 (v2.1 completo) e p34 (template cooperação v1.1). Endereça 3 red flags pré-circulação ao Ivan Lourenço.

## Resumo Executivo

Endereça: (1) clausulado IRRF robusto para Política §4.5.4(e) — 8 sub-alíneas com base legal completa, tabela progressiva 2026, alíquotas exterior, CDTs e DIRF/e-Reinf; (2) clausulado GDPR completo para Política §2.5 — 9 sub-seções cobrindo escopo (EEE + UK), controlador/DPO, base legal, rights art. 15-22, transferência via SCCs/consent/contratual, retention, breach 72h, representante UE; (3) decisão chapter_witness: **Opção 3c** (obrigatório com grace period 60 dias).

## Peças aplicadas ao DB (19/04/2026 p34)

- **Peça 1 — §4.5.4(e) IRRF**: aplicado via migration `20260503120001_ip3d_politica_pi_rf2_irrf_upgrade` (UPDATE em `document_versions.id = e3513c94-4351-4616-b13d-f2c0f9b645aa`). Conteúdo: 8 sub-alíneas substituindo (e.1)-(e.4) condensado.

- **Peça 2 — §2.5 GDPR**: aplicado via migration `20260503120000_ip3d_politica_pi_rf2_gdpr_upgrade`. Conteúdo: 9 sub-seções substituindo §2.5.1-7 condensado.

- **Peça 3 — Chapter Witness (Opção 3c)**: aplicado via migration `20260503120002_ip3d_template_chapter_witness_3c_grace_period` (UPDATE em `document_versions.id = 16e07e92` — Template Unificado v1.1). Adicionada nota de grace period 60 dias.

## Red Flags residuais (RF-A a RF-F)

- **RF-A — CDT Alemanha (Dec. 76.988/1976): alíquota 10% ou 15% conforme classificação.** Frameworks metodológicos podem ser "uso literário" (15%) ou "know-how/assistência técnica" (alíquota diferente). Consulta jurídico-fiscal antes primeiro pagamento a beneficiário alemão.

- **RF-B — SCCs não auto-executáveis.** Adendo Técnico (Annex I/II/III da Decisão 2021/914) precisa ser assinado por cada voluntário EEE. Recomendação pragmática: invocar consentimento art. 49(1)(a) para programa atual (ocasional, <50 voluntários EEE), migrar para SCCs quando escalar.

- **RF-C — UK pós-Brexit.** UK GDPR tem IDTAs próprios. SCCs UE não são válidas para BR→UK. Adendo Técnico precisa incluir IDTAs britânicas ou SCCs Addendum for UK.

- **RF-D — DIRF sendo substituída por e-Reinf (2024-2025).** Texto da Política usa formulação aberta que protege ("ou instrução normativa vigente"), mas departamento fiscal PMI-GO deve confirmar instrumento vigente antes primeiro pagamento.

- **RF-E — DPA formal entre PMI-GO e plataforma nucleoia.vitormr.dev.** RGPD Art. 28 exige contrato escrito controlador↔operador. Prioridade média: resolver antes de onboardar voluntários EEE formalmente.

- **RF-F — Migration IP-3c precisa implementar grace period.** `_can_sign_gate` chapter_witness deve verificar `cooperation_agreement.signed_at + 60d > now()` como bypass condicional. Encaminhar para IP-3d follow-up ou IP-4.

## Recomendação operacional

Antes de qualquer pagamento de royalties: consulta tributária (RF-A).
Antes de onboardar primeiro voluntário EEE formalmente: formalizar DPA + Adendo Técnico SCCs ou colher consentimento explícito renovável (RF-B, RF-E).
Antes de lacrar template cooperação v1.1 com real signatário: implementar migration grace period IP-3c (RF-F).

---

*Parecer para revisão inicial; confirmação com advogado licenciado recomendada antes de ratificação. Para RF-A/B/D consulta adicional com especialista tributário e advogado europeu de proteção de dados.*
