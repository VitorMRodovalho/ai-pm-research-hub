// tests/helpers/contract-whitelist-skips.mjs
//
// Quarentena declarada de testes de contrato: arquivos que existem em disco e, de propósito, NÃO
// estão nas listas do `package.json`.
//
// Extraído de `tests/contracts/1109-contract-whitelist-completeness.test.mjs` na A1 (#1908) para
// ter UMA fonte. Dois consumidores precisam da mesma lista — o guard do #1109 e o classificador
// `scripts/classify-test-suite.mjs`, que varre `tests/` inteiro para a partição estrutural x
// comportamental. Duas cópias divergiriam, e a divergência apareceria como "teste sumiu do CI",
// que é exatamente o que esta lista existe para impedir. Mesmo padrão do
// `tests/helpers/rpc-body-drift-parser.mjs`, compartilhado entre teste e script.
//
// ⚠️ Cada entrada precisa de motivo escrito E issue viva. Sem issue é silenciamento, não
// quarentena. O guard do #1109 valida as entradas contra o disco e contra as listas: uma desculpa
// velha, de arquivo já religado, reprova igual.

/** @type {{file: string, reason: string, issue: number}[]} */
export const SKIP_LIST = [
  {
    file: 'ip-gate-templates.test.mjs',
    reason:
      'Deterministic policy-drift: resolve_default_gates diverged from the test ' +
      '(first gate committee_majority != curator; executive_summary returns gates ' +
      "!= NULL; threshold 'majority' not number/'all') since ADR-0016 C9 (9d2eea3c). " +
      'Never wired into either whitelist; not running in CI. Reconcile test-vs-policy.',
    issue: 1340,
  },
];

/** Só os basenames, para checagem de pertinência. */
export const SKIP_SET = new Set(SKIP_LIST.map((e) => e.file));

/** Caminhos relativos à raiz do repo, como o classificador da A1 os enxerga. */
export const SKIP_PATHS = SKIP_LIST.map((e) => `tests/contracts/${e.file}`);
