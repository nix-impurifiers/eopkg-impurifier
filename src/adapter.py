#!/usr/bin/python3
# SPDX-License-Identifier: MIT
"""Run native eopkg and reconcile Nix intent after its transaction."""
from pathlib import Path
import subprocess
import sys


def main():
    aliases = {"install": "install", "it": "install", "upgrade": "upgrade", "up": "upgrade",
               "remove": "remove", "rm": "remove"}
    if len(sys.argv) < 2 or sys.argv[1] not in aliases:
        raise ValueError("usage: eopkg-impurifier {install|upgrade|remove} [native options] packages")
    args = sys.argv[2:]
    if any(arg in {"-D", "--destdir"} or arg.startswith("--destdir=")
           or (arg.startswith("-D") and len(arg) > 2) for arg in args):
        raise ValueError("foreign destdir cannot activate the host")
    status = subprocess.run(["eopkg", aliases[sys.argv[1]], *args]).returncode
    if any(arg in {"-n", "--dry-run", "-f", "--fetch-only"} for arg in args):
        return status
    engine = Path("/usr/sbin/nix-profile-engine")
    activation = subprocess.run([str(engine), "reconcile"]).returncode if engine.exists() else 0
    return status or activation


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, ValueError) as error:
        print("eopkg-impurifier: " + str(error), file=sys.stderr)
        sys.exit(1)
