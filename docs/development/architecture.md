# Architecture

Format 1.2 zip archives contain metadata.xml, files.xml and install.tar.xz. The emitter validates them with upstream eopkg. Native runtime version constraints precede unpacking. Flavors have identical native identity and require explicit reinstall. The adapter runs native transactions before atomic profile reconciliation; native filesystem changes are not rolled back. Native /etc configuration protection remains authoritative. Current Solus C usysconf and newer Go/TOML usysconf are distinct; no unsupported trigger path is assumed.
