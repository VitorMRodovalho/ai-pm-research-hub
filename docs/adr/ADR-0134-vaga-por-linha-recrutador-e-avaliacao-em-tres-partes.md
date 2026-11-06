# ADR-0134 - Vaga por linha de pesquisa e por organização: recrutador, avaliação em três partes e mecanismos por candidatura

**Status:** Aceita (02/10/2026). Aprovada pelo GP nesta data ("1 e 2 aprovados para seguir"), depois das decisões de 01/10/2026, tomadas uma a uma sobre um caderno com contexto medido, opções e recomendação. Emendada em 03/10/2026 (base legal do vídeo) e em 06/11/2026 (o líder da vaga na objetiva), nas seções do fim.
**Pedido:** [#2393](https://github.com/VitorMRodovalho/ai-pm-research-hub/issues/2393) (direção do GP em 20/09/2026: vaga por tema de pesquisa, com o líder da tribo na seleção). Esta ADR responde as quatro perguntas que a #2393 deixou abertas.
**Insumo:**
- gap assessment do processo de vagas, com revisão nas três personas (candidatura, GP e líder recrutador, capítulo e parceiro);
- benchmark externo sobre vídeo assíncrono e conversa de fit, com 34 fontes;
- leitura de 21 ADRs de seleção, organização e LGPD.

Os três documentos são de 01/10/2026.
**Relacionadas:** ADR-0004, 0005, 0007, 0009, 0012, 0022, 0059, 0061, 0066, 0067, 0074, 0076, 0079, 0093, 0104, 0105, 0109, 0111, 0121, 0123, 0127, 0128, 0131, 0133.

---

## Contexto (medido em 01/10/2026, ciclo `cycle4-2026`)

**Uma vaga para tudo.** O Núcleo posta no VEP uma vaga única para todas as linhas de pesquisa. `vep_opportunities` não tem organização nem iniciativa, e a candidatura cai no ciclo aberto mais recente. O tema de interesse foi registrado em 3 de 72 entrevistas, então a plataforma não sabe para qual linha a maioria se candidatou.

**A tribo é escolhida depois, em outra rodada.** A aprovação cria o vínculo sem iniciativa, e a pessoa pede entrada numa tribo depois, com prazo e teto únicos.
- Dos 64 aprovados, 9 pesquisadores ainda estão sem tribo.
- Uma tribo tem 0 pesquisadores, outra 1 e outra 2. Nada no fluxo olha para isso.

**O líder não entrevista porque não está no comitê.**
- Só 1 dos 14 líderes de tribo ativos está no comitê do ciclo.
- Das 72 avaliações de entrevista, 68 foram do GP e do deputy.
- Quem é do comitê lê o ciclo inteiro (`get_selection_dashboard`, #1591): no ciclo 4, as 96 candidaturas. Não existe leitura limitada a uma vaga.

**A entrevista é o formato menos confiável.** É uma pessoa sozinha, ao vivo, e sem rubrica de fit. A dupla avaliação do Manual mora só na objetiva.

**O vídeo não é etapa de fato.**
- 1 de 96 candidaturas enviou vídeo; 40 escolheram a entrevista ao vivo, e 55 não têm registro.
- As 5 perguntas são genéricas e estão fixas em 4 lugares do código.
- A vaga no VEP não menciona o vídeo.

**A IA não pesa na nota.** A fórmula do ciclo soma objetiva e entrevista. A nota objetiva média de quem recusou a análise por IA (150,4) é maior que a de quem aceitou (147,3). Não existe declaração de uso de IA pelo candidato.

**Retorno ao reprovado quase não existe.**
- Só 1 dos 13 reprovados teve retorno, e o Manual R2 pede retorno estruturado.
- 12 dos 13 têm notas do avaliador por critério.
- O detalhamento da nota só aparece ao aprovado, e só na fase de anúncio.

**O ciclo virou entrada contínua, mas os mecanismos são de lote.** O ciclo 4 abriu em 15/05, recebeu candidaturas até 10/09 e segue em `evaluating`. O detector de divergência entre avaliadores (ADR-0059) só roda na passagem para `evaluations_closed`, e por isso nunca rodou. Ele também tem dois defeitos:
- limiar de escala de 0 a 10, com notas que vão de 23 a 245;
- objetiva e entrevista misturadas no mesmo cálculo.

Calculado como está, marcaria 91 de 93 candidaturas. A divergência real é outra: 10 de 91 candidaturas têm diferença acima de 30% da média.

**Retenção divergente.** A política ativa guarda a candidatura por 1825 dias e depois anonimiza. O vídeo não tem política. As ADRs falam em 90 e 180 dias, 12 meses e 3 anos.

**Prazos.** Da candidatura à primeira entrevista, a mediana é de 18,4 dias e o p90 de 44,3. Da candidatura à oferta no VEP, a mediana é de 16,6 dias e o p90 de 48,6.

---

## Decisão

### 1. A vaga é uma entidade com dono

- `vep_opportunities` ganha:
  - `organization_id` (obrigatório, ADR-0004);
  - `initiative_id` (opcional: vazio é a vaga geral, preenchido é a vaga da linha; aponta para `initiatives`, nunca para `tribes`, pelas ADRs 0005 e 0012);
  - `cycle_id`;
  - o texto da vaga versionado, que é a fonte do que se copia para o VEP.
- **O recrutador não é uma coluna que concede leitura.** Ele deriva do vínculo de liderança na iniciativa da vaga (ADRs 0007 e 0131).
- **A vaga por linha convive com a vaga geral.** A geral vira banco de talentos que o comitê distribui. Abre vaga de linha quem tem líder disponível para recrutar.
- **Cada pessoa tenta até 2 vagas.** Quem não entra numa linha vai para a vaga geral **só com consentimento**, por `consent_records` (versionado e revogável, como na ADR-0133), com aviso.
- **No VEP:**
  - o capítulo posta a vaga, com o e-mail institucional do Núcleo como contato;
  - o líder recruta só na plataforma;
  - a importação continua centralizada (ADR-0066), e a lista de vagas do script de extração passa a sair das vagas ativas.

### 2. Perguntas em três camadas, versionadas

Geral (Núcleo), organização e linha. A candidatura guarda o par pergunta e resposta. O `essay_mapping` passa a ser gerado das camadas, e não escrito à mão. A camada geral inclui:
- disponibilidade em horas por semana, com a carga declarada igual na vaga e na pergunta;
- a declaração de uso de IA (seção 5).

### 3. Avaliação em três partes, com pesos fixos

| Parte | Quem | Como | Peso |
|---|---|---|---|
| Objetiva (currículo e respostas) | o líder da vaga e 1 avaliador de fora da linha (emenda de 06/11/2026) | régua do ciclo | 35% |
| Vídeo estruturado | 2 avaliadores de fora da linha | rubrica com âncoras por pergunta, escrita com o líder; nota antes da discussão | 45% |
| Conversa de fit | líder da linha | critérios escritos antes (horas, fuso, idioma, competências da linha, alinhamento ao objetivo da pesquisa), com âncoras; aprofunda 1 ou 2 histórias do vídeo e confere a autoria | 20% |

- Os pesos são a proposta que o piloto testa.
- O fit tem um mínimo para casos extremos, com justificativa escrita. **Não é veto livre:** o benchmark mostra que fit sem estrutura vira semelhança com o avaliador.
- **O vídeo:**
  - 3 a 5 perguntas da linha, sobre experiências passadas, reveladas só na hora de gravar;
  - 30 a 60 s de preparo, 1 regravação e até 3 min por resposta, com configuração igual para todos;
  - gravação pelo celular aceita;
  - a vaga explica por que o formato é padronizado.
- **Alternativa ao vivo:** quem não quiser ou não puder gravar faz a mesma etapa ao vivo, com as mesmas perguntas e a mesma rubrica, sem precisar justificar. O formato fica registrado, e as notas são comparadas por formato.
- **A resposta à #2393 ("voto ou parecer"):** o líder dá nota de fit com peso fixo. A decisão final fica com o comitê, e a aprovação continua com o GP (ADR-0109: "selection-admin = GP-only by design").

### 4. Independência e impedimento

- **O líder fica impedido da avaliação do vídeo da própria vaga.** Na objetiva, ele avalia com 1 avaliador de fora da linha, e nenhuma outra pessoa com vínculo na linha entra (emenda de 06/11/2026). O impedimento vale na escrita (`submit_evaluation`, `submit_interview_scores`) **e** no despachante automático de avaliações (ADR-0022, D-sel-5). Esta ADR abre o lado da escrita que a ADR-0109 não cobre, com o precedente da ADR-0133 (3-B).
- **Avaliadores de fora da linha:** o comitê é ampliado por convite, com avaliadores voluntários como pesquisadores seniores e ex-líderes.
  - A autoridade vem de um vínculo próprio de avaliador (ADR-0007), com calibragem prévia obrigatória.
  - Cada avaliador lê só as candidaturas atribuídas a ele.
- **No piloto (P2):** o vídeo é avaliado por 2 líderes de outras linhas que aceitarem. São Nível 3, como a R2 pede na avaliação qualitativa. A objetiva fica com o líder da vaga e 1 avaliador de fora da linha, os dois calibrados (emenda de 06/11/2026). Antes da emenda, ficava com convidados: o GP convidaria 4 pessoas e 1 reserva. O convite amplo é a direção para o ciclo 5, junto com a R3.
- Revisão cega (ADR-0059) e recusa por conflito (ADR-0109) seguem valendo.

### 5. IA

- **A declaração de uso de IA pelo candidato entra já no piloto.** É uma pergunta curta (usou IA? para quê?) com compromisso de autoria.
  - Não é critério negativo e não ordena nem filtra o painel (ADR-0067, D1 e D2).
  - Fica fora do prompt da triagem por IA (ADR-0076, P4).
- A vaga diz: "declarar uso de IA ou recusar a análise por IA não reduz a nota".
- **Supersessão registrada:** o "Gate 1" da ADR-0066, IA antes da entrevista, já foi aposentado no código (#1640) sem ADR. Esta ADR registra essa supersessão.
- **No vídeo, a IA só transcreve e legenda.** Sem nota automática e sem análise de rosto, voz ou emoção. Avaliar candidatos com IA é alto risco no EU AI Act (Anexo III, aplicação em 02/12/2027) e no PL 2338/2023 (não é lei em 01/10/2026). Inferir emoção no trabalho é proibido na UE.
- O vídeo tem consentimento específico e destacado, e a alternativa ao vivo continua sem pedir justificativa. É uma escolha de cautela do Núcleo, não uma exigência do art. 11 da LGPD; a base legal fica para o Encarregado confirmar (emendado em 03/10/2026, ver a Emenda no fim).

### 6. Leitura por vaga (portão novo, antes do piloto)

- Uma ação nova, com escopo de vaga e de atribuição. **Não reusa** `view_internal_analytics` (ADR-0111) e não dá lugar no comitê do ciclo.
- Cobre as 6 superfícies de seleção da ADR-0109 e o roteiro de entrevista por IA, que hoje exige `view_pii` (ADR-0074).
- Aplica o portão de iniciativa confidencial (ADR-0105) e registra o acesso em `pii_access_log`.
- Autoridade só de vínculo autoritativo (ADR-0121).
- O resumo semanal ao líder não leva nome de candidato (ADR-0022, emendas B e C).

### 7. Da aprovação à tribo

Na vaga de uma linha, a aprovação cria o vínculo na iniciativa da vaga, pela função canônica `approve_selection_application` (ADR-0093). Isso emenda a ADR-0123, que hoje só admite o pedido de entrada ou a via de admin. O pedido de entrada na tribo continua para a vaga geral.

### 8. Retorno, prazos e mecanismos por candidatura

- **Retorno obrigatório para fechar a vaga, com dois modelos:**
  - retorno estruturado para quem foi avaliado, montado das notas por critério e revisado por uma pessoa;
  - mensagem de encerramento para quem não seguiu.
  - Ganha tipo próprio no catálogo de notificações, com modo de entrega e relação com o `suppress_all` declarados (ADR-0022). O precedente é a ADR-0133 (4-B).
- **Prazos declarados na vaga:**
  - até 21 dias para o convite do vídeo ou da conversa;
  - até 45 dias para o resultado;
  - alerta ao GP no resumo semanal quando estoura (precedente: `selection_interview_overdue`);
  - os números são revistos depois do piloto.
- **Por candidatura, não por fase do ciclo:** o detector de divergência, o detalhamento ao candidato, o retorno e a revisão cega passam a disparar por candidatura. Emenda à ADR-0059:
  - limiar relativo por tipo de avaliação (proposta: diferença acima de 30% da média);
  - disparo quando chega a 2ª nota;
  - o caso marcado vai a um 3º avaliador e à calibragem.
- **A fase do ciclo 4 não muda antes desse conserto.**

### 9. Retenção por categoria

Um prazo por categoria, cada um com a sua base legal, decidido com revisão jurídica:
- reprovado e não selecionado;
- aprovado;
- banco geral com consentimento;
- vídeo e análise de IA.

O vídeo e a análise de IA ganham política já. Os prazos de retenção das ADRs 0067, 0074, 0076 e 0079 passam a contar da decisão da candidatura, e não do ciclo.

### 10. Organização e parceria

- **Dentro do hub do Núcleo:** o PMI-GO segue controlador e único capítulo contratante (ADR-0104), e o capítulo que posta responde pela publicação.
- **Outra organização no mesmo motor:** é controladora dos seus candidatos e assina os seus termos, com o Núcleo como operador. Isso exige:
  - isolamento por organização em toda leitura;
  - revisão do `auth_org()` (ADR-0077) para pessoas em duas organizações;
  - provavelmente o change request dos 5 capítulos (ADR-0076, S2).
- Revisão jurídica antes de abrir para fora. Não é preciso para o piloto.

### 11. Capítulo na candidatura

O capítulo pedido nas boas-vindas a quem veio sem ele é **autodeclarado**, nunca canônico (ADR-0104). "Não sou filiado" vira o motivo registrado (ADR-0128). O relatório por capítulo usa a filiação canônica quando ela existir. Normalizar por grafia é vedado: "PMI-RIO" junta dois capítulos (ADR-0127).

---

## Emendas, supersessões e propostas absorvidas

| ADR | O que muda |
|---|---|
| 0059 (Aceita) | detector de divergência e revisão cega por candidatura (seção 8) |
| 0066 (Aceita) | "Gate 1" registrado como superado (#1640); o vídeo assíncrono ganha perguntas próprias, porque a R2 queria as da entrevista vistas ao vivo |
| 0109 (Aceita) | o impedimento passa a valer também na escrita (seção 4) |
| 0123 (Aceita) | a aprovação na vaga de uma linha cria o vínculo na tribo (seção 7) |
| 0067 (Proposta) | ratificada junto, com prazos reancorados por candidatura |
| 0076 (Proposta) | P3, P4 e P6 absorvidos, com a retenção da seção 9 |
| 0079 (Proposta) | **rejeitada:** a premissa (comitê sem tempo de ver vídeos) caiu com 1 vídeo em 96, e nota automática a partir de vídeo é o uso de alto risco que a seção 5 exclui |
| 0078 (Proposta) | fora de escopo (revisor externo de documentos de governança) |

## Invariantes

- A aprovação final é do GP. A IA nunca decide (ADR-0067).
- Dupla avaliação: 2 objetivas, do líder da vaga e de 1 avaliador de fora da linha, e 2 de vídeo, de fora da linha. Na objetiva, no máximo 1 avaliador de dentro da linha por candidatura, e só o líder da vaga (emenda de 06/11/2026).
- A divergência entre as duas notas de uma parte é sinalizada por candidatura (ADR-0059, emendada pela seção 8) e chega a quem decide.
- Revisão cega e recusa por conflito (ADRs 0059 e 0109).
- Leitura de candidatura só com escopo, com registro em `pii_access_log`. Nenhuma superfície nova reusa `view_internal_analytics`.
- Toda entrada nova de aprovação passa pela função canônica (ADR-0093).
- `organization_id` em toda tabela e RPC nova (ADR-0004).

## Consequências

- O GP e o deputy saem do papel de entrevistadores de quase todos os candidatos. O custo se desloca para avaliadores convidados, que precisam ser recrutados e calibrados.
- O candidato escolhe a linha ao se candidatar, sabe de antemão que há vídeo e prazo, e recebe retorno.
- A vaga passa a ter funil próprio, o que dá o relatório por linha e por capítulo que hoje não existe.
- O motor fica pronto para outra organização, mas só a revisão jurídica libera esse uso.

## Alternativas rejeitadas

- **Líder no comitê do ciclo:** abre as 96 candidaturas para entrevistar poucas.
- **Entrevista ao vivo como avaliação, com vídeo opcional:** mantém o formato menos confiável e a carga no GP.
- **Vídeo obrigatório sem alternativa ao vivo:** sem acomodação para quem não pode gravar.
- **Líder recrutador nomeado no VEP:** decidido pelo contato institucional.
- **Os 14 líderes avaliando todas as outras linhas, como regra do ciclo 5:** preterido pelo comitê ampliado por convite. No piloto, os líderes de outras linhas avaliam o vídeo (P2).
- **Controlador por vaga dentro do hub:** conflita com a ADR-0104.
- **Capítulo por lista fechada como valor canônico:** vedado pela ADR-0104.

## Base no Manual e regras do piloto (decididas pelo GP em 01/10/2026)

**P1. Change request de piloto sob a R2.** A seção 3.4 da R2 fixa três coisas que este modelo muda:
- a avaliação qualitativa é entrevista conduzida pelos Níveis 2 e 3;
- a matriz é "Total = Subtotal 1 + Subtotal 2";
- os critérios qualitativos são os da Tabela 3 (Comunicação, Proatividade e Iniciativa, Trabalho em Equipe, Alinhamento Cultural).

O rascunho da R3 está parado desde 02/04/2026. Por isso, um change request autoriza **só para o piloto**:
- o vídeo como avaliação qualitativa;
- a matriz 35/45/20 com fit;
- as perguntas da linha, ancoradas nos critérios da Tabela 3, que viram as dimensões da rubrica.

O CR tem prazo e regra de reversão, e a R3 incorpora a mudança para o ciclo 5. **Antes de submeter, confirmar quem aprova o CR.** Na plataforma há 35 CRs implementados e 16 submetidos parados.

**P2. Avaliadores do piloto.** Ver a seção 4.

**P3. Regra de decisão do piloto, fixada antes de abrir.**
- **Quando o piloto vale como sinal:** com pelo menos 6 candidatos que cheguem ao vídeo. Abaixo disso, a vaga é estendida.
- **Funcionou se:**
  - metade ou mais dos convidados concluir o vídeo;
  - os 2 avaliadores concordarem na maioria das perguntas;
  - toda mudança de decisão vinda da conversa de fit citar um critério escrito;
  - 100% dos candidatos receberem retorno em até 45 dias.
- **Depois:** presença e entregas dos selecionados aos 3 e aos 6 meses.

## Plano

Em `docs/planning/2026-10-01_plano_adr0134_exame_de_otimismo.md`, com etapas, dependências e o exame de otimismo pedido pelo GP em A1. O benchmark está em `docs/research/2026-10-01_benchmark_video_assincrono_e_fit.md`.

## Emenda (03/10/2026, #2393): base legal do vídeo

**O que dizia.** A seção 5 tratava o vídeo como dado sensível, com consentimento específico e destacado, citando o art. 11 da LGPD. A frase veio do benchmark de 01/10, que se declarava leitura do agente e não parecer jurídico.

**Por que mudou.** O parecer jurídico de 21/09/2026, da revisão voluntária dos instrumentos do Núcleo, já respondia a essa pergunta para os usos da plataforma:
- foto, vídeo e voz são dados pessoais comuns;
- só viram dado biométrico sensível quando passam por tratamento técnico para identificar ou autenticar alguém de forma inequívoca, o que não acontece aqui: a IA só transcreve e legenda, sem reconhecimento facial, sem identificação de voz e sem template biométrico;
- a base legal pode ser o art. 7º, V (procedimento pré-contratual) ou o consentimento;
- o ponto de maior atenção é o art. 20, sobre decisão automatizada e pontuação.

O mesmo parecer recomendou retirar a classificação de imagem e voz como categoria especial do art. 11 nos instrumentos.

**Decisão do GP (03/10/2026, opção A de três):** corrigir agora, com texto neutro.
- O consentimento específico e destacado do vídeo continua, junto com a alternativa ao vivo, como escolha de cautela.
- A base legal do vídeo fica para o Encarregado confirmar. O pedido segue junto com a revisão mínima do piloto: texto do consentimento, aviso da vaga e prazo de guarda do vídeo.
- O art. 20 já está atendido pelo desenho da seção 5: no vídeo a IA não dá nota, e a decisão é sempre humana. A triagem por IA que já existe continua opcional, com consentimento próprio, e não entra na nota.

**Opções descartadas:**
- esperar a resposta do Encarregado para corrigir uma vez só, deixando até lá a ADR dizer o contrário do parecer;
- manter o art. 11 por cautela, contra a recomendação expressa do parecer.

**Fora desta emenda:** o Acordo de Operador (Doc 09) na plataforma ainda está na v1, de 11/06/2026, e a cláusula 4.4 dele ainda trata imagem e voz como dado sensível do art. 11. A correção ali é uma versão nova do documento, em trilha própria.

A linha E4 do plano e o benchmark de 01/10 foram ajustados na mesma mudança.

## Nota de execução (03/11/2026, #2967): seção 5 no vídeo

A função de borda `analyze-application-video` passa a só transcrever: Whisper e gravação do texto em `pmi_video_screenings`. Ela não chama modelo de texto, não baixa a miniatura do Drive, não lê o campo de nome e não grava em `selection_evaluation_ai_suggestions`. A descrição da ferramenta `analyze_application_video` no MCP reflete o mesmo contrato. Guard: `tests/contracts/analyze-application-video-transcription-only.test.mjs`.

## Emenda (06/11/2026, #2393): na objetiva, o líder da vaga com 1 avaliador de fora

**O que dizia.** A seção 4 impedia o líder da vaga nas duas partes avaliadas por pessoas, a objetiva e o vídeo. As 2 notas de cada parte vinham de fora da linha, e o líder só entrava no fit.

**Decisão do GP (06/11/2026).** O líder da vaga entra na objetiva, ao lado de 1 avaliador de fora da linha. O GP pesou duas coisas: o líder não deve decidir sozinho a entrada, e o processo não deve travar nem deixar o dono da vaga fora da análise. O avaliador de fora tira o viés da linha, seja o GP no alfa ou outra pessoa sem vínculo com ela depois.

**O motivo: auditoria no lugar de controle.** Impedir o líder é controle: a regra evita o viés antes que ele aconteça, ao custo de recrutar, calibrar e acompanhar mais convidados para cada vaga. Com várias linhas abrindo vaga, esse custo não escala. A emenda troca o controle por auditoria: o líder avalia, e uma divergência grande entre a nota dele e a da pessoa de fora vira sinal para quem decide.

**Como fica.**

| Parte | Quem avalia |
|---|---|
| Objetiva | o líder da vaga e 1 avaliador de fora da linha, os dois calibrados |
| Vídeo | 2 avaliadores de fora da linha, sem mudança |
| Fit | o líder da vaga, sem mudança |

- Na objetiva, entra no máximo 1 avaliador de dentro da linha por candidatura, e só com vínculo de líder ativo na iniciativa da vaga. Qualquer outro vínculo na linha continua impedido nas duas partes.
- A regra é conferida na atribuição e de novo a cada uso, pela regra única de quem avalia. Se a pessoa de fora entrar na linha depois de atribuída, as duas atribuições daquela candidatura param, e a gestão refaz.
- A decisão final continua com o comitê, e a aprovação, com o GP (ADR-0109).

**O farol.**
- **Agora, humano.** O detector de divergência por candidatura (ADR-0059, emendada pela seção 8) marca a candidatura quando a maior nota de uma parte passa a menor em mais de 30% da média. O caso marcado vai para a revisão da gestão. Para isso, o sinal precisa chegar a quem decide. Em 06/11, ele só era gravado e ainda não chegava a nenhuma tela nem aviso. Fazer o sinal chegar é condição desta emenda, e não melhoria futura.
- **Depois do alfa, a IA como mais um sinal.** Comparar a triagem por IA com a nota humana, com as escalas normalizadas, só onde o candidato consentiu na análise por IA. A IA nunca decide nem entra na nota (ADR-0067, D1; seção 5 desta ADR).

**Risco conhecido.** Quando o avaliador de fora também é da gestão, ele pode ler as notas do piloto como gestão. Nesse caso, a independência entre as duas notas fica por conduta, e não por trava do sistema. O texto ao candidato deixou de prometer que nenhum avaliador vê a nota do outro.

**Execução.** Uma migration troca o impedimento por vínculo na linha, nas funções de atribuição e de quem avalia, por uma regra única por candidatura e por parte. O texto de "quem avalia" no portal do candidato muda nas 3 línguas (#3014).
