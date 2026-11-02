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
