#!/usr/bin/env bash
# TheWindowsLinux – Schritt 2: Theme-Dateien des gewählten Stils installieren
#   GTK-2/3-Theme + xfwm4-Dekoration, Icon-Theme (inkl. Pixel-Cursor beim Retro-Stil),
#   Start-Icons in hicolor, Hintergrundbilder, Sounds, Schriften, Datenverzeichnis mit cmd-Overlay
# Wird von install.sh gesourct; nutzt lib/common.sh.
set -u

w7_step_theme() {
    w7_step "Theme »$W7_GTKTHEME«, Icons, Hintergründe und Sounds installieren ($W7_MODE)"

    # --- Datenverzeichnis (bin, cmd, sounds, wallpapers) -------------------
    w7_mkdir "$W7_DATADIR/bin" "$W7_DATADIR/cmd"
    local b
    for b in "$W7_SRC"/cmd/bin/*; do
        w7_install -m 755 "$b" "$W7_DATADIR/bin/$(basename "$b")"
    done
    w7_install "$W7_SRC/cmd/cmdrc.sh" "$W7_DATADIR/cmd/cmdrc.sh"
    w7_copy_tree "$W7_STYLEDIR/sounds" "$W7_DATADIR/sounds"
    w7_copy_tree "$W7_STYLEDIR/wallpapers" "$W7_DATADIR/wallpapers"
    printf '%s\n' "$W7_VERSION" | w7_do tee "$W7_DATADIR/VERSION" >/dev/null
    w7_track "$W7_DATADIR"
    W7_WALLPAPER="$W7_DATADIR/wallpapers/$W7_WALLPAPER_FILE"
    W7_LOGIN_WALLPAPER="$W7_DATADIR/wallpapers/$W7_LOGIN_WALLPAPER_FILE"
    export W7_WALLPAPER W7_LOGIN_WALLPAPER
    w7_ok "Daten in $W7_DATADIR"

    # --- GTK + xfwm4 Theme --------------------------------------------------
    local tdir="$W7_THEMEDIR/$W7_GTKTHEME"
    w7_copy_tree "$W7_STYLEDIR/gtk/$W7_GTKTHEME" "$tdir" clean
    w7_copy_tree "$W7_STYLEDIR/xfwm4/$W7_WMTHEME" "$tdir/xfwm4"
    w7_track "$tdir"
    w7_ok "GTK/xfwm4-Theme in $tdir"

    # --- Icon-Theme (+ Cursor beim Retro-Stil) + Start-Icons in hicolor ----
    local idir="$W7_ICONDIR/$W7_ICONTHEME"
    w7_copy_tree "$W7_STYLEDIR/icons/$W7_ICONTHEME" "$idir" clean
    w7_track "$idir"
    local s name
    for s in 16 22 24 32 48 64 96 128 256; do
        local src="$W7_STYLEDIR/icons/$W7_ICONTHEME/${s}x${s}/apps"
        [ -d "$src" ] || continue
        for name in win7-start win7-cmd win7-explorer win7-control-panel; do
            [ -f "$src/$name.png" ] && w7_install "$src/$name.png" "$W7_ICONDIR/hicolor/${s}x${s}/apps/$name.png"
        done
    done
    w7_install "$W7_STYLEDIR/icons/$W7_ICONTHEME/48x48/apps/win7-start.png" "$W7_DATADIR/win7-start.png"
    if w7_have gtk-update-icon-cache; then
        w7_do gtk-update-icon-cache -f -t -q "$idir" 2>/dev/null || true
        [ -f "$W7_ICONDIR/hicolor/index.theme" ] && w7_do gtk-update-icon-cache -f -t -q "$W7_ICONDIR/hicolor" 2>/dev/null || true
    fi
    w7_ok "Icon-Theme in $idir"

    # --- Sound-Theme (freedesktop) ------------------------------------------
    local sdir
    if [ "$W7_MODE" = system ]; then sdir="/usr/share/sounds/windows7"; else sdir="${XDG_DATA_HOME:-$HOME/.local/share}/sounds/windows7"; fi
    w7_mkdir "$sdir/stereo"
    w7_install "$W7_STYLEDIR/sounds/notify.wav" "$sdir/stereo/message-new-instant.wav"
    w7_install "$W7_STYLEDIR/sounds/notify.wav" "$sdir/stereo/message.wav"
    w7_install "$W7_STYLEDIR/sounds/error.wav"  "$sdir/stereo/dialog-error.wav"
    w7_install "$W7_STYLEDIR/sounds/ding.wav"   "$sdir/stereo/dialog-warning.wav"
    w7_install "$W7_STYLEDIR/sounds/ding.wav"   "$sdir/stereo/bell.wav"
    w7_install "$W7_STYLEDIR/sounds/logon.wav"  "$sdir/stereo/desktop-login.wav"
    w7_install "$W7_STYLEDIR/sounds/logoff.wav" "$sdir/stereo/desktop-logout.wav"
    local tmp; tmp="$(mktemp)"
    printf '[Sound Theme]\nName=windows7\nComment=TheWindowsLinux Systemklänge (synthetisch, Original-Kompositionen)\nInherits=freedesktop\nDirectories=stereo\n\n[stereo]\nOutputProfile=stereo\n' > "$tmp"
    w7_install "$tmp" "$sdir/index.theme"; rm -f "$tmp"
    w7_track "$sdir"
    w7_ok "Sound-Theme in $sdir"

    # --- Schriften (optional, best effort) ----------------------------------
    w7_step_fonts

    # Schrift-/Cursor-/Programmauswahl für die Konfigurationsdateien
    w7_pick_fonts; w7_pick_cursor; w7_pick_apps
    w7_info "UI-Schrift: $W7_UIFONT $W7_UIFONTSIZE · Monospace: $W7_MONOFONT $W7_MONOFONTSIZE · Cursor: $W7_CURSOR"

    # Stil-Infos für win7-firstrun und cmd
    tmp="$(mktemp)"
    cat > "$tmp" <<EOF
STYLE=$W7_STYLE
GTKTHEME=$W7_GTKTHEME
WMTHEME=$W7_WMTHEME
ICONTHEME=$W7_ICONTHEME
CURSOR=$W7_CURSOR
CURSORSIZE=$W7_CURSORSIZE
WALLPAPER=$W7_WALLPAPER
CMD_VERSION=$W7_CMD_VERSION
UIFONT=$W7_UIFONT
UIFONTSIZE=$W7_UIFONTSIZE
MONOFONT=$W7_MONOFONT
MONOFONTSIZE=$W7_MONOFONTSIZE
AA=$W7_AA
HINTSTYLE=$W7_HINTSTYLE
RGBA=$W7_RGBA
EOF
    w7_install "$tmp" "$W7_DATADIR/style.conf"; rm -f "$tmp"
}

# Segoe-UI-Ersatz "Selawik" (Microsoft, SIL Open Font License). Wird NICHT automatisch geladen:
# Schriften werden von FreeType/Pango eingelesen, und für den Download gibt es hier keine geprüfte Prüfsumme.
# Nur mit --with-selawik, nur für den Aero-Stil, und die SHA-256-Summen werden zur Kontrolle angezeigt.
w7_step_fonts() {
    if [ "$W7_STYLE" = retro ]; then
        if w7_font_available "Terminus"; then w7_info "Pixel-Schrift Terminus vorhanden."
        else w7_info "Terminus (fonts-terminus-otb / terminus-font) nicht gefunden – es wird eine Vektorschrift ohne Antialiasing genutzt."; fi
        return 0
    fi
    [ "${W7_WITH_SELAWIK:-0}" = 1 ] || { w7_info "Selawik wird nicht geladen (Option --with-selawik); es werden Noto Sans/DejaVu genutzt."; return 0; }
    w7_font_available "Selawik" && { w7_info "Selawik bereits vorhanden."; return 0; }
    w7_have curl || { w7_warn "curl fehlt – Selawik-Download übersprungen."; return 0; }
    w7_warn "Lade Selawik von GitHub (ungeprüfter Download – bitte die angezeigten Prüfsummen vergleichen)."
    local tmpd ok=0 f url magic
    tmpd="$(mktemp -d)"
    for f in Selawik-Regular Selawik-Bold Selawik-Semibold Selawik-Light Selawik-Semilight; do
        for url in \
            "https://raw.githubusercontent.com/microsoft/Selawik/master/fonts/$f.ttf" \
            "https://github.com/microsoft/Selawik/raw/master/fonts/$f.ttf"; do
            if curl -fsSL --proto '=https' --tlsv1.2 --connect-timeout 8 -m 40 -o "$tmpd/$f.ttf" "$url" 2>/dev/null && [ -s "$tmpd/$f.ttf" ]; then
                magic="$(head -c4 "$tmpd/$f.ttf" | od -An -tx1 | tr -d ' \n')"
                if [ "$magic" = 00010000 ] || [ "$magic" = 4f54544f ]; then
                    w7_info "$f.ttf  sha256 $(sha256sum "$tmpd/$f.ttf" | cut -d' ' -f1)"; ok=1; break
                fi
            fi
            rm -f "$tmpd/$f.ttf"
        done
    done
    if [ $ok -eq 1 ]; then
        w7_mkdir "$W7_FONTDIR"
        for f in "$tmpd"/*.ttf; do w7_install "$f" "$W7_FONTDIR/$(basename "$f")"; done
        w7_have fc-cache && { if [ "$W7_MODE" = system ]; then w7_root fc-cache -f >/dev/null 2>&1; else fc-cache -f >/dev/null 2>&1; fi; }
        w7_ok "Selawik (Segoe-UI-Ersatz) installiert."
    else
        w7_info "Selawik nicht herunterladbar (offline/geblockt) – es wird Noto Sans bzw. DejaVu Sans verwendet."
    fi
    rm -rf "$tmpd"
}
