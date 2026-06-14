# Conteúdo do pitch de COOPERAÇÃO Núcleo IA & GP × Grupo ALUN (interlocutor: Cristiano Kruel).
# SÓ strings. Layout em build_kruel.py; engine em deck_engine.py (modo CLARO = template PMI padrão).
# Regra do engine: NENHUM travessao (—) em slide/nota (o guard quebra o build). Usar "-" / ":" / "·".
# Titulos curtos (1 linha, <=44 chars): no template PMI o titulo de 2 linhas colide com o eyebrow/regua.
# Numeros do Nucleo = get_public_impact_data ao vivo (13/jun/2026). Codigo ANSI = selo da capa oficial.
# Estrutura R3 (2026-06-13): reverte p/ CLARO (brand-accurate: o deck oficial do PMI de parcerias e claro);
# fala a LINGUAGEM OFICIAL do PMI Chapter Partnerships Framework (tipos + 6 propositos + matriz);
# +slide dedicado do PMI; +slide de formalizacao (governanca, enquadrado como autoridade). 11 slides.

CONTENT = {
    "pt": {
        # 1 ---------------------------------------------------------------------------
        "cover": {
            "title": "Núcleo IA & GP",
            "sub": "Proposta de Cooperação  ·  Grupo ALUN (Alura · FIAP · PM3 · StartSE)  ·  Junho de 2026",
            "attr": "PMI, o logotipo PMI, PMP, PMI-ACP, PMI-CP, PMI-PMOCP, PMI-CPMAI, CSPP e CPMAI são marcas "
                    "do Project Management Institute, Inc. Uso conforme as diretrizes de marca para capítulos. "
                    "Números do ALUN e do PMI: fontes públicas, jun/2026.",
            "note": "Abertura de uma conversa de cooperacao, nao de uma palestra. Interlocutor: Cristiano Kruel "
                    "(CIO da StartSE, grupo ALUN). Objetivo: tangibilizar o caminho para ele reagir async, como "
                    "ele pediu. Tese: ALUN e PMI nao competem, fecham o ciclo.",
        },
        # 2 ---------------------------------------------------------------------------
        "fit": {
            "eyebrow": "O encaixe",
            "title": "Do MVP de IA ao projeto entregue",
            "h1": "O ALUN forma",
            "l1": ["O Profissional Minimamente Viável em IA (a tese do seu livro, MAIVP).",
                   "O saber usar IA: negócios, empreendedorismo, produto, inovação e tech.",
                   "Escala de audiência e marca de inovação."],
            "h2": "O PMI / Núcleo entrega",
            "l2": ["A disciplina que transforma 'usar IA' em projeto entregue com valor.",
                   "Os dois gestores que o mercado exige: o que implementa IA, e o que conduz a "
                   "transformação (upskilling, time, cultura e dados).",
                   "Governança, método CPMAI e a credencial global que o seu público já busca."],
            "caption": "Você define o mínimo viável em IA; o PMI leva até o resultado. A ponte é a sua própria metáfora.",
            "note": "Slide-cunha. Gancho = metafora do proprio Kruel (MAIVP e trocadilho com MVP). Enquadramento "
                    "dual do GP (pedido do Vitor): o que IMPLEMENTA IA e o que CONDUZ a transformacao. A capa do "
                    "livro do Kruel ancora o slide (ponto de conexao).",
        },
        # 3 ---------------------------------------------------------------------------
        "fronts": {
            "eyebrow": "Como cooperar",
            "title": "Três frentes de cooperação",
            "cols": [
                ["1 · Conteúdo cruzado", "Co-Branding + Content Distribution",
                 ["Palestrantes do ALUN no SGPL e nos webinars do Núcleo.",
                  "Conteúdo e pesquisadores nossos para a audiência de vocês.",
                  "Baixa fricção: começa já, sem acordo formal."]],
                ["2 · Ponte de certificação", "Academic",
                 ["Trilha co-branded sobre a formação de vocês.",
                  "A credencial global que o seu público já busca.",
                  "Funil direto: do aluno de vocês ao membro e certificado PMI."]],
                ["3 · Hackathon / Tribo CPMAI", "Research + Social Impact",
                 ["Projeto-piloto de IA com o método CPMAI.",
                  "Vira case para os dois lados.",
                  "Pesquisa aplicada, com propriedade intelectual (PI) conjunta."]],
            ],
            "caption": "Tipos de parceria do próprio PMI Chapter Partnerships Framework. Você escolhe a profundidade: diga qual ressoa e a gente avança por ali.",
            "note": "PROMOVIDO p/ logo apos a abertura: responde direto a msg async do Kruel. Cada frente recebe "
                    "o TIPO OFICIAL de parceria do PMI Framework (Co-Branding/Content Distribution, Academic, "
                    "Research/Social Impact) - sinaliza que sabemos como isso e aprovado no capitulo. Trocado "
                    "'custo zero' por 'baixa friccao'. Sigla PI definida na frente. PRECEDENTE (municao de conversa, "
                    "nao slide): o PMI ja roda essas jogadas - Content Distribution com Agile Trends (Brasil!), "
                    "Academic com ATP (Red Learning), Co-Branding com org de treinamento (OTEAcademy). E pratica "
                    "sancionada, nao experimento (Apendice B do Partnerships Framework).",
        },
        # 4 ---------------------------------------------------------------------------
        "synergy": {
            "eyebrow": "A sinergia",
            "title": "Onde os dois ecossistemas se encontram",
            "center": "Profissionais de IA\nque entregam projetos",
            "caption": "A formação do ALUN vira entrega e carreira: do aluno de IA ao membro e certificado PMI (funil "
                       "natural). Complementar, não concorrente: o ALUN forma, o PMI certifica e dá o ambiente.",
            "purposes": "Ativa as 3 arenas do PMI:Next: plataformas de conhecimento, aprendizado contínuo de carreira e as certificações 'gold standard'.",
            "note": "FUNDE o antigo 'gap' + 'troca de valor'. Titulo NAO agressivo: e sinergia/interseccao. Diagrama "
                    "Venn (synergy.png). A linha 'purposes' nomeia os 6 PROPOSITOS oficiais de parceria do PMI "
                    "Framework (Expand Outreach, Brand Awareness, Enhance Member Value, Share Knowledge & Research, "
                    "Activate PMI:Next, Strengthen Operations) em PT-BR. Tese do Vitor: pool de talento do ALUN + "
                    "ambiente/cultura/protecao do Nucleo.",
        },
        # 5 ---------------------------------------------------------------------------
        "who": {
            "eyebrow": "Quem somos",
            "title": "Uma comunidade de prática federada",
            "lead": "Iniciativa federada de Communities of Practice (CoP, conceito do próprio PMI) para mudar cultura e avançar a transformação digital na era pós-IA.",
            "h1": "Pessoas e cultura: nosso diferencial",
            "l1": ["Time voluntário selecionado por critério: mestres, doutores, C-level, professores, gestores.",
                   "Segunda onda de protagonismo, num único foco: IA aplicada à gestão de projetos.",
                   "Começou no PMI-GO; hoje engaja capítulos do PMI no Brasil por cooperação."],
            "h2": "O que o Núcleo oferece",
            "l2": ["Verticais de pesquisa e exposição a temáticas diversas.",
                   "Upskilling, networking e oportunidades dentro da comunidade PMI.",
                   "Ambiente para inovação e até formação de negócios (incubação)."],
            "proof_h": "Tração e palco · dados públicos (jun/2026)",
            "proof": ["72 colaboradores · 8 tribos · capítulo-sede PMI-GO + 4 capítulos parceiros (15 engajados) · 1.618h de impacto.",
                      "SESTEC / Univ. de Vassouras (jun/2026): mesa redonda 'IA e o futuro das competências', transmissão ao vivo com +1.000 espectadores.",
                      "PMI LIM LATAM 2026 (Lima): sessão aceita no encontro de líderes do PMI na América Latina.",
                      "Prêmio Carlos Novello: finalista como Voluntário do Ano (PMI LATAM)."],
            "note": "Pessoas e cultura ANTES dos numeros (maior patrimonio). Numeros PUBLICOS ao vivo: 72 colab, 8 "
                    "tribos, 5 capitulos (PMI-GO sede 23 + CE 18 + MG 12 + RS 9 + DF 6) / 15 engajados, 1.618h. "
                    "SESTEC, LIM LATAM e Carlos Novello agora em LINHAS SEPARADAS com contexto (pedido do Vitor: "
                    "estavam na mesma linha e pareciam congruentes, mas sao coisas distintas). SESTEC: fonte "
                    "publica = transmissao YouTube canal SESTec/@nucleo_ia (2/jun/2026, ~1.065 views).",
        },
        # 6 ---------------------------------------------------------------------------
        "pmi": {
            "eyebrow": "A instituição",
            "title": "O peso de cooperar com o PMI",
            "h1": "A comunidade",
            "l1": ["800 mil membros (marco anunciado pelo CEO do PMI, 2026).",
                   "Mantido por voluntários, feito para voluntários: comunidade global.",
                   "Cresce em todas as regiões; capítulos como motor local."],
            "h2": "A máquina global",
            "l2": ["Domina as certificações de gestão de projetos globalmente aceitas.",
                   "Dono dos Standards (ANSI), incluindo o de IA.",
                   "PMIxAI (pilar do PMI:Next): 4 cursos de IA com +350 mil inscritos, o AI Practice Guide e a plataforma PMI Infinity."],
            "caption": "Cooperar com um capítulo do PMI é plugar nessa máquina: marca, padrão, certificação e comunidade globais.",
            "note": "Slide DEDICADO do PMI (pedido explicito do Vitor: faltava). Da o PESO da instituicao antes "
                    "da autoridade dos standards. 800 mil membros = marco anunciado pelo CEO Pierre Le Manh (post "
                    "publico 2026; atribuido, nao e metrica de plataforma). PMI:Next = a estrategia que o "
                    "Partnerships Framework existe para ativar. PMI Infinity = plataforma de IA do PMI.",
        },
        # 7 ---------------------------------------------------------------------------
        "ansi": {
            "eyebrow": "A autoridade",
            "title": "O PMI não só ensina IA: escreve o padrão",
            "head": ["Padrão (ANSI)", "O que o PMI define"],
            "rows": [
                ["ANSI/PMI 26-007 · 2026", "Standard for AI in Portfolio, Program and Project Mgmt: 1º standard de IA aprovado pela ANSI, recém-lançado; alinhado a EU AI Act e ISO 42001."],
                ["ANSI/PMI 99-001", "Standard for Project Management (PMBOK Guide 7ª ed.)."],
                ["ANSI/PMI 08-002", "Standard for Program Management (2024)."],
                ["ANSI/PMI 19-006", "Earned Value Management (2019)."],
            ],
            "caption": "E não só padrão: um roadmap de carreira (o 'career-long learning' do PMI:Next). Do PMP às especializações, até a fronteira: a IA.",
            "covers": [
                {"slot": "ansi_ai_standard", "label": "Standard de IA · ANSI/PMI 26-007 (2026)"},
            ],
            "certs": [
                {"file": "PMP.jpeg", "label": "PMP", "desc": "Gerenciamento de projetos"},
                {"file": "PMI-ACP.png", "label": "PMI-ACP", "desc": "Práticas ágeis"},
                {"file": "PMI-PMOCP.png", "label": "PMI-PMOCP", "desc": "Gestão de PMO"},
                {"file": "PMI-CP.png", "label": "PMI-CP", "desc": "Construção"},
                {"file": "PMI CSPP.jpeg", "label": "CSPP", "desc": "Sustentabilidade · ESG"},
                {"file": "PMI-CPMAI.png", "label": "PMI-CPMAI", "desc": "Gestão de IA", "hero": True},
            ],
            "note": "Codigo ANSI/PMI 26-007-2026 CONFIRMADO lendo o selo da capa oficial (corrige o 25-001 errado). "
                    "Standard de IA = PRIMEIRO aprovado pela ANSI, recem-lancado = elo com o time ALUN. CERTS agora "
                    "como ROADMAP DE CARREIRA (decisao do Vitor: mostrar o roadmap completo; mapeia a arena #2 do "
                    "PMI:Next 'Career-Long Learning'): PMP (base) > PMI-ACP (agil) > PMI-PMOCP (PMO) > PMI-CP "
                    "(construcao) > CSPP (sustentabilidade/ESG, com GPM) > PMI-CPMAI (IA, HERO/fronteira, destacado). "
                    "Legendas PT-BR. Selos com fundo transparente; CSPP vem de JPEG branco (prep_certs torna transp).",
        },
        # 8 ---------------------------------------------------------------------------
        "whynow": {
            "eyebrow": "Por que agora",
            "title": "Onde os projetos de IA travam",
            "caption": "95% dos pilotos de IA generativa não chegam a valor (MIT, 2025); a maioria falha por "
                       "começar sem gestão (McKinsey, PMI Pulse). Não é falha de quem ensina IA: falta o elo de "
                       "execução e de valor percebido (o que o PMI chama de M.O.R.E.). É aí que ALUN e Núcleo se somam.",
            "covers": [
                {"slot": "mckinsey", "label": "McKinsey · State of AI"},
                {"slot": "pmi_pulse", "label": "PMI · Pulse of the Profession"},
            ],
            "note": "REESCRITO p/ NAO denegrir o ALUN: a dor e de MERCADO (MIT 95%, McKinsey, PMI Pulse), nao "
                    "fraqueza deles. O elo que falta e EXECUCAO (gestao de projetos / CPMAI), onde os dois se "
                    "SOMAM. Diagrama strategy_flow.png (Estrategia > Execucao > Valor, ponte CPMAI).",
        },
        # 9 ---------------------------------------------------------------------------
        "formalize": {
            "eyebrow": "Como formalizamos",
            "title": "Um caminho de governança claro",
            "steps": [
                ["1 · Informal", ["Conteúdo e co-branding começam já.", "Sem assinar nada.", "Prova o valor na prática."]],
                ["2 · MOU", ["Acordo preliminar (não-vinculante).", "Define papéis, marca e dados.", "Enquadra a relação."]],
                ["3 · Contrato", ["Master Agreement, quando fizer sentido.", "NDA + acordo de PI (copyright).", "Cada parte com seu jurídico."]],
            ],
            "caption": "Tudo dentro do PMI Chapter Partnerships Framework. Você não assina nada para começar; formaliza quando o valor estiver provado. As frentes são desenhadas para baixo risco e baixo investimento do capítulo.",
            "note": "REINTRODUZIDO com enquadramento de AUTORIDADE (decisao do Vitor): mostra que conhecemos o "
                    "processo oficial do PMI (LOI/Informal -> MOU preliminar -> Contrato/Master Agreement, com NDA "
                    "+ IP Agreement). O framework explicita que parceiro que engaja proativamente volta ao Passo 1 "
                    "(nosso caso). PMI nao da consultoria juridica: cada parte tem advogado proprio (por isso 'cada "
                    "parte com seu juridico', sem implicar template legal). A frase final sinaliza os criterios da "
                    "matriz de avaliacao do PMI (baixo risco/investimento do capitulo = score alto).",
        },
        # 10 --------------------------------------------------------------------------
        "managers": {
            "eyebrow": "Quem conduz",
            "title": "Gestores do projeto",
            "people": [
                {"name": "Vitor Maia Rodovalho", "role": "Idealizador e líder · Núcleo IA & GP",
                 "sub": "Senior Cost Manager na Linesight (grupo Berkshire Hathaway), em projetos de data centers para a Google.",
                 "photo": "vitor.jpg", "linkedin": "linkedin.com/in/vitor-rodovalho-pmp",
                 "phone": "+1 267-874-8329"},
                {"name": "Fabrício Costa", "role": "Co-gestor · Núcleo IA & GP",
                 "sub": "Program Manager de Design e Engenharia na AWS; doutorando em Business.",
                 "photo": "fabricio.jpg", "linkedin": "linkedin.com/in/fabriciorcc",
                 "phone": "+1 503-544-7898"},
            ],
            "links": [
                ("Plataforma do Núcleo", "nucleoia.pmigo.org.br", "https://nucleoia.pmigo.org.br"),
                ("PMI", "pmi.org", "https://www.pmi.org"),
                ("Mentor: Mário Trentim, PMI Global Board", "pmi.org/about/board-of-directors", "https://www.pmi.org/about/board-of-directors"),
            ],
            "mentor": "Iniciativa voluntária, mentorada por Mário Trentim, hoje no PMI Global Board.",
            "note": "Rostos + contatos clicaveis. Credly REMOVIDO. Telefones + cargo atual de cada um. Links "
                    "clicaveis: nucleoia.pmigo.org.br (confirmado HTTP 200, redireciona p/ vitormr.dev), pmi.org, "
                    "board do PMI p/ o Mario.",
        },
        # 11 --------------------------------------------------------------------------
        "ask": {
            "eyebrow": "O convite",
            "title": "Vamos construir algo grande",
            "h1": "O pedido",
            "l1": ["Escolher 1 das 3 frentes para um primeiro movimento.",
                   "Indicar um ponto focal do ALUN.",
                   "Async por aqui, no seu tempo, ou um café de 30 min."],
            "h2": "Pontes já abertas",
            "l2": ["Mentoria do Mário Trentim (PMI Global Board), que já atendeu vocês.",
                   "SGPL 24-26/set (Goiânia) como primeiro palco.",
                   "Janela quente: o standard de IA acabou de ser publicado."],
            "cta_h": "Entrar no flywheel do PMI",
            "cta": "A comunidade global que multiplica valor pela rede. É só o começo, e queremos vocês nele.",
            "note": "Fecho AMBICIOSO (nada de 'comecar pequeno'). Ask de baixa friccao (1 frente, focal, async - "
                    "eco da msg do Kruel), mas enquadramento de construir algo grande e escalavel.",
        },
    }
}
