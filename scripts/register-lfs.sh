#!/bin/bash
# register-lfs.sh — Register all LFS 13.0 Chapter 8 packages in pacman's local DB
#
# This creates fake pacman DB entries for every package built in LFS Chapter 8,
# mapping each LFS package name to its Arch Linux equivalent.
#
# After running this, pacman/QP-ng knows about all your LFS packages and can
# correctly resolve dependencies for new packages you install.
#
# Usage:
#   ./register-lfs.sh                  # register all Chapter 8 packages
#   ./register-lfs.sh --dry-run        # show what would be registered
#   ./register-lfs.sh --verify         # check which packages are already registered
#   ./register-lfs.sh --auto-provides  # auto-detect shared library provides

set -euo pipefail

GREEN='\033[1;32m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
RESET='\033[0m'
say()  { echo -e "${GREEN}==>${RESET} $*"; }
warn() { echo -e "${YELLOW}==>${RESET} $*" >&2; }
die()  { echo -e "${RED}==>${RESET} $*" >&2; exit 1; }

DRY_RUN=false
VERIFY=false
AUTO_PROVIDES=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)       DRY_RUN=true; shift ;;
        --verify)        VERIFY=true; shift ;;
        --auto-provides) AUTO_PROVIDES=true; shift ;;
        *) die "Unknown option: $1" ;;
    esac
done

if [[ $EUID -ne 0 ]] && ! $DRY_RUN && ! $VERIFY; then
    die "Must be root to register packages."
fi

if ! command -v qp &>/dev/null && ! $VERIFY; then
    die "qp not found. Install qp-ng first: ./scripts/install-lfs.sh"
fi

# ─── Critical shared library provides ────────────────────────────────────────
# These are packages whose .so files other packages depend on at build/runtime.
# Without these provides, pacman can't resolve dependencies correctly.
declare -A CRITICAL_PROVIDES=(
    # glibc — the foundation. Everything links against these.
    [glibc]="libc.so.6,libm.so.6,libpthread.so.0,libdl.so.2,librt.so.1,libresolv.so.2,libnsl.so.1,libutil.so.1,libnss_files.so.2,libnss_dns.so.2,libanl.so.1,libBrokenLocale.so.1,libthread_db.so.1,ld-linux-x86-64.so.2"
    # openssl — TLS/crypto
    [openssl]="libssl.so.3,libcrypto.so.3"
    # Compression
    [zlib]="libz.so.1"
    [zstd]="libzstd.so.1"
    [xz]="liblzma.so.5"
    [bzip2]="libbz2.so.1"
    [lz4]="liblz4.so.1"
    # Terminal / text
    [ncurses]="libncurses.so.6,libncursesw.so.6,libform.so.6,libmenu.so.6,libpanel.so.6"
    [readline]="libreadline.so.8,libhistory.so.8"
    # Math / crypto
    [gmp]="libgmp.so.10"
    [mpfr]="libmpfr.so.6"
    [mpc]="libmpc.so.3"
    # Regex
    [pcre2]="libpcre2-8.so.0,libpcre2-16.so.0,libpcre2-32.so.0,libpcre2-posix.so.3"
    # XML
    [expat]="libexpat.so.1"
    # FFI
    [libffi]="libffi.so.8"
    # Capabilities
    [libcap]="libcap.so.2,libpsx.so.2"
    # Database
    [gdbm]="libgdbm.so.6"
    [sqlite]="libsqlite3.so.0"
    # ELF
    [elfutils]="libelf.so.1,libdw.so.1,libasm.so.1"
    # Extended attributes / ACLs
    [attr]="libattr.so.1"
    [acl]="libacl.so.1"
    # Filesystem
    [e2fsprogs]="libext2fs.so.2,libcom_err.so.2,libe2p.so.2,libss.so.2"
    # IPC
    [dbus]="libdbus-1.so.3"
    # Systemd
    [systemd]="libsystemd.so.0,libudev.so.1"
    [systemd-libs]="libsystemd.so.0,libudev.so.1"
    # Util-linux
    [util-linux]="libuuid.so.1,libblkid.so.1,libmount.so.1,libfdisk.so.1,libsmartcols.so.1"
    [util-linux-libs]="libuuid.so.1,libblkid.so.1,libmount.so.1,libfdisk.so.1,libsmartcols.so.1"
    # Python (for python-* packages)
    [python]="python3"
    # Perl
    [perl]="perl"
    # PAM (provided by shadow in LFS)
    [shadow]="libmisc.so.2"
    # kmod
    [kmod]="libkmod.so.2"
    # libpipeline
    [libpipeline]="libpipeline.so.1"
    # libtool
    [libtool]="libltdl.so.7"
    # libxcrypt
    [libxcrypt]="libcrypt.so.1"
)

# ─── Package mapping: LFS name → (Arch name, version detection method) ───────
# Format: "LFS_PKG|ARCH_PKG|VERSION_HINT"
# VERSION_HINT is used when auto-detection isn't possible.
#
# Where one LFS package maps to multiple Arch packages, use multiple entries.

PACKAGE_MAP=(
    # ── Core toolchain ──
    "Acl|acl|"
    "Attr|attr|"
    "Autoconf|autoconf|"
    "Automake|automake|"
    "Bash|bash|"
    "Bc|bc|"
    "Binutils|binutils|"
    "Bison|bison|"
    "Bzip2|bzip2|"
    "Coreutils|coreutils|"

    # ── System libraries ──
    "D-Bus|dbus|"
    "E2fsprogs|e2fsprogs|"
    "Elfutils|elfutils|"
    "Expat|expat|"
    "GDBM|gdbm|"
    "Glibc|glibc|"
    "GMP|gmp|"
    "Libcap|libcap|"
    "Libffi|libffi|"
    "Libpipeline|libpipeline|"
    "Libtool|libtool|"
    "Libxcrypt|libxcrypt|"
    "Lz4|lz4|"
    "MPC|mpc|"
    "MPFR|mpfr|"
    "Ncurses|ncurses|"
    "OpenSSL|openssl|"
    "Pcre2|pcre2|"
    "Pkgconf|pkgconf|"
    "Readline|readline|"
    "Sqlite|sqlite|"
    "Xz|xz|"
    "Zlib|zlib|"
    "Zstd|zstd|"

    # ── Systemd and its libs ──
    "Systemd|systemd|"
    "Systemd|systemd-libs|"

    # ── GCC (compiler + runtime libs) ──
    "GCC|gcc|"
    "GCC|gcc-libs|"

    # ── Util-linux (utilities + libs) ──
    "Util-linux|util-linux|"
    "Util-linux|util-linux-libs|"

    # ── Build tools ──
    "DejaGNU|dejagnu|"
    "Diffutils|diffutils|"
    "Expect|expect|"
    "File|file|"
    "Findutils|findutils|"
    "Flex|flex|"
    "Gawk|gawk|"
    "Gettext|gettext|"
    "Gperf|gperf|"
    "Grep|grep|"
    "Groff|groff|"
    "Gzip|gzip|"
    "Intltool|intltool|"
    "M4|m4|"
    "Make|make|"
    "Meson|meson|"
    "Ninja|ninja|"
    "Patch|patch|"
    "Sed|sed|"
    "Tar|tar|"
    "Tcl|tcl|"
    "Texinfo|texinfo|"

    # ── Kernel / boot ──
    "GRUB|grub|"
    "Kbd|kbd|"
    "Kmod|kmod|"

    # ── Networking / IPC ──
    "Iana-Etc|iana-etc|"
    "Inetutils|inetutils|"
    "IPRoute2|iproute2|"

    # ── Perl ──
    "Perl|perl|"
    "XML::Parser|perl-xml-parser|"

    # ── Python ──
    "Python|python|"
    "Flit-Core|python-flit-core|"
    "Jinja2|python-jinja|"
    "MarkupSafe|python-markupsafe|"
    "Packaging|python-packaging|"
    "Setuptools|python-setuptools|"
    "Wheel|python-wheel|"

    # ── Docs / Man ──
    "Man-DB|man-db|"
    "Man-pages|man-pages|"

    # ── Admin / Misc ──
    "Less|less|"
    "Procps-ng|procps-ng|"
    "Psmisc|psmisc|"
    "Shadow|shadow|"
    "Vim|vim|"
)

# Helper: try to detect the installed version of a package
detect_version() {
    local lfs_name="$1"
    local arch_name="$2"

    # Method 1: check /usr/share/doc/<lfs_name>-<ver>
    # LFS installs docs with version in dir name
    local doc_dir
    doc_dir=$(ls -d /usr/share/doc/${lfs_name}-[0-9]* 2>/dev/null | head -1) && {
        basename "$doc_dir" | sed "s/^${lfs_name}-//"
        return 0
    }

    # Method 2: try arch name doc dir
    doc_dir=$(ls -d /usr/share/doc/${arch_name}-[0-9]* 2>/dev/null | head -1) && {
        basename "$doc_dir" | sed "s/^${arch_name}-//"
        return 0
    }

    # Method 3: binary --version (common patterns)
    case "$arch_name" in
        bash)      /usr/bin/bash --version 2>/dev/null | head -1 | grep -oP '\d+\.\d+[^\s,)]*' | head -1 && return 0 ;;
        python)    /usr/bin/python3 --version 2>/dev/null | grep -oP '\d+\.\d+\.\d+' && return 0 ;;
        perl)      /usr/bin/perl --version 2>/dev/null | grep -oP 'v\d+\.\d+\.\d+' | head -1 | sed 's/^v//' && return 0 ;;
        gcc)       /usr/bin/gcc --version 2>/dev/null | head -1 | grep -oP '\d+\.\d+\.\d+' && return 0 ;;
        make)      /usr/bin/make --version 2>/dev/null | head -1 | grep -oP '\d+\.\d+' && return 0 ;;
        vim)       /usr/bin/vim --version 2>/dev/null | head -1 | grep -oP '\d+\.\d+' | head -1 && return 0 ;;
        openssl)   /usr/bin/openssl version 2>/dev/null | grep -oP '\d+\.\d+\.\d+' && return 0 ;;
        systemd)   /usr/lib/systemd/systemd --version 2>/dev/null | head -1 | grep -oP '\d+[^\s,)]*' && return 0 ;;
        coreutils) /usr/bin/ls --version 2>/dev/null | head -1 | grep -oP '\d+\.\d+' && return 0 ;;
        grep)      /usr/bin/grep --version 2>/dev/null | head -1 | grep -oP '\d+\.\d+' && return 0 ;;
        sed)       /usr/bin/sed --version 2>/dev/null | head -1 | grep -oP '\d+\.\d+' && return 0 ;;
        tar)       /usr/bin/tar --version 2>/dev/null | head -1 | grep -oP '\d+\.\d+' && return 0 ;;
        gzip)      /usr/bin/gzip --version 2>/dev/null | head -1 | grep -oP '\d+\.\d+' && return 0 ;;
        curl)      /usr/bin/curl --version 2>/dev/null | head -1 | grep -oP '\d+\.\d+\.\d+' && return 0 ;;
    esac

    # Method 4: check pkg-config
    if pkgconf --exists "$arch_name" 2>/dev/null; then
        pkgconf --modversion "$arch_name" 2>/dev/null && return 0
    fi

    # Method 5 (fallback): pkg-config for the .pc file name
    local pc_name="${arch_name//-/_}"
    if pkgconf --exists "$pc_name" 2>/dev/null; then
        pkgconf --modversion "$pc_name" 2>/dev/null && return 0
    fi

    return 1
}

# ─── Main ─────────────────────────────────────────────────────────────────────
say "LFS 13.0 → Arch package registration"
say ""

count_ok=0
count_skip=0
count_fail=0

for entry in "${PACKAGE_MAP[@]}"; do
    IFS='|' read -r lfs_name arch_name _ <<< "$entry"

    # Check if already registered in pacman
    if pacman -Q "$arch_name" &>/dev/null 2>&1; then
        if $VERIFY; then
            say "OK: $arch_name ($lfs_name) — $(pacman -Q "$arch_name" 2>/dev/null | awk '{print $2}')"
        fi
        ((count_skip++)) || true
        continue
    fi

    # Detect version
    version=$(detect_version "$lfs_name" "$arch_name" 2>/dev/null) || true
    if [[ -z "$version" ]]; then
        warn "SKIP: $arch_name ($lfs_name) — cannot detect version"
        ((count_fail++)) || true
        continue
    fi

    # Build qp arguments array
    local qp_args=(--mark-installed)
    $AUTO_PROVIDES && qp_args+=(--auto-provides)

    if [[ -n "${CRITICAL_PROVIDES[$arch_name]:-}" ]]; then
        qp_args+=(--mark-provides "${CRITICAL_PROVIDES[$arch_name]}")
    fi
    qp_args+=("$arch_name" "$version")

    if $DRY_RUN || $VERIFY; then
        say "REGISTER: $arch_name $version (from LFS: $lfs_name)"
        if [[ -n "${CRITICAL_PROVIDES[$arch_name]:-}" ]]; then
            say "  provides: ${CRITICAL_PROVIDES[$arch_name]}"
        fi
        ((count_ok++)) || true
        continue
    fi

    # Register with qp
    if qp "${qp_args[@]}" 2>/dev/null; then
        say "OK: $arch_name $version"
        if [[ -n "${CRITICAL_PROVIDES[$arch_name]:-}" ]]; then
            say "  provides: ${CRITICAL_PROVIDES[$arch_name]}"
        fi
        ((count_ok++)) || true
    else
        warn "FAIL: $arch_name $version"
        ((count_fail++)) || true
    fi
done

# ─── Summary ──────────────────────────────────────────────────────────────────
say ""
say "Results: $count_ok registered, $count_skip already present, $count_fail failed"

if [[ $count_fail -gt 0 ]]; then
    warn "Some packages could not be registered."
    warn "For those, register manually: qp --mark-installed <arch-name> <version>"
fi

if $DRY_RUN; then
    say "(dry-run — nothing actually changed)"
fi
