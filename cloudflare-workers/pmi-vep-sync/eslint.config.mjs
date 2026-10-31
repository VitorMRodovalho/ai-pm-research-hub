import js from '@eslint/js';
import tsParser from '@typescript-eslint/parser';

// Config própria do worker. Sem ela, o lint usava a config da raiz, que só dá parser TypeScript a
// caminhos do site: os .ts daqui caíam no espree e todo arquivo dava erro fatal de parse. O ESLint 10
// busca a config a partir de cada arquivo, então esta é achada antes da da raiz.
export default [
  {
    ignores: ['node_modules/**', '.wrangler/**', 'dist/**'],
  },
  js.configs.recommended,
  {
    files: ['**/*.ts'],
    languageOptions: {
      parser: tsParser,
      parserOptions: {
        ecmaVersion: 'latest',
        sourceType: 'module',
      },
    },
    rules: {
      // Identificador indefinido já é erro no `tsc --noEmit` do worker.
      'no-undef': 'off',
      // Desligado como nos blocos TypeScript da raiz. O que a regra acha quando ligada está na #2875.
      'no-unused-vars': 'off',
    },
  },
];
