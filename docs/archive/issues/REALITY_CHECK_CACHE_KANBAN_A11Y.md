# Reality Check: Cache, Kanban Vazio & Acessibilidade Radix

**Data:** 2026-03-11  
**Commits:** `eb61462` (fix principal), `8b89c67` (revert debug)  
**Agente:** Cursor (sessão b653b865)  
**Status:** Parcialmente resolvido — cache validado, dados corrigidos, a11y corrigido. Kanban depende de validação em produção com utilizador autenticado.

---

## Contexto

Após múltiplos deploys (Fase 2 e 3 do CXO Task Force), três problemas persistiam em produção:

1. **Header da Tribo** exibia fundo escuro/transparente apesar do código fonte ter `bg-white`
2. **Warnings Radix** no console: `DialogContent requires a DialogTitle`
3. **Kanban vazio** para Tribo 2 (Débora) — 0 cards apesar de 193 items importados do Miro

---

## Diagnóstico Realizado

### Ponto 1: Cache do Cloudflare

**Método:** Grep no ficheiro `src/pages/tribe/[id].astro` por `bg-black`, `linear-gradient`, `text-shadow`.

**Resultado:** Zero referências ao design antigo. O ficheiro já continha `bg-white` correto. Problema era cache do Cloudflare servindo versão antiga.

**Prova:** Injetámos `bg-red-500` no header, fizemos deploy, e o CPO confirmou que o vermelho apareceu — cache quebrado.

### Ponto 2: Acessibilidade Radix

**Método:** Grep no `TribeKanbanIsland.tsx` por `DialogTitle`, `DialogDescription`.

**Resultado:** Nenhum `Dialog.Title` existia dentro do `Dialog.Content`.

**Fix:**
- Instalado `@radix-ui/react-visually-hidden`
- Adicionado `<VisuallyHidden asChild><Dialog.Title>Editar card</Dialog.Title></VisuallyHidden>`
- Adicionado `aria-describedby={undefined}` no `Dialog.Content`

### Ponto 3: Kanban Vazio — CAUSA RAIZ

**Método:** Queries diretas ao Supabase com `service_role_key`.

**Descobertas em sequência:**

1. Board da T2 (`10d4c04a-...`) tem **0 items** — nenhum dado importado diretamente
2. Board da T6 (`118b55be-...`) tem **193 items** (importação Miro)
3. A RPC `list_legacy_board_items_for_tribe` retornava **0 items** para T2
4. **Causa raiz:** `member_cycle_history` da Débora no Ciclo 2 tinha `tribe_id = NULL`:

```json
{
  "cycle_code": "cycle_2",
  "tribe_id": null,
  "tribe_name": "T6: Equipes Híbridas",
  "operational_role": "tribe_leader"
}
```

5. **Problema sistêmico:** TODOS os registros de `member_cycle_history` dos ciclos 1, 2 e pilot tinham `tribe_id = NULL`. Apenas ciclo 3 tinha `tribe_id` preenchido.

6. A RPC fazia `pb.tribe_id IN (SELECT mch.tribe_id ...)` — em SQL, `IN (NULL)` nunca é verdadeiro.

---

## Correções Aplicadas

### Migration `20260316100000_fix_legacy_tribe_ids_and_rpc.sql`

**Data healing:**
```sql
UPDATE public.member_cycle_history mch
SET tribe_id = t.id
FROM public.tribes t
WHERE mch.tribe_id IS NULL
  AND mch.tribe_name IS NOT NULL
  AND (
    mch.tribe_name ILIKE '%' || t.name || '%'
    OR mch.tribe_name ILIKE 'T' || t.id::text || ':%'
  );
```

**Resultado:** Zero registros ficaram com `tribe_id = NULL` + `tribe_name` preenchido.

**RPC resiliente:** Adicionado fallback por `tribe_name` na RPC para casos futuros:
```sql
OR pb.tribe_id IN (
  SELECT tr.id
  FROM public.member_cycle_history mch2
  JOIN public.tribes tr ON mch2.tribe_name ILIKE '%' || tr.name || '%'
  WHERE mch2.member_id = v_leader_id
    AND mch2.operational_role = 'tribe_leader'
    AND mch2.tribe_id IS NULL
    AND mch2.tribe_name IS NOT NULL
)
```

### Console.log de diagnóstico

Adicionados em `TribeKanbanIsland.tsx` para auditoria em produção:
```
[Kanban] Board items: <count> Error: <err>
[Kanban] Legacy items: <count> Error: <err>
[Kanban] Combined items: <total> (board: <n> + legacy: <n>)
```

---

## Testes Executados

| Teste | Resultado |
|-------|-----------|
| `npm run build` | OK |
| `npm test` (100 testes) | 100/100 pass |
| ReadLints em ficheiros editados | 0 erros |
| Query direta T2 board items | 0 (esperado) |
| Query direta T6 board items | 193 |
| Débora `member_cycle_history` pós-fix | `tribe_id = 6` no cycle_2 |
| Registros NULL tribe_id + tribe_name pós-fix | 0 |
| RPC via service_role_key | 0 (esperado — `auth.uid()` é NULL com service role) |
| Validação manual da lógica RPC | Débora → T6 (cycle_2) → board T6 → 193 items |
| Deploy Cloudflare (bg-red-500 test) | CPO confirmou vermelho visível |
| Deploy Cloudflare (bg-white revert) | Push `8b89c67` enviado |

---

## Limitação Conhecida / Ponto em Aberto

A RPC `list_legacy_board_items_for_tribe` usa `auth.uid()` para identificar o caller. Isso significa:

- **Não é testável** via `service_role_key` (retorna sempre 0)
- **Depende de login real** — só funciona quando Débora (ou superadmin/manager) está autenticada
- O CPO confirmou que os 193 cards apareceram no F12 em produção com utilizador autenticado

**Se o Kanban continuar vazio para algum utilizador:**
1. Verificar no F12 os logs `[Kanban]`
2. Se `Legacy items: 0` e `Error: null` → o utilizador não tem permissão (não é líder, superadmin ou manager)
3. Se `Legacy items: 0` e `Error: { code: '42501' }` → problema de RLS
4. Se `Legacy items: NOT_ARRAY` → a RPC não existe ou falhou

---

## Lições Aprendidas

1. **Dados legados são minas terrestres.** O `member_cycle_history` foi populado em fases diferentes com qualidade de dados diferente. Ciclos antigos não tinham `tribe_id` — só `tribe_name` como texto livre. Qualquer RPC que dependa de JOINs por `tribe_id` vai falhar silenciosamente.

2. **`IN (NULL)` é invisível.** SQL não gera erro quando `IN (subquery)` retorna NULL — simplesmente não faz match. Isso torna o bug silencioso e difícil de diagnosticar sem queries manuais.

3. **Cache do Cloudflare é real.** Mesmo com novo deploy, assets podem ficar presos. O teste `bg-red-500` é uma técnica eficaz para validar que o CDN está a servir a versão correta.

4. **Radix exige a11y explícita.** `Dialog.Content` sem `Dialog.Title` gera warnings em runtime. Usar `VisuallyHidden` é a solução canónica.

5. **RPCs com `auth.uid()` não são testáveis com service role.** Para testes automatizados futuros, considerar criar uma versão `_admin` da RPC que aceite `p_caller_id` como parâmetro (restrita a superadmin).

6. **Console.log temporários são valiosos em produção.** Permitiram ao CPO validar em tempo real o que a aplicação estava a receber do Supabase.

---

## Ficheiros Modificados

| Ficheiro | Alteração |
|----------|-----------|
| `src/pages/tribe/[id].astro` | bg-red-500 → bg-white (cache test + revert) |
| `src/components/boards/TribeKanbanIsland.tsx` | DialogTitle a11y + console.log diagnóstico |
| `supabase/migrations/20260316100000_fix_legacy_tribe_ids_and_rpc.sql` | Data healing + RPC resiliente |
| `package.json` / `package-lock.json` | `@radix-ui/react-visually-hidden` adicionado |
