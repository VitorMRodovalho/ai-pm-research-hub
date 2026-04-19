# Parecer Jurídico CR-050 v2.1 → v2.2 — Curadoria Final Pré-Submissão

- **Data:** 2026-04-20 (sessão p32)
- **Agente:** legal-counsel (AI, council Tier 2)
- **Escopo:** Curadoria final dos 5 instrumentos CR-050 v2.1 antes de submissão ao jurídico do Ivan, com foco em RF-2 (IRRF royalties) + RF-3 (GDPR UE Ambassadors) + scope alignment cross-doc.
- **Contexto:** Correção PM p32 — Ivan NÃO indicou advogado próprio nem especialista externo (tributário/GDPR); jurídico dele analisa durante comment/approval. Responsabilidade do Núcleo: entregar versão "final-quality" para maximizar aprovação sem round-trips.
- **Precedente:** Parecer p30 (`2026-04-19-legal-counsel-ip-review.md`) resolveu 6 P1 + 7 P2 em v2.1; RF-2 e RF-3 foram marcados "fora do escopo AI" e agora são endereçados.

## 1. Resumo Executivo

- v2.1 absorveu 100% dos P1 + P2 do parecer p30 — patamar substancialmente superior ao v1.
- **RF-2 (IRRF):** v2.1 Política §4.5.4(e) cita base legal mas está incompleta em 4 dimensões técnicas. Proposta: substituir alínea por (e.1)–(e.4) cobrindo tabela progressiva PF residente + 15% não-residente + CDT carve-outs + tratamento rateio capítulos. Base: CTN 43/45, RIR 9.580/2018 arts. 779+, Lei 9.779/99, Lei 9.430/96.
- **RF-3 (GDPR):** v2.1 §2.5 é "norma de intenção futura" — inadequado para advogado revisor. Proposta: substituir integralmente por Seção 2.5 operacional com 7 sub-cláusulas (Art. 3(2) scope, Art. 6(1)(b) base legal, Art. 49(1)(a)+(b) transferência, Arts. 15-21 rights catalogue, Art. 27 threshold 10 voluntários UE, Art. 33 notificação 72h, Art. 35 DPIA trigger).
- **7 inconsistências cross-doc** identificadas (mostly editorial): nomenclatura "Encarregado/DPO", versão "v2.0/v2.1", CC-BY-SA "4.0/4.0 Internacional", Track B re-licensing ausente no Adendo Coop, standby itálico, v2.0 no Sumário.
- **5 residual risks** pós-v2.2 fora do escopo LLM: lista CDTs ativas, CEBAS do PMI-GO, threshold Art. 27 refinado, alínea (e.4) rateio PJ-PJ, Art. 49 vs SCCs adequação por EDPB.

## 2. RF-2 — IRRF: Diagnóstico e Texto Proposto

### 2.1 Análise técnica da alínea (e) v2.1

**Texto atual:**
> "(e) Retenção e recolhimento dos tributos incidentes sobre os royalties conforme a legislação tributária vigente, ficando a cargo do PMI-GO a responsabilidade pela retenção na fonte aplicável — Imposto de Renda Retido na Fonte (IRRF) para beneficiários residentes no Brasil, nos termos da Lei nº 7.713/1988 e da tabela progressiva vigente; e imposto sobre remessas ao exterior para beneficiários não residentes, nos termos do art. 5º da Lei nº 9.779/1999 e da Instrução Normativa RFB nº 1.455/2014 —, deduzindo o valor retido do montante a pagar ao beneficiário."

**Gaps técnicos:**

1. **Base legal incompleta.** Falta citar CTN 43 (fato gerador IR) e CTN 45 (responsabilidade fonte pagadora) — fundamento constitucional da obrigação de retenção. Falta citar RIR 9.580/2018 arts. 779+ (royalties especificamente). IN RFB 1455/2014 foi alterada pela IN RFB 1881/2019 e 2119/2022 — referência tecnicamente desatualizada.
2. **Alíquota e mecanismo ausentes.** Não cita a tabela progressiva mensal vigente (isento até R$ 2.259,20; 7,5%/15%/22,5%/27,5% acima). Não menciona DARF código 0588 (PF residente) nem 0473 (não-residente), prazo de recolhimento, comprovante anual de rendimentos, DIRF.
3. **CDT carve-out ausente.** Não diferencia alíquota reduzida via CDT (ex: Portugal 10–15% vs Brasil 15%). Não menciona formulário de residência fiscal estrangeira (IN RFB 1662/2016). Nota: Brasil NÃO tem CDT com Alemanha (relevante para Fabrício).
4. **Rateio capítulos omitido.** Quando PMI-GO recebe royalty e distribui a 4 outros capítulos, surge problema: isenção IR do PMI-GO não se transmite ao beneficiário PF; redistribuição PJ-PJ pode caracterizar receita tributável. Texto atual não trata.

### 2.2 Texto proposto — substitui integralmente a alínea (e)

> **(e) Retenção, recolhimento e prestação de contas tributárias sobre royalties:**
>
> O PMI-GO, na qualidade de fonte pagadora, é responsável pela retenção do Imposto de Renda Retido na Fonte (IRRF) sobre os royalties pagos, nos termos dos arts. 43 e 45 do Código Tributário Nacional (CTN — Lei nº 5.172/1966) e do Decreto nº 9.580/2018 (Regulamento do Imposto de Renda — RIR/2018, arts. 779 e seguintes), observadas as seguintes regras:
>
> **(e.1)** Para beneficiários pessoas físicas residentes no Brasil: aplica-se a tabela progressiva mensal do IRRF vigente (Lei nº 7.713/1988, art. 7º), com recolhimento via DARF ao código 0588 até o último dia útil do mês subsequente ao pagamento; emissão de comprovante anual de rendimentos ao beneficiário e inclusão na DIRF do exercício, nos termos das Instruções Normativas da Receita Federal vigentes.
>
> **(e.2)** Para beneficiários não residentes no Brasil: aplica-se a alíquota de 15% (quinze por cento) sobre o valor bruto da remessa, nos termos do art. 5º da Lei nº 9.779/1999, sujeita a redução conforme Convenção para Evitar a Dupla Tributação celebrada pelo Brasil com o país de residência do beneficiário, quando aplicável, mediante apresentação de comprovante de residência fiscal estrangeira; para remessas a residentes em jurisdições com tributação favorecida (art. 24 da Lei nº 9.430/1996), aplica-se a alíquota de 25% (vinte e cinco por cento); o recolhimento é feito via DARF ao código 0473.
>
> **(e.3)** A isenção do PMI-GO de Imposto de Renda não se transmite ao beneficiário do royalty, que é tributado individualmente como acima descrito.
>
> **(e.4)** Quando houver rateio de royalties entre capítulos signatários (pessoas jurídicas), o tratamento tributário será definido em instrumento específico de rateio, verificando-se a natureza da receita para cada capítulo receptor, em consulta com contador ou assessor tributário.

## 3. RF-3 — GDPR: Diagnóstico e Texto Proposto

### 3.1 Análise técnica da Seção 2.5 v2.1

**Texto atual:**
> "Para voluntários residentes em países membros da União Europeia, o Programa avaliará a aplicabilidade do Regulamento (UE) 2016/679 (GDPR) em consulta com o Encarregado do PMI-GO antes da formalização do vínculo, incluindo a verificação da necessidade de Data Processing Agreement (DPA), representante na UE (Art. 27 GDPR) e base legal adequada para transferência internacional de dados. Até deliberação específica, aplicam-se os padrões LGPD com observância do princípio da disposição mais protetiva ao titular."

**Fragilidade-chave:** redação de intenção futura ("avaliará") em vez de norma operacional. Para jurídico revisor sinaliza "gap não resolvido". GDPR Art. 3(2) já incide — recrutamento AIPM Ambassadors via chamada pública constitui "offering of services" a residentes UE, independente de controlador estar no Brasil.

**Regime aplicável:**

- **Base legal (Art. 6):** Art. 6(1)(b) — execução de contrato (Termo) é a mais adequada para voluntariado formalizado. Dados complementares (gamificação, telemetria) podem precisar Art. 6(1)(f) com LIA.
- **Transferência BR↔UE:** Brasil SEM decisão de adequação. Opções: Art. 46(2)(c) SCCs Módulo 1/4 OU Art. 49(1)(b) necessidade contratual + Art. 49(1)(a) consentimento explícito (pragmático para escala atual).
- **Art. 27 representante UE:** isenção Art. 27(2)(a) aplicável a "occasional processing + low risk" — Núcleo está no limiar; threshold razoável 10 voluntários UE ativos simultâneos.

### 3.2 Texto proposto — substitui integralmente Seção 2.5

> **2.5 Voluntários Residentes na União Europeia — Aplicação do GDPR**
>
> **2.5.1 Alcance.** O Regulamento (UE) 2016/679 (GDPR) pode incidir sobre o tratamento de dados de voluntários residentes em Estados-membros da União Europeia quando o Núcleo recrutar ou oferecer participação a residentes da UE, nos termos do Art. 3(2) do GDPR. O Núcleo reconhece esta responsabilidade e adota as disposições desta Seção para voluntários UE formalizados.
>
> **2.5.2 Base legal de processamento.** O tratamento de dados pessoais de voluntários residentes na UE fundamenta-se no Art. 6(1)(b) do GDPR — execução do Termo de Voluntariado do qual o voluntário é parte —, para todos os dados necessários à gestão do vínculo voluntário (identificação, comunicação, registro de contribuições intelectuais). Dados complementares coletados para finalidades específicas (ex: dados de uso da plataforma para fins de gamificação) serão identificados e comunicados ao titular no ato da coleta, com base legal individualizada.
>
> **2.5.3 Transferência internacional de dados Brasil ↔ UE.** O Brasil, à data desta Política, não possui decisão de adequação emitida pela Comissão Europeia nos termos do Art. 45 do GDPR. A transferência dos dados pessoais de voluntários residentes na UE para servidores localizados no Brasil (operados pelo PMI-GO como controlador) fundamenta-se no Art. 49(1)(b) do GDPR — necessidade de execução do contrato (Termo de Voluntariado) do qual o titular é parte —, complementado por consentimento explícito e informado do voluntário no ato da assinatura do Termo, conforme Art. 49(1)(a) do GDPR, após ciência dos riscos decorrentes da ausência de decisão de adequação.
>
> **2.5.4 Direitos dos voluntários UE como titulares.** Voluntários residentes na UE têm, em adição aos direitos previstos no Art. 18 da LGPD, os seguintes direitos garantidos pelo GDPR:
> - (a) Direito de acesso (Art. 15): confirmação do tratamento e cópia dos dados;
> - (b) Direito de retificação (Art. 16): correção de dados inexatos;
> - (c) Direito ao apagamento ('direito ao esquecimento', Art. 17): eliminação dos dados quando cessado o vínculo, ressalvadas obrigações legais de retenção;
> - (d) Direito à portabilidade (Art. 20): recebimento dos dados em formato estruturado e legível por máquina;
> - (e) Direito de oposição (Art. 21): oposição ao tratamento baseado em legítimos interesses;
> - (f) Direito à limitação do tratamento (Art. 18): suspensão do tratamento em situações específicas previstas na norma.
>
> Estes direitos são exercíveis junto ao Encarregado designado pelo PMI-GO, conforme Seção 2.3, que atuará como ponto de contato com as autoridades supervisoras competentes (Autoridade Nacional de Proteção de Dados — ANPD no Brasil; autoridade de supervisão do Estado-membro da UE de residência do voluntário, nos termos do Art. 77 do GDPR).
>
> **2.5.5 Representante na UE.** O Núcleo avaliará a necessidade de designar representante na União Europeia nos termos do Art. 27 do GDPR quando o número de voluntários UE ativos simultaneamente exceder 10 (dez) indivíduos, ou quando o processamento envolver categorias especiais de dados (Art. 9 GDPR) ou dados de natureza sensível, o que ocorrer primeiro. Até esse limiar, o Programa se apoia na isenção prevista no Art. 27(2)(a) do GDPR para processamento não sistemático de baixo risco.
>
> **2.5.6 Notificação de violação.** Em caso de violação de dados que afete voluntários residentes na UE, o Núcleo notificará a autoridade supervisora competente no Estado-membro de residência do titular afetado no prazo de 72 (setenta e duas) horas após a tomada de conhecimento, nos termos do Art. 33 do GDPR, e comunicará o titular afetado sem demora injustificada quando a violação puder resultar em alto risco para seus direitos e liberdades (Art. 34 do GDPR).
>
> **2.5.7 Deliberação específica por caso.** Acordos com entidades internacionais que envolvam fluxo sistemático de dados de residentes UE serão precedidos de avaliação específica pelo Encarregado do PMI-GO quanto à necessidade de Avaliação de Impacto sobre a Proteção de Dados (DPIA — Art. 35 GDPR) e de Data Processing Agreement (DPA — Art. 28 GDPR) quando o Núcleo atuar como operador de controlador estabelecido na UE.

## 4. Scope Alignment — Inconsistências Cross-Doc

| # | Doc A | Doc B | Inconsistência | Resolução |
|---|---|---|---|---|
| I-1 | Política §4.5.4(e) — cita Lei 7.713/88 + tabela progressiva | Nenhum outro doc menciona IRRF | Assimetria de detalhe após RF-2 aplicado. Aceitável — Política é fonte única tributária. | Nenhuma ação. |
| I-2 | Política §2.5 — "Encarregado do PMI-GO" | Termo Cláusula 9 §1 — "Encarregado pela Proteção de Dados Pessoais (DPO)" | Terminologia diferente para mesmo cargo. LGPD usa "Encarregado" sem "(DPO)". | Padronizar todos docs: "Encarregado pela Proteção de Dados Pessoais (Encarregado), designado pelo PMI-GO, nos termos do art. 5º, VIII, da Lei nº 13.709/2018". Substituir "(DPO)" por "(Encarregado)". |
| I-3 | Política §5 Track A — "CC-BY 4.0 (Creative Commons Atribuição 4.0 Internacional)" | Adendo Coop Art. 2 — "Track A: CC-BY 4.0" (sem "Internacional") | Possível ambiguidade (3.0 BR vs 4.0 Internacional). | Adendo Coop Art. 2: substituir por "CC-BY 4.0 Internacional" e "CC-BY-SA 4.0 Internacional". |
| I-4 | Política §5 Track B — menciona re-licensing para periódicos (exceção v2.1) | Adendo Coop Art. 2 — Track B sem menção a re-licensing | Leitor pode interpretar Adendo como "CC-BY-SA 4.0 irrevogável" conflitando com Política. | Adicionar ao Art. 2 Adendo Coop: "O re-licenciamento de obras Track B para periódicos científicos, nos termos da Seção 5 da Política de Publicação, não afeta os direitos de uso irrevogável dos capítulos signatários sobre a versão originalmente publicada pelo Núcleo." |
| I-5 | Termo 2.6 — "suspensão temporária (standby)" consistente | Adendo Retif — às vezes só "standby" sem itálico/aspas | Inconsistência tipográfica. | Padronizar Adendo: "suspensão temporária (*standby*)" na primeira ocorrência de cada subseção, apenas "suspensão" nas demais. |
| I-6 | Política §8 — referencia "Cláusula 2.6 do Termo" | Adendo Retif — Art. 3 substitui integralmente Cláusula 2 | Referência implícita funciona (Art. 3 do Adendo incorpora 2.6). | Nenhuma ação — referência abrange ambos cenários. |
| I-7 | Sumário Executivo §4 (tabela) + rodapé — versões marcadas "v2.0" | Os 4 instrumentais são v2.1 | Inconsistência editorial — confunde leitor jurídico sobre versão. | Atualizar Sumário §4 e rodapé para "v2.1 \| CR-050". Timeline §6 abrir conforme P2-D do parecer p30. |

## 5. Risco Residual Pós-v2.2 (fora do escopo LLM)

Sinalizar explicitamente ao jurídico do Ivan como "pendentes de validação por advogado licenciado":

1. **Lista de CDTs ativas BR** relevantes para perfil de voluntários internacionais (Brasil tem ~32 CDTs). Nota: SEM CDT com Alemanha.
2. **Validade do CEBAS / isenção IR do PMI-GO** — base para cálculo tributário do programa.
3. **Threshold Art. 27 GDPR (10 voluntários UE)** — estimativa razoável mas sem norma EDPB fixando.
4. **Alínea (e.4) rateio PJ-PJ** — depende da situação tributária concreta de cada capítulo parceiro.
5. **Art. 49(1)(b) GDPR como base continuada** — EDPB Guidelines 2/2018 adotam interpretação restritiva (derogações "ocasionais"). Para voluntários com vínculo continuado, ideal complementar SCCs a médio prazo. Defensável para escala atual.

## 6. Ordem de Aplicação Recomendada

**Passo 1 — Política v2.1 → v2.2** (3 edits independentes entre si):
- 1a. Substituir Política §2.5 pelo texto completo GDPR (RF-3).
- 1b. Substituir alínea (e) da §4.5.4 pelo texto RF-2 (e.1–e.4).
- 1c. Adicionar ao Art. 2 Adendo Coop frase re-licensing Track B (I-4).

**Passo 2 — Cross-doc refs** (depende de Passo 1 para Política):
- 2a. Padronizar "Encarregado (Encarregado)" em todos docs (I-2).
- 2b. Atualizar Adendo Coop Art. 2: "Internacional" após CC-BY 4.0 e CC-BY-SA 4.0 (I-3).

**Passo 3 — Editorial** (paralelo aos Passos 1–2):
- 3a. Padronizar itálico/aspas "standby" no Adendo Retif (I-5).
- 3b. Atualizar Sumário §4 + §6 para v2.1 (I-7 + P2-D).

**Passo 4 — Opcional recomendado** para jurídico do Ivan:
- 4a. Bloco de consentimento explícito Art. 49(1)(a) no Termo + Adendo Retif (renderizado condicionalmente apenas para residentes UE via campo `country` no perfil).

## 7. Declaração Final

Após aplicação de todos edits, o pacote CR-050 v2.2 estará em patamar de curadoria máxima alcançável sem especialistas humanos externos. Cobertura final:

- Direito autoral BR + Lei 9.609 software: completo (desde v2.0)
- LGPD: completo + operacional (desde v2.1)
- Conflito exclusividade periódicos: completo (desde v2.1)
- IRRF nacional + remessas: operacional (após RF-2)
- GDPR UE operacional (após RF-3), exceto RF-3a/RF-3b na seção 5.

O jurídico do Ivan recebe pacote com problemas diagnosticados, opções mapeadas e texto parcialmente resolvido — reduzindo trabalho dele a validação + refinamento final em vez de redação do zero.

---

**Arquivos consultados:**
- `docs/council/cr-050-v2.1-source/*.md` (5 docs v2.1 fonte)
- `docs/council/2026-04-19-legal-counsel-ip-review.md` (parecer p30)
- `docs/council/2026-04-19-ip-ratification-decisions.md` (PM decisions)
