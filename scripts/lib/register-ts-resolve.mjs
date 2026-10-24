/**
 * Registra o hook de resolução do repo. Uso:
 *   node --import ./scripts/lib/register-ts-resolve.mjs scripts/<algum>.ts
 * Ver `ts-resolve-hook.mjs` para o porquê.
 *
 * `registerHooks` (síncrono, na mesma thread) e não `register` (assíncrono, em outra thread):
 * o Node 26 depreciou `module.register()` em runtime (DEP0205, "será removido"), e o 24 já o
 * marca depreciado na documentação desde 24.15.0. `registerHooks` existe desde 22.15.0 (#2774).
 */
import { registerHooks } from 'node:module';
import { resolve } from './ts-resolve-hook.mjs';

registerHooks({ resolve });
