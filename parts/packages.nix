{ inputs, ... }:
{
  perSystem = { system, lib, pkgs, self', config, ... }:
    let
      mkImage = config._module.args.mkImage;
      mkVmVariant = config._module.args.mkVmVariant;
      overlaysList = config._module.args.overlaysList or [];
      mkProfileImage = module: mkImage { configModule = module; };
    in {
      packages = {
        production = mkProfileImage ../infra/nixos/configs/production.nix;
        dataPlane = mkProfileImage ../infra/nixos/configs/data-plane.nix;
        appsPlane = mkProfileImage ../infra/nixos/configs/apps-plane.nix;
        development = mkProfileImage ../infra/nixos/configs/development.nix;
        demo = mkProfileImage ../infra/nixos/configs/demo.nix;
        productionWithPort = mkImage { configModule = ../infra/nixos/configs/production.nix; };
        virtualbox = mkImage { configModule = ../infra/nixos/configs/production.nix; format = "virtualbox"; };
        vmware = mkImage { configModule = ../infra/nixos/configs/production.nix; format = "vmware"; };
        raw = mkImage { configModule = ../infra/nixos/configs/production.nix; format = "raw"; };
        iso = mkImage { configModule = ../infra/nixos/configs/production.nix; format = "iso"; };
        default = self'.packages.production;
        vm-production = mkVmVariant { configModule = ../infra/nixos/configs/production.nix; };
        vm-development = mkVmVariant { configModule = ../infra/nixos/configs/development.nix; };
        vm-dataPlane = mkVmVariant { configModule = ../infra/nixos/configs/data-plane.nix; };
        vm-appsPlane = mkVmVariant { configModule = ../infra/nixos/configs/apps-plane.nix; };
        vm-demo = mkVmVariant { configModule = ../infra/nixos/configs/demo.nix; };
        rave-cli = pkgs.writeShellScriptBin "rave" ''
          export PATH="${pkgs.python3.withPackages (ps: [ ps.click ])}/bin:$PATH"
          cd ${../.}
          exec python3 src/apps/cli/rave "$@"
        '';
        auth-manager = pkgs.auth-manager;
      };

      flake.profileMetadata = {
        production = {
          attr = "production";
          description = "Full stack (GitLab, Mattermost, Penpot, Outline, n8n, observability)";
          defaultImage = "artifacts/qcow/production/rave-production-localhost.qcow2";
          features = {
            penpot = true;
            outline = true;
            n8n = true;
            monitoring = true;
          };
        };
        dataPlane = {
          attr = "dataPlane";
          description = "Data plane only (PostgreSQL + Redis, SSH, SOPS secrets)";
          defaultImage = "artifacts/qcow/data-plane/rave-data-plane.qcow2";
          features = {
            penpot = false;
            outline = false;
            n8n = false;
            monitoring = false;
          };
        };
        appsPlane = {
          attr = "appsPlane";
          description = "Application plane (GitLab/Mattermost/etc.) targeting external data services";
          defaultImage = "artifacts/qcow/apps-plane/rave-apps-plane.qcow2";
          features = {
            penpot = true;
            outline = true;
            n8n = true;
            monitoring = true;
          };
        };
        development = {
          attr = "development";
          description = "Slimmer build (Penpot/Outline/n8n disabled, lower RAM/disk)";
          defaultImage = "artifacts/qcow/development/rave-development-localhost.qcow2";
          features = {
            penpot = false;
            outline = false;
            n8n = false;
            monitoring = true;
          };
        };
        demo = {
          attr = "demo";
          description = "Demo-friendly stack (observability + optional apps disabled)";
          defaultImage = "artifacts/qcow/demo/rave-demo-localhost.qcow2";
          features = {
            penpot = false;
            outline = false;
            n8n = false;
            monitoring = false;
          };
        };
      };
    };
}
