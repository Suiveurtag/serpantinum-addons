#!/usr/bin/env python3
"""Terminal manager for Serpantinum Addons: install, update, reinstall, uninstall, doctor."""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

ACTIONS = ("install", "update", "reinstall", "uninstall", "doctor")

EPILOG = """\
Without an action, an interactive menu is shown.
install, update and reinstall also install what is missing: Serpantinum itself
(through its own installer) and the required system packages (pacman, dnf or xbps).
Examples:
  python3 addons.py                    interactive menu
  python3 addons.py update             update to the latest release
  python3 addons.py uninstall --yes    unattended uninstall (add --purge to delete addon data)
  python3 addons.py doctor --report    markdown block to paste in a GitHub issue
"""


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="addons.py",
        description="Manage Serpantinum Addons (install, update, reinstall, uninstall, doctor).",
        epilog=EPILOG,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    p.add_argument("action", nargs="?", choices=ACTIONS, help="what to do (default: interactive menu)")
    p.add_argument("--focus", choices=ACTIONS, metavar="ACTION",
                   help="preselect an action in the menu (it still asks for confirmation)")
    p.add_argument("-y", "--yes", action="store_true",
                   help="accept the defaults without asking (requires an action; sudo, the package manager "
                        "and the Serpantinum installer still prompt)")
    p.add_argument("--ref", metavar="REF", help="update to this tag or branch instead of the latest release")
    p.add_argument("--purge", action="store_true", help="with uninstall: also delete addon data")
    p.add_argument("--report", action="store_true", help="with doctor: print a markdown report for GitHub issues")
    return p


def parse_args(argv=None):
    p = build_parser()
    args = p.parse_args(argv)
    if args.report and args.action is None:
        args.action = "doctor"
    if args.report and args.action != "doctor":
        p.error("--report only works with the doctor action")
    if args.purge and args.action != "uninstall":
        p.error("--purge only works with the uninstall action")
    if args.yes and args.action is None:
        p.error("--yes needs an explicit action (for example: install --yes)")
    return args


def main(argv=None) -> int:
    args = parse_args(argv)
    import userpath

    userpath.extend_environ()  # tools installed after the session started (npm -g, cargo...) are found without a reboot
    from manager.flow import run

    return run(args)


if __name__ == "__main__":
    sys.exit(main())
