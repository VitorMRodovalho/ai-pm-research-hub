# Draft — Cláusula sobre Dados Enriquecidos (Termo Voluntariado R3-C3)

**Status:** Draft — para revisão jurídica + ratificação CR-050.
**Origem:** legal-counsel review N2 do Wave 5b spec (2026-04-30).
**Audiências:** PM (Vitor) → Roberto Macioni (advogado) → comitê CR-050 → presidentes capítulos PMI Brasil ratificação.

---

## Contexto

A plataforma Núcleo IA & GP processa duas categorias distintas de dados de candidatos voluntários:

1. **Dados originados no PMI VEP** (PMI Volunteer Experience Platform — operada por PMI Inc., EUA)
   - Inscrição inicial, formulário base, currículo (resume_url), perfil PMI público
   - Sob termos de uso PMI Inc. + transferência internacional sob ADR-0066 (PMI Journey v4)

2. **Dados enriquecidos pelo candidato** (gerados na plataforma brasileira pós-consent)
   - Edições de carta de motivação, formação acadêmica detalhada, experiência relevante, temas de interesse, links pessoais (LinkedIn, Credly), respostas a sugestões da IA
   - Coleta sob base legal LGPD: consentimento granular + interesse legítimo
   - Análises por IA (Google Gemini) geradas a partir desses dados — múltiplas versões preservadas para auditoria

A distinção entre as duas categorias tem implicações de propriedade intelectual e privacidade que precisam ser claras no Termo de Voluntariado R3-C3.

---

## Cláusula proposta

### Cláusula 9-A — Dados Enriquecidos pelo Candidato

**§1. Definição.** "Dados Enriquecidos" são todas as informações fornecidas pelo Candidato ao Núcleo IA & GP através da plataforma `nucleoia.vitormr.dev`, incluindo mas não limitado a: edições subsequentes de carta de motivação, descrições de formação acadêmica, experiência profissional relevante, propostas de tema de pesquisa, links de portfólio (LinkedIn, Credly, repositórios públicos), respostas a sugestões de fortalecimento de aplicação geradas por sistema de Inteligência Artificial, e quaisquer dados adicionais inseridos voluntariamente nos campos editáveis durante o processo seletivo.

**§2. Distinção dos dados PMI VEP.** Os Dados Enriquecidos são juridicamente distintos dos dados originalmente submetidos pelo Candidato à plataforma PMI Volunteer Experience Platform (PMI Inc.). Enquanto os dados PMI VEP são governados pelos termos de uso da PMI Inc., os Dados Enriquecidos coletados na plataforma brasileira do Núcleo IA & GP são tratados exclusivamente pelas regras estabelecidas neste Termo, pela Política de Privacidade do Núcleo (`/privacy`) e pela LGPD (Lei nº 13.709/2018).

**§3. Autoria e direitos morais.** Os Dados Enriquecidos constituem obra intelectual do Candidato, nos termos da Lei 9.610/98, Art. 7º (escritos de qualquer natureza). O Candidato preserva integralmente seus direitos morais sobre esses conteúdos.

**§4. Escopo de uso autorizado pelo Núcleo.** Ao fornecer Dados Enriquecidos, o Candidato concede ao Núcleo IA & GP, gerido pelo PMI-GO Capítulo Brasil como controlador, o direito não-exclusivo de:
- (a) processar os Dados Enriquecidos para fins exclusivos do processo seletivo voluntário em curso;
- (b) submeter os Dados Enriquecidos a análise automatizada por sistema de Inteligência Artificial (Google Gemini 2.5 Flash) sob consentimento expresso, registrado mediante carimbo temporal específico (`consent_ai_analysis_at`, `consent_ai_reanalysis_1_at`, `consent_ai_reanalysis_2_at`);
- (c) preservar versões históricas dos Dados Enriquecidos em tabela auditada (`ai_analysis_versions`) por prazo necessário ao processo seletivo, até o limite de 90 (noventa) dias após o encerramento do ciclo, para permitir revisão pelo comitê avaliador e eventual contestação pelo Candidato;
- (d) compartilhar os Dados Enriquecidos com membros do comitê avaliador habilitados (`manage_selection`) para fins exclusivos de avaliação humana da candidatura.

**§5. Vedação de uso comercial.** O Núcleo IA & GP não poderá utilizar os Dados Enriquecidos para fins comerciais, inclusive — mas não limitado a — treinamento de modelos próprios de IA, comercialização a terceiros, publicações com fins lucrativos, ou cessão para PMI Inc. ou qualquer outra entidade fora do escopo do processo seletivo voluntário, sem novo consentimento expresso e específico do Candidato.

**§6. Direito de retificação e exclusão.** O Candidato pode, a qualquer tempo, exercer os direitos previstos no Art. 18 da LGPD sobre os Dados Enriquecidos, incluindo:
- (i) retificação de dados incompletos, inexatos ou desatualizados (Art. 18, IV);
- (ii) exclusão dos dados pessoais tratados com base em consentimento (Art. 18, VI);
- (iii) revisão de decisões tomadas com base em tratamento automatizado (Art. 20).

A exclusão exercida pelo Candidato resultará em apagamento em cascata das versões históricas (`ai_analysis_versions`), logs de auditoria associados (`selection_topic_views`) e demais registros derivados, preservando-se apenas registros de contestação ativa, nos termos da LGPD Art. 16, II.

**§7. Decisão humana final.** Nenhuma decisão sobre admissão, recusa ou avanço do Candidato no processo seletivo será tomada exclusivamente com base em tratamento automatizado. A análise por Inteligência Artificial constitui ferramenta de apoio ao comitê humano, sem caráter vinculativo. Metadados como contagem de re-análises ou visualização de tópicos prováveis da entrevista são informativos e não podem ser utilizados como critério negativo de seleção. Esta cláusula é ratificada em ADR específico (ADR-0067, Art. 20 LGPD safeguards).

---

## Notas para revisão

1. **Roberto Macioni**: confirmar wording §3 sobre autoria — é "Dados Enriquecidos" obra intelectual ou apenas comunicação livre não-protegida por direito autoral? Ambos têm consequências, mas precisam clareza.
2. **Comitê CR-050**: a §6 (cascade delete) precisa ser tecnicamente verificável antes da ratificação — auditoria de FKs em `notifications`, `ai_analysis_runs`, `selection_topic_views` recomendada por legal-counsel.
3. **Presidentes PMI Brasil capítulos**: a distinção §2 entre PMI VEP (Inc.) e dados enriquecidos (BR) deve ser comunicada explicitamente em qualquer materiail externo (blog framework, abstract PMI Global Summit Detroit) para evitar ambiguidade institucional.
4. **PMI Inc. relação**: §5 veda cessão para PMI Inc. sem consent — mas PMI VEP já tem termos próprios. A cláusula respeita essa separação ou cria conflito? Roberto avalia.

## Próximos passos

- [ ] Roberto revisa wording (1-2h)
- [ ] PM consolida feedback + ajusta para v1.1
- [ ] Adicionar como Cláusula 9-A ao Termo R3-C3 v2.2 (CR-050 chain de aprovação)
- [ ] Comunicar aos 5 presidentes signatários atuais (PMI-GO, CE, DF, MG, RS) + 10 novos quando lista oficial chegar
- [ ] Ratificação durante o ciclo regular de aprovação CR-050 IP policy

## Status pré-publish framework blog

Esta cláusula é pré-requisito para publicação externa do framework MCP/Núcleo (blog reescrito + abstract PMI Global Summit Detroit) — sem ela, há ambiguidade jurídica sobre quem pode usar/citar dados enriquecidos em materiais públicos derivados.
