#!/bin/bash
# ============================================================
#  MR PANAL SETUP v1.0.0 — Auto Pterodactyl Panel + Node (Wings)
#  by MR REAN (mr-rean-x) | https://github.com/mr-rean-x/MR-Ubuntu-Proot
#
#  ONE COMMAND — paste it, answer 4 questions, done:
#    python3 -c "import urllib.request,os;urllib.request.urlretrieve('https://raw.githubusercontent.com/mr-rean-x/MR-Ubuntu-Proot/main/mr-panel-setup.sh','mr-panel-setup.sh');os.execv('/bin/bash',['bash','mr-panel-setup.sh'])"
#
#  It asks ONLY: domain, admin username, admin password, admin email.
#  Then it installs, all by itself:
#    Panel v1.15.2 (PHP 8.3 + MariaDB + Redis + Nginx + SSL)
#    + Node (Wings v1.13.5 + Docker) — node auto-created, config auto-written.
#
#  MENU:  1) Full Setup (Panel + Node)  2) Panel only  3) Node only
#         4) Check status              5) Exit
#  DIRECT: bash mr-panel-setup.sh full|panel|node|status|tunnel|node-token [--dry-run]
#  TUNNEL (v1.1): bash mr-panel-setup.sh tunnel — installs cloudflared,
#    runs YOUR Cloudflare tunnel (token typed in the terminal, hidden,
#    never in chat/repo) as a systemd service + sets panel APP_URL to
#    the tunnel domain. Token lives only in the unit file on your VPS.
#  ROUTES (v1.1): panel.<domain> -> localhost:80, node.<domain> -> localhost:8080 —
#    dashboard-e tunnel-er Public Hostnames-e add koro (script nije check kore).
#  NODE-TOKEN (v1.2): panel-e nije node banale (node1) — bash mr-panel-setup.sh node-token
#    script nijei token chaibe (hidden), config.yml-e bosabe, Wings restart kore green korbe.
#  NODE DOMAIN (v1.1): node FQDN is node.<panel-domain> by default
#    (override: MR_NODE_DOMAIN). Point node.<domain> DNS to the node
#    server (A record) or add it as a tunnel Public Hostname (:8080).
#  PREVIEW (installs nothing): bash mr-panel-setup.sh full --dry-run
#
#  VERIFIED AGAINST (official Pterodactyl v1 docs + panel v1.15.2 source):
#    - Panel deps + install steps (docs.pterodactyl.io/v1/panel/getting-started)
#    - Wings install (docs.pterodactyl.io/v1/wings/installing) — Docker via
#      get.docker.com, wings.service unit, systemctl enable --now wings
#    - p:user:make --email= --username= --name-first= --name-last=
#      --password= --admin=1   (exact signature from MakeUserCommand.php)
#    - p:node:make --name= --description= --locationId= --fqdn= --scheme=
#      --public= --proxy= --maintenance= --maxMemory= --overallocateMemory=
#      --maxDisk= --overallocateDisk= --uploadSize= --daemonListeningPort=
#      --daemonSFTPPort= --daemonBase=  (exact signature, MakeNodeCommand.php)
#    - p:node:configuration <id> > /etc/pterodactyl/config.yml (official docs)
#    - locations table: id, short (unique), long (migration AddLocations)
#    - allocations table: node_id, ip, ip_alias, port, server_id, notes
#      (Allocation.php model, v1.15.2)
#    - pteroq.service ExecStart + cron schedule:run (official docs)
#
#  HONEST LIMITS:
#    - Needs a REAL root VPS (Ubuntu 22.04 or 24.04) with systemd. On a
#      container host (Render / Jupyter / Altare sandbox) Wings + Docker
#      can NEVER run — the script installs the Panel only there and says so.
#    - Needs a domain whose DNS points to the server for HTTPS. Without
#      that, Certbot fails and the panel installs on plain HTTP (it says so).
#    - The admin password is NEVER written to any file by this script.
#    - First run takes 5-15 minutes (downloads + composer). Do not stop it.
#
#  POSIX-safe: works pasted into /bin/sh (dash) too. No exploits, ever.
# ============================================================
# POSIX-safe: works even when pasted into /bin/sh (dash), which has no pipefail.
set -eu

VERSION="1.2.0-MR-PANAL"
PANEL_VERSION="v1.15.2"
WINGS_VERSION="v1.13.5"
PHP_VER="8.3"
PANEL_DIR="/var/www/pterodactyl"

# ---------- args ----------
DRY_RUN=0
MODE=""
for _a in "$@"; do
    case "$_a" in
        full|panel|node|status|tunnel|node-token|help|--help|-h) MODE="$_a" ;;
        --dry-run) DRY_RUN=1 ;;
        *) printf 'Unknown argument: %s\n' "$_a" >&2; exit 1 ;;
    esac
done
[ -n "$MODE" ] || MODE="menu"

# ---------- colours / logging (printf, NOT echo -e — dash breaks echo -e) ----------
RED='\033[1;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()  { printf '%b\n' "${CYAN}[*]${NC} $*"; }
ok()    { printf '%b\n' "${GREEN}[+]${NC} $*"; }
warn()  { printf '%b\n' "${YELLOW}[!]${NC} $*"; }
error() { printf '%b\n' "${RED}[x]${NC} $*" >&2; }
die()   { error "$*"; exit 1; }

# ---------- run: dry-run prints, real run executes ----------
run() {
    if [ "$DRY_RUN" = "1" ]; then printf '%b\n' "${YELLOW}[dry-run]${NC} $*"; return 0; fi
    "$@"
}

# ---------- apt (time-boxed, update once) — same fix as mr-vps-power.sh ----------
APT_OPTS="-o Acquire::http::Timeout=20 -o Acquire::https::Timeout=20 -o Acquire::Retries=1"
with_timeout() {
    local secs="$1"; shift
    if command -v timeout >/dev/null 2>&1; then timeout "$secs" "$@"; else "$@"; fi
}
apt_update_once() {
    if [ "$DRY_RUN" = "1" ]; then printf '%b\n' "${YELLOW}[dry-run]${NC} apt-get update"; return 0; fi
    if [ ! -f /tmp/mr-apt-updated ]; then
        if with_timeout 180 apt-get $APT_OPTS update -y >/tmp/mr-apt.log 2>&1; then
            rm -f /tmp/mr-apt-update-failed
        else
            warn "apt-get update failed/timed out (see /tmp/mr-apt.log)"
            touch /tmp/mr-apt-update-failed
        fi
        touch /tmp/mr-apt-updated
    fi
}
apt_install() {
    if [ "$DRY_RUN" = "1" ]; then printf '%b\n' "${YELLOW}[dry-run]${NC} apt install $*"; return 0; fi
    if ! command -v apt-get >/dev/null 2>&1; then warn "apt-get not found"; return 1; fi
    apt_update_once
    with_timeout 900 apt-get $APT_OPTS install -y "$@" >>/tmp/mr-apt.log 2>&1 || { warn "apt install failed for: $* (see /tmp/mr-apt.log)"; return 1; }
    return 0
}

# ---------- download (wget -> curl -> python3) ----------
download_file() {
    local url="$1" dest="$2" tries=0
    if [ "$DRY_RUN" = "1" ]; then printf '%b\n' "${YELLOW}[dry-run]${NC} download $url -> $dest"; return 0; fi
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

random_hex() { openssl rand -hex 16 2>/dev/null || head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n'; }

# ---------- banner + menu (red, as requested) ----------
show_banner() {
    printf '%b\n' "${RED}============================================================${NC}"
    printf '%b\n' "${RED}   __  __ ____    ____   _    _   _    _    _     ${NC}"
    printf '%b\n' "${RED}  |  \/  |  _ \  |  _ \ / \  | \ | |  / \  | |    ${NC}"
    printf '%b\n' "${RED}  | |\/| | |_) | | |_) / _ \ |  \| | / _ \ | |    ${NC}"
    printf '%b\n' "${RED}  | |  | |  _ <  |  __/ ___ \| |\  |/ ___ \| |___ ${NC}"
    printf '%b\n' "${RED}  |_|  |_|_| \_\ |_| /_/   \_\_| \_/_/   \_\_____|${NC}"
    printf '%b\n' "${RED}              S E T U P  v${VERSION}${NC}"
    printf '%b\n' "${RED}============================================================${NC}"
    printf '%b\n' "${RED}  Auto Pterodactyl Panel ${PANEL_VERSION} + Node (Wings ${WINGS_VERSION})${NC}"
    printf '%b\n' "${RED}============================================================${NC}"
}
show_menu() {
    show_banner
    echo
    echo "  1) Full Setup — Panel + Node (Wings)  [recommended]"
    echo "  2) Panel only"
    echo "  3) Node (Wings) only — needs a panel already on this machine"
    echo "  4) Check status"
    echo "  5) Exit"
    echo
}

# ---------- prompts ----------
ask() { # ask <var> <prompt> <default>
    local _var="$1" _prompt="$2" _def="$3" _val=""
    printf '%s' "$_prompt"
    [ -n "$_def" ] && printf ' [%s]' "$_def"
    printf ': '
    read -r _val || die "Input closed."
    [ -z "$_val" ] && _val="$_def"
    eval "$_var=\$_val"
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
valid_domain() {
    case "$1" in
        ""|*[!A-Za-z0-9.-]*|*..*|.-*|-.*|.*|*.) return 1 ;;
    esac
    case "$1" in *.*) return 0 ;; *) return 1 ;; esac
}
valid_email() {
    case "$1" in
        *@*.*) [ "${1#*@}" != "$1" ] && [ "${1%%@*}" != "" ] && return 0 ;;
    esac
    return 1
}
ask_panel_inputs() {
    # Env overrides skip prompts (advanced / testing): MR_DOMAIN, MR_ADMIN_USER,
    # MR_ADMIN_PASS, MR_ADMIN_EMAIL
    DOMAIN="${MR_DOMAIN:-}"; ADMIN_USER="${MR_ADMIN_USER:-}"; ADMIN_PASS="${MR_ADMIN_PASS:-}"; ADMIN_EMAIL="${MR_ADMIN_EMAIL:-}"
    if [ -z "$DOMAIN" ]; then
        while :; do
            ask DOMAIN "Panel domain (example: panel.example.com)" ""
            valid_domain "$DOMAIN" && break
            error "Bad domain '$DOMAIN' — use a real domain like panel.example.com (with a dot, no spaces)."
        done
    fi
    if [ -z "$ADMIN_USER" ]; then
        while :; do
            ask ADMIN_USER "Admin username" "mrrean"
            case "$ADMIN_USER" in
                ""|*[!A-Za-z0-9_-]*|"") error "Username: letters, numbers, - and _ only." ;;
                *) [ "${#ADMIN_USER}" -ge 3 ] && break || error "Username must be at least 3 characters." ;;
            esac
        done
    fi
    if [ -z "$ADMIN_EMAIL" ]; then
        while :; do
            ask ADMIN_EMAIL "Admin email (gmail)" ""
            valid_email "$ADMIN_EMAIL" && break
            error "Bad email '$ADMIN_EMAIL' — use a real email like you@gmail.com."
        done
    fi
    if [ -z "$ADMIN_PASS" ]; then
        while :; do
            ask_secret ADMIN_PASS "Admin password (min 8 characters, hidden)"
            [ "${#ADMIN_PASS}" -ge 8 ] && break
            error "Password must be at least 8 characters."
        done
        local _confirm=""
        ask_secret _confirm "Type the password again"
        [ "$ADMIN_PASS" = "$_confirm" ] || die "Passwords do not match — run again."
        _confirm=""
    fi
    echo
    info "Domain: $DOMAIN | Admin: $ADMIN_USER <$ADMIN_EMAIL>"
}

# ---------- checks ----------
check_prereqs() {
    [ "$(id -u)" = "0" ] || die "Run as root (sudo -i first). This installer needs root."
    [ "$DRY_RUN" = "1" ] && { warn "dry-run: skipping OS checks."; return 0; }
    local os_id="" os_ver=""
    if [ -f /etc/os-release ]; then
        os_id="$(grep -E '^ID=' /etc/os-release | cut -d= -f2 | tr -d '"')"
        os_ver="$(grep -E '^VERSION_ID=' /etc/os-release | cut -d= -f2 | tr -d '"')"
    fi
    [ "$os_id" = "ubuntu" ] || die "This installer supports Ubuntu only (found: ${os_id:-unknown})."
    case "$os_ver" in
        22.04|24.04) ok "Ubuntu $os_ver — supported." ;;
        *) die "Ubuntu $os_ver is not supported by Pterodactyl v1 — use 22.04 or 24.04." ;;
    esac
    [ "$(cat /proc/1/comm 2>/dev/null)" = "systemd" ] || warn "PID 1 is not systemd — services may not start. A real VPS with systemd is expected."
    local ram_mb disk_gb
    ram_mb="$(awk '/MemTotal:/ {print int($2/1024)}' /proc/meminfo)"
    disk_gb="$(df -k --output=avail / 2>/dev/null | tail -1 | awk '{print int($1/1024/1024)}')"
    [ "$ram_mb" -ge 2048 ] || warn "Only ${ram_mb}MB RAM — Pterodactyl wants 2GB+. It may still install, but game servers will struggle."
    [ "$disk_gb" -ge 5 ] || die "Only ${disk_gb}GB disk free — need at least 5GB."
    [ "$disk_gb" -ge 10 ] || warn "Only ${disk_gb}GB disk free — 10GB+ recommended for game servers."
    ok "RAM ${ram_mb}MB | Disk free ${disk_gb}GB."
}
is_container_host() {
    if command -v systemd-detect-virt >/dev/null 2>&1; then
        case "$(systemd-detect-virt 2>/dev/null || echo none)" in
            docker|lxc|systemd-nspawn|openvz|podman) return 0 ;;
        esac
    fi
    [ -f /.dockerenv ] || [ -f /run/.containerenv ] && return 0
    return 1
}
panel_installed() { [ -f "$PANEL_DIR/.env" ] && [ -f "$PANEL_DIR/artisan" ]; }
db_cli() { command -v mariadb || command -v mysql || echo ""; }
env_get() { grep -E "^$1=" "$PANEL_DIR/.env" 2>/dev/null | cut -d= -f2- | tr -d '"' | tr -d "'"; }
env_set() { # env_set KEY VALUE — replace or append in .env
    local key="$1" val="$2" esc
    if [ "$DRY_RUN" = "1" ]; then printf '%b\n' "${YELLOW}[dry-run]${NC} .env: $key=***"; return 0; fi
    esc="$(printf '%s' "$val" | sed 's/[&|]/\\&/g')"
    if grep -q -E "^${key}=" "$PANEL_DIR/.env" 2>/dev/null; then
        sed -i "s|^${key}=.*|${key}=${esc}|" "$PANEL_DIR/.env"
    else
        printf '%s=%s\n' "$key" "$val" >> "$PANEL_DIR/.env"
    fi
}
fix_perms() {
    if [ "$DRY_RUN" = "1" ]; then printf '%b\n' "${YELLOW}[dry-run]${NC} chown -R www-data:www-data $PANEL_DIR"; return 0; fi
    chown -R www-data:www-data "$PANEL_DIR" 2>/dev/null || warn "chown www-data failed (user may not exist yet — continuing)."
    chmod -R 755 "$PANEL_DIR/storage" "$PANEL_DIR/bootstrap/cache" 2>/dev/null || true
}
public_ip() {
    local ip=""
    ip="$(curl -s --max-time 10 https://ifconfig.me 2>/dev/null || true)"
    [ -n "$ip" ] || ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
    printf '%s' "$ip"
}

# ---------- panel ----------
install_deps() {
    info "Installing dependencies (PHP $PHP_VER + MariaDB + Redis + Nginx)..."
    local os_ver=""
    os_ver="$(grep -E '^VERSION_ID=' /etc/os-release | cut -d= -f2 | tr -d '"')"
    apt_update_once
    apt_install software-properties-common curl apt-transport-https ca-certificates gnupg lsb-release || die "Base packages failed (see /tmp/mr-apt.log)."
    if [ "$os_ver" = "22.04" ]; then
        info "Ubuntu 22.04: adding ondrej/php PPA (PHP 8.3) + Redis repo..."
        run env LC_ALL=C.UTF-8 add-apt-repository -y ppa:ondrej/php
        if [ "$DRY_RUN" = "1" ]; then printf '%b\n' "${YELLOW}[dry-run]${NC} curl -fsSL https://packages.redis.io/gpg | gpg --dearmor -o /usr/share/keyrings/redis-archive-keyring.gpg"; else curl -fsSL https://packages.redis.io/gpg | gpg --dearmor -o /usr/share/keyrings/redis-archive-keyring.gpg || warn "Redis GPG key failed — continuing (Ubuntu redis-server still works)."; fi
        apt_update_once
    fi
    apt_install "php${PHP_VER}" "php${PHP_VER}-common" "php${PHP_VER}-cli" "php${PHP_VER}-gd" "php${PHP_VER}-mysql" "php${PHP_VER}-mbstring" "php${PHP_VER}-bcmath" "php${PHP_VER}-xml" "php${PHP_VER}-fpm" "php${PHP_VER}-curl" "php${PHP_VER}-zip" mariadb-server nginx tar unzip git redis-server python3-certbot-nginx || die "Dependency install failed (see /tmp/mr-apt.log)."
    if ! command -v composer >/dev/null 2>&1; then
        info "Installing Composer v2..."
        if [ "$DRY_RUN" = "1" ]; then printf '%b\n' "${YELLOW}[dry-run]${NC} curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer";
        else curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer || die "Composer install failed."; fi
    fi
    ok "Dependencies installed."
}

setup_database() {
    info "Creating panel database + user..."
    DB_PASS="$(random_hex)"
    if [ "$DRY_RUN" = "1" ]; then
        printf '%b\n' "${YELLOW}[dry-run]${NC} mariadb -u root: CREATE USER pterodactyl, DATABASE panel"
        return 0
    fi
    local cli; cli="$(db_cli)"
    [ -n "$cli" ] || die "MariaDB client not found (mariadb/mysql)."
    "$cli" -u root -e "CREATE USER IF NOT EXISTS 'pterodactyl'@'127.0.0.1' IDENTIFIED BY '$DB_PASS'; ALTER USER 'pterodactyl'@'127.0.0.1' IDENTIFIED BY '$DB_PASS'; CREATE DATABASE IF NOT EXISTS panel; GRANT ALL PRIVILEGES ON panel.* TO 'pterodactyl'@'127.0.0.1' WITH GRANT OPTION; FLUSH PRIVILEGES;" || die "Database setup failed — is MariaDB running? (systemctl status mariadb). If MariaDB root has a password, run: mysql -u root -p, then re-run this installer."
    ok "Database 'panel' + user 'pterodactyl' ready."
}

install_panel_files() {
    info "Downloading Pterodactyl Panel $PANEL_VERSION..."
    run mkdir -p "$PANEL_DIR"
    if [ "$DRY_RUN" = "0" ]; then cd "$PANEL_DIR" || die "Cannot enter $PANEL_DIR"; fi
    download_file "https://github.com/pterodactyl/panel/releases/download/$PANEL_VERSION/panel.tar.gz" panel.tar.gz || die "Panel download failed — check internet/GitHub."
    if [ "$DRY_RUN" = "1" ]; then printf '%b\n' "${YELLOW}[dry-run]${NC} tar -xzvf panel.tar.gz + chmod storage + bootstrap/cache";
    else tar -xzvf panel.tar.gz || die "Panel extract failed."; chmod -R 755 storage/* bootstrap/cache/ || true; fi
    if [ "$DRY_RUN" = "1" ]; then printf '%b\n' "${YELLOW}[dry-run]${NC} cp .env.example .env";
    else cp .env.example .env 2>/dev/null || die ".env.example missing — bad download?"; fi
    env_set APP_URL "http://$DOMAIN"
    env_set APP_TIMEZONE "Asia/Dhaka"
    env_set APP_ENV "production"
    env_set APP_ENVIRONMENT_ONLY "false"
    env_set DB_HOST "127.0.0.1"
    env_set DB_PORT "3306"
    env_set DB_DATABASE "panel"
    env_set DB_USERNAME "pterodactyl"
    env_set DB_PASSWORD "$DB_PASS"
    env_set CACHE_DRIVER "redis"
    env_set SESSION_DRIVER "redis"
    env_set QUEUE_CONNECTION "redis"
    env_set REDIS_HOST "127.0.0.1"
    env_set REDIS_PORT "6379"
    info "Installing PHP dependencies (composer — takes a few minutes)..."
    if [ "$DRY_RUN" = "1" ]; then printf '%b\n' "${YELLOW}[dry-run]${NC} COMPOSER_ALLOW_SUPERUSER=1 composer install --no-dev --optimize-autoloader";
    else COMPOSER_ALLOW_SUPERUSER=1 with_timeout 900 composer install --no-dev --optimize-autoloader || die "Composer install failed."; fi
    info "Generating app key + migrating database..."
    if [ "$DRY_RUN" = "1" ]; then
        printf '%b\n' "${YELLOW}[dry-run]${NC} php artisan key:generate --force"
        printf '%b\n' "${YELLOW}[dry-run]${NC} php artisan migrate --seed --force"
    else
        php artisan key:generate --force || die "key:generate failed."
        php artisan migrate --seed --force || die "Database migrate failed — check DB settings in $PANEL_DIR/.env."
    fi
    fix_perms
    ok "Panel files installed."
}

create_admin_user() {
    info "Creating admin user $ADMIN_USER..."
    if [ "$DRY_RUN" = "1" ]; then
        printf '%b\n' "${YELLOW}[dry-run]${NC} php artisan p:user:make --email=$ADMIN_EMAIL --username=$ADMIN_USER --name-first=MR --name-last=Admin --password=******** --admin=1"
        return 0
    fi
    cd "$PANEL_DIR" || die "Cannot enter $PANEL_DIR"
    php artisan p:user:make --email="$ADMIN_EMAIL" --username="$ADMIN_USER" --name-first="MR" --name-last="Admin" --password="$ADMIN_PASS" --admin=1 || die "Admin user creation failed (email/username may already exist)."
    fix_perms
    ok "Admin user created."
}

install_nginx() {
    info "Setting up Nginx..."
    if [ "$DRY_RUN" = "1" ]; then
        printf '%b\n' "${YELLOW}[dry-run]${NC} write /etc/nginx/sites-available/pterodactyl.conf + enable + nginx -t + reload"
        return 0
    fi
    mkdir -p /etc/nginx/sites-available /etc/nginx/sites-enabled
    cat > /etc/nginx/sites-available/pterodactyl.conf <<EOF
server {
    listen 80;
    server_name __DOMAIN__;
    root /var/www/pterodactyl/public;
    index index.php;
    access_log /var/log/nginx/pterodactyl.app-access.log;
    error_log /var/log/nginx/pterodactyl.app-error.log error;
    client_max_body_size 100m;
    client_body_timeout 120s;
    sendfile off;
    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }
    location ~ \.php\$ {
        fastcgi_split_path_info ^(.+\.php)(/.+)\$;
        fastcgi_pass unix:/run/php/php${PHP_VER}-fpm.sock;
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param PHP_VALUE "upload_max_filesize = 100M \n post_max_size=100M";
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param HTTP_PROXY "";
        fastcgi_intercept_errors off;
        fastcgi_buffer_size 16k;
        fastcgi_buffers 4 16k;
        fastcgi_connect_timeout 300;
        fastcgi_send_timeout 300;
        fastcgi_read_timeout 300;
    }
    location ~ /\.ht {
        deny all;
    }
}
EOF
    sed -i "s/__DOMAIN__/$DOMAIN/g" /etc/nginx/sites-available/pterodactyl.conf
    ln -sf /etc/nginx/sites-available/pterodactyl.conf /etc/nginx/sites-enabled/pterodactyl.conf
    rm -f /etc/nginx/sites-enabled/default
    nginx -t || die "Nginx config test failed."
    systemctl reload nginx || systemctl restart nginx || die "Nginx reload failed."
    ok "Nginx is serving http://$DOMAIN"
}

setup_ssl() {
    SCHEME="http"
    info "Trying HTTPS with Certbot (needs $DOMAIN pointing to this server)..."
    if [ "$DRY_RUN" = "1" ]; then
        printf '%b\n' "${YELLOW}[dry-run]${NC} certbot --nginx -d $DOMAIN --non-interactive --agree-tos -m $ADMIN_EMAIL"
        SCHEME="https"; return 0
    fi
    if certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos -m "$ADMIN_EMAIL" >>/tmp/mr-certbot.log 2>&1; then
        SCHEME="https"
        env_set APP_URL "https://$DOMAIN"
        (cd "$PANEL_DIR" && php artisan config:clear >/dev/null 2>&1 || true)
        ok "HTTPS enabled: https://$DOMAIN"
    else
        warn "Certbot FAILED (see /tmp/mr-certbot.log) — panel stays on HTTP. This usually means $DOMAIN does not point to this server yet. Point the DNS A record to this server, then run: certbot --nginx -d $DOMAIN"
        warn "The node will also use http until you fix HTTPS."
    fi
}

setup_workers() {
    info "Setting up queue worker + scheduler..."
    if [ "$DRY_RUN" = "1" ]; then
        printf '%b\n' "${YELLOW}[dry-run]${NC} write /etc/systemd/system/pteroq.service + enable/start + cron schedule:run"
        return 0
    fi
    cat > /etc/systemd/system/pteroq.service <<'EOF'
[Unit]
Description=Pterodactyl Queue Worker
After=redis-server.service
[Service]
User=www-data
Group=www-data
Restart=always
ExecStart=/usr/bin/php /var/www/pterodactyl/artisan queue:work --queue=high,standard,low --sleep=3 --tries=3
StartLimitInterval=180
StartLimitBurst=30
RestartSec=5s
[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable --now pteroq || warn "pteroq worker failed to start — check: systemctl status pteroq"
    (crontab -l 2>/dev/null | grep -v "artisan schedule:run"; echo "* * * * * php /var/www/pterodactyl/artisan schedule:run >> /dev/null 2>&1") | crontab - || warn "Cron setup failed — add manually: * * * * * php /var/www/pterodactyl/artisan schedule:run"
    ok "Queue worker + cron ready."
}

# ---------- node / wings ----------
create_location_node() {
    info "Creating location + node (auto)..."
    # Node subdomain: node.<panel-domain> by default (override: MR_NODE_DOMAIN)
    NODE_DOMAIN="${MR_NODE_DOMAIN:-node.$DOMAIN}"
    info "Node domain: $NODE_DOMAIN (panel: $DOMAIN)"
    local cli loc_id node_ram node_disk node_out
    local db_name db_user db_pass
    # Node size: host total minus reserve for panel/OS (computed in both modes)
    local total_ram total_disk
    total_ram="$(awk '/MemTotal:/ {print int($2/1024)}' /proc/meminfo)"
    total_disk="$(df -k --output=avail /var/lib 2>/dev/null | tail -1 | awk '{print int($1/1024/1024)}')"
    node_ram=$((total_ram - 1024)); [ "$node_ram" -lt 512 ] && node_ram=512
    node_disk=$((total_disk - 5)); [ "$node_disk" -lt 1 ] && node_disk=1
    info "Node size: ${node_ram}MB RAM, ${node_disk}GB disk (host total ${total_ram}MB/${total_disk}GB minus reserve)."
    if [ "$DRY_RUN" = "1" ]; then
        printf '%b\n' "${YELLOW}[dry-run]${NC} mariadb: INSERT location (mr1, MR Location) + SELECT id"
        printf '%b\n' "${YELLOW}[dry-run]${NC} php artisan p:node:make --name=node1 --description=MR Node --locationId=1 --fqdn=$NODE_DOMAIN --scheme=$SCHEME --public=1 --proxy=0 --maintenance=0 --maxMemory=$node_ram --overallocateMemory=0 --maxDisk=$node_disk --overallocateDisk=0 --uploadSize=100 --daemonListeningPort=8080 --daemonSFTPPort=2022 --daemonBase=/var/lib/pterodactyl/volumes"
        printf '%b\n' "${YELLOW}[dry-run]${NC} mariadb: INSERT allocations ports 25565-25575"
        NODE_ID=1; return 0
    fi
    cli="$(db_cli)"
    [ -n "$cli" ] || die "MariaDB client not found."
    db_name="$(env_get DB_DATABASE)"; db_user="$(env_get DB_USERNAME)"; db_pass="$(env_get DB_PASSWORD)"
    [ -n "$db_name" ] || db_name="panel"
    [ -n "$db_user" ] || db_user="pterodactyl"
    loc_id="$("$cli" -u "$db_user" "-p$db_pass" -N -e "SELECT id FROM $db_name.locations WHERE short='mr1';" 2>/dev/null || echo "")"
    if [ -z "$loc_id" ]; then
        "$cli" -u "$db_user" "-p$db_pass" -e "INSERT INTO $db_name.locations (short, long, created_at, updated_at) VALUES ('mr1', 'MR Location', NOW(), NOW());" || die "Location insert failed."
        loc_id="$("$cli" -u "$db_user" "-p$db_pass" -N -e "SELECT id FROM $db_name.locations WHERE short='mr1';" 2>/dev/null || echo "")"
    fi
    [ -n "$loc_id" ] || die "Could not get location id."
    ok "Location id: $loc_id"
    cd "$PANEL_DIR" || die "Cannot enter $PANEL_DIR"
    node_out="$(php artisan p:node:make --name="node1" --description="MR Node" --locationId="$loc_id" --fqdn="$NODE_DOMAIN" --scheme="$SCHEME" --public=1 --proxy=0 --maintenance=0 --maxMemory="$node_ram" --overallocateMemory=0 --maxDisk="$node_disk" --overallocateDisk=0 --uploadSize=100 --daemonListeningPort=8080 --daemonSFTPPort=2022 --daemonBase="/var/lib/pterodactyl/volumes" 2>&1)" || { printf '%s\n' "$node_out"; die "Node creation failed."; }
    NODE_ID="$(printf '%s' "$node_out" | sed -n 's/.*has an id of \([0-9]*\).*/\1/p' | head -1)"
    [ -n "$NODE_ID" ] || { printf '%s\n' "$node_out"; die "Node created but its id could not be read."; }
    ok "Node created: node1 (id $NODE_ID, ${node_ram}MB RAM, ${node_disk}GB disk, $SCHEME://$NODE_DOMAIN)"
    # Default allocations: ports 25565-25575 on the server IP (so you can create servers right away)
    local srv_ip p
    srv_ip="$(public_ip)"
    if [ -n "$srv_ip" ]; then
        for p in 25565 25566 25567 25568 25569 25570 25571 25572 25573 25574 25575; do
            "$cli" -u "$db_user" "-p$db_pass" -e "INSERT INTO $db_name.allocations (node_id, ip, ip_alias, port, server_id, notes, created_at, updated_at) SELECT $NODE_ID, '$srv_ip', NULL, $p, NULL, NULL, NOW(), NOW() FROM DUAL WHERE NOT EXISTS (SELECT 1 FROM $db_name.allocations WHERE node_id=$NODE_ID AND ip='$srv_ip' AND port=$p);" 2>/dev/null || true
        done
        ok "Allocations added: $srv_ip ports 25565-25575."
    else
        warn "Could not detect the server IP — add allocations in the panel (Admin -> Nodes -> node1 -> Allocation)."
    fi
    fix_perms
}

install_wings() {
    info "Installing Wings $WINGS_VERSION + Docker..."
    if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
        ok "Docker already running."
    else
        info "Installing Docker (official script — takes a few minutes)..."
        if [ "$DRY_RUN" = "1" ]; then
            printf '%b\n' "${YELLOW}[dry-run]${NC} curl -sSL https://get.docker.com/ | CHANNEL=stable bash"
        else
            with_timeout 600 bash -c "curl -sSL https://get.docker.com/ | CHANNEL=stable bash" >>/tmp/mr-docker.log 2>&1 || { warn "Docker script failed (see /tmp/mr-docker.log) — trying docker.io from apt..."; apt_install docker.io || die "Docker install failed."; }
        fi
        if [ "$DRY_RUN" = "0" ]; then systemctl enable --now docker || die "Docker failed to start — Wings cannot run on this machine."; fi
    fi
    local arch wings_url
    case "$(uname -m)" in
        x86_64) arch="amd64" ;;
        aarch64|arm64) arch="arm64" ;;
        *) die "Unsupported CPU architecture: $(uname -m) (Wings needs amd64 or arm64)." ;;
    esac
    wings_url="https://github.com/pterodactyl/wings/releases/download/$WINGS_VERSION/wings_linux_$arch"
    run mkdir -p /etc/pterodactyl
    download_file "$wings_url" /usr/local/bin/wings || die "Wings download failed."
    if [ "$DRY_RUN" = "0" ]; then chmod u+x /usr/local/bin/wings; fi
    [ -n "${NODE_ID:-}" ] || die "No node id — create the node first."
    info "Writing Wings config from the panel (p:node:configuration)..."
    if [ "$DRY_RUN" = "1" ]; then
        printf '%b\n' "${YELLOW}[dry-run]${NC} php artisan p:node:configuration $NODE_ID > /etc/pterodactyl/config.yml"
    else
        (cd "$PANEL_DIR" && php artisan p:node:configuration "$NODE_ID" > /etc/pterodactyl/config.yml) || die "Could not generate Wings config."
        grep -q "uuid:" /etc/pterodactyl/config.yml || die "Wings config looks empty — check: php artisan p:node:configuration $NODE_ID"
    fi
    info "Starting Wings as a service..."
    if [ "$DRY_RUN" = "1" ]; then
        printf '%b\n' "${YELLOW}[dry-run]${NC} write /etc/systemd/system/wings.service + daemon-reload + enable --now wings"
        return 0
    fi
    cat > /etc/systemd/system/wings.service <<'EOF'
[Unit]
Description=Pterodactyl Wings Daemon
After=docker.service
Requires=docker.service
PartOf=docker.service
[Service]
User=root
WorkingDirectory=/etc/pterodactyl
LimitNOFILE=4096
PIDFile=/var/run/wings/daemon.pid
ExecStart=/usr/local/bin/wings
Restart=on-failure
StartLimitInterval=180
StartLimitBurst=30
RestartSec=5s
[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable --now wings || die "Wings failed to start — check: systemctl status wings && journalctl -u wings -n 100"
    sleep 5
    if systemctl is-active --quiet wings; then ok "Wings is RUNNING."; else warn "Wings service is not active — check: systemctl status wings"; fi
}

# ---------- tunnel (cloudflared) ----------
install_cloudflared() {
    if command -v cloudflared >/dev/null 2>&1; then ok "cloudflared already installed: $(cloudflared --version 2>/dev/null | head -1)"; return 0; fi
    local arch deb_url
    case "$(uname -m)" in
        x86_64) arch="amd64" ;;
        aarch64|arm64) arch="arm64" ;;
        *) die "Unsupported CPU architecture: $(uname -m) (cloudflared needs amd64 or arm64)." ;;
    esac
    deb_url="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-$arch.deb"
    info "Downloading cloudflared ($arch)..."
    download_file "$deb_url" /tmp/cloudflared.deb || die "cloudflared download failed."
    if [ "$DRY_RUN" = "1" ]; then printf '%b\n' "${YELLOW}[dry-run]${NC} dpkg -i /tmp/cloudflared.deb"; return 0; fi
    dpkg -i /tmp/cloudflared.deb >>/tmp/mr-cloudflared.log 2>&1 || { apt_install -f || true; dpkg -i /tmp/cloudflared.deb >>/tmp/mr-cloudflared.log 2>&1 || die "cloudflared install failed (see /tmp/mr-cloudflared.log)."; }
    command -v cloudflared >/dev/null 2>&1 || die "cloudflared still missing after install."
    ok "cloudflared installed: $(cloudflared --version 2>/dev/null | head -1)"
}

do_tunnel() {
    check_prereqs
    echo "============================================"
    echo "       MR PANAL — TUNNEL (Cloudflare)"
    echo "============================================"
    echo "  Cloudflare dashboard-e giye: Zero Trust -> Networks -> Tunnels"
    echo "  -> Create tunnel -> token copy koro. Token chat-e diba NA —"
    echo "  ekhane terminal-e likhba (lukano thakbe, file-eo jabe na)."
    echo
    local TOKEN="" TUN_DOMAIN=""
    if [ -n "${MR_TUNNEL_TOKEN:-}" ]; then
        TOKEN="$MR_TUNNEL_TOKEN"
    else
        ask_secret TOKEN "Tunnel token (Cloudflare theke copy kora)"
        [ -n "$TOKEN" ] || die "Token dite hobe."
    fi
    if [ -n "${MR_TUNNEL_DOMAIN:-}" ]; then
        TUN_DOMAIN="$MR_TUNNEL_DOMAIN"
    else
        while :; do
            ask TUN_DOMAIN "Tunnel domain (example: panel.example.com)" ""
            valid_domain "$TUN_DOMAIN" && break
            error "Bad domain '$TUN_DOMAIN'."
        done
    fi
    install_cloudflared
    if [ "$DRY_RUN" = "1" ]; then
        printf '%b\n' "${YELLOW}[dry-run]${NC} write /etc/systemd/system/cloudflared.service + enable + restart cloudflared"
        printf '%b\n' "${YELLOW}[dry-run]${NC} panel APP_URL -> https://$TUN_DOMAIN"
        TOKEN=""
        return 0
    fi
    cat > /etc/systemd/system/cloudflared.service <<EOF
[Unit]
Description=Cloudflare Tunnel (MR PANAL)
After=network-online.target
Wants=network-online.target
[Service]
Type=simple
ExecStart=/usr/local/bin/cloudflared tunnel --no-autoupdate run --token $TOKEN
Restart=always
RestartSec=5
[Install]
WantedBy=multi-user.target
EOF
    chmod 600 /etc/systemd/system/cloudflared.service
    systemctl daemon-reload
    systemctl enable cloudflared >/dev/null 2>&1 || true
    systemctl restart cloudflared || die "cloudflared service failed to start — check: systemctl status cloudflared"
    sleep 5
    if systemctl is-active --quiet cloudflared; then ok "cloudflared RUNNING."; else warn "cloudflared not active — check: journalctl -u cloudflared -n 50"; fi
    if panel_installed; then
        env_set APP_URL "https://$TUN_DOMAIN"
        (cd "$PANEL_DIR" && php artisan config:clear >/dev/null 2>&1 || true)
        systemctl reload nginx 2>/dev/null || true
        systemctl restart pteroq 2>/dev/null || true
        ok "Panel URL set to https://$TUN_DOMAIN"
    else
        warn "Panel ekhono install hoy nai — age panel install koro, tarpor tunnel domain-e APP_URL set korte 'tunnel' abar chalao."
    fi
    # --- routes: panel + node (dashboard Public Hostnames) ---
    case "$TUN_DOMAIN" in
        *.*.*) ROOT_DOM="${TUN_DOMAIN#*.}" ;;
        *) ROOT_DOM="$TUN_DOMAIN" ;;
    esac
    NODE_TUN_DOMAIN="node.$ROOT_DOM"
    echo
    echo "ROUTES — Cloudflare dashboard-e tunnel-er Public Hostnames-e 2ta add koro:"
    echo "  1) Hostname: $TUN_DOMAIN | Service: http://localhost:80   (panel)"
    echo "  2) Hostname: $NODE_TUN_DOMAIN | Service: http://localhost:8080   (node/Wings)"
    {
        echo "MR PANAL TUNNEL ROUTES ($(date))"
        echo "Panel: $TUN_DOMAIN -> http://localhost:80"
        echo "Node:  $NODE_TUN_DOMAIN -> http://localhost:8080"
    } > ~/tunnel-routes.txt
    echo "  (saved: ~/tunnel-routes.txt)"
    local code code2
    code="$(curl -s -o /dev/null -w "%{http_code}" --max-time 15 "https://$TUN_DOMAIN" 2>/dev/null || echo 000)"
    code2="$(curl -s -o /dev/null -w "%{http_code}" --max-time 15 "https://$NODE_TUN_DOMAIN" 2>/dev/null || echo 000)"
    case "$code" in
        200|301|302) ok "Panel route LIVE: https://$TUN_DOMAIN (HTTP $code)" ;;
        *) warn "Panel route ekhono khultese na (HTTP $code) — dashboard-e hostname add korso to? 1-2 min wait koro." ;;
    esac
    case "$code2" in
        200|301|302|404) ok "Node route LIVE: https://$NODE_TUN_DOMAIN (HTTP $code2)" ;;
        *) warn "Node route ekhono khultese na (HTTP $code2) — dashboard-e node hostname add korso to?" ;;
    esac
    echo
    echo "============================================"
    echo "       MR PANAL — TUNNEL READY"
    echo "============================================"
    echo "  Panel: https://$TUN_DOMAIN"
    echo "  Node:  https://$NODE_TUN_DOMAIN"
    echo "  Check: systemctl status cloudflared"
    echo "  Node-er FQDN bodlate hole: panel-e Admin -> Nodes -> node1 -> FQDN"
    TOKEN=""
}

# ---------- status ----------
do_status() {
    show_banner
    echo
    if panel_installed; then
        local url; url="$(env_get APP_URL)"
        [ -n "$url" ] || url="http://localhost"
        local code; code="$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "$url" 2>/dev/null || echo 000)"
        printf 'Panel: %s  (HTTP %s)\n' "$url" "$code"
        (cd "$PANEL_DIR" && php artisan p:node:list 2>/dev/null || echo "  (node list unavailable)") | head -20
    else
        echo "Panel: NOT installed (no $PANEL_DIR/.env)"
    fi
    if systemctl is-active --quiet wings 2>/dev/null; then echo "Wings: RUNNING"; else echo "Wings: not running"; fi
    if systemctl is-active --quiet pteroq 2>/dev/null; then echo "Queue worker (pteroq): RUNNING"; else echo "Queue worker (pteroq): not running"; fi
    if systemctl is-active --quiet docker 2>/dev/null; then echo "Docker: RUNNING"; else echo "Docker: not running"; fi
}

# ---------- flows ----------
do_panel() {
    check_prereqs
    ask_panel_inputs
    if panel_installed; then
        warn "Panel is already installed at $PANEL_DIR — skipping panel install."
        return 0
    fi
    install_deps
    setup_database
    install_panel_files
    create_admin_user
    install_nginx
    setup_ssl
    setup_workers
    echo
    echo "============================================"
    echo "       MR PANAL — PANEL READY"
    echo "============================================"
    echo "  URL:   $SCHEME://$DOMAIN"
    echo "  Admin: $ADMIN_USER <$ADMIN_EMAIL>"
    echo "  Login with the password you typed (it is not shown here)."
    if [ "$SCHEME" = "http" ]; then echo "  NOTE: HTTP only — point $DOMAIN DNS to this server, then run: certbot --nginx -d $DOMAIN"; fi
}
do_node() {
    check_prereqs
    panel_installed || die "No panel found at $PANEL_DIR — install the panel first (menu option 1 or 2)."
    DOMAIN="$(env_get APP_URL)"
    DOMAIN="${DOMAIN#https://}"; DOMAIN="${DOMAIN#http://}"; DOMAIN="${DOMAIN%%/*}"
    [ -n "$DOMAIN" ] || { ask DOMAIN "Node FQDN (domain)" ""; valid_domain "$DOMAIN" || die "Bad domain."; }
    SCHEME="https"; case "$(env_get APP_URL)" in http://*) SCHEME="http" ;; esac
    ADMIN_EMAIL="${MR_ADMIN_EMAIL:-admin@example.com}"
    if is_container_host; then
        warn "This looks like a CONTAINER host — Docker/Wings almost never work here. Trying anyway; if Wings fails, use a real KVM VPS."
    fi
    create_location_node
    install_wings
    echo
    echo "============================================"
    echo "       MR PANAL — NODE READY"
    echo "============================================"
    echo "  Node: node1 (id ${NODE_ID:-?}) on $SCHEME://$NODE_DOMAIN"
    if systemctl is-active --quiet wings 2>/dev/null; then echo "  Wings: running"; else echo "  Wings: not running"; fi
    echo "  Check the panel: Admin -> Nodes -> node1 should be green."
}
do_full() {
    check_prereqs
    ask_panel_inputs
    # MR_ALLOW_CONTAINER=1 skips the container fallback (testing / privileged LXC).
    if is_container_host && [ "${MR_ALLOW_CONTAINER:-0}" != "1" ]; then
        warn "This looks like a CONTAINER host — Wings + Docker will almost certainly FAIL here."
        warn "Installing the PANEL only. For Wings, use a real KVM VPS (Ubuntu 22.04/24.04)."
        do_panel
        return 0
    fi
    if panel_installed; then
        warn "Panel already installed — going straight to the node."
        SCHEME="https"; case "$(env_get APP_URL)" in http://*) SCHEME="http" ;; esac
        ADMIN_EMAIL="${MR_ADMIN_EMAIL:-admin@example.com}"
    else
        install_deps
        setup_database
        install_panel_files
        create_admin_user
        install_nginx
        setup_ssl
        setup_workers
    fi
    create_location_node
    install_wings
    echo
    echo "============================================"
    echo "       MR PANAL — ALL DONE"
    echo "============================================"
    echo "  Panel: $SCHEME://$DOMAIN"
    echo "  Admin: $ADMIN_USER <$ADMIN_EMAIL>"
    if systemctl is-active --quiet wings 2>/dev/null; then echo "  Node:  node1 (id ${NODE_ID:-?}) — Wings: running"; else echo "  Node:  node1 (id ${NODE_ID:-?}) — Wings: not running"; fi
    echo "  Login with the password you typed (it is not shown here)."
    echo "  Next: log in -> create a server (eggs are already seeded)."
    if [ "$SCHEME" = "http" ]; then echo "  NOTE: HTTP only — point $DOMAIN DNS to this server, then run: certbot --nginx -d $DOMAIN"; fi
}

# ---------- node-token: panel-e nije node banale, token diye Wings green koro ----------
do_node_token() {
    check_prereqs
    panel_installed || die "No panel found at $PANEL_DIR — install the panel first (menu option 1 or 2)."
    local node_id="${MR_NODE_ID:-}" node_token="${MR_NODE_TOKEN:-}"
    local cli db_name db_user db_pass row
    local node_uuid node_token_id node_fqdn node_scheme node_port node_sftp panel_url code
    [ -n "$node_id" ] || { ask node_id "Node id (node1 = 1)" "1"; }
    case "$node_id" in *[!0-9]*|'') die "Node id number hote hobe (node1 = 1)." ;; esac
    if [ -z "$node_token" ]; then
        ask_secret node_token "Node token (panel > Nodes > node1 > Configuration tab theke copy koro)"
    fi
    [ -n "$node_token" ] || die "Token dao nai — panel-er Configuration tab theke token copy kore abar chalao."
    if [ "$DRY_RUN" = "1" ]; then
        printf '%b\n' "${YELLOW}[dry-run]${NC} mariadb: SELECT uuid, daemon_token_id, fqdn, scheme, daemonListeningPort, daemonSFTPPort FROM nodes WHERE id=$node_id"
        printf '%b\n' "${YELLOW}[dry-run]${NC} write /etc/pterodactyl/config.yml (uuid + token_id + TOKEN + remote) + systemctl restart wings"
        return 0
    fi
    cli="$(db_cli)"
    [ -n "$cli" ] || die "MariaDB client not found."
    db_name="$(env_get DB_DATABASE)"; db_user="$(env_get DB_USERNAME)"; db_pass="$(env_get DB_PASSWORD)"
    [ -n "$db_name" ] || db_name="panel"
    [ -n "$db_user" ] || db_user="pterodactyl"
    row="$("$cli" -u "$db_user" "-p$db_pass" -N -e "SELECT uuid, daemon_token_id, fqdn, scheme, daemonListeningPort, daemonSFTPPort FROM $db_name.nodes WHERE id=$node_id;" 2>/dev/null || echo "")"
    [ -n "$row" ] || die "Node id $node_id panel-e paoa jay nai — panel-e Admin -> Nodes-e id check koro."
    node_uuid="$(printf '%s' "$row" | cut -f1)"
    node_token_id="$(printf '%s' "$row" | cut -f2)"
    node_fqdn="$(printf '%s' "$row" | cut -f3)"
    node_scheme="$(printf '%s' "$row" | cut -f4)"
    node_port="$(printf '%s' "$row" | cut -f5)"
    node_sftp="$(printf '%s' "$row" | cut -f6)"
    [ -n "$node_uuid" ] && [ -n "$node_token_id" ] || die "Node-er uuid/token_id paoa jay nai."
    [ -n "$node_port" ] || node_port=8080
    [ -n "$node_sftp" ] || node_sftp=2022
    panel_url="$(env_get APP_URL)"
    [ -n "$panel_url" ] || panel_url="http://localhost"
    if [ "$node_scheme" = "https" ]; then
        "$cli" -u "$db_user" "-p$db_pass" -e "UPDATE $db_name.nodes SET scheme='http' WHERE id=$node_id;" 2>/dev/null || true
        info "Node scheme http kora holo (Wings SSL off — tunnel-e http-e cholbe)."
    fi
    run mkdir -p /etc/pterodactyl
    {
        printf 'debug: false\n'
        printf 'uuid: %s\n' "$node_uuid"
        printf 'token_id: %s\n' "$node_token_id"
        printf 'token: %s\n' "$node_token"
        printf 'api:\n  host: 0.0.0.0\n  port: %s\n  ssl:\n    enabled: false\n    cert: /etc/pterodactyl/certs/server.crt\n    key: /etc/pterodactyl/certs/server.key\n  upload_limit: 100\n' "$node_port"
        printf 'system:\n  data: /var/lib/pterodactyl/volumes\n  sftp:\n    bind_port: %s\n' "$node_sftp"
        printf 'remote: %s\n' "$panel_url"
    } > /etc/pterodactyl/config.yml
    chmod 600 /etc/pterodactyl/config.yml
    ok "Wings config lekha holo: /etc/pterodactyl/config.yml (node $node_id, $node_fqdn)"
    if [ -f /etc/systemd/system/wings.service ]; then
        systemctl daemon-reload
        systemctl restart wings || systemctl enable --now wings || die "Wings start hoy nai — check: systemctl status wings"
        sleep 3
        if systemctl is-active --quiet wings; then ok "Wings RUNNING."; else warn "Wings service active na — check: systemctl status wings"; fi
    else
        die "Wings install hoy nai — age 'full' ba 'node' chalao, tarpor 'node-token' chalao."
    fi
    code="$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "http://$node_fqdn:$node_port" 2>/dev/null || echo 000)"
    case "$code" in
        200|301|302|404) ok "Node route LIVE: http://$node_fqdn:$node_port (HTTP $code)" ;;
        *) warn "Node-e ekhono connect hocche na (HTTP $code) — tunnel route (node -> localhost:$node_port) + Wings check koro." ;;
    esac
    node_token=""
    echo
    echo "============================================"
    echo "       MR PANAL — NODE-TOKEN READY"
    echo "============================================"
    echo "  Node: node1 (id $node_id) on $node_fqdn"
    echo "  Panel-e refresh dao: Admin -> Nodes -> node1 green hobe."
}

show_help() {
    show_banner
    echo
    echo "Usage: bash mr-panel-setup.sh [command] [--dry-run]"
    echo
    echo "  (no command)  Show the MR PANAL SETUP menu"
    echo "  full          Panel + Node (Wings), all automatic"
    echo "  panel         Panel only"
    echo "  node          Node (Wings) only — panel must already exist here"
    echo "  status        Check panel + Wings status"
    echo "  tunnel        Cloudflare Tunnel — install cloudflared + run your tunnel + set panel URL"
    echo "  node-token    Panel-e nije node banale — script nijei token chaibe, config.yml-e bosabe, Wings restart korbe"
    echo "  help          This help"
    echo "  --dry-run     Print every step, install nothing"
    echo
    echo "The installer asks only: domain, admin username, admin password,"
    echo "admin email. Node size is automatic (host total minus reserve)."
    echo "Env overrides: MR_DOMAIN MR_ADMIN_USER MR_ADMIN_PASS MR_ADMIN_EMAIL MR_NODE_DOMAIN MR_TUNNEL_TOKEN MR_TUNNEL_DOMAIN MR_NODE_ID MR_NODE_TOKEN"
}

# ---------- main ----------
case "$MODE" in
    menu)
        while :; do
            show_menu
            printf 'Choose [1-5]: '
            read -r _choice || break
            case "$_choice" in
                1) do_full; echo; printf 'Press Enter to return to the menu...'; read -r _x || break ;;
                2) do_panel; echo; printf 'Press Enter to return to the menu...'; read -r _x || break ;;
                3) do_node; echo; printf 'Press Enter to return to the menu...'; read -r _x || break ;;
                4) do_status; echo; printf 'Press Enter to return to the menu...'; read -r _x || break ;;
                5) echo "Bye."; exit 0 ;;
                *) error "Choose 1-5." ;;
            esac
        done
        ;;
    full)   do_full ;;
    panel)  do_panel ;;
    node)   do_node ;;
    status) do_status ;;
    tunnel) do_tunnel ;;
    node-token) do_node_token ;;
    help|--help|-h) show_help ;;
    *) error "Unknown command: $MODE"; show_help; exit 1 ;;
esac
