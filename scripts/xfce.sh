#!/usr/bin/env bash
# TheWindowsLinux – Schritt 3: XFCE konfigurieren
#   xfconf-Kanäle (Panel, Desktop, xfwm4, xsettings, Tastenkürzel, Thunar, Notifyd, Session, Appfinder),
#   Whisker-Menü, Panel-Starter, Terminalprofil, Thunar-Aktionen/Lesezeichen,
#   Menüeinträge (Windows-Namen), Autostart, Umgebungsvariablen
# Wird von install.sh gesourct; nutzt lib/common.sh.
set -u

w7_step_xfce() {
    w7_step "XFCE konfigurieren ($W7_MODE)"
    W7_CMD_LAUNCH="$W7_DATADIR/bin/win7-terminal"
    export W7_CMD_LAUNCH

    local session_running=0
    if [ "$W7_MODE" = user ] && w7_xfce_running; then
        session_running=1
        # Laufende Komponenten schreiben ihren Speicherstand beim Beenden zurück und
        # würden unsere frisch geschriebenen Dateien überschreiben → vorher beenden.
        # (xfce4-panel speichert whiskermenu-*.rc / die Plugin-Liste beim Neustart.)
        pkill -u "$(id -u)" -x xfce4-panel 2>/dev/null || true
        pkill -u "$(id -u)" -x xfconfd 2>/dev/null || true
        sleep 1
    fi

    # --- xfconf-Kanäle ----------------------------------------------------------
    local confdirs=("$W7_XDG_CONF/xfce4/xfconf/xfce-perchannel-xml")
    if [ "$W7_MODE" = system ]; then
        # Distributions-Overlays (Xubuntu, Mint ...) haben Vorrang vor /etc/xdg → dort ebenfalls ablegen
        local d
        for d in /etc/xdg/xdg-*/xfce4/xfconf/xfce-perchannel-xml; do
            [ -d "$d" ] && confdirs+=("$d")
        done
    fi
    local dir f
    for dir in "${confdirs[@]}"; do
        w7_mkdir "$dir"
        for f in "$W7_SRC"/theme/xfce4/xfconf/*.xml; do
            local name; name="$(basename "$f")"
            [ "$W7_MODE" = user ] && w7_backup "$dir/$name"
            w7_render "$f" "$dir/$name"
            w7_track "$dir/$name"
        done
    done
    w7_ok "xfconf-Kanäle in ${confdirs[0]}"

    # --- Panel: Whisker-Menü + Starter -------------------------------------------
    local pdir="$W7_XDG_CONF/xfce4/panel"
    [ "$W7_MODE" = user ] && w7_backup "$pdir"
    w7_render "$W7_SRC/theme/xfce4/panel/whiskermenu-1.rc" "$pdir/whiskermenu-1.rc"
    local l
    for l in "$W7_SRC"/theme/xfce4/panel/launcher-*; do
        local ln; ln="$(basename "$l")"
        for f in "$l"/*.desktop; do
            w7_render "$f" "$pdir/$ln/$(basename "$f")"
        done
    done
    w7_track "$pdir/whiskermenu-1.rc"
    w7_ok "Panel-Konfiguration in $pdir"

    # --- Terminal-Profil "Eingabeaufforderung" -----------------------------------
    local tdir="$W7_XDG_CONF/xfce4/terminal"
    [ "$W7_MODE" = user ] && w7_backup "$tdir/terminalrc"
    w7_render "$W7_SRC/theme/xfce4/terminal/terminalrc" "$tdir/terminalrc"
    w7_track "$tdir/terminalrc"
    # Neuere xfce4-terminal-Versionen (>= 1.1) lesen den xfconf-Kanal "xfce4-terminal" statt terminalrc
    local tmpx; tmpx="$(mktemp)"
    w7_terminalrc_to_xfconf "$tdir/terminalrc" > "$tmpx"
    for dir in "${confdirs[@]}"; do
        w7_install "$tmpx" "$dir/xfce4-terminal.xml"
        w7_track "$dir/xfce4-terminal.xml"
    done
    rm -f "$tmpx"

    # --- Thunar: Kontextmenü-Aktionen + Lesezeichen ------------------------------
    [ "$W7_MODE" = user ] && w7_backup "$W7_XDG_CONF/Thunar/uca.xml"
    w7_render "$W7_SRC/theme/xfce4/Thunar/uca.xml" "$W7_XDG_CONF/Thunar/uca.xml"
    w7_track "$W7_XDG_CONF/Thunar/uca.xml"
    if [ "$W7_MODE" = user ]; then
        if [ ! -s "$W7_XDG_CONF/gtk-3.0/bookmarks" ]; then
            w7_render "$W7_SRC/theme/xfce4/Thunar/bookmarks" "$W7_XDG_CONF/gtk-3.0/bookmarks"
            w7_track "$W7_XDG_CONF/gtk-3.0/bookmarks"
        fi
        # deutsche XDG-Ordner anlegen, falls noch nicht vorhanden
        w7_have xdg-user-dirs-update && xdg-user-dirs-update 2>/dev/null || true
        mkdir -p "$HOME/Desktop" 2>/dev/null || true
    else
        w7_mkdir "$W7_SKEL/.config/gtk-3.0"
        w7_render "$W7_SRC/theme/xfce4/Thunar/bookmarks" "$W7_SKEL/.config/gtk-3.0/bookmarks"
    fi

    # --- Menüeinträge mit Windows-Namen ------------------------------------------
    w7_mkdir "$W7_APPDIR"
    for f in "$W7_SRC"/theme/xfce4/applications/*.desktop; do
        w7_render "$f" "$W7_APPDIR/$(basename "$f")"
        w7_track "$W7_APPDIR/$(basename "$f")"
    done
    w7_have update-desktop-database && w7_do update-desktop-database -q "$W7_APPDIR" 2>/dev/null || true
    w7_ok "Menüeinträge (Windows-Explorer, Eingabeaufforderung, Systemsteuerung, Editor, ...)"

    # --- Autostart --------------------------------------------------------------
    w7_mkdir "$W7_AUTOSTART"
    for f in "$W7_SRC"/theme/xfce4/autostart/*.desktop; do
        w7_render "$f" "$W7_AUTOSTART/$(basename "$f")"
        w7_track "$W7_AUTOSTART/$(basename "$f")"
    done
    # Ersteinrichtung soll beim nächsten Login (wieder) laufen
    [ "$W7_MODE" = user ] && rm -f "$W7_STATE/firstrun-done"

    # --- Umgebungsvariablen (klassische Scrollbalken, Qt im GTK-Look) -------------
    w7_step_env

    # --- Laufende Sitzung aktualisieren ---------------------------------------------
    if [ $session_running -eq 1 ]; then
        w7_info "Laufende XFCE-Sitzung wird aktualisiert ..."
        # WICHTIG: xfconfd muss unsere neuen Kanal-XML-Dateien geladen haben, BEVOR das Panel
        # startet – sonst baut das Panel ein Standard-Layout und überschreibt unsere Config.
        # Ein xfconf-query erzwingt das Nachladen (xfconfd wird per D-Bus gestartet).
        local i
        for i in $(seq 1 20); do
            xfconf-query -c xfce4-panel -p /plugins/plugin-1 >/dev/null 2>&1 && break
            sleep 0.3
        done
        (xfsettingsd --replace >/dev/null 2>&1 &) ; sleep 1
        (xfwm4 --replace >/dev/null 2>&1 &)
        # Panel wurde oben beendet → frisch starten, damit es die neue Konfiguration liest
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
        val="${val//&/&amp;}"; val="${val//</&lt;}"; val="${val//>/&gt;}"; val="${val//\"/&quot;}"
        printf '  <property name="%s" type="%s" value="%s"/>\n' "$name" "$type" "$val"
    done
    echo '</channel>'
}

w7_step_env() {
    local block
    block="$(cat <<'EOF'
# >>> TheWindowsLinux >>>
export GTK_OVERLAY_SCROLLING=0           # klassische Scrollbalken mit Pfeilen
export QT_QPA_PLATFORMTHEME=gtk2         # Qt-Programme im GTK-Look (wenn qt5-gtk2-platformtheme installiert)
export QT_STYLE_OVERRIDE=gtk2
export WIN7_DATADIR="@DATADIR@"
export WIN7_STYLE="@STYLE@"
case ":$PATH:" in *":@BINDIR@:"*) ;; *) export PATH="@BINDIR@:$PATH" ;; esac
# <<< TheWindowsLinux <<<
EOF
)"
    block="${block//@DATADIR@/$W7_DATADIR}"
    block="${block//@BINDIR@/$W7_BINDIR}"
    block="${block//@STYLE@/$W7_STYLE}"
    if [ "$W7_MODE" = system ]; then
        printf '%s\n' "$block" | w7_root tee "$W7_PROFILE" >/dev/null
        w7_track "$W7_PROFILE"
    else
        touch "$W7_PROFILE"
        if ! grep -q '>>> TheWindowsLinux >>>' "$W7_PROFILE"; then
            w7_backup "$W7_PROFILE"
            printf '\n%s\n' "$block" >> "$W7_PROFILE"
        else
            # Block ersetzen
            local tmp; tmp="$(mktemp)"
            awk -v blk="$block" '
                /# >>> TheWindowsLinux >>>/ {skip=1; print blk; next}
                /# <<< TheWindowsLinux <<</ {skip=0; next}
                !skip {print}' "$W7_PROFILE" > "$tmp" && cat "$tmp" > "$W7_PROFILE"
            rm -f "$tmp"
        fi
        # Auch für Shells, die nur ~/.bashrc lesen
        if [ -f "$HOME/.bashrc" ] && ! grep -q 'WIN7_DATADIR' "$HOME/.bashrc"; then
            printf '\n# TheWindowsLinux\nexport WIN7_DATADIR="%s"\nexport WIN7_STYLE="%s"\ncase ":$PATH:" in *":%s:"*) ;; *) export PATH="%s:$PATH" ;; esac\n' "$W7_DATADIR" "$W7_STYLE" "$W7_BINDIR" "$W7_BINDIR" >> "$HOME/.bashrc"
        fi
    fi
    w7_ok "Umgebungsvariablen in $W7_PROFILE"
}
