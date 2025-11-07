{ config, lib, pkgs, ... }:

let
  cfg = config.services.rave.outline;

  outlineBasePath =
    let
      match = builtins.match "https?://[^/]+(/.*)" cfg.publicUrl;
    in
    if cfg.publicUrl == "" then "/outline" else
    if match == null || match == [] then "/outline" else builtins.head match;

  basePathWithSlash =
    let normalized = if lib.hasSuffix "/" outlineBasePath then outlineBasePath else "${outlineBasePath}/";
    in normalized;
  basePathNoSlash =
    let trimmed = lib.removeSuffix "/" basePathWithSlash;
    in if trimmed == "" then "/" else trimmed;
in
{
  options.services.rave.outline = {
    enable = lib.mkEnableOption "Outline wiki service";

    publicUrl = lib.mkOption {
      type = lib.types.str;
      default = "https://localhost:8443/outline";
      description = "External URL (including base path) for Outline.";
    };

    dockerImage = lib.mkOption {
      type = lib.types.str;
      default = "outlinewiki/outline:latest";
      description = "Container image to run for Outline.";
    };

    hostPort = lib.mkOption {
      type = lib.types.int;
      default = 8310;
      description = "Loopback port exposed by the Outline container.";
    };

    dbPassword = lib.mkOption {
      type = lib.types.str;
      default = "outline-production-password";
      description = "Database password for the Outline PostgreSQL user.";
    };

    secretKey = lib.mkOption {
      type = lib.types.str;
      default = "outline-secret-key";
      description = "Outline SECRET_KEY value.";
    };

    utilsSecret = lib.mkOption {
      type = lib.types.str;
      default = "outline-utils-secret";
      description = "Outline UTILS_SECRET value.";
    };

    redisDb = lib.mkOption {
      type = lib.types.int;
      default = 5;
      description = "Redis database number used by Outline.";
    };
  };

  config = lib.mkIf cfg.enable {
    services.postgresql.ensureDatabases = lib.mkAfter [ "outline" ];
    services.postgresql.ensureUsers = lib.mkAfter [
      { name = "outline"; ensureDBOwnership = true; }
    ];
    services.postgresql.initialScript = lib.mkAfter ''
      SELECT format('CREATE ROLE %I LOGIN', 'outline')
      WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'outline')
      \gexec

      SELECT format('CREATE DATABASE %I OWNER %I', 'outline', 'outline')
      WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = 'outline')
      \gexec

      -- Outline wiki database setup
      GRANT ALL PRIVILEGES ON DATABASE outline TO outline;
      ALTER USER outline WITH PASSWORD '${cfg.dbPassword}';
    '';
    systemd.services.postgresql.postStart = lib.mkAfter ''
      ${pkgs.postgresql}/bin/psql -U postgres -c "ALTER USER outline PASSWORD '${cfg.dbPassword}';" || true
    '';

    systemd.services.outline = {
      description = "Outline wiki (Docker)";
      after = [ "docker.service" "postgresql.service" "redis-main.service" ];
      requires = [ "docker.service" "postgresql.service" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "simple";
        Restart = "on-failure";
        RestartSec = 5;
        ExecStartPre = [
          "${pkgs.bash}/bin/bash -c '${pkgs.docker}/bin/docker rm -f outline || true'"
          "${pkgs.docker}/bin/docker pull ${cfg.dockerImage}"
          "${pkgs.bash}/bin/bash -c '${pkgs.docker}/bin/docker volume create outline-data || true'"
        ];
        ExecStart = pkgs.writeShellScript "outline-start" ''
          exec ${pkgs.docker}/bin/docker run \
            --rm \
            --name outline \
            -p 127.0.0.1:${toString cfg.hostPort}:3000 \
            -v outline-data:/var/lib/outline/data \
            -e URL=${cfg.publicUrl} \
            -e PORT=3000 \
            -e SECRET_KEY=${cfg.secretKey} \
            -e UTILS_SECRET=${cfg.utilsSecret} \
            -e DATABASE_URL=postgresql://outline:${cfg.dbPassword}@172.17.0.1:5432/outline \
            -e PGSSLMODE=disable \
            -e REDIS_URL=redis://172.17.0.1:6379/${toString cfg.redisDb} \
            -e FILE_STORAGE=local \
            -e FILE_STORAGE_LOCAL_ROOT_DIR=/var/lib/outline/data \
            -e FILE_STORAGE_LOCAL_SERVER_ROOT=${cfg.publicUrl}/uploads \
            ${cfg.dockerImage}
        '';
        ExecStop = "${pkgs.docker}/bin/docker stop outline";
      };
    };

    services.nginx.virtualHosts."localhost".locations = {
      "${basePathWithSlash}" = {
        proxyPass = "http://127.0.0.1:${toString cfg.hostPort}/";
        extraConfig = ''
          proxy_set_header Host $host;
          proxy_set_header X-Real-IP $remote_addr;
          proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
          proxy_set_header X-Forwarded-Proto $scheme;
          proxy_set_header X-Forwarded-Port $rave_forwarded_port;
          proxy_set_header X-Forwarded-Host "$host:$rave_forwarded_port";
          proxy_set_header X-Forwarded-Prefix ${basePathWithSlash};
          proxy_set_header X-Forwarded-Ssl on;
          proxy_set_header Upgrade $http_upgrade;
          proxy_set_header Connection $connection_upgrade;
          client_max_body_size 100M;
          proxy_redirect off;
        '';
      };

      "${basePathNoSlash}" = {
        return = "302 ${basePathWithSlash}";
      };
    };
  };
}
