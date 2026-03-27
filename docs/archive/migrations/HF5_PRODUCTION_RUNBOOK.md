# HF5 Data Patch — Runbook de Execução em Produção

**Objetivo**: Executar o patch idempotente HF5 no banco de produção para:
1. Restaurar LinkedIn da Sarah (quando em branco)
2. Alinhar `members.operational_role` e `members.designations` com `member_cycle_history` ativo
3. Garantir consistência deputy_manager (co_gp) e manager (sem co_gp)

**Pré-requisitos**: Acesso ao Supabase SQL Editor do projeto de produção.

---

## Passo 1 — Pré-auditoria

No Supabase SQL Editor, execute o conteúdo de:

```
docs/migrations/hf5-audit-data-patch.sql
```

**O que observar**:
- 1) Snapshot dos membros Sarah e Roberto — estado antes do patch
- 1b) Sarah sem LinkedIn — deve retornar 0 linhas *após* o patch; antes pode ter 1
- 2) Mismatches entre `members` e `member_cycle_history` — quantos registros divergem
- 3a) `deputy_manager` sem `co_gp` — quantos precisam de correção
- 3b) `manager` com `co_gp` — quantos precisam de correção

Guarde um print ou export dos resultados para referência.

---

## Passo 2 — Aplicar o patch

Execute o conteúdo de:

```
docs/migrations/hf5-apply-data-patch.sql
```

O script é **idempotente** — pode ser executado mais de uma vez sem efeitos colaterais.

---

## Passo 3 — Pós-auditoria

Execute novamente:

```
docs/migrations/hf5-audit-data-patch.sql
```

**Verificações esperadas**:
- 1b) **0 linhas** — Sarah deve ter LinkedIn preenchido (ou não existir no critério)
- 2) **0 linhas** — nenhum mismatch entre members e cycle history
- 3a) **0 linhas** — nenhum deputy_manager sem co_gp
- 3b) **0 linhas** — nenhum manager com co_gp

---

## Passo 4 — Registrar em RELEASE_LOG

Adicione entrada em `docs/RELEASE_LOG.md`:

```markdown
## YYYY-MM-DD — HF5 Data Patch (Produção)

### Scope
Execução do patch HF5 em produção: Sarah LinkedIn, alinhamento cycle history, deputy hierarchy.

### Delivered
- Executado hf5-apply-data-patch.sql no Supabase produção
- Pós-auditoria confirmou 0 mismatches e 0 inconsistências de hierarchy

### Validation captured
- [Resultados da auditoria pós-patch — anexar evidência ou resumo]
```

---

## Rollback (se necessário)

Não há rollback automático. O patch altera dados com base em `member_cycle_history` como fonte de verdade. Se houver problema:
- Reverter manualmente com base nos dados da pré-auditoria
- Ou rodar queries inversas específicas (contate o time antes de alterar)
