{ config, lib, ... }:

with lib;

let
  cfg = config.services.rave.redis;
  instanceName = cfg.instanceName;
  redisUnit = "redis-${instanceName}.service";

in
{
  options.services.rave.redis = {
    enable = mkEnableOption "Redis server configuration";

    instanceName = mkOption {
      type = types.str;
      default = "main";
      description = "Attribute name under services.redis.servers.";
    };

    port = mkOption {
      type = types.int;
      default = 6379;
      description = "Redis listening port.";
    };

    bind = mkOption {
      type = types.str;
      default = "127.0.0.1";
      description = "Bind address for Redis.";
    };

    clientHost = mkOption {
      type = types.str;
      default = "127.0.0.1";
      description = "Hostname or IP local services should use to reach Redis.";
    };

    dockerHost = mkOption {
      type = types.str;
      default = "host.docker.internal";
      description = "Hostname or IP that Docker containers should use when connecting to Redis.";
    };

    databases = mkOption {
      type = types.int;
      default = 16;
      description = "Number of logical Redis databases.";
    };

    allocations = mkOption {
      type = types.attrsOf types.int;
      default = {
        gitlab = 0;
        outline = 5;
        penpot = 10;
      };
      description = ''Map of service identifiers to reserved Redis database indexes (used by Penpot, Outline, GitLab, etc.).'';
      example = { gitlab = 0; penpot = 10; outline = 20; };
    };

    maxMemory = mkOption {
      type = types.str;
      default = "512MB";
      description = "Value for maxmemory setting.";
    };

    maxMemoryPolicy = mkOption {
      type = types.str;
      default = "noeviction";
      description = "Redis maxmemory-policy.";
    };

    save = mkOption {
      type = types.listOf types.str;
      default = [ "900 1" "300 10" "60 10000" ];
      description = "RDB save directives.";
    };

    extraSettings = mkOption {
      type = types.attrs;
      default = {};
      description = "Additional Redis settings merged into the generated configuration.";
    };
  };

  config = {
    services.rave.redis.platform = {
      unit = redisUnit;
      port = cfg.port;
      host = cfg.clientHost;
      dockerHost = cfg.dockerHost;
      allocations = cfg.allocations;
    };
  } // mkIf cfg.enable {
    services.redis.servers = {
      "${instanceName}" = {
        enable = true;
        port = cfg.port;
        settings = {
          bind = mkForce cfg.bind;
          maxmemory = cfg.maxMemory;
          maxmemory-policy = cfg.maxMemoryPolicy;
          save = cfg.save;
          databases = cfg.databases;
        } // cfg.extraSettings;
      };
    };
  };
}
