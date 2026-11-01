#!/usr/bin/env python3
"""Cut an addons release: validate, stamp compat.json + VERSION, commit, tag, push, gh release.

Usage: python3 scripts/release.py X.Y.Z [--dry-run] [--skip-tests] [--from-unreleased]
Needs git and gh (authenticated). Never force-pushes.
"""
import argparse
import datetime
import json
import re
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))
import addons_release as ar  # noqa: E402

SEMVER = re.compile(r"^\d+\.\d+\.\d+$")
DRY = False
PROBLEMS = []


def ok(msg):
    print(f"✓ {msg}")


def fail(msg, hint=""):
    """Abort, except in dry-run where the problem is reported and the plan continues."""
    print(f"✗ {msg}" + (f"\n  -> {hint}" if hint else ""))
    if not DRY:
        sys.exit(1)
    PROBLEMS.append(msg)


def run(cmd, mutating=True, **kw):
    """Run a command; in dry-run, mutating commands are only printed."""
    shown = " ".join(cmd)
    if DRY and mutating:
        print(f"  [dry-run] $ {shown}")
        return subprocess.CompletedProcess(cmd, 0, "", "")
    r = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True, **kw)
    if r.returncode != 0:
        print(f"✗ command failed: {shown}\n{(r.stdout + r.stderr).strip()}")
        sys.exit(1)
    return r


def changelog_section(text, version):
    m = re.search(rf"^## \[{re.escape(version)}\][^\n]*\n(.*?)(?=^## \[|\Z)", text, re.M | re.S)
    return m.group(0).rstrip() + "\n" if m else None


def main():
    global DRY
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("version")
    p.add_argument("--dry-run", action="store_true")
    p.add_argument("--skip-tests", action="store_true")
    p.add_argument("--from-unreleased", action="store_true",
                   help="rename '## [Unreleased]' to the new version if no section exists")
    a = p.parse_args()
    DRY = a.dry_run
    v = a.version.lstrip("v")
    tag = f"v{v}"
    if DRY:
        print("DRY RUN: nothing will be executed or written.\n")

    # 1. version
    current = (ROOT / "VERSION").read_text().strip()
    if not SEMVER.match(v):
        fail(f"'{a.version}' is not a valid X.Y.Z version")
    elif ar.compare(v, current) == 0 and not subprocess.run(
            ["git", "rev-parse", "-q", "--verify", f"refs/tags/v{v}"], cwd=ROOT,
            capture_output=True).returncode == 0:
        ok(f"version {v} (first release of the current VERSION, tag v{v} does not exist yet)")
    elif ar.compare(v, current) <= 0:
        fail(f"{v} is not greater than current VERSION {current}", "pick a higher version")
    else:
        ok(f"version {current} -> {v}")

    # 2. git state
    branch = run(["git", "rev-parse", "--abbrev-ref", "HEAD"], mutating=False).stdout.strip()
    if branch != "main":
        fail(f"on branch '{branch}', not main", "git switch main")
    else:
        ok("on branch main")
    dirty = run(["git", "status", "--porcelain"], mutating=False).stdout.strip()
    if dirty:
        fail("working tree is not clean", "commit or stash your changes first")
    else:
        ok("working tree clean")
    if run(["git", "tag", "-l", tag], mutating=False).stdout.strip():
        fail(f"tag {tag} already exists")

    # 3. changelog
    cl_path = ROOT / "CHANGELOG.md"
    cl = cl_path.read_text()
    new_cl = None
    if changelog_section(cl, v):
        ok(f"CHANGELOG.md has a [{v}] section")
    else:
        m = re.search(r"^## \[Unreleased\][^\n]*\n(.*?)(?=^## \[|\Z)", cl, re.M | re.S)
        if m and m.group(1).strip() and a.from_unreleased:
            today = datetime.date.today().isoformat()
            new_cl = cl.replace(m.group(0).split("\n", 1)[0], f"## [{v}] - {today}", 1)
            ok(f"CHANGELOG.md: [Unreleased] -> [{v}] - {today}")
        elif m and m.group(1).strip():
            fail(f"CHANGELOG.md has no [{v}] section but has Unreleased content",
                 "rename it by hand or pass --from-unreleased")
        else:
            fail(f"CHANGELOG.md has no [{v}] section", f"add '## [{v}] - YYYY-MM-DD' with the notes")

    # 4. tests
    if a.skip_tests:
        ok("tests skipped (--skip-tests)")
    else:
        cmd = [sys.executable, "-m", "unittest", "discover", "-s", "tests"]
        if DRY:
            print(f"  [dry-run] $ {' '.join(cmd)}")
        else:
            print("  running tests...")
            run(cmd)
            ok("tests passed")

    # 5. serpantinum version
    sv = ar.serpantinum_state().get("version")
    if not sv:
        fail("cannot read the installed Serpantinum version",
             "install Serpantinum (~/.local/state/serpantinum/version must exist)")
        sv = "<serpantinum-version>"
    else:
        ok(f"installed Serpantinum {sv} (will be stamped as min = tested)")

    # 6. file changes
    cpath = ROOT / "compat.json"
    compat = json.loads(cpath.read_text())
    compat.setdefault("serpantinum", {}).update({"min": sv, "tested": sv})
    compat_txt = json.dumps(compat, indent=2) + "\n"
    print("\nFile changes:")
    print(f"  compat.json: serpantinum.min = tested = {sv}")
    print(f"  VERSION: {current} -> {v}")
    if new_cl:
        print("  CHANGELOG.md: rename [Unreleased]")
    if not DRY:
        cpath.write_text(compat_txt)
        (ROOT / "VERSION").write_text(v + "\n")
        if new_cl:
            cl_path.write_text(new_cl)
        cl = new_cl or cl

    # 7. release notes
    notes = changelog_section(new_cl or cl, v) or f"## [{v}]\n"
    if DRY:
        print(f"\nRelease notes would be:\n---\n{notes}---")
        notes_file = "<tmp-notes-file>"
    else:
        tf = tempfile.NamedTemporaryFile("w", suffix=".md", delete=False)
        tf.write(notes)
        tf.close()
        notes_file = tf.name

    # 8. git + gh
    print("\nCommands:")
    if not DRY:
        gh = run(["gh", "auth", "status"], mutating=False) if _has("gh") else None
        if gh is None:
            fail("gh is not installed", "install GitHub CLI, then 'gh auth login'")
    run(["git", "commit", "-am", f"release: {tag}"])
    run(["git", "tag", "-a", tag, "-m", f"Serpantinum addons {tag}"])
    run(["git", "push", "origin", "main", tag])
    run(["gh", "release", "create", tag, "--title", tag, "--notes-file", notes_file])
    if DRY:
        print(f"\nDry run complete; {len(PROBLEMS)} blocking problem(s) would abort a real run.")
        for pr in PROBLEMS:
            print(f"  - {pr}")
    else:
        ok(f"released {tag}")


def _has(prog):
    from shutil import which
    return which(prog) is not None


if __name__ == "__main__":
    try:
        main()
    except subprocess.CalledProcessError as e:
        print(f"✗ {e}")
        sys.exit(1)
