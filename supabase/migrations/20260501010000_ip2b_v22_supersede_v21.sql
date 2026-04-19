-- ============================================================================
-- Migration: Phase IP-2b — v2.1 → v2.2 supersede (atomic, idempotent)
-- Scope: withdraw 4 v2.1 chains + insert 5 v2.2 document_versions (locked) +
--        open 4 new v2.2 chains in 'review' + update governance_documents.version.
-- ADR-0016 D4 (imutabilidade via new row) + D5 (audit trail).
-- Trigger trg_sync_current_version_on_publish auto-updates current_version_id
-- when locked_at is set.
-- Idempotency: all steps guarded — safe for replay on fresh DBs or re-runs.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- Step 1 — Withdraw v2.1 approval_chains (guard: only if still active).
-- ---------------------------------------------------------------------------
UPDATE public.approval_chains
SET status='withdrawn', closed_at=now(), closed_by=NULL,
    notes=coalesce(notes || E'\n---\n','') || '[withdrawn 2026-04-20 p32] Superseded by v2.2.',
    updated_at=now()
WHERE id IN (
  'acfeece1-cb1b-466d-84ba-d08fda2f7fa0',  -- Política v2.1
  '2d4015cb-bab5-4a30-910c-01f9da592cf5',  -- Termo v2.1
  '24eb9b50-ddc6-4409-a578-3753f4a52240',  -- Adendo Retif v2.1
  '22fbf5a8-593b-485e-b0f7-f94e70d224e1'   -- Adendo Coop v2.1
)
AND status IN ('draft', 'review', 'approved');

-- Audit log (guard: INSERT only if not already present for same chain_id).
INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, metadata)
SELECT NULL, 'approval_chain.advanced_to_withdrawn', 'approval_chain', ac.id,
       jsonb_build_object('document_id', ac.document_id, 'from_status', 'review',
                          'to_status', 'withdrawn', 'reason', 'superseded_by_v2.2')
FROM public.approval_chains ac
WHERE ac.id IN (
  'acfeece1-cb1b-466d-84ba-d08fda2f7fa0',
  '2d4015cb-bab5-4a30-910c-01f9da592cf5',
  '24eb9b50-ddc6-4409-a578-3753f4a52240',
  '22fbf5a8-593b-485e-b0f7-f94e70d224e1'
)
AND NOT EXISTS (
  SELECT 1 FROM public.admin_audit_log al
  WHERE al.action = 'approval_chain.advanced_to_withdrawn'
    AND al.target_id = ac.id
    AND al.metadata->>'reason' = 'superseded_by_v2.2'
);

-- ---------------------------------------------------------------------------
-- Step 2 — Update governance_documents.version label (idempotent: same value).
-- ---------------------------------------------------------------------------
UPDATE public.governance_documents SET version='v2.2', updated_at=now()
WHERE id IN (
  'cfb15185-2800-4441-9ff1-f36096e83aa8',
  'd2b7782c-dc1a-44d4-a5d5-16248117a895',
  '41de16e2-4f2e-4eac-b63e-8f0b45b22629',
  '9a0e5000-0000-0000-0000-000000000000'
) AND version IS DISTINCT FROM 'v2.2';

UPDATE public.governance_documents SET version='R3-C3-IP-v2.2', updated_at=now()
WHERE id='280c2c56-e0e3-4b10-be68-6c731d1b4520' AND version IS DISTINCT FROM 'R3-C3-IP-v2.2';

-- ---------------------------------------------------------------------------
-- Step 3 — Insert 5 new document_versions v2.2, locked_at=now().
-- Unique constraint: (document_id, version_number) + (document_id, version_label).
-- Idempotent via ON CONFLICT DO NOTHING.
-- ---------------------------------------------------------------------------

-- Sumário Executivo v2.2
INSERT INTO public.document_versions
  (document_id, version_number, version_label, content_html,
   authored_at, published_at, locked_at, notes)
VALUES
  ('9a0e5000-0000-0000-0000-000000000000', 2, 'v2.2',
   $html_sumario$
<p><strong>CR-050 — Sumário Executivo da Revisão</strong></p>
<p>Propriedade Intelectual no Núcleo de IA &amp; GP</p>
<p><em>Preparado por Vitor Rodovalho · 16 de Abril de 2026</em></p>
<p>Apoio à reunião Ivan Lourenço × Vitor Rodovalho · 16h</p>
<p><strong>TL;DR —</strong> O pacote CR-050 foi revisado em profundidade
após contribuição técnica do Roberto Macêdo (Curador PMI-CE), análise
sistêmica dos efeitos cruzados (v2.0), auditoria jurídica
pré-ratificação com 6 ajustes P1 + 7 ajustes P2 (v2.1) e curadoria final
pré-submissão ao jurídico do Ivan endereçando RF-2 (IRRF) + RF-3 (GDPR
UE) + 5 alinhamentos cross-doc (v2.2). Quatro documentos operacionais
(Termo, Adendo Retificativo, Adendo de Cooperação, Política) + este
Sumário estão prontos para submissão ao advogado do Ivan. Todas as
referências legais foram validadas nas fontes oficiais. O pacote cobre
escopo internacional (relevante para o Fabricio e para o programa AIPM
Ambassadors), inclui mecanismo de opt-out para publicação em periódicos
exclusivos, define governança de registro, custeio e royalties (com
retenção IRRF detalhada em sub-alíneas operacionais), corrige
enquadramento jurídico de software, e agora opera o GDPR para
voluntários UE com base legal, mecanismo de transferência internacional
e catálogo de direitos.</p>
<p>1. Contribuição do Roberto Macêdo (PMI-CE)</p>
<p>Revisão feita durante a manhã de 16/Abr. Roberto identificou dois
pontos diretos e levantou dois pontos de governança. Todos os quatro
foram incorporados ao pacote revisado.</p>
<p>Ponto 1 — Conflito com periódicos exclusivos</p>
<p>Periódicos de peso (Elsevier IJPM, RAUSP, Nature, etc.) exigem
ineditismo e cessão exclusiva. A licença “irrevogável” do draft v1
conflitaria com essa exigência. Pesquisadores seriam forçados a escolher
entre contribuir com o Núcleo ou publicar em canal top — exatamente o
que a política deve evitar.</p>
<p><strong>Solução incorporada:</strong> Cláusula 2.6 do termo (v2) cria
mecanismo de suspensão temporária da licença por obra específica, com
prazo de 24 meses renováveis e reativação automática ao fim do embargo.
O Núcleo preserva direitos sobre obras anteriores, simultâneas e
derivadas. Voluntário inclui nota de agradecimento ao Núcleo ou, se
vedado, registra na página de perfil de autor.</p>
<p>Ponto 2 — Software não é propriedade industrial</p>
<p>A Cláusula 2.5 do draft v1 invocava a Lei 9.279 (propriedade
industrial) para tratar software e frameworks. Erro técnico: software é
direito autoral sob a Lei 9.609; frameworks e documentos são direito
autoral sob a Lei 9.610. A Lei 9.279 cobre só patentes, marcas, desenho
industrial.</p>
<p><strong>Solução incorporada:</strong> Cláusula 2.5 reescrita em
quatro subcláusulas — cada tipo de obra com o enquadramento legal
correto (9.610 para obras gerais, 9.609 para software, 9.279 para
propriedade industrial, tratados internacionais para registros em outras
jurisdições).</p>
<p>Ponto 3 — Governança de registro e custeio</p>
<p>Roberto perguntou: quem analisa viabilidade? Quem paga INPI,
Biblioteca Nacional, honorários de agente de PI? Sem resposta clara, a
política vira letra morta.</p>
<p><strong>Solução incorporada:</strong> Seção 4 nova da Política cria
fluxo Curadoria → parecer técnico → GP + Presidente PMI-GO → notificação
aos demais presidentes (15 dias). Custos arcados pelo orçamento anual do
Núcleo administrado pelo PMI-GO. Desconto de 50% do INPI para entidades
sem fins lucrativos (Portaria INPI/PR nº 10/2025) torna os custos
administráveis. Plano B para restrição orçamentária: patrocínio,
cotitularidade, publicação defensiva, renúncia ao registro mantendo
proteção automática.</p>
<p>Ponto 4 — Uso pós-registro e política de royalties</p>
<p>Marcas sem uso caducam em 5 anos (Lei 9.279 Art. 143). Patentes sem
exploração podem sofrer licença compulsória (Art. 68). Se o Núcleo
registra algo, precisa ter política de uso explícita. E royalties, se
houver, precisam de destino definido.</p>
<p><strong>Solução incorporada:</strong> Regime padrão = uso universal
gratuito com atribuição, declarado no ato do registro. Finalidade:
defensiva e de reconhecimento formal, não reserva comercial. Exploração
com royalties é exceção, requer aprovação específica. Royalties, quando
houver, têm diretrizes mínimas: parcela aos autores, parcela ao fundo do
Núcleo, distribuição equitativa entre capítulos, vedação a fins alheios.
Controle anual de uso pela Curadoria para prevenir caducidade.</p>
<p>2. Contribuições Adicionais Identificadas na Análise</p>
<p>Seis pontos adicionais surgiram da análise sistêmica — efeitos
cruzados que não apareciam no exame ponto-a-ponto.</p>
<p>5. “Irrevogável” sujeita a prazo de 5 anos</p>
<p>A Lei 9.610 Art. 51 limita cessão de obras futuras a 5 anos —
jurisprudência aplica analogia a licenças sem prazo. “Licença
irrevogável e mundial” do draft v1, aplicada a obras futuras, corre
risco de redução judicial.</p>
<p><strong>Solução:</strong> Licença reestruturada como “licença por
obra específica”, outorgada no momento da entrega de cada obra. Deixa de
ser cessão de obras futuras em bloco. Vigora pelo prazo de proteção
legal da obra (70 anos pós-morte do autor, no Brasil), sem conflito com
o Art. 51.</p>
<p>6. Ineditismo operacional</p>
<p>Publisher pode questionar: apresentar em reunião interna do Núcleo
conta como “publicação prévia”? E em webinar público? E em CBGPL? Sem
definição, voluntário assina submissão e depois descobre que violou
ineditismo.</p>
<p><strong>Solução:</strong> Seção 6 nova da Política define
operacionalmente. Webinars internos, rascunhos, cards de plataforma,
relatórios internos = não contam. Blog público, congressos com gravação,
preprints públicos = contam.</p>
<p>7. Cláusula 4 vs. Track A</p>
<p>Cláusula 4 do termo vigente exige “prévia autorização” para usar o
nome do capítulo. Track A da política prevê apenas “notificação”.
Conflito direto: voluntário publica em Track A mas tecnicamente viola
Cláusula 4.</p>
<p><strong>Solução:</strong> Parágrafo único novo na Cláusula 4 do termo
ressalva três hipóteses: atribuição institucional em publicações Tracks
A/B/C, menção em contextos acadêmicos, demais hipóteses da Política.</p>
<p>8. Encarregado LGPD, não “DPO”</p>
<p>LGPD Art. 5º VIII usa o termo “encarregado” para o que o GDPR chama
de DPO. Documento jurídico brasileiro deve usar o termo legal correto. E
o Núcleo não precisa de encarregado próprio — usa o do PMI-GO (capítulo
sede).</p>
<p><strong>Solução:</strong> Seção 2 nova da Política formaliza. Track C
revisado para “Encarregado pela Proteção de Dados Pessoais (Encarregado)
do PMI-GO”. Política de privacidade do PMI-GO é referência operacional,
com prevalência da disposição mais protetiva em caso de ambiguidade.</p>
<p>9. Jurisdições estrangeiras</p>
<p>Você mora em Leesburg/VA. Fabricio pode estar em qualquer lugar.
Pesquisadores brasileiros apresentam em LIM Summit (Peru). PMI é
americano. AIPM Ambassadors é programa internacional. A política não
pode ser só brasileira.</p>
<p><strong>Solução:</strong> Seção 1 nova da Política estabelece lei
aplicável brasileira + tratamento nacional da Convenção de Berna +
proteção de direitos morais no padrão mais protetivo entre Brasil e
jurisdição local + foro Goiânia-GO como padrão, com protocolo reforçado
opcional (ICC, PMI Ethics, foro bilíngue) para casos internacionais.</p>
<p>10. Acordos internacionais futuros</p>
<p>O programa AIPM Ambassadors (Vargas + Nieto-Rodriguez) vai demandar
acordo institucional PMI-GO × entidade internacional. Sem
princípio-âncora na política, cada acordo vira negociação do zero.</p>
<p><strong>Solução:</strong> Seção 10 nova da Política estabelece que
acordos internacionais herdam a Política como baseline. Divergências
tratadas por adendo específico. Negociação pelos representantes
designados (você e Fabricio no caso Ambassadors) com aprovação prévia do
presidente PMI-GO e notificação aos 4 demais presidentes (15 dias).</p>
<p>3. Correção Crítica de Referência Jurídica</p>
<p>O draft v1 da política citava <strong>“Art. 49 §4º”</strong> da Lei
9.610 como base para o prazo de 5 anos de cessão de obras futuras. Essa
referência <strong>não existe</strong> nessa configuração no texto
legal. O dispositivo correto é o <strong>Art. 51</strong> (“A cessão dos
direitos de autor sobre obras futuras abrangerá, no máximo, o período de
cinco anos”). Se o pacote tivesse ido ao advogado com a referência
errada, teria prejudicado a credibilidade de todo o trabalho. Corrigido
no draft v2.</p>
<p>4. Instrumentos do Pacote CR-050 (v2.2)</p>
<table>
<colgroup>
<col style="width: 2%" />
<col style="width: 17%" />
<col style="width: 53%" />
<col style="width: 26%" />
</colgroup>
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
<td>Política de Publicação e Propriedade Intelectual (v2.2)</td>
<td>12 seções — escopo internacional, LGPD, governança de registro, 3
tracks, ineditismo, royalties, acordos internacionais. v2.1 incorporou
P1+P2 do parecer jurídico. v2.2 detalha IRRF em sub-alíneas operacionais
(§4.5.4 e.1–e.4) e reescreve §2.5 para GDPR operacional
(2.5.1–2.5.7).</td>
<td>Revisão jurídica do Ivan → aprovação via CR-050 no manual</td>
</tr>
<tr class="even">
<td>2</td>
<td>Termo de Voluntariado R3-C3-IP v2.2</td>
<td>Cláusula 2 integralmente substituída (2.1–2.6); Cláusula 4 com
parágrafo de ressalvas; Cláusula 9 atualizada (Encarregado + §2 direitos
do titular); Cláusula 11 revogação imagem; Cláusula 13 nova (lei
aplicável e jurisdição); v2.2 inclui Cláusula 14 (consentimento GDPR
Art. 49(1)(a), renderizada condicionalmente para residentes UE).</td>
<td>Revisão jurídica do Ivan → aprovação 5 presidentes → uso no Ciclo
4</td>
</tr>
<tr class="odd">
<td>3</td>
<td>Adendo Retificativo do Termo v2.2</td>
<td>Para os 52 voluntários que já assinaram R3-C3. Referencia termo
original, declara prevalência, retifica Cláusula 2 com nova redação.
Art. 4 incorpora escopo internacional. v2.2 inclui Art. 8 (consentimento
GDPR Art. 49(1)(a), renderizado condicionalmente para residentes
UE).</td>
<td>Revisão jurídica do Ivan → assinatura individual pelos voluntários
ativos</td>
</tr>
<tr class="even">
<td>4</td>
<td>Adendo de IP aos Acordos de Cooperação Bilateral v2.2</td>
<td>9 artigos (originalmente 7) — obras coletivas, uso irrevogável,
saída de capítulo, direitos morais, crédito, registro e titularidade,
escopo internacional, vigência, revisão. v2.2 explicita “4.0
Internacional” nas licenças CC-BY/CC-BY-SA e adiciona parágrafo único no
Art. 2 sobre re-licenciamento Track B para periódicos.</td>
<td>Circular para 5 presidentes (Jessica/CE, Matheus/DF, Felipe/MG,
Márcio/RS) + Ivan/GO</td>
</tr>
</tbody>
</table>
<p>5. Validação Jurídica das Referências</p>
<p>Todas as leis, decretos e portarias citados nos documentos foram
verificados em fontes oficiais (Planalto, LexML, gov.br/inpi,
gov.br/bn). Segue resumo:</p>
<table>
<colgroup>
<col style="width: 30%" />
<col style="width: 15%" />
<col style="width: 54%" />
</colgroup>
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
<td>Direitos Autorais. Art. 24-27 (morais); Art. 51 (5 anos obras
futuras)</td>
</tr>
<tr class="even">
<td>Lei nº 9.279</td>
<td>14/05/1996</td>
<td>Propriedade Industrial. Art. 11 (novidade); Art. 143 (caducidade
marca)</td>
</tr>
<tr class="odd">
<td>Lei nº 13.709</td>
<td>14/08/2018</td>
<td>LGPD. Art. 5º VIII define “encarregado” (termo legal
brasileiro)</td>
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
<p>A ratificação do pacote CR-050 segue fluxo on-platform (plataforma
<code>nucleoia.vitormr.dev</code>) com rastreabilidade legal,
assinaturas digitais e gates de aprovação sequenciais. Sem timeline
hard-coded: cada etapa avança conforme a anterior se conclui.</p>
<ul>
<li><p><strong>Etapa 1 — Auditoria jurídica pré-ratificação (concluída
19/Abr/2026):</strong> Revisão completa dos 5 documentos v2.0 por
parecer interno de curadoria. Resultado: APROVADO COM RESSALVAS — 6
ajustes P1 + 7 ajustes P2 incorporados no v2.1. Parecer em
<code>docs/council/2026-04-19-legal-counsel-ip-review.md</code>.</p></li>
<li><p><strong>Etapa 1-A — Curadoria final pré-submissão (concluída
20/Abr/2026):</strong> Segunda rodada de curadoria interna endereçando
os Red Flags externos que haviam sido marcados “fora do escopo AI” no
parecer anterior. Incorporados no v2.2: (i) detalhamento operacional do
IRRF em sub-alíneas (e.1)–(e.4) na Política §4.5.4 — base legal CTN/RIR,
DARF códigos 0588/0473, DIRF, CDTs, jurisdições favorecidas, rateio
capítulos; (ii) reescrita da Política §2.5 (GDPR) substituindo nota de
intenção por cláusula operacional (2.5.1–2.5.7) com base legal Art.
6(1)(b), mecanismo de transferência Art. 49(1)(a)+(b), direitos Arts.
15–21, threshold Art. 27, notificação Art. 33/34, DPIA Art. 35; (iii)
inclusão de Cláusula 14 (Termo) e Art. 8 (Adendo Retificativo) com
consentimento Art. 49(1)(a) GDPR renderizado condicionalmente para
residentes UE; (iv) 5 alinhamentos cross-doc (Encarregado, CC-BY 4.0
Internacional, Track B re-licensing, standby itálico, versioning).
Parecer em
<code>docs/council/2026-04-20-legal-counsel-v2.1-to-v2.2-curation.md</code>.</p></li>
<li><p><strong>Etapa 2 — Validação jurídica pelo advogado do Ivan
(próxima):</strong> Submissão do pacote v2.2 ao jurídico indicado pelo
Ivan Lourenço (PMI-GO) durante a fase de comment/approval do chain de
ratificação. Foco da revisão: validação dos textos propostos para IRRF
(Política §4.5.4 sub-alíneas) e GDPR (Política §2.5 + consentimento
condicional no Termo/Adendo), além da validação dos riscos residuais
sinalizados (lista de CDTs relevantes; vigência CEBAS do PMI-GO;
threshold Art. 27 para representante UE; rateio PJ-PJ entre capítulos;
aplicabilidade continuada de Art. 49 GDPR à luz do EDPB Guidelines
2/2018). O pacote chega ao revisor humano com o problema diagnosticado,
as opções mapeadas e o texto parcialmente resolvido — reduzindo o escopo
de revisão a validação e refinamento final.</p></li>
<li><p><strong>Etapa 3 — Aprovação política pelos 5 presidentes
(paralelo):</strong> Circulação do v2.2 aos presidentes Ivan/GO,
Jessica/CE, Matheus/DF, Felipe/MG, Márcio/RS via plataforma. Comentários
e questionamentos registrados em thread por cláusula. Aprovação
sequencial (curador → líder → president_go → 4 demais presidentes) com
silêncio positivo para marcas/patentes.</p></li>
<li><p><strong>Etapa 4 — Ratificação pelos 52 voluntários
ativos:</strong> Após aprovação política, disparo do Adendo Retificativo
v2.2 para os 52 voluntários. Cadência de lembretes D-14/-7/-3/-1.
Magic-link para external signers (se houver).</p></li>
<li><p><strong>Etapa 5 — Vigência plena:</strong> Entrada em vigor do
Termo R3-C3-IP v2.2 para o Ciclo 4 (novos voluntários) e do Adendo de
Cooperação v2.2 integrado aos 4 acordos bilaterais existentes.</p></li>
<li><p><strong>Eventos públicos paralelos:</strong> CBGPL (28/Abr/2026)
é momento de comunicação institucional, não gate da ratificação. LIM
Summit, PMI Global Congress e outros são oportunidades de apresentação,
não condicionantes da formalização.</p></li>
</ul>
<p>7. Pontos de Decisão Específicos para a Reunião</p>
<p>Sugestão de agenda focada — 30 min:</p>
<ul>
<li><p><strong>(1) Validação da direção geral</strong> — 5 min.
Confirmar que os 10 pontos endereçados fazem sentido como pacote. Não
precisa entrar em texto específico.</p></li>
<li><p><strong>(2) Escopo internacional</strong> — 5 min. Decisão de
tratar o programa como transnacional agora (não depois). Pergunta: Ivan
vê algum obstáculo estatutário do PMI-GO?</p></li>
<li><p><strong>(3) Registro e custeio</strong> — 5 min. Decisão:
orçamento anual do Núcleo para PI administrado pelo PMI-GO. Pergunta:
qual o teto sugerido para o primeiro ciclo?</p></li>
<li><p><strong>(4) Política de royalties</strong> — 5 min. Decisão de
deixar aberto agora e resolver caso a caso. Pergunta: Ivan concorda ou
quer bounds mínimos?</p></li>
<li><p><strong>(5) Encaminhamento jurídico</strong> — 5 min. Ivan indica
advogado. Prazo acordado: até 25/Abr para ter pacote validado antes do
CBGPL.</p></li>
<li><p><strong>(6) Comunicação aos 4 presidentes</strong> — 5 min.
Alinhar quem manda, quando, com que formato. Sugestão: circular após
validação jurídica, não antes.</p></li>
</ul>
<p><em>CR-050 v2.2 | Núcleo de Estudos e Pesquisa em IA &amp; GP |
nucleoia.vitormr.dev</em></p>
<p><em>Documentos do pacote (v2.2): 01_Politica_Publicacao_IP_v2.2 ·
02_Termo_Voluntariado_R3-C3-IP_v2.2 · 03_Adendo_Retificativo_Termo_v2.2
· 04_Adendo_IP_Acordos_Cooperacao_v2.2</em></p>
<p><em>Parecer de auditoria jurídica pré-ratificação (v2.1):
<code>docs/council/2026-04-19-legal-counsel-ip-review.md</code></em></p>
<p><em>Parecer de curadoria final v2.1 → v2.2:
<code>docs/council/2026-04-20-legal-counsel-v2.1-to-v2.2-curation.md</code></em></p>
$html_sumario$,
   now(), now(), now(),
   'v2.2: curadoria final pré-submissão ao jurídico (parecer 5f2df67; commits 1679400+).')
ON CONFLICT (document_id, version_label) DO NOTHING;

-- Política v2.2
INSERT INTO public.document_versions
  (document_id, version_number, version_label, content_html,
   authored_at, published_at, locked_at, notes)
VALUES
  ('cfb15185-2800-4441-9ff1-f36096e83aa8', 2, 'v2.2',
   $html_politica$
<p><strong>Política de Publicação e Propriedade Intelectual</strong></p>
<p>Núcleo de Estudos e Pesquisa em Inteligência Artificial e Gestão de
Projetos</p>
<p><em>DRAFT v2.2 — Pendente validação jurídica e aprovação |
CR-050</em></p>
<p>Capítulos: PMI-GO (sede), PMI-CE, PMI-DF, PMI-MG, PMI-RS</p>
<p><strong>Nota de versão:</strong> Esta versão consolida o draft v1.0
com as revisões do CR-050 decorrentes da análise colaborativa com o
Presidente do PMI-GO (Ivan Lourenço), com o Diretor Curador PMI-CE
(Roberto Macêdo) e com o Gerente de Projeto do Núcleo (Vitor Rodovalho),
incorporando as considerações de conflito com periódicos exclusivos,
enquadramento jurídico correto para software e documentos, governança de
registro, política de uso e royalties, escopo internacional e
alinhamento terminológico com a LGPD.</p>
<p><strong>Nota v2.0 → v2.1 (19/Abr/2026):</strong> Incorporados os
ajustes do parecer de auditoria jurídica pré-ratificação: (i) silêncio
positivo na notificação de depósito de marcas e patentes aos demais
presidentes signatários (§1 da Cláusula 4.2.1); (ii) retenção IRRF sobre
royalties (alínea “e” da Cláusula 4.5.4); (iii) mecanismo de
re-licenciamento CC-BY-SA → CC-BY para obras Track B submetidas a
periódicos que exigem licença não-SA (Seção 5, Track B); (iv) nota
interpretativa sobre AI training vs. citação acadêmica de material PMI
(Seção 11); (v) nota sobre aplicabilidade do GDPR para voluntários
residentes na União Europeia (Seção 2).</p>
<p><strong>Nota v2.1 → v2.2 (20/Abr/2026):</strong> Incorporados os
ajustes da curadoria final pré-submissão ao jurídico do Ivan (parecer
<code>2026-04-20-legal-counsel-v2.1-to-v2.2-curation.md</code>): (i)
reescrita operacional da Seção 2.5 (aplicação do GDPR para voluntários
residentes na União Europeia), substituindo a nota de intenção futura
por cláusula com base legal (Art. 6(1)(b) GDPR), mecanismo de
transferência internacional (Art. 49(1)(a)+(b) GDPR), catálogo de
direitos do titular (Arts. 15–21 GDPR), threshold para representante na
UE (Art. 27 GDPR), notificação de violação 72h (Arts. 33–34 GDPR) e
avaliação DPIA/DPA (Arts. 35/28 GDPR); (ii) detalhamento da alínea (e)
da Cláusula 4.5.4 em sub-alíneas (e.1)–(e.4) para retenção e
recolhimento de IRRF, com base legal consolidada (CTN arts. 43/45, RIR
Decreto nº 9.580/2018, DARF códigos 0588/0473, DIRF, CDTs e art. 24 da
Lei nº 9.430/1996), diferenciação entre PF residente no Brasil e
não-residente, e diretriz de rateio entre capítulos signatários; (iii)
alinhamentos terminológicos cross-doc (Encarregado pela Proteção de
Dados Pessoais, CC-BY/CC-BY-SA 4.0 Internacional, Track B
re-licenciamento referenciado no Adendo de Cooperação).</p>
<p>1. Escopo Institucional e Lei Aplicável</p>
<p><strong>1.1</strong> O Núcleo de Estudos e Pesquisa em IA &amp; GP é
programa interinstitucional sediado no Brasil, tendo o PMI Brasil–Goiás
Chapter (PMI-GO) como capítulo sede e entidade juridicamente
responsável, com os demais capítulos signatários (PMI-CE, PMI-DF,
PMI-MG, PMI-RS) vinculados por Acordos de Cooperação Bilaterais.</p>
<p><strong>1.2</strong> Esta Política é regida pela legislação
brasileira, em especial:</p>
<ul>
<li><p>Lei nº 9.610, de 19 de fevereiro de 1998 (Direitos
Autorais);</p></li>
<li><p>Lei nº 9.609, de 19 de fevereiro de 1998 (Proteção da Propriedade
Intelectual de Programa de Computador);</p></li>
<li><p>Lei nº 9.279, de 14 de maio de 1996 (Propriedade
Industrial);</p></li>
<li><p>Lei nº 9.608, de 18 de fevereiro de 1998 (Serviço Voluntário),
com redação atualizada pela Lei nº 13.297, de 16 de junho de
2016;</p></li>
<li><p>Lei nº 13.709, de 14 de agosto de 2018 (Lei Geral de Proteção de
Dados Pessoais — LGPD).</p></li>
</ul>
<p><strong>1.3</strong> Aplicam-se ainda os tratados internacionais
vigentes no Brasil em matéria de propriedade intelectual, em especial a
Convenção de Berna para a Proteção das Obras Literárias e Artísticas
(promulgada pelo Decreto nº 75.699, de 6 de maio de 1975) e o Acordo
TRIPS (promulgado pelo Decreto nº 1.355, de 30 de dezembro de 1994), nos
termos do art. 2º da Lei nº 9.610/1998.</p>
<p><strong>1.4</strong> O Núcleo reconhece sua natureza transnacional,
decorrente de: (a) filiação ao Project Management Institute, entidade
global sediada nos Estados Unidos; (b) participação de voluntários
residentes em jurisdições estrangeiras; (c) apresentação de obras em
eventos e periódicos internacionais; (d) celebração de acordos com
entidades internacionais.</p>
<p><strong>1.5</strong> Para VOLUNTÁRIOS residentes fora do Brasil, a
licença concedida ao Núcleo (Cláusula 2.2 do Termo de Voluntariado) será
interpretada nos termos equivalentes aos previstos nesta Política,
respeitada a legislação da jurisdição local do autor no que for mais
protetivo em matéria de direitos morais, conforme o princípio do
tratamento nacional da Convenção de Berna (Art. 5.1).</p>
<p><strong>1.6</strong> O Código de Ética e Conduta Profissional do
Project Management Institute é reconhecido como instrumento aplicável a
todos os voluntários independentemente de jurisdição, complementando a
legislação local.</p>
<p><strong>1.7</strong> Controvérsias serão resolvidas prioritariamente
por conciliação interna mediada pelo Gerente de Projeto e pelos
presidentes dos capítulos envolvidos. Persistindo o conflito, o foro de
eleição é a Comarca de Goiânia/GO, ressalvado que, em casos envolvendo
voluntários residentes no exterior ou entidades internacionais, o método
de solução de controvérsias poderá ser definido em instrumento
específico.</p>
<p><strong>1.7.1</strong> <em>(Adendo — Protocolo Reforçado para Solução
Internacional de Controvérsias).</em> Quando a controvérsia envolver
voluntário residente no exterior ou entidade internacional parte de
acordo com o Núcleo, e não sendo possível a conciliação interna no prazo
de 60 (sessenta) dias, as partes poderão optar, em instrumento
específico, por: (i) arbitragem conforme regras da Câmara de Comércio
Internacional (ICC) ou de câmara arbitral brasileira; (ii) submissão ao
PMI Ethics Review Committee, quando a matéria envolver conduta ética
profissional; ou (iii) foro da Comarca de Goiânia/GO com opção por
processo em língua inglesa ou portuguesa. A ativação deste protocolo não
é obrigatória e depende de acordo expresso entre as partes.</p>
<p>2. Proteção de Dados Pessoais e Política de Privacidade</p>
<p><strong>2.1</strong> O tratamento de dados pessoais no âmbito do
Núcleo observa a Lei nº 13.709/2018 (LGPD) e a Política de Privacidade
do PMI Brasil–Goiás Chapter (PMI-GO), disponível em
pmigo.org.br/politicas/ e espelhada em nucleoia.vitormr.dev/privacy, na
condição de capítulo sede e controlador dos dados tratados no âmbito do
Programa.</p>
<p><strong>2.2</strong> Os demais capítulos signatários dos Acordos de
Cooperação Bilaterais aderem à Política de Privacidade do PMI-GO como
referência operacional do Programa, sem prejuízo de suas próprias
políticas institucionais para atividades fora do escopo do Núcleo.</p>
<p><strong>2.3</strong> O Encarregado pela Proteção de Dados Pessoais
(Encarregado), designado pelo PMI-GO nos termos do art. 5º, VIII, da Lei
nº 13.709/2018 (LGPD), atua como ponto focal de comunicação com
titulares de dados e com a Autoridade Nacional de Proteção de Dados
(ANPD) para todas as atividades do Núcleo.</p>
<p><strong>2.4</strong> Em caso de ambiguidade ou lacuna entre a
Política de Privacidade do PMI-GO e a legislação aplicável, prevalece a
disposição mais protetiva ao titular dos dados, observado o disposto na
legislação federal brasileira.</p>
<p><strong>2.5 Voluntários Residentes na União Europeia — Aplicação do
GDPR.</strong></p>
<p><strong>2.5.1</strong> <em>Alcance.</em> O Regulamento (UE) 2016/679
(GDPR) pode incidir sobre o tratamento de dados de voluntários
residentes em Estados-membros da União Europeia quando o Núcleo recrutar
ou oferecer participação a residentes da UE, nos termos do Art. 3(2) do
GDPR. O Núcleo reconhece esta responsabilidade e adota as disposições
desta Seção para voluntários UE formalizados.</p>
<p><strong>2.5.2</strong> <em>Base legal de processamento.</em> O
tratamento de dados pessoais de voluntários residentes na UE
fundamenta-se no Art. 6(1)(b) do GDPR — execução do Termo de
Voluntariado do qual o voluntário é parte —, para todos os dados
necessários à gestão do vínculo voluntário (identificação, comunicação,
registro de contribuições intelectuais). Dados complementares coletados
para finalidades específicas (ex: dados de uso da plataforma para fins
de gamificação) serão identificados e comunicados ao titular no ato da
coleta, com base legal individualizada.</p>
<p><strong>2.5.3</strong> <em>Transferência internacional de dados
Brasil ↔︎ UE.</em> O Brasil, à data desta Política, não possui decisão de
adequação emitida pela Comissão Europeia nos termos do Art. 45 do GDPR.
A transferência dos dados pessoais de voluntários residentes na UE para
servidores localizados no Brasil (operados pelo PMI-GO como controlador)
fundamenta-se no Art. 49(1)(b) do GDPR — necessidade de execução do
contrato (Termo de Voluntariado) do qual o titular é parte —,
complementado por consentimento explícito e informado do voluntário no
ato da assinatura do Termo, conforme Art. 49(1)(a) do GDPR, após ciência
dos riscos decorrentes da ausência de decisão de adequação.</p>
<p><strong>2.5.4</strong> <em>Direitos dos voluntários UE como
titulares.</em> Voluntários residentes na UE têm, em adição aos direitos
previstos no Art. 18 da LGPD, os seguintes direitos garantidos pelo
GDPR:</p>
<ul>
<li><p>(a) Direito de acesso (Art. 15 GDPR): confirmação do tratamento e
cópia dos dados;</p></li>
<li><p>(b) Direito de retificação (Art. 16 GDPR): correção de dados
inexatos;</p></li>
<li><p>(c) Direito ao apagamento (“direito ao esquecimento”, Art. 17
GDPR): eliminação dos dados quando cessado o vínculo, ressalvadas
obrigações legais de retenção;</p></li>
<li><p>(d) Direito à portabilidade (Art. 20 GDPR): recebimento dos dados
em formato estruturado e legível por máquina;</p></li>
<li><p>(e) Direito de oposição (Art. 21 GDPR): oposição ao tratamento
baseado em legítimos interesses;</p></li>
<li><p>(f) Direito à limitação do tratamento (Art. 18 GDPR): suspensão
do tratamento em situações específicas previstas na norma.</p></li>
</ul>
<p>Estes direitos são exercíveis junto ao Encarregado designado pelo
PMI-GO, conforme Seção 2.3, que atuará como ponto de contato com as
autoridades supervisoras competentes (Autoridade Nacional de Proteção de
Dados — ANPD no Brasil; autoridade de supervisão do Estado-membro da UE
de residência do voluntário, nos termos do Art. 77 do GDPR).</p>
<p><strong>2.5.5</strong> <em>Representante na UE.</em> O Núcleo
avaliará a necessidade de designar representante na União Europeia nos
termos do Art. 27 do GDPR quando o número de voluntários UE ativos
simultaneamente exceder 10 (dez) indivíduos, ou quando o processamento
envolver categorias especiais de dados (Art. 9 GDPR) ou dados de
natureza sensível, o que ocorrer primeiro. Até esse limiar, o Programa
se apoia na isenção prevista no Art. 27(2)(a) do GDPR para processamento
não sistemático de baixo risco.</p>
<p><strong>2.5.6</strong> <em>Notificação de violação.</em> Em caso de
violação de dados que afete voluntários residentes na UE, o Núcleo
notificará a autoridade supervisora competente no Estado-membro de
residência do titular afetado no prazo de 72 (setenta e duas) horas após
a tomada de conhecimento, nos termos do Art. 33 do GDPR, e comunicará o
titular afetado sem demora injustificada quando a violação puder
resultar em alto risco para seus direitos e liberdades (Art. 34 do
GDPR).</p>
<p><strong>2.5.7</strong> <em>Deliberação específica por caso.</em>
Acordos com entidades internacionais que envolvam fluxo sistemático de
dados de residentes UE serão precedidos de avaliação específica pelo
Encarregado do PMI-GO quanto à necessidade de Avaliação de Impacto sobre
a Proteção de Dados (DPIA — Art. 35 GDPR) e de Data Processing Agreement
(DPA — Art. 28 GDPR) quando o Núcleo atuar como operador de controlador
estabelecido na UE.</p>
<p>3. Princípios</p>
<p>1. Direitos morais (autoria, crédito, integridade) são inalienáveis e
pertencem aos autores.</p>
<p>2. O Núcleo é uma colaboração multi-capítulo; a propriedade
intelectual não pertence a um único capítulo.</p>
<p>3. Pesquisadores devem ter caminho claro para publicação com crédito
adequado, inclusive em periódicos e editoras externas.</p>
<p>4. Transparência e equidade entre voluntários de todos os
capítulos.</p>
<p>5. Proteção de informações confidenciais e dados pessoais (LGPD).</p>
<p>6. Sempre que possível, obras registradas pelo Núcleo são
disponibilizadas para uso universal com atribuição, privilegiando o
impacto sobre a reserva comercial.</p>
<p>4. Registro de Propriedade Intelectual e Política de Exploração</p>
<p>4.1 Âmbito de Aplicação</p>
<p>Esta seção aplica-se a obras produzidas no âmbito do Programa que
sejam candidatas a registro formal de propriedade intelectual,
incluindo:</p>
<ul>
<li><p>(a) Registro autoral de obras literárias, científicas, artísticas
ou compilações junto ao Escritório de Direitos Autorais da Fundação
Biblioteca Nacional (EDA/FBN), conforme a Lei nº 9.610/1998;</p></li>
<li><p>(b) Registro de programa de computador junto ao Instituto
Nacional da Propriedade Industrial (INPI), conforme a Lei nº
9.609/1998;</p></li>
<li><p>(c) Depósito de patente de invenção, patente de modelo de
utilidade, registro de desenho industrial ou registro de marca junto ao
INPI, conforme a Lei nº 9.279/1996;</p></li>
<li><p>(d) Registros internacionais equivalentes, quando aplicáveis,
observados os tratados vigentes no Brasil (Convenção de Berna, TRIPS,
Tratado de Cooperação em Matéria de Patentes — PCT, entre
outros).</p></li>
</ul>
<p>4.2 Análise de Viabilidade pela Curadoria</p>
<p>A Comissão de Curadoria do Núcleo é responsável pela análise de
viabilidade de registro, mediante parecer fundamentado que
considere:</p>
<ul>
<li><p><strong>(a) Originalidade e mérito técnico-científico</strong> da
obra;</p></li>
<li><p><strong>(b) Requisitos legais de registrabilidade</strong> (para
patentes: novidade, atividade inventiva, aplicação industrial, conforme
art. 8º da Lei nº 9.279/1996; para software e obras autorais:
originalidade);</p></li>
<li><p><strong>(c) Estratégia de proteção</strong> mais adequada ao caso
concreto (autoral vs. industrial; registro nacional
vs. internacional);</p></li>
<li><p><strong>(d) Análise de custo-benefício,</strong> considerando os
valores praticados pelos órgãos competentes e os benefícios
institucionais do registro;</p></li>
<li><p><strong>(e) Política de exploração</strong> aplicável à obra
(Seção 4.5), definida no próprio ato de solicitação de
registro;</p></li>
<li><p><strong>(f) Existência de direitos de terceiros</strong> que
possam ser afetados.</p></li>
</ul>
<p><strong>4.2.1</strong> O parecer da Curadoria é submetido à aprovação
do Gerente de Projeto e do Presidente do PMI-GO, capítulo sede e titular
legal do registro. Aprovado o registro, os demais presidentes
signatários dos Acordos de Cooperação Bilaterais serão notificados com
antecedência mínima de 15 (quinze) dias do ato de depósito, em
consonância com o princípio de tratamento igualitário entre capítulos
previsto na Seção 9 desta Política.</p>
<p><strong>§ 1º Aprovação tácita por silêncio para marcas e
patentes.</strong> Para depósito de marcas e patentes — ativos de maior
impacto sobre a identidade institucional do Programa — a ausência de
manifestação contrária por escrito de qualquer dos presidentes
signatários no prazo de 15 (quinze) dias contados do recebimento da
notificação importa aprovação tácita, nos termos do art. 111 do Código
Civil. Em caso de manifestação contrária, o depósito será suspenso por
até 30 (trinta) dias para deliberação conjunta entre os presidentes
signatários. Para registros autorais junto à EDA/FBN, mantém-se a
notificação simples sem efeito de aprovação tácita.</p>
<p><strong>4.2.2</strong> Em caso de parecer desfavorável, a obra
permanece protegida nos termos da proteção automática prevista na Lei nº
9.610/1998 e na Convenção de Berna (proteção independe de registro), sem
prejuízo de publicação sob Track A ou Track B conforme esta
Política.</p>
<p>4.3 Titularidade</p>
<p>Os registros formais de propriedade intelectual de obras produzidas
no âmbito do Programa são depositados em nome do <strong>PMI
Brasil–Goiás Chapter (PMI-GO)</strong>, como capítulo sede do Núcleo e
entidade juridicamente responsável, preservados:</p>
<ul>
<li><p>(a) Os direitos morais dos autores individuais, nos termos da
Cláusula 2.1 do Termo de Voluntariado e das Leis nº 9.610/1998 e nº
9.609/1998;</p></li>
<li><p>(b) A identificação nominal dos autores/inventores no ato do
registro, conforme exigido pela legislação aplicável (art. 6º, §4º, da
Lei nº 9.279/1996 — direito do inventor de ser nomeado);</p></li>
<li><p>(c) O direito de uso irrevogável pelos demais capítulos
signatários dos Acordos de Cooperação Bilaterais, nos termos do
respectivo Adendo de Propriedade Intelectual.</p></li>
</ul>
<p>4.4 Custeio</p>
<p><strong>4.4.1</strong> Os custos de registro — incluindo taxas dos
órgãos competentes (INPI, EDA/FBN, órgãos internacionais), honorários de
agentes de propriedade industrial quando necessários, e anuidades de
manutenção — são custeados pelo orçamento anual do Núcleo, administrado
pelo PMI-GO.</p>
<p><strong>4.4.2</strong> O Núcleo beneficia-se dos descontos de 50%
(cinquenta por cento) concedidos pelo INPI a entidades sem fins
lucrativos, nos termos do art. 2º da Portaria INPI/PR nº 10/2025 ou
norma posterior equivalente, mediante comprovação da natureza jurídica
do PMI-GO.</p>
<p><strong>4.4.3</strong> O orçamento anual de propriedade intelectual é
aprovado pela Presidência do PMI-GO em consulta aos demais presidentes
signatários, com previsão de reserva técnica para eventuais registros
emergenciais ao longo do ciclo.</p>
<p><strong>4.4.4</strong> Em caso de impossibilidade orçamentária de
arcar com os custos de registro ou manutenção de um ativo já registrado,
a Curadoria apresentará parecer sobre as opções disponíveis,
incluindo:</p>
<ul>
<li><p>(a) busca de patrocínio externo específico;</p></li>
<li><p>(b) parceria com instituição de pesquisa ou universidade que
possa custear o registro em regime de cotitularidade;</p></li>
<li><p>(c) publicação defensiva (<em>defensive publication</em>), que
afasta a patenteabilidade por terceiros sem gerar custos de
manutenção;</p></li>
<li><p>(d) renúncia ao registro, com manutenção da proteção automática
da obra pela Lei nº 9.610/1998.</p></li>
</ul>
<p>4.5 Política de Exploração e Royalties</p>
<p><strong>4.5.1 Regime padrão — Uso universal com atribuição.</strong>
Por padrão, obras registradas em nome do Núcleo/PMI-GO serão
disponibilizadas sob regime de uso universal gratuito com atribuição,
mediante declaração formal no ato do registro ou por meio de licença
pública compatível (CC-BY 4.0 para obras autorais; MIT ou Apache-2.0
para software; declaração equivalente para patentes, quando
aplicável).</p>
<p><strong>4.5.2 Finalidade do registro sob regime padrão.</strong>
Nesse regime, o registro tem finalidade defensiva e de reconhecimento
formal da autoria institucional, afastando apropriação indevida por
terceiros sem gerar reserva comercial de mercado.</p>
<p><strong>4.5.3 Regime de exploração com retorno financeiro.</strong>
Em caráter excepcional, mediante parecer específico da Curadoria e
aprovação pela Presidência do PMI-GO em consulta aos demais presidentes
signatários, uma obra poderá ser registrada sob regime de exploração
comercial com previsão de royalties ou licenciamento oneroso.</p>
<p><strong>4.5.4 Destinação de royalties.</strong> Quando houver
previsão de royalties, sua destinação será definida no próprio
instrumento de aprovação do registro, observando as seguintes diretrizes
mínimas:</p>
<ul>
<li><p>(a) Reconhecimento de percentual aos autores/inventores
individuais, nos termos a serem acordados;</p></li>
<li><p>(b) Alocação de parcela ao fundo de pesquisa e custeio do
Núcleo;</p></li>
<li><p>(c) Distribuição equitativa entre os capítulos signatários,
conforme regra específica aprovada caso a caso;</p></li>
<li><p>(d) Vedação ao uso de royalties para fins alheios aos objetivos
institucionais do Núcleo e do PMI-GO;</p></li>
<li><p>(e) <strong>Retenção, recolhimento e prestação de contas
tributárias sobre royalties.</strong> O PMI-GO, na qualidade de fonte
pagadora, é responsável pela retenção do Imposto de Renda Retido na
Fonte (IRRF) sobre os royalties pagos, nos termos dos arts. 43 e 45 do
Código Tributário Nacional (CTN — Lei nº 5.172/1966) e do Decreto nº
9.580/2018 (Regulamento do Imposto de Renda — RIR/2018, arts. 779 e
seguintes), observadas as seguintes regras:</p>
<ul>
<li><p>(e.1) Para beneficiários pessoas físicas residentes no Brasil:
aplica-se a tabela progressiva mensal do IRRF vigente (Lei nº
7.713/1988, art. 7º), com recolhimento via DARF ao código 0588 até o
último dia útil do mês subsequente ao pagamento; emissão de comprovante
anual de rendimentos ao beneficiário e inclusão na DIRF do exercício,
nos termos das Instruções Normativas da Receita Federal
vigentes;</p></li>
<li><p>(e.2) Para beneficiários não residentes no Brasil: aplica-se a
alíquota de 15% (quinze por cento) sobre o valor bruto da remessa, nos
termos do art. 5º da Lei nº 9.779/1999, sujeita a redução conforme
Convenção para Evitar a Dupla Tributação celebrada pelo Brasil com o
país de residência do beneficiário, quando aplicável, mediante
apresentação de comprovante de residência fiscal estrangeira; para
remessas a residentes em jurisdições com tributação favorecida (art. 24
da Lei nº 9.430/1996), aplica-se a alíquota de 25% (vinte e cinco por
cento); o recolhimento é feito via DARF ao código 0473;</p></li>
<li><p>(e.3) A isenção do PMI-GO de Imposto de Renda não se transmite ao
beneficiário do royalty, que é tributado individualmente como acima
descrito;</p></li>
<li><p>(e.4) Quando houver rateio de royalties entre capítulos
signatários (pessoas jurídicas), o tratamento tributário será definido
em instrumento específico de rateio, verificando-se a natureza da
receita para cada capítulo receptor, em consulta com contador ou
assessor tributário.</p></li>
</ul></li>
</ul>
<p><strong>4.5.5 Prevenção de caducidade por desuso.</strong> Para
registros sujeitos à caducidade por desuso — em especial marcas
registradas (art. 143 da Lei nº 9.279/1996) e patentes sujeitas a
licença compulsória por não exploração (art. 68 da Lei nº 9.279/1996) —
a Curadoria manterá controle anual de uso efetivo ou licenciamento,
adotando tempestivamente medidas de preservação do direito, incluindo
declaração pública de <em>patent pledge</em> ou <em>defensive
publication</em> quando couber.</p>
<p>4.6 Registros Internacionais</p>
<p>A decisão sobre depósito em jurisdições estrangeiras — diretamente
nos respectivos escritórios nacionais (USPTO, EPO, entre outros) ou por
meio do Tratado de Cooperação em Matéria de Patentes (PCT) — segue o
mesmo fluxo de análise da Curadoria, aprovação pela Presidência e
custeio por orçamento específico, observadas as regras de prioridade
unionista previstas na Convenção de Paris e na Lei nº 9.279/1996 (arts.
16 e 17).</p>
<p>5. Tracks de Publicação</p>
<p>Track A — Aberto</p>
<p><strong>Tipos:</strong> Artigos, reviews comparativas, webinars,
posts de blog, apresentações em eventos, livros, capítulos de livro.</p>
<p><strong>Licença:</strong> CC-BY 4.0 (Creative Commons Atribuição 4.0
Internacional).</p>
<p><strong>Aprovação:</strong> Notificação ao Gerente de Projeto com 15
(quinze) dias de antecedência (não requer autorização prévia).</p>
<p><strong>Crédito:</strong> Autor(es) + “Núcleo de Estudos e Pesquisa
em IA &amp; GP — PMI [Capítulos]”.</p>
<p><strong>Restrições:</strong> Não pode incluir dados pessoais (LGPD),
informações confidenciais, ou material protegido do PMI sem
permissão.</p>
<p>Track B — Framework</p>
<p><strong>Tipos:</strong> Frameworks originais, metodologias,
ferramentas conceituais, livros técnicos/metodológicos, templates
reutilizáveis, código-fonte.</p>
<p><strong>Licença:</strong> CC-BY-SA 4.0 (documentos/metodologias) ou
MIT/Apache-2.0 (código-fonte).</p>
<p><strong>Aprovação:</strong> Gerente de Projeto + pelo menos 1 (um)
presidente de capítulo parceiro.</p>
<p><strong>Crédito:</strong> Autores individuais + líder da tribo (se
supervisionou) + Núcleo.</p>
<p><strong>Restrições:</strong> Revisão prévia pelo GP para garantir
ausência de IP de terceiros.</p>
<p><strong>Re-licenciamento para periódicos.</strong> Quando obra
licenciada sob CC-BY-SA 4.0 (Track B) for submetida a periódico
científico que exija licença CC-BY 4.0 (ou equivalente não-SA) como
condição de publicação, o Gerente de Projeto — com concordância expressa
dos autores individuais — poderá autorizar a publicação da versão
submetida sob CC-BY 4.0, preservando-se a versão originalmente publicada
pelo Núcleo sob CC-BY-SA 4.0. O re-licenciamento aplica-se
exclusivamente à versão editorial submetida, não afetando os direitos
sobre a versão originalmente publicada pelo Núcleo nem os direitos
morais dos autores. O mesmo mecanismo aplica-se a obras Track B
licenciadas sob CC-BY-SA 4.0 que precisem ser submetidas sob MIT ou
Apache-2.0 por exigência de repositório de código.</p>
<p>Track C — Restrito</p>
<p><strong>Tipos:</strong> Algoritmos proprietários, modelos de scoring,
dados de seleção, invenções patenteáveis, dados PII agregados.</p>
<p><strong>Licença:</strong> Proprietário (Núcleo/PMI-GO como capítulo
sede).</p>
<p><strong>Aprovação:</strong> Gerente de Projeto + Presidente do PMI-GO
+ Encarregado pela Proteção de Dados Pessoais (Encarregado) do PMI-GO,
quando o conteúdo envolver dados pessoais nos termos da Lei nº
13.709/2018 (LGPD).</p>
<p><strong>Crédito:</strong> Inventores/autores registrados
internamente; publicação externa requer aprovação específica.</p>
<p><strong>Restrições:</strong> Acesso restrito. Avaliação de
patenteabilidade antes de divulgação (Lei nº 9.279/1996, art. 11).</p>
<p><strong>Sobre livros e publicações comerciais:</strong> <em>As
licenças CC-BY e CC-BY-SA permitem uso comercial. Um voluntário pode
publicar um livro por editora, cobrar por ele — a única exigência é
atribuição ao Núcleo. É o padrão acadêmico global: PLOS ONE, Nature
Communications e Springer Open publicam sob CC-BY 4.0. A OpenStax (Rice
University) publica livros didáticos inteiros sob CC-BY. Licenciar não é
perder controle — é formalizar o que já funciona no mundo
científico.</em></p>
<p>6. Definição Operacional de Publicação Prévia e Ineditismo</p>
<p><strong>6.1</strong> Para fins de relacionamento do Núcleo com
periódicos científicos, editoras e eventos que exijam ineditismo da
obra, aplica-se a seguinte definição operacional, sem prejuízo das
definições específicas de cada publicador externo:</p>
<p><strong>Não constituem publicação prévia</strong> (obra permanece
inédita):</p>
<ul>
<li><p>Rascunhos, versões preliminares ou work-in-progress em circulação
restrita a membros do Núcleo;</p></li>
<li><p>Apresentações internas em webinars, reuniões de tribo ou reuniões
gerais do Núcleo, sem gravação de acesso público;</p></li>
<li><p>Discussões em boards, cards e canais de comunicação internos da
plataforma (nucleoia.vitormr.dev);</p></li>
<li><p>Relatórios internos de tribo ou de curadoria.</p></li>
</ul>
<p><strong>Constituem publicação prévia</strong> (obra deixa de ser
considerada inédita para efeito editorial):</p>
<ul>
<li><p>Artigos, posts ou papers publicados em blog público, site ou
mídias sociais do Núcleo;</p></li>
<li><p>Apresentações em congressos, seminários ou eventos externos com
registro ou gravação de acesso público (incluindo CBGPL, PMI LIM Summit,
PMI Global Congress, entre outros);</p></li>
<li><p>Obras licenciadas publicamente sob Track A (CC-BY 4.0) ou Track B
(CC-BY-SA 4.0 / MIT / Apache-2.0) antes da submissão ao publicador
externo;</p></li>
<li><p>Preprints depositados em repositórios públicos (arXiv, SSRN,
Zenodo, ResearchGate etc.).</p></li>
</ul>
<p><strong>6.2</strong> Em caso de dúvida sobre enquadramento, o
VOLUNTÁRIO deve consultar o Gerente de Projeto antes da submissão
externa.</p>
<p><strong>6.3</strong> Publicadores externos podem adotar definições
mais restritivas ou permissivas de ineditismo — a política editorial do
destino prevalece sobre esta definição operacional para efeito de
submissão.</p>
<p>7. Regras de Crédito</p>
<p><strong>Autoria:</strong> Autores individuais na ordem de
contribuição substantiva.</p>
<p><strong>Afiliação:</strong> Nome do Autor, Núcleo de Estudos e
Pesquisa em IA &amp; GP — PMI [Capítulo de origem].</p>
<p><strong>Líder de tribo:</strong> Coautor automático se supervisionou
o trabalho e contribuiu intelectualmente.</p>
<p><strong>Gerente de Projeto:</strong> <em>Acknowledgments</em>, não
coautor (exceto se contribuiu intelectualmente).</p>
<p>8. Publicação Externa</p>
<p><strong>Congressos e seminários:</strong> Notificação ao GP com 15
(quinze) dias de antecedência. GP pode solicitar revisão, mas não pode
vetar publicação Track A.</p>
<p><strong>Eventos PMI (CBGPL, Global Congress, LIM Summit,
etc.):</strong> Track A com notificação ao GP e ao presidente do
capítulo de origem.</p>
<p><strong>Webinars internos:</strong> Track A por padrão. Gravações
ficam disponíveis na plataforma.</p>
<p><strong>Periódicos com exigência de exclusividade:</strong>
Aplicam-se os procedimentos de suspensão temporária da licença previstos
na Cláusula 2.6 do Termo de Voluntariado.</p>
<p>9. IP nos Acordos de Cooperação</p>
<p><strong>Multi-capítulo:</strong> Tratamento igualitário entre
voluntários de todos os capítulos.</p>
<p><strong>Obras coletivas:</strong> Lei nº 9.610/1998, art. 5º, VIII,
alínea “h”. Direitos patrimoniais pertencem ao Núcleo como programa.</p>
<p><strong>Saída de capítulo:</strong> Retém uso perpétuo, sem
exclusividade.</p>
<p><strong>Addendum:</strong> Cada Acordo de Cooperação deverá incluir
adendo de IP referenciando esta Política.</p>
<p>10. Acordos com Entidades Internacionais</p>
<p><strong>10.1</strong> Futuros acordos de cooperação ou parceria entre
o Núcleo (representado pelo PMI-GO como capítulo sede) e entidades
internacionais — incluindo, sem limitação, o programa AIPM Ambassadors,
outras seções do PMI globalmente, sociedades acadêmicas estrangeiras e
editoras internacionais — herdarão esta Política como baseline de
propriedade intelectual.</p>
<p><strong>10.2</strong> Divergências entre esta Política e exigências
da entidade parceira serão tratadas por adendo específico ao acordo,
preservando-se os direitos morais dos voluntários (Seção 1.5) e o
tratamento igualitário entre capítulos signatários (Seção 9).</p>
<p><strong>10.3</strong> A negociação de acordos internacionais será
conduzida pelos representantes designados pelo Núcleo. Qualquer cláusula
que altere materialmente esta Política deverá ser submetida à aprovação
prévia do presidente do PMI-GO e notificada aos demais presidentes
signatários com antecedência mínima de 15 (quinze) dias.</p>
<p>11. Material PMI</p>
<p><strong>Restrição:</strong> Material protegido do PMI (PMBOK,
figuras, glossário) NÃO pode ser reproduzido sem permissão.</p>
<p><strong>Citação:</strong> Citação breve (até 650 palavras) com fonte
completa é permitida.</p>
<p><strong>AI Training:</strong> A cláusula “NO AI TRAINING” do PMI deve
ser respeitada integralmente. A proibição aplica-se ao treinamento de
modelos de propósito geral com material PMI como dados de entrada.
Pesquisa acadêmica que cite, analise criticamente ou comente material
PMI como objeto de estudo não constitui uso proibido, sendo permitida
nos limites do art. 46 da Lei nº 9.610/1998 (citação para fins
educacionais e científicos) e das cláusulas de <em>fair use</em>
aplicáveis em jurisdições estrangeiras.</p>
<p>12. Revisão</p>
<p>Esta Política será revisada anualmente ou quando houver mudança
significativa na composição de capítulos, na legislação aplicável ou no
escopo de acordos internacionais. Revisões seguem o processo de Change
Request do Manual Operacional.</p>
<p><em>Draft v2.2 | CR-050 | Núcleo de Estudos e Pesquisa em IA &amp;
GP</em></p>
$html_politica$,
   now(), now(), now(),
   'v2.2: RF-2 IRRF (§4.5.4 e.1-e.4) + RF-3 GDPR (§2.5.1-2.5.7) + Encarregado alignment.')
ON CONFLICT (document_id, version_label) DO NOTHING;

-- Termo R3-C3-IP v2.2
INSERT INTO public.document_versions
  (document_id, version_number, version_label, content_html,
   authored_at, published_at, locked_at, notes)
VALUES
  ('280c2c56-e0e3-4b10-be68-6c731d1b4520', 2, 'R3-C3-IP-v2.2',
   $html_termo$
<p><strong>Termo de Compromisso de Voluntário</strong></p>
<p>Núcleo de Estudos e Pesquisa em Inteligência Artificial e Gestão de
Projetos</p>
<p><em>DRAFT R3-C3-IP v2.2 — Pendente validação jurídica e aprovação
CR-050</em></p>
<p>Capítulos: PMI-GO (sede), PMI-CE, PMI-DF, PMI-MG, PMI-RS</p>
<p><strong>Nota de versão:</strong> Este draft incorpora as revisões do
CR-050 ao Termo R3-C3 vigente. Alterações principais em relação ao
R3-C3-IP v1 (draft anterior): (i) substituição integral da Cláusula 2
por cinco subcláusulas (2.1 a 2.5) com enquadramento jurídico correto
para direitos autorais (9.610), software (9.609) e propriedade
industrial (9.279); (ii) inclusão da Cláusula 2.6 (publicação externa
com exigência de exclusividade) — mecanismo de suspensão temporária da
licença; (iii) ressalva na Cláusula 4 para compatibilizar com a Política
de Publicação; (iv) inclusão da Cláusula 13 (lei aplicável e jurisdição)
para escopo internacional do Programa; (v) correção de referência
jurídica (Art. 51 da Lei 9.610, que trata do prazo de cinco anos para
cessão de obras futuras — no draft anterior havia referência incorreta
ao “Art. 49 §4º”).</p>
<p><strong>Nota v2.0 → v2.1 (19/Abr/2026):</strong> Incorporados os
ajustes do parecer de auditoria jurídica pré-ratificação: (i)
refinamento da Cláusula 2.2.2 para deixar explícito que a suspensão
temporária prevista na 2.6 não constitui revogação da licença; (ii)
cross-reference da Cláusula 2.4 indicando prevalência da 2.6 para
publicações com exigência de exclusividade; (iii) nova Cláusula 2.6.7 —
autorização expressa para cessão exclusiva ao publicador durante o
período de suspensão; (iv) nova Cláusula 2.6.8 — restabelecimento
antecipado da licença em caso de rejeição ou desistência; (v) nota final
na Cláusula 2.6 estendendo o mecanismo para casos de incompatibilidade
CC-BY-SA → CC-BY; (vi) novo §2 da Cláusula 9 explicitando a posição do
VOLUNTÁRIO como titular de dados pessoais perante o PMI-GO como
controlador (LGPD Art. 7º V e Art. 18); (vii) parágrafo único da
Cláusula 11 sobre revogação do consentimento ao uso de imagem.</p>
<p><strong>Nota v2.1 → v2.2 (20/Abr/2026):</strong> Incorporados os
ajustes da curadoria final pré-submissão ao jurídico do Ivan: (i)
alinhamento terminológico do Encarregado pela Proteção de Dados Pessoais
no §1 da Cláusula 9 (remoção do acrônimo “DPO” e uso consistente de
“Encarregado” conforme art. 5º, VIII, LGPD); (ii) inclusão da Cláusula
14 (Consentimento para Transferência Internacional de Dados),
renderizada condicionalmente pela plataforma apenas para VOLUNTÁRIOS
residentes em Estados-membros da União Europeia, nos termos do Art.
49(1)(a) do Regulamento (UE) 2016/679 (GDPR).</p>
<p><strong>Cláusula 1.</strong> O VOLUNTÁRIO declara que está ciente e
que aceitou os termos da Lei do Serviço Voluntário, Lei nº 9.608, de 18
de fevereiro de 1998, com redação atualizada pela Lei nº 13.297, de 16
de junho de 2016, anexa a este termo, sendo que:</p>
<ul>
<li><p>(a) O {chapterName} não terá qualquer vínculo trabalhista,
previdenciário, fiscal e/ou financeiro com o VOLUNTÁRIO;</p></li>
<li><p>(b) Da mesma forma, qualquer parceiro do {chapterName} que venha
a ter atividades desenvolvidas junto ao VOLUNTÁRIO, não terá, por razão
destas atividades, qualquer vínculo trabalhista, previdenciário, fiscal
e/ou financeiro com o VOLUNTÁRIO;</p></li>
<li><p>(c) O {chapterName} não se obriga a comprar, alugar, instalar,
disponibilizar e/ou manter qualquer tipo de equipamento ou sistemas que
venham a ser utilizados pelo VOLUNTÁRIO na execução das atividades
voluntárias.</p></li>
</ul>
<p>Cláusula 2. Propriedade Intelectual</p>
<p>Os direitos sobre obras intelectuais produzidas pelo VOLUNTÁRIO no
âmbito do Programa seguem as regras abaixo:</p>
<p><strong>2.1 Direitos Morais.</strong> O VOLUNTÁRIO retém todos os
direitos morais sobre suas obras, incluindo os direitos de paternidade,
crédito e integridade, conforme a Lei nº 9.610/1998, Art. 24 a 27, e,
quando aplicável, conforme a legislação de direitos morais da jurisdição
de residência do VOLUNTÁRIO, reconhecendo-se o padrão mais protetivo ao
autor em caso de divergência, nos termos da Convenção de Berna. Esses
direitos são inalienáveis e irrenunciáveis.</p>
<p><strong>Parágrafo único.</strong> No caso específico de programa de
computador, aplicam-se os direitos morais na extensão prevista pelo art.
2º, §1º, da Lei nº 9.609/1998, que assegura ao VOLUNTÁRIO o direito de
reivindicar a paternidade do programa e de opor-se a alterações não
autorizadas que impliquem deformação, mutilação ou modificação que
prejudiquem sua honra ou reputação.</p>
<p><strong>2.2 Licença ao Núcleo.</strong> O VOLUNTÁRIO concede ao
Núcleo de Estudos e Pesquisa em IA &amp; GP licença não-exclusiva,
gratuita e mundial para reproduzir, distribuir, exibir publicamente,
criar obras derivadas e sublicenciar <strong>cada obra</strong>
produzida no âmbito do Programa — exclusivamente para fins educacionais
e científicos.</p>
<p><strong>2.2.1</strong> A licença prevista no caput é outorgada
<strong>no momento da entrega ou publicação interna de cada obra
específica</strong> e vigorará pelo prazo de proteção legal da obra
aplicável em cada jurisdição, não caracterizando cessão de obras futuras
em bloco, nos termos do art. 51 da Lei nº 9.610/1998.</p>
<p><strong>2.2.2</strong> A licença é <strong>não-revogável
unilateralmente pelo VOLUNTÁRIO após a sua outorga por obra
específica</strong>, ressalvada a suspensão temporária prevista na
Cláusula 2.6 (Publicação Externa com Exigência de Exclusividade), que
não constitui revogação da licença mas regime transitório de
não-exercício pelo Núcleo, e as hipóteses legais de resolução
contratual.</p>
<p><strong>2.3 Direito de Publicação.</strong> O VOLUNTÁRIO mantém o
direito de publicar individualmente ou em coautoria as obras produzidas,
desde que inclua atribuição ao Núcleo conforme a Política de Publicação
e Propriedade Intelectual vigente.</p>
<p><strong>2.4 Notificação.</strong> Publicações externas de obras
produzidas no Programa requerem notificação prévia ao Gerente de Projeto
com 15 (quinze) dias de antecedência, exceto para conteúdo classificado
como confidencial (Cláusula 9). O GP pode solicitar revisão, mas não
pode vetar publicação de conteúdo Track A (Aberto). Quando a publicação
externa envolver exigência de exclusividade pelo publicador, aplicam-se
adicionalmente os procedimentos da Cláusula 2.6, que prevalece sobre
esta Cláusula no que for específico.</p>
<p><strong>2.5 Enquadramento Jurídico das Obras.</strong> Os direitos
sobre as obras produzidas pelo VOLUNTÁRIO no âmbito do Programa seguem o
enquadramento legal aplicável à natureza de cada obra:</p>
<p><strong>2.5.1 Obras literárias, científicas, artísticas, frameworks,
metodologias, templates e documentos em geral</strong> são protegidos
como direitos autorais, nos termos da Lei nº 9.610/1998,
independentemente de registro (art. 18 da Lei nº 9.610/1998).</p>
<p><strong>2.5.2 Programas de computador</strong> (códigos-fonte e
objeto) são protegidos pelo regime de direitos autorais, nos termos da
Lei nº 9.609/1998, observadas as especificidades do art. 2º, §1º, quanto
aos direitos morais (Cláusula 2.1, parágrafo único, deste Termo).</p>
<p><strong>2.5.3 Invenções, modelos de utilidade, desenhos industriais e
marcas</strong> passíveis de proteção industrial seguem a Lei nº
9.279/1996. A avaliação de patenteabilidade ou registrabilidade deve
preceder qualquer divulgação pública, sob pena de perda da novidade
exigida pelo art. 11 da Lei nº 9.279/1996. O fluxo de análise,
aprovação, titularidade, custeio e política de exploração segue o
disposto na Seção 4 da Política de Publicação e Propriedade
Intelectual.</p>
<p><strong>2.5.4 Registros internacionais</strong> equivalentes em
jurisdições estrangeiras observam os tratados vigentes no Brasil e a
Seção 4.6 da Política de Publicação.</p>
<p><strong>2.6 Publicação Externa com Exigência de
Exclusividade.</strong> Caso o VOLUNTÁRIO pretenda submeter obra
produzida no âmbito do Programa a periódico científico, editora ou
evento que exija, como condição de aceitação, cessão exclusiva de
direitos patrimoniais ou ineditismo da obra, aplica-se o seguinte
procedimento:</p>
<p><strong>2.6.1</strong> O VOLUNTÁRIO notificará o Gerente de Projeto
com antecedência mínima de 15 (quinze) dias, indicando: (a) a obra
objeto da publicação; (b) o periódico, editora ou evento de destino; (c)
a política editorial exigida (exclusividade, cessão, ineditismo); (d) o
prazo estimado de embargo editorial.</p>
<p><strong>2.6.2</strong> Mediante a notificação, a licença concedida ao
Núcleo sobre aquela obra específica entra em <strong>regime de suspensão
temporária (</strong><em>standby</em><strong>)</strong> pelo prazo
necessário ao cumprimento das exigências editoriais, não excedendo 24
(vinte e quatro) meses renováveis por igual período mediante nova
notificação.</p>
<p><strong>2.6.3</strong> Durante o período de suspensão, o Núcleo
compromete-se a não publicar, distribuir ou criar obras derivadas
daquela obra específica, preservando-se, contudo, os direitos do Núcleo
sobre obras anteriores, simultâneas ou derivadas já em circulação.</p>
<p><strong>2.6.4</strong> Findo o período de exclusividade editorial ou
cessando a exigência que a motivou, a licença ao Núcleo é
<strong>automaticamente restabelecida</strong> em seus termos originais,
devendo o VOLUNTÁRIO comunicar o fim do embargo ao Gerente de
Projeto.</p>
<p><strong>2.6.5</strong> O VOLUNTÁRIO obriga-se a incluir, na
publicação externa, nota de agradecimento ao Núcleo de Estudos e
Pesquisa em IA &amp; GP como origem institucional da pesquisa, na forma
mais ampla permitida pela política editorial de destino, ou, caso vedada
pelo publicador, a registrar a vinculação ao Núcleo na página de perfil
do autor no próprio publicador ou em repositório pessoal de acesso
público equivalente.</p>
<p><strong>2.6.6</strong> A suspensão temporária não se aplica a
publicações sob Track A (Aberto) da Política de Publicação, que seguem
fluxo de notificação simples sem necessidade de standby.</p>
<p><strong>2.6.7 Autorização para cessão exclusiva ao
publicador.</strong> Durante o período de suspensão temporária previsto
nas subcláusulas anteriores, o VOLUNTÁRIO fica autorizado a outorgar ao
publicador externo os direitos de exclusividade exigidos como condição
editorial, incluindo cessão exclusiva de direitos patrimoniais sobre a
obra específica pelo prazo do embargo. A licença do Núcleo, embora não
extinta, não será exercida nesse período (Cláusula 2.6.3), de modo que a
exclusividade concedida ao publicador seja factualmente operante.</p>
<p><strong>2.6.8 Restabelecimento antecipado.</strong> Em caso de
rejeição da submissão pelo publicador ou desistência do VOLUNTÁRIO antes
do término do prazo de embargo, o VOLUNTÁRIO comunicará imediatamente ao
Gerente de Projeto, e a licença ao Núcleo será automaticamente
restabelecida na data dessa comunicação, sem aguardar o término do prazo
original de suspensão.</p>
<p><strong>2.6.9 Incompatibilidade entre licenças abertas.</strong> O
mecanismo desta Cláusula aplica-se também às hipóteses de
incompatibilidade de licença aberta entre o Track B (CC-BY-SA 4.0) e a
licença exigida pelo publicador externo (CC-BY 4.0 ou equivalente
não-SA), mediante autorização específica nos termos da Seção 5 da
Política de Publicação e Propriedade Intelectual (Re-licenciamento para
periódicos).</p>
<p>Cláusulas Gerais</p>
<p><strong>Cláusula 3.</strong> O VOLUNTÁRIO, por sua vez, tem direito
ao reconhecimento oficial de seu trabalho de acordo com as
responsabilidades efetivamente assumidas e as tarefas efetivamente
executadas.</p>
<p><strong>Cláusula 4.</strong> O VOLUNTÁRIO não poderá emitir
conceitos, falar ou utilizar o nome ou documentos do {chapterName} sem a
prévia autorização do {chapterName}, ressalvadas as seguintes
hipóteses:</p>
<p><strong>Parágrafo único.</strong> Não constitui violação desta
cláusula:</p>
<ul>
<li><p>(a) A inclusão de atribuição institucional ao Núcleo de Estudos e
Pesquisa em IA &amp; GP e ao capítulo de origem do VOLUNTÁRIO em
publicações enquadradas nas Tracks A, B ou C da Política de Publicação,
observados os respectivos fluxos de notificação ou aprovação previstos
na referida Política;</p></li>
<li><p>(b) A menção institucional ao capítulo em contextos acadêmicos,
científicos ou profissionais relacionados às atividades voluntárias do
VOLUNTÁRIO no âmbito do Programa, desde que consistente com o Código de
Ética do Project Management Institute;</p></li>
<li><p>(c) As demais hipóteses expressamente previstas na Política de
Publicação e Propriedade Intelectual vigente.</p></li>
</ul>
<p><strong>Cláusula 5.</strong> O VOLUNTÁRIO deverá agir sempre em
conformidade com as políticas e os padrões éticos e procedimentais do
PMI, e seguir todas as normas internas e do ordenamento jurídico
aplicável quando do exercício de suas atividades.</p>
<p><strong>Cláusula 6.</strong> A rescisão do compromisso do VOLUNTÁRIO
com o {chapterName} pode ser feita em qualquer tempo, e sem qualquer
ônus para ambas as partes.</p>
<p><strong>Cláusula 7.</strong> O VOLUNTÁRIO poderá ser ressarcido pelas
despesas que comprovadamente realizar no desempenho das atividades
voluntárias, desde que previamente autorizadas pelo {chapterName} e
conforme políticas do {chapterName} em vigor.</p>
<p><strong>Parágrafo único —</strong> As despesas a serem ressarcidas
deverão estar expressamente autorizadas pela entidade a que for prestado
o serviço voluntário.</p>
<p><strong>Cláusula 8.</strong> O presente Termo tem validade
indeterminada ou até o rompimento conforme disposto na Cláusula 6.</p>
<p><strong>Cláusula 9. Confidencialidade e LGPD.</strong> A Lei Geral de
Proteção de Dados Pessoais — Lei nº 13.709, de 14 de agosto de 2018
(LGPD) — dispõe que quaisquer dados de terceiros e/ou informações
pessoais que possam ser obtidas ou utilizadas por qualquer das partes em
decorrência do presente contrato, serão recolhidos, utilizados,
armazenados e mantidos de acordo com os padrões geralmente aceitos para
coleta de dados e pela legislação aplicável. O VOLUNTÁRIO se obriga
a:</p>
<ul>
<li><p>(a) Tratar os dados conforme sua necessidade ou obrigatoriedade,
respeitando os princípios da finalidade, adequação, transparência, livre
acesso, segurança, prevenção e não discriminação;</p></li>
<li><p>(b) Manter sigilo de todos os dados, informações científicas e
técnicas obtidas por meio da prestação de serviço voluntário;</p></li>
<li><p>(c) Não revelar, reproduzir ou dar conhecimento a terceiros de
dados, informações ou materiais obtidos;</p></li>
<li><p>(d) Não tomar qualquer medida com vistas a obter para si ou para
terceiros os direitos de propriedade intelectual relativos às
informações sigilosas a que tenha acesso;</p></li>
<li><p>(e) Utilizar as informações confidenciais apenas com o propósito
de cumprir com os fins do programa voluntário;</p></li>
<li><p>(f) Manter procedimentos adequados à prevenção de extravios ou
perda de documentos ou informações confidenciais.</p></li>
</ul>
<p><strong>§ 1º</strong> O {chapterName} não disponibiliza informações
para bancos de dados, empresas ou associações. O Encarregado pela
Proteção de Dados Pessoais (Encarregado), designado pelo PMI-GO nos
termos do art. 5º, VIII, da Lei nº 13.709/2018 (LGPD), atua como ponto
focal para o Núcleo, nos termos da Seção 2 da Política de Publicação e
Propriedade Intelectual.</p>
<p><strong>§ 2º Direitos do VOLUNTÁRIO como titular de dados
pessoais.</strong> O PMI Brasil–Goiás Chapter (PMI-GO), na condição de
controlador, trata os dados pessoais do próprio VOLUNTÁRIO para fins de
execução deste Termo, tendo como base legal o art. 7º, V, da Lei nº
13.709/2018 (LGPD — execução de contrato). O VOLUNTÁRIO, na qualidade de
titular, tem direito de acesso, retificação, eliminação, portabilidade e
revogação de consentimento referentes aos seus dados pessoais,
exercíveis junto ao Encarregado designado pelo PMI-GO, na forma da Seção
2 da Política de Publicação e Propriedade Intelectual e dos arts. 17 e
18 da LGPD. Os dados pessoais do VOLUNTÁRIO serão retidos pelo prazo de
vigência deste Termo, acrescido de 5 (cinco) anos após seu encerramento
para fins de cumprimento de obrigações legais e prestação de contas
institucionais, conforme a Política de Privacidade do PMI-GO.</p>
<p><strong>Cláusula 10.</strong> O presente Termo estabelece e consolida
as obrigações do VOLUNTÁRIO relativas à confidencialidade, ao sigilo de
informações e à proteção de dados pessoais, nos termos da Lei nº
13.709/2018 (LGPD), sendo suficiente para reger tais matérias no âmbito
do programa de voluntariado.</p>
<p><strong>Cláusula 11.</strong> Ao assinar este Termo o VOLUNTÁRIO
autoriza a utilização de fotos ou imagens profissionais captadas em
evento para divulgação e promoção do trabalho voluntário.</p>
<p><strong>Parágrafo único.</strong> O VOLUNTÁRIO poderá revogar a
autorização prevista nesta Cláusula a qualquer tempo, mediante
comunicação ao Gerente de Projeto ou ao Encarregado do PMI-GO, sem
efeito retroativo sobre usos já realizados, nos termos do art. 8º, §5º,
da Lei nº 13.709/2018.</p>
<p><strong>Cláusula 12.</strong> Não se estabelece entre as partes
qualquer forma de sociedade, associação, mandato, representação,
agência, consórcio ou responsabilidade solidária.</p>
<p>Cláusula 13. Lei Aplicável e Jurisdição</p>
<p><strong>13.1</strong> Este Termo é regido pela legislação brasileira,
em especial pelas Leis nº 9.608/1998, nº 9.609/1998, nº 9.610/1998, nº
9.279/1996 e nº 13.709/2018, bem como pelo Código de Ética do Project
Management Institute e pelos tratados internacionais de propriedade
intelectual vigentes no Brasil.</p>
<p><strong>13.2</strong> Para VOLUNTÁRIOS residentes fora do Brasil,
aplica-se a legislação brasileira, observado o princípio do tratamento
nacional da Convenção de Berna, preservando-se os direitos morais do
VOLUNTÁRIO no padrão mais protetivo entre a legislação brasileira e a
legislação da jurisdição de sua residência.</p>
<p><strong>13.3</strong> Controvérsias decorrentes deste Termo seguem o
disposto na Seção 1.7 da Política de Publicação e Propriedade
Intelectual do Núcleo.</p>
<p>Cláusula 14. Consentimento para Transferência Internacional de Dados
(Voluntários Residentes na União Europeia)</p>
<p><strong>Nota sobre renderização:</strong> Esta Cláusula é exibida
condicionalmente pela plataforma apenas quando o VOLUNTÁRIO declarar, em
seu perfil, residência em Estado-membro da União Europeia. Para
VOLUNTÁRIOS residentes no Brasil ou em jurisdições fora da UE, esta
Cláusula não é aplicável e não é renderizada no ato da assinatura.</p>
<p><strong>14.1</strong> Para VOLUNTÁRIOS residentes em Estados-membros
da União Europeia, ao assinar este Termo o VOLUNTÁRIO consente
expressamente, nos termos do Art. 49(1)(a) do Regulamento (UE) 2016/679
(GDPR), com a transferência de seus dados pessoais para servidores
localizados no Brasil, operados pelo PMI Brasil–Goiás Chapter (PMI-GO),
reconhecendo que:</p>
<ul>
<li><p>(a) O Brasil não possui, à data desta assinatura, decisão de
adequação emitida pela Comissão Europeia nos termos do Art. 45 do
GDPR;</p></li>
<li><p>(b) A proteção aplicada aos dados pessoais observa os padrões da
Lei nº 13.709/2018 (LGPD) brasileira e os princípios de proteção
equivalente da Convenção de Berna e do GDPR, conforme descrito na Seção
2.5 da Política de Publicação e Propriedade Intelectual;</p></li>
<li><p>(c) O VOLUNTÁRIO mantém os direitos de acesso, retificação,
eliminação, portabilidade, oposição e limitação do tratamento garantidos
pelos Arts. 15 a 21 do GDPR, exercíveis junto ao Encarregado designado
pelo PMI-GO (Cláusula 9, §1º);</p></li>
<li><p>(d) O VOLUNTÁRIO pode revogar este consentimento a qualquer
tempo, nos termos do Art. 7(3) do GDPR, sem efeito retroativo sobre
tratamentos já realizados, mediante comunicação ao Encarregado do
PMI-GO. A revogação pode implicar impossibilidade de continuidade do
vínculo voluntário quando o tratamento dos dados for essencial à
execução deste Termo.</p></li>
</ul>
<p><strong>14.2</strong> Esta Cláusula complementa a Cláusula 9 e o §2º
nela contido, aplicando-se especificamente à base legal Art. 49(1)(a) do
GDPR, em adição à base Art. 49(1)(b) do GDPR (necessidade contratual)
prevista na Seção 2.5.3 da Política de Publicação e Propriedade
Intelectual.</p>
<p><em>Draft R3-C3-IP v2.2 | CR-050 | Núcleo de Estudos e Pesquisa em IA
&amp; GP</em></p>
<p><em>Alterações em relação ao R3-C3 (termo vigente): Cláusula 2
integralmente substituída; Cláusula 4 com parágrafo único de ressalvas;
Cláusula 9 com atualização do Encarregado e §2 novo (direitos do
voluntário como titular LGPD); Cláusula 11 com parágrafo único
(revogação consentimento imagem); Cláusula 13 incluída; Cláusula 14
incluída (renderização condicional para residentes UE — GDPR Art.
49(1)(a)).</em></p>
$html_termo$,
   now(), now(), now(),
   'v2.2: Cláusula 9 §1 Encarregado + nova Cláusula 14 (GDPR Art. 49(1)(a) condicional UE).')
ON CONFLICT (document_id, version_label) DO NOTHING;

-- Adendo Retificativo v2.2
INSERT INTO public.document_versions
  (document_id, version_number, version_label, content_html,
   authored_at, published_at, locked_at, notes)
VALUES
  ('d2b7782c-dc1a-44d4-a5d5-16248117a895', 2, 'v2.2',
   $html_retif$
<p><strong>Adendo Retificativo ao Termo de Compromisso de
Voluntariado</strong></p>
<p>Núcleo de Estudos e Pesquisa em Inteligência Artificial e Gestão de
Projetos</p>
<p><em>DRAFT v2.2 — Pendente validação jurídica | CR-050</em></p>
<p>Capítulos: PMI-GO (sede), PMI-CE, PMI-DF, PMI-MG, PMI-RS</p>
<p><strong>Nota v2.0 → v2.1 (19/Abr/2026):</strong> Incorporados os
ajustes do parecer de auditoria jurídica pré-ratificação: (i)
refinamento da Cláusula 2.2 do Art. 3 para deixar explícito que a
suspensão temporária da 2.6 não constitui revogação; (ii)
cross-reference da Cláusula 2.4 indicando prevalência da 2.6 para
publicações com exigência de exclusividade; (iii) novas subcláusulas
2.6.7 e 2.6.8 na Cláusula 2.6 do Art. 3 (autorização cessão exclusiva +
restabelecimento antecipado); (iv) extensão do mecanismo 2.6 para
incompatibilidade CC-BY-SA → CC-BY; (v) substituição integral do Art. 4
— incorporação direta das disposições de lei aplicável e jurisdição
(antes referenciadas ao R3-C3-IP v2.0, não assinado pelos 52
voluntários); (vi) reformulação do Art. 5 para substituir explicitamente
a Cláusula 4 do Termo Original, incorporando as hipóteses (a), (b) e (c)
de não-violação.</p>
<p><strong>Nota v2.1 → v2.2 (20/Abr/2026):</strong> Incorporados os
ajustes da curadoria final pré-submissão ao jurídico do Ivan: (i)
padronização tipográfica do termo “suspensão temporária
(<em>standby</em>)” no Art. 3 subcláusula 2.6.2; (ii) inclusão do Art. 8
(Consentimento para Transferência Internacional de Dados), renderizado
condicionalmente pela plataforma apenas para VOLUNTÁRIOS residentes em
Estados-membros da União Europeia, nos termos do Art. 49(1)(a) do
Regulamento (UE) 2016/679 (GDPR); (iii) atualização das referências de
versão (v2.1 → v2.2 em todas as marcações, incluindo Termo R3-C3-IP e
Política de Publicação de referência).</p>
<p>O presente Adendo Retificativo integra e complementa o Termo de
Compromisso de Voluntariado (doravante <strong>Termo Original</strong>)
firmado entre o VOLUNTÁRIO e o Capítulo signatário no âmbito do Núcleo
de Estudos e Pesquisa em Inteligência Artificial e Gestão de Projetos.
As disposições deste Adendo prevalecem sobre aquelas anteriormente
estabelecidas no Termo Original, no que houver conflito.</p>
<p>Art. 1 — Objeto</p>
<p>Este Adendo tem por objeto retificar a Cláusula 2 (Propriedade
Intelectual) do Termo Original, substituindo-a integralmente pela nova
redação constante do Art. 3 abaixo, em razão de necessidade de adequação
à legislação brasileira (Leis nº 9.610/1998, nº 9.609/1998, nº
9.279/1996, nº 9.608/1998 e nº 13.709/2018), aos tratados internacionais
de propriedade intelectual vigentes no Brasil, ao Código de Ética do
Project Management Institute e à natureza multi-capítulo e transnacional
do Programa.</p>
<p>Art. 2 — Redação Original (sendo retificada)</p>
<p><strong>CLÁUSULA 2 DO TERMO ORIGINAL</strong></p>
<blockquote>
<p><em>“Todos os direitos sobre produtos e serviços desenvolvidos pelo
voluntário serão cedidos ao PMI Goiás por prazo indeterminado.”</em></p>
</blockquote>
<p><strong>Fragilidades jurídicas identificadas:</strong></p>
<ul>
<li><p>(i) Direitos morais são inalienáveis (Lei nº 9.610/1998, Art.
24-27) — cessão total é juridicamente ineficaz quanto à parte
moral;</p></li>
<li><p>(ii) A cessão de obras futuras por prazo indeterminado é limitada
a 5 (cinco) anos, nos termos do art. 51 da Lei nº 9.610/1998;</p></li>
<li><p>(iii) Cessão genérica (“todos os direitos”) sem especificação é
interpretada restritivamente (art. 4º da Lei nº 9.610/1998);</p></li>
<li><p>(iv) Atribui propriedade intelectual a um único capítulo (PMI-GO)
quando o programa é multi-capítulo (PMI-GO, PMI-CE, PMI-DF, PMI-MG,
PMI-RS);</p></li>
<li><p>(v) Utiliza enquadramento jurídico inadequado para software e
documentos, que são protegidos por direito autoral (Leis nº 9.610/1998 e
nº 9.609/1998), não por propriedade industrial (Lei nº
9.279/1996).</p></li>
</ul>
<p>Art. 3 — Nova Redação da Cláusula 2</p>
<p><strong>PROPRIEDADE INTELECTUAL</strong></p>
<p>Os direitos sobre obras intelectuais produzidas pelo VOLUNTÁRIO no
âmbito do Programa seguem as regras abaixo:</p>
<p><strong>2.1 Direitos Morais.</strong> O VOLUNTÁRIO retém todos os
direitos morais sobre suas obras, incluindo os direitos de paternidade,
crédito e integridade, conforme a Lei nº 9.610/1998, Art. 24 a 27, e,
quando aplicável, conforme a legislação de direitos morais da jurisdição
de residência do VOLUNTÁRIO, reconhecendo-se o padrão mais protetivo ao
autor em caso de divergência, nos termos da Convenção de Berna. Esses
direitos são inalienáveis e irrenunciáveis.</p>
<p><strong>Parágrafo único.</strong> No caso específico de programa de
computador, aplicam-se os direitos morais na extensão prevista pelo art.
2º, §1º, da Lei nº 9.609/1998, que assegura ao VOLUNTÁRIO o direito de
reivindicar a paternidade do programa e de opor-se a alterações não
autorizadas que impliquem deformação, mutilação ou modificação que
prejudiquem sua honra ou reputação.</p>
<p><strong>2.2 Licença ao Núcleo.</strong> O VOLUNTÁRIO concede ao
Núcleo de Estudos e Pesquisa em IA &amp; GP licença não-exclusiva,
gratuita e mundial para reproduzir, distribuir, exibir publicamente,
criar obras derivadas e sublicenciar <strong>cada obra</strong>
produzida no âmbito do Programa — exclusivamente para fins educacionais
e científicos. A licença é outorgada no momento da entrega ou publicação
interna de cada obra específica e vigorará pelo prazo de proteção legal
da obra aplicável em cada jurisdição, não caracterizando cessão de obras
futuras em bloco, nos termos do art. 51 da Lei nº 9.610/1998. A licença
é não-revogável unilateralmente pelo VOLUNTÁRIO após a sua outorga por
obra específica, ressalvada a suspensão temporária prevista na
subcláusula 2.6, que não constitui revogação da licença mas regime
transitório de não-exercício pelo Núcleo, e as hipóteses legais de
resolução contratual.</p>
<p><strong>2.3 Direito de Publicação.</strong> O VOLUNTÁRIO mantém o
direito de publicar individualmente ou em coautoria as obras produzidas,
desde que inclua atribuição ao Núcleo conforme a Política de Publicação
e Propriedade Intelectual vigente.</p>
<p><strong>2.4 Notificação.</strong> Publicações externas de obras
produzidas no Programa requerem notificação prévia ao Gerente de Projeto
com 15 (quinze) dias de antecedência, exceto para conteúdo classificado
como confidencial (cláusula 9 do Termo Original). O GP pode solicitar
revisão, mas não pode vetar publicação de conteúdo Track A (Aberto).
Quando a publicação externa envolver exigência de exclusividade pelo
publicador, aplicam-se adicionalmente os procedimentos da subcláusula
2.6, que prevalece sobre esta no que for específico.</p>
<p><strong>2.5 Enquadramento Jurídico das Obras.</strong> Os direitos
sobre as obras produzidas pelo VOLUNTÁRIO no âmbito do Programa seguem o
enquadramento legal aplicável à natureza de cada obra, nos termos da
Política de Publicação e Propriedade Intelectual, observando-se:</p>
<ul>
<li><p>(a) Obras literárias, científicas, artísticas, frameworks,
metodologias, templates e documentos em geral — Lei nº 9.610/1998
(Direitos Autorais);</p></li>
<li><p>(b) Programas de computador — Lei nº 9.609/1998, observadas as
especificidades do art. 2º, §1º, quanto aos direitos morais;</p></li>
<li><p>(c) Invenções, modelos de utilidade, desenhos industriais e
marcas — Lei nº 9.279/1996, com avaliação de patenteabilidade
antecedendo qualquer divulgação pública (art. 11 da Lei nº
9.279/1996);</p></li>
<li><p>(d) Registros internacionais equivalentes observam os tratados
vigentes no Brasil.</p></li>
</ul>
<p><strong>2.6 Publicação Externa com Exigência de
Exclusividade.</strong> Caso o VOLUNTÁRIO pretenda submeter obra
produzida no âmbito do Programa a periódico científico, editora ou
evento que exija, como condição de aceitação, cessão exclusiva de
direitos patrimoniais ou ineditismo da obra, aplicam-se os seguintes
procedimentos:</p>
<p><strong>2.6.1</strong> O VOLUNTÁRIO notificará o Gerente de Projeto
com antecedência mínima de 15 (quinze) dias, indicando: (a) a obra
objeto da publicação; (b) o periódico, editora ou evento de destino; (c)
a política editorial exigida (exclusividade, cessão, ineditismo); (d) o
prazo estimado de embargo editorial.</p>
<p><strong>2.6.2</strong> Mediante a notificação, a licença concedida ao
Núcleo sobre aquela obra específica entra em <strong>regime de suspensão
temporária (<em>standby</em>)</strong> pelo prazo necessário ao
cumprimento das exigências editoriais, não excedendo 24 (vinte e quatro)
meses renováveis por igual período mediante nova notificação.</p>
<p><strong>2.6.3</strong> Durante o período de suspensão, o Núcleo
compromete-se a não publicar, distribuir ou criar obras derivadas
daquela obra específica, preservando-se, contudo, os direitos do Núcleo
sobre obras anteriores, simultâneas ou derivadas já em circulação.</p>
<p><strong>2.6.4</strong> Findo o período de exclusividade editorial ou
cessando a exigência que a motivou, a licença ao Núcleo é
automaticamente restabelecida em seus termos originais, devendo o
VOLUNTÁRIO comunicar o fim do embargo ao Gerente de Projeto.</p>
<p><strong>2.6.5</strong> O VOLUNTÁRIO obriga-se a incluir, na
publicação externa, nota de agradecimento ao Núcleo de Estudos e
Pesquisa em IA &amp; GP como origem institucional da pesquisa, na forma
mais ampla permitida pela política editorial de destino, ou, caso vedada
pelo publicador, a registrar a vinculação ao Núcleo na página de perfil
do autor no próprio publicador ou em repositório pessoal de acesso
público equivalente.</p>
<p><strong>2.6.6</strong> A suspensão temporária não se aplica a
publicações sob Track A (Aberto) da Política de Publicação, que seguem
fluxo de notificação simples sem necessidade de standby.</p>
<p><strong>2.6.7 Autorização para cessão exclusiva ao
publicador.</strong> Durante o período de suspensão temporária previsto
nas subcláusulas anteriores, o VOLUNTÁRIO fica autorizado a outorgar ao
publicador externo os direitos de exclusividade exigidos como condição
editorial, incluindo cessão exclusiva de direitos patrimoniais sobre a
obra específica pelo prazo do embargo. A licença do Núcleo, embora não
extinta, não será exercida nesse período (subcláusula 2.6.3), de modo
que a exclusividade concedida ao publicador seja factualmente
operante.</p>
<p><strong>2.6.8 Restabelecimento antecipado.</strong> Em caso de
rejeição da submissão pelo publicador ou desistência do VOLUNTÁRIO antes
do término do prazo de embargo, o VOLUNTÁRIO comunicará imediatamente ao
Gerente de Projeto, e a licença ao Núcleo será automaticamente
restabelecida na data dessa comunicação, sem aguardar o término do prazo
original de suspensão.</p>
<p><strong>2.6.9 Incompatibilidade entre licenças abertas.</strong> O
mecanismo desta Cláusula aplica-se também às hipóteses de
incompatibilidade de licença aberta entre o Track B (CC-BY-SA 4.0) e a
licença exigida pelo publicador externo (CC-BY 4.0 ou equivalente
não-SA), mediante autorização específica nos termos da Seção 5 da
Política de Publicação e Propriedade Intelectual (Re-licenciamento para
periódicos).</p>
<p>Art. 4 — Lei Aplicável e Jurisdição</p>
<p>Este Adendo e o Termo Original ao qual se vincula são regidos pela
legislação brasileira, em especial pelas Leis nº 9.608/1998, nº
9.609/1998, nº 9.610/1998, nº 9.279/1996 e nº 13.709/2018, bem como pelo
Código de Ética do Project Management Institute e pelos tratados
internacionais de propriedade intelectual vigentes no Brasil (Convenção
de Berna — Decreto nº 75.699/1975; Acordo TRIPS — Decreto nº
1.355/1994).</p>
<p><strong>§ 1º</strong> Para VOLUNTÁRIOS residentes fora do Brasil,
aplica-se a legislação brasileira, observado o princípio do tratamento
nacional da Convenção de Berna (Art. 5.1), preservando-se os direitos
morais do VOLUNTÁRIO no padrão mais protetivo entre a legislação
brasileira e a legislação da jurisdição de sua residência.</p>
<p><strong>§ 2º</strong> Controvérsias decorrentes deste Adendo ou do
Termo Original serão resolvidas prioritariamente por conciliação interna
mediada pelo Gerente de Projeto e pelos presidentes dos capítulos
envolvidos. Persistindo o conflito, o foro de eleição é a Comarca de
Goiânia/GO, ressalvado que, em casos envolvendo VOLUNTÁRIOS residentes
no exterior ou entidades internacionais, as partes poderão optar, em
instrumento específico, por: (i) arbitragem conforme regras da Câmara de
Comércio Internacional (ICC) ou de câmara arbitral brasileira; (ii)
submissão ao PMI Ethics Review Committee, quando a matéria envolver
conduta ética profissional; ou (iii) foro da Comarca de Goiânia/GO com
opção por processo em língua inglesa ou portuguesa, nos termos da Seção
1.7 da Política de Publicação e Propriedade Intelectual do Núcleo.</p>
<p>Art. 5 — Retificação da Cláusula 4 do Termo Original</p>
<p>A Cláusula 4 do Termo Original, que dispõe que “o VOLUNTÁRIO não
poderá emitir conceitos, falar ou utilizar o nome ou documentos do
{chapterName} sem a prévia autorização do {chapterName}”, passa a
vigorar com o seguinte parágrafo único:</p>
<p><strong>Parágrafo único.</strong> Não constitui violação desta
cláusula:</p>
<ul>
<li><p>(a) A inclusão de atribuição institucional ao Núcleo de Estudos e
Pesquisa em IA &amp; GP e ao capítulo de origem do VOLUNTÁRIO em
publicações enquadradas nas Tracks A, B ou C da Política de Publicação,
observados os respectivos fluxos de notificação ou aprovação previstos
na referida Política;</p></li>
<li><p>(b) A menção institucional ao capítulo em contextos acadêmicos,
científicos ou profissionais relacionados às atividades voluntárias do
VOLUNTÁRIO no âmbito do Programa, desde que consistente com o Código de
Ética do Project Management Institute;</p></li>
<li><p>(c) As demais hipóteses expressamente previstas na Política de
Publicação e Propriedade Intelectual vigente.</p></li>
</ul>
<p>Art. 5-A — Demais Cláusulas</p>
<p>As demais cláusulas do Termo Original permanecem inalteradas e em
pleno vigor.</p>
<p>Art. 6 — Vigência</p>
<p>Este Adendo entra em vigor na data de sua assinatura e permanece
vigente enquanto durar o Termo Original ao qual está vinculado.</p>
<p>Art. 7 — Assinaturas</p>
<p>Assinado pelo VOLUNTÁRIO e pelo representante legal do Capítulo de
origem (presidente ou procurador), em formato digital via plataforma
nucleoia.vitormr.dev ou DocuSign.</p>
<p>___________________________________________</p>
<p>[Nome do Voluntário] PMI ID: [XXXXXX] | Capítulo: [PMI-XX]</p>
<p>___________________________________________</p>
<p>[Nome do Presidente] Presidente | [Nome do Capítulo] | CNPJ:
[XX.XXX.XXX/XXXX-XX]</p>
<p>Art. 8 — Consentimento para Transferência Internacional de Dados
(Voluntários Residentes na União Europeia)</p>
<p><strong>Nota sobre renderização.</strong> Este Artigo é exibido
condicionalmente pela plataforma apenas quando o VOLUNTÁRIO declarar, em
seu perfil, residência em Estado-membro da União Europeia. Para
VOLUNTÁRIOS residentes no Brasil ou em jurisdições fora da UE, este
Artigo não é aplicável e não é renderizado no ato da assinatura.</p>
<p><strong>§ 1º</strong> Para VOLUNTÁRIOS residentes em Estados-membros
da União Europeia, ao assinar este Adendo o VOLUNTÁRIO consente
expressamente, nos termos do Art. 49(1)(a) do Regulamento (UE) 2016/679
(GDPR), com a transferência de seus dados pessoais para servidores
localizados no Brasil, operados pelo PMI Brasil–Goiás Chapter (PMI-GO),
reconhecendo que:</p>
<ul>
<li><p>(a) O Brasil não possui, à data desta assinatura, decisão de
adequação emitida pela Comissão Europeia nos termos do Art. 45 do
GDPR;</p></li>
<li><p>(b) A proteção aplicada aos dados pessoais observa os padrões da
Lei nº 13.709/2018 (LGPD) brasileira e os princípios de proteção
equivalente da Convenção de Berna e do GDPR, conforme descrito na Seção
2.5 da Política de Publicação e Propriedade Intelectual (v2.2);</p></li>
<li><p>(c) O VOLUNTÁRIO mantém os direitos de acesso, retificação,
eliminação, portabilidade, oposição e limitação do tratamento garantidos
pelos Arts. 15 a 21 do GDPR, exercíveis junto ao Encarregado designado
pelo PMI-GO;</p></li>
<li><p>(d) O VOLUNTÁRIO pode revogar este consentimento a qualquer
tempo, nos termos do Art. 7(3) do GDPR, sem efeito retroativo sobre
tratamentos já realizados, mediante comunicação ao Encarregado do
PMI-GO. A revogação pode implicar impossibilidade de continuidade do
vínculo voluntário quando o tratamento dos dados for essencial à
execução deste Adendo e do Termo Original.</p></li>
</ul>
<p><strong>§ 2º</strong> Este Artigo complementa o tratamento de dados
pessoais previsto no Termo Original (Cláusula 9) e na Seção 2.5 da
Política de Publicação e Propriedade Intelectual, aplicando-se
especificamente à base legal Art. 49(1)(a) do GDPR, em adição à base
Art. 49(1)(b) do GDPR (necessidade contratual).</p>
<p><em><strong>Termo Original:</strong> Termo de Compromisso de
Voluntariado — Ciclo [ANO], Código de Verificação
[TERM-XXXX-XXXXXX]</em></p>
<p><em><strong>Change Request:</strong> CR-050 — Revisão da Cláusula de
Propriedade Intelectual e Adoção de Política de Publicação</em></p>
<p><em><strong>Política de referência:</strong> Política de Publicação e
Propriedade Intelectual do Núcleo de IA &amp; GP (v2.2)</em></p>
<p><em><strong>Termo revisado de referência:</strong> Termo de
Voluntariado R3-C3-IP v2.2</em></p>
<p><em>Draft v2.2 | CR-050 | Núcleo de Estudos e Pesquisa em IA &amp;
GP</em></p>
$html_retif$,
   now(), now(), now(),
   'v2.2: §2.6.2 standby itálico + novo Art. 8 (GDPR Art. 49(1)(a) condicional UE).')
ON CONFLICT (document_id, version_label) DO NOTHING;

-- Adendo Cooperação v2.2
INSERT INTO public.document_versions
  (document_id, version_number, version_label, content_html,
   authored_at, published_at, locked_at, notes)
VALUES
  ('41de16e2-4f2e-4eac-b63e-8f0b45b22629', 2, 'v2.2',
   $html_coop$
<p><strong>Adendo de Propriedade Intelectual aos Acordos de Cooperação
Bilateral</strong></p>
<p>Núcleo de Estudos e Pesquisa em Inteligência Artificial e Gestão de
Projetos</p>
<p><em>DRAFT v2.2 — Pendente aprovação dos 5 presidentes |
CR-050</em></p>
<p>Aplica-se aos 4 acordos bilaterais (GO↔︎CE, GO↔︎DF, GO↔︎MG, GO↔︎RS)</p>
<p><strong>Nota v2.0 → v2.1 (19/Abr/2026):</strong> Incorporado ao Art.
6 parágrafo único sobre aprovação tácita por silêncio para depósito de
marcas e patentes (consistente com §1 da Cláusula 4.2.1 da Política
v2.1), dando segurança jurídica à notificação de 15 dias conforme art.
111 do Código Civil.</p>
<p><strong>Nota v2.1 → v2.2 (20/Abr/2026):</strong> Incorporados os
ajustes da curadoria final pré-submissão ao jurídico do Ivan: (i)
explicitação da versão “Internacional” nas licenças Creative Commons
referenciadas no Art. 2 (CC-BY 4.0 Internacional e CC-BY-SA 4.0
Internacional); (ii) inclusão de ressalva no Art. 2 sobre o
re-licenciamento de obras Track B para periódicos científicos previsto
na Seção 5 da Política de Publicação, preservando os direitos
irrevogáveis dos capítulos sobre a versão originalmente publicada pelo
Núcleo; (iii) atualização da referência à Política de Publicação e
Propriedade Intelectual (v2.1 → v2.2).</p>
<p>O presente Adendo integra o Acordo de Cooperação bilateral celebrado
entre os Capítulos signatários e tem por objetivo estabelecer regras
claras de propriedade intelectual para obras produzidas no âmbito do
Núcleo de Estudos e Pesquisa em Inteligência Artificial e Gestão de
Projetos, observados a legislação brasileira, os tratados internacionais
vigentes no Brasil e o Código de Ética do Project Management
Institute.</p>
<p>Art. 1 — Obras Coletivas</p>
<p>Obras intelectuais produzidas por voluntários de múltiplos capítulos
no âmbito do Programa são consideradas obras coletivas, nos termos do
art. 5º, VIII, alínea “h”, da Lei nº 9.610/1998. Os direitos
patrimoniais das obras coletivas pertencem ao Núcleo como programa
interinstitucional, garantido o crédito individual aos autores conforme
a Política de Publicação e Propriedade Intelectual.</p>
<p>Art. 2 — Direito de Uso Irrevogável</p>
<p>Cada capítulo signatário tem direito irrevogável de uso das obras
produzidas durante sua participação no Programa, incluindo reprodução,
distribuição e criação de derivados para fins educacionais e
científicos, conforme licenciamento definido na Política de Publicação e
Propriedade Intelectual (Track A: CC-BY 4.0 Internacional; Track B:
CC-BY-SA 4.0 Internacional ou MIT/Apache-2.0; Track C: proprietário, com
acesso definido no ato do registro).</p>
<p><strong>Parágrafo único — Re-licenciamento Track B para periódicos
científicos.</strong> O re-licenciamento de obras Track B para
periódicos científicos ou repositórios de código que exijam licença
CC-BY 4.0 Internacional (ou equivalente não-SA) ou MIT/Apache-2.0 como
condição de publicação, nos termos da Seção 5 da Política de Publicação
e Propriedade Intelectual (Re-licenciamento para periódicos), não afeta
os direitos de uso irrevogável dos capítulos signatários sobre a versão
originalmente publicada pelo Núcleo sob a licença Track B. A versão
submetida ao publicador externo é tratada como produto editorial
específico, preservando-se integralmente os direitos dos capítulos sobre
a versão institucional de origem.</p>
<p>Art. 3 — Saída de Capítulo</p>
<p>Em caso de saída de capítulo (aviso prévio de 30 dias conforme Acordo
de Cooperação), o capítulo retém direito de uso perpétuo das obras
criadas durante sua participação, sem exclusividade. Novas obras
produzidas após a saída não geram direito para o capítulo que deixou o
Programa.</p>
<p>Art. 4 — Direitos Morais</p>
<p>Os direitos morais dos autores individuais (paternidade, crédito,
integridade) são inalienáveis e irrenunciáveis, conforme Lei nº
9.610/1998, Art. 24 a 27. Nenhuma disposição deste Adendo ou dos Acordos
de Cooperação pode restringir esses direitos. No caso de programa de
computador, aplica-se a extensão específica do art. 2º, §1º, da Lei nº
9.609/1998. Para autores residentes em jurisdições estrangeiras,
observa-se o padrão mais protetivo entre a legislação brasileira e a
legislação local, nos termos da Convenção de Berna.</p>
<p>Art. 5 — Regras de Crédito</p>
<p>Todo output publicado deve incluir:</p>
<ul>
<li><p>(a) Nomes dos autores individuais na ordem de contribuição
substantiva;</p></li>
<li><p>(b) Afiliação institucional no formato: Núcleo de Estudos e
Pesquisa em IA &amp; GP — PMI [Capítulos de origem];</p></li>
<li><p>(c) Líder de tribo como coautor se supervisionou o trabalho e
contribuiu intelectualmente.</p></li>
</ul>
<p>Art. 6 — Registro e Titularidade Formal</p>
<p>Em caso de registro formal de propriedade intelectual (autoral junto
à Fundação Biblioteca Nacional, de software ou industrial junto ao INPI,
ou equivalentes internacionais), o depósito é realizado em nome do PMI
Brasil–Goiás Chapter (PMI-GO), como capítulo sede, nos termos da Seção 4
da Política de Publicação e Propriedade Intelectual, preservados os
direitos morais dos autores individuais, o direito de uso irrevogável
dos demais capítulos signatários (Art. 2) e a notificação prévia aos
demais presidentes signatários com antecedência mínima de 15 (quinze)
dias do ato de depósito.</p>
<p><strong>Parágrafo único — Aprovação tácita por silêncio para marcas e
patentes.</strong> Para depósito de marcas e patentes — ativos de maior
impacto sobre a identidade institucional do Programa — a ausência de
manifestação contrária por escrito de qualquer dos presidentes
signatários no prazo de 15 (quinze) dias contados do recebimento da
notificação importa aprovação tácita, nos termos do art. 111 do Código
Civil. Em caso de manifestação contrária, o depósito será suspenso por
até 30 (trinta) dias para deliberação conjunta entre os presidentes
signatários. Para registros autorais junto à EDA/FBN, mantém-se a
notificação simples sem efeito de aprovação tácita.</p>
<p>Art. 7 — Escopo Internacional e Acordos com Entidades
Estrangeiras</p>
<p>Reconhecida a natureza transnacional do Programa — decorrente da
filiação ao Project Management Institute, entidade global, e da
participação de voluntários residentes em jurisdições estrangeiras — os
Capítulos signatários concordam que futuros acordos de cooperação ou
parceria entre o Núcleo (representado pelo PMI-GO) e entidades
internacionais herdarão a Política de Publicação e Propriedade
Intelectual como baseline, sendo eventuais divergências tratadas por
adendo específico, preservado o tratamento igualitário entre capítulos
signatários.</p>
<p>Art. 8 — Vigência</p>
<p>Este Adendo entra em vigor na data de sua assinatura pelos
representantes dos capítulos e permanece vigente enquanto durar o Acordo
de Cooperação ao qual está vinculado.</p>
<p>Art. 9 — Revisão</p>
<p>Este Adendo será revisado anualmente ou quando houver mudança
significativa na composição de capítulos, na legislação aplicável ou no
escopo de acordos internacionais, seguindo o processo de Change Request
do Manual Operacional.</p>
<p>___________________________________________</p>
<p><strong>Ivan Lourenço</strong> Presidente | PMI Brasil–Goiás Chapter
(PMI-GO)</p>
<p>___________________________________________</p>
<p><strong>[Presidente Capítulo Parceiro]</strong> Presidente | PMI
[XX]</p>
<p><em>Draft v2.2 | Política de referência: Política de Publicação e
Propriedade Intelectual do Núcleo de IA &amp; GP (v2.2) |
CR-050</em></p>
$html_coop$,
   now(), now(), now(),
   'v2.2: Art. 2 CC-BY/CC-BY-SA 4.0 Internacional + parágrafo Track B re-licensing.')
ON CONFLICT (document_id, version_label) DO NOTHING;

-- ---------------------------------------------------------------------------
-- Step 4 — Open new approval_chains v2.2. Unique: (document_id, version_id).
-- Idempotent via WHERE NOT EXISTS guard.
-- ---------------------------------------------------------------------------

-- Política v2.2 chain (5 gates)
INSERT INTO public.approval_chains
  (document_id, version_id, status, gates, opened_at, opened_by, notes)
SELECT
  'cfb15185-2800-4441-9ff1-f36096e83aa8',
  dv.id,
  'review',
  '[{"kind":"curator","order":1,"threshold":1},{"kind":"leader","order":2,"threshold":1},{"kind":"president_go","order":3,"threshold":1},{"kind":"president_others","order":4,"threshold":4},{"kind":"member_ratification","order":5,"threshold":"all"}]'::jsonb,
  now(), NULL,
  'v2.2 chain. Supersede of v2.1 chain acfeece1-cb1b-466d-84ba-d08fda2f7fa0 (ADR-0016).'
FROM public.document_versions dv
WHERE dv.document_id='cfb15185-2800-4441-9ff1-f36096e83aa8' AND dv.version_label='v2.2'
AND NOT EXISTS (
  SELECT 1 FROM public.approval_chains ac WHERE ac.document_id=dv.document_id AND ac.version_id=dv.id
);

-- Termo v2.2 chain (5 gates)
INSERT INTO public.approval_chains
  (document_id, version_id, status, gates, opened_at, opened_by, notes)
SELECT
  '280c2c56-e0e3-4b10-be68-6c731d1b4520',
  dv.id,
  'review',
  '[{"kind":"curator","order":1,"threshold":1},{"kind":"leader","order":2,"threshold":1},{"kind":"president_go","order":3,"threshold":1},{"kind":"president_others","order":4,"threshold":4},{"kind":"member_ratification","order":5,"threshold":"all"}]'::jsonb,
  now(), NULL,
  'v2.2 chain. Supersede of v2.1 chain 2d4015cb-bab5-4a30-910c-01f9da592cf5 (ADR-0016).'
FROM public.document_versions dv
WHERE dv.document_id='280c2c56-e0e3-4b10-be68-6c731d1b4520' AND dv.version_label='R3-C3-IP-v2.2'
AND NOT EXISTS (
  SELECT 1 FROM public.approval_chains ac WHERE ac.document_id=dv.document_id AND ac.version_id=dv.id
);

-- Adendo Retif v2.2 chain (5 gates)
INSERT INTO public.approval_chains
  (document_id, version_id, status, gates, opened_at, opened_by, notes)
SELECT
  'd2b7782c-dc1a-44d4-a5d5-16248117a895',
  dv.id,
  'review',
  '[{"kind":"curator","order":1,"threshold":1},{"kind":"leader","order":2,"threshold":1},{"kind":"president_go","order":3,"threshold":1},{"kind":"president_others","order":4,"threshold":4},{"kind":"member_ratification","order":5,"threshold":"all"}]'::jsonb,
  now(), NULL,
  'v2.2 chain. Supersede of v2.1 chain 24eb9b50-ddc6-4409-a578-3753f4a52240 (ADR-0016).'
FROM public.document_versions dv
WHERE dv.document_id='d2b7782c-dc1a-44d4-a5d5-16248117a895' AND dv.version_label='v2.2'
AND NOT EXISTS (
  SELECT 1 FROM public.approval_chains ac WHERE ac.document_id=dv.document_id AND ac.version_id=dv.id
);

-- Adendo Coop v2.2 chain (3 gates, no member_ratification)
INSERT INTO public.approval_chains
  (document_id, version_id, status, gates, opened_at, opened_by, notes)
SELECT
  '41de16e2-4f2e-4eac-b63e-8f0b45b22629',
  dv.id,
  'review',
  '[{"kind":"curator","order":1,"threshold":1},{"kind":"president_go","order":2,"threshold":1},{"kind":"president_others","order":3,"threshold":4}]'::jsonb,
  now(), NULL,
  'v2.2 chain. Supersede of v2.1 chain 22fbf5a8-593b-485e-b0f7-f94e70d224e1 (ADR-0016).'
FROM public.document_versions dv
WHERE dv.document_id='41de16e2-4f2e-4eac-b63e-8f0b45b22629' AND dv.version_label='v2.2'
AND NOT EXISTS (
  SELECT 1 FROM public.approval_chains ac WHERE ac.document_id=dv.document_id AND ac.version_id=dv.id
);

