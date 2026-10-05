// The socle documentation site. The content is ../docs; this folder holds
// only the generator. Built several times into one GitHub Pages artifact
// (.github/scripts/build-pages.sh):
//   SOCLE_CHANNEL=latest  the last release, at the root (/socle/)
//   SOCLE_CHANNEL=dev     main, under /socle/dev/, with an "unreleased" banner
//   SOCLE_CHANNEL=pr      pull request SOCLE_PR, under /socle/pr/<N>/, as a
//                         preview
// Unset (a local build), it is built like dev.

import { readdirSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { unified } from '@astrojs/markdown-remark';
import starlight from '@astrojs/starlight';
import { defineConfig } from 'astro/config';
import starlightLinksValidator from 'starlight-links-validator';
import { sections } from './src/sections.mjs';
import remarkSocle, { checkIncludes } from './src/plugins/remark-socle.mjs';

const repoRoot = path.resolve(fileURLToPath(new URL('..', import.meta.url)));
const docsDir = path.join(repoRoot, 'docs');
const repository = 'https://github.com/do-now-io/socle';

const channel = process.env.SOCLE_CHANNEL ?? 'dev';
const pr = process.env.SOCLE_PR ?? '';
if (channel === 'pr' && !/^[0-9]+$/.test(pr)) throw new Error('SOCLE_CHANNEL=pr needs SOCLE_PR, the pull request number');
const base = { latest: '/socle', pr: `/socle/pr/${pr}` }[channel] ?? '/socle/dev';
// The ref the content was checked out at: links to files outside docs/ point
// at that exact tree on GitHub, so a released page links to released code.
const ref = process.env.SOCLE_REF ?? 'main';
// Whether a release exists at all: until the first one, the root serves main
// too, and says so (src/route-data.ts).
const released = process.env.SOCLE_RELEASED === 'true';

// Rule 8: a page missing from the navigation fails the build. The navigation
// is generated from `sections`, so a page is missing from it exactly when it
// sits outside every section.
const markdown = readdirSync(docsDir, { recursive: true })
  .filter((f) => /\.mdx?$/.test(f))
  .map((f) => f.split(path.sep).join('/'));
const strays = markdown.filter((f) => !sections.covers(f) && !sections.isLegacy(f));
if (strays.length > 0) {
  throw new Error(
    `docs/: ${strays.length} page(s) outside the site's sections (src/sections.mjs), so missing from its navigation:\n` +
      strays.map((f) => `  docs/${f}`).join('\n'),
  );
}

// Rule 8 again: an include that does not resolve fails the build.
const unresolved = checkIncludes(repoRoot, docsDir, markdown.filter(sections.covers));
if (unresolved.length > 0) throw new Error(`docs/: includes that do not resolve:\n  ${unresolved.join('\n  ')}`);

export default defineConfig({
  site: 'https://do-now-io.github.io',
  base,
  trailingSlash: 'always',
  vite: {
    define: {
      'import.meta.env.SOCLE_CHANNEL': JSON.stringify(channel),
      'import.meta.env.SOCLE_RELEASED': JSON.stringify(String(released)),
      'import.meta.env.SOCLE_PR': JSON.stringify(pr),
    },
  },
  // unified, not Astro 7's default Sätteri: Starlight's asides and
  // remark-socle are remark plugins.
  markdown: {
    processor: unified({
      remarkPlugins: [[remarkSocle, { repoRoot, docsDir, base, githubTree: `${repository}/blob/${ref}`, isPage: sections.covers }]],
    }),
  },
  integrations: [
    starlight({
      title: 'Socle',
      description: 'An open source GitOps distribution for managed Kubernetes clusters: EKS, GKE, AKS and Scaleway Kapsule.',
      social: [{ icon: 'github', label: 'GitHub', href: repository }],
      // Rewritten to docs/ by src/route-data.ts.
      editLink: { baseUrl: `${repository}/edit/main/site/` },
      routeMiddleware: './src/route-data.ts',
      sidebar: sections.sidebar,
      plugins: [starlightLinksValidator({ errorOnRelativeLinks: true, errorOnInvalidHashes: true })],
    }),
  ],
});
