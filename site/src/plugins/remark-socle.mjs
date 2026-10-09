// Two jobs, one remark plugin, so a page reads the same on GitHub and on the
// site:
//
//   ::include{file="opentofu/aws/README.md" section="tf-docs"}
//     splices another file of the repository into the page at build time —
//     never a copy (CONTRIBUTING.md, Documentation, rule 2). `file` is
//     relative to the repository root. `section="tf-docs"` keeps only what
//     terraform-docs writes between its BEGIN_TF_DOCS / END_TF_DOCS markers,
//     one heading level down, so it sits under the page's own heading.
//     A file or a section that does not resolve fails the build.
//
//   [text](../guides/upgrade.md)
//     a relative link, written the way GitHub resolves it. A link to a page
//     of the site becomes its route under the site's base; a link to any
//     other file of the repository (docs/ pages the site does not load
//     included) becomes its URL on GitHub, at the ref
//     this build was made from. Links in included files are resolved against
//     the included file, not the page.

import { existsSync, readFileSync, realpathSync } from 'node:fs';
import path from 'node:path';
import remarkGfm from 'remark-gfm';
import remarkParse from 'remark-parse';
import { unified } from 'unified';
import { visit } from 'unist-util-visit';

const TF_DOCS = /<!-- BEGIN_TF_DOCS -->([\s\S]*?)<!-- END_TF_DOCS -->/;
const SCHEME = /^[a-z][a-z0-9+.-]*:/i;

/**
 * @param {{ repoRoot: string, docsDir: string, base: string, githubTree: string, isPage: (rel: string) => boolean }} options
 *   isPage tells, from a path relative to docs/, whether the site loads it.
 *   githubTree is the URL files outside docs/ link to, e.g.
 *   https://github.com/do-now-io/socle/blob/main
 */
/**
 * The text an include brings in, or an error saying why it cannot.
 * @param {string} repoRoot
 * @param {{ file?: string, section?: string }} attributes
 * @param {string} where  file:line of the directive, for the message
 */
export function resolveInclude(repoRoot, { file: ref, section }, where) {
  if (!ref) throw new Error(`${where}: ::include needs a file="…" attribute`);
  const abs = path.resolve(repoRoot, ref);
  if (!abs.startsWith(repoRoot + path.sep) || !existsSync(abs)) {
    throw new Error(`${where}: ::include file "${ref}" does not exist`);
  }
  let text = readFileSync(abs, 'utf8');
  if (section === 'tf-docs') {
    const match = TF_DOCS.exec(text);
    if (!match) throw new Error(`${where}: "${ref}" has no BEGIN_TF_DOCS / END_TF_DOCS block`);
    text = match[1];
  } else if (section) {
    throw new Error(`${where}: unknown ::include section "${section}" (known: tf-docs)`);
  }
  return { abs, text };
}

/**
 * Every include of every page, checked before the build starts: Astro's
 * content loader logs a page that fails to render and carries on, so an
 * include that does not resolve would otherwise leave an empty page and a
 * green build (rule 8).
 * @param {string} repoRoot
 * @param {string} docsDir
 * @param {string[]} pages  paths relative to docsDir
 * @returns {string[]} one message per include that does not resolve
 */
export function checkIncludes(repoRoot, docsDir, pages) {
  const errors = [];
  for (const page of pages) {
    readFileSync(path.join(docsDir, page), 'utf8')
      .split('\n')
      .forEach((line, i) => {
        const directive = /^::include\{([^}]*)\}\s*$/.exec(line);
        if (!directive) return;
        const attributes = Object.fromEntries([...directive[1].matchAll(/(\w+)="([^"]*)"/g)].map((m) => [m[1], m[2]]));
        try {
          resolveInclude(repoRoot, attributes, `docs/${page}:${i + 1}`);
        } catch (error) {
          errors.push(error.message);
        }
      });
  }
  return errors;
}

export default function remarkSocle({ repoRoot, docsDir, base, githubTree, isPage }) {
  const parser = unified().use(remarkParse).use(remarkGfm);
  const siteBase = base.endsWith('/') ? base : `${base}/`;

  function route(absFile, hash) {
    let slug = path.relative(docsDir, absFile).replace(/\.mdx?$/, '').split(path.sep).join('/');
    slug = slug === 'index' ? '' : slug.replace(/\/index$/, '');
    return `${siteBase}${slug ? `${slug.toLowerCase()}/` : ''}${hash}`;
  }

  function rewriteLinks(tree, fromDir) {
    visit(tree, ['link', 'definition'], (node) => {
      const url = node.url;
      if (!url || url.startsWith('#') || url.startsWith('/') || SCHEME.test(url)) return;
      const [target, hash = ''] = url.split(/(?=#)/);
      const abs = path.resolve(fromDir, decodeURIComponent(target));
      if (!abs.startsWith(repoRoot)) return;
      const inDocs = path.relative(docsDir, abs).split(path.sep).join('/');
      if (abs.startsWith(docsDir + path.sep) && isPage(inDocs)) {
        node.url = route(abs, hash);
      } else {
        const rel = path.relative(repoRoot, abs).split(path.sep).join('/');
        node.url = `${githubTree}/${rel}${hash}`;
      }
    });
  }

  function include(node, page) {
    const where = `${path.relative(repoRoot, page)}:${node.position?.start.line}`;
    const { abs, text } = resolveInclude(repoRoot, node.attributes ?? {}, where);
    // A whole Markdown file comes with its own H1; the page already has one,
    // its title.
    const included = parser.parse(text);
    included.children = included.children.filter((child) => !(child.type === 'heading' && child.depth === 1));
    if (node.attributes?.section === 'tf-docs') {
      visit(included, 'heading', (heading) => {
        heading.depth = Math.min(heading.depth + 1, 6);
      });
    }
    rewriteLinks(included, path.dirname(abs));
    // terraform-docs anchors its tables with <a name="input_x"></a>; an id is
    // what the page (and the link check) can target.
    visit(included, 'html', (html) => {
      html.value = html.value.replace(/<a name="([^"]+)">/g, '<a id="$1">');
    });
    return included.children;
  }

  return (tree, file) => {
    if (!file.path) return;
    // Pages are read through the src/content/docs symlink; their links are
    // relative to where they really are, in docs/.
    const real = realpathSync(file.path);
    visit(tree, 'leafDirective', (node, index, parent) => {
      if (node.name !== 'include' || !parent) return;
      parent.children.splice(index, 1, ...include(node, real));
      return index;
    });
    rewriteLinks(tree, path.dirname(real));
  };
}
