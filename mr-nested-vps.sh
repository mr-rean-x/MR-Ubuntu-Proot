#!/bin/bash
# ============================================================
#  MR NESTED VPS v2.0.0 — VPS-er vitore VPS banao (QEMU/KVM)
#  by MR REAN (mr-rean-x) | https://github.com/mr-rean-x/MR-Ubuntu-Proot
#
#  ONE COMMAND — MAKE a VPS (v2, main mode — 4ta proshno, KVM thakuk ar na thakuk):
#    python3 -c "import urllib.request,os;urllib.request.urlretrieve('https://raw.githubusercontent.com/mr-rean-x/MR-Ubuntu-Proot/main/mr-nested-vps.sh','mr-nested-vps.sh');os.execv('/bin/bash',['bash','mr-nested-vps.sh','make'])"
#
#  OR check first if this host CAN make nested VPS:
#    bash mr-nested-vps.sh check
#
#  CREATE a nested VPS (Ubuntu 22.04 cloud image):
#    bash mr-nested-vps.sh create myvps1 2048 20 2
#    #                     ^name  ^RAM MB ^disk GB ^CPUs
#    # login: user mrrean / password mrrean  (change with --password)
#
#  COMMANDS:
#    make | check | create <name> <ramMB> <diskGB> <cpus> [--emulate] [--password P] [--image URL]
#    list | start <name> | stop <name> | delete <name> [--yes] | console <name> | help
#
#  HONEST LIMITS — please read:
#    - "Joto iccha RAM/CPU" is NOT real. A nested VPS shares the HOST's
#      real RAM/disk/CPU. Host-e 6GB RAM thakle sob nested VPS miliye
#      6GB-er beshi dite parba na — script-ta hiseb kore na dile
#      refuse korbe (exact number soho).
#    - KVM thakle FAST (real virtualization). KVM NA thakle MAKE
#      auto TCG emulation use kore — VPS banano JABE, kintu 10-20x
#      slow, boot-e 10+ min lagte pare, real use-er jonno na.
#      Free container hosts (Render / Jupyter / Altare sandbox)-eo
#      TCG-e VPS banano jay — slow, testing only.
#    - No exploits: only legitimate host-provided virtualization
#      (KVM) or pure software emulation (TCG).
#
#  POSIX-safe: works pasted into /bin/sh (dash) too.
# ============================================================
# POSIX-safe: works even when pasted into /bin/sh (dash), which has no pipefail.
set -eu

VERSION="2.0.0-MR-NESTED"
CMD="${1:-check}"
# NOTE: plain `shift || true` kills dash (shift is a special builtin).
if [ $# -gt 0 ]; then shift; fi

VM_DIR="${VM_DIR:-$HOME/mr-vms}"
# BUG FIX: df on a not-yet-created VM_DIR returns nothing, so "Disk free"
# printed empty and the guard computed -2GB. Create the dir first.
mkdir -p "$VM_DIR" "$VM_DIR/images" 2>/dev/null || true
IMAGE_URL_DEFAULT="https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img"
IMAGE_NAME_DEFAULT="ubuntu-22.04-cloudimg-amd64.img"

# ---------- colours / logging (printf, NOT echo -e — dash breaks echo -e) ----------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()  { printf '%b\n' "${CYAN}[*]${NC} $*"; }
ok()    { printf '%b\n' "${GREEN}[+]${NC} $*"; }
warn()  { printf '%b\n' "${YELLOW}[!]${NC} $*"; }
error() { printf '%b\n' "${RED}[x]${NC} $*" >&2; }
die()   { error "$*"; exit 1; }
good()  { printf '%b\n' "  ${GREEN}OK${NC}  $*"; }
bad()   { printf '%b\n' "  ${RED}NO${NC}  $*"; }

# ---------- sudo / root ----------
if [ "$(id -u)" = "0" ]; then SUDO=""; IS_ROOT=1;
elif command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then SUDO="sudo"; IS_ROOT=0;
else SUDO=""; IS_ROOT=0; fi

has_cap() {
    local bit="$1" caps hex val
    caps="$(grep -E '^CapEff:' /proc/self/status 2>/dev/null | awk '{print $2}' || true)"
    [ -n "$caps" ] || return 1
    hex="$(printf '%s' "$caps" | sed 's/^0*//')"
    [ -n "$hex" ] || hex="0"
    val=$((0x$hex)) 2>/dev/null || return 1
    [ $((val & (1 << bit))) -ne 0 ]
}

# ---------- download (wget -> curl -> python3) ----------
download_file() {
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
        warn "Download try $tries/5 failed — retrying..."
        sleep 3
    done
    return 1
}

# ---------- apt (time-boxed, update once) ----------
APT_OPTS="-o Acquire::http::Timeout=20 -o Acquire::https::Timeout=20 -o Acquire::Retries=1"
with_timeout() {
    local secs="$1"; shift
    if command -v timeout >/dev/null 2>&1; then timeout "$secs" "$@"; else "$@"; fi
}
apt_install() {
    if ! command -v apt-get >/dev/null 2>&1; then warn "apt-get not found (not Ubuntu/Debian?)"; return 1; fi
    if [ -z "$SUDO" ] && [ "$IS_ROOT" = "0" ]; then warn "Not root and no sudo — cannot install $*"; return 1; fi
    if [ ! -f /tmp/mr-apt-updated ]; then
        if with_timeout 180 $SUDO apt-get $APT_OPTS update -y >/tmp/mr-apt.log 2>&1; then
            rm -f /tmp/mr-apt-update-failed
        else
            warn "apt-get update failed/timed out (see /tmp/mr-apt.log)"
            touch /tmp/mr-apt-update-failed
        fi
        touch /tmp/mr-apt-updated
    fi
    with_timeout 600 $SUDO apt-get $APT_OPTS install -y "$@" >>/tmp/mr-apt.log 2>&1 || { warn "apt install failed for: $* (see /tmp/mr-apt.log)"; return 1; }
    return 0
}

# ---------- host resources (MB / GB / CPUs) ----------
# Env overrides (advanced): MR_RAM_MB / MR_DISK_GB — useful when /proc/meminfo
# shows the HOST's memory but a container/cgroup limit is lower, and for tests.
host_ram_avail_mb() {
    [ -n "${MR_RAM_MB:-}" ] && { echo "$MR_RAM_MB"; return; }
    awk '/MemAvailable:/ {print int($2/1024)}' /proc/meminfo 2>/dev/null || echo 0
}
host_disk_avail_gb() {
    [ -n "${MR_DISK_GB:-}" ] && { echo "$MR_DISK_GB"; return; }
    local v
    v="$(df -k --output=avail "$VM_DIR" 2>/dev/null | tail -1 | awk '{print int($1/1024/1024)}')"
    [ -n "$v" ] || v=0
    echo "$v"
}
host_cpus() { nproc 2>/dev/null || grep -c ^processor /proc/cpuinfo 2>/dev/null || echo 1; }
used_ram_mb() {
    local sum=0 v
    for f in "$VM_DIR"/*/vm.conf; do
        [ -f "$f" ] || continue
        v="$(grep -E '^RAM=' "$f" 2>/dev/null | cut -d= -f2 || echo 0)"
        sum=$((sum + v))
    done
    echo "$sum"
}
used_disk_gb() {
    local sum=0 v
    for f in "$VM_DIR"/*/vm.conf; do
        [ -f "$f" ] || continue
        v="$(grep -E '^DISK=' "$f" 2>/dev/null | cut -d= -f2 || echo 0)"
        sum=$((sum + v))
    done
    echo "$sum"
}

has_kvm_cpu() { grep -Eq 'vmx|svm' /proc/cpuinfo 2>/dev/null; }
has_kvm_dev() { [ -e /dev/kvm ]; }

# ============================================================
#  CHECK — can this host make nested VPS?
# ============================================================
do_check() {
    echo "============================================"
    echo "       MR NESTED VPS — HOST CHECK"
    echo "============================================"
    local ram disk cpus maxram maxdisk
    ram="$(host_ram_avail_mb)"; disk="$(host_disk_avail_gb)"; cpus="$(host_cpus)"
    printf '%b\n' "Host RAM free: ${ram} MB | Disk free: ${disk} GB | CPUs: ${cpus}"
    echo
    if has_kvm_cpu; then good "CPU has vmx/svm flag — virtualization exposed."; else bad "CPU has NO vmx/svm flag — host does NOT expose virtualization."; fi
    if has_kvm_dev; then good "/dev/kvm exists — KVM ready."; else bad "/dev/kvm missing."; fi
    if command -v qemu-system-x86_64 >/dev/null 2>&1; then good "qemu-system-x86_64: $(qemu-system-x86_64 --version 2>/dev/null | head -1)"; else bad "qemu-system-x86_64 NOT installed."; fi
    if command -v virsh >/dev/null 2>&1; then good "virsh (libvirt) installed."; else bad "virsh NOT installed (optional — plain QEMU fallback exists)."; fi
    if command -v cloud-localds >/dev/null 2>&1; then good "cloud-localds (cloud-init seed) installed."; else bad "cloud-localds NOT installed."; fi
    echo
    maxram=$((ram - 512)); [ "$maxram" -lt 512 ] && maxram=0
    maxdisk=$((disk - 2)); [ "$maxdisk" -lt 1 ] && maxdisk=0
    echo "Biggest single nested VPS you can make here:"
    echo "  RAM: ${maxram} MB | Disk: ${maxdisk} GB | CPUs: ${cpus} (keep 1 for host)"
    echo "  (512MB RAM + 2GB disk kept for the host itself)"
    echo
    if has_kvm_cpu && has_kvm_dev; then
        ok "THIS HOST CAN MAKE NESTED VPS. Example:"
        echo "  bash mr-nested-vps.sh create myvps1 2048 20 2"
    elif has_kvm_cpu; then
        warn "CPU supports it but /dev/kvm is missing — try: sudo modprobe kvm_intel (or kvm_amd), or enable it in the provider panel."
    else
        warn "THIS HOST CANNOT MAKE NESTED VPS (real KVM). It is a container, or nested virt is off in the provider panel."
        echo "  What works instead: proot Ubuntu (mr-root.sh) or containers — but those are NOT real VPS with their own kernel."
        echo "  With --emulate you can still boot a VM in pure software emulation (10-20x slower, testing only)."
    fi
}

# ---------- start plain-QEMU VM (used by create AND start) ----------
# start_qemu <name> <ram> <cpus> <diskfile> <seediso> <port> <accel>
start_qemu() {
    local _n="$1" _ram="$2" _cpus="$3" _disk="$4" _seed="$5" _port="$6" _accel="$7"
    local _flag="-enable-kvm"
    [ "$_accel" = "tcg" ] && _flag="-accel tcg"
    $SUDO qemu-system-x86_64 -name "$_n" $_flag -m "$_ram" -smp "$_cpus" \
        -drive file="$_disk",if=virtio,format=qcow2 \
        -cdrom "$_seed" \
        -netdev user,id=net0,hostfwd=tcp::"$_port"-:22 \
        -device virtio-net-pci,netdev=net0 \
        -display none -daemonize \
        -pidfile "$VM_DIR/$_n/qemu.pid" \
        -serial file:"$VM_DIR/$_n/console.log" \
        -monitor unix:"$VM_DIR/$_n/monitor.sock",server,nowait
}

# ============================================================
#  CREATE — the main event
# ============================================================
do_create() {
    local NAME="$1" RAM="$2" DISK="$3" CPUS="$4"; shift 4
    local EMULATE=0 PASSWORD="mrrean" IMAGE_URL="$IMAGE_URL_DEFAULT"
    while [ $# -gt 0 ]; do
        case "$1" in
            --emulate)  EMULATE=1; shift ;;
            --password) PASSWORD="$2"; shift 2 ;;
            --image)    IMAGE_URL="$2"; shift 2 ;;
            *) die "Unknown option: $1 (see: bash mr-nested-vps.sh help)" ;;
        esac
    done
    case "$NAME" in
        *[!A-Za-z0-9_-]*|"") die "Bad VM name '$NAME' — use letters, numbers, - and _ only." ;;
    esac
    case "$RAM$DISK$CPUS" in
        *[!0-9]*) die "RAM / disk / CPUs must be numbers: create <name> <ramMB> <diskGB> <cpus>" ;;
    esac
    [ "$RAM" -ge 512 ] 2>/dev/null || die "RAM must be at least 512 MB."
    [ "$DISK" -ge 5 ] 2>/dev/null || die "Disk must be at least 5 GB."
    [ "$CPUS" -ge 1 ] 2>/dev/null || die "CPUs must be at least 1."
    [ -d "$VM_DIR/$NAME" ] && die "VM '$NAME' already exists — delete it first or pick another name."

    echo "============================================"
    echo "       CREATING NESTED VPS: $NAME"
    echo "       RAM ${RAM}MB | Disk ${DISK}GB | CPUs ${CPUS}"
    echo "============================================"

    # --- STEP 1: resource guard (TOTAL across all VMs must fit the host) ---
    local ram_av disk_av cpus_n used_r used_d free_r free_d
    ram_av="$(host_ram_avail_mb)"; disk_av="$(host_disk_avail_gb)"; cpus_n="$(host_cpus)"
    used_r="$(used_ram_mb)"; used_d="$(used_disk_gb)"
    free_r=$((ram_av - 512 - used_r)); free_d=$((disk_av - 2 - used_d))
    printf '%b\n' "Host now: RAM free ${ram_av}MB (other VMs use ${used_r}MB) | Disk free ${disk_av}GB (other VMs use ${used_d}GB) | CPUs ${cpus_n}"
    printf '%b\n' "You can still give: RAM ${free_r}MB | Disk ${free_d}GB"
    [ "$RAM" -le "$free_r" ] || die "NOT ENOUGH RAM: you asked ${RAM}MB but only ${free_r}MB is free for new VMs (host keeps 512MB). Use a smaller number — 'joto iccha' is not real, the host only has ${ram_av}MB free."
    [ "$DISK" -le "$free_d" ] || die "NOT ENOUGH DISK: you asked ${DISK}GB but only ${free_d}GB is free for new VMs. Use a smaller number."
    [ "$CPUS" -le "$cpus_n" ] || die "NOT ENOUGH CPUs: host has ${cpus_n} CPUs, you asked ${CPUS}."
    [ "$CPUS" -eq "$cpus_n" ] && warn "You took ALL ${cpus_n} CPUs — host will be slow. Keep 1 CPU for the host if you can."

    # --- STEP 2: KVM guard ---
    local ACCEL="kvm"
    if has_kvm_dev; then
        ok "KVM ready (/dev/kvm exists)."
    elif has_kvm_cpu && [ "$IS_ROOT" = "1" ] && has_cap 16; then
        info "Trying to load the kvm module..."
        grep -q vmx /proc/cpuinfo 2>/dev/null && $SUDO modprobe kvm_intel 2>/dev/null || $SUDO modprobe kvm_amd 2>/dev/null || true
        $SUDO modprobe kvm 2>/dev/null || true
        sleep 1
        has_kvm_dev && ok "KVM module loaded, /dev/kvm is here now." || die "CPU supports virt but /dev/kvm still missing — host blocks the device. Enable nested virt in the provider panel."
    elif [ "$EMULATE" = "1" ]; then
        warn "NO KVM — using pure software emulation (TCG). 10-20x slower. Ubuntu boot alone can take 10+ minutes. Testing only!"
        ACCEL="tcg"
    else
        die "NO KVM on this host (no /dev/kvm, no vmx/svm flag). Nested VPS is IMPOSSIBLE here — this is a container host or nested virt is off. Run 'bash mr-nested-vps.sh check' to see why. (--emulate forces slow software emulation, testing only.)"
    fi

    # --- STEP 3: install tools ---
    mkdir -p "$VM_DIR/images" "$VM_DIR/$NAME"
    if ! command -v qemu-system-x86_64 >/dev/null 2>&1 || ! command -v qemu-img >/dev/null 2>&1; then
        if [ -f /tmp/mr-apt-update-failed ]; then
            die "QEMU is not installed and apt update already failed on this machine (proxy/network — see /tmp/mr-apt.log). Install qemu-system-x86 + qemu-utils + cloud-image-utils where apt works, then re-run."
        fi
        info "Installing QEMU + tools (apt)..."
        apt_install qemu-system-x86 qemu-utils || die "QEMU install failed — check apt/network (see /tmp/mr-apt.log)."
    fi
    if ! command -v cloud-localds >/dev/null 2>&1; then
        if [ -f /tmp/mr-apt-update-failed ]; then
            warn "cloud-localds missing and apt update failed — will try genisoimage instead."
        else
            apt_install cloud-image-utils || warn "cloud-localds missing — will try genisoimage instead."
        fi
    fi
    command -v qemu-system-x86_64 >/dev/null 2>&1 || die "qemu-system-x86_64 still missing after install."
    if ! command -v virsh >/dev/null 2>&1; then
        if [ -f /tmp/mr-apt-update-failed ]; then
            warn "libvirt not installed and apt update failed — using plain QEMU (no virsh)."
        else
            apt_install libvirt-clients virtinst || warn "libvirt not installed — will use plain QEMU (no virsh)."
        fi
    fi

    # --- STEP 4: cloud image (download once, reuse for all VMs) ---
    local BASE_IMG="$VM_DIR/images/$IMAGE_NAME_DEFAULT"
    if [ ! -s "$BASE_IMG" ]; then
        info "Downloading Ubuntu 22.04 cloud image (~600MB, once only)..."
        download_file "$IMAGE_URL" "$BASE_IMG" || die "Cloud image download failed."
    else
        ok "Cloud image already downloaded — reusing it."
    fi
    [ -s "$BASE_IMG" ] || die "Cloud image is empty/corrupt."

    # --- STEP 5: disk (thin overlay on the base image — fast, small) ---
    local DISKFILE="$VM_DIR/$NAME/disk.qcow2"
    qemu-img create -f qcow2 -b "$BASE_IMG" -F qcow2 "$DISKFILE" "${DISK}G" || die "qemu-img create failed."

    # --- STEP 6: cloud-init seed (login user) ---
    local SEEDDIR="$VM_DIR/$NAME/seed" SEEDISO="$VM_DIR/$NAME/seed.iso"
    mkdir -p "$SEEDDIR"
    cat > "$SEEDDIR/user-data" <<EOF
#cloud-config
hostname: $NAME
manage_etc_hosts: true
users:
  - name: mrrean
    sudo: ALL=(ALL) NOPASSWD:ALL
    groups: sudo
    shell: /bin/bash
    lock_passwd: false
    plain_text_passwd: '$PASSWORD'
ssh_pwauth: true
disable_root: false
packages:
  - openssh-server
  - curl
  - wget
runcmd:
  - systemctl enable --now ssh || service ssh start || true
  - echo "MR NESTED VPS $NAME is up"
EOF
    printf 'instance-id: %s\nlocal-hostname: %s\n' "$NAME" "$NAME" > "$SEEDDIR/meta-data"
    if command -v cloud-localds >/dev/null 2>&1; then
        cloud-localds "$SEEDISO" "$SEEDDIR/user-data" "$SEEDDIR/meta-data" || die "cloud-localds failed."
    elif command -v genisoimage >/dev/null 2>&1; then
        genisoimage -output "$SEEDISO" -volid cidata -joliet -rock "$SEEDDIR/user-data" "$SEEDDIR/meta-data" || die "genisoimage failed."
    else
        die "Need cloud-localds or genisoimage to build the seed ISO (apt install cloud-image-utils)."
    fi
    ok "Login seed ready: user mrrean / password (you chose it)."

    # --- STEP 7: start the VM ---
    local MODE="qemu" PORT="2222" IP=""
    # find a free SSH forward port (2222, 2223, ...)
    while :; do
        (command -v ss >/dev/null 2>&1 && ss -ltn 2>/dev/null | grep -q ":$PORT ") && PORT=$((PORT + 1)) || break
        [ "$PORT" -gt 2299 ] && die "No free SSH forward port (2222-2299 busy)."
    done
    if command -v virsh >/dev/null 2>&1 && command -v virt-install >/dev/null 2>&1 && [ "$ACCEL" = "kvm" ]; then
        info "Creating with libvirt (virt-install)..."
        $SUDO virsh net-start default >/dev/null 2>&1 || true
        if ! $SUDO virt-install --name "$NAME" --ram "$RAM" --vcpus "$CPUS" \
                --disk path="$DISKFILE",size="$DISK",format=qcow2 \
                --disk path="$SEEDISO",device=cdrom \
                --os-variant ubuntu22.04 --import \
                --network network=default --graphics none --noautoconsole --autostart >/tmp/virt-install.log 2>&1; then
            warn "virt-install with --os-variant failed — retrying without it..."
            $SUDO virt-install --name "$NAME" --ram "$RAM" --vcpus "$CPUS" \
                --disk path="$DISKFILE",size="$DISK",format=qcow2 \
                --disk path="$SEEDISO",device=cdrom \
                --import --network network=default \
                --graphics none --noautoconsole --autostart >/tmp/virt-install.log 2>&1 || { cat /tmp/virt-install.log; die "virt-install failed (see above)."; }
        fi
        MODE="libvirt"
        info "Waiting for the VM to get an IP (up to 60s)..."
        local i=0
        while [ "$i" -lt 12 ]; do
            sleep 5; i=$((i + 1))
            IP="$($SUDO virsh domifaddr "$NAME" 2>/dev/null | awk '/192\.168|10\./ {print $4}' | cut -d/ -f1 | head -1)"
            [ -n "$IP" ] && break
        done
    else
        info "Creating with plain QEMU (no libvirt)..."
        start_qemu "$NAME" "$RAM" "$CPUS" "$DISKFILE" "$SEEDISO" "$PORT" "$ACCEL" || die "qemu failed to start."
        MODE="qemu"
        IP="127.0.0.1 (port $PORT)"
    fi

    # --- STEP 8: save state + report ---
    {
        printf 'NAME=%s\nMODE=%s\nRAM=%s\nDISK=%s\nCPUS=%s\nPORT=%s\nIP=%s\nACCEL=%s\nDISKFILE=%s\nSEEDISO=%s\n' "$NAME" "$MODE" "$RAM" "$DISK" "$CPUS" "$PORT" "$IP" "$ACCEL" "$DISKFILE" "$SEEDISO"
    } > "$VM_DIR/$NAME/vm.conf"
    echo
    echo "============================================"
    echo "       NESTED VPS READY: $NAME"
    echo "============================================"
    echo "  RAM: ${RAM}MB | Disk: ${DISK}GB | CPUs: ${CPUS} | Mode: ${MODE}"
    if [ "$MODE" = "libvirt" ]; then
        if [ -n "$IP" ]; then echo "  SSH: ssh mrrean@$IP   (password: the one you chose)"; else echo "  IP not yet assigned — wait 1 min, then: virsh domifaddr $NAME"; fi
        echo "  Console: virsh console $NAME"
    else
        echo "  SSH: ssh mrrean@127.0.0.1 -p $PORT   (password: the one you chose)"
        echo "  Console log: tail -f $VM_DIR/$NAME/console.log"
    fi
    echo "  Manage: bash mr-nested-vps.sh list | start $NAME | stop $NAME | delete $NAME"
    echo "  First boot takes 1-3 min (cloud-init) — if SSH refuses, wait and retry."
}

# ============================================================
#  MAKE (v2) — KVM thakuk ar na thakuk, 4ta proshno diye VPS banao.
#  No KVM -> TCG emulation (slow, 10-20x) + slirp networking.
#  Non-interactive: MR_VM_NAME / MR_VM_RAM / MR_VM_DISK / MR_VM_CPUS / MR_VM_PASS
# ============================================================
do_make() {
    local NAME="${MR_VM_NAME:-}" RAM="${MR_VM_RAM:-}" DISK="${MR_VM_DISK:-}" CPUS="${MR_VM_CPUS:-}" PASSWORD="${MR_VM_PASS:-}"
    echo "============================================"
    echo "       MR NESTED VPS — MAKE A VPS"
    echo "============================================"
    if has_kvm_dev; then
        ok "KVM ase — fast mode (real KVM)."
    else
        warn "KVM NAI ei host-e — TCG emulation-e banano hobe (10-20x slow, boot-e 10+ min lagte pare)."
        echo "  Jodi real KVM chao: provider panel-e nested virt on koro, ba real KVM VPS naw."
    fi
    if [ -z "$NAME" ]; then printf 'VM name (letters/numbers/-/_): '; read -r NAME || true; fi
    if [ -z "$RAM" ]; then printf 'RAM MB (min 512, e.g. 2048): '; read -r RAM || true; fi
    if [ -z "$DISK" ]; then printf 'Disk GB (min 5, e.g. 20): '; read -r DISK || true; fi
    if [ -z "$CPUS" ]; then printf 'CPUs (e.g. 2): '; read -r CPUS || true; fi
    if [ -z "$PASSWORD" ]; then
        printf 'Password for user mrrean (min 4 chars, blank = mrrean): '
        stty -echo 2>/dev/null || true
        read -r PASSWORD || true
        stty echo 2>/dev/null || true
        echo
        [ -z "$PASSWORD" ] && PASSWORD="mrrean"
    fi
    if has_kvm_dev; then
        do_create "$NAME" "$RAM" "$DISK" "$CPUS" --password "$PASSWORD"
    else
        do_create "$NAME" "$RAM" "$DISK" "$CPUS" --emulate --password "$PASSWORD"
    fi
}

# ---------- manage ----------
vm_conf() { [ -f "$VM_DIR/$1/vm.conf" ] || die "No VM named '$1'. List: bash mr-nested-vps.sh list"; }
do_list() {
    echo "Nested VPS on this host (dir: $VM_DIR):"
    local found=0
    for f in "$VM_DIR"/*/vm.conf; do
        [ -f "$f" ] || continue
        found=1
        local n m r d c st
        n="$(grep -E '^NAME=' "$f" | cut -d= -f2)"
        m="$(grep -E '^MODE=' "$f" | cut -d= -f2)"
        r="$(grep -E '^RAM=' "$f" | cut -d= -f2)"
        d="$(grep -E '^DISK=' "$f" | cut -d= -f2)"
        c="$(grep -E '^CPUS=' "$f" | cut -d= -f2)"
        if [ "$m" = "libvirt" ]; then st="$($SUDO virsh domstate "$n" 2>/dev/null || echo unknown)"
        elif [ -f "$VM_DIR/$n/qemu.pid" ] && kill -0 "$(cat "$VM_DIR/$n/qemu.pid" 2>/dev/null)" 2>/dev/null; then st="running"
        else st="shut off"; fi
        printf '  %-15s %-8s RAM %sMB Disk %sGB CPU %s  [%s]\n' "$n" "$m" "$r" "$d" "$c" "$st"
    done
    if [ "$found" = "0" ]; then echo "  (none yet — create one: bash mr-nested-vps.sh make)"; fi
    return 0
}
do_start() {
    vm_conf "$1"
    local m; m="$(grep -E '^MODE=' "$VM_DIR/$1/vm.conf" | cut -d= -f2)"
    if [ "$m" = "libvirt" ]; then $SUDO virsh start "$1" && ok "VM $1 started."
    else
        [ -f "$VM_DIR/$1/qemu.pid" ] && kill -0 "$(cat "$VM_DIR/$1/qemu.pid" 2>/dev/null)" 2>/dev/null && die "VM $1 is already running."
        local _r _c _d _s _p _a
        _r="$(grep -E '^RAM=' "$VM_DIR/$1/vm.conf" | cut -d= -f2)"
        _c="$(grep -E '^CPUS=' "$VM_DIR/$1/vm.conf" | cut -d= -f2)"
        _d="$(grep -E '^DISKFILE=' "$VM_DIR/$1/vm.conf" | cut -d= -f2)"
        _s="$(grep -E '^SEEDISO=' "$VM_DIR/$1/vm.conf" | cut -d= -f2)"
        _p="$(grep -E '^PORT=' "$VM_DIR/$1/vm.conf" | cut -d= -f2)"
        _a="$(grep -E '^ACCEL=' "$VM_DIR/$1/vm.conf" | cut -d= -f2)"
        start_qemu "$1" "$_r" "$_c" "$_d" "$_s" "$_p" "$_a" || die "qemu failed to start $1."
        ok "VM $1 started."
    fi
}
do_stop() {
    vm_conf "$1"
    local m; m="$(grep -E '^MODE=' "$VM_DIR/$1/vm.conf" | cut -d= -f2)"
    if [ "$m" = "libvirt" ]; then $SUDO virsh shutdown "$1" && ok "VM $1 shutting down (graceful)."
    else
        [ -f "$VM_DIR/$1/qemu.pid" ] || die "VM $1 is not running (no pid file)."
        kill "$(cat "$VM_DIR/$1/qemu.pid")" && ok "VM $1 stopped."
    fi
}
do_delete() {
    vm_conf "$1"
    local yes=0; [ "${2:-}" = "--yes" ] && yes=1
    if [ "$yes" = "0" ]; then
        printf 'Delete VM %s and its disk? Type YES to confirm: ' "$1"
        read -r ans || true
        [ "$ans" = "YES" ] || { echo "Cancelled."; exit 0; }
    fi
    local m; m="$(grep -E '^MODE=' "$VM_DIR/$1/vm.conf" | cut -d= -f2)"
    if [ "$m" = "libvirt" ]; then
        $SUDO virsh destroy "$1" >/dev/null 2>&1 || true
        $SUDO virsh undefine "$1" --nvram >/dev/null 2>&1 || true
    else
        [ -f "$VM_DIR/$1/qemu.pid" ] && kill "$(cat "$VM_DIR/$1/qemu.pid")" 2>/dev/null || true
    fi
    rm -rf "$VM_DIR/$1"
    ok "VM $1 deleted."
}
do_console() {
    vm_conf "$1"
    local m; m="$(grep -E '^MODE=' "$VM_DIR/$1/vm.conf" | cut -d= -f2)"
    if [ "$m" = "libvirt" ]; then $SUDO virsh console "$1"
    else tail -f "$VM_DIR/$1/console.log"; fi
}

show_help() {
    echo "MR NESTED VPS v$VERSION — VPS-er vitore VPS"
    echo "Usage: bash mr-nested-vps.sh <command> [options]"
    echo
    echo "  make                           v2: 4ta proshno diye VPS banao (KVM thakuk ar na thakuk)"
    echo "  check                          Can this host make nested VPS?"
    echo "  create <name> <ramMB> <diskGB> <cpus> [--emulate] [--password P] [--image URL]"
    echo "                                 Make a nested VPS (Ubuntu 22.04)"
    echo "  list                           List your nested VPS"
    echo "  start <name> | stop <name>     Start / stop a VPS"
    echo "  delete <name> [--yes]          Delete a VPS + its disk"
    echo "  console <name>                 VM console"
    echo "  help                           This help"
    echo
    echo "Examples:"
    echo "  bash mr-nested-vps.sh make"
    echo "  bash mr-nested-vps.sh check"
    echo "  bash mr-nested-vps.sh create myvps1 2048 20 2"
    echo "  bash mr-nested-vps.sh create small 1024 10 1 --password mysecret123"
    echo
    echo "Remember: total RAM/disk of ALL your nested VPS can never exceed"
    echo "the host's real RAM/disk. The script refuses oversized requests."
}

case "$CMD" in
    make)    do_make "$@" ;;
    check)   do_check ;;
    create)  [ $# -ge 4 ] || { error "Usage: bash mr-nested-vps.sh create <name> <ramMB> <diskGB> <cpus>"; exit 1; }; do_create "$@" ;;
    list)    do_list ;;
    start)   [ $# -ge 1 ] || die "Usage: start <name>"; do_start "$1" ;;
    stop)    [ $# -ge 1 ] || die "Usage: stop <name>"; do_stop "$1" ;;
    delete)  [ $# -ge 1 ] || die "Usage: delete <name> [--yes]"; do_delete "$1" "${2:-}" ;;
    console) [ $# -ge 1 ] || die "Usage: console <name>"; do_console "$1" ;;
    help|--help|-h) show_help ;;
    *) error "Unknown command: $CMD"; show_help; exit 1 ;;
esac
