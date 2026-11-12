#!/usr/bin/env bash
# Tests für win7-doctor: baut Kernel-Zustände nach (nachgebautes /proc und /sys, Ersatzprogramme für dpkg-query,
# apt-get, debsecan, …) und prüft, dass gute Zustände sauber und schlechte Zustände als Warnung erkannt werden.
# Aufruf: bash tests/test-doctor.sh
# shellcheck disable=SC2034   # OUT wird in den eval-Prüfungen verwendet
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOC="$ROOT/cmd/bin/win7-doctor"
T="$(mktemp -d /tmp/w7doc-XXXXXX)"
pass=0; fail=0
check() { if ( eval "$2" ); then pass=$((pass + 1)); printf '  ok    %s\n' "$1"; else fail=$((fail + 1)); printf '  FAIL  %s\n' "$1"; fi; }

# --- Kernel-Attrappe -------------------------------------------------------------------------------
mk_kernel() {  # mk_kernel ORDNER   → "guter" Zustand
    local d="$1"
    mkdir -p "$d/proc/sys/kernel" "$d/proc/sys/vm" "$d/proc/sys/fs" "$d/proc/sys/net/ipv4/conf/all" "$d/proc/sys/net/core" "$d/proc/sys/dev/tty" "$d/sys/devices/system/cpu/vulnerabilities" "$d/sys/kernel/security"
    echo 2 > "$d/proc/sys/kernel/randomize_va_space"; echo 2 > "$d/proc/sys/kernel/kptr_restrict"; echo 1 > "$d/proc/sys/kernel/dmesg_restrict"
    echo 1 > "$d/proc/sys/kernel/unprivileged_bpf_disabled"; echo 2 > "$d/proc/sys/kernel/perf_event_paranoid"; echo 65536 > "$d/proc/sys/vm/mmap_min_addr"
    echo 1 > "$d/proc/sys/fs/protected_symlinks"; echo 1 > "$d/proc/sys/fs/protected_hardlinks"; echo 1 > "$d/proc/sys/net/ipv4/tcp_syncookies"
    echo 2 > "$d/proc/sys/net/core/bpf_jit_harden"; echo 0 > "$d/proc/sys/dev/tty/ldisc_autoload"; echo 0 > "$d/proc/sys/net/ipv4/conf/all/accept_redirects"
    echo 0 > "$d/proc/sys/kernel/tainted"; echo 1 > "$d/proc/sys/kernel/yama_dummy"
    echo "BOOT_IMAGE=/vmlinuz-6.8.0-45-generic root=/dev/sda2 ro quiet splash" > "$d/proc/cmdline"
    local v; for v in meltdown mds l1tf; do echo "Not affected" > "$d/sys/devices/system/cpu/vulnerabilities/$v"; done
    echo "Mitigation: Retpolines; IBPB: conditional; STIBP: disabled" > "$d/sys/devices/system/cpu/vulnerabilities/spectre_v2"
}
sect6() { W7_DOCTOR_PROC="$1/proc" W7_DOCTOR_SYS="$1/sys" W7_DOCTOR_UNAME="${2:-6.8.0-45-generic}" "$DOC" --fast --no-color 2>&1 | sed -n '/== 6\./,/== 7\./p'; }

echo "== guter Kernel-Zustand =="
mk_kernel "$T/gut"
OUT="$(sect6 "$T/gut")"
check "keine Warnung im Kernel-Abschnitt" '! printf "%s\n" "$OUT" | grep -q "^\[WARN\]"'
check "CPU-Schwachstellen: nichts offen" 'printf "%s\n" "$OUT" | grep -q "CPU-Schwachstellen: 3 nicht betroffen, 1 abgemildert, 0 offen"'
check "Startparameter unauffällig" 'printf "%s\n" "$OUT" | grep -q "Keine Schutzfunktion per Kernel-Startparameter"'

echo "== schlechter Kernel-Zustand =="
mk_kernel "$T/schlecht"
echo "Vulnerable: Clear CPU buffers attempted, no microcode; SMT vulnerable" > "$T/schlecht/sys/devices/system/cpu/vulnerabilities/mds"
echo "BOOT_IMAGE=/vmlinuz root=/dev/sda2 ro quiet mitigations=off nokaslr apparmor=0" > "$T/schlecht/proc/cmdline"
echo 0 > "$T/schlecht/proc/sys/kernel/unprivileged_bpf_disabled"; echo 4096 > "$T/schlecht/proc/sys/vm/mmap_min_addr"
echo 0 > "$T/schlecht/proc/sys/kernel/kptr_restrict"; echo 0 > "$T/schlecht/proc/sys/fs/protected_symlinks"; echo 128 > "$T/schlecht/proc/sys/kernel/tainted"
OUT="$(sect6 "$T/schlecht")"
check "offene CPU-Schwachstelle (mds) wird gemeldet" 'printf "%s\n" "$OUT" | grep -q "^\[WARN\] CPU-Schwachstelle mds"'
check "abgeschaltete Schutzfunktionen im Startparameter werden gemeldet" 'printf "%s\n" "$OUT" | grep -q "^\[WARN\].*mitigations=off nokaslr apparmor=0"'
check "unprivilegiertes BPF erlaubt wird gemeldet" 'printf "%s\n" "$OUT" | grep -q "^\[WARN\] BPF nur für root"'
check "zu kleine mmap-Adresse wird gemeldet" 'printf "%s\n" "$OUT" | grep -q "^\[WARN\] Null-Zeiger-Schutz"'
check "kptr_restrict=0 und fehlender Symlink-Schutz werden gemeldet" 'printf "%s\n" "$OUT" | grep -q "^\[WARN\] Kernel-Adressen" && printf "%s\n" "$OUT" | grep -q "^\[WARN\] Schutz vor Symlink"'
check "Kernel-Oops (tainted=128) wird gemeldet" 'printf "%s\n" "$OUT" | grep -q "^\[WARN\] Der Kernel meldet einen Fehlerzustand"'

echo "== Kernel-Version: laufend vs. installiert =="
SHIM="$T/shim"; mkdir -p "$SHIM"
printf '#!/bin/sh\nprintf "linux-image-6.8.0-44-generic\\nlinux-image-6.8.0-45-generic\\n"\n' > "$SHIM/dpkg-query"
printf '#!/bin/sh\nexit 0\n' > "$SHIM/apt-get"; chmod +x "$SHIM"/*
OUT="$(PATH="$SHIM:$PATH" sect6 "$T/gut" 6.8.0-44-generic)"
check "älterer laufender Kernel → Neustart-Warnung" 'printf "%s\n" "$OUT" | grep -q "^\[WARN\] Es ist ein neuerer Kernel installiert (6.8.0-45-generic)"'
OUT="$(PATH="$SHIM:$PATH" sect6 "$T/gut" 6.8.0-45-generic)"
check "neuester Kernel läuft → in Ordnung" 'printf "%s\n" "$OUT" | grep -q "Der laufende Kernel ist der neueste installierte"'
printf '#!/bin/sh\n[ "$1" = "-s" ] && echo "Inst linux-image-6.8.0-46-generic [6.8.0-45] (6.8.0-46 Ubuntu:24.04/noble-security)"\nexit 0\n' > "$SHIM/apt-get"
OUT="$(PATH="$SHIM:$PATH" sect6 "$T/gut" 6.8.0-45-generic)"
check "ausstehendes Kernel-Update wird gemeldet" 'printf "%s\n" "$OUT" | grep -q "^\[WARN\] Ein Kernel-Update steht aus"'

echo "== bekannte Schwachstellen (CVE) über Distributionswerkzeuge =="
cve() { W7_DOCTOR_OSREL="$1" "$DOC" --fast --no-color 2>&1 | sed -n '/== 9\./,/== Ergebnis/p'; }
printf 'ID=debian\nVERSION_CODENAME=bookworm\nPRETTY_NAME="Debian"\n' > "$T/os-debian"
printf '#!/bin/sh\nprintf "libssl3\\nlinux-image-6.1.0-18-amd64\\n"\n' > "$SHIM/debsecan"; chmod +x "$SHIM/debsecan"
OUT="$(PATH="$SHIM:$PATH" cve "$T/os-debian")"
check "Debian: debsecan-Treffer werden als Warnung mit Anzahl gemeldet" 'printf "%s\n" "$OUT" | grep -q "^\[WARN\] 2 Pakete haben bekannte Schwachstellen"'
printf '#!/bin/sh\nexit 0\n' > "$SHIM/debsecan"
OUT="$(PATH="$SHIM:$PATH" cve "$T/os-debian")"
check "Debian: keine Treffer → in Ordnung" 'printf "%s\n" "$OUT" | grep -q "^\[ OK \] debsecan: keine"'
printf 'ID=arch\nPRETTY_NAME="Arch"\n' > "$T/os-arch"; printf '#!/bin/sh\necho "Package openssl is affected by CVE-2024-0001. High risk!"\n' > "$SHIM/arch-audit"; chmod +x "$SHIM/arch-audit"
OUT="$(PATH="$SHIM:$PATH" cve "$T/os-arch")"
check "Arch: arch-audit-Treffer werden gemeldet" 'printf "%s\n" "$OUT" | grep -q "^\[WARN\] arch-audit"'
printf 'ID=kali\nPRETTY_NAME="Kali"\n' > "$T/os-kali"
OUT="$(cve "$T/os-kali")"
check "Kali: Hinweis auf full-upgrade" 'printf "%s\n" "$OUT" | grep -q "full-upgrade"'
printf 'ID=debian\nPRETTY_NAME="Debian"\n' > "$T/os-debian2"
OUT="$(PATH="/usr/bin:/bin" W7_DOCTOR_OSREL="$T/os-debian2" "$DOC" --fast --no-color 2>&1 | sed -n '/== 9\./,/== Ergebnis/p')"
check "ohne Werkzeug: Installationshinweis" 'printf "%s\n" "$OUT" | grep -q "sudo apt install debsecan"'

echo "== Overlay selbst =="
check "Overlay bringt keine SUID/SGID-Dateien mit" '[ -z "$(find "$ROOT/cmd" "$ROOT/scripts" "$ROOT/lib" "$ROOT/theme" \( -perm -4000 -o -perm -2000 \) 2>/dev/null)" ]'

echo; echo "$pass bestanden, $fail fehlgeschlagen"
rm -rf "$T"
[ $fail -eq 0 ]
