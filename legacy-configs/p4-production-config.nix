# Legacy P4 configuration placeholder
# The original Matrix/Element integration has been deprecated in favour of
# Mattermost-based chat control. This stub keeps the file for compatibility and
# delegates to the P3 configuration.
{ ... }:
{
  imports = [ ./p3-production-config.nix ];
}
