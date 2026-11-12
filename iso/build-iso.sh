#!/usr/bin/env bash
# ============================================================================
#  TheWindowsLinux – Live-ISO bauen (Debian live-build)
#
#  Erzeugt ein bootfähiges Live-System (mit Calamares-Installer, falls
#  verfügbar), in dem das Overlay bereits systemweit installiert ist.
#
#    sudo ./iso/build-iso.sh [--style retro|aero] [--suite bookworm|trixie] [--arch amd64]
#
#  Voraussetzungen: Debian/Ubuntu-Host, Pakete live-build, debootstrap, xorriso,
#  squashfs-tools, ~10 GB Platz, Internet. Dauer: 20-60 Minuten.
#  Das Ergebnis liegt in iso/build/live-image-<arch>.hybrid.iso
#
#  Das Live-System meldet sich als "user" (Passwort "live") an – Standard von Debian live-config, bei einer
#  Installation sofort ändern.
#
#  HINWEIS: Dieser Build wurde in der Entwicklungsumgebung nur auf Syntax geprüft,
#  nicht vollständig durchlaufen (live-build benötigt root, loop-Devices und viel Zeit).
# ============================================================================
set -euo pipefail

STYLE=retro
SUITE=bookworm
ARCH=amd64
while [ $# -gt 0 ]; do
    case "$1" in
        --style) STYLE="$2"; shift ;;
        --suite) SUITE="$2"; shift ;;
        --arch) ARCH="$2"; shift ;;
        -h|--help) sed -n '2,16p' "$0"; exit 0 ;;
        *) echo "Unbekannte Option: $1" >&2; exit 2 ;;
    esac
    shift
done

[ "$(id -u)" -eq 0 ] || { echo "Bitte als root ausführen (sudo)." >&2; exit 1; }
for t in lb debootstrap xorriso mksquashfs; do
    command -v "$t" >/dev/null 2>&1 || { echo "Fehlt: $t  (apt install live-build debootstrap xorriso squashfs-tools)" >&2; exit 1; }
done

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="$SRC/iso/build"
rm -rf "$BUILD"
mkdir -p "$BUILD"
cd "$BUILD"

echo "[iso] live-build konfigurieren ($SUITE/$ARCH, Stil $STYLE)"
lb config \
    --distribution "$SUITE" \
    --architectures "$ARCH" \
    --archive-areas "main contrib non-free non-free-firmware" \
    --debian-installer none \
    --bootappend-live "boot=live components locales=de_DE.UTF-8 keyboard-layouts=de hostname=thewindowslinux username=user" \
    --iso-application "TheWindowsLinux" \
    --iso-volume "TheWindowsLinux" \
    --iso-publisher "TheWindowsLinux" \
    --memtest none \
    --apt-recommends false

# Pakete
mkdir -p config/package-lists
cat > config/package-lists/thewindowslinux.list.chroot <<'EOF'
xfce4 xfce4-goodies xfce4-whiskermenu-plugin xfce4-terminal thunar thunar-archive-plugin thunar-volman
mousepad ristretto parole galculator catfish file-roller
lightdm lightdm-gtk-greeter xorg xserver-xorg-video-all xserver-xorg-input-all
network-manager network-manager-gnome policykit-1-gnome
pulseaudio pavucontrol pulseaudio-utils
gvfs gvfs-backends gvfs-fuse xdg-utils xdg-user-dirs xdg-user-dirs-gtk
dmz-cursor-theme elementary-xfce-icon-theme adwaita-icon-theme
fonts-noto-core fonts-dejavu-core fonts-liberation fonts-terminus-otb fonts-unifont fonts-cascadia-code
firefox-esr libreoffice-writer libreoffice-calc
libnotify-bin tree psmisc procps iproute2 lsb-release curl unzip sudo
firmware-linux-free firmware-misc-nonfree firmware-iwlwifi firmware-realtek firmware-atheros
live-boot live-config live-config-systemd
calamares-settings-debian calamares
EOF

# Projektdateien ins Chroot kopieren
mkdir -p config/includes.chroot/opt/thewindowslinux
# per tar kopieren: Eigentümer des Quellordners wird NICHT übernommen (sonst gehörten Systemdateien dem Klon-Benutzer)
tar -C "$SRC" --exclude=.git --exclude=iso/build --exclude=__pycache__ -cf - \
    install.sh uninstall.sh lib scripts cmd theme tools README.md LICENSE | tar -C config/includes.chroot/opt/thewindowslinux --no-same-owner -xf -
chmod -R go-w config/includes.chroot/opt/thewindowslinux

# Hook: Overlay systemweit installieren
mkdir -p config/hooks/live
cat > config/hooks/live/9000-thewindowslinux.hook.chroot <<EOF
#!/bin/sh
set -e
chown -R root:root /opt/thewindowslinux
chmod -R go-w /opt/thewindowslinux
cd /opt/thewindowslinux
W7_ALLOW_ROOT_USER=1 bash ./install.sh --system --no-packages --with-login --cmd-everywhere --style $STYLE --yes
# Live-Benutzer: Erstanmeldung-Skript läuft automatisch (Autostart)
echo "TheWindowsLinux Live" > /etc/issue.thewindowslinux
EOF
chmod +x config/hooks/live/9000-thewindowslinux.hook.chroot

# Bootmenü-Hintergrund
mkdir -p config/bootloaders
if [ -d /usr/share/live/build/bootloaders/isolinux ]; then
    cp -a /usr/share/live/build/bootloaders/isolinux config/bootloaders/
    python3 - "$SRC/theme/styles/$STYLE/wallpapers" config/bootloaders/isolinux/splash.png <<'PY' || true
import sys, os
from PIL import Image
src, dst = sys.argv[1], sys.argv[2]
for n in ("retro-480x270.png", "retro-login.png", "aero-login.png"):
    p = os.path.join(src, n)
    if os.path.exists(p):
        Image.open(p).convert("RGB").resize((640, 480)).save(dst); break
PY
fi

echo "[iso] Build starten – das dauert ..."
lb build 2>&1 | tee build.log
ls -lh "$BUILD"/live-image-*.hybrid.iso 2>/dev/null && echo "[iso] fertig: $BUILD/live-image-$ARCH.hybrid.iso"
