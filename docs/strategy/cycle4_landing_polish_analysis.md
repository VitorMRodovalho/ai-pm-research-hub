# Landing C4 — Análise holística para a sessão de polish (pré-lançamento julho)

- **Status:** Diagnóstico + recomendações + pontos de decisão. **Não implementado** — insumo para uma sessão limpa dedicada (decisão PM 2026-06-21).
- **Origem:** após o QA holístico R1→R9 (branch `cycle4-landing-redesign`, redesign completo e aprovado no QA). O PM pediu análise como um todo de: ordenamento das seções, âncoras `#` no menu (web+mobile), enquadramento de certificação, tom/discurso da home, + os polimentos carregados (descrições de vertical en/es, contraste laranja). Tudo aterrado em copy/dado ao vivo nesta sessão.
- **Já resolvido nesta sessão (fora do polish):** `team.label` de-hardcoded (`'44 Colaboradores · 5 Capítulos · 1 Missão'` → "Quem faz acontecer" / "Who makes it happen" / "Quienes lo hacen"); doc-alvo §6 atualizado (mapa = Brasil-only, sem LatAm).

---

## 0. Ordem atual das seções (aterrada no QA, idêntica pt/en/es)

| # | id | Componente | Zona |
|---|----|-----------|------|
| 1 | `#hero` | HomepageHero | anon |
| 2 | `#verticals` | ModelSection (R3 — "O modelo", hub-and-spoke) | anon |
| 3 | `#trail` | LadderSection (R4 — "A escada de certificação") | anon |
| 4 | `#platform-stats` | PlatformStatsSection (R2 — prova viva, 47/807h/340/68%/5) | anon |
| 5 | `#capitulos` | ChaptersSection (R6+R9 — banda + **mapa Brasil**) | anon |
| 6 | `#join` | RouterSection (R7 — 2 portas, CTA único) | anon |
| 7 | `#partners` | PartnersSection (porta de parceiros) | anon |
| 8 | `#agenda` | WeeklyScheduleSection (R8 — Agenda Viva pública) | anon |
| 9 | `#team` | TeamSection | anon |
| 10 | `#tribes` | TribesSection | membro |
| 11 | `#rules` | RulesSection | membro |
| 12 | `#kpis` | KpiSection | membro |
| 13 | `#trail-ranking` | TrailRankingSection | membro |
| 14 | `#resources` | ResourcesSection (zona membro) | membro |

---

## 1. Ordenamento das seções — observações + decisão

O funil anon está coerente (herói → o quê → como → prova → cobertura → converte → parceiro → agenda → time). Dois pontos valem decisão:

- **PD-ORD-1 — "A escada" (#trail) em 3º, antes da prova (#platform-stats em 4º).** A seção mais carregada de certificação aparece muito cedo e antes da credibilidade por números. Se a certificação for despriorizada (ver §3), faz sentido **mover a prova (stats) para antes da escada** (herói → modelo → **prova** → escada → cobertura) para a credibilidade aterrar antes do "como progredir".
- **PD-ORD-2 — A escada vs. o mapa de cobertura.** Hoje escada(3) vem antes de capítulos+mapa(5). Se o objetivo é "pesquisa colaborativa entre capítulos PMI do Brasil", a cobertura geográfica (mapa) é prova forte e poderia subir. Decisão de ênfase: pesquisa/protagonismo primeiro (escada→cobertura) ou rede/escala primeiro (cobertura→escada).

> Nenhum dos dois é bug; são escolhas de ênfase do funil. Recomendação default se nada mudar: **mover #platform-stats para antes de #trail** (prova antes do caminho).

---

## 2. Âncoras `#` no menu (web + mobile) — **BUG + lacunas (acionável)**

O menu "Seções" (dropdown desktop + drawer mobile) é dirigido por **um único array** `NAV_ITEMS` (group `home-anchors`) em `src/lib/navigation.config.ts` → web e mobile corrigem juntos.

**Estado atual (7 itens):** `#quadrants` · `#verticals` · `#partners` · `#breakout` (networking) · `#trail` · `#team` · `#resources`

**Problemas:**
- 🔴 **2 âncoras MORTAS:** `#quadrants` e `#breakout` (networking) — essas seções **não existem mais** (R3/R4 fundiram quadrants em #verticals; não há #breakout). Clicar → não rola / vai pro topo. **Remover.**
- ⚠️ **Faltam âncoras de seções reais e importantes do funil:** `#platform-stats`, `#capitulos` (capítulos + mapa R9), `#join` (roteador/conversão), `#agenda`.
- ⚠️ `#resources` no menu anon aponta para zona de membro (fim da home) — reavaliar se entra no menu público.

**Recomendação (menu anon alinhado ao funil):**
`O modelo` (#verticals) · `Números` (#platform-stats) · `Capítulos` (#capitulos) · `Faça parte` (#join) · `Parceiros` (#partners) · `Agenda` (#agenda) · `Time` (#team) — e a escada (#trail) com o rótulo que sair da §3.

- **PD-NAV-1:** quais seções entram no menu (todas as 8 anon vs. curado)? Rótulos?
- **PD-NAV-2:** i18n — criar `nav.platformStats/chapters/join/agenda` nos 3 dicts; aposentar `nav.quadrants/networking`.
- **PD-NAV-3 (comportamento):** no QA, a nav fixa (sticky) sobrepõe o topo da seção ao ancorar. Adicionar `scroll-margin-top` (≈ altura da nav) nas `<section>` para o heading não ficar escondido sob a barra — verificar em web **e** mobile.

---

## 3. Enquadramento de certificação — **o ponto mais sensível** (risco institucional PMI)

Diretriz do PM: *certificação não é foco, é consequência; só a PMI-CPMAI é celebrada (mural); evitar conflito com as diretorias de certificação do PMI.* Hoje a home **enquadra a progressão central EM TORNO de certificação**.

> ### ✅ RESOLUÇÕES PM (2026-06-21) — travadas para a sessão de polish
>
> **R1 — `hero.gain` "co-branded": NÃO existe MoU/acordo assinado** que autorize "credenciais PMI
> co-branded". → **PD-CERT-1 resolvido: remover "co-branded" do herói** (e qualquer afirmação de
> credencial conjunta) antes do launch. Sem paper trail, não vai ao ar.
>
> **R2 — As "verticais" NÃO são escada/trilha de certificação.** São **temáticas de pesquisa por
> contexto de atuação do gestor de projetos** (agilista, construção/megaprojetos, ESG/sustentável,
> negócios, PMO, tradicional/híbrido, …). → **PD-CERT-2 + PD-CERT-4 resolvidos:** o eixo "para quem"
> deixa de ser "por credencial PMI" e passa a ser **"por contexto de atuação"**. A IA segue
> transversal. A "escada de certificação" (R4) deixa de ser nomeada por certificação.
>
> **R3 — Credencial PMI e área de conhecimento: IMPLÍCITAS, nunca escritas.** Decisão de
> posicionamento do PM (validada): organizar por credencial publicamente lê-se como funil de
> certificação (conflito com diretorias PMI) E é menos honesto (elas são temas de pesquisa, não
> trilhas). O praticante reconhece a afinidade pelo NOME do contexto; o site nunca reivindica a
> credencial. Mapeamento mantido só INTERNO:
>
> | Tema público | Credencial PMI (implícito) | Área de conhecimento (implícito) |
> |---|---|---|
> | Agilismo | PMI-ACP | adaptativo/ágil |
> | Construção & Megaprojetos | PMI-CP | megaprojetos |
> | ESG & Sustentabilidade | CSPP | sustentabilidade |
> | Negócios *(ou "Análise de Negócios" — PD aberto)* | PMI-PBA | análise de negócio/valor |
> | PMO | PMI-PMOCP | portfólio/PMO |
> | Tradicional & Híbrido | PMP | preditivo/integração |
> | *(IA aplicada — transversal)* | **PMI-CPMAI** *(EXPLÍCITO, celebrado no mural)* | IA |
>
> **Ressalvas de execução (do PM + análise):**
> 1. Implícito na credencial, **explícito na substância**: cada card = nome do contexto + 1 linha da
>    pergunta de pesquisa (ex.: "IA aplicada a megaprojetos de construção"), senão fica vago.
> 2. **Não apagar o vínculo PMI** (capítulos, PMI-GO, CPMAI seguem explícitos e são força). O que vira
>    implícito é só "organizado pela sua certificação".
> 3. **CPMAI = exceção deliberada**: nomeada/celebrada (é cert de IA = tema real do Núcleo).
> 4. **Varrer TODAS as superfícies**: `hero.gain` ("toda credencial"/"co-branded"), `model.subtitle`,
>    `model.axisWho` E os **dados dinâmicos das verticais no DB** (labels/descrições expostas pelo RPC
>    público `get_public_verticals` — se o DB mantém "PMI-ACP" etc., a credencial vaza pelo dado).
> 5. **Enquadrar como "frentes de pesquisa (ativas / em formação)"**, não catálogo completo de GP
>    (evita parecer reproduzir o mapa de domínios do PMI; casa com anti-vaporware — hoje só Construção
>    live, resto `forming`).

**Princípio separador (parecer accountability-advisor):** *quem é o sujeito da frase de certificação?*
- ✅ SEGURO: "membros do Núcleo **conquistam/completam** certificações PMI porque fazem pesquisa de alto nível" — o PMI certifica, o Núcleo pesquisa, a certificação é reconhecimento externo.
- 🔴 RISCO: "o Núcleo **oferece/estrutura/organiza** uma progressão de certificação" — o Núcleo vira agente do processo certificatório (encosta nas diretorias do PMI). Corolário: celebrar "Maria completou a PMI-CPMAI" (ok) ≠ "nossa escada de certificação leva você à PMI-CPMAI" (risco).
- Segundo princípio: **afirmação de co-branding só com paper trail** (MoU/acordo assinado).

**Classificação das strings (i18n):**

| String | Texto atual (resumo) | Veredito |
|---|---|---|
| `ladder.title` | "Uma escada **de certificação**, por tier" | 🔴 REPOSICIONAR (heading canônico, maior risco) |
| `ladder.subtitle` | "...progressão por mérito, com **certificados reais**..." | 🔴 REPOSICIONAR ("certificados reais" implica Núcleo=emissor) |
| `hero.gain` | "...**conquiste credenciais PMI co-branded**..." | 🔴 REPOSICIONAR (co-branded sem paper trail = afirmação não sustentada; cert no centro do herói) |
| `trail.subtitle` | "4 **mini-certificações** core + 2 especialidade..." | ⚠️ ATENÇÃO (taxonomia própria sobre produto PMI) |
| `model.subtitle` / `model.axisWho` | "verticais **por credencial PMI** (para quem)" | ⚠️ ATENÇÃO (ok se = audiência por área de prática; risco se = preparatório p/ credencial) |
| `trail.label` | "Meta 2026: 70% da Trilha PMI AI Completa" | ✅ SEGURO (engajamento com produto PMI externo) |
| `cpmai.disclaimer` | "...NÃO substitui o curso oficial do PMI..." | ✅ SEGURO (é o modelo a replicar) |

**Reescritas sugeridas (do parecer):**
- `ladder.title` → **"Uma escada de maestria, por tier"** (ou "Uma trilha de pesquisa com reconhecimento real").
- `ladder.subtitle` → "...uma progressão por mérito e protagonismo. Cada degrau soma ao seu **portfólio de pesquisa** e à meta anual do Núcleo." (remove "certificados reais"; CPMAI segue como destino natural, não produto do Núcleo).
- `hero.gain` → "...e **veja seu progresso reconhecido na Trilha PMI AI**. É a leitura prática de PMI:Next e do M.O.R.E." (remove "conquiste credenciais co-branded"; sujeito que reconhece é o PMI).
- `trail.subtitle` → "8 módulos da Trilha PMI AI (**emitidos pelo PMI**) + 1 certificação PMI-CPMAI™..." (some a taxonomia core/especialidade/master; emissor explícito).
- `model.subtitle`/`axisWho` → "verticais **por área de prática** em IA e GP (para quem)" / "comunidades de prática por área".

**Pontos de decisão (por urgência):**
- **PD-CERT-1 (URGENTE):** existe instrumento assinado que autoriza "credenciais PMI **co-branded**"? Se não, a string sai do herói antes de qualquer lançamento. Se sim, registrar nº/data do documento.
- **PD-CERT-2:** rebatizar a seção "escada de certificação" → "escada de maestria/protagonismo" (escolher vocabulário). Certificação vira menção dentro da descrição, não o nome da estrutura.
- **PD-CERT-3:** o Núcleo tem autoridade (no acordo) para reclassificar módulos da Trilha PMI AI em taxonomia própria (core/especialidade/master)? Se não, simplificar para contagem + atribuição ao PMI.
- **PD-CERT-4:** verticais definidas por **credencial** (quem você é) ou **área de prática** (o que você faz)? A 2ª é mais segura e mais alinhada à missão de pesquisa.
- **PD-CERT-5:** "Meta 2026: 70% da Trilha" é meta de **engajamento** (seguro, manter) ou meta de **certificação do Núcleo** (reformular como capacitação)?

---

## 4. Tom / discurso da home — análise

O tom geral é **concreto e factual** (alinhado ao feedback anterior de evitar jargão "silo/costura" — confirmado 0 ocorrências na branch). Pontos:

- **Densidade de siglas acima da dobra.** Herói + modelo já trazem: PMI:Next, M.O.R.E., credencial PMI, PMI-CPMAI™, Trilha PMI AI, co-branded. Para um visitante novo (não-PMI), é muita sigla insider de uma vez.
  - **PD-TOM-1:** reduzir a carga de siglas no herói/above-the-fold (ex.: "M.O.R.E." e "PMI:Next" descem para o modelo/sobre, onde há espaço para explicar). O herói diz o que é em linguagem simples; as siglas aparecem mais fundo.
- **`hero.subtitle`** ("IA aplicada à Gestão de Projetos — pesquisa colaborativa entre capítulos PMI do Brasil") é limpo e factual. ✅ Manter.
- **Consistência protagonismo.** O CTA "Seja protagonista" se repete (herói→modelo→roteador→agenda) — bom para o funil de CTA único. ✅
- **PD-TOM-2:** revisar o `hero.gain` em conjunto com a §3 (a reescrita de certificação já melhora o tom).

---

## 5. Polimentos carregados (backlog, baixa prioridade)

- **GAP-B2.C — descrições de vertical em en/es.** As descrições dinâmicas (vindas do DB, pt-BR) ficam **suprimidas** em en/es (não vazam pt — confirmado no QA), mas faltam. Localizar (traduzir no DB ou via i18n) ou manter suprimido. Decisão: **PD-POL-1**.
- **GAP-C1.B — contraste do laranja.** Texto branco sobre `--color-orange` (#FF610F) ≈ **3.0:1** de contraste → **reprova WCAG AA para texto normal** (exige 4.5:1); passa só como texto grande/bold (3:1, no limite). Afeta botões/portas preenchidos de laranja (ex.: porta protagonista do roteador, CTAs).
  - **PD-POL-2:** escurecer o laranja para botões com texto, ou garantir texto grande+bold, ou usar texto escuro sobre laranja. (Verificar em todos os CTAs laranja.)

---

## 6. Resumo dos pontos de decisão

| ID | Decisão | Urgência |
|---|---|---|
| PD-CERT-1 | ✅ RESOLVIDO: sem MoU → **remover "co-branded"** do herói | 🔴 executar |
| PD-CERT-2 | ✅ RESOLVIDO: a "escada de certificação" deixa de ser nomeada por cert (eixo = contexto de atuação) | executar |
| PD-CERT-3 | taxonomia própria da Trilha PMI AI: autorizada? | média (aberto) |
| PD-CERT-4 | ✅ RESOLVIDO: verticais = **temas por contexto**, credencial **implícita** (ver Resoluções §3) | executar |
| PD-CERT-5 | "Meta 70% Trilha" = engajamento ou certificação? | média (aberto) |
| PD-CERT-6 | "Negócios" vs "Análise de Negócios" (nome do tema PBA) | baixa (aberto) |
| PD-NAV-1/2/3 | itens do menu + i18n + scroll-margin (web/mobile) | alta (bug de links mortos) |
| PD-ORD-1/2 | mover prova antes da escada / cobertura vs escada | média |
| PD-TOM-1/2 | reduzir siglas no herói; revisar hero.gain | média |
| PD-POL-1/2 | descrições vertical en/es; contraste laranja AA | baixa |

> **Próximo:** sessão limpa dedicada de polish executa as decisões acima (i18n + nav config + ordenamento + a11y), seguida de QA e da estratégia de merge→main (1 PR, com "vai" explícito do PM — `deploy.yml` auto-deploya prod).
