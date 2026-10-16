#!/usr/bin/env python3
"""Every `# appVersion` comment of the catalog is the appVersion of the chart
it sits beside.

A module pins its chart by `tag:` (an OCIRepository) or `version:` (a
HelmRelease from a HelmRepository), and says which application that chart
runs in a comment on the same line: `tag: 2.13.0  # appVersion v2.13.0`. The
comment is read by people and by pr-static.yaml (the external-secrets CRDs are
fetched at that tag). Renovate bumps the chart, not the comment: it cannot
know the new chart's appVersion. This check does, with `helm show chart` at
the pinned version, and names the line and the value it should carry (#103).

Needs helm.

    python3 .github/scripts/check-app-versions.py
"""
import glob
import re
import subprocess
import sys

PIN = re.compile(r"^\s*(?:tag|version):\s*(\S+)\s+#\s*appVersion\s+(\S+)\s*$")
OCI = re.compile(r"^\s*url:\s*(oci://\S+)\s*$")
HTTPS = re.compile(r"^\s*url:\s*(https://\S+)\s*$")
CHART = re.compile(r"^\s*chart:\s*(\S+)\s*$")


def app_version(*ref):
    for _ in range(3):
        out = subprocess.run(["helm", "show", "chart", *ref], capture_output=True, text=True)
        if out.returncode == 0:
            break
    else:
        sys.exit(f"helm show chart {' '.join(ref)}: {out.stderr.strip()}")
    for line in out.stdout.splitlines():
        if line.startswith("appVersion:"):
            return line.split(":", 1)[1].strip().strip('"')
    return ""


def main():
    rc = n = 0
    for path in sorted(glob.glob("oci/catalog/*/resourceset.yaml")):
        lines = open(path).read().splitlines()
        repos = [m.group(1) for m in map(HTTPS.match, lines) if m]
        for i, line in enumerate(lines):
            pin = PIN.match(line)
            if not pin:
                continue
            version, comment = pin.groups()
            before = lines[:i]
            oci = next((m.group(1) for m in map(OCI.match, reversed(before)) if m), None)
            chart = next((m.group(1) for m in map(CHART.match, reversed(before)) if m), None)
            if line.lstrip().startswith("tag:") and oci:
                ref = (oci, "--version", version)
            elif chart and len(repos) == 1:
                ref = (chart, "--repo", repos[0], "--version", version)
            else:
                print(f"::error file={path},line={i + 1}::no chart source found for this pin")
                rc = 1
                continue
            n += 1
            actual = app_version(*ref)
            if actual != comment:
                print(f"::error file={path},line={i + 1}::chart {version} runs {actual}, "
                      f"the comment says {comment}: write `# appVersion {actual}`")
                rc = 1
            else:
                print(f"{path}:{i + 1}: {version} runs {actual}")
    if rc == 0:
        print(f"appVersion comments: {n}, each its chart's. ✅")
    return rc


if __name__ == "__main__":
    sys.exit(main())
