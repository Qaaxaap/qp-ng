# QP-ng

QP-ng is a package manager forked from [paru](https://github.com/Morganamilo/paru).
It works on Arch Linux, Linux From Scratch, and any distribution where pacman
is available — as long as the target paths are on a writable filesystem.

> **A package manager that exists for you.**
> We respect your right to control your own system. QP-ng does not dictate how you manage
> packages — it adapts to your choices, whether you build from source, install binaries,
> or manage packages by hand.

## Features

QP-ng retains all of paru's AUR helper functionality — you can use it on Arch Linux and
migrate from paru seamlessly. Your existing paru configuration files (`paru.conf`) are
fully compatible — simply rename to `qp.conf`. On top of that, it adds:

- **Manual package registration (`--mark-installed` / `--mark-uninstalled`)**
  Register packages you installed outside of pacman (e.g. LFS-built packages, pip-installed
  Python modules) directly into pacman's local database. Pacman sees them as installed,
  dependency resolution works, and upgrades are blocked via `IgnorePkg`.
  Uninstalled packages are held back via `AssumeInstalled` so they won't be pulled in
  as dependencies.

- **Overlay PKGBUILD repositories with priorities**
  Configure multiple PKGBUILD repositories (remote git or local paths) with configurable
  priority. When the same package exists in multiple overlays or conflicts with official
  repos, QP-ng resolves by priority or prompts interactively.

- **Source-first official packages (`BuildOfficialFromSource`)**
  Build official Arch packages from source (via `pkgctl repo clone` from GitLab) instead
  of downloading binaries. Useful for customization, auditing, or non-x86_64 architectures.

- **The [qur](https://github.com/Qaaxaap/qur) overlay**
  A curated PKGBUILD repository maintained alongside QP-ng, focused on LFS compatibility
  patches and compile-time optimizations.

- **Works on LFS**
  QP-ng is designed to bootstrap on a bare LFS 13.0 system. See `scripts/install-lfs.sh`
  for the full from-source bootstrap chain (curl → gpgme → libarchive → pacman →
  rustc → qp-ng).

## Installation

### Arch Linux

QP-ng is not yet available on the AUR due to [ongoing supply-chain concerns](https://archlinux.org/news/aur-security-incident/).
Build it from source for now:

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

# Fast path: download official Rust binary (~30 min)
sudo ./scripts/install-lfs.sh --quick

# Full from-source path: bootstrap rustc via mrustc (~5-9 hours, no binaries)
sudo ./scripts/install-lfs.sh

# Register all LFS Chapter 8 packages in pacman
sudo ./scripts/register-lfs.sh
```

Use `--help` on each script to see options. The full bootstrap builds ~8 dependencies
from source (curl, gpgme, libarchive, pacman, rustc, ...) before building QP-ng itself.

### Other distributions

If you have pacman installed but no AUR access, QP-ng can still manage local packages,
overlay repos, and manually-installed software. Build with:

```bash
cargo build --release
sudo install -Dm755 target/release/qp /usr/bin/qp
```

`libalpm >= 16.0` is required at build time.

## Quick start after installation

```bash
# Register an LFS-built package so pacman knows about it
qp --mark-installed glibc 2.43

# Register with shared library provides (critical for dependency resolution)
qp --mark-installed --mark-provides 'libssl.so.3,libcrypto.so.3' openssl 3.6.1

# Auto-detect .so provides from installed files
qp --mark-installed --auto-provides ncurses 6.6

# Register with explicit dependencies
qp --mark-installed --mark-depends 'glibc,gcc-libs' mypkg 1.0

# Prevent a package from being re-installed as a dependency
qp --mark-uninstalled pulseaudio

# List all manually-tracked packages
qp --list-manual
```

## Configuration

Edit `/etc/qp.conf` or `~/.config/qp/qp.conf`:

```ini
[options]
# Build official packages from source instead of binaries
BuildOfficialFromSource

[my-overlay]
# A remote overlay repo with priority (lower = higher priority)
Url = https://github.com/user/pkgbuilds.git
Priority = 1
# Allow this overlay to override official repo packages
OverrideOfficial

[local-dev]
# A local directory of PKGBUILDs
Path = /home/user/my-pkgbuilds
Priority = 2
```

## Examples

```bash
# Search and install a package interactively
qp <target>

# Update all packages (equivalent to pacman -Syu)
qp

# Install a specific package
qp -S <target>

# Upgrade AUR packages only
qp -Sua

# Print available AUR updates
qp -Qua

# Download PKGBUILD and related files
qp -G <target>

# Print the PKGBUILD of a package
qp -Gp <target>

# Print AUR comments for a package
qp -Gc <target>

# Generate the devel database for tracking -git packages
qp --gendb

# Build and install a PKGBUILD in the current directory
qp -Bi .

# Register an LFS package with auto-detected library provides
qp --mark-installed --auto-provides glibc 2.43

# Register a manually-built package with explicit provides
qp --mark-installed --mark-provides 'perl-xml-parser' perl-xml-parser 2.47

# List overlay repos and their priorities
qp -Ly
```

## General Tips

- **Man pages**: `qp(8)` and `qp.conf(5)`.
- **Color**: QP-ng only enables color if `Color` is enabled in `pacman.conf`.
- **File-based review**: Enable `FileManager` with your file manager of choice in `qp.conf`
  to get an interactive PKGBUILD review process.
- **Flip search order**: Enable `BottomUp` in `qp.conf` to start search results from the bottom.
- **Editing PKGBUILDs**: Commit your changes to make them permanent. When the package is
  upgraded, `git` will attempt to merge your changes with upstream.
- **PKGBUILD syntax highlighting**: Install [`bat`](https://github.com/sharkdp/bat) to
  enable syntax highlighting during PKGBUILD review.
- **Tracking -git packages**: QP-ng tracks `-git` packages by monitoring the upstream
  repository. Run `qp --gendb` after initial setup to make QP-ng aware of packages it
  didn't install itself.

## Debugging

QP-ng is not an official Arch tool. If it can't build a package, first check whether
`makepkg` can build it successfully. If makepkg also fails, report the issue to the
package maintainer. Otherwise, it's likely a QP-ng issue and should be reported
[here](https://github.com/Qaaxaap/qp-ng/issues).

## FAQ

**Why migrate from paru to QP-ng?**

If you want more flexible package management — registering hand-installed packages,
configuring overlay repos with priorities, building official packages from source —
QP-ng gives you those tools while keeping all of paru's AUR functionality. It also
works outside Arch Linux.

**Why use a package manager on LFS?**

LFS teaches you how a Linux system is built from scratch, which deserves respect.
But maintaining thousands of packages by hand isn't practical for daily use. QP-ng is
an attempt to bridge that gap — add pacman-based package management to your LFS
system without sacrificing the control and transparency that drew you to LFS in the
first place. It may not be perfect, but it beats formatting your LFS partition out
of frustration.

## Contributing

See [CONTRIBUTING.md](./CONTRIBUTING.md).

---

*Your system, your rules.*
**A package manager that exists for you.**
