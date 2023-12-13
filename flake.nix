{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-23.11";
  description = "systemd getent hosts localhost reproducer";

  outputs = { self, nixpkgs }: let
    system = "x86_64-linux";
    hostName = "testhostname";
    domain = "testdomain";
    fqdn = "${hostName}.${domain}";
    pkgs = import nixpkgs {
      inherit system;
    };
    pkgsFixed = import nixpkgs {
      inherit system;
      overlays = [
        (self: super: {
          systemd = super.systemd.overrideAttrs (oa: {
            patches = oa.patches ++ [
              ./revert-pr-28370.patch
            ];
          });
        })
      ];
    };
    lib = pkgs.lib;

    testScript = { nodes, ... }: ''
    start_all()
    machine = ${hostName}

    machine.wait_for_unit("network-online.target")

    # The FQDN, domain name, and hostname detection should work as expected:
    assert "${fqdn}" == machine.succeed("hostname --fqdn").strip()
    assert "${domain}" == machine.succeed("dnsdomainname").strip()
    assert (
        "${hostName}"
        == machine.succeed(
            'hostnamectl status | grep "Static hostname" | cut -d: -f2'
        ).strip()
    )

    # 127.0.0.1 and ::1 should resolve back to "localhost":
    assert (
        "localhost" == machine.succeed("getent hosts 127.0.0.1 | awk '{print $2}'").strip()
    )
    assert "localhost" == machine.succeed("getent hosts ::1 | awk '{print $2}'").strip()

    # 127.0.0.2 should resolve back to the FQDN and hostname:
    fqdn_and_host_name = "${"${hostName}.${domain} "}${hostName}"
    assert (
        fqdn_and_host_name
        == machine.succeed("getent hosts 127.0.0.2 | awk '{print $2,$3}'").strip()
    )
  '';

    common = {
      networking = {
        inherit hostName domain;
      };

      environment.systemPackages = with pkgs; [
        inetutils
      ];
    };
  in {
    packages.${system} = {
      legacy-works = pkgs.nixosTest {
        name = "legacy-works";
        inherit testScript;
        nodes.machine = {
          imports = [ common ];
        };
      };
      useNetworkd-broken = pkgs.nixosTest {
        name = "useNetworkd-broken";
        inherit testScript;
        nodes.machine = {
          imports = [ common ];
          networking.useNetworkd = true;
        };
      };
      useNetworkd-fixed = pkgsFixed.nixosTest {
        name = "useNetworkd-fixed";
        inherit testScript;
        nodes.machine = {
          imports = [ common ];
          networking.useNetworkd = true;
        };
      };
    };
  };
}
