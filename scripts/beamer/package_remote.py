#!/usr/bin/env python3
"""Create a small archive for installing this Beamer adapter on another machine."""

import argparse
from pathlib import Path
import tarfile

from remote_install import FILES


def make_archive(output):
    source = Path(__file__).resolve().parent
    for name in FILES:
        if not (source / name).is_file():
            raise FileNotFoundError(source / name)
    with tarfile.open(output, "x:gz") as archive:
        for name in FILES:
            archive.add(source / name, arcname=f"beamer-hyprland/{name}", recursive=False)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    make_archive(parser.parse_args().output)
