import { build } from "esbuild";

// Bundle the Lambda handler into a single ESM file. AWS SDK v3 is available in
// the Lambda Node 22 runtime, so we keep it external to shrink the bundle.
await build({
  entryPoints: ["src/handler.ts"],
  bundle: true,
  platform: "node",
  target: "node22",
  format: "esm",
  outfile: "dist/handler.mjs",
  sourcemap: true,
  banner: {
    // esbuild ESM output uses import.meta; nothing else needed for Node 22.
    js: "",
  },
  external: ["@aws-sdk/*"],
});

console.log("Built dist/handler.mjs");
