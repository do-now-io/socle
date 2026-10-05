// The site's sections: one source for what the site loads from docs/
// (content.config.ts) and for its navigation (astro.config.mjs), so the two
// cannot disagree. The tree is the one in CONTRIBUTING.md, Documentation.

const clouds = [
  ['aws', 'AWS · EKS'],
  ['gcp', 'GCP · GKE'],
  ['azure', 'Azure · AKS'],
  ['scaleway', 'Scaleway · Kapsule'],
];

const sidebar = [
  { label: 'Getting started', items: [{ autogenerate: { directory: 'getting-started' } }] },
  {
    label: 'Clouds',
    items: clouds.map(([cloud, label]) => ({ label, collapsed: true, items: [{ autogenerate: { directory: `clouds/${cloud}` } }] })),
  },
  { label: 'Catalog', items: [{ autogenerate: { directory: 'catalog' } }] },
  { label: 'Guides', items: [{ autogenerate: { directory: 'guides' } }] },
  { label: 'Architecture', items: [{ autogenerate: { directory: 'architecture' } }] },
  { label: 'Decisions', items: [{ autogenerate: { directory: 'decisions' } }] },
  { label: 'Reference', items: [{ autogenerate: { directory: 'reference' } }] },
  { label: 'Contributing', slug: 'contributing' },
];

const pages = ['index.md', 'contributing.md'];
const directories = ['getting-started', 'clouds', 'guides', 'architecture', 'decisions', 'reference'];

// The documentation as it stood before the site (#71). It stays readable on
// GitHub and out of the site until the migration (M2) moves it into the tree
// above; this list then goes. docs/catalog/<module>.md are legacy until they
// carry the frontmatter of the module page template.
const legacy = [/^(aws|gcp|azure|scaleway|standards)\//, /^(distribution|flux-catalog|monitoring)\.md$/, /^catalog\/(?!index\.md$)[^/]+\.md$/];

export const sections = {
  sidebar,
  // Glob patterns, relative to docs/, for Astro's glob() loader. A leading
  // `_` keeps a file out, as in Starlight's own loader.
  patterns: [...pages, 'catalog/index.md', ...directories.map((d) => `${d}/**/[^_]*.{md,mdx}`)],
  covers: (file) =>
    pages.includes(file) || file === 'catalog/index.md' || directories.some((d) => file.startsWith(`${d}/`)),
  isLegacy: (file) => legacy.some((re) => re.test(file)),
};
