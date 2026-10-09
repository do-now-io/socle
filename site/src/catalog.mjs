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
  const requires = [
    ...head.matchAll(/^ {2}- module: *([a-z0-9_-]+)\n(?: {4}clouds: *\[([^\]]*)\]\n)?(?: {4}why: *(.*)\n?)?/gm),
  ].map((r) => ({
    module: r[1],
    clouds: r[2] ? r[2].split(',').map((c) => c.trim()) : null,
    why: (r[3] ?? '').trim().replace(/^(['"])(.*)\1$/, '$2'),
  }));
  return { description: field('description'), category: field('category'), requires };
}

// How a module relates to the others, from its ResourceSet:
//   after  the ResourceSet's top-level spec.dependsOn: it waits for them
//   uses   the other modules its templates read (`inputs.modules.<name>`):
//          it plugs into them when they are on, and works without them
function relations(page, name) {
  const text = readFileSync(path.join(repo, 'oci/catalog', page, 'resourceset.yaml'), 'utf8');
  const first = text.split(/\n---/)[0];
  const spec = /^spec:\n((?: {2}.*\n|\n)*)/m.exec(first)?.[1] ?? '';
  const dependsOn = /^ {2}dependsOn:\n((?: {4}.*\n)*)/m.exec(spec)?.[1] ?? '';
  const after = [...dependsOn.matchAll(/name: *([a-z0-9-]+)/g)].map((m) => m[1]);
  const uses = [...new Set([...text.matchAll(/inputs\.modules\.([a-z_]+)/g)].map((m) => m[1].replace(/_/g, '-')))].filter(
    (other) => other !== page,
  );
  return { after, uses };
}

/** @type {{ name: string, page: string, enabled: boolean, clouds: string[] | null, description: string, category: string, requires: { module: string, clouds: string[] | null }[], after: string[], uses: string[] }[]} */
export const modules = [...body.matchAll(/^ {4}([a-z][a-z0-9_]*) *= *\{\n {6}enabled *= *(true|false)/gm)].map((m) => {
  const page = m[1].replace(/_/g, '-');
  return { name: m[1], page, enabled: m[2] === 'true', clouds: restricted[m[1]] ?? null, ...frontmatter(page), ...relations(page, m[1]) };
});
if (modules.length === 0) throw new Error('catalog.tf: no module found');
for (const m of modules) {
  if (!m.description || !m.category) throw new Error(`docs/catalog/${m.page}.md: frontmatter needs description and category`);
}
