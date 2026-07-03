# Proposta — Certificados de Reconhecimento do Ciclo 3 (para revisão do PM)

**Data:** 2026-07-03 · **Status:** PROPOSTA para você revisar offline e voltar com recomendações. **Nada emitido em lote.**
**Arquivos nesta pasta:** `template_mockup.pdf` (v1) · **`template_mockup_v2.pdf` (v2, VIGENTE)** · este handoff.

---

## ✅ DECISÕES TRAVADAS (sessão B, 2026-07-03) — refletidas na `template_mockup_v2.pdf`
1. **Layout:** A4 **paisagem** (matou o vazio vertical da v1).
2. **Paleta:** base **clara** (creme, print-friendly, sem navy chapado); navy + **roxo #461DA3** só como acento; **dourado só no selo**. Marca d'água neutra e fraca do mark do Núcleo.
3. **Categorias:** **todas** — A (Champion Ciclo), B (Champion Vitalício/Hall da Lenda), C/D (Tribo campeã), E (Conclusão do Ciclo).
4. **Conclusão (E) — abrangência:** **todos os ativos** (47 ativos não-guest), não os 29 pesquisadores+.
5. **NIA mascote:** reintroduzida como **medalhão/selo** — a carinha ("NIA foto de rosto", transparente) dentro do selo dourado + fitinha navy da categoria. (A pose "baile de gala" de corpo inteiro foi descartada por destoar; a forma digna é como selo.)
6. **Ornamentos de canto (círculos PMI):** **REMOVIDOS** (decoração abstrata sem significado + colidiam com logo/"CAPÍTULO-SEDE").
7. **Assinaturas:** Vitor Maia Rodovalho, PMP — **Gestor do Núcleo**; **Fabricio R. C. Costa** — **Co-Gestor do Núcleo**. (Era "do Projeto"; virou "do Núcleo" porque é um programa com várias iniciativas e tribos de pesquisa.)
8. **Pontuação no box:** **mantida** (ex.: "547 pontos") — reconfirmar se quiser só a posição.
9. **URL de verificação:** **`nucleoia.pmigo.org.br/verify/<código>`** (domínio do capítulo, não o pessoal). Aterrado ao vivo: o domínio já resolve (→ `ai-pm-research-hub.pages.dev`) e cai na mesma página via redirect.
10. **Sede + federação:** PMI-GO como **CAPÍTULO-SEDE** no topo + **faixa dos 15 capítulos** no rodapé.

### ✅ Resolvido (design)
- **Faixa de capítulos:** os marks eram **branco puro** → sumiam no creme. **Recoloridos p/ navy** (`recolor()` no gerador, preserva alpha). Agora nítidos. Os 15 capítulos **confirmados** como participantes.

### ⚠️ Nota de implementação p/ `pdf.ts` (host de verificação)
`src/lib/canonical.ts` centraliza `CANONICAL_HOST` (= `nucleoia.vitormr.dev`) e um teste de contrato (`canonical-host-centralization.test.mjs`) **quebra o build se qualquer arquivo em `src/` cravar outro host**. Para exibir `nucleoia.pmigo.org.br` no certificado sem fazer o flip completo de domínio (OAuth/MCP/Supabase), adicionar uma constante dedicada em `canonical.ts` (ex.: `CERT_VERIFY_HOST = "nucleoia.pmigo.org.br"`) e usá-la no `pdf.ts` — NÃO hardcodar no `pdf.ts`.

> Todos os números vêm de query ao vivo (`ldrfrvwhxsmgaabwmaik`) em 2026-07-03.

---

## 0. Pendência a reconciliar — 1 certificado JÁ emitido (template ANTIGO)
Na etapa de amostra emiti **1 certificado real** com o template atual (sem logo, 1 assinatura só): **Fernando Maquiaveli · `CERT-2026-C51E0A`** (cert_id `2969e372-2e1f-4a6f-8d25-59bdea6f0ae1`). Como o template vai mudar, decisão: **revogar+reemitir** com o novo layout, ou **atualizar**. (Ver decisão #9.)

---

## 1. Categorias propostas + destinatários (aterrados ao vivo)

**Regra transversal:** a **gestão da plataforma fica fora do ranking dos membros** — exclui **Vitor** (Ciclo 654 / Vitalício 1264) e **Fabricio** (Ciclo 310 / Vitalício 1090). Eles **assinam** os certificados (GP + Co-GP), não recebem.

| # | Categoria | Tipo DB sugerido | Destinatários (ao vivo) |
|---|---|---|---|
| **A** | Champion Individual — **Ciclo 3** (Top 5) | `excellence` | Fernando 547 · Marcos 526 · Débora 515 · Jefferson 495 · Hayala 460 |
| **B** | Champion Individual — **Vitalício / Hall da Lenda** (Top 5) | `excellence` | Débora 1080 · Fernando 1052 · Paulo 1050 · Jefferson 850 · Ítalo 820 |
| **C** | Champion de **Tribo — Ciclo 3** | `excellence` | **T05 Talentos & Upskilling** (1º) → replicado aos ativos: Jefferson (líder), Ligia, Paulo |
| **D** | Champion de **Tribo — Vitalício** | `excellence` | **T05** também é 1º no vitalício → mesmos 3 |
| **E** | **Conclusão do Ciclo 3** (fim de ciclo) | `completion`/`participation` | escopo a definir: **47** ativos não-guest **ou 29** pesquisadores+ (ver decisão #2) |

**Sobreposições:** Fernando, Débora e Jefferson aparecem em A **e** B; Jefferson e Paulo também em C/D → decisão #5 (2 certs cada vs combinar).

**Nota importante — `champions_awarded` é OUTRA coisa:** a tabela de champions tem **3 registros ativos** (Jefferson ×1, Débora ×2), todos `surface=deliverable/artifact` (atas ricas, 50 pts cada). É reconhecimento **por entregável**, não o "champion do ciclo/tribo". As categorias A–D acima derivam do **ranking de gamificação**, não dessa tabela. (Decidir se os champions-de-entregável entram no programa também.)

---

## 2. Desenho proposto (ver `template_mockup.pdf`)
O template ATUAL (`src/lib/certificates/pdf.ts`, tipo `excellence`) é minimalista: sem logo, corpo genérico, **1 assinatura só (Vitor)**, específico só no bloco "Principais contribuições". O mockup proposto adiciona:

- **Logo PMI-GO** no topo (hoje só o Termo de Voluntário usa logo).
- **Faixa dourada de categoria** ("🏆 Top 5 do Ciclo 3" / "🏅 Hall da Lenda" / "🥇 Tribo Campeã" / "🎓 Conclusão do Ciclo").
- **Box de destaque** com a conquista + **pontuação** ("1º lugar · Ranking do Ciclo 3 · 547 pontos").
- **DUAS assinaturas:** Vitor Maia Rodovalho, PMP (Gestor) + **Fabricio R. C. Costa (Co-Gestor)** — ambos têm `signature_url` no banco (imagens reais entram na emissão).
- **Selo/medalha** dourado decorativo.
- Tribo: **lista nominal do time** em destaque.
- Linha de **verificação** (código + URL).

⚠️ Implementar isso é **tarefa dev**: alterar `pdf.ts` (nova rota de render para `excellence`/reconhecimento) + branch + build + PR, **antes** de emitir o lote. (Também: a coluna `certificates.title` é NOT NULL — obrigatório no payload, mesmo não sendo renderizado.)

---

## 3. Decisões para você trazer de volta
1. **Categorias:** incluir A–E todas, ou subset? Champions-de-entregável (tabela) entram?
2. **Fim de ciclo (E):** escopo dos destinatários — 47 (todos ativos não-guest) · 29 (pesquisadores+) · ou um critério (mín. presença/pontos)?
3. **Pontuação no destaque:** manter os pontos no box (mockup mostra), ou só a posição?
4. **Tribo (C/D):** 2 certs separados (ciclo + vitalício) ou 1 combinado? Destinatários = líder + pesquisadores ativos (3) — confirma?
5. **Sobreposições (A∩B, tribo):** 2 certs por pessoa (decisão "A" anterior) — confirma?
6. **Tipos DB:** `excellence` p/ champions; `completion` ou `participation` p/ fim de ciclo — ok?
7. **Assinaturas:** Fabricio como Co-GP — confirmado; forma do nome ("Fabricio R. C. Costa" vs completo "Fabricio Rodrigues do Carmo Costa")?
8. **Template dev:** aprovar o incremento no `pdf.ts` (mockup) como alvo — sim?
9. **Fernando já emitido (`CERT-2026-C51E0A`):** revogar+reemitir com novo template, ou atualizar?
10. **Escrita:** revisar o texto/copy de cada categoria (tom, redação).

---

## 4. Números-âncora (ao vivo 2026-07-03)
- Ciclo 3: início 2026-03-01, em curso. Ranking por soma do ledger `gamification_points` dentro da janela.
- **Ranking Ciclo (gestão fora):** Fernando 547 · Marcos 526 · Débora 515 · Jefferson 495 · Hayala 460 (Vitor 654 e Fabricio 310 excluídos).
- **Ranking Vitalício (gestão fora):** Débora 1080 · Fernando 1052 · Paulo 1050 · Jefferson 850 · Ítalo 820 (Vitor 1264 e Fabricio 1090 excluídos).
- **Tribo #1 (ciclo e vitalício):** T05 Talentos & Upskilling (ativos: Jefferson líder, Ligia, Paulo).
- Roster: 47 ativos não-guest · 29 pesquisadores+.
- champions_awarded: 3 ativos (por-entregável, não usados nas categorias A–D).

member_ids: Fernando `c8b930c3…` · Marcos `c204ac61…` · Débora `a8c9af17…` · Jefferson `622ab18b…` · Hayala `f64ee70a…` · Paulo `57fcf33c…` · Ítalo `c1f428b5…` · Ligia `f7b73a72…`.
