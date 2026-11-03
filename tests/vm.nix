# SPDX-License-Identifier: MIT
{
  pkgs,
  impurifier,
  hardwareFixture,
  bundled ? false,
}:
let
  tool =
    version:
    pkgs.runCommand "eopkg-tool-${version}"
      {
        pname = "eopkg-tool";
        inherit version;
      }
      ''
        mkdir -p $out/bin
        printf '#!${pkgs.busybox}/bin/sh\necho ${version}\n' > $out/bin/eopkg-tool
        chmod +x $out/bin/eopkg-tool
      '';
  app =
    offline: version:
    impurifier.makePackage {
      pkg = tool version;
      inherit offline;
      configFiles."/etc/eopkg-tool.conf" = pkgs.writeText "eopkg-config" "version=${version}\n";
    };
  daemon =
    version:
    pkgs.runCommand "eopkg-service-${version}"
      {
        pname = "eopkg-service";
        inherit version;
      }
      ''
        mkdir -p $out/bin
        cat > $out/bin/eopkg-service <<'SCRIPT'
        #!${pkgs.busybox}/bin/sh
        echo ${version} > /var/lib/eopkg-service/version
        exec ${pkgs.busybox}/bin/sleep infinity
        SCRIPT
        chmod +x $out/bin/eopkg-service
      '';
  service =
    version:
    impurifier.makeOfflinePackage {
      pkg = daemon version;
      users.eopkg-service = { };
      directories."/var/lib/eopkg-service" = {
        owner = "eopkg-service:eopkg-service";
        mode = "0750";
      };
      lifecycle = {
        onInstall = ''
          /usr/bin/python3 -c "import pwd; pwd.getpwnam('eopkg-service')"
          test -x /opt/nix/profile/bin/eopkg-service
          echo initialized > /var/lib/eopkg-service/initialized
        '';
        onUpgrade = "echo ${version} > /var/lib/eopkg-service/migrated";
      };
      systemd.unit = pkgs.writeText "eopkg-service.service" ''
        [Service]
        Type=exec
        User=eopkg-service
        ExecStart=/opt/nix/profile/bin/eopkg-service
        [Install]
        WantedBy=multi-user.target
      '';
    };
  provider =
    name:
    impurifier.buildPackage {
      inherit name;
      version = "1";
      payload = pkgs.runCommand "${name}-inventory" { } ''
        mkdir -p $out/usr/share/eopkg-fixture
        echo preinstalled > $out/usr/share/eopkg-fixture/${name}
      '';
    };
  hostDriver =
    version:
    impurifier.buildPackage {
      name = "impurifier-host-driver";
      inherit version;
      payload = hardwareFixture.driver version;

    };
  hardware = impurifier.makeOfflinePackage {
    hostDependencies = [ "impurifier-host-driver" ];
    pkg = hardwareFixture.tool;
    inherit (hardwareFixture) hardware;
  };
in
pkgs.testers.runNixOSTest {
  name = "eopkg-impurifier";
  requiredFeatures = {
    kvm = false;
    devnet = false;
  };
  nodes.machine = { lib, ... }: {
    virtualisation.memorySize = 2048;
    virtualisation.useNixStoreImage = true;
    virtualisation.writableStore = true;
    virtualisation.qemu.package = lib.mkForce pkgs.qemu;
    virtualisation.qemu.forceAccel = false;
    environment.systemPackages = [
      impurifier.nativeEopkg
      pkgs.nix
      pkgs.python3
    ];
    systemd.tmpfiles.rules = [
      "d /usr/bin 0755 root root -"
      "L+ /usr/bin/python3 - - - - ${pkgs.python3}/bin/python3"
      "L+ /usr/bin/nix-store - - - - ${
        if bundled then
          pkgs.writeShellScript "incompatible-nix-store" "echo incompatible; exit 1"
        else
          "${pkgs.nix}/bin/nix-store"
      }"
      "L+ /usr/bin/systemctl - - - - ${pkgs.systemd}/bin/systemctl"
      "L+ /usr/bin/systemd-sysusers - - - - ${pkgs.systemd}/bin/systemd-sysusers"
      "L+ /usr/bin/systemd-tmpfiles - - - - ${pkgs.systemd}/bin/systemd-tmpfiles"
    ];
    nix.settings.substituters = lib.mkForce [ ];
  };
  testScript = ''
    start_all()
    machine.wait_for_unit("multi-user.target")
    machine.succeed("mkdir -p /var/lib/eopkg /var/cache/eopkg /tmp/packages")
    machine.succeed("cp ${app false "1"}/*.eopkg /tmp/packages/net1.eopkg; cp ${app true "1"}/*.eopkg /tmp/packages/offline1.eopkg; cp ${app true "2"}/*.eopkg /tmp/packages/offline2.eopkg; cp ${service "1"}/*.eopkg /tmp/packages/service1.eopkg; cp ${service "2"}/*.eopkg /tmp/packages/service2.eopkg; cp ${hostDriver "1"}/*.eopkg /tmp/packages/driver1.eopkg; cp ${hostDriver "2"}/*.eopkg /tmp/packages/driver2.eopkg; cp ${hardware}/*.eopkg /tmp/packages/hardware.eopkg")
    machine.succeed("cp -rL /etc/systemd/system /tmp/systemd-system; chmod -R u+w /tmp/systemd-system; rm /etc/systemd/system; mv /tmp/systemd-system /etc/systemd/system; systemctl daemon-reload")
    machine.succeed("systemctl stop dhcpcd; ip link set eth0 down")
    install = "${impurifier.adapter}/bin/eopkg-impurifier install --reinstall -y "
    remove = "/usr/sbin/eopkg-impurifier remove -y "
    with subtest("native versioned dependency rejects a legacy runtime inventory marker"):
        machine.succeed(install + "${provider "nix"}/*.eopkg ${provider "python3"}/*.eopkg ${provider "python-eopkg"}/*.eopkg ${
          impurifier.buildPackage {
            name = "eopkg-impurifier";
            version = "0.1";
            payload =
              pkgs.runCommand "legacy-eopkg-runtime-marker" { }
                "mkdir -p $out/usr/share/eopkg-fixture; echo legacy-inventory > $out/usr/share/eopkg-fixture/legacy-runtime";
          }
        }/*.eopkg")
        machine.succeed("eopkg info eopkg-impurifier | grep 0.1")
        code, output = machine.execute(install + "/tmp/packages/offline1.eopkg 2>&1")
        assert code != 0 and "eopkg-impurifier" in output, output
        machine.fail("test -d /var/lib/eopkg/package/eopkg-tool-1-1")
    machine.succeed(install + "${impurifier.runtimePackage}/*.eopkg")
    machine.fail("test -e ${builtins.unsafeDiscardStringContext (toString (tool "1"))}")
    with subtest("adapter fetch failure preserves the previous profile"):
        before = machine.succeed("readlink /opt/nix/profile").strip()
        code, output = machine.execute(install + "/tmp/packages/net1.eopkg 2>&1")
        assert code != 0 and "nix-profile-engine:" in output, output
        assert machine.succeed("readlink /opt/nix/profile").strip() == before
    with subtest("help remains read-only with unresolved native intent"):
        output = machine.succeed(install + "--help")
        assert "nix-profile-engine:" not in output, output
        assert machine.succeed("readlink /opt/nix/profile").strip() == before
    with subtest("offline reinstall recovers with no network"):
        machine.succeed(install + "/tmp/packages/offline1.eopkg")
        machine.succeed("test $(/opt/nix/profile/bin/eopkg-tool) = 1")
    with subtest("native checksums update unedited defaults"):
        machine.succeed("grep version=1 /etc/eopkg-tool.conf")
        machine.succeed(install + "/tmp/packages/offline2.eopkg")
        machine.succeed("grep version=2 /etc/eopkg-tool.conf")
        machine.succeed(install + "/tmp/packages/offline1.eopkg")
        machine.succeed("grep version=1 /etc/eopkg-tool.conf")
    with subtest("native conffiles survive transport switches and upgrades"):
        machine.succeed("echo local > /etc/eopkg-tool.conf")
        machine.succeed(install + "/tmp/packages/net1.eopkg")
        machine.succeed("grep local /etc/eopkg-tool.conf")
        machine.succeed(install + "/tmp/packages/offline2.eopkg")
        machine.succeed("grep local /etc/eopkg-tool.conf; test $(/opt/nix/profile/bin/eopkg-tool) = 2")
    with subtest("adapter activation follows the complete native batch"):
        output = machine.succeed(install + "${
          impurifier.makeOfflinePackage {
            pkg = pkgs.hello;
            name = "batch-a";
            version = "1";
          }
        }/*.eopkg ${
          impurifier.makeOfflinePackage {
            pkg = pkgs.hello;
            name = "batch-b";
            version = "1";
          }
        }/*.eopkg")
        assert output.count("activated ") == 1, output
        machine.succeed("/opt/nix/profile/bin/hello | grep Hello")
        machine.succeed(remove + "batch-a batch-b")
    with subtest("native service ownership and lifecycle preserve administrator intent"):
        machine.succeed(install + "/tmp/packages/service1.eopkg")
        machine.wait_for_unit("eopkg-service.service")
        machine.wait_until_succeeds("grep '^1$' /var/lib/eopkg-service/version")
        machine.succeed("grep initialized /var/lib/eopkg-service/initialized; test $(stat -c %U /var/lib/eopkg-service) = eopkg-service")
        machine.succeed(install + "/tmp/packages/service2.eopkg")
        machine.wait_until_succeeds("grep '^2$' /var/lib/eopkg-service/version")
        machine.succeed("grep '^2$' /var/lib/eopkg-service/migrated")
        machine.succeed("systemctl disable --now eopkg-service.service")
        machine.succeed(install + "/tmp/packages/service1.eopkg")
        machine.fail("systemctl is-active --quiet eopkg-service.service")
        machine.fail("systemctl is-enabled --quiet eopkg-service.service")
        machine.succeed("systemctl enable --now eopkg-service.service")
        machine.succeed(remove + "eopkg-service")
        machine.fail("systemctl is-active --quiet eopkg-service.service")
        machine.fail("test -e /etc/systemd/system/eopkg-service.service")
    with subtest("native driver transactions refresh snapshot bindings"):
        code, output = machine.execute(install + "/tmp/packages/hardware.eopkg 2>&1")
        assert code != 0 and "impurifier-host-driver" in output, output
        machine.succeed(install + "/tmp/packages/driver1.eopkg /tmp/packages/hardware.eopkg")
        machine.succeed("/opt/nix/profile/bin/hardware-tool | grep '^1$'")
        machine.succeed(install + "/tmp/packages/driver2.eopkg")
        machine.succeed("/opt/nix/profile/bin/hardware-tool | grep '^2$'")
        machine.succeed(remove + "hardware-tool")
        machine.succeed(remove + "impurifier-host-driver")
    with subtest("offline-root maintainer scripts cannot activate the host"):
        before = machine.succeed("readlink /opt/nix/profile").strip()
        code, output = machine.execute(install + "--destdir=/tmp/foreign-root /tmp/packages/offline1.eopkg 2>&1")
        assert code != 0 and "foreign destdir cannot activate the host" in output, output
        assert machine.succeed("readlink /opt/nix/profile").strip() == before
    with subtest("GC and native removal release profile intent"):
        machine.succeed("nix-store --gc; test $(/opt/nix/profile/bin/eopkg-tool) = 2")
        machine.succeed(remove + "eopkg-tool")
        machine.fail("test -e /opt/nix/profile/bin/eopkg-tool")
        machine.succeed("grep local /etc/eopkg-tool.conf")
        machine.succeed("/usr/sbin/nix-profile-engine prune --keep 0; nix-store --gc; test -d /opt/nix/profile")
  '';
}
