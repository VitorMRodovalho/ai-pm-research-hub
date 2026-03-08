# Debug Holístico e Prevenção de Regressão

## Objetivo
Evitar correções parciais que resolvem um sintoma e deixam falhas adjacentes ativas.

## Fluxo obrigatório (produção)
1. Reproduzir com evidência:
- URL, perfil afetado, horário, ação exata.
- Resultado esperado vs atual.
2. Mapear cadeia completa:
- UI (click/handler/render)
- sessão/auth (`navGetSb`, `currentMember`)
- API/RPC/Edge Function
- RLS/SQL e persistência
3. Instrumentar antes de alterar:
- mensagem de erro para usuário (toast)
- fallback para estado não pronto (sessão não carregada)
4. Corrigir na origem:
- preferir handlers resilientes (event delegation) em UIs com re-render.
- eliminar dependência frágil de `onclick` inline em fluxos críticos.
5. Validar em camadas:
- unit/smoke local (`npm test`, `npm run build`)
- validação funcional da jornada real em produção
6. Registrar aprendizagem:
- `docs/RELEASE_LOG.md` (o que corrigiu + como validou)
- `docs/GOVERNANCE_CHANGELOG.md` (regra de engenharia se recorrente)

## Checklist anti-regressão (PR)
- [ ] Jornada ponta-a-ponta testada (UI -> RPC/Function -> DB -> UI)
- [ ] Cenário de sessão não pronta coberto
- [ ] Mensagem de erro amigável implementada
- [ ] Build e testes locais verdes
- [ ] Release log atualizado
- [ ] Se houver SQL: apply/audit/rollback documentados

## Aplicação atual
- Caso profile (email secundário + verify Credly): adotar event delegation estável no container e remover dependência de binding por render.
- Caso homepage (prazo tribos + reunião geral): remover textos hardcoded duplicados e centralizar constantes em `src/config/homeSchedule.ts` para evitar divergência entre DB/UI e idiomas.
- Caso Tribes (cards/contadores/entregáveis): validar sempre três camadas juntas antes do deploy:
  - SSR com contrato resolvido (`resolveTribes` + labels de quadrantes)
  - script browser-safe (sem sintaxe TS no HTML final)
  - fallback visível quando dado/client runtime falhar
