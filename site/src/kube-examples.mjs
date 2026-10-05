// The copy-paste tfvars blocks of the module pages, held to catalog.tf so
// they cannot drift from what a client may set:
//
//   ```hcl title="terraform.tfvars" kube-full="argocd"
//     every attribute of the module, no more, no less (`values` and
//     `values_secret` show an example, the others their default). An
//     attribute the root derives is listed commented out (`    # key = …`):
//     copied as a value, it would override what the root sets.
//   ```hcl title="terraform.tfvars" kube-start="argocd"
//     only attributes that exist, for every module the block names
//
// Every module page carries one of each. Attributes are read at exactly four
// spaces under a module at two (`kube = {` / `  argocd = {` / `    key = …`),
// the layout `tofu fmt` gives. Checked before the build starts: Astro's
// content loader would only log a failure.
import { readFileSync } from 'node:fs';
import path from 'node:path';

/** The attributes of every catalog module, in catalog.tf's order. */
function catalogAttributes(repoRoot) {
  const source = readFileSync(path.join(repoRoot, 'opentofu/bootstrap/catalog.tf'), 'utf8');
  const body = /^ {2}catalog += \{\n([\s\S]*?)^ {2}\}/m.exec(source)?.[1];
  if (!body) throw new Error('catalog.tf: no `catalog = { … }` block');
  const modules = {};
  for (const [, name, block] of body.matchAll(/^ {4}([a-z][a-z0-9_]*) *= *\{\n([\s\S]*?)^ {4}\}/gm)) {
    modules[name] = [...block.matchAll(/^ {6}([a-z][a-z0-9_]*) *=/gm)].map((m) => m[1]);
  }
  return modules;
}

/** Module name → attributes, as an example block writes them. */
function blockAttributes(code) {
  const found = {};
  let current = null;
  for (const line of code.split('\n')) {
    // `  crossplane = { enabled = true }`: a module on one line.
    const inline = /^ {2}([a-z][a-z0-9_]*) *= *\{(.*)\}\s*(#.*)?$/.exec(line);
    if (inline) {
      found[inline[1]] = [...inline[2].matchAll(/([a-z][a-z0-9_]*) *=/g)].map((m) => m[1]);
      continue;
    }
    const module = /^ {2}([a-z][a-z0-9_]*) *= *\{/.exec(line);
    if (module) {
      current = module[1];
      found[current] = [];
      continue;
    }
    const attribute = /^ {4}([a-z][a-z0-9_]*) *=/.exec(line);
    if (attribute && current) found[current].push(attribute[1]);
    const commented = /^ {4}# ([a-z][a-z0-9_]*) *= /.exec(line);
    if (commented && current) (found[`${current}#`] ??= []).push(commented[1]);
    if (/^ {2}\}/.test(line)) current = null;
  }
  return found;
}

/**
 * @param {string} repoRoot
 * @param {string} docsDir
 * @param {string[]} pages  catalog module pages, relative to docsDir (catalog/<page>.md)
 * @returns {string[]} one message per problem
 */
export function checkKubeExamples(repoRoot, docsDir, pages) {
  const catalog = catalogAttributes(repoRoot);
  const errors = [];
  for (const page of pages) {
    const text = readFileSync(path.join(docsDir, page), 'utf8');
    const counts = { full: 0, start: 0 };
    for (const [, kind, module, code] of text.matchAll(/^```hcl[^\n]*\bkube-(full|start)="([a-z_]+)"[^\n]*\n([\s\S]*?)^```/gm)) {
      const where = `docs/${page}: kube-${kind}="${module}"`;
      counts[kind] += 1;
      if (!catalog[module]) {
        errors.push(`${where}: no module ${module} in catalog.tf`);
        continue;
      }
      const written = blockAttributes(code);
      if (kind === 'full') {
        const got = [...(written[module] ?? []), ...(written[`${module}#`] ?? [])];
        const missing = catalog[module].filter((a) => !got.includes(a));
        const extra = got.filter((a) => !catalog[module].includes(a));
        if (Object.keys(written).some((m) => m !== module && m !== `${module}#`)) errors.push(`${where}: names other modules; a full block holds one`);
        if (missing.length) errors.push(`${where}: missing ${missing.join(', ')}`);
        if (extra.length) errors.push(`${where}: not attributes of ${module}: ${extra.join(', ')}`);
      } else {
        for (const [name, attributes] of Object.entries(written)) {
          if (name.endsWith('#')) continue;
          if (!catalog[name]) errors.push(`${where}: no module ${name} in catalog.tf`);
          else {
            const extra = attributes.filter((a) => !catalog[name].includes(a));
            if (extra.length) errors.push(`${where}: not attributes of ${name}: ${extra.join(', ')}`);
          }
        }
      }
    }
    if (counts.full !== 1) errors.push(`docs/${page}: needs one kube-full block, has ${counts.full}`);
    if (counts.start < 1) errors.push(`docs/${page}: needs a kube-start block`);
  }
  return errors;
}
