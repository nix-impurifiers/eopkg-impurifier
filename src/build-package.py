# SPDX-License-Identifier: MIT
"""Emit eopkg format 1.2 and validate it with the upstream reader."""
import hashlib
import json
import os
from pathlib import Path
import sys
import tarfile
import tempfile
import xml.etree.ElementTree as ET
import zipfile

import pisi.package

spec = json.loads(Path(sys.argv[1]).read_text())
root = Path(sys.argv[2])
output = Path(sys.argv[3])


def child(parent, name, value, **attributes):
    element = ET.SubElement(parent, name, attributes)
    element.text = str(value)
    return element


metadata = ET.Element("PISI")
source = ET.SubElement(metadata, "Source")
child(source, "Name", spec["name"])
child(source, "Homepage", "https://github.com/nix-impurifiers/eopkg-impurifier")
packager = ET.SubElement(source, "Packager")
child(packager, "Name", "Nix Impurifiers")
child(packager, "Email", "root@localhost")
package = ET.SubElement(metadata, "Package")
for name, value in [
    ("Name", spec["name"]), ("Summary", spec["description"]),
    ("Description", spec["description"]), ("License", spec["license"]),
    ("Distribution", spec["distribution"]),
    ("DistributionRelease", spec["distributionRelease"]),
    ("Architecture", spec["architecture"]), ("PackageFormat", "1.2"),
]:
    child(package, name, value)
deps = ET.SubElement(package, "RuntimeDependencies")
for dependency in spec["dependencies"]:
    if isinstance(dependency, str):
        dependency = {"name": dependency}
    child(deps, "Dependency", dependency["name"], **{
        key: value for key, value in dependency.items() if key != "name"})
history = ET.SubElement(package, "History")
update = ET.SubElement(history, "Update", {"release": spec["release"]})
child(update, "Date", "1980-01-01")
child(update, "Version", spec["version"])
child(update, "Comment", "Nix application transport")
child(update, "Name", "Nix Impurifiers")
child(update, "Email", "root@localhost")
files = ET.Element("Files")
size = 0
paths = sorted(root.rglob("*"))
for path in paths:
    relative = path.relative_to(root).as_posix()
    if path.is_dir() and not path.is_symlink() and any(path.iterdir()):
        continue
    entry = ET.SubElement(files, "File")
    child(entry, "Path", relative)
    child(entry, "Type", "config" if relative.startswith("etc/") or "/" + relative in spec["configPaths"] else "data")
    stat = path.lstat()
    child(entry, "Size", stat.st_size if not path.is_dir() else 0)
    child(entry, "Uid", "0")
    child(entry, "Gid", "0")
    child(entry, "Mode", oct(stat.st_mode & 0o7777))
    if path.is_symlink():
        digest = hashlib.sha1(os.readlink(path).encode()).hexdigest()
    elif path.is_file():
        with path.open("rb") as stream:
            digest = hashlib.file_digest(stream, "sha1").hexdigest()
        size += stat.st_size
    else:
        digest = None
    if digest is not None:
        child(entry, "Hash", digest)
if size == 0:
    raise ValueError("eopkg cannot persist zero-size metadata; include a nonempty inventory marker")
child(package, "InstalledSize", size)
with tempfile.TemporaryDirectory(dir=".") as temporary:
    archive = Path(temporary) / "install.tar.xz"
    with tarfile.open(archive, "w:xz", format=tarfile.PAX_FORMAT) as transport:
        for path in paths:
            info = transport.gettarinfo(str(path), path.relative_to(root).as_posix())
            info.uid = info.gid = 0
            info.uname = info.gname = "root"
            info.mtime = 1
            if info.isfile():
                with path.open("rb") as stream:
                    transport.addfile(info, stream)
            else:
                transport.addfile(info)
    with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_STORED) as native:
        for name, data in [("metadata.xml", ET.tostring(metadata, encoding="utf-8")),
                           ("files.xml", ET.tostring(files, encoding="utf-8")),
                           ("install.tar.xz", archive.read_bytes())]:
            entry = zipfile.ZipInfo(name, (1980, 1, 1, 0, 0, 0))
            entry.external_attr = 0o100644 << 16
            native.writestr(entry, data)
    parsed = pisi.package.Package(str(output), tmp_dir=temporary)
    parsed.read()
    if parsed.metadata.package.name != spec["name"]:
        raise ValueError("native metadata round-trip failed")
    expected_hashes = {entry.findtext("Path"): entry.findtext("Hash") for entry in files}
    actual_hashes = {entry.path: entry.hash for entry in parsed.files.list}
    if actual_hashes != expected_hashes:
        raise ValueError("native file checksums did not round-trip")
    parsed.close()
