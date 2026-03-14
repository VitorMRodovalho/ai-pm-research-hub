# Propostas de Evolução — Manual de Governança R3

**Documento:** Propostas de Alteração ao Manual de Governança e Operações R2
**Referência:** GC-007 a GC-013
**Data:** 2026-03-14
**Propostas por:** Vitor Maia Rodovalho (GP) e Fabrício Costa (Co-GP)
**Para aprovação de:** Liderança dos Capítulos (Nível 1) conforme Seção 7 do Manual R2

---

## Contexto

Com a conclusão do processo seletivo do Ciclo 3 (1º Semestre 2026) e a expansão do Núcleo para 5 capítulos e 44 colaboradores ativos, foram identificadas oportunidades de melhoria nos processos de seleção, integração e governança operacional. As propostas a seguir são fundamentadas na experiência prática dos Ciclos 2 e 3, nas boas práticas de gestão de talentos em organizações de pesquisa, e no compromisso do Núcleo com transparência, mérito técnico e escalabilidade.

Cada proposta inclui: a redação atual do Manual, a alteração proposta, a justificativa técnica e o impacto na operação.

---

## GC-007 — Normalização da Escala de Avaliação para 0-10

**Data:** 2026-03-14 · **Autor:** Vitor Maia Rodovalho (GP)

**Estado atual (Manual R2, Seção 3.4, Tabela 3):**
A avaliação objetiva de pesquisadores utiliza escalas mistas: Certificação em GP usa 0-1, Disponibilidade usa 0-5, e os demais critérios usam 0-5. A avaliação qualitativa (entrevista) usa escalas de 1-4 e 1-3. A Tabela 2 (Líderes) usa escalas 0-5 uniformes.

**Alteração proposta:**
Padronizar TODAS as escalas de avaliação (objetiva e qualitativa) para **0-10**, tanto para pesquisadores quanto para líderes de tribo. Cada critério deve incluir uma **guia de calibração** com descrição do que se espera para as faixas 0-3 (não atende), 4-6 (atende parcialmente), 7-8 (atende bem) e 9-10 (supera expectativas).

**Justificativa:**
- Escalas mistas (0-1, 0-3, 0-5, 1-4) dificultam a comparabilidade entre critérios e entre avaliadores.
- A escala 0-10 oferece maior granularidade, permitindo diferenciar melhor candidatos em faixas intermediárias — exatamente onde as decisões são mais críticas.
- A guia de calibração reduz a subjetividade e alinha o entendimento dos avaliadores sobre o que cada faixa significa, prática comum em processos seletivos de organizações de pesquisa.
- Na avaliação do Ciclo 3, identificamos divergências significativas entre avaliadores em critérios específicos (exemplo: Carta de Motivação de um mesmo candidato recebeu 0 de um avaliador e 3 de outro), evidenciando a necessidade de calibração.

**Impacto na Tabela 3 (Pesquisadores):**

| Critério | Peso | Escala Atual | Escala Proposta |
|---|---|---|---|
| Certificação em GP | 2 | 0-1 | 0-10 |
| Experiência em Pesquisa | 2 | 0-5 | 0-10 |
| Conhecimento em GP | 3 | 0-5 | 0-10 |
| Conhecimento em IA | 3 | 0-5 | 0-10 |
| Habilidades Técnicas | 2 | 0-5 | 0-10 |
| Disponibilidade | 1 | 0-5 | 0-10 |
| Carta de Motivação | 2 | 0-5 | 0-10 |
| Comunicação (entrevista) | 1 | 1-4 | 0-10 |
| Proatividade (entrevista) | 1 | 1-3 | 0-10 |
| Trabalho em Equipe (entrevista) | 1 | 1-3 | 0-10 |
| Alinhamento Cultural (entrevista) | 1 | 1-3 | 0-10 |

**Consultorias envolvidas:**
- *HR Lead:* Confirma que escalas uniformes são padrão em processos seletivos estruturados. A calibração prévia entre avaliadores é prática obrigatória em grandes consultorias de RH.
- *Data Architect:* A normalização simplifica o cálculo de scores no sistema e permite comparações históricas entre ciclos.

---

## GC-008 — Comitê de Seleção Configurável

**Data:** 2026-03-14 · **Autor:** Vitor Maia Rodovalho (GP)

**Estado atual (Manual R2, Seção 3.4):**
"Dupla Avaliação: Dois avaliadores independentes aplicam a metodologia." Na prática, os avaliadores dos Ciclos 2 e 3 foram sempre o GP e o Co-GP.

**Alteração proposta:**
Formalizar a figura do **Comitê de Seleção**, composto por no mínimo 2 avaliadores designados pelo GP para cada ciclo. O comitê pode incluir Líderes de Tribo, membros do Comitê de Curadoria, ou outros colaboradores seniores com experiência relevante. O GP mantém poder de validação final das decisões caso não integre diretamente o comitê.

Adicionar ao Manual, Seção 3.4:

> *"A avaliação de candidatos é conduzida por um Comitê de Seleção designado pelo Gerente de Projeto para cada ciclo seletivo. O comitê deve ser composto por no mínimo dois avaliadores independentes, podendo incluir colaboradores dos Níveis 2 a 5 e membros do Comitê de Curadoria, priorizando diversidade de capítulos e experiências. Caso o Gerente de Projeto não integre diretamente o comitê avaliador, cabe-lhe a validação final das decisões de seleção."*

**Justificativa:**
- Com 5 capítulos, centralizar a avaliação em 2 pessoas cria gargalo operacional (SLA do Ciclo 3 foi 26 dias vs meta de 14 dias).
- A delegação para um comitê configurável permite escalar o processo sem perder qualidade.
- Líderes de Tribo são avaliadores naturais por conhecerem as necessidades específicas de suas tribos.
- A validação final do GP preserva a responsabilidade pela qualidade das decisões.

**Consultorias envolvidas:**
- *PM Consultant:* Comitês de seleção configuráveis são prática padrão em programas de voluntariado do PMI Global. A delegação com supervisão é princípio de liderança distribuída.
- *CXO:* Permite ao candidato ser avaliado por pessoas mais próximas do tema de interesse, melhorando a experiência e a precisão da alocação.

---

## GC-009 — Avaliação Blind (Às Cegas) Obrigatória

**Data:** 2026-03-14 · **Autor:** Vitor Maia Rodovalho (GP)

**Estado atual (Manual R2, Seção 3.4):**
"Dois avaliadores independentes aplicam a metodologia." O Manual menciona independência, mas não especifica mecanismo de isolamento.

**Alteração proposta:**
Formalizar que a avaliação é **blind** (às cegas): cada avaliador pontua de forma isolada, sem acesso às notas dos demais avaliadores até que todos tenham concluído suas avaliações. As notas só são reveladas (desbloqueadas) após submissão de todos os avaliadores designados para aquele candidato.

Adicionar ao Manual, Seção 3.4:

> *"A avaliação objetiva é conduzida de forma blind: cada membro do Comitê de Seleção atribui suas pontuações de forma isolada, sem visualizar as notas dos demais avaliadores. As pontuações individuais são reveladas apenas após todos os avaliadores designados terem concluído e submetido suas avaliações para o candidato em questão. Esta prática visa eliminar o viés de ancoragem e garantir julgamento genuinamente independente."*

**Justificativa:**
- No Ciclo 3, ambos os avaliadores pontuaram na mesma planilha. Ao scrollar horizontalmente, um podia ver as notas do outro — configurando viés de ancoragem.
- Exemplo concreto: para o candidato Hayala Curto, o Avaliador 1 atribuiu 0 em Carta de Motivação enquanto o Avaliador 2 atribuiu 3. Divergências desta magnitude sugerem critérios distintos ou influência mútua.
- A avaliação blind é padrão ouro em processos de peer review acadêmico e em processos seletivos de organizações como PMI Global, IEEE e ACM.

**Consultorias envolvidas:**
- *HR Lead:* O viés de ancoragem é um dos vieses cognitivos mais documentados em avaliações. A solução é simples: separação física (ou digital) dos formulários.
- *AI Engineer:* O sistema pode detectar automaticamente divergências acima de 3 pontos e sinalizar para calibração pós-avaliação, sem comprometer a independência durante o processo.

---

## GC-010 — Vaga Unificada com Faixa de Líder

**Data:** 2026-03-14 · **Autor:** Vitor Maia Rodovalho (GP)

**Estado atual (Manual R2, Seções 3.3 e 3.4):**
Os processos de seleção para Líder de Tribo (Nível 3) e Pesquisador (Nível 4) são descritos como processos distintos, com critérios e matrizes ponderadas diferentes (Tabelas 2 e 3).

**Alteração proposta:**
Unificar a vaga em um único processo seletivo. O candidato aplica uma vez e, no formulário, responde perguntas opcionais para quem deseja ser considerado para a função de Líder de Tribo. A jornada de avaliação inicia unificada (critérios de pesquisador), e candidatos com pontuação acima do percentil 90 ou identificados pelo Comitê como potenciais líderes recebem uma **pré-recomendação** de conversão. O fluxo de conversão é:

1. **Sistema pré-recomenda** (baseado em score + tags do avaliador)
2. **GP aprova** a recomendação
3. **Candidato aceita** o convite para continuar como Líder

Adicionar ao Manual, Seção 3.4:

> *"O processo seletivo utiliza vaga unificada. Candidatos interessados na função de Líder de Tribo respondem perguntas adicionais não obrigatórias no formulário de candidatura. A avaliação inicial segue os critérios da Tabela 3 (pesquisador). Candidatos com desempenho excepcional ou perfil identificado pelo Comitê de Seleção como adequado à liderança podem ser recomendados para avaliação complementar conforme critérios da Tabela 2. A conversão de pesquisador para líder requer aprovação do Gerente de Projeto e aceite formal do candidato."*

**Justificativa:**
- No Ciclo 3, 3 candidatos a pesquisador foram identificados como potenciais líderes (Alexandre Meirelles, Paulo Alves, Ana Carla Cavalcante) — todos foram convertidos informalmente. A proposta formaliza uma prática que já existe.
- Reduz fricção para o candidato: aplica-se uma vez, é avaliado uma vez, e o sistema identifica o melhor encaixe.
- Elimina o risco de perder bons líderes que não se candidataram por insegurança ou desconhecimento da função.

**Consultorias envolvidas:**
- *Product Lead:* Pipeline unificado com fork é padrão em plataformas de recrutamento (Greenhouse, Lever). Reduz abandono de candidatura por excesso de vagas.
- *CXO:* O candidato tem melhor experiência: aplica uma vez e descobre se é melhor pesquisador ou líder, em vez de ter que decidir antes de conhecer o projeto.

---

## GC-011 — Métricas de Diversidade no Processo Seletivo

**Data:** 2026-03-14 · **Autor:** Vitor Maia Rodovalho (GP)

**Estado atual (Manual R2):**
Não há menção a rastreamento de diversidade no processo seletivo. A Seção 3.4 menciona apenas "distribuição proporcional entre capítulos" como meta de equilíbrio.

**Alteração proposta:**
Formalizar o rastreamento e reporte de métricas de diversidade em cada ciclo seletivo, abrangendo as seguintes dimensões: distribuição por capítulo, gênero, faixa etária, senioridade profissional, setor de atuação (público/privado/acadêmico/terceiro setor), indústria e região geográfica.

Adicionar ao Manual, Seção 3.4 (Distribuição e Alocação):

> *"O Comitê de Seleção, em conjunto com o Gerente de Projeto, acompanhará métricas de diversidade do processo seletivo, incluindo mas não se limitando a: distribuição por capítulo, gênero, senioridade, setor de atuação e região. Estas métricas serão reportadas ao final de cada ciclo como parte do relatório de seleção e utilizadas como subsídio para estratégias de captação em ciclos futuros, visando ampliar a representatividade e a riqueza de perspectivas no Núcleo."*

**Justificativa:**
- Pesquisa e desenvolvimento de qualidade requerem diversidade de perspectivas: idade, senioridade, indústria, setor e região influenciam diretamente a riqueza das análises produzidas.
- Dados do Ciclo 3 mostram desequilíbrio: PMI-GO tem 15 membros, PMI-RS tem 2. Sem métricas formais, não há como direcionar esforços de captação.
- O PMI Global valoriza explicitamente D&I em suas diretrizes estratégicas (PMI: NEXT). Reportar métricas de diversidade fortalece a posição do Núcleo perante o PMI.
- As métricas são agregadas (sem dados pessoais identificáveis), em conformidade com a LGPD.

**Consultorias envolvidas:**
- *HR Lead:* Diversidade mensurável é pré-requisito para programas de melhoria. Sem baseline, não há como definir metas.
- *PM Consultant (FP&A):* As métricas podem alimentar o dashboard de capítulo (W115) e o relatório executivo de ciclo (W105), criando visibilidade para sponsors.

---

## GC-012 — Onboarding Estruturado em 7 Etapas com SLA

**Data:** 2026-03-14 · **Autor:** Vitor Maia Rodovalho (GP)

**Estado atual (Manual R2, Seção 3.8.1):**
O onboarding é descrito em prosa genérica: "orientação estruturada que inclui apresentação da missão, alocação funcional, acesso às ferramentas, sessão de orientação e pareamento com colaborador experiente." Não há etapas definidas, prazos ou critérios de conclusão.

**Alteração proposta:**
Substituir a descrição genérica por um **checklist formal de 7 etapas** com prazos (SLA) e critério de conclusão mensuráveis:

| Etapa | Descrição | SLA | Evidência |
|---|---|---|---|
| 1. Aceitar convite na plataforma | Cadastro no Hub do Núcleo | 48h | Registro no sistema |
| 2. Completar perfil | Bio, LinkedIn, disponibilidade, interesses | 3 dias | Perfil ≥ 80% completo |
| 3. Aceitar posição no PMI VEP | Aceite formal na plataforma de voluntários do PMI Global | 7 dias | Print da confirmação |
| 4. Completar curso Kickoff PMI | Pelo menos um módulo (Preditivo ou Ágil, 45 min) | 7 dias | Badge/certificado |
| 5. Assinar Termo de Voluntariado | Assinatura eletrônica do Termo de Adesão | 14 dias | Documento assinado |
| 6. Entrar nos canais de comunicação | Grupo geral + grupo da tribo alocada | 7 dias | Confirmação do líder |
| 7. Participar do Kick-off do projeto | Reunião geral de abertura do ciclo | Até kick-off | Registro de presença |

Atualizar a Seção 3.8.1:

> *"Todo colaborador selecionado passará por um processo de integração estruturado em sete etapas sequenciais, cada uma com prazo definido e evidência de conclusão. O progresso é acompanhado pela plataforma digital do Núcleo e reportado ao Gerente de Projeto. O colaborador é considerado 'Ativo' e apto a iniciar suas contribuições nas tribos somente após a conclusão de todas as etapas obrigatórias."*

**Justificativa:**
- No Ciclo 2, o onboarding de 12 membros levou 4 dias. No Ciclo 3, com 44 membros, levou 22 dias — evidenciando que o processo manual não escala.
- Análise do chat de WhatsApp do grupo de onboarding revelou: confusão sobre o que é obrigatório vs opcional, emails perdidos, termos confeccionados manualmente um a um, e ausência de visibilidade sobre quem já concluiu cada etapa.
- Etapas e SLAs definidos permitem automação (notificações de lembrete, alertas de atraso) e prestação de contas transparente.

**Consultorias envolvidas:**
- *Onboarding Lead:* O checklist digital é prática padrão em RH. Cada etapa deve ter owner (quem é responsável), deadline, e fallback (o que acontece se atrasar).
- *CXO:* O novo membro tem clareza total do que precisa fazer e em qual ordem. Elimina a ansiedade de "será que estou fazendo certo?".

---

## GC-013 — SLA e Fórmula de Corte no Processo Seletivo

**Data:** 2026-03-14 · **Autor:** Vitor Maia Rodovalho (GP)

**Estado atual (Manual R2, Seção 3.4):**
Não há SLA definido para as etapas do processo seletivo, nem fórmula explícita de corte para decisão de aprovação/reprovação.

**Alteração proposta:**
Formalizar SLAs por etapa do processo seletivo e a fórmula estatística de corte.

**SLA por etapa:**

| Etapa | Prazo máximo |
|---|---|
| Período de inscrições | 14-21 dias (definido por ciclo) |
| Triagem de requisitos mínimos | 3 dias úteis após encerramento |
| Avaliação objetiva | 7 dias úteis |
| Agendamento de entrevistas | 5 dias úteis |
| Realização das entrevistas | 7 dias úteis |
| Decisão final e comunicação | 3 dias úteis |
| **Total máximo** | **~35 dias úteis (~7 semanas)** |

**Fórmula de consolidação (PERT entre avaliadores):**

> *Score consolidado = (2 × Menor nota + 4 × Média das notas + 2 × Maior nota) ÷ 8*

**Fórmula de corte:**

> *Threshold de corte = Mediana dos scores consolidados × 0,75*

Candidatos abaixo do threshold na avaliação objetiva não avançam para entrevista. Candidatos abaixo do threshold após a pontuação final (objetiva + entrevista) são reprovados. O resultado é comunicado com feedback estruturado.

Adicionar ao Manual, Seção 3.4:

> *"O processo seletivo opera com prazos definidos por etapa (SLA), acompanhados pelo Gerente de Projeto e reportados à Liderança dos Capítulos. A consolidação das pontuações entre avaliadores utiliza estimativa PERT ponderada. O threshold de corte é calculado como 75% da mediana dos scores consolidados, aplicado em duas etapas: após a avaliação objetiva (gate para entrevista) e após a pontuação final (gate para aprovação). Candidatos não aprovados recebem feedback estruturado e são elegíveis para recandidatura em ciclos futuros."*

**Justificativa:**
- O Ciclo 3 não tinha SLA formal. O processo levou 26 dias desde o início das avaliações até a comunicação final, com picos de ociosidade entre etapas.
- A fórmula PERT (já utilizada informalmente no Ciclo 3) atenua outliers sem ignorá-los, sendo mais robusta que média simples.
- O corte a 75% da mediana foi calibrado no Ciclo 3 e produziu resultados alinhados com o julgamento qualitativo dos avaliadores.
- Feedback estruturado para reprovados é prática de respeito ao candidato e fortalece a reputação do programa para ciclos futuros.

**Consultorias envolvidas:**
- *PM Consultant:* SLAs são fundamentais para gestão de expectativas. Sem eles, o processo se estende indefinidamente e perde credibilidade.
- *Data Architect:* A fórmula PERT e o threshold são calculáveis automaticamente pelo sistema, eliminando decisões ad hoc.

---

## Próximos Passos

1. **Apresentação** destas propostas à Liderança dos Capítulos (Nível 1) para apreciação
2. **Período de análise** de 7 dias úteis para comentários e sugestões
3. **Aprovação** por consenso conforme Seção 7 do Manual R2
4. **Publicação** como Adendo ao Manual de Governança R2 (ou incorporação ao R3)
5. **Registro** no GOVERNANCE_CHANGELOG.md (GC-007 a GC-013)
6. **Implementação** na plataforma digital do Núcleo (W124 — Selection Pipeline Digital)

---

*Este documento foi preparado com base na análise do processo seletivo do Ciclo 3, mapeamento da jornada de onboarding via WhatsApp, e dados extraídos da planilha de seleção, calendário de entrevistas e Manual de Governança R2.*
