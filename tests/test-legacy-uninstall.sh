#!/usr/bin/env bash
# Deinstallation einer Installation der ALTEN Version (aus der Git-Historie) mit dem NEUEN Skript.
# Aufruf: bash tests/test-legacy-uninstall.sh [<Commit>]   (Standard: 88b2e9f = Version 1.1)
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REV="${1:-88b2e9f}"
T="$(mktemp -d /tmp/w7leg-XXXXXX)"
export HOME="$T/home" LANG=de_DE.UTF-8 W7_ALLOW_ROOT_USER=1
unset XDG_CONFIG_HOME XDG_DATA_HOME
mkdir -p "$HOME" "$T/old"
git -C "$ROOT" archive "$REV" | tar -x -C "$T/old" || { echo "Commit $REV nicht gefunden"; exit 2; }
pass=0; fail=0
check() { if ( eval "$2" ); then pass=$((pass + 1)); printf '  ok    %s\n' "$1"; else fail=$((fail + 1)); printf '  FAIL  %s\n' "$1"; fi; }
snap() { (cd "$HOME" && find . -mindepth 1 \( -type f -o -type l -o -type d \) -printf '%y %m %p\n' | LC_ALL=C sort; find . -type f -exec sha256sum {} + 2>/dev/null | LC_ALL=C sort -k2); }

cp /etc/skel/.bashrc "$HOME/.bashrc" 2>/dev/null || echo "# bashrc" > "$HOME/.bashrc"
printf '# ~/.profile\nexport EDITOR=nano\n' > "$HOME/.profile"
mkdir -p "$HOME/.config/xfce4/xfconf/xfce-perchannel-xml" "$HOME/.config/xfce4/panel" "$HOME/Desktop" "$HOME/.local/bin"
echo '<channel name="xsettings" version="1.0"/>' > "$HOME/.config/xfce4/xfconf/xfce-perchannel-xml/xsettings.xml"
echo 'favorites=meine-app.desktop' > "$HOME/.config/xfce4/panel/whiskermenu-1.rc"
snap > "$T/before.txt"
run_scenario() {  # run_scenario NAME UPGRADE(0|1)
    local name="$1" upgrade="$2"
    echo "== $name: alte Version ($REV) installieren =="
    ( cd "$T/old" && ./install.sh --no-packages --no-fonts --yes --cmd-everywhere > "$T/old-install.log" 2>&1 ) || true
    check "alte Installation hat Dateien angelegt" '[ -d "$HOME/.themes" ] && grep -q TheWindowsLinux "$HOME/.profile"'
    if [ "$upgrade" = 1 ]; then
        echo "== $name: NEU darüber installieren (Upgrade) =="
        "$ROOT/install.sh" --no-packages --yes --style retro > "$T/upgrade.log" 2>&1
        check "Upgrade-Installation endet ohne Fehler" 'grep -q "Fertig" "$T/upgrade.log"'
        check "Upgrade: Originale liegen im neuen Sicherungsordner, nicht die alten Overlay-Dateien (die .bashrc der alten Version war schon verändert und wird ohnehin nicht daraus wiederhergestellt)" 'grep -q "favorites=meine-app" "$HOME/.config/thewindowslinux/original/${HOME#/}/.config/xfce4/panel/whiskermenu-1.rc" && ! grep -rqs --exclude=.bashrc "TheWindowsLinux" "$HOME/.config/thewindowslinux/original/"'
    fi
    echo "== $name: neu deinstallieren =="
    "$ROOT/uninstall.sh" --yes > "$T/uninstall.log" 2>&1
    check "Deinstallation endet ohne Fehler" 'grep -q "wurde entfernt" "$T/uninstall.log"'
    snap > "$T/after.txt"
    if diff -u "$T/before.txt" "$T/after.txt" > "$T/diff.txt"; then check "Zustand == Ausgangszustand" 'true'
    else check "Zustand == Ausgangszustand" 'false'; head -25 "$T/diff.txt"; fi
}
run_scenario "A) alt installiert, neu deinstalliert" 0
run_scenario "B) alt installiert, neu darüber installiert, neu deinstalliert" 1
echo; echo "$pass bestanden, $fail fehlgeschlagen"
rm -rf "$T"
[ $fail -eq 0 ]
