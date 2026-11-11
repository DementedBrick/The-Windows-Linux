# shellcheck shell=bash
# TheWindowsLinux – gemeinsame Funktionen für install.sh / uninstall.sh / scripts/*.sh
# Wird gesourct, nicht ausgeführt.

W7_VERSION="1.1.0"

# ---------------------------------------------------------------------------
# Ausgabe
# ---------------------------------------------------------------------------
if [ -t 1 ]; then
    C_B=$'\033[1m'; C_BLUE=$'\033[1;34m'; C_GREEN=$'\033[1;32m'; C_YELLOW=$'\033[1;33m'; C_RED=$'\033[1;31m'; C_0=$'\033[0m'
else
    C_B=""; C_BLUE=""; C_GREEN=""; C_YELLOW=""; C_RED=""; C_0=""
fi
w7_step() { printf '%s[%s]%s %s\n' "$C_BLUE" "TheWindowsLinux" "$C_0" "$*"; }
w7_ok()   { printf '%s  ✔%s %s\n' "$C_GREEN" "$C_0" "$*"; }
w7_warn() { printf '%s  !%s %s\n' "$C_YELLOW" "$C_0" "$*" >&2; }
w7_err()  { printf '%s  ✘ %s%s\n' "$C_RED" "$*" "$C_0" >&2; }
w7_die()  { w7_err "$@"; exit 1; }
w7_info() { [ "${W7_QUIET:-0}" = 1 ] || printf '    %s\n' "$*"; }

w7_have() { command -v "$1" >/dev/null 2>&1; }

# ---------------------------------------------------------------------------
# Distribution / Paketverwaltung
# ---------------------------------------------------------------------------
w7_detect_distro() {
    W7_DISTRO=unknown; W7_DISTRO_ID=""; W7_PKG=""; W7_DISTRO_LIKE=""; W7_DISTRO_NAME=""
    if [ -r /etc/os-release ]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        W7_DISTRO_ID="${ID:-}"
        W7_DISTRO_LIKE="${ID_LIKE:-}"
        W7_DISTRO_NAME="${PRETTY_NAME:-$W7_DISTRO_ID}"
    fi
    case "${W7_DISTRO_ID} ${W7_DISTRO_LIKE}" in
        *debian*|*ubuntu*|*linuxmint*|*pop*|*elementary*|*zorin*|*kali*|*raspbian*|*mx*) W7_DISTRO=debian; W7_PKG=apt ;;
        *fedora*|*rhel*|*centos*|*rocky*|*alma*|*nobara*) W7_DISTRO=fedora; W7_PKG=dnf ;;
        *arch*|*manjaro*|*endeavouros*|*garuda*|*artix*|*cachyos*) W7_DISTRO=arch; W7_PKG=pacman ;;
        *suse*|*opensuse*) W7_DISTRO=suse; W7_PKG=zypper ;;
        *void*) W7_DISTRO=void; W7_PKG=xbps ;;
        *alpine*) W7_DISTRO=alpine; W7_PKG=apk ;;
        *gentoo*) W7_DISTRO=gentoo; W7_PKG=emerge ;;
    esac
    if [ "$W7_DISTRO" = unknown ]; then
        w7_have apt-get && { W7_DISTRO=debian; W7_PKG=apt; }
        w7_have dnf && { W7_DISTRO=fedora; W7_PKG=dnf; }
        w7_have pacman && { W7_DISTRO=arch; W7_PKG=pacman; }
        w7_have zypper && { W7_DISTRO=suse; W7_PKG=zypper; }
    fi
    export W7_DISTRO W7_PKG W7_DISTRO_ID W7_DISTRO_NAME
}

# Als root ausführen (direkt oder per sudo/doas)
w7_root() {
    if [ "$(id -u)" -eq 0 ]; then "$@"
    elif w7_have sudo; then sudo "$@"
    elif w7_have doas; then doas "$@"
    else w7_die "Root-Rechte nötig (sudo/doas fehlt): $*"
    fi
}
w7_can_root() { [ "$(id -u)" -eq 0 ] || w7_have sudo || w7_have doas; }

# ---------------------------------------------------------------------------
# Pfade (abhängig vom Modus user/system)
# ---------------------------------------------------------------------------
w7_setup_paths() {
    W7_MODE="${W7_MODE:-user}"
    W7_SRC="${W7_SRC:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
    if [ "$W7_MODE" = system ]; then
        W7_DATADIR=/usr/local/share/thewindowslinux
        W7_THEMEDIR=/usr/share/themes
        W7_ICONDIR=/usr/share/icons
        W7_FONTDIR=/usr/local/share/fonts/thewindowslinux
        W7_APPDIR=/usr/local/share/applications
        W7_BINDIR=/usr/local/bin
        W7_XDG_CONF=/etc/xdg
        W7_AUTOSTART=/etc/xdg/autostart
        W7_SKEL=/etc/skel
        W7_PROFILE=/etc/profile.d/thewindowslinux.sh
        W7_HOME_PLACEHOLDER='$HOME'
    else
        W7_DATADIR="${XDG_DATA_HOME:-$HOME/.local/share}/thewindowslinux"
        W7_THEMEDIR="$HOME/.themes"
        W7_ICONDIR="${XDG_DATA_HOME:-$HOME/.local/share}/icons"
        W7_FONTDIR="${XDG_DATA_HOME:-$HOME/.local/share}/fonts/thewindowslinux"
        W7_APPDIR="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
        W7_BINDIR="$HOME/.local/bin"
        W7_XDG_CONF="${XDG_CONFIG_HOME:-$HOME/.config}"
        W7_AUTOSTART="${XDG_CONFIG_HOME:-$HOME/.config}/autostart"
        W7_SKEL=""
        W7_PROFILE="$HOME/.profile"
        W7_HOME_PLACEHOLDER="$HOME"
    fi
    W7_STATE="${XDG_CONFIG_HOME:-$HOME/.config}/thewindowslinux"
    export W7_MODE W7_SRC W7_DATADIR W7_THEMEDIR W7_ICONDIR W7_FONTDIR W7_APPDIR W7_BINDIR W7_XDG_CONF W7_AUTOSTART W7_SKEL W7_PROFILE W7_STATE
}

# ---------------------------------------------------------------------------
# Stil (retro = Pixel-/Windows-95-Look, aero = Windows-7-Look)
# ---------------------------------------------------------------------------
w7_setup_style() {
    W7_STYLE="${W7_STYLE:-retro}"
    W7_STYLEDIR="$W7_SRC/theme/styles/$W7_STYLE"
    [ -d "$W7_STYLEDIR" ] || w7_die "Unbekannter Stil: $W7_STYLE (verfügbar: retro, aero)"
    case "$W7_STYLE" in
        retro)
            W7_GTKTHEME=Windows-Retro; W7_WMTHEME=Windows-Retro; W7_ICONTHEME=Windows-Retro
            W7_CURSOR_PREF="Windows-Retro DMZ-White Vanilla-DMZ Adwaita"; W7_CURSORSIZE=32
            W7_WALLPAPER_FILE=retro.png; W7_LOGIN_WALLPAPER_FILE=retro-login.png
            W7_AA=0; W7_HINTSTYLE=hintfull; W7_RGBA=none
            W7_PANELSIZE=28; W7_PANELICON=16; W7_DESKICON=32; W7_DESKFONTSIZE=9
            W7_STARTTITLE=Start; W7_SHOWSTARTTITLE=true; W7_STARTICON=win7-start
            W7_TASKGROUP=0; W7_CLOCKFORMAT="%H:%M"; W7_CLOCKLAYOUT=3
            W7_SHADOW=false; W7_TITLESHADOW=false; W7_MOVEOPACITY=100
            W7_MENUW=420; W7_MENUH=480
            W7_CMD_VERSION="4.10.2222"
            ;;
        aero)
            W7_GTKTHEME=Windows7-Aero; W7_WMTHEME=Windows7-Aero; W7_ICONTHEME=Windows7-Aero
            W7_CURSOR_PREF="DMZ-White Vanilla-DMZ Adwaita"; W7_CURSORSIZE=24
            W7_WALLPAPER_FILE=aero.png; W7_LOGIN_WALLPAPER_FILE=aero-login.png
            W7_AA=1; W7_HINTSTYLE=hintslight; W7_RGBA=rgb
            W7_PANELSIZE=40; W7_PANELICON=24; W7_DESKICON=48; W7_DESKFONTSIZE=9
            W7_STARTTITLE=Start; W7_SHOWSTARTTITLE=false; W7_STARTICON=win7-start
            W7_TASKGROUP=1; W7_CLOCKFORMAT="%H:%M%n%d.%m.%Y"; W7_CLOCKLAYOUT=1
            W7_SHADOW=true; W7_TITLESHADOW=frame; W7_MOVEOPACITY=90
            W7_MENUW=460; W7_MENUH=560
            W7_CMD_VERSION="6.1.7601"
            ;;
    esac
    export W7_STYLE W7_STYLEDIR W7_GTKTHEME W7_WMTHEME W7_ICONTHEME W7_CURSOR_PREF W7_CURSORSIZE W7_WALLPAPER_FILE W7_LOGIN_WALLPAPER_FILE
    export W7_AA W7_HINTSTYLE W7_RGBA W7_PANELSIZE W7_PANELICON W7_DESKICON W7_DESKFONTSIZE W7_STARTTITLE W7_SHOWSTARTTITLE W7_STARTICON
    export W7_TASKGROUP W7_CLOCKFORMAT W7_CLOCKLAYOUT W7_SHADOW W7_TITLESHADOW W7_MOVEOPACITY W7_MENUW W7_MENUH W7_CMD_VERSION
}

# Schreibender Dateibefehl – im Systemmodus mit root-Rechten
w7_do() { if [ "$W7_MODE" = system ]; then w7_root "$@"; else "$@"; fi; }

w7_mkdir() { w7_do mkdir -p "$@"; }

# Datei kopieren (Quelle → Ziel), Zielverzeichnis anlegen
w7_install() {  # w7_install [-m MODE] quelle ziel
    local mode=644
    if [ "$1" = -m ]; then mode="$2"; shift 2; fi
    w7_mkdir "$(dirname "$2")"
    w7_do install -m "$mode" "$1" "$2"
}

# Verzeichnis rekursiv kopieren (Symlinks bleiben erhalten – wichtig für Cursor-Aliase)
w7_copy_tree() {  # w7_copy_tree quelle zielverzeichnis
    w7_mkdir "$2"
    w7_do cp -a "$1"/. "$2"/
}

# Platzhalter in einer Datei ersetzen und ans Ziel schreiben
w7_sed_escape() { printf '%s' "$1" | sed -e 's/[&|\\]/\\&/g'; }
w7_render() {  # w7_render quelle ziel [mode]
    local src="$1" dst="$2" mode="${3:-644}" tmp
    tmp="$(mktemp)"
    sed -e "s|@WALLPAPER@|$(w7_sed_escape "$W7_WALLPAPER")|g" \
        -e "s|@GTKTHEME@|$(w7_sed_escape "$W7_GTKTHEME")|g" \
        -e "s|@WMTHEME@|$(w7_sed_escape "$W7_WMTHEME")|g" \
        -e "s|@ICONTHEME@|$(w7_sed_escape "$W7_ICONTHEME")|g" \
        -e "s|@UIFONTSIZE@|$(w7_sed_escape "$W7_UIFONTSIZE")|g" \
        -e "s|@UIFONT@|$(w7_sed_escape "$W7_UIFONT")|g" \
        -e "s|@MONOFONTSIZE@|$(w7_sed_escape "$W7_MONOFONTSIZE")|g" \
        -e "s|@MONOFONT@|$(w7_sed_escape "$W7_MONOFONT")|g" \
        -e "s|@TITLEFONT@|$(w7_sed_escape "$W7_TITLEFONT")|g" \
        -e "s|@CURSORSIZE@|$(w7_sed_escape "$W7_CURSORSIZE")|g" \
        -e "s|@CURSOR@|$(w7_sed_escape "$W7_CURSOR")|g" \
        -e "s|@AA@|$(w7_sed_escape "$W7_AA")|g" \
        -e "s|@HINTSTYLE@|$(w7_sed_escape "$W7_HINTSTYLE")|g" \
        -e "s|@RGBA@|$(w7_sed_escape "$W7_RGBA")|g" \
        -e "s|@PANELSIZE@|$(w7_sed_escape "$W7_PANELSIZE")|g" \
        -e "s|@PANELICON@|$(w7_sed_escape "$W7_PANELICON")|g" \
        -e "s|@DESKICON@|$(w7_sed_escape "$W7_DESKICON")|g" \
        -e "s|@DESKFONTSIZE@|$(w7_sed_escape "$W7_DESKFONTSIZE")|g" \
        -e "s|@STARTTITLE@|$(w7_sed_escape "$W7_STARTTITLE")|g" \
        -e "s|@SHOWSTARTTITLE@|$(w7_sed_escape "$W7_SHOWSTARTTITLE")|g" \
        -e "s|@STARTICON@|$(w7_sed_escape "$W7_STARTICON")|g" \
        -e "s|@TASKGROUP@|$(w7_sed_escape "$W7_TASKGROUP")|g" \
        -e "s|@CLOCKFORMAT@|$(w7_sed_escape "$W7_CLOCKFORMAT")|g" \
        -e "s|@CLOCKLAYOUT@|$(w7_sed_escape "$W7_CLOCKLAYOUT")|g" \
        -e "s|@SHADOW@|$(w7_sed_escape "$W7_SHADOW")|g" \
        -e "s|@TITLESHADOW@|$(w7_sed_escape "$W7_TITLESHADOW")|g" \
        -e "s|@MOVEOPACITY@|$(w7_sed_escape "$W7_MOVEOPACITY")|g" \
        -e "s|@MENUW@|$(w7_sed_escape "$W7_MENUW")|g" \
        -e "s|@MENUH@|$(w7_sed_escape "$W7_MENUH")|g" \
        -e "s|@CMD_LAUNCH@|$(w7_sed_escape "$W7_CMD_LAUNCH")|g" \
        -e "s|@CALC@|$(w7_sed_escape "$W7_CALC")|g" \
        -e "s|@EDITOR_APP@|$(w7_sed_escape "$W7_EDITOR_APP")|g" \
        -e "s|@DATADIR@|$(w7_sed_escape "$W7_DATADIR")|g" \
        -e "s|@HOME@|$(w7_sed_escape "$W7_HOME_PLACEHOLDER")|g" \
        "$src" > "$tmp"
    if grep -q '@[A-Z_]*@' "$tmp"; then
        w7_warn "Unersetzter Platzhalter in $(basename "$src"): $(grep -o '@[A-Z_]*@' "$tmp" | sort -u | tr '\n' ' ')"
    fi
    w7_install -m "$mode" "$tmp" "$dst"
    rm -f "$tmp"
}

# Vorhandene Datei sichern (einmalig, mit Zeitstempel)
w7_backup() {
    local f="$1"
    [ -e "$f" ] || return 0
    local bdir="$W7_STATE/backup-$W7_RUN_ID"
    mkdir -p "$bdir"
    local rel="${f#/}"
    mkdir -p "$bdir/$(dirname "$rel")"
    cp -a "$f" "$bdir/$rel" 2>/dev/null || w7_do cp -a "$f" "$bdir/$rel"
}
w7_track() { mkdir -p "$W7_STATE"; printf '%s\n' "$1" >> "$W7_STATE/installed-files.txt"; }

# ---------------------------------------------------------------------------
# Erkennung von Schriften / Programmen
# ---------------------------------------------------------------------------
w7_font_available() { w7_have fc-list && [ -n "$(fc-list 2>/dev/null | grep -i ":[^:]*$1" | head -1)" ]; }
w7_pick_fonts() {
    if [ "$W7_STYLE" = retro ]; then
        # Pixel-Schriften: Terminus (OTB-Bitmap) → Unifont → ohne Antialiasing gerenderte Vektorschrift
        W7_UIFONT="Sans"; W7_UIFONTSIZE=8
        if w7_font_available "Terminus"; then W7_UIFONT="Terminus"; W7_UIFONTSIZE=9
        else
            for f in "Liberation Sans" "DejaVu Sans" "Noto Sans"; do
                w7_font_available "$f" && { W7_UIFONT="$f"; W7_UIFONTSIZE=8; break; }
            done
        fi
        W7_MONOFONT="Monospace"; W7_MONOFONTSIZE=10
        if w7_font_available "Terminus"; then W7_MONOFONT="Terminus"; W7_MONOFONTSIZE=12
        elif w7_font_available "Unifont"; then W7_MONOFONT="Unifont"; W7_MONOFONTSIZE=12
        else
            for f in "Liberation Mono" "DejaVu Sans Mono" "Noto Sans Mono"; do
                w7_font_available "$f" && { W7_MONOFONT="$f"; W7_MONOFONTSIZE=10; break; }
            done
        fi
        W7_TITLEFONT="$W7_UIFONT Bold $W7_UIFONTSIZE"
    else
        W7_UIFONT="Sans"; W7_UIFONTSIZE=9
        for f in "Selawik" "Noto Sans" "DejaVu Sans" "Liberation Sans" "Cantarell"; do
            w7_font_available "$f" && { W7_UIFONT="$f"; break; }
        done
        W7_MONOFONT="Monospace"; W7_MONOFONTSIZE=10
        for f in "Cascadia Mono" "Cascadia Code" "Inconsolata" "DejaVu Sans Mono" "Noto Sans Mono" "Liberation Mono"; do
            w7_font_available "$f" && { W7_MONOFONT="$f"; break; }
        done
        W7_TITLEFONT="$W7_UIFONT $W7_UIFONTSIZE"
    fi
    export W7_UIFONT W7_UIFONTSIZE W7_MONOFONT W7_MONOFONTSIZE W7_TITLEFONT
}
w7_pick_cursor() {
    W7_CURSOR="default"
    local c d
    for c in $W7_CURSOR_PREF; do
        for d in "$W7_ICONDIR" /usr/share/icons "$HOME/.icons" "$HOME/.local/share/icons"; do
            [ -d "$d/$c/cursors" ] && { W7_CURSOR="$c"; break 2; }
        done
    done
    export W7_CURSOR
}
w7_first_cmd() { local c; for c in "$@"; do w7_have "$c" && { printf '%s' "$c"; return 0; }; done; printf '%s' "$1"; }
w7_pick_apps() {
    W7_CALC="$(w7_first_cmd galculator gnome-calculator mate-calc qalculate-gtk kcalc xcalc)"
    W7_EDITOR_APP="$(w7_first_cmd mousepad gedit pluma xed leafpad featherpad kate)"
    export W7_CALC W7_EDITOR_APP
}

# Läuft gerade eine XFCE-Sitzung dieses Benutzers?
w7_xfce_running() { [ -n "${DISPLAY:-}" ] && pgrep -u "$(id -u)" -x xfce4-session >/dev/null 2>&1; }
