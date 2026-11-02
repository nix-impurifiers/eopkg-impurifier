# Testing

QEMU runs actual pinned eopkg 5.0 on NixOS with native checks enabled. Real preinstalled Nix/Python/eopkg have nonempty native inventory markers, not installers. Legacy runtime rejection is checked before application unpack. The full suite covers dependencies, offline recovery, flavor/configuration changes, batching, accounts/services/admin intent, driver refresh, foreign destdir rejection, removal and rooted GC. usysconf is absent and native diagnostics remain visible; this does not claim full Solus integration.
