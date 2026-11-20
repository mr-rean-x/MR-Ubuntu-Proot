# MR ROOT v3 — Powerful Ubuntu Proot Installer

**MR REAN custom repo.** Ubuntu 20.04 (or 22.04) inside any Linux host **without root, without Docker, without sudo** — using PRoot. Built for Jupyter / Render / free hosts where the original FOX YTOUX script kept breaking.

## ⚡ ONE COMMAND — paste this, get root

Works even when the host has **no curl and no wget** (Jupyter always has python3):

```bash
python3 -c "import urllib.request,os;urllib.request.urlretrieve('https://raw.githubusercontent.com/mr-rean-x/MR-Ubuntu-Proot/main/mr-root.sh','mr-root.sh');os.execv('/bin/bash',['bash','mr-root.sh','install'])"
```

One line, press Enter, Ubuntu installs and drops you into a root shell. Already installed? It skips the download and goes straight to root.

**Or paste the whole script like the original:** copy the full [`mr-root-one.sh`](mr-root-one.sh) file into your terminal and press Enter — no download needed at all, works even in `/bin/sh` (dash) terminals.

## ⚡ MR VPS POWER — Docker / Privileged / Kernel / Networking / Systemd / KVM

One command — checks your VPS and sets up everything that **can** be set up, then prints a true ✅/❌ report:

```bash
python3 -c "import urllib.request,os;urllib.request.urlretrieve('https://raw.githubusercontent.com/mr-rean-x/MR-Ubuntu-Proot/main/mr-vps-power.sh','mr-vps-power.sh');os.execv('/bin/bash',['bash','mr-vps-power.sh','install'])"
```

Check only (installs nothing, safe anywhere):

```bash
bash mr-vps-power.sh check
```

What it does: installs Docker (`docker.io`, starts the daemon via systemd or directly, Podman rootless fallback), enables IP forwarding, checks kernel module loading, checks `/dev/kvm` (loads the kvm module if the CPU supports it), reports systemd status.

**Honest limits:** Privileged / Kernel / KVM are decided by the HOST, not by any command inside. If the host did not give your VPS `CAP_SYS_ADMIN`, `/dev/kvm` or module loading, no script can create them from inside — that would be breaking out of the container, and this script does NOT do exploits. On a real root KVM VPS all six go green. On free container hosts (Render / Jupyter / Altare sandbox) Docker daemon, systemd-as-PID-1 and KVM stay blocked by the host — the script tells you exactly which and why.

Fixes in v1.0.0: apt calls are time-boxed (slow/blocked mirrors fail fast instead of hanging), `apt-get update` runs once per run, and the Docker report now says the TRUE cause — apt download failure vs host block (older message blamed the host even when the proxy broke apt).

## 🖥️ MR NESTED VPS — VPS-er vitore VPS banao (QEMU/KVM)

Check first (5 seconds, installs nothing):

```bash
python3 -c "import urllib.request,os;urllib.request.urlretrieve('https://raw.githubusercontent.com/mr-rean-x/MR-Ubuntu-Proot/main/mr-nested-vps.sh','mr-nested-vps.sh');os.execv('/bin/bash',['bash','mr-nested-vps.sh','check'])"
```

Make a nested VPS (Ubuntu 22.04, login `mrrean` / password you choose):

```bash
bash mr-nested-vps.sh create myvps1 2048 20 2 --password mysecret123
#                         ^name  ^RAM MB ^disk GB ^CPUs
bash mr-nested-vps.sh list
bash mr-nested-vps.sh stop myvps1
bash mr-nested-vps.sh start myvps1
bash mr-nested-vps.sh delete myvps1 --yes
```

**Honest limits:** nested VPS shares the HOST's real RAM/disk/CPU — "joto iccha" is not real. Host-e 6GB RAM thakle sob nested VPS miliye 6GB-er beshi dite parba na; script-ta hiseb kore na dile exact number soho refuse kore. It needs a REAL KVM VPS with nested virt enabled (CPU vmx/svm flag + `/dev/kvm`). Free container hosts can NEVER make nested VPS. Without KVM, `--emulate` boots in pure software emulation (10-20x slower, testing only).

Tested end-to-end (stub QEMU/libvirt): create → list → stop → start → delete works on BOTH the libvirt path and the plain-QEMU path; oversize requests and bad names are refused with exact numbers. A live boot of a real Ubuntu cloud image still needs a real KVM host — first boot takes 1-3 min (cloud-init).

Note: if apt was broken once, the scripts remember it in `/tmp/mr-apt-update-failed` and skip pointless installs — if you fixed apt, run `rm -f /tmp/mr-apt-updated /tmp/mr-apt-update-failed` and re-run.

## 🔴 MR PANAL SETUP — Auto Pterodactyl Panel + Node (1 command)

ONE command — paste it, answer 4 questions, done. Menu upre lal **MR PANAL SETUP** lekha thakbe:

```bash
python3 -c "import urllib.request,os;urllib.request.urlretrieve('https://raw.githubusercontent.com/mr-rean-x/MR-Ubuntu-Proot/main/mr-panel-setup.sh','mr-panel-setup.sh');os.execv('/bin/bash',['bash','mr-panel-setup.sh'])"
```

It asks ONLY: **domain, admin username, admin password, admin email (gmail)**. Then it installs everything by itself:

- **Panel v1.15.2** — PHP 8.3 + MariaDB + Redis + Nginx + queue worker + cron + HTTPS (Certbot)
- **Node (Wings v1.13.5 + Docker)** — node auto-created (`p:node:make`), config auto-written (`p:node:configuration`), 11 allocations (ports 25565–25575) auto-added

Menu: `1) Full Setup (Panel + Node)` · `2) Panel only` · `3) Node only` · `4) Check status` · `5) Exit`
Direct: `bash mr-panel-setup.sh full|panel|node|status [--dry-run]` — `--dry-run` prints every step, installs nothing.

Node size is automatic (host total RAM/disk minus reserve for the panel/OS). Admin password is NEVER written to any file. Timezone is set to Asia/Dhaka.

**Honest limits:** needs a REAL root VPS (Ubuntu 22.04 or 24.04) with systemd — on a container host (Render / Jupyter / Altare) it installs the Panel only and says why Wings cannot run there. Needs the domain's DNS pointing to the server for HTTPS — without that, Certbot fails and the panel installs on plain HTTP (it says so, and the node uses http too). First run takes 5–15 minutes. A live install on a real VPS is still untested — the full flow is verified end-to-end with stubbed panel/Wings/DB tools (prompts, validation, both HTTPS + HTTP-fallback paths, node + allocations + config + services all confirmed).

## 🖥️ MR VM INFO — jekono VM-er IP, user, login info (1 command)

Chalalei oi machine-er sob dekhabe — public IP, private IP, hostname, OS, RAM/disk, current user, sob login user, SSH status/port, ar ready-to-copy login card (`ssh user@ip`). Railway/Render hole domain + service info dekhabe.

```bash
python3 -c "import urllib.request,os;urllib.request.urlretrieve('https://raw.githubusercontent.com/mr-rean-x/MR-Ubuntu-Proot/main/mr-vm-info.sh','mr-vm-info.sh');os.execv('/bin/bash',['bash','mr-vm-info.sh'])"
```

Notun password set kore dekhate (root only):

```bash
bash mr-vm-info.sh setpass [user]
```

**Sotto kotha:** ager password KOKHONO dekha jay na — oita one-way hash hoye `/etc/shadow`-te thake, kono command-e oita ber korte pare na. Tai `setpass` NOTUN password banay, ar tokhon IP + user + notun password ekbare dekhay. Railway-te kono VM password/IP thake na — Railway dey sudhu domain, script-ta oitao dekhay. Password kono file-e lekha hoy na.

One file does everything: `mr-root.sh` (installer) and `mr-root-one.sh` (v3 one-paste version)

## One-line install

```bash
curl -fsSL https://raw.githubusercontent.com/mr-rean-x/MR-Ubuntu-Proot/main/mr-root.sh -o mr-root.sh
bash mr-root.sh install
```

Or with `wget` (use this if you see `curl: not found`):

```bash
wget https://raw.githubusercontent.com/mr-rean-x/MR-Ubuntu-Proot/main/mr-root.sh -O mr-root.sh
bash mr-root.sh install
```

Or with `python3` (works even when both curl and wget are missing — Jupyter hosts always have python3):

```bash
python3 -c "import urllib.request; urllib.request.urlretrieve('https://raw.githubusercontent.com/mr-rean-x/MR-Ubuntu-Proot/main/mr-root.sh','mr-root.sh')"
bash mr-root.sh install
```

> Paste ONE line at a time, press Enter, and wait for it to finish before the next line. Pasting both lines together can mangle them in web terminals.

After install, enter Ubuntu any time with:

```bash
bash ~/mr-ubuntu-start.sh
# or, if ~/.local/bin is on PATH:
mr-ubuntu
```

## Commands

| Command | What it does |
|---|---|
| `bash mr-root.sh install` | Download Ubuntu + proot, fix DNS, create launcher, setup Node 20 + git + PM2, then enter Ubuntu |
| `bash mr-root.sh install --no-setup` | Ubuntu only, fast — no apt/Node setup |
| `bash mr-root.sh install --with-java` | Full setup + OpenJDK 21 (JTG panel needs Java, takes ~10-15 min) |
| `bash mr-root.sh install --ubuntu 22.04` | Install Ubuntu 22.04 instead of 20.04 |
| `bash mr-root.sh install --dir ~/my-ubuntu` | Install to a custom folder (default: `~/mr-ubuntu`) |
| `bash mr-root.sh start` | Enter Ubuntu |
| `bash mr-root.sh exec "node -v"` | Run one command inside Ubuntu |
| `bash mr-root.sh setup` | Re-run first-boot setup (apt + Node 20 + git + PM2) |
| `bash mr-root.sh jtg` | Clone JTG panel + run its installer — choose `[1]` Install Panel, then `[2]` Pure Local Node.js, owner `mrrean` |
| `bash mr-root.sh status` | Show install status |
| `bash mr-root.sh clean --yes` | Delete Ubuntu + launcher |
| `bash mr-root.sh help` | Help |

## JTG panel (port 6767)

```bash
bash mr-root.sh install --with-java
bash mr-root.sh jtg
# inside the installer: choose 1, then 2 (Pure Local Node.js)
# owner username: mrrean — password: YOU type it yourself (min 6 chars)
# panel: http://localhost:6767
```

JTG repo: https://github.com/JishnuTheGamer/Jtg

## Bugs fixed vs the original FOX YTOUX script

1. **`ROOTFS_DIR=$(pwd)` — DANGEROUS.** The old script extracted Ubuntu into whatever folder you ran it from, polluting your home / Jupyter work dir and breaking if you ran it twice from different folders. **Fix:** fixed dir `~/mr-ubuntu` (override with `--dir`).
2. **Whole rootfs re-downloaded when only proot was missing.** The old `if [ ! -x bin/sh ] || [ ! -x proot ]` check wiped everything on one missing file. **Fix:** rootfs and proot are checked and installed separately.
3. **No download resume / no checksum.** A half download passed `gzip -t` sometimes and broke later. **Fix:** `wget -c` / `curl -C -` resume, 5 retries, SHA256 check from cdimage when an entry exists.
4. **No fallback if `wget` is missing** — it just exited. **Fix:** uses `wget` OR `curl`, whichever exists.
5. **Proot binary never tested.** A failed download (HTML error page) was `chmod +x`'d and only failed at launch. **Fix:** ELF-magic check + `proot --version` test, bad file deleted, mirror fallback (jsDelivr GH mirror).
6. **Missing binds.** Old script bound only `/dev /sys /proc` — `apt` and Node break without `/dev/pts`, `/dev/shm`, `/tmp`. **Fix:** launcher binds all of them + `--link2symlink`.
7. **No command support.** Old script always opened `/bin/sh -l`, you could not run one command. **Fix:** `mr-root.sh exec "<cmd>"` and `~/mr-ubuntu-start.sh "<cmd>"`.
8. **No setup at all.** Bare `ubuntu-base` has no git/curl/Node — JTG cannot install. **Fix:** first-boot setup installs curl, wget, git, python3, Node.js 20 (NodeSource), PM2. `--with-java` adds OpenJDK 21.
9. **DNS copy could silently fail.** `/etc/resolv.conf` is a symlink on many hosts; a blind `cp` left Ubuntu with no DNS. **Fix:** `cp -L` + fallback to 1.1.1.1 / 8.8.8.8 + a proper `/etc/hosts`.
10. **No disk check, no cleanup.** A full disk left a half-extracted rootfs marked as installed. **Fix:** 600 MB free-space check, `.mr-installed` marker with version, broken downloads deleted on failure.
11. **No seccomp fallback.** On hosts where proot's seccomp is blocked, launch just died. **Fix:** launcher retries with `PROOT_NO_SECCOMP=1`.
12. **No commands / flags at all.** **Fix:** `install / start / exec / setup / jtg / status / clean / help`, `--ubuntu`, `--dir`, `--no-setup`, `--with-java`.
13. **`tar -xzf` fails as a non-root user (found by live test 2026-11-20).** Plain tar tries to chown files to uid 0, exits non-zero, and the old script died with "Extraction failed" even though every file was extracted fine. **Fix:** `tar --no-same-owner` + judge success by content (`bin/sh` + `/usr/bin`), not tar's exit code.
14. **No downloader at all on minimal hosts (found 2026-11-20 — Render Jupyter has no curl).** The whole install died before it started. **Fix:** downloader tries wget → curl → **python3** (urllib), so any Jupyter host works.
15. **`shift || true` kills dash (found by live test 2026-11-20).** `shift` is a special builtin — in non-interactive `/bin/sh` its error is fatal even after `||`. **Fix:** guarded shift (`if [ $# -gt 0 ]; then shift; fi`).
16. **`echo -e` prints literal `-e` under dash (found by live test 2026-11-20).** All log lines looked broken in `/bin/sh` terminals. **Fix:** `printf '%b\n'` everywhere — plus the whole one-paste script is POSIX-only (no `pipefail`, no `[[ ]]`), so pasting into dash works.
17. **Setup failure killed the whole install before root (found by live test 2026-11-20).** If `apt-get update` failed (e.g. proxy-blocked host), `set -e` aborted everything and the user never got a root shell. **Fix:** setup script has no `set -e` — every step reports and continues — and `do_setup` always returns 0, so you ALWAYS land in root. Retry setup later from inside with `bash /root/.mr-setup.sh`.

## What is NOT fixed (honest limits)

- **Render / free Jupyter restarts wipe everything.** No script can survive a container wipe — you must re-run install after a restart. That is a host limit, not a script bug.
- **Not 24/7.** When the host sleeps / the terminal closes, Ubuntu + JTG stop. Same limit as before.
- **Not real root / no Docker / no systemd.** PRoot fakes root (`-0`). `sudo` / `systemctl` / Docker will not work inside. JTG "Pure Local Node.js" mode is the one that works here.
- **512 MB RAM hosts (Render free) are too small for JTG's full build.** JTG needs ~1 GB+ for `npm run build`. Use a bigger host (Helsinki JupyterLab / Altare) for JTG.

## Files

- `mr-root.sh` — the whole installer (single file, everything above)
- `mr-root-one.sh` — v3 ADVANCE one-paste version: copy the whole file into a terminal, press Enter, get root. No download of itself, dash-safe, no setup by default (fast root — run `bash /root/.mr-setup.sh` inside for Node 20 + git + PM2)
- `mr-vps-power.sh` — v1 VPS POWER: Docker / privileged / kernel / networking / systemd / KVM check + setup + honest report
- `mr-nested-vps.sh` — v1 NESTED VPS: VPS-er vitore VPS banao (QEMU/KVM, libvirt + plain-QEMU paths, resource guard)
- `mr-panel-setup.sh` — v1 MR PANAL SETUP: auto Pterodactyl Panel v1.15.2 + Node (Wings v1.13.5) — red menu, 4 prompts, full auto
- `mr-vm-info.sh` — v1 MR VM INFO: any VM terminal — IP, user, login card + setpass (new password)
- `README.md` — this file

## Credits

- Original idea: FOX YTOUX Ubuntu proot installer (foxytouxxx/freeroot)
- Fixed + powered up by MR REAN — https://github.com/mr-rean-x
