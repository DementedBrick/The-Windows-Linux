#!/usr/bin/env bash
# ============================================================================
#  TheWindowsLinux × Kali – bootfähiges Kali-Live-ISO mit dem Windows-Overlay
#
#  Baut mit der OFFIZIELLEN Kali-Baukonfiguration (gitlab.com/kalilinux/build-scripts/live-build-config)
#  ein Kali-Live-/Installer-Image und spielt das Overlay als zusätzliche Dateien + Hook ein.
#  Ergebnis: Kali mit allen Kali-Paketen (kali-linux-default usw.) im Retro- oder Aero-Look.
#
#    sudo ./iso/build-kali-iso.sh [Optionen]
#
#    --variant NAME    Kali-Variante: xfce (Standard), xfce-large, xfce-everything, xfce-light, default, ...
#                      (nur Xfce-Varianten bekommen das Overlay sinnvoll; andere Desktops werden nicht umgestellt)
#    --style retro|aero    Aussehen (Standard: retro)
#    --branch NAME     kali-rolling (Standard), kali-last-snapshot, kali-dev
#    --arch NAME       amd64 (Standard) oder arm64
#    --prepare-only    nur vorbereiten (klonen, Overlay einspielen), nicht bauen
#    --no-container    direkt auf dem Host bauen (nur sinnvoll auf Kali); sonst Docker/Podman
#
#  Voraussetzungen: root (sudo), git, und entweder Docker/Podman (empfohlen, funktioniert auf jeder
#  Distribution) oder ein Kali-Host mit live-build. Rund 40 GB freier Platz, mehrere Stunden Zeit, Internet.
#  Das Ergebnis liegt in iso/kali-build/live-build-config/output/ (bzw. images/).
#
#  STATUS: Die Vorbereitung (Klonen, Einspielen, Hook, Paketliste) ist getestet. Der eigentliche
#  Image-Bau wurde in der Entwicklungsumgebung NICHT ausgeführt (braucht Docker/Root, ~40 GB, Stunden).
#  Kali selbst: Anmeldung im Live-System kali/kali – bei einer Installation sofort ändern.
# ============================================================================
set -euo pipefail

VARIANT=xfce; STYLE=retro; BRANCH=kali-rolling; ARCH=amd64; PREPARE_ONLY=0; USE_CONTAINER=1
while [ $# -gt 0 ]; do
    case "$1" in
        --variant) VARIANT="${2:?}"; shift ;;
        --style) STYLE="${2:?}"; shift ;;
        --branch) BRANCH="${2:?}"; shift ;;
        --arch) ARCH="${2:?}"; shift ;;
        --prepare-only) PREPARE_ONLY=1 ;;
        --no-container) USE_CONTAINER=0 ;;
        -h|--help) sed -n '2,28p' "$0"; exit 0 ;;
        *) echo "Unbekannte Option: $1" >&2; exit 2 ;;
    esac
    shift
done
[[ "$VARIANT" =~ ^[a-z0-9-]+$ && "$BRANCH" =~ ^[a-z0-9-]+$ && "$ARCH" =~ ^[a-z0-9]+$ ]] || { echo "Ungültige Angabe." >&2; exit 2; }
case "$STYLE" in retro|aero) ;; *) echo "--style muss retro oder aero sein" >&2; exit 2 ;; esac
case "$VARIANT" in xfce*|default) ;; *) echo "Hinweis: Das Overlay stellt nur Xfce um – Variante »$VARIANT« bleibt optisch unverändert." >&2 ;; esac

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="${W7_KALI_WORK:-$SRC/iso/kali-build}"
REPO="$WORK/live-build-config"
URL="https://gitlab.com/kalilinux/build-scripts/live-build-config.git"

if [ "$PREPARE_ONLY" -eq 0 ] && [ "$(id -u)" -ne 0 ]; then echo "Bitte als root ausführen (sudo)." >&2; exit 1; fi
command -v git >/dev/null 2>&1 || { echo "git fehlt." >&2; exit 1; }

mkdir -p "$WORK"
if [ -d "$REPO/.git" ]; then
    echo "[kali] aktualisiere Baukonfiguration ..."
    git -C "$REPO" pull --ff-only --quiet || echo "[kali] Hinweis: Aktualisierung nicht möglich, nutze vorhandenen Stand."
else
    echo "[kali] klone offizielle Kali-Baukonfiguration ..."
    git clone --depth 1 --quiet "$URL" "$REPO"
fi
CFG="$REPO/kali-config"
[ -d "$CFG/common" ] && [ -d "$CFG/variant-$VARIANT" ] || { echo "Variante »$VARIANT« gibt es nicht. Verfügbar: $(ls "$CFG" | sed -n 's/^variant-//p' | tr '\n' ' ')" >&2; exit 1; }

# --- 1. Overlay als Dateien ins Image (ohne .git/Bauordner; Eigentümer = der ausführende Benutzer, im Hook auf root) ---
DEST="$CFG/common/includes.chroot/opt/thewindowslinux"
[ -n "$DEST" ] && rm -rf -- "$DEST"
mkdir -p "$DEST"
tar -C "$SRC" --exclude=.git --exclude=iso/build --exclude=iso/kali-build --exclude=__pycache__ -cf - \
    install.sh uninstall.sh lib scripts cmd theme LICENSE README.md | tar -C "$DEST" --no-same-owner -xf -
chmod -R go-w "$DEST"
echo "[kali] Overlay eingespielt: $DEST"

# --- 2. Zusätzliche Pakete (zusätzlich zu den Kali-Metapaketen der Variante) ---
mkdir -p "$CFG/common/package-lists"
cat > "$CFG/common/package-lists/thewindowslinux.list.chroot" <<'EOF'
## TheWindowsLinux: Pakete, die das Overlay braucht (Kali bringt Xfce bereits mit)
xfce4-whiskermenu-plugin
xfce4-screensaver
xfce4-terminal
xfce4-taskmanager
thunar
mousepad
galculator
dmz-cursor-theme
elementary-xfce-icon-theme
fonts-terminus-otb
fonts-unifont
xfonts-terminus
libnotify-bin
gnome-keyring
pavucontrol
desktop-file-utils
EOF

# --- 3. Hook: Overlay im Chroot systemweit installieren (läuft nach der Paketinstallation) ---
mkdir -p "$CFG/common/hooks/live"
cat > "$CFG/common/hooks/live/9000-thewindowslinux.chroot" <<EOF
#!/bin/sh
# TheWindowsLinux: Overlay systemweit installieren; /etc/skel erhält die Konfiguration für den Live-Benutzer.
set -e
chown -R root:root /opt/thewindowslinux
chmod -R go-w /opt/thewindowslinux
cd /opt/thewindowslinux
W7_ALLOW_ROOT_USER=1 bash ./install.sh --system --no-packages --yes --style $STYLE --with-login
EOF
chmod 755 "$CFG/common/hooks/live/9000-thewindowslinux.chroot"
echo "[kali] Hook und Paketliste angelegt (Stil $STYLE, Variante $VARIANT)."

if [ "$PREPARE_ONLY" -eq 1 ]; then
    echo "[kali] --prepare-only: fertig vorbereitet in $REPO"
    exit 0
fi

# --- 4. Bauen ---
cd "$REPO"
ARGS=(--variant "$VARIANT" --branch "$BRANCH" --arch "$ARCH" -H thewindowslinux -x "thewindowslinux-$(date +%Y.%m)")
if [ "$USE_CONTAINER" -eq 1 ] && { command -v docker >/dev/null 2>&1 || command -v podman >/dev/null 2>&1; }; then
    echo "[kali] baue im Container (Kali-Bauumgebung) – das dauert mehrere Stunden ..."
    exec ./build-in-container.sh "${ARGS[@]}"
elif [ "$USE_CONTAINER" -eq 0 ]; then
    echo "[kali] baue direkt auf dem Host ..."
    exec ./build.sh "${ARGS[@]}"
else
    echo "Weder Docker noch Podman gefunden. Installiere eines davon (z. B. 'sudo apt install podman') oder baue auf einem Kali-Host mit --no-container." >&2
    exit 1
fi
