UPDATE public.governance_documents SET version='v2.1', status='under_review', updated_at=now()
WHERE id='cfb15185-2800-4441-9ff1-f36096e83aa8';

INSERT INTO public.document_versions
  (document_id, version_number, version_label, content_html,
   authored_by, authored_at, published_at, published_by, locked_at, locked_by, notes)
VALUES
  ('cfb15185-2800-4441-9ff1-f36096e83aa8', 1, 'v2.1',
   $html_v21$
<p><strong>Política de Publicação e Propriedade Intelectual</strong></p>
<p>Núcleo de Estudos e Pesquisa em Inteligência Artificial e Gestão de Projetos</p>
<p><em>DRAFT v2.1 — Pendente validação jurídica e aprovação | CR-050</em></p>
<p>Capítulos: PMI-GO (sede), PMI-CE, PMI-DF, PMI-MG, PMI-RS</p>
<p><strong>Nota de versão:</strong> Esta versão consolida o draft v1.0 com as revisões do CR-050 decorrentes da análise colaborativa com o Presidente do PMI-GO (Ivan Lourenço), com o Diretor Curador PMI-CE (Roberto Macêdo) e com o Gerente de Projeto do Núcleo (Vitor Rodovalho), incorporando as considerações de conflito com periódicos exclusivos, enquadramento jurídico correto para software e documentos, governança de registro, política de uso e royalties, escopo internacional e alinhamento terminológico com a LGPD.</p>
<p><strong>Nota v2.0 → v2.1 (19/Abr/2026):</strong> Incorporados os ajustes do parecer de auditoria jurídica pré-ratificação: (i) silêncio positivo na notificação de depósito de marcas e patentes aos demais presidentes signatários (§1 da Cláusula 4.2.1); (ii) retenção IRRF sobre royalties (alínea "e" da Cláusula 4.5.4); (iii) mecanismo de re-licenciamento CC-BY-SA → CC-BY para obras Track B submetidas a periódicos que exigem licença não-SA (Seção 5, Track B); (iv) nota interpretativa sobre AI training vs. citação acadêmica de material PMI (Seção 11); (v) nota sobre aplicabilidade do GDPR para voluntários residentes na União Europeia (Seção 2).</p>
<p>1. Escopo Institucional e Lei Aplicável</p>
<p><strong>1.1</strong> O Núcleo de Estudos e Pesquisa em IA &amp; GP é programa interinstitucional sediado no Brasil, tendo o PMI Brasil–Goiás Chapter (PMI-GO) como capítulo sede e entidade juridicamente responsável, com os demais capítulos signatários (PMI-CE, PMI-DF, PMI-MG, PMI-RS) vinculados por Acordos de Cooperação Bilaterais.</p>
<p><strong>1.2</strong> Esta Política é regida pela legislação brasileira, em especial:</p>
<ul>
<li><p>Lei nº 9.610, de 19 de fevereiro de 1998 (Direitos Autorais);</p></li>
<li><p>Lei nº 9.609, de 19 de fevereiro de 1998 (Proteção da Propriedade Intelectual de Programa de Computador);</p></li>
<li><p>Lei nº 9.279, de 14 de maio de 1996 (Propriedade Industrial);</p></li>
<li><p>Lei nº 9.608, de 18 de fevereiro de 1998 (Serviço Voluntário), com redação atualizada pela Lei nº 13.297, de 16 de junho de 2016;</p></li>
<li><p>Lei nº 13.709, de 14 de agosto de 2018 (Lei Geral de Proteção de Dados Pessoais — LGPD).</p></li>
</ul>
<p><strong>1.3</strong> Aplicam-se ainda os tratados internacionais vigentes no Brasil em matéria de propriedade intelectual, em especial a Convenção de Berna para a Proteção das Obras Literárias e Artísticas (promulgada pelo Decreto nº 75.699, de 6 de maio de 1975) e o Acordo TRIPS (promulgado pelo Decreto nº 1.355, de 30 de dezembro de 1994), nos termos do art. 2º da Lei nº 9.610/1998.</p>
<p><strong>1.4</strong> O Núcleo reconhece sua natureza transnacional, decorrente de: (a) filiação ao Project Management Institute, entidade global sediada nos Estados Unidos; (b) participação de voluntários residentes em jurisdições estrangeiras; (c) apresentação de obras em eventos e periódicos internacionais; (d) celebração de acordos com entidades internacionais.</p>
<p><strong>1.5</strong> Para VOLUNTÁRIOS residentes fora do Brasil, a licença concedida ao Núcleo (Cláusula 2.2 do Termo de Voluntariado) será interpretada nos termos equivalentes aos previstos nesta Política, respeitada a legislação da jurisdição local do autor no que for mais protetivo em matéria de direitos morais, conforme o princípio do tratamento nacional da Convenção de Berna (Art. 5.1).</p>
<p><strong>1.6</strong> O Código de Ética e Conduta Profissional do Project Management Institute é reconhecido como instrumento aplicável a todos os voluntários independentemente de jurisdição, complementando a legislação local.</p>
<p><strong>1.7</strong> Controvérsias serão resolvidas prioritariamente por conciliação interna mediada pelo Gerente de Projeto e pelos presidentes dos capítulos envolvidos. Persistindo o conflito, o foro de eleição é a Comarca de Goiânia/GO, ressalvado que, em casos envolvendo voluntários residentes no exterior ou entidades internacionais, o método de solução de controvérsias poderá ser definido em instrumento específico.</p>
<p><strong>1.7.1</strong> <em>(Adendo — Protocolo Reforçado para Solução Internacional de Controvérsias).</em> Quando a controvérsia envolver voluntário residente no exterior ou entidade internacional parte de acordo com o Núcleo, e não sendo possível a conciliação interna no prazo de 60 (sessenta) dias, as partes poderão optar, em instrumento específico, por: (i) arbitragem conforme regras da Câmara de Comércio Internacional (ICC) ou de câmara arbitral brasileira; (ii) submissão ao PMI Ethics Review Committee, quando a matéria envolver conduta ética profissional; ou (iii) foro da Comarca de Goiânia/GO com opção por processo em língua inglesa ou portuguesa. A ativação deste protocolo não é obrigatória e depende de acordo expresso entre as partes.</p>
<p>2. Proteção de Dados Pessoais e Política de Privacidade</p>
<p><strong>2.1</strong> O tratamento de dados pessoais no âmbito do Núcleo observa a Lei nº 13.709/2018 (LGPD) e a Política de Privacidade do PMI Brasil–Goiás Chapter (PMI-GO), disponível em pmigo.org.br/politicas/ e espelhada em nucleoia.vitormr.dev/privacy, na condição de capítulo sede e controlador dos dados tratados no âmbito do Programa.</p>
<p><strong>2.2</strong> Os demais capítulos signatários dos Acordos de Cooperação Bilaterais aderem à Política de Privacidade do PMI-GO como referência operacional do Programa, sem prejuízo de suas próprias políticas institucionais para atividades fora do escopo do Núcleo.</p>
<p><strong>2.3</strong> O Encarregado pela Proteção de Dados Pessoais (DPO) designado pelo PMI-GO atua como ponto focal de comunicação com titulares de dados e com a Autoridade Nacional de Proteção de Dados (ANPD) para todas as atividades do Núcleo.</p>
<p><strong>2.4</strong> Em caso de ambiguidade ou lacuna entre a Política de Privacidade do PMI-GO e a legislação aplicável, prevalece a disposição mais protetiva ao titular dos dados, observado o disposto na legislação federal brasileira.</p>
<p><strong>2.5</strong> Para voluntários residentes em países membros da União Europeia, o Programa avaliará a aplicabilidade do Regulamento (UE) 2016/679 (GDPR) em consulta com o Encarregado do PMI-GO antes da formalização do vínculo, incluindo a verificação da necessidade de Data Processing Agreement (DPA), representante na UE (Art. 27 GDPR) e base legal adequada para transferência internacional de dados. Até deliberação específica, aplicam-se os padrões LGPD com observância do princípio da disposição mais protetiva ao titular.</p>
<p>3. Princípios</p>
<p>1. Direitos morais (autoria, crédito, integridade) são inalienáveis e pertencem aos autores.</p>
<p>2. O Núcleo é uma colaboração multi-capítulo; a propriedade intelectual não pertence a um único capítulo.</p>
<p>3. Pesquisadores devem ter caminho claro para publicação com crédito adequado, inclusive em periódicos e editoras externas.</p>
<p>4. Transparência e equidade entre voluntários de todos os capítulos.</p>
<p>5. Proteção de informações confidenciais e dados pessoais (LGPD).</p>
<p>6. Sempre que possível, obras registradas pelo Núcleo são disponibilizadas para uso universal com atribuição, privilegiando o impacto sobre a reserva comercial.</p>
<p>4. Registro de Propriedade Intelectual e Política de Exploração</p>
<p>4.1 Âmbito de Aplicação</p>
<p>Esta seção aplica-se a obras produzidas no âmbito do Programa que sejam candidatas a registro formal de propriedade intelectual, incluindo:</p>
<ul>
<li><p>(a) Registro autoral de obras literárias, científicas, artísticas ou compilações junto ao Escritório de Direitos Autorais da Fundação Biblioteca Nacional (EDA/FBN), conforme a Lei nº 9.610/1998;</p></li>
<li><p>(b) Registro de programa de computador junto ao Instituto Nacional da Propriedade Industrial (INPI), conforme a Lei nº 9.609/1998;</p></li>
<li><p>(c) Depósito de patente de invenção, patente de modelo de utilidade, registro de desenho industrial ou registro de marca junto ao INPI, conforme a Lei nº 9.279/1996;</p></li>
<li><p>(d) Registros internacionais equivalentes, quando aplicáveis, observados os tratados vigentes no Brasil (Convenção de Berna, TRIPS, Tratado de Cooperação em Matéria de Patentes — PCT, entre outros).</p></li>
</ul>
<p>4.2 Análise de Viabilidade pela Curadoria</p>
<p>A Comissão de Curadoria do Núcleo é responsável pela análise de viabilidade de registro, mediante parecer fundamentado que considere:</p>
<ul>
<li><p><strong>(a) Originalidade e mérito técnico-científico</strong> da obra;</p></li>
<li><p><strong>(b) Requisitos legais de registrabilidade</strong> (para patentes: novidade, atividade inventiva, aplicação industrial, conforme art. 8º da Lei nº 9.279/1996; para software e obras autorais: originalidade);</p></li>
<li><p><strong>(c) Estratégia de proteção</strong> mais adequada ao caso concreto (autoral vs. industrial; registro nacional vs. internacional);</p></li>
<li><p><strong>(d) Análise de custo-benefício,</strong> considerando os valores praticados pelos órgãos competentes e os benefícios institucionais do registro;</p></li>
<li><p><strong>(e) Política de exploração</strong> aplicável à obra (Seção 4.5), definida no próprio ato de solicitação de registro;</p></li>
<li><p><strong>(f) Existência de direitos de terceiros</strong> que possam ser afetados.</p></li>
</ul>
<p><strong>4.2.1</strong> O parecer da Curadoria é submetido à aprovação do Gerente de Projeto e do Presidente do PMI-GO, capítulo sede e titular legal do registro. Aprovado o registro, os demais presidentes signatários dos Acordos de Cooperação Bilaterais serão notificados com antecedência mínima de 15 (quinze) dias do ato de depósito, em consonância com o princípio de tratamento igualitário entre capítulos previsto na Seção 9 desta Política.</p>
<p><strong>§ 1º Aprovação tácita por silêncio para marcas e patentes.</strong> Para depósito de marcas e patentes — ativos de maior impacto sobre a identidade institucional do Programa — a ausência de manifestação contrária por escrito de qualquer dos presidentes signatários no prazo de 15 (quinze) dias contados do recebimento da notificação importa aprovação tácita, nos termos do art. 111 do Código Civil. Em caso de manifestação contrária, o depósito será suspenso por até 30 (trinta) dias para deliberação conjunta entre os presidentes signatários. Para registros autorais junto à EDA/FBN, mantém-se a notificação simples sem efeito de aprovação tácita.</p>
<p><strong>4.2.2</strong> Em caso de parecer desfavorável, a obra permanece protegida nos termos da proteção automática prevista na Lei nº 9.610/1998 e na Convenção de Berna (proteção independe de registro), sem prejuízo de publicação sob Track A ou Track B conforme esta Política.</p>
<p>4.3 Titularidade</p>
<p>Os registros formais de propriedade intelectual de obras produzidas no âmbito do Programa são depositados em nome do <strong>PMI Brasil–Goiás Chapter (PMI-GO)</strong>, como capítulo sede do Núcleo e entidade juridicamente responsável, preservados:</p>
<ul>
<li><p>(a) Os direitos morais dos autores individuais, nos termos da Cláusula 2.1 do Termo de Voluntariado e das Leis nº 9.610/1998 e nº 9.609/1998;</p></li>
<li><p>(b) A identificação nominal dos autores/inventores no ato do registro, conforme exigido pela legislação aplicável (art. 6º, §4º, da Lei nº 9.279/1996 — direito do inventor de ser nomeado);</p></li>
<li><p>(c) O direito de uso irrevogável pelos demais capítulos signatários dos Acordos de Cooperação Bilaterais, nos termos do respectivo Adendo de Propriedade Intelectual.</p></li>
</ul>
<p>4.4 Custeio</p>
<p><strong>4.4.1</strong> Os custos de registro — incluindo taxas dos órgãos competentes (INPI, EDA/FBN, órgãos internacionais), honorários de agentes de propriedade industrial quando necessários, e anuidades de manutenção — são custeados pelo orçamento anual do Núcleo, administrado pelo PMI-GO.</p>
<p><strong>4.4.2</strong> O Núcleo beneficia-se dos descontos de 50% (cinquenta por cento) concedidos pelo INPI a entidades sem fins lucrativos, nos termos do art. 2º da Portaria INPI/PR nº 10/2025 ou norma posterior equivalente, mediante comprovação da natureza jurídica do PMI-GO.</p>
<p><strong>4.4.3</strong> O orçamento anual de propriedade intelectual é aprovado pela Presidência do PMI-GO em consulta aos demais presidentes signatários, com previsão de reserva técnica para eventuais registros emergenciais ao longo do ciclo.</p>
<p><strong>4.4.4</strong> Em caso de impossibilidade orçamentária de arcar com os custos de registro ou manutenção de um ativo já registrado, a Curadoria apresentará parecer sobre as opções disponíveis, incluindo:</p>
<ul>
<li><p>(a) busca de patrocínio externo específico;</p></li>
<li><p>(b) parceria com instituição de pesquisa ou universidade que possa custear o registro em regime de cotitularidade;</p></li>
<li><p>(c) publicação defensiva (<em>defensive publication</em>), que afasta a patenteabilidade por terceiros sem gerar custos de manutenção;</p></li>
<li><p>(d) renúncia ao registro, com manutenção da proteção automática da obra pela Lei nº 9.610/1998.</p></li>
</ul>
<p>4.5 Política de Exploração e Royalties</p>
<p><strong>4.5.1 Regime padrão — Uso universal com atribuição.</strong> Por padrão, obras registradas em nome do Núcleo/PMI-GO serão disponibilizadas sob regime de uso universal gratuito com atribuição, mediante declaração formal no ato do registro ou por meio de licença pública compatível (CC-BY 4.0 para obras autorais; MIT ou Apache-2.0 para software; declaração equivalente para patentes, quando aplicável).</p>
<p><strong>4.5.2 Finalidade do registro sob regime padrão.</strong> Nesse regime, o registro tem finalidade defensiva e de reconhecimento formal da autoria institucional, afastando apropriação indevida por terceiros sem gerar reserva comercial de mercado.</p>
<p><strong>4.5.3 Regime de exploração com retorno financeiro.</strong> Em caráter excepcional, mediante parecer específico da Curadoria e aprovação pela Presidência do PMI-GO em consulta aos demais presidentes signatários, uma obra poderá ser registrada sob regime de exploração comercial com previsão de royalties ou licenciamento oneroso.</p>
<p><strong>4.5.4 Destinação de royalties.</strong> Quando houver previsão de royalties, sua destinação será definida no próprio instrumento de aprovação do registro, observando as seguintes diretrizes mínimas:</p>
<ul>
<li><p>(a) Reconhecimento de percentual aos autores/inventores individuais, nos termos a serem acordados;</p></li>
<li><p>(b) Alocação de parcela ao fundo de pesquisa e custeio do Núcleo;</p></li>
<li><p>(c) Distribuição equitativa entre os capítulos signatários, conforme regra específica aprovada caso a caso;</p></li>
<li><p>(d) Vedação ao uso de royalties para fins alheios aos objetivos institucionais do Núcleo e do PMI-GO;</p></li>
<li><p>(e) Retenção e recolhimento dos tributos incidentes sobre os royalties conforme a legislação tributária vigente, ficando a cargo do PMI-GO a responsabilidade pela retenção na fonte aplicável — Imposto de Renda Retido na Fonte (IRRF) para beneficiários residentes no Brasil, nos termos da Lei nº 7.713/1988 e da tabela progressiva vigente; e imposto sobre remessas ao exterior para beneficiários não residentes, nos termos do art. 5º da Lei nº 9.779/1999 e da Instrução Normativa RFB nº 1.455/2014 —, deduzindo o valor retido do montante a pagar ao beneficiário.</p></li>
</ul>
<p><strong>4.5.5 Prevenção de caducidade por desuso.</strong> Para registros sujeitos à caducidade por desuso — em especial marcas registradas (art. 143 da Lei nº 9.279/1996) e patentes sujeitas a licença compulsória por não exploração (art. 68 da Lei nº 9.279/1996) — a Curadoria manterá controle anual de uso efetivo ou licenciamento, adotando tempestivamente medidas de preservação do direito, incluindo declaração pública de <em>patent pledge</em> ou <em>defensive publication</em> quando couber.</p>
<p>4.6 Registros Internacionais</p>
<p>A decisão sobre depósito em jurisdições estrangeiras — diretamente nos respectivos escritórios nacionais (USPTO, EPO, entre outros) ou por meio do Tratado de Cooperação em Matéria de Patentes (PCT) — segue o mesmo fluxo de análise da Curadoria, aprovação pela Presidência e custeio por orçamento específico, observadas as regras de prioridade unionista previstas na Convenção de Paris e na Lei nº 9.279/1996 (arts. 16 e 17).</p>
<p>5. Tracks de Publicação</p>
<p>Track A — Aberto</p>
<p><strong>Tipos:</strong> Artigos, reviews comparativas, webinars, posts de blog, apresentações em eventos, livros, capítulos de livro.</p>
<p><strong>Licença:</strong> CC-BY 4.0 (Creative Commons Atribuição 4.0 Internacional).</p>
<p><strong>Aprovação:</strong> Notificação ao Gerente de Projeto com 15 (quinze) dias de antecedência (não requer autorização prévia).</p>
<p><strong>Crédito:</strong> Autor(es) + "Núcleo de Estudos e Pesquisa em IA &amp; GP — PMI [Capítulos]".</p>
<p><strong>Restrições:</strong> Não pode incluir dados pessoais (LGPD), informações confidenciais, ou material protegido do PMI sem permissão.</p>
<p>Track B — Framework</p>
<p><strong>Tipos:</strong> Frameworks originais, metodologias, ferramentas conceituais, livros técnicos/metodológicos, templates reutilizáveis, código-fonte.</p>
<p><strong>Licença:</strong> CC-BY-SA 4.0 (documentos/metodologias) ou MIT/Apache-2.0 (código-fonte).</p>
<p><strong>Aprovação:</strong> Gerente de Projeto + pelo menos 1 (um) presidente de capítulo parceiro.</p>
<p><strong>Crédito:</strong> Autores individuais + líder da tribo (se supervisionou) + Núcleo.</p>
<p><strong>Restrições:</strong> Revisão prévia pelo GP para garantir ausência de IP de terceiros.</p>
<p><strong>Re-licenciamento para periódicos.</strong> Quando obra licenciada sob CC-BY-SA 4.0 (Track B) for submetida a periódico científico que exija licença CC-BY 4.0 (ou equivalente não-SA) como condição de publicação, o Gerente de Projeto — com concordância expressa dos autores individuais — poderá autorizar a publicação da versão submetida sob CC-BY 4.0, preservando-se a versão originalmente publicada pelo Núcleo sob CC-BY-SA 4.0. O re-licenciamento aplica-se exclusivamente à versão editorial submetida, não afetando os direitos sobre a versão originalmente publicada pelo Núcleo nem os direitos morais dos autores. O mesmo mecanismo aplica-se a obras Track B licenciadas sob CC-BY-SA 4.0 que precisem ser submetidas sob MIT ou Apache-2.0 por exigência de repositório de código.</p>
<p>Track C — Restrito</p>
<p><strong>Tipos:</strong> Algoritmos proprietários, modelos de scoring, dados de seleção, invenções patenteáveis, dados PII agregados.</p>
<p><strong>Licença:</strong> Proprietário (Núcleo/PMI-GO como capítulo sede).</p>
<p><strong>Aprovação:</strong> Gerente de Projeto + Presidente do PMI-GO + Encarregado pela Proteção de Dados Pessoais (DPO) do PMI-GO, quando o conteúdo envolver dados pessoais nos termos da Lei nº 13.709/2018 (LGPD).</p>
<p><strong>Crédito:</strong> Inventores/autores registrados internamente; publicação externa requer aprovação específica.</p>
<p><strong>Restrições:</strong> Acesso restrito. Avaliação de patenteabilidade antes de divulgação (Lei nº 9.279/1996, art. 11).</p>
<p><strong>Sobre livros e publicações comerciais:</strong> <em>As licenças CC-BY e CC-BY-SA permitem uso comercial. Um voluntário pode publicar um livro por editora, cobrar por ele — a única exigência é atribuição ao Núcleo. É o padrão acadêmico global: PLOS ONE, Nature Communications e Springer Open publicam sob CC-BY 4.0. A OpenStax (Rice University) publica livros didáticos inteiros sob CC-BY. Licenciar não é perder controle — é formalizar o que já funciona no mundo científico.</em></p>
<p>6. Definição Operacional de Publicação Prévia e Ineditismo</p>
<p><strong>6.1</strong> Para fins de relacionamento do Núcleo com periódicos científicos, editoras e eventos que exijam ineditismo da obra, aplica-se a seguinte definição operacional, sem prejuízo das definições específicas de cada publicador externo:</p>
<p><strong>Não constituem publicação prévia</strong> (obra permanece inédita):</p>
<ul>
<li><p>Rascunhos, versões preliminares ou work-in-progress em circulação restrita a membros do Núcleo;</p></li>
<li><p>Apresentações internas em webinars, reuniões de tribo ou reuniões gerais do Núcleo, sem gravação de acesso público;</p></li>
<li><p>Discussões em boards, cards e canais de comunicação internos da plataforma (nucleoia.vitormr.dev);</p></li>
<li><p>Relatórios internos de tribo ou de curadoria.</p></li>
</ul>
<p><strong>Constituem publicação prévia</strong> (obra deixa de ser considerada inédita para efeito editorial):</p>
<ul>
<li><p>Artigos, posts ou papers publicados em blog público, site ou mídias sociais do Núcleo;</p></li>
<li><p>Apresentações em congressos, seminários ou eventos externos com registro ou gravação de acesso público (incluindo CBGPL, PMI LIM Summit, PMI Global Congress, entre outros);</p></li>
<li><p>Obras licenciadas publicamente sob Track A (CC-BY 4.0) ou Track B (CC-BY-SA 4.0 / MIT / Apache-2.0) antes da submissão ao publicador externo;</p></li>
<li><p>Preprints depositados em repositórios públicos (arXiv, SSRN, Zenodo, ResearchGate etc.).</p></li>
</ul>
<p><strong>6.2</strong> Em caso de dúvida sobre enquadramento, o VOLUNTÁRIO deve consultar o Gerente de Projeto antes da submissão externa.</p>
<p><strong>6.3</strong> Publicadores externos podem adotar definições mais restritivas ou permissivas de ineditismo — a política editorial do destino prevalece sobre esta definição operacional para efeito de submissão.</p>
<p>7. Regras de Crédito</p>
<p><strong>Autoria:</strong> Autores individuais na ordem de contribuição substantiva.</p>
<p><strong>Afiliação:</strong> Nome do Autor, Núcleo de Estudos e Pesquisa em IA &amp; GP — PMI [Capítulo de origem].</p>
<p><strong>Líder de tribo:</strong> Coautor automático se supervisionou o trabalho e contribuiu intelectualmente.</p>
<p><strong>Gerente de Projeto:</strong> <em>Acknowledgments</em>, não coautor (exceto se contribuiu intelectualmente).</p>
<p>8. Publicação Externa</p>
<p><strong>Congressos e seminários:</strong> Notificação ao GP com 15 (quinze) dias de antecedência. GP pode solicitar revisão, mas não pode vetar publicação Track A.</p>
<p><strong>Eventos PMI (CBGPL, Global Congress, LIM Summit, etc.):</strong> Track A com notificação ao GP e ao presidente do capítulo de origem.</p>
<p><strong>Webinars internos:</strong> Track A por padrão. Gravações ficam disponíveis na plataforma.</p>
<p><strong>Periódicos com exigência de exclusividade:</strong> Aplicam-se os procedimentos de suspensão temporária da licença previstos na Cláusula 2.6 do Termo de Voluntariado.</p>
<p>9. IP nos Acordos de Cooperação</p>
<p><strong>Multi-capítulo:</strong> Tratamento igualitário entre voluntários de todos os capítulos.</p>
<p><strong>Obras coletivas:</strong> Lei nº 9.610/1998, art. 5º, VIII, alínea "h". Direitos patrimoniais pertencem ao Núcleo como programa.</p>
<p><strong>Saída de capítulo:</strong> Retém uso perpétuo, sem exclusividade.</p>
<p><strong>Addendum:</strong> Cada Acordo de Cooperação deverá incluir adendo de IP referenciando esta Política.</p>
<p>10. Acordos com Entidades Internacionais</p>
<p><strong>10.1</strong> Futuros acordos de cooperação ou parceria entre o Núcleo (representado pelo PMI-GO como capítulo sede) e entidades internacionais — incluindo, sem limitação, o programa AIPM Ambassadors, outras seções do PMI globalmente, sociedades acadêmicas estrangeiras e editoras internacionais — herdarão esta Política como baseline de propriedade intelectual.</p>
<p><strong>10.2</strong> Divergências entre esta Política e exigências da entidade parceira serão tratadas por adendo específico ao acordo, preservando-se os direitos morais dos voluntários (Seção 1.5) e o tratamento igualitário entre capítulos signatários (Seção 9).</p>
<p><strong>10.3</strong> A negociação de acordos internacionais será conduzida pelos representantes designados pelo Núcleo. Qualquer cláusula que altere materialmente esta Política deverá ser submetida à aprovação prévia do presidente do PMI-GO e notificada aos demais presidentes signatários com antecedência mínima de 15 (quinze) dias.</p>
<p>11. Material PMI</p>
<p><strong>Restrição:</strong> Material protegido do PMI (PMBOK, figuras, glossário) NÃO pode ser reproduzido sem permissão.</p>
<p><strong>Citação:</strong> Citação breve (até 650 palavras) com fonte completa é permitida.</p>
<p><strong>AI Training:</strong> A cláusula "NO AI TRAINING" do PMI deve ser respeitada integralmente. A proibição aplica-se ao treinamento de modelos de propósito geral com material PMI como dados de entrada. Pesquisa acadêmica que cite, analise criticamente ou comente material PMI como objeto de estudo não constitui uso proibido, sendo permitida nos limites do art. 46 da Lei nº 9.610/1998 (citação para fins educacionais e científicos) e das cláusulas de <em>fair use</em> aplicáveis em jurisdições estrangeiras.</p>
<p>12. Revisão</p>
<p>Esta Política será revisada anualmente ou quando houver mudança significativa na composição de capítulos, na legislação aplicável ou no escopo de acordos internacionais. Revisões seguem o processo de Change Request do Manual Operacional.</p>
<p><em>Draft v2.0 | CR-050 | Núcleo de Estudos e Pesquisa em IA &amp; GP</em></p>
$html_v21$,
   '880f736c-3e76-4df4-9375-33575c190305', now(), now(), '880f736c-3e76-4df4-9375-33575c190305', now(), '880f736c-3e76-4df4-9375-33575c190305',
   'Seed Phase IP-1 v2.1 pos-auditoria juridica 19/Abr/2026 (CR-050 Politica)');

INSERT INTO public.approval_chains
  (document_id, version_id, status, gates, opened_at, opened_by, notes)
SELECT 'cfb15185-2800-4441-9ff1-f36096e83aa8', id, 'review',
  '[{"kind":"curator","threshold":1,"order":1},{"kind":"leader","threshold":1,"order":2},{"kind":"president_go","threshold":1,"order":3},{"kind":"president_others","threshold":4,"order":4},{"kind":"member_ratification","threshold":"all","order":5}]'::jsonb,
  now(), '880f736c-3e76-4df4-9375-33575c190305', 'Chain aberto pos-auditoria juridica 19/Abr/2026'
FROM public.document_versions
WHERE document_id='cfb15185-2800-4441-9ff1-f36096e83aa8' AND version_label='v2.1'
ON CONFLICT (document_id, version_id) DO NOTHING;
