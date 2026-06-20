# FedInstall

Turn a fresh **Fedora** install into a ready-to-use **KDE Plasma** desktop, one command one outcome.

<img width="1128" height="774" alt="FediCrap screenshot" src="FediCrap.webp" />

## Run it

Install **Base Fedora** using the [**Fedora Everything**](https://fedoraproject.org/misc/#everything) ISO and once on the TTY, login and run the following command.

```bash
curl -fsSL https://raw.githubusercontent.com/DarkXero-dev/FedoraCrap/main/xero-kde-fedora.sh | bash
```

## What you get

- RPMFusion (free + nonfree) + Flathub + Terra
- KDE Plasma desktop (vanilla, Breeze Dark by default)
- Faster dnf (20 parallel downloads, fastest mirrors)
- Multimedia codecs that just work
- A handy set of utilities, fonts and dev tools
- An optional menu to pick extra apps
- Plasma Login Manager + fastfetch on terminal start
- Optional XeroLinux Rice install menu

## Optional apps

During the run you get a numbered menu. Type the numbers you want (space-separated), or just press Enter to skip. Tags:

- *(no tag)* — installed from Fedora / RPMFusion
- `[R]` — official vendor repo (Brave, Vivaldi, LibreWolf, VSCodium)
- `[F]` — Flatpak from Flathub

When done, reboot:

```bash
sudo systemctl reboot
```
