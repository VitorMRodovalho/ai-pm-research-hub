# Parecer legal-counsel — ADR-0079 (subjective scoring por vídeo)

**Resumo executivo**

A proposta é viável juridicamente com ajustes. Ponto mais robusto: arquitetura de non-binding score (D-NON-BIND=A), condição necessária — mas não suficiente — para afastar incidência plena do Art. 20 §1 LGPD. Os dois pontos de maior risco residual: (1) reuso do consentimento `consent_ai_analysis_at` sem adendo de escopo para análise subjetiva de conteúdo de vídeo, tratamento materialmente distinto da análise de currículo/narrativa; (2) ausência de banner/disclosure obrigatório ao titular informando que vídeos são objeto de scoring automatizado por IA, exigência decorrente do Art. 9 LGPD independente da base legal. Demais aspectos (retenção, revoke, export) defensáveis com ajustes. **Veredicto: APROVADO COM AJUSTES — não bloqueia implementação, mas 3 medidas devem preceder deploy em produção com candidatos reais.**

---

## 1. Análise Art. 20 §1 LGPD (D-NON-BIND)

**Texto legal pertinente.** Art. 20 caput LGPD: direito ao titular de solicitar revisão de "decisões tomadas unicamente com base em tratamento automatizado de dados pessoais que afetem seus interesses". §1: controlador deve fornecer "informações claras e adequadas a respeito dos critérios e dos procedimentos utilizados para a decisão automatizada".

**Tese da spec.** Score 0-10 nunca entra em `final_score`. Fórmula consome exclusivamente `selection_evaluations` humanas. Score IA é "signal visual" para comitê humano.

**Análise.** Arquitetura materialmente compatível com exigência de human-in-the-loop que elimina o "unicamente" do Art. 20. Doutrina dominante (Bioni, Schertel Mendes, Doneda) e GDPR Art. 22 — referência interpretativa consolidada pela ANPD: human-in-the-loop com efetiva capacidade decisória elimina "unicamente". Palavra-chave: "efetiva". Comitê precisa ter acesso ao score IA como input entre vários — não como única informação prática.

**Risco residual.** Se na prática operacional o score IA se tornar heurístico dominante (anchoring), e registro humano for mera ratificação formal, regulador pode requalificar como "unicamente automatizada" substancialmente. ANPD em Nota Técnica sobre IA de 2023 (orientativa) sinaliza este risco: humano "fantasma" que não agrega julgamento real não afasta Art. 20.

**Salvaguardas adicionais recomendadas:**

(a) **Invariante de código (já na spec, R4):** `final_score` computed NÃO referencia `ai_subjective_score_avg`. Contract test CI auditando body via `pg_get_functiondef`. Salvaguarda técnica mais sólida.

(b) **Banner UI obrigatório:** quando avaliador humano vê score IA, texto visível: "Score gerado por IA — informação de apoio. Decisão final é exclusivamente de competência do Comitê de Curadoria." Sem banner, score pode induzir ancoragem cognitiva não documentada.

(c) **Audit de divergência deliberada:** calibration view registra não apenas correlação estatística mas casos em que comitê deliberadamente divergiu do score IA e motivo. Evidência de genuine human deliberation.

(d) **Template de resposta a pedido de revisão Art. 20 §1:** deve demonstrar decisão tomada por avaliadores humanos com base em `selection_evaluations`, documentando quais avaliadores, critérios e como score IA foi apenas um elemento de suporte.

---

## 2. Base legal — consent reuse ou consent dedicado (D-CONSENT)

**Texto legal pertinente.** Art. 7 I LGPD: consentimento livre, informado e inequívoco para finalidade determinada. Art. 8 §§4-5: revogação a qualquer momento; cessão refere-se a finalidades determinadas. Art. 5 XII: consentimento = manifestação livre, informada e inequívoca pela qual titular concorda com tratamento para finalidade determinada.

**Ponto crítico.** `consent_ai_analysis_at` foi criado no contexto ADR-0074 (análise IA de currículo/narrativa/triage). Proposta reusa para análise subjetiva de conteúdo de vídeo.

**Análise.** Há gap de especificidade de escopo. Análise IA de conteúdo de vídeo (transcrição + scoring de perfil comportamental/comunicacional) é materialmente distinta de currículo ou respostas textuais. Art. 7 I e Art. 5 XII exigem consentimento vinculado à finalidade determinada. Se titular ao dar `consent_ai_analysis_at` entendeu que autorizava análise de dados de candidatura (texto, CV, formulário), extensão para "análise IA qualitativa do conteúdo de meus vídeos com geração de score por pillar" pode não estar coberta.

Risco maior porque: (a) vídeo é modalidade mais invasiva — contém informações paralinguísticas (dicção, ritmo, vocabulário); (b) "scoring subjetivo" por IA (Comunicação, Pensamento Crítico) é avaliação de perfil comportamental que mesmo baseada só em transcrição textual revela características de personalidade.

**Recomendação. Duas opções juridicamente defensáveis:**

**Opção preferida (menor risco):** Criar `consent_subjective_video_scoring_at`. Apresentar disclosure específico ao candidato no momento de upload: *"Ao submeter vídeos, você autoriza que o Núcleo IA use inteligência artificial para transcrever e analisar o conteúdo das suas respostas, gerando pontuações por pilar como sinal de suporte para o Comitê de Curadoria. Você pode revogar este consentimento a qualquer momento. [aceitar / recusar]"*. Custo operacional: coluna + tela de consent na jornada de upload (aproveitar modal existente Phase B).

**Opção alternativa (defensável com adendo):** Manter `consent_ai_analysis_at` mas acrescentar ao texto de disclosure menção a "incluindo análise de conteúdo de vídeos submetidos, com geração de score qualitativo por pilar como sinal de apoio ao Comitê". Antes do próximo ciclo com vídeos (Cycle 5+), candidatos com consent anterior recebem re-disclosure com prazo de revogação de 30 dias. Defensável porque finalidade-mãe ("processo seletivo") é a mesma; muda modalidade de tratamento.

Para Cycle 4 (Eduardo Luz), Opção 2 com re-disclosure retroativo antes do scoring cobriria a lacuna. Recomendo Opção 1 para Cycle 5+ por maior robustez.

**Quanto ao Art. 11 (dados sensíveis):** transcrição de vídeo não é dado sensível na acepção do Art. 11. Scoring de "perfil de comunicação" por transcrição textual não se enquadra nos incisos. Base legal Art. 7 I (consent) ou Art. 7 IX (legítimo interesse) suficiente — não necessário Art. 11.

---

## 3. Direito Art. 18 — export de reasoning (D-EXPORT)

**Texto legal.** Art. 18 II: direito de "acesso aos dados" em tratamento. Art. 18 V: "portabilidade dos dados". Art. 20 §1: "informações claras sobre critérios e procedimentos".

**Qualificação do `reasoning`.** Campo `video_screening_analysis.reasoning` (texto livre ≤500 chars gerado pela IA descrevendo pontos fortes/lacunas) é dado pessoal do titular nos termos do Art. 5 I: "informação referente a pessoa natural identificada ou identificável". Reasoning descreve o candidato por nome (ou por application_id referenciado a ele) — dado pessoal derivado. Não é dado "do controlador" nem propriedade intelectual do modelo — é output sobre a pessoa.

**Conclusão D-EXPORT.** D-EXPORT=A (incluir reasoning no export) é juridicamente mais segura, alinhada com Art. 18 II e Art. 20 §1 (critérios e procedimentos). Omitir defensável somente se reasoning fosse dado exclusivo do controlador sem referência identificável — não é o caso.

**Recomendação adicional.** Export deve incluir também: (a) nome do modelo (`model` + `model_version`); (b) `prompt_hash` (não prompt completo, mas identificação para auditoria); (c) `confidence`; (d) `score` numérico; (e) data de processamento. Atende Art. 20 §1 e demonstra transparência perante ANPD.

---

## 4. Retenção e revoke

**Retenção 90d/180d (Art. 16 LGPD).**

Art. 16 estabelece eliminação após término do tratamento, ressalvadas hipóteses legais. Retenção 90d (não-selecionados) e 180d (selecionados) baseada em `cycle_decision_date` é razoável e defensável como "prazo necessário para exercício regular de direitos" — análogo a prazo de defesa processual.

Para `video_screening_analysis`, prazo deve seguir mesmo cron que `selection_applications` — dados derivados perdem finalidade simultaneamente. Não há razão jurídica para retenção diferenciada de outputs IA vs dados fonte.

**Ponto de atenção:** `prompt_hash` e `transcription_hash` na tabela não são dados pessoais (hashes sem reversibilidade prática), portanto podem ser retidos além dos prazos para auditoria de modelo sem violar Art. 16. Recomendo manter registro de auditoria de hashes em `ai_processing_log` mesmo após purge dos dados pessoais — atende Art. 37.

**Revoke trigger 72h.**

Art. 18 IV combinado com Art. 8 §5: revogação a qualquer momento, mediante manifestação expressa gratuita, facilitada. Lei não estipula prazo máximo de execução. Res. ANPD 2/2022 (Regulamento direitos dos titulares) estabelece 15 dias úteis para responder solicitações — mas refere-se à resposta, não ao tempo de execução técnica.

72h proposto é mais favorável que prazo ANPD, não conflita. **Risco operacional:** se sistema falhar e purge não ocorrer em 72h, controlador em situação de inadimplência com próprio compromisso. Recomendo: (a) monitoramento ativo do revoke queue (job alerta se `consent_ai_analysis_revoked_at IS NOT NULL AND rows não purged > 72h`); (b) **SLA comunicado ao titular como "até 5 dias úteis"** na tela de revogação, mesmo que sistema execute em 72h internamente. Protege controlador de inadimplência por falha técnica transitória.

---

## 5. Impacto na Política IP / Termo de Adesão (Material/Editorial change)

**Verificação de escopo existente.** Com base na leitura do handoff v2.7-p150 (docs/drafts/v2.7_p150_termo_voluntario_handoff.md) e ADR-0076 (Princípio 2 — base legal por field): Termo Adesão e Política IP v2.7 contemplam análise IA de curricula/dados de candidatura, triage por IA (ADR-0074), e tratamento de dados de processo seletivo. **NÃO há menção explícita** a "scoring automatizado de conteúdo de vídeos" ou "avaliação qualitativa de vídeos por IA com geração de score por pilar".

**Classificação da mudança. Material change** nos termos da Política §12.2:

1. Introduz nova modalidade de tratamento (análise IA de conteúdo de vídeo) não prevista nos instrumentos vigentes;
2. Afeta direitos do titular: gera output (score + reasoning) sobre perfil comportamental que ficará retido e será exportável;
3. Implica nova camada de processamento por IA com finalidade distinta da triage.

**Consequência direta (gate de ship):** Funcionalidade NÃO deve ser habilitada para candidatos reais (Cycle 4 ou Cycle 5) até que Termo de Adesão v2.7/v2.8 e/ou disclosure de consent reflitam explicitamente esta modalidade. Para Eduardo Luz (Cycle 4): necessário re-disclosure específico antes de rodar EF, ainda que mensagem individual via plataforma.

**Texto sugerido para adendo:**

*"O processo seletivo pode incluir o uso de sistemas de inteligência artificial para transcrever e analisar o conteúdo de vídeos submetidos pelo candidato, gerando pontuações numéricas (0-10) e avaliações qualitativas por pilar de competência. Esses outputs são utilizados exclusivamente como sinal de apoio ao Comitê de Curadoria, que é a instância decisória final, e não determinam automaticamente o resultado do processo. O candidato tem direito de acesso aos outputs gerados, de revogar o consentimento para este tratamento e de solicitar revisão da decisão ao Comitê."*

---

## 6. Justificativa econômica IA (Art. 9 §2)

Art. 9 exige que controlador informe ao titular a finalidade. §2: tratamento por legítimo interesse, controlador deve disponibilizar informação clara sobre legitimidade.

Spec documenta finalidade operacional (§0, §1) mas em documento interno. **Recomendação:** criar parágrafo de "Justificativa de tratamento por IA" em documento visível ao titular (Política de Privacidade ou Termo de Adesão), articulando: (a) finalidade: apoio ao processo seletivo; (b) necessidade: volume inviabiliza revisão humana integral; (c) salvaguardas: não-vinculação à decisão final, revisão humana obrigatória, direitos de acesso e revogação. Análogo ao LIA document que ADR-0076 prevê para Art. 7 IX.

---

## 7. Riscos residuais para ANPD

**R-L1 — Requalificação Art. 20 por anchoring cognitivo.** Se calibration view mostrar alta correlação (Pearson r > 0.85) entre score IA e avaliação final ao longo de múltiplos ciclos, ANPD pode interpretar humano como mero ratificador. Mitigação: manter audit de divergências deliberadas + documentar casos onde comitê decidiu contrariamente ao score IA com justificativa. Periodicidade: cada ciclo.

**R-L2 — Consent gap para candidatos de ciclos anteriores.** Cycle 3 e 4 (Eduardo Luz) deram consent para análise IA antes desta funcionalidade. Se scoring rodar sobre vídeos já submetidos sem re-disclosure, controlador trata dados com finalidade não prevista no consent original. EF validará `consent_ai_analysis_at IS NOT NULL` — mas não resolve gap de finalidade.

**R-L3 — Ausência de notificação ao titular da ocorrência do scoring.** LGPD Art. 9 + Art. 20 §1: titular tem direito de saber que dados foram objeto de tratamento automatizado. Spec não prevê notificação. Recomendo: ao completar scoring (EF step 6), disparar notificação: "Seus vídeos foram analisados por IA. Você tem direito de acessar os resultados e de solicitar revisão." Email simples via Resend (infrastructure existente).

**R-L4 — Retenção de `prompt_hash` e `transcription_hash` como dados pessoais indiretos.** Hashes não reversíveis individualmente. Mas se controlador mantiver também transcrição e vídeo original, combinação pode ser usada para reidentificar. Após purge da transcrição (90d/180d), hashes tornam-se efetivamente anônimos. Risco baixo, documentar explicitamente que hashes são retidos para auditoria e considerados anonimizados após eliminação dos dados originais.

**R-L5 — Ausência de DPA com Anthropic para este uso específico.** ADR-0076 menciona DPA com Anthropic como condição para uso de `profile_about_me` em prompts LLM. Para scoring por vídeo (transcrição como input para Anthropic Sonnet), verificar se DPA existente cobre ou se necessário adendo. Transcrições contêm dados pessoais identificáveis. Se DPA atual cobre "dados pessoais processados via API Anthropic para fins de seleção de voluntários", uso atual coberto. **Confirmar antes de enviar transcrições.**

**R-L6 — Compartilhamento de dados com terceiro (Anthropic) sem previsão no consent/Termo.** Candidato provavelmente não sabe que transcrição é enviada para servidor Anthropic. LGPD Art. 9 I exige informação sobre "possibilidade de compartilhamento com outros controladores ou operadores". Recomendo disclosure explícito: "dados processados via modelos de linguagem de terceiros (processadores de dados), com os quais o Núcleo mantém DPA adequado". Ponto sensível para ANPD em contexto LLM.

---

## 8. Veredicto final

**APROVADO COM AJUSTES.** Arquitetura tem fundação jurídica sólida. Salvaguardas non-binding score (D-NON-BIND=A), audit trail (prompt_hash/transcription_hash), export reasoning (D-EXPORT=A), e retenção 90d/180d corretamente endereçadas.

**3 medidas que devem preceder deploy em produção com candidatos reais:**

1. **Re-disclosure e consent gate** para candidatos com vídeos já submetidos (Eduardo Luz, Cycle 4) e consent gate específico na jornada de upload para Cycle 5+ — seja via `consent_subjective_video_scoring_at` dedicado (preferido) ou via adendo ao consent existente com re-aceite explícito.

2. **Material change no Termo de Adesão v2.7/v2.8 e/ou Política de Privacidade** incluindo: (a) menção explícita a análise IA de conteúdo de vídeo com scoring; (b) disclosure de processamento por terceiro (Anthropic como operador); (c) direito de acesso ao scoring, revogação e revisão. Material change passa pelo workflow de ratificação existente (curadores + Ângelina).

3. **Banner UI na interface do comitê** identificando score IA como "sinal de apoio — decisão final é humana" e **notificação ao candidato** após conclusão do scoring, informando sobre tratamento e direitos.

Salvaguardas técnicas da spec (contract test CI, calibration view com audit de divergências, revoke 72h, purge cron) são adequadas conforme especificadas.

---

*Parecer para revisão inicial; confirmação com advogado licenciado recomendada antes de ratificação e deploy em produção. Referências aplicadas: LGPD Arts. 5 I/XII, 7 I/IX, 8 §§4-5, 9, 9 §2, 16, 18 II/IV/V, 20 caput/§1; Resolução CD/ANPD 2/2022; CF/88 Art. 5 XXXVI; Lei 9.610/98 Art. 49; ADR-0076 Princípios 2, 4, 6, 7; ADR-0074; Termo de Adesão v2.7-p150 handoff.*
