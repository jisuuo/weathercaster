// https://docs.expo.dev/guides/using-eslint/
const expoConfig = require('eslint-config-expo/flat');
const eslintConfigPrettier = require('eslint-config-prettier');

module.exports = [
  {
    // supabase/.temp 는 `supabase start` 가 만드는 런타임 산물이다(git 도 무시한다).
    // flat config 는 .gitignore 를 안 읽으므로 여기서 따로 빼야 한다.
    ignores: [
      'node_modules/**',
      '.expo/**',
      'dist/**',
      'out/**',
      'coverage/**',
      'supabase/.temp/**',
      'supabase/.branches/**',
    ],
  },
  ...expoConfig,
  eslintConfigPrettier,
];
