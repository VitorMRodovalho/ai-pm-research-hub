# Pitch ALUN/Kruel — Ledger de Feedback (Rodada 1)

> Fonte: feedback do Vitor, 2026-06-13, slide por slide + global. Este documento é o
> registro durável (sobrevive a `/clear`). Numeração de slide = **estado atual** (11 slides)
> e fica congelada como referência nesta rodada, mesmo se a pág. 2 for quebrada em duas
> (instrução explícita do Vitor). Status: `[ ]` aberto · `[~]` em curso · `[x]` feito.

## 0. Catches críticos (grounding / fatos)

- [ ] **C1 — Código ANSI do standard de IA está ERRADO no deck.** Slide 5 e a memória dizem
  `ANSI/PMI 25-001-2026`. A capa oficial em alta-res fornecida pelo Vitor
  (`inbox_r1/1780955617370.jpeg`) mostra o selo ANSI = **`ANSI/PMI 26-007-2026`**, "Approved
  American National Standard". Título oficial: *The Standard for Artificial Intelligence in
  Portfolio, Program, and Project Management*. → Corrigir slide 5; trocar a capa plugada
  (`assets/covers/ansi_ai_standard.jpg`) por esta versão oficial; atualizar a memória
  `nucleo-partnerships-alun-deck`. **Confirmar o código lendo o selo junto com o Vitor antes de gravar.**
- [ ] **C2 — Link do Núcleo divergente.** Deck/CLAUDE.md = `nucleoia.vitormr.dev`; Vitor agora
  pediu `nucleoia.pmigo.org.br` (slide 10). Confirmar qual é o canônico (pode ser vanity novo).
- [ ] **C3 — "1000 jovens / SESTEC maio".** Número novo p/ slide 4. Por regra de grounding do
  repo, todo número no deck vem de tool ao vivo. Buscar fonte (plataforma / get_public_impact_data
  / registro do evento) antes de gravar "1000".

## 1. Global / cross-cutting

- [ ] **G1 — Numeração de página.** Canto inf. direito mostra `#` (placeholder de slide-number
  do template não populado no clone). Ativar numeração real em todas as páginas (tratar no engine).
- [ ] **G2 — Paleta / identidade visual.** Sites do grupo ALUN (Alura/FIAP/PM3/StartSE) têm
  comunicação mais sóbria e escura. Pesquisar + decidir se uma variante escura faz sentido vs.
  template PMI. NOTA já levantada: o próprio PMI usa fundo **verde-escuro sóbrio** em material
  oficial (`inbox_r1/PMI Ecossystem.jpeg`) e a capa do standard de IA é **navy escuro** — ou seja,
  uma variante escura PODE ser brand-consistent com o PMI. (Recomendação minha pendente em G2.)
- [ ] **G3 — Estrangeirismos.** Reduzir (ex.: "business" → preferir "negócios" quando couber).
  Ao usar sigla, definir na frente: "propriedade intelectual (PI)", etc. Manter clareza.
- [ ] **G4 — Maturidade visual de diagramas.** Os diagramas/workflows estão imaturos. Avaliar
  gerar via HTML/SVG (ou Visio-like) com UI/UX executiva, limpa, não poluída. Aplica a slides 3, 6, 7.

## 2. Per-slide (referência = numeração atual)

### Slide 2 — `fit` (Do MVP de IA ao projeto entregue) — GREENLIT p/ começar
- [ ] P2.1 — Inserir a **capa do livro do Kruel** (`inbox_r1/livro Kruel.png`). Imagem-âncora
  (ponto de conexão). Avaliar remover fundo / ajuste de UI. Fonte: startse.com/artigos/cristiano-kruel-lanca-livro...
- [ ] P2.2 — Em "O saber usar IA: business, produto, inovação, tech" → **acrescentar
  "empreendedorismo"** (protagonista de negócios, não só parte do ecossistema). Rever "business"→"negócios".
- [ ] P2.3 — Adicionar **contexto do PMI** ao falar de PMI/Núcleo: 800.000 membros (marco,
  Pierre Le Manh); "mantido por voluntários, feito para voluntários"; domina certificações
  globalmente aceitas; protagonista nos Standards (IA, portfólio, etc.). (Cuidar p/ não sobrecarregar
  o slide 2 — parte deste contexto pode morar em slide próprio / 4 / 5.)
- [ ] P2.4 — Enquadramento **dual do gestor de projetos** (visão Núcleo): (a) o GP que implementa
  IA / transformação digital; (b) o GP no meio de uma transformação precisando de upskilling,
  seleção de time, cultura de equipe, cultura de dados, necessidade de negócio — independe de
  modelo tradicional ou ágil. Esse é o cerne da cunha.

### Slide 3 — `problem` (Onde os projetos de IA travam)
- [ ] P3.1 — Se a pág. 2 virar duas, manter numeração atual como referência (ver topo).
- [ ] P3.2 — Diagrama de workflow muito imaturo visualmente → refazer (HTML/SVG/Visio, UI/UX executiva). (G4)
- [ ] P3.3 — Usar dado **MIT 95% dos pilotos de GenAI falham** (`inbox_r1/MIT 95% pilots AI fail.png`/
  `.svg`; fonte fortune.com/2025/08/18/mit-report...). Reforça a dor de mercado.
- [ ] P3.4 — **Reescrever frase que denigre o ALUN**: "É o elo que o ALUN não ensina e que o
  Núcleo traz." Queremos ALUN como PARCEIRO → mostrar diferencial/complementaridade, não fraqueza
  no SWOT deles. Reposicionar como dor de MERCADO (não falha do ALUN).

### Slide 4 — `who` (A costura de IA dentro do PMI)
- [ ] P4.1 — "5 capítulos sede (15 engajados)": esclarecer que é **um capítulo sede** + todos os
  capítulos brasileiros aderentes via **acordo de cooperação**. Reescrever sem ambiguidade.
- [ ] P4.2 — **Tirar "4 artigos no projectmanagement.com"** (nicho, incipiente). Trocar por
  prova de alcance maior: **SESTEC — ~1000 jovens impactados** numa palestra/mesa-redonda em
  seminário (maio/2026, parceria); articulação com outras entidades p/ replicar ações; formação
  de lideranças; apreço por boas práticas de GP. (Número 1000 = C3, validar.)
- [ ] P4.3 — Rever a linha "1.618h · 4 artigos · 10 turmas" e "Ciclo 4 LATAM" à luz de P4.2.
- [ ] P4.4 — Adicionar **o que o Núcleo OFERECE**: verticais de pesquisa; exposição a temáticas
  diversas; upskilling; oportunidades/networking/exposição por estar dentro da comunidade PMI;
  ambiente p/ inovação/upskilling e até formação de negócios (incubação). E o que o PMI dá:
  ecossistema de eventos, filiação, projeção global, selo internacional (certificação + standards).

### Slide 5 — `ansi` (O PMI escreve o padrão)
- [ ] P5.1 — Adicionar **certificações PMI** como diferencial além dos Standards. Imagem com várias +
  **PMI-CP** (`inbox_r1/PMI-CP.png`), **PMI-PMOCP** (`inbox_r1/PMI-PMOCP.png`), **PMI-CPMAI EM
  DESTAQUE** (`inbox_r1/PMI-CPMAI.jpeg`), PMP (`inbox_r1/PMP.jpeg`). Curar por UX/CX.
- [ ] P5.2 — Triar/categorizar as demais imagens (séries 177*/178*/1780955617*) e decidir uso.
- [ ] P5.3 — Deixar claro que o **standard de IA é o PRIMEIRO** e **acabou de ser lançado**; frase
  curta sobre ele (elo de conexão com o time ALUN). Ver C1 (código correto).

### Slide 6 — `gap` (título agressivo) — RENOMEAR
- [ ] P6.1 — Título "O que o grupo já tem, e o que falta" é **agressivo** → reposicionar para
  **sinergia/colaboração/entrega de valor**: a interseção dos dois ecossistemas, onde o meio
  converge. Ideal: **diagrama de interseção** (Venn/convergência), UI/UX executiva, limpa. (G4)

### Slide 7 — `exchange` (A troca de valor)
- [ ] P7.1 — O contexto de interseção do slide 6 clareia este. Tese: o ecossistema/qualidade que o
  ALUN criou oferece um **pool de alunos focados no tema**; o Núcleo fornece **ambiente + cultura +
  proteção + exposição**. Ser crítico aqui, mas usar como base épica.

### Slide 8 — `fronts` (Três frentes) — possivelmente PROMOVER p/ posição 2
- [ ] P8.1 — SGPL é **um** evento; mas os pesquisadores se cadastram em **todos** os seminários
  regionais do PMI nos capítulos. Corrigir a redação.
- [ ] P8.2 — Maior patrimônio = **pessoas e cultura**: qualidade + critério de seleção do time
  voluntário (2ª onda de protagonismo: mestres, doutores, empresários, C-level, professores,
  líderes/gestores de 2º nível) num único foco. Tudo voluntário. Esse é o diferencial.
- [ ] P8.3 — **Evitar "custo zero"** (conotação ruim). O projeto é voluntário, sem custo de entrada
  além de ser filiado PMI ou ter acordo de cooperação via entidade. Reescrever sem o termo.
- [ ] P8.4 — Sigla com definição na frente ("propriedade intelectual (PI)"). Dar contexto de
  **motor de inovação** (intra/extra-empreendedorismo, plugar aceleradoras/incubadoras) — mas
  talvez NÃO no pitch p/ ALUN (avaliar).
- [ ] P8.5 — **Reordenar**: em resposta à msg do Kruel (ver §3), este slide (tipo de colaboração)
  talvez deva ser o MAIS importante e vir **logo após a abertura** (posição ~2), antes dos demais.

### Slide 9 — `path` (Começar pequeno, sem acordo formal) — REVER/REMOVER
- [ ] P9.1 — Vitor **discorda de "começar sem acordo"**. Deixar mais claro OU remover o slide.

### Slide 10 — `managers` (Gestores)
- [ ] P10.1 — **Remover Credly.**
- [ ] P10.2 — Adicionar **telefones** + LinkedIn como **links clicáveis**:
  - Vitor: +1 267-874-8329 — Senior Cost Manager na Linesight (investida da Berkshire Hathaway;
    atuando on behalf da Google em projetos de data centers). LinkedIn clicável.
  - Fabrício Costa: +1 503-544-7898 — Program Manager no time de Design & Engineering da AWS;
    PhD em Business em andamento. LinkedIn clicável.
  - (Evitar estrangeirismo, manter clareza.)
- [ ] P10.3 — Links clicáveis: Núcleo `nucleoia.pmigo.org.br` (ver C2); PMI `pmi.org`; Mário →
  board PMI `https://www.pmi.org/about/board-of-directors`.

### Slide 11 — `ask` (Vamos começar pequeno) — REVER/REMOVER
- [ ] P11.1 — "Começar pequeno" pode dar mal-entendido ("go big or go home"). Remover, redirecionar
  a mensagem, ou retirar. (Casa com P9.1 e P8.5 — tensão do enquadramento "small start".)

## 3. Mensagem do Kruel (âncora do tom)
> "Olá Vitor, eu prefiro que vc me passe aqui qual o tipo de colaboração que vc procura pois posso
> ir respondendo. Eu lancei um livro novo e minha agenda está impossível durante a semana. Conforme
> o que formos falando eu vou pensando contigo como poderíamos colaborar."

Implicações: (a) ele quer **o tipo de colaboração concreto, cedo e async**; (b) agenda apertada →
deck escaneável; (c) conversa iterativa. → Favorece promover `fronts` (slide 8) p/ perto da abertura
e enxugar o enredo "small start" (slides 9/11).

## 4. Inventário de assets (`assets/inbox_r1/`, gitignored)
| arquivo | conteúdo | slide alvo |
|---|---|---|
| `livro Kruel.png` | capa do livro MAIVP do Kruel | 2 |
| `PMI Ecossystem.jpeg` | ecossistema PMI (fundo verde-escuro sóbrio) | 2/5 + ref. paleta |
| `MIT 95% pilots AI fail.png` / `.svg` | manchete MIT 95% pilotos GenAI falham | 3 |
| `1755775285046.jpeg` | (triar — provável arte MIT/AI) | 3 |
| `PMI-CPMAI.jpeg` | selo PMI-CPMAI (navy/teal premium) — DESTAQUE | 5 |
| `PMI-CP.png` | selo PMI-CP | 5 |
| `PMI-PMOCP.png` | selo PMI-PMOCP | 5 |
| `PMP.jpeg` | selo PMP | 5 |
| `1780955617370.jpeg` | **capa oficial standard IA — selo ANSI/PMI 26-007-2026** | 5 (capa) + C1 |
| `1780955617{241,226,231,270}.jpeg` | série standard IA (triar) | 5 |
| `1775705668{854,768}.jpeg`, `1775924201252`, `1776177480694`, `1777912813{028,029}`, `1778250642230`, `1779487531647` | posts Pierre Le Manh (800k membros, standards, sustentabilidade) — triar | 2/4/5 |

(Também referenciados mas em `assets/covers/`: mckinsey, pmi_pulse, ansi_ai_standard, pmbok.)

## 5. Decisões (resolvidas 2026-06-13)
1. ✅ **Estrutura: REESTRUTURAR.** Promover `fronts` p/ ~posição 3 (responde o Kruel), fundir
   `gap`+`exchange` em "sinergia/interseção", enxugar "small start" → fecho ambicioso; dropar slide 9.
2. ✅ **Paleta: VARIANTE ESCURA SÓBRIA.** Âncora = capa do standard de IA (navy) + acentos PMI.
   Ressalva: fetch dos sites ALUN foi inconclusivo (só texto); justificativa real = material escuro
   do PRÓPRIO PMI (standard IA navy, CSPP verde-escuro). Confirmar paleta exata na hora do build.
3. ⏳ **C1/C2/C3** — pendentes: confirmar código ANSI (26-007 lendo o selo), link do Núcleo, nº SESTEC.

## 7. Estrutura nova proposta (reestruturado, ~9 slides) — CONFIRMAR ordem
1. Capa
2. O encaixe (wedge MAIVP, "Do MVP de IA ao projeto entregue") + capa do livro do Kruel
3. Frentes de colaboração (menu concreto — responde direto o Kruel)  [ex-8]
4. Sinergia / interseção dos dois ecossistemas (diagrama, sem título agressivo)  [funde ex-6 + ex-7]
5. Quem é o Núcleo: pessoas + cultura + tração + provas (SESTEC, LIM, Novello)  [ex-4 + P8.2]
6. Autoridade PMI: Standards (ANSI/PMI 26-007-2026) + certificações (CPMAI em destaque)  [ex-5]
7. Por que agora: MIT 95% + McKinsey + standard recém-lançado (sem denegrir ALUN)  [ex-3]
8. Quem conduz: gestores + contatos clicáveis  [ex-10]
9. O convite: fecho ambicioso (sem "começar pequeno"; absorve o "como começar")  [ex-11 reformulado]

Paleta escura (proposta inicial, p/ validar no build):
- Fundo: navy profundo (~#0C1B2A, da capa do standard). Cards: navy +claro (~#14263A).
- Texto: quase-branco (#F6F4EF / LIGHT). Acentos PMI que brilham no escuro: LILAC #A98EEC,
  BLUE #6CBEDE, ORANGE #E0611F, TEAL. PURPLE escuro vira realce secundário.
- Desafio de engenharia: o template PMI é CLARO; ir escuro exige recolorir o fundo pós-clone
  ou achar layout escuro no template. Inspecionar o template no início do Lote D.

## 8. Progresso — build R2 (2026-06-13)
FEITO neste ciclo (deck reconstruído escuro, 9 slides, builda limpo):
- ✅ C1 código ANSI 25-001 -> **26-007-2026** (lido do selo) + capa oficial plugada + memória corrigida.
- ✅ C3 SESTEC: +1.000 espectadores (fonte pública YouTube) no slide 5.
- ✅ G1 numeração de página real (engine `_number_pages`, cor clara no dark).
- ✅ Paleta escura (engine `dark=True`, base slide-18, copia `<p:bg>` no clone).
- ✅ Reestruturação 11->9 slides na ordem aprovada; slide "path/começar pequeno" removido; fecho ambicioso.
- ✅ P2.1 capa do livro · P2.2 empreendedorismo+negócios · P2.4 GP dual · P2.3 tag PMI 800k/voluntário.
- ✅ P3.4 (agora slide 7) reescrito sem denegrir ALUN (dor de mercado MIT 95%/McKinsey).
- ✅ P4.1/P4.2/P4.4 quem somos: pessoas&cultura 1º, SESTEC, "o que o Núcleo oferece", capítulo-sede+parceiros.
- ✅ P5.1/P5.3 certificações (CPMAI destaque, CP, PMOCP, PMP) + standard "recém-lançado".
- ✅ P6.1 título de sinergia (não agressivo) + diagrama de interseção (Venn) · G4 diagramas dark-native.
- ✅ P8.3 "custo zero"->"baixa fricção" · P8.4 PI definida · P8.5 frentes promovidas p/ slide 3.
- ✅ P10.1 Credly removido · P10.2 telefones+cargos+LinkedIn clicável · P10.3 links nucleoia.pmigo.org.br/pmi.org/board.

PENDENTE / próxima rodada:
- ⏳ C2: confirmar que `nucleoia.pmigo.org.br` resolve (usei como primário).
- Polish: espaço vertical vazio nos slides de texto (2/3/9 top-aligned); badge PMP tem fundo branco (destoa no
  dark); capas McKinsey/Pulse claras sobre o escuro; balancear o slide 2 (muita folga central).
- Decks executivos (`build.py`) seguem claros (engine retrocompatível, não testado nesta sessão).

## 9. R3 — revert p/ claro + framework PMI (2026-06-13, 2ª leva de feedback)
- ✅ Paleta revertida p/ CLARO (Vitor achou o roxo pesado; o deck oficial do PMI de parcerias é claro).
- ✅ +Slide dedicado do PMI (instituição: 800k membros, voluntário, certs+Standards, PMI:Next/PMIxAI/Infinity).
- ✅ Certs com LEGENDA PT-BR (CPMAI=Gestão de IA, PMP, PMOCP, ACP=Práticas ágeis); colisão do slide 7 corrigida.
- ✅ PMI-CP (=Construction Professional, off-theme) TROCADA por PMI-ACP (slot drop-in: falta `inbox_r1/PMI-ACP.png`).
- ✅ SESTEC e LIM LATAM em LINHAS SEPARADAS com contexto (+Carlos Novello).
- ✅ Li o PMI Chapter Partnerships Framework → notas em `partnerships/PMI_PARTNERSHIP_FRAMEWORK_NOTES.md`.
  Aplicado: frentes rotuladas pelos TIPOS oficiais; sinergia nomeia os 6 PROPÓSITOS; +slide "como formalizamos"
  (LOI/Informal→MOU→Contrato+NDA+PI) enquadrado como autoridade. Linha de "baixo risco/investimento do capítulo".
- 11 slides claros, builda limpo. Pendências: badge PMI-ACP (drop-in); selo CPMAI mantém leve quadrado escuro
  (bg gradiente, flood-fill parcial); confirmar 800k (atribuído ao CEO do PMI, fonte pública).

## 6. Lotes de execução propostos
- **Lote A (sem decisão, alto valor):** G1 numeração · C1 código ANSI + capa correta · P2.1/P2.2 · P3.4 · P8.3 · P10.1.
- **Lote B (depende de decisão 1):** reordenar slides (P8.5/P9.1/P11.1) + reescrever 6/7 (P6.1/P7.1).
- **Lote C (conteúdo + assets):** P2.3/P2.4 · P4.* · P5.* · P10.2/P10.3.
- **Lote D (visual):** G2 paleta · G4 diagramas (HTML/SVG) p/ 3/6/7.
