INSERT INTO public.governance_documents (id, doc_type, title, version, status, description, created_at, updated_at)
VALUES ('9a0e5000-0000-0000-0000-000000000000','executive_summary',
  'Sumario Executivo CR-050 v2.1 — Propriedade Intelectual',
  'v2.1','active',
  'Documento de contexto do pacote CR-050 versao 2.1 (19/Abr/2026 pos-auditoria juridica). Nao-ratificavel — apenas orientador para presidentes e membros.',
  now(), now())
ON CONFLICT (id) DO UPDATE SET version='v2.1', status='active', updated_at=now();

INSERT INTO public.document_versions
  (document_id, version_number, version_label, content_html,
   authored_by, authored_at, published_at, published_by, locked_at, locked_by, notes)
VALUES
  ('9a0e5000-0000-0000-0000-000000000000', 1, 'v2.1',
   $html_v21$
<p><strong>CR-050 — Sumário Executivo da Revisão</strong></p>
<p>Propriedade Intelectual no Núcleo de IA &amp; GP</p>
<p><em>Preparado por Vitor Rodovalho · 16 de Abril de 2026</em></p>
<p>Apoio à reunião Ivan Lourenço × Vitor Rodovalho · 16h</p>
<p><strong>TL;DR —</strong> O pacote CR-050 foi revisado em profundidade após contribuição técnica do Roberto Macêdo (Curador PMI-CE) e análise sistêmica dos efeitos cruzados entre as decisões. Dez pontos de melhoria foram identificados e todos endereçados. Quatro documentos revisados estão prontos para validação jurídica (termo, adendo retificativo, adendo de cooperação, política). Todas as referências legais foram validadas nas fontes oficiais. O pacote agora cobre escopo internacional (relevante para o Fabricio e para o programa AIPM Ambassadors). Inclui mecanismo de opt-out para publicação em periódicos exclusivos. Define governança de registro, custeio e royalties. Corrige enquadramento jurídico de software. Timeline CBGPL preservada.</p>
<p>1. Contribuição do Roberto Macêdo (PMI-CE)</p>
<p>Revisão feita durante a manhã de 16/Abr. Roberto identificou dois pontos diretos e levantou dois pontos de governança. Todos os quatro foram incorporados ao pacote revisado.</p>
<p>Ponto 1 — Conflito com periódicos exclusivos</p>
<p>Periódicos de peso (Elsevier IJPM, RAUSP, Nature, etc.) exigem ineditismo e cessão exclusiva. A licença "irrevogável" do draft v1 conflitaria com essa exigência. Pesquisadores seriam forçados a escolher entre contribuir com o Núcleo ou publicar em canal top — exatamente o que a política deve evitar.</p>
<p><strong>Solução incorporada:</strong> Cláusula 2.6 do termo (v2) cria mecanismo de suspensão temporária da licença por obra específica, com prazo de 24 meses renováveis e reativação automática ao fim do embargo. O Núcleo preserva direitos sobre obras anteriores, simultâneas e derivadas. Voluntário inclui nota de agradecimento ao Núcleo ou, se vedado, registra na página de perfil de autor.</p>
<p>Ponto 2 — Software não é propriedade industrial</p>
<p>A Cláusula 2.5 do draft v1 invocava a Lei 9.279 (propriedade industrial) para tratar software e frameworks. Erro técnico: software é direito autoral sob a Lei 9.609; frameworks e documentos são direito autoral sob a Lei 9.610. A Lei 9.279 cobre só patentes, marcas, desenho industrial.</p>
<p><strong>Solução incorporada:</strong> Cláusula 2.5 reescrita em quatro subcláusulas — cada tipo de obra com o enquadramento legal correto (9.610 para obras gerais, 9.609 para software, 9.279 para propriedade industrial, tratados internacionais para registros em outras jurisdições).</p>
<p>Ponto 3 — Governança de registro e custeio</p>
<p>Roberto perguntou: quem analisa viabilidade? Quem paga INPI, Biblioteca Nacional, honorários de agente de PI? Sem resposta clara, a política vira letra morta.</p>
<p><strong>Solução incorporada:</strong> Seção 4 nova da Política cria fluxo Curadoria → parecer técnico → GP + Presidente PMI-GO → notificação aos demais presidentes (15 dias). Custos arcados pelo orçamento anual do Núcleo administrado pelo PMI-GO. Desconto de 50% do INPI para entidades sem fins lucrativos (Portaria INPI/PR nº 10/2025) torna os custos administráveis. Plano B para restrição orçamentária: patrocínio, cotitularidade, publicação defensiva, renúncia ao registro mantendo proteção automática.</p>
<p>Ponto 4 — Uso pós-registro e política de royalties</p>
<p>Marcas sem uso caducam em 5 anos (Lei 9.279 Art. 143). Patentes sem exploração podem sofrer licença compulsória (Art. 68). Se o Núcleo registra algo, precisa ter política de uso explícita. E royalties, se houver, precisam de destino definido.</p>
<p><strong>Solução incorporada:</strong> Regime padrão = uso universal gratuito com atribuição, declarado no ato do registro. Finalidade: defensiva e de reconhecimento formal, não reserva comercial. Exploração com royalties é exceção, requer aprovação específica. Royalties, quando houver, têm diretrizes mínimas: parcela aos autores, parcela ao fundo do Núcleo, distribuição equitativa entre capítulos, vedação a fins alheios. Controle anual de uso pela Curadoria para prevenir caducidade.</p>
<p>2. Contribuições Adicionais Identificadas na Análise</p>
<p>Seis pontos adicionais surgiram da análise sistêmica — efeitos cruzados que não apareciam no exame ponto-a-ponto.</p>
<p>5. "Irrevogável" sujeita a prazo de 5 anos</p>
<p>A Lei 9.610 Art. 51 limita cessão de obras futuras a 5 anos — jurisprudência aplica analogia a licenças sem prazo. "Licença irrevogável e mundial" do draft v1, aplicada a obras futuras, corre risco de redução judicial.</p>
<p><strong>Solução:</strong> Licença reestruturada como "licença por obra específica", outorgada no momento da entrega de cada obra. Deixa de ser cessão de obras futuras em bloco. Vigora pelo prazo de proteção legal da obra (70 anos pós-morte do autor, no Brasil), sem conflito com o Art. 51.</p>
<p>6. Ineditismo operacional</p>
<p>Publisher pode questionar: apresentar em reunião interna do Núcleo conta como "publicação prévia"? E em webinar público? E em CBGPL? Sem definição, voluntário assina submissão e depois descobre que violou ineditismo.</p>
<p><strong>Solução:</strong> Seção 6 nova da Política define operacionalmente. Webinars internos, rascunhos, cards de plataforma, relatórios internos = não contam. Blog público, congressos com gravação, preprints públicos = contam.</p>
<p>7. Cláusula 4 vs. Track A</p>
<p>Cláusula 4 do termo vigente exige "prévia autorização" para usar o nome do capítulo. Track A da política prevê apenas "notificação". Conflito direto: voluntário publica em Track A mas tecnicamente viola Cláusula 4.</p>
<p><strong>Solução:</strong> Parágrafo único novo na Cláusula 4 do termo ressalva três hipóteses: atribuição institucional em publicações Tracks A/B/C, menção em contextos acadêmicos, demais hipóteses da Política.</p>
<p>8. Encarregado LGPD, não "DPO"</p>
<p>LGPD Art. 5º VIII usa o termo "encarregado" para o que o GDPR chama de DPO. Documento jurídico brasileiro deve usar o termo legal correto. E o Núcleo não precisa de encarregado próprio — usa o do PMI-GO (capítulo sede).</p>
<p><strong>Solução:</strong> Seção 2 nova da Política formaliza. Track C revisado para "Encarregado pela Proteção de Dados Pessoais (DPO) do PMI-GO". Política de privacidade do PMI-GO é referência operacional, com prevalência da disposição mais protetiva em caso de ambiguidade.</p>
<p>9. Jurisdições estrangeiras</p>
<p>Você mora em Leesburg/VA. Fabricio pode estar em qualquer lugar. Pesquisadores brasileiros apresentam em LIM Summit (Peru). PMI é americano. AIPM Ambassadors é programa internacional. A política não pode ser só brasileira.</p>
<p><strong>Solução:</strong> Seção 1 nova da Política estabelece lei aplicável brasileira + tratamento nacional da Convenção de Berna + proteção de direitos morais no padrão mais protetivo entre Brasil e jurisdição local + foro Goiânia-GO como padrão, com protocolo reforçado opcional (ICC, PMI Ethics, foro bilíngue) para casos internacionais.</p>
<p>10. Acordos internacionais futuros</p>
<p>O programa AIPM Ambassadors (Vargas + Nieto-Rodriguez) vai demandar acordo institucional PMI-GO × entidade internacional. Sem princípio-âncora na política, cada acordo vira negociação do zero.</p>
<p><strong>Solução:</strong> Seção 10 nova da Política estabelece que acordos internacionais herdam a Política como baseline. Divergências tratadas por adendo específico. Negociação pelos representantes designados (você e Fabricio no caso Ambassadors) com aprovação prévia do presidente PMI-GO e notificação aos 4 demais presidentes (15 dias).</p>
<p>3. Correção Crítica de Referência Jurídica</p>
<p>O draft v1 da política citava <strong>"Art. 49 §4º"</strong> da Lei 9.610 como base para o prazo de 5 anos de cessão de obras futuras. Essa referência <strong>não existe</strong> nessa configuração no texto legal. O dispositivo correto é o <strong>Art. 51</strong> ("A cessão dos direitos de autor sobre obras futuras abrangerá, no máximo, o período de cinco anos"). Se o pacote tivesse ido ao advogado com a referência errada, teria prejudicado a credibilidade de todo o trabalho. Corrigido no draft v2.</p>
<p>4. Instrumentos do Pacote CR-050 (v2)</p>
<table>
<thead>
<tr class="header">
<th><strong>#</strong></th>
<th><strong>Documento</strong></th>
<th><strong>Principais alterações</strong></th>
<th><strong>Próximo passo</strong></th>
</tr>
</thead>
<tbody>
<tr class="odd">
<td>1</td>
<td>Política de Publicação e Propriedade Intelectual (v2.0)</td>
<td>12 seções — escopo internacional, LGPD, governança de registro, 3 tracks, ineditismo, royalties, acordos internacionais</td>
<td>Revisão jurídica → aprovação via CR-050 no manual</td>
</tr>
<tr class="even">
<td>2</td>
<td>Termo de Voluntariado R3-C3-IP v2.0</td>
<td>Cláusula 2 integralmente substituída (2.1–2.6); Cláusula 4 com parágrafo de ressalvas; Cláusula 9 atualizada (encarregado); Cláusula 13 nova (lei aplicável e jurisdição)</td>
<td>Revisão jurídica → aprovação 5 presidentes → uso no Ciclo 4</td>
</tr>
<tr class="odd">
<td>3</td>
<td>Adendo Retificativo do Termo v2.0</td>
<td>Para os 52 voluntários que já assinaram R3-C3. Referencia termo original, declara prevalência, retifica Cláusula 2 com nova redação. Art. 4 incorpora escopo internacional.</td>
<td>Revisão jurídica → assinatura individual pelos voluntários ativos</td>
</tr>
<tr class="even">
<td>4</td>
<td>Adendo de IP aos Acordos de Cooperação Bilateral v2.0</td>
<td>9 artigos (originalmente 7) — obras coletivas, uso irrevogável, saída de capítulo, direitos morais, crédito, registro e titularidade, escopo internacional, vigência, revisão</td>
<td>Circular para 5 presidentes (Jessica/CE, Matheus/DF, Felipe/MG, Márcio/RS) + Ivan/GO</td>
</tr>
</tbody>
</table>
<p>5. Validação Jurídica das Referências</p>
<p>Todas as leis, decretos e portarias citados nos documentos foram verificados em fontes oficiais (Planalto, LexML, gov.br/inpi, gov.br/bn). Segue resumo:</p>
<table>
<thead>
<tr class="header">
<th><strong>Referência</strong></th>
<th><strong>Data</strong></th>
<th><strong>Conteúdo relevante</strong></th>
</tr>
</thead>
<tbody>
<tr class="odd">
<td>Lei nº 9.608</td>
<td>18/02/1998</td>
<td>Serviço Voluntário (redação atualizada pela Lei 13.297/2016)</td>
</tr>
<tr class="even">
<td>Lei nº 9.609</td>
<td>19/02/1998</td>
<td>Proteção de software (direitos morais limitados no art. 2º §1º)</td>
</tr>
<tr class="odd">
<td>Lei nº 9.610</td>
<td>19/02/1998</td>
<td>Direitos Autorais. Art. 24-27 (morais); Art. 51 (5 anos obras futuras)</td>
</tr>
<tr class="even">
<td>Lei nº 9.279</td>
<td>14/05/1996</td>
<td>Propriedade Industrial. Art. 11 (novidade); Art. 143 (caducidade marca)</td>
</tr>
<tr class="odd">
<td>Lei nº 13.709</td>
<td>14/08/2018</td>
<td>LGPD. Art. 5º VIII define "encarregado" (termo legal brasileiro)</td>
</tr>
<tr class="even">
<td>Decreto nº 75.699</td>
<td>06/05/1975</td>
<td>Promulga Convenção de Berna. Tratamento nacional (Art. 5.1)</td>
</tr>
<tr class="odd">
<td>Decreto nº 1.355</td>
<td>30/12/1994</td>
<td>Promulga Acordo TRIPS (OMC)</td>
</tr>
<tr class="even">
<td>Portaria INPI/PR nº 10/2025</td>
<td>Vigente 07/08/2025</td>
<td>Desconto 50% para entidades sem fins lucrativos</td>
</tr>
<tr class="odd">
<td>Instrução Normativa EDA/FBN nº 02/2024</td>
<td>Vigente 01/01/2025</td>
<td>Registro autoral Biblioteca Nacional (R$ 40 PF / R$ 80 PJ)</td>
</tr>
</tbody>
</table>
<p>6. Roadmap de Ratificação (Atualizado)</p>
<p>A ratificação do pacote CR-050 segue fluxo on-platform (plataforma <code>nucleoia.vitormr.dev</code>) com rastreabilidade legal, assinaturas digitais e gates de aprovação sequenciais. Sem timeline hard-coded: cada etapa avança conforme a anterior se conclui.</p>
<ul>
<li><p><strong>Etapa 1 — Auditoria jurídica pré-ratificação (concluída 19/Abr/2026):</strong> Revisão completa dos 5 documentos v2. Resultado: APROVADO COM RESSALVAS — 6 ajustes P1 + 7 ajustes P2 incorporados no v2.1. Parecer em <code>docs/council/2026-04-19-legal-counsel-ip-review.md</code>.</p></li>
<li><p><strong>Etapa 2 — Validação jurídica por advogado humano (pendente):</strong> Ivan Lourenço (PMI-GO) indica advogado licenciado para revisar o v2.1. Foco: (i) validação dos ajustes P1-A a P1-F; (ii) consulta especializada para Red Flag RF-2 (tributação de royalties) e RF-3 (GDPR para voluntários UE).</p></li>
<li><p><strong>Etapa 3 — Aprovação política pelos 5 presidentes (paralelo):</strong> Circulação do v2.1 aos presidentes Ivan/GO, Jessica/CE, Matheus/DF, Felipe/MG, Márcio/RS via plataforma. Comentários e questionamentos registrados em thread por cláusula. Aprovação sequencial (curador → líder → president_go → 4 demais presidentes) com silêncio positivo para marcas/patentes.</p></li>
<li><p><strong>Etapa 4 — Ratificação pelos 52 voluntários ativos:</strong> Após aprovação política, disparo do Adendo Retificativo para os 52 voluntários. Cadência de lembretes D-14/-7/-3/-1. Magic-link para external signers (se houver).</p></li>
<li><p><strong>Etapa 5 — Vigência plena:</strong> Entrada em vigor do Termo R3-C3-IP v2.1 para o Ciclo 4 (novos voluntários) e do Adendo de Cooperação v2.1 integrado aos 4 acordos bilaterais existentes.</p></li>
<li><p><strong>Eventos públicos paralelos:</strong> CBGPL (28/Abr/2026) é momento de comunicação institucional, não gate da ratificação. LIM Summit, PMI Global Congress e outros são oportunidades de apresentação, não condicionantes da formalização.</p></li>
</ul>
<p>7. Pontos de Decisão Específicos para a Reunião</p>
<p>Sugestão de agenda focada — 30 min:</p>
<ul>
<li><p><strong>(1) Validação da direção geral</strong> — 5 min. Confirmar que os 10 pontos endereçados fazem sentido como pacote. Não precisa entrar em texto específico.</p></li>
<li><p><strong>(2) Escopo internacional</strong> — 5 min. Decisão de tratar o programa como transnacional agora (não depois). Pergunta: Ivan vê algum obstáculo estatutário do PMI-GO?</p></li>
<li><p><strong>(3) Registro e custeio</strong> — 5 min. Decisão: orçamento anual do Núcleo para PI administrado pelo PMI-GO. Pergunta: qual o teto sugerido para o primeiro ciclo?</p></li>
<li><p><strong>(4) Política de royalties</strong> — 5 min. Decisão de deixar aberto agora e resolver caso a caso. Pergunta: Ivan concorda ou quer bounds mínimos?</p></li>
<li><p><strong>(5) Encaminhamento jurídico</strong> — 5 min. Ivan indica advogado. Prazo acordado: até 25/Abr para ter pacote validado antes do CBGPL.</p></li>
<li><p><strong>(6) Comunicação aos 4 presidentes</strong> — 5 min. Alinhar quem manda, quando, com que formato. Sugestão: circular após validação jurídica, não antes.</p></li>
</ul>
<p><em>CR-050 v2.1 | Núcleo de Estudos e Pesquisa em IA &amp; GP | nucleoia.vitormr.dev</em></p>
<p><em>Documentos do pacote (v2.1): 01_Politica_Publicacao_IP_v2.1 · 02_Termo_Voluntariado_R3-C3-IP_v2.1 · 03_Adendo_Retificativo_Termo_v2.1 · 04_Adendo_IP_Acordos_Cooperacao_v2.1</em></p>
<p><em>Parecer de auditoria jurídica pré-ratificação: <code>docs/council/2026-04-19-legal-counsel-ip-review.md</code></em></p>
$html_v21$,
   '880f736c-3e76-4df4-9375-33575c190305', now(), now(), '880f736c-3e76-4df4-9375-33575c190305', now(), '880f736c-3e76-4df4-9375-33575c190305',
   'Seed Phase IP-1 v2.1 pos-auditoria juridica 19/Abr/2026 (CR-050)');
