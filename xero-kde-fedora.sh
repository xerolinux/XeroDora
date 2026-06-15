#!/usr/bin/env bash

# XeroLinux KDE Plasma Installer — Fedora port v1.0
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

print_header() {
    clear
    echo -e "${PURPLE}╔════════════════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║                                                ║${NC}"
    echo -e "${PURPLE}║${CYAN}  ✨ XeroLinux KDE Plasma Installer (Fedora) ✨ ${PURPLE}║${NC}"
    echo -e "${PURPLE}║                                                ║${NC}"
    echo -e "${PURPLE}╚════════════════════════════════════════════════╝${NC}"
    echo ""
}

print_step()    { echo -e "${BLUE}➜${NC} ${CYAN}$1${NC}"; }
print_success() { echo -e "${GREEN}✓${NC} $1"; }
print_error()   { echo -e "${RED}✗${NC} $1"; sleep 1; }
print_warning() { echo -e "${YELLOW}⚠${NC} $1"; sleep 1; }

# ── Progress ──────────────────────────────────────────────────────────────────
# Each major phase calls progress_header to show "Step N/TOTAL" + a bar.
TOTAL_STEPS=9
CURRENT_STEP=0

# progress_header <title> [tip] — tip (if given) prints above the progress bar.
progress_header() {
    CURRENT_STEP=$((CURRENT_STEP + 1))
    print_header
    [[ -n "${2:-}" ]] && { echo -e "${YELLOW}$2${NC}"; echo ""; }
    local width=40
    local filled=$((CURRENT_STEP * width / TOTAL_STEPS))
    local empty=$((width - filled))
    local pct=$((CURRENT_STEP * 100 / TOTAL_STEPS))
    local bar=""
    local i
    for ((i = 0; i < filled; i++)); do bar+="█"; done
    for ((i = 0; i < empty; i++)); do bar+="░"; done
    echo -e "${PURPLE}[${GREEN}${bar}${PURPLE}]${NC} ${CYAN}${pct}%${NC}  ${YELLOW}Step ${CURRENT_STEP}/${TOTAL_STEPS}${NC}"
    echo -e "${PURPLE}▶ ${CYAN}$1${NC}"
    echo ""
}

# ── Privilege handling ────────────────────────────────────────────────────────

# Fedora desktop install context: user runs with sudo, or as root from TTY.
setup_sudo() {
    if [[ ${EUID:-0} -eq 0 ]]; then
        SUDO_CMD=""
        print_step "Running as root."
    else
        if ! command -v sudo >/dev/null 2>&1; then
            print_error "Not root and 'sudo' not found. Re-run as root."
            exit 1
        fi
        SUDO_CMD="sudo"
    fi
}

# ── Preflight ─────────────────────────────────────────────────────────────────

check_fedora() {
    if [[ ! -r /etc/os-release ]]; then
        print_error "/etc/os-release missing — cannot detect distro."
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
# package never blocks the rest. Never aborts — reports skipped as warnings.
install_group() {
    local group_name="$1"; shift
    local pkgs=("$@")

    print_step "[$group_name] Installing ${#pkgs[@]} packages..."
    if $SUDO_CMD dnf install -y "${pkgs[@]}" 2>/dev/null; then
        print_success "[$group_name] Done!"
        echo ""
        return 0
    fi

    print_warning "[$group_name] Bulk install failed — retrying individually..."
    local failed=() installed=0
    for pkg in "${pkgs[@]}"; do
        if $SUDO_CMD dnf install -y "$pkg" 2>/dev/null; then
            (( installed++ )) || true
        else
            failed+=("$pkg")
        fi
    done

    [[ ${#failed[@]} -gt 0 ]] && \
        print_warning "[$group_name] Skipped (${#failed[@]}): ${failed[*]}"
    print_success "[$group_name] Done — $installed installed, ${#failed[@]} skipped."
    echo ""
    return 0
}

# install_group_required <name> <pkg...> — aborts if ZERO installed.
install_group_required() {
    local group_name="$1"; shift
    local pkgs=("$@")

    print_step "[$group_name] Installing ${#pkgs[@]} packages (required)..."
    if $SUDO_CMD dnf install -y "${pkgs[@]}" 2>/dev/null; then
        print_success "[$group_name] Done!"
        echo ""
        return 0
    fi

    print_warning "[$group_name] Bulk install failed — retrying individually..."
    local failed=() installed=0
    for pkg in "${pkgs[@]}"; do
        if $SUDO_CMD dnf install -y "$pkg" 2>/dev/null; then
            (( installed++ )) || true
        else
            failed+=("$pkg")
        fi
    done

    [[ ${#failed[@]} -gt 0 ]] && \
        print_warning "[$group_name] Skipped (${#failed[@]}): ${failed[*]}"
    if [[ $installed -eq 0 ]]; then
        print_error "[$group_name] Critical: zero packages installed — aborting!"
        exit 1
    fi
    print_success "[$group_name] Done — $installed installed, ${#failed[@]} skipped."
    echo ""
    return 0
}

# install_dnf_group <comterm group-id>... — install a dnf comps group, non-fatal.
install_dnf_group() {
    local g="$1"
    print_step "Installing dnf group: $g ..."
    if $SUDO_CMD dnf group install -y "$g" 2>/dev/null; then
        print_success "Group '$g' installed!"
    else
        print_warning "Group '$g' failed or not found — continuing."
    fi
    echo ""
}

# ── Flatpak helpers ───────────────────────────────────────────────────────────

setup_flatpak() {
    print_step "Setting up Flatpak + Flathub..."
    $SUDO_CMD dnf install -y flatpak 2>/dev/null || print_warning "flatpak install failed"
    $SUDO_CMD flatpak remote-add --if-not-exists flathub \
        https://flathub.org/repo/flathub.flatpakrepo 2>/dev/null \
        && print_success "Flathub remote ready!" \
        || print_warning "Could not add Flathub remote (non-critical)"
    echo ""
}

# flatpak_install <app-id>...
flatpak_install() {
    local apps=("$@")
    [[ ${#apps[@]} -eq 0 ]] && return 0
    print_step "[Flatpak] Installing ${#apps[@]} app(s)..."
    local failed=() installed=0
    for app in "${apps[@]}"; do
        if $SUDO_CMD flatpak install -y --noninteractive flathub "$app" 2>/dev/null; then
            (( installed++ )) || true
        else
            failed+=("$app")
        fi
    done
    [[ ${#failed[@]} -gt 0 ]] && \
        print_warning "[Flatpak] Skipped (${#failed[@]}): ${failed[*]}"
    print_success "[Flatpak] Done — $installed installed, ${#failed[@]} skipped."
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
# set_dnf_opt <key> <value> — idempotent (replace existing line or append).
set_dnf_opt() {
    local key="$1" val="$2"
    if $SUDO_CMD grep -q "^${key}=" /etc/dnf/dnf.conf 2>/dev/null; then
        $SUDO_CMD sed -i "s|^${key}=.*|${key}=${val}|" /etc/dnf/dnf.conf
    else
        echo "${key}=${val}" | $SUDO_CMD tee -a /etc/dnf/dnf.conf >/dev/null
    fi
}

tune_dnf() {
    progress_header "Tuning dnf (fastest mirrors, 25 parallel downloads)"
    print_step "Patching /etc/dnf/dnf.conf..."
    $SUDO_CMD touch /etc/dnf/dnf.conf 2>/dev/null || true
    set_dnf_opt max_parallel_downloads 25
    set_dnf_opt fastestmirror True
    set_dnf_opt defaultyes True
    set_dnf_opt keepcache False
    print_success "dnf tuned — 25 parallel downloads, fastestmirror on."
    echo ""
}

enable_rpmfusion() {
    progress_header "Enabling RPMFusion + system upgrade"
    print_step "Enabling RPMFusion (free + nonfree)..."
    $SUDO_CMD dnf install -y \
        "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${FEDORA_VER}.noarch.rpm" \
        "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${FEDORA_VER}.noarch.rpm" \
        || { print_error "RPMFusion enable failed!"; exit 1; }
    print_success "RPMFusion enabled!"
    echo ""

    print_step "Updating system + core group..."
    $SUDO_CMD dnf -y group upgrade core 2>/dev/null || true
    $SUDO_CMD dnf -y upgrade --refresh || print_warning "System upgrade had errors — continuing."
    # appstream metadata for KDE Discover / Flatpak
    $SUDO_CMD dnf install -y rpmfusion-free-appstream-data rpmfusion-nonfree-appstream-data 2>/dev/null || true
    print_success "System updated!"
    echo ""
}

install_codecs() {
    progress_header "Installing multimedia codecs"
    print_step "Installing multimedia codecs..."

    # Swap the limited ffmpeg-free for the full RPMFusion ffmpeg
    $SUDO_CMD dnf swap -y ffmpeg-free ffmpeg --allowerasing 2>/dev/null \
        || $SUDO_CMD dnf install -y ffmpeg --allowerasing 2>/dev/null \
        || print_warning "ffmpeg swap/install had issues"

    # Multimedia + sound-and-video groups (full gstreamer plugin set)
    $SUDO_CMD dnf group install -y multimedia \
        --setopt="install_weak_deps=False" \
        --exclude=PackageKit-gstreamer-plugin 2>/dev/null || true
    $SUDO_CMD dnf group install -y sound-and-video 2>/dev/null || true

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
    progress_header "Installing KDE Plasma desktop" \
        "☕ This phase pulls a lot of packages and may take a while — sit back, grab a coffee."
    print_step "Installing KDE Plasma desktop..."
    # Fedora's curated Plasma group — guarantees a complete, existing package set.
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
        kdeconnectd krfb krdc skanlite kamoso k3b yakuake kio-extras kio-admin \
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
    progress_header "Installing curated utilities & fonts"
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
    echo -e "  ${CYAN}10)${NC} Helium (n/a Fedora) ${CYAN}11)${NC} Zen Browser [F]"
    echo ""
    echo -e "${GREEN}-- SOCIAL & COMMUNICATION -------------------------------------------------${NC}"
    echo ""
    echo -e "  ${GREEN}12)${NC} ZapZap (WA) [F]     ${GREEN}13)${NC} Discord [F]         ${GREEN}14)${NC} Vesktop [F]"
    echo -e "  ${GREEN}15)${NC} Telegram            ${GREEN}16)${NC} Ferdium [F]"
    echo ""
    echo -e "${PURPLE}-- DEVELOPMENT TOOLS ------------------------------------------------------${NC}"
    echo ""
    echo -e "  ${PURPLE}17)${NC} Hugo                ${PURPLE}18)${NC} Meld                ${PURPLE}19)${NC} VSCodium [R]"
    echo -e "  ${PURPLE}20)${NC} GitHub Desktop [F]"
    echo ""
    echo -e "${YELLOW}-- PASSWORD MANAGERS -------------------------------------------------------${NC}"
    echo ""
    echo -e "  ${YELLOW}21)${NC} KeePassXC           ${YELLOW}22)${NC} Bitwarden [F]       ${YELLOW}23)${NC} pass"
    echo ""
    echo -e "${BLUE}-- CREATIVE & IMAGING -----------------------------------------------------${NC}"
    echo ""
    echo -e "  ${BLUE}24)${NC} GIMP                ${BLUE}25)${NC} Krita               ${BLUE}26)${NC} Inkscape"
    echo ""
    echo -e "${RED}-- MUSIC & AUDIO ----------------------------------------------------------${NC}"
    echo ""
    echo -e "  ${RED}27)${NC} MPV                 ${RED}28)${NC} Amarok              ${RED}29)${NC} Spotify [F]"
    echo -e "  ${RED}30)${NC} Tenacity [F]        ${RED}31)${NC} JamesDSP [F]        ${RED}32)${NC} EasyEffects"
    echo ""
    echo -e "${GREEN}-- VIDEO EDITING ----------------------------------------------------------${NC}"
    echo ""
    echo -e "  ${GREEN}33)${NC} MakeMKV [F]         ${GREEN}34)${NC} Kdenlive            ${GREEN}35)${NC} Avidemux [F]"
    echo -e "  ${GREEN}36)${NC} MKVToolNix"
    echo ""
    echo -e "${CYAN}-- OFFICE -----------------------------------------------------------------${NC}"
    echo ""
    echo -e "  ${CYAN}37)${NC} LibreOffice"
    echo ""
    read -p ">> Your choices: " user_input </dev/tty

    DNF_APPS=""        # native repo / rpmfusion packages
    FLAT_APPS=""       # flathub app-ids
    NEED_BRAVE="" NEED_VIVALDI="" NEED_LIBREWOLF="" NEED_VSCODIUM=""
    WANTS_LIBREOFFICE=""

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
            10) print_warning "Helium has no Fedora rpm or Flatpak — skipping." ;;
            11) FLAT_APPS="$FLAT_APPS app.zen_browser.zen" ;;
            12) FLAT_APPS="$FLAT_APPS com.rtosta.zapzap" ;;
            13) FLAT_APPS="$FLAT_APPS com.discordapp.Discord" ;;
            14) FLAT_APPS="$FLAT_APPS dev.vencord.Vesktop" ;;
            15) DNF_APPS="$DNF_APPS telegram-desktop" ;;
            16) FLAT_APPS="$FLAT_APPS org.ferdium.Ferdium" ;;
            17) DNF_APPS="$DNF_APPS hugo" ;;
            18) DNF_APPS="$DNF_APPS meld" ;;
            19) NEED_VSCODIUM="yes"; DNF_APPS="$DNF_APPS codium" ;;
            20) FLAT_APPS="$FLAT_APPS io.github.shiftey.Desktop" ;;
            21) DNF_APPS="$DNF_APPS keepassxc" ;;
            22) FLAT_APPS="$FLAT_APPS com.bitwarden.desktop" ;;
            23) DNF_APPS="$DNF_APPS pass" ;;
            24) DNF_APPS="$DNF_APPS gimp" ;;
            25) DNF_APPS="$DNF_APPS krita" ;;
            26) DNF_APPS="$DNF_APPS inkscape" ;;
            27) DNF_APPS="$DNF_APPS mpv" ;;
            28) DNF_APPS="$DNF_APPS amarok" ;;
            29) FLAT_APPS="$FLAT_APPS com.spotify.Client" ;;
            30) FLAT_APPS="$FLAT_APPS org.tenacityaudio.Tenacity" ;;
            31) FLAT_APPS="$FLAT_APPS me.timschneeberger.jdsp4linux" ;;
            32) DNF_APPS="$DNF_APPS easyeffects" ;;
            33) FLAT_APPS="$FLAT_APPS com.makemkv.MakeMKV" ;;
            34) DNF_APPS="$DNF_APPS kdenlive" ;;
            35) FLAT_APPS="$FLAT_APPS org.avidemux.Avidemux" ;;
            36) DNF_APPS="$DNF_APPS mkvtoolnix-gui" ;;
            37) WANTS_LIBREOFFICE="yes" ;;
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
    progress_header "Installing your selected apps"
    print_step "Installing user-selected apps..."
    echo ""

    # Add vendor repos only for what was selected
    [[ -n "$NEED_BRAVE" ]]     && add_brave_repo
    [[ -n "$NEED_VIVALDI" ]]   && add_vivaldi_repo
    [[ -n "$NEED_LIBREWOLF" ]] && add_librewolf_repo
    [[ -n "$NEED_VSCODIUM" ]]  && add_vscodium_repo
    [[ -n "$NEED_BRAVE$NEED_VIVALDI$NEED_LIBREWOLF$NEED_VSCODIUM" ]] && \
        $SUDO_CMD dnf makecache 2>/dev/null

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
        print_warning "Unit $svc not found — skipping"
    fi
}

finalize_system() {
    progress_header "Finalizing system (services + boot target)"
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
# Append a fastfetch hook to the real user's ~/.bashrc. No other config touched.
setup_fastfetch_hook() {
    progress_header "Adding fastfetch to shell startup"
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
        print_warning "Could not determine target user — skipping fastfetch hook."
        echo ""; return 0
    fi
    home="$(getent passwd "$user" | cut -d: -f6)"
    if [[ -z "${home:-}" || ! -d "$home" ]]; then
        print_warning "Home dir for $user not found — skipping fastfetch hook."
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
    progress_header "Setting up Plasma Login Manager + Breeze Dark"
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
    # their own theme — no per-user config files touched.
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

# ── Completion ────────────────────────────────────────────────────────────────

show_completion() {
    print_header
    echo -e "${PURPLE}╔════════════════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║${GREEN}     🎉 Installation Complete! 🎉              ${PURPLE}║${NC}"
    echo -e "${PURPLE}╠════════════════════════════════════════════════╣${NC}"
    echo -e "${PURPLE}║${NC}  Your KDE Plasma desktop is ready!            ${PURPLE}║${NC}"
    echo -e "${PURPLE}║${NC}  Reboot to start using it.                    ${PURPLE}║${NC}"
    echo -e "${PURPLE}║${NC}                                               ${PURPLE}║${NC}"
    echo -e "${PURPLE}║${NC}  Command: ${YELLOW}sudo systemctl reboot${NC}              ${PURPLE}║${NC}"
    echo -e "${PURPLE}╚════════════════════════════════════════════════╝${NC}"
    echo ""
}

# ── Main ──────────────────────────────────────────────────────────────────────

setup_sudo
check_fedora
prompt_user
customization_prompts
tune_dnf
enable_rpmfusion
setup_flatpak
install_codecs
install_plasma
install_utilities
install_user_packages
finalize_system
setup_fastfetch_hook
setup_login_manager
show_completion

# Self-destruct only when run as a downloaded file (not via curl | bash, where
# SCRIPT_PATH is empty or /dev/fd/*).
if [[ -n "$SCRIPT_PATH" && -f "$SCRIPT_PATH" && "$SCRIPT_PATH" != /dev/* && "$SCRIPT_PATH" != /proc/* ]]; then
    rm -f "$SCRIPT_PATH"
fi
