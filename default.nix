{ pkgs ? import <nixpkgs> {} }:

{
  vibe-kanban = pkgs.callPackage ./vibe-kanban.nix {};
}