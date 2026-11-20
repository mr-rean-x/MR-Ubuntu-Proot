#!/bin/bash
# ============================================================
#  MR VPS POWER v1.0.0 — Docker / Privileged / Kernel /
#  Networking / Systemd / KVM — check + setup in ONE command
#  by MR REAN (mr-rean-x) | https://github.com/mr-rean-x/MR-Ubuntu-Proot
#
#  ONE COMMAND (paste this, get the full report + setup):
#    python3 -c "import urllib.request,os;urllib.request.urlretrieve('https://raw.githubusercontent.com/mr-rean-x/MR-Ubuntu-Proot/main/mr-vps-power.sh','mr-vps-power.sh');os.execv('/bin/bash',['bash','mr-vps-power.sh','install'])"
#
#  OR check only (nothing installed, safe anywhere):
#    bash mr-vps-power.sh check
#
#  HONEST LIMITS — read this before you run it:
#    - Privileged / Kernel / KVM are decided by the HOST (the provider),
#      not by any command inside. If the host did not give your VPS
#      CAP_SYS_ADMIN, /dev/kvm or module loading, NO script can create
#      them from inside — that would be breaking out of the container,
#      and this script does NOT do exploits. It installs everything
#      that IS possible and tells you plainly what is blocked and why.
#    - On a REAL root VPS (KVM VPS with root): Docker + systemd +
#      networking + KVM all set up by this one script.
#    - On free container hosts (Render / Jupyter / Altare sandbox):
#      Docker daemon, systemd-as-PID-1 and KVM stay BLOCKED by the
#      host. What you CAN get there: rootless Podman (if user
#      namespaces are on), networking tools, and a true report.
#
#  COMMANDS: check | install (default) | docker | kvm | network | systemd | kernel | help
#  POSIX-safe: works pasted into /bin/sh (dash) too. No exploits, ever.
# ============================================================
# POSIX-safe: works even when pasted into /bin/sh (dash), which has no pipefail.
set -eu

VERSION="1.0.0-MR-POWER"
CMD="${1:-install}"
# NOTE: plain `shift || true` kills dash (shift is a special builtin).
if [ $# -gt 0 ]; then shift; fi

# ---------- colours / logging (printf, NOT echo -e — dash breaks echo -e) ----------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()  { printf '%b\n' "${CYAN}[*]${NC} $*"; }
ok()    { printf '%b\n' "${GREEN}[+]${NC} $*"; }
warn()  { printf '%b\n' "${YELLOW}[!]${NC} $*"; }
error() { printf '%b\n' "${RED}[x]${NC} $*" >&2; }
good()  { printf '%b\n' "  ${GREEN}OK${NC}  $*"; }
bad()   { printf '%b\n' "  ${RED}NO${NC}  $*"; }
part()  { printf '%b\n' "  ${YELLOW}HALF${NC} $*"; }

# ---------- results (filled by checks) ----------
R_DOCKER="?"; R_PRIV="?"
R_KERNEL="?"; R_NET="?"
R_SYSTEMD="?"; R_KVM="?"
NOTE_DOCKER=""; NOTE_PRIV=""; NOTE_KERNEL=""
NOTE_NET=""; NOTE_SYSTEMD=""; NOTE_KVM=""

# ---------- sudo handling ----------
if [ "$(id -u)" = "0" ]; then
    SUDO=""
    IS_ROOT=1
else
    IS_ROOT=0
    if command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
        SUDO="sudo"
    else
        SUDO=""
    fi
fi

# ---------- capability check (reads CapEff, tests one bit) ----------
# bit numbers: CAP_SYS_ADMIN=21, CAP_NET_ADMIN=12, CAP_SYS_MODULE=16
has_cap() {
    local bit="$1" caps hex val
    caps="$(grep -E '^CapEff:' /proc/self/status 2>/dev/null | awk '{print $2}' || true)"
    [ -n "$caps" ] || return 1
    # strip leading zeros safely for arithmetic
    hex="$(printf '%s' "$caps" | sed 's/^0*//')"
    [ -n "$hex" ] || hex="0"
    val=$((0x$hex)) 2>/dev/null || return 1
    [ $((val & (1 << bit))) -ne 0 ]
}

is_container() {
    [ -f /.dockerenv ] || [ -f /run/.containerenv ] && return 0
    if command -v systemd-detect-virt >/dev/null 2>&1; then
        [ "$(systemd-detect-virt 2>/dev/null || echo none)" != "none" ] && return 0
    fi
    grep -q -E "docker|lxc|kubepods" /proc/self/cgroup 2>/dev/null && return 0
    return 1
}

# BUG FIX: apt without timeouts hung the whole install for 300s on a
# slow/blocked mirror. Every apt call is now time-boxed and fail-fast,
# and apt-get update runs only once per script run.
APT_OPTS="-o Acquire::http::Timeout=20 -o Acquire::https::Timeout=20 -o Acquire::Retries=1"
with_timeout() {
    local secs="$1"; shift
    if command -v timeout >/dev/null 2>&1; then
        timeout "$secs" "$@"
    else
        "$@"
    fi
}

apt_install() {
    # apt_install <pkgs...> — guarded: never kills the script on failure
    if ! command -v apt-get >/dev/null 2>&1; then
        warn "apt-get not found (not Ubuntu/Debian?) — cannot install $*"
        return 1
    fi
    if [ -z "$SUDO" ] && [ "$IS_ROOT" = "0" ]; then
        warn "Not root and no sudo — cannot install $*"
        return 1
    fi
    if [ ! -f /tmp/mr-apt-updated ]; then
        if with_timeout 180 $SUDO apt-get $APT_OPTS update -y >/tmp/mr-apt.log 2>&1; then
            rm -f /tmp/mr-apt-update-failed
        else
            warn "apt-get update failed/timed out — check network/proxy (see /tmp/mr-apt.log)"
            touch /tmp/mr-apt-update-failed
        fi
        touch /tmp/mr-apt-updated
    fi
    with_timeout 600 $SUDO apt-get $APT_OPTS install -y "$@" >>/tmp/mr-apt.log 2>&1 || { warn "apt install failed for: $* (see /tmp/mr-apt.log)"; return 1; }
    return 0
}

# ============================================================
#  1. PRIVILEGED ACCESS — detect only. Nothing inside can grant
#     itself capabilities the host did not give it.
# ============================================================
check_privileged() {
    info "Checking privileged access..."
    local caps=""
    has_cap 21 && caps="$caps SYS_ADMIN"
    has_cap 12 && caps="$caps NET_ADMIN"
    has_cap 16 && caps="$caps SYS_MODULE"
    if [ "$IS_ROOT" = "1" ] && has_cap 21; then
        if is_container; then
            R_PRIV="HALF"; NOTE_PRIV="root + SYS_ADMIN inside a CONTAINER (host gave caps). Real privileges, but still inside the host's container."
        else
            R_PRIV="OK"; NOTE_PRIV="root + SYS_ADMIN on a real machine/VM. Full privileges."
        fi
    elif [ "$IS_ROOT" = "1" ]; then
        R_PRIV="HALF"; NOTE_PRIV="uid 0 but NO SYS_ADMIN — fake root (proot / user namespace). Host keeps real privileges."
    else
        R_PRIV="NO"; NOTE_PRIV="not root (uid $(id -u)). No sudo. Only user-level tools possible."
    fi
    printf '%b\n' "  caps:${caps:- (none of SYS_ADMIN/NET_ADMIN/SYS_MODULE)}"
    printf '%b\n' "  root: $([ "$IS_ROOT" = "1" ] && echo yes || echo no) | container: $(is_container && echo yes || echo no) | PID1: $(cat /proc/1/comm 2>/dev/null || echo ?)"
    [ "$R_PRIV" = "OK" ] && good "Privileged: $NOTE_PRIV" || { [ "$R_PRIV" = "HALF" ] && part "Privileged: $NOTE_PRIV" || bad "Privileged: $NOTE_PRIV"; }
}

# ============================================================
#  2. DOCKER — install docker.io, start daemon, fallback rootless
#     Docker / Podman. Daemon needs SYS_ADMIN; without it only
#     rootless mode can work (needs user namespaces).
# ============================================================
check_docker() {
    if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
        R_DOCKER="OK"; NOTE_DOCKER="Docker daemon is running: $(docker --version 2>/dev/null)"
        good "Docker: $NOTE_DOCKER"
    elif command -v podman >/dev/null 2>&1 && podman info >/dev/null 2>&1; then
        R_DOCKER="HALF"; NOTE_DOCKER="No Docker daemon, but Podman works: $(podman --version 2>/dev/null)"
        part "Docker: $NOTE_DOCKER"
    elif command -v docker >/dev/null 2>&1; then
        R_DOCKER="NO"; NOTE_DOCKER="docker binary exists but daemon is NOT running."
        bad "Docker: $NOTE_DOCKER"
    else
        R_DOCKER="NO"; NOTE_DOCKER="Docker is not installed."
        bad "Docker: $NOTE_DOCKER"
    fi
}

install_docker() {
    info "Setting up Docker..."
    check_docker
    [ "$R_DOCKER" = "OK" ] && { ok "Docker already running — nothing to do."; return 0; }
    if [ "$IS_ROOT" = "0" ] && [ -z "$SUDO" ]; then
        warn "Not root — cannot install Docker. Use a root VPS, or ask the host for root."
        R_DOCKER="NO"; NOTE_DOCKER="install needs root."
        return 0
    fi
    apt_install docker.io || warn "docker.io install failed — trying Podman as fallback."
    # Try to start the daemon
    if [ "$(cat /proc/1/comm 2>/dev/null)" = "systemd" ]; then
        $SUDO systemctl enable --now docker >/dev/null 2>&1 || warn "systemctl start docker failed."
    elif has_cap 21; then
        info "No systemd as PID 1 — starting dockerd directly (vfs driver)..."
        $SUDO mkdir -p /var/run/docker /var/lib/docker
        nohup $SUDO dockerd --storage-driver=vfs >/tmp/dockerd.log 2>&1 &
        sleep 5
    else
        warn "No systemd and no SYS_ADMIN — normal Docker daemon cannot start here."
    fi
    sleep 2
    if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
        R_DOCKER="OK"; NOTE_DOCKER="Docker daemon running: $(docker --version 2>/dev/null)"
        ok "Docker is running."
        with_timeout 180 docker run --rm hello-world >/tmp/docker-test.log 2>&1 && ok "docker run hello-world: WORKS" || warn "daemon runs but hello-world pull failed/timed out (network?) — daemon itself is up."
        return 0
    fi
    # Fallback: rootless Podman (needs user namespaces)
    info "Docker daemon did not start — trying rootless Podman fallback..."
    if [ "$(cat /proc/sys/kernel/unprivileged_userns_clone 2>/dev/null || echo 0)" = "1" ] || [ "$(cat /proc/sys/user/max_user_namespaces 2>/dev/null || echo 0)" != "0" ]; then
        apt_install podman || true
        if command -v podman >/dev/null 2>&1 && with_timeout 180 podman run --rm docker.io/library/hello-world >/tmp/podman-test.log 2>&1; then
            R_DOCKER="HALF"; NOTE_DOCKER="Docker daemon blocked by host, but rootless Podman WORKS — use podman instead of docker."
            ok "Podman works (rootless)."
            return 0
        fi
    fi
    R_DOCKER="NO"
    # BUG FIX: the old message blamed the host even when apt itself failed
    # (e.g. proxy blocks the mirror -> "Unable to locate package docker.io").
    # Say which one it really was.
    if ! command -v docker >/dev/null 2>&1 && ! command -v podman >/dev/null 2>&1; then
        NOTE_DOCKER="apt could NOT download docker.io or podman on this machine (apt update failed — proxy/network, see /tmp/mr-apt.log). This does NOT mean the host blocks Docker — the packages just could not be fetched here. Retry where apt works, or install Docker from download.docker.com."
    else
        NOTE_DOCKER="Docker daemon cannot run here — host blocks it (no SYS_ADMIN / no systemd). A real root VPS is needed for Docker."
    fi
    warn "Docker: $NOTE_DOCKER"
}

# ============================================================
#  3. KERNEL ACCESS — module loading + /dev/kvm
# ============================================================
check_kernel() {
    info "Checking kernel access..."
    local kver
    kver="$(uname -r)"
    printf '%b\n' "  kernel: $kver | modules dir: $([ -d "/lib/modules/$kver" ] && echo yes || echo MISSING)"
    if has_cap 16 && [ -d "/lib/modules/$kver" ]; then
        R_KERNEL="OK"; NOTE_KERNEL="CAP_SYS_MODULE + modules present — can load kernel modules (own kernel)."
        good "Kernel: $NOTE_KERNEL"
    elif has_cap 16; then
        R_KERNEL="HALF"; NOTE_KERNEL="CAP_SYS_MODULE yes, but /lib/modules/$kver missing — module loading will mostly fail."
        part "Kernel: $NOTE_KERNEL"
    else
        R_KERNEL="NO"; NOTE_KERNEL="No CAP_SYS_MODULE — host blocks module loading. Kernel is the host's, you cannot change it from inside."
        bad "Kernel: $NOTE_KERNEL"
    fi
}

check_kvm() {
    info "Checking KVM..."
    if [ -e /dev/kvm ]; then
        R_KVM="OK"; NOTE_KVM="/dev/kvm exists — KVM available. $(ls -l /dev/kvm 2>/dev/null)"
        good "KVM: $NOTE_KVM"
        return 0
    fi
    if ! grep -Eq 'vmx|svm' /proc/cpuinfo 2>/dev/null; then
        R_KVM="NO"; NOTE_KVM="CPU has NO vmx/svm flag — host does not expose virtualization. Enable nested virt in the provider panel, or use a KVM VPS that supports it. No command inside can create this."
        bad "KVM: $NOTE_KVM"
        return 0
    fi
    # CPU supports it, but /dev/kvm missing — try loading the module (real VM only)
    if [ "$IS_ROOT" = "1" ] && has_cap 16; then
        if grep -q ' vmx ' /proc/cpuinfo 2>/dev/null || grep -q vmx /proc/cpuinfo 2>/dev/null; then
            $SUDO modprobe kvm_intel 2>/dev/null || true
        else
            $SUDO modprobe kvm_amd 2>/dev/null || true
        fi
        $SUDO modprobe kvm 2>/dev/null || true
        sleep 1
        if [ -e /dev/kvm ]; then
            R_KVM="OK"; NOTE_KVM="/dev/kvm created after loading kvm module."
            good "KVM: $NOTE_KVM"
            return 0
        fi
    fi
    R_KVM="NO"; NOTE_KVM="CPU supports virt, but /dev/kvm is NOT exposed — host/container blocks the device. On containers: start with --device=/dev/kvm (host-side). On a VPS: enable nested virt in the provider panel."
    bad "KVM: $NOTE_KVM"
}

# ============================================================
#  4. NETWORKING — tools + IP forwarding + iptables
# ============================================================
check_network() {
    info "Checking networking..."
    local fwd="?"
    fwd="$(cat /proc/sys/net/ipv4/ip_forward 2>/dev/null || echo ?)"
    printf '%b\n' "  ip_forward: $fwd | tools: ip=$(command -v ip >/dev/null && echo yes || echo no) iptables=$(command -v iptables >/dev/null && echo yes || echo no) nft=$(command -v nft >/dev/null && echo yes || echo no) curl=$(command -v curl >/dev/null && echo yes || echo no)"
    if command -v iptables >/dev/null 2>&1 && iptables -L >/dev/null 2>&1; then
        R_NET="OK"; NOTE_NET="iptables works, forwarding value: $fwd."
        good "Networking: $NOTE_NET"
    elif command -v ip >/dev/null 2>&1; then
        R_NET="HALF"; NOTE_NET="basic tools work, but iptables rules cannot be changed (host firewall is the host's)."
        part "Networking: $NOTE_NET"
    else
        R_NET="NO"; NOTE_NET="no networking tools found."
        bad "Networking: $NOTE_NET"
    fi
}

install_network() {
    info "Setting up networking..."
    apt_install iproute2 iptables nftables curl wget dnsutils || true
    if [ "$IS_ROOT" = "1" ] && has_cap 12; then
        sysctl -w net.ipv4.ip_forward=1 >/dev/null 2>&1 && ok "IP forwarding enabled." || warn "Cannot write /proc/sys — host keeps sysctls read-only."
        sysctl -w net.bridge.bridge-nf-call-iptables=1 >/dev/null 2>&1 || true
    else
        warn "Not root / no NET_ADMIN — cannot change sysctls or firewall."
    fi
    check_network
}

# ============================================================
#  5. SYSTEMD — PID 1 cannot be replaced from inside a container.
# ============================================================
check_systemd() {
    info "Checking systemd..."
    if [ "$(cat /proc/1/comm 2>/dev/null)" = "systemd" ]; then
        R_SYSTEMD="OK"; NOTE_SYSTEMD="systemd IS PID 1: $(systemctl is-system-running 2>/dev/null || echo unknown)."
        good "Systemd: $NOTE_SYSTEMD"
    elif command -v systemctl >/dev/null 2>&1; then
        R_SYSTEMD="NO"; NOTE_SYSTEMD="systemctl exists but PID 1 is '$(cat /proc/1/comm 2>/dev/null)' — systemd is NOT running. PID 1 is fixed when the container/VM starts; it CANNOT be changed from inside. Host-side fix: start the container with /sbin/init (docker run --privileged -v /sys/fs/cgroup:/sys/fs/cgroup:ro IMAGE /sbin/init) or boot a real VM (systemd is PID 1 there by default)."
        bad "Systemd: $NOTE_SYSTEMD"
    else
        R_SYSTEMD="NO"; NOTE_SYSTEMD="no systemd installed. On Ubuntu/Debian: apt install systemd — but it still only runs if PID 1 is systemd (see above)."
        bad "Systemd: $NOTE_SYSTEMD"
    fi
}

# ---------- final report ----------
report() {
    echo
    echo "============================================"
    echo "       MR VPS POWER — FINAL REPORT"
    echo "============================================"
    printf '%-11s %s\n' "Docker:"     "$R_DOCKER — $NOTE_DOCKER"
    printf '%-11s %s\n' "Privileged:" "$R_PRIV — $NOTE_PRIV"
    printf '%-11s %s\n' "Kernel:"     "$R_KERNEL — $NOTE_KERNEL"
    printf '%-11s %s\n' "Networking:" "$R_NET — $NOTE_NET"
    printf '%-11s %s\n' "Systemd:"    "$R_SYSTEMD — $NOTE_SYSTEMD"
    printf '%-11s %s\n' "KVM:"        "$R_KVM — $NOTE_KVM"
    echo
    if [ "$R_DOCKER" = "NO" ] || [ "$R_KVM" = "NO" ] || [ "$R_SYSTEMD" = "NO" ]; then
        echo "What is blocked is blocked BY THE HOST, not by this script."
        echo "To get all six: use a real KVM VPS with root (not a free"
        echo "container host) and enable nested virt in its panel."
    else
        echo "All six green — this VPS has full power."
    fi
}

show_help() {
    echo "MR VPS POWER v$VERSION"
    echo "Usage: bash mr-vps-power.sh <command>"
    echo
    echo "  check      Report only — install nothing (safe anywhere)"
    echo "  install    Check + install everything possible (default)"
    echo "  docker     Docker only (install + start + Podman fallback)"
    echo "  kvm        KVM only (check + try loading kvm module)"
    echo "  network    Networking only (tools + forwarding + iptables test)"
    echo "  systemd    Systemd only (report — PID 1 cannot change from inside)"
    echo "  kernel     Kernel access only (module loading check)"
    echo "  help       This help"
}

do_check() {
    check_privileged
    check_docker
    check_kernel
    check_network
    check_systemd
    check_kvm
    report
}

do_install() {
    echo "============================================"
    echo "       MR VPS POWER v$VERSION"
    echo "============================================"
    check_privileged
    install_docker
    check_kernel
    install_network
    check_systemd
    check_kvm
    report
}

case "$CMD" in
    check)   do_check ;;
    install) do_install ;;
    docker)  check_privileged; install_docker; report ;;
    kvm)     check_privileged; check_kernel; check_kvm; report ;;
    network) check_privileged; install_network; report ;;
    systemd) check_privileged; check_systemd; report ;;
    kernel)  check_privileged; check_kernel; report ;;
    help|--help|-h) show_help ;;
    *) error "Unknown command: $CMD"; show_help; exit 1 ;;
esac
