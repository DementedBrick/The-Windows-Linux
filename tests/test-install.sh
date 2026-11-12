#!/usr/bin/env bash
# Installations-Roundtrip im Benutzermodus mit einem Testkonto:
#   Ausgangszustand (mit eigenen Konfigurationsdateien!) → install (retro) → install (aero) → uninstall
#   → der Zustand muss dem Ausgangszustand entsprechen. Prüft außerdem Idempotenz, XML-/Desktop-Dateien und
#   dass .bashrc/.profile des Benutzers nur an markierten Stellen verändert werden.
# Aufruf: bash tests/test-install.sh [--keep]
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
T="$(mktemp -d /tmp/w7inst-XXXXXX)"
export HOME="$T/home"
unset XDG_CONFIG_HOME XDG_DATA_HOME
export LANG=de_DE.UTF-8 W7_ALLOW_ROOT_USER=1
mkdir -p "$HOME"
pass=0; fail=0
check() { if ( eval "$2" ); then pass=$((pass + 1)); printf '  ok    %s\n' "$1"; else fail=$((fail + 1)); printf '  FAIL  %s\n' "$1"; fi; }
snap() { (cd "$HOME" && find . -mindepth 1 \( -type f -o -type l -o -type d \) -printf '%y %m %p\n' | LC_ALL=C sort; \
          find . -type f -exec sha256sum {} + 2>/dev/null | LC_ALL=C sort -k2); }

# ---- Ausgangszustand: ein "gelebtes" Benutzerkonto -------------------------------------------------
cp /etc/skel/.bashrc "$HOME/.bashrc" 2>/dev/null || echo "# bashrc" > "$HOME/.bashrc"
printf '\n# meine eigene Zeile\ncase ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) export PATH="$HOME/.local/bin:$PATH" ;; esac\nalias ll="ls -l"\n' >> "$HOME/.bashrc"
printf '# ~/.profile\nexport EDITOR=nano\n' > "$HOME/.profile"
mkdir -p "$HOME/.config/xfce4/xfconf/xfce-perchannel-xml" "$HOME/.config/xfce4/panel" "$HOME/.config/Thunar" "$HOME/.local/bin" "$HOME/Desktop" "$HOME/.config/gtk-3.0"
echo '<?xml version="1.0"?><channel name="xsettings" version="1.0"><property name="Net" type="empty"><property name="ThemeName" type="string" value="MeinTheme"/></property></channel>' > "$HOME/.config/xfce4/xfconf/xfce-perchannel-xml/xsettings.xml"
echo 'favorites=meine-app.desktop' > "$HOME/.config/xfce4/panel/whiskermenu-1.rc"
echo '<actions/>' > "$HOME/.config/Thunar/uca.xml"
echo 'file:///home/x/Projekte Projekte' > "$HOME/.config/gtk-3.0/bookmarks"
printf '#!/bin/sh\necho mein werkzeug\n' > "$HOME/.local/bin/mytool"; chmod 755 "$HOME/.local/bin/mytool"
chmod 600 "$HOME/.profile"
snap > "$T/before.txt"
cp "$HOME/.bashrc" "$T/bashrc.orig"
echo "Ausgangszustand: $(wc -l < "$T/before.txt") Einträge"

# ---- Installation 1 (retro) --------------------------------------------------------------------------
echo "== install --style retro =="
"$ROOT/install.sh" --no-packages --yes --style retro > "$T/install1.log" 2>&1
check "Installation (retro) endet ohne Fehler" '[ $? -eq 0 ] && grep -q "Fertig" "$T/install1.log"'
check "Installer meldet keine unersetzten Platzhalter" '! grep -q "Unersetzter Platzhalter" "$T/install1.log"'
check ".bashrc des Benutzers bleibt unverändert (kein --cmd-everywhere)" 'cmp -s "$HOME/.bashrc" "$T/bashrc.orig"'
check ".profile: markierter Block genau einmal" '[ "$(grep -c ">>> TheWindowsLinux >>>" "$HOME/.profile")" = 1 ] && grep -q "export EDITOR=nano" "$HOME/.profile"'
check ".profile behält Rechte 600" '[ "$(stat -c %a "$HOME/.profile")" = 600 ]'
check "eigene xsettings.xml wurde gesichert" '[ -f "$HOME/.config/thewindowslinux/original/${HOME#/}/.config/xfce4/xfconf/xfce-perchannel-xml/xsettings.xml" ]'
check "alle gerenderten XML-Dateien sind gültig" 'for f in "$HOME"/.config/xfce4/xfconf/xfce-perchannel-xml/*.xml "$HOME/.config/Thunar/uca.xml"; do python3 -c "import sys,xml.dom.minidom as m; m.parse(sys.argv[1])" "$f" || exit 1; done'
check "Desktop-Dateien bestehen desktop-file-validate" 'command -v desktop-file-validate >/dev/null || exit 0; for f in "$HOME"/.local/share/applications/win7-*.desktop "$HOME"/.config/autostart/win7-*.desktop; do desktop-file-validate "$f" 2>&1 | grep -E "error" && exit 1; done; exit 0'
check "Themes/Icons installiert" '[ -d "$HOME/.themes/Windows-Retro/gtk-3.0" ] && [ -d "$HOME/.local/share/icons/Windows-Retro/16x16" ] && [ -L "$HOME/.local/share/icons/Windows-Retro/cursors/default" ]'
check "eigene ~/.local/bin/mytool unberührt" '[ "$(cat "$HOME/.local/bin/mytool" | sed -n 2p)" = "echo mein werkzeug" ]'
check "win7-doctor ist verlinkt und ausführbar" '[ -x "$HOME/.local/bin/win7-doctor" ]'
snap > "$T/after1.txt"

# ---- Installation 2 (aero, über die erste) ----------------------------------------------------------
echo "== install --style aero (über die erste) =="
"$ROOT/install.sh" --no-packages --yes --style aero --cmd-everywhere --scale 150 > "$T/install2.log" 2>&1
check "zweite Installation (aero) endet ohne Fehler" 'grep -q "Fertig" "$T/install2.log"'
check ".profile: Block weiterhin genau einmal" '[ "$(grep -c ">>> TheWindowsLinux >>>" "$HOME/.profile")" = 1 ]'
check ".bashrc: genau eine markierte Overlay-Zeile" '[ "$(grep -c "TheWindowsLinux cmd-Overlay" "$HOME/.bashrc")" = 1 ]'
check "Original von xsettings.xml wurde NICHT durch unsere erste Fassung überschrieben" 'grep -q MeinTheme "$HOME/.config/thewindowslinux/original/${HOME#/}/.config/xfce4/xfconf/xfce-perchannel-xml/xsettings.xml"'
check "Größe 150 % gespeichert, doppelt große Fensterrahmen installiert" '[ "$(cat "$HOME/.config/thewindowslinux/scale")" = 150 ] && [ -f "$HOME/.themes/Windows7-Aero-2x/xfwm4/themerc" ] && [ -x "$HOME/.local/bin/win7-scale" ]'
check "Stil aero aktiv" 'grep -q "Windows7-Aero" "$HOME/.config/xfce4/xfconf/xfce-perchannel-xml/xsettings.xml"'

# ---- Deinstallation ---------------------------------------------------------------------------------------
echo "== uninstall =="
"$ROOT/uninstall.sh" --yes > "$T/uninstall.log" 2>&1
check "Deinstallation endet ohne Fehler" 'grep -q "wurde entfernt" "$T/uninstall.log"'
snap > "$T/after.txt"
if diff -u "$T/before.txt" "$T/after.txt" > "$T/diff.txt"; then
    check "Zustand nach Deinstallation == Ausgangszustand (Dateien, Ordner, Rechte, Inhalte)" 'true'
else
    check "Zustand nach Deinstallation == Ausgangszustand (Dateien, Ordner, Rechte, Inhalte)" 'false'
    echo "--- Unterschiede (max. 30 Zeilen) ---"; head -30 "$T/diff.txt"
fi
check "eigene xsettings.xml ist wieder da" 'grep -q MeinTheme "$HOME/.config/xfce4/xfconf/xfce-perchannel-xml/xsettings.xml"'
check "eigene whiskermenu-1.rc ist wieder da" 'grep -q meine-app "$HOME/.config/xfce4/panel/whiskermenu-1.rc"'
check ".bashrc ist wieder byte-identisch" 'cmp -s "$HOME/.bashrc" "$T/bashrc.orig"'
check ".profile ohne Overlay-Block, eigene Zeile erhalten" '! grep -q TheWindowsLinux "$HOME/.profile" && grep -q "export EDITOR=nano" "$HOME/.profile"'

echo
echo "$pass bestanden, $fail fehlgeschlagen"
[ "${1:-}" = --keep ] && echo "Testordner: $T" || rm -rf "$T"
[ $fail -eq 0 ]
