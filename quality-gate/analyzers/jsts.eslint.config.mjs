import { createRequire } from 'node:module';
const require = createRequire(process.env.QC_ESLINT_ANCHOR);
const tseslint = require('typescript-eslint');
const sonarjs = require('eslint-plugin-sonarjs');
export default [
  ...(tseslint.default ?? tseslint).configs.recommended,
  (sonarjs.default ?? sonarjs).configs.recommended,
  { rules: { complexity: ['warn', 15], 'max-lines-per-function': ['warn', 100] } }
];
