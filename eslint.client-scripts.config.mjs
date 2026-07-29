// #1205 gate — free identifiers in .astro client `<script>` blocks.
//
// A client `<script>` in a .astro file is bundled as an ES module, so it runs in strict mode and
// a free identifier is a runtime ReferenceError, not a silent global. Nothing type-checks these
// blocks today (`astro check` needs @astrojs/check, which is not installed), so `no-undef` is the
// only gate that catches the class. It found `shareWa` in profile.astro, shipped and broken since
// 2026-03-24: clicking "Salvar" with no field changed threw, and saveSelf() has no catch, so the
// save failed with no toast at all. Same sweep found `cycleOn` (gamification.astro), four
// top-level assignments to undeclared names (admin/member/[id].astro) and a frontmatter-only
// import referenced from the browser (admin/cycle-report.astro).
//
// Deliberately separate from eslint.config.mjs: this config lints ONLY the virtual script blocks
// and ONLY for no-undef. The repo's main config also covers .astro frontmatter, which carries
// ~159 pre-existing style findings; folding the gate in there would bury the ReferenceError class
// and the gate would never go green.
//
// Run: npm run lint:client-scripts (wired into CI; guarded by
// tests/contracts/1205-client-script-undef-gate-wired.test.mjs).
import js from '@eslint/js';
import globals from 'globals';
import astroPlugin from 'eslint-plugin-astro';
import tsParser from '@typescript-eslint/parser';

export default [
  { ignores: ['dist/**', 'node_modules/**', '.astro/**'] },
  ...astroPlugin.configs.recommended,
  {
    files: ['**/*.astro/*.ts', '**/*.astro/*.js'],
    languageOptions: {
      parser: tsParser,
      parserOptions: { sourceType: 'module' },
      globals: {
        ...globals.browser,
        // Injected on window by Nav (see src/components/Nav.astro), read bare in several pages.
        navGetSb: 'readonly',
        navGetMember: 'readonly',
        toast: 'readonly',
        // DOM lib type names: they appear in type positions, and no-undef cannot tell a type
        // reference from a value reference.
        EventListener: 'readonly',
        NodeListOf: 'readonly',
      },
    },
    rules: {
      ...Object.fromEntries(Object.keys(js.configs.recommended.rules).map((rule) => [rule, 'off'])),
      'no-undef': 'error',
    },
  },
];
