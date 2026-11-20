#!/bin/bash
# ============================================================
#  MR VM INFO v1.0.0 — jekono VM / Linux terminal-e chalalei
#  oi machine-er IP, user, login info ekbare dekhabe.
#  by MR REAN (mr-rean-x) | https://github.com/mr-rean-x/MR-Ubuntu-Proot
#
#  ONE COMMAND (info dekhabe):
#    python3 -c "import urllib.request,os;urllib.request.urlretrieve('https://raw.githubusercontent.com/mr-rean-x/MR-Ubuntu-Proot/main/mr-vm-info.sh','mr-vm-info.sh');os.execv('/bin/bash',['bash','mr-vm-info.sh'])"
#
#  PASSWORD SET KORE DEKHATE (notun password banabe + dekhabe):
#    bash mr-vm-info.sh setpass [user]
#
#  DIRECT: bash mr-vm-info.sh [info|setpass [user]|help]
#
#  JA DEKHABE: public IP, private IP, hostname, OS, RAM/disk, current user,
#  sob login user, SSH status/port, environment (Railway / Render / KVM /
#  container), ar ready-to-copy login card: ssh user@ip
#
#  HONEST KOTHA (password niye):
#    Ager password KOKHONO dekha jay na — oita one-way hash hoye
#    /etc/shadow-te thake, kono command-e oita ber korte pare na.
#    Tai ei script password "dekhay" na — `setpass` diye NOTUN password
#    banay, ar tokhon IP + user + NOTUN password ekbare dekhay.
#    Railway-te kono VM password/IP thake na — Railway dey sudhu domain
#    (RAILWAY_PUBLIC_DOMAIN) — script-ta oitao dekhabe.
#
#  POSIX-safe: works pasted into /bin/sh (dash) too. Password kono file-e
#  lekha hoy na — sudhu ekbar screen-e dekhano hoy.
# ============================================================
# POSIX-safe: works even when pasted into /bin/sh (dash), which has no pipefail.
set -eu

VERSION="1.0.0-MR-VM-INFO"

# ---------- colours / logging (printf, NOT echo -e — dash breaks echo -e) ----------
CYAN='\033[0;36m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info()  { printf '%b\n' "${CYAN}[*]${NC} $*"; }
ok()    { printf '%b\n' "${GREEN}[+]${NC} $*"; }
warn()  { printf '%b\n' "${YELLOW}[!]${NC} $*"; }
error() { printf '%b\n' "${RED}[x]${NC} $*" >&2; }
die()   { error "$*"; exit 1; }

# ---------- helpers ----------
public_ip() {
    local ip=""
    if command -v curl >/dev/null 2>&1; then
        ip="$(curl -s --max-time 10 https://ifconfig.me 2>/dev/null || true)"
        [ -n "$ip" ] || ip="$(curl -s --max-time 10 https://ipinfo.io/ip 2>/dev/null || true)"
    fi
    if [ -z "$ip" ] && command -v wget >/dev/null 2>&1; then
        ip="$(wget -qO- --timeout=10 https://ifconfig.me 2>/dev/null || true)"
    fi
    if [ -z "$ip" ] && command -v python3 >/dev/null 2>&1; then
        ip="$(python3 -c "import urllib.request; print(urllib.request.urlopen('https://ifconfig.me', timeout=10).read().decode().strip())" 2>/dev/null || true)"
    fi
    case "$ip" in *.*) printf '%s' "$ip" ;; *) printf '' ;; esac
}
private_ips() {
    local ips=""
    if command -v hostname >/dev/null 2>&1; then ips="$(hostname -I 2>/dev/null || true)"; fi
    if [ -z "$ips" ] && command -v ip >/dev/null 2>&1; then
        ips="$(ip -4 addr show scope global 2>/dev/null | awk '/inet / {print $2}' | cut -d/ -f1 | tr '\n' ' ')"
    fi
    printf '%s' "$ips"
}
os_name() {
    if [ -f /etc/os-release ]; then
        grep -E '^PRETTY_NAME=' /etc/os-release | cut -d= -f2 | tr -d '"'
    else
        uname -s
    fi
}
virt_name() {
    if command -v systemd-detect-virt >/dev/null 2>&1; then
        systemd-detect-virt 2>/dev/null || echo "unknown"
    elif [ -f /.dockerenv ]; then echo "docker";
    elif [ -f /run/.containerenv ]; then echo "container";
    else echo "unknown"; fi
}
ask_secret() { # ask_secret <var> <prompt> — hidden input, POSIX (stty, not read -s)
    local _var="$1" _prompt="$2" _val=""
    printf '%s: ' "$_prompt"
    stty -echo 2>/dev/null || true
    read -r _val || { stty echo 2>/dev/null || true; die "Input closed."; }
    stty echo 2>/dev/null || true
    echo
    eval "$_var=\$_val"
}

# ---------- info ----------
do_info() {
    local pub_ip priv_ip host os virt user ram disk
    pub_ip="$(public_ip)"; priv_ip="$(private_ips)"
    host="$(hostname 2>/dev/null || echo "?")"
    os="$(os_name)"; virt="$(virt_name)"
    user="$(whoami 2>/dev/null || echo "?")"
    ram="$(awk '/MemTotal:/ {print int($2/1024)" MB"}' /proc/meminfo 2>/dev/null || echo "?")"
    disk="$(df -h / 2>/dev/null | tail -1 | awk '{print $4" free"}' || echo "?")"

    printf '%b\n' "${CYAN}============================================================${NC}"
    printf '%b\n' "${CYAN}   MR VM INFO  v${VERSION}${NC}"
    printf '%b\n' "${CYAN}============================================================${NC}"
    echo
    echo "  Hostname:    $host"
    echo "  OS:          $os"
    echo "  Kernel:      $(uname -r 2>/dev/null || echo '?')"
    echo "  Virtual:     $virt"
    echo "  Uptime:      $(uptime -p 2>/dev/null || uptime 2>/dev/null | sed 's/.*up *//;s/, *[0-9]* user.*//' || echo '?')"
    echo "  RAM:         $ram  |  Disk (/): $disk"
    echo
    echo "  Public IP:   ${pub_ip:-"(not found — no internet or blocked)"}"
    echo "  Private IP:  ${priv_ip:-"(none)"}"
    echo "  Current user: $user  (home: ${HOME:-?})"
    echo

    # --- environment: Railway / Render / others ---
    if [ -n "${RAILWAY_PUBLIC_DOMAIN:-}" ] || [ -n "${RAILWAY_SERVICE_NAME:-}" ]; then
        echo "  --- Railway ---"
        echo "  Service:     ${RAILWAY_SERVICE_NAME:-?}"
        echo "  Project:     ${RAILWAY_PROJECT_NAME:-?}"
        echo "  Environment: ${RAILWAY_ENVIRONMENT_NAME:-?}"
        echo "  Public URL:  https://${RAILWAY_PUBLIC_DOMAIN:-?}"
        warn "  Railway-te kono VM password / public IP thake na — access sudhu domain diye."
        echo
    fi
    if [ -n "${RENDER_SERVICE_NAME:-}" ] || [ -n "${RENDER:-}" ]; then
        echo "  --- Render ---"
        echo "  Service:     ${RENDER_SERVICE_NAME:-?}"
        warn "  Render-er free instance-e kono SSH password thake na — access dashboard diye."
        echo
    fi
    case "$virt" in
        docker|lxc|systemd-nspawn|openvz|podman)
            warn "  Eita ekta CONTAINER ($virt), asol VPS na — er kono nijer public IP/password nai."
            echo ;;
    esac

    # --- login users ---
    echo "  --- Login users (jara shell diye login korte pare) ---"
    if [ -r /etc/passwd ]; then
        awk -F: '$7 ~ /(ba)?sh$/ && $1 != "nobody" {print "  " $1 "  (uid " $3 ", " $7 ")"}' /etc/passwd
    else
        echo "  (cannot read /etc/passwd)"
    fi
    echo

    # --- SSH ---
    echo "  --- SSH ---"
    local ssh_port="22" sshd_on="no"
    if [ -f /etc/ssh/sshd_config ]; then
        ssh_port="$(grep -E '^Port ' /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}')"
        [ -n "$ssh_port" ] || ssh_port="22"
    fi
    if command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet ssh 2>/dev/null; then sshd_on="yes (ssh)";
    elif command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet sshd 2>/dev/null; then sshd_on="yes (sshd)";
    elif command -v pgrep >/dev/null 2>&1 && pgrep -x sshd >/dev/null 2>&1; then sshd_on="yes";
    fi
    echo "  SSH service: $sshd_on  |  Port: $ssh_port"
    echo

    # --- login card ---
    echo "  ================= LOGIN CARD ================="
    if [ -n "$pub_ip" ]; then
        echo "  IP:       $pub_ip"
        echo "  User:     $user"
        echo "  SSH:      ssh $user@$pub_ip -p $ssh_port"
    elif [ -n "$priv_ip" ]; then
        echo "  IP:       $(printf '%s' "$priv_ip" | awk '{print $1}')  (private — same network theke)"
        echo "  User:     $user"
        echo "  SSH:      ssh $user@$(printf '%s' "$priv_ip" | awk '{print $1}') -p $ssh_port"
    else
        echo "  IP khuje pawa jay nai — internet check koro."
    fi
    echo "  Password: (ager password dekha jay na — hash kora thake)"
    echo "            Notun password set korte: bash mr-vm-info.sh setpass"
    echo "  ============================================"
}

# ---------- setpass ----------
do_setpass() {
    local target="${1:-}"
    [ "$(id -u)" = "0" ] || die "setpass needs root (sudo -i first) — naile nijer password bodlate 'passwd' chalao."
    if [ -z "$target" ]; then
        printf 'User (khali rakhle current user: %s): ' "$(whoami)"
        read -r target || die "Input closed."
        [ -z "$target" ] && target="$(whoami)"
    fi
    id "$target" >/dev/null 2>&1 || die "User '$target' nai — age user banaw: useradd -m $target"
    local p1="" p2=""
    ask_secret p1 "New password for $target (hidden)"
    [ -n "$p1" ] || die "Khali password cholbe na."
    ask_secret p2 "Type it again"
    [ "$p1" = "$p2" ] || die "Passwords do not match — abar chalao."
    printf '%s:%s\n' "$target" "$p1" | chpasswd || die "Password set korte pari nai."
    p1=""; p2=""
    local pub_ip priv_ip ssh_port
    pub_ip="$(public_ip)"; priv_ip="$(private_ips)"
    ssh_port="22"
    if [ -f /etc/ssh/sshd_config ]; then
        ssh_port="$(grep -E '^Port ' /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}')"
        [ -n "$ssh_port" ] || ssh_port="22"
    fi
    echo
    ok "Password set for $target. (Password kono file-e lekha hoy nai.)"
    echo
    echo "  ================= LOGIN CARD ================="
    if [ -n "$pub_ip" ]; then
        echo "  IP:       $pub_ip"
    elif [ -n "$priv_ip" ]; then
        echo "  IP:       $(printf '%s' "$priv_ip" | awk '{print $1}')  (private)"
    else
        echo "  IP:       (not found)"
    fi
    echo "  User:     $target"
    echo "  Password: (tumi ja dile — upre mone rakho, ar dekhano hobe na)"
    if [ -n "$pub_ip" ]; then
        echo "  SSH:      ssh $target@$pub_ip -p $ssh_port"
    fi
    echo "  ============================================"
}

show_help() {
    printf '%b\n' "${CYAN}MR VM INFO v${VERSION}${NC}"
    echo
    echo "Usage: bash mr-vm-info.sh [command]"
    echo
    echo "  (no command)  Show this machine's IP, user, login info"
    echo "  info          Same as above"
    echo "  setpass [user]  Set a NEW password for user (root only), then"
    echo "                  show the login card (IP + user + new password)"
    echo "  help          This help"
    echo
    echo "Note: an OLD password can never be shown — it is stored as a"
    echo "one-way hash in /etc/shadow. setpass makes a new one instead."
}

# ---------- main ----------
MODE="${1:-info}"
case "$MODE" in
    info|"") do_info ;;
    setpass) do_setpass "${2:-}" ;;
    help|--help|-h) show_help ;;
    *) error "Unknown command: $MODE"; show_help; exit 1 ;;
esac
