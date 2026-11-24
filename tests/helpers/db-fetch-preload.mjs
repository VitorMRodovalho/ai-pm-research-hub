// #3192: carregado com `--import` por todo `node --test` da suite (scripts/run-suite.mjs e os scripts
// do package.json que chamam `node --test` direto). Instala no `fetch` global a mesma repeticao do
// `dbFetch` para os hosts do Supabase, de forma que nenhum teste DB-aware escape dela, inclusive os
// que usam `createClient`. O que ela repete e por que esta em ./db-fetch.mjs.
import { instalarNoFetchGlobal } from './db-fetch.mjs';

instalarNoFetchGlobal();
