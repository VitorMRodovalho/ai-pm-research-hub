# Parecer Jurídico CR-050 v2 — Auditoria Pré-Ratificação

**Data:** 19 de abril de 2026 (p30)
**Agente:** legal-counsel (AI)
**Documentos auditados:** 5 instrumentos do pacote CR-050 v2 (Sumário Executivo, Política v2, Termo R3-C3-IP v2, Adendo Retificativo v2, Adendo Cooperação v2)
**Input:** `/home/vitormrodovalho/Desktop/ai-pm-research-hub/tmp/ip-v2-md/*.md` (convertidos de .docx via pandoc 3.1.3)
**Contexto:** PM decisões nas 10 OQs em `2026-04-19-ip-ratification-decisions.md`; Roberto's 2 pontos incorporados no v2; ratificação on-platform via Phase IP-1.

---

## 1. Resumo Executivo

**Status global: APROVADO COM RESSALVAS — 6 ajustes P1, 7 ajustes P2, 4 Red Flags**

O pacote CR-050 v2 é um avanço técnico real sobre o v1. As duas correções de Roberto Macêdo estão tecnicamente corretas: o enquadramento jurídico software = Lei 9.609/documentos = Lei 9.610 está preciso, e o mecanismo de suspensão temporária resolve o conflito factual com periódicos exclusivos. O pacote está apto para circulação política aos 5 presidentes. Contudo, há 6 ajustes P1 que precisam ser incorporados antes da ratificação formal pelos 52 voluntários e da entrada em vigor do Ciclo 4: (1) autorização explícita para cessão exclusiva ao periódico durante a suspensão + restabelecimento antecipado; (2) mecanismo de recompatibilização CC-BY-SA → CC-BY quando periódico exige licença aberta não-SA; (3) direitos LGPD do voluntário como titular de seus próprios dados; (4) substituição da referência no Adendo Retificativo Art. 4 a cláusulas de termo não assinado pelos 52 pelo texto incorporado no próprio corpo do adendo; (5) silêncio positivo para depósito de marcas/patentes com aprovação tácita em 15 dias; (6) previsão de retenção IRRF sobre royalties. Há também exposição GDPR para voluntários na UE e risco fiscal sobre royalties que requerem validação especializada fora do escopo deste agente.

---

## 2. Validação dos Pontos de Roberto Macêdo

### Ponto 1 — Conflito com periódicos que exigem exclusividade (Cláusula 2.6)

O mecanismo é tecnicamente correto na sua estrutura central. A "suspensão temporária (standby)" da licença ao Núcleo sobre obra específica, ativada por notificação e com reativação automática, resolve o conflito *factual* que existia no v1: o Núcleo explorar a obra ao mesmo tempo em que o periódico exige exclusividade.

**O que está correto:**
- Separação licença não-exclusiva ao Núcleo vs. cessão exclusiva ao periódico — abordagem doutrinariamente sustentável (analogia com STJ, REsp 1.442.438/SP, 2014, sobre licença não-exclusiva com cláusula de não-exercício);
- Cláusula 2.6.3 cria o compromisso operacional de não-exercício pelo Núcleo durante o embargo;
- Reativação automática ao fim do embargo é tecnicamente correta;
- Exceção do Track A (2.6.6) é necessária porque obras CC-BY 4.0 já publicadas são irrevogavelmente licenciadas ao público.

**O que está incompleto:**
- O documento não declara explicitamente que a suspensão *autoriza o voluntário a outorgar exclusividade ao terceiro* — um departamento jurídico de periódico pode questionar se a licença suspensa "existente" é compatível com a exclusividade exigida. Precisa subcláusula 2.6.7 explicitando isso.
- Não há previsão de restabelecimento antecipado da licença quando o periódico rejeita a submissão ou o voluntário desiste — a licença fica suspensa por prazo desnecessário. Precisa subcláusula 2.6.8.

Prazo de 24 meses renováveis: razoável para o mercado editorial (principais periódicos operam com embargos de 6-24 meses).

Caso edge residual: se o Núcleo publicou obra derivada da obra-suspensa *antes* da suspensão, a Cláusula 2.6.3 ressalva adequadamente ("obras anteriores ou derivadas já em circulação"). Periódico pode exigir remoção das derivadas — o documento não resolve esse caso. É risco residual aceitável, mas deve ser mencionado ao voluntário na notificação de ativação do standby.

**Conclusão Ponto 1:** Resolve o conflito central. Dois ajustes necessários antes da ratificação (P1-A). Apto para circulação política.

---

### Ponto 2 — Software = direito autoral (Cláusula 2.5 e subcláusulas)

O enquadramento v2 está tecnicamente correto e sem lacunas para o escopo atual do Núcleo:

- **2.5.1** (obras gerais → Lei 9.610/98): correto. Frameworks, metodologias, templates e documentos são obras do Art. 7º, protegidas automaticamente, independentemente de registro (Art. 18 da mesma Lei).
- **2.5.2** (software → Lei 9.609/98): correto. Lex specialis. Prazo de proteção de 50 anos (Art. 2º §4º), direitos morais limitados (Art. 2º §1º). A remissão ao Parágrafo único da Cláusula 2.1 para os direitos morais de software é tecnicamente precisa.
- **2.5.3** (industrial → Lei 9.279/96): correto como enquadramento residual. A menção ao Art. 11 (novidade como requisito de patenteabilidade) é relevante: divulgação prematura destrói novidade. O texto adverte o voluntário corretamente.
- **2.5.4** (internacional → tratados): correto e necessário.

Sobre a questão CF-88 Art. 5º XXVII vs. Art. 2º §1º da Lei 9.609 (Flag K): o Parágrafo único da Cláusula 2.1 aplica corretamente os direitos morais reduzidos para software. A CF-88 Art. 5º XXVII protege o aspecto patrimonial ("direito exclusivo de utilização, publicação ou reprodução") — não impõe escopo mínimo de direitos morais. A limitação legislativa é constitucionalmente válida. Sem conflito.

Ponto cego para o futuro: datasets de machine learning podem não se enquadrar claramente em nenhuma das 4 subcláusulas (podem ser banco de dados sob Lei 9.610 Art. 7º XIII, ou pipeline de software, ou segredo de negócio). Para o escopo atual do Núcleo (frameworks, artigos, código de pesquisa) não é problema imediato. Recomenda-se incluir no roadmap de revisão anual (Seção 12 da Política).

**Conclusão Ponto 2:** Enquadramento correto. Sem ajuste bloqueador. Aprovado.

---

## 3. Flags A-K

### Flag A — "Revogação" vs. "Suspensão" em 2.2.2 — **REFINADO (P2-A)**

O deslize é real mas de baixo risco prático. "Ressalvado o disposto na Cláusula 2.6" cria a impressão de que 2.6 é exceção à irrevogabilidade, quando é apenas regime transitório de não-exercício. Um leitor atento diferencia porque 2.6 usa "suspensão" explicitamente, mas a imprecisão não é boa em instrumento jurídico.

**Substituir em 2.2.2 (Termo v2) e na Cláusula 2.2 do Adendo Retificativo Art. 3:**

De: "ressalvado o disposto na Cláusula 2.6"
Para: "ressalvada a suspensão temporária prevista na Cláusula 2.6, que não constitui revogação da licença mas regime transitório de não-exercício pelo Núcleo"

### Flag B — Falta cross-ref entre Cláusulas 2.4 e 2.6 — **CONFIRMADO baixo risco (P2-B)**

Ambas as cláusulas exigem notificação de 15 dias. A sobreposição não cria conflito — quem cumpre 2.6.1 (mais específica e mais exigente) automaticamente cumpre 2.4. Mas falta hierarquia explícita.

**Acrescentar ao final da Cláusula 2.4 (Termo v2 e Adendo Retificativo):**

"Quando a publicação externa envolver exigência de exclusividade pelo publicador, aplicam-se adicionalmente os procedimentos da Cláusula 2.6, que prevalece sobre esta Cláusula no que for específico."

### Flag C — Mecanismo de suspensão = cessão exclusiva via proxy — **CONFIRMADO (P1-A)**

Este é o problema jurídico mais sutil do Ponto 1 de Roberto. A Cláusula 2.6 cria o regime de suspensão e o compromisso de não-exercício (2.6.3), mas não declara explicitamente que isso constitui autorização para o voluntário outorgar exclusividade ao periódico. Um departamento jurídico rigoroso pode questionar: "a licença ao Núcleo está suspensa mas ainda existe — isso é incompatível com a exclusividade que exigimos."

A resposta técnica é que licença não-exclusiva + compromisso de não-exercício + cessão exclusiva a terceiro coexistem juridicamente — análogo ao que o STJ reconheceu em REsp 1.442.438/SP (2014) para marcas. Mas a falta de explicitação é um gap que periódicos com departamentos jurídicos ativos podem explorar.

**Adicionar Cláusula 2.6.7 (nova) no Termo v2 e no Art. 3 do Adendo Retificativo:**

"2.6.7 Durante o período de suspensão temporária previsto nas subcláusulas anteriores, o VOLUNTÁRIO fica autorizado a outorgar ao publicador externo os direitos de exclusividade exigidos como condição editorial, incluindo cessão exclusiva de direitos patrimoniais sobre a obra específica pelo prazo do embargo. A licença do Núcleo, embora não extinta, não será exercida nesse período (Cláusula 2.6.3), de modo que a exclusividade concedida ao publicador seja factualmente operante."

**Adicionar também Cláusula 2.6.8:**

"2.6.8 Em caso de rejeição da submissão pelo publicador ou desistência do VOLUNTÁRIO antes do término do prazo de embargo, o VOLUNTÁRIO comunicará imediatamente ao Gerente de Projeto, e a licença ao Núcleo será automaticamente restabelecida na data dessa comunicação, sem aguardar o término do prazo original de suspensão."

### Flag D — Cláusula 4 parágrafo único redundância — **REFUTADO**

O caput anuncia ressalvas; o parágrafo único as especifica com formulação negativa de exclusão de responsabilidade ("não constitui violação"), que é técnica legislativa correta e padrão no direito contratual brasileiro. Sem necessidade de alteração.

### Flag E — CC-BY-SA 4.0 (Track B) conflito com periódicos CC-BY — **CONFIRMADO (P1-B)**

O v2 resolve o conflito de exclusividade (Cláusula 2.6). Mas há segundo conflito estrutural não resolvido: quando obra Track B está licenciada sob CC-BY-SA 4.0 (share-alike obrigatório) e o periódico aceita apenas CC-BY 4.0 (sem share-alike), não há mecanismo de recompatibilização. A Creative Commons não prevê conversão automática entre versões SA e não-SA. Periódicos de alto impacto que adotam CC-BY (Elsevier, MDPI, PLOS ONE) não aceitarão obras sob CC-BY-SA. Pesquisadores com frameworks Track B não conseguirão publicar nesses veículos sem autorização específica que o instrumento atual não prevê.

**Adicionar ao Track B na Seção 5 da Política:**

"Re-licenciamento para periódicos: Quando obra licenciada sob CC-BY-SA 4.0 (Track B) for submetida a periódico científico que exija licença CC-BY 4.0 como condição de publicação, o Gerente de Projeto — com concordância expressa dos autores individuais — poderá autorizar a publicação da versão submetida sob CC-BY 4.0, preservando-se a versão originalmente publicada pelo Núcleo sob CC-BY-SA 4.0. O re-licenciamento aplica-se exclusivamente à versão editorial submetida, não afetando os direitos sobre a versão originalmente publicada pelo Núcleo."

**Adicionar nota ao final da Cláusula 2.6 do Termo v2 (e Art. 3 subcláusula 2.6 do Adendo):**

"O mecanismo desta Cláusula aplica-se também às hipóteses de incompatibilidade de licença aberta entre o Track B (CC-BY-SA 4.0) e a licença exigida pelo publicador externo (CC-BY 4.0 ou equivalente), mediante autorização específica nos termos da Seção 5 da Política de Publicação e Propriedade Intelectual."

### Flag F — LGPD direitos voluntário como titular — **CONFIRMADO (P1-C)**

A Cláusula 9 cobre bem as obrigações do voluntário como operador de dados de terceiros. Mas não trata da relação inversa: o voluntário também é titular de dados tratados pelo PMI-GO. A LGPD Art. 18 garante ao titular direitos de acesso, retificação, eliminação e portabilidade. O Art. 37 exige formalização da relação controlador-operador. A Cláusula 9 atual não menciona: (a) que o PMI-GO é o controlador dos dados do voluntário; (b) os direitos do voluntário como titular; (c) prazo de retenção dos seus dados após término do vínculo.

**Adicionar §2 à Cláusula 9 do Termo v2 (idem por referência no Adendo Retificativo):**

"§ 2º. O PMI Brasil–Goiás Chapter (PMI-GO), na condição de controlador, trata os dados pessoais do próprio VOLUNTÁRIO para fins de execução deste Termo, tendo como base legal o art. 7º, V, da Lei nº 13.709/2018 (LGPD). O VOLUNTÁRIO, na qualidade de titular, tem direito de acesso, retificação, eliminação, portabilidade e revogação de consentimento referentes aos seus dados pessoais, exercíveis junto ao Encarregado designado pelo PMI-GO, na forma da Seção 2 da Política de Publicação e Propriedade Intelectual. Os dados pessoais do VOLUNTÁRIO serão retidos pelo prazo de vigência deste Termo, acrescido de 5 (cinco) anos após seu encerramento para fins de cumprimento de obrigações legais, conforme a Política de Privacidade do PMI-GO."

### Flag G — Adendo Retificativo Art. 5 ressalva Cláusula 4 — **CONFIRMADO (P2-C)**

O Art. 3 do Adendo substitui integralmente a Cláusula 2. O Art. 5 apenas "ressalva a interpretação da Cláusula 4" em consonância com a Política. Essa assimetria é juridicamente mais frágil: a Cláusula 4 original ("O VOLUNTÁRIO não poderá emitir conceitos... sem prévia autorização") permanece textualmente em vigor para os 52, e o Parágrafo único do Termo v2 (que especifica as hipóteses de não-violação) não foi incorporado ao corpo do Adendo.

**Reformular Art. 5** para substituir explicitamente a Cláusula 4, incorporando o parágrafo único com as hipóteses (a), (b) e (c) de não-violação, exatamente como consta no Termo v2.

### Flag H — Adendo Retificativo Art. 4 referencia termo não assinado — **CONFIRMADO (P1-D)**

O Art. 4 incorpora por referência "as disposições da Cláusula 13 (Lei Aplicável e Jurisdição) do Termo de Voluntariado vigente (R3-C3-IP v2.0)". Os 52 voluntários do Adendo Retificativo nunca assinaram o R3-C3-IP v2.0 — esse é o novo termo para o Ciclo 4. Referenciar cláusulas de instrumento não assinado como vinculante é tecnicamente problemático: não há consentimento expresso dos 52 às cláusulas de jurisdição do v2.0, especialmente relevante para o foro de eleição em Goiânia/GO.

**Substituir Art. 4 por texto integral:**

"Art. 4 — Lei Aplicável e Jurisdição. Este Adendo e o Termo Original ao qual se vincula são regidos pela legislação brasileira, em especial pelas Leis nº 9.608/1998, nº 9.609/1998, nº 9.610/1998, nº 9.279/1996 e nº 13.709/2018, bem como pelo Código de Ética do Project Management Institute e pelos tratados internacionais de propriedade intelectual vigentes no Brasil (Convenção de Berna — Decreto nº 75.699/1975; Acordo TRIPS — Decreto nº 1.355/1994). Para VOLUNTÁRIOS residentes fora do Brasil, aplica-se a legislação brasileira, observado o princípio do tratamento nacional da Convenção de Berna (Art. 5.1), preservando-se os direitos morais do VOLUNTÁRIO no padrão mais protetivo entre a legislação brasileira e a legislação da jurisdição de sua residência. Controvérsias decorrentes deste Adendo ou do Termo Original serão resolvidas prioritariamente por conciliação interna mediada pelo Gerente de Projeto e pelos presidentes dos capítulos envolvidos; persistindo o conflito, o foro de eleição é a Comarca de Goiânia/GO, ressalvado que, em casos envolvendo VOLUNTÁRIOS residentes no exterior, as partes poderão optar, em instrumento específico, por arbitragem conforme regras da Câmara de Comércio Internacional (ICC) ou por foro bilíngue, nos termos da Seção 1.7 da Política de Publicação e Propriedade Intelectual do Núcleo."

### Flag I — Timeline Sumário Executivo stale — **CONFIRMADO editorial (P2-D)**

Issue editorial sem impacto jurídico. A timeline do Sumário Executivo (item 6) está facticamente defasada — o PM removeu o CBGPL como gate no commit 052879d. Os documentos normativos não referenciam a timeline, portanto não há impacto jurídico nas 4 peças instrumentais. Antes de circular para os presidentes, atualizar o item 6 com formulação aberta.

### Flag J — Notificação 15d aos 4 outros presidentes — **CONFIRMADO (P1-E)**

Cada capítulo (PMI-CE, DF, MG, RS) é pessoa jurídica autônoma com CNPJ próprio. Notificação de 15 dias dá conhecimento, não consentimento. Para ativos de alta relevância institucional (marcas, patentes), o PMI-GO depositar sem aprovação pode gerar disputa com capítulo que contribuiu com voluntários para a obra. O enquadramento de obra coletiva (Lei 9.610 Art. 5º VIII "h") dá base legal para PMI-GO como titular formal, mas não resolve o conflito político-contratual.

**Adicionar §1 à Cláusula 4.2.1 da Política e parágrafo equivalente ao Art. 6 do Adendo de Cooperação:**

"§ 1º Para depósito de marcas e patentes — ativos de maior impacto sobre a identidade institucional do Programa — a ausência de manifestação contrária por escrito de qualquer dos presidentes signatários no prazo de 15 (quinze) dias contados do recebimento da notificação importa aprovação tácita, nos termos do art. 111 do Código Civil. Em caso de manifestação contrária, o depósito será suspenso por até 30 (trinta) dias para deliberação conjunta. Para registros autorais junto à EDA/FBN, mantém-se a notificação simples sem efeito de aprovação tácita."

### Flag K — CF-88 vs. Lei 9.609 — **REFUTADO**

A Cláusula 2.1 parágrafo único aplica corretamente o Art. 2º §1º da Lei 9.609/98. A CF-88 Art. 5º XXVII protege o aspecto patrimonial do direito autoral, não impõe escopo mínimo de direitos morais. A restrição legislativa dos direitos morais para software é escolha do legislador ordinário dentro do espaço constitucionalmente permitido. Sem conflito. Sem necessidade de ajuste.

---

## 4. Descobertas Independentes

### DI-1 — Jurisprudência brasileira sobre licença não-exclusiva + cessão exclusiva

Não existe precedente brasileiro direto sobre essa combinação em direito autoral acadêmico. A sustentação doutrinária existe por analogia com direito de marcas (STJ, REsp 1.442.438/SP, 2014) e com a doutrina de Bittar Filho e Carboni sobre licenças não-exclusivas: o licenciante pode outorgar exclusividade a terceiro para o mesmo período desde que o licenciado original não exerça o direito — exatamente o que a 2.6.3 faz. A lacuna jurisprudencial direta é real mas não invalida o mecanismo. A explicitação do Flag C (subcláusula 2.6.7) mitiga o risco.

### DI-2 — Cláusula "NO AI TRAINING" do PMI vs. LGPD Art. 20 — **P2-E**

A Seção 11 da Política reproduz a cláusula "NO AI TRAINING" do PMI. O conflito com LGPD Art. 20 (revisão de decisões automatizadas) é de planos diferentes: o Art. 20 LGPD rege o uso de IA para tomar decisões sobre titulares de dados (exige revisão humana); a cláusula PMI proíbe treinar modelos com material PMI. Não há conflito normativo direto.

O risco real é outro: o Código de Ética PMI pode ser interpretado como proibindo voluntários de usar material PMI como entrada em qualquer processo de IA — o que colide com a missão de pesquisa em IA do Núcleo. A Política não diferencia "AI training com material PMI" de "pesquisa acadêmica que analisa material PMI como objeto de estudo".

**Adicionar nota à Seção 11 da Política:** "A proibição de uso de material PMI para AI training aplica-se ao treinamento de modelos de propósito geral. Pesquisa acadêmica que cite ou analise criticamente material PMI como objeto de estudo não constitui uso proibido, sendo permitida nos limites do art. 46 da Lei nº 9.610/1998 (citação para fins educacionais e científicos)."

### DI-3 — Validade do Adendo Retificativo: reconhecimento de firma, ICP-Brasil, DocuSign

- **Reconhecimento de firma:** não exigido. Lei 9.610/98 e Lei 9.608/98 não o exigem. Código Civil Art. 107 (liberdade de forma).
- **Assinatura digital:** Lei 14.063/2021 dispensa ICP-Brasil para contratos privados. DocuSign (assinatura eletrônica avançada com rastreabilidade de IP, hash, timestamp) é juridicamente válido. A plataforma nucleoia.vitormr.dev também é válida desde que implemente: (a) autenticação do assinante; (b) hash do documento; (c) timestamp do servidor; (d) log de IP. O `approval_signoffs.content_snapshot` planejado para a Fase IP-1 contempla todos esses elementos.

**Conclusão:** sem necessidade de ICP-Brasil ou cartório. Arquitetura planejada é adequada.

### DI-4 — Voluntários na UE: direito internacional privado e GDPR — **RF-3**

**Lei aplicável à obra:** o Art. 5.1 da Convenção de Berna adota territorialidade — para obras usadas no Brasil, aplica-se a Lei 9.610/98 independentemente de onde foram criadas. Para obras usadas na Alemanha, aplica-se o UrhG alemão, que tem direitos morais significativamente mais amplos (§14 UrhG sobre integridade; §12 UrhG direito de divulgação; §25 UrhG acesso ao original). A Cláusula 2.1 do Termo v2 reconhece o "padrão mais protetivo" — para o Fabrício, isso pode significar direitos morais mais extensos do que os do Art. 24 da Lei 9.610/98. Sem conflito com o texto atual, mas o Núcleo deve estar ciente de que publicar ou criar derivadas de obra do Fabrício sem consulta pode acionar obrigações sob o UrhG.

**Foro eleito (Goiânia/GO):** válido como escolha contratual. A Alemanha reconhece foros eleitos em contratos civis entre maiores capazes (Código Civil alemão §38 ZPO).

**GDPR:** ponto mais delicado. O GDPR Art. 3(2) tem alcance extraterritorial quando o controlador (PMI-GO, pessoa jurídica brasileira) oferece serviços a residentes da UE ou monitora seu comportamento. Se o Núcleo recruta voluntários na Europa ativamente (AIPM Ambassadors com chamada pública), o PMI-GO pode ser considerado sujeito ao GDPR para esses voluntários — o que exigiria DPA (Data Processing Agreement) específico, representante na UE (Art. 27 GDPR) e possivelmente base legal de adequação ou cláusulas contratuais padrão para transferência internacional de dados.

**Este ponto está além do escopo deste agente (direito europeu).** Flag para validação com advogado GDPR antes de qualquer formalização de vínculo com residentes da UE.

### DI-5 — Tratamento fiscal de royalties — **RF-2 / P1-F**

O v2 prevê royalties como regime excepcional (Política 4.5.3-4.5.4). Quando royalties forem efetivamente pagos:

- **Pessoa física residente no Brasil:** IRRF progressivo (tabela do Art. 43 CTN + Lei 7.713/88). O PMI-GO como pagador é responsável pela retenção.
- **Não-residente no Brasil (ex. Fabrício na Alemanha):** IRRF de 15% sobre remessas ao exterior de royalties (Lei 9.779/99 Art. 5º; IN RFB 1455/2014). Brasil e Alemanha não têm Convenção para Evitar Dupla Tributação — alíquota de 15% plena.
- **PMI-GO** como entidade sem fins lucrativos tem isenção própria de IR, mas essa isenção não se transmite ao beneficiário do royalty.

A Cláusula 4.5.4 lista diretrizes mínimas de destinação de royalties mas não menciona tributação. O PMI-GO estaria exposto a auto de infração se pagar royalties sem retenção.

**Adicionar alínea (e) à Cláusula 4.5.4 da Política:**

"(e) Retenção e recolhimento dos tributos incidentes sobre os royalties conforme a legislação tributária vigente, ficando a cargo do PMI-GO a responsabilidade pela retenção na fonte aplicável — Imposto de Renda Retido na Fonte (IRRF) para beneficiários residentes no Brasil e imposto sobre remessas ao exterior para beneficiários não residentes, nos termos da Lei nº 9.779/1999 e da Instrução Normativa RFB nº 1.455/2014 —, deduzindo o valor retido do montante a pagar ao beneficiário."

### DI-6 — Validade da "aprovação por silêncio" (complemento P1-E)

O mecanismo de silêncio positivo proposto no Flag J é válido no Código Civil Art. 111: "O silêncio importa anuência quando as circunstâncias ou os usos o autorizarem, e não for necessária a declaração de vontade expressa." Para que produza efeitos, o instrumento contratual deve prever expressamente que o silêncio no prazo implica anuência. O Adendo de Cooperação atual não tem essa previsão — apenas notificação simples. A inclusão é necessária para dar segurança jurídica ao mecanismo.

---

## 5. LGPD Compliance dos 5 Documentos

| Documento | Status | Issues |
|---|---|---|
| 00 Sumário Executivo | ✓ OK | Sem coleta de PII. |
| 01 Política v2 | ⚠ Refinar | Seção 2 correta (encarregado/ANPD). Lacuna: não lista direitos Art. 18 LGPD do voluntário. Base legal não mencionada. Recomenda-se menção. |
| 02 Termo v2 | ⚠ P1-C | Cláusula 9 cobre obrigações do voluntário como operador. Faltam direitos do voluntário como titular + base legal + retenção. Cláusula 11 (imagem): falta menção à revogação do consentimento (P2-G). |
| 03 Adendo Retificativo | ⚠ P1-C | Reproduz Cláusula 9 por referência. Lacunas do Termo se transmitem. |
| 04 Adendo Cooperação | ✓ OK | Signatários são representantes institucionais — dados de presidentes em qualidade representativa não são PII no sentido LGPD. |

---

## 6. Ajustes Sugeridos — Priorizados

### P0 — Bloqueadores absolutos

Nenhum. O pacote é apto para circulação política aos 5 presidentes na versão atual. Os P1 abaixo devem ser resolvidos antes da ratificação formal pelos 52 voluntários.

### P1 — Importantes (resolver antes da ratificação)

- **P1-A** (Flag C): Subcláusulas 2.6.7 (cessão exclusiva) + 2.6.8 (restabelecimento antecipado) — Termo v2 + Adendo Retificativo Art. 3.
- **P1-B** (Flag E): Recompatibilização CC-BY-SA → CC-BY Track B — Política Seção 5 + nota na Cláusula 2.6.
- **P1-C** (Flag F): LGPD §2 Cláusula 9 — direitos titular voluntário, base legal, retenção — Termo v2.
- **P1-D** (Flag H): Substituir Adendo Retificativo Art. 4 por texto incorporado integralmente.
- **P1-E** (Flag J + DI-6): Silêncio positivo marcas/patentes 15d — Política 4.2.1 + Adendo Cooperação Art. 6.
- **P1-F** (DI-5): Retenção IRRF royalties — Política 4.5.4 (e) nova.

### P2 — Nice-to-have

- **P2-A** (Flag A): Refinar "ressalvado 2.6" → "ressalvada suspensão temporária".
- **P2-B** (Flag B): Cross-ref 2.4 → 2.6.
- **P2-C** (Flag G): Adendo Retificativo Art. 5 substituir Cláusula 4 explicitamente.
- **P2-D** (Flag I): Atualizar timeline Sumário Executivo.
- **P2-E** (DI-2): Nota Seção 11 sobre AI training vs. pesquisa acadêmica.
- **P2-F** (DI-4): Nota Seção 1.4/2 sobre GDPR para voluntários UE.
- **P2-G** (LGPD): Parágrafo único Cláusula 11 sobre revogação consentimento imagem.

### Red Flags

- **RF-1:** Adendo Retificativo Art. 4 — resolvido via P1-D.
- **RF-2:** Ausência de retenção IRRF — resolvido via P1-F, requer validação com especialista tributário antes de qualquer pagamento.
- **RF-3:** GDPR para voluntários UE — fora de escopo deste agente. Requer advogado europeu antes de formalização.
- **RF-4:** CC-BY-SA → CC-BY — resolvido via P1-B.

---

## 7. Assinatura

Revisão jurídica por legal-counsel agent (AI). Recomenda-se validação adicional por advogado humano brasileiro licenciado, indicado pelo Ivan Lourenço (PMI-GO), antes da ratificação formal pelos 52 voluntários e antes da entrada em vigor do Ciclo 4. Para os Red Flags RF-3 (GDPR) e RF-2 (fiscal), recomenda-se adicionalmente consulta com advogado europeu de proteção de dados e especialista tributário, respectivamente.

**Arquivos de referência auditados:**
- `/home/vitormrodovalho/Desktop/ai-pm-research-hub/tmp/ip-v2-md/00_Sumario_Executivo_CR050_v2.md`
- `/home/vitormrodovalho/Desktop/ai-pm-research-hub/tmp/ip-v2-md/01_Politica_Publicacao_IP_v2.md`
- `/home/vitormrodovalho/Desktop/ai-pm-research-hub/tmp/ip-v2-md/02_Termo_Voluntariado_R3-C3-IP_v2.md`
- `/home/vitormrodovalho/Desktop/ai-pm-research-hub/tmp/ip-v2-md/03_Adendo_Retificativo_Termo_v2.md`
- `/home/vitormrodovalho/Desktop/ai-pm-research-hub/tmp/ip-v2-md/04_Adendo_IP_Acordos_Cooperacao_v2.md`
