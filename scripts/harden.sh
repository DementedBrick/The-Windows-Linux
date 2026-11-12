#!/usr/bin/env bash
# TheWindowsLinux – optionaler Schritt: System absichern (--harden)
#
#   * Firewall (ufw): eingehend sperren, ausgehend erlauben; laufendes SSH bleibt erreichbar
#   * automatische Sicherheitsupdates (unattended-upgrades bzw. dnf-automatic)
#   * Kernel-/Netzwerk-Einstellungen (sysctl-Datei), die auf Desktops praktisch nie stören
#   * SSH-Server (falls vorhanden): Root-Anmeldung per Passwort aus, kurze Anmeldefrist
#
# Alles wird über w7_install protokolliert und von uninstall.sh wieder entfernt (die Firewall bleibt
# bewusst aktiv – sie abzuschalten wäre ein Sicherheitsverlust; dafür: sudo ufw disable).
# Mit W7_HARDEN_DRYRUN=1 werden die Schritte nur angezeigt, nicht ausgeführt.
# Wird von install.sh gesourct; nutzt lib/common.sh.
set -u

w7_hd() {  # Ausführen (oder im Trockenlauf nur anzeigen)
    if [ "${W7_HARDEN_DRYRUN:-0}" = 1 ]; then printf '    [Trockenlauf] %s\n' "$*"; return 0; fi
    w7_root "$@"
}

w7_harden_firewall() {
    if w7_have firewall-cmd && systemctl is-active --quiet firewalld 2>/dev/null; then
        w7_ok "firewalld ist aktiv – Firewall bleibt unverändert."; return 0
    fi
    if ! w7_have ufw; then
        if [ "${W7_NO_PACKAGES:-0}" = 1 ]; then w7_warn "ufw fehlt und --no-packages ist gesetzt – Firewall übersprungen."; return 0; fi
        case "$W7_PKG" in
            apt)    w7_hd env DEBIAN_FRONTEND=noninteractive apt-get install -y -q ufw ;;
            dnf)    w7_hd dnf install -y ufw ;;
            pacman) w7_hd pacman -S --needed --noconfirm ufw ;;
            zypper) w7_hd zypper --non-interactive install ufw ;;
            *) w7_warn "Keine ufw-Installation für diese Distribution bekannt – Firewall übersprungen."; return 0 ;;
        esac
    fi
    # SSH nicht aussperren: lauscht ein SSH-Server, bleibt Port 22 (mit Ratenbegrenzung) offen
    if w7_have ss && ss -ltnH 2>/dev/null | awk '{print $4}' | grep -Eq '(^|:)22$'; then
        w7_info "SSH-Server erkannt – Port 22 bleibt (mit Ratenbegrenzung) offen."
        w7_hd ufw limit 22/tcp
    fi
    w7_hd ufw default deny incoming
    w7_hd ufw default allow outgoing
    w7_hd ufw --force enable
    w7_ok "Firewall (ufw): eingehend gesperrt, ausgehend erlaubt. Freigeben z. B. mit: sudo ufw allow 8080/tcp"
}

w7_harden_updates() {
    case "$W7_PKG" in
        apt)
            if [ "${W7_NO_PACKAGES:-0}" != 1 ]; then w7_hd env DEBIAN_FRONTEND=noninteractive apt-get install -y -q unattended-upgrades; fi
            local tmp; tmp="$(mktemp)"
            printf '// TheWindowsLinux: täglich Paketlisten aktualisieren, Sicherheitsupdates automatisch einspielen\nAPT::Periodic::Update-Package-Lists "1";\nAPT::Periodic::Unattended-Upgrade "1";\nAPT::Periodic::AutocleanInterval "7";\n' > "$tmp"
            [ "${W7_HARDEN_DRYRUN:-0}" = 1 ] || w7_install "$tmp" /etc/apt/apt.conf.d/52thewindowslinux-auto-upgrades
            rm -f "$tmp"
            w7_ok "Automatische Sicherheitsupdates aktiviert (unattended-upgrades)." ;;
        dnf)
            if [ "${W7_NO_PACKAGES:-0}" != 1 ]; then w7_hd dnf install -y dnf-automatic; fi
            w7_hd systemctl enable --now dnf-automatic-install.timer
            w7_ok "Automatische Updates aktiviert (dnf-automatic)." ;;
        *) w7_info "Automatische Updates: für diese Distribution nicht eingerichtet (Arch/Void: regelmäßig selbst aktualisieren)." ;;
    esac
}

w7_harden_sysctl() {
    local tmp; tmp="$(mktemp)"
    cat > "$tmp" <<'EOF'
# TheWindowsLinux – Kernel-/Netzwerk-Härtung (nur Einstellungen, die Desktops praktisch nie stören)
kernel.kptr_restrict = 2
kernel.dmesg_restrict = 1
kernel.randomize_va_space = 2
fs.suid_dumpable = 0
fs.protected_hardlinks = 1
fs.protected_symlinks = 1
fs.protected_fifos = 2
fs.protected_regular = 2
net.ipv4.tcp_syncookies = 1
net.ipv4.conf.all.rp_filter = 2
net.ipv4.conf.default.rp_filter = 2
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
-net.ipv6.conf.all.accept_redirects = 0
-net.ipv6.conf.default.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
-net.ipv6.conf.all.accept_source_route = 0
net.ipv4.icmp_echo_ignore_broadcasts = 1
EOF
    if [ "${W7_HARDEN_DRYRUN:-0}" = 1 ]; then
        printf '    [Trockenlauf] /etc/sysctl.d/99-thewindowslinux.conf (%s Einstellungen)\n' "$(grep -c '=' "$tmp")"
    else
        w7_install "$tmp" /etc/sysctl.d/99-thewindowslinux.conf
        w7_root sysctl --system >/dev/null 2>&1 || w7_warn "sysctl --system meldete Fehler (z. B. fehlen IPv6-Schlüssel, wenn IPv6 abgeschaltet ist – der Rest wurde trotzdem gesetzt)."
    fi
    rm -f "$tmp"
    w7_ok "Kernel-/Netzwerk-Einstellungen gesetzt (/etc/sysctl.d/99-thewindowslinux.conf)."
}

w7_harden_ssh() {
    [ -d /etc/ssh ] || return 0
    w7_have sshd || [ -x /usr/sbin/sshd ] || return 0
    if ! grep -qs '^Include.*sshd_config.d' /etc/ssh/sshd_config; then
        w7_info "sshd_config bindet sshd_config.d nicht ein – SSH-Härtung übersprungen."; return 0
    fi
    local tmp; tmp="$(mktemp)"
    printf '# TheWindowsLinux\nPermitRootLogin prohibit-password\nX11Forwarding no\nMaxAuthTries 4\nLoginGraceTime 30\n' > "$tmp"
    if [ "${W7_HARDEN_DRYRUN:-0}" = 1 ]; then printf '    [Trockenlauf] /etc/ssh/sshd_config.d/50-thewindowslinux.conf\n'; rm -f "$tmp"; return 0; fi
    w7_install "$tmp" /etc/ssh/sshd_config.d/50-thewindowslinux.conf
    rm -f "$tmp"
    local sshd_bin; sshd_bin="$(command -v sshd || echo /usr/sbin/sshd)"
    if w7_root "$sshd_bin" -t 2>/dev/null; then
        w7_root systemctl reload ssh 2>/dev/null || w7_root systemctl reload sshd 2>/dev/null || true
        w7_ok "SSH-Server gehärtet (Root nur per Schlüssel, kurze Anmeldefrist, kein X11-Forwarding)."
    else
        w7_rm_rf /etc/ssh/sshd_config.d/50-thewindowslinux.conf
        w7_warn "sshd -t meldete einen Fehler – die SSH-Härtung wurde wieder entfernt."
    fi
}

w7_step_harden() {
    [ "${W7_HARDEN:-0}" = 1 ] || return 0
    w7_step "System absichern (--harden)"
    if [ "$W7_MODE" != system ]; then
        w7_warn "--harden verändert das ganze System und braucht --system (sudo ./install.sh --system --harden)."; return 0
    fi
    w7_harden_sysctl
    w7_harden_updates
    w7_harden_ssh
    w7_harden_firewall
    w7_info "Prüfen jederzeit mit: win7-doctor"
}
