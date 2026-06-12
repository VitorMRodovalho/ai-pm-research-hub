# Outline do Pitch Deck Executivo — Núcleo IA & GP (esqueleto para sessão limpa)

- Status: **Esqueleto / pré-sessão** (montar o deck numa sessão limpa, por higiene de contexto)
- Data: 2026-06-12
- Skill a usar: **`branded-deck-build`** (clona template `.pptx` branded, injeta por shape, renderiza PDF/PNG para QA)
- Relacionado: `verticals_x_quadrants_model.md`, `cycle4_landing_value_prop.md`, `vertical_pitch_kit.md`, ADR-0103, issue #661

> **O conteúdo já existe.** Este deck é uma *renderização* dos 3 docs de estratégia — não há pesquisa nova a fazer, só transposição visual. A coluna "Fonte" abaixo diz qual doc alimenta cada slide.

## Pré-requisitos para a sessão limpa

1. **Template `.pptx` oficial do PMIGO/PMI** (o SSOT a clonar pela skill). Sem ele, `branded-deck-build` não tem marca para clonar.
2. **Check de marca:** usar identidade PMIGO é legítimo (Núcleo sob os capítulos), mas a marca PMI tem guidelines — validar antes de externalizar ao board.
3. **Logo PMIGO** em alta resolução.

## Princípios do deck

- **Nível executivo:** ~12–15 slides, **1 ideia por slide**, denso em sinal, sem jargão.
- **Fact-driven:** números vêm de dado/fonte conferida (mesma disciplina da landing). Não inventar métrica.
- **Visual-âncora:** o **hub-and-spoke** (IA costurando os silos) é o centro do deck.
- **Pedido trocável por audiência:** um deck, slide de "pedido" varia (mesmo princípio costura + doca).

## Estrutura slide-a-slide

| # | Slide | Mensagem-chave | Fonte |
|---|-------|----------------|-------|
| 1 | Título | Núcleo IA & GP + PMIGO | — |
| 2 | O problema | PMI é organizado em silos de credencial; a IA é transversal | modelo §1 |
| 3 | **O fio + vento a favor** | IA é a costura; e o **próprio PMI está integrando os silos** (PMOGA→PMI, GPM→CSPP, Agile Alliance→PMI) | modelo §1.1 ← *slide-matador p/ board* |
| 4 | O modelo | Quadrantes × verticais × tribos — **diagrama hub-and-spoke** | modelo §3 + landing §5a |
| 5 | A escada | PMIxAI Champion → CPMAI (espinha comum) | modelo §4 |
| 6 | Cobertura & alcance | Brasil + LatAm em 1º plano + presença internacional (networking) | landing §5b |
| 7 | Vertical Construção | PMI-CP · "Megaprojects demand mega skills" | pitch kit §1 |
| 8 | Vertical PMO | PMI-PMOCP · PMO aumentado por IA | pitch kit §2 |
| 9 | Vertical Ágil | PMI-ACP · julgamento humano na era dos agentes (Highsmith) | pitch kit §3 |
| 10 | Vertical ESG | CSPP · sustentabilidade = #1 preditor (55% vs 33%) | pitch kit §4 |
| 11 | Vertical Negócio | PfMP/PgMP/PMI-PBA · IA em portfólio | pitch kit §5 |
| 12 | **O pedido** | (varia por audiência — ver abaixo) | — |
| 13 | Próximos passos | Ciclo 4: verticais-piloto + chamada de protagonistas | landing §4 + kit (ordem de ativação) |

## Slide 12 — "O pedido" por audiência

- **Mario Trentim / board PMI:** endorsement estratégico + reconhecimento do Núcleo como leitura prática de **PMI:Next / M.O.R.E.** (a comunidade que executa a integração dos silos que o PMI já está fazendo institucionalmente).
- **Presidentes de capítulo:** adesão do capítulo, indicação de protagonistas/pesquisadores, validação do discurso.
- **Parceiros de vertical (GPM, Construction Ambassadors, PMOGA):** co-curadoria + acesso à comunidade da credencial (ver "pedido ao parceiro" no pitch kit).

## Para a sessão limpa fazer

1. Carregar `branded-deck-build` + o template PMIGO.
2. Gerar os 13 slides pela tabela acima (copy a partir das fontes).
3. Renderizar PDF/PNG e fazer QA visual.
4. Produzir as 3 variações do slide 12 (board / presidentes / parceiros).
