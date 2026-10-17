"""Prepare a guarded stable-release merge in a disposable CI checkout only."""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess

UPSTREAM = "https://github.com/The412Banner/Bannerlator.git"
TAG = re.compile(r"v?\d+\.\d+\.\d+(?:\.\d+)?\Z")
PROTECTED = (".github/", "keystore/", "scripts/stable_upstream.py",
             "scripts/test_stable_upstream.py", "docs/STABLE-UPDATES.md")


def git(*args, check=True):
    result = subprocess.run(["git", "-c", "core.hooksPath=" + os.devnull,
                             *args], capture_output=True, text=True, check=False)
    if check and result.returncode:
        raise RuntimeError(f"git {args[0]} failed (exit {result.returncode})")
    return result


def stable_tag(release):
    tag = release.get("tag_name", "")
    if release.get("draft") is not False or release.get("prerelease") is not False:
        raise ValueError("Release must explicitly be stable and published")
    if not isinstance(tag, str) or not TAG.fullmatch(tag):
        raise ValueError("Unsupported stable version tag")
    return tag


def block(text, name):
    match = re.search(r"\b" + name + r"\s*\{", text)
    if not match:
        raise ValueError("Missing signing configuration")
    start, depth = match.start(), 1
    for pos in range(match.end(), len(text)):
        depth += (text[pos] == "{") - (text[pos] == "}")
        if depth == 0:
            return text[start:pos + 1]
    raise ValueError("Unbalanced signing configuration")


def identity(text):
    # Compare without logging signing material. Keep all flavor IDs/names and
    # signing selections, while allowing version/dependency changes.
    lines = tuple(line.strip() for line in text.splitlines() if re.search(
        r'\bapplicationId\b|resValue\s+"string",\s*"app_name"|\bsigningConfig\s+', line))
    if len([line for line in lines if line.startswith("applicationId")]) != 3:
        raise ValueError("Expected three existing product identities")
    return lines, block(text, "signingConfigs")


def guard(base, candidate):
    changed = git("diff", "--name-only", base, candidate, "--").stdout.splitlines()
    guarded = [path for path in changed if path.startswith(PROTECTED)
               or "tyrantlator" in path.lower()]
    if guarded:
        return "Protected automation, signing or branding changed: " + ", ".join(guarded)
    deleted = git("diff", "--name-only", "--diff-filter=D", base, candidate, "--").stdout.splitlines()
    if deleted:
        return "File removal needs review: " + ", ".join(deleted)
    before = git("show", base + ":app/build.gradle").stdout
    after = git("show", candidate + ":app/build.gradle").stdout
    if identity(before) != identity(after):
        return "Application identity or signing configuration changed"
    return None


def prepare(release, report):
    tag = stable_tag(release)
    if git("status", "--porcelain").stdout:
        raise RuntimeError("Disposable checkout must be clean")
    git("fetch", "--no-tags", "origin", "refs/heads/profiling")
    base = git("rev-parse", "FETCH_HEAD").stdout.strip()
    git("fetch", "--no-tags", UPSTREAM, "refs/tags/" + tag)
    upstream = git("rev-parse", "FETCH_HEAD^{commit}").stdout.strip()
    report.update(tag=tag, base=base, upstream=upstream)
    if git("merge-base", "--is-ancestor", upstream, base, check=False).returncode == 0:
        report.update(status="current", reason="Stable release already integrated")
        return
    git("checkout", "--detach", base)
    merged = git("merge", "--no-ff", "--no-commit", upstream, check=False)
    if merged.returncode:
        paths = git("diff", "--name-only", "--diff-filter=U").stdout.splitlines()
        git("merge", "--abort")
        report.update(status="blocked", reason="Merge requires review", conflicts=paths)
        return
    tree = git("write-tree").stdout.strip()
    reason = guard(base, tree)
    if reason:
        git("merge", "--abort")
        report.update(status="blocked", reason=reason)
        return
    git("commit", "-m", "Merge Bannerlator stable " + tag + " into Tyrantlator profiling")
    report.update(status="ready", candidate=git("rev-parse", "HEAD").stdout.strip(),
                  reason="Clean guarded merge; PUBG build still required")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--release-json", required=True, type=Path)
    parser.add_argument("--report", required=True, type=Path)
    parser.add_argument("--disposable-checkout", action="store_true", required=True)
    args = parser.parse_args()
    if os.environ.get("GITHUB_ACTIONS") != "true":
        parser.error("Only run preparation in a disposable GitHub Actions checkout")
    report = {"status": "error"}
    try:
        prepare(json.loads(args.release_json.read_text(encoding="utf-8")), report)
    finally:
        args.report.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    output = os.environ.get("GITHUB_OUTPUT")
    if output:
        with open(output, "a", encoding="utf-8") as stream:
            for key in ("status", "tag", "base", "upstream", "candidate"):
                stream.write(key + "=" + report.get(key, "") + "\n")


if __name__ == "__main__":
    main()
