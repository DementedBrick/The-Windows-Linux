#!/usr/bin/env bash
# TheWindowsLinux – Schritt 4: Terminal-Overlay ("Eingabeaufforderung") einrichten
#   * Befehle cmd / win7-terminal / win7-sound im PATH
#   * optional: cmd-Overlay in jeder bash (--cmd-everywhere)
# Wird von install.sh gesourct; nutzt lib/common.sh.
set -u

w7_step_cmd() {
    w7_step "Terminal-Overlay (cmd) einrichten"
    w7_mkdir "$W7_BINDIR"
    local b
    for b in cmd win7-terminal win7-sound win7-firstrun win7-wallpaper win7-doctor win7-scale; do
        w7_do ln -sf "$W7_DATADIR/bin/$b" "$W7_BINDIR/$b"
        w7_track "$W7_BINDIR/$b"
    done
    # Windows-typische Namen
    w7_do ln -sf "$W7_DATADIR/bin/cmd" "$W7_BINDIR/cmd.exe"
    w7_do ln -sf "$W7_DATADIR/bin/win7-terminal" "$W7_BINDIR/eingabeaufforderung"
    w7_track "$W7_BINDIR/cmd.exe"; w7_track "$W7_BINDIR/eingabeaufforderung"
    w7_ok "Befehle: cmd, cmd.exe, win7-terminal, win7-sound  (in $W7_BINDIR)"

    if [ "${W7_CMD_EVERYWHERE:-0}" = 1 ]; then
        local hook='[ -n "$PS1" ] && [ -z "$WIN7_CMD_LOADED" ] && [ -r "'"$W7_DATADIR"'/cmd/cmdrc.sh" ] && WIN7_CMD_FROM_BASHRC=1 . "'"$W7_DATADIR"'/cmd/cmdrc.sh"  # TheWindowsLinux cmd-Overlay'
        if [ "$W7_MODE" = system ]; then
            local target=/etc/bashrc                                   # Fedora/Arch-Stil
            [ -f /etc/bash.bashrc ] && target=/etc/bash.bashrc         # Debian/Ubuntu-Stil hat Vorrang
            if ! w7_root grep -q 'TheWindowsLinux cmd-Overlay' "$target" 2>/dev/null; then
                if [ -s "$target" ] && [ -n "$(tail -c1 "$target")" ]; then echo | w7_root tee -a "$target" >/dev/null; fi
                printf '%s\n' "$hook" | w7_root tee -a "$target" >/dev/null
            fi
            w7_ok "cmd-Overlay für alle Benutzer in $target aktiviert"
        else
            touch "$HOME/.bashrc"
            if ! grep -q 'TheWindowsLinux cmd-Overlay' "$HOME/.bashrc"; then
                [ -s "$HOME/.bashrc" ] && [ -n "$(tail -c1 "$HOME/.bashrc")" ] && echo >> "$HOME/.bashrc"
                printf '%s\n' "$hook" >> "$HOME/.bashrc"      # eine markierte Zeile; uninstall.sh entfernt sie wieder
            fi
            w7_ok "cmd-Overlay in ~/.bashrc aktiviert (jedes Terminal ist eine Eingabeaufforderung)"
        fi
    else
        w7_info "Das Overlay startet nur über »Eingabeaufforderung« bzw. den Befehl cmd. (--cmd-everywhere aktiviert es in jeder bash)"
    fi
}
