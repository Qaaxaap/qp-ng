#!/bin/bash
# install-lfs.sh — Bootstrap qp-ng on LFS 13.0 (systemd) from source
#
# Assumes ONLY packages from the LFS 13.0 systemd book (Chapter 8) are available:
#   gcc, g++, make, autoconf, automake, libtool, m4, pkgconf, meson, ninja,
#   python3, openssl, bison, flex, gettext, zlib, zstd, xz, lz4, bzip2, ...
#
# Everything else (curl, git, cmake, libgpg-error, libassuan, gpgme,
# libarchive, pacman, rustc, cargo) is built from source by this script.
#
# Usage:
#   ./install-lfs.sh                      # full from-source bootstrap
#   ./install-lfs.sh --quick              # use official Rust bootstrap tarball
#   ./install-lfs.sh --dry-run            # show what would be done
#   ./install-lfs.sh --skip-downloads     # sources already in $SOURCES dir
#   PREFIX=/opt/qp ./install-lfs.sh       # custom install prefix

set -euo pipefail

# ─── Configuration ───────────────────────────────────────────────────────────
PREFIX="${PREFIX:-/usr}"
SOURCES="${SOURCES:-/tmp/qp-ng-sources}"
BUILD_DIR="${BUILD_DIR:-/tmp/qp-ng-build}"
JOBS="${JOBS:-$(nproc 2>/dev/null || echo 4)}"

# Versions — bump these as needed
CURL_VER="${CURL_VER:-8.17.0}"
LIBGPG_ERROR_VER="${LIBGPG_ERROR_VER:-1.55}"
LIBASSUAN_VER="${LIBASSUAN_VER:-3.0.2}"
GPGME_VER="${GPGME_VER:-2.1.2}"
LIBARCHIVE_VER="${LIBARCHIVE_VER:-3.8.8}"
PACMAN_VER="${PACMAN_VER:-7.1.0}"
RUSTC_BOOTSTRAP_VER="${RUSTC_BOOTSTRAP_VER:-1.90.0}"
RUSTC_TARGET_VER="${RUSTC_TARGET_VER:-1.93.0}"
MRUSTC_BRANCH="${MRUSTC_BRANCH:-master}"

# URLs
CURL_URL="https://curl.se/download/curl-${CURL_VER}.tar.xz"
LIBGPG_ERROR_URL="https://gnupg.org/ftp/gcrypt/libgpg-error/libgpg-error-${LIBGPG_ERROR_VER}.tar.bz2"
LIBASSUAN_URL="https://gnupg.org/ftp/gcrypt/libassuan/libassuan-${LIBASSUAN_VER}.tar.bz2"
GPGME_URL="https://gnupg.org/ftp/gcrypt/gpgme/gpgme-${GPGME_VER}.tar.bz2"
LIBARCHIVE_URL="https://github.com/libarchive/libarchive/releases/download/v${LIBARCHIVE_VER}/libarchive-${LIBARCHIVE_VER}.tar.xz"
PACMAN_URL="https://gitlab.archlinux.org/pacman/pacman/-/archive/v${PACMAN_VER}/pacman-v${PACMAN_VER}.tar.gz"
MRUSTC_URL="https://github.com/thepowersgang/mrustc/archive/refs/heads/${MRUSTC_BRANCH}.tar.gz"
RUSTC_BOOTSTRAP_SRC="https://static.rust-lang.org/dist/rustc-${RUSTC_BOOTSTRAP_VER}-src.tar.xz"
RUSTC_TARGET_SRC="https://static.rust-lang.org/dist/rustc-${RUSTC_TARGET_VER}-src.tar.xz"
RUST_QUICK_URL="https://static.rust-lang.org/dist/rust-${RUSTC_TARGET_VER}-x86_64-unknown-linux-gnu.tar.xz"

# Flags
DRY_RUN=false
QUICK_MODE=false
SKIP_DOWNLOADS=false

# ─── Helpers ─────────────────────────────────────────────────────────────────
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
RESET='\033[0m'
say()  { echo -e "${GREEN}==>${RESET} $*"; }
warn() { echo -e "${YELLOW}==>${RESET} $*" >&2; }
die()  { echo -e "${RED}==>${RESET} $*" >&2; exit 1; }
check_bin() { command -v "$1" &>/dev/null && return 0; warn "$1: MISSING"; return 1; }

run() {
    if $DRY_RUN; then
        echo "  [dry-run] $*"
    else
        say "  RUN: $*"
        eval "$*"
    fi
}

# Use python3 to download (LFS has no curl/wget in base)
download() {
    local url="$1"
    local dest="$2"
    if $DRY_RUN; then
        echo "  [dry-run] download $url → $dest"
        return 0
    fi
    if [[ -f "$dest" ]] && [[ -s "$dest" ]]; then
        say "  SKIP (exists): $dest"
        return 0
    fi
    say "  DOWNLOAD: $url"
    python3 -c "
import urllib.request, sys
url, dest = sys.argv[1], sys.argv[2]
try:
    with urllib.request.urlopen(url) as resp:
        with open(dest, 'wb') as f:
            while True:
                chunk = resp.read(8192)
                if not chunk: break
                f.write(chunk)
    print(f'OK: {dest}')
except Exception as e:
    print(f'FAIL: {e}', file=sys.stderr)
    sys.exit(1)
" "$url" "$dest"
}

build_autotools() {
    # Usage: build_autotools <name> <tarball> <configure-args...>
    local name="$1"
    local tarball="$2"
    shift 2

    local src_dir="$BUILD_DIR/$name"
    run "rm -rf '$src_dir'"
    run "mkdir -p '$src_dir'"
    run "tar -xf '$SOURCES/$tarball' -C '$src_dir' --strip-components=1"

    # Find configure (sometimes in a subdir for legacy packages)
    local configure_path
    if [[ -f "$src_dir/configure" ]]; then
        configure_path="$src_dir/configure"
    elif [[ -f "$src_dir/autogen.sh" ]]; then
        run "(cd '$src_dir' && ./autogen.sh)"
        configure_path="$src_dir/configure"
    else
        die "No configure script found in $src_dir"
    fi

    run "(cd '$src_dir' && '$configure_path' --prefix=$PREFIX $*)"
    run "make -C '$src_dir' -j${JOBS}"
    run "make -C '$src_dir' install"
}

# ─── CLI ─────────────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)        DRY_RUN=true; shift ;;
        --quick)          QUICK_MODE=true; shift ;;
        --skip-downloads) SKIP_DOWNLOADS=true; shift ;;
        --prefix=*)       PREFIX="${1#*=}"; shift ;;
        --help|-h)
            echo "Usage: $0 [--quick] [--dry-run] [--skip-downloads] [--prefix=PATH]"
            echo ""
            echo "Bootstrap qp-ng on an LFS 13.0 (systemd) system."
            echo "Only base LFS packages are assumed present. Everything else is built."
            echo ""
            echo "  --quick           Use official Rust bootstrap (fast, download binary)"
            echo "  --dry-run         Show what would be done without doing it"
            echo "  --skip-downloads  All source tarballs are already in \$SOURCES dir"
            echo "  --prefix=PATH     Install prefix (default: /usr)"
            echo ""
            echo "Full bootstrap order:"
            echo "  curl → libgpg-error → libassuan → gpgme → libarchive → pacman"
            echo "  → mrustc → rustc ${RUSTC_BOOTSTRAP_VER} → rustc ${RUSTC_TARGET_VER} → cargo → qp-ng"
            echo ""
            echo "Expected time (full): 5-9 hours. With --quick: ~30 minutes."
            exit 0
            ;;
        *) die "Unknown option: $1" ;;
    esac
done

# ─── Root check ──────────────────────────────────────────────────────────────
if [[ $EUID -ne 0 ]] && ! $DRY_RUN; then
    die "This script must be run as root."
fi

# ─── Phase 0: Check base LFS toolchain ───────────────────────────────────────
say "Phase 0: Checking base LFS toolchain..."

mkdir -p "$SOURCES" "$BUILD_DIR"

MISSING=()
for cmd in gcc g++ make m4; do
    check_bin "$cmd" || MISSING+=("$cmd")
done
for cmd in autoconf automake libtool; do
    check_bin "$cmd" || MISSING+=("$cmd")
done
for cmd in meson ninja pkgconf python3; do
    check_bin "$cmd" || MISSING+=("$cmd")
done

if [[ ${#MISSING[@]} -gt 0 ]]; then
    die "Missing from base LFS: ${MISSING[*]}\n" \
        "These should all be in LFS 13.0 Chapter 8. Install them first."
fi

# Check pkg-config essentials
for lib in openssl zlib zstd liblzma; do
    pkgconf --exists "$lib" 2>/dev/null || warn "$lib (pkg-config): MISSING"
done

say "Base toolchain OK. Build will proceed."
say "Sources dir:  $SOURCES"
say "Build dir:    $BUILD_DIR"
say "Install dir:  $PREFIX"
$DRY_RUN && say "(dry-run — nothing actually built)"

# ─── Phase 1: curl ───────────────────────────────────────────────────────────
# pacman needs libcurl for HTTP downloads. LFS base has no curl/wget.
if ! check_bin curl 2>/dev/null; then
    say "Phase 1: Building curl ${CURL_VER}..."

    CURL_TARBALL="curl-${CURL_VER}.tar.xz"
    $SKIP_DOWNLOADS || download "$CURL_URL" "$SOURCES/$CURL_TARBALL"

    build_autotools "curl-${CURL_VER}" "$CURL_TARBALL" \
        --with-openssl --without-libpsl --disable-ldap --disable-static

    run "ldconfig 2>/dev/null || true"
    check_bin curl || die "curl build failed"
    say "curl ${CURL_VER} installed."
else
    say "Phase 1: curl — SKIP (already available)"
fi

# ─── Phase 2: libgpg-error ───────────────────────────────────────────────────
if ! pkgconf --exists gpg-error 2>/dev/null; then
    say "Phase 2: Building libgpg-error ${LIBGPG_ERROR_VER}..."

    TARBALL="libgpg-error-${LIBGPG_ERROR_VER}.tar.bz2"
    $SKIP_DOWNLOADS || download "$LIBGPG_ERROR_URL" "$SOURCES/$TARBALL"

    build_autotools "libgpg-error-${LIBGPG_ERROR_VER}" "$TARBALL" --disable-static
    run "ldconfig 2>/dev/null || true"

    pkgconf --exists gpg-error 2>/dev/null || die "libgpg-error build failed"
    say "libgpg-error ${LIBGPG_ERROR_VER} installed."
else
    say "Phase 2: libgpg-error — SKIP (already available)"
fi

# ─── Phase 3: libassuan ──────────────────────────────────────────────────────
if ! pkgconf --exists libassuan 2>/dev/null; then
    say "Phase 3: Building libassuan ${LIBASSUAN_VER}..."

    TARBALL="libassuan-${LIBASSUAN_VER}.tar.bz2"
    $SKIP_DOWNLOADS || download "$LIBASSUAN_URL" "$SOURCES/$TARBALL"

    build_autotools "libassuan-${LIBASSUAN_VER}" "$TARBALL" --disable-static
    run "ldconfig 2>/dev/null || true"

    pkgconf --exists libassuan 2>/dev/null || die "libassuan build failed"
    say "libassuan ${LIBASSUAN_VER} installed."
else
    say "Phase 3: libassuan — SKIP (already available)"
fi

# ─── Phase 4: gpgme ──────────────────────────────────────────────────────────
if ! pkgconf --exists gpgme 2>/dev/null; then
    say "Phase 4: Building gpgme ${GPGME_VER}..."

    TARBALL="gpgme-${GPGME_VER}.tar.bz2"
    $SKIP_DOWNLOADS || download "$GPGME_URL" "$SOURCES/$TARBALL"

    build_autotools "gpgme-${GPGME_VER}" "$TARBALL" \
        --disable-gpg-test --disable-g13-test --disable-static
    run "ldconfig 2>/dev/null || true"

    pkgconf --exists gpgme 2>/dev/null || die "gpgme build failed"
    say "gpgme ${GPGME_VER} installed."
else
    say "Phase 4: gpgme — SKIP (already available)"
fi

# ─── Phase 5: libarchive ─────────────────────────────────────────────────────
if ! pkgconf --exists libarchive 2>/dev/null; then
    say "Phase 5: Building libarchive ${LIBARCHIVE_VER}..."

    TARBALL="libarchive-${LIBARCHIVE_VER}.tar.xz"
    $SKIP_DOWNLOADS || download "$LIBARCHIVE_URL" "$SOURCES/$TARBALL"

    # libarchive can use cmake OR autotools. The release tarball has configure.
    build_autotools "libarchive-${LIBARCHIVE_VER}" "$TARBALL" --disable-static
    run "ldconfig 2>/dev/null || true"

    pkgconf --exists libarchive 2>/dev/null || die "libarchive build failed"
    say "libarchive ${LIBARCHIVE_VER} installed."
else
    say "Phase 5: libarchive — SKIP (already available)"
fi

# ─── Phase 6: pacman + libalpm + makepkg ─────────────────────────────────────
if ! check_bin pacman 2>/dev/null; then
    say "Phase 6: Building pacman ${PACMAN_VER} (includes libalpm + makepkg)..."

    PACMAN_TARBALL="pacman-v${PACMAN_VER}.tar.gz"
    $SKIP_DOWNLOADS || download "$PACMAN_URL" "$SOURCES/$PACMAN_TARBALL"

    local pacman_src="$BUILD_DIR/pacman-v${PACMAN_VER}"
    run "rm -rf '$pacman_src'"
    run "tar -xf '$SOURCES/$PACMAN_TARBALL' -C '$BUILD_DIR'"

    # pacman 7.x uses meson. Disable docs to avoid asciidoc dependency.
    run "(cd '$pacman_src' && meson setup build --prefix=$PREFIX \
        -Ddoc=disabled -Ddoxygen=disabled -Di18n=false \
        -Dbuildtype=release)"
    run "meson compile -C '$pacman_src/build' -j${JOBS}"
    run "meson install -C '$pacman_src/build'"
    run "ldconfig 2>/dev/null || true"

    check_bin pacman || die "pacman build failed"
    say "pacman ${PACMAN_VER} installed."
    pacman --version 2>/dev/null | head -1 || true
else
    say "Phase 6: pacman — SKIP (already available)"
fi

# ─── Create /etc/pacman.conf ─────────────────────────────────────────────────
if [[ ! -f /etc/pacman.conf ]] && ! $DRY_RUN; then
    say "Creating /etc/pacman.conf..."
    cat > /etc/pacman.conf <<'CONF'
#
# /etc/pacman.conf — generated by qp-ng install script
#
[options]
HoldPkg     = pacman glibc
Architecture = auto
SigLevel    = Optional
LocalFileSigLevel = Optional

[core]
Include = /etc/pacman.d/mirrorlist-arch

[extra]
Include = /etc/pacman.d/mirrorlist-arch
CONF
    mkdir -p /etc/pacman.d
    cat > /etc/pacman.d/mirrorlist-arch <<'MIRRORS'
Server = https://geo.mirror.pkgbuild.com/$repo/os/$arch
Server = https://mirror.rackspace.com/archlinux/$repo/os/$arch
Server = https://mirror.leaseweb.com/archlinux/$repo/os/$arch
MIRRORS
    mkdir -p /var/lib/pacman/sync
    mkdir -p /var/lib/pacman/local
    say "pacman.conf created."
fi

# ─── Phase 7: Rust toolchain ─────────────────────────────────────────────────
HAVE_RUST=false
if check_bin rustc 2>/dev/null && check_bin cargo 2>/dev/null; then
    HAVE_RUST=true
fi

if $HAVE_RUST; then
    say "Phase 7: Rust toolchain — SKIP (already available)"
    rustc --version
    cargo --version
elif $QUICK_MODE; then
    # ── Quick: official Rust bootstrap binaries ──────────────────────────────
    say "Phase 7 (quick): Installing Rust ${RUSTC_TARGET_VER} from official tarball..."

    RUST_TARBALL="rust-${RUSTC_TARGET_VER}-x86_64-unknown-linux-gnu.tar.xz"
    $SKIP_DOWNLOADS || download "$RUST_QUICK_URL" "$SOURCES/$RUST_TARBALL"

    local rust_dir="$BUILD_DIR/rust-${RUSTC_TARGET_VER}-x86_64-unknown-linux-gnu"
    run "rm -rf '$rust_dir'"
    run "tar -xf '$SOURCES/$RUST_TARBALL' -C '$BUILD_DIR'"
    run "(cd '$rust_dir' && ./install.sh --prefix=$PREFIX --without=rust-docs)"

    check_bin rustc || die "Rust install failed"
    check_bin cargo || die "Cargo install failed"
    HAVE_RUST=true
    say "Rust ${RUSTC_TARGET_VER} (quick) installed."
else
    # ── Full bootstrap: mrustc → rustc 1.90 → latest rustc → cargo ──────────
    say "Phase 7: Full Rust bootstrap (mrustc → rustc ${RUSTC_BOOTSTRAP_VER} → ${RUSTC_TARGET_VER})"
    warn "This will take several hours and needs ~25GB disk space."
    warn "Use --quick for a 30-minute prebuilt alternative."

    # Step 7a: Build mrustc
    say "Phase 7a: Building mrustc..."
    MRUSTC_TARBALL="mrustc-${MRUSTC_BRANCH}.tar.gz"
    $SKIP_DOWNLOADS || download "$MRUSTC_URL" "$SOURCES/$MRUSTC_TARBALL"

    local mrustc_dir="$BUILD_DIR/mrustc"
    run "rm -rf '$mrustc_dir'"
    run "mkdir -p '$mrustc_dir'"
    run "tar -xf '$SOURCES/$MRUSTC_TARBALL' -C '$mrustc_dir' --strip-components=1"

    # Download rustc source that mrustc can compile
    RUSTC_SRC_TARBALL="rustc-${RUSTC_BOOTSTRAP_VER}-src.tar.xz"
    $SKIP_DOWNLOADS || download "$RUSTC_BOOTSTRAP_SRC" "$SOURCES/$RUSTC_SRC_TARBALL"

    local rustc_src_dir="$BUILD_DIR/rustc-${RUSTC_BOOTSTRAP_VER}-src"
    run "rm -rf '$rustc_src_dir'"
    run "tar -xf '$SOURCES/$RUSTC_SRC_TARBALL' -C '$BUILD_DIR'"

    say "Phase 7b: Building rustc ${RUSTC_BOOTSTRAP_VER} with mrustc..."
    run "(cd '$mrustc_dir' && make -j${JOBS} -f minicargo.mk \
        RUSTCSRC_DIR='$rustc_src_dir')"

    say "Phase 7c: Building cargo with mrustc-built rustc..."
    run "(cd '$mrustc_dir' && make -j${JOBS} -f minicargo.mk \
        RUSTCSRC_DIR='$rustc_src_dir' CARGO_BUILD=1)"

    # Step 7d: Use stage1 to build latest rustc + cargo from source
    say "Phase 7d: Building final rustc ${RUSTC_TARGET_VER}..."

    local stage1_bin="$mrustc_dir/output/bin"
    if [[ ! -x "$stage1_bin/rustc" ]]; then
        die "mrustc stage1 build incomplete — no rustc at $stage1_bin"
    fi

    export PATH="${stage1_bin}:${PATH}"

    RUSTC_FINAL_TARBALL="rustc-${RUSTC_TARGET_VER}-src.tar.xz"
    $SKIP_DOWNLOADS || download "$RUSTC_TARGET_SRC" "$SOURCES/$RUSTC_FINAL_TARBALL"

    local rustc_final_dir="$BUILD_DIR/rustc-${RUSTC_TARGET_VER}-src"
    run "rm -rf '$rustc_final_dir'"
    run "tar -xf '$SOURCES/$RUSTC_FINAL_TARBALL' -C '$BUILD_DIR'"
    run "(cd '$rustc_final_dir' && ./configure \
        --prefix=$PREFIX \
        --enable-local-rust \
        --local-rust-root='$stage1_bin')"
    run "(cd '$rustc_final_dir' && python3 x.py build --stage 2 -j${JOBS})"
    run "(cd '$rustc_final_dir' && python3 x.py install --stage 2)"

    check_bin rustc || die "Final rustc build failed"
    check_bin cargo || die "Final cargo build failed"
    HAVE_RUST=true
    say "Full Rust bootstrap complete."
    rustc --version
fi

# ─── Phase 8: Build qp-ng ────────────────────────────────────────────────────
say "Phase 8: Building qp-ng..."

if ! $HAVE_RUST && ! $DRY_RUN; then
    die "No Rust toolchain available."
fi

if [[ ! -f Cargo.toml ]]; then
    die "Cargo.toml not found. Run from the qp-ng source directory."
fi

# Verify libalpm is findable
if ! pkgconf --exists libalpm 2>/dev/null && ! $DRY_RUN; then
    warn "libalpm not in pkg-config path. Trying to locate..."
    A_PC=$(find /usr -name 'libalpm.pc' 2>/dev/null | head -1)
    if [[ -n "$A_PC" ]]; then
        export PKG_CONFIG_PATH="$(dirname "$A_PC"):${PKG_CONFIG_PATH:-}"
        say "Found libalpm.pc at $(dirname "$A_PC")"
    else
        die "libalpm.pc not found. pacman build may have failed."
    fi
fi

# Build with QP_VERSION
QP_VERSION="$(git describe --tags --long 2>/dev/null || echo '0.0.0')"
export QP_VERSION

run "cargo build --release"
run "install -Dm755 target/release/qp ${PREFIX}/bin/qp"

# Man pages
run "install -Dm644 man/qp.8 ${PREFIX}/share/man/man8/qp.8"
run "install -Dm644 man/qp.conf.5 ${PREFIX}/share/man/man5/qp.conf.5"

# Completions
run "install -Dm644 completions/bash ${PREFIX}/share/bash-completion/completions/qp.bash"
run "install -Dm644 completions/fish ${PREFIX}/share/fish/vendor_completions.d/qp.fish"
run "install -Dm644 completions/zsh ${PREFIX}/share/zsh/site-functions/_qp"

# Config
run "install -Dm644 qp.conf /etc/qp.conf"

# Locale
if [[ -d locale ]]; then
    run "cp -r locale ${PREFIX}/share/"
fi

# ─── Done ────────────────────────────────────────────────────────────────────
say ""
say "qp-ng installation complete."
say ""

if ! $DRY_RUN && check_bin qp 2>/dev/null; then
    qp --version 2>/dev/null || true
    say ""
    say "Next steps:"
    say "  1. Edit /etc/pacman.conf to configure mirrors"
    say "  2. Initialize keyring:  pacman-key --init && pacman-key --populate"
    say "  3. Register existing LFS packages so pacman knows about them:"
    say "     for each LFS package:"
    say "       qp --mark-installed <name> <version>"
    say ""
    say "  4. Import Arch core packages to satisfy toolchain deps:"
    say "     pacman -Sy base-devel"
    say ""
    say "     TIP: Use --quick next time for a 30min install instead of hours."
fi
