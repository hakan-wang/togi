import { build } from "esbuild";

await build({
  entryPoints: ["src/main.ts"],
  bundle: true,
  platform: "node",
  target: "node22",
  format: "cjs",
  outfile: "dist/main.cjs",
  external: ["better-sqlite3"],
});
console.log("sidecar bundled -> dist/main.cjs");
