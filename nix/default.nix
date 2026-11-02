# SPDX-License-Identifier: MIT
{
  pkgs,
  coreSrc,
  sourceInfo ? { },
}:
let
  inherit (pkgs) lib;
  core = import (coreSrc + "/nix") {
    inherit pkgs;
    sourceInfo = {
      # Native updates must include adapter-only releases, not just engine pins.
      lastModified = pkgs.lib.max (if builtins.isAttrs coreSrc then coreSrc.lastModified or 0 else 0) (
        if builtins.isAttrs sourceInfo then sourceInfo.lastModified or 0 else 0
      );
    };
    namespace = "eopkg-impurifier";
  };
  tools = import ./tools.nix { pkgs = pkgs.buildPackages; };
  defaultArchitecture =
    if pkgs.stdenv.hostPlatform.isx86_64 then
      "x86_64"
    else if pkgs.stdenv.hostPlatform.isAarch64 then
      "aarch64"
    else
      throw "unsupported eopkg architecture";
  adapter = pkgs.writeScriptBin "eopkg-impurifier" (
    builtins.replaceStrings [ "#!/usr/bin/python3" ] [ "#!${pkgs.python3}/bin/python3" ] (
      builtins.readFile ../src/adapter.py
    )
  );
  buildPackage =
    {
      name,
      version,
      payload,
      release ? "1",
      architecture ? defaultArchitecture,
      description ? "Impurified Nix application",
      license ? "LicenseRef-Unknown",
      distribution ? "Solus",
      distributionRelease ? "1",
      dependencies ? [ ],
      configPaths ? [ ],
    }:
    assert lib.assertMsg (
      builtins.match "[a-z0-9][a-z0-9+_.-]*" name != null
      && builtins.match "[A-Za-z0-9_.+]+" version != null
      && builtins.match "[1-9][0-9]*" release != null
      && builtins.match "[A-Za-z0-9_]+" architecture != null
    ) "invalid eopkg package metadata";
    assert lib.assertMsg (lib.all (
      dep:
      let
        value = if builtins.isString dep then { name = dep; } else dep;
      in
      builtins.match "[a-z0-9][a-z0-9+_.-]*" value.name != null
      && lib.all (
        key:
        lib.elem key [
          "name"
          "version"
          "versionFrom"
          "versionTo"
          "release"
          "releaseFrom"
          "releaseTo"
        ]
      ) (builtins.attrNames value)
    ) dependencies) "invalid eopkg dependency";
    pkgs.runCommand "${name}-${version}-${release}-eopkg-package"
      {
        __structuredAttrs = true;
        unsafeDiscardReferences.out = true;
        passthru.filename = "${name}-${version}-${release}-${architecture}.eopkg";
      }
      ''
        mkdir -p root $out
        cp -r ${payload}/. root/
        chmod -R u+w root
        ${tools.python}/bin/python3 ${../src/build-package.py} ${
          pkgs.writeText "eopkg-spec.json" (
            builtins.toJSON {
              inherit
                name
                version
                release
                description
                license
                distribution
                distributionRelease
                dependencies
                configPaths
                ;
              inherit architecture;
            }
          )
        } root $out/${name}-${version}-${release}-${architecture}.eopkg
      '';
  makePackage =
    args@{
      pkg,
      release ? "1",
      hostDependencies ? [ ],
      distribution ? "Solus",
      distributionRelease ? "1",
      license ? null,
      ...
    }:
    let
      payload = core.makePayload (
        builtins.removeAttrs args [
          "release"
          "hostDependencies"
          "distribution"
          "distributionRelease"
          "license"
        ]
      );
      nativeLicense =
        if license != null then
          license
        else
          lib.concatMapStringsSep " AND " (value: value.spdxId or "LicenseRef-Unknown") (
            lib.toList (pkg.meta.license or [ ])
          );
    in
    buildPackage {
      name = payload.name;
      inherit (payload) version description configPaths;
      inherit
        payload
        release
        distribution
        distributionRelease
        ;
      license = if nativeLicense == "" then "LicenseRef-Unknown" else nativeLicense;
      dependencies = [
        {
          name = "eopkg-impurifier";
          versionFrom = core.runtimeVersion;
        }
      ]
      ++ hostDependencies;
    };
  makeRuntimePackage =
    {
      nixDependency ? "nix",
      pythonDependency ? "python3",
      eopkgDependency ? "python-eopkg",
      distribution ? "Solus",
      distributionRelease ? "1",
    }:
    buildPackage {
      name = "eopkg-impurifier";
      version = core.runtimeVersion;
      license = "MIT";
      inherit distribution distributionRelease;
      dependencies = [
        nixDependency
        pythonDependency
        eopkgDependency
      ];
      payload = pkgs.runCommand "eopkg-impurifier-runtime-payload" { } ''
        mkdir -p $out
        cp -r ${core.makeRuntimeTree { }}/. $out/
        chmod -R u+w $out
        install -Dm755 ${../src/adapter.py} $out/usr/sbin/eopkg-impurifier
      '';
    };
in
{
  inherit (core)
    engine
    offlineCache
    unit
    runtimeVersion
    ;
  inherit
    adapter
    buildPackage
    makePackage
    makeRuntimePackage
    ;
  nativeEopkg = tools.package;
  runtimePackage = makeRuntimePackage { };
  makeNetPackage = args: makePackage (args // { offline = false; });
  makeOfflinePackage = args: makePackage (args // { offline = true; });
}
