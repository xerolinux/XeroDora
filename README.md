# FedInstall

Post-install setup script for **Fedora** — a port of the XeroLinux KDE Plasma
installer to Fedora's package ecosystem. Run it from a TTY right after a
minimal/Server Fedora install to get a complete KDE Plasma desktop with
RPMFusion repos, multimedia codecs, a curated app/utility set, and your choice
of optional applications.

## Quick start

Run from a TTY (or any terminal) on a fresh Fedora install:

```bash
curl -fsSL https://raw.githubusercontent.com/<user>/FedInstall/main/xero-kde-fedora.sh | bash
```

> Replace `<user>` with your GitHub username/org once the repo is pushed.

Or download and run it:

```bash
curl -fsSLO https://raw.githubusercontent.com/<user>/FedInstall/main/xero-kde-fedora.sh
chmod +x xero-kde-fedora.sh
./xero-kde-fedora.sh
```

Works whether you run as root or as a normal user with `sudo`. Interactive
prompts read from `/dev/tty`, so they work correctly under `curl | bash`.

## What it does

1. **dnf tuning** — `max_parallel_downloads=10`, `fastestmirror=True`.
2. **RPMFusion** — enables both **free** and **nonfree** release repos, then a
   full system upgrade.
3. **Flatpak** — installs `flatpak` and adds the **Flathub** remote.
4. **Multimedia codecs** — swaps `ffmpeg-free` → full `ffmpeg`, installs the
   `multimedia` / `sound-and-video` groups, the GStreamer plugin set
   (incl. RPMFusion `freeworld`/`ugly` plugins), and `libavcodec-freeworld`
   for hardware-accelerated browser video.
5. **KDE Plasma** — installs the `kde-desktop-environment` group plus a curated
   set of KDE applications, Wayland bits, and power/Bluetooth utilities.
6. **Curated utilities & fonts** — dev tools, CLI utilities, fonts, themes,
   Python libraries, and a Bash language server.
7. **Optional apps** — an interactive menu (see below).
8. **Services** — enables CUPS, Bluetooth, power-profiles-daemon, etc., and
   sets `graphical.target` as the default boot target.
9. **Shell config** — applies the portable XeroLinux `.bashrc` with
   **oh-my-posh** (installed to `/usr/local/bin`) and **fastfetch** on launch.
10. **SDDM** — installs SDDM, the **XeroDark** theme, and enables it.

## Optional application menu

When run, the script presents a numbered menu. Enter the numbers you want
(space-separated), or press Enter to skip. Each app installs via the best
method for Fedora:

| Tag   | Method                                                        |
|-------|---------------------------------------------------------------|
| *(none)* | Native `dnf` from Fedora or RPMFusion repos                |
| `[R]` | Official **vendor dnf repo** added on demand (Brave, Vivaldi, LibreWolf, VSCodium) |
| `[F]` | **Flatpak** from Flathub                                       |

Categories: Web Browsers, Social & Communication, Development Tools, Password
Managers, Creative & Imaging, Music & Audio, Video Editing, Office.

LibreOffice prompts for a language and pulls the matching `libreoffice-langpack-*`
and `hunspell-*` packages.

### Install-method notes

- **Native (dnf):** Firefox, Tor Browser, FileZilla, Telegram, Hugo, Meld,
  KeePassXC, pass, GIMP, Krita, Inkscape, MPV, Amarok, EasyEffects, Kdenlive,
  MKVToolNix, LibreOffice.
- **Vendor repo `[R]`:** Brave, Vivaldi, LibreWolf, VSCodium — official `.repo`
  added to `/etc/yum.repos.d/` only if selected.
- **Flatpak `[F]`:** Floorp, Mullvad Browser, Ungoogled Chromium, Zen, ZapZap,
  Discord, Vesktop, Ferdium, GitHub Desktop, Bitwarden, Spotify, Tenacity,
  JamesDSP, MakeMKV, Avidemux.
- **Unavailable on Fedora:** Helium Browser (no rpm, no Flatpak) — listed but
  skipped.

## Design notes

- **Resilient installs** — packages install in bulk; on any failure the script
  retries each one individually, so a single missing/broken package never
  aborts the run. Skipped packages are reported as warnings.
- **Package names verified** against Fedora 43 (`mdapi.fedoraproject.org`) and
  the Flathub API. RPMFusion-only and vendor-repo packages were cross-checked
  via Repology.
- **Self-destruct** — when run as a downloaded file the script removes itself on
  success. It does **not** delete anything when piped via `curl | bash`.

## Requirements

- A fresh **Fedora** install (Workstation, Server, or minimal) — tested target
  Fedora 41+.
- Network access and either root or `sudo`.

## License

Based on the XeroLinux installer. Check upstream licensing before redistribution.
