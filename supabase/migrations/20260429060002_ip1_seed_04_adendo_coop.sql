UPDATE public.governance_documents SET version='v2.1', status='under_review', updated_at=now()
WHERE id='41de16e2-4f2e-4eac-b63e-8f0b45b22629';

INSERT INTO public.document_versions
  (document_id, version_number, version_label, content_html,
   authored_by, authored_at, published_at, published_by, locked_at, locked_by, notes)
VALUES
  ('41de16e2-4f2e-4eac-b63e-8f0b45b22629', 1, 'v2.1',
   $html_v21$
<p><strong>Adendo de Propriedade Intelectual aos Acordos de Cooperação Bilateral</strong></p>
<p>Núcleo de Estudos e Pesquisa em Inteligência Artificial e Gestão de Projetos</p>
<p><em>DRAFT v2.1 — Pendente aprovação dos 5 presidentes | CR-050</em></p>
<p>Aplica-se aos 4 acordos bilaterais (GO↔︎CE, GO↔︎DF, GO↔︎MG, GO↔︎RS)</p>
<p><strong>Nota v2.0 → v2.1 (19/Abr/2026):</strong> Incorporado ao Art. 6 parágrafo único sobre aprovação tácita por silêncio para depósito de marcas e patentes (consistente com §1 da Cláusula 4.2.1 da Política v2.1), dando segurança jurídica à notificação de 15 dias conforme art. 111 do Código Civil.</p>
<p>O presente Adendo integra o Acordo de Cooperação bilateral celebrado entre os Capítulos signatários e tem por objetivo estabelecer regras claras de propriedade intelectual para obras produzidas no âmbito do Núcleo de Estudos e Pesquisa em Inteligência Artificial e Gestão de Projetos, observados a legislação brasileira, os tratados internacionais vigentes no Brasil e o Código de Ética do Project Management Institute.</p>
<p>Art. 1 — Obras Coletivas</p>
<p>Obras intelectuais produzidas por voluntários de múltiplos capítulos no âmbito do Programa são consideradas obras coletivas, nos termos do art. 5º, VIII, alínea "h", da Lei nº 9.610/1998. Os direitos patrimoniais das obras coletivas pertencem ao Núcleo como programa interinstitucional, garantido o crédito individual aos autores conforme a Política de Publicação e Propriedade Intelectual.</p>
<p>Art. 2 — Direito de Uso Irrevogável</p>
<p>Cada capítulo signatário tem direito irrevogável de uso das obras produzidas durante sua participação no Programa, incluindo reprodução, distribuição e criação de derivados para fins educacionais e científicos, conforme licenciamento definido na Política de Publicação e Propriedade Intelectual (Track A: CC-BY 4.0; Track B: CC-BY-SA 4.0 ou MIT/Apache-2.0; Track C: proprietário, com acesso definido no ato do registro).</p>
<p>Art. 3 — Saída de Capítulo</p>
<p>Em caso de saída de capítulo (aviso prévio de 30 dias conforme Acordo de Cooperação), o capítulo retém direito de uso perpétuo das obras criadas durante sua participação, sem exclusividade. Novas obras produzidas após a saída não geram direito para o capítulo que deixou o Programa.</p>
<p>Art. 4 — Direitos Morais</p>
<p>Os direitos morais dos autores individuais (paternidade, crédito, integridade) são inalienáveis e irrenunciáveis, conforme Lei nº 9.610/1998, Art. 24 a 27. Nenhuma disposição deste Adendo ou dos Acordos de Cooperação pode restringir esses direitos. No caso de programa de computador, aplica-se a extensão específica do art. 2º, §1º, da Lei nº 9.609/1998. Para autores residentes em jurisdições estrangeiras, observa-se o padrão mais protetivo entre a legislação brasileira e a legislação local, nos termos da Convenção de Berna.</p>
<p>Art. 5 — Regras de Crédito</p>
<p>Todo output publicado deve incluir:</p>
<ul>
<li><p>(a) Nomes dos autores individuais na ordem de contribuição substantiva;</p></li>
<li><p>(b) Afiliação institucional no formato: Núcleo de Estudos e Pesquisa em IA &amp; GP — PMI [Capítulos de origem];</p></li>
<li><p>(c) Líder de tribo como coautor se supervisionou o trabalho e contribuiu intelectualmente.</p></li>
</ul>
<p>Art. 6 — Registro e Titularidade Formal</p>
<p>Em caso de registro formal de propriedade intelectual (autoral junto à Fundação Biblioteca Nacional, de software ou industrial junto ao INPI, ou equivalentes internacionais), o depósito é realizado em nome do PMI Brasil–Goiás Chapter (PMI-GO), como capítulo sede, nos termos da Seção 4 da Política de Publicação e Propriedade Intelectual, preservados os direitos morais dos autores individuais, o direito de uso irrevogável dos demais capítulos signatários (Art. 2) e a notificação prévia aos demais presidentes signatários com antecedência mínima de 15 (quinze) dias do ato de depósito.</p>
<p><strong>Parágrafo único — Aprovação tácita por silêncio para marcas e patentes.</strong> Para depósito de marcas e patentes — ativos de maior impacto sobre a identidade institucional do Programa — a ausência de manifestação contrária por escrito de qualquer dos presidentes signatários no prazo de 15 (quinze) dias contados do recebimento da notificação importa aprovação tácita, nos termos do art. 111 do Código Civil. Em caso de manifestação contrária, o depósito será suspenso por até 30 (trinta) dias para deliberação conjunta entre os presidentes signatários. Para registros autorais junto à EDA/FBN, mantém-se a notificação simples sem efeito de aprovação tácita.</p>
<p>Art. 7 — Escopo Internacional e Acordos com Entidades Estrangeiras</p>
<p>Reconhecida a natureza transnacional do Programa — decorrente da filiação ao Project Management Institute, entidade global, e da participação de voluntários residentes em jurisdições estrangeiras — os Capítulos signatários concordam que futuros acordos de cooperação ou parceria entre o Núcleo (representado pelo PMI-GO) e entidades internacionais herdarão a Política de Publicação e Propriedade Intelectual como baseline, sendo eventuais divergências tratadas por adendo específico, preservado o tratamento igualitário entre capítulos signatários.</p>
<p>Art. 8 — Vigência</p>
<p>Este Adendo entra em vigor na data de sua assinatura pelos representantes dos capítulos e permanece vigente enquanto durar o Acordo de Cooperação ao qual está vinculado.</p>
<p>Art. 9 — Revisão</p>
<p>Este Adendo será revisado anualmente ou quando houver mudança significativa na composição de capítulos, na legislação aplicável ou no escopo de acordos internacionais, seguindo o processo de Change Request do Manual Operacional.</p>
<p>___________________________________________</p>
<p><strong>Ivan Lourenço</strong>
Presidente | PMI Brasil–Goiás Chapter (PMI-GO)</p>
<p>___________________________________________</p>
<p><strong>[Presidente Capítulo Parceiro]</strong>
Presidente | PMI [XX]</p>
<p><em>Draft v2.1 | Política de referência: Política de Publicação e Propriedade Intelectual do Núcleo de IA &amp; GP (v2.1) | CR-050</em></p>
$html_v21$,
   '880f736c-3e76-4df4-9375-33575c190305', now(), now(), '880f736c-3e76-4df4-9375-33575c190305', now(), '880f736c-3e76-4df4-9375-33575c190305',
   'Seed Phase IP-1 v2.1 pos-auditoria juridica 19/Abr/2026 (4 acordos bilaterais PMI-GO x CE/DF/MG/RS)');

INSERT INTO public.approval_chains
  (document_id, version_id, status, gates, opened_at, opened_by, notes)
SELECT '41de16e2-4f2e-4eac-b63e-8f0b45b22629', id, 'review',
  '[{"kind":"curator","threshold":1,"order":1},{"kind":"president_go","threshold":1,"order":2},{"kind":"president_others","threshold":4,"order":3}]'::jsonb,
  now(), '880f736c-3e76-4df4-9375-33575c190305', 'Chain aberto pos-auditoria juridica 19/Abr/2026'
FROM public.document_versions
WHERE document_id='41de16e2-4f2e-4eac-b63e-8f0b45b22629' AND version_label='v2.1'
ON CONFLICT (document_id, version_id) DO NOTHING;
