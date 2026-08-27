/**
 * Registra o hook de resolução do repo. Uso:
 *   node --import ./scripts/lib/register-ts-resolve.mjs scripts/<algum>.ts
 * Ver `ts-resolve-hook.mjs` para o porquê.
 */
import { register } from 'node:module';
import { pathToFileURL } from 'node:url';

register('./ts-resolve-hook.mjs', pathToFileURL(import.meta.dirname + '/'));
