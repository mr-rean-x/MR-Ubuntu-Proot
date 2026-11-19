#!/bin/bash
# ============================================================
#  MR ROOT ONE v3.0.0 — ADVANCE One-Paste Root Command
#  by MR REAN (mr-rean-x) | https://github.com/mr-rean-x/MR-Ubuntu-Proot
#
#  HOW TO USE — AKTA COMMAND, PASTE KORLEI ROOT:
#    1. Copy this WHOLE file (first line to last line).
#    2. Paste it into any terminal (Jupyter / Render / any VPS) and press Enter.
#    3. Done — Ubuntu install hoye root shell-e dhuke jabe. Ar kichu lagbe na.
#    Already installed thakle download skip kore soja root-e dhukbe.
#
#  WHY THIS WORKS WHERE curl FAILED:
#    - Kono download lagbe na ei file-er jonno — tumi nijei paste korteso.
#    - Ubuntu + proot download-er jonno wget -> curl -> python3 try kore.
#      Jupyter host-e python3 thakbei, tai curl/wget na thakleo cholbe.
#    - /bin/sh (dash) terminal-e paste korleo cholbe — kono bash-only
#      jinish nai (no pipefail, no [[ ]], shob POSIX).
#
#  AFTER YOU GET ROOT — inside Ubuntu:
#    bash /root/.mr-setup.sh     # Node 20 + git + PM2 install (JTG-ready)
#    apt-get install -y openjdk-21-jdk   # JTG needs Java (optional, ~10 min)
#    git clone https://github.com/JishnuTheGamer/Jtg.git && cd Jtg && bash install.sh
#    # JTG installer: choose 1, then 2 (Pure Local Node.js), owner mrrean
#
#  ALL 13 BUGS FIXED vs the original FOX YTOUX script — see README.md
# ============================================================
# POSIX-safe: works even when pasted into /bin/sh (dash), which has no pipefail.
set -eu

VERSION="3.0.0-MR-ONE"
UBUNTU_VERSION="${UBUNTU_VERSION:-20.04}"
ROOTFS_DIR="${ROOTFS_DIR:-$HOME/mr-ubuntu}"
# ONE-PASTE default: NO setup — fastest way to root. Setup still gets
# written to /root/.mr-setup.sh inside Ubuntu, run it by hand after (see header).
DO_SETUP=0
WITH_JAVA=0
YES=0
CMD="${1:-install}"
# NOTE: plain `shift || true` kills dash (shift is a special builtin — its
# error is fatal in non-interactive sh even after ||). Guard it instead.
if [ $# -gt 0 ]; then shift; fi

# ---------- colours / logging ----------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
# NOTE: printf '%b' — NOT echo -e. dash's echo prints a literal "-e"
# and no colours, so the log lines looked broken when pasted into /bin/sh.
info()  { printf '%b\n' "${CYAN}[*]${NC} $*"; }
ok()    { printf '%b\n' "${GREEN}[+]${NC} $*"; }
warn()  { printf '%b\n' "${YELLOW}[!]${NC} $*"; }
error() { printf '%b\n' "${RED}[x]${NC} $*" >&2; }
die()   { error "$*"; exit 1; }

banner() {
    echo "============================================"
    echo "       MR ROOT v$VERSION — UBUNTU PROOT"
    echo "============================================"
}

# ---------- args ----------
while [ $# -gt 0 ]; do
    case "$1" in
        --dir)       ROOTFS_DIR="$2"; shift 2 ;;
        --ubuntu)    UBUNTU_VERSION="$2"; shift 2 ;;
        --no-setup)  DO_SETUP=0; shift ;;
        --with-java) WITH_JAVA=1; shift ;;
        --yes|-y)    YES=1; shift ;;
        -h|--help)   CMD="help"; shift ;;
        *) # extra args belong to exec / start — leave "$@" untouched
            break ;;
    esac
done

ROOTFS_DIR="$(cd "$(dirname "$ROOTFS_DIR")" 2>/dev/null && pwd)/$(basename "$ROOTFS_DIR")"
PROOT_BIN="$ROOTFS_DIR/usr/local/bin/proot"
MARKER="$ROOTFS_DIR/.mr-installed"
LAUNCHER="$HOME/mr-ubuntu-start.sh"

# ---------- arch ----------
ARCH="$(uname -m)"
case "$ARCH" in
    x86_64)  ARCH_ALT="amd64";;
    aarch64) ARCH_ALT="arm64";;
    *) die "Unsupported architecture: $ARCH (only x86_64 / aarch64)" ;;
esac

case "$UBUNTU_VERSION" in
    20.04) UBUNTU_RELEASE="20.04.4" ;;
    22.04) UBUNTU_RELEASE="22.04.5" ;;
    *) die "Unsupported Ubuntu version: $UBUNTU_VERSION (use 20.04 or 22.04)" ;;
esac

ROOTFS_URL="https://cdimage.ubuntu.com/ubuntu-base/releases/${UBUNTU_VERSION}/release/ubuntu-base-${UBUNTU_RELEASE}-base-${ARCH_ALT}.tar.gz"
ROOTFS_FILE="ubuntu-base-${UBUNTU_RELEASE}-base-${ARCH_ALT}.tar.gz"
SHA_URL="https://cdimage.ubuntu.com/ubuntu-base/releases/${UBUNTU_VERSION}/release/SHA256SUMS"
PROOT_URL="https://raw.githubusercontent.com/foxytouxxx/freeroot/main/proot-${ARCH}"
PROOT_FALLBACK="https://cdn.jsdelivr.net/gh/foxytouxxx/freeroot@main/proot-${ARCH}"

# ---------- helpers ----------
need_cmd() { command -v "$1" >/dev/null 2>&1 || die "Missing required tool: $1 — install it first."; }

download_file() {
    # download_file <url> <dest> — resume capable, 5 tries.
    # Tries wget, then curl, then python3 (Jupyter hosts always have python3,
    # even when curl AND wget are both missing — that is why this fallback exists).
    local url="$1" dest="$2" tries=0
    while [ "$tries" -lt 5 ]; do
        tries=$((tries + 1))
        if command -v wget >/dev/null 2>&1; then
            if wget -c --tries=3 --timeout=60 --waitretry=3 --no-hsts -O "$dest" "$url"; then return 0; fi
        elif command -v curl >/dev/null 2>&1; then
            if curl -fL -C - --retry 3 --connect-timeout 30 -o "$dest" "$url"; then return 0; fi
        elif command -v python3 >/dev/null 2>&1; then
            if python3 -c "import urllib.request,sys; urllib.request.urlretrieve(sys.argv[1], sys.argv[2])" "$url" "$dest"; then return 0; fi
        else
            die "Need wget, curl or python3 to download files."
        fi
        warn "Download try $tries/5 failed for $url — retrying..."
        sleep 3
    done
    return 1
}

check_disk() {
    # need at least 600 MB free in $HOME
    local free_kb
    free_kb="$(df -k "$HOME" | awk 'NR==2 {print $4}')"
    if [ -n "$free_kb" ] && [ "$free_kb" -lt 614400 ]; then
        die "Not enough disk space: need 600MB free, only $((free_kb / 1024))MB free in $HOME"
    fi
}

is_elf() {
    # check ELF magic bytes (first 4 bytes = 7f 45 4c 46)
    [ -s "$1" ] && [ "$(head -c 4 "$1" | od -An -tx1 | tr -d ' \n')" = "7f454c46" ]
}

verify_sha256() {
    # verify_sha256 <file> — checks cdimage SHA256SUMS if an entry exists; warns, never hard-fails on missing entry
    local file="$1" base sha_file expected actual
    base="$(basename "$file")"
    sha_file="$(mktemp)"
    if ! download_file "$SHA_URL" "$sha_file" 2>/dev/null; then warn "Could not fetch SHA256SUMS — skipping hash check."; rm -f "$sha_file"; return 0; fi
    expected="$(grep " $base\$" "$sha_file" | awk '{print $1}' || true)"
    rm -f "$sha_file"
    if [ -z "$expected" ]; then warn "No SHA256 entry for $base — skipping hash check (gzip + tar test still runs)."; return 0; fi
    command -v sha256sum >/dev/null 2>&1 || { warn "sha256sum missing — skipping hash check."; return 0; }
    actual="$(sha256sum "$file" | awk '{print $1}')"
    [ "$actual" = "$expected" ] || die "SHA256 MISMATCH for $base — file is corrupted, delete it and re-run."
    ok "SHA256 verified: $base"
}

# ---------- install steps (FIXED: each step checked separately) ----------
install_rootfs() {
    # BUG FIX #1/#2: old script re-downloaded the whole rootfs when only
    # proot was missing, and extracted into $(pwd). Now rootfs has its own
    # fixed dir and its own check — proot problems never trigger a re-download.
    if [ -x "$ROOTFS_DIR/bin/sh" ] && [ -f "$MARKER" ] && grep -q "ubuntu=$UBUNTU_VERSION" "$MARKER" 2>/dev/null; then
        ok "Ubuntu $UBUNTU_VERSION rootfs already installed at $ROOTFS_DIR — skipping download."
        return 0
    fi
    info "Installing Ubuntu $UBUNTU_VERSION ($UBUNTU_RELEASE, $ARCH_ALT) to $ROOTFS_DIR ..."
    mkdir -p "$ROOTFS_DIR"
    local tmp_archive="/tmp/$ROOTFS_FILE"
    rm -f "$MARKER"
    download_file "$ROOTFS_URL" "$tmp_archive" || die "Ubuntu download failed after 5 tries. Check internet and re-run."
    [ -s "$tmp_archive" ] || die "Downloaded Ubuntu archive is empty."
    info "Checking Ubuntu archive..."
    gzip -t "$tmp_archive" || { rm -f "$tmp_archive"; die "Ubuntu archive is corrupted (gzip test failed)."; }
    verify_sha256 "$tmp_archive"
    info "Extracting Ubuntu rootfs (this takes a minute)..."
    # BUG FIX #13 (found by live test): as a NON-ROOT user, plain
    # `tar -xzf` tries to chown files to uid 0 and exits non-zero — even
    # though every file was extracted fine. So: --no-same-owner, and judge
    # success by the extracted CONTENT (bin/sh + /usr/bin), not tar's exit code.
    if ! tar --no-same-owner -xzf "$tmp_archive" -C "$ROOTFS_DIR" 2>"$ROOTFS_DIR/.extract.log"; then
        warn "tar reported warnings during extraction (usually ownership — harmless under proot, see $ROOTFS_DIR/.extract.log)"
    fi
    rm -f "$tmp_archive"
    [ -x "$ROOTFS_DIR/bin/sh" ] || die "/bin/sh still missing after extraction. Disk full or bad archive?"
    [ -d "$ROOTFS_DIR/usr/bin" ] || die "Rootfs looks incomplete (no /usr/bin)."
    ok "Ubuntu rootfs extracted."
}

install_proot() {
    # BUG FIX: old script never tested the proot binary — a bad/HTML download
    # was chmod +x'd and only failed later at launch. Now we verify ELF + run it.
    if [ -x "$PROOT_BIN" ] && is_elf "$PROOT_BIN" && "$PROOT_BIN" --version >/dev/null 2>&1; then
        ok "PRoot already installed and working — skipping download."
        return 0
    fi
    info "Downloading PRoot ($ARCH)..."
    mkdir -p "$(dirname "$PROOT_BIN")"
    if ! download_file "$PROOT_URL" "$PROOT_BIN"; then
        warn "Primary proot URL failed — trying mirror..."
        download_file "$PROOT_FALLBACK" "$PROOT_BIN" || die "PRoot download failed from both URLs."
    fi
    chmod 755 "$PROOT_BIN"
    if ! is_elf "$PROOT_BIN"; then
        rm -f "$PROOT_BIN"
        die "Downloaded proot is NOT a real binary (got HTML/error page?). Deleted — re-run to retry."
    fi
    "$PROOT_BIN" --version >/dev/null 2>&1 || { rm -f "$PROOT_BIN"; die "Downloaded proot does not run — deleted, re-run to retry."; }
    ok "PRoot installed: $("$PROOT_BIN" --version 2>&1 | head -1)"
}

configure_dns() {
    mkdir -p "$ROOTFS_DIR/root" "$ROOTFS_DIR/tmp" "$ROOTFS_DIR/etc" "$ROOTFS_DIR/usr/local/bin"
    # BUG FIX: old script copied /etc/resolv.conf blindly — on hosts where it
    # is a broken symlink the copy fails and DNS dies inside Ubuntu.
    if [ -e /etc/resolv.conf ] && [ -s /etc/resolv.conf ]; then
        cp -L /etc/resolv.conf "$ROOTFS_DIR/etc/resolv.conf" 2>/dev/null || true
    fi
    if ! grep -q nameserver "$ROOTFS_DIR/etc/resolv.conf" 2>/dev/null; then
        printf 'nameserver 1.1.1.1\nnameserver 8.8.8.8\n' > "$ROOTFS_DIR/etc/resolv.conf"
        warn "No host DNS found — using 1.1.1.1 / 8.8.8.8 inside Ubuntu."
    fi
    # hosts file so localhost + the container hostname resolve
    if ! grep -q "localhost" "$ROOTFS_DIR/etc/hosts" 2>/dev/null; then
        printf '127.0.0.1 localhost\n::1 localhost ip6-localhost ip6-loopback\n' > "$ROOTFS_DIR/etc/hosts"
    fi
    ok "DNS configured."
}

write_launcher() {
    # The launcher is the real "root command": ~/mr-ubuntu-start.sh
    # BUG FIX #6/#8: old script bound only /dev /sys /proc and always opened
    # /bin/sh -l. The launcher binds /dev/pts /dev/shm /tmp too (apt + Node
    # break without them) and passes your command through: start "node -v"
    cat > "$LAUNCHER" <<LAUNCHER_EOF
#!/bin/bash
# MR ROOT launcher — generated by mr-root.sh v$VERSION. Do not edit by hand; re-run mr-root.sh to regenerate.
set -e
ROOTFS="$ROOTFS_DIR"
PROOT="\$ROOTFS/usr/local/bin/proot"
[ -x "\$PROOT" ] || { echo "[x] proot missing at \$PROOT — run: bash mr-root.sh install"; exit 1; }
[ -x "\$ROOTFS/bin/sh" ] || { echo "[x] Ubuntu rootfs missing at \$ROOTFS — run: bash mr-root.sh install"; exit 1; }
run_proot() {
    "\$PROOT" --rootfs="\$ROOTFS" -0 -w /root \\
        -b /dev -b /dev/pts -b /dev/shm -b /sys -b /proc -b /tmp \\
        -b /etc/resolv.conf --link2symlink --kill-on-exit \\
        /bin/bash -l "\$@"
}
if [ \$# -eq 0 ]; then
    run_proot
else
    # first launch attempt; if seccomp blocks proot on this host, retry without it
    if ! run_proot -c "\$*"; then
        echo "[!] First launch failed — retrying with PROOT_NO_SECCOMP=1 ..."
        PROOT_NO_SECCOMP=1 run_proot -c "\$*"
    fi
fi
LAUNCHER_EOF
    chmod +x "$LAUNCHER"
    # also make a short command available if ~/.local/bin is on PATH
    mkdir -p "$HOME/.local/bin" 2>/dev/null || true
    ln -sf "$LAUNCHER" "$HOME/.local/bin/mr-ubuntu" 2>/dev/null || true
    ok "Launcher created: $LAUNCHER  (also: mr-ubuntu, if ~/.local/bin is on PATH)"
}

write_setup_inside() {
    # First-boot setup that runs INSIDE Ubuntu — this is what makes it JTG-ready.
    cat > "$ROOTFS_DIR/root/.mr-setup.sh" <<'SETUP_EOF'
#!/bin/bash
# No `set -e` on purpose: one failed step (e.g. apt blocked by a proxy)
# must NOT kill the whole setup — report it and keep going.
export DEBIAN_FRONTEND=noninteractive
echo "[*] MR ROOT first-boot setup — apt + Node 20 + git + PM2 ..."
apt-get update -y || echo "[!] apt-get update FAILED (DNS/proxy?). Check: cat /etc/resolv.conf — then re-run: bash /root/.mr-setup.sh"
apt-get install -y --no-install-recommends curl wget git ca-certificates gnupg python3 unzip zip nano procps || echo "[!] apt install had errors — continuing with whatever is installed."
if ! command -v node >/dev/null 2>&1 || ! node -v 2>/dev/null | grep -q "^v20"; then
    if command -v curl >/dev/null 2>&1; then
        echo "[*] Installing Node.js 20 (NodeSource)..."
        curl -fsSL https://deb.nodesource.com/setup_20.x | bash - || echo "[!] NodeSource setup failed."
        apt-get install -y nodejs || echo "[!] nodejs install failed."
    else
        echo "[!] curl missing, cannot install Node 20 — fix apt first, then re-run this script."
    fi
fi
if command -v node >/dev/null 2>&1; then node -v; npm -v; else echo "[!] Node NOT installed."; fi
if command -v npm >/dev/null 2>&1; then npm install -g pm2 2>/dev/null || echo "[!] pm2 install failed — optional, JTG can run with npm."; fi
echo "[*] Setup finished."
SETUP_EOF
    chmod +x "$ROOTFS_DIR/root/.mr-setup.sh"
}

run_inside() {
    # run_inside <bash -c string> — runs a command inside the proot Ubuntu
    "$PROOT_BIN" --rootfs="$ROOTFS_DIR" -0 -w /root \
        -b /dev -b /dev/pts -b /dev/shm -b /sys -b /proc -b /tmp \
        -b /etc/resolv.conf --link2symlink --kill-on-exit \
        /bin/bash -l -c "$1"
}

do_setup() {
    # BUG FIX #17: setup must NEVER kill the install. If apt/Node fails
    # (proxy-blocked host, no network), warn and STILL enter root — the
    # user can retry setup later from inside with: bash /root/.mr-setup.sh
    info "Running first-boot setup inside Ubuntu (apt + Node 20 + git + PM2)..."
    if [ "$WITH_JAVA" = "1" ]; then
        info "WITH_JAVA: also installing openjdk-21 (JTG needs it, takes ~10-15 min)..."
        run_inside "export DEBIAN_FRONTEND=noninteractive; bash /root/.mr-setup.sh; apt-get install -y openjdk-21-jdk || echo '[!] Java install failed — retry inside: apt-get install -y openjdk-21-jdk'; java -version 2>&1 | head -1 || true" || warn "Setup step had errors — root still works, retry inside with: bash /root/.mr-setup.sh"
    else
        run_inside "bash /root/.mr-setup.sh" || warn "Setup step had errors — root still works, retry inside with: bash /root/.mr-setup.sh"
    fi
    ok "Setup step finished."
    run_inside 'echo "node: $(node -v 2>/dev/null || echo MISSING) / npm: $(npm -v 2>/dev/null || echo MISSING)"' || true
    return 0
}

do_install() {
    banner
    echo "Architecture: $ARCH ($ARCH_ALT)"
    echo "Rootfs: $ROOTFS_DIR"
    echo "Ubuntu: $UBUNTU_VERSION ($UBUNTU_RELEASE)"
    echo
    need_cmd tar; need_cmd gzip
    command -v wget >/dev/null 2>&1 || command -v curl >/dev/null 2>&1 || command -v python3 >/dev/null 2>&1 || die "Need wget, curl or python3."
    check_disk
    install_rootfs
    install_proot
    configure_dns
    write_launcher
    write_setup_inside
    printf 'mr-root-version=%s\nubuntu=%s\narch=%s\ninstalled=%s\n' "$VERSION" "$UBUNTU_VERSION" "$ARCH" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$MARKER"
    if [ "$DO_SETUP" = "1" ]; then
        do_setup || true
    else
        warn "Setup skipped (--no-setup). Run 'bash mr-root.sh setup' later for Node 20 + git."
    fi
    echo
    echo "============================================"
    echo "       UBUNTU INSTALLATION COMPLETED"
    echo "============================================"
    echo "Enter Ubuntu with:"
    echo "  bash ~/mr-ubuntu-start.sh"
    echo "  (or: mr-ubuntu, if ~/.local/bin is on PATH)"
    echo "Run one command inside:"
    echo "  bash mr-root.sh exec \"node -v\""
    echo "Install JTG panel inside:"
    echo "  bash mr-root.sh jtg"
    echo
    info "Starting Ubuntu now — type 'exit' to leave."
    exec "$LAUNCHER"
}

do_jtg() {
    [ -x "$PROOT_BIN" ] && [ -x "$ROOTFS_DIR/bin/sh" ] || die "Ubuntu not installed yet — run 'bash mr-root.sh install' first."
    info "JTG panel setup inside Ubuntu..."
    run_inside '
        set -e
        command -v node >/dev/null 2>&1 || { echo "[x] Node missing — run: bash mr-root.sh setup"; exit 1; }
        command -v git >/dev/null 2>&1 || { echo "[x] git missing — run: bash mr-root.sh setup"; exit 1; }
        cd /root
        if [ -d Jtg/.git ]; then echo "[*] Jtg exists — pulling latest..."; cd Jtg && git pull --ff-only || true
        else git clone https://github.com/JishnuTheGamer/Jtg.git; cd Jtg; fi
        echo "[+] JTG cloned at /root/Jtg"
        echo "[*] Starting JTG installer — choose [1] Install Panel, then [2] Pure Local Node.js"
        echo "[*] Owner username: mrrean — password: YOU type it (min 6 chars, never in chat)"
        bash install.sh
    '
}

do_status() {
    echo "MR ROOT v$VERSION — status"
    echo "Rootfs: $ROOTFS_DIR"
    if [ -f "$MARKER" ]; then cat "$MARKER"; else echo "installed: NO (run: bash mr-root.sh install)"; fi
    [ -x "$PROOT_BIN" ] && echo "proot: $("$PROOT_BIN" --version 2>&1 | head -1)" || echo "proot: MISSING"
    [ -x "$ROOTFS_DIR/bin/sh" ] && echo "rootfs: OK ($(du -sh "$ROOTFS_DIR" 2>/dev/null | cut -f1))" || echo "rootfs: MISSING"
    if [ -x "$PROOT_BIN" ] && [ -x "$ROOTFS_DIR/bin/sh" ]; then
        run_inside 'grep PRETTY_NAME /etc/os-release 2>/dev/null || echo "os: unknown"'
        run_inside 'command -v node >/dev/null && echo "node: $(node -v)" || echo "node: not installed (run: bash mr-root.sh setup)"'
        run_inside '[ -d /root/Jtg ] && echo "JTG: cloned at /root/Jtg" || echo "JTG: not cloned (run: bash mr-root.sh jtg)"'
    fi
}

do_clean() {
    if [ "$YES" != "1" ]; then
        echo "This deletes $ROOTFS_DIR and $LAUNCHER"
        printf "Type YES to confirm: "; read -r ans
        [ "$ans" = "YES" ] || { echo "Cancelled."; exit 0; }
    fi
    rm -rf "$ROOTFS_DIR" "$LAUNCHER" "$HOME/.local/bin/mr-ubuntu"
    ok "Cleaned. Re-install with: bash mr-root.sh install"
}

show_help() {
    banner
    echo "Usage: bash mr-root.sh <command> [options]"
    echo
    echo "Commands:"
    echo "  install [--no-setup] [--with-java] [--dir PATH] [--ubuntu 20.04|22.04]"
    echo "          Download + install Ubuntu, fix DNS, create launcher, setup Node 20"
    echo "  start | shell              Enter Ubuntu (same as ~/mr-ubuntu-start.sh)"
    echo "  exec \"<cmd>\"              Run one command inside Ubuntu"
    echo "  setup                      (Re)run first-boot setup (apt + Node 20 + git + PM2)"
    echo "  jtg                        Clone JTG panel + run its installer (1, then 2)"
    echo "  status                     Show install status"
    echo "  clean [--yes]              Delete Ubuntu + launcher"
    echo "  help                       This help"
    echo
    echo "Examples:"
    echo "  bash mr-root.sh install --with-java     # JTG needs Java — full setup"
    echo "  bash mr-root.sh install --no-setup      # Ubuntu only, fast"
    echo "  bash mr-root.sh exec \"node -v && npm -v\""
    echo "  bash ~/mr-ubuntu-start.sh               # enter Ubuntu any time"
    echo
    echo "Bugs fixed vs the original FOX YTOUX script — see README.md"
}

case "$CMD" in
    install) do_install ;;
    start|shell) [ -x "$LAUNCHER" ] || die "Launcher missing — run install first."; exec "$LAUNCHER" ;;
    exec) [ $# -gt 0 ] || die "Usage: bash mr-root.sh exec \"<command>\""; run_inside "$*" ;;
    setup) write_setup_inside; do_setup ;;
    jtg) do_jtg ;;
    status) do_status ;;
    clean) do_clean ;;
    help|--help|-h) show_help ;;
    *) error "Unknown command: $CMD"; show_help; exit 1 ;;
esac
