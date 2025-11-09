{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.security.rave.sopsBootstrap;

  secretModule = types.submodule ({ config, ... }: {
    options = {
      selector = mkOption {
        type = types.str;
        description = ''SOPS --extract selector (e.g. ["group"]["key"]).'';
      };

      path = mkOption {
        type = types.str;
        description = "Filesystem path where the secret will be written.";
      };

      owner = mkOption {
        type = types.str;
        default = "root";
        description = "Owner applied to the secret file.";
      };

      group = mkOption {
        type = types.str;
        default = "root";
        description = "Group applied to the secret file.";
      };

      mode = mkOption {
        type = types.str;
        default = "0400";
        description = "File mode applied to the secret file.";
      };
    };
  });

  ageKeyPath = cfg.ageKeyPath;

  mountCommand = "${pkgs.util-linux}/bin/mount -t 9p -o trans=virtio,version=9p2000.L,rw ${cfg.virtfsTag} /host-keys";

  extractScript = pkgs.writeShellScript "rave-extract-sops-secret" ''
    set -euo pipefail
    selector="$1"
    dest="$2"
    owner="$3"
    group="$4"
    mode="$5"

    echo "Extracting secret $selector -> $dest"
    dest_dir="$(${pkgs.coreutils}/bin/dirname -- "$dest")"
    ${pkgs.coreutils}/bin/mkdir -p "$dest_dir"
    ${pkgs.sops}/bin/sops -d --extract "$selector" ${cfg.sopsFile} > "$dest"
    chown "$owner:$group" "$dest"
    chmod "$mode" "$dest"
  '';

in {
  options.security.rave.sopsBootstrap = {
    enable = mkEnableOption "Bootstrap AGE keys and decrypt SOPS secrets";

    sopsFile = mkOption {
      type = types.path;
      description = "Absolute path to the SOPS secrets YAML file.";
    };

    ageKeyPath = mkOption {
      type = types.str;
      default = "/var/lib/sops-nix/key.txt";
      description = "Destination path for the AGE key pulled from virtfs/env.";
    };

    virtfsTag = mkOption {
      type = types.str;
      default = "sops-keys";
      description = "Virtio fs tag used to mount the host-provided AGE key.";
    };

    secretMappings = mkOption {
      type = types.listOf secretModule;
      default = [];
      description = "List of SOPS selectors to extract along with destination metadata.";
    };

    extraTmpfiles = mkOption {
      type = types.listOf types.str;
      default = [];
      description = "Additional tmpfiles rules to append when the bootstrap is enabled.";
    };
  };

  config = mkIf cfg.enable {
    systemd.services.mount-sops-keys = {
      description = "Mount SOPS keys filesystem for AGE key access";
      wantedBy = [ "multi-user.target" ];
      after = [ "local-fs.target" ];
      before = [ "install-age-key.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = "root";
        Group = "root";
      };
      script = ''
        set -euo pipefail
        mkdir -p /host-keys
        echo "Attempting to mount virtfs with tag '${cfg.virtfsTag}'..."
        if ${mountCommand}; then
          echo "SOPS keys filesystem mounted at /host-keys"
          ls -la /host-keys/ || true
        else
          echo "Failed to mount virtfs; continuing (development mode?)"
          ls -la /sys/bus/virtio/devices/ || true
        fi
      '';
    };

    systemd.services.install-age-key = {
      description = "Install AGE key from host system";
      wantedBy = [ "multi-user.target" ];
      after = [ "local-fs.target" ];
      before = [ "sops-init.service" "sops-nix.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = "root";
        Group = "root";
      };
      script = ''
        set -euo pipefail
        mkdir -p /var/lib/sops-nix /host-keys

        echo "Attempting virtfs mount for AGE keys..."
        if ${mountCommand} 2>/dev/null; then
          echo "virtfs mounted successfully"
          if [ -f /host-keys/keys.txt ]; then
            cp /host-keys/keys.txt ${ageKeyPath}
            chmod 600 ${ageKeyPath}
            echo "AGE key installed from virtfs"
            exit 0
          else
            echo "virtfs mounted but keys.txt missing"
            umount /host-keys 2>/dev/null || true
          fi
        fi

        if [ -n "''${SOPS_AGE_KEY:-}" ]; then
          echo "Installing AGE key from SOPS_AGE_KEY environment variable"
          printf '%s' "$SOPS_AGE_KEY" > ${ageKeyPath}
          chmod 600 ${ageKeyPath}
          exit 0
        fi

        echo "No AGE key available; running in development mode"
        exit 0
      '';
    };

    systemd.services.sops-init = {
      description = "Initialize SOPS secrets";
      wantedBy = [ "multi-user.target" ];
      after = [ "install-age-key.service" ];
      before = [ "gitlab-db-password.service" "gitlab.service" "mattermost.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = "root";
        Group = "root";
      };
      script = ''
        set -euo pipefail
        if [ ! -f ${ageKeyPath} ]; then
          echo "AGE key missing at ${ageKeyPath}"
          exit 1
        fi
        if [ ! -f ${cfg.sopsFile} ]; then
          echo "SOPS file ${cfg.sopsFile} missing"
          exit 1
        fi

        export SOPS_AGE_KEY_FILE=${ageKeyPath}
        ${pkgs.coreutils}/bin/mkdir -p /run/secrets/gitlab /run/secrets/mattermost /run/secrets/oidc

        ${concatStringsSep "\n" (map (secret: ''
          ${extractScript} '${secret.selector}' '${secret.path}' '${secret.owner}' '${secret.group}' '${secret.mode}'
        '') cfg.secretMappings)}

        echo "SOPS secrets extracted"
      '';
    };

    systemd.tmpfiles.rules = mkAfter (
      [
        "d /run/secrets 0755 root root -"
        "d /run/secrets/gitlab 0750 postgres gitlab -"
        "d /run/secrets/mattermost 0750 root mattermost -"
        "d /run/secrets/oidc 0700 root root -"
      ]
      ++ cfg.extraTmpfiles
    );
  };
}
