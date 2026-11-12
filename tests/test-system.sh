#!/usr/bin/env bash
# Systemmodus-Test (braucht root; ändert das System – nur in einem Wegwerf-Container/VM ausführen!):
#   * Quellordner gehört einem FREMDEN Benutzer und ist gruppenbeschreibbar → nach der Installation darf
#     keine Systemdatei ihm gehören oder für Gruppe/Andere beschreibbar sein
#   * Neuer Benutzer (aus /etc/skel) bekommt den Desktop mit dem Overlay
#   * uninstall --system stellt den Systemzustand wieder her
# Aufruf: sudo bash tests/test-system.sh
set -uo pipefail
[ "$(id -u)" -eq 0 ] || { echo "Bitte als root ausführen."; exit 2; }
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
T="$(mktemp -d /tmp/w7sys-XXXXXX)"
pass=0; fail=0
check() { if ( eval "$2" ); then pass=$((pass + 1)); printf '  ok    %s\n' "$1"; else fail=$((fail + 1)); printf '  FAIL  %s\n' "$1"; fi; }
DIRS="/etc/xdg /etc/skel /etc/profile.d /etc/bash.bashrc /usr/local /usr/share/themes /usr/share/icons /usr/share/sounds /var/lib/thewindowslinux"
snap() { find $DIRS -xdev \( -type f -o -type l -o -type d \) ! -name 'icon-theme.cache' ! -name 'mimeinfo.cache' -printf '%y %m %u:%g %p\n' 2>/dev/null | LC_ALL=C sort
         find /etc/xdg /etc/skel /etc/profile.d /etc/bash.bashrc /usr/local -xdev -type f -exec sha256sum {} + 2>/dev/null | LC_ALL=C sort -k2; }

# Quellkopie mit fremdem Eigentümer und Gruppen-Schreibrecht (so entsteht es bei "git clone" mit umask 002)
cp -a "$ROOT" "$T/src"; rm -rf "$T/src/.git" "$T/src/iso/build"
chown -R 1234:1234 "$T/src"; chmod -R g+w "$T/src"
snap > "$T/before.txt"
echo "== install --system (Quelle gehört UID 1234, gruppenbeschreibbar) =="
"$T/src/install.sh" --system --no-packages --yes --style retro --cmd-everywhere > "$T/install.log" 2>&1
check "Installation endet ohne Fehler" 'grep -q "Fertig" "$T/install.log"'
check "keine unersetzten Platzhalter" '! grep -q "Unersetzter Platzhalter" "$T/install.log"'
# shellcheck disable=SC2034   # OURS wird in eval-Prüfungen verwendet
OURS="/usr/local/share/thewindowslinux /usr/share/themes/Windows-Retro /usr/share/icons/Windows-Retro /usr/share/sounds/windows7"
check "keine Systemdatei gehört dem fremden Benutzer (UID 1234)" '[ -z "$(find $OURS /etc/xdg/xfce4 /etc/skel/.config /usr/local/bin -xdev \( -uid 1234 -o -gid 1234 \) 2>/dev/null | head -1)" ]'
check "nichts ist für Gruppe/Andere beschreibbar" '[ -z "$(find $OURS /etc/xdg/xfce4 /etc/skel/.config /etc/profile.d/thewindowslinux.sh -xdev ! -type l -perm /022 2>/dev/null | head -1)" ]'
check "Skripte gehören root und sind ausführbar" '[ "$(stat -c %U:%a /usr/local/share/thewindowslinux/bin/cmd)" = root:755 ]'
check "Cursor-Symlinks bleiben erhalten" '[ -L /usr/share/icons/Windows-Retro/cursors/default ]'
check "/etc/skel erhält die XFCE-Konfiguration für neue Benutzer" '[ -f /etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml ]'
check "systemweit: eigene Kanäle in /etc/xdg, Distributionsdateien (xsettings, session, shortcuts) unberührt" 'grep -q Windows-Retro /etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfwm4.xml && ! grep -q Windows-Retro /etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xsettings.xml && grep -q Failsafe /etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfce4-session.xml'
check "/etc/bash.bashrc: genau eine Overlay-Zeile" '[ "$(grep -c "TheWindowsLinux cmd-Overlay" /etc/bash.bashrc /etc/bashrc 2>/dev/null | awk -F: "{s+=\$2} END {print s}")" = 1 ]'
check "Installationsliste liegt root-eigen unter /var/lib" '[ "$(stat -c %U /var/lib/thewindowslinux/installed-files.txt)" = root ]'
check "Overlay-Angriffsfläche: keine SUID/SGID-Dateien, keine Capabilities, keine Systemdienste" '[ -z "$(find $OURS -xdev \( -perm -4000 -o -perm -2000 \) 2>/dev/null | head -1)" ] && { ! command -v getcap >/dev/null || [ -z "$(getcap -r $OURS 2>/dev/null)" ]; } && [ -z "$(find $OURS /etc/systemd /usr/local/lib/systemd -name "*.service" -newer "$T/before.txt" 2>/dev/null | head -1)" ]'
check "win7-doctor findet am Overlay nichts zu beanstanden" '! /usr/local/bin/win7-doctor --fast --no-color 2>&1 | sed -n "/== 1\./,/== 2\./p" | grep -q "WARN"'

echo "== neuer Benutzer: Desktop-Sitzung =="
if command -v xfce4-session >/dev/null && command -v Xvfb >/dev/null; then
    id w7user >/dev/null 2>&1 && userdel -r w7user >/dev/null 2>&1
    useradd -m -s /bin/bash w7user
    check "neuer Benutzer bekommt die Konfiguration aus /etc/skel" '[ -f /home/w7user/.config/xfce4/xfconf/xfce-perchannel-xml/xsettings.xml ]'
    mkdir -p /tmp/xdg-w7user; chown w7user /tmp/xdg-w7user; chmod 700 /tmp/xdg-w7user
    (Xvfb :98 -screen 0 1280x800x24 -ac -nolisten tcp >"$T/xvfb.log" 2>&1 &); sleep 2
    (runuser -u w7user -- env -i HOME=/home/w7user USER=w7user LANG=de_DE.UTF-8 PATH=/usr/local/bin:/usr/bin:/bin DISPLAY=:98 XDG_RUNTIME_DIR=/tmp/xdg-w7user \
        bash -c 'eval "$(dbus-launch --sh-syntax)"; exec xfce4-session' >"$T/session.log" 2>&1 &)
    sleep 20
    pid="$(pgrep -u w7user -x xfce4-session | head -1)"
    check "XFCE-Sitzung des neuen Benutzers läuft (Panel + Fenstermanager + Desktop)" '[ -n "$pid" ] && pgrep -u w7user -x xfce4-panel >/dev/null && pgrep -u w7user -x xfwm4 >/dev/null && pgrep -u w7user -x xfdesktop >/dev/null'
    if [ -n "$pid" ]; then
        bus="$(tr '\0' '\n' < /proc/$pid/environ | sed -n 's/^DBUS_SESSION_BUS_ADDRESS=//p')"
        q() { runuser -u w7user -- env DBUS_SESSION_BUS_ADDRESS="$bus" DISPLAY=:98 xfconf-query "$@" 2>/dev/null; }
        check "Theme im neuen Benutzer ist Windows-Retro" '[ "$(q -c xsettings -p /Net/ThemeName)" = Windows-Retro ]'
        check "Fensterdekoration ist Windows-Retro" '[ "$(q -c xfwm4 -p /general/theme)" = Windows-Retro ]'
        check "Hintergrundbild ist gesetzt (win7-firstrun lief)" 'q -c xfce4-desktop -l | grep -q last-image && q -c xfce4-desktop -p "$(q -c xfce4-desktop -l | grep last-image | head -1)" | grep -q thewindowslinux'
        runuser -u w7user -- env DISPLAY=:98 HOME=/home/w7user XDG_RUNTIME_DIR=/tmp/xdg-w7user DBUS_SESSION_BUS_ADDRESS="$bus" /usr/local/bin/win7-terminal >/dev/null 2>&1 &
        sleep 5
        import -display :98 -window root "$T/system-desktop.png" 2>/dev/null && cp "$T/system-desktop.png" /tmp/w7-system-desktop.png
    fi
    pkill -u w7user 2>/dev/null; sleep 1; pkill -9 -u w7user 2>/dev/null; pkill -x Xvfb 2>/dev/null; sleep 1
    userdel -r w7user >/dev/null 2>&1; rm -rf /tmp/xdg-w7user
else echo "  (übersprungen: xfce4-session/Xvfb fehlen)"; fi

echo "== uninstall --system =="
"$ROOT/uninstall.sh" --system --yes > "$T/uninstall.log" 2>&1
check "Deinstallation endet ohne Fehler" 'grep -q "wurde entfernt" "$T/uninstall.log"'
snap > "$T/after.txt"
if diff -u "$T/before.txt" "$T/after.txt" > "$T/diff.txt"; then check "Systemzustand nach Deinstallation == vorher" 'true'
else check "Systemzustand nach Deinstallation == vorher" 'false'; head -30 "$T/diff.txt"; fi
echo; echo "$pass bestanden, $fail fehlgeschlagen"
rm -rf "$T"
[ $fail -eq 0 ]
