# SPEC - Governance Documents End-to-End

> **Status:** Draft para decisao GP/dev - nao implementar sem fechar a matriz de decisoes em #315.
>
> **Data:** 2026-05-23
>
> **Origem:** Auditoria reversa da jornada Frontiers + curadoria + certificados.
>
> **Issues relacionadas:** #96, #171, #181, #301, #308, #310, #311, #312, #314, #315.

## 1. Objetivo

Transformar documentos de governanca em um fluxo canonico ponta a ponta:

1. Documento nasce fora ou dentro da plataforma.
2. GP/admin registra intake auditavel.
3. Conteudo vira `governance_documents` + `document_versions`.
4. Versao e lacrada e revisada por gates adequados.
5. Documento aprovado/vigente fica acessivel aos membros ativos quando a visibilidade permitir.
6. Termos, politicas, templates e certificados referenciam versoes lacradas, nao links soltos.
7. Evidencias de funcao e acoes podem gerar certificados/declaracoes com lastro.

Escopo imediato:

- Guia Editorial Frontiers como caso de aceite.
- Biblioteca de documentos aprovados/vigentes para membros ativos.
- Intake admin para novos documentos/policies.
- Auditoria por persona do fluxo de revisao/comentario/aprovacao.
- Base para bundles de evidencia e certificados funcionais.

Fora de escopo desta spec:

- Reescrever o subsistema atual de approval chains.
- Definir merito juridico dos documentos.
- Abrir arquivos restritos de Drive fora das regras de acesso aprovadas.

## 2. Principios

1. **Plataforma como fonte canonica:** depois de aprovado/lacrado, o documento vigente deve viver na plataforma. Drive/DocuSign ficam como origem, anexo ou evidencia.
2. **Versao antes de link:** termos, politicas, certificados e evidencias devem referenciar `document_versions.id`.
3. **Autor nao e necessariamente submitter:** o intake assistido deve preservar autor/proponente e executor do intake separadamente.
4. **Ciencia nao e assinatura:** leitura/ciencia, ratificacao formal e assinatura legal sao eventos diferentes.
5. **Visibilidade explicita:** todo documento precisa de classe de acesso propria.
6. **Certificado nasce de evidencia travada:** declaracoes nao devem sair de campos mutaveis ou texto livre.
7. **Sem impersonation silenciosa:** acoes em nome de outra pessoa exigem metadado auditavel.

## 3. Arquitetura Atual

Ja existe:

- `governance_documents`: metadados do documento.
- `document_versions`: conteudo versionado/lacrado.
- `approval_chains`: cadeia de aprovacao/ratificacao.
- `approval_signoffs`: aprovacoes, acknowledgements e assinaturas por gate.
- `DocumentVersionEditor`: editor de rascunho, autosave, lock e gate preview.
- `ReviewChainIsland`: revisao, assinatura, recirculacao, PDF/DOCX/auditoria.
- `ClauseCommentDrawer`: comentarios por clausula, notas, resolucao e heranca.
- `ChainAuditReportIsland`: relatorio de auditoria.
- `/governance/document/[id]`: leitura individual de documento vigente.

Gaps confirmados:

- Falta intake UI para criar novo `governance_documents`.
- Falta biblioteca `/governance/documents` para membros ativos.
- Falta taxonomia/visibilidade formal para novos tipos.
- Falta matriz de ciencia/ratificacao/assinatura.
- Falta grafo explicito de dependencia entre versoes de documentos.
- Falta camada generica de evidence bundles para certificados funcionais.

## 4. Fluxo Canonico

### 4.1 Intake

Entrada possivel:

- Google Doc/DOCX em Drive institucional.
- Documento criado diretamente na plataforma.
- Documento DocuSign/externo ja assinado.
- Template vigente a ser registrado.
- Documento de iniciativa, TAP, charter ou guia operacional.

Registro minimo:

- `title`
- `doc_type`
- `status`
- `version`
- `description`
- instrumento/canal alvo: LinkedIn post, LinkedIn Newsletter, blog, revista, documento de governanca, template, outro
- produto derivado quando uma mesma fonte gerar mais de um artefato
- autor/proponente
- submitter/executor do intake
- `submitted_via`
- origem/anexo: file id, URL restrita, tipo, access policy
- `initiative_id`, quando aplicavel
- secoes do Manual relacionadas, quando aplicavel
- dependencias normativas, quando aplicavel
- decisao de visibilidade
- modo de ciencia/ratificacao/assinatura

Resultado esperado:

- Novo `governance_documents`.
- Primeira `document_versions` em draft.
- Redirecionamento para editor de versao.

### 4.2 Draft e Revisao

O editor deve permitir:

- importar/colar conteudo inicial;
- salvar rascunho;
- registrar notas de autoria;
- previsualizar gates;
- lacrar versao;
- abrir approval chain.

Revisores devem conseguir:

- ler versao lacrada;
- comentar por clausula;
- resolver comentarios;
- ver comentarios herdados;
- gerar nova versao quando houver ajuste;
- recircular preservando linhagem.

O modo de revisao deve variar por instrumento:

- LinkedIn post: revisao colaborativa pode ser adequada, pois o produto e curto e iterativo.
- LinkedIn Newsletter/blog: revisao pode misturar comentarios editoriais e curadoria final, com atencao a tamanho, idioma e publico.
- Artigo de revista/publicacao formal: revisao independente/blind entre curadores deve ser suportada para reduzir vies.
- Documento de governanca: comentarios podem ser visiveis por role e devem preservar trilha de decisao.

### 4.3 Aprovacao

Gates devem ser definidos por `doc_type` + politica de visibilidade + impacto:

- curadoria/revisao tecnica;
- ciencia de liderancas;
- aceite do GP/submitter;
- testemunhas/capitulos;
- presidencias, quando aplicavel;
- ciencia ou ratificacao de voluntarios/membros ativos;
- revisor externo, quando aplicavel.

Nenhuma curadoria deve ser considerada pronta sem definicao explicita de instrumento/canal final. O rigor, idioma, tamanho, referencias, trilha de revisao e evidencias mudam conforme o destino.

### 4.4 Publicacao Interna

Depois de aprovado/ativo:

- documento aparece na biblioteca member-facing se a visibilidade permitir;
- rota individual `/governance/document/{id}` renderiza a versao atual;
- documentos relacionados apontam para versoes exatas;
- status anterior vira superseded/withdrawn quando necessario;
- Drive continua como anexo/origem, nao fonte canonica.

### 4.5 Evidencia e Certificados

Eventos relevantes viram itens de evidencia:

- autoria/proposta;
- intake assistido;
- comentario/revisao;
- aprovacao;
- ciencia;
- assinatura;
- publicacao;
- uso como template;
- dependencia normativa.

Certificados/declaracoes devem referenciar:

- evidence bundle travado;
- `document_versions.id` aplicaveis;
- periodo/funcao por V4 engagements/history;
- acoes executadas;
- idioma(s);
- verification code/hash.

## 5. Taxonomia Recomendada

### 5.1 `doc_type`

Recomendacao para #315:

| Tipo | Uso | Visibilidade default | Gate default |
|---|---|---|---|
| `manual` | Manual de Governanca | active members | policy-like |
| `policy` | Politicas gerais | active members ou public | policy-like |
| `ip_policy` | Politica de PI | active members | policy-like |
| `privacy_policy` | Politica de Privacidade/LGPD | public | policy-like |
| `volunteer_term_template` | Template de termo de voluntariado | active members | volunteer-term |
| `cooperation_agreement` | Acordo de cooperacao | scoped | legal/chapter |
| `cooperation_addendum` | Adendo de cooperacao | scoped | legal/chapter |
| `project_charter` | TAP/charter de iniciativa | active members ou initiative-scoped | charter |
| `editorial_guide` | Guia editorial Frontiers e similares | active members | guideline |
| `governance_guideline` | Playbook/guia operacional normativo | active members | guideline |
| `template` | Template aprovado em uso | active members ou role-scoped | template |

Decisao pendente: se `ip_policy` e `privacy_policy` serao subtipos em `metadata` ou novos valores no CHECK constraint.

### 5.2 Status

Recomendacao:

| Status | Significado | Entra na biblioteca? |
|---|---|---|
| `draft` | Criado, ainda nao revisado | Nao |
| `under_review` | Em cadeia ativa de revisao | Apenas para elegiveis |
| `approved` | Aprovado, ainda nao vigente | Opcional, se future-effective |
| `active` | Vigente/canonico | Sim, se visivel |
| `superseded` | Substituido por nova versao | Historico |
| `withdrawn` | Retirado | Historico restrito |
| `revoked` | Revogado por erro/risco | Historico restrito |

Decisao pendente: manter `approved` separado de `active` para vigencia futura.

### 5.3 Visibilidade

Recomendacao:

| Classe | Quem ve | Exemplos |
|---|---|---|
| `public` | qualquer visitante | Privacy Policy |
| `active_members` | membros ativos autenticados | Manual, PI Policy, Frontiers Guide |
| `initiative_scoped` | membros da iniciativa | TAP/charter restrito |
| `role_scoped` | papeis especificos | guias internos de curadoria |
| `legal_scoped` | GP, capitulos, testemunhas, legal signers | acordos/adendos sensiveis |
| `admin_only` | GP/admin | drafts, materiais preparatorios |
| `audit_restricted` | auditoria privilegiada | anexos sensiveis |

## 6. Ciencia, Ratificacao e Assinatura

| Evento | Quando usar | Bloqueia aprovacao? | Evidencia |
|---|---|---:|---|
| Read access | Documento apenas consultivo | Nao | acesso opcional/log |
| `acknowledge` / ciencia | Membros devem tomar conhecimento | Nao, salvo regra explicita | `approval_signoffs.signoff_type=acknowledge` ou registro dedicado |
| Ratificacao | Membros precisam validar formalmente | Sim | `approval_signoffs` + snapshot |
| Assinatura legal | Termo/acordo exige aceite legal | Sim | `approval_signoffs` + `member_document_signatures`/certificado |

Decisao recomendada para Frontiers:

- Guia Frontiers aprovado deve ter acesso para `active_members`.
- Membros ativos recebem ciencia informativa, nao assinatura legal.
- Ciencia pode ser registrada, mas nao deve bloquear vigencia salvo decisao GP.

## 6.1 Instrumento, Produto e Modo de Revisao

Uma mesma fonte pode gerar varios produtos. Exemplo: um texto de tribo pode virar post LinkedIn, LinkedIn Newsletter, artigo de blog, submissao a revista e/ou anexo de documento de governanca. A plataforma deve registrar o produto revisado, nao apenas o arquivo de origem.

Campos recomendados:

- `source_artifact_id`: documento/pasta/board item de origem;
- `target_instrument`: canal ou instrumento final;
- `target_audience`: publico foco;
- `target_language_policy`: EN-only, PT-BR, ES-LATAM, trilingue;
- `target_length_policy`: limite de palavras/caracteres ou formato;
- `review_mode`: collaborative, independent_blind, sequential, governance_commentary;
- `review_round`: rodada de revisao;
- `derived_product_group_id`: agrupa varios produtos derivados da mesma fonte.

Regras recomendadas:

| Instrumento | Modo default | Observacao |
|---|---|---|
| LinkedIn post | collaborative | texto curto; comentarios encadeados ajudam a lapidar |
| LinkedIn Newsletter | sequential ou collaborative | precisa adequar tamanho, idioma e formato da newsletter |
| Blog/Hub article | sequential | editoria + curadoria final |
| Revista/artigo formal | independent_blind | curadores nao veem comentarios uns dos outros ate submeterem parecer inicial |
| Documento de governanca | governance_commentary | comentarios por role e trilha de decisao |
| Template | governance_commentary | foco em versao em uso, dependencias e aprovacao |

Gap de produto: a UI atual nao deve assumir que todo comentario de curadoria e colaborativo. Para artigos formais, o fluxo deve permitir parecer independente antes da consolidacao.

## 7. Biblioteca Member-Facing

Rota canonica:

- `/governance/documents`

Alias opcional:

- `/documents`

Conteudo minimo:

- documentos ativos/vigentes por categoria;
- versao atual;
- status;
- validade/vigencia;
- data de ratificacao;
- relacoes/dependencias;
- templates em uso;
- link para leitura individual;
- link para historico quando permitido.

Nao deve listar:

- drafts;
- anexos restritos;
- documentos `admin_only`;
- under_review fora da audiencia elegivel.

## 8. Dependencias entre Documentos

Criar modelo ou metadata para dependencias por versao:

```json
{
  "depends_on": [
    {
      "document_id": "...",
      "version_id": "...",
      "relationship": "normative_reference"
    }
  ]
}
```

Exemplos:

- Termo de Voluntariado referencia Manual + PI Policy + Privacy Policy.
- Guia Frontiers referencia Manual + PI Policy/CR-050 + ADR-0021.
- Certificado funcional referencia template de certificado + evidence bundle schema.

## 9. Caso de Aceite - Guia Frontiers

Estado desejado:

- Documento cadastrado em `governance_documents`.
- `doc_type`: recomendacao `editorial_guide`.
- Titulo: `Guia Editorial Frontiers in AI & Project Mgmt`.
- Autor/proponente: Fabricio Costa.
- Submitter: GP/admin por intake assistido.
- `submitted_via`: `GP-assisted intake`.
- Fonte: Google Doc/DOCX no Drive institucional como anexo/origem restrita.
- Instrumento: documento de governanca/editorial da iniciativa Frontiers.
- Produtos derivados relacionados: LinkedIn Newsletter e possiveis posts/artigos futuros.
- Status inicial: `draft` ou `under_review`.
- Versao inicial: `v1.0-proposed`.
- Visibilidade pos-aprovacao: `active_members`.
- Ciencia: informativa para membros ativos.
- Dependencias: Manual de Governanca, PI Policy/CR-050, ADR-0021, publication pipeline.

Observacao de curadoria:

- Antes de revisar um conteudo derivado do Guia ou da iniciativa Frontiers, o target precisa estar explicito: LinkedIn post, LinkedIn Newsletter, blog/hub ou revista.
- Se o produto for LinkedIn, tamanho e idioma devem ser validados antes de curadoria profunda.
- Se o produto for revista/artigo formal, o parecer independente/blind entre curadores deve ser considerado para evitar vies de ancoragem.

Ajustes antes de v1.0:

- idioma: EN+PT+ES nativo;
- cadencia: quinzenal;
- vinculo com politica de PI/CR-050;
- declaracoes obrigatorias: uso de IA, consentimento empregador, conflitos de interesse;
- mapeamento de tracks A/B/C da PI;
- restricao para PII/material confidencial/PMI/employer.

## 10. Requisitos por Issue

### #315 - Decisao/spec

- Fechar taxonomia, visibilidade, status, gates e ciencia/ratificacao.
- Definir doc_type do Frontiers.
- Definir se `/documents` sera alias.

### #310 - Intake admin

- Criar tab/CTA para novo documento/policy.
- Suportar intake assistido.
- Criar documento + primeira versao draft.
- Capturar fonte Drive/anexo.
- Validar campos por doc_type.

### #312 - Auditoria de jornada

- Smoke por persona.
- Rotas admin vs member-facing.
- Comentarios, recirculacao e export.
- Casos de ciencia, ratificacao e assinatura.
- Modos de revisao por instrumento: collaborative, sequential, independent_blind e governance_commentary.
- Produto derivado: uma mesma fonte gerando post, newsletter, blog e revista.

### #314 - Biblioteca

- Listar ativos/vigentes.
- Respeitar visibilidade.
- Mostrar versao/dependencias/templates.
- Expor leitura individual.

### #311 - Evidencias/certificados

- Modelar evidence bundle generico.
- Consumir documentos/versoes travadas.
- Gerar declaracoes/certificados por funcao e acao.

## 11. Matriz de Smoke Tests

| Persona | Deve conseguir | Nao deve conseguir |
|---|---|---|
| GP/admin | intake, editar draft, lock, recircular, exportar | impersonar sem metadata |
| Autor/proponente | ver documento e comentarios permitidos | virar submitter automaticamente |
| Curador | revisar/comentar/aprovar quando gateado | abrir anexos sem grant |
| Curador independente | submeter parecer sem ver pareceres pares quando `review_mode=independent_blind` | ser influenciado por comentarios antes do parecer inicial |
| Revisor externo | ler/comentar em modo restrito | assinar/recircular |
| Lider de tribo | ciencia/ratificacao quando elegivel | acessar admin shell se nao autorizado |
| Membro ativo | consultar biblioteca e dar ciencia quando pedido | ver drafts/anexos restritos |
| Auditor privilegiado | export audit trail | alterar documento lacrado |

## 12. Sequencia Recomendada

1. Fechar #315.
2. Implementar #310 com Frontiers como fixture real.
3. Implementar #314 usando documentos ativos existentes.
4. Rodar #312 com pelo menos um documento novo + um documento existente.
5. Evoluir #311/#308 para evidence bundles e certificados.
6. Backfill do corpus atual: Manual, PI, Privacy, Termos, templates, acordos, charters.

## 13. Backfill Inicial

Inventario minimo:

- Manual de Governanca.
- Politica de Propriedade Intelectual.
- Politica de Privacidade/LGPD.
- Termo de Voluntariado template vigente.
- Acordos de Cooperacao e adendos vigentes.
- Project charters/TAPs ativos.
- Guia Editorial Frontiers.
- Produtos derivados da iniciativa Frontiers: LinkedIn Newsletter, post LinkedIn, blog/hub article, revista/artigo formal quando aplicavel.
- Templates institucionais em uso.

Para cada item:

- localizar fonte atual;
- definir doc_type;
- definir visibilidade;
- criar/lacar versao;
- registrar dependencias;
- linkar na biblioteca;
- registrar evidencias/anexos.


## 15. Decisoes Recomendadas e Impacto Tecnico

As decisoes de negocio recomendadas para #315 impactam diretamente DB, frontend, camada semantica e MCP/APIs.

### 15.1 Decisoes adotadas como recomendacao

| Tema | Decisao recomendada | Impacto principal |
|---|---|---|
| Tipo Frontiers | `editorial_guide` | migration em `governance_documents.doc_type`, labels, filtros, gates |
| Guias gerais | `governance_guideline` | evita usar `policy` para playbooks operacionais |
| Visibilidade | classes explicitas | novas colunas/metadata/RPCs de leitura filtrada |
| Status | separar `approved` e `active` | fluxo de vigencia futura e biblioteca correta |
| Ciencia | informativa nao bloqueante para guias | notification/ack flow sem travar vigencia |
| Revisao | por instrumento | modelar `review_mode` e esconder comentarios em `independent_blind` |
| Canal alvo | obrigatorio antes de curadoria profunda | intake/curation validation |
| Produtos derivados | fonte comum + produtos separados | novas entidades ou metadata para `derived_product_group_id` |
| Drive | anexo/origem, nao canonico | artifact metadata + grants, sem depender de URL solta |
| Templates | documentos versionados | templates vigentes referenciam `document_versions` |
| Certificados | evidence bundles travados | schema/RPCs para bundles e verify/public audit |

### 15.2 Impacto no banco de dados

Mudancas provaveis:

1. Expandir `governance_documents.doc_type`:
   - `editorial_guide`
   - `governance_guideline`
   - possivelmente `ip_policy`, `privacy_policy`, `template`

2. Adicionar ou estruturar campos de visibilidade/status:
   - `visibility_class`
   - `effective_from`
   - `effective_until`
   - `approved_at`
   - `approved_by`
   - manter `active` como vigente/canonico

3. Registrar relacoes entre versoes:
   - tabela recomendada: `document_version_dependencies`
   - alternativa menor: `document_versions.metadata.depends_on`

4. Registrar source artifacts:
   - tabela recomendada: `governance_document_artifacts`
   - campos: provider, file_id, url, artifact_type, access_policy, snapshot_hash, revision_id

5. Modelar produtos derivados:
   - tabela recomendada: `content_products` ou extensao de `publication_ideas`
   - campos: source_artifact_id, target_instrument, target_audience, target_language_policy, target_length_policy, review_mode, derived_product_group_id

6. Revisao independente/blind:
   - `curation_reviews` ou `document_comments` precisam suportar visibilidade por rodada/modo;
   - para `independent_blind`, comentarios de pares ficam ocultos ate o parecer inicial do curador ser submetido.

7. Evidence bundles:
   - `evidence_bundles`
   - `evidence_bundle_items`
   - referencias para `document_versions`, `approval_signoffs`, `document_comments`, `curation_review_log`, `publication_ideas`, `board_items`, eventos e engagements V4.

8. Templates vigentes:
   - templates devem apontar para `document_versions.id`;
   - certificados/termos gerados devem snapshotar o template usado.

### 15.3 Impacto em RLS/RPCs

Necessario evitar leitura direta ampla de tabelas. Criar RPCs reader/writer com V4 permissions:

Readers:

- `list_governance_library(p_filters jsonb)`
- `get_governance_document_public(p_document_id uuid)`
- `list_document_dependencies(p_version_id uuid)`
- `list_governance_templates(p_scope text)`
- `list_content_products_for_source(p_source_artifact_id uuid)`
- `get_evidence_bundle(p_bundle_id uuid)`

Writers/admin:

- `create_governance_document_intake(p_payload jsonb)`
- `attach_governance_document_artifact(p_document_id uuid, p_payload jsonb)`
- `set_document_visibility(p_document_id uuid, p_visibility_class text)`
- `activate_document_version(p_version_id uuid, p_effective_from timestamptz)`
- `record_document_acknowledgement(p_document_id uuid, p_version_id uuid)`
- `create_content_product_from_source(p_payload jsonb)`
- `submit_independent_review(p_payload jsonb)`
- `release_blind_reviews(p_review_round_id uuid)`
- `create_evidence_bundle(p_payload jsonb)`
- `lock_evidence_bundle(p_bundle_id uuid)`

Security notes:

- RLS deve filtrar por `visibility_class` + active membership + role/capability.
- `admin_only` e `audit_restricted` nao devem aparecer na biblioteca.
- Drive URLs restritas nao devem vazar em payloads member-facing.
- MCP write tools devem chamar RPCs, nao escrever tabelas diretamente.

### 15.4 Impacto no frontend

Rotas/telas novas ou alteradas:

1. `/admin/governance/documents`
   - nova tab/CTA: Novo documento / Nova politica;
   - wizard de intake;
   - selecao de doc_type, visibilidade, status, canal/produto, fonte Drive;
   - redireciona para editor de versao.

2. `/admin/governance/documents/{docId}/versions/new`
   - usar campos de doc_type/visibilidade;
   - preview de gates por doc_type;
   - avisar se faltam instrumento/canal ou dependencias obrigatorias.

3. `/admin/governance/documents/{chainId}`
   - mostrar autor/proponente e submitter separados;
   - mostrar dependencies/version references;
   - comentarios respeitam `review_mode`;
   - em `independent_blind`, pares ficam ocultos ate submissao inicial.

4. `/governance/documents`
   - biblioteca member-facing;
   - filtros por tipo/status/visibilidade;
   - listar templates vigentes;
   - destacar documento atual vs historico.

5. `/governance/document/{id}`
   - leitura individual mais generica;
   - mostrar versao, vigencia, dependencias e status;
   - sem links restritos indevidos.

6. Curadoria/publicacao
   - intake de produto derivado deve exigir `target_instrument`;
   - UI deve escolher `review_mode` por instrumento;
   - LinkedIn valida tamanho/idioma antes de curadoria profunda;
   - revista/formal article usa independent/blind.

7. Certificados/evidencias
   - admin/member views para evidence bundles;
   - gerar declaracao/certificado a partir de bundle travado;
   - verify page com payload minimo publico.

### 15.5 Impacto na camada semantica

A camada semantica deve expor fatos/dimensoes estaveis para analytics, auditoria e MCP:

Dimensoes:

- `dim_governance_document`
- `dim_document_version`
- `dim_document_type`
- `dim_visibility_class`
- `dim_content_instrument`
- `dim_review_mode`
- `dim_member_function`

Fatos:

- `fact_document_intake`
- `fact_document_review_action`
- `fact_document_signoff`
- `fact_document_acknowledgement`
- `fact_document_publication`
- `fact_content_product_derivation`
- `fact_evidence_bundle_item`
- `fact_certificate_issuance`

Consultas semanticas esperadas:

- quais documentos estao vigentes por tipo;
- quais membros deram ciencia de uma versao;
- quais revisores atuaram em um produto;
- quais acoes sustentam um certificado;
- quais produtos derivaram da mesma fonte;
- quais documentos dependem de uma politica ou template.

### 15.6 Impacto em MCP/APIs

MCP deve cobrir operacoes de governanca sem exigir UI manual para tudo:

Read tools:

- `list_governance_library`
- `get_governance_document`
- `list_governance_document_versions`
- `list_document_dependencies`
- `list_content_products`
- `get_review_status_by_product`
- `get_evidence_bundle`

Write tools:

- `create_governance_document_intake`
- `propose_document_version`
- `lock_document_version` (ja existe)
- `start_document_approval_chain`
- `add_document_comment` (ja existe)
- `submit_independent_review`
- `release_blind_review_round`
- `record_document_acknowledgement`
- `create_content_product_from_source`
- `create_evidence_bundle`
- `lock_evidence_bundle`
- `issue_certificate_from_evidence_bundle`

API principle:

- MCP tools devem ser finos wrappers sobre RPCs auditadas.
- Nao expor service role nem bypassar RLS no client.
- Toda escrita deve gerar audit log e actor real.

### 15.7 Sequencia tecnica sugerida

1. DB foundation:
   - doc_type/status/visibility/dependencies/source artifacts.
2. RPC/RLS:
   - library readers + admin intake writer.
3. Frontend admin:
   - intake tab + editor integration.
4. Frontend member-facing:
   - governance library + document reader hardening.
5. Curadoria products:
   - target instrument + review_mode + blind reviews.
6. Evidence bundles:
   - schema, RPCs, certificate integration.
7. MCP:
   - wrappers para intake, library, review, acknowledgement, evidence.
8. Semantic layer:
   - dims/facts para auditoria e dashboards.

### 15.8 Riscos de arquitetura

- Usar `policy` para tudo cria ambiguidade e dificulta filtros/gates.
- Expor Drive URLs na biblioteca vaza artefatos restritos.
- Implementar revisao colaborativa unica enviesa artigos formais.
- Gerar certificado direto de texto livre enfraquece lastro.
- Separar templates da governanca quebra rastreabilidade de termos.
- Ignorar `approved` vs `active` dificulta vigencia futura.
- MCP write tool direto em tabela pode contornar auditoria.


## 16. Refinamento por Lane Full-Stack

Esta secao transforma a spec em pacotes de trabalho por lane. A regra de coordenacao e: Foundation define contratos de dados/RPC primeiro; Frontend consome somente contratos aprovados; Integration/MCP encapsula RPCs; Governance fecha decisoes e backfill; QA valida persona + regressao.

### 16.1 Lane Foundation - DB, RLS, RPCs

Objetivo: criar o substrato canonico sem depender de UI.

Escopo recomendado:

1. Migration de taxonomia:
   - expandir `governance_documents.doc_type` com `editorial_guide` e `governance_guideline`;
   - decidir se `ip_policy`, `privacy_policy` e `template` entram como `doc_type` ou `metadata.subtype`.

2. Migration de visibilidade/vigencia:
   - `visibility_class text` com CHECK;
   - `effective_from timestamptz`;
   - `effective_until timestamptz`;
   - `approved_at timestamptz`;
   - `approved_by uuid references members(id)`.

3. Dependencias versionadas:
   - preferencia: tabela `document_version_dependencies`;
   - colunas: `source_version_id`, `target_document_id`, `target_version_id`, `relationship`, `required`, `created_by`, `created_at`.

4. Artefatos de origem/anexos:
   - tabela `governance_document_artifacts`;
   - campos: `document_id`, `version_id`, `provider`, `artifact_type`, `file_id`, `folder_id`, `url_redacted`, `access_policy`, `drive_permission_role`, `revision_id`, `snapshot_hash`, `visibility_class`, `created_by`.

5. Produtos derivados:
   - preferencia: nova tabela `content_products` se o produto nao for sempre `publication_ideas`;
   - alternativa: extender `publication_ideas.metadata` para MVP;
   - campos minimos: `source_artifact_id`, `source_document_version_id`, `target_instrument`, `target_audience`, `target_language_policy`, `target_length_policy`, `review_mode`, `derived_product_group_id`, `status`.

6. Revisao blind:
   - se reaproveitar `document_comments`, adicionar conceito de `review_round_id`, `submitted_at`, `visible_after_round_release`;
   - se criar tabela propria, usar `curation_product_reviews` com parecer independente, score, comentarios e release controlado.

7. Evidence bundles:
   - tabelas `evidence_bundles` e `evidence_bundle_items`;
   - status: `draft`, `locked`, `issued`, `revoked`;
   - todo item referencia source table/object + action kind + timestamp + snapshot.

RPCs minimos para Foundation:

- `create_governance_document_intake(p_payload jsonb)`
- `list_governance_library(p_filters jsonb)`
- `get_governance_document_public(p_document_id uuid)`
- `list_document_dependencies(p_version_id uuid)`
- `attach_governance_document_artifact(p_document_id uuid, p_payload jsonb)`
- `record_document_acknowledgement(p_document_id uuid, p_version_id uuid)`
- `create_content_product_from_source(p_payload jsonb)`
- `submit_independent_review(p_payload jsonb)`
- `release_blind_reviews(p_review_round_id uuid)`
- `create_evidence_bundle(p_payload jsonb)`
- `lock_evidence_bundle(p_bundle_id uuid)`

Foundation gates:

- RLS denies direct broad reads for restricted artifacts.
- Library RPC never returns `admin_only` or `audit_restricted` artifacts to ordinary members.
- Intake RPC records real actor and optional proposer/author separately.
- Blind review RPC hides peer comments until release.
- Evidence bundle cannot lock without at least one evidence item.

### 16.2 Lane Frontend - Admin, Member Library, Curadoria

Objetivo: criar UX sobre contratos estaveis, sem inferir regra de negocio no client.

Escopo recomendado:

1. Admin intake tab in `/admin/governance/documents`:
   - wizard: classificacao, autor/proponente, fonte/anexo, visibilidade, dependencias, canal/produto;
   - preview de gates;
   - criar documento e abrir editor de versao.

2. Editor de versao:
   - alertas se faltam dependencias obrigatorias;
   - mostrar source artifacts sem vazar links indevidos;
   - mostrar autor/proponente vs submitter.

3. Review chain:
   - renderizar doc_type, visibilidade e vigencia;
   - comentarios respeitam `review_mode`;
   - modo `independent_blind` bloqueia visualizacao de pareceres pares;
   - callout para instrumento/canal alvo.

4. Biblioteca member-facing `/governance/documents`:
   - filtros por categoria, status, tipo e vigencia;
   - cards para documentos vigentes;
   - secao de templates em uso;
   - links para documentos relacionados;
   - rota opcional `/documents` como alias se #315 aprovar.

5. Produto/curadoria:
   - UI exige `target_instrument` antes de curadoria profunda;
   - validacoes por instrumento: tamanho LinkedIn, idioma, publico, modo de revisao;
   - uma fonte pode ter varios produtos derivados.

6. Evidencias/certificados:
   - tela admin para bundle draft/locked;
   - tela membro para certificados/declaracoes geradas;
   - verify page minima e privacy-preserving.

Frontend gates:

- Nenhuma tela admin-only e usada como destino obrigatorio para membro nao-admin.
- Membro ativo acessa biblioteca sem capability admin.
- Curador independente nao ve comentarios pares antes da submissao/release.
- Links Drive restritos nao aparecem na biblioteca.
- Frontiers passa pelo intake sem SQL manual.

### 16.3 Lane Integration/MCP/API

Objetivo: expor as capacidades via MCP/API sem contornar RLS, audit log ou regras de negocio.

Escopo recomendado:

1. MCP readers:
   - `list_governance_library`
   - `get_governance_document`
   - `list_governance_document_versions`
   - `list_document_dependencies`
   - `list_content_products`
   - `get_review_status_by_product`
   - `get_evidence_bundle`

2. MCP writers:
   - `create_governance_document_intake`
   - `attach_governance_document_artifact`
   - `propose_document_version`
   - `lock_document_version` (existente, revisar contrato)
   - `add_document_comment` (existente, revisar review_mode)
   - `submit_independent_review`
   - `release_blind_review_round`
   - `record_document_acknowledgement`
   - `create_content_product_from_source`
   - `create_evidence_bundle`
   - `lock_evidence_bundle`
   - `issue_certificate_from_evidence_bundle`

3. Drive integration:
   - ferramenta/servico deve registrar file/folder metadata;
   - grants temporarios seguem #301;
   - retorno para membros deve mascarar URL quando visibility nao permitir.

4. Notifications/API:
   - ciencia informativa nao bloqueante;
   - notificacao por persona aponta para `/governance/...` quando nao-admin;
   - admin operations apontam para `/admin/...`.

Integration gates:

- Nenhum MCP writer faz insert/update direto em tabela quando houver RPC canonica.
- Toda acao escreve actor real e audit log.
- Tools retornam payload minimizado para dados sensiveis.
- Testes de manifest/contract cobrem parametros obrigatorios.

### 16.4 Lane Governance - Decisoes, Manual, Corpus e Operacao

Objetivo: fechar regra de negocio e preparar backfill/operacao.

Decisoes a fechar em #315:

1. `doc_type` final para Frontiers: recomendado `editorial_guide`.
2. Se `governance_guideline` entra ja ou fica para segunda fase.
3. Se `ip_policy`/`privacy_policy` sao novos tipos ou subtipos.
4. Alias `/documents`: aprovar ou manter somente `/governance/documents`.
5. Classes de visibilidade e regra default por tipo.
6. Quando `approved` difere de `active`.
7. Modos de ciencia/ratificacao/assinatura por tipo de documento.
8. `review_mode` default por instrumento.
9. Obrigatoriedade de independent/blind para revista/artigo formal.
10. Backfill inicial e ordem de migracao do corpus.

Manual/governance updates:

- Atualizar Manual de Governanca com biblioteca canonica.
- Definir que Drive e fonte/anexo, nao fonte normativa final.
- Definir ciencia vs ratificacao vs assinatura.
- Definir que certificados dependem de evidence bundles.
- Definir regra editorial por instrumento/canal.

Governance gates:

- #315 fechado antes de migrations de taxonomia.
- Frontiers documentado como caso de aceite.
- Backfill list aprovado antes de alterar documentos vigentes.
- Politica de PI/CR-050 alinhada antes de Frontiers ativo.

### 16.5 Lane QA/Audit - Persona, Contratos e Regressao

Objetivo: validar que o fluxo funciona para pessoas reais e nao apenas para admin.

Smoke matrix minima:

1. GP/admin cria Frontiers via intake e abre draft.
2. Fabricio aparece como autor/proponente, mas nao como actor do intake se GP executou.
3. Curador comenta em documento de governanca.
4. Curador em `independent_blind` nao ve parecer par antes de submeter.
5. Roberto/Sarah acessam rotas de curadoria/revisao sem depender de admin indevido.
6. Membro ativo acessa `/governance/documents` e ve docs ativos.
7. Membro ativo nao ve anexos restritos.
8. Ciencia informativa nao bloqueia vigencia do Guia Frontiers.
9. Termo/certificado referencia `document_versions.id` travado.
10. Audit export aponta para a mesma versao do PDF oficial.

Contract tests recomendados:

- RPC library visibility.
- RPC intake actor/proposer separation.
- RPC blind review visibility.
- RPC evidence bundle lock invariants.
- Navigation route access for admin vs member-facing.
- MCP tool schemas for new tools.

Audit evidence:

- PR deve citar spec e issues relacionadas.
- Migration deve ter rollback.
- Release log deve registrar mudanca de governanca.
- Smoke por persona deve ser anexado ao handoff.

### 16.6 Dependencias entre lanes

Ordem recomendada:

1. Governance fecha #315.
2. Foundation cria schema/RPC base.
3. Integration cria MCP wrappers sobre RPCs.
4. Frontend implementa intake e biblioteca usando RPCs.
5. QA valida persona e contratos.
6. Governance executa backfill e atualiza Manual.
7. Evidence/certificates evoluem apos documentos/versionamento estabilizados.

Nao fazer:

- Frontend chamar tabela nova diretamente antes de RPC/RLS.
- MCP escrever direto em tabela.
- Backfill manual sem doc_type/visibility definidos.
- Certificado sair antes de evidence bundle travado.
- Curadoria de artigo formal usar comentarios colaborativos por default.


## 17. Ondas de Implementacao por Sprint

As ondas abaixo sao sequenciais por dependencia, mas podem ter trabalho paralelo dentro da mesma onda quando os contratos estiverem definidos. Cada onda deve virar uma ou mais issues de lane, respeitando p201 parallel-agent model.

### Onda 0 - Decisao e congelamento da spec

> **STATUS: RATIFIED 2026-05-24** — Tier P0 (10/10) + Tier P1 (7/7) closed by PM via GitHub. See **§19** below for the canonical ratification record, three amendments (A1/A2/A3 — `acknowledgement_mode`, `pending_proposer_consent` state, declaration enforcement by instrument), and the Wave 1a footprint. Council pre-review evidence: [#315 comment-4530590590](https://github.com/VitorMRodovalho/ai-pm-research-hub/issues/315#issuecomment-4530590590) and [comment-4530613476](https://github.com/VitorMRodovalho/ai-pm-research-hub/issues/315#issuecomment-4530613476).

Objetivo: fechar #315 antes de qualquer migration ou UI.

Escopo:

- aprovar `doc_type` de Frontiers (`editorial_guide` recomendado);
- decidir `governance_guideline`;
- decidir `ip_policy`/`privacy_policy` como tipo ou subtipo;
- aprovar classes de visibilidade;
- aprovar `approved` vs `active`;
- aprovar ciencia vs ratificacao vs assinatura por tipo;
- aprovar `review_mode` default por instrumento;
- aprovar alias `/documents`;
- aprovar backfill inicial.

Criterios de aceite:

- [ ] #315 tem matriz final de decisoes registrada.
- [ ] Spec atualizada com decisoes finais.
- [ ] Frontiers tem doc_type, visibilidade, review/ack mode definidos.
- [ ] Ordem de backfill aprovada.
- [ ] Issues de implementation por lane criadas ou atualizadas.

Gate de saida:

- Nenhuma lane inicia migration/UI antes da matriz #315 estar fechada.

### Onda 1 - Foundation: schema, RLS e RPC base

Objetivo: criar contratos de dados seguros para todo o fluxo.

Escopo:

- migrations de doc_type/status/visibility/vigencia;
- dependencias entre document_versions;
- artifacts de origem/anexos;
- produtos derivados ou metadata MVP;
- review_mode/blind review primitives;
- RPCs reader/writer minimos;
- RLS e grants.

Criterios de aceite:

- [ ] `editorial_guide` aceito no schema.
- [ ] `visibility_class` filtra biblioteca e artifacts.
- [ ] RPC `create_governance_document_intake` separa actor, submitter e proposer/author.
- [ ] RPC `list_governance_library` nao vaza drafts/admin_only/audit_restricted.
- [ ] RPC de blind review esconde comentarios pares antes do release.
- [ ] Dependencias versionadas podem apontar para Manual/PI/Privacy.
- [ ] Migration tem rollback e tests/contracts.

Gate de saida:

- Frontend e MCP so podem consumir RPCs versionadas desta onda.

### Onda 2 - Admin intake e versionamento operacional

Objetivo: permitir criar documento/policy sem SQL manual e mandar para o editor existente.

Escopo:

- tab/CTA Novo documento / Nova politica;
- wizard de intake;
- captura de fonte Drive/anexo;
- campos de instrumento/produto;
- dependencias normativas;
- preview de gates;
- redirecionamento para editor de versao.

Criterios de aceite:

- [ ] GP cria Guia Frontiers via UI sem SQL manual.
- [ ] Fabricio aparece como autor/proponente; GP como actor/intake submitter.
- [ ] Documento abre em `/admin/governance/documents/{docId}/versions/new`.
- [ ] Source artifact fica registrado sem expor URL indevida.
- [ ] Campos obrigatorios por doc_type bloqueiam cadastro incompleto.
- [ ] i18n PT/EN/ES cobre novos labels.

Gate de saida:

- Frontiers cadastravel como fixture real de QA.

### Onda 3 - Biblioteca member-facing e leitura canonica

Objetivo: documentos aprovados/vigentes ficam consultaveis por membros ativos.

Escopo:

- `/governance/documents`;
- alias `/documents` se aprovado;
- filtros por tipo/status/visibilidade;
- templates vigentes;
- dependencias e documentos relacionados;
- hardening de `/governance/document/{id}`.

Criterios de aceite:

- [ ] Membro ativo acessa biblioteca sem admin permission.
- [ ] Documento ativo aparece com versao, status, vigencia e tipo.
- [ ] Draft/under_review restrito nao aparece indevidamente.
- [ ] Templates em uso aparecem separados dos termos assinados.
- [ ] Links relacionados apontam para versoes canonicas.
- [ ] Drive URLs restritas nao aparecem.
- [ ] Navigation config e permissions matrix atualizadas.

Gate de saida:

- Documentos aprovados ja podem ser usados como referencia em termos/templates/certificados.

### Onda 4 - Curadoria por instrumento e review modes

Objetivo: adequar curadoria ao produto final e reduzir vies em artigo formal.

Escopo:

- `target_instrument` obrigatorio antes de curadoria profunda;
- produtos derivados de uma mesma fonte;
- validacoes LinkedIn/newsletter/blog/revista;
- `review_mode` por instrumento;
- independent/blind review para revista/artigo formal;
- release/consolidacao de pareceres.

Criterios de aceite:

- [ ] Curation product exige instrumento/canal final.
- [ ] Uma fonte pode gerar post, newsletter, blog e revista com trilhas separadas.
- [ ] LinkedIn alerta tamanho/idioma/publico antes de revisao profunda.
- [ ] Revista/formal article oculta pareceres pares ate submissao inicial.
- [ ] Release de blind reviews torna consolidacao visivel para curadoria/GP.
- [ ] Smoke Sarah/Roberto/Fabricio cobre os modos principais.

Gate de saida:

- Curadoria nao depende de comentarios soltos no Google Doc para operar com rigor.

### Onda 5 - MCP/API e automacoes de Drive/notificacao

Objetivo: expor o fluxo para agentes e automacoes sem quebrar auditoria.

Escopo:

- MCP readers/writers sobre RPCs;
- Drive metadata/grants conforme #301;
- notificacoes por persona;
- acknowledgement informativo;
- ferramentas para produtos derivados e reviews.

Criterios de aceite:

- [ ] MCP create intake chama RPC, nao tabela direta.
- [ ] MCP list library respeita visibility_class.
- [ ] Drive grants para curadoria seguem role e prazo definidos.
- [ ] Notifications levam nao-admin para `/governance/...`.
- [ ] Acknowledgement informativo nao bloqueia vigencia.
- [ ] Manifest/tool contract atualizado e testado.

Gate de saida:

- Agentes podem operar governanca documental sem bypass de seguranca.

### Onda 6 - Evidence bundles e certificados funcionais

Objetivo: gerar declaracoes/certificados a partir de lastro travado.

Escopo:

- `evidence_bundles` e `evidence_bundle_items`;
- bundle para curadoria, governanca, editoria, lideranca, autoria;
- lock/revoke/issue;
- certificate/declaration templates versionados;
- verify page privacy-preserving;
- link com engagements V4 e document_versions.

Criterios de aceite:

- [ ] Bundle nao trava sem evidence items.
- [ ] Certificado/declaracao referencia bundle locked + document_versions.
- [ ] Funcao/periodo vem de engagements/history, nao campo mutavel isolado.
- [ ] Verificacao publica mostra minimo necessario.
- [ ] Auditor privilegiado consegue drill-down.
- [ ] Frontiers gera evidence case: autor, intake, revisoes, aprovacao, ciencia.

Gate de saida:

- Certificados funcionais deixam de depender de texto livre/admin manual.

### Onda 7 - Semantic layer, dashboards e backfill do corpus

Objetivo: dar visibilidade operacional e completar migracao dos documentos atuais.

Escopo:

- dims/facts semanticos;
- dashboard de documentos vigentes, pendentes e acknowledgements;
- backfill Manual, PI, Privacy, Termos, acordos, charters, Frontiers, templates;
- relatorio de cobertura de evidencias.

Criterios de aceite:

- [ ] Dashboard lista documentos por status/tipo/visibilidade.
- [ ] Consultas mostram quem deu ciencia/assinou por versao.
- [ ] Backfill inicial concluido ou explicitamente fatiado.
- [ ] Documentos estaticos antigos apontam para fonte canonica.
- [ ] Release log e governance changelog atualizados.

Gate de saida:

- Corpus vigente do Nucleo esta navegavel, versionado e auditavel.

### Ordem resumida

| Onda | Tema | Bloqueia |
|---|---|---|
| 0 | Decisoes #315 | todas |
| 1 | Foundation DB/RLS/RPC | Frontend/MCP |
| 2 | Admin intake | Frontiers cadastro real |
| 3 | Biblioteca | consulta por membros |
| 4 | Curadoria por instrumento | reviews robustos |
| 5 | MCP/API/Drive/notificacao | automacao segura |
| 6 | Evidence/certificates | certificados confiaveis |
| 7 | Semantic/backfill | operacao completa |

## 18. Definition of Done

- [x] #315 aprovado com matriz de decisoes. *(Ratified 2026-05-24 — see §19.)*
- [ ] Frontiers pode ser cadastrado sem SQL manual.
- [ ] Documento aprovado aparece para membros ativos.
- [ ] Termos/templates referenciam versoes travadas.
- [ ] Revisor/curador/lider/membro ativo tem rota correta.
- [ ] PDF/DOCX/auditoria apontam para a mesma versao.
- [ ] Certificados/declaracoes usam evidence bundle travado.
- [ ] Corpus atual inventariado para backfill.

## 19. Wave 0 Ratification State (2026-05-24)

> Ratified by PM via GitHub thread on #315. This section is the canonical record; PR `docs(governance): ratify #315 Wave 0 decision matrix` carried it into main. Full PM response captured at [#315 comment-4530613476](https://github.com/VitorMRodovalho/ai-pm-research-hub/issues/315#issuecomment-4530613476); council pre-review at [comment-4530590590](https://github.com/VitorMRodovalho/ai-pm-research-hub/issues/315#issuecomment-4530590590).

### 19.1 Tier P0 — 10/10 ratified

| Q | Decision | Status |
|---|---|---|
| P0-Q1 | Frontiers `doc_type = editorial_guide` | R |
| P0-Q2 | 5 structural visibility classes (`public` · `active_members` · `legal_scoped` · `admin_only` · `audit_restricted`) + `required_action text NULL` for V4 hook | R |
| P0-Q3 | Atomic `visibility_class IS NULL → DENY` migration (backfill → NOT NULL → fail-closed RLS swap in same tx) | R |
| P0-Q4 | `acknowledgement_mode` per-document (not strictly per-doc_type) | A — see Amendment A1 |
| P0-Q5 | ADR-0004 `organization_id` backfill on existing `governance_documents` / `document_versions` / `approval_chains` / `approval_signoffs` before any new gov DDL | R |
| P0-Q6 | Separate `approved` and `active` statuses + invariant V (status/chain coherence) added to `check_schema_invariants()` | R |
| P0-Q7 | `proposer_consent` signoff row at intake (Option B over Option A `on_behalf_of_member_id` audit column) | A — see Amendment A2 |
| P0-Q8 | Drive `file_id` internal-only; `artifact_handle uuid` is the public surface; SECDEF `request_artifact_access` mediates URL generation | R |
| P0-Q9 | Evidence bundle items via typed sidecar tables + ON DELETE RESTRICT (architectural lock now; implementation in Wave 6) | R |
| P0-Q10 | `closing_gate_signoff_id` + `approved_at` on `governance_documents` (NOT denormalized `approved_by` per ADR-0012) | R |

### 19.2 Tier P1 — 7/7 ratified

| Q | Decision | Final |
|---|---|---|
| P1-Q1 | `ip_policy` / `privacy_policy` as `policy` + `metadata.subtype` | metadata.subtype |
| P1-Q2 | Ship `governance_guideline` doc_type in Wave 1 (alongside `editorial_guide`) | ship Wave 1 |
| P1-Q3 | `metadata.template_role = 'instance' \| 'template'` (avoid `template` as doc_type to prevent naming conflict with `volunteer_term_template`) | template_role |
| P1-Q4 | Drive v1 = plain-text `file_id` + `artifact_handle` only; grant orchestration deferred to #301 / Wave 5 | plain text v1 |
| P1-Q5 | Ratify full 7-declaration list as normative model | A — see Amendment A3 |
| P1-Q6 | Intake Tier 1 = 5 fields (title, doc_type, author_label, visibility_class, description); submitter read-only | R |
| P1-Q7 | Acknowledgement via inline card on biblioteca/documento (not modal, not header badge) | inline card |

### 19.3 Amendments — operationalized into schema deltas

#### Amendment A1 (P0-Q4): `acknowledgement_mode` is per-document, not strictly per-doc_type

Ciência informativa non-blocking for `editorial_guide` / `governance_guideline` / templates operacionais. Binding aceite/ratificação for `ip_policy` / `volunteer_term_template` / `cooperation_agreement` when the document requires formal acceptance. For `privacy_policy`: **context-dependent** — ciência or aceite per coleta/termo context, without presuming legal signature always.

**Schema delta** (lands in Wave 1a.M2):

```sql
ALTER TABLE governance_documents
  ADD COLUMN acknowledgement_mode text NOT NULL
  CHECK (acknowledgement_mode IN ('informational','binding','legal_signature'));
```

Default-per-doc_type table (intake RPC pre-fills; GP can override at intake-time):

| doc_type | Default | Override allowed? |
|---|---|---|
| `editorial_guide` | `informational` | No |
| `governance_guideline` | `informational` | No |
| `manual` | `informational` | Yes (binding allowed for major Manual revisions) |
| `policy` (ip_policy subtype) | `binding` | Yes |
| `policy` (privacy_policy subtype) | **context-dependent** (intake wizard asks "bound to specific coleta/termo?") | Yes |
| `volunteer_term_template` | `binding` | No (legal_signature is upgrade) |
| `cooperation_agreement` | `legal_signature` | No |
| `project_charter` | `informational` | Yes |

#### Amendment A2 (P0-Q7): New status state `pending_proposer_consent`

If the proponente cannot sign on platform at intake time, the intake produces a row in state `pending_proposer_consent`.

**Schema delta** (lands in Wave 1a.M2):

```sql
-- 8 status values
status text NOT NULL CHECK (status IN (
  'draft',
  'pending_proposer_consent',  -- NEW per A2
  'under_review',
  'approved',
  'active',
  'superseded',
  'withdrawn',
  'revoked'
));
```

Status machine:
- Intake without proposer ack → `pending_proposer_consent`.
- Proposer signs in-app OR via offline attestation registered by GP → `draft`.
- `pending_proposer_consent` documents are NOT eligible for `under_review` (enforced via invariant V' or trigger).

Invariant V (P0-Q6) refined: `status IN ('approved','active') → current_ratified_chain_id IS NOT NULL`. Invariant V' (added per A2): `status = 'pending_proposer_consent' → NOT EXISTS (SELECT 1 FROM approval_chains WHERE document_id = id AND status NOT IN ('cancelled'))`.

The intake RPC `create_governance_document_intake` accepts optional `proposer_ack_offline boolean`:
- `true` → immediately creates `proposer_consent` signoff with `signoff_type='acknowledge'`, `metadata->>'method'='offline_gp_attestation'`; status starts at `draft`.
- `false` (default) → status starts at `pending_proposer_consent` until proposer signs in-app.

#### Amendment A3 (P1-Q5): Declaration enforcement varies by target instrument

Full 7-item declaration list ratified as normative model. Enforcement varies per `target_instrument`:
- `linkedin_post`, `linkedin_newsletter`, `blog`: all 7 = `warning` (minimum operational with metadata).
- `formal_article`, `journal_submission`: all 7 = `required` (mandatory pre-submission).
- `governance_document`: `pmi_disclaimer` + `third_party_pii_consent` = `required`; others N/A.

**Schema delta** (architectural lock now; concrete table ships in Wave 4):

```sql
CREATE TABLE content_product_declaration_requirements (
  target_instrument text NOT NULL,
  declaration_kind text NOT NULL CHECK (declaration_kind IN (
    'ai_use',                              -- spec §9
    'employer_consent',                    -- spec §9
    'conflict_of_interest',                -- spec §9
    'originality_no_prior_publication',    -- legal #1
    'periodical_license_acceptance',       -- legal #2
    'pmi_disclaimer',                      -- legal #3
    'third_party_pii_consent'              -- legal #4 (LGPD Art. 9)
  )),
  enforcement_level text NOT NULL CHECK (enforcement_level IN ('warning','required')),
  PRIMARY KEY (target_instrument, declaration_kind)
);
```

Wave 1a reserves a placeholder column `target_instrument text` on the future `content_products` table; concrete enforcement table ships in Wave 4.

### 19.4 Tier P2 — deferred to consuming wave

| Q | Topic | Defer to |
|---|---|---|
| P2-Q1 | `review_mode` defaults per instrument | Wave 4 |
| P2-Q2 | Mandatory `independent_blind` for revista/artigo formal | Wave 4 |
| P2-Q3 | `/documents` alias route | Wave 3 |
| P2-Q4 | Backfill order (Manual → PI → Privacy → Termo → Acordos → Charters → Frontiers → Templates) | Wave 7 |
| P2-Q5 | PI Track A/B/C trilateral protocol (autor / Núcleo / periódico) | Wave 4 OR CR-050 v2 |
| P2-Q6 | Public verify page payload + rate limiting | Wave 6 |
| P2-Q7 | Missing personas (GP-transition / pre-active volunteer / alumni) | Wave 4 |

### 19.5 Wave 1a footprint (post-ratification, ready to scaffold)

Three migrations:

- **1a.M1** — ADR-0004 backfill: ALTER `governance_documents`, `document_versions`, `approval_chains`, `approval_signoffs` add `organization_id` (backfill Núcleo IA org UUID; NOT NULL).
- **1a.M2** — Taxonomy + visibility + status machine + invariants:
  - Extend `doc_type` CHECK with `editorial_guide`, `governance_guideline` (P0-Q1 + P1-Q2).
  - Drop+recreate `status` CHECK with 8 values per A2 + P0-Q6.
  - Add `visibility_class text NOT NULL` (5 values per P0-Q2 — backfill + NOT NULL gate).
  - Add `required_action text NULL` (P0-Q2).
  - Add `acknowledgement_mode text NOT NULL` with default-per-doc_type backfill (A1).
  - Add `effective_from`, `effective_until`, `approved_at`, `closing_gate_signoff_id` (P0-Q6 + P0-Q10).
  - Atomic RLS swap: drop `document_versions_read_published` + create fail-closed variant in same tx (P0-Q3).
  - `check_schema_invariants()` extension: invariant V + V' (P0-Q6 + A2).
- **1a.M3** — Intake + library RPCs:
  - `create_governance_document_intake(p_payload jsonb)` — SECDEF, gates `manage_event` via `can_by_member()`. Accepts 5 Tier-1 fields (P1-Q6) + optional `proposer_ack_offline` (A2). Writes `proposer_consent` signoff per A2; status starts at `draft` or `pending_proposer_consent` accordingly. Contract test asserts FK source columns (SEDIMENT-239b.A).
  - `list_governance_library(p_filters jsonb)` — SECDEF reader, filters by `visibility_class` + active membership. Never returns `admin_only` / `audit_restricted` to non-admin. Forward-defense test asserts `file_id` absence from response shape (P0-Q8).

Wave 1b (deferred to follow-up): `document_version_dependencies`, `governance_document_artifacts` (with `file_id`/`artifact_handle` separation per P0-Q8), `content_products` (or `publication_ideas.metadata` MVP per P1-Q4), `document_comments` blind-review columns (for Wave 4 enforcement of invariant 20 — see C6 in council pre-review).

Out of v1: Wave 5 (MCP/Drive grants), Wave 6 (evidence bundles + certificates), Wave 7 (semantic layer + corpus backfill). Track in cluster narrative; do not pull into v1 sprint.

### 19.6 Wave 1b W4d footprint — reader hardening (p263 #380)

One migration:

- **W4d.M1** — `get_governance_document_reader(p_document_id uuid)` RETURNS jsonb — single-doc SECDEF reader for `/governance/document/[id].astro`. Enforces 3 gates in body (privacy-preserving null-envelope on any block — no oracle between 404 and 403):
  - **Active membership** (mirror `list_governance_library`): `members WHERE auth_id = auth.uid() AND is_active = true` — RAISE `Unauthorized: no active member record` ERRCODE `42501` on miss.
  - **Visibility predicate** (mirror gd_read RLS + p256 M3 reader) — 5-class ladder: `public` and `active_members` → any active member; `legal_scoped` → admin (`manage_member`) OR signer with `member_document_signatures.is_current = true`; `admin_only` → admin; `audit_restricted` → platform admin (`manage_platform`). On block → `{ok:true, document:null, current_version:null}`.
  - **Status default-exclusion** (mirror p262 W4c — 4-status set): non-admin sees only `('active','approved','under_review','superseded')`; `manage_member` bypasses to see all 8 statuses. On block → null-envelope.
  - **Version locked_at HARD-GATE** (mirror `document_versions_read_published` RLS): member view requires `dv.locked_at IS NOT NULL`; admin bypass sees unlocked drafts. When `current_version_id IS NULL` the SELECT is skipped (scalar version locals default to NULL — record-style locals would RAISE "not-yet-assigned").
  - **Payload P0-Q8 forward-defense**: response shape NEVER includes `file_id`, `drive_url`, `pdf_url`, `docusign_envelope_id`, `partner_entity_id`, `content_markdown`, `content_diff_json`, `signed_at`, `signatories`, `parties`. Document object exposes 13 fields (id + title + description + doc_type + status + visibility_class + acknowledgement_mode + effective_from + effective_until + approved_at + current_version_id + current_ratified_version_id). Current_version object exposes 6 fields including `content_html`.
- **Route rewire** — `src/pages/governance/document/[id].astro` drops two table-direct SELECTs (`governance_documents`, `document_versions`) and replaces both with `sb.rpc('get_governance_document_reader', { p_document_id: DOC_ID })` (one round-trip). Loading/error/empty UX states preserved verbatim.

Frontiers smoke (live, post-deploy):
- Vitor admin (`manage_member`) → `document=object` with `status='draft'`, `current_version=null` (Frontiers `current_version_id IS NULL`).
- Non-admin member → `document=null` (status default-exclusion blocks draft).
- Manual R2 (`status=active`, locked version) → non-admin member sees full document + `content_html_length=2167` + 0 forbidden columns in payload.
- Unknown UUID → null-envelope (no oracle).
- Anon/service-role → gate fires (Unauthorized).

Known regression preserved (deferred to W4e #381): curators (`curate_content` without `manage_member`) cannot read drafts through this reader. Dedicated curator-draft-read surface ships in #381. This reader is the **member-safe surface**; curator/reviewer paths continue via `get_document_detail` (composite admin RPC) + chain workflow RPCs.

Invariants: 21/21 violation_count=0 live post-deploy. RPC is a read helper; doesn't mutate governed table state.

Cross-refs: #312 audit umbrella + #315 Governance Documents v1 + #96 Frontiers + #380 (this child W4d) + #379 (W4c GAP-259.A predecessor) + #378 (W4a gate templates) + #377 (W4b sign_proposer_consent) + p256 M2/M3 (RLS + library RPC) + p262 W4c (status default-exclusion).
