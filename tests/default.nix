# SPDX-License-Identifier: MIT
{
  pkgs,
  impurifier,
  coreSrc,
}:
let
  package = impurifier.makeOfflinePackage { pkg = pkgs.hello; };
  closure = pkgs.closureInfo { rootPaths = [ package ]; };
in
{
  native-vm = import ./native-vm.nix { inherit pkgs impurifier; };
  bundled-vm = import ./vm.nix {
    inherit pkgs;
    bundled = true;
    impurifier = impurifier // {
      runtimePackage = impurifier.makeRuntimePackage {
        bundledNixStore = "${import (coreSrc + "/tests/static-nix.nix") { inherit pkgs; }}/bin/nix-store";
        bundledNixNotices = [ "${pkgs.nix.src}/COPYING" ];
      };
    };
    hardwareFixture = import (coreSrc + "/tests/hardware-fixture.nix") { inherit pkgs; };
  };
  unit = impurifier.unit;
  emitter = pkgs.runCommand "eopkg-transport-contract" { } ''
    test "$(wc -l < ${closure}/store-paths)" = 1
    touch $out
  '';
  vm = import ./vm.nix {
    inherit pkgs impurifier;
    hardwareFixture = import (coreSrc + "/tests/hardware-fixture.nix") { inherit pkgs; };
  };
}
