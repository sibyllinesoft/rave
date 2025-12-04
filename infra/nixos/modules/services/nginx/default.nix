{ lib, ... }:

{
  options.services.rave.nginx = {
    enable = lib.mkEnableOption "Legacy nginx front door (deprecated; unused when Traefik is enabled)";
  };

  # No configuration emitted; keeping the option only for compatibility.
  config = {};
}
