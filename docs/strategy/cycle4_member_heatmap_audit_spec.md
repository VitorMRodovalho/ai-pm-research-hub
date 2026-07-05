# Heatmap de membros por estado — Auditoria + Spec (pré-implementação)

- **Status:** Auditoria CONCLUÍDA + spec. **Não implementado** — destinado a sessão limpa dedicada (decisão PM 2026-06-21).
- **Origem:** durante o polish da landing C4, o PM pediu um mapa de calor por estado (densidade de membros ativos por residência), "densidade + capítulos juntos". Antes de construir, pediu auditoria da proveniência do dado, adequação do campo de perfil, e uso LGPD.
- **Veredito legal-counsel:** **CONDICIONAL** (parecer completo abaixo). Não construir sem cumprir as 4 condições.

---

## 1. Auditoria do dado (aterrada nesta sessão)

### 1a. Proveniência
- Fonte = `members.state` (text), **autopreenchido pelo próprio membro** no formulário de perfil (`src/pages/profile.astro:1721-1722`): `<input id="self-state" placeholder="Ex: GO, SP, CE">`.
- **Campo de texto livre, sem dropdown de UF, sem validação** → causa-raiz da inconsistência (uns digitam "GO", outros "Goiás").
- Há `self-cep-wrapper` (CEP, só Brasil) que *poderia* autofill cidade/estado, mas o campo manual aceita qualquer string. `profile.astro:2131` salva `value.trim()` como veio.

### 1b. Natureza (PII)
- `state` é tratado como **PII de verificação de afiliação/identidade**: na migration `20260805000148` (affiliation verification) aparece junto de `address`/`city`/`birth_date` na lista de campos de identidade; é setado a `NULL` na anonimização do delete LGPD (`20260410160000`).
- **Finalidade de coleta original = verificar afiliação**, não exibição geográfica pública.

### 1c. Qualidade (query live sobre `members WHERE is_active`)
- **28 ativos com `state = NULL`** (maior bucket).
- Formatos misturados: `GO`(2) + `Goiás`(3) = mesmo estado em 2 buckets; idem `MG`/`MG`, `RJ`/`RJ`, `Maranhão`/`MA`, `Rio Grande do Sul`/`RS`.
- Erros de país: `SP`/Portugal, `Virgínia`/`VA`/`Virginia` (3 grafias), `Brasil`/`Brazil`/`Estados Unidos`/`United States`/`USA` misturados.
- Conclusão: dado **esparso e não-normalizado** — agregar sem normalizar produz counts errados.

---

## 2. Parecer LGPD (legal-counsel, PT-BR) — resumo

**Mudança de finalidade (Art. 6º I/VIII):** repurposar `state` (coletado p/ afiliação) num choropleth público é desvio de finalidade; a base original **não cobre**. O precedente `get_public_country_reach()` (agregado por país) valida a *arquitetura* (SECURITY DEFINER + agregado zero-PII) mas **não** retroage p/ a granularidade de estado (expectativa de privacidade diferente; base de ~47 membros).

**Reidentificação:** estado com n=1 num choropleth = dado nominal de fato (viola minimização Art. 6º III). **Supressão obrigatória de buckets `count < k`**, k=5 mínimo defensável (k=10 conservador). Com ~47 ativos, provavelmente só SP/GO/RJ sobrevivem a k=5 → mapa esparso (input de produto).

**🔴 Achado já ao vivo:** `get_public_country_reach()` expõe **PT=1** (membro único identificável por país). Recomendação imediata e independente do heatmap: filtrar `HAVING count(*) >= 3` nessa RPC. **Toca prod (padrão R2/R6: levar o `.sql` à main com "vai" do PM).**

**Veredito: CONDICIONAL.** Pode construir após: (a) corrigir PT=1 na RPC existente; (b) opt-in com campo booleano no perfil; (c) supressão k>=5 na RPC nova; (d) normalizar `state`→UF antes de agregar.

---

## 3. Spec do heatmap (p/ sessão limpa)

### Pré-requisitos (gates legais)
- **R1 (imediato, independe do heatmap):** `get_public_country_reach()` → `HAVING count(*) >= 3` (corrige PT=1 live). Migration simples; PR à main com "vai".
- **R2:** coluna `members.allow_state_in_public_map boolean NOT NULL DEFAULT false` (Privacy by Design, opt-out por padrão).
- **R3:** checkbox no perfil (`profile.astro`, junto do campo estado) — texto aprovado pelo legal:
  > "Autorizo a inclusão do meu estado de residência em mapas de distribuição geográfica exibidos publicamente na plataforma Núcleo IA & GP. O dado aparecerá apenas de forma agregada (nunca individual). Você pode revogar a qualquer momento."
  Persistir via RPC de update de perfil. Revogável (Art. 18 §4/§5).
- **R4:** RPC pública `get_public_state_reach()` (padrão de `get_public_country_reach`, SECURITY DEFINER, zero-PII): `WHERE allow_state_in_public_map = true`, **normaliza `state`→UF** (Goiás→GO etc.), `HAVING count(*) >= 5`. Retorno `(state_code text, member_count bigint)`.
- **R5:** registrar base legal (Art. 7º I consentimento) + supressão no COMMENT da RPC e no RoPA.

### Implementação técnica
- **Normalização UF:** tabela/CASE de mapeamento nome→sigla (27 UFs) dentro da RPC (ou função helper). Coalescer `GO`/`Goiás`. Descartar não-Brasil.
- **`BrazilMap.astro`:** hoje pinta fill por presença de capítulo (teal/laranja/cinza). Estender p/ aceitar `density: Record<UF,count>` → **fill = intensidade (escala teal)**, mantendo a marcação de capítulo/fundador por cima (stroke/marcador). Decisão de produto: "densidade + capítulos juntos" (2 leituras no mesmo mapa) — definir legenda dupla.
- **Reaproveita:** `chapter_code`=UF (R9) casa com `id` do SVG; mesma técnica `<style set:html>`.
- **i18n:** legenda nova (densidade) + nota "X sem estado informado" (honestidade sobre os nulls).
- **Contrato de teste:** estender o `cycle4-coverage-map` (anti-hardcode + paridade).

### Considerações de produto (do parecer)
- Com k>=5 e base de ~47, o mapa nasce **esparso** (poucos estados). PM decide se vale agora ou quando a base crescer. Alternativa: subir o heatmap só quando ≥N estados atingirem k.
- Higiene de dado forward: tornar o campo estado do perfil um **select de UF** (não texto livre) resolve a inconsistência daqui pra frente (reduz necessidade de normalização e melhora a cobertura).

---

## 4. Pontos de decisão do PM

| ID | Decisão | Nota |
|---|---|---|
| PD-MAP-1 | Corrigir PT=1 no `get_public_country_reach` AGORA (PR à main)? | 🔴 LGPD live; independe do heatmap |
| PD-MAP-2 | Base legal do heatmap: **opt-in** (consentimento, recomendado) vs LIA+RILPD (mais rápido, mais arriscado) | legal recomenda opt-in |
| PD-MAP-3 | Tornar o campo estado do perfil um **select de UF** (higiene forward)? | reduz normalização + melhora cobertura |
| PD-MAP-4 | Construir o heatmap agora (nasce esparso) ou esperar a base crescer? | input de produto |
| PD-MAP-5 | k de supressão: 5 (mínimo) vs 10 (conservador) | legal: ≥5 obrigatório |

> **Próximo:** sessão limpa executa R1→R5 + render do mapa, com QA e PR(s) à main (com "vai"). Parecer completo do legal-counsel disponível na transcrição da sessão 2026-06-21.
