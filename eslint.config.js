// https://docs.expo.dev/guides/using-eslint/
const expoConfig = require('eslint-config-expo/flat');
const eslintConfigPrettier = require('eslint-config-prettier');

module.exports = [
  {
    ignores: ['node_modules/**', '.expo/**', 'dist/**', 'out/**', 'coverage/**'],
  },
  ...expoConfig,
  eslintConfigPrettier,
];
