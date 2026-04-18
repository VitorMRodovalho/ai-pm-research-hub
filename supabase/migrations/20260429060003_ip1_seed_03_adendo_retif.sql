UPDATE public.governance_documents SET version='v2.1', status='under_review', updated_at=now()
WHERE id='d2b7782c-dc1a-44d4-a5d5-16248117a895';

INSERT INTO public.document_versions
  (document_id, version_number, version_label, content_html,
   authored_by, authored_at, published_at, published_by, locked_at, locked_by, notes)
VALUES
  ('d2b7782c-dc1a-44d4-a5d5-16248117a895', 1, 'v2.1',
   $html_v21$
<p><strong>Adendo Retificativo ao Termo de Compromisso de Voluntariado</strong></p>
<p>Núcleo de Estudos e Pesquisa em Inteligência Artificial e Gestão de Projetos</p>
<p><em>DRAFT v2.1 — Pendente validação jurídica | CR-050</em></p>
<p>Capítulos: PMI-GO (sede), PMI-CE, PMI-DF, PMI-MG, PMI-RS</p>
<p><strong>Nota v2.0 → v2.1 (19/Abr/2026):</strong> Incorporados os ajustes do parecer de auditoria jurídica pré-ratificação: (i) refinamento da Cláusula 2.2 do Art. 3 para deixar explícito que a suspensão temporária da 2.6 não constitui revogação; (ii) cross-reference da Cláusula 2.4 indicando prevalência da 2.6 para publicações com exigência de exclusividade; (iii) novas subcláusulas 2.6.7 e 2.6.8 na Cláusula 2.6 do Art. 3 (autorização cessão exclusiva + restabelecimento antecipado); (iv) extensão do mecanismo 2.6 para incompatibilidade CC-BY-SA → CC-BY; (v) substituição integral do Art. 4 — incorporação direta das disposições de lei aplicável e jurisdição (antes referenciadas ao R3-C3-IP v2.0, não assinado pelos 52 voluntários); (vi) reformulação do Art. 5 para substituir explicitamente a Cláusula 4 do Termo Original, incorporando as hipóteses (a), (b) e (c) de não-violação.</p>
<p>O presente Adendo Retificativo integra e complementa o Termo de Compromisso de Voluntariado (doravante <strong>Termo Original</strong>) firmado entre o VOLUNTÁRIO e o Capítulo signatário no âmbito do Núcleo de Estudos e Pesquisa em Inteligência Artificial e Gestão de Projetos. As disposições deste Adendo prevalecem sobre aquelas anteriormente estabelecidas no Termo Original, no que houver conflito.</p>
<p>Art. 1 — Objeto</p>
<p>Este Adendo tem por objeto retificar a Cláusula 2 (Propriedade Intelectual) do Termo Original, substituindo-a integralmente pela nova redação constante do Art. 3 abaixo, em razão de necessidade de adequação à legislação brasileira (Leis nº 9.610/1998, nº 9.609/1998, nº 9.279/1996, nº 9.608/1998 e nº 13.709/2018), aos tratados internacionais de propriedade intelectual vigentes no Brasil, ao Código de Ética do Project Management Institute e à natureza multi-capítulo e transnacional do Programa.</p>
<p>Art. 2 — Redação Original (sendo retificada)</p>
<p><strong>CLÁUSULA 2 DO TERMO ORIGINAL</strong></p>
<blockquote>
<p><em>"Todos os direitos sobre produtos e serviços desenvolvidos pelo voluntário serão cedidos ao PMI Goiás por prazo indeterminado."</em></p>
</blockquote>
<p><strong>Fragilidades jurídicas identificadas:</strong></p>
<ul>
<li><p>(i) Direitos morais são inalienáveis (Lei nº 9.610/1998, Art. 24-27) — cessão total é juridicamente ineficaz quanto à parte moral;</p></li>
<li><p>(ii) A cessão de obras futuras por prazo indeterminado é limitada a 5 (cinco) anos, nos termos do art. 51 da Lei nº 9.610/1998;</p></li>
<li><p>(iii) Cessão genérica ("todos os direitos") sem especificação é interpretada restritivamente (art. 4º da Lei nº 9.610/1998);</p></li>
<li><p>(iv) Atribui propriedade intelectual a um único capítulo (PMI-GO) quando o programa é multi-capítulo (PMI-GO, PMI-CE, PMI-DF, PMI-MG, PMI-RS);</p></li>
<li><p>(v) Utiliza enquadramento jurídico inadequado para software e documentos, que são protegidos por direito autoral (Leis nº 9.610/1998 e nº 9.609/1998), não por propriedade industrial (Lei nº 9.279/1996).</p></li>
</ul>
<p>Art. 3 — Nova Redação da Cláusula 2</p>
<p><strong>PROPRIEDADE INTELECTUAL</strong></p>
<p>Os direitos sobre obras intelectuais produzidas pelo VOLUNTÁRIO no âmbito do Programa seguem as regras abaixo:</p>
<p><strong>2.1 Direitos Morais.</strong> O VOLUNTÁRIO retém todos os direitos morais sobre suas obras, incluindo os direitos de paternidade, crédito e integridade, conforme a Lei nº 9.610/1998, Art. 24 a 27, e, quando aplicável, conforme a legislação de direitos morais da jurisdição de residência do VOLUNTÁRIO, reconhecendo-se o padrão mais protetivo ao autor em caso de divergência, nos termos da Convenção de Berna. Esses direitos são inalienáveis e irrenunciáveis.</p>
<p><strong>Parágrafo único.</strong> No caso específico de programa de computador, aplicam-se os direitos morais na extensão prevista pelo art. 2º, §1º, da Lei nº 9.609/1998, que assegura ao VOLUNTÁRIO o direito de reivindicar a paternidade do programa e de opor-se a alterações não autorizadas que impliquem deformação, mutilação ou modificação que prejudiquem sua honra ou reputação.</p>
<p><strong>2.2 Licença ao Núcleo.</strong> O VOLUNTÁRIO concede ao Núcleo de Estudos e Pesquisa em IA &amp; GP licença não-exclusiva, gratuita e mundial para reproduzir, distribuir, exibir publicamente, criar obras derivadas e sublicenciar <strong>cada obra</strong> produzida no âmbito do Programa — exclusivamente para fins educacionais e científicos. A licença é outorgada no momento da entrega ou publicação interna de cada obra específica e vigorará pelo prazo de proteção legal da obra aplicável em cada jurisdição, não caracterizando cessão de obras futuras em bloco, nos termos do art. 51 da Lei nº 9.610/1998. A licença é não-revogável unilateralmente pelo VOLUNTÁRIO após a sua outorga por obra específica, ressalvada a suspensão temporária prevista na subcláusula 2.6, que não constitui revogação da licença mas regime transitório de não-exercício pelo Núcleo, e as hipóteses legais de resolução contratual.</p>
<p><strong>2.3 Direito de Publicação.</strong> O VOLUNTÁRIO mantém o direito de publicar individualmente ou em coautoria as obras produzidas, desde que inclua atribuição ao Núcleo conforme a Política de Publicação e Propriedade Intelectual vigente.</p>
<p><strong>2.4 Notificação.</strong> Publicações externas de obras produzidas no Programa requerem notificação prévia ao Gerente de Projeto com 15 (quinze) dias de antecedência, exceto para conteúdo classificado como confidencial (cláusula 9 do Termo Original). O GP pode solicitar revisão, mas não pode vetar publicação de conteúdo Track A (Aberto). Quando a publicação externa envolver exigência de exclusividade pelo publicador, aplicam-se adicionalmente os procedimentos da subcláusula 2.6, que prevalece sobre esta no que for específico.</p>
<p><strong>2.5 Enquadramento Jurídico das Obras.</strong> Os direitos sobre as obras produzidas pelo VOLUNTÁRIO no âmbito do Programa seguem o enquadramento legal aplicável à natureza de cada obra, nos termos da Política de Publicação e Propriedade Intelectual, observando-se:</p>
<ul>
<li><p>(a) Obras literárias, científicas, artísticas, frameworks, metodologias, templates e documentos em geral — Lei nº 9.610/1998 (Direitos Autorais);</p></li>
<li><p>(b) Programas de computador — Lei nº 9.609/1998, observadas as especificidades do art. 2º, §1º, quanto aos direitos morais;</p></li>
<li><p>(c) Invenções, modelos de utilidade, desenhos industriais e marcas — Lei nº 9.279/1996, com avaliação de patenteabilidade antecedendo qualquer divulgação pública (art. 11 da Lei nº 9.279/1996);</p></li>
<li><p>(d) Registros internacionais equivalentes observam os tratados vigentes no Brasil.</p></li>
</ul>
<p><strong>2.6 Publicação Externa com Exigência de Exclusividade.</strong> Caso o VOLUNTÁRIO pretenda submeter obra produzida no âmbito do Programa a periódico científico, editora ou evento que exija, como condição de aceitação, cessão exclusiva de direitos patrimoniais ou ineditismo da obra, aplicam-se os seguintes procedimentos:</p>
<p><strong>2.6.1</strong> O VOLUNTÁRIO notificará o Gerente de Projeto com antecedência mínima de 15 (quinze) dias, indicando: (a) a obra objeto da publicação; (b) o periódico, editora ou evento de destino; (c) a política editorial exigida (exclusividade, cessão, ineditismo); (d) o prazo estimado de embargo editorial.</p>
<p><strong>2.6.2</strong> Mediante a notificação, a licença concedida ao Núcleo sobre aquela obra específica entra em regime de suspensão temporária (standby) pelo prazo necessário ao cumprimento das exigências editoriais, não excedendo 24 (vinte e quatro) meses renováveis por igual período mediante nova notificação.</p>
<p><strong>2.6.3</strong> Durante o período de suspensão, o Núcleo compromete-se a não publicar, distribuir ou criar obras derivadas daquela obra específica, preservando-se, contudo, os direitos do Núcleo sobre obras anteriores, simultâneas ou derivadas já em circulação.</p>
<p><strong>2.6.4</strong> Findo o período de exclusividade editorial ou cessando a exigência que a motivou, a licença ao Núcleo é automaticamente restabelecida em seus termos originais, devendo o VOLUNTÁRIO comunicar o fim do embargo ao Gerente de Projeto.</p>
<p><strong>2.6.5</strong> O VOLUNTÁRIO obriga-se a incluir, na publicação externa, nota de agradecimento ao Núcleo de Estudos e Pesquisa em IA &amp; GP como origem institucional da pesquisa, na forma mais ampla permitida pela política editorial de destino, ou, caso vedada pelo publicador, a registrar a vinculação ao Núcleo na página de perfil do autor no próprio publicador ou em repositório pessoal de acesso público equivalente.</p>
<p><strong>2.6.6</strong> A suspensão temporária não se aplica a publicações sob Track A (Aberto) da Política de Publicação, que seguem fluxo de notificação simples sem necessidade de standby.</p>
<p><strong>2.6.7 Autorização para cessão exclusiva ao publicador.</strong> Durante o período de suspensão temporária previsto nas subcláusulas anteriores, o VOLUNTÁRIO fica autorizado a outorgar ao publicador externo os direitos de exclusividade exigidos como condição editorial, incluindo cessão exclusiva de direitos patrimoniais sobre a obra específica pelo prazo do embargo. A licença do Núcleo, embora não extinta, não será exercida nesse período (subcláusula 2.6.3), de modo que a exclusividade concedida ao publicador seja factualmente operante.</p>
<p><strong>2.6.8 Restabelecimento antecipado.</strong> Em caso de rejeição da submissão pelo publicador ou desistência do VOLUNTÁRIO antes do término do prazo de embargo, o VOLUNTÁRIO comunicará imediatamente ao Gerente de Projeto, e a licença ao Núcleo será automaticamente restabelecida na data dessa comunicação, sem aguardar o término do prazo original de suspensão.</p>
<p><strong>2.6.9 Incompatibilidade entre licenças abertas.</strong> O mecanismo desta Cláusula aplica-se também às hipóteses de incompatibilidade de licença aberta entre o Track B (CC-BY-SA 4.0) e a licença exigida pelo publicador externo (CC-BY 4.0 ou equivalente não-SA), mediante autorização específica nos termos da Seção 5 da Política de Publicação e Propriedade Intelectual (Re-licenciamento para periódicos).</p>
<p>Art. 4 — Lei Aplicável e Jurisdição</p>
<p>Este Adendo e o Termo Original ao qual se vincula são regidos pela legislação brasileira, em especial pelas Leis nº 9.608/1998, nº 9.609/1998, nº 9.610/1998, nº 9.279/1996 e nº 13.709/2018, bem como pelo Código de Ética do Project Management Institute e pelos tratados internacionais de propriedade intelectual vigentes no Brasil (Convenção de Berna — Decreto nº 75.699/1975; Acordo TRIPS — Decreto nº 1.355/1994).</p>
<p><strong>§ 1º</strong> Para VOLUNTÁRIOS residentes fora do Brasil, aplica-se a legislação brasileira, observado o princípio do tratamento nacional da Convenção de Berna (Art. 5.1), preservando-se os direitos morais do VOLUNTÁRIO no padrão mais protetivo entre a legislação brasileira e a legislação da jurisdição de sua residência.</p>
<p><strong>§ 2º</strong> Controvérsias decorrentes deste Adendo ou do Termo Original serão resolvidas prioritariamente por conciliação interna mediada pelo Gerente de Projeto e pelos presidentes dos capítulos envolvidos. Persistindo o conflito, o foro de eleição é a Comarca de Goiânia/GO, ressalvado que, em casos envolvendo VOLUNTÁRIOS residentes no exterior ou entidades internacionais, as partes poderão optar, em instrumento específico, por: (i) arbitragem conforme regras da Câmara de Comércio Internacional (ICC) ou de câmara arbitral brasileira; (ii) submissão ao PMI Ethics Review Committee, quando a matéria envolver conduta ética profissional; ou (iii) foro da Comarca de Goiânia/GO com opção por processo em língua inglesa ou portuguesa, nos termos da Seção 1.7 da Política de Publicação e Propriedade Intelectual do Núcleo.</p>
<p>Art. 5 — Retificação da Cláusula 4 do Termo Original</p>
<p>A Cláusula 4 do Termo Original, que dispõe que "o VOLUNTÁRIO não poderá emitir conceitos, falar ou utilizar o nome ou documentos do {chapterName} sem a prévia autorização do {chapterName}", passa a vigorar com o seguinte parágrafo único:</p>
<p><strong>Parágrafo único.</strong> Não constitui violação desta cláusula:</p>
<ul>
<li><p>(a) A inclusão de atribuição institucional ao Núcleo de Estudos e Pesquisa em IA &amp; GP e ao capítulo de origem do VOLUNTÁRIO em publicações enquadradas nas Tracks A, B ou C da Política de Publicação, observados os respectivos fluxos de notificação ou aprovação previstos na referida Política;</p></li>
<li><p>(b) A menção institucional ao capítulo em contextos acadêmicos, científicos ou profissionais relacionados às atividades voluntárias do VOLUNTÁRIO no âmbito do Programa, desde que consistente com o Código de Ética do Project Management Institute;</p></li>
<li><p>(c) As demais hipóteses expressamente previstas na Política de Publicação e Propriedade Intelectual vigente.</p></li>
</ul>
<p>Art. 5-A — Demais Cláusulas</p>
<p>As demais cláusulas do Termo Original permanecem inalteradas e em pleno vigor.</p>
<p>Art. 6 — Vigência</p>
<p>Este Adendo entra em vigor na data de sua assinatura e permanece vigente enquanto durar o Termo Original ao qual está vinculado.</p>
<p>Art. 7 — Assinaturas</p>
<p>Assinado pelo VOLUNTÁRIO e pelo representante legal do Capítulo de origem (presidente ou procurador), em formato digital via plataforma nucleoia.vitormr.dev ou DocuSign.</p>
<p>___________________________________________</p>
<p>[Nome do Voluntário]
PMI ID: [XXXXXX] | Capítulo: [PMI-XX]</p>
<p>___________________________________________</p>
<p>[Nome do Presidente]
Presidente | [Nome do Capítulo] | CNPJ: [XX.XXX.XXX/XXXX-XX]</p>
<p><em><strong>Termo Original:</strong> Termo de Compromisso de Voluntariado — Ciclo [ANO], Código de Verificação [TERM-XXXX-XXXXXX]</em></p>
<p><em><strong>Change Request:</strong> CR-050 — Revisão da Cláusula de Propriedade Intelectual e Adoção de Política de Publicação</em></p>
<p><em><strong>Política de referência:</strong> Política de Publicação e Propriedade Intelectual do Núcleo de IA &amp; GP (v2.1)</em></p>
<p><em><strong>Termo revisado de referência:</strong> Termo de Voluntariado R3-C3-IP v2.1</em></p>
<p><em>Draft v2.1 | CR-050 | Núcleo de Estudos e Pesquisa em IA &amp; GP</em></p>
$html_v21$,
   '880f736c-3e76-4df4-9375-33575c190305', now(), now(), '880f736c-3e76-4df4-9375-33575c190305', now(), '880f736c-3e76-4df4-9375-33575c190305',
   'Seed Phase IP-1 v2.1 pos-auditoria juridica 19/Abr/2026 (para 52 voluntarios ativos)');

INSERT INTO public.approval_chains
  (document_id, version_id, status, gates, opened_at, opened_by, notes)
SELECT 'd2b7782c-dc1a-44d4-a5d5-16248117a895', id, 'review',
  '[{"kind":"curator","threshold":1,"order":1},{"kind":"leader","threshold":1,"order":2},{"kind":"president_go","threshold":1,"order":3},{"kind":"president_others","threshold":4,"order":4},{"kind":"member_ratification","threshold":"all","order":5}]'::jsonb,
  now(), '880f736c-3e76-4df4-9375-33575c190305', 'Chain aberto pos-auditoria juridica 19/Abr/2026'
FROM public.document_versions
WHERE document_id='d2b7782c-dc1a-44d4-a5d5-16248117a895' AND version_label='v2.1'
ON CONFLICT (document_id, version_id) DO NOTHING;
