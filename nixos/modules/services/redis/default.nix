{ config, lib, ... }:

with lib;

let
  cfg = config.services.rave.redis;
  instanceName = cfg.instanceName;

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

    databases = mkOption {
      type = types.int;
      default = 16;
      description = "Number of logical Redis databases.";
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

  config = mkIf cfg.enable {
    services.redis.servers = {
      "${instanceName}" = {
        enable = true;
        port = cfg.port;
        settings = {
          bind = cfg.bind;
          maxmemory = cfg.maxMemory;
          maxmemory-policy = cfg.maxMemoryPolicy;
          save = cfg.save;
          databases = cfg.databases;
        } // cfg.extraSettings;
      };
    };
  };
}
