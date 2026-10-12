import * as esbuild from "esbuild";
await esbuild.build({
  entryPoints: ["src/main.js"],
  bundle: true,
  minify: true,
  format: "iife",
  target: ["safari17"],
  outfile: "../Resources/editor/editor.js",
  legalComments: "none",
});
console.log("built ../Resources/editor/editor.js");
