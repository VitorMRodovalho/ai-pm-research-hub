# Benchmark: vídeo assíncrono para a avaliação e conversa ao vivo para fit

**Pedido do GP (01/10/2026), em B3:** a entrevista ao vivo como momento de conexão, com as perguntas já respondidas por vídeo (a avaliação completa) e a conversa servindo para validação, dúvidas e fit com os objetivos da pesquisa e as competências pedidas.

**Como foi feito:**
- A pesquisa foi feita por um agente, em web, OpenAlex, Crossref e fontes oficiais.
- [lido] quer dizer que o agente abriu o texto; [só resumo] quer dizer que viu só o resumo.
- O Scholar Gateway falhou, e o artigo "Into the void" (Lukacik, Bourdage e Roulin, 2022) ficou atrás de paywall, sem citação.
- **Conferido por mim na fonte primária em 01/10/2026:**
  - **PL 2338/2023:** a API da Câmara mostra "Aguardando Parecer", com última movimentação em 02/09/2026. Não é lei.
  - **EU AI Act:** o Regulamento 2026/1744 adia o alto risco do Anexo III para 02/12/2027.
- O resto é leitura do agente: bem fundamentado, mas não verificado por mim.

## Achados principais

**Estrutura é o que decide a qualidade:**
- Pela meta-análise de Sackett et al. (2022, reproduzida em 2023), a validade média é **.42** na entrevista estruturada e **.19** na não estruturada [lido].
- A confiabilidade é **.74** com banca de 2 ou mais pessoas e **.44** com entrevistas separadas, o formato atual do Núcleo (Huffcutt et al., 2013) [só resumo].

**O vídeo funciona quando é estruturado:**
- **Concordância:** com 2 avaliadores treinados e rubrica com âncoras, o índice de concordância (ICC) ficou em .94 (Basch et al., 2021) [lido].
- **Validade:** num estudo simulado com 229 pessoas, o vídeo previu o desempenho tão bem quanto a entrevista presencial (Germanier et al., 2025) [só resumo].
- **Tempo de preparo:** melhora a nota sem aumentar a autoapresentação enganosa [lido].
- **Tempo de resposta:** o limite de 3 minutos foi o melhor (Orji e Bangerter, 2025) [só resumo].
- **Regravar:** só oferecer a opção não muda o resultado [só resumo].
- **Formatos:** não misturar vídeo e videoconferência na mesma etapa, porque o vídeo dá notas maiores (Langer et al., 2017) [só resumo].

**Reação do candidato:**
- O vídeo é visto como mais invasivo e menos pessoal, e há risco de desistência (Langer et al., 2017) [só resumo].
- Com 27.809 candidatos reais, preparo e a opção de regravar melhoraram a reação; mais perguntas pioraram, sobretudo acima de 31 anos (Tilston et al., 2024) [só resumo].
- Explicar por que o processo é padronizado melhora a justiça percebida (Basch e Melchers, 2019) [só resumo].
- Avaliação feita por algoritmo piora a justiça percebida (Oostrom et al., 2024) [só resumo].

**IA e autoria:** respostas lidas do ChatGPT tiraram nota maior em conteúdo (Canagasuriam e Lukacik, 2025) [só resumo]. Aprofundar ao vivo as histórias do vídeo confere a autoria.

**Fit sem estrutura é a porta do viés de similaridade:**
- Rivera (2012), com 120 entrevistas: fit virou semelhança de lazer e de trajetória, e pesava mais que a competência [lido].
- Combinar dados "no olho" perde validade; combinar por fórmula melhora a previsão em mais de 50% (Kuncel et al., 2013) [só resumo].
- ⇒ O fit deve pontuar com âncoras e peso fixo, definidos antes, e não ser um parecer livre que vira veto.

**Casos análogos:**
- **Google Summer of Code:** o mentor ranqueia, e o guia diz para não escolher sem contato prévio [lido].
- **Outreachy:** ensaio, depois cerca de 4 semanas de contribuição, e o mentor escolhe. As regras proíbem escolher por relação prévia ou país, e lembram que basta uma sobreposição de 2 a 3 horas de fuso com o mentor [lido].
- **Wikimedia (mentores Outreachy):** microtarefas, depois entrevista online com rubrica [lido]. É o caso mais parecido com o modelo do GP.
- **AAMC (vídeo padronizado para residência médica, 2017 a 2020):** era confiável e válido, mas foi abandonado. Os avaliadores não usavam a nota, e menos de um quarto dos candidatos sentiu que conseguiu mostrar as suas habilidades [lido].
- **VEP do PMI:** o recrutador do capítulo revisa os candidatos e oferece a vaga. Não há orientação pública sobre entrevista estruturada [lido].

**Regulação:**
- **EU AI Act:**
  - IA para avaliar candidatos é de alto risco (Anexo III, 4a), com aplicação adiada para 02/12/2027 (conferido).
  - Inferir emoção no trabalho e na educação é proibido desde 02/02/2025 (Art. 5(1)(f)) [lido].
- **Illinois (AI Video Interview Act, desde 2020):** aviso, explicação, consentimento, compartilhamento só com quem avalia e exclusão em 30 dias a pedido [lido].
- **PL 2338:** classifica a avaliação de candidatos como alto risco, mas não é lei (conferido).
- **LGPD:** a imagem pode revelar raça ou deficiência, então convém tratar o vídeo como dado sensível, com consentimento específico e destacado (Art. 11). Se a IA só transcreve e um humano decide com rubrica, o Art. 20 não se aplica. É leitura do agente, não parecer jurídico.
  > **Nota de 03/10/2026:** o parecer jurídico de 21/09/2026 conclui que imagem e voz não atraem o art. 11 sem tratamento biométrico para identificação, e que a base pode ser o art. 7º, V ou o consentimento. A leitura acima sobre o art. 11 foi superada; ver a Emenda de 03/10/2026 na ADR-0134.

**Acessibilidade:**
- **Celular:** 65% de quem usa internet no Brasil acessa só pelo celular, e 39% de quem tem celular ficou sem dados ao menos uma vez em 3 meses (TIC Domicílios 2025) [lido].
- **Fundo da gravação:** vaza sinais de classe e de partido [só resumo].
- **Guia do governo britânico (2024):** pede formato alternativo e não usar contato visual como sinal de engajamento [lido].

## Condições de desenho
1. **Perguntas:** 3 a 5 por linha, sobre experiências passadas, reveladas só na hora de gravar.
2. **Tempos:** preparo de 30 a 60 s, 1 regravação e até 3 min por resposta. Configuração escolhida de propósito e igual para todos.
3. **Avaliação do vídeo:** 2 avaliadores independentes, rubrica com âncoras, nota antes da discussão e calibragem prévia com vídeos de exemplo.
4. **Conversa ao vivo:** aprofunda 1 ou 2 histórias do vídeo e avalia o fit com critérios escritos (horas, fuso, idioma, competências da linha, alinhamento ao objetivo da pesquisa), com âncoras e peso fixo. Nada de afinidade nem de hobbies.
5. **Alternativa ao vivo** sem pedir justificativa, com as mesmas perguntas e a mesma rubrica, registrando o formato.
6. **Comunicação:** explicar o porquê, dar aviso de privacidade, aceitar gravação pelo celular e orientar sobre o fundo.
7. **IA:** só transcrição e legenda. Sem nota automática e sem análise de rosto, voz ou emoção. Consentimento destacado, retenção curta e decisão humana.

## O que medir no piloto
- quantos concluem o vídeo e em que pergunta param;
- quantos pedem a alternativa ao vivo;
- concordância (ICC) entre os 2 avaliadores por pergunta;
- quantas decisões a conversa mudou, e com que critério escrito;
- minutos de avaliador por candidato;
- reação do candidato em 3 a 5 itens;
- distribuição por gênero, idade, país e idioma;
- presença e entregas aos 3 e 6 meses.

Com poucas vagas, o piloto mostra direção, não prova. As regras de decisão são definidas antes.

## Fontes
- **S1.** Sackett, Zhang, Berry & Lievens (2023), IOP 16(3):283-300, doi:10.1017/iop.2023.24.
- **S3.** Huffcutt, Culbertson & Weyhrauch (2013), IJSA 21(3):264-276, doi:10.1111/ijsa.12036.
- **S4.** Campion, Palmer & Campion (1997), Pers. Psych. 50(3):655-702; Levashina et al. (2014), Pers. Psych. 67(1):241-293, doi:10.1111/peps.12052.
- **S5.** Basch et al. (2021), IJSA 29:378-392, doi:10.1111/ijsa.12341.
- **S6.** Roulin, Wong, Langer & Bourdage (2023), EJWOP 32(3):333-345, doi:10.1080/1359432X.2022.2156862.
- **S7.** Lukacik & Bourdage (2025), IJSA 33(1), doi:10.1111/ijsa.12511.
- **S8.** Germanier et al. (2025), Human Performance 38(5):284-298, doi:10.1080/08959285.2025.2580653.
- **S9.** Orji & Bangerter (2025), IJSA 33(4), doi:10.1111/ijsa.70031.
- **S10.** Langer, König & Krause (2017), IJSA 25(4):371-382, doi:10.1111/ijsa.12191.
- **S11.** Tilston et al. (2024), HRM 63(2):313-332, doi:10.1002/hrm.22202.
- **S12.** Canagasuriam & Lukacik (2025), IJSA 33(1), doi:10.1111/ijsa.12491.
- **S13.** Basch & Melchers (2019), PAD 5(3), doi:10.25035/pad.2019.03.002.
- **S15.** Oostrom et al. (2024), JOOP 97(1):160-189, doi:10.1111/joop.12465.
- **S16.** Dunlop, Holtrop & Wee (2022), IJSA 30(3):448-455, doi:10.1111/ijsa.12372.
- **S17.** Rivera (2012), ASR 77(6):999-1022, doi:10.1177/0003122412463213.
- **S18.** Cable & Judge (1997), JAP 82(4):546-561, doi:10.1037/0021-9010.82.4.546.
- **S19.** Kuncel et al. (2013), JAP 98(6):1060-1072, doi:10.1037/a0034156.
- **S20.** https://google.github.io/gsocguides/mentor/selecting-a-student ; https://www.outreachy.org/docs/applicant/ ; https://www.outreachy.org/mentor/mentor-faq/ ; https://www.mediawiki.org/wiki/Outreachy/Mentors
- **S21.** "Volunteer Recruitment Made Easy with VEP" (PMI LIM LatAm, 2025) e https://pmihouston.org/volunteering/volunteer-faqs
- **S22.** Gallahue et al. (2020), Acad. Med. 95(11):1639-1642, doi:10.1097/ACM.0000000000003573.
- **S23.** https://www.ama-assn.org/medical-students/preparing-residency/fade-black-why-aamc-scrapped-standardized-video-interview
- **S24.** Posselt (2016), Inside Graduate Admissions, Harvard UP [só resumo].
- **S25 a S27.** https://artificialintelligenceact.eu/annex/3/ ; https://artificialintelligenceact.eu/ai-act-explorer/digital-omnibus/ ; https://artificialintelligenceact.eu/article/5/
- **S28.** https://www.ilga.gov/Legislation/ILCS/Articles?ActID=4015&ChapterID=68
- **S29.** https://dadosabertos.camara.leg.br/api/v2/proposicoes/2487262
- **S30.** https://www.planalto.gov.br/ccivil_03/_ato2015-2018/2018/lei/l13709compilado.htm
- **S31.** https://cetic.br/media/analises/tic_domicilios_2025_principais_resultados.pdf
- **S32.** Roulin et al. (2023), JOB 44(3):458-475, doi:10.1002/job.2680.
- **S33.** Springle & Bourdage (2025), IJSA 33(1), doi:10.1111/ijsa.12504.
- **S34.** https://www.gov.uk/government/publications/responsible-ai-in-recruitment-guide/responsible-ai-in-recruitment
