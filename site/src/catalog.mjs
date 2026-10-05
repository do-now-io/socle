// The catalog modules as the landing page shows them, read at build time so
// the page cannot drift from what ships:
//   opentofu/bootstrap/catalog.tf   which modules exist, on by default or not,
//                                   and on which clouds (catalog_clouds)
//   docs/catalog/<module>.md        description and category (frontmatter)
// The same parse as .github/scripts/check-catalog-clouds.sh; the generated
// catalog (#71, M3.5) replaces both.
import { readFileSync } from 'node:fs';
import path from 'node:path';

// Relative to site/, where Astro runs: once bundled, import.meta.url no
// longer points into src/.
const repo = path.resolve(process.cwd(), '..');
const source = readFileSync(path.join(repo, 'opentofu/bootstrap/catalog.tf'), 'utf8');
const body = /^ {2}catalog += \{\n([\s\S]*?)^ {2}\}/m.exec(source)?.[1];
if (!body) throw new Error('catalog.tf: no `catalog = { … }` block');
const cloudsBody = /^ {2}catalog_clouds += \{([\s\S]*?)\}/m.exec(source)?.[1] ?? '';
const restricted = Object.fromEntries(
  [...cloudsBody.matchAll(/^\s*([a-z][a-z0-9_]*) *= *\[([^\]]*)\]/gm)].map((m) => [m[1], [...m[2].matchAll(/"([a-z]+)"/g)].map((c) => c[1])]),
);

function frontmatter(page) {
  const text = readFileSync(path.join(repo, 'docs/catalog', `${page}.md`), 'utf8');
  const head = /^---\n([\s\S]*?)\n---/.exec(text)?.[1] ?? '';
  const field = (name) => {
    const raw = new RegExp(`^${name}: *(.*)$`, 'm').exec(head)?.[1]?.trim() ?? '';
    return raw.replace(/^(['"])(.*)\1$/, '$2').replace(/''/g, "'");
  };
  // requires: [{ module, clouds? }], as written in the page's frontmatter.
  const requires = [...head.matchAll(/^ {2}- module: *([a-z0-9_-]+)\n(?: {4}clouds: *\[([^\]]*)\]\n)?/gm)].map((r) => ({
    module: r[1],
    clouds: r[2] ? r[2].split(',').map((c) => c.trim()) : null,
  }));
  return { description: field('description'), category: field('category'), requires };
}

/** @type {{ name: string, page: string, enabled: boolean, clouds: string[] | null, description: string, category: string, requires: { module: string, clouds: string[] | null }[] }[]} */
export const modules = [...body.matchAll(/^ {4}([a-z][a-z0-9_]*) *= *\{\n {6}enabled *= *(true|false)/gm)].map((m) => {
  const page = m[1].replace(/_/g, '-');
  return { name: m[1], page, enabled: m[2] === 'true', clouds: restricted[m[1]] ?? null, ...frontmatter(page) };
});
if (modules.length === 0) throw new Error('catalog.tf: no module found');
for (const m of modules) {
  if (!m.description || !m.category) throw new Error(`docs/catalog/${m.page}.md: frontmatter needs description and category`);
}
