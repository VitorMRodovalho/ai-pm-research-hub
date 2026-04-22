# ADR-0021: Newsletter Frontiers Governance — addendum operacional ao Pipeline (ADR-0020)

- Status: Partially Accepted (2026-04-21 pós-decisões GP) / Pending Termo R3 (quinta 2026-04-23)
- Data: 2026-04-21
- Revisão: 2026-04-21 24h — GP decidiu F1, F2 (trilíngue upgrade), F7 (busca formal desescalada), cadência biweekly. Pendente D3 (licensing comparativo apresentado), D4 (termo — quinta)
- Autor: Claude (debug session 9908f3) — aguarda aprovação Fabrício + ratificação CR-050 + Termo R3-C4
- Escopo: Formaliza decisões editoriais e operacionais específicas da Newsletter "Frontiers in AI & Project Mgmt" (proposta por Fabrício em docx 2026-04-21) dentro do framework do Publication Pipeline (ADR-0020). Resolve 4 conflitos identificados em análise dual (Claude A jurídico/PI + Claude B operacional/editorial), consolidados em [issue #96](https://github.com/VitorMRodovalho/ai-pm-research-hub/issues/96).

## Contexto

### Estado em 2026-04-21
- Guia Editorial "Frontiers in AI & Project Mgmt" criado pelo Fabrício, em revisão (Google Doc com permissão comment-only do GP)
- Apenas 2 comentários no doc (Marcos + Jefferson aprovando título)
- ADR-0020 aprovou primitivo `publication_series` (5 seeds aplicados via commit `57a1ce9`)
- ADR-0020 D2 (`publication_ideas`) ainda **não aplicado** (W2 pendente)
- Política de Propriedade Intelectual CR-050 v2.2 ainda **`under_review`** no portal de governance
- Termo de Voluntário R3-C3 vigente tem Cláusula 2 (cessão automática) **juridicamente ineficaz** segundo análise paralela
- Plataforma usa PT-BR como idioma primário; jsonb i18n já suporta EN+ES mas hoje só PT é populado em `blog_posts`

### Tensões editoriais identificadas
1. **Idioma:** Guia exige US-EN obrigatório vs Playbook do Núcleo exige PT-BR obrigatório
2. **Marca:** "Frontiers" colide potencialmente com Frontiers Media SA (editora suíça com 100+ journals "Frontiers in X")
3. **Categoria editorial:** Guia §5 lista 7 tipos, plataforma tem 10 (3 não cobrem o Guia)
4. **Fluxo:** Guia §9 lista 7 etapas que mapeiam quase 1:1 com `publication_ideas.stage` (#94 W2), faltando 3 stages

### Bloqueador estrutural
ADR-0020 não trata licensing, AI disclosure, employer consent, declarações de CoI — itens que CR-050 v2.2 cobre. Sem CR-050 ratificada, Frontiers não pode publicar legalmente. **Este ADR só faz sentido se ADR-0016 (IP ratification) sair de gate primeiro.**

## Decisão

> Todas as decisões deste ADR ficam em estado **Proposed** até as 6 perguntas pendentes da issue #96 serem respondidas pelo GP+Fabrício. Defaults sugeridos abaixo são recomendações do Claude B, não vinculantes.

### F1 — Frontiers como 6ª `publication_series` (confirmado GP 2026-04-21)

**Decisão GP Vitor:** "fica dentro do pipeline".

Frontiers **vira instância** de `publication_series`, não pipeline paralelo. Herda toda a infra (`publication_ideas`, `blog_posts.series_id`, MCP tools futuras, webhook de cadência, check_idea_originality #95). Slug definido: `frontiers-newsletter`. **Cadência: biweekly** (a cada 2 semanas — decisão GP 2026-04-21, upgrade vs monthly original do Guia).

**SQL:** ver SPEC_FRONTIERS_NEWSLETTER_LAUNCH.md SQL Block 3.

### F2 — Política de idioma: **trilíngue nativo EN+PT+ES** (decidido 2026-04-21)

**Decisão GP Vitor (2026-04-21):** trilíngue nativo (upgrade vs bilíngue original).

**Justificativa do GP:** "a plataforma é trilíngue, ser o editorial também mantém a consistência". Blog posts, wiki pages, e UI já suportam jsonb i18n com 3 locales — Frontiers cai no mesmo padrão.

**Implicação operacional:**
- Todas as issues publicadas em EN + PT + ES **simultaneamente** (paridade, não waterfall)
- EN continua sendo fonte canônica (ancorada no Guia Editorial §6)
- PT e ES são **versões nativas**, não traduções automáticas — tradução editorial cuidadosa com review humano
- Custo estimado por issue: ~60-90min de translation+review humano (3 idiomas × ~20-30min cada)

**Opções rejeitadas (registro):**
- ~~(a) EN-only + tradução LLM — conflita com Playbook Núcleo que exige PT-BR~~
- ~~(b) Bilíngue EN+PT — subestimava mercado LATAM espanholófono + ambassadors PMI LATAM~~
- ~~(c) EN-only sem tradução — exclui ~70% da audiência Núcleo não-fluente em EN~~

**Operacionalização:** `publication_ideas.target_languages = ARRAY['en-US','pt-BR','es-LATAM']` mandatório para `series_id = 'frontiers-newsletter'`. App-level check + `blog_posts.title/excerpt/body_html` jsonb exige 3 chaves populadas antes de `published`.

### F3 — Licensing default: CC BY-SA 4.0 (recomendado)

3 opções:

| License | Comercial OK? | Share-alike? | Recomendação |
|---|---|---|---|
| CC BY 4.0 | ✅ | ❌ | Mais permissiva, terceiros podem comercializar sem retornar |
| **CC BY-SA 4.0** | ✅ | ✅ | Defensiva: derivativos devem manter mesma licença |
| CC BY-NC 4.0 | ❌ | ❌ | Restritiva: bloqueia uso comercial mesmo educacional |

**Decisão proposta:** CC BY-SA 4.0 — equilíbrio entre reach (qualquer um pode usar) e proteção (derivativos abertos).

**Operacionalização:** `publication_ideas.metadata->>'cc_license'` validado contra enum `['CC BY 4.0','CC BY-SA 4.0','CC BY-NC 4.0']` antes de `tribe_review`.

### F4 — 3 declarações obrigatórias no template de submissão

Antes de `publication_ideas.stage` avançar de `draft` para `tribe_review`, autor DEVE preencher em `metadata jsonb`:

1. **`ai_usage_declaration`** — string descrevendo uso de IA (modelo, escopo, % do conteúdo). CR-050 v2.2 §4.
2. **`employer_consent_confirmed`** — boolean atestando que material proprietário do empregador (se houver) tem autorização documentada. Proteção contra NDA.
3. **`conflicts_of_interest`** — string listando afiliações relevantes (PMI certifications, sponsors, employer, vendor relationships). Padrão arXiv/IEEE.

**Operacionalização:** trigger `publication_ideas_check_declarations()` no SQL Block 2 do SPEC. Bloqueia stage transition.

### F5 — Stages do Guia §9 ↔ `publication_ideas.stage`

Adiciona 3 stages a ADR-0020 D2:
- `proposed` — pós-`draft`, validação preliminar (curador checa fit com série, originality via #95 `check_idea_originality`)
- `tribe_review` — pós-`writing`, revisão pela tribo do autor
- `leader_review` — pós-`tribe_review`, revisão pelo líder de tribo OU comms_leader

**Justificativa:** mapeia 1:1 com fluxo Frontiers, evita divergência operacional. Não quebra outras séries (stage transitions opcionais; algumas séries podem pular `tribe_review` se autor não está em tribo).

### F6 — Originality check obrigatório para Frontiers (#95 cross-ref)

Para séries com claim de alcance internacional (Frontiers, futuras), `check_idea_originality(title, summary)` (issue #95 W2) é **chamado obrigatoriamente** na transição `draft → proposed`. Se cluster denso de 3+ fontes externas convergentes for encontrado, avança para `proposed` mas com flag `originality_warning=true` em metadata. Curador pode aprovar mesmo assim, mas decision tem audit trail.

**Operacionalização:** depende de #95 W1-W4 entregues. Se não estiver pronto até Gate 2, fallback: skip check + adicionar nota manual no template.

### F7 — Marca "Frontiers": busca formal DESESCALADA (decidido 2026-04-21)

**Decisão GP Vitor (2026-04-21):** manter "Frontiers in AI & Project Mgmt" por enquanto, **sem busca formal USPTO/INPI pre-launch**.

**Racional:**
- Newsletter de nicho PM BR/LATAM em estágio inicial (cadência biweekly, audiência específica)
- Frontiers Media SA (editora científica suíça, 100+ journals "Frontiers in X") opera em mercado distinto (biomédico/científico)— risco real de cease-and-desist é **baixo** neste estágio
- Custo busca formal: R$ 3-8k + 3-6 meses → desproporcional vs risco atual
- Custo-benefício: monitoramento passivo tem 90% do valor por 5% do custo

**Mitigações ativas (pre-launch, custo quase zero):**
1. **Google Alerts** para: `"Frontiers in AI & Project Mgmt"`, `"Frontiers AI project management"` (5min setup)
2. **Busca livre de trademarks existentes** (informativa, não protetiva):
   - INPI Brasil: https://busca.inpi.gov.br/pePI/ (10min — confirmar que não há registro ATIVO conflitante)
   - USPTO EUA: https://www.uspto.gov/trademarks/search (10min)
3. **Disclaimer defensivo no masthead** da newsletter:
   > *"Published by Núcleo IA & GP, an independent community hub affiliated with PMI Brasil. Not affiliated with Frontiers Media SA or its journals."*
4. **Review trimestral** dos gatilhos de escalação (ver abaixo)

**Gatilhos que DESTRAVAM decisão de busca/registro formal:**
- 🚨 **10+ issues** publicadas OU **1000+ subscribers** — atingiu massa crítica
- 🚨 **Primeiro contato comercial/sponsorship** — há dinheiro em jogo
- 🚨 **Qualquer menção/cease-and-desist** recebido de Frontiers Media SA ou terceiros
- 🚨 **Expansão para mercado EUA/Europa** — exposição a jurisdições mais litigiosas
- 🚨 **Publicação em journals formais com peer review** — entra no território da Frontiers Media

Quando qualquer gatilho disparar, revisitar F7 com busca formal + consulta jurídica + consideração de alternativas:
- *AI×PM Research Hub Quarterly*
- *PMI Latin America AI Intelligence Brief*
- *Frontline AI for PMs*
- *Augmented PM Review*

**Decisão técnica:** slug `frontiers-newsletter` mantido no SPEC SQL Block 3. Se gatilho futuro forçar rename, migration ALTER UPDATE vira possível (1 INSERT + UPDATE de URLs antigas).

**Anti-risco adicional:** não fazer claim de "journal" ou "peer review formal" no masthead — fica claro que é newsletter de comunidade, não publicação científica. Reduz confusão com Frontiers Media.

## Consequências

### Positivas
- Frontiers fica governável dentro da plataforma desde o launch (não requer flow paralelo manual)
- 3 declarações obrigatórias automatizam compliance CR-050 + LGPD + NDA proteção
- Stages alinhados Guia ↔ plataforma evitam dupla taxonomia editorial
- Originality check (#95) agrega valor diferencial vs newsletters concorrentes
- Reuse de `publication_series` reduz código novo

### Negativas
- Cada submissão precisa 3 declarações — friction adicional pro autor (~5min)
- Bilíngue nativo dobra custo de review (LLM translation + review humano)
- Trigger SQL pode bloquear flows legítimos se template UI não guiar bem o autor — necessita UX cuidadoso

### Não-consequências
- Não força que `publication_series` legacy (5 originais) usem 3 declarações — só Frontiers (definido via app-level check em UI)
- Não altera workflow `publication_submissions` para PM.com/PMI.org
- Não impede publicações `blog_posts` órfãs (sem `series_id`) de continuar saindo

## Alternativas consideradas

1. **Pipeline paralelo manual via Google Drive + spreadsheet** — rejeitado. Não rastreável, não auditable, não escala.
2. **Frontiers como `publication_submissions` standalone (sem série)** — rejeitado. Perde benefício de cadência + voice consistente que séries oferecem.
3. **Adiar launch até pipeline #94 W2-W6 todo entregue** — rejeitado. Gate 0 jurídico é o real bloqueador; pipeline pode entregar incremental enquanto Gate 0 destrava.
4. **Sem trigger de declarações (deixar como app-level only)** — rejeitado. Aplicação na DB garante que MCP, scripts, edge functions também respeitem o invariant.

## Dependências

- **ADR-0016** — IP Ratification Governance Model. CR-050 v2.2 precisa sair de `under_review` (este ADR não pode aplicar antes).
- **ADR-0020** — Publication Pipeline base. F1, F4, F5 dependem de `publication_ideas` aplicado.
- **Issue #94 W2** — `publication_ideas` primitive. Este ADR enriquece o W2 com 3 stages adicionais e trigger de declarações.
- **Issue #95 W1-W4** — `check_idea_originality` RPC. F6 depende.
- **Issue #96 Gate 0** — todos os checks jurídicos + decisões 1-6 do GP+Fabrício.

## Riscos

| Risco | Mitigação |
|---|---|
| Frontiers Media SA cease-and-desist | Busca marca Gate 0; consulta PMI legal advisor antes |
| ~40% voluntários PT-only ficam sem acesso | Política bilíngue (F2 opção b) |
| Trigger de declarações bloqueia flow legítimo | UI guiada + smoke test antes do prod; rollback fácil (drop trigger) |
| CR-050 não ratifica — Gate 0 trava indefinidamente | Issue #96 Gate 0 vira backlog crítico; Board PMI escala |
| 3 declarações reduzem submissões voluntárias | Comunicação clara que é proteção do autor, não burocracia |

## Métricas de sucesso (após launch)

Após 6 meses operando:
- ≥ 3 issues Frontiers publicadas (cadência mensal)
- 0 incidentes jurídicos (NDA, marca, copyright)
- ≥ 80% das submissões aprovadas têm 3 declarações completas (proxy de adoção)
- ≥ 1 issue tem `originality_warning=true` (proxy que check funciona)
- 0 reclamações de voluntários PT-only sobre exclusão linguística

Se métricas falham:
- Revisar F2 (bilíngue está sendo cumprido?)
- Revisar F4 (declarações estão UX-friendly?)
- Revisar nome (F7 — Frontiers Media reagiu?)

## Referências

- [Guia Editorial "Frontiers in AI & Project Mgmt"](docx do Fabrício, 2026-04-21) — fonte primária
- ADR-0016 — IP Ratification Governance Model
- ADR-0020 — Publication Pipeline (primitivo base)
- Issue #94 — Pipeline (#94 Oportunidades #11-15 detalhadas em comment)
- Issue #95 — Echo-chamber detection (originality check para F6)
- Issue #96 — Frontiers Launch consolidation (Gate 0/1/2/3 plan)
- SPEC_FRONTIERS_NEWSLETTER_LAUNCH.md — plano técnico Gate 1
- Frontiers Media SA — https://www.frontiersin.org/ (verificar marca)
- CR-050 v2.2 — portal de governance (`under_review`)

## Aprovação

Aguarda:
1. **GP Vitor** — aprovar F1, F2, F3, F5 (decisões 1, 2, 3, 6 da #96)
2. **Fabrício** — co-autor do Guia, validar que F2/F3/F5 não desfiguram a proposta editorial original
3. **Board PMI / Mario Trentim** — confirmar F7 (uso da palavra "Frontiers" + marcas PMI)
4. **CR-050 v2.2 ratificação** — pré-requisito formal (ADR-0016 dependência)
