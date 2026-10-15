#!/usr/bin/env python3
"""webapp's and cronjob's pods against the kyverno_policies module's policies.

#83: a client who switches every policy to Enforce deploys both charts
unchanged. The policies are the module's, never copied: its ResourceSet is
built with the CI's sample inputs (profile restricted, the socle's own
policies, ghcr.io allowed), and the chart it pins is rendered with the values
it gives it. Every fixture of both charts is rendered, its pods taken out of
their Deployment or CronJob, since the module's policies match Pods only, and
applied: every policy passes on every pod, none fails, errors or is skipped.

Needs helm, flux-operator, kyverno and PyYAML.

    python3 .github/scripts/charts-kyverno.py
"""
import glob
import os
import re
import subprocess
import sys
import tempfile

import yaml

MODULE = "oci/catalog/kyverno-policies/resourceset.yaml"
INPUTS = "oci/.ci/inputs-sample.yaml"
CHARTS = ["webapp", "cronjob"]


def run(*cmd):
    return subprocess.run(cmd, check=True, capture_output=True, text=True).stdout


def docs(text):
    # Helm prints the chart it pulled ("Pulled: …, Digest: …") among the
    # manifests: only the objects are kept.
    return [d for d in yaml.safe_load_all(text) if isinstance(d, dict) and "kind" in d]


def pods(rendered):
    """The pods a render's workloads would run, as Pod objects."""
    out = []
    for d in docs(rendered):
        if d["kind"] == "Deployment":
            template = d["spec"]["template"]
        elif d["kind"] == "CronJob":
            template = d["spec"]["jobTemplate"]["spec"]["template"]
        else:
            continue
        out.append({
            "apiVersion": "v1",
            "kind": "Pod",
            "metadata": {**template["metadata"], "name": d["metadata"]["name"], "namespace": "shop"},
            "spec": template["spec"],
        })
    return out


def main():
    os.chdir(run("git", "rev-parse", "--show-toplevel").strip())
    inputs = yaml.safe_load(open(INPUTS))[0]
    profile = inputs["modules"]["kyverno_policies"]["profile"]
    if profile != "restricted":
        sys.exit(f"{INPUTS}: kyverno_policies.profile is {profile}, the charts are held to restricted")

    built = docs(run("flux-operator", "build", "rset", "-f", MODULE, "--inputs-from", INPUTS))
    tag = next(d for d in built if d["kind"] == "OCIRepository")["spec"]["ref"]["tag"]
    values = next(d for d in built if d["kind"] == "ConfigMap"
                  and d["metadata"]["name"] == "kyverno-policies-socle-values")["data"]["values.yaml"]

    with tempfile.TemporaryDirectory() as work:
        open(os.path.join(work, "values.yaml"), "w").write(values)
        policies = run("helm", "template", "kyverno-policies", "oci://ghcr.io/kyverno/charts/kyverno-policies",
                       "--version", tag, "--values", os.path.join(work, "values.yaml"))
        names = sorted(d["metadata"]["name"] for d in docs(policies) if d["kind"] == "ValidatingPolicy")
        open(os.path.join(work, "policies.yaml"), "w").write(policies)
        print(f"kyverno-policies {tag}, profile {profile}: {len(names)} policies")
        print("  " + ", ".join(names))

        failed = False
        for chart in CHARTS:
            run("helm", "dependency", "build", f"charts/{chart}")
            for fixture in sorted(glob.glob(f"charts/{chart}/ci/*-values.yaml")):
                found = pods(run("helm", "template", "shop", f"charts/{chart}", "--namespace", "shop",
                                 "--values", fixture))
                path = os.path.join(work, "pods.yaml")
                yaml.safe_dump_all(found, open(path, "w"))
                result = subprocess.run(["kyverno", "apply", os.path.join(work, "policies.yaml"),
                                         "--resource", path], capture_output=True, text=True)
                summary = re.search(r"pass: (\d+), fail: (\d+), warn: (\d+), error: (\d+), skip: (\d+)",
                                    result.stdout)
                if not summary:
                    print(result.stdout + result.stderr)
                    sys.exit(f"{fixture}: no summary from kyverno apply")
                passed, fail, warn, error, skip = map(int, summary.groups())
                want = len(names) * len(found)
                ok = fail == error == skip == warn == 0 and passed == want
                print(f"{'ok  ' if ok else 'FAIL'} {fixture}: {len(found)} pod(s), "
                      f"pass {passed}/{want}, fail {fail}, error {error}, skip {skip}")
                if not ok:
                    failed = True
                    print("\n".join(line for line in result.stdout.splitlines() if "->" in line))
        if failed:
            sys.exit("a chart's pods do not pass the kyverno_policies module's policies")


if __name__ == "__main__":
    main()
