# Handoff de 13/09 — três ondas entregues, e a jornada de conhecimento aberta com medição

> **Nada aqui é medição de agora.** Carimbado em 13/09 às 16h UTC. **Re-meça antes de decidir:**

```bash
git fetch --all && git log --oneline -1 origin/main
gh pr list --state open
gh issue list --state open --limit 400 --json number --jq 'length'
```

**Estado ao encerrar:** `main 785fe0da` · **0 PRs abertas** · 366 issues abertas.

---

## 1. O que entrou na main hoje

| onda | commit | verificação |
|---|---|---|
| **#2130** o desfecho do provedor alcança a notificação | `877fbfe6` | cadeia exercida em 6 s com envio controlado: `resend_id` capturado, `accepted`, webhook, `delivered` |
| **#2255** o deploy carimba o commit publicado | `a40eb560` | `/api/version` respondeu `a40eb560` em produção |
| **#2245** a fonte das chaves fora do catálogo | `8598cb1f` | 10 órfãs → 0, 3 ciclos sujos → 0, FK exercida por INSERT recusado |
| **ADR-0129** a camada de conhecimento | `785fe0da` | status `Proposed`, não ratificado |

Nenhuma delas foi verificada por leitura de código. Todas por medição antes e depois.

---

## 2. Redação de PII: 83 itens, e a lição que custou mais que o trabalho

Decisão do dono: redigir **só ALTA** (e-mail pessoal ou telefone), deixar MÉDIA e BAIXA.

- 41 corpos de issue, 20 comentários, 25 títulos renomeados
- **83 itens únicos** — não 86; #230, #251 e #270 estão nas duas listas
- Verificação final: 0 e-mail pessoal, 0 telefone, 0 nome em título, com controle positivo

### O erro que vale mais que o resultado

O protocolo era de dois lados: eu conto o que editei, o nó par conta o que sobrou. **Os dois deram 0.
Restavam 4 telefones na #1355.**

O meu verificador importava os mesmos dois regexes do meu redator, e o instrumento "independente" do
par carregava as mesmas duas suposições. **Não eram dois instrumentos: era uma régua quebrada lida por
duas pessoas.**

**Independência de pessoa não é independência de método.** As regras que ficaram:

1. o protocolo declara o **instrumento**, não só quem conta;
2. **precisão é trabalho do ator; revocação é do verificador** — padrão amplo mais inspeção, e a
   maioria dos achados será falso positivo (23 candidatos nos 61 eram todos identificador técnico);
3. controle positivo se constrói com as formas que **escaparam**, nunca com formas inventadas.

E o que pegou não foi o protocolo: foi acaso. Registrado como acaso, porque vestir sorte de processo
constrói confiança falsa no processo seguinte.

---

## 3. A jornada de conhecimento — aberta hoje, com medição

Origem: discussão do grupo geral em 13/09 + deck V1 + briefing.

**A descoberta que reordena tudo:** a camada de conhecimento **já existe nas quatro superfícies** —
página (`governance/glossario`, `admin/knowledge`, com `/en` e `/es`), RPC (`knowledge_search`,
`get_governance_glossary`, `can_manage_knowledge`), cron (58 corridas) e MCP
(`search_nucleo_knowledge`). **Falta acervo:** `knowledge_assets` tem 1 linha.

| | |
|---|---|
| **#2260** | guarda-chuva, com as 11 perguntas do briefing revisitadas |
| **#2261** | abastecimento: 58 corridas verdes receberam 16 linhas; trilho do YouTube nunca ligado |
| **#2262** | autoria na plataforma, Diátaxis, e o MCP amadurecendo junto |
| **#2263** | onde moram arquivos e PDFs: 4 moradas coexistem, nenhuma escrita |
| **#2264** | trilíngue declarado e ausente: 0 linhas `es-LATAM`, e `wiki_pages` sem a coluna |

**Ordem:** #2261 antes de #2262 (o detector de corrida vazia precede qualquer trilho novo). #2264 não
espera o acervo — acrescentar idioma depois obriga a reclassificar tudo que nascer sem ele.

### Três fatos que o briefing não tinha

- **O espelho está parado há 41 dias, e não é defeito.** Último `synced_at` 03/08; último commit do
  repo do wiki no **mesmo dia**; as 13 datas de sync casam com commits. O webhook funciona, ninguém
  escreve.
- **107 das 151 páginas não têm `summary`**, que é o que a busca mostra.
- **Storage já é camada de arquivo em escala:** 9 buckets, 937 objetos, ~758 MB.

---

## 4. Incidente vivo, com pessoa esperando

**#2265** — link de onboarding expira sem caminho de volta.

| | |
|---|---:|
| tokens desde 29/04 | 172 |
| **expirados sem uso** | **94 (54,7%)** |
| **expiraram e alguém tentou** | **25** |
| janela média | 10,5 dias |

E a assimetria que é o defeito: a porta de **agendamento de entrevista** tem
`request_interview_booking_link_via_token`; a de **onboarding não tem nada**. A tela só oferece
"entre em contato".

⚠️ **Ação imediata, fora da issue:** a pessoa do relato precisa de link novo. É operação do GP.

---

## 5. Outras issues abertas hoje

**#2251** lista morta de eventos no `webhook-parser` · **#2252** alcance do ADR-0012 · **#2253** o hook
casa `TODO` dentro de `TODOS` (203 linhas acusadas contra 78 reais) · **#2255** o portão de deploy
`skipped` em silêncio.

---

## 6. O mecanismo do dia, em sete instâncias

**Uma ausência, ou um recorte, que lê como benigna.** O estado de falha e o normal são graficamente
idênticos, então ninguém distingue sem ir à fonte.

1. deploy `skipped` (não é vermelho) · 2. 58 corridas verdes recebendo 16 linhas · 3. `gh pr checks`
não lista quem não reportou · 4. lista truncada devolvendo exatamente o limite (3 vezes hoje) ·
5. `npm test` com 850 skipped lendo como verde · 6. fronteira de data exclusiva medindo 6 dias e
rotulando 7 · 7. o verificador compartilhando instrumento com o ator.

**A contramedida é invariante de segunda fonte** — e a segunda fonte tem de ser outro **método**, não
outra pessoa. Diligência não resolve: olhar de novo com cuidado produziu um segundo número errado.

---

## 7. Dívidas minhas, nomeadas

- **A main ficou vermelha 9,5 h** por linha fantasma de `apply_migration`, e eu mergeei por cima
  porque a verificação que fiz media outra coisa. A regra em `.claude/rules/database.md` estava
  **errada** e foi corrigida em #2245.
- **Rodei `npm test` sem `.env`** e quase entreguei 850 skipped como verde.
- **Um laço de espera chamou `gen-types-drift` de flake** e re-rodou duas vezes um check
  determinístico.
- **Um guard meu não podia reprovar**: a janela engolia o ramo vizinho.

---

## 8. Os três órfãos continuam órfãos

`docs/specs/SPEC_TROCA_DE_TRIBO_JANELA_E_ALERTA.md`, `scripts/design-kit/_t11_airmeet_tmp.py` e
`scripts/design-kit/_t11_formas.py`, todos de 29/08. **Não toquei**, pela mesma razão da sessão
anterior: é trabalho de outra pessoa e misturá-lo tira a decisão de quem deve tomá-la.
