import js from '@eslint/js';
import reactPlugin from 'eslint-plugin-react';
import astroPlugin from 'eslint-plugin-astro';
import astroParser from 'astro-eslint-parser';
import tsParser from '@typescript-eslint/parser';

export default [
  {
    ignores: ['dist/**', 'node_modules/**', '.astro/**'],
  },
  js.configs.recommended,
  ...astroPlugin.configs.recommended,
  {
    files: ['src/components/boards/**/*.tsx'],
    languageOptions: {
      parser: tsParser,
      parserOptions: {
        ecmaVersion: 'latest',
        sourceType: 'module',
        ecmaFeatures: { jsx: true },
      },
    },
    plugins: {
      react: reactPlugin,
    },
    rules: {
      'no-undef': 'off',
      'no-unused-vars': 'off',
      'react/jsx-no-literals': ['error', { noStrings: true, ignoreProps: true }],
    },
    settings: {
      react: {
        version: 'detect',
      },
    },
  },
  {
    files: ['src/pages/admin/portfolio.astro'],
    languageOptions: {
      parser: astroParser,
      parserOptions: {
        parser: tsParser,
      },
    },
    plugins: {
      react: reactPlugin,
    },
    rules: {
      'no-undef': 'off',
      'no-unused-vars': 'off',
      'react/jsx-no-literals': ['error', { noStrings: true, ignoreProps: true }],
    },
  },
];
