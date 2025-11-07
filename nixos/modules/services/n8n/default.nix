{ config, lib, pkgs, ... }:

let
  cfg = config.services.rave.n8n;
  basePath = cfg.basePath;
  normalizedPath = if lib.hasSuffix "/" basePath then basePath else "${basePath}/";
  redirectPath = lib.removeSuffix "/" normalizedPath;
  publicUrl = cfg.publicUrl;
in {
  options.services.rave.n8n = {
    enable = lib.mkEnableOption "n8n automation service";

    publicUrl = lib.mkOption {
      type = lib.types.str;
      default = "https://localhost:8443/n8n";
      description = "External URL (including base path) for n8n.";
    };

    dockerImage = lib.mkOption {
      type = lib.types.str;
      default = "n8nio/n8n:latest";
      description = "Container image to run";
    };

    hostPort = lib.mkOption {
      type = lib.types.int;
      default = 5678;
      description = "Loopback port for n8n";
    };

    dbPassword = lib.mkOption {
      type = lib.types.str;
      default = "n8n-production-password";
      description = "PostgreSQL password used by n8n";
    };

    encryptionKey = lib.mkOption {
      type = lib.types.str;
      default = "n8n-encryption-key";
      description = "Value for N8N_ENCRYPTION_KEY";
    };

    basicAuthPassword = lib.mkOption {
      type = lib.types.str;
      default = "n8n-basic-auth-password";
      description = "Password for n8n basic auth";
    };

    basePath = lib.mkOption {
      type = lib.types.str;
      default = "/n8n";
      description = "Base path served via nginx";
    };
  };

  config = lib.mkIf cfg.enable {
    services.postgresql.ensureDatabases = lib.mkAfter [ "n8n" ];
    services.postgresql.ensureUsers = lib.mkAfter [ { name = "n8n"; ensureDBOwnership = true; } ];
    services.postgresql.initialScript = lib.mkAfter ''
      SELECT format('CREATE ROLE %I LOGIN', 'n8n')
      WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'n8n')
      \gexec

      SELECT format('CREATE DATABASE %I OWNER %I', 'n8n', 'n8n')
      WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = 'n8n')
      \gexec

      GRANT ALL PRIVILEGES ON DATABASE n8n TO n8n;
      ALTER USER n8n WITH PASSWORD '${cfg.dbPassword}';
    '';
    systemd.services.postgresql.postStart = lib.mkAfter ''
      ${pkgs.postgresql}/bin/psql -U postgres -c "ALTER USER n8n PASSWORD '${cfg.dbPassword}';" || true
    '';

    systemd.services.n8n = {
      description = "n8n automation (Docker)";
      wantedBy = [ "multi-user.target" ];
      after = [ "docker.service" "postgresql.service" ];
      requires = [ "docker.service" "postgresql.service" ];
      serviceConfig = {
        Type = "simple";
        Restart = "always";
        RestartSec = 10;
        ExecStartPre = [
          "${pkgs.bash}/bin/bash -c '${pkgs.docker}/bin/docker rm -f n8n || true'"
          "${pkgs.docker}/bin/docker pull ${cfg.dockerImage}"
          "${pkgs.bash}/bin/bash -c '${pkgs.docker}/bin/docker volume create n8n-data || true'"
        ];
        ExecStart = pkgs.writeShellScript "n8n-start" ''
          exec ${pkgs.docker}/bin/docker run \
            --name n8n \
            --rm \
            -p 127.0.0.1:${toString cfg.hostPort}:5678 \
            -v n8n-data:/home/node/.n8n \
            -e DB_TYPE=postgresdb \
            -e DB_POSTGRESDB_HOST=172.17.0.1 \
            -e DB_POSTGRESDB_PORT=5432 \
            -e DB_POSTGRESDB_DATABASE=n8n \
            -e DB_POSTGRESDB_USER=n8n \
            -e DB_POSTGRESDB_PASSWORD=${cfg.dbPassword} \
            -e N8N_ENCRYPTION_KEY=${cfg.encryptionKey} \
            -e WEBHOOK_URL=${cfg.publicUrl} \
            -e N8N_HOST=localhost \
            -e N8N_PORT=5678 \
            -e N8N_PROTOCOL=https \
            -e N8N_BASE_PATH=${cfg.basePath} \
            -e N8N_EDITOR_BASE_URL=${cfg.publicUrl} \
            -e EXECUTIONS_DATA_SAVE_ON_ERROR=all \
            -e EXECUTIONS_DATA_SAVE_ON_SUCCESS=none \
            -e EXECUTIONS_DATA_PRUNE=true \
            -e N8N_BASIC_AUTH_ACTIVE=true \
            -e N8N_BASIC_AUTH_USER=admin \
            -e N8N_BASIC_AUTH_PASSWORD=${cfg.basicAuthPassword} \
            ${cfg.dockerImage}
        '';
        ExecStop = "${pkgs.docker}/bin/docker stop n8n";
      };
    };

    services.nginx.virtualHosts."localhost".locations.${normalizedPath} = {
      proxyPass = "http://127.0.0.1:${toString cfg.hostPort}";
      proxyWebsockets = true;
      extraConfig = ''
        proxy_set_header Host "$host:$rave_forwarded_port";
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-Port $rave_forwarded_port;
        proxy_set_header X-Forwarded-Host "$host:$rave_forwarded_port";
        proxy_set_header X-Forwarded-Prefix ${normalizedPath};
        proxy_set_header X-Forwarded-Ssl on;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $connection_upgrade;
        client_max_body_size 100M;
        proxy_redirect off;
      '';
    };

    services.nginx.virtualHosts."localhost".locations.${redirectPath} = {
      return = "302 ${normalizedPath}";
    };
  };
}
