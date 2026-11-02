# eopkg-impurifier

Build native eopkg format 1.2 archives for Nix applications. Original project
code is MIT licensed. Upstream eopkg and its dependencies retain their own
licenses. This backend is package-manager scoped; consumers choose native
providers and distribution metadata.

```nix
let impurifier = inputs.eopkg-impurifier.lib.eopkg-impurifier { inherit pkgs; };
in impurifier.makeOfflinePackage { pkg = pkgs.hello; }
```

Build `adapter` and `runtime-package`, then use the adapter to install the
runtime. Nix, Python and eopkg must already have native inventory providers.
`makeRuntimePackage` accepts `nixDependency`, `pythonDependency` and
`eopkgDependency` (default `python-eopkg`). Providing Nix itself is deferred,
not excluded.

Use `/usr/sbin/eopkg-impurifier install --reinstall -y /path/to/app/*.eopkg`
and `/usr/sbin/eopkg-impurifier remove -y app-name`. This wrapper runs actual
eopkg, then reconciles the Nix profile after the native transaction. Existing
native configuration hooks still run. **Plain eopkg does not activate profiles**;
use the adapter for managed packages and driver updates, or reconcile manually.
Solus currently packages the C usysconf implementation; this adapter does not
assume that newer Go/TOML trigger configuration is available.

The wrapper accepts native options and supports install/it, upgrade/up and
remove/rm. Dry-run and fetch-only commands do not reconcile. Foreign destdir
activation is rejected. Native failure may follow partial changes; the wrapper
reconciles actual intent and returns failure. Engine failure preserves the
previous published profile, not a rollback of native files. Repair, then run
`/usr/sbin/nix-profile-engine reconcile`.

`makeNetPackage`, `makeOfflinePackage` and `makePackage` accept shared application
arguments, numeric `release`, `hostDependencies`, `license`, `distribution` and
`distributionRelease`. Defaults for the last two are Solus/1; native architecture
is selected from the target platform. Native checks remain enabled. Dependency
entries are names or attributes such as `{ name = "driver"; versionFrom = "2"; }`.
Applications require a versioned runtime derived from the pinned core source.
These are native artifact versions, not SemVer releases.

Net/offline variants retain the same native name/version/release and live in
separate output directories/channels. Use native `--reinstall` to switch flavors.
Offline archives contain the complete Nix closure. `/etc` files use native
configuration protection, including preservation of modified files on normal
removal. Native purge remains a separate operator decision.

Shared users, directories, lifecycle hooks, explicit hardware bindings and
chosen systemd/OpenRC/runit protocols are supported. Consumers supply native
host dependency names; CLI applications retain explicit dependencies too.
`buildPackage` emits a raw archive from a payload. Its installed size must be
nonzero: upstream eopkg cannot persist zero-size metadata reliably. Inventory
markers should contain a short description instead of an empty file.

The emitter validates archives with upstream eopkg's reader. `nix flake check -L`
also boots QEMU and runs the actual pinned eopkg 5.0 client, with native version,
distribution and architecture checks enabled. Coverage includes legacy-runtime
rejection before unpack, dependency solving, offline recovery, flavor switches,
protected and unedited config, batch activation, accounts/services/lifecycle/admin intent,
driver refresh, foreign-root safety, removal and GC. The outer OS/init is NixOS;
preinstalled providers are inventory markers, not installers. The fixture does
not install usysconf and eopkg reports its normal missing-usysconf diagnostic;
full Solus/usysconf integration remains separate coverage.
