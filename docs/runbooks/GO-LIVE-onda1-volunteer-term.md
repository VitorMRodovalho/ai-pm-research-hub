# Runbook - Go-live Onda 1 do Termo de Adesão do Voluntário (#1153)

**Audiência:** GP / Gerente de Projeto do Núcleo (quem detém `manage_platform`).
**Status:** active (preparado 2026-07-06/07).
**Specs:** `docs/reference/SPEC-1153-volunteer-term-signing-sync.md`.
**Issues:** #1153 (Direção 1) · #1152 (gate `president_go`) · #1155 (F1+F2, merged) · #1156 (F3, este ciclo).

> **Objetivo de negócio.** Destravar a assinatura da 1ª adesão para os ~45 novos C4 **com o texto
> jurídico corrigido** (rodada Aaron/Angeline 06/07, `.docx` V2), fechando a drift entre a versão
> aprovada na cadeia e a versão que o voluntário assina. A assinatura está **bloqueada por design**
> desde 14/04 (nenhum `volunteer_term_template` com `status='active'`); este runbook é o caminho
> controlado para reativá-la sobre a v9.

> **O que Claude NÃO faz.** Claude **não assina** a cadeia por Ivan nem pelos curadores (ato pessoal,
> LGPD Art. 18 / autoridade institucional), e **não ativa** a versão sem o go explícito do GP. As
> etapas de assinatura e ativação são executadas **por pessoas**; Claude apenas prepara, aterra os
> números ao vivo e verifica.

---

## 0. Estado aterrado (2026-07-07 01:24 UTC - reconferir antes de executar)

| Fato | Valor | Fonte (re-query) |
|---|---|---|
| `volunteer_term_template` `status='active'` | **0** (assinatura bloqueada - correto) | INV-1 abaixo |
| Documento (governance) | `280c2c56-e0e3-4b10-be68-6c731d1b4520`, `status=under_review` | `governance_documents` |
| Versão corrente (lacrada) | `246ff8be-9ed8-4a81-9211-bf097750c4c7` - "R3-C3-IP v9 (jurídico V2 Aaron/Angeline 2026-07-06)" | `document_versions` |
| Corpo v9 | `len=28037`, `md5=45041522e8a141ec9ad61dc8d0e82ab1` | `document_versions.content_html` |
| Cadeia de aprovação | `c72ceca4-16f8-4b09-b22a-61381388fbd2`, `status=review` | `approval_chains` |
| Gates | `curator (threshold: all)` → `president_go (threshold: 1)` | `approval_chains.gates` |
| Assinaturas colhidas | **nenhuma** (`gate_state = {}`, `approved_at=NULL`, `activated_at=NULL`) | `approval_chains.gate_state` |

> **Regra de aterramento (CLAUDE.md).** Qualquer número, contagem ou versão que entrar numa decisão,
> commit ou comunicação **tem de vir de um tool result do turno corrente**. As queries abaixo re-aterram
> cada valor. Nunca recitar de memória.

**Re-query do estado (read-only):**

```sql
-- INV-1: quantos templates ativos (esperado 0 ANTES; 1 DEPOIS da ativação)
SELECT count(*) AS active_templates
FROM governance_documents
WHERE doc_type='volunteer_term_template' AND status='active';

-- Cadeia + gates + progresso das assinaturas
SELECT id, status, gates, gate_state, approved_at, activated_at
FROM approval_chains
WHERE document_id='280c2c56-e0e3-4b10-be68-6c731d1b4520'
ORDER BY opened_at DESC NULLS LAST LIMIT 1;

-- Versão corrente + integridade do corpo (comparar md5 com o esperado acima)
SELECT gd.current_version_id, dv.version_label, dv.locked_at,
       length(dv.content_html) AS body_len, md5(dv.content_html) AS body_md5
FROM governance_documents gd
JOIN document_versions dv ON dv.id = gd.current_version_id
WHERE gd.id='280c2c56-e0e3-4b10-be68-6c731d1b4520';
```

---

## 1. Pré-flight (gates que precedem a coleta de assinaturas)

- [ ] **#1155 (F1+F2) em PROD.** O chrome do instrumento diz "Termo de **Adesão** ao Serviço Voluntário"
      e a "Nota sobre renderização" saiu do corpo v9. Confirmar: main em `95c6b0c7`, Worker deployado
      (`50423c5f`). Sem F1 vivo, o PDF re-renderizado mostra o título legado errado.
- [ ] **#1152 (gate `president_go`) em PROD.** `_can_sign_gate` exige SEMPRE `legal_signer`; o carve-out
      `voluntariado_director` foi removido (a diretoria de voluntariado é **contraparte** do instrumento,
      não gate de versão). Migração `20260805000353` aplicada. Verificar ao vivo (substituir os UUIDs):

      ```sql
      SELECT public._can_sign_gate(
        '<member_id>'::uuid,
        'c72ceca4-16f8-4b09-b22a-61381388fbd2'::uuid,
        'president_go', 'volunteer_term_template') AS can_sign;
      ```
      Esperado: Ivan (legal_signer) = `true`; Lorena (contraparte, não legal_signer) = `false`.
- [ ] **#1156 (F3) - recomendado, NÃO bloqueante.** A Cláusula 14 (Transferência Internacional de
      Dados) passa a renderizar **condicionalmente** por residência (EEE/UK). Como C4 é majoritariamente
      BR e a cláusula é auto-escopada, o release dos 45 não fica bloqueado por F3; mas deployar F3 antes
      do release deixa o BR sem a cláusula fora de escopo e o (raro) residente EEE/UK com ela. Ver §6.
- [ ] **Diff `.docx` V2 × corpo vivo = limpo.** Já validado (handoff 06/07): 6 docs, 2.6.4 resolvida
      (âncora art. 49 IV mantida), CNPJ do preâmbulo bate o cartão da Receita (`06.065.645/0001-99`).
      Se o `md5` do corpo divergir do aterrado em §0, **PARAR** e reconferir a cadeia antes de assinar.

---

## 2. Coletar as assinaturas da cadeia (ato humano - pela plataforma)

A cadeia `c72ceca4` exige, **nesta ordem**: **todos os curadores** (gate `curator`, threshold `all`) e
depois **1 `president_go`** (Ivan, `legal_signer`). São ~4 atos: 3 curadores + Ivan (reconfirmar a
contagem exata pela query abaixo - a roster é derivada de autoridade, não hardcoded).

Os signatários assinam **pela plataforma** (CTA de ratificação no leitor de governança), que chama
`sign_ip_ratification(p_chain_id, p_gate_kind, ...)`. **Não** rodar isso por SQL em nome de terceiros.

**Monitorar o progresso (read-only, GP):**

```sql
-- Quem ainda falta assinar / estado por gate
SELECT * FROM public.get_pending_ratifications();

-- Trilha de auditoria da cadeia (assinaturas colhidas, ordem, timestamps)
SELECT * FROM public.get_chain_audit_report('c72ceca4-16f8-4b09-b22a-61381388fbd2'::uuid);
```

- [ ] Todos os curadores assinaram (gate 1 `curator` satisfeito).
- [ ] Ivan assinou o `president_go` (gate 2 satisfeito).
- [ ] `approval_chains.approved_at` **deixou de ser NULL** para a cadeia `c72ceca4`.

> **Se um signatário travar / trocar:** a cadeia é lacre da v9; não editar o corpo. Se for preciso
> recircular por mudança de signatários ou nova rodada, usar `recirculate_governance_doc(p_chain_id,
> p_dry_run=>true, ...)` primeiro (dry-run) e só então com `p_dry_run=>false`. Recircular reinicia a
> coleta - não é atalho.

---

## 3. Ativar a versão (ato do GP - `manage_platform`)

**Só após `approved_at` da cadeia estar preenchido.** A ativação é atômica e idempotente-por-INV-1:
supersede qualquer outra `active` e ativa a v9; só ativa uma versão **lacrada**.

```sql
-- GP autenticado (manage_platform). Ativa a v9 do doc 280c2c56.
SELECT public.activate_volunteer_term_version('280c2c56-e0e3-4b10-be68-6c731d1b4520'::uuid);

-- Recarregar o schema cache do PostgREST se necessário (não custa)
NOTIFY pgrst, 'reload schema';
```

**Pós-ativação (confirmar INV-1 = exatamente 1):**

```sql
SELECT id, version, status
FROM governance_documents
WHERE doc_type='volunteer_term_template' AND status='active';
-- Esperado: 1 linha, a v9 (280c2c56 / 246ff8be).
```

- [ ] `active_templates = 1` (era 0).
- [ ] `activated_at` da cadeia preenchido.

---

## 4. Smoke QA do instrumento assinado (gate ANTES de liberar os 45)

Objetivo: provar que **texto assinado == texto jurídico aprovado (`.docx` V2)** e que o chrome (F1),
o corpo v9 (F2) e a condicional EEE/UK (F3) renderizam certo.

1. **Uma adesão de teste, com rollback.** Assinar o Termo por um usuário de teste (ou impersonação com
   `set local role authenticated` + `request.jwt.claims` numa transação, revertida - padrão usado no
   #1094) e gerar o PDF do instrumento.
2. **Conferências no PDF:**
   - [ ] Título do chrome: "Termo de **Adesão** ao Serviço Voluntário com o {forma curta do capítulo}"
         (F1). NÃO "Termo de Compromisso".
   - [ ] `{chapterName}` resolvido no corpo (nunca `{chapterName}` cru - INV-2).
   - [ ] Corpo == v9: Cláusulas 1→16, sem a "Nota sobre renderização" (F2).
   - [ ] **F3 - residência BR:** a **Cláusula 14** (Transferência Internacional de Dados) **NÃO** aparece.
   - [ ] **F3 - residência EEE/UK:** a Cláusula 14 **aparece** (testar com `member_country` = ex.
         "Portugal" / "Reino Unido").
3. **INV-2 ao vivo (nenhum snapshot com `{chapterName}` cru):**

   ```sql
   SELECT verification_code
   FROM certificates
   WHERE type='volunteer_agreement'
     AND content_snapshot->>'html_body' LIKE '%{chapterName}%';
   -- Esperado: 0 linhas.
   ```

- [ ] Smoke aprovado. **Se qualquer item falhar: NÃO liberar.** Rollback e diagnosticar.

**Plano de rollback (se o smoke reprovar):** supersede a v9 e voltar ao estado `active=0` (assinatura
volta a ficar bloqueada - o estado seguro):

```sql
UPDATE governance_documents
SET status='under_review'
WHERE id='280c2c56-e0e3-4b10-be68-6c731d1b4520' AND status='active';
-- Confirmar: active_templates volta a 0. Nenhuma nova adesão é possível até re-ativar.
```

> Adesões de **teste** devem ser removidas/anonimizadas após o smoke (LGPD). Adesões **reais** são
> imutáveis (#648) - não mexer.

---

## 5. Liberar os 45 novos C4

- [ ] Comunicar aos 45 (e-mail institucional `nucleoia@` / alias `nucleoia.pmigo.org.br` - nunca o
      domínio pessoal em comunicação a membros). Se houver draft no Gmail, **enviar de `nucleoia@`**.
- [ ] Confirmar que a jornada de assinatura destrava (o picker de tribo / kickoff era gated por termo
      assinado - 35/40 C4 estavam bloqueados em 06/07; ver #1139/#1153).
- [ ] Monitorar as primeiras adesões: `verification_code` gerado, `content_snapshot.html_body` gravado,
      contra-assinatura institucional pendente.

**Re-aceite dos ativos (Onda 2) é DESACOPLADO** desta Onda 1: os voluntários já ativos re-aceitam depois,
via `recirculate` (Material change, Cláusula 15.3), fora do escopo deste runbook.

---

## 6. F3 (#1156) - renderização condicional da Cláusula 14 (contexto)

O instrumento assinado renderiza o **corpo aprovado inteiro** (Direção 1). Pela `.docx` V2 a Cláusula 14
(consentimento GDPR/UK-GDPR Art. 49(1)(a) para transferência internacional) aplica-se **só a residentes
no EEE ou no Reino Unido**. F3 torna a renderização condicional em `pdf.ts`:

- Deriva de `certData.member_country` (congelado no snapshot da assinatura → estável em re-renders).
- **Não muda o corpo aprovado/snapshotado** (single source == `.docx`, INV-2): o superset fica no
  snapshot; a condicional é decisão de **render**.
- Detecção: marcador explícito `data-conditional="eee-uk"` (forward-compat) **ou** âncora semântica pelo
  título da cláusula ("Transferência Internacional de Dados"), varrendo até o próximo cabeçalho
  `Cláusula N.`. Verificado no corpo v9 real (28037 chars): residência BR/desconhecida remove exatamente
  a Cláusula 14 (2724 chars) preservando 13/15/16; EEE/UK mantém.
- **Default de residência desconhecida = omitir** (cláusula auto-escopada + consentimento Art. 49(1)(a)
  só é válido para residente EEE/UK declarado; provisões gerais da Cláusula 9 continuam valendo).

Código: `src/lib/certificates/conditional-clauses.ts` (leaf, testável) consumido por
`buildVolunteerAgreementHTML`. Trava: `tests/contracts/1156-volunteer-term-eee-uk-conditional-clause.test.mjs`.

---

## Cross-ref

- Drift 2-representações que motivou a Direção 1: memória `reference-volunteer-term-signing-representation-drift`.
- Jornada de tribo gated por termo: `reference-tribe-selection-hybrid-journey` (#1139/#1153).
- `members.cycles` não é fonte de coorte confiável: `reference-members-cycles-unreliable-cohort-source`.
- Merge à main = só a sessão dev/main: memória `feedback-merge-to-main-is-main-session-only`.
