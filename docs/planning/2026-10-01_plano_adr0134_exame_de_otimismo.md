# Plano da ADR-0134 e exame de otimismo

**Pedido do GP (A1, 01/10/2026):** fazer a ADR e o plano inteiro antes do piloto, "para ver se não estamos sendo otimistas ou se algo não teria que ser corrigido ou melhorado em conjunto".

**Base:** medições de 01/10/2026 no banco e no código. Prazos marcados como **estimativa** não são medição.

---

## 1. O tamanho real da mudança (medido)

| O que | Medido | O que isso quer dizer |
|---|---|---|
| Funções `SECURITY DEFINER` que leem `selection_applications` | 145 | o portão por vaga não pode mexer em todas: são funções novas com escopo, e as atuais seguem para o comitê |
| Funções que usam `is_selection_committee_member` | 6 | é o inventário da leitura pelo comitê que o portão novo espelha |
| Caminhos que escrevem avaliação | `submit_evaluation`, `submit_interview_scores`, `mirror_sibling_interview` e 2 de importação | o impedimento do líder precisa estar em todos |
| Caminhos que escrevem entrevista | `schedule_interview`, `sync_calendar_booking_to_interview` e 1 de importação | a conversa de fit reaproveita esses |
| Caminhos que escrevem vídeo | `register_video_screening`, `opt_out_all_pillars` e a exclusão LGPD | o vídeo novo passa por eles |
| Onde estão as perguntas do vídeo | 4 lugares: o portal (`PMIOnboardingPortal.tsx`), 2 Edge Functions e o MCP | perguntas por vaga exigem fonte única antes |
| Quem chama `approve_selection_application` | `admin_update_application`, `finalize_decisions` e o verificador de invariantes | a entrada na tribo pela aprovação entra na função canônica |
| Rotinas agendadas de seleção ativas | 10 | cada uma precisa ser conferida contra "por candidatura, não por fase" |
| Testes de contrato que citam as tabelas | candidaturas 76, comitê 31, entrevistas 20, avaliações 11, convites de tribo 7, vídeo 6, vagas 5 | toda mudança tem guard por perto; ler os guards antes de escrever (regra do repo) |

**O análogo mais próximo de velocidade:** o módulo de competições (ADR-0133) foi da aprovação da ADR, em 30/09, a duas fases em produção, no mesmo dia. Mas era um esquema novo e isolado. Aqui se mexe num fluxo vivo, com 76 testes ao redor e um ciclo aberto. **O código não é o gargalo. Gente e governança são.**

---

## 2. Etapas e dependências

| # | Etapa | Depende de | Quem | Prazo (estimativa) |
|---|---|---|---|---|
| 0 | Consertos que vão juntos (seção 4) | nada | sessão orquestradora | 2 a 4 dias de sessão |
| 1 | ADR-0134 aceita | revisão do GP | GP | dias |
| 1b | Change request de piloto sob a R2 (P1): vídeo como avaliação qualitativa, matriz 35/45/20 com fit, perguntas da linha ancoradas na Tabela 3, com prazo e reversão | 1; confirmar quem aprova o CR | GP submete | **desconhecido**: há 16 CRs submetidos e parados |
| 2 | Revisão jurídica do mínimo do piloto: texto do consentimento do vídeo, aviso de privacidade da vaga e categoria de retenção do vídeo | 1 | DPO ou conselho jurídico | **desconhecido**, caminho crítico |
| 3 | Migration 1, modelo: vaga com organização, iniciativa e ciclo; perguntas em camadas; declaração de IA; tipos de avaliação vídeo e fit; pesos; vínculo de avaliador | 1 | orquestradora | 1 semana |
| 4 | Migration 2, portão: ação nova por vaga e por atribuição; impedimento na escrita e no despachante; entrada na tribo pela aprovação | 3 | orquestradora | 1 semana |
| 5 | Vídeo novo: perguntas da vaga reveladas na hora, tempo de preparo, 1 regravação, celular; perguntas numa fonte só; IA só transcreve | 3 | orquestradora | 1 a 2 semanas, com teste em celular |
| 6 | Comunicação: retorno em 2 modelos (tipo novo no catálogo), alerta de prazo, texto da vaga e da etapa de vídeo nas 3 línguas | 3 | orquestradora + GP aprova textos | 3 a 5 dias |
| 7 | Avaliadores convidados: convite, vínculo e calibragem com vídeos de exemplo | 1 | GP convida; orquestradora prepara a calibragem | **2 a 3 semanas**, caminho crítico |
| 8 | Vaga da Tribo 15: texto aprovado, postada no VEP pelo PMI-GO e incluída na lista de importação | 3, 6 | GP, ponto focal do PMI-GO, líder | dias, depois do resto |
| 9 | Piloto rodando, com as regras de decisão escritas antes | 1b, 2, 4, 5, 7, 8 | todos | 4 a 6 semanas de vaga aberta |
| 10 | Leitura do piloto e ajuste para o ciclo 5 | 9 | GP | 1 semana |

**Leitura honesta (estimativa):** com as etapas 2 e 7 em paralelo às de código, a vaga piloto abre na segunda quinzena de novembro, e o resultado sai entre dezembro e janeiro. Antes de decidir A1, a minha recomendação era "começa em dias". Esse era o otimismo.

---

## 3. Exame de otimismo: o que estamos supondo, e o que pode dar errado

| # | Suposição | O que pode dar errado | Sinal medido | O que fazer |
|---|---|---|---|---|
| E1 | O candidato grava o vídeo | quando era opcional, 40 preferiram ao vivo e 1 gravou; com a alternativa ao vivo sem justificativa, a maioria pode voltar ao ao vivo, e o modelo vira "entrevista estruturada" | 1 em 96 | explicar o porquê na vaga, vídeo-convite do líder, celular, preparo e regravação; medir a conclusão e decidir antes o que conta como sucesso |
| E2 | Existem vídeos de exemplo para calibrar | **não existem:** o único vídeo real é de um candidato e não pode virar material de treino sem consentimento | 1 vídeo, de candidato | gravar respostas de exemplo com voluntários (líderes, ex-líderes), em níveis diferentes da rubrica |
| E3 | Há avaliadores para convidar | o grupo é pequeno e voluntário, e cada vídeo exige 2 notas | 3 avaliadores efetivos hoje; conta para o ciclo 4: 332 avaliações | começar o convite já, em paralelo. No piloto (P2), 2 líderes de outras linhas avaliam o vídeo e convidados fazem a objetiva: o GP convida 4 pessoas e 1 reserva |
| E4 | A revisão jurídica é rápida | o vídeo como dado sensível pede consentimento destacado, e a retenção por categoria é decisão jurídica | sem medida de prazo do DPO | separar o mínimo do piloto (consentimento do vídeo, aviso, retenção do vídeo) do resto (retenção geral, parceria), e mandar o mínimo primeiro |
| E5 | O Manual acompanha | a seção nova da R3 não sai a tempo | o rascunho da R3 foi criado em 02/04 e nunca mais atualizado; 16 change requests submetidos parados; o último foi criado em 03/07 | **não pendurar o piloto na R3.** A R2 não comporta o modelo sem mudança: fixa entrevista pelos Níveis 2 e 3, a matriz Subtotal 1 + Subtotal 2 e os critérios da Tabela 3. Decidido (P1): change request de piloto sob a R2, com prazo e reversão, e a R3 incorpora para o ciclo 5. Risco que sobra: quem aprova o CR e em quanto tempo |
| E6 | O ciclo 4 aguenta mais uma vaga | o ciclo segue em `evaluating`; qualquer mudança de fase dispara o detector com defeito | 91 de 93 alertas, simulado | conserto do detector na etapa 0, antes de tudo; não mudar a fase do ciclo 4 |
| E7 | O rodízio respeita a vaga | o despachante já tem defeitos abertos, e um rodízio "por vaga" herda todos | issues abertas #2188, #1762, #2408 | consertar junto na etapa 4 |
| E8 | A Tribo 15 espera | a tribo começa em 06/10 e a vaga abre em novembro | na Liderança de 01/10/2026, o GP informou que a 15ª tribo é lançada sem recrutamento interno | a tribo começa só com o líder e recebe pesquisadores pelo piloto; não se encaminham para ela aprovados do ciclo 4 |
| E9 | O líder tem tempo para a conversa de fit | o líder também conduz a tribo; uma conversa por finalista | entrevista mediana de 30 min | fit só com finalistas (depois de objetiva e vídeo), com teto por vaga |
| E10 | Os pesos (35, 45 e 20) estão certos | não há dado para calibrar o fit antes | nenhum ciclo teve nota de fit | o piloto testa; a regra de decisão e a revisão dos pesos ficam escritas antes |
| E11 | Notas de vídeo e de ao vivo são comparáveis | o benchmark mostra que o vídeo dá notas maiores que a videoconferência | literatura (Langer et al., 2017) | registrar o formato e comparar as notas por formato antes de ranquear junto |
| E12 | Poucas vagas dão uma resposta | com poucas candidaturas, os números indicam direção, não provam | piloto pequeno por desenho | regra de decisão escrita antes de abrir (pergunta aberta 3 da ADR) |

---

## 4. O que corrigir junto (etapa 0)

Cada item está medido, e todos tocam o que o redesenho vai mexer:

1. **Detector de divergência** (emenda à ADR-0059). Hoje dispara só na troca de fase, com limiar de outra escala, e mistura tipos de avaliação.
2. **Entrevistas sem entrevistador:** 20 das 72 entrevistas feitas não guardam quem entrevistou. Sem isso, o impedimento do líder e a carga por avaliador não se medem.
3. **#2392:** aprovados com uma avaliação objetiva só, contra o mínimo de 2. O modelo novo depende desse mínimo.
4. **Cadastro de tribo do membro defasado do engajamento:** na Tribo 1, 6 contra 7; na Tribo 7, 3 contra 5. O painel de ocupação por linha precisa ler o engajamento.
5. **Perguntas do vídeo fixas em 4 lugares.** Uma fonte só antes de virar "por vaga".
6. **Rodízio:** #2188 (despacha sem horário livre na agenda), #1762 (empate no lote) e #2408 (leitura de agenda atrasada), antes de ensiná-lo a respeitar a vaga.

---

## 5. Regras de decisão do piloto (decididas pelo GP em 01/10/2026, P3)

- **Quando vale como sinal:** com pelo menos 6 candidatos que cheguem ao vídeo. Abaixo disso, a vaga é estendida.
- **O vídeo funcionou** se pelo menos metade dos convidados concluir e a concordância entre os 2 avaliadores for boa na maioria das perguntas.
- **O fit ficou estruturado** se toda mudança de decisão causada pela conversa citar um critério escrito.
- **O GP saiu da mesa** se as entrevistas e avaliações do GP no piloto forem só as de calibragem e de desempate.
- **A comunicação foi cumprida** se 100% dos candidatos receberam retorno até 45 dias.
- **O que olhar depois:** presença e entregas dos selecionados aos 3 e aos 6 meses.
