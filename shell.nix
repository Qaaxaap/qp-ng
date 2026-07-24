{ pkgs ? import <nixpkgs> { } }:

pkgs.mkShell {
  buildInputs = with pkgs; [
    pkgconf
    openssl
    curl
    gcc
    gpgme
    libarchive
    pacman
  ];

  PKG_CONFIG = "${pkgs.pkgconf}/bin/pkgconf";

  shellHook = ''
    export PKG_CONFIG_PATH="/home/Qaaxaap/local/pacman/lib/pkgconfig:$PKG_CONFIG_PATH"
    export PKG_CONFIG_PATH_x86_64_unknown_linux_gnu="/home/Qaaxaap/local/pacman/lib/pkgconfig:$PKG_CONFIG_PATH_x86_64_unknown_linux_gnu"
    export LD_LIBRARY_PATH="/home/Qaaxaap/local/pacman/lib:$LD_LIBRARY_PATH"
  '';
}
