# FedInstall

Turn a fresh **Fedora** install into a ready-to-use **KDE Plasma** desktop —
one command, run it from a TTY after the base install.

## Run it

```bash
curl -fsSL https://raw.githubusercontent.com/DarkXero-dev/FedoraCrap/main/xero-kde-fedora.sh | bash
```

Works as root or with `sudo`.

## What you get

- RPMFusion (free + nonfree) + Flathub enabled
- KDE Plasma desktop (vanilla, Breeze Dark by default)
- Faster dnf (20 parallel downloads, fastest mirrors)
- Multimedia codecs that just work
- A handy set of utilities, fonts and dev tools
- An optional menu to pick extra apps (browsers, chat, editors, etc.)
- Plasma Login Manager + fastfetch on terminal start

## Optional apps

During the run you get a numbered menu. Type the numbers you want
(space-separated), or just press Enter to skip. Tags:

- *(no tag)* — installed from Fedora / RPMFusion
- `[R]` — official vendor repo (Brave, Vivaldi, LibreWolf, VSCodium)
- `[F]` — Flatpak from Flathub

When done, reboot:

```bash
sudo systemctl reboot
```
