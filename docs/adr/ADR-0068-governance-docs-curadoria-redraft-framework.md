# ADR-0068: Governance Docs — Curadoria Redraft Framework (Path A/B + Material/Editorial Change)

**Status:** Proposed (2026-05-01) — aguardando ratificação curadores + revisão advogado humano
**Decision date:** p87 EXTENDED marathon (post-Bug Ana Carla, pré-redraft 5 docs)
**Related:** ADR-0011 IP framework, ADR-0016 governance chain, ADR-0066 PMI Journey, ADR-0067 N1 Art.20 LGPD

---

## Context

5 documentos governance Núcleo IA & GP em curadoria pré-circulação para 15 capítulos PMI Brasil:

1. **Acordo de Cooperação Bilateral — Template Unificado** (cooperation_agreement, v1)
2. **Adendo de Propriedade Intelectual aos Acordos de Cooperação** (cooperation_addendum, v2)
3. **Adendo Retificativo ao Termo de Compromisso de Voluntário** (volunteer_addendum, v2)
4. **Termo de Compromisso de Voluntário** (volunteer_term_template, v2)
5. **Política de Publicação e Propriedade Intelectual** (policy, v2)

3 curadores comentaram: **Roberto Macêdo (PMI-CE)**, **Sarah Faria Alcantara Macedo Rodovalho (PMI-GO)**, **Fabricio Costa (PMI-GO, vice-GP)**. Total 18 comments + 7 signoffs já dados (curator gate).

### Problema central — Track B-Periódico

Comentário **CRITICAL** Roberto (Adendo PI Art. 2, Parágrafo Único): re-licenciamento Track B "não funciona assim" — periódicos científicos exigem cessão exclusiva, programas inovação aberta capturam IP. Propõe deliberação caso a caso por petit comitê.

**Validation:** Lei 9.610/98 art. 49 + art. 4º (interpretação restritiva). Elsevier subscription confirma transfer/exclusive policy. Springer OA preserva copyright author com CC.

### Outros comments materiais validados

- Roberto preâmbulo Acordo Coop: versão vigente vs adesão futura (risco diferentes versões coexistindo)
- Roberto Retificativo §2.6: standby 24m invalidado se editora exige indeterminado
- Roberto Adendo PI Art. 5: termos inglês sem tradução em doc brasileiro
- Roberto Adendo PI Art. 6: período graça INPI (Lei 9.279/96 art. 12 — 12 meses)
- Roberto Acordo Coop §6: ausência attribution obrigatória (Lei 9.610/98 art. 24 II)
- Roberto Acordo Coop §2: "Código Civil Brasileiro" explícito
- Sarah Adendo PI Art. 2: aprovação prévia autores antes reprodução chapters
- Fabricio + Sarah: glossário ausente (Track A/B/C/D, CC-BY-SA, MIT/Apache)
- Fabricio Acordo Coop branding: "PMI Goiás" canonical (4 acordos ativos confirmam)

### Process — 3 rounds deferring

1. **Round 1**: legal-counsel + accountability-advisor pareceres iniciais
2. **Round 2**: PM solicitou simplificação (manter governance, reduzir overhead). Eu propus Path A/B framework. Agents validaram com 7 ressalvas
3. **Round 3 final**: APROVARAM com 4 ressalvas residuais. Total **11 ressalvas absorvidas**

---

## Decision

Adotar framework consolidado abaixo com 11 ressalvas incorporadas no redraft. Red flag preservado: **advogado humano licenciado** revisar Track B + Standby ANTES de circular para 15 capítulos.

### 1. Track B-Periódico — Path A / Path B

#### PATH A — Automático (sem comitê, ~80% casos)

**Aciona-se** quando periódico OA genuíno = **CC-BY ou CC-BY-SA apenas** (CC-BY-NC/ND/NC-ND ativam Path B — **R-L1**).

**Checklist self-declaratório obrigatório** (4 triggers — **R-A1 + R-A5**):
1. "Não há conflito de interesse não declarado"
2. "Não há embargo > 6 meses"
3. "Não há cessão exclusiva pendente"
4. "Periódico é CC-BY ou CC-BY-SA confirmado **com link DOI/URL oficial arquivado**"

Resultado: notificação automática Núcleo + atribuição obrigatória + Núcleo mantém licença não-exclusiva. Audit trail plataforma com timestamp + hash + autor signature.

#### PATH B — Comitê de Curadoria pleno (~20% casos)

**Aciona-se quando QUALQUER**: cessão exclusiva/total/indeterminada / programa inovação aberta com captação / embargo > 6 meses / conflito obras anteriores / Path A checklist falhou.

**Estrutura**:
- Comitê Curadoria existente (não Ad Hoc novo — anti-capture via multi-chapter)
- Autores envolvidos voz consultiva sem voto sobre própria obra (**R-L2**)
- Comitê escopo dual no regimento: mandato Path B distinct (arbitragem PI) vs curadoria conteúdo + declaração CoI obrigatória (**R-A4**)

**Prazo**: 15d + extensão única +15d = 30d max. **Gate opcional 45d** (parecer jurídico externo, qualquer membro propõe + maioria aprova, gate expirado = Comitê delibera com info disponível — **R-L5**).

**Comitê pode propor**: standby (24m default, **acima 48m requer ata fundamentada** — Lei 9.610/98 art. 49 IV — **R-L3**); versão prévia/fundacional separada (opção, contribuição autônoma documentada); adaptação attribution.

**Ata** plataforma: voto nominal + fundamentação + voto divergente + declaração CoI por votante.

**Cross-doc remissão Acordo Coop** (**R-L4**):
> "Qualquer período de standby está sujeito ao teto máximo de 48 (quarenta e oito) meses sem ata fundamentada do Comitê de Curadoria, nos termos do art. 49, IV da Lei 9.610/98. Prazos superiores exigem deliberação registrada com fundamentação expressa."

### 2. Lifecycle versionamento — Material vs Editorial Change

**Material change** (nova obrigação, alteração escopo IP, mudança quórum, nova sanção, alteração opt-out):
- Notificação 30d + janela re-aceite 15d + status "suspenso" 30d adicionais antes desligamento

**Editorial change** (correção gramatical, clareza, sem alteração obrigação/direito):
- Comunicação informativa, prazo ciência 15d, sem re-aceite

**Aprovação material change**: Comitê Curadoria maioria simples + ratificação chapter sponsor PMI Goiás. Chapters parceiros 15d manifestação (sem veto).

**Audit trail**: registro plataforma com mesma imutabilidade consent flow ADR-0066/0067.

### 3. Direito objeção (notificação reprodução chapters)

**Lista FECHADA triggers "sensível"** (10+5d) — **R-A2**:
- (a) dados pessoais identificáveis terceiros
- (b) reprodução com vínculo comercial qualquer chapter
- (c) obra parceria/contrato terceiros
- (d) obra captação recursos

**Fora da lista = rotina** (5+3d). **Adicionar trigger requer decisão registrada Comitê**.

### 4. Atribuição obrigatória (Acordo Coop §6 + Política §7)

**Acordo Coop §6**: cláusula contratual com formato canônico + sanção escalada (1ª/2ª/3ª violação).

**Política §7** (canonical template): formato attribution = "Desenvolvido por [Autor(es)], no âmbito do Núcleo de IA & GP — PMI Brasil. Licenciado sob [licença]." Lei 9.610/98 art. 24 II + arts. 102-110.

**Audit semestral** Comitê varredura usos públicos.

### 5. Período de graça INPI (Adendo PI Art. 6)

Lei 9.279/96 art. 12 — Núcleo não divulga publicamente informação com potencial inventivo sem consulta autor; preserva 12 meses graça pré-depósito patente.

### 6. Glossário centralizado (Política — referenciado nos demais)

**Track A**: periódico com revisão por pares + restrição temporária acesso aberto.
**Track B**: periódico com acesso aberto desde publicação.
**Track C**: repositório interno/wiki.
**Track D**: confidencial não-publicável externamente.

**CC-BY**: Atribuição. **CC-BY-SA**: Atribuição-CompartilhaIgual. **CC-BY-NC** / **CC-BY-ND** / **CC-BY-NC-ND**: variantes restringindo comercial/derivada (ativam Path B). **MIT** / **Apache-2.0**: licenças software livre.

### 7. Policy Owner por documento (R-A3)

| Documento | Cargo | Member individual + vigência mandato |
|---|---|---|
| Acordo Cooperação | GP do Núcleo IA & GP | (registrado plataforma) |
| Adendo PI | GP do Núcleo IA & GP | (idem) |
| Termo Compromisso | GP do Núcleo IA & GP | (idem) |
| Adendo Retificativo | GP do Núcleo IA & GP | (idem) |
| **Política** | **Comitê de Curadoria** | (collective; coordenador nomeado) |

### 8. Outras cláusulas

- "**Código Civil Brasileiro (Lei 10.406/02)**" em Acordo Coop §2
- "**PMI Goiás**" em Acordo Coop (substitui "PMI Brasil-Goias Chapter") — 4 acordos ativos confirmam canonical

---

## Alternatives considered

**A1 — Comitê Ad Hoc PI novo**: rejeitada (overhead duplica Comitê Curadoria; anti-capture já existente via multi-chapter)
**A2 — Salami slicing como default**: rejeitada (COPE/ICMJE classificam questionável; mantida como **opção** comitê pode propor caso a caso com contribuição autônoma documentada)
**A3 — Notificação 10+5d para todos casos reprodução**: rejeitada (paralisante para reprodução rotineira; substituída por lista fechada triggers)
**A4 — Path A automático sem checklist**: rejeitada após accountability sign-off (autor pode classificar erroneamente; checklist 4 triggers + link documental adicionado — R-A1 + R-A5)

---

## Implications

### Cross-doc updates necessárias (próximo commit migration)

1. **Política**: §5 Track B redraft (Path A/B); §7 Atribuição; glossário; lifecycle Material/Editorial; §4 período graça INPI
2. **Acordo Cooperação**: Preâmbulo lifecycle; §2 "Código Civil Brasileiro"; §6 Atribuição contratual; cláusula remissiva standby; PMI Goiás fix
3. **Adendo PI**: Art. 2 Path A/B + Sarah notificação; Art. 5 glossário; Art. 6 período graça
4. **Adendo Retificativo**: §2.6 Standby fallback prazo indeterminado + teto 48m
5. **Termo Compromisso**: ciência Path A/B; remissão glossário Política

### Re-assinaturas pós-redraft

| Doc | Quem | Razão |
|---|---|---|
| Acordo Cooperação | **Fabricio + Sarah** | Roberto comments 29/4 após signoffs 21/4 + 27/4 |
| Adendo PI | **Fabricio** | Sarah 27/4 + Roberto 29/4 após 21/4 |
| Adendo Retificativo | **Fabricio** | Sarah 27/4 + Roberto 29/4 após 21/4 |
| Termo Compromisso | **Fabricio** | Sarah 27/4 após 21/4 |
| Política | **NENHUM** | Roberto 19/4 anterior + change_note |

Roberto: primeira signature em todos 5 (não assinou).

### Red flag preservado (não substituível por AI)

Advogado humano licenciado revisar Track B redraft + Standby ANTES de circular para 15 capítulos. PM owns checkpoint externo.

### Sponsor PMI Goiás assimetria

Chapter sponsor PMI Goiás: voto material change + ratificação obrigatória + responsabilidade legal jurídica (Goiânia/GO foro).

### A6 deferred (PM strategic decision)

NOT contact PMI Latam/Global proativo. Núcleo será procurado quando atingir tamanho que justifique aproximação. Estratégia organic growth com self-governance defensible até momento certo de surface ao PMI Global.

---

## Validation evidence (sources oficiais)

| Claim | Source | Status |
|---|---|---|
| Lei 9.279/96 art. 12 (período graça 12m) | [Planalto](https://www.planalto.gov.br/ccivil_03/leis/l9279.htm) + [WIPO Lex](https://www.wipo.int/wipolex/en/legislation/details/21166) | ✅ VERIFIED |
| Lei 9.610/98 art. 49 + art. 4º | [Planalto](https://www.planalto.gov.br/ccivil_03/leis/l9610.htm) + [Jusbrasil](https://www.jusbrasil.com.br/topicos/10624947/) | ✅ VERIFIED |
| Lei 9.610/98 art. 24 II direito moral | Planalto | ✅ VERIFIED |
| Elsevier subscription transfer/exclusive | [Elsevier](https://www.elsevier.com/about/policies-and-standards/copyright) | ✅ VERIFIED |
| Springer OA preserva copyright | [Springer](https://www.springer.com/gp/open-access/publication-policies/copyright-transfer) | ✅ VERIFIED |
| STJ REsp 1.765.578 + 1.584.022 | Cases existem; conteúdo not verified | ⚠️ PARTIAL |
| Linux/IETF/Wikimedia material/editorial | Doutrina governance reconhecida | ⚠️ PARTIAL |

---

## Status

- **ADR Proposed** (este doc) — canonical reference
- **Migration redraft** 5 docs em sessão dedicada (próximo step, ~2h)
- **Resolve comments** via resolution_note linking este ADR
- **PM checkpoint A6** deferred — strategic timing organic growth
- **Advogado humano** revisar Track B + Standby antes circular 15 capítulos

## Trace

- 18 comments curadores (2026-04-19 a 2026-04-29)
- 7 signoffs curator gate dados
- legal-counsel + accountability-advisor 3 rounds (6 invocations)
- WebSearch + WebFetch validation reliable sources
- PM Vitor decisões sequenciais: simplificação + sign-off final + A6 strategic rejection

Assisted-By: Claude (Anthropic)
