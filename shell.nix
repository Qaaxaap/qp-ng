{ pkgs ? import <nixpkgs> {} }:

(pkgs.buildFHSEnv {
  name = "qp-ng-dev";
  targetPkgs = pkgs: with pkgs; [
    pacman
    fakeroot
    rustc
  ];
  runScript = "bash";
}).env
