{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.rave.postgresql;
  initialScriptFile =
    if cfg.initialSql == ""
    then null
    else pkgs.writeText "postgres-init.sql" cfg.initialSql;

  userSubmodule = types.submodule ({ name, ... }: {
    options = {
      name = mkOption {
        type = types.str;
        default = name;
        description = "PostgreSQL role/user name.";
      };
      ensureDBOwnership = mkOption {
        type = types.bool;
        default = false;
        description = "Whether this role owns a database with the same name.";
      };
    };
  });

in
{
  options.services.rave.postgresql = {
    enable = mkEnableOption "PostgreSQL cluster for the RAVE stack";

    package = mkOption {
      type = types.package;
      default = pkgs.postgresql_15;
      description = "PostgreSQL package to use.";
    };

    listenAddresses = mkOption {
      type = types.str;
      default = "localhost";
      description = "Comma-separated list of addresses PostgreSQL listens on.";
    };

    ensureDatabases = mkOption {
      type = types.listOf types.str;
      default = [];
      description = "Databases to pre-create.";
    };

    ensureUsers = mkOption {
      type = types.listOf userSubmodule;
      default = [];
      description = "Roles/users to ensure exist.";
    };

    settings = mkOption {
      type = types.attrs;
      default = {};
      description = "Extra PostgreSQL settings merged into the configuration.";
    };

    initialSql = mkOption {
      type = types.lines;
      default = "";
      description = "SQL script executed at initial cluster creation.";
    };

    postStartSql = mkOption {
      type = types.listOf types.str;
      default = [];
      description = ''SQL statements executed after PostgreSQL starts (each entry is passed to `psql -U postgres -c`).'';
    };
  };

  config = mkIf cfg.enable {
    services.postgresql =
      {
        enable = mkForce true;
        package = cfg.package;
        ensureDatabases = cfg.ensureDatabases;
        ensureUsers = cfg.ensureUsers;
        settings = cfg.settings // {
          listen_addresses = mkForce cfg.listenAddresses;
        };
      }
      // optionalAttrs (initialScriptFile != null) {
        initialScript = initialScriptFile;
      };

    systemd.services.postgresql.postStart = mkIf (cfg.postStartSql != []) ''
      while ! ${cfg.package}/bin/pg_isready -d postgres > /dev/null 2>&1; do
        sleep 1
      done

      ${concatMapStrings (stmt: ''
        ${cfg.package}/bin/psql -U postgres -c ${lib.escapeShellArg stmt} || true
      '') cfg.postStartSql}
    '';
  };
}
