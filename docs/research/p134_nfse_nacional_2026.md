# Research — NFS-e Nacional 2026 + libs JS

**Data**: 2026-05-09 · **Wave**: p134 Ω-A council Wave 2 · **Researcher**: research-agent
**Audience**: PM (Vitor) — fiscal compliance Núcleo IA Hub para PMI chapters Brasil

---

## TL;DR (5 lines)

1. **NFS-e Nacional já está em produção** desde 1º-out-2025. Obrigatória para todos os municípios em 1º-jan-2026, e para Simples Nacional em 1º-set-2026 (Resolução CGSN 189/2026).
2. **API REST oficial existe** com Swaggers públicos (`nfse.gov.br/swagger/contribuintesissqn/`), sandbox em `producaorestrita.nfse.gov.br`. Comunicação via mTLS + cert ICP-Brasil A1/A3 + JSON, com XMLDSIG para a NFS-e em si.
3. **Cloudflare Workers SUPORTA mTLS outbound** via `mtls_certificates` binding (PEM format, wrangler upload). Game-changer: a EF de emit-fiscal-doc pode rodar diretamente no Worker sem proxy intermediário.
4. **Libs JS ainda imaturas**: `node-sped-nfse` (kalmonv) tem 8 stars, sem release; `@nfewizard-io/nfse` está oficialmente "em fase de testes" (não usar produção). NFeWizard core é GPL-3 + requer JDK + filesystem (incompatível com Workers).
5. **Recomendação**: **REST API direct contra Receita Federal** (mTLS Workers binding + assinatura XML via Web Crypto). Fallback **PlugNotas/NFE.io** se complexidade XMLDSIG inviabilizar MVP em <4 semanas. Vínculos chapter-by-chapter NÃO necessários (1 cert nacional cobre todos os municípios aderidos).

---

## NFS-e Nacional 2026 status

### Marco regulatório
- **LC 214/2025** (Reforma Tributária) Art. 62 + EC 132/2023 → padrão único nacional NFS-e
- **Resolução CGSN nº 189, 23-abr-2026**: Simples Nacional obrigatório usar Emissor Nacional a partir de 1º-set-2026
- **Penalidade municípios**: suspensão de transferências voluntárias da União em 2026 + perda de participação na arrecadação IBS

### Adesão atual
- 1.463 municípios assinaram convênio até início ago/2025 (291 em uso efetivo mai-jul/2025)
- ~70% das capitais já aderiram (set/2025)
- APIs de **produção restrita (homologação)** + **produção** liberadas oficialmente em **1º-out-2025**

### Documentação técnica oficial (URLs canônicas)
- Portal: `https://www.gov.br/nfse/pt-br`
- Manual API contribuintes (v1.2 out-2025): `https://www.gov.br/nfse/pt-br/biblioteca/documentacao-tecnica/documentacao-atual/manual-contribuintes-emissor-publico-api-sistema-nacional-nfs-e-v1-2-out2025.pdf`
- Manual ADN APIs: `https://www.gov.br/nfse/pt-br/biblioteca/documentacao-tecnica/documentacao-atual/manual-contribuintes-apis-adn-sistema-nacional-nfse.pdf`
- Swagger contribuintes ISSQN: `https://www.nfse.gov.br/swagger/contribuintesissqn/`
- Sandbox/Homologação: `https://www.producaorestrita.nfse.gov.br/EmissorNacional`
- XSD Schemas v1.01 (09-fev-2026): `NFSe-ESQUEMAS_XSD-v1.01-20260209.zip`
- Annex B (Lista NBS2 v1.01 jan-2026) + Annex C (Indicadores Operacionais v1.01)

### Autenticação (CRÍTICO para arquitetura)
- **mTLS obrigatório** com cert ICP-Brasil **A1 (PFX)** ou **A3 (token físico)**
- TLS 1.2+ com mutual authentication
- JSON nas rotas REST + **XML assinado (XMLDSIG W3C, schema xmldsig-core-schema_v1.01.xsd)** dentro do envelope da NFS-e em si
- Schema validation obrigatória (envio + recebimento)
- Logs auditáveis de cada transação

---

## Adesão municipal chapter cities

| City | Chapter PMI | Status NFS-e Nacional | Notes |
|------|-------------|----------------------|-------|
| Goiânia | PMI-GO | **Aderiu** (em vigor 1º-jan-2026, transição até 31-jan-2026) | Continua recebendo no padrão ABRASF até 31/01 como fallback |
| Fortaleza | PMI-CE | **Aderiu** (atualizou emissor conforme NT 007/2026 do CGNFS-e) | Em vigor jan-2026 |
| Brasília (DF) | PMI-DF | **Aderiu híbrido** — mantém ISSnet próprio + share automático com ADN | ABRASF desativado a partir de 1º-jan-2026 |
| Belo Horizonte | PMI-MG | Aderiu (cronograma AMM oficial) | Capitais em 70% já aderiram |
| Porto Alegre | PMI-RS | Provável aderente (confirmar status) | Não enumerado individualmente nos resultados |
| São Paulo | PMI-SP | Provável (orientação SP/Fazenda 2026 publicada) | Verificar URL `prefeitura.sp.gov.br/web/fazenda/w/nfs-e_orientacoes` |
| Rio de Janeiro | PMI-Rio | Não confirmado nos resultados | Confirmar via portal CNM |
| Recife | PMI-PE | **Aderiu cronograma escalonado**: nov-2025 (PF/autônomos), dez-2025 (Simples), jan-2026 (demais) | Modelo gradual |
| Uberlândia | n/a | **Aderiu** (decreto local 17-dez-2025, vigência 1º-jan-2026) | Referência cidade média |

**Coexistência durante 2026**: municípios com sistema próprio (ex: Brasília via ISSnet) podem manter emissão local desde que façam **share automático** com ADN. Modelo ABRASF foi oficialmente encerrado em 1º-jan-2026 (sem mais updates de versão).

**Validação contínua**: portal `https://www.gov.br/nfse/pt-br/municipios/monitoramento-adesoes` é a fonte de verdade para status municipal.

---

## node-sped-nfse deep dive

| Critério | Valor |
|----------|-------|
| GitHub | `kalmonv/node-sped-nfse` |
| Stars / forks | **8 / 2** (muito baixo) |
| Commits totais | 16 |
| Releases publicados | **NENHUM** |
| Linguagem | TypeScript 98.3% |
| License | LICENSE.md presente, tipo não documentado claramente (kalmonv usa MIT no node-sped-nfe gêmeo) |
| Versão npm | Não publicada / pre-release |
| NFS-e Nacional | Foco unificado (DPS + NFSe) — segue layout nacional |
| Workers/Deno compat | Não documentada explicitamente |
| Maturidade | **Pre-release / early-stage** |

**Veredicto**: NÃO confiável para produção fiscal. Sem CHANGELOG, sem release tag, ~16 commits.

---

## NFeWizard-io deep dive

| Critério | Valor |
|----------|-------|
| GitHub | `nfewizard-org/nfewizard-io` |
| Stars / forks | **202 / 33** |
| Versão atual | 1.0.0 (modularizada) |
| Última atividade | jan-2025 (v0.3.1 nota release) |
| License | **GPL-3.0** |
| Node.js | v16+ |
| **Dependências nativas** | **JDK obrigatório** (Java) para schema validation, drivers DB (better-sqlite3, mysql, mysql2, oracledb, tedious, sqlite3, pg-query-stream) |
| Workers compat | **NÃO compatível** (JDK + filesystem + native modules) |
| NFSe sub-package | `@nfewizard-io/nfse` — explicitamente **"em fase de testes, use com cautela em produção"** |

### GPL-3 distribution analysis
- GPL-3 é **copyleft forte**: distribuir software que linka GPL-3 obriga publicação do código sob GPL-3 também
- **Cloudflare Workers JS bundle = "distribuição"?** Sim, a definição GPL-3 cobre "convey" (qualquer transferência de cópia executável) — bundle deployado via wrangler é distribuição.
- **Implicação para Núcleo IA Hub**: se incorporar NFeWizard-io diretamente, o repo `ai-pm-research-hub` (atualmente proprietário) precisaria ser GPL-3 ou uma das compatible licenses (LGPL, AGPL, etc.) — incompatível com modelo SaaS comercial whitelabel.
- **AGPL clause network distribution**: GPL-3 NÃO inclui cláusula AGPL — uso server-side via API SaaS (sem distribuir o JS para o cliente final) **pode** se qualificar como uso interno (fronteira jurídica cinzenta — recomendar parecer Ângelina). NFeWizard-io é GPL-3 puro, não AGPL.
- **Veredicto**: incompatível com Workers (nem chega ao debate de licença) + GPL-3 restringe modelo de negócio. **Descartar.**

---

## Cert A1 PFX in Cloudflare Workers

### Game-changer descoberto
**Cloudflare Workers tem suporte nativo a mTLS outbound** via `mtls_certificates` binding:

```toml
# wrangler.toml
[[mtls_certificates]]
binding = "RECEITA_FEDERAL_CERT"
certificate_id = "<id-from-wrangler-mtls-certificate-upload>"
```

```typescript
// no Worker
await env.RECEITA_FEDERAL_CERT.fetch('https://www.nfse.gov.br/EmissorNacional/api/...', {
  method: 'POST',
  body: JSON.stringify(dpsPayload)
});
// → presenta automaticamente o cert A1 no handshake mTLS
```

### Constraints práticos
- **Formato**: PEM (cert + key separados). PFX/PKCS#12 precisa ser convertido com `openssl pkcs12 -in cert.pfx -clcerts -nokeys -out cert.pem` + `openssl pkcs12 -in cert.pfx -nocerts -nodes -out key.pem`
- **Upload via wrangler**: `wrangler mtls-certificate upload --cert cert.pem --key key.pem`
- **Limitações**:
  - Não funciona se o destino for um zone proxiada Cloudflare (retorna 520) — irrelevante aqui pois `nfse.gov.br` não é Cloudflare
  - Sem rotação dinâmica documentada — rotação cert A1 (validade 1 ano) requer novo upload + redeploy ou multi-binding com fallback
  - Pricing: requer Workers Paid plan (Workers Free não tem mTLS bindings)
- **ICP-Brasil compat**: certs A1 ICP-Brasil são x509 padrão — Workers mTLS não distingue CA. **Funciona.**

### Alternativa node-forge (se precisar parsing in-line)
- `node-forge` tem `pkcs12.pkcs12FromAsn1()` para parse PFX
- **Workers compat**: parcial — `node-forge` usa apenas APIs disponíveis no Workers runtime (sem fs), porém alguns submódulos puxam Node-only. **Verificar bundling com nodejs_compat flag.**
- Use case: parsing local do PFX antes de upload (não no runtime do Worker).

### KMS rotation strategy
- Armazenar PFX original em **R2** (encrypted) ou Workers Secrets
- Cron job mensal: alertar D-30 antes do vencimento → operador faz upload nova versão via wrangler
- Multi-tenant chapters: 1 cert A1 do CNPJ "Núcleo IA Hub" emite NFS-e em qualquer município (cert é da entidade emissora, não do município)

---

## SaaS NF-e BR alternatives

| Tool | API | Pricing (NFSe) | Multi-tenant | NFS-e Nacional | NPO discount |
|------|-----|---------------|--------------|----------------|--------------|
| **PlugNotas (Tecnospeed)** | REST/JSON | Por consulta — sem pricing público | Sim (1.600+ cidades) | Sim (gateway oficial NFSe Nacional) | Não documentado |
| **NFE.io** | REST/JSON | R$ 119/mês (120 docs) + R$ 0,75/doc adicional + setup fee + fidelidade 3 meses | Sim | Sim | Não documentado |
| **eNotas** | REST | A partir de R$ 137/mês | Sim (foco infoprodutos) | Sim | Não documentado |
| **Focus NFe** | REST | "Sem fidelidade, sem setup" — preços variam por volume | Sim | Sim | Não documentado |
| **TransmiteNota** | REST | R$ 15,00 por CNPJ ativo/mês (modelo per-tenant) | Sim explicitamente | Sim | Não documentado |
| **NotaZZ** | REST/SDK | Não documentado público; foco dropshipping/infoproduto | Sim | Verificar | Não documentado |
| **Sienge** | n/a | ERP construção civil — fora do escopo | Não | Sim (módulo) | Não |
| **Tecnospeed (componentes)** | DLL/SDK | Modelo Delphi legado — suporte só Windows | Não | Sim | Não |

### Ranking para Núcleo IA Hub
1. **TransmiteNota** se confirmar: R$ 15/mês por chapter ativo escala linearmente. 8 chapters = R$ 120/mês. **Mais barato e multi-tenant nativo.**
2. **NFE.io** se quiser nome estabelecido + dashboard pronto: R$ 119/mês todos os 8 chapters compartilhando quota — funciona se volume <120 NFs/mês total.
3. **PlugNotas** se quiser robustez Tecnospeed (200 especialistas) — pricing precisa contato comercial.

### Build vs Buy quick math
- **Build (REST direct + Workers mTLS)**: ~3-5 semanas dev (parsing XSD, XMLDSIG, retries, error handling) + R$ 0/mês variável + R$ 200/ano cert A1
- **Buy (PlugNotas/NFE.io)**: ~1 semana integração + R$ 119-150/mês fixo + custo cert A1 também necessário (ainda precisa do cert para auth via SaaS)

**Trade-off chave**: Buy economiza tempo de desenvolvimento mas adiciona dependência terceiro + lock-in (cada provider tem schema próprio). Build alinha com filosofia ADR-0010 ("operational data stays SQL/REST direct").

---

## ONG/associação compliance

### Princípios chave
- **Associações sem fins lucrativos NÃO são obrigadas a emitir NFS-e** quando prestam serviços a **associados** dentro do escopo estatutário (Migalhas, Jusbrasil, IAR Brasil — jurisprudência consolidada)
- **Quando há obrigação**: serviços a **não-associados** + serviços fora do objeto estatutário → emitir NFS-e + recolher ISS
- **Imunidade ISS Art. 150 VI "c" CF**: condicionada a:
  - Não distribuir patrimônio/renda
  - Aplicar recursos no país
  - Manter escrituração completa
  - **CEBAS** (Certificado de Entidade Beneficente de Assistência Social) reforça mas não é estritamente obrigatório para imunidade ISS

### Cenários PMI Chapters
- **Cenário A — Doação/contribuição associativa**: NÃO emite NFS-e (vínculo associativo, não prestação serviço)
- **Cenário B — Patrocínio empresa para evento**: pode ser caracterizado como prestação de serviço (espaço, mídia, branding) → emitir NFS-e (com possível imunidade ISS conforme município) — **Receita Federal e municípios divergem; consultar Ângelina**
- **Cenário C — Venda ingresso evento (curso/treinamento)**: prestação serviço educacional → emitir NFS-e (item 8 lista LC 116/2003, código 8.02 ensino regular ou 8.04 cursos livres)

### Simples Nacional
- Associações **podem** optar por Simples Nacional desde Lei Complementar 147/2014 (ampliou rol)
- Caracteriza-se em **Anexo III** (serviços) ou **Anexo V** (cursos/educação) dependendo da atividade
- **PMI Chapters tipicamente são Anexo III** (treinamento/eventos sem grade fixa equivalente regulamentada MEC)
- Optar por Simples Nacional **automatiza obrigatoriedade** NFS-e Nacional via Resolução CGSN 189/2026 a partir de 1º-set-2026

### Recomendação operacional
- Mapear tipo de receita por chapter (ingresso, patrocínio, doação) → cada tipo tem tratamento fiscal distinto
- Iniciar com **Cenário C (cursos/eventos pagos)** como MVP fiscal → caso uso mais comum + obrigação clara
- Verificar com Ângelina (PMI-GO) o município-a-município se há benefício ISS (ex: Goiânia tem incentivos para entidades culturais)

---

## Recommendation Núcleo IA Hub

### Arquitetura recomendada (ranqueada)

**1ª opção — REST direct + Workers mTLS** (preferida)
- Justificativa: alinha com stack atual (Workers + Supabase), zero dep terceiro, custo marginal ~R$ 200/ano (cert A1), single source of truth para audit
- Esforço: ~4 semanas (XMLDSIG + schema XSD + retry/error)
- Risco: complexidade XMLDSIG (schema W3C) + parsing PFX (resolvido com mTLS binding)

**2ª opção — TransmiteNota como SaaS gateway** (se cronograma apertado)
- Justificativa: R$ 15/mês × 8 chapters = R$ 120/mês escalável; menor risco de bug fiscal
- Esforço: ~1 semana
- Risco: lock-in + dependência uptime terceiro
- **Quando escolher**: se ship antes de set/2026 (Simples Nacional obrigatório) for crítico

**3ª opção — NFE.io plano shared** (se quiser dashboard pronto)
- R$ 119/mês todos chapters → bom para MVP; revisar quando >120 NFs/mês

### Decisão recomendada para PM
- **Iniciar com 2ª opção (TransmiteNota)** como ship rápido para piloto PMI-GO/PMI-CE em 2026
- **Migrar para 1ª opção** quando volume justificar (>500 NFs/mês ou >R$ 300/mês SaaS)
- **Nunca usar libs JS** (`node-sped-nfse` ou `@nfewizard-io/nfse`) — imaturidade documentada + GPL-3 incompat

---

## Architecture sketch

### Edge Function `emit-fiscal-doc` (Supabase EF Deno)

```
┌─────────────────────────────────────────────────────────────┐
│ Caller (Astro SSR / pmi-vep-sync Worker / cron)             │
│   POST { chapter_id, recipient_cpf_cnpj, service_code,      │
│          amount, description }                              │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│ EF emit-fiscal-doc                                          │
│  1. Fetch chapter config from `chapter_fiscal_config` table │
│     (CNPJ emitter, municipal code, ISS rate, tax regime)    │
│  2. Build DPS (Declaração Prestação Serviço) JSON           │
│  3. Sign XML inner block via WebCrypto (XMLDSIG)            │
│  4. Forward to Worker `nfse-bridge` (mTLS binding)          │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│ Worker `nfse-bridge` (Cloudflare, mtls_certificates binding)│
│  - env.RECEITA_CERT.fetch(NFSE_NACIONAL_API)                │
│  - cert A1 ICP-Brasil PEM upload via wrangler               │
│  - Retry/backoff + idempotency key                          │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│ Receita Federal API NFS-e Nacional                          │
│  POST /EmissorNacional/api/v1/dps                           │
│  Returns: { chave_acesso, xml_assinado, pdf_url, status }   │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│ EF persist `fiscal_documents` table                         │
│  { chapter_id, type, chave_acesso, xml, pdf_url,            │
│    recipient, amount, status, issued_at }                   │
│  + row in `fiscal_audit_log` (LGPD compliance)              │
└─────────────────────────────────────────────────────────────┘
```

### 2 tables proposal

```sql
-- Per-chapter fiscal config (multi-tenant ready)
CREATE TABLE chapter_fiscal_config (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES organizations(id),
  cnpj text NOT NULL CHECK (length(cnpj) = 14),
  municipal_inscription text,
  ibge_code text NOT NULL,        -- código IBGE município
  tax_regime text NOT NULL CHECK (tax_regime IN ('simples', 'lucro_presumido', 'imune')),
  iss_rate numeric(5,2),          -- alíquota ISS percentual
  default_service_code text,      -- código LC 116/2003 padrão (ex: '8.02')
  iss_retained_default boolean DEFAULT false,
  cert_binding_id text,           -- ID Workers mTLS binding (ou SaaS API key se opção 2)
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- Emitted documents
CREATE TABLE fiscal_documents (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  chapter_fiscal_config_id uuid NOT NULL REFERENCES chapter_fiscal_config(id),
  document_type text NOT NULL CHECK (document_type IN ('nfse_nacional', 'nfse_municipal_legacy')),
  chave_acesso text UNIQUE,       -- chave 50 dígitos NFS-e Nacional
  recipient_doc text NOT NULL,    -- CPF ou CNPJ (PII — RLS strict)
  recipient_name text,
  service_code text,              -- LC 116
  amount_cents bigint NOT NULL,
  iss_amount_cents bigint,
  description text,
  status text NOT NULL CHECK (status IN ('pending', 'authorized', 'cancelled', 'rejected')),
  xml_signed text,                -- raw XML autorizado (para audit)
  pdf_url text,                   -- URL R2 ou link gov.br
  rejection_reason text,
  issued_at timestamptz,
  cancelled_at timestamptz,
  created_at timestamptz DEFAULT now()
);

ALTER TABLE chapter_fiscal_config ENABLE ROW LEVEL SECURITY;
ALTER TABLE fiscal_documents ENABLE ROW LEVEL SECURITY;
-- Policies via rls_can('manage_fiscal') gate (V4 ADR-0007 pattern)
```

### Multi-client alignment (PMIS-vision-aware)
- `organization_id` segrega cada chapter PMI (PMI-GO, PMI-CE, PMI-DF, etc.)
- 1 cert A1 do "Núcleo IA Hub Brasil" emite para todos chapters (entidade emissora unificada)
- ALT: cada chapter com próprio CNPJ + cert A1 (mais isolamento, custo R$ 200/ano × N chapters)
- **Sustentabilidade module substrato confirmed (handoff_p133)**: tabela `fiscal_documents` integra com Sustentabilidade dashboard (faturamento por chapter, ISS recolhido)

---

## Sources

- [Receita Federal - NFS-e Padrão Nacional Simples Nacional 2026](https://www.gov.br/receitafederal/pt-br/assuntos/noticias/2026/abril/nfs-e-de-padrao-nacional-sera-obrigatoria-para-optantes-do-simples-nacional)
- [Ministério da Fazenda - NFS-e obrigatória 2026](https://www.gov.br/fazenda/pt-br/assuntos/noticias/2025/agosto/a-partir-de-janeiro-de-2026-a-nota-fiscal-de-servico-eletronica-nfs-e-sera-obrigatoria-a-fim-de-simplificar-cotidiano-das-empresas)
- [Portal NFS-e Nacional - API de Integração](https://www.gov.br/nfse/pt-br/municipios/produtos-disponiveis/api-de-integracao)
- [Manual Contribuintes API v1.2 (out-2025)](https://www.gov.br/nfse/pt-br/biblioteca/documentacao-tecnica/documentacao-atual/manual-contribuintes-emissor-publico-api-sistema-nacional-nfs-e-v1-2-out2025.pdf)
- [Documentação Técnica Atual NFS-e Nacional](https://www.gov.br/nfse/pt-br/biblioteca/documentacao-tecnica/documentacao-atual)
- [Monitoramento Adesões Municipais NFS-e](https://www.gov.br/nfse/pt-br/municipios/monitoramento-adesoes)
- [CRC-GO - Goiânia adesão NFS-e Nacional](https://crcgo.org.br/prefeitura-de-goiania-inicia-adocao-do-modelo-nacional-de-nota-fiscal-de-servicos-a-partir-de-outubro/)
- [Distrito Federal NFS-e Nacional 2026](https://www.contabeis.com.br/noticias/74583/df-adota-nfs-e-nacional-a-partir-de-2026/)
- [TOTVS - Goiânia NFS-e Nacional Reforma Tributária](https://www.totvs.com/blog/fiscal-clientes/nfs-e-nacional-goiania-ajusta-padrao-as-regras-exigidas-na-reforma-tributaria/)
- [TOTVS - Fortaleza NFS-e atualização NT 007/2026](https://www.legisweb.com.br/noticia/?id=33233)
- [ABRASF - Encerramento modelo ABRASF para NFS-e Nacional](https://abrasf.org.br/comunicacao/noticias/nova-fase-nfs-e-adesao-ao-modelo-nacional-encerra-atualizacoes-do-modelo-abrasf)
- [NotaGateway - API NFSe Nacional dev guide](https://notagateway.com.br/blog/api-nfse-nacional/)
- [Notaas - API NFSe Nacional integração tech](https://www.notaas.com.br/blog/post/api-nfse-nacional-guia-integracao-tech)
- [Notaas - Comparativo APIs 2026](https://www.notaas.com.br/blog/post/api-nfse-nacional-melhor-provedor-emissao-nota-fiscal-de-servico-eletronica-nacional)
- [Cloudflare Workers mTLS docs](https://developers.cloudflare.com/workers/runtime-apis/bindings/mtls/)
- [Cloudflare blog - mTLS Workers launch](https://blog.cloudflare.com/mtls-workers/)
- [Cloudflare Web Crypto Workers docs](https://developers.cloudflare.com/workers/runtime-apis/web-crypto/)
- [GitHub kalmonv/node-sped-nfse](https://github.com/kalmonv/node-sped-nfse)
- [GitHub nfewizard-org/nfewizard-io](https://github.com/nfewizard-org/nfewizard-io)
- [npm @nfewizard-io/nfce](https://www.npmjs.com/package/@nfewizard-io/nfce)
- [PlugNotas NFSe API](https://plugnotas.com.br/nfse/)
- [NFE.io Preços NFSe](https://nfe.io/precos/emissao-nfse/)
- [Focus NFe Preços](https://focusnfe.com.br/precos/)
- [TransmiteNota Preços](https://www.transmitenota.com.br/site/api/precos.php)
- [Migalhas - Associações NFS-e desobrigadas](https://www.migalhas.com.br/depeso/335572/associacoes-nao-estao-obrigadas-a-emitir-nota-fiscal-de-servico---nfs)
- [Jusbrasil - Associações tributação NFS-e](https://www.jusbrasil.com.br/artigos/associacoes-nao-estao-obrigadas-a-emitir-nota-fiscal-de-servicos-nfs/805750360)
- [Tecnospeed blog - NFS-e Nacional retenção ISS](https://blog.tecnospeed.com.br/entenda-tudo-sobre-a-retencao-de-impostos-na-nota-fiscal-de-servico-eletronica/)
- [Crisog - Cloudflare Workers mTLS guide](http://crisog.com/blog/cloudflare-workers-mtls/)
- [node-forge npm](https://www.npmjs.com/package/node-forge)
- [CNM - Adesão obrigatória municípios 2026](https://cnm.org.br/comunicacao/noticias/municipios-devem-fazer-adesao-obrigatoria-a-nfs-e-nacional-ou-perderao-recursos-em-2026)
- [Uberlândia Decreto NFS-e Nacional 2026](https://www.uberlandia.mg.gov.br/2025/12/17/adesao-da-prefeitura-ao-emissor-nacional-da-nota-fiscal-de-servicos-eletronica-nfs-e-entra-em-vigencia-a-partir-de-1o-de-janeiro-de-2026/)
