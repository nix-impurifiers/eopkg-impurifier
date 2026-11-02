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
    action = aliases[sys.argv[1]]
    status = subprocess.run(["eopkg", action, *args]).returncode
    readonly = {"-n", "--dry-run", "-h", "--help", "--version"}
    if action in {"install", "upgrade"}:
        readonly.update({"-f", "--fetch-only"})
    if any(arg in readonly for arg in args):
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
