#!/usr/bin/env bash
# TheWindowsLinux – Schritt 1: Pakete installieren (XFCE, Whisker-Menü, Schriften, Cursor, Werkzeuge)
# Wird von install.sh gesourct; nutzt lib/common.sh.
set -u

w7_packages_debian() {
    local pkgs=(
        xfce4-screensaver blueman pavucontrol gnome-keyring libpam-gnome-keyring xdg-desktop-portal-gtk
        xfce4 xfce4-goodies xfce4-whiskermenu-plugin xfce4-panel xfwm4 xfdesktop4 xfconf
        xfce4-session xfce4-settings xfce4-terminal thunar thunar-archive-plugin thunar-volman
        xfce4-appfinder xfce4-taskmanager xfce4-screenshooter xfce4-notifyd xfce4-pulseaudio-plugin
        xfce4-power-manager xfce4-clipman-plugin mousepad ristretto parole galculator catfish
        gvfs gvfs-backends gvfs-fuse xdg-utils xdg-user-dirs xdg-user-dirs-gtk
        dmz-cursor-theme elementary-xfce-icon-theme adwaita-icon-theme
        fonts-noto-core fonts-dejavu-core fonts-liberation fonts-cascadia-code fonts-terminus-otb fonts-unifont xfonts-terminus
        pulseaudio-utils libnotify-bin tree psmisc procps iproute2 lsb-release
        network-manager-gnome policykit-1-gnome file-roller unzip curl
    )
    w7_root env DEBIAN_FRONTEND=noninteractive apt-get update -qq || w7_warn "apt-get update meldete Fehler – fahre fort."
    # Nur Pakete mit echtem Installationskandidaten (apt-cache show allein reicht nicht:
    # es meldet auch Pakete, die auf diesem System nicht installierbar sind).
    local pkg cand available=() skipped=()
    for pkg in "${pkgs[@]}"; do
        cand="$(apt-cache policy "$pkg" 2>/dev/null | awk '/Candidate:/ {print $2}')"
        if [ -n "$cand" ] && [ "$cand" != "(none)" ]; then available+=("$pkg"); else skipped+=("$pkg"); fi
    done
    [ ${#skipped[@]} -gt 0 ] && w7_info "Nicht verfügbar, übersprungen: ${skipped[*]}"
    # Sammelinstallation; schlägt sie fehl, jedes Paket einzeln versuchen, damit ein
    # einzelnes fehlendes/kaputtes Paket nicht die ganze Installation stoppt.
    if ! w7_root env DEBIAN_FRONTEND=noninteractive apt-get install -y -q "${available[@]}"; then
        w7_warn "Sammelinstallation fehlgeschlagen – installiere Pakete einzeln."
        local failed=()
        for pkg in "${available[@]}"; do
            w7_root env DEBIAN_FRONTEND=noninteractive apt-get install -y -q "$pkg" >/dev/null 2>&1 || failed+=("$pkg")
        done
        [ ${#failed[@]} -gt 0 ] && w7_warn "Nicht installierbar (optional, wird übersprungen): ${failed[*]}"
    fi
    # Anzeige-Manager + X-Server, falls noch keiner vorhanden
    if ! w7_display_manager_present; then
        w7_root env DEBIAN_FRONTEND=noninteractive apt-get install -y -q xorg lightdm lightdm-gtk-greeter lightdm-gtk-greeter-settings
    fi
}

w7_packages_fedora() {
    local pkgs=(
        xfce4-screensaver blueman pavucontrol gnome-keyring xdg-desktop-portal-gtk
        @xfce-desktop-environment xfce4-whiskermenu-plugin xfce4-panel xfwm4 xfdesktop xfconf
        xfce4-terminal thunar thunar-archive-plugin xfce4-appfinder xfce4-taskmanager xfce4-screenshooter
        xfce4-notifyd xfce4-pulseaudio-plugin xfce4-power-manager xfce4-clipman-plugin mousepad ristretto
        galculator catfish gvfs gvfs-fuse xdg-utils xdg-user-dirs xdg-user-dirs-gtk
        dmz-cursor-themes elementary-xfce-icon-theme adwaita-icon-theme
        google-noto-sans-fonts dejavu-sans-fonts liberation-fonts cascadia-code-fonts terminus-fonts unifont-fonts
        pulseaudio-utils libnotify tree psmisc procps-ng iproute network-manager-applet polkit-gnome
        file-roller unzip curl
    )
    w7_root dnf install -y --skip-unavailable "${pkgs[@]}" 2>/dev/null || w7_root dnf install -y --skip-broken "${pkgs[@]}"
    if ! w7_display_manager_present; then
        w7_root dnf install -y lightdm lightdm-gtk xorg-x11-server-Xorg xorg-x11-xinit
        w7_root systemctl enable lightdm 2>/dev/null || true
    fi
}

w7_packages_arch() {
    local pkgs=(
        xfce4-screensaver blueman pavucontrol gnome-keyring xdg-desktop-portal-gtk
        xfce4 xfce4-goodies xfce4-whiskermenu-plugin thunar-archive-plugin thunar-volman
        mousepad ristretto parole galculator catfish gvfs gvfs-mtp xdg-utils xdg-user-dirs xdg-user-dirs-gtk
        xcursor-vanilla-dmz adwaita-icon-theme elementary-xfce-icons
        noto-fonts ttf-dejavu ttf-liberation ttf-cascadia-code terminus-font bdf-unifont
        libpulse libnotify tree psmisc procps-ng iproute2 network-manager-applet polkit-gnome
        file-roller unzip curl
    )
    # Auf Arch ist "pacman -Sy" ohne Upgrade ein unterstützter-Weg-ins-Nichts (Teil-Upgrades können das System
    # beschädigen). Darum: vollständiges Upgrade zusammen mit der Installation (-Syu).
    w7_info "Arch: führe ein vollständiges Systemupdate (pacman -Syu) zusammen mit der Installation durch."
    w7_root pacman -Syu --needed --noconfirm "${pkgs[@]}" || {
        # einzeln versuchen, falls ein Paketname fehlt (Datenbank ist nach dem ersten Lauf aktuell)
        local pkg; for pkg in "${pkgs[@]}"; do w7_root pacman -S --needed --noconfirm "$pkg" 2>/dev/null || w7_info "übersprungen: $pkg"; done
    }
    if ! w7_display_manager_present; then
        w7_root pacman -S --needed --noconfirm xorg-server xorg-xinit lightdm lightdm-gtk-greeter
        w7_root systemctl enable lightdm 2>/dev/null || true
    fi
}

w7_packages_suse() {
    local pkgs=(
        xfce4-screensaver blueman pavucontrol gnome-keyring xdg-desktop-portal-gtk
        patterns-xfce-xfce xfce4-whiskermenu-plugin xfce4-terminal thunar mousepad ristretto galculator catfish
        gvfs xdg-utils xdg-user-dirs xdg-user-dirs-gtk dmz-icon-theme-cursors elementary-xfce-icon-theme adwaita-icon-theme
        google-noto-sans-fonts dejavu-fonts liberation-fonts terminus-bitmap-fonts pulseaudio-utils libnotify-tools tree psmisc procps iproute2
        NetworkManager-applet polkit-gnome file-roller unzip curl
    )
    w7_root zypper --non-interactive install --no-recommends "${pkgs[@]}" || {
        local pkg; for pkg in "${pkgs[@]}"; do w7_root zypper --non-interactive install "$pkg" 2>/dev/null || w7_info "übersprungen: $pkg"; done
    }
    if ! w7_display_manager_present; then
        w7_root zypper --non-interactive install xorg-x11-server lightdm lightdm-gtk-greeter
    fi
}

w7_packages_void() {
    w7_root xbps-install -Sy xfce4 xfce4-whiskermenu-plugin xfce4-terminal Thunar mousepad ristretto galculator catfish gvfs xdg-utils xdg-user-dirs xdg-user-dirs-gtk \
        xcursor-vanilla-dmz elementary-xfce-icon-theme adwaita-icon-theme noto-fonts-ttf dejavu-fonts-ttf liberation-fonts-ttf terminus-font \
        pulseaudio-utils libnotify tree psmisc procps-ng iproute2 network-manager-applet polkit-gnome file-roller unzip curl \
        xfce4-screensaver blueman pavucontrol gnome-keyring xdg-desktop-portal-gtk
    if ! w7_display_manager_present; then
        w7_root xbps-install -Sy xorg-minimal xorg-fonts lightdm lightdm-gtk3-greeter
    fi
}

w7_display_manager_present() {
    [ -e /etc/X11/default-display-manager ] && return 0
    [ -e /etc/systemd/system/display-manager.service ] && return 0
    w7_have lightdm || w7_have gdm || w7_have gdm3 || w7_have sddm || w7_have lxdm || w7_have ly
}

w7_step_packages() {
    w7_step "Pakete installieren ($W7_DISTRO_NAME)"
    if [ "${W7_NO_PACKAGES:-0}" = 1 ]; then
        w7_info "übersprungen (--no-packages)"; return 0
    fi
    if ! w7_can_root; then
        w7_warn "Keine Root-Rechte – Paketinstallation übersprungen. Benötigt: xfce4, xfce4-whiskermenu-plugin, xfce4-terminal, thunar."
        return 0
    fi
    case "$W7_DISTRO" in
        debian) w7_packages_debian ;;
        fedora) w7_packages_fedora ;;
        arch)   w7_packages_arch ;;
        suse)   w7_packages_suse ;;
        void)   w7_packages_void ;;
        *) w7_warn "Unbekannte Distribution ($W7_DISTRO_ID). Bitte XFCE 4.14+ mit Whisker-Menü, xfce4-terminal und Thunar von Hand installieren."; return 0 ;;
    esac
    w7_ok "Pakete installiert."
}

w7_check_xfce() {
    local missing=()
    for b in xfce4-panel xfwm4 xfdesktop xfce4-session xfconf-query thunar; do
        w7_have "$b" || missing+=("$b")
    done
    if [ ${#missing[@]} -gt 0 ]; then
        w7_warn "XFCE-Komponenten fehlen: ${missing[*]} – das Overlay wird trotzdem installiert, wirkt aber erst mit XFCE."
        return 1
    fi
    if ! find /usr/lib /usr/lib64 /usr/libexec -path '*xfce4*panel*plugins*' -name 'libwhiskermenu*' 2>/dev/null | grep -q .; then
        w7_warn "Whisker-Menü-Plugin (xfce4-whiskermenu-plugin) nicht gefunden – der Start-Button zeigt sonst das Standardmenü."
    fi
    return 0
}
