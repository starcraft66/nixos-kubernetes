{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-22.11";
    flake-compat.url = "github:edolstra/flake-compat";
    flake-compat.flake = false;
    flake-utils.url = "github:numtide/flake-utils";
  };
  outputs = inputs@{ self, nixpkgs, flake-utils, ... }:
    let platforms = [ "x86_64-linux" "x86_64-darwin" "aarch64-darwin" ];
    in {
      overlays = {
        inputs = final: prev: { inherit inputs; };
        kubernetes = final: prev: {
          etcd = prev.pkgs.etcd_3_5;
          hubble = prev.hubble.overrideAttrs (oldAttrs: {
            # remove `|| stdenv.isDarwin`
            meta.broken = (prev.stdenv.isLinux && prev.stdenv.isAarch64);
          });
          cni-plugin-cilium =
            final.callPackage ./pkgs/cni-plugin-cilium.nix { };
        };
      };
    } // inputs.flake-utils.lib.eachSystem platforms (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = builtins.attrValues self.overlays;
        };
        inherit (nixpkgs) lib;
      in {
        devShells.default = let
          myTerraform = pkgs.terraform.withPlugins (tp: [ tp.libvirt ]);
          ter = pkgs.writeShellScriptBin "ter" ''
            ${myTerraform}/bin/terraform $@ && \
              ${myTerraform}/bin/terraform show -json > show.json
          '';

          ci-lint = pkgs.writeShellScriptBin "ci-lint" ''
            echo Checking the formatting of Nix files
            ${pkgs.nixpkgs-fmt}/bin/nixpkgs-fmt --check **/*.nix

            echo

            echo Checking the formatting of Terraform files
            ${myTerraform}/bin/terraform fmt -check -recursive
          '';

          k = pkgs.writeShellScriptBin "k" ''
            kubectl --kubeconfig certs/generated/kubernetes/admin.kubeconfig $@
          '';

          make-boot-image = pkgs.writeShellScriptBin "make-boot-image" ''
            nix-build -o boot/image boot/image.nix
          '';

          make-certs = pkgs.writeShellScriptBin "make-certs" ''
            $(nix-build --no-out-link certs)/bin/generate-certs
          '';
        in pkgs.mkShell {
          buildInputs = with pkgs; [
            # software for deployment
            colmena
            jq
            libxslt
            myTerraform

            # software for testing
            etcd
            kubectl
            cilium-cli
            hubble
            openssl

            # scripts
            ci-lint
            k
            make-boot-image
            make-certs
            ter
          ];
        };
      }) // (let
        pkgs = import nixpkgs {
          # We deploying to x86_64 linux
          system = "x86_64-linux";
          overlays = builtins.attrValues self.overlays;
        };

        inherit (pkgs.callPackage ./resources.nix { })
          resources resourcesByRole;
        inherit (import ./utils.nix) nodeIP;

        etcdHosts = map (r: r.values.name) (resourcesByRole "etcd");
        controlPlaneHosts =
          map (r: r.values.name) (resourcesByRole "controlplane");
        workerHosts = map (r: r.values.name) (resourcesByRole "worker");
        loadBalancerHosts =
          map (r: r.values.name) (resourcesByRole "loadbalancer");

        etcdConf = { ... }: {
          imports = [ ./modules/etcd.nix ];
          deployment.tags = [ "etcd" ];
        };

        controlPlaneConf = { ... }: {
          imports = [ ./modules/controlplane ];
          deployment.tags = [ "controlplane" ];
        };

        workerConf = { ... }: {
          imports = [ ./modules/worker ];
          deployment.tags = [ "worker" ];
        };

        loadBalancerConf = { ... }: {
          imports = [ ./modules/loadbalancer ];
          deployment.tags = [ "loadbalancer" ];
        };
      in {
        colmena = {
          meta.nixpkgs = pkgs;

          defaults = { name, self, ... }: {
            imports = [ ./modules/autoresources.nix ./modules/base.nix ];

            deployment.targetHost = nodeIP self;
            networking.hostName = name;

            system.stateVersion = "22.05";
          };
        } // builtins.listToAttrs (map (h: {
          name = h;
          value = etcdConf;
        }) etcdHosts) // builtins.listToAttrs (map (h: {
          name = h;
          value = controlPlaneConf;
        }) controlPlaneHosts) // builtins.listToAttrs (map (h: {
          name = h;
          value = loadBalancerConf;
        }) loadBalancerHosts) // builtins.listToAttrs (map (h: {
          name = h;
          value = workerConf;
        }) workerHosts);
      });
}
