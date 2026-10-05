// The catalog modules and their defaults, read from
// opentofu/bootstrap/catalog.tf at build time, so the landing page cannot
// drift from what ships. The same parse as .github/scripts/check-catalog-clouds.sh;
// the generated catalog (#71, M3.5) replaces both.
import { readFileSync } from 'node:fs';
import path from 'node:path';

// Relative to site/, where Astro runs: once bundled, import.meta.url no
// longer points into src/.
const source = readFileSync(path.resolve(process.cwd(), '../opentofu/bootstrap/catalog.tf'), 'utf8');
const body = /^ {2}catalog += \{\n([\s\S]*?)^ {2}\}/m.exec(source)?.[1];
if (!body) throw new Error('catalog.tf: no `catalog = { … }` block');

/** @type {{ name: string, enabled: boolean }[]} */
export const modules = [...body.matchAll(/^ {4}([a-z][a-z0-9_]*) *= *\{\n {6}enabled *= *(true|false)/gm)].map((m) => ({
  name: m[1],
  enabled: m[2] === 'true',
}));
if (modules.length === 0) throw new Error('catalog.tf: no module found');
