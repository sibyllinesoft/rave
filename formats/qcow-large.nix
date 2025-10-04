# Custom qcow format with 20GB disk size
{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [
    "${toString modulesPath}/../lib/make-disk-image.nix"
  ];

  system.build.diskImage = lib.mkForce (pkgs.vmTools.runInLinuxVM (
    pkgs.runCommand "nixos-disk-image" {
      memSize = 2048;
      QEMU_OPTS = "-drive file=${pkgs.lib.makeBinPath [ pkgs.e2fsprogs ]}/e2fsck,format=raw,if=virtio";
    } ''
      ${pkgs.diskrsync}/bin/diskrsync --size=20G ${config.system.build.toplevel} $out/nixos.qcow2
      ${pkgs.qemu}/bin/qemu-img convert -f raw -O qcow2 $out/nixos.raw $out/nixos.qcow2
      rm $out/nixos.raw
    ''
  ));

  formatAttr = "diskImage";
}