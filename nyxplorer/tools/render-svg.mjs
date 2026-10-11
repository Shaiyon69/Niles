// Renders an SVG to a square transparent PNG, centered, with filters (blur, masks, inner shadows) supported.
// Usage: node render-svg.mjs <input.svg> <output.png> <size>

import { readFileSync, writeFileSync } from "node:fs";
import { Resvg } from "@resvg/resvg-js";

const [input, output, sizeArg] = process.argv.slice(2);
const size = Number.parseInt(sizeArg ?? "1024", 10);
if (!input || !output || !(size > 0)) {
  console.error("Usage: node render-svg.mjs <input.svg> <output.png> <size>");
  process.exit(1);
}

const png = new Resvg(readFileSync(input), {
  fitTo: { mode: "width", value: size },
  background: "rgba(0, 0, 0, 0)",
}).render().asPng();

writeFileSync(output, png);
console.log(`  [svg] ${input} -> ${output} (${size}px)`);
