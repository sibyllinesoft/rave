{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.rave.outline;
  nginxVhost = config.services.rave.nginx.host;
  redisPlatform = config.services.rave.redis.platform or {};
  sharedAllocations = redisPlatform.allocations or {};
  sharedRedisHost = redisPlatform.dockerHost or "172.17.0.1";
  sharedRedisPort = redisPlatform.port or 6379;
  sharedRedisUnit = redisPlatform.unit or "redis-main.service";
  redisDatabase = if cfg.redisDb != null then cfg.redisDb else sharedAllocations.outline or 5;
  redisUrl = "redis://${sharedRedisHost}:${toString sharedRedisPort}/${toString redisDatabase}";
  trimNewline = "${pkgs.coreutils}/bin/tr -d '\\n'";

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

    dbPasswordFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Path to a file containing the Outline database password.";
    };

    secretKey = lib.mkOption {
      type = lib.types.str;
      default = "outline-secret-key";
      description = "Outline SECRET_KEY value.";
    };

    secretKeyFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Path to a file containing Outline's SECRET_KEY.";
    };

    utilsSecret = lib.mkOption {
      type = lib.types.str;
      default = "outline-utils-secret";
      description = "Outline UTILS_SECRET value.";
    };

    utilsSecretFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Path to a file containing Outline's UTILS_SECRET.";
    };

    redisDb = lib.mkOption {
      type = lib.types.nullOr lib.types.int;
      default = null;
      description = "Redis database number used by Outline (defaults to services.rave.redis.allocations.outline).";
    };
  };

  config = lib.mkIf cfg.enable {
    services.postgresql.ensureDatabases = lib.mkAfter [ "outline" ];
    services.postgresql.ensureUsers = lib.mkAfter [
      { name = "outline"; ensureDBOwnership = true; }
    ];
    systemd.services.postgresql.postStart = lib.mkAfter ''
      ${pkgs.postgresql}/bin/psql -U postgres -c "ALTER USER outline PASSWORD '${cfg.dbPassword}';" || true
    '';

    systemd.services.outline = {
      description = "Outline wiki (Docker)";
      after = [ "docker.service" "postgresql.service" sharedRedisUnit ];
      requires = [ "docker.service" "postgresql.service" sharedRedisUnit ];
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
          set -euo pipefail
${optionalString (cfg.dbPasswordFile != null) ''
          if [ -s ${cfg.dbPasswordFile} ]; then
            DB_PASSWORD="$(${pkgs.coreutils}/bin/cat ${cfg.dbPasswordFile} | ${trimNewline})"
          else
            DB_PASSWORD=${lib.escapeShellArg cfg.dbPassword}
          fi
''}${optionalString (cfg.dbPasswordFile == null) ''
          DB_PASSWORD=${lib.escapeShellArg cfg.dbPassword}
''}
${optionalString (cfg.secretKeyFile != null) ''
          if [ -s ${cfg.secretKeyFile} ]; then
            SECRET_KEY="$(${pkgs.coreutils}/bin/cat ${cfg.secretKeyFile} | ${trimNewline})"
          else
            SECRET_KEY=${lib.escapeShellArg cfg.secretKey}
          fi
''}${optionalString (cfg.secretKeyFile == null) ''
          SECRET_KEY=${lib.escapeShellArg cfg.secretKey}
''}
${optionalString (cfg.utilsSecretFile != null) ''
          if [ -s ${cfg.utilsSecretFile} ]; then
            UTILS_SECRET="$(${pkgs.coreutils}/bin/cat ${cfg.utilsSecretFile} | ${trimNewline})"
          else
            UTILS_SECRET=${lib.escapeShellArg cfg.utilsSecret}
          fi
''}${optionalString (cfg.utilsSecretFile == null) ''
          UTILS_SECRET=${lib.escapeShellArg cfg.utilsSecret}
''}

          exec ${pkgs.docker}/bin/docker run \
            --rm \
            --name outline \
            -p 127.0.0.1:${toString cfg.hostPort}:3000 \
            -v outline-data:/var/lib/outline/data \
            -e URL=${cfg.publicUrl} \
            -e PORT=3000 \
            -e SECRET_KEY="$SECRET_KEY" \
            -e UTILS_SECRET="$UTILS_SECRET" \
            -e DATABASE_URL="postgresql://outline:''${DB_PASSWORD}@172.17.0.1:5432/outline" \
            -e PGSSLMODE=disable \
            -e REDIS_URL=${redisUrl} \
            -e FILE_STORAGE=local \
            -e FILE_STORAGE_LOCAL_ROOT_DIR=/var/lib/outline/data \
            -e FILE_STORAGE_LOCAL_SERVER_ROOT=${cfg.publicUrl}/uploads \
            ${cfg.dockerImage}
        '';
        ExecStop = "${pkgs.docker}/bin/docker stop outline";
      };
    };

    services.nginx.virtualHosts."${nginxVhost}".locations = {
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
