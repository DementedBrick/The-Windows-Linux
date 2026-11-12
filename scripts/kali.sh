#!/usr/bin/env bash
# TheWindowsLinux – optionaler Schritt: Kali-Werkzeuge (--with-kali-tools[=STUFE] / --kali-level STUFE)
#
#   Auf Kali Linux:        die offiziellen Metapakete (kali-linux-default, kali-tools-top10, ...)
#   Auf Debian/Ubuntu/...: die Kali-typischen Werkzeuge aus den NORMALEN Paketquellen der Distribution
#                          (scripts/kali-tools.list). Das Kali-Repository wird absichtlich NICHT eingebunden:
#                          Kali warnt ausdrücklich davor, weil es Pakete der eigenen Distribution ersetzt
#                          und das System unbrauchbar machen kann.
#
#   Stufen (Kali):    core · top10 · default · large · everything · headless · eine Kategorie wie web, wireless,
#                     passwords, forensics ... (= Metapaket kali-tools-<Kategorie>)
#   Stufen (andere):  top10 = die wichtigsten Zehn, jede andere Stufe = alle verfügbaren Werkzeuge
# Wird von install.sh gesourct; nutzt lib/common.sh.
set -u

w7_is_kali() { [ "${W7_DISTRO_ID:-}" = kali ]; }

# Paketkandidat vorhanden? (apt-cache show allein reicht nicht – es meldet auch nicht installierbare Pakete)
w7_apt_has() {
    local c; c="$(apt-cache policy "$1" 2>/dev/null | awk '/Candidate:/ {print $2}')"
    [ -n "$c" ] && [ "$c" != "(none)" ]
}

# Pakete der Liste für eine Stufe ausgeben (eines pro Zeile, ohne Duplikate)
w7_kali_list_pkgs() {  # w7_kali_list_pkgs STUFE
    local level="$1" file="$W7_SRC/scripts/kali-tools.list" cat pkgs
    if [ "$level" = top10 ]; then
        grep '^top10|' "$file" | cut -d'|' -f2 | tr ' ' '\n'
    else
        while IFS='|' read -r cat pkgs; do
            case "$cat" in ''|'#'*|top10) continue ;; esac
            printf '%s\n' $pkgs
        done < "$file" | sort -u
    fi
}

w7_kali_install_apt_list() {
    local level="$1" pkg available=() skipped=() failed=()
    while IFS= read -r pkg; do
        [ -n "$pkg" ] || continue
        if w7_apt_has "$pkg"; then available+=("$pkg"); else skipped+=("$pkg"); fi
    done < <(w7_kali_list_pkgs "$level")
    w7_info "${#available[@]} Werkzeuge verfügbar, ${#skipped[@]} gibt es in dieser Distribution nicht."
    [ ${#skipped[@]} -gt 0 ] && w7_info "Nicht verfügbar: ${skipped[*]}"
    [ ${#available[@]} -gt 0 ] || { w7_warn "Keine Werkzeuge gefunden – ist »universe«/»main« aktiv? (sudo apt update)"; return 0; }
    # Dialoge vermeiden: Wireshark nur für root, MAC-Wechsel nicht beim Booten
    printf '%s\n' 'wireshark-common wireshark-common/install-setuid boolean false' 'macchanger macchanger/automatically_run boolean false' | w7_root debconf-set-selections 2>/dev/null || true
    if ! w7_root env DEBIAN_FRONTEND=noninteractive apt-get install -y -q "${available[@]}"; then
        w7_warn "Sammelinstallation fehlgeschlagen – installiere Werkzeuge einzeln."
        for pkg in "${available[@]}"; do
            w7_root env DEBIAN_FRONTEND=noninteractive apt-get install -y -q "$pkg" >/dev/null 2>&1 || failed+=("$pkg")
        done
        [ ${#failed[@]} -gt 0 ] && w7_warn "Nicht installierbar: ${failed[*]}"
    fi
}

w7_kali_install_other() {  # Fedora/Arch/openSUSE: bekannte Namen einzeln versuchen, fehlende überspringen
    local pkg missing=0
    local -a list=(nmap wireshark tcpdump aircrack-ng john hashcat hydra sqlmap gobuster nikto binwalk radare2 gdb strace ltrace nasm yara
                   foremost testdisk steghide proxychains-ng proxychains4 tor socat ncat macchanger bettercap ettercap hping3 whois bind-utils dnsutils)
    case "$W7_PKG" in
        dnf)    w7_root dnf group install -y "Security Lab" 2>/dev/null || w7_info "Gruppe »Security Lab« nicht verfügbar."
                w7_root dnf install -y --skip-unavailable "${list[@]}" 2>/dev/null || true ;;
        pacman) for pkg in "${list[@]}"; do w7_root pacman -S --needed --noconfirm "$pkg" >/dev/null 2>&1 || missing=$((missing + 1)); done
                w7_info "$missing von ${#list[@]} Namen gibt es in den Arch-Repositories nicht (für mehr: BlackArch-Repository, eigene Verantwortung)." ;;
        zypper) for pkg in "${list[@]}"; do w7_root zypper --non-interactive install "$pkg" >/dev/null 2>&1 || missing=$((missing + 1)); done ;;
        *)      w7_warn "Für diese Distribution ist keine Kali-Werkzeugliste hinterlegt."; return 0 ;;
    esac
}

w7_step_kali() {
    [ "${W7_WITH_KALI:-0}" = 1 ] || return 0
    local level="${W7_KALI_LEVEL:-default}"
    [[ "$level" =~ ^[a-z0-9-]+$ ]] || w7_die "Ungültige Kali-Stufe: »$level«"
    w7_step "Kali-Werkzeuge (Stufe: $level)"
    w7_info "Hinweis: Diese Werkzeuge nur auf eigenen Systemen oder mit ausdrücklicher Erlaubnis einsetzen."
    if [ "${W7_NO_PACKAGES:-0}" = 1 ]; then w7_info "übersprungen (--no-packages)"; return 0; fi
    w7_can_root || { w7_warn "Keine Root-Rechte – Kali-Werkzeuge übersprungen."; return 0; }

    if [ "$W7_PKG" = apt ]; then
        w7_root env DEBIAN_FRONTEND=noninteractive apt-get update -qq 2>/dev/null || true
        if w7_is_kali; then
            local meta
            case "$level" in
                core|default|large|everything|headless) meta="kali-linux-$level" ;;
                top10) meta="kali-tools-top10" ;;
                *) meta="kali-tools-$level" ;;
            esac
            if w7_apt_has "$meta"; then
                w7_info "Installiere das offizielle Kali-Metapaket $meta (kann viele GB laden) ..."
                w7_root env DEBIAN_FRONTEND=noninteractive apt-get install -y -q "$meta" || w7_warn "Installation von $meta meldete Fehler."
            else
                w7_warn "Metapaket $meta nicht gefunden – nutze die Werkzeugliste."
                w7_kali_install_apt_list "$level"
            fi
        else
            w7_info "Kein Kali-System: installiere die Werkzeuge aus den normalen Paketquellen von ${W7_DISTRO_NAME:-dieser Distribution}."
            w7_info "Das Kali-Repository wird bewusst nicht eingebunden (würde das System beschädigen können)."
            w7_kali_install_apt_list "$level"
        fi
        # Tor soll nicht ungefragt als Dienst laufen
        if w7_have systemctl && systemctl list-unit-files tor.service >/dev/null 2>&1; then
            w7_root systemctl disable --now tor tor@default >/dev/null 2>&1 || true
            w7_info "Tor-Dienst ist aus (Start bei Bedarf: sudo systemctl start tor)."
        fi
    else
        w7_kali_install_other
    fi
    w7_ok "Kali-Werkzeuge installiert. Nicht per apt erhältlich (nur Kali-Repository): metasploit-framework, burpsuite, responder – siehe README."
}
