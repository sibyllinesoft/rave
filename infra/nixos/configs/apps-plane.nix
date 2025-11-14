{ lib, ... }:
let
  dataHostEnv = builtins.getEnv "RAVE_DATA_HOST";
  dataHost = if dataHostEnv == "" then "rave-data-plane.local" else dataHostEnv;
  parsePort = envVar: default:
    let
      raw = builtins.getEnv envVar;
    in if raw == "" then default else
      let parsed = builtins.tryEval (builtins.fromJSON raw);
      in if parsed.success && builtins.isInt parsed.value then parsed.value else default;
  redisPort = parsePort "RAVE_DATA_REDIS_PORT" 6379;
  pgPort = parsePort "RAVE_DATA_PG_PORT" 5432;
in {
  imports = [ ./production.nix ];

  config = {
    services.rave.postgresql.enable = lib.mkForce false;
    services.postgresql.enable = lib.mkForce false;

    services.rave.redis = {
      enable = lib.mkForce false;
      clientHost = lib.mkForce dataHost;
      dockerHost = lib.mkForce dataHost;
      port = lib.mkForce redisPort;
    };

    services.gitlab = {
      # GitLab talks to the external data plane over the default PostgreSQL port;
      # host-only override keeps the remote endpoint configurable without
      # touching the upstream module options (which no longer expose databasePort).
      databaseHost = lib.mkForce dataHost;
    };

    services.rave.mattermost.databaseDatasource = lib.mkForce "postgres://mattermost:mmpgsecret@${dataHost}:${toString pgPort}/mattermost?sslmode=disable&connect_timeout=10";

    services.rave.outline = {
      dbHost = lib.mkForce dataHost;
      dbPort = lib.mkForce pgPort;
    };
    services.rave.n8n = {
      dbHost = lib.mkForce dataHost;
      dbPort = lib.mkForce pgPort;
    };

    services.rave.penpot = {
      database = {
        host = lib.mkForce dataHost;
        port = lib.mkForce pgPort;
      };
      redis = {
        host = lib.mkForce dataHost;
        port = lib.mkForce redisPort;
      };
    };

    services.rave.monitoring.grafana.database.host = lib.mkForce "${dataHost}:${toString pgPort}";
  };
}
