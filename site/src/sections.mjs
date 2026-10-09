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
  { label: 'Reference', items: [{ autogenerate: { directory: 'reference' } }] },
  { label: 'Contributing', slug: 'contributing' },
];

// The landing page is not one of them: it is site/src/pages/index.astro.
const pages = ['contributing.md'];
const directories = ['getting-started', 'clouds', 'catalog', 'guides', 'architecture', 'reference'];
// In docs/ for contributors, read on GitHub; the site does not publish them,
// and no published page links to them.
const unpublished = ['decisions'];

export const sections = {
  sidebar,
  // Glob patterns, relative to docs/, for Astro's glob() loader. A leading
  // `_` keeps a file out, as in Starlight's own loader.
  patterns: [...pages, ...directories.map((d) => `${d}/**/[^_]*.{md,mdx}`)],
  // A file whose name starts with `_` (a template) is not published.
  covers: (file) => pages.includes(file) || directories.some((d) => file.startsWith(`${d}/`) && !/(^|\/)_[^/]*$/.test(file)),
  isTemplate: (file) => /(^|\/)_[^/]*$/.test(file),
  isUnpublished: (file) => unpublished.some((d) => file.startsWith(`${d}/`)),
};
