#!/usr/bin/env bash
# ============================================================================
#  TheWindowsLinux – Deinstaller
#
#  Macht die Installation rückgängig:
#    * jede von install.sh geschriebene Datei wird entfernt – oder, falls es vorher eine gab, durch das
#      ORIGINAL ersetzt, das beim ersten Installieren gesichert wurde
#    * von uns neu angelegte, nun leere Ordner verschwinden
#    * Einträge in ~/.profile / ~/.bashrc werden entfernt (nur unsere markierten Zeilen)
#    * erkennt auch Installationen älterer Versionen (1.0/1.1)
#  NICHT rückgängig gemacht werden installierte Pakete (xfce4, Schriften, Kali-Werkzeuge, ufw ...) und
#  die Firewall – sie abzuschalten wäre ein Sicherheitsverlust (sudo ufw disable, falls gewollt).
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

LIST="$W7_VARDIR/installed-files.txt"
DIRS="$W7_VARDIR/created-dirs.txt"
ORIG="$W7_VARDIR/original"
LEGACY=0
if [ ! -d "$ORIG" ]; then
    # Installationen vor Version 1.2 legten Sicherungen als backup-<datum>/ ab → die älteste enthält die Originale
    old="$(ls -d "$W7_VARDIR"/backup-* 2>/dev/null | sort | head -1 || true)"
    if [ -n "$old" ]; then ORIG="$old"; LEGACY=1; fi
fi

[ -f "$W7_VARDIR/legacy-migrated" ] && LEGACY=1      # von einer älteren Version aktualisiert: Altlasten zusätzlich aufräumen
if [ ! -e "$LIST" ] && [ ! -e "$W7_DATADIR/VERSION" ]; then
    w7_warn "Keine Installation von TheWindowsLinux gefunden ($W7_MODE-Modus). Nichts zu tun."
    exit 0
fi

n_files=0; [ -f "$LIST" ] && n_files="$(sort -u "$LIST" | grep -c .)"
w7_step "TheWindowsLinux deinstallieren ($W7_MODE, Stil $W7_STYLE)"
w7_info "$n_files installierte Einträge werden entfernt bzw. durch ihre Originale ersetzt."
[ -d "$ORIG" ] && w7_info "Originale (vor der Installation vorhandene Dateien) werden wiederhergestellt aus: $ORIG"
[ $LEGACY -eq 1 ] && w7_info "Ältere Installation erkannt – zusätzlich werden bekannte Altlasten entfernt."
echo
if [ "$W7_YES" != 1 ] && [ -t 0 ]; then
    read -r -p "Fortfahren? [j/N] " ans
    case "${ans,,}" in j|ja|y|yes) ;; *) echo "Abgebrochen."; exit 0 ;; esac
fi

# Laufende Sitzung: xfconfd beenden, damit unsere Dateien nicht zurückgeschrieben werden
if [ "$W7_MODE" = user ] && w7_xfce_running; then
    pkill -u "$(id -u)" -x xfce4-panel 2>/dev/null || true
    pkill -u "$(id -u)" -x xfconfd 2>/dev/null || true
    sleep 1
fi

had_grub=0; [ -e /etc/default/grub.d/50-thewindowslinux.cfg ] && had_grub=1
had_plymouth=0; [ -d /usr/share/plymouth/themes/windows7 ] && had_plymouth=1
had_sysctl=0; [ -e /etc/sysctl.d/99-thewindowslinux.conf ] && had_sysctl=1
had_ssh=0; [ -e /etc/ssh/sshd_config.d/50-thewindowslinux.conf ] && had_ssh=1

removed=0; restored=0
restore_or_remove() {
    local p="$1" o="$ORIG/${1#/}"
    if [ -e "$o" ] || [ -L "$o" ]; then
        w7_rm_rf "$p"
        w7_do mkdir -p "$(dirname "$p")"
        w7_do cp -a -- "$o" "$p"
        restored=$((restored + 1))
    elif [ -e "$p" ] || [ -L "$p" ]; then
        w7_rm_rf "$p"
        removed=$((removed + 1))
    fi
}

# 1. Alle protokollierten Einträge – tiefste Pfade zuerst
if [ -f "$LIST" ]; then
    while IFS= read -r p; do
        [ -n "$p" ] || continue
        case "$p" in /*) restore_or_remove "$p" ;; esac
    done < <(sort -u "$LIST" | awk '{print length($0) "\t" $0}' | sort -rn | cut -f2-)
fi

# 2. Bekannte Pfade älterer Versionen (1.0/1.1 protokollierten nicht alles)
if [ $LEGACY -eq 1 ] || [ ! -f "$LIST" ]; then
    for t in Windows-Retro Windows7-Aero; do
        w7_rm_rf "$W7_THEMEDIR/$t"; w7_rm_rf "$W7_ICONDIR/$t"
    done
    for s in 16 22 24 32 48 64 96 128 256; do
        for n in win7-start win7-cmd win7-explorer win7-control-panel; do
            [ -e "$W7_ICONDIR/hicolor/${s}x${s}/apps/$n.png" ] && w7_rm_rf "$W7_ICONDIR/hicolor/${s}x${s}/apps/$n.png"
        done
    done
    for f in xfce4-panel xfce4-desktop xfwm4 xsettings xfce4-keyboard-shortcuts thunar xfce4-notifyd xfce4-session xfce4-appfinder xfce4-terminal; do
        [ -e "$W7_XDG_CONF/xfce4/xfconf/xfce-perchannel-xml/$f.xml" ] && restore_or_remove "$W7_XDG_CONF/xfce4/xfconf/xfce-perchannel-xml/$f.xml"
    done
    for f in "$W7_XDG_CONF/xfce4/panel/whiskermenu-1.rc" "$W7_XDG_CONF/xfce4/terminal/terminalrc" "$W7_XDG_CONF/Thunar/uca.xml"; do
        [ -e "$f" ] && restore_or_remove "$f"
    done
    for l in 2 3 4; do [ -d "$W7_XDG_CONF/xfce4/panel/launcher-$l" ] && w7_rm_rf "$W7_XDG_CONF/xfce4/panel/launcher-$l"; done
    for f in "$W7_SRC"/theme/xfce4/applications/*.desktop; do [ -e "$W7_APPDIR/$(basename "$f")" ] && w7_rm_rf "$W7_APPDIR/$(basename "$f")"; done
    for f in "$W7_SRC"/theme/xfce4/autostart/*.desktop; do [ -e "$W7_AUTOSTART/$(basename "$f")" ] && w7_rm_rf "$W7_AUTOSTART/$(basename "$f")"; done
    [ -d "$W7_DATADIR" ] && w7_rm_rf "$W7_DATADIR"
    for b in cmd cmd.exe eingabeaufforderung win7-terminal win7-sound win7-firstrun win7-wallpaper win7-doctor; do
        [ -L "$W7_BINDIR/$b" ] && w7_rm_rf "$W7_BINDIR/$b"
    done
    if [ "$W7_MODE" = system ]; then w7_rm_rf /usr/share/sounds/windows7; else w7_rm_rf "${XDG_DATA_HOME:-$HOME/.local/share}/sounds/windows7"; fi
fi

# 2b. Desktop-Cache einer nun leeren Anwendungsliste aufräumen (sonst bliebe der Ordner nicht leer)
if ! ls "$W7_APPDIR"/*.desktop >/dev/null 2>&1; then
    w7_do rm -f "$W7_APPDIR/mimeinfo.cache"; w7_do rmdir "$W7_APPDIR" 2>/dev/null || true     # Cache einer nun leeren Anwendungsliste
elif w7_have update-desktop-database; then
    w7_do update-desktop-database -q "$W7_APPDIR" 2>/dev/null || true
fi

# 3. Von uns angelegte Ordner, soweit jetzt leer (nie Ordner mit fremden Dateien)
if [ -f "$DIRS" ]; then
    while IFS= read -r d; do
        [ -n "$d" ] && [ -d "$d" ] || continue
        case "$d" in /*) ;; *) continue ;; esac
        [ "$(printf '%s' "$d" | tr -cd / | wc -c)" -ge 2 ] || continue
        w7_do find "$d" -depth -type d -empty -delete 2>/dev/null || true
    done < <(sort -u "$DIRS" | awk '{print length($0) "\t" $0}' | sort -rn | cut -f2-)
fi
if [ $LEGACY -eq 1 ] && [ "$W7_MODE" = user ]; then
    # Ältere Versionen protokollierten angelegte Ordner nicht: bekannte Orte aufräumen (nur, was leer ist)
    for d in "$W7_ICONDIR/hicolor" "$W7_ICONDIR" "$W7_APPDIR" "$(dirname "$W7_FONTDIR")" "${XDG_DATA_HOME:-$HOME/.local/share}/sounds" \
             "$W7_THEMEDIR" "$W7_AUTOSTART" "$W7_XDG_CONF/gtk-3.0" "$W7_XDG_CONF/Thunar" "$W7_XDG_CONF/xfce4" "${XDG_DATA_HOME:-$HOME/.local/share}"; do
        [ -d "$d" ] && find "$d" -depth -type d -empty -delete 2>/dev/null || true
    done
fi

# 3b. Von uns (bzw. win7-firstrun) angelegte Explorer-Lesezeichen entfernen – nur wenn nichts Eigenes darin steht
bm="${XDG_CONFIG_HOME:-$HOME/.config}/gtk-3.0/bookmarks"
if [ "$W7_MODE" = user ] || [ -f "$bm" ]; then
    if [ -f "$bm" ] && [ -s "$bm" ] && ! grep -qvE "^file://$HOME/(Downloads|Dokumente|Bilder|Musik|Videos) (Downloads|Dokumente|Bilder|Musik|Videos)$" "$bm"; then
        rm -f "$bm"; rmdir "$(dirname "$bm")" 2>/dev/null || true
    fi
fi

# 4. Einträge in Shell-Startdateien (nur unsere markierten Zeilen)
# Ältere Versionen (<1.2) hängten ihre Einträge mit einer Leerzeile davor an; die gehört dann ebenfalls weg.
strip_legacy_bashrc() {  # entfernt den alten 4-Zeilen-Block samt vorangehender Leerzeile
    awk 'BEGIN{held=0}
         /^$/ { if (held) print ""; held=1; next }
         { if ($0 == "# TheWindowsLinux") { held=0; skip=1; next }
           if (skip && ($0 ~ /^export WIN7_(DATADIR|STYLE)=/ || $0 ~ /^case ":\$PATH:" in .*\.local\/bin:.*esac$/)) next
           skip=0; if (held) { print ""; held=0 }; print }
         END { if (held) print "" }' "$1" > "$1.w7tmp" && cat "$1.w7tmp" > "$1"; rm -f "$1.w7tmp"
}
strip_block() {  # entfernt den markierten Block; im Altformat samt einer Leerzeile davor
    if [ $LEGACY -eq 1 ]; then
        awk 'BEGIN{held=0}
             /^$/ { if (held) print ""; held=1; next }
             { if ($0 ~ /# >>> TheWindowsLinux >>>/) { held=0; skip=1; next }
               if (skip) { if ($0 ~ /# <<< TheWindowsLinux <<</) skip=0; next }
               if (held) { print ""; held=0 }; print }
             END { if (held) print "" }' "$1" > "$1.w7tmp" && cat "$1.w7tmp" > "$1"; rm -f "$1.w7tmp"
    else
        sed -i '/# >>> TheWindowsLinux >>>/,/# <<< TheWindowsLinux <<</d' "$1"
    fi
}
if [ "$W7_MODE" = user ]; then
    if [ -f "$HOME/.profile" ] && grep -q '>>> TheWindowsLinux >>>' "$HOME/.profile"; then
        strip_block "$HOME/.profile"
    fi
    [ -f "$HOME/.profile" ] && [ ! -s "$HOME/.profile" ] && rm -f "$HOME/.profile"      # nur noch leer = wir hatten sie angelegt
    if [ -f "$HOME/.bashrc" ]; then
        grep -q '^# TheWindowsLinux$' "$HOME/.bashrc" && strip_legacy_bashrc "$HOME/.bashrc"
        if grep -q 'TheWindowsLinux cmd-Overlay' "$HOME/.bashrc"; then
            if [ $LEGACY -eq 1 ]; then
                awk 'BEGIN{held=0} /^$/ { if (held) print ""; held=1; next }
                     { if ($0 ~ /TheWindowsLinux cmd-Overlay/) { held=0; next } if (held) { print ""; held=0 } print }
                     END { if (held) print "" }' "$HOME/.bashrc" > "$HOME/.bashrc.w7tmp" && cat "$HOME/.bashrc.w7tmp" > "$HOME/.bashrc"; rm -f "$HOME/.bashrc.w7tmp"
            else
                sed -i '/TheWindowsLinux cmd-Overlay/d' "$HOME/.bashrc"
            fi
        fi
        [ ! -s "$HOME/.bashrc" ] && rm -f "$HOME/.bashrc"
    fi
    rm -f "$HOME/.config/autostart/win7-firstrun.desktop" "$HOME/.config/autostart/win7-logon-sound.desktop"
else
    if grep -qs 'TheWindowsLinux cmd-Overlay' /etc/bash.bashrc 2>/dev/null; then w7_root sed -i '/TheWindowsLinux cmd-Overlay/d' /etc/bash.bashrc; fi
    if grep -qs 'TheWindowsLinux cmd-Overlay' /etc/bashrc 2>/dev/null; then w7_root sed -i '/TheWindowsLinux cmd-Overlay/d' /etc/bashrc; fi
    rm -f "$HOME/.config/autostart/win7-firstrun.desktop"      # Abschalt-Datei des aktuellen Benutzers
fi

# 5. Nachbereitung systemweiter Änderungen
if [ "$W7_MODE" = system ]; then
    if [ $had_grub -eq 1 ]; then
        if w7_have update-grub; then w7_root update-grub >/dev/null 2>&1 || true
        elif w7_have grub2-mkconfig; then w7_root grub2-mkconfig -o /boot/grub2/grub.cfg >/dev/null 2>&1 || true; fi
        w7_info "GRUB-Konfiguration neu erzeugt."
    fi
    if [ $had_plymouth -eq 1 ] && w7_have plymouth-set-default-theme; then
        w7_root plymouth-set-default-theme --reset -R >/dev/null 2>&1 || w7_warn "Plymouth konnte nicht zurückgesetzt werden (sudo plymouth-set-default-theme --reset -R)."
    fi
    [ $had_sysctl -eq 1 ] && { w7_root sysctl --system >/dev/null 2>&1 || true; }
    [ $had_ssh -eq 1 ] && { w7_root systemctl reload ssh 2>/dev/null || w7_root systemctl reload sshd 2>/dev/null || true; }
fi
w7_have gtk-update-icon-cache && [ -f "$W7_ICONDIR/hicolor/index.theme" ] && w7_do gtk-update-icon-cache -f -t -q "$W7_ICONDIR/hicolor" 2>/dev/null || true

# 6. Protokoll und Sicherungen
w7_rm_rf "$W7_VARDIR"

# Laufende Sitzung wieder starten
if [ "$W7_MODE" = user ] && [ -n "${DISPLAY:-}" ] && pgrep -u "$(id -u)" -x xfce4-session >/dev/null 2>&1; then
    (xfsettingsd --replace >/dev/null 2>&1 &); (xfwm4 --replace >/dev/null 2>&1 &)
    (nohup xfce4-panel >/dev/null 2>&1 &); (xfdesktop --reload >/dev/null 2>&1 &)
fi

echo
printf '%s✔ TheWindowsLinux wurde entfernt.%s (%d Einträge entfernt, %d Originale wiederhergestellt)\n' "$C_GREEN" "$C_0" "$removed" "$restored"
echo "Zum Abschluss ab- und wieder anmelden."
echo "Nicht entfernt: installierte Pakete (xfce4, Schriften, Kali-Werkzeuge, ufw ...) und die Firewall."
