# Per-language content for the Núcleo pitch deck. ONLY strings live here.
# Layout (positions, colors, slide order) lives in build.py; the engine in deck_engine.py.
# Adding a language = adding one dict here (e.g. "es"). No em-dash anywhere (engine guards it).
# The Núcleo name "Núcleo IA & GP" is kept verbatim in every language (dual-language brand);
# only the cover gloss + node/tagline labels localize.

CONTENT = {
    # ===================================================================== PT-BR
    "pt": {
        "labels": {"audience_pain": "Público & dor", "ai_thesis": "Tese de IA",
                   "timing": "Timing:", "anchor_proof": "Prova-âncora:",
                   "on_board": "Já a bordo: liderança definida"},
        "cover": {
            "title": "Núcleo IA & GP",
            "sub": "A costura entre os silos de credencial do PMI  ·  "
                   "Núcleo de Estudos e Pesquisa em IA & GP  ·  Junho de 2026",
            "attr": "PMI, o logotipo PMI, PMI-CP, PMI-PMOCP, PMI-ACP, CSPP, CPMAI, PfMP, PgMP e "
                    "PMI-PBA são marcas do Project Management Institute, Inc. Uso conforme as "
                    "diretrizes de marca para capítulos.",
            "note": "Abertura. O Núcleo IA & GP é a costura entre os silos de credencial do PMI: uma "
                    "comunidade voluntária que junta gente boa de toda credencial em pesquisa, "
                    "desenvolvimento e networking, com a IA como o fio. Este deck mostra a tese (a "
                    "horizontal que o PMI nao tem por desenho), o modelo de tres eixos, as verticais e o "
                    "pedido por audiencia. Publico: board do PMI, presidentes de capitulo e parceiros de "
                    "vertical. Marca PMIGO sob as diretrizes de capitulo; atribuicao no rodape.",
        },
        "problem": {
            "eyebrow": "O problema", "title": "O ativo que falta no PMI é uma horizontal",
            "h1": "O PMI vive em silos de credencial",
            "l1": ["Construção, PMO, Ágil, Sustentabilidade, Negócio.",
                   "Cada comunidade na sua trilha; raramente conversam.",
                   "Toda parceria (GPM, Construction Ambassadors, PMOGA) vira caso especial e isolado."],
            "h2": "A IA é transversal a todas",
            "l2": ["Nenhuma credencial escapa da IA: ela atravessa todos os silos.",
                   "Falta no ecossistema uma horizontal que costure as fronteiras.",
                   "Esse é o papel do Núcleo: voluntário para voluntário, um só propósito, gente boa através das credenciais."],
            "note": "O problema nao e falta de comunidades, e falta de uma costura entre elas. O PMI e "
                    "organizado por silos de credencial; a IA e transversal a todos. Sem uma horizontal "
                    "explicita, cada parceria vira caso especial. O Nucleo e essa horizontal por desenho: "
                    "comunidade voluntaria, um proposito, juntando gente boa atraves das fronteiras de "
                    "credencial, com a IA como o fio.",
        },
        "tailwind": {
            "eyebrow": "O vento a favor", "title": "Não remamos contra a maré: nomeamos a maré",
            "head": ["Silo", "Movimento do próprio PMI (verificado, jun/2026)"],
            "rows": [
                ["PMO", "PMI adquiriu o PMO-CP da PMOGA (2023) e relançou como PMI-PMOCP, ISO-accredited (fev/2026); PMOGA hoje em pmoga.pmi.org"],
                ["ESG / Verde", "GPM-b evolui para CSPP, co-branded PMI + GPM, alinhado ao Standard P5 (efetivo 5 jun/2026)"],
                ["Ágil", "Agile Alliance entrou no PMI (2026)"],
            ],
            "caption": "O Núcleo é a expressão humana e de pesquisa dessa mesma integração. A IA é o fio.",
            "note": "Este e o slide-matador para o board. A tese de hub integrador nao rema contra a mare "
                    "institucional, ela nomeia a mare: o proprio PMI esta absorvendo comunidades de "
                    "credencial para dentro de si (PMO-CP da PMOGA em 2023; GPM-b vira CSPP em jun/2026; "
                    "Agile Alliance entra em 2026). O Nucleo e a expressao humana e de pesquisa dessa "
                    "integracao, com a IA como fio. Leitura pratica de PMI:Next e M.O.R.E., nao mais uma iniciativa.",
        },
        "model": {
            "eyebrow": "O modelo", "title": "A IA no centro, as comunidades como raios",
            "caption": [
                "Três eixos ortogonais: Quadrante (o quê) × Tribo (quem produz) × Vertical (pra quem "
                "aterrissa). A escada comum a toda vertical: PMIxAI Champion (aberto) → Grupo de Estudos "
                "CPMAI → PMI-CPMAI.",
                "A vertical é doca, nunca silo: a tribo produz, a vertical distribui. Ninguém é dono do conhecimento."],
            "note": "O visual e o pitch. Centro: Nucleo + IA, a costura. Raios: as verticais, cada uma uma "
                    "comunidade de credencial do PMI. Anel: a escada Champion > CPMAI, espinha comum a "
                    "todos os raios. O modelo tem tres eixos ortogonais: quadrante (tipo de conhecimento, "
                    "taxonomia propria do Nucleo), tribo (quem produz, Eixo A) e vertical (pra quem "
                    "distribui, Eixo B). A vertical nao duplica o quadrante: define publico e empacotamento. "
                    "Principio anti-silo: producao e da tribo, distribuicao e da vertical; nenhuma vertical "
                    "e dona de conhecimento, e doca.",
        },
        "ladder": {
            "eyebrow": "A escada comum", "title": "A costura de credencial é uma escada, não um ponto",
            "steps": [
                ["1 · PMIxAI Champion", ["Reconhecimento e badge, aberto e leve.",
                    "Porta de entrada (Eixo B).", "Já é primitivo da plataforma (award_champion)."]],
                ["2 · Grupo de Estudos CPMAI", ["Preparatório, em tribo (Eixo A).",
                    "A ponte entre o aberto e a credencial.", "Já modelado como iniciativa (cpmai_*)."]],
                ["3 · PMI-CPMAI", ["A credencial-costura.", "Faz interface com TODAS as verticais.",
                    "O ponto comum entre comunidades que não se falariam."]],
            ],
            "note": "A costura tem uma escada que toda vertical atravessa. PMIxAI Champion (aberto, "
                    "gamificado, ja existe como award_champion) prepara o terreno; o Grupo de Estudos CPMAI "
                    "(Eixo A, preparatorio, ja modelado) faz a ponte; o PMI-CPMAI e a credencial-costura que "
                    "faz interface com todas as verticais. Isomorfia central: no ecossistema PMI os silos "
                    "sao credenciais e a costura e a IA (CPMAI); dentro do Nucleo a costura e o mesmo "
                    "mecanismo, com a escada Champion > CPMAI como espinha compartilhada.",
        },
        "reach": {
            "eyebrow": "Cobertura & alcance", "title": "Quebramos o silo geográfico, não só o de credencial",
            "h1": "Brasil + LatAm em primeiro plano",
            "l1": ["Membros ativos (pesquisadores, líderes, curadores) já em vários estados do Brasil.",
                   "15 capítulos no Brasil; diversidade intra-Brasil é a prioridade.",
                   "Enquadrar a LatAm é o recado de expansão por geografia, sem precisar declarar em texto."],
            "h2": "Presença internacional = networking",
            "l2": ["O Núcleo já reúne gente em Brasil, Portugal, Itália e EUA.",
                   "Não é heatmap mundial esparso: é ativo de acesso a networking, nomeado por país.",
                   "Embaixadores são poucos (cerca de 4); a comunidade ativa é maior que isso."],
            "lgpd": "Governança-first (LGPD): agregação por capítulo, estado ou país. Zero PII; pin individual só com opt-in.",
            "note": "Calibracao de jun/2026: o Nucleo nao e so embaixadores (sao cerca de 4); membros ativos "
                    "ja estao em varios estados do Brasil mais Portugal, Italia e EUA. A diversidade "
                    "prioritaria e intra-Brasil, mas a presenca internacional e ativo de networking e deve "
                    "aparecer, nomeada por pais, nao como borrao mundial. Em pagina publica tudo agrega por "
                    "capitulo/estado/pais, zero PII, pin de pessoa so com opt-in registrado. O mapa do "
                    "PMAIrevolution pode ser reaproveitado, re-projetado para Brasil/LatAm.",
        },
        "verticals": [
            {"eyebrow": "Vertical · Construção", "title": "Giga-projetos: PMI-CP e a IA nos megaprojetos",
             "dor": ["Líderes de megaprojetos e infraestrutura (A/E/C).",
                     "Projetos longos, documentação massiva, risco de prazo e custo.",
                     "Contratos e RFIs intermináveis; dados fragmentados entre stakeholders."],
             "teses": ["Análise de risco e cronograma em megaprojetos.",
                       "Leitura e sumarização de contratos, RFIs e submittals em escala.",
                       "Gêmeos digitais e dados de campo como insumo de decisão."],
             "timing": "mote do PMI 'Megaprojects demand mega skills' (megaprojeto = mais de US$1bi, multi-ano); Construction Ambassadors advoga segurança, eficiência e sustentabilidade (hub pmicp.us).",
             "prova": "estudo 'IA aplicada a um pleito ou risco típico de megaprojeto' + webinar com um embaixador.",
             "bordo": ["Henrique Diniz (Brasil) e Fabrício Costa (EUA): Construction Global Ambassadors.",
                       "Henrique foi aceito para liderar a vertical no Núcleo, com a trilha Giga Projetos e IA.",
                       "Prova-âncora: estudo de IA em pleito ou risco de megaprojeto + webinar com os embaixadores."],
             "note": "Vertical Construcao. Credencial-ancora PMI-CP; parceiro Global Construction Ambassadors. "
                     "JA TEM protagonistas: Henrique Diniz (Brasil) e Fabricio Costa (EUA) sao Construction "
                     "Global Ambassadors; Henrique se inscreveu e foi aceito para liderar a vertical no Nucleo, "
                     "com a trilha Giga Projetos e IA. Timing: mote 'Megaprojects demand mega skills' "
                     "(megaprojeto = mais de US$1bi, multi-ano); IA e a alavanca dos tres pilares (seguranca, "
                     "eficiencia, sustentabilidade), hub pmicp.us. Pedido ao parceiro: co-curadoria mais "
                     "acesso a comunidade PMI-CP para a coorte fundadora."},
            {"eyebrow": "Vertical · PMO", "title": "PMO aumentado por IA: PMI-PMOCP",
             "dor": ["Líderes de PMO sob pressão de provar valor.",
                     "Status reporting manual; dados de portfólio dispersos.",
                     "PMO visto como custo, não como inteligência."],
             "teses": ["O PMO como camada de inteligência (analytics de portfólio, previsão).",
                       "Status e relatórios automatizados a partir dos dados.",
                       "Priorização de portfólio assistida por IA."],
             "timing": "o mais quente do modelo institucional: PMI-PMOCP recém-lançada (ISO, fev/2026) e a PMOGA absorvida pelo PMI. Comunidade ávida por 'o que a IA muda no meu PMO'.",
             "prova": "'PMO Aumentado': como a IA entra nos 6 domínios do PMI-PMOCP.",
             "bordo": None,
             "note": "Vertical PMO. Credencial-ancora PMI-PMOCP (sucessora do PMO-CP); parceiro PMO Global "
                     "Alliance, hoje sob o PMI (pmoga.pmi.org). Maximo alinhamento institucional. Pedido ao "
                     "parceiro: trilha conjunta PMO + IA e presenca na comunidade PMOGA."},
            {"eyebrow": "Vertical · Ágil", "title": "Julgamento humano na era dos agentes: PMI-ACP",
             "dor": ["Agilistas repensando o papel humano na era da IA.",
                     "Medo de 'IA contra agilidade'.",
                     "Incerteza sobre onde o julgamento humano agrega."],
             "teses": ["Jim Highsmith (co-autor do Manifesto Ágil) reposiciona a pergunta para 'que liderança humana não se automatiza', e aponta o julgamento como a capacidade mais crítica.",
                       "Gerir pessoas e bots como nova competência ágil.",
                       "Entrega acelerada por IA sem perder os princípios."],
             "timing": "Agile Alliance dentro do PMI + refresh do PMP (jul/2026) enfatizando ágil e híbrido; a comunidade está se reposicionando.",
             "prova": "ensaio ou debate 'julgamento humano na era dos agentes', com referência ao Manifesto.",
             "bordo": None,
             "note": "Vertical Agil. Credencial-ancora PMI-ACP; parceiro Agile Alliance (entrou no PMI em "
                     "2026). Fonte da tese: PMI AI Today, 'Reimagining Agility in an AI World'. ATENCAO de "
                     "fonte: a frase popular de 'sprints de 5h' NAO e do Highsmith; usar apenas a parafrase "
                     "do enquadramento (julgamento, pessoas e bots). Pedido ao parceiro: sessao conjunta "
                     "Agile Alliance x Nucleo na virada do PMP."},
            {"eyebrow": "Vertical · ESG / Verde", "title": "Sustentabilidade é o #1 preditor de sucesso: CSPP",
             "dor": ["Profissionais de sustentabilidade em projetos.",
                     "Intenção corporativa de ESG que não vira entrega.",
                     "Medição e reporte difíceis; dados ambientais e sociais dispersos."],
             "teses": ["Medição e reporte de sustentabilidade, alinhados ao Standard P5.",
                       "IA tornando intenção ESG em entrega rastreável.",
                       "Análise de dados ambientais e sociais em escala."],
             "timing": "o mais fresco: CSPP saiu em 5 jun/2026. Pesquisa PMI + GPM (cerca de 1.600 profissionais, 35 países) aponta sustentabilidade como o #1 preditor de sucesso, à frente de metodologia e governança.",
             "prova": "'IA + P5': como a IA fecha o gap de execução. Munição: 55% de satisfação (alinhados) vs 33% (não); só 23% alinhados hoje; gap de confiança de 42 pontos (85% sust. vs 43% PMO).",
             "bordo": None,
             "note": "Vertical ESG/Verde. Credencial-ancora CSPP (evolucao do GPM-b, PMI + GPM, efetiva 5 "
                     "jun/2026); parceiro GPM Global. Numeros conferidos no pitch kit: 55 vs 33; 23% "
                     "alinhados; 79% dizem que posiciona para o longo prazo mas so 41% integram; gap de "
                     "confianca de 42 pontos (85% executivos de sustentabilidade vs 43% lideres de PMO). "
                     "Gancho de midia pronto. Pedido: co-lancamento na janela CSPP."},
            {"eyebrow": "Vertical · Negócio", "title": "IA em portfólio e estratégia: PfMP, PgMP, PMI-PBA",
             "dor": ["Gestores de programa e portfólio; analistas de negócio.",
                     "Decisão estratégica sob incerteza.",
                     "Priorização de portfólio; requisitos voláteis."],
             "teses": ["Priorização de portfólio e cenários assistidos por IA.",
                       "Análise de negócio aumentada (requisitos, stakeholders).",
                       "Ligação estratégia e execução com dados."],
             "timing": "PfMP, PgMP e PMI-PBA confirmadas no registry PMI. São 3 sub-públicos distintos: podem virar sub-verticais se a demanda justificar.",
             "prova": "caso de priorização de portfólio com IA.",
             "bordo": None,
             "note": "Vertical Negocio/Programa/Portfolio. Credenciais-ancora PfMP (portfolio), PgMP "
                     "(programa), PMI-PBA (analise de negocio), confirmadas no registry. Parceiro a definir; "
                     "gancho de timing a verificar. E a ultima da ordem de ativacao justamente por depender "
                     "de definir parceiro primeiro."},
        ],
        "asks": [
            {"eyebrow": "O pedido · Board PMI", "title": "O que pedimos ao board",
             "h1": "Para Mario Trentim e o board do PMI",
             "l1": ["Endorsement estratégico do Núcleo como horizontal-costura entre os silos de credencial.",
                    "Reconhecimento do Núcleo como leitura prática de PMI:Next e M.O.R.E.: a comunidade que executa, no nível humano e de pesquisa, a integração de silos que o PMI já faz institucionalmente."],
             "h2": "Por que cabe agora",
             "l2": ["O movimento já é institucional (PMOGA, GPM, Agile Alliance entraram para dentro do PMI).",
                    "O Núcleo dá rosto humano e produção de pesquisa a essa estratégia, com a IA como fio (PMIxAI, PMI Infinity)."],
             "note": "Variacao 1 de 3 (trocavel por audiencia). Para o board: endorsement estrategico e "
                     "reconhecimento do Nucleo como leitura pratica de PMI:Next / M.O.R.E. Ancorar no fato "
                     "de que a integracao de silos ja e institucional; o Nucleo e a expressao humana e de "
                     "pesquisa dela. Manter as outras duas variacoes ocultas conforme a plateia."},
            {"eyebrow": "O pedido · Presidentes de capítulo", "title": "O que pedimos aos capítulos",
             "h1": "Para os presidentes de capítulo",
             "l1": ["Adesão do capítulo à horizontal Núcleo IA & GP (federação leve, sem perder identidade local).",
                    "Indicação de protagonistas, pesquisadores e curadores do capítulo para as verticais."],
             "h2": "O que o capítulo ganha",
             "l2": ["Acesso à produção de pesquisa e à escada Champion → CPMAI para os seus membros.",
                    "Validação do discurso AI-forward localmente, alinhado à estratégia global do PMI."],
             "note": "Variacao 2 de 3. Para presidentes de capitulo: adesao do capitulo, indicacao de "
                     "protagonistas/pesquisadores e validacao do discurso. Enfatizar que e federacao leve, "
                     "ganho de pesquisa e escada de credencial para os membros, sem perder identidade local."},
            {"eyebrow": "O pedido · Parceiros de vertical", "title": "O que pedimos aos parceiros",
             "h1": "Para os parceiros de vertical (GPM, Construction Ambassadors, PMOGA)",
             "l1": ["Co-curadoria da vertical: o conteúdo fala a credencial, a dor e a linguagem da comunidade.",
                    "Acesso à comunidade da credencial para formar a coorte fundadora."],
             "h2": "A regra que protege o parceiro",
             "l2": ["Produção é da tribo; a vertical é canal. Nenhuma vertical é dona do conhecimento: é doca.",
                    "O pitch de cada vertical se refina com o parceiro antes de ir a público."],
             "note": "Variacao 3 de 3. Para parceiros de vertical: co-curadoria mais acesso a comunidade da "
                     "credencial para a coorte fundadora. Reforcar o principio anti-silo (producao da tribo, "
                     "distribuicao da vertical) como a garantia de que o parceiro nao perde dominio sobre o "
                     "proprio conhecimento."},
        ],
        "next": {
            "eyebrow": "Próximos passos", "title": "Ciclo 4: verticais-piloto e chamada de protagonistas",
            "head": ["Ordem de ativação", "Por que primeiro", "Status"],
            "rows": [
                ["1 · Construção", "Líder aceito (Henrique Diniz) + 2 Global Ambassadors (BR/EUA): a mais pronta para ativar", "em formação · líder definido"],
                ["2 · PMO", "PMI-PMOCP recém-lançada + PMOGA absorvida: máximo alinhamento institucional", "em formação · Ciclo 4"],
                ["3 · ESG", "CSPP recém-lançada (janela de mídia) + #1 preditor de sucesso", "em formação · Ciclo 4"],
                ["4 · Ágil", "Agile Alliance no PMI + refresh do PMP (jul)", "declarada"],
                ["5 · Negócio", "definir parceiro primeiro", "declarada"],
            ],
            "cta_h": "Seja protagonista",
            "cta": ["Cada vertical entra com status explícito (em formação, não vaporware). O CTA recruta "
                    "fundadores, não consumidores: um programa de liderança, alinhado a M.O.R.E. e PMI:Next."],
            "note": "Fechamento. A ordem de ativacao agora abre pela PRONTIDAO: Construcao e #1 porque e a "
                    "unica com lider aceito (Henrique Diniz) e dois Global Ambassadors (BR/EUA) ja a bordo, "
                    "com trilha Giga Projetos e IA. Depois PMO (alinhamento institucional), ESG (janela de "
                    "midia CSPP, perecivel), Agil (comunidade se reposicionando), Negocio (definir parceiro). "
                    "Cada vertical aparece com status explicito (em formacao), sem fingir atividade. A "
                    "chamada e 'Seja protagonista', nao 'seja membro': recruta coorte fundadora, com vinculo "
                    "a M.O.R.E. e PMI:Next que justifica chamar de lideranca. Sem hardcode: a pagina le o "
                    "status da iniciativa e renderiza o CTA.",
        },
    },

    # ===================================================================== EN-US
    "en": {
        "labels": {"audience_pain": "Audience & pain", "ai_thesis": "AI thesis",
                   "timing": "Timing:", "anchor_proof": "Anchor proof:",
                   "on_board": "Already on board: leadership in place"},
        "cover": {
            "title": "Núcleo IA & GP",
            "sub": "AI & PM Study and Research Hub  ·  The seam across PMI's credential silos  ·  June 2026",
            "attr": "PMI, the PMI logo, PMI-CP, PMI-PMOCP, PMI-ACP, CSPP, CPMAI, PfMP, PgMP and PMI-PBA "
                    "are marks of the Project Management Institute, Inc. Used under the chapter brand guidelines.",
            "note": "Opening. The Nucleo IA & GP (kept as the dual-language brand) is the seam across PMI's "
                    "credential silos: a volunteer community that brings good people from every credential "
                    "into research, development and networking, with AI as the thread. This deck shows the "
                    "thesis (the horizontal PMI does not have by design), the three-axis model, the verticals "
                    "and the ask per audience. Audience: PMI board, chapter presidents and vertical partners. "
                    "PMIGO brand under chapter guidelines; marks attribution line in the footer.",
        },
        "problem": {
            "eyebrow": "The problem", "title": "What PMI is missing is a horizontal",
            "h1": "PMI lives in credential silos",
            "l1": ["Construction, PMO, Agile, Sustainability, Business.",
                   "Each community in its own track; they rarely talk.",
                   "Every partnership (GPM, Construction Ambassadors, PMOGA) becomes an isolated special case."],
            "h2": "AI is transversal to all of them",
            "l2": ["No credential escapes AI: it cuts across every silo.",
                   "The ecosystem lacks a horizontal that sews the boundaries together.",
                   "That is the Núcleo's role: volunteer to volunteer, a single purpose, good people across credentials."],
            "note": "The problem is not a lack of communities, it is the lack of a seam between them. PMI is "
                    "organized by credential silos; AI is transversal to all of them. Without an explicit "
                    "horizontal, every partnership becomes a special case. The Nucleo is that horizontal by "
                    "design: a volunteer community, one purpose, bringing good people together across "
                    "credential boundaries, with AI as the thread.",
        },
        "tailwind": {
            "eyebrow": "The tailwind", "title": "We are not fighting the tide: we are naming it",
            "head": ["Silo", "The PMI's own move (verified, Jun/2026)"],
            "rows": [
                ["PMO", "PMI acquired PMO-CP from PMOGA (2023) and relaunched it as PMI-PMOCP, ISO-accredited (Feb/2026); PMOGA now lives at pmoga.pmi.org"],
                ["ESG / Green", "GPM-b evolves into CSPP, co-branded PMI + GPM, aligned to the P5 Standard (effective 5 Jun/2026)"],
                ["Agile", "Agile Alliance joined PMI (2026)"],
            ],
            "caption": "The Núcleo is the human and research expression of that same integration. AI is the thread.",
            "note": "This is the killer slide for the board. The integrating-hub thesis does not row against "
                    "the institutional tide, it names the tide: PMI itself is absorbing credential "
                    "communities into itself (PMO-CP from PMOGA in 2023; GPM-b becomes CSPP in Jun/2026; "
                    "Agile Alliance joins in 2026). The Nucleo is the human and research expression of that "
                    "integration, with AI as the thread. A practical reading of PMI:Next and M.O.R.E., not "
                    "one more initiative.",
        },
        "model": {
            "eyebrow": "The model", "title": "AI at the center, the communities as spokes",
            "caption": [
                "Three orthogonal axes: Quadrant (what) x Tribe (who produces) x Vertical (who it lands "
                "with). The ladder shared by every vertical: PMIxAI Champion (open) → CPMAI Study Group → PMI-CPMAI.",
                "A vertical is a dock, never a silo: the tribe produces, the vertical distributes. No one owns the knowledge."],
            "note": "The visual is the pitch. Center: Nucleo + AI, the seam. Spokes: the verticals, each a "
                    "PMI credential community. Ring: the Champion > CPMAI ladder, the spine shared by every "
                    "spoke. The model has three orthogonal axes: quadrant (type of knowledge, the Nucleo's "
                    "own taxonomy), tribe (who produces, Axis A) and vertical (who it distributes to, Axis "
                    "B). The vertical does not duplicate the quadrant: it defines audience and packaging. "
                    "Anti-silo principle: the tribe produces, the vertical distributes; no vertical owns "
                    "knowledge, it is a dock.",
        },
        "ladder": {
            "eyebrow": "The common ladder", "title": "The credential seam is a ladder, not a single point",
            "steps": [
                ["1 · PMIxAI Champion", ["Recognition and badge, open and light.",
                    "Entry point (Axis B).", "Already a platform primitive (award_champion)."]],
                ["2 · CPMAI Study Group", ["Preparatory, within a tribe (Axis A).",
                    "The bridge from open to credential.", "Already modeled as an initiative (cpmai_*)."]],
                ["3 · PMI-CPMAI", ["The seam credential.", "Interfaces with ALL verticals.",
                    "The common point between communities that would not otherwise talk."]],
            ],
            "note": "The seam has a ladder that every vertical climbs. PMIxAI Champion (open, gamified, "
                    "already exists as award_champion) prepares the ground; the CPMAI Study Group (Axis A, "
                    "preparatory, already modeled) is the bridge; PMI-CPMAI is the seam credential that "
                    "interfaces with all verticals. Central isomorphism: in the PMI ecosystem the silos are "
                    "credentials and the seam is AI (CPMAI); inside the Nucleo the seam is the same "
                    "mechanism, with the Champion > CPMAI ladder as the shared spine.",
        },
        "reach": {
            "eyebrow": "Reach & coverage", "title": "We break the geographic silo, not only the credential one",
            "h1": "Brazil + LatAm in the foreground",
            "l1": ["Active members (researchers, leaders, curators) already across several Brazilian states.",
                   "15 PMI chapters in Brazil; intra-Brazil diversity is the priority.",
                   "Framing LatAm is the geographic-expansion message, without spelling it out in copy."],
            "h2": "International presence = networking",
            "l2": ["The Núcleo already gathers people in Brazil, Portugal, Italy and the USA.",
                   "Not a sparse world heatmap: a networking-access asset, named by country.",
                   "Ambassadors are few (about 4); the active community is larger than that."],
            "lgpd": "Governance-first (LGPD): aggregate by chapter, state or country. Zero PII; individual pins only with opt-in.",
            "note": "Calibration as of Jun/2026: the Nucleo is not only ambassadors (about 4); active "
                    "members are already across several Brazilian states plus Portugal, Italy and the USA. "
                    "Intra-Brazil diversity is the priority, but the international presence is a networking "
                    "asset and should appear, named by country, not as a sparse world blur. On a public page "
                    "everything aggregates by chapter/state/country, zero PII, individual pins only with "
                    "recorded opt-in. The PMAIrevolution map can be reused, re-projected to Brazil/LatAm.",
        },
        "verticals": [
            {"eyebrow": "Vertical · Construction", "title": "Giga-projects: PMI-CP and AI in megaprojects",
             "dor": ["Leaders of megaprojects and infrastructure (A/E/C).",
                     "Long projects, massive documentation, schedule and cost risk.",
                     "Endless contracts and RFIs; data fragmented across stakeholders."],
             "teses": ["Risk and schedule analysis in megaprojects.",
                       "Reading and summarizing contracts, RFIs and submittals at scale.",
                       "Digital twins and field data as decision input."],
             "timing": "the PMI motto 'Megaprojects demand mega skills' (megaproject = over US$1bn, multi-year); the Construction Ambassadors advocate safety, efficiency and sustainability (hub pmicp.us).",
             "prova": "AI study on a typical megaproject claim or risk + webinar with an ambassador.",
             "bordo": ["Henrique Diniz (Brazil) and Fabrício Costa (USA): Construction Global Ambassadors.",
                       "Henrique was accepted to lead the vertical at the Núcleo, with the Giga-projects and AI track.",
                       "Anchor proof: AI study on a typical megaproject claim or risk + webinar with the ambassadors."],
             "note": "Construction vertical. Anchor credential PMI-CP; partner Global Construction "
                     "Ambassadors. ALREADY HAS protagonists: Henrique Diniz (Brazil) and Fabricio Costa "
                     "(USA) are Construction Global Ambassadors; Henrique applied and was accepted to lead "
                     "the vertical at the Nucleo, with the Giga-projects & AI track. Timing: motto "
                     "'Megaprojects demand mega skills' (megaproject = over US$1bn, multi-year); AI is the "
                     "lever for the three program pillars (safety, efficiency, sustainability), hub "
                     "pmicp.us. Ask to the partner: co-curation plus access to the PMI-CP community for the "
                     "founding cohort."},
            {"eyebrow": "Vertical · PMO", "title": "AI-augmented PMO: PMI-PMOCP",
             "dor": ["PMO leaders under pressure to prove value.",
                     "Manual status reporting; scattered portfolio data.",
                     "PMO seen as a cost, not as intelligence."],
             "teses": ["The PMO as an intelligence layer (portfolio analytics, forecasting).",
                       "Automated status and reports straight from the data.",
                       "AI-assisted portfolio prioritization."],
             "timing": "the hottest in the institutional model: PMI-PMOCP just launched (ISO, Feb/2026) and PMOGA absorbed by PMI. The community is eager for 'what AI changes in my PMO'.",
             "prova": "'Augmented PMO': how AI enters the 6 domains of PMI-PMOCP.",
             "bordo": None,
             "note": "PMO vertical. Anchor credential PMI-PMOCP (successor to PMO-CP); partner PMO Global "
                     "Alliance, now under PMI (pmoga.pmi.org). Maximum institutional alignment. Ask to the "
                     "partner: a joint PMO + AI track and presence in the PMOGA community."},
            {"eyebrow": "Vertical · Agile", "title": "Human judgment in the age of agents: PMI-ACP",
             "dor": ["Agilists rethinking the human role in the age of AI.",
                     "Fear of 'AI versus agility'.",
                     "Uncertainty about where human judgment adds value."],
             "teses": ["Jim Highsmith (co-author of the Agile Manifesto) reframes the question to 'what human leadership does not automate', and points to judgment as the most critical capability.",
                       "Managing people and bots as a new agile competency.",
                       "AI-accelerated delivery without losing the principles."],
             "timing": "Agile Alliance inside PMI + the PMP refresh (Jul/2026) emphasizing agile and hybrid; the community is repositioning.",
             "prova": "essay or debate 'human judgment in the age of agents', referencing the Manifesto.",
             "bordo": None,
             "note": "Agile vertical. Anchor credential PMI-ACP; partner Agile Alliance (joined PMI in "
                     "2026). Thesis source: PMI AI Today, 'Reimagining Agility in an AI World'. SOURCE "
                     "CAUTION: the popular 'five-hour sprints' phrase is NOT Highsmith's; use only the "
                     "paraphrase of the framing (judgment, people and bots). Ask to the partner: a joint "
                     "Agile Alliance x Nucleo session around the PMP refresh."},
            {"eyebrow": "Vertical · ESG / Green", "title": "Sustainability is the #1 predictor of success: CSPP",
             "dor": ["Sustainability professionals in projects.",
                     "Corporate ESG intent that does not turn into delivery.",
                     "Hard measurement and reporting; scattered environmental and social data."],
             "teses": ["Sustainability measurement and reporting, aligned to the P5 Standard.",
                       "AI turning ESG intent into traceable delivery.",
                       "Analysis of environmental and social data at scale."],
             "timing": "the freshest: CSPP launched on 5 Jun/2026. PMI + GPM research (about 1,600 professionals, 35 countries) points to sustainability as the #1 predictor of success, ahead of methodology and governance.",
             "prova": "'AI + P5': how AI closes the execution gap. Ammo: 55% satisfaction (aligned) vs 33% (not); only 23% aligned today; 42-point confidence gap (85% sustainability vs 43% PMO).",
             "bordo": None,
             "note": "ESG/Green vertical. Anchor credential CSPP (evolution of GPM-b, PMI + GPM, effective 5 "
                     "Jun/2026); partner GPM Global. Numbers verified in the pitch kit: 55 vs 33; 23% "
                     "aligned; 79% say it positions for the long term but only 41% integrate it; 42-point "
                     "confidence gap (85% sustainability executives vs 43% PMO leaders). Media hook ready. "
                     "Ask: a co-launch in the CSPP window."},
            {"eyebrow": "Vertical · Business", "title": "AI in portfolio and strategy: PfMP, PgMP, PMI-PBA",
             "dor": ["Program and portfolio managers; business analysts.",
                     "Strategic decisions under uncertainty.",
                     "Portfolio prioritization; volatile requirements."],
             "teses": ["AI-assisted portfolio prioritization and scenarios.",
                       "Augmented business analysis (requirements, stakeholders).",
                       "Linking strategy and execution with data."],
             "timing": "PfMP, PgMP and PMI-PBA confirmed in the PMI registry. Three distinct sub-audiences: may become sub-verticals if demand justifies.",
             "prova": "portfolio prioritization case with AI.",
             "bordo": None,
             "note": "Business/Program/Portfolio vertical. Anchor credentials PfMP (portfolio), PgMP "
                     "(program), PMI-PBA (business analysis), confirmed in the registry. Partner to be "
                     "defined; timing hook to verify. It is last in the activation order precisely because "
                     "it depends on defining a partner first."},
        ],
        "asks": [
            {"eyebrow": "The ask · PMI board", "title": "What we ask the board",
             "h1": "For Mario Trentim and the PMI board",
             "l1": ["Strategic endorsement of the Núcleo as the horizontal seam across credential silos.",
                    "Recognition of the Núcleo as a practical reading of PMI:Next and M.O.R.E.: the community that executes, at the human and research level, the silo integration PMI already does institutionally."],
             "h2": "Why it fits now",
             "l2": ["The move is already institutional (PMOGA, GPM, Agile Alliance joined PMI).",
                    "The Núcleo gives a human face and research output to that strategy, with AI as the thread (PMIxAI, PMI Infinity)."],
             "note": "Variation 1 of 3 (swappable per audience). For the board: strategic endorsement and "
                     "recognition of the Nucleo as a practical reading of PMI:Next / M.O.R.E. Anchor on the "
                     "fact that silo integration is already institutional; the Nucleo is the human and "
                     "research expression of it. Keep the other two variations hidden depending on the audience."},
            {"eyebrow": "The ask · Chapter presidents", "title": "What we ask the chapters",
             "h1": "For chapter presidents",
             "l1": ["Chapter adherence to the Núcleo IA & GP horizontal (light federation, without losing local identity).",
                    "Nomination of protagonists, researchers and curators from the chapter for the verticals."],
             "h2": "What the chapter gains",
             "l2": ["Access to research output and to the Champion → CPMAI ladder for its members.",
                    "Local validation of the AI-forward narrative, aligned with PMI's global strategy."],
             "note": "Variation 2 of 3. For chapter presidents: chapter adherence, nomination of "
                     "protagonists/researchers and validation of the narrative. Stress that it is a light "
                     "federation, a research gain and a credential ladder for members, without losing local identity."},
            {"eyebrow": "The ask · Vertical partners", "title": "What we ask the partners",
             "h1": "For vertical partners (GPM, Construction Ambassadors, PMOGA)",
             "l1": ["Co-curation of the vertical: content speaks the credential, the pain and the language of the community.",
                    "Access to the credential community to form the founding cohort."],
             "h2": "The rule that protects the partner",
             "l2": ["The tribe produces; the vertical is a channel. No vertical owns the knowledge: it is a dock.",
                    "Each vertical's pitch is refined with the partner before it goes public."],
             "note": "Variation 3 of 3. For vertical partners: co-curation plus access to the credential "
                     "community for the founding cohort. Reinforce the anti-silo principle (production by "
                     "the tribe, distribution by the vertical) as the guarantee that the partner does not "
                     "lose control over its own knowledge."},
        ],
        "next": {
            "eyebrow": "Next steps", "title": "Cycle 4: pilot verticals and a call for protagonists",
            "head": ["Activation order", "Why first", "Status"],
            "rows": [
                ["1 · Construction", "Lead accepted (Henrique Diniz) + 2 Global Ambassadors (BR/US): the readiest to activate", "forming · lead in place"],
                ["2 · PMO", "PMI-PMOCP just launched + PMOGA absorbed: maximum institutional alignment", "forming · Cycle 4"],
                ["3 · ESG", "CSPP just launched (media window) + #1 predictor of success", "forming · Cycle 4"],
                ["4 · Agile", "Agile Alliance in PMI + PMP refresh (Jul)", "declared"],
                ["5 · Business", "define partner first", "declared"],
            ],
            "cta_h": "Be a protagonist",
            "cta": ["Each vertical enters with explicit status (forming, not vaporware). The CTA recruits "
                    "founders, not consumers: a leadership program, aligned with M.O.R.E. and PMI:Next."],
            "note": "Closing. The activation order now opens by READINESS: Construction is #1 because it is "
                    "the only one with an accepted lead (Henrique Diniz) and two Global Ambassadors (BR/US) "
                    "already on board, with the Giga-projects & AI track. Then PMO (institutional "
                    "alignment), ESG (CSPP media window, perishable), Agile (community repositioning), "
                    "Business (define partner). Each vertical shows explicit status (forming), without "
                    "faking activity. The call is 'Be a protagonist', not 'be a member': it recruits a "
                    "founding cohort, with the M.O.R.E. and PMI:Next link that justifies calling it "
                    "leadership. No hardcoding: the page reads the initiative status and renders the CTA.",
        },
    },
}
