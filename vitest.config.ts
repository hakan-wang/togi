import { defineConfig } from "vitest/config";

export default defineConfig({
  // Match Next's automatic JSX runtime so React components render in tests
  // without an explicit React import.
  esbuild: { jsx: "automatic" },
  test: {
    environment: "node",
    include: ["src/**/*.test.ts", "supabase/**/*.test.ts"]
  },
  resolve: {
    alias: {
      "@": new URL("./src", import.meta.url).pathname
    }
  }
});
