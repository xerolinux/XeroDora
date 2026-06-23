#!/usr/bin/env bash

# XeroLinux KDE Plasma Installer - Fedora port v1.0
# Run from TTY after a minimal/Server Fedora install, or via:
#   curl -fsSL https://raw.githubusercontent.com/DarkXero-dev/FedoraCrap/main/xero-kde-fedora.sh | bash
#
# Enables RPMFusion (free + nonfree), installs KDE Plasma, multimedia codecs,
# a curated app/utility set, optional user-selected apps (native rpm where an
# official repo exists, Flatpak otherwise), and the Plasma Login Manager. Result
# is a vanilla Plasma desktop with Breeze Dark set as the default theme.

SCRIPT_PATH="$(readlink -f "$0" 2>/dev/null || echo "")"

# ── Colours ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

RULE="════════════════════════════════════════════════════"

print_header() {
    clear
    echo -e "${PURPLE}${RULE}${NC}"
    echo -e "    ${CYAN}✨ XeroLinux KDE Plasma Installer (Fedora) ✨${NC}"
    echo -e "${PURPLE}${RULE}${NC}"
    echo ""
}

print_step()    { echo -e "${BLUE}➜${NC} ${CYAN}$1${NC}"; }
print_success() { echo -e "${GREEN}✓${NC} $1"; }
print_error()   { echo -e "${RED}✗${NC} $1"; sleep 1; }
print_warning() { echo -e "${YELLOW}⚠${NC} $1"; sleep 1; }

# ── Phase header (sticky/pinned) ──────────────────────────────────────────────
# On a real terminal the phase header is pinned to the top rows via a DECSTBM
# scroll region; install output scrolls underneath it. When stdout is not a TTY
# (e.g. logged to a file) it degrades to a plain printed banner.

HEADER_ROWS=4          # rows reserved at the top for the pinned header
STICKY=0               # 1 once the scroll region is active
TERM_LINES=24
HEADER_INNER=54        # inner width of the header box

# Enable the pinned-header mode (called once, before the first phase).
term_init_sticky() {
    [[ -t 1 ]] || return 0
    TERM_LINES="$(tput lines 2>/dev/null || echo 24)"
    [[ "$TERM_LINES" -lt $((HEADER_ROWS + 4)) ]] && return 0   # tiny term → skip
    STICKY=1
    clear
    # Reserve the top HEADER_ROWS; scroll region = rest of the screen.
    printf '\033[%d;%dr' "$((HEADER_ROWS + 1))" "$TERM_LINES"
    printf '\033[%d;1H' "$((HEADER_ROWS + 1))"
}

# Restore the terminal (full-screen scrolling, cursor at bottom). Idempotent.
term_reset() {
    [[ "$STICKY" == 1 ]] || return 0
    printf '\033[r'                       # reset scroll region
    printf '\033[%d;1H' "$TERM_LINES"     # park cursor at the bottom
    STICKY=0
}
trap 'term_reset; stop_sudo_keepalive' EXIT INT TERM

# Draw the pinned header in the reserved rows, then clear + park the cursor in
# the scroll region so the next phase starts with a fresh area beneath it.
draw_sticky_header() {
    local title="$1" tip="${2:-}"
    local bar t
    bar="$(printf '═%.0s' $(seq 1 "$HEADER_INNER"))"
    # content = leading space + "▶ " (3 cols) + title padded to fill the rest
    printf -v t '%-*s' "$((HEADER_INNER - 3))" "${title:0:$((HEADER_INNER - 3))}"

    printf '\033[s'                        # save cursor (current scroll pos)
    printf '\033[1;1H'                     # top-left
    echo -e "\033[2K${PURPLE}╔${bar}╗${NC}"
    echo -e "\033[2K${PURPLE}║${NC} ${CYAN}▶ ${t}${NC}${PURPLE}║${NC}"
    echo -e "\033[2K${PURPLE}╚${bar}╝${NC}"
    if [[ -n "$tip" ]]; then
        echo -e "\033[2K  ${YELLOW}${tip}${NC}"
    else
        printf '\033[2K\n'
    fi
    printf '\033[u'                        # restore cursor
}

# print_phase <title> [tip]
print_phase() {
    if [[ "$STICKY" == 1 ]]; then
        draw_sticky_header "$1" "${2:-}"
    else
        echo ""
        echo -e "${PURPLE}════════════════════════════════════════════════════════${NC}"
        echo -e "${PURPLE}▶ ${CYAN}$1${NC}"
        [[ -n "${2:-}" ]] && echo -e "  ${YELLOW}$2${NC}"
        echo -e "${PURPLE}════════════════════════════════════════════════════════${NC}"
        echo ""
    fi
}

# ── Privilege handling ────────────────────────────────────────────────────────

SUDO_KEEPALIVE_PID=""

setup_sudo() {
    if [[ ${EUID:-0} -eq 0 ]]; then
        if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
            # Launched via `sudo bash script.sh` - works but rice configs will
            # land in /root. Running as your normal user is preferred:
            #   bash xero-kde-fedora.sh
            print_warning "Running as root via sudo. Prefer: bash xero-kde-fedora.sh (no sudo)"
            print_warning "Rice/theme configs will target ${SUDO_USER}'s home via sudo -H -u."
            sleep 2
        else
            print_step "Running as root."
        fi
        SUDO_CMD=""
    else
        if ! command -v sudo >/dev/null 2>&1; then
            print_error "sudo not found. Re-run as root or install sudo."
            exit 1
        fi
        SUDO_CMD="sudo"
        # Cache credentials now and keep the timestamp alive for the full install.
        # A typical KDE install takes 20-40 min - well past the default 15 min expiry.
        print_step "Caching sudo credentials..."
        sudo -v || { print_error "sudo auth failed."; exit 1; }
        ( while true; do sleep 50; sudo -n true 2>/dev/null; done ) &
        SUDO_KEEPALIVE_PID=$!
        print_success "sudo keepalive started (PID ${SUDO_KEEPALIVE_PID})."
    fi
}

stop_sudo_keepalive() {
    if [[ -n "${SUDO_KEEPALIVE_PID:-}" ]]; then
        kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
        SUDO_KEEPALIVE_PID=""
    fi
}

# ── Preflight ─────────────────────────────────────────────────────────────────

check_fedora() {
    if [[ ! -r /etc/os-release ]]; then
        print_error "/etc/os-release missing - cannot detect distro."
        exit 1
    fi
    # shellcheck disable=SC1091
    . /etc/os-release
    if [[ "${ID:-}" != "fedora" && "${ID_LIKE:-}" != *fedora* ]]; then
        print_error "Not Fedora (ID=${ID:-unknown}). Aborting."
        exit 1
    fi
    FEDORA_VER="$(rpm -E %fedora)"
    print_success "Fedora ${FEDORA_VER} detected."
}

# ── UI: confirmation ──────────────────────────────────────────────────────────

prompt_user() {
    print_header
    echo -e "${CYAN}This script will:${NC}"
    echo -e "  ${BLUE}•${NC} Enable RPMFusion (free + nonfree) + Flathub"
    echo -e "  ${BLUE}•${NC} Optionally enable Terra repo (Fyra Labs)"
    echo -e "  ${BLUE}•${NC} Install KDE Plasma Desktop + curated KDE apps"
    echo -e "  ${BLUE}•${NC} Install multimedia codecs (ffmpeg, gstreamer, hw accel)"
    echo -e "  ${BLUE}•${NC} Install a curated utility/font set"
    echo -e "  ${BLUE}•${NC} Your selected optional apps"
    echo -e "  ${BLUE}•${NC} Plasma Login Manager + Breeze Dark as the default Plasma theme"
    echo ""
    echo -e "${YELLOW}⚠ This will modify your system!${NC}"
    echo ""
    read -p "$(echo -e "${GREEN}Proceed? ${NC}[${GREEN}y${NC}/${RED}N${NC}]: ")" -n 1 -r </dev/tty
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_warning "Cancelled by user. Exiting..."
        exit 0
    fi
}

# ── Package install helpers (dnf) ─────────────────────────────────────────────

# install_group <name> <pkg...>
# Bulk install; on failure retry each package individually so one missing/bad
# package never blocks the rest. Never aborts - reports skipped as warnings.
install_group() {
    local group_name="$1"; shift
    local pkgs=("$@")

    print_step "[$group_name] Installing ${#pkgs[@]} packages..."
    if $SUDO_CMD dnf install -y "${pkgs[@]}"; then
        print_success "[$group_name] Done!"
        echo ""
        return 0
    fi

    print_warning "[$group_name] Bulk install failed - retrying individually..."
    local failed=() installed=0
    for pkg in "${pkgs[@]}"; do
        if $SUDO_CMD dnf install -y "$pkg"; then
            (( installed++ )) || true
        else
            failed+=("$pkg")
        fi
    done

    [[ ${#failed[@]} -gt 0 ]] && \
        print_warning "[$group_name] Skipped (${#failed[@]}): ${failed[*]}"
    print_success "[$group_name] Done - $installed installed, ${#failed[@]} skipped."
    echo ""
    return 0
}

# install_group_required <name> <pkg...> - aborts if ZERO installed.
install_group_required() {
    local group_name="$1"; shift
    local pkgs=("$@")

    print_step "[$group_name] Installing ${#pkgs[@]} packages (required)..."
    if $SUDO_CMD dnf install -y "${pkgs[@]}"; then
        print_success "[$group_name] Done!"
        echo ""
        return 0
    fi

    print_warning "[$group_name] Bulk install failed - retrying individually..."
    local failed=() installed=0
    for pkg in "${pkgs[@]}"; do
        if $SUDO_CMD dnf install -y "$pkg"; then
            (( installed++ )) || true
        else
            failed+=("$pkg")
        fi
    done

    [[ ${#failed[@]} -gt 0 ]] && \
        print_warning "[$group_name] Skipped (${#failed[@]}): ${failed[*]}"
    if [[ $installed -eq 0 ]]; then
        print_error "[$group_name] Critical: zero packages installed - aborting!"
        exit 1
    fi
    print_success "[$group_name] Done - $installed installed, ${#failed[@]} skipped."
    echo ""
    return 0
}

# install_dnf_group <comterm group-id>... - install a dnf comps group, non-fatal.
install_dnf_group() {
    local g="$1"
    print_step "Installing dnf group: $g ..."
    if $SUDO_CMD dnf group install -y "$g"; then
        print_success "Group '$g' installed!"
    else
        print_warning "Group '$g' failed or not found - continuing."
    fi
    echo ""
}

# ── Flatpak helpers ───────────────────────────────────────────────────────────

setup_flatpak() {
    print_phase "Setting up Flatpak (Flathub source)"
    print_step "Setting up Flatpak + Flathub..."
    $SUDO_CMD dnf install -y flatpak || print_warning "flatpak install failed"

    # Add the FULL Flathub remote (system-wide).
    $SUDO_CMD flatpak remote-add --if-not-exists flathub \
        https://flathub.org/repo/flathub.flatpakrepo \
        && print_success "Flathub remote added!" \
        || print_warning "Could not add Flathub remote (non-critical)"

    # Fedora ships its Flathub pre-filtered to a subset - drop the filter and
    # make sure it's enabled so the complete Flathub catalog is available.
    $SUDO_CMD flatpak remote-modify --enable flathub 2>/dev/null || true
    $SUDO_CMD flatpak remote-modify --no-filter flathub 2>/dev/null || true

    # Disable Fedora's own flatpak remotes (the OCI "fedora" ones) - an inferior,
    # half-maintained subset. Everything should come from Flathub instead.
    print_step "Disabling Fedora flatpak remotes..."
    for r in fedora fedora-testing; do
        if $SUDO_CMD flatpak remotes --system 2>/dev/null | awk '{print $1}' | grep -qx "$r"; then
            $SUDO_CMD flatpak remote-modify --disable "$r" 2>/dev/null \
                || $SUDO_CMD flatpak remote-delete --force "$r" 2>/dev/null
            print_success "Fedora flatpak remote '$r' disabled."
        fi
    done

    # Pin Flathub as the preferred source (lower number = higher priority).
    $SUDO_CMD flatpak remote-modify --prio=1 flathub 2>/dev/null || true
    echo ""
}

# flatpak_install <app-id>...
flatpak_install() {
    local apps=("$@")
    [[ ${#apps[@]} -eq 0 ]] && return 0
    print_step "[Flatpak] Installing ${#apps[@]} app(s)..."
    local failed=() installed=0
    for app in "${apps[@]}"; do
        if $SUDO_CMD flatpak install -y --noninteractive flathub "$app"; then
            (( installed++ )) || true
        else
            failed+=("$app")
        fi
    done
    [[ ${#failed[@]} -gt 0 ]] && \
        print_warning "[Flatpak] Skipped (${#failed[@]}): ${failed[*]}"
    print_success "[Flatpak] Done - $installed installed, ${#failed[@]} skipped."
    echo ""
}

# ── Vendor repo helpers (hybrid: native rpm where an official repo exists) ─────

add_brave_repo() {
    print_step "Adding Brave repo..."
    $SUDO_CMD curl -fsSLo /etc/yum.repos.d/brave-browser.repo \
        https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo 2>/dev/null \
        && print_success "Brave repo added!" \
        || print_warning "Failed to add Brave repo"
}

add_vivaldi_repo() {
    print_step "Adding Vivaldi repo..."
    $SUDO_CMD curl -fsSLo /etc/yum.repos.d/vivaldi-fedora.repo \
        https://repo.vivaldi.com/archive/vivaldi-fedora.repo 2>/dev/null \
        && print_success "Vivaldi repo added!" \
        || print_warning "Failed to add Vivaldi repo"
}

add_librewolf_repo() {
    print_step "Adding LibreWolf repo..."
    $SUDO_CMD curl -fsSLo /etc/yum.repos.d/librewolf.repo \
        https://repo.librewolf.net/librewolf.repo 2>/dev/null \
        && print_success "LibreWolf repo added!" \
        || print_warning "Failed to add LibreWolf repo"
}

add_vscodium_repo() {
    print_step "Adding VSCodium repo..."
    $SUDO_CMD rpm --import \
        https://gitlab.com/paulcarroty/vscodium-deb-rpm-repo/raw/master/pub.gpg 2>/dev/null
    printf '%s\n' \
        '[gitlab.com_paulcarroty_vscodium_repo]' \
        'name=download.vscodium.com' \
        'baseurl=https://download.vscodium.com/rpms/' \
        'enabled=1' \
        'gpgcheck=1' \
        'repo_gpgcheck=1' \
        'gpgkey=https://gitlab.com/paulcarroty/vscodium-deb-rpm-repo/raw/master/pub.gpg' \
        'metadata_expire=1h' \
        | $SUDO_CMD tee /etc/yum.repos.d/vscodium.repo >/dev/null \
        && print_success "VSCodium repo added!" \
        || print_warning "Failed to add VSCodium repo"
}

# ── System setup: RPMFusion + codecs ──────────────────────────────────────────

# Patch dnf BEFORE any install: fastest mirrors + 25 parallel downloads.
# set_dnf_opt <key> <value> - idempotent (replace existing line or append).
set_dnf_opt() {
    local key="$1" val="$2"
    if $SUDO_CMD grep -q "^${key}=" /etc/dnf/dnf.conf 2>/dev/null; then
        $SUDO_CMD sed -i "s|^${key}=.*|${key}=${val}|" /etc/dnf/dnf.conf
    else
        echo "${key}=${val}" | $SUDO_CMD tee -a /etc/dnf/dnf.conf >/dev/null
    fi
}

tune_dnf() {
    print_phase "Tuning dnf (fastest mirrors, 20 parallel downloads)"
    print_step "Patching /etc/dnf/dnf.conf..."
    $SUDO_CMD touch /etc/dnf/dnf.conf 2>/dev/null || true
    # librepo (dnf5) hard-caps parallel downloads at 20 - higher = "Bad value
    # of LRO_MAXPARALLELDOWNLOADS" and all metadata fails.
    set_dnf_opt max_parallel_downloads 20
    set_dnf_opt fastestmirror True
    set_dnf_opt defaultyes True
    set_dnf_opt keepcache False
    print_success "dnf tuned - 20 parallel downloads, fastestmirror on."
    echo ""
}

enable_rpmfusion() {
    print_phase "Enabling RPMFusion + system upgrade"
    print_step "Enabling RPMFusion (free + nonfree)..."
    $SUDO_CMD dnf install -y \
        "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${FEDORA_VER}.noarch.rpm" \
        "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${FEDORA_VER}.noarch.rpm" \
        || { print_error "RPMFusion enable failed!"; exit 1; }
    print_success "RPMFusion enabled!"
    echo ""

    print_step "Updating system + core group..."
    $SUDO_CMD dnf -y group upgrade core || true
    $SUDO_CMD dnf -y upgrade --refresh || print_warning "System upgrade had errors - continuing."
    # appstream metadata for KDE Discover / Flatpak
    $SUDO_CMD dnf install -y rpmfusion-free-appstream-data rpmfusion-nonfree-appstream-data || true
    print_success "System updated!"
    echo ""
}

enable_terra() {
    print_phase "Enabling Terra repo (Fyra Labs)"

    # Pre-import the Terra GPG key BEFORE any DNF operation. DNF5 checks the
    # key for repomd.xml (repo_gpgcheck=1) before it can install terra-release,
    # so we fetch it directly from upstream and trust it first. This avoids
    # both the "Signing key not found" error and the need to use --nogpgcheck.
    print_step "Pre-importing Terra GPG key..."
    local key_ok=0
    if curl -fsSL "https://repos.fyralabs.com/terra${FEDORA_VER}/key.asc" \
            -o /tmp/terra-pubkey.gpg 2>/dev/null \
        && $SUDO_CMD rpm --import /tmp/terra-pubkey.gpg 2>/dev/null; then
        print_success "Terra GPG key imported."
        key_ok=1
    else
        print_warning "Could not fetch Terra GPG key - will fall back to --nogpgcheck."
    fi
    rm -f /tmp/terra-pubkey.gpg

    print_step "Installing terra-release..."
    # shellcheck disable=SC2016
    local terra_url='https://repos.fyralabs.com/terra$releasever'
    if [[ $key_ok -eq 1 ]]; then
        $SUDO_CMD dnf install -y \
            --repofrompath "terra,${terra_url}" \
            terra-release 2>/dev/null \
            && print_success "Terra repo enabled!" \
            || key_ok=0   # fall through to --nogpgcheck retry
    fi
    if [[ $key_ok -eq 0 ]]; then
        $SUDO_CMD dnf install -y --nogpgcheck \
            --repofrompath "terra,${terra_url}" \
            terra-release \
            && print_success "Terra repo enabled (fallback --nogpgcheck)." \
            || { print_warning "Terra repo install failed - continuing without it."; return 0; }
    fi

    print_step "Refreshing repo metadata (RPMFusion + Terra)..."
    $SUDO_CMD dnf clean metadata
    $SUDO_CMD dnf -y makecache \
        && print_success "Repo metadata refreshed!" \
        || print_warning "Metadata refresh had errors - some packages may 404."
    echo ""
}

install_codecs() {
    print_phase "Installing multimedia codecs"
    print_step "Installing multimedia codecs..."

    # Swap the limited ffmpeg-free for the full RPMFusion ffmpeg
    $SUDO_CMD dnf swap -y ffmpeg-free ffmpeg --allowerasing \
        || $SUDO_CMD dnf install -y ffmpeg --allowerasing \
        || print_warning "ffmpeg swap/install had issues"

    # Multimedia + sound-and-video groups (full gstreamer plugin set)
    $SUDO_CMD dnf group install -y multimedia \
        --setopt="install_weak_deps=False" \
        --exclude=PackageKit-gstreamer-plugin || true
    $SUDO_CMD dnf group install -y sound-and-video || true

    install_group "Codecs" \
        gstreamer1-plugins-base gstreamer1-plugins-good gstreamer1-plugins-good-extras \
        gstreamer1-plugins-bad-free gstreamer1-plugins-bad-free-extras \
        gstreamer1-plugins-bad-freeworld gstreamer1-plugins-ugly-free \
        gstreamer1-plugins-ugly gstreamer1-plugin-openh264 gstreamer1-libav \
        libavcodec-freeworld lame lame-libs

    print_success "Codecs installed!"
    echo ""
}

# ── KDE Plasma + apps ─────────────────────────────────────────────────────────

install_plasma() {
    print_phase "Installing KDE Plasma desktop" \
        "☕ This phase pulls a lot of packages and may take a while - sit back, grab a coffee."
    print_step "Installing KDE Plasma desktop..."
    # Fedora's curated Plasma group - guarantees a complete, existing package set.
    install_dnf_group kde-desktop-environment

    # Belt-and-suspenders core bits in case the group is trimmed.
    install_group_required "KDE Plasma Core" \
        plasma-workspace plasma-desktop plasma-systemmonitor kscreen \
        plasma-nm plasma-pa powerdevil kinfocenter systemsettings \
        kde-gtk-config breeze-gtk plasma-browser-integration \
        xdg-desktop-portal-kde plasma-discover plasma-discover-flatpak

    install_group "KDE Applications" \
        dolphin dolphin-plugins konsole kate ark gwenview okular spectacle \
        filelight kfind kcalc kcharselect kcolorchooser kgpg kwalletmanager5 \
        kde-connect krfb krdc skanlite kamoso k3b yakuake kio-extras kio-admin \
        kio-gdrive kdenetwork-filesharing kcolorchooser markdownpart qalculate-qt \
        kdegraphics-thumbnailers ffmpegthumbs

    install_group "Wayland & Display" \
        qt6-qtwayland xdg-desktop-portal-gtk xorg-x11-server-Xwayland

    install_group "Power & Hardware" \
        power-profiles-daemon brightnessctl switcheroo-control bolt \
        bluez bluez-tools

    echo ""
}

# ── Curated utilities + fonts (Fedora-mapped from the Arch set) ───────────────

install_utilities() {
    print_phase "Installing curated utilities & fonts"
    print_step "Installing curated utilities..."

    install_group "System Utilities" \
        git curl wget gcc gcc-c++ make cmake meson ninja-build pkgconf-pkg-config \
        nodejs npm jq yq tree htop btop duf inxi lshw hwinfo lm_sensors nvtop \
        unzip zip p7zip p7zip-plugins unrar lzop tar bzip2 xz zstd \
        ripgrep fd-find fzf bat eza zoxide most mc tmux \
        fastfetch figlet lolcat gum \
        gparted gnome-disk-utility udisks2 ntfs-3g exfatprogs dosfstools \
        cifs-utils nfs-utils sshfs fuse fuse3 \
        usbutils pciutils iputils bind-utils nmap iftop vnstat ethtool tcpdump \
        playerctl yt-dlp wavpack \
        flatpak dnf-plugins-core dnf-utils \
        graphviz xmlstarlet gettext intltool \
        polkit cronie plocate bash-completion xdg-user-dirs xdg-utils \
        timeshift smartmontools cryptsetup lvm2 mdadm hdparm \
        wireguard-tools nvme-cli usbmuxd

    install_group "Fonts & Themes" \
        fira-code-fonts jetbrains-mono-fonts jetbrains-mono-nl-fonts \
        google-roboto-fonts google-noto-sans-fonts google-noto-emoji-fonts \
        adobe-source-sans-pro-fonts adobe-source-code-pro-fonts \
        liberation-fonts dejavu-sans-fonts dejavu-sans-mono-fonts \
        kvantum adw-gtk3-theme rsms-inter-fonts

    install_group "Python Libraries" \
        python3-pip python3-cffi python3-numpy python3-pygments python3-websockets \
        python3-pyaudio

    install_group "Language Servers" \
        nodejs-bash-language-server || true

    echo ""
}

# ── User app selection ────────────────────────────────────────────────────────

customization_prompts() {
    clear
    echo -e "${PURPLE}═══════════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${PURPLE}                PACKAGE SELECTION -- Choose Your Apps${NC}"
    echo -e "${CYAN}     Enter numbers separated by spaces, or press Enter to skip all${NC}"
    echo -e "${CYAN}     [F] = installed via Flatpak, [R] = via official vendor repo${NC}"
    echo -e "${PURPLE}═══════════════════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "${CYAN}-- WEB BROWSERS -----------------------------------------------------------${NC}"
    echo ""
    echo -e "  ${CYAN} 1)${NC} Floorp [F]          ${CYAN} 2)${NC} Firefox             ${CYAN} 3)${NC} Brave [R]"
    echo -e "  ${CYAN} 4)${NC} LibreWolf [R]       ${CYAN} 5)${NC} Vivaldi [R]         ${CYAN} 6)${NC} Tor Browser"
    echo -e "  ${CYAN} 7)${NC} Mullvad Browser [F] ${CYAN} 8)${NC} Ungoogled Chrom [F] ${CYAN} 9)${NC} FileZilla"
    echo -e "  ${CYAN}10)${NC} Zen Browser [F]"
    echo ""
    echo -e "${GREEN}-- SOCIAL & COMMUNICATION -------------------------------------------------${NC}"
    echo ""
    echo -e "  ${GREEN}11)${NC} ZapZap (WA) [F]     ${GREEN}12)${NC} Discord [F]         ${GREEN}13)${NC} Vesktop [F]"
    echo -e "  ${GREEN}14)${NC} Telegram            ${GREEN}15)${NC} Ferdium [F]"
    echo ""
    echo -e "${PURPLE}-- DEVELOPMENT TOOLS ------------------------------------------------------${NC}"
    echo ""
    echo -e "  ${PURPLE}16)${NC} Hugo                ${PURPLE}17)${NC} Meld                ${PURPLE}18)${NC} VSCodium [R]"
    echo -e "  ${PURPLE}19)${NC} GitHub Desktop [F]"
    echo ""
    echo -e "${YELLOW}-- PASSWORD MANAGERS -------------------------------------------------------${NC}"
    echo ""
    echo -e "  ${YELLOW}20)${NC} KeePassXC           ${YELLOW}21)${NC} Bitwarden [F]       ${YELLOW}22)${NC} pass"
    echo ""
    echo -e "${BLUE}-- CREATIVE & IMAGING -----------------------------------------------------${NC}"
    echo ""
    echo -e "  ${BLUE}23)${NC} GIMP                ${BLUE}24)${NC} Krita               ${BLUE}25)${NC} Inkscape"
    echo ""
    echo -e "${RED}-- MUSIC & AUDIO ----------------------------------------------------------${NC}"
    echo ""
    echo -e "  ${RED}26)${NC} MPV                 ${RED}27)${NC} Amarok              ${RED}28)${NC} Spotify [F]"
    echo -e "  ${RED}29)${NC} Tenacity [F]        ${RED}30)${NC} JamesDSP [F]        ${RED}31)${NC} EasyEffects"
    echo ""
    echo -e "${GREEN}-- VIDEO EDITING ----------------------------------------------------------${NC}"
    echo ""
    echo -e "  ${GREEN}32)${NC} MakeMKV [F]         ${GREEN}33)${NC} Kdenlive            ${GREEN}34)${NC} Avidemux [F]"
    echo -e "  ${GREEN}35)${NC} MKVToolNix"
    echo ""
    echo -e "${CYAN}-- OFFICE -----------------------------------------------------------------${NC}"
    echo ""
    echo -e "  ${CYAN}36)${NC} LibreOffice"
    echo ""
    read -p ">> Your choices: " user_input </dev/tty

    DNF_APPS=""        # native repo / rpmfusion packages
    FLAT_APPS=""       # flathub app-ids
    NEED_BRAVE="" NEED_VIVALDI="" NEED_LIBREWOLF="" NEED_VSCODIUM=""
    WANTS_LIBREOFFICE=""
    WANT_TERRA=""

    for choice in $user_input; do
        case $choice in
            1)  FLAT_APPS="$FLAT_APPS one.ablaze.floorp" ;;
            2)  DNF_APPS="$DNF_APPS firefox" ;;
            3)  NEED_BRAVE="yes"; DNF_APPS="$DNF_APPS brave-browser" ;;
            4)  NEED_LIBREWOLF="yes"; DNF_APPS="$DNF_APPS librewolf" ;;
            5)  NEED_VIVALDI="yes"; DNF_APPS="$DNF_APPS vivaldi-stable" ;;
            6)  DNF_APPS="$DNF_APPS torbrowser-launcher" ;;
            7)  FLAT_APPS="$FLAT_APPS net.mullvad.MullvadBrowser" ;;
            8)  FLAT_APPS="$FLAT_APPS io.github.ungoogled_software.ungoogled_chromium" ;;
            9)  DNF_APPS="$DNF_APPS filezilla" ;;
            10) FLAT_APPS="$FLAT_APPS app.zen_browser.zen" ;;
            11) FLAT_APPS="$FLAT_APPS com.rtosta.zapzap" ;;
            12) FLAT_APPS="$FLAT_APPS com.discordapp.Discord" ;;
            13) FLAT_APPS="$FLAT_APPS dev.vencord.Vesktop" ;;
            14) DNF_APPS="$DNF_APPS telegram-desktop" ;;
            15) FLAT_APPS="$FLAT_APPS org.ferdium.Ferdium" ;;
            16) DNF_APPS="$DNF_APPS hugo" ;;
            17) DNF_APPS="$DNF_APPS meld" ;;
            18) NEED_VSCODIUM="yes"; DNF_APPS="$DNF_APPS codium" ;;
            19) FLAT_APPS="$FLAT_APPS io.github.shiftey.Desktop" ;;
            20) DNF_APPS="$DNF_APPS keepassxc" ;;
            21) FLAT_APPS="$FLAT_APPS com.bitwarden.desktop" ;;
            22) DNF_APPS="$DNF_APPS pass" ;;
            23) DNF_APPS="$DNF_APPS gimp" ;;
            24) DNF_APPS="$DNF_APPS krita" ;;
            25) DNF_APPS="$DNF_APPS inkscape" ;;
            26) DNF_APPS="$DNF_APPS mpv" ;;
            27) DNF_APPS="$DNF_APPS amarok" ;;
            28) FLAT_APPS="$FLAT_APPS com.spotify.Client" ;;
            29) FLAT_APPS="$FLAT_APPS org.tenacityaudio.Tenacity" ;;
            30) FLAT_APPS="$FLAT_APPS me.timschneeberger.jdsp4linux" ;;
            31) DNF_APPS="$DNF_APPS easyeffects" ;;
            32) FLAT_APPS="$FLAT_APPS com.makemkv.MakeMKV" ;;
            33) DNF_APPS="$DNF_APPS kdenlive" ;;
            34) FLAT_APPS="$FLAT_APPS org.avidemux.Avidemux" ;;
            35) DNF_APPS="$DNF_APPS mkvtoolnix-gui" ;;
            36) WANTS_LIBREOFFICE="yes" ;;
        esac
    done

    DNF_APPS="$(echo "$DNF_APPS" | xargs)"
    FLAT_APPS="$(echo "$FLAT_APPS" | xargs)"

    # ── LibreOffice language ──────────────────────────────────────────────────
    LO_PKGS=""
    if [[ -n "$WANTS_LIBREOFFICE" ]]; then
        echo ""
        echo -e "${CYAN}LibreOffice selected -- choose language (UI langpack + spellcheck):${NC}"
        echo ""
        LO_LANG_MENU=(
            "Use system locale|SYSTEM"
            "English|en"
            "German|de"
            "French|fr"
            "Spanish|es"
            "Italian|it"
            "Dutch|nl"
            "Polish|pl"
            "Russian|ru"
            "Greek|el"
            "Portuguese|pt"
            "Custom (enter lang code)|CUSTOM"
        )
        for i in "${!LO_LANG_MENU[@]}"; do
            idx=$((i + 1))
            IFS='|' read -r label code <<< "${LO_LANG_MENU[$i]}"
            echo -e "  ${BLUE}${idx})${NC} ${label}"
        done
        echo ""
        read -p "Enter choice (default: English): " lang_choice </dev/tty
        [[ -z "$lang_choice" ]] && lang_choice=2
        if ! [[ "$lang_choice" =~ ^[0-9]+$ ]] || (( lang_choice < 1 || lang_choice > ${#LO_LANG_MENU[@]} )); then
            lang_choice=2
        fi
        IFS='|' read -r _ LO_CODE <<< "${LO_LANG_MENU[$((lang_choice - 1))]}"

        if [[ "$LO_CODE" == "SYSTEM" ]]; then
            sys_loc="$(locale 2>/dev/null | awk -F= '/^LANG=/{print $2}' | tr -d '"')"
            sys_loc="${sys_loc:-en_US}"
            LO_CODE="${sys_loc%%_*}"
        elif [[ "$LO_CODE" == "CUSTOM" ]]; then
            read -p "Enter lang code (e.g. en, de, fr, es, pt): " LO_CODE </dev/tty
            LO_CODE="${LO_CODE%%_*}"
            LO_CODE="${LO_CODE:-en}"
        fi
        LO_CODE="${LO_CODE,,}"
        # libreoffice-langpack-* and hunspell-* exist for most codes; missing
        # ones are skipped by install_group's individual retry.
        LO_PKGS="libreoffice libreoffice-langpack-${LO_CODE} hunspell hunspell-${LO_CODE}"
    fi

    # ── Terra repo ────────────────────────────────────────────────────────────
    echo ""
    echo -e "${PURPLE}═══════════════════════════════════════════════════════════════════════${NC}"
    echo -e "  ${CYAN}Terra repo (Fyra Labs) adds extra packages not in Fedora/RPMFusion.${NC}"
    echo -e "  ${YELLOW}Note: requires GPG key trust; may show a prompt on first use.${NC}"
    echo -e "${PURPLE}═══════════════════════════════════════════════════════════════════════${NC}"
    read -p "$(echo -e "${GREEN}Enable Terra repo? ${NC}[${GREEN}y${NC}/${RED}N${NC}]: ")" -n 1 -r </dev/tty
    echo ""
    [[ $REPLY =~ ^[Yy]$ ]] && WANT_TERRA="yes"

    # ── Summary ───────────────────────────────────────────────────────────────
    echo ""
    echo -e "${PURPLE}═══════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}Selection Summary:${NC}"
    [[ -n "$DNF_APPS" ]]  && echo -e "  Native (dnf):   ${CYAN}$DNF_APPS${NC}"
    [[ -n "$FLAT_APPS" ]] && echo -e "  Flatpak:        ${CYAN}$FLAT_APPS${NC}"
    [[ -n "$LO_PKGS" ]]   && echo -e "  LibreOffice:    ${CYAN}$LO_PKGS${NC}"
    if [[ -z "$DNF_APPS$FLAT_APPS$LO_PKGS" ]]; then
        echo -e "  ${YELLOW}(no apps selected)${NC}"
    fi
    echo -e "${PURPLE}═══════════════════════════════════════════════════════════════════════${NC}"
    echo ""
    read -p "Press Enter to begin installation..." </dev/tty
}

install_user_packages() {
    print_phase "Installing your selected apps"
    print_step "Installing user-selected apps..."
    echo ""

    # Add vendor repos only for what was selected
    [[ -n "$NEED_BRAVE" ]]     && add_brave_repo
    [[ -n "$NEED_VIVALDI" ]]   && add_vivaldi_repo
    [[ -n "$NEED_LIBREWOLF" ]] && add_librewolf_repo
    [[ -n "$NEED_VSCODIUM" ]]  && add_vscodium_repo
    [[ -n "$NEED_BRAVE$NEED_VIVALDI$NEED_LIBREWOLF$NEED_VSCODIUM" ]] && \
        $SUDO_CMD dnf makecache

    # shellcheck disable=SC2086
    [[ -n "$DNF_APPS" ]]  && install_group "Native Apps" $DNF_APPS
    # shellcheck disable=SC2086
    [[ -n "$LO_PKGS" ]]   && install_group "LibreOffice" $LO_PKGS
    # shellcheck disable=SC2086
    [[ -n "$FLAT_APPS" ]] && flatpak_install $FLAT_APPS

    print_success "User-selected apps processed!"
    echo ""
}

# ── Finalize: services + default target ───────────────────────────────────────

enable_service_if_available() {
    local svc="$1"
    if $SUDO_CMD systemctl cat "$svc" &>/dev/null; then
        $SUDO_CMD systemctl enable "$svc" &>/dev/null \
            && print_success "Enabled: $svc" \
            || print_warning "Failed to enable $svc"
    else
        print_warning "Unit $svc not found - skipping"
    fi
}

finalize_system() {
    print_phase "Finalizing system (services + boot target)"
    print_step "Finalizing system configuration... ⚙️"
    echo ""

    print_step "Enabling core services..."
    enable_service_if_available cups.socket
    enable_service_if_available bluetooth.service
    enable_service_if_available power-profiles-daemon.service
    enable_service_if_available switcheroo-control.service
    enable_service_if_available udisks2.service
    print_success "Core services processed!"
    echo ""

    print_step "Setting graphical boot target..."
    $SUDO_CMD systemctl set-default graphical.target &>/dev/null \
        && print_success "Default target = graphical.target" \
        || print_warning "Could not set default target"
    echo ""
}

# ── fastfetch on terminal launch ──────────────────────────────────────────────
# Ask the user, then append a fastfetch hook to the real user's ~/.bashrc.
setup_fastfetch_hook() {
    print_phase "Fastfetch on terminal launch"
    read -p "$(echo -e "${GREEN}Show system info (fastfetch) on every terminal open? ${NC}[${GREEN}y${NC}/${RED}N${NC}]: ")" -n 1 -r </dev/tty
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_warning "Skipping fastfetch hook."
        echo ""; return 0
    fi
    print_step "Hooking fastfetch into ~/.bashrc..."

    # Determine the real (non-root) user
    local user home
    if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
        user="$SUDO_USER"
    elif [[ -n "${USER:-}" && "${USER}" != "root" ]]; then
        user="$USER"
    elif [[ "$(id -un 2>/dev/null)" != "root" ]]; then
        user="$(id -un)"
    else
        user="$(getent passwd | awk -F: '$3 >= 1000 && $3 < 65534 && $1 != "nobody" && $6 ~ /^\/home\// {print $1; exit}')"
    fi
    if [[ -z "${user:-}" ]]; then
        print_warning "Could not determine target user - skipping fastfetch hook."
        echo ""; return 0
    fi
    home="$(getent passwd "$user" | cut -d: -f6)"
    if [[ -z "${home:-}" || ! -d "$home" ]]; then
        print_warning "Home dir for $user not found - skipping fastfetch hook."
        echo ""; return 0
    fi

    if grep -qF "clear && fastfetch" "$home/.bashrc" 2>/dev/null; then
        print_success "fastfetch hook already present."
    else
        printf '\n%s\n%s\n' "# Fastfetch on terminal start" "clear && fastfetch" \
            >> "$home/.bashrc"
        $SUDO_CMD chown "$user:$user" "$home/.bashrc" 2>/dev/null || true
        print_success "fastfetch hook added for $user."
    fi
    echo ""
}

# ── Plasma Login Manager + Breeze Dark default ────────────────────────────────

setup_login_manager() {
    print_phase "Setting up Plasma Login Manager + Breeze Dark"
    print_step "Installing plasma-login-manager..."
    $SUDO_CMD dnf install -y plasma-login-manager \
        || { print_error "Failed to install plasma-login-manager!"; exit 1; }
    print_success "Plasma Login Manager installed!"
    echo ""

    print_step "Enabling plasmalogin.service..."
    # Disable any other display manager first (harmless if absent).
    $SUDO_CMD systemctl disable gdm.service &>/dev/null || true
    $SUDO_CMD systemctl disable sddm.service &>/dev/null || true
    $SUDO_CMD systemctl enable plasmalogin.service \
        && print_success "plasmalogin.service enabled!" \
        || { print_error "Failed to enable plasmalogin.service!"; exit 1; }
    echo ""

    # Make Breeze Dark the system-wide Plasma default (look-and-feel + color
    # scheme). Written to /etc/xdg so it applies to every user who hasn't picked
    # their own theme - no per-user config files touched.
    print_step "Setting Breeze Dark as default Plasma theme..."
    $SUDO_CMD mkdir -p /etc/xdg
    printf '%s\n' \
        '[General]' \
        'ColorScheme=BreezeDark' \
        '' \
        '[KDE]' \
        'LookAndFeelPackage=org.kde.breezedark.desktop' \
        | $SUDO_CMD tee /etc/xdg/kdeglobals >/dev/null \
        && print_success "Default theme = Breeze Dark." \
        || print_warning "Could not write default theme (non-critical)"
    echo ""
}

# ── Branding: os-release + lsb-release ───────────────────────────────────────

setup_branding() {
    print_phase "Applying XeroLinux Fedora branding"

    # Patch a key=value line in /etc/os-release: replace if present, append if not.
    # Keeps ID=fedora and VERSION_ID untouched (DNF/RPM rely on them).
    patch_os_release() {
        local key="$1" val="$2"
        if $SUDO_CMD grep -q "^${key}=" /etc/os-release 2>/dev/null; then
            $SUDO_CMD sed -i "s|^${key}=.*|${key}=${val}|" /etc/os-release
        else
            echo "${key}=${val}" | $SUDO_CMD tee -a /etc/os-release >/dev/null
        fi
    }

    print_step "Patching /etc/os-release..."
    patch_os_release NAME            '"XeroLinux Fedora"'
    patch_os_release PRETTY_NAME     '"XeroLinux KDE (Fedora '"${FEDORA_VER}"')"'
    patch_os_release HOME_URL        '"https://xerolinux.xyz"'
    patch_os_release DOCUMENTATION_URL '"https://github.com/DarkXero-dev/FedoraCrap"'
    patch_os_release SUPPORT_URL     '"https://github.com/DarkXero-dev/FedoraCrap/discussions"'
    patch_os_release BUG_REPORT_URL  '"https://github.com/DarkXero-dev/FedoraCrap/issues"'
    patch_os_release VARIANT         '"KDE Plasma"'
    patch_os_release VARIANT_ID      'kde'
    print_success "/etc/os-release patched!"

    print_step "Writing /etc/lsb-release..."
    printf '%s\n' \
        'DISTRIB_ID="XeroLinux"' \
        "DISTRIB_RELEASE=\"${FEDORA_VER}\"" \
        'DISTRIB_CODENAME="Fedora"' \
        "DISTRIB_DESCRIPTION=\"XeroLinux KDE Fedora ${FEDORA_VER}\"" \
        | $SUDO_CMD tee /etc/lsb-release >/dev/null \
        && print_success "/etc/lsb-release written!" \
        || print_warning "Could not write /etc/lsb-release (non-critical)"

    # Fix GRUB menu entries so they show "XeroLinux Fedora" instead of "Fedora Linux".
    # Two parts: BLS entry files (current boot entries) + GRUB_DISTRIBUTOR (future kernels).
    print_step "Patching GRUB menu titles..."
    local bls_patched=0
    for f in /boot/loader/entries/*.conf; do
        [[ -f "$f" ]] || continue
        $SUDO_CMD sed -i 's/^title Fedora Linux/title XeroLinux Fedora/' "$f" && bls_patched=1
    done
    [[ $bls_patched -eq 1 ]] \
        && print_success "BLS boot entries updated." \
        || print_warning "No BLS entries found at /boot/loader/entries/ - skipping."

    # GRUB_DISTRIBUTOR controls the title for kernels installed in the future.
    if [[ -f /etc/default/grub ]]; then
        $SUDO_CMD sed -i \
            's|^GRUB_DISTRIBUTOR=.*|GRUB_DISTRIBUTOR="XeroLinux Fedora"|' \
            /etc/default/grub \
            && print_success "GRUB_DISTRIBUTOR set." \
            || print_warning "Could not patch /etc/default/grub."
    fi

    # Regenerate grub.cfg so the changes are picked up immediately.
    print_step "Regenerating grub.cfg..."
    if $SUDO_CMD grub2-mkconfig -o /boot/grub2/grub.cfg 2>/dev/null; then
        print_success "grub.cfg regenerated."
    elif $SUDO_CMD grub2-mkconfig -o /boot/efi/EFI/fedora/grub.cfg 2>/dev/null; then
        print_success "grub.cfg regenerated (EFI path)."
    else
        print_warning "grub2-mkconfig failed - reboot may still show old titles."
    fi
    echo ""
}

# ── Optional: XeroLinux Layan KDE Rice ───────────────────────────────────────

prompt_layan_rice() {
    clear
    echo -e "${PURPLE}═══════════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${PURPLE}              ✨  XeroLinux Layan KDE Rice  ✨${NC}"
    echo -e "${PURPLE}───────────────────────────────────────────────────────────────────────────${NC}"
    echo -e "${CYAN}     A curated Layan theme stack: icons, colours, Kvantum,${NC}"
    echo -e "${CYAN}     cursors & Plasma look-and-feel - auto-detected for Fedora.${NC}"
    echo -e "${PURPLE}═══════════════════════════════════════════════════════════════════════════${NC}"
    echo ""
    read -p "$(echo -e "${GREEN}Apply Layan rice? ${NC}[${GREEN}y${NC}/${RED}N${NC}]: ")" -n 1 -r </dev/tty
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_warning "Skipping Layan rice."
        echo ""; return 0
    fi

    print_phase "Applying XeroLinux Layan KDE Rice"

    if ! command -v git >/dev/null 2>&1; then
        print_warning "git not found - cannot clone Layan rice. Skipping."
        echo ""; return 0
    fi

    # Resolve the real (non-root) user. install.sh copies configs to $HOME, so
    # running it as root deposits everything in /root instead of the user's home.
    local real_user=""
    if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
        real_user="$SUDO_USER"
    elif [[ ${EUID:-0} -ne 0 ]]; then
        real_user="${USER:-$(id -un)}"
    else
        real_user="$(getent passwd | awk -F: '$3 >= 1000 && $3 < 65534 && $6 ~ /^\/home\// {print $1; exit}')"
    fi

    local tmp_dir
    tmp_dir="$(mktemp -d)"
    print_step "Cloning xero-layan-git..."
    if ! git clone https://github.com/xerolinux/xero-layan-git "$tmp_dir/xero-layan-git"; then
        print_error "Clone failed - skipping Layan rice."
        rm -rf "$tmp_dir"; echo ""; return 0
    fi

    # Patch install.sh:
    # - drop -e from set -eu so a package failure does not abort the script
    # - skip GRUB theme (not needed on Fedora)
    # - skip the interactive fastfetch-to-bashrc prompt; xero-kde-fedora.sh
    #   handles that itself via setup_fastfetch_hook (called after this function
    #   returns), so the rice does not double-add or try to write to an unknown rc
    print_step "Patching install.sh for Fedora..."
    sed -i \
        -e 's/^set -eu$/set -u/' \
        -e 's|sudo ./Grub.sh|echo "GRUB theme skipped on Fedora."|' \
        -e '/set_grub_option GRUB_TIMEOUT/d' \
        -e '/set_grub_option GRUB_TIMEOUT_STYLE/d' \
        -e '/set_grub_option GRUB_GFXMODE/d' \
        -e 's/^read -p "Enable fastfetch on terminal launch.*$/response=n  # fastfetch handled by xero-kde-fedora.sh/' \
        "$tmp_dir/xero-layan-git/install.sh"
    print_success "Patched."

    local exit_code=0
    if [[ "${EUID:-0}" -ne 0 ]]; then
        # Normal user (preferred): $HOME is already correct, install.sh uses its
        # own sudo for root writes. Just run it directly with TTY access.
        print_step "Running Layan install.sh..."
        ( cd "$tmp_dir/xero-layan-git" && bash install.sh ) </dev/tty \
            || exit_code=$?
    elif [[ -n "$real_user" ]]; then
        # Running as root (via sudo): drop to the real user so configs land in
        # their home. sudo -H ensures $HOME is set correctly. install.sh re-
        # escalates via its own `sudo ./Grub.sh` for system writes.
        print_step "Running Layan install.sh as ${real_user}..."
        chown -R "${real_user}:${real_user}" "$tmp_dir"
        sudo -H -u "$real_user" bash -c \
            "cd '$tmp_dir/xero-layan-git' && bash install.sh" </dev/tty \
            || exit_code=$?
    else
        # True root with no detectable normal user (bare root login).
        print_step "Running Layan install.sh as root..."
        ( cd "$tmp_dir/xero-layan-git" && bash install.sh ) </dev/tty \
            || exit_code=$?
    fi

    # Verify rice landed - kvantum config is one of the first things copied.
    local rice_ok=0
    local check_home="${HOME}"
    [[ "${EUID:-0}" -eq 0 && -n "$real_user" ]] && \
        check_home="$(getent passwd "$real_user" | cut -d: -f6)"
    [[ -f "${check_home}/.config/kvantum/kvantum.kvconfig" ]] && rice_ok=1

    if [[ $rice_ok -eq 1 ]]; then
        print_success "Layan rice applied and verified!"
    elif [[ $exit_code -eq 0 ]]; then
        print_warning "install.sh exited cleanly but rice config not detected - reboot and check."
    else
        print_warning "install.sh finished with code ${exit_code} - check output above."
    fi

    rm -rf "$tmp_dir"
    echo ""
}

# ── Completion ────────────────────────────────────────────────────────────────

show_completion() {
    print_header
    echo -e "${GREEN}${RULE}${NC}"
    echo -e "            ${GREEN}🎉 Installation Complete! 🎉${NC}"
    echo -e "${GREEN}${RULE}${NC}"
    echo ""
    echo -e "  ${CYAN}Your KDE Plasma desktop is ready.${NC}"
    echo -e "  Reboot to start using it:"
    echo ""
    echo -e "    ${YELLOW}sudo systemctl reboot${NC}"
    echo ""
}

# ── Main ──────────────────────────────────────────────────────────────────────

setup_sudo
check_fedora
prompt_user
customization_prompts

term_init_sticky      # pin phase headers to the top; output scrolls below

tune_dnf
enable_rpmfusion
[[ -n "$WANT_TERRA" ]] && enable_terra
setup_flatpak
install_codecs
install_plasma
install_utilities
install_user_packages
finalize_system
setup_login_manager
setup_branding

term_reset            # restore normal full-screen scrolling
prompt_layan_rice
setup_fastfetch_hook  # runs after rice so it survives any .bashrc overwrite
show_completion

# Self-destruct only when run as a downloaded file (not via curl | bash, where
# SCRIPT_PATH is empty or /dev/fd/*).
if [[ -n "$SCRIPT_PATH" && -f "$SCRIPT_PATH" && "$SCRIPT_PATH" != /dev/* && "$SCRIPT_PATH" != /proc/* ]]; then
    rm -f "$SCRIPT_PATH"
fi
