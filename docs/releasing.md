# Releasing (maintainer guide)

## Version scheme

SemVer `MAJOR.MINOR.PATCH`. The current version lives in `VERSION`; tags are `vX.Y.Z`.

- PATCH: fixes. MINOR: new addons or settings. MAJOR: breaking changes (settings reset, removed addons).

## Changelog workflow

`CHANGELOG.md` follows Keep a Changelog. While working, add entries under `## [Unreleased]` (Added / Changed / Fixed / Removed). At release time the section must be named `## [X.Y.Z] - YYYY-MM-DD`: either rename it by hand, or let the script do it with `--from-unreleased`. The GitHub release notes are this section, verbatim.

## Compatibility policy

Always the latest Serpantinum release. Each addons release records the Serpantinum version it was tested on, as both `serpantinum.min` and `serpantinum.tested` in `compat.json`. The release script stamps them from the Serpantinum installed on the maintainer machine (`~/.local/state/serpantinum/version`), so install and test on the newest Serpantinum before releasing. Other keys (`policy`, `hyprland_min`, `quickshell_min`) are kept; edit them by hand when requirements change.

For users: a newer Serpantinum than `tested` gives a warning; an older one than `min` is refused unless `--force`.

## Cutting a release

1. Be on `main` with a clean tree, `gh auth login` done, newest Serpantinum installed.
2. Make sure the changelog section exists (or use `--from-unreleased`).
3. Rehearse: `python3 scripts/release.py 2.0.1 --dry-run` prints every check, file change and command without executing or writing anything.
4. Release: `python3 scripts/release.py 2.0.1`. It validates, runs the tests (`--skip-tests` to bypass), stamps `compat.json` and `VERSION`, commits `release: v2.0.1`, tags, pushes `main` and the tag (never forced), and runs `gh release create` with the changelog section as notes.

If a step fails the script stops with the reason. Nothing is rolled back automatically: if it fails after the commit, fix the cause and finish by hand (`git push origin main vX.Y.Z`, `gh release create ...`).

## What users see

- The Serpantinum shell checks for a new release about every hour and shows the peach "Addons update" button at the bottom of the Settings sidebar.
- Settings → About shows the addons card: version, compatibility, changelog, hold-to-update.
- Terminal: `bash -c "$(curl -fsSL https://raw.githubusercontent.com/Suiveurtag/serpantinum-addons-v2/main/install/install.sh)" _ update`.

## Hotfix and rollback

Ship a hotfix as a normal PATCH release. To roll a user back to a known-good release, reinstall that tag:

```sh
python3 addons.py reinstall --ref vX.Y.Z
```

(or pass `_ reinstall --ref vX.Y.Z` to the bootstrap command). Delete a bad GitHub release only after publishing the fix.

## Serpantinum updates

A Serpantinum update replaces the shell files the addons patch, so the addons must be reinstalled afterwards. The shell shows this in Settings as "Reinstall addons". If the new Serpantinum is newer than `tested`, ship a new addons release stamped on it.
