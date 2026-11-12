#!/usr/bin/env bash
# TheWindowsLinux – Schritt 3: XFCE konfigurieren
#   xfconf-Kanäle (Panel, Desktop, xfwm4, xsettings, Tastenkürzel, Thunar, Notifyd, Session, Appfinder, Terminal),
#   Whisker-Menü, Panel-Starter, Terminalprofil, Thunar-Aktionen/Lesezeichen,
#   Menüeinträge (Windows-Namen), Autostart, Umgebungsvariablen
#
#   Benutzermodus: ~/.config      Systemmodus: /etc/xdg (alle Benutzer) UND /etc/skel (neue Benutzer –
#   Distributionen wie Kali legen dort eigene XFCE-Konfiguration ab, die sonst Vorrang hätte)
# Wird von install.sh gesourct; nutzt lib/common.sh.
set -u

# Konfigurationswurzeln, in die geschrieben wird
w7_xfce_roots() {
    if [ "$W7_MODE" = system ]; then
        printf '%s\n' /etc/xdg
        [ -n "$W7_SKEL" ] && printf '%s\n' "$W7_SKEL/.config"
    else
        printf '%s\n' "$W7_XDG_CONF"
    fi
}

# Gehört die Zieldatei der Distribution (existiert, stammt aber nicht von uns)?
w7_foreign() { [ -e "$1" ] && ! grep -qxF -- "$1" "$W7_VARDIR/installed-files.txt" 2>/dev/null; }

# Rendern; an GEMEINSAMEN Orten (shared=1, also /etc/xdg) wird nie eine Datei der Distribution überschrieben:
# z. B. enthält deren xfce4-session.xml die Failsafe-Sitzung – ohne sie startet für niemanden ein Desktop.
# Neue Benutzer bekommen unsere Fassung in ihr eigenes Profil (/etc/skel); xfconf führt beide Ebenen zusammen.
w7_render_shared() {  # w7_render_shared SHARED QUELLE ZIEL
    local shared="$1"; shift
    if [ "$shared" = 1 ] && w7_foreign "$2"; then
        w7_info "unverändert (gehört der Distribution): $2"
        return 0
    fi
    w7_render "$@"
}

# xfconf-Kanäle schreiben (inkl. xfce4-terminal-Kanal aus dem Terminalprofil)
w7_xfce_write_channels() {  # w7_xfce_write_channels ZIELVERZEICHNIS [shared]
    local dir="$1" shared="${2:-0}" f rc tmpx
    for f in "$W7_SRC"/theme/xfce4/xfconf/*.xml; do
        w7_render_shared "$shared" "$f" "$dir/$(basename "$f")"
    done
    # xfce4-terminal ≥ 1.1 liest seine Einstellungen aus dem xfconf-Kanal statt aus terminalrc
    rc="$(mktemp)"; tmpx="$(mktemp)"
    w7_render_text "$W7_SRC/theme/xfce4/terminal/terminalrc" > "$rc"
    w7_terminalrc_to_xfconf "$rc" > "$tmpx"
    if ! { [ "$shared" = 1 ] && w7_foreign "$dir/xfce4-terminal.xml"; }; then w7_install "$tmpx" "$dir/xfce4-terminal.xml"; fi
    rm -f "$rc" "$tmpx"
}

w7_xfce_write_root() {  # w7_xfce_write_root WURZEL
    local root="$1" l ln f shared=0
    [ "$W7_MODE" = system ] && [ "$root" = /etc/xdg ] && shared=1
    w7_xfce_write_channels "$root/xfce4/xfconf/xfce-perchannel-xml" "$shared"
    # Panel: Whisker-Menü + Starter
    w7_render_shared "$shared" "$W7_SRC/theme/xfce4/panel/whiskermenu-1.rc" "$root/xfce4/panel/whiskermenu-1.rc"
    for l in "$W7_SRC"/theme/xfce4/panel/launcher-*; do
        ln="$(basename "$l")"
        for f in "$l"/*.desktop; do w7_render_shared "$shared" "$f" "$root/xfce4/panel/$ln/$(basename "$f")"; done
    done
    # Terminal-Profil "Eingabeaufforderung" (Altformat) und Thunar-Aktionen
    w7_render_shared "$shared" "$W7_SRC/theme/xfce4/terminal/terminalrc" "$root/xfce4/terminal/terminalrc"
    w7_render_shared "$shared" "$W7_SRC/theme/xfce4/Thunar/uca.xml" "$root/Thunar/uca.xml"
}

w7_step_xfce() {
    w7_step "XFCE konfigurieren ($W7_MODE)"
    W7_CMD_LAUNCH="$W7_DATADIR/bin/win7-terminal"
    export W7_CMD_LAUNCH

    local session_running=0 root d f
    if [ "$W7_MODE" = user ] && w7_xfce_running; then
        session_running=1
        # Laufende Komponenten schreiben ihren Speicherstand beim Beenden zurück und würden unsere
        # frisch geschriebenen Dateien überschreiben → vorher beenden.
        pkill -u "$(id -u)" -x xfce4-panel 2>/dev/null || true
        pkill -u "$(id -u)" -x xfconfd 2>/dev/null || true
        sleep 1
    fi

    while IFS= read -r root; do w7_xfce_write_root "$root"; done < <(w7_xfce_roots)
    w7_ok "XFCE-Konfiguration geschrieben ($(w7_xfce_roots | tr '\n' ' '))"

    if [ "$W7_MODE" = system ]; then
        # Distributions-Overlays (Xubuntu, Mint ...) haben Vorrang vor /etc/xdg → dort ebenfalls ablegen
        for d in /etc/xdg/xdg-*/xfce4/xfconf/xfce-perchannel-xml; do
            [ -d "$d" ] && w7_xfce_write_channels "$d" 1
        done
        # (GTK-Lesezeichen brauchen absolute Pfade: win7-firstrun legt sie beim ersten Login des Benutzers an)
    else
        [ -s "$W7_XDG_CONF/gtk-3.0/bookmarks" ] || w7_render "$W7_SRC/theme/xfce4/Thunar/bookmarks" "$W7_XDG_CONF/gtk-3.0/bookmarks"
        # Leave standard XDG user-directory setup to the desktop session; it is outside this reversible overlay.
        mkdir -p "$HOME/Desktop" 2>/dev/null || true
    fi

    # Menüeinträge mit Windows-Namen
    for f in "$W7_SRC"/theme/xfce4/applications/*.desktop; do
        w7_render "$f" "$W7_APPDIR/$(basename "$f")"
    done
    w7_have update-desktop-database && w7_do update-desktop-database -q "$W7_APPDIR" 2>/dev/null || true
    w7_ok "Menüeinträge (Windows-Explorer, Eingabeaufforderung, Systemsteuerung, Editor, ...)"

    # Autostart (Ersteinrichtung + Anmeldesound)
    for f in "$W7_SRC"/theme/xfce4/autostart/*.desktop; do
        w7_render "$f" "$W7_AUTOSTART/$(basename "$f")"
    done
    # Ersteinrichtung soll beim nächsten Login (wieder) laufen
    [ "$W7_MODE" = user ] && rm -f "$W7_STATE/firstrun-done"

    w7_step_env

    # Laufende Sitzung aktualisieren
    if [ $session_running -eq 1 ]; then
        w7_info "Laufende XFCE-Sitzung wird aktualisiert ..."
        # xfconfd muss unsere neuen Kanal-Dateien geladen haben, BEVOR das Panel startet –
        # sonst baut das Panel ein Standard-Layout und überschreibt unsere Konfiguration.
        for _ in $(seq 1 20); do
            xfconf-query -c xfce4-panel -p /plugins/plugin-1 >/dev/null 2>&1 && break
            sleep 0.3
        done
        (xfsettingsd --replace >/dev/null 2>&1 &) ; sleep 1
        (xfwm4 --replace >/dev/null 2>&1 &)
        (nohup xfce4-panel >/dev/null 2>&1 &) ; sleep 2
        (xfdesktop --reload >/dev/null 2>&1 || (nohup xfdesktop >/dev/null 2>&1 &))
        "$W7_DATADIR/bin/win7-firstrun" --force >/dev/null 2>&1 || true
        w7_ok "Sitzung aktualisiert."
    fi
}

# terminalrc (Key=Value) in einen xfconf-Kanal umwandeln: FontName → /font-name usw.
w7_terminalrc_to_xfconf() {
    local src="$1"
    echo '<?xml version="1.0" encoding="UTF-8"?>'
    echo '<channel name="xfce4-terminal" version="1.0">'
    grep -E '^[A-Za-z]+=' "$src" | while IFS='=' read -r key val; do
        local name type
        name="$(printf '%s' "$key" | sed -E 's/([a-z0-9])([A-Z])/\1-\2/g' | tr '[:upper:]' '[:lower:]')"
        case "$val" in
            TRUE)  type=bool; val=true ;;
            FALSE) type=bool; val=false ;;
            *)
                if printf '%s' "$val" | grep -Eq '^-?[0-9]+$'; then type=int
                elif printf '%s' "$val" | grep -Eq '^-?[0-9]+\.[0-9]+$'; then type=double
                else type=string; fi ;;
        esac
        val="$(w7_xml_escape "$val")"
        printf '  <property name="%s" type="%s" value="%s"/>\n' "$name" "$type" "$val"
    done
    echo '</channel>'
}

# Umgebung für Sitzungen: klassische Scrollbalken (GTK_OVERLAY_SCROLLING=0), Programmpfad, Stil
w7_step_env() {
    local block
    block="$(cat <<EOF
# >>> TheWindowsLinux >>>
export GTK_OVERLAY_SCROLLING=0           # klassische Scrollbalken mit Pfeilen
export WIN7_DATADIR="$W7_DATADIR"
export WIN7_STYLE="$W7_STYLE"
case ":\$PATH:" in *":$W7_BINDIR:"*) ;; *) export PATH="$W7_BINDIR:\$PATH" ;; esac
# <<< TheWindowsLinux <<<
EOF
)"
    if [ "$W7_MODE" = system ]; then
        local tmp; tmp="$(mktemp)"
        printf '%s\n' "$block" > "$tmp"
        w7_install "$tmp" "$W7_PROFILE"
        rm -f "$tmp"
    else
        touch "$W7_PROFILE"
        # alten Block (falls vorhanden) entfernen, neuen anhängen – Rest der Datei bleibt byte-genau unberührt
        sed -i '/# >>> TheWindowsLinux >>>/,/# <<< TheWindowsLinux <<</d' "$W7_PROFILE"
        [ -s "$W7_PROFILE" ] && [ -n "$(tail -c1 "$W7_PROFILE")" ] && echo >> "$W7_PROFILE"   # fehlenden Zeilenumbruch ergänzen
        printf '%s\n' "$block" >> "$W7_PROFILE"
    fi
    w7_ok "Umgebungsvariablen in $W7_PROFILE"
}
