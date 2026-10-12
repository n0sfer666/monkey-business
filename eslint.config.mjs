import fs from 'node:fs';

import js from '@eslint/js';
import prettier from 'eslint-config-prettier';
import globals from 'globals';

const LUCI = 'luci/htdocs/luci-static/resources';
const REQUIRE = /^\s*'require\s+([\w.-]+)(?:\s+as\s+(\w+))?';/gm;

const required = (file) =>
  Object.fromEntries([...fs.readFileSync(file, 'utf8').matchAll(REQUIRE)].map((m) => [m[2] || m[1], 'readonly']));

const views = fs.globSync(`${LUCI}/**/*.js`).map((file) => ({
  files: [file],
  languageOptions: { globals: required(file) },
}));

export default [
  { ignores: ['.context/**', '.claude/**', '.dev-vm/**', 'build/**', 'dist/**'] },
  js.configs.recommended,
  {
    languageOptions: { ecmaVersion: 'latest', globals: globals.node, sourceType: 'commonjs' },
    rules: {
      eqeqeq: ['error', 'always', { null: 'ignore' }],
      'no-empty': ['error', { allowEmptyCatch: true }],
      'no-unused-vars': ['error', { argsIgnorePattern: '^_', caughtErrorsIgnorePattern: '^_' }],
      'padding-line-between-statements': [
        'error',
        { blankLine: 'always', next: 'return', prev: '*' },
        { blankLine: 'always', next: '*', prev: ['const', 'let', 'var'] },
        { blankLine: 'any', next: ['const', 'let', 'var'], prev: ['const', 'let', 'var'] },
      ],
    },
  },
  { files: ['**/*.mjs'], languageOptions: { sourceType: 'module' } },
  { files: ['scripts/ui-diff/**/*.js'], languageOptions: { globals: globals.browser } },
  {
    files: [`${LUCI}/**/*.js`],
    languageOptions: {
      globals: { ...globals.browser, _: 'readonly', E: 'readonly', L: 'readonly', N_: 'readonly' },
      parserOptions: { ecmaFeatures: { globalReturn: true } },
      sourceType: 'script',
    },
    rules: { 'no-console': ['error', { allow: ['warn', 'error'] }] },
  },
  ...views,
  prettier,
];
