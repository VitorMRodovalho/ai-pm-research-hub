# Round 6 Material Fixes — Análise Crítica com Trailback + Texto Proposto

**Sessão:** p90.c (2026-05-04 → 2026-05-05)
**Trigger:** Vitor decision 2026-05-05 — não esperar Ângelina; aplicar todas as mudanças com trailback + confirmação fato/dado, entregando docs PRONTOS para validação (não remendos).
**Spec mestre:** `docs/specs/p90-round-6-editorial-material-fixes-matrix.md`
**Migration:** `20260516500002_p90c_round6_material_fixes_plus_anexo_tecnico.sql`

Este documento apresenta, para cada material fix:
1. **Trailback** — fonte da crítica/sugestão
2. **Verificação de fato/dado** — checagem com base em conhecimento + flag de itens que requerem verificação primária
3. **Texto atual** (snapshot pré-fix)
4. **Texto proposto** (post-fix)
5. **Rationale + cross-refs**

---

## M1 — Aceite tácito framework (CC favor aderente)

### Trailback
**Fonte:** Ricardo Santos análise crítica, item #2:
> "Em contrato de adesão, a combinação de remissão dinâmica, mudança posterior de obrigações e aceite tácito é sensível. O Código Civil diz que o silêncio só importa anuência quando as circunstâncias autorizarem (art. 111), e cláusulas ambíguas em contrato de adesão devem ser interpretadas em favor do aderente."
> 
> **Recomendação Ricardo:** "manter atualização automática apenas para mudanças editoriais; para mudanças materiais de PI, dados, sanções e uso de obras, exigir aceite expresso."

### Verificação de fato/dado
- ✅ **CC art. 111** (Lei 10.406/2002): "O silêncio importa anuência, quando as circunstâncias ou os usos o autorizarem, e não for necessária a declaração de vontade expressa." — Real, vigente.
- ✅ **CC art. 423**: "Quando houver no contrato de adesão cláusulas ambíguas ou contraditórias, dever-se-á adotar a interpretação mais favorável ao aderente." — Real, vigente.
- ✅ **ADR-0068 Material vs Editorial change framework** — já existe na Política Cláusulas 12.2 e 12.3.

### Texto atual (Termo §15.4 + Adendo Retificativo §3º — espelhados)

```html
15.4 Aceite tácito por ato concludente. A continuidade da participação ativa no Programa após o decurso dos prazos estabelecidos em 15.3 sem manifestação contrária constitui aceite tácito da revisão, nos termos do art. 111 do Código Civil Brasileiro (Lei nº 10.406/2002).
```

**Issue:** "revisão" sem distinguir Editorial vs Material change. Aceite tácito blanket viola CC art. 423 ↔ favor aderente em contrato de adesão.

### Texto proposto (Termo §15.4)

```html
<p><strong>15.4 Aceite tácito por ato concludente — limites e aplicação.</strong></p>
<p><strong>(a) Aceite tácito aplicável apenas a Editorial change.</strong> A continuidade da participação ativa no Programa após o decurso dos prazos estabelecidos em 15.3 sem manifestação contrária do(a) VOLUNTÁRIO(A) constitui aceite tácito de Editorial change, conforme definição da Cláusula 12.3 da Política de Governança de Propriedade Intelectual, nos termos do art. 111 do Código Civil Brasileiro (Lei nº 10.406/2002).</p>
<p><strong>(b) Aceite expresso obrigatório para Material change.</strong> Material change, conforme definição da Cláusula 12.2 da Política de Governança de Propriedade Intelectual — alteração que afete direitos, deveres, sanções, uso das obras ou regras de dados pessoais — exige aceite expresso (assinatura eletrônica ou clique de aceite) do(a) VOLUNTÁRIO(A), na forma prevista na Cláusula 13. Sem aceite expresso, a versão anteriormente assinada permanece em vigor para o(a) VOLUNTÁRIO(A) até a manifestação expressa de aceite ou até a sua eventual saída do Programa.</p>
<p><strong>(c) Princípio interpretativo.</strong> Em caso de dúvida quanto à classificação de uma alteração como Editorial ou Material, prevalece a interpretação mais favorável ao(à) VOLUNTÁRIO(A), nos termos do art. 423 do Código Civil Brasileiro (cláusulas ambíguas em contrato de adesão).</p>
```

### Texto proposto (Adendo Retificativo §3º) — paralelo ao Termo

```html
<p><strong>§ 3º Aceite tácito por ato concludente — limites e aplicação.</strong></p>
<p><strong>(a) Aceite tácito aplicável apenas a Editorial change.</strong> A continuidade da participação ativa no Programa após o decurso dos prazos estabelecidos no § 2º sem manifestação contrária do(a) VOLUNTÁRIO(A) constitui aceite tácito de Editorial change, conforme definição da Cláusula 12.3 da Política de Governança de Propriedade Intelectual, nos termos do art. 111 do Código Civil Brasileiro (Lei nº 10.406/2002).</p>
<p><strong>(b) Aceite expresso obrigatório para Material change.</strong> Material change, conforme definição da Cláusula 12.2 da Política de Governança de Propriedade Intelectual, exige aceite expresso do(a) VOLUNTÁRIO(A) na forma da Cláusula 13 do Termo de Adesão ao Serviço Voluntário. Sem aceite expresso, a versão anteriormente assinada permanece em vigor.</p>
<p><strong>(c) Princípio interpretativo.</strong> Em caso de dúvida quanto à classificação de uma alteração como Editorial ou Material, prevalece a interpretação mais favorável ao(à) VOLUNTÁRIO(A), nos termos do art. 423 do Código Civil Brasileiro.</p>
```

### Rationale
- Distingue 2 categorias com cross-ref interno (Cláusulas 12.2 + 12.3 da Política)
- Aceite tácito reservado a editorial (alinha com ADR-0068 framework)
- Aceite expresso para material (CC art. 423 favor aderente respeitado)
- Princípio interpretativo explícito favor aderente (cobertura art. 423)

---

## M2 — Transferência internacional de dados (LGPD §2.5.5 + §2.5.7)

### Trailback
**Fonte:** Ricardo Santos análise crítica, item #3:
> "A política afirma que o Brasil estava sem decisão de adequação para UE/EEE; o adendo pede consentimento expresso de residentes da UE com base no art. 49(1)(a) do GDPR. Isso ficou desatualizado em 2026. A Comissão Europeia e o Brasil adotaram decisões de adequação recíproca em janeiro de 2026. Já para o Reino Unido, a situação é diferente: a orientação atual do ICO ainda trata o Brasil como sem adequacy no regime UK GDPR."
> 
> **Recomendação Ricardo:** "separar três regimes: Brasil, UE/EEE e Reino Unido. Para UE/EEE, usar a base da adequação quando aplicável; para UK e outros países sem adequação, usar o mecanismo cabível do direito aplicável. Não usar consentimento do art. 49 como solução padrão para fluxo rotineiro."

### Verificação de fato/dado
- ✅ **GDPR Regulamento (UE) 2016/679** — Real, em vigor desde 25 de maio de 2018.
- ✅ **GDPR art. 45** (decisões de adequação) — Real.
- ✅ **GDPR art. 46** (salvaguardas para transferência internacional) — Real.
- ✅ **GDPR art. 49** (derrogações para situações específicas) — Real, mas Comissão Europeia e EDPB têm orientação específica de que **art. 49 não deve ser solução padrão para fluxo rotineiro** (EDPB Guidelines 2/2018). Ricardo está correto.
- ✅ **Decisão (UE) 2021/914** (novas SCCs / Standard Contractual Clauses) — Real, em vigor desde 27 de junho de 2021.
- ✅ **UK GDPR** independente do EU GDPR após Brexit, fiscalizado pelo Information Commissioner's Office (ICO) — Real.
- ✅ **International Data Transfer Agreement (IDTA)** + **UK Addendum to EU SCCs** — Real, mecanismos atuais ICO para transferência internacional (em vigor desde 21 março 2022).
- ✅ **LGPD Lei 13.709/2018, arts. 33-36** — transferência internacional de dados, base legal brasileira. Real, vigente.
- ✅ **ANPD** (Autoridade Nacional de Proteção de Dados) — autoridade fiscalizadora brasileira. Real.
- ⚠️ **Reciprocal adequacy decision Brasil ↔ UE/EEE em janeiro/2026** — afirmação de Ricardo. **Sem confirmação primária por mim**; ANPD e Comissão Europeia têm conduzido diálogos desde 2022, mas decisão formal pode estar em andamento OU já adotada — **PENDÊNCIA: Ângelina verifica via ANPD (https://www.gov.br/anpd) e Comissão Europeia (https://commission.europa.eu/law/law-topic/data-protection/international-dimension-data-protection_en) antes do lock final**. Por isso o texto proposto é **future-proof**: cobre ambos cenários sem afirmar com data específica.
- ✅ **EDPB Guidelines 2/2018** sobre derrogações art. 49 — Real, ainda vigente.
- ✅ **Transfer Impact Assessment (TIA)** — exigência pós-Schrems II, jurisprudência TJUE C-311/18 (julho/2020). Real.

### Texto atual (Política IP §2.5.5)

```html
2.5.5 Transferência internacional BR↔EEE. Brasil sem decisão de adequação (art. 45.º RGPD — verificado abr/2026). Salvaguardas aplicáveis: 
(i) Cláusulas Contratuais Padrão (SCCs) da Decisão (UE) 2021/914, como Adendo Técnico ao Termo de Voluntariado/Acordo, com Transfer Impact Assessment documentado — para transferências sistemáticas; 
(ii) consentimento explícito art. 49.º(1)(a), com ciência prévia dos riscos, renovável se condições materiais mudarem — para transferências ocasionais; 
(iii) necessidade contratual art. 49.º(1)(b), subsidiária para dados mínimos indispensáveis. 
O mecanismo vigente por voluntário é documentado no registro de atividades de tratamento (art. 30.º).
```

### Texto proposto (Política IP §2.5.5)

```html
<p><strong>2.5.5 Transferência internacional de dados pessoais — três regimes.</strong></p>
<p><strong>(a) Brasil → Brasil (fluxo doméstico).</strong> Tratamento doméstico de dados de titulares residentes no Brasil observa exclusivamente a LGPD (Lei nº 13.709/2018), sem aplicação direta de normas estrangeiras a este fluxo.</p>
<p><strong>(b) Brasil ↔ UE / EEE.</strong> Aplicam-se as decisões de adequação eventualmente vigentes na data da transferência, conforme verificação atualizada junto à Autoridade Nacional de Proteção de Dados (ANPD — <a href="https://www.gov.br/anpd">www.gov.br/anpd</a>) e à Comissão Europeia (<a href="https://commission.europa.eu/law/law-topic/data-protection/international-dimension-data-protection_en">commission.europa.eu</a>). Na ausência de decisão de adequação aplicável a determinado fluxo, são adotadas: (i) <strong>Cláusulas Contratuais Padrão</strong> da Decisão (UE) 2021/914 (SCCs de geração 2021), com Transfer Impact Assessment documentado, conforme art. 46.º do RGPD, para transferências sistemáticas; (ii) outra salvaguarda compatível com o art. 46.º do RGPD quando aplicável. As <strong>derrogações do art. 49.º</strong> do RGPD não são adotadas como solução padrão para fluxo rotineiro, conforme orientação do European Data Protection Board (EDPB Guidelines 2/2018), restringindo-se a situações específicas e ocasionais devidamente documentadas.</p>
<p><strong>(c) Brasil → Reino Unido (UK GDPR).</strong> Submete-se ao regime do UK GDPR sob fiscalização do Information Commissioner's Office (ICO — <a href="https://ico.org.uk">ico.org.uk</a>). Salvaguardas aplicáveis conforme orientação ICO vigente — atualmente International Data Transfer Agreement (IDTA) ou UK Addendum to EU SCCs, em vigor desde 21 de março de 2022 — verificadas junto ao ICO antes de cada transferência sistemática. Aplicam-se as mesmas restrições do item (b) ao uso de derrogações do UK GDPR.</p>
<p><strong>(d) Brasil → demais jurisdições.</strong> Aplicam-se as regras da LGPD para transferência internacional (arts. 33 a 36 da Lei nº 13.709/2018) com a salvaguarda cabível no direito aplicável da jurisdição de destino, observada a orientação atualizada da ANPD.</p>
<p><strong>(e) Voluntários residentes em jurisdição estrangeira ao Brasil.</strong> Quando o(a) VOLUNTÁRIO(A) reside em UE/EEE, Reino Unido ou outra jurisdição com regulamentação de dados pessoais aplicável a partir do território de residência, observa-se a base legal e mecanismo de transferência cabível conforme o regime correspondente, documentado em Registro de Atividades de Tratamento (art. 30.º RGPD ou equivalente).</p>
<p><strong>(f) Atualização normativa.</strong> Esta seção será revisada na ocorrência de mudança normativa relevante (decisão de adequação superveniente, novas SCCs, atualização do regime UK, alteração da LGPD), por meio de Material change ou Editorial change conforme classificação aplicável (Cláusulas 12.2 e 12.3).</p>
```

### Rationale
- **Future-proof:** cobre cenários com ou sem adequacy decision (não afirma fato com data específica)
- **3 regimes separados** (Ricardo OK) + 4º catch-all (demais jurisdições) + 5º regra residência voluntário
- **Art. 49 não é solução padrão** explícito (EDPB Guidelines 2/2018)
- **UK separado** (ICO + IDTA + UK Addendum) — Ricardo OK
- **Atualização normativa** explicitada — não engessa o texto

### Pendência verificação Ângelina
- ⚠️ Status atual da decisão de adequacy Brasil ↔ UE/EEE → confirmar via ANPD + Comissão Europeia primary sources
- ⚠️ Versão atual do UK Addendum / IDTA → confirmar via ICO

---

## M3 — Cláusula plataforma → Anexo Técnico (NOVO 6º DOC)

### Trailback
**Fonte:** Ricardo Santos análise crítica, item #8:
> "A cláusula sobre a plataforma pessoal do GP está deslocada [no termo do voluntário]. O adendo trata a plataforma operacional como projeto pessoal e independente do GP autor. Isso pode gerar desconfiança e confusão entre PI das obras do Núcleo e PI da plataforma."
> 
> **Recomendação Ricardo:** "mover esse tema para um anexo técnico separado ou para os termos de uso da plataforma. No termo do voluntário, basta dizer que a plataforma é ferramenta de gestão e que o uso dela não altera a titularidade das obras do voluntário nem do Núcleo."

**Fonte adicional Vitor 2026-05-04 (clarification de contexto):**
> "vou deixar a plataforma como parte do legado do Nucleo, mas desde o dia zero declarei opensource no meu github entao eu auto licensie desta forma, e futuramente podemos ter uma exploracao comercial fechando o opensource mas com o nucleo junto - outros contribuidores na plataforma ainda nao existem entao somente meu nome, mas la na frente com o amadurecimento do nucleo e entrada de outros membros talvez isto possa vir a mudar caso outros venham a contribuir para com o desenvolvimento e amadurecimento da plataforma"

### Verificação de fato/dado
- ✅ Plataforma "ai-pm-research-hub" em https://nucleoia.vitormr.dev — Real, sediada em ldrfrvwhxsmgaabwmaik.supabase.co (verificado via Supabase MCP)
- ✅ Repositório GitHub https://github.com/VitorMRodovalho/ai-pm-research-hub — citado no Adendo PI Cooperação Art 8 § 4º (verificado via Supabase content extract)
- ✅ Vitor Maia Rodovalho como GP único contribuidor atual — confirmado via memory + repository ownership
- ✅ Lei nº 9.610/1998 art. 15 (coautoria) — Real, vigente
- ✅ Código de Ética PMI® (Code of Ethics and Professional Conduct) — Real, política oficial PMI Global

### Solução estrutural
1. **Criar 6º doc governance** — `Anexo Técnico — Plataforma Operacional do Núcleo IA & GP` (doc_type=`framework_reference`)
2. **Conteúdo full** organizado em 8 seções (1. Propósito · 2. Identificação · 3. Titularidade e Autoria · 4. CoI Declarado · 5. Uso pelo Núcleo · 6. Continuidade e Migração · 7. Futura Exploração Comercial · 8. Disposições Finais)
3. **Adendo PI Cooperação Art 8 simplificado** para thin cross-ref ao Anexo
4. **Política IP Cláusula 15.2 cross-ref** atualizada
5. **Termo, Adendo Retificativo, Acordo Coop Bilateral** mantêm cross-refs (não precisam mudar texto)

### Texto proposto — Adendo PI Cooperação Art 8 (simplificação)

```html
<h3>Art. 8 — Plataforma operacional do Núcleo</h3>
<p>A plataforma operacional do Núcleo IA &amp; GP, suas regras de titularidade, autoria, conflito de interesse, uso, continuidade e eventual exploração comercial são integralmente regidas pelo <strong>Anexo Técnico — Plataforma Operacional do Núcleo IA &amp; GP</strong>, que integra este Adendo por remissão dinâmica e prevalece sobre interpretações divergentes a respeito da plataforma como ativo de software distinto das obras intelectuais produzidas no âmbito do Programa.</p>
```

### Conteúdo completo do Anexo Técnico

**Aplicado via migration v6 — ver migration `20260516500002_p90c_round6_material_fixes_plus_anexo_tecnico.sql` ou doc atualizado em DB pós-aplicação.**

Estrutura:
1. **Propósito deste Anexo** — distingue PI das obras vs PI da plataforma
2. **Identificação da Plataforma** — denominação + repositório + licença
3. **Titularidade e Autoria** — Vitor único atual; co-autoria futura (Lei 9.610 art. 15)
4. **Conflito de Interesse Declarado** — recusal automático + transparência + auditoria
5. **Uso pelo Núcleo e Capítulos Signatários** — natureza opensource + não-altera-titularidade-obras
6. **Continuidade e Migração** — opção de migração + independência plataforma
7. **Futura Exploração Comercial** — possibilidade + gatilhos + princípios
8. **Disposições Finais** — vigência + atualização + cross-references

### Rationale
- **Separação clara** entre PI das obras (Política) e PI da plataforma (Anexo)
- **Endereça crítica Ricardo #8** sobre cláusula deslocada
- **Captura clarification Vitor 2026-05-04** sobre opensource + futura exploração comercial conjunta
- **Versionamento independente** (Anexo evolve sem precisar amend Política/Termo)
- **Audit trail formal** via document_versions

---

## M4 — Disclaimer Marca PMI® (RED FLAG #2c — estrutural, independente Round 6)

### Trailback
**Fonte 1:** Ricardo Santos análise crítica, RED FLAG #2c (interno-Vitor sumário):
> "marca PMI® third-party — Núcleo usa 'PMI®' branding mas não tem legal status PMI Brasil/Global = risco third-party trademark dispute"

**Fonte 2:** Sediment incident CBGPL 2026-04-29 — Ricardo Vargas usou "ação do PMI" sem citar capítulos; slide com logo PMI-GO antiga; Natália Tavares (PMI Latam) reagiu positivamente, querendo INTEGRAR (não competir).

**Fonte 3:** Memory `feedback_pmi_brand_canonical.md` + `feedback_pmi_brand_at_cbgpl_natalia_signal.md`.

### Verificação de fato/dado
- ✅ **PMI® (Project Management Institute, Inc.)** — entidade jurídica registrada nos EUA; sede Newtown Square, Pennsylvania. Real.
- ✅ **PMI® é marca registrada** com proteção internacional (USPTO + WIPO Madrid System). Real.
- ✅ **PMP®, CPMAI™, PMI Goiás Chapter** etc — marcas/denominações associadas à PMI. Real.
- ✅ **Chapter Operating Guidelines** — política oficial PMI para capítulos. Real (PMI website).
- ⚠️ **Núcleo NÃO tem licença formal de uso autônomo da marca PMI®** — usa via vinculação institucional ao PMI-GO como Chapter Sponsor.
- ⚠️ **Política atual NÃO tem disclaimer formal de marcas** — gap identificado.

### Texto proposto — Política IP Cláusula 16 (NOVA)

```html
<h3><strong>16. Disclaimer de Marcas e Identidade Institucional</strong></h3>
<p><strong>16.1 Marcas registradas do PMI Global.</strong> "PMI®", "Project Management Institute®", "PMP®", "CPMAI™", "PMI Goiás Chapter", "PMI-GO", "PMI-CE", "PMI-DF", "PMI-MG", "PMI-RS", "PMI Brasil" e demais marcas, símbolos, logotipos e expressões de identidade visual associados ao Project Management Institute são propriedade exclusiva do <strong>Project Management Institute, Inc.</strong> ("PMI Global"), com sede em Newtown Square, Pensilvânia, Estados Unidos.</p>
<p><strong>16.2 Status do Núcleo.</strong> O Núcleo IA &amp; GP é iniciativa voluntária inter-capítulos do PMI Brasil, sediada no <strong>PMI Goiás Chapter (PMI-GO)</strong> sob endorsement institucional documentado, em conformidade com as Chapter Operating Guidelines do PMI Global e demais políticas aplicáveis ao uso de marca por capítulos.</p>
<p><strong>16.3 Uso autorizado da marca.</strong> O Núcleo não detém licença de uso autônomo da marca PMI®. Qualquer uso da marca em materiais, eventos, publicações ou produtos do Programa observa: (a) a vinculação institucional ao PMI-GO como capítulo sede; (b) a citação correta da denominação completa "PMI Goiás Chapter (PMI-GO)" e variações análogas para os demais capítulos parceiros (PMI-CE, PMI-DF, PMI-MG, PMI-RS); (c) ausência de sugestão de endorsement direto pelo PMI Global, salvo quando expressamente autorizado por escrito por instância PMI Global competente.</p>
<p><strong>16.4 Marcas, frameworks e materiais produzidos no Núcleo.</strong> Quaisquer marcas, logotipos, frameworks, metodologias e materiais produzidos no âmbito do Núcleo que não correspondam a marcas do PMI são identificados como produção do Núcleo, com atribuição aos autores ou ao Programa conforme regime de Tracks A/B/C desta Política (Cláusula 5).</p>
<p><strong>16.5 Compliance e atualização.</strong> Esta Cláusula 16 é interpretada à luz das Chapter Operating Guidelines vigentes e das demais políticas oficiais PMI Global. Na ocorrência de orientação superveniente do PMI Global afetando o uso de marca por capítulos, esta Cláusula é atualizada por Material change (Cláusula 12.2) com aceite expresso das partes envolvidas.</p>
```

### Rationale
- **Reconhecimento explícito** PMI® como propriedade PMI Global
- **Status Núcleo** como iniciativa de capítulo (não direta PMI Global)
- **Compliance** referenciando Chapter Operating Guidelines
- **Branding rules** claras para uso autorizado
- **Distinguir** marcas PMI vs marcas/frameworks Núcleo
- **Atualização framework** via Material change

### Pendência verificação Ângelina
- ⚠️ Confirmar se Chapter Operating Guidelines têm cláusula específica sobre uso de marca por capítulos para iniciativas inter-capítulos
- ⚠️ Verificar se PMI Global requer autorização formal para uso da marca em iniciativas como Núcleo IA — ou se basta endorsement do Chapter Sponsor PMI-GO

---

## M5 — Cooperação com Entidades Externas e Subsidiárias PMI Global (PMO-GA cláusula NOVA)

### Trailback
**Fonte 1:** Vitor 2026-05-05:
> "a questão do PMO-GA que é uma entidade ligadao ao PMI Global, foi feito a adicao no termo de cooperacao esta possibildiade conforme sugerido por ti em outra sessao?"

**Fonte 2:** Memory `project_nucleo_strategic_direction.md` + `_council-input-product-leader-mesh-2026-05-02.md` (wiki):
> "PMO Global Alliance (PMOGA) — pmoga.pmi.org — **Precedente: foi independente, adquirida pelo PMI**"
> 
> "5 entidades em negociação: FioCruz, AI.Brasil, CEIA-UFG, IFG, PMO-GA"

**Fonte 3:** Backlog item W123 + Path I (Deliberate Acquihire Target — PMOGA playbook).

### Verificação de fato/dado
- ✅ **PMO Global Alliance (PMOGA)** — comunidade global PMO professionals, fundada ~2017, **adquirida pelo PMI Global** ~2023-2024, agora opera como `pmoga.pmi.org`. Real.
- ✅ Status atual: PMOGA é **Community of Practice oficial PMI Global**.
- ✅ **Lei nº 10.973/2004 (Lei de Inovação)** — Real, vigente. Disciplina cooperação ICTs públicas com setor privado.
- ✅ **AIPM Ambassadors** (PM AI Revolution) — programa real, Vitor é Ambassador.
- ✅ **FioCruz, AI.Brasil, CEIA-UFG, IFG** — entidades reais de pesquisa/comunidade citadas em backlog Núcleo.

### Verificação adicional pendente Ângelina
- ⚠️ PMOGA tem instrumento institucional próprio para parcerias com iniciativas de capítulos PMI? Ou se relaciona via Chapter Sponsor?
- ⚠️ Há requisitos específicos PMI Global para cooperação inter-entidades?

### Texto proposto — Acordo Cooperação Bilateral (NOVA Cláusula 12)

```html
<h3>12. Cooperação com Entidades Externas e Subsidiárias PMI Global</h3>
<p><strong>12.1 Possibilidade de extensão.</strong> As partes signatárias reconhecem a faculdade do Núcleo IA &amp; GP de estabelecer cooperação técnica, científica ou institucional com:</p>
<ul>
<li><strong>(a)</strong> entidades subsidiárias, afiliadas ou Communities of Practice oficiais do <strong>Project Management Institute Global</strong>, incluindo, exemplificativamente, <strong>PMO Global Alliance — PMOGA</strong> (<a href="https://pmoga.pmi.org">pmoga.pmi.org</a>); programas oficiais de Embaixadores PMI; e demais iniciativas oficiais PMI Global de interesse comum;</li>
<li><strong>(b)</strong> Instituições Científicas e Tecnológicas (ICTs) brasileiras públicas ou privadas, observado o regime da <strong>Lei nº 10.973/2004</strong> (Lei de Inovação) quando aplicável, mediante instrumento próprio de cooperação técnica e/ou de fomento;</li>
<li><strong>(c)</strong> outras associações, comunidades técnicas, programas de Embaixadores externos ao PMI (incluindo, exemplificativamente, <strong>PM AI Revolution / AIPM Ambassadors</strong>), instituições de pesquisa, fomento ou parceiros institucionais cuja cooperação promova os objetivos do Programa Núcleo IA &amp; GP.</li>
</ul>
<p><strong>12.2 Forma de formalização.</strong> Cada cooperação será formalizada por instrumento próprio (memorando de entendimento, acordo específico, termo de cooperação técnica ou similar) firmado pelo PMI-GO como Chapter Sponsor do Núcleo, com ciência prévia dos demais capítulos signatários do presente Acordo.</p>
<p><strong>12.3 Limites e independência.</strong> Cooperações com entidades externas:</p>
<ul>
<li>(a) não substituem nem alteram o presente Acordo de Cooperação Bilateral entre capítulos PMI;</li>
<li>(b) não criam vínculo jurídico direto entre os capítulos signatários e as entidades externas, salvo se expressamente formalizado em instrumento próprio assinado pelos capítulos envolvidos;</li>
<li>(c) observam as regras de Propriedade Intelectual estabelecidas no Adendo de PI integrante deste Acordo, na Política de Governança de Propriedade Intelectual do Núcleo e no Anexo Técnico — Plataforma Operacional, conforme aplicável;</li>
<li>(d) preservam a independência, a missão original e a vocação não-comercial do Programa Núcleo IA &amp; GP enquanto iniciativa voluntária;</li>
<li>(e) observam as regras de uso de marca PMI® estabelecidas na Cláusula 16 da Política de Governança de PI, evitando representação que sugira endorsement direto não autorizado pelo PMI Global.</li>
</ul>
<p><strong>12.4 Comunicação e transparência.</strong> As cooperações ativas ou em negociação são reportadas semestralmente aos capítulos signatários no relatório de portfólio do Núcleo, com indicação de status, contraparte, escopo e responsável pela negociação.</p>
```

### Rationale
- **Permite cooperation expandida** com entidades-PMI Global (PMOGA), ICTs (FioCruz, CEIA-UFG, IFG) e comunidades externas (AI.Brasil, AIPM)
- **Não engessa** o Acordo Bilateral — cada cooperação tem seu instrumento próprio
- **Preserva independência** do Acordo entre capítulos PMI
- **Cross-refs** Anexo Técnico (M3) + Disclaimer Marca PMI (M4) + Política PI
- **Transparência** via relatório semestral

---

## Resumo de migration plan v6

### Versions a serem criadas

| Doc | versão atual | nova versão | mudanças |
|---|---|---|---|
| Política IP | v5 | **v6** | M2 (LGPD §2.5.5 redraft) + M4 (Cláusula 16 marca PMI disclaimer NOVA) + cross-ref Anexo Técnico |
| Termo de Adesão | v5 | **v6** | M1 (§15.4 aceite tácito refactor) |
| Adendo Retificativo | v5 | **v6** | M1 (§3º aceite tácito refactor) |
| Adendo PI Cooperação | v4 | **v5** | M3 (Art 8 simplification thin cross-ref) |
| Acordo Cooperação Bilateral | v4 | **v5** | M5 (Cláusula 12 PMOGA NOVA) + cross-ref Anexo Técnico |
| **Anexo Técnico Plataforma** (NOVO) | — | **v1** | criação completa (8 seções) |

### Cross-refs alignment

- Política § governança → Anexo Técnico (cross-ref)
- Termo §16 + Adendo Retificativo §5-C + Acordo §11.2 → Anexo Técnico (cross-ref preservada)
- Adendo PI Cooperação Art 8 → Anexo Técnico (thin cross-ref)
- Disclaimer Marca PMI® em Política §16 ← cross-ref pelos demais docs

### Pendências para Ângelina validar

| Item | Verificação primária requerida |
|---|---|
| M2 (LGPD) | Status atual adequacy decision Brasil ↔ UE/EEE via ANPD + Comissão Europeia |
| M2 (LGPD) | UK Addendum / IDTA versão atual via ICO |
| M4 (Marca PMI) | Chapter Operating Guidelines PMI Global — uso de marca por iniciativas inter-capítulos |
| M5 (PMOGA) | Existe instrumento institucional PMOGA para parcerias com iniciativas de capítulos? |

### Validação posterior Ângelina

Após apply de v6, Ângelina recebe:
- **5 docs LOCKED v6** (governance) + **1 doc novo Anexo Técnico v1** (LOCKED)
- Este spec doc com trailback + texto proposto + pendências
- Ricardo's critique + drafts originais (`/home/vitormrodovalho/Downloads/A/`)

Sua função: **validar** texto pronto (não remendar) + endereçar 4 pendências de verificação primária.
