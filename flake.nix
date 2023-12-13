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

    lib = pkgs.lib;

    testScript = { nodes, ... }: ''
    start_all()
    machine = ${hostName}

    machine.wait_for_unit("network-online.target")
    print(machine.succeed("getent hosts ${hostName}").strip())
    assert machine.succeed("getent hosts ${hostName} | grep '${hostName}'").strip()
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
      useNetworkd-fixed = pkgs.nixosTest {
        name = "useNetworkd-fixed";
        inherit testScript;
        nodes.machine = {
          systemd.package = pkgs.systemd.overrideAttrs (oa: {
            patches = oa.patches ++ [
              ./revert-pr-28370.patch
            ];
          });
          imports = [ common ];
          networking.useNetworkd = true;
        };
      };
    };
  };
}
