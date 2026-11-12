#!/usr/bin/env bash
# ============================================================================
#  TheWindowsLinux – Deinstaller
#  Entfernt Theme, Icons, Konfiguration und cmd-Overlay wieder und stellt
#  gesicherte Konfigurationsdateien (Benutzermodus) wieder her.
#
#    ./uninstall.sh            (Benutzermodus)
#    sudo ./uninstall.sh --system
# ============================================================================
set -euo pipefail
W7_SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export W7_SRC
# shellcheck source=lib/common.sh
. "$W7_SRC/lib/common.sh"

W7_MODE=user; W7_YES=0
while [ $# -gt 0 ]; do
    case "$1" in
        --system) W7_MODE=system ;;
        --user) W7_MODE=user ;;
        --yes|-y) W7_YES=1 ;;
        --help|-h) echo "Verwendung: $0 [--user|--system] [--yes]"; exit 0 ;;
        *) w7_err "Unbekannte Option: $1"; exit 2 ;;
    esac
    shift
done
export W7_MODE
w7_setup_paths
W7_STYLE="$(sed -n 's/^STYLE=//p' "$W7_DATADIR/style.conf" 2>/dev/null || true)"
W7_STYLE="${W7_STYLE:-retro}"
w7_setup_style

w7_step "TheWindowsLinux deinstallieren ($W7_MODE, Stil $W7_STYLE)"
w7_info "Entfernt werden:"
w7_info "  $W7_DATADIR"
w7_info "  $W7_THEMEDIR/Windows-Retro, $W7_THEMEDIR/Windows7-Aero"
w7_info "  $W7_ICONDIR/Windows-Retro, $W7_ICONDIR/Windows7-Aero (+ win7-* in hicolor)"
w7_info "  XFCE-Konfiguration unter $W7_XDG_CONF/xfce4 (Panel, Desktop, Fenster, Tastenkürzel, Terminal)"
w7_info "  Menüeinträge win7-*.desktop, Autostart-Einträge, Befehle cmd/win7-* in $W7_BINDIR"
echo
if [ "$W7_YES" != 1 ] && [ -t 0 ]; then
    read -r -p "Fortfahren? [j/N] " ans
    case "${ans,,}" in j|ja|y|yes) ;; *) echo "Abgebrochen."; exit 0 ;; esac
fi

rm_path() { [ -e "$1" ] || [ -L "$1" ] || return 0; w7_do rm -rf "$1"; w7_info "entfernt: $1"; }

# Laufende Sitzung: xfconfd beenden, damit Dateien nicht zurückgeschrieben werden
if [ "$W7_MODE" = user ] && w7_xfce_running; then pkill -u "$(id -u)" -x xfconfd 2>/dev/null || true; sleep 0.5; fi

# Themes / Icons / Daten
rm_path "$W7_DATADIR"
for t in Windows-Retro Windows7-Aero; do
    rm_path "$W7_THEMEDIR/$t"
    rm_path "$W7_ICONDIR/$t"
done
for s in 16 22 24 32 48 64 96 128 256; do
    for n in win7-start win7-cmd win7-explorer win7-control-panel; do
        rm_path "$W7_ICONDIR/hicolor/${s}x${s}/apps/$n.png"
    done
done
if [ "$W7_MODE" = system ]; then rm_path /usr/share/sounds/windows7; else rm_path "${XDG_DATA_HOME:-$HOME/.local/share}/sounds/windows7"; fi
rm_path "$W7_FONTDIR"

# XFCE-Konfiguration
for f in xfce4-panel xfce4-desktop xfwm4 xsettings xfce4-keyboard-shortcuts thunar xfce4-notifyd xfce4-session xfce4-appfinder; do
    rm_path "$W7_XDG_CONF/xfce4/xfconf/xfce-perchannel-xml/$f.xml"
    if [ "$W7_MODE" = system ]; then
        for d in /etc/xdg/xdg-*/xfce4/xfconf/xfce-perchannel-xml; do rm_path "$d/$f.xml"; done
    fi
done
rm_path "$W7_XDG_CONF/xfce4/panel/whiskermenu-1.rc"
for l in 2 3 4; do rm_path "$W7_XDG_CONF/xfce4/panel/launcher-$l"; done
rm_path "$W7_XDG_CONF/xfce4/terminal/terminalrc"
rm_path "$W7_XDG_CONF/Thunar/uca.xml"
for f in "$W7_SRC"/theme/xfce4/applications/*.desktop; do rm_path "$W7_APPDIR/$(basename "$f")"; done
for f in "$W7_SRC"/theme/xfce4/autostart/*.desktop; do rm_path "$W7_AUTOSTART/$(basename "$f")"; done
[ "$W7_MODE" = system ] && rm_path /etc/skel/.config/gtk-3.0/bookmarks

# Befehle
for b in cmd cmd.exe eingabeaufforderung win7-terminal win7-sound win7-firstrun win7-wallpaper; do rm_path "$W7_BINDIR/$b"; done

# Login/Boot (nur System)
if [ "$W7_MODE" = system ]; then
    rm_path /etc/lightdm/lightdm-gtk-greeter.conf.d/50-thewindowslinux.conf
    rm_path /etc/lightdm/lightdm.conf.d/50-thewindowslinux.conf
    rm_path /etc/default/grub.d/50-thewindowslinux.cfg
    rm_path /usr/share/plymouth/themes/windows7
    rm_path /etc/profile.d/thewindowslinux.sh
    if w7_root grep -q 'TheWindowsLinux cmd-Overlay' /etc/bash.bashrc 2>/dev/null; then
        w7_root sed -i '/TheWindowsLinux cmd-Overlay/d' /etc/bash.bashrc
    fi
else
    # Profil-/bashrc-Blöcke entfernen
    if [ -f "$HOME/.profile" ] && grep -q '>>> TheWindowsLinux >>>' "$HOME/.profile"; then
        sed -i '/# >>> TheWindowsLinux >>>/,/# <<< TheWindowsLinux <<</d' "$HOME/.profile"
    fi
    if [ -f "$HOME/.bashrc" ]; then
        sed -i '/TheWindowsLinux cmd-Overlay/d; /^# TheWindowsLinux$/d; /^export WIN7_DATADIR=/d; /^export WIN7_STYLE=/d; /thewindowslinux\/bin:\$PATH/d; /\.local\/bin:"\*) ;; \*) export PATH="[^"]*\.local\/bin:\$PATH" ;; esac$/d' "$HOME/.bashrc"
    fi
    # Backups zurückspielen (neueste Sicherung)
    last="$(ls -d "$W7_STATE"/backup-* 2>/dev/null | sort | tail -1 || true)"
    if [ -n "$last" ]; then
        w7_info "Stelle gesicherte Konfiguration aus $last wieder her ..."
        (cd "$last" && find . -type f -o -type l | while IFS= read -r rel; do
            dst="/${rel#./}"
            mkdir -p "$(dirname "$dst")"
            cp -a "$rel" "$dst"
        done)
    fi
    # Standard-Erscheinungsbild zurücksetzen, wenn noch kein anderes Theme konfiguriert ist
    if [ ! -f "$W7_XDG_CONF/xfce4/xfconf/xfce-perchannel-xml/xsettings.xml" ]; then
        rm -f "$W7_XDG_CONF/xfce4/xfconf/xfce-perchannel-xml/xsettings.xml"
    fi
    rm_path "$W7_STATE/firstrun-done"
    if w7_xfce_running; then
        (xfsettingsd --replace >/dev/null 2>&1 &); (xfwm4 --replace >/dev/null 2>&1 &); (xfce4-panel -r >/dev/null 2>&1 &); (xfdesktop --reload >/dev/null 2>&1 &)
    fi
fi
rm -f "$W7_STATE/installed-files.txt" "$W7_STATE/install.info"

echo
printf '%s✔ TheWindowsLinux wurde entfernt.%s Zum Abschluss ab- und wieder anmelden.\n' "$C_GREEN" "$C_0"
echo "Pakete (xfce4, Schriften, ...) wurden nicht deinstalliert."
