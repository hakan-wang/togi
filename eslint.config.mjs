import { FlatCompat } from "@eslint/eslintrc";

const compat = new FlatCompat({
  baseDirectory: import.meta.dirname
});

const config = [
  {
    ignores: [".next/**", "node_modules/**", "tsconfig.tsbuildinfo"]
  },
  ...compat.extends("next/core-web-vitals")
];

export default config;
