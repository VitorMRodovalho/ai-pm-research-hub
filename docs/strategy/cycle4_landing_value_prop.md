# Brief de Execução — Proposta de Valor da Landing (Ciclo 4)

- Status: **Proposta / Draft** (brief para o time de execução)
- Data: 2026-06-12
- Autor: Vitor (PM) + Claude (PMO)
- Escopo: Refresh da página de entrada (`nucleoia.vitormr.dev`) na virada para o **Ciclo 4** (jul/2026)
- Relacionado: `verticals_x_quadrants_model.md`, ADR-0102 (vertical como `initiative_kind`), issue #661

> **Este é um brief de estratégia, não a copy final nem o design final.** O time executa. Duas regras valem como contrato: (1) **nada hardcoded** — indicadores saem de dados ao vivo; (2) **evoluir a informação, preservar o sistema visual** — sem rebrand na virada de ciclo.

---

## 1. Espinha narrativa (a proposta de valor em uma frase)

> O Núcleo IA & GP é a **costura entre os silos do PMI** — uma comunidade voluntária que junta gente boa de toda credencial num ambiente de pesquisa, desenvolvimento e networking, usando a IA como o fio que atravessa os silos.

**Gancho institucional** (legitimidade): o próprio PMI está integrando suas comunidades — PMO Global Alliance, GPM e Agile Alliance entraram para dentro do PMI (2023–2026). O Núcleo é a **expressão humana e de pesquisa** dessa mesma integração. Posiciona o Núcleo como leitura prática de PMI:Next / M.O.R.E., não como "mais uma iniciativa".

## 2. Os 6 blocos da página

| # | Bloco | Função | Conteúdo |
|---|-------|--------|----------|
| 1 | Herói / missão | O fio | Frase-costura + promessa bimodal (pesquisa de elite Eixo A + comunidade aberta Eixo B) |
| 2 | **Prova viva** | Credibilidade por fato | Contadores ao vivo (ver §3) |
| 3 | O modelo | Clareza sem jargão | Quadrantes × verticais com a IA costurando → **diagrama hub-and-spoke** (ver §5a) |
| 4 | A escada | "Como entro/cresço" | PMIxAI Champion → Grupo de Estudos CPMAI → PMI-CPMAI |
| 5 | Cobertura & alcance | Diversidade + networking | **Mapa Brasil/LatAm + presença internacional** (ver §5b) |
| 6 | **Chamada de protagonistas** | Conversão | CTA por vertical, inclusive "declaradas, ainda não abertas" (ver §4) |

## 3. Regra inegociável: indicadores fact-driven (nada hardcoded)

Todo número da página sai **ao vivo** dos dados da plataforma — nunca digitado no HTML. Fontes existentes: `get_public_impact_data`, `get_public_trail_ranking`, contagens de `initiatives` / `members` / deliverables, `champions_ranking`.

Indicadores sugeridos (todos derivados, não fixos):
- nº de pesquisadores / membros ativos
- nº de capítulos PMI envolvidos
- nº de tribos (= `initiatives WHERE kind='research_tribe'`)
- nº de verticais (= `kind='community_vertical'`), com status
- nº de entregáveis (artigos / protótipos / webinars)
- nº de Champions

Benefício duplo: a página é **honesta** *e* **se atualiza sozinha** a cada ciclo — ninguém edita código quando entra um membro. Coerente com o princípio do Núcleo de comunicar com **fatos e dimensões**.

## 4. Mecânica "chamada de protagonistas" (vertical declarada, não aberta)

Declarar uma vertical futura sem parecer vaporware:
- A vertical aparece com **status explícito** ("Vertical ESG — *em formação para o Ciclo 4*"). Não finge atividade.
- CTA **"Seja protagonista"** (não "seja membro") → recruta **fundadores**, cria coorte fundadora. Mais atraente para gente boa.
- Sem hardcode: a vertical é uma `initiative` com `status = 'forming'` (ADR-0102/ADR-0009); a página **lê o status** e renderiza o CTA. Interesse entra como `capture_visitor_lead` (com `target_vertical`) → vira `application` quando a vertical abre.

Resultado: momentum visível ("venha fundar") sem mentir sobre o estado atual.

### Copy do CTA (aprovada — refinar tom com a liderança)

> **Seja protagonista.**
> O Núcleo é a próxima onda de formadores de opinião em **IA e Gestão de Projetos** — levando o tema ao contexto e à forma certa. Aqui você não só participa: constrói a **base para escalar suas ideias**, amadurecer seu pensamento e formar opinião com fundamento, ao lado de gente boa, em pesquisa, desenvolvimento e networking.
> É um **programa de liderança**: exige compromisso e protagonismo. Por isso ele conversa diretamente com o **M.O.R.E.** e o **PMI:Next** — liderança que assume responsabilidade por gerar valor real, não só por entregar.

Notas de tom: "protagonista/protagonismo" e "formador de opinião" são o núcleo da mensagem (compromisso, não consumo passivo). Evitar buzzword empilhada; manter a promessa concreta (base para escalar a própria voz). O vínculo M.O.R.E./NEXT é o que justifica chamar de "liderança", não enfeite.

## 5. Especificação dos dois visuais

### 5a. Diagrama hub-and-spoke (bloco 3) — *este visual É o pitch*
- Centro: **Núcleo + IA** (a costura).
- Raios: as **verticais** (Construção, PMO, Ágil, ESG, Negócio) — cada raio uma comunidade/credencial PMI.
- Anel/legenda: a **escada Champion → CPMAI** como espinha comum a todos os raios.
- Conta o que mapa nenhum conta: **integração de silos**. Deve renderizar as verticais a partir dos dados (lista dinâmica de `community_vertical`), não fixas.

### 5b. Mapa de cobertura & alcance (bloco 5) — **Brasil + LatAm** em primeiro plano, mundo como legenda
Calibração (jun/2026): o Núcleo **não é só embaixadores** (são ~4); membros ativos — pesquisadores, líderes, curadores — já estão em **vários estados do Brasil + Portugal, Itália, EUA**. A diversidade prioritária é **intra-Brasil**, mas a presença internacional é **ativo de networking** e deve aparecer.

- **Primeiro plano: mapa do Brasil + América Latina** por capítulo/estado (15 capítulos no Brasil). Calor/contagem por capítulo. Conta "quebramos o silo geográfico" e mostra a coorte real. **A escolha de enquadrar a LatAm é um recado de próximos passos por geografia, não por texto** — o mapa sinaliza a fronteira de expansão sem que a copy precise declará-la.
- **Presença internacional (fora da LatAm): legenda/inset nomeado**, não heatmap mundial esparso. Ex.: *"O Núcleo já reúne gente em 🇧🇷 🇵🇹 🇮🇹 🇺🇸 …"* com contagem por país. Vende o **acesso a networking** que a comunidade dá — sem o problema do "borrão sobre o Brasil cercado de vazio".
- **Reúso:** o componente de mapa do PMAIrevolution pode ser reaproveitado tecnicamente — re-projetar para Brasil/LatAm e agregar. Trabalho re-escopado, não descartado.

#### Restrição LGPD (obrigatória)
O Núcleo é governança-first (`lgpd_*`, `pii_access_log`, declarações de exclusão). Em página pública:
- **Agregar por capítulo / estado / país** (contagem, calor). Zero PII.
- Pins de **pessoa física só com opt-in** explícito (precedente: `set_my_gamification_visibility`).
- Nunca plotar localização individual sem consentimento registrado.

## 6. Identidade vs. evolução (UI/UX)

- **Sem rebrand na virada de ciclo.** Continuidade visual = confiança da comunidade voluntária.
- Verticais entram como **nova camada de informação, não nova pele.** Paleta existente; no máximo **um** token de acento novo para o CTA "protagonista".
- Componentes net-new (mapa, hub-and-spoke, contadores) são **aditivos**. Tematizar por **token**, nunca cor hardcoded.
- Regra de ouro: **mude a informação, preserve o sistema visual.** Se precisar tocar a paleta-base, virou projeto à parte — fora do escopo da virada de ciclo.

## 7. Checklist de aceite (para o time)

- [ ] Nenhum indicador numérico hardcoded — todos derivam de fonte de dados ao vivo
- [ ] Verticais renderizadas a partir de `community_vertical` (lista + status), não fixas
- [ ] CTA "protagonista" dirigido por `status='forming'`
- [ ] Mapa agrega por capítulo/país; pins individuais só com opt-in
- [ ] Presença internacional visível (legenda nomeada por país)
- [ ] Paleta/identidade preservadas; mudanças aditivas e tokenizadas
- [ ] Diagrama hub-and-spoke comunica integração de silos sem jargão

## Decisões tomadas (PM, 2026-06-12)

- **Escopo geográfico do bloco 5:** Brasil + LatAm em primeiro plano (LatAm como recado de expansão por geografia, não por texto).
- **CTA:** "Seja protagonista" — copy aprovada em §4 (refinar tom com a liderança).

## Perguntas abertas

- A "prova viva" mostra todos os indicadores ou um subconjunto curado para não poluir o herói?
