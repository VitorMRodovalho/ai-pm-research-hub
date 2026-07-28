# #1477 — check_my_tcv_readiness: carve-out cirúrgico (rota A) — spec de execução

> **Status:** decisão do owner RATIFICADA 2026-07-24 = **rota A (carve-out cirúrgico)**. Execução SERIALIZADA:
> só aplicar o DDL DEPOIS do merge do PR #1483 (wave2), senão o gate de body-drift fica vermelho no #1483 e na
> main (a função é drift-clean hoje; corpo vivo divergir da captura em main = red em toda CI que lê prod).
> Ver [[reference-shared-db-drift-gate-serializes-ddl-prs]]. NÃO aplicado em prod neste lane.

## Bug (aterrado ao vivo 2026-07-24)
`check_my_tcv_readiness()` isenta do TCV por `operational_role IN ('sponsor','chapter_liaison','observer','candidate','visitor')`
— lê o cache de EXIBIÇÃO `operational_role`, que colapsa multi-hat (antipadrão do arco #1476). Resultado:
**2 membros `chapter_liaison` que TÊM engagement operacional** (via `v_member_operational_tiers`) escapam do TCV
mas deveriam assinar.

## Before/after ao vivo (fonte: members × v_member_operational_tiers, 2026-07-24)
| operational_role | isento hoje | tem eng. operacional | n | rota A | rota B |
|---|---|---|---|---|---|
| chapter_liaison | sim | **sim** | **2** | vira NÃO-isento (corrige) | vira NÃO-isento (corrige) |
| chapter_liaison/sponsor | sim | não | 14 | segue isento | segue isento |
| researcher/tribe_leader/manager | não | sim | 69 | segue não-isento | segue não-isento |
| alumni/guest/none | não | não | **45** (25/15/5) | **segue não-isento (0 ripple)** | vira isento (ripple) |

Rota A escolhida: corrige os 2 dual-hat com **0 ripple**. Razão: gate legal (TCV é contratual PMI-GO); erro da A
é só over-inclusivo, erro da B seria lacuna de conformidade se a view omitir um voluntário operacional real.

## Mudança (predicado único)
No bloco de isenção, adicionar a condição `AND NOT EXISTS (... v_member_operational_tiers ...)`:

```sql
-- ANTES:
IF v_member.operational_role IN ('sponsor', 'chapter_liaison', 'observer', 'candidate', 'visitor') THEN
    RETURN jsonb_build_object('applicable', false, 'reason', 'role_exempt');
END IF;

-- DEPOIS (rota A — carve-out: label isenta SÓ se não houver engagement operacional):
IF v_member.operational_role IN ('sponsor', 'chapter_liaison', 'observer', 'candidate', 'visitor')
   AND NOT EXISTS (
     SELECT 1 FROM public.v_member_operational_tiers t WHERE t.member_id = v_member.id
   ) THEN
    RETURN jsonb_build_object('applicable', false, 'reason', 'role_exempt');
END IF;
```

Dual-hat (label + engagement) cai para o check real de campos (`applicable=true`) → é solicitado a assinar.

## Ritual de execução (na onda curta, pós-merge #1483)
1. `CREATE OR REPLACE FUNCTION` baseado no corpo VIVO (`pg_get_functiondef`, não grep na 1ª migração) —
   [[reference-create-or-replace-base-on-live-body]]. Só o predicado acima muda.
2. `apply_migration` BYTE-fiel ao arquivo (comentário stripped já mordeu #785 antes) —
   [[reference-apply-migration-comment-word-flips-text-audit]].
3. `Write` migração local `supabase/migrations/<ts>_1477_tcv_carveout_engagement.sql` (ts > head atual);
   `supabase migration repair --status applied <ts>`; **deletar phantom row** por versão exata;
   `NOTIFY pgrst, 'reload schema'` (superfície PostgREST muda).
4. Contract test novo `tests/contracts/1477-tcv-carveout.test.mjs` (static: predicado presente; live: os 2
   dual-hat com engagement retornam `applicable=true`, um label sem engagement retorna `role_exempt`).
   Registrar nas **2 whitelists** do `package.json` (`test` + `test:contracts`).
5. `npx astro build` + `npm test` com secrets → verde. Preparar PR (`Closes #1477`); merge = sessão main.
