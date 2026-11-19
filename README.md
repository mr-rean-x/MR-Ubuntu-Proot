# MR ROOT v2 — Powerful Ubuntu Proot Installer

**MR REAN custom repo.** Ubuntu 20.04 (or 22.04) inside any Linux host **without root, without Docker, without sudo** — using PRoot. Built for Jupyter / Render / free hosts where the original FOX YTOUX script kept breaking.

One file does everything: `mr-root.sh`

## One-line install

```bash
curl -fsSL https://raw.githubusercontent.com/mr-rean-x/MR-Ubuntu-Proot/main/mr-root.sh -o mr-root.sh
bash mr-root.sh install
```

Or with `wget`:

```bash
wget https://raw.githubusercontent.com/mr-rean-x/MR-Ubuntu-Proot/main/mr-root.sh
bash mr-root.sh install
```

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

## What is NOT fixed (honest limits)

- **Render / free Jupyter restarts wipe everything.** No script can survive a container wipe — you must re-run install after a restart. That is a host limit, not a script bug.
- **Not 24/7.** When the host sleeps / the terminal closes, Ubuntu + JTG stop. Same limit as before.
- **Not real root / no Docker / no systemd.** PRoot fakes root (`-0`). `sudo` / `systemctl` / Docker will not work inside. JTG "Pure Local Node.js" mode is the one that works here.
- **512 MB RAM hosts (Render free) are too small for JTG's full build.** JTG needs ~1 GB+ for `npm run build`. Use a bigger host (Helsinki JupyterLab / Altare) for JTG.

## Files

- `mr-root.sh` — the whole installer (single file, everything above)
- `README.md` — this file

## Credits

- Original idea: FOX YTOUX Ubuntu proot installer (foxytouxxx/freeroot)
- Fixed + powered up by MR REAN — https://github.com/mr-rean-x
