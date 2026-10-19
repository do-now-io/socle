#!/usr/bin/env python3
"""Every OpenTofu module's tests cover what it declares (#61, M2).

A static check, like check-catalog-clouds.sh: it reads the sources and the
tests, runs nothing. For every module under opentofu/ (foundations,
bootstrap, the cluster roots):

- the module has tests (tests/*.tftest.hcl);
- every variable with a `validation` block is named by at least one run's
  `expect_failures` — a new refusal cannot land without the case that trips
  it (docs/reference/opentofu-module-standard.md, Tests);
- every output is read by at least one assertion (`output.<name>`) — an
  output nothing reads can be dropped or renamed without a test noticing;
- bootstrap only: every key of local.catalog names a run in
  tests/defaults.tftest.hcl and one in tests/validations.tftest.hcl, so a
  new catalog module brings its defaults and its refusals.

Red with the list of what is missing. Runnable locally:

    python3 .github/scripts/check-test-coverage.py
"""
import glob
import os
import re
import sys


def blocks(text, kind):
    """(name, body) of every top-level `kind "name" { … }` block."""
    for match in re.finditer(r'^%s\s+"([^"]+)"\s*\{' % kind, text, re.M):
        i, depth = match.end(), 1
        while depth and i < len(text):
            c = text[i]
            if c == "{":
                depth += 1
            elif c == "}":
                depth -= 1
            elif c == '"':
                i += 1
                while i < len(text) and text[i] != '"':
                    i += 2 if text[i] == "\\" else 1
            elif c == "#" or text[i:i + 2] == "//":
                while i < len(text) and text[i] != "\n":
                    i += 1
            i += 1
        yield match.group(1), text[match.end():i - 1]


def strip_comments(text):
    return re.sub(r"(?m)^\s*(#|//).*$", "", text)


def read(paths):
    return "\n".join(strip_comments(open(p).read()) for p in sorted(paths))


def catalog_keys(bootstrap):
    source = open(os.path.join(bootstrap, "catalog.tf")).read()
    body = source[source.index("catalog = {"):]
    return re.findall(r"^    ([a-z_]+) = \{", body, re.M)


def main():
    rows, missing = [], []
    modules = sorted(d for d in glob.glob("opentofu/*/") + glob.glob("opentofu/clusters/*/")
                     if glob.glob(d + "*.tf"))
    for module in modules:
        sources = read(glob.glob(module + "*.tf"))
        tests = glob.glob(module + "tests/*.tftest.hcl")
        if not tests:
            missing.append(f"{module}: no tests/*.tftest.hcl")
            rows.append((module, "—", "—", "—"))
            continue
        body = read(tests)
        refused = set()
        for expect in re.findall(r"expect_failures\s*=\s*\[([^\]]*)\]", body):
            refused.update(re.findall(r"\bvar\.([A-Za-z0-9_]+)", expect))
        read_outputs = set(re.findall(r"\boutput\.([A-Za-z0-9_]+)", body))

        validated = [n for n, b in blocks(sources, "variable") if re.search(r"\bvalidation\s*\{", b)]
        outputs = [n for n, _ in blocks(sources, "output")]
        untripped = [n for n in validated if n not in refused]
        unread = [n for n in outputs if n not in read_outputs]
        missing += [f"{module}: no run has expect_failures = [var.{n}]" for n in untripped]
        missing += [f"{module}: no assertion reads output.{n}" for n in unread]

        catalog = "—"
        if module == "opentofu/bootstrap/":
            keys = catalog_keys(module)
            runs = {os.path.basename(t): [n for n, _ in blocks(read([t]), "run")] for t in tests}
            for key in keys:
                for file in ("defaults.tftest.hcl", "validations.tftest.hcl"):
                    if not any(key in run for run in runs.get(file, [])):
                        missing.append(f"{module}: no run named after catalog module {key} in tests/{file}")
            catalog = f"{len(keys)} modules"
        rows.append((module,
                     f"{len(validated) - len(untripped)}/{len(validated)}",
                     f"{len(outputs) - len(unread)}/{len(outputs)}",
                     catalog))

    print("| Module | Validations tripped | Outputs asserted | Catalog |")
    print("|---|---|---|---|")
    for row in rows:
        print("| `%s` | %s | %s | %s |" % row)
    if missing:
        print()
        for line in missing:
            print(f"- {line}")
        print(f"\n::error::{len(missing)} gap(s) in the OpenTofu tests (#61, M2)", file=sys.stderr)
        return 1
    print("\nEvery validation tripped, every output asserted. ✅")
    return 0


if __name__ == "__main__":
    sys.exit(main())
