{ lib, ... }:
{
  options.services.rave.ports = {
    https = lib.mkOption {
      type = lib.types.int;
      default = 8443;
      description = "HTTPS port for the RAVE VM services";
    };
  };
}
