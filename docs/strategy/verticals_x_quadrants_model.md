# Modelo Conceitual — Verticais × Quadrantes × Tribos (a IA como linha de costura)

- Status: **Proposta / Draft** (para validação de liderança e tribos)
- Data: 2026-06-12
- Autor: Vitor (PM) + Claude (PMO)
- Escopo: Posicionamento + modelo de domínio do Núcleo IA & GP
- Relacionado: ADR-0005 (initiative-as-domain-primitive), ADR-0009 (config-driven-initiative-kinds), bimodal Eixo A/B, Trilha PMI AI

> **TL;DR.** O Núcleo já organiza *conhecimento* por **quadrantes** (o quê) produzido por **tribos** (quem). Este doc adiciona um terceiro eixo ortogonal — **verticais** (pra quem / onde aterrissa) — alinhado às comunidades de credencial do PMI. A IA é a *linha de costura* que atravessa os silos de credencial do PMI; o Núcleo é, por desenho, a horizontal que o PMI não tem. As verticais não são novos silos: são **docas** onde o conhecimento cross-cutting atraca em cada comunidade.

---

## 1. O problema que justifica o eixo novo

O PMI é organizado por **silos de credencial** (Construção, PMO, Ágil, Sustentabilidade, Negócio…). Cada comunidade vive em sua trilha e raramente conversa com as outras. A IA é transversal a todas — então o ativo que falta no ecossistema é uma **horizontal que costure os silos**. Esse é o papel do Núcleo: voluntário-para-voluntário, uma comunidade com um único propósito, juntando gente boa através das fronteiras de credencial.

Para cumprir esse papel sem se fragmentar, precisamos nomear o eixo "comunidade-alvo" explicitamente — senão ele fica implícito e cada parceria (Construction Ambassadors, GPM, PMO-GA) vira um caso especial.

### 1.1 O vento a favor: o próprio PMI está absorvendo os silos

A tese de "hub integrador" não rema contra a maré institucional — ela *nomeia* a maré. O PMI está consolidando comunidades de credencial para dentro de si:

| Silo | Origem | Movimento PMI (verificado, jun/2026) |
|------|--------|--------------------------------------|
| PMO | PMO-CP (PMO Global Alliance) | PMI **adquiriu** o PMO-CP da PMOGA (dez/2023) → relançou como **PMI-PMOCP** (fev/2026, ISO-accredited); PMOGA agora vive em `pmoga.pmi.org` |
| ESG / Verde | GPM-b (GPM Global) | GPM-b **evolui para CSPP** (efetivo 5 jun/2026), co-branded PMI+GPM, alinhado ao Standard P5 |
| Ágil | Agile Alliance | **entrou no PMI** (2026) |

Conclusão de modelagem: as credenciais-âncora de cada vertical não são estáticas — várias são **linhagens em sucessão** (PMO-CP→PMI-PMOCP, GPM-b→CSPP). A vertical deve ancorar na credencial **vigente** e tratar a predecessora como histórico. O Núcleo é a expressão humana/de pesquisa dessa mesma integração, com a IA como o fio.

## 2. Aterramento institucional (por que agora)

- **PMI:Next** é a estratégia institucional (propósito: *maximize project success to elevate our world*). **M.O.R.E.** é o framework de valor embutido nela (accountability além das métricas). *Não são quadrantes* — são a moldura estratégica na qual o Núcleo se posiciona.
- **Timing a favor das verticais** (todos jun/2026):
  - **CSPP** (Certified Sustainable Project Professional, PMI + GPM Global) lançado → ancora a vertical ESG/Verde.
  - **Agile Alliance entra no PMI** → fortalece a vertical Ágil.
  - **Refresh do PMP** (jul/2026) enfatiza ágil/híbrido.
  - Pesquisa **PMI + GPM**: sustentabilidade é o **maior preditor** de sucesso de projeto.
- **PMI Infinity** (IA do PMI) e o movimento **PMIxAI** mostram que a costura-IA é pauta institucional, não aposta nossa isolada.

> Os quadrantes atuais do Núcleo (Praticante Aumentado / Gestão de Projetos de IA / Liderança Organizacional / Futuro e Responsabilidade) **são taxonomia de conhecimento própria** — não derivam de PMI:Next/M.O.R.E. Verticais e quadrantes são ortogonais.

## 3. O modelo de três eixos

| Eixo | Pergunta | Natureza | Estado |
|------|----------|----------|--------|
| **Quadrante** | *O quê* — tipo de conhecimento | Conteúdo | Existe (4 domínios) |
| **Tribo** | *Quem* produz | Produção (Eixo A) | Existe (≈8 tribos) |
| **Vertical** | *Pra quem / onde aterrissa* | Distribuição / comunidade (Eixo B) | **Novo** |

**Como um output flui:** uma tribo (ex.: *Governança & Trustworthy AI*, no quadrante *Futuro e Responsabilidade*) produz um artigo. O mesmo insight é **roteado e re-empacotado** para a vertical **PMO** *e* para a vertical **ESG**, com framings distintos. Um conhecimento, costurado em vários silos — essa é a operação concreta da "linha de costura".

A vertical **não duplica** o quadrante: o quadrante define o *conteúdo*, a vertical define o *público e o empacotamento*. São dimensões independentes que se cruzam numa matriz.

## 4. A costura tem uma escada (não um ponto único)

A IA costura na camada de prática; na camada de **credencial**, a costura é uma trilha progressiva que toda vertical atravessa:

```
PMIxAI Champion  →  Grupo de Estudos CPMAI (prep)  →  PMI-CPMAI (cert master)
   (aberto, leve,        (Eixo A, preparatório)          (credencial-costura que
   Eixo B, gamificado)                                     faz interface com todas)
```

- **PMIxAI Champion** — reconhecimento/badge leve e aberto. Porta de entrada (Eixo B, Ambassadors). Já existe como primitivo na plataforma (`award_champion`, `champions_ranking`).
- **PMI-CPMAI** (Cognitive Project Management for AI) — a credencial-costura. Faz interface com *todas* as verticais; é o "ponto comum" entre comunidades que não se falariam. Já modelado como iniciativa (grupo de estudos preparatório, `cpmai_*`).

Isso dá a **isomorfia central**: no ecossistema PMI os silos são credenciais e a costura é a IA (credencial = CPMAI); dentro do Núcleo a costura é o mesmo mecanismo, com a escada Champion→CPMAI como espinha que todas as verticais compartilham.

## 5. Catálogo de verticais (rascunho — códigos a conferir no registry)

| Vertical | Credencial-âncora (vigente) | Parceiro / contexto | Tese de IA |
|----------|-----------------------------|---------------------|------------|
| Giga-projetos / Construção | **PMI-CP** (Construction Professional) | Global Construction Ambassadors | IA em megaprojetos |
| PMO | **PMI-PMOCP** ¹ | PMO Global Alliance (comunidade, hoje em pmoga.pmi.org) | PMO aumentado por IA |
| Ágil | **PMI-ACP** | Agile Alliance (entrou no PMI, jun/2026) | Highsmith: human-in-the-loop em sprints de horas |
| ESG / Verde | **CSPP** (← GPM-b) ² | GPM Global | Sustentabilidade = #1 preditor de sucesso (PMI+GPM) |
| Negócio / Programa / Portfólio | PfMP, PgMP, PMI-PBA | — | IA em portfólio e estratégia |
| **Costura (transversal)** | **PMIxAI Champion → PMI-CPMAI** | — | a escada que toda vertical compartilha |

¹ PMI-PMOCP (ISO-accredited, fev/2026) é a credencial, sucessora do PMO-CP que o PMI adquiriu da PMOGA em 2023; PMO Global Alliance é a *comunidade*, hoje sob o guarda-chuva PMI. ² **CSPP** (Certified Sustainable Project Professional, PMI+GPM) é a evolução do **GPM-b** (efetivo 5 jun/2026); são uma linhagem só, por isso ficam numa única vertical ESG/Verde ancorada em CSPP. Códigos conferidos na fonte oficial PMI/GPM (jun/2026).

## 6. Princípio anti-silo (a regra que mantém a costura)

Risco real: verticais virarem feudos e recriarem os silos que queremos quebrar. Antídoto, já coerente com o modelo bimodal:

> **Produção é da tribo (Eixo A). Distribuição é da vertical (Eixo B). Nenhuma vertical é dona de conhecimento — ela é canal.**

A tribo gera; a vertical traduz e leva à comunidade-alvo. Mantida essa separação, a vertical é uma *doca*, nunca um silo.

## 7. Mapeamento operacional na plataforma

O modelo de domínio **já comporta** verticais sem código novo (ADR-0005 / ADR-0009):

- **Vertical como `initiative` de um `kind` novo** (ex.: `community_vertical`), criado por config no admin — sem migration. Cada vertical tem `organization_id` e pode ter `parent_initiative_id`.
- **Sub-iniciativas existentes plugam como filhas**: o Grupo de Estudos CPMAI, webinars por comunidade, workshops — viram `child` da vertical correspondente via `parent_initiative_id`.
- **Quadrante e vertical como metadados ortogonais** de um deliverable: um output carrega `quadrant` (já existe) + `vertical[]` (rota de distribuição). Permite relatórios `GROUP BY vertical` sem duplicar conteúdo.
- **PMIxAI Champion / CPMAI** já são primitivos (`award_champion`, `cpmai_*`) — a escada da costura não precisa ser reinventada, só conectada a cada vertical.

*Decisão de modelagem a ratificar:* vertical como `initiative_kind` vs. como tag/metadado transversal. Recomendação inicial: **`initiative_kind`** (durável, tem governança e parceiro), com `quadrant`/`vertical` também disponíveis como metadado em deliverables para o roteamento N:N.

## 8. Próximos passos (o que este modelo gera)

Este doc é SSOT conceitual; dele saem itens acionáveis:

1. **Validar com liderança/tribos** (issue de discussão ou pauta de reunião).
2. **Conferir códigos de credencial** no PMI Certification Registry.
3. **ADR de modelagem**: vertical como `initiative_kind` (formaliza §7).
4. **Pitch por vertical** para parceiros (Construction Ambassadors, GPM, PMO-GA).
5. **Instanciar 1 vertical-piloto** na plataforma (sugestão: ESG ou Ágil, pelo timing institucional).

## Perguntas abertas

- Verticais são fixas (catálogo curado) ou abertas (qualquer comunidade pode propor)? Ver `max_concurrent_per_org` em ADR-0009.
- Uma tribo pode ser "dona" de uma vertical, ou a separação produção/distribuição é estrita?
- A escada Champion→CPMAI é a única costura de credencial, ou cada vertical tem sua própria credencial-âncora *além* da escada comum?

## Fontes

- PMI:Next & M.O.R.E. — <https://www.pmi.org/whats-next> · <https://www.pmi.org/blog/more-project-management-future>
- Certificações & Registry — <https://www.pmi.org/certifications> · <https://www.pmi.org/certifications/certification-resources/registry>
- CSPP / sustentabilidade = #1 preditor (PMI + GPM, jun/2026) — pesquisa PMI+GPM
- Agile Alliance entra no PMI — <https://agilealliance.org/agile-alliance-joins-project-management-institute-pmi/>
- Núcleo IA & GP — <https://nucleoia.vitormr.dev/>
