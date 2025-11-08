{ config, lib, ... }:

with lib;

let
  cfg = config.services.rave.coturn;
  deniedBlock = concatStringsSep "\n" (map (ip: "      denied-peer-ip=${ip}") cfg.deniedIpCidrs);

in
{
  options.services.rave.coturn = {
    enable = mkEnableOption "Coturn STUN/TURN server";

    realm = mkOption {
      type = types.str;
      default = "localhost";
      description = "TURN realm presented to clients.";
    };

    staticAuthSecret = mkOption {
      type = types.str;
      default = "change-me-turn-secret";
      description = "Shared authentication secret for TURN credentials.";
    };

    listeningIps = mkOption {
      type = types.listOf types.str;
      default = [ "0.0.0.0" ];
      description = "Addresses Coturn listens on.";
    };

    minPort = mkOption {
      type = types.int;
      default = 49152;
      description = "Lower bound for relay port range.";
    };

    maxPort = mkOption {
      type = types.int;
      default = 65535;
      description = "Upper bound for relay port range.";
    };

    verbose = mkOption {
      type = types.bool;
      default = true;
      description = "Enable verbose logging.";
    };

    deniedIpCidrs = mkOption {
      type = types.listOf types.str;
      default = [
        "0.0.0.0-0.255.255.255"
        "10.0.0.0-10.255.255.255"
        "100.64.0.0-100.127.255.255"
        "127.0.0.0-127.255.255.255"
        "169.254.0.0-169.254.255.255"
        "172.16.0.0-172.31.255.255"
        "192.0.0.0-192.0.0.255"
        "192.0.2.0-192.0.2.255"
        "192.88.99.0-192.88.99.255"
        "192.168.0.0-192.168.255.255"
        "198.18.0.0-198.19.255.255"
        "198.51.100.0-198.51.100.255"
        "203.0.113.0-203.0.113.255"
        "240.0.0.0-255.255.255.255"
        "::1"
        "64:ff9b::-64:ff9b::ffff:ffff"
        "::ffff:0.0.0.0-::ffff:255.255.255.255"
        "2001::-2001:1ff:ffff:ffff:ffff:ffff:ffff:ffff"
        "2002::-2002:ffff:ffff:ffff:ffff:ffff:ffff:ffff"
        "fc00::-fdff:ffff:ffff:ffff:ffff:ffff:ffff:ffff"
        "fe80::-febf:ffff:ffff:ffff:ffff:ffff:ffff:ffff"
      ];
      description = "IP ranges Coturn refuses to relay.";
    };

    extraConfig = mkOption {
      type = types.lines;
      default = "";
      description = "Additional raw Coturn directives appended to the generated config.";
    };
  };

  config = mkIf cfg.enable {
    services.coturn = {
      enable = true;
      no-cli = true;
      no-tcp-relay = true;
      min-port = cfg.minPort;
      max-port = cfg.maxPort;
      use-auth-secret = true;
      static-auth-secret = cfg.staticAuthSecret;
      realm = cfg.realm;
      listening-ips = cfg.listeningIps;
      extraConfig = ''
        ${optionalString cfg.verbose "      verbose"}
        fingerprint
        lt-cred-mech
        ${deniedBlock}
        ${cfg.extraConfig}
      '';
    };
  };
}
