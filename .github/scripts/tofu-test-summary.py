#!/usr/bin/env python3
"""One module's `tofu test -json-into` as a table the Checks tab shows.

OpenTofu has no JUnit output (opentofu/opentofu#2501): this reads the JSON
lines `tofu test -json-into=<file>` writes and prints, in Markdown, one table
row per test file, then every run that did not pass with the error its
assertion or diagnostic gave — the failing run named, not buried in the log.

    python3 .github/scripts/tofu-test-summary.py <module> <tofu-test.json>
"""
import json
import sys


def main(module, path):
    files, runs, errors = {}, [], {}
    with open(path) as lines:
        for line in lines:
            line = line.strip()
            if not line:
                continue
            event = json.loads(line)
            kind = event.get("type")
            if kind == "test_file":
                files[event["test_file"]["path"]] = event["test_file"]["status"]
            elif kind == "test_run" and "status" in event.get("test_run", {}):
                runs.append(event["test_run"])
            elif kind == "diagnostic" and event["diagnostic"].get("severity") == "error":
                key = (event.get("@testfile"), event.get("@testrun"))
                d = event["diagnostic"]
                errors.setdefault(key, []).append(f'{d.get("summary", "")}: {d.get("detail", "")}'.strip(": "))

    passed = sum(1 for r in runs if r["status"] == "pass")
    failed = [r for r in runs if r["status"] != "pass"]
    mark = "✅" if not failed and all(s == "pass" for s in files.values()) else "❌"
    print(f"#### `tofu test` `{module}` {mark} — {passed}/{len(runs)} runs")
    print("| File | Status | Runs |")
    print("|---|---|---|")
    for file, status in files.items():
        print(f"| `{file}` | {status} | {sum(1 for r in runs if r['path'] == file)} |")
    for run in failed:
        detail = " · ".join(errors.get((run["path"], run["run"]), [])) or "see the job log"
        print(f"- **{run['path']} › {run['run']}** ({run['status']}): {detail.replace(chr(10), ' ')}")
    for (file, run), messages in errors.items():
        if run is None:
            print(f"- **{file}**: {' · '.join(messages).replace(chr(10), ' ')}")


if __name__ == "__main__":
    main(*sys.argv[1:3])
