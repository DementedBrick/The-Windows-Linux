#!/usr/bin/env bash
# ============================================================================
#  TheWindowsLinux – Installer
#  Verwandelt ein normales Linux (XFCE) in einen Windows-7-Desktop
#  inkl. "Eingabeaufforderung" (cmd-Terminal-Overlay).
#
#  Schnellstart:   ./install.sh                 (für den aktuellen Benutzer)
#                  sudo ./install.sh --system   (für alle Benutzer + Anmeldebildschirm)
#
#  ./install.sh --help zeigt alle Optionen.
# ============================================================================
set -euo pipefail

W7_SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export W7_SRC
# shellcheck source=lib/common.sh
. "$W7_SRC/lib/common.sh"
for s in packages theme xfce cmd login harden kali; do
    # shellcheck source=/dev/null
    . "$W7_SRC/scripts/$s.sh"
done

usage() {
    cat <<EOF
${C_B}TheWindowsLinux ${W7_VERSION}${C_0} – Windows-7-Overlay für Linux (XFCE)

Verwendung: $0 [Optionen]

Stil
  --style retro       Pixel-Retro-Look (Windows-95-artig, 16 Farben, Dithering, Pixel-Schrift)  [Standard]
  --style aero        Windows-7-Aero-Look (Glas-Rahmen, Start-Orb)

Modus
  --user              Nur für den aktuellen Benutzer installieren (~/.themes, ~/.config …)  [Standard]
  --system            Für alle Benutzer installieren (/usr/share, /etc/xdg, /etc/skel) – benötigt root

Umfang
  --no-packages       Keine Pakete installieren (XFCE muss schon vorhanden sein)
  --with-selawik      Aero-Stil: Schrift Selawik von GitHub laden (ungeprüfter Download, Prüfsummen werden angezeigt)
  --cmd-everywhere    cmd-Overlay in JEDER bash aktivieren (nicht nur in der »Eingabeaufforderung«)
  --with-login        Anmeldebildschirm (LightDM GTK-Greeter) im Windows-7-Look   (nur --system)
  --with-grub         GRUB-Hintergrund setzen                                       (nur --system)
  --with-plymouth     Plymouth-Boot-Splash installieren                             (nur --system)
  --full              = --system --with-login --with-grub --with-plymouth --cmd-everywhere

Werkzeuge und Absicherung (optional)
  --with-kali-tools[=STUFE]  Kali-Werkzeuge installieren. Auf Kali: Metapakete (core, top10, default, large, everything,
                      headless oder eine Kategorie wie web/wireless/passwords). Sonst: die Kali-typischen Werkzeuge
                      aus den normalen Paketquellen (Stufe top10 = die wichtigsten, sonst alle verfügbaren).
  --kali-level STUFE  wie oben, getrennt angegeben
  --harden            System absichern: Firewall (ufw), automatische Sicherheitsupdates, Kernel-Einstellungen,
                      SSH-Härtung                                                       (nur --system)

Sonstiges
  --yes, -y           Keine Rückfrage
  --quiet             Weniger Ausgabe
  --help, -h          Diese Hilfe

Nach der Installation: abmelden und mit der Sitzung »Xfce« neu anmelden.
EOF
}

W7_MODE=user
W7_STYLE=retro
W7_NO_PACKAGES=0
W7_WITH_SELAWIK=0
W7_WITH_KALI=0
W7_KALI_LEVEL=default
W7_HARDEN=0
W7_CMD_EVERYWHERE=0
W7_WITH_LOGIN=0
W7_WITH_GRUB=0
W7_WITH_PLYMOUTH=0
W7_YES=0
W7_QUIET=0
while [ $# -gt 0 ]; do
    case "$1" in
        --user) W7_MODE=user ;;
        --system) W7_MODE=system ;;
        --style) W7_STYLE="${2:-}"; shift ;;
        --style=*) W7_STYLE="${1#*=}" ;;
        --retro) W7_STYLE=retro ;;
        --aero) W7_STYLE=aero ;;
        --no-packages) W7_NO_PACKAGES=1 ;;
        --no-fonts) ;;   # (veraltet: Selawik wird nur noch mit --with-selawik geladen)
        --with-selawik) W7_WITH_SELAWIK=1 ;;
        --with-kali-tools) W7_WITH_KALI=1 ;;
        --with-kali-tools=*) W7_WITH_KALI=1; W7_KALI_LEVEL="${1#*=}" ;;
        --kali-level) W7_WITH_KALI=1; W7_KALI_LEVEL="${2:-default}"; shift ;;
        --kali-level=*) W7_WITH_KALI=1; W7_KALI_LEVEL="${1#*=}" ;;
        --harden) W7_HARDEN=1 ;;
        --cmd-everywhere) W7_CMD_EVERYWHERE=1 ;;
        --with-login) W7_WITH_LOGIN=1 ;;
        --with-grub) W7_WITH_GRUB=1 ;;
        --with-plymouth) W7_WITH_PLYMOUTH=1 ;;
        --full) W7_MODE=system; W7_WITH_LOGIN=1; W7_WITH_GRUB=1; W7_WITH_PLYMOUTH=1; W7_CMD_EVERYWHERE=1 ;;
        --yes|-y) W7_YES=1 ;;
        --quiet|-q) W7_QUIET=1 ;;
        --help|-h) usage; exit 0 ;;
        *) w7_err "Unbekannte Option: $1"; usage; exit 2 ;;
    esac
    shift
done
export W7_MODE W7_STYLE W7_NO_PACKAGES W7_WITH_SELAWIK W7_WITH_KALI W7_KALI_LEVEL W7_HARDEN W7_CMD_EVERYWHERE W7_WITH_LOGIN W7_WITH_GRUB W7_WITH_PLYMOUTH W7_QUIET

# ---------------------------------------------------------------------------
w7_detect_distro
w7_setup_paths
w7_setup_style
W7_RUN_ID="$(date +%Y%m%d-%H%M%S)"
export W7_RUN_ID

if [ "$W7_MODE" = system ] && [ "$(id -u)" -ne 0 ] && ! w7_can_root; then
    w7_die "--system benötigt root-Rechte (sudo ./install.sh --system)."
fi
# Als root im Benutzermodus würde alles nach /root installieren und der Desktop des normalen Benutzers
# bliebe unverändert – das ist fast immer ein Versehen (z. B. »sudo ./install.sh« ohne --system).
if [ "$W7_MODE" = user ] && [ "$(id -u)" -eq 0 ] && [ "${W7_ALLOW_ROOT_USER:-0}" != 1 ]; then
    w7_die "Du bist root. Starte ohne sudo (./install.sh) für deinen Benutzer, oder nutze --system für alle Benutzer."
fi
w7_do mkdir -p "$W7_VARDIR"
w7_migrate_legacy

printf '\n%s╔══════════════════════════════════════════════════════════════╗%s\n' "$C_BLUE" "$C_0"
printf '%s║%s   TheWindowsLinux %-6s – Windows-Overlay für Linux (XFCE)     %s║%s\n' "$C_BLUE" "$C_0" "$W7_VERSION" "$C_BLUE" "$C_0"
printf '%s╚══════════════════════════════════════════════════════════════╝%s\n\n' "$C_BLUE" "$C_0"
w7_info "Distribution : ${W7_DISTRO_NAME:-unbekannt} (${W7_DISTRO})"
w7_info "Stil         : $W7_STYLE ($W7_GTKTHEME)"
w7_info "Modus        : $W7_MODE"
w7_info "Datenordner  : $W7_DATADIR"
w7_info "Themes       : $W7_THEMEDIR · Icons: $W7_ICONDIR"
w7_info "XFCE-Konfig  : $W7_XDG_CONF/xfce4"
[ "$W7_NO_PACKAGES" = 1 ] || w7_info "Pakete       : werden installiert ($W7_PKG)"
[ "$W7_CMD_EVERYWHERE" = 1 ] && w7_info "cmd-Overlay  : in jeder bash"
[ "$W7_WITH_LOGIN" = 1 ] && w7_info "Login        : LightDM-Greeter wird angepasst"
[ "$W7_WITH_KALI" = 1 ] && w7_info "Kali-Tools   : Stufe $W7_KALI_LEVEL"
[ "$W7_HARDEN" = 1 ] && w7_info "Absicherung  : Firewall, Auto-Updates, Kernel-Einstellungen, SSH"
echo
if [ "$W7_YES" != 1 ] && [ -t 0 ]; then
    read -r -p "Fortfahren? [J/n] " ans
    case "${ans,,}" in n|nein|no) echo "Abgebrochen."; exit 0 ;; esac
fi

# ---------------------------------------------------------------------------
w7_step_packages
w7_check_xfce || true
w7_step_theme
w7_step_xfce
w7_step_cmd
w7_step_login
w7_step_grub
w7_step_plymouth
w7_step_harden
w7_step_kali

# Installationsprotokoll
tmpinfo="$(mktemp)"
{
    echo "version=$W7_VERSION"
    echo "style=$W7_STYLE"
    echo "mode=$W7_MODE"
    echo "date=$W7_RUN_ID"
    echo "kali=$W7_WITH_KALI"
    echo "harden=$W7_HARDEN"
    echo "datadir=$W7_DATADIR"
    echo "themedir=$W7_THEMEDIR/$W7_GTKTHEME"
    echo "icondir=$W7_ICONDIR/$W7_ICONTHEME"
    echo "xdgconf=$W7_XDG_CONF"
    echo "appdir=$W7_APPDIR"
    echo "bindir=$W7_BINDIR"
    echo "autostart=$W7_AUTOSTART"
    echo "profile=$W7_PROFILE"
} > "$tmpinfo"
w7_do install -m 644 "$tmpinfo" "$W7_VARDIR/install.info"; rm -f "$tmpinfo"

echo
printf '%s✔ Fertig.%s TheWindowsLinux ist installiert.\n\n' "$C_GREEN" "$C_0"
if w7_xfce_running && [ "$W7_MODE" = user ]; then
    echo "Die laufende XFCE-Sitzung wurde aktualisiert. Für alle Details (Tastenkürzel, Sounds) einmal ab- und wieder anmelden."
else
    echo "Jetzt abmelden und mit der Sitzung »Xfce« neu anmelden (bzw. neu starten)."
fi
cat <<EOF

  Startmenü ........ Windows-Taste  ·  Explorer: Win+E  ·  Ausführen: Win+R  ·  Desktop: Win+D
  Eingabeaufforderung  Strg+Alt+T oder Befehl »cmd«   (DIR, CLS, COPY, IPCONFIG, TASKLIST, ...)
  Aero Snap ........ Win+Pfeiltasten  ·  Sperren: Win+L  ·  Task-Manager: Strg+Umschalt+Esc
  Anderer Stil ..... $W7_SRC/install.sh --style $( [ "$W7_STYLE" = retro ] && printf 'aero' || printf 'retro') --no-packages$( [ "$W7_MODE" = system ] && printf ' --system')
  Systemprüfung .... win7-doctor   (Updates, Firewall, offene Ports, Konten, Kernel – nur lesend; mit sudo gründlicher)
  Hintergrund ...... win7-wallpaper list
  Deinstallation ... $W7_SRC/uninstall.sh$( [ "$W7_MODE" = system ] && printf ' --system')
EOF
