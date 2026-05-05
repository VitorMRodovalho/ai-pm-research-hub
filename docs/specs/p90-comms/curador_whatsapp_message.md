# Mensagem WhatsApp para grupo curadoria — Round 6 completo (Editorial + Material + Anexo Técnico)

**Para enviar Vitor → Sarah + Roberto + Fabricio (grupo curadoria)**
**Sugestão: enviar como áudio explicativo + sumário escrito anexo**
**Status:** Phase 1 (editorial) + Phase 1.5 (cross-refs patch) + Phase 2 (material fixes + 6º doc Anexo Técnico) — todas aplicadas 2026-05-04 / 2026-05-05

---

## Versão áudio (para Vitor narrar — script sugerido)

> Pessoal, atualização das nossas chains v3 governance — saímos de v3 para versões finais (v6 nos principais), incluindo tanto correções editoriais quanto material fixes, e criamos um 6º documento. Vou contextualizar.
>
> **Onde isso começou:** o Ricardo Santos, pesquisador do Núcleo (pesquisador com patentes próprias), enviou uma análise crítica dos documentos enviados — ele revisou Política IP e Termo de Voluntariado e apontou 8 pontos. 5 são correção factual / nomenclatura, e 3 envolvem mudança material que afeta direitos ou estrutura. Plus, o Ivan mencionou na conversa de ontem que a Ângelina, advogada voluntária do PMI-GO há uns 2 anos, vai topar fazer revisão jurídica dos docs.
>
> **A decisão estratégica que tomei:** em vez de mandar pra Ângelina os docs Round 5 atuais e ela ficar fazendo remendo, fiz toda a análise crítica + verificação de fato/dado de cada ponto do Ricardo, redigi os textos novos com trailback documentado, e apliquei. Assim a Ângelina recebe texto pronto pra validar — não pra reescrever. E vocês também recebem versões finais sem precisar revisar intermediárias.
>
> **O que mudou em cada documento:**
>
> **1. Correções factuais e de nomenclatura (todas verificadas)**
>
> - Renomeei "Termo de Compromisso" para "Termo de Adesão ao Serviço Voluntário" — Lei 9.608/1998 usa exatamente essa expressão "termo de adesão". Apliquei em todos os docs onde aparecia (cerca de 11 ocorrências em 4 docs).
> - Corrigi um typo legal grave: estava "Lei 14.063/2021" — o correto é "Lei 14.063/2020" (assinaturas eletrônicas). Aproveitei e adicionei a MP 2.200-2/2001 que é a base de ICP-Brasil para contratos privados.
> - Tirei o termo "fair use" da Política — fair use é direito americano. No Brasil aplicamos art. 46 da Lei 9.610/1998 (LDA), que era inclusive o que já estava lá; o "fair use" tava só duplicando.
> - Renomeei o título da Política para "Política de Governança de Propriedade Intelectual" — "governança" é mais preciso pelo escopo atual; "publicação" sozinho não captura tudo que tá no doc.
> - Simplifiquei a seção tributária da Política. Tirei o detalhamento de alíquotas IRRF, faixas, lista de tratados CDT — porque essas regras mudam ano a ano e o time financeiro do PMI-GO ou do capítulo é quem deve verificar caso a caso na hora do pagamento. Ficou só a regra-mãe: "pagamentos observam a legislação tributária federal vigente na data do pagamento". Política mais enxuta e durável.
> - Expandi o glossário com 12 termos novos que estavam aparecendo no doc sem definição: SCC, Adequação, CDT, Beneficial owner, Standby, Aceite expresso vs tácito, Direitos morais vs patrimoniais, Coautoria, Obra sensível, Período de graça INPI. Agora tem definição inline para os voluntários sem precisar buscar fora do doc.
>
> **2. Mudanças materiais — endereçando os pontos do Ricardo com cuidado**
>
> - Refatorei a cláusula de aceite tácito no Termo §15.4 e no Adendo Retificativo §3º. O Ricardo apontou que aceite tácito blanket pra "revisão" é sensível em contrato de adesão (CC art. 111 + 423 — favor aderente). Agora distinguimos explicitamente: aceite tácito aplica APENAS a Editorial change, e Material change exige aceite expresso do voluntário. Em ambiguidade, prevalece interpretação favorável ao voluntário. Isso não muda nosso framework Material/Editorial change que já existe nas Cláusulas 12.2 e 12.3 — só explicita que aceite tácito não cobre material.
> - Refatorei a seção de transferência internacional de dados na Política IP para 3 regimes separados — Brasil + UE/EEE + UK + demais jurisdições. O Ricardo apontou que o art. 49 do GDPR não deve ser solução padrão para fluxo rotineiro (orientação EDPB) e que a situação UE-UK é diferente. Texto está future-proof: cobre cenário com OU sem decisão de adequação Brasil-UE — Ângelina vai verificar status atualizado via ANPD e Comissão Europeia.
> - Movi a cláusula da plataforma operacional pra um documento separado novo. O Ricardo apontou que misturar PI das obras dos voluntários com PI da plataforma como ferramenta de software gera confusão interpretativa. Mais sobre isso no item 3.
> - Adicionei uma Cláusula 16 nova na Política — Disclaimer de Marcas e Identidade Institucional. Reconhece explicitamente que "PMI®", "PMI Goiás Chapter", etc são propriedade exclusiva do PMI Global, e o Núcleo é iniciativa de capítulo (não direta PMI Global), em conformidade com Chapter Operating Guidelines. Isso fecha o flank de risco de uso da marca, que era um RED FLAG do Ricardo. Ângelina vai validar se Chapter Operating Guidelines requer autorização adicional.
> - Adicionei uma Cláusula 12 nova no Acordo de Cooperação Bilateral — Cooperação com Entidades Externas e Subsidiárias PMI Global. Isso permite a gente formalizar parceria com PMOGA, ICTs como FioCruz/CEIA-UFG/IFG, AIPM Ambassadors, sem precisar amend o Acordo Bilateral cada vez. As 5 partnership prospects que estão no nosso pipeline ficam cobertas.
>
> **3. Documento NOVO — o sexto doc**
>
> Criei um Anexo Técnico — Plataforma Operacional do Núcleo IA & GP. Tem 8 seções: propósito, identificação técnica da plataforma, titularidade e autoria, conflito de interesse declarado, uso pelo Núcleo, continuidade e migração, futura exploração comercial, e disposições finais. Ele captura claramente que a plataforma é meu projeto pessoal opensource desde dia zero (auto-licenciado no meu GitHub), que outros contribuidores futuros adquirem coautoria sobre suas contribuições nos termos da Lei 9.610 art. 15, que o conflito de interesse está declarado com mecanismo de recusal, e que existe possibilidade futura de exploração comercial conjunta Núcleo + autor sob negociação institucional. Isso fica explicado em um lugar só, em vez de espalhado pelos cinco docs principais. O Adendo de PI aos Acordos de Cooperação no Art. 8 agora é só um cross-ref pra esse Anexo Técnico.
>
> **4. Cross-refs alinhados em tudo**
>
> Aproveitei pra alinhar nomenclatura: "Política de Publicação" antiga foi atualizada pra "Política de Governança" em todos os cross-refs textuais (eram cerca de 31 ocorrências em 6 docs). E corrigi também um typo do REPLACE inicial onde "Termo de Adesão ao Serviço Voluntário" tava aparecendo como "Termo de Adesão ao Serviço Voluntário de Voluntário" em alguns lugares (9 ocorrências corrigidas).
>
> **5. O que vocês recebem agora**
>
> Vocês podem revisar diretamente as **versões finais** das chains:
> - Política de Governança de PI — v6
> - Termo de Adesão ao Serviço Voluntário — v6
> - Adendo Retificativo — v6
> - Adendo de PI aos Acordos de Cooperação — v5
> - Acordo de Cooperação Bilateral — v5
> - Anexo Técnico — Plataforma Operacional — v1 (NOVO)
>
> Não precisam revisar v4 ou v5 intermediárias — vão direto na atual current_version_id de cada chain.
>
> **6. O que ainda depende da Ângelina**
>
> Identifiquei 4 pontos específicos que precisam de verificação primária dela, com fontes oficiais (ANPD, EU Commission, ICO, PMI Global):
> 1. Status atualizado da decisão de adequacy Brasil ↔ UE/EEE
> 2. Versão atual do UK Addendum / IDTA via ICO
> 3. Chapter Operating Guidelines do PMI Global sobre uso de marca
> 4. Existência de instrumento institucional PMOGA para parcerias com capítulos PMI
>
> O texto que apliquei é future-proof onde tem incerteza factual — funciona com ou sem mudança nesses pontos.
>
> **7. Trailback documentado**
>
> Cada mudança tem trailback no spec doc — fonte da crítica, verificação de fato, texto antes / texto depois, rationale. Tudo em `docs/specs/p90-comms/round6_material_fixes_proposed_text_with_trailback.md` no repo. Se quiserem ver diff exato de qualquer item, é só me chamar.
>
> Mais alguma dúvida ou se identificarem algo nos docs, joguem aqui no grupo. Pretendo enviar pra Ângelina ainda hoje / amanhã pelo canal que o Ivan abrir, e quando ela validar a gente fecha pra circulação aos 15 capítulos.
>
> Abraço!

---

## Sumário escrito (para anexar à mensagem se quiser)

**Round 6 — Phase 1 + Phase 1.5 + Phase 2 aplicadas 2026-05-04 / 2026-05-05**

### Versões finais (todas LOCKED + current_version_id)

| Doc | Versão final |
|---|---|
| Política de Governança de Propriedade Intelectual | **v6** (`v2.6-p90c-material-fixes`) |
| Termo de Adesão ao Serviço Voluntário | **v6** (`R3-C3-IP v2.6-p90c-material-fixes`) |
| Adendo Retificativo ao Termo de Adesão ao Serviço Voluntário | **v6** (`v2.6-p90c-material-fixes`) |
| Adendo de Propriedade Intelectual aos Acordos de Cooperação | **v5** (`v2.5-p90c-material-fixes`) |
| Acordo de Cooperação Bilateral — Template Unificado | **v5** (`v1.4-p90c-material-fixes`) |
| **Anexo Técnico — Plataforma Operacional do Núcleo IA & GP** ⭐ NOVO | **v1** (`v1.0-p90c-anexo-tecnico-creation`) |

### Mudanças aplicadas (verificadas via Supabase + trailback documentado)

**Editorial / Nomenclatura (5 fixes — não alteram direitos)**
1. "Termo de Compromisso" → "Termo de Adesão ao Serviço Voluntário" (Lei 9.608/1998 art. 2)
2. "Lei 14.063/2021" → "Lei 14.063/2020 + MP 2.200-2/2001" (typo legal corrigido + ICP-Brasil)
3. "art. 46 Lei 9.610 + fair use" → "art. 46 da Lei nº 9.610/1998" (drop terminologia EUA)
4. Título Política → "Política de Governança de PI" (decisão Vitor)
5. Tributária §4.5(e) detalhado → regra-mãe simples (time financeiro caso a caso)
6. Glossário §13.4 expandido com 12 termos novos + Material/Editorial change definitions completas

**Cross-refs patch (Phase 1.5)**
- 31 ocorrências "Política de Publicação" textuais → "Política de Governança" (em 6 docs)
- 9 ocorrências typo "Termo de Adesão ao Serviço Voluntário de Voluntário" → "Termo de Adesão ao Serviço Voluntário"
- H2 self-ref headers atualizados em Política e Termo

**Material fixes (5 — texto pronto para validação Ângelina)**

| Fix | Aplicado em | Trailback |
|---|---|---|
| **M1** Aceite tácito refactor (Editorial=tácito; Material=expresso; ambiguidade=favor aderente) | Termo §15.4 + Adendo Retificativo §3º | CC art. 111 + 423 + ADR-0068 framework |
| **M2** LGPD §2.5.5 — 3 regimes (BR / UE-EEE / UK / demais) future-proof | Política IP | GDPR arts. 45-46-49 + Decisão (UE) 2021/914 + LGPD arts. 33-36 + EDPB Guidelines 2/2018 |
| **M3** Cláusula plataforma → Anexo Técnico (Art. 8 simplificado) | Adendo PI Cooperação Art 8 + 6º doc NOVO | Lei 9.610/1998 art. 15 (coautoria) |
| **M4** Disclaimer Marca PMI® + Identidade Institucional (NOVA Cláusula 16) | Política IP | Chapter Operating Guidelines PMI Global |
| **M5** Cooperação com Entidades Externas e Subsidiárias PMI Global (NOVA Cláusula 12) | Acordo Cooperação Bilateral | Lei 10.973/2004 (Inovação) + framework PMOGA + AIPM |

### 4 pendências verificação primária Ângelina

1. Status adequacy decision Brasil ↔ UE/EEE — via ANPD + EU Commission
2. UK Addendum / IDTA versão atual — via ICO
3. Chapter Operating Guidelines PMI Global — uso de marca por iniciativas inter-capítulos
4. PMOGA — instrumento institucional para parcerias com capítulos PMI

### Audit log
- 14 entries `governance.*_p90/p90b/p90c` registrando todas as mudanças
- Migrations registradas em `schema_migrations` (4 migrations)
- Local files em `supabase/migrations/`

### URL para review na plataforma
https://nucleoia.vitormr.dev/governance/[doc-slug]

### Spec doc completo (trailback + texto antes/depois + rationale)
`docs/specs/p90-comms/round6_material_fixes_proposed_text_with_trailback.md`
