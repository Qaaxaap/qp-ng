# QP-ng

QP-ng is a package manager forked from [paru](https://github.com/Morganamilo/paru).
It works on Arch Linux, Linux From Scratch, and any distribution where pacman
is available — as long as the target paths are on a writable filesystem.

> **A package manager that exists for you.**
> We respect your right to control your own system. QP-ng does not dictate how
> you manage packages — it adapts to your choices.

## Features

QP-ng keeps all of paru's AUR helper functionality. Your existing `paru.conf`
is fully compatible — rename to `qp.conf` and you're done. On top of that:

- **Manual package registration** — Mark packages as installed or uninstalled
  outside of pacman (LFS builds, pip modules). Pacman sees them, dependency
  resolution works, and upgrades are blocked via `IgnorePkg`. Uninstalled
  packages use `AssumeInstalled` so they won't be pulled back as dependencies.
  Supports `--mark-provides`, `--mark-depends`, and `--auto-provides` for
  automatic shared library detection.

- **Overlay PKGBUILD repos with priorities** — Configure multiple repos
  (remote git or local paths) with numeric priority. When the same package
  exists in multiple sources, QP-ng resolves by priority or prompts
  interactively. Overlays can optionally override official repo packages.

- **Source-first official packages** — Enable `BuildOfficialFromSource` in
  `qp.conf` to build official Arch packages from GitLab PKGBUILDs instead of
  downloading binaries. Useful for customization, auditing, or non-x86_64.

- **The [qur](https://github.com/Qaaxaap/qur) overlay** — A curated PKGBUILD
  repository for LFS compatibility patches and compile-time optimizations.
  **Currently in planning stage** — the repository still contains legacy
  qp (pre-ng) code and is not yet functional with QP-ng.

- **LFS bootstrap** — Designed to bootstrap on a bare LFS 13.0 system. See
  `scripts/install-lfs.sh` for the full from-source chain.

## Installation

### Arch Linux

QP-ng is not yet on the AUR due to [ongoing supply-chain concerns](https://archlinux.org/news/aur-security-incident/).
Build from source:

```bash
sudo pacman -S --needed base-devel git rustup
rustup default stable
git clone https://github.com/Qaaxaap/qp-ng.git
cd qp-ng
makepkg -si
```

### Linux From Scratch (13.0 systemd)

```bash
git clone https://github.com/Qaaxaap/qp-ng.git
cd qp-ng

# Fast path: official Rust binary (~30 min)
sudo ./scripts/install-lfs.sh --quick

# Full from-source: bootstrap rustc via mrustc (~5-9 hours, no binaries)
sudo ./scripts/install-lfs.sh

# Register all LFS Chapter 8 packages in pacman
sudo ./scripts/register-lfs.sh
```

### Other distributions

If you have pacman but no AUR access, QP-ng still works for local packages,
overlay repos, and manual management. Build with:

```bash
cargo build --release
sudo install -Dm755 target/release/qp /usr/bin/qp
```

`libalpm >= 16.0` is required at build time. On distributions that don't
package libalpm (Ubuntu, Debian, Fedora, etc.), you'll need to build
[pacman](https://gitlab.archlinux.org/pacman/pacman) from source first —
this provides both `libalpm` and `pacman` itself.

## Quick start

```bash
# Register a package so pacman knows about it
qp --mark-installed glibc 2.43

# With shared library provides (critical for dependency resolution)
qp --mark-installed --mark-provides 'libssl.so.3,libcrypto.so.3' openssl 3.6.1

# With explicit dependencies
qp --mark-installed --mark-depends 'glibc,gcc-libs' mypkg 1.0

# Auto-detect .so provides from installed files
qp --mark-installed --auto-provides ncurses 6.6

# Prevent a package from being re-installed as a dependency
qp --mark-uninstalled pulseaudio

# List all manually-tracked packages
qp --list-manual
```

## Configuration

Edit `/etc/qp.conf` or `~/.config/qp/qp.conf`:

```ini
[options]
# Build official packages from source instead of downloading binaries
BuildOfficialFromSource

[my-overlay]
Url = https://github.com/user/pkgbuilds.git
Priority = 1
# Allow this overlay to override official repo packages
OverrideOfficial

[local-dev]
Path = /home/user/my-pkgbuilds
Priority = 2

[qur]
Url = https://github.com/Qaaxaap/qur.git
Priority = 3
```

## Qur overlay

Qur is a planned curated PKGBUILD repository providing LFS compatibility
patches and compile-time optimizations (LTO, x86-64-v3, etc.):

```ini
[qur]
Url = https://github.com/Qaaxaap/qur.git
Priority = 3
```

> **Note: qur is currently in the planning stage.** The repository still
> contains legacy qp (pre-ng) code and is not yet functional with QP-ng.
> Follow the repo for updates or jump in and contribute.

## Examples

### General usage (inherited from paru)

```bash
qp                   # alias for qp -Syu
qp <target>          # interactive search and install
qp -S <target>       # install a specific package
qp -Sua              # upgrade AUR packages only
qp -Qua              # print available AUR updates
qp -G <target>       # download PKGBUILD and related files
qp -Gp <target>      # print the PKGBUILD of a package
qp -Gc <target>      # print AUR comments for a package
qp -Bi .             # build and install a PKGBUILD in the current directory
qp --gendb           # generate devel database for tracking -git packages
```

### QP-ng specific

```bash
# Manual package management
qp --mark-installed glibc 2.43
qp --mark-installed --auto-provides ncurses 6.6
qp --mark-installed --mark-depends 'glibc,gcc-libs' mypkg 1.0
qp --mark-uninstalled pulseaudio
qp --list-manual

# Overlay repositories
qp -Ly                           # refresh and list overlay repos
qp -S --pkgbuilds mypkg          # install from overlay only (skip AUR)
qp -S somepkg                    # resolved by overlay priority automatically

# Build official packages from source (when BuildOfficialFromSource is enabled)
qp -S glibc                      # clones PKGBUILD from GitLab, builds, installs
```

## General Tips

- **Man pages**: `qp(8)` and `qp.conf(5)`.
- **Color**: QP-ng only enables color if `Color` is enabled in `pacman.conf`.
- **File-based review**: Enable `FileManager` in `qp.conf` for interactive
  PKGBUILD review with your file manager of choice.
- **Flip search order**: Enable `BottomUp` in `qp.conf` to show results
  starting from the bottom.
- **Editing PKGBUILDs**: Commit your changes to make them permanent. When the
  package is upgraded, `git` will attempt to merge your changes with upstream.
- **PKGBUILD syntax highlighting**: Install [`bat`](https://github.com/sharkdp/bat).
- **Tracking -git packages**: Run `qp --gendb` after initial setup to make
  QP-ng aware of packages it didn't install itself.

## Debugging

QP-ng is not an official Arch tool. If it can't build a package, first check
whether `makepkg` can build it successfully. If makepkg also fails, report
the issue to the package maintainer. Otherwise, report it
[here](https://github.com/Qaaxaap/qp-ng/issues).

## FAQ

**Why migrate from paru to QP-ng?**

If you want more flexible package management — registering hand-installed
packages, configuring overlay repos with priorities, building official
packages from source — QP-ng gives you those tools while keeping all of
paru's AUR functionality. It also works outside Arch Linux.

**Why use a package manager on LFS?**

LFS teaches you how a Linux system is built from scratch, which deserves
respect. But maintaining thousands of packages by hand isn't practical for
daily use. QP-ng is an attempt to bridge that gap — add pacman-based package
management to your LFS system without sacrificing the control and transparency
that drew you to LFS in the first place.

## Contributing

See [CONTRIBUTING.md](./CONTRIBUTING.md).

---

*Your system, your rules.*
**A package manager that exists for you.**
